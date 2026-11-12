// ============================================================
// Module : line_buffer_3x3
// Target : ALG-01（行缓存 + 3x3 窗口）
// Desc   : 在 line_buffer_rows(P_ROWS=3) 之上加列移位，输出 3x3 窗口 9 像素
// LATENCY: 2 cycles（+ 前 2 行的空间对齐）
// Note   : 1) 窗口排布（与 Sobel / 滤波核一致），w22 = 最新像素，w11 = 中心：
//                w00 w01 w02   <- (x-1,y-1) (x,y-1) (x+1,y-1)
//                w10 w11 w12   <- (x-1,y  ) (x,y  ) (x+1,y  )
//                w20 w21 w22   <- (x-1,y+1) (x,y+1) (x+1,y+1)
//              （即窗口中心 = m_axis_tx / m_axis_ty 所指坐标）
//          2) 9 个窗口寄存器在***同一拍***整体移位，移位使能 = 全局流水使能 en
//             （即 pixel_valid 同源），禁止各自计数（避坑 #9）；
//          3) 输出 m_axis_tx/ty = 窗口***中心***像素坐标（已扣 1 行 1 列），
//             下游只按此坐标裁剪，**不需要**再自行产生行列计数器；
//          4) 边界裁剪在此完成：中心必须满足 x>=1 且 y>=1，否则 tvalid 拉低，
//             杜绝"跨行拼接"的伪有效像素（每行左端丢 2 个中心点）。
// ============================================================
`timescale 1ns / 1ps

module line_buffer_3x3 #(
    parameter P_DATA_W = 8,
    parameter P_IMG_W  = 1920,
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

    // ---- 输出流（窗口中心像素的 valid / 坐标 / 帧行标志）----
    output wire                       m_axis_tvalid,
    output wire [P_XW-1:0]            m_axis_tx,
    output wire [P_YW-1:0]            m_axis_ty,
    output wire                       m_axis_tuser,
    output wire                       m_axis_tlast,

    // ---- 3x3 窗口 ----
    output reg  [P_DATA_W-1:0]        w00, w01, w02,
    output reg  [P_DATA_W-1:0]        w10, w11, w12,
    output reg  [P_DATA_W-1:0]        w20, w21, w22
);

    wire en = m_axis_tready;

    // ---------- 级 1：行缓存（P_ROWS=3，1 拍）----------
    wire [3*P_DATA_W-1:0] row_flat;
    wire [P_DATA_W-1:0]   row_cur = row_flat[2*P_DATA_W +: P_DATA_W];  // 行 y+1
    wire [P_DATA_W-1:0]   row_m1  = row_flat[1*P_DATA_W +: P_DATA_W];  // 行 y
    wire [P_DATA_W-1:0]   row_m2  = row_flat[0*P_DATA_W +: P_DATA_W];  // 行 y-1

    wire                  v_rows;
    wire [P_XW-1:0]       x_rows;
    wire [P_YW-1:0]       y_rows;
    wire                  u_rows, l_rows;

    line_buffer_rows #(
        .P_DATA_W (P_DATA_W),
        .P_IMG_W  (P_IMG_W ),
        .P_ROWS   (3       ),
        .P_XW     (P_XW    ),
        .P_YW     (P_YW    )
    ) u_rowbuf (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .m_axis_tready (m_axis_tready),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  (s_axis_tdata ),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tx     (s_axis_tx    ),
        .s_axis_ty     (s_axis_ty    ),
        .s_axis_tuser  (s_axis_tuser ),
        .s_axis_tlast  (s_axis_tlast ),
        .m_axis_tdata  (             ),
        .m_axis_tvalid (v_rows       ),
        .m_axis_tx     (x_rows       ),
        .m_axis_ty     (y_rows       ),
        .m_axis_tuser  (u_rows       ),
        .m_axis_tlast  (l_rows       ),
        .m_row_flat    (row_flat     )
    );

    // ---------- 级 2：列移位 + 窗口寄存（同一拍整体移位）----------
    reg [P_DATA_W-1:0] a1, a2;   // 行 y-1 的 (x) / (x-1)
    reg [P_DATA_W-1:0] b1, b2;   // 行 y   的 (x) / (x-1)
    reg [P_DATA_W-1:0] c1, c2;   // 行 y+1 的 (x) / (x-1)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a1 <= {P_DATA_W{1'b0}}; a2 <= {P_DATA_W{1'b0}};
            b1 <= {P_DATA_W{1'b0}}; b2 <= {P_DATA_W{1'b0}};
            c1 <= {P_DATA_W{1'b0}}; c2 <= {P_DATA_W{1'b0}};
            w00 <= {P_DATA_W{1'b0}}; w01 <= {P_DATA_W{1'b0}}; w02 <= {P_DATA_W{1'b0}};
            w10 <= {P_DATA_W{1'b0}}; w11 <= {P_DATA_W{1'b0}}; w12 <= {P_DATA_W{1'b0}};
            w20 <= {P_DATA_W{1'b0}}; w21 <= {P_DATA_W{1'b0}}; w22 <= {P_DATA_W{1'b0}};
        end else if (en) begin
            a1 <= row_m2;  a2 <= a1;
            b1 <= row_m1;  b2 <= b1;
            c1 <= row_cur; c2 <= c1;

            w00 <= a2;     w01 <= a1;     w02 <= row_m2;
            w10 <= b2;     w11 <= b1;     w12 <= row_m1;
            w20 <= c2;     w21 <= c1;     w22 <= row_cur;
        end
    end

    // ---------- 标志/坐标延迟 2 拍（与窗口严格等长）----------
    reg            v1;
    reg [P_XW-1:0] x1;
    reg [P_YW-1:0] y1;
    reg            u1, l1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0;
            x1 <= {P_XW{1'b0}};
            y1 <= {P_YW{1'b0}};
            u1 <= 1'b0;
            l1 <= 1'b0;
        end else if (en) begin
            v1 <= v_rows;
            x1 <= x_rows;
            y1 <= y_rows;
            u1 <= u_rows;
            l1 <= l_rows;
        end
    end

    // 窗口中心坐标 = 延迟 2 拍的输入坐标 - 1；
    // 中心必须满足 cx>=1 且 cy>=1（否则 3x3 会跨行拼接出伪像素）
    localparam [P_XW-1:0] C_XMIN = 2;
    localparam [P_YW-1:0] C_YMIN = 2;

    assign m_axis_tvalid = v1 & (x1 >= C_XMIN) & (y1 >= C_YMIN);
    assign m_axis_tx     = (x1 == {P_XW{1'b0}}) ? {P_XW{1'b0}} : (x1 - 1'b1);
    assign m_axis_ty     = (y1 == {P_YW{1'b0}}) ? {P_YW{1'b0}} : (y1 - 1'b1);
    assign m_axis_tuser  = u1;
    assign m_axis_tlast  = l1;

endmodule
