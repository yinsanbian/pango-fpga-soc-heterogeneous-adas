// ============================================================
// Module : line_buffer_rows
// Target : ALG-01（行缓存）· 通用 N 行窗口底座
// Desc   : 用 P_ROWS-1 块"简单双口 RAM"缓存前 P_ROWS-1 行，输出 P_ROWS 行
//          在同一列的像素向量（像素流式，无需整帧）。
// LATENCY: 1 cycle（+ 前 P_ROWS-1 行的空间对齐）
// Note   : 1) ★★ 读写地址同源：读地址与写地址都是***当前像素坐标 s_axis_tx***，
//             块选择子 wr_sel = s_axis_ty mod (P_ROWS-1) 也直接取自坐标；
//             **全模块没有任何行列计数器** —— 从结构上杜绝 docs/04 §3.3
//             「行缓存读写指针与 pixel_valid 不同源」与避坑 #9；
//          2) 输出 m_row_flat 切片约定（下游必须按此解读）：
//                [ (P_ROWS-1)*DW +: DW ] = 当前行 y
//                [ (P_ROWS-2)*DW +: DW ] = 前行   y-1
//                ...
//                [            0 +: DW ] = 最旧行 y-(P_ROWS-1)
//          3) RAM 组织：第 y 行写入 RAM (y mod (P_ROWS-1))；因
//             (y-(P_ROWS-1)) mod (P_ROWS-1) == y mod (P_ROWS-1)，该 RAM 被
//             覆盖前保存的正是第 y-(P_ROWS-1) 行（读优先 read-first）；
//             其余行由 ((wr_sel + j) & (P_ROWS-1)) 旋转选取（j 为相对滞后）；
//          4) ★ 约束：P_ROWS-1 必须为 2 的幂（P_ROWS ∈ {2,3,5,9}），
//             以保证取模 / 旋转退化为按位与；
//          5) 本模块不裁剪 valid 与坐标：有效范围由下游按真实坐标 (tx,ty)
//             自行界定，避免"双重裁剪"造成坐标错位。
// ============================================================
`timescale 1ns / 1ps

module line_buffer_rows #(
    parameter P_DATA_W = 8,
    parameter P_IMG_W  = 1920,
    parameter P_ROWS   = 3,        // 窗口行数，P_ROWS-1 必须是 2 的幂
    parameter P_XW     = 11,
    parameter P_YW     = 11
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       m_axis_tready,
    output wire                       s_axis_tready,

    // ---- 输入流 ----
    input  wire [P_DATA_W-1:0]        s_axis_tdata,
    input  wire                       s_axis_tvalid,
    input  wire [P_XW-1:0]            s_axis_tx,
    input  wire [P_YW-1:0]            s_axis_ty,
    input  wire                       s_axis_tuser,
    input  wire                       s_axis_tlast,

    // ---- 输出流（当前像素，延迟 1 拍；坐标同步寄存）----
    output reg  [P_DATA_W-1:0]        m_axis_tdata,
    output reg                        m_axis_tvalid,
    output reg  [P_XW-1:0]            m_axis_tx,
    output reg  [P_YW-1:0]            m_axis_ty,
    output reg                        m_axis_tuser,
    output reg                        m_axis_tlast,

    // ---- P_ROWS 行同列像素向量 ----
    output reg  [P_ROWS*P_DATA_W-1:0] m_row_flat
);

    localparam P_RAM_N = P_ROWS - 1;                                  // RAM 块数
    localparam P_SEL_W = (P_RAM_N <= 1) ? 1 : $clog2(P_RAM_N);
    localparam P_CW    = (P_IMG_W <= 1) ? 1 : $clog2(P_IMG_W);
    localparam [P_SEL_W-1:0] P_RAM_MASK = P_RAM_N[P_SEL_W-1:0] - 1'b1;

    assign s_axis_tready = m_axis_tready;
    wire en  = m_axis_tready;
    // ★ 每个使能拍都写 RAM（**不再用 tvalid 门控**）：
    //   下游模块把 tvalid 打包进数据一起过行缓存（valid 随窗口传播），
    //   因此 RAM 必须逐拍刷新，否则无效像素处的 valid 位会成为陈旧值。
    wire acc = en;

    // ---------- 块选择子：直接由行坐标取模（无计数器）----------
    wire [P_SEL_W-1:0] wr_sel = s_axis_ty[P_SEL_W-1:0] & P_RAM_MASK;

    // ---------- 输入流打 1 拍 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {P_DATA_W{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tvalid <= s_axis_tvalid;
            m_axis_tx     <= s_axis_tx;
            m_axis_ty     <= s_axis_ty;
            m_axis_tuser  <= s_axis_tuser;
            m_axis_tlast  <= s_axis_tlast;
        end
    end

    // ---------- P_ROWS-1 块行 RAM（写/读地址均为当前列坐标）----------
    wire [P_RAM_N*P_DATA_W-1:0] ram_rd_flat;

    genvar gi;
    generate
        for (gi = 0; gi < P_RAM_N; gi = gi + 1) begin : g_row_ram
            localparam [P_SEL_W-1:0] L_IDX = gi[P_SEL_W-1:0];
            reg [P_DATA_W-1:0] mem [0:P_IMG_W-1];
            reg [P_DATA_W-1:0] rd;

            // LINT-EXCEPTION: BRAM 推断块（数据通路）不打复位——
            //   省掉上千个复位脚，功能上由 valid 随窗口传播保证有效性
            always @(posedge clk) begin
                if (acc && (wr_sel == L_IDX))
                    mem[s_axis_tx[P_CW-1:0]] <= s_axis_tdata;   // 读优先：同址读出旧值
                if (en)
                    rd <= mem[s_axis_tx[P_CW-1:0]];
            end

            assign ram_rd_flat[gi*P_DATA_W +: P_DATA_W] = rd;
        end
    endgenerate

    // RAM read data and output metadata are one accepted token behind input.
    // Use the matching REGISTERED row for rotation. Current wr_sel switches at
    // the next row's first input and would swap banks in the previous last col.
    wire [P_SEL_W-1:0] rd_sel = m_axis_ty[P_SEL_W-1:0] & P_RAM_MASK;
    // ---------- 行向量组装：切片 j -> RAM ((rd_sel + j) & (P_RAM_N-1)) ----------
    integer jj;
    always @(*) begin
        for (jj = 0; jj < P_RAM_N; jj = jj + 1) begin
            m_row_flat[jj*P_DATA_W +: P_DATA_W] =
                ram_rd_flat[(((rd_sel + jj[P_SEL_W-1:0]) & P_RAM_MASK) * P_DATA_W)
                            +: P_DATA_W];
        end
        m_row_flat[P_RAM_N*P_DATA_W +: P_DATA_W] = m_axis_tdata;   // 当前行
    end

endmodule
