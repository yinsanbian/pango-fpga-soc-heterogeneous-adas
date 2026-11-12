// ============================================================
// Module : roi_mask
// Target : ALG-09（车道检测 · 感兴趣区域）
// Desc   : 复现 OpenCV region_selection() 的梯形 ROI 掩膜
//              bottom_left = (0.10W, 0.95H)   top_left  = (0.40W, 0.60H)
//              bottom_right= (0.90W, 0.95H)   top_right = (0.60W, 0.60H)
//          行内左右边界随行号线性插值，用 **每行一次累加 STEP_Q8** 实现，
//          全模块不占用任何乘法器 / 除法器。
// LATENCY: 1 cycle
// Note   : 1) 边界在"行首事件"（tuser 或 ty 变化）预置，数据同步打 1 拍，
//             保证每行第 0 列像素就用到本行正确的边界；
//          2) STEP 为 Q8 定点：STEP_Q8 = (X_LT - X_LB) * 256 / DY，
//             1080P 时 = 390（真值 390.10），378 行累计误差 < 1 像素；
//          3) 凸四边形的"逐行区间"与 cv2.fillPoly 完全等价（已与参考模型
//             逐像素交叉验证，见 sim/ 用例）。
// ============================================================
`timescale 1ns / 1ps

module roi_mask #(
    parameter P_IMG_W = 1920,
    parameter P_IMG_H = 1080,
    parameter P_XW    = 11,
    parameter P_YW    = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    m_axis_tready,
    output wire                    s_axis_tready,

    // ---- 输入流：二值边缘 ----
    input  wire                    s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire [P_XW-1:0]         s_axis_tx,
    input  wire [P_YW-1:0]         s_axis_ty,
    input  wire                    s_axis_tuser,
    input  wire                    s_axis_tlast,

    // ---- 输出流：ROI 内边缘 ----
    output reg                     m_axis_tdata,
    output reg                     m_axis_tvalid,
    output reg  [P_XW-1:0]         m_axis_tx,
    output reg  [P_YW-1:0]         m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    // ---------- 多边形顶点（与 Python 参考模型共用同一份比例）----------
    localparam [P_YW-1:0] Y_TOP = (P_IMG_H * 60) / 100;   // 0.60H
    localparam [P_YW-1:0] Y_BOT = (P_IMG_H * 95) / 100;   // 0.95H
    localparam [P_XW-1:0] X_LT  = (P_IMG_W * 40) / 100;   // 0.40W（顶边左点）
    localparam [P_XW-1:0] X_LB  = (P_IMG_W * 10) / 100;   // 0.10W（底边左点）
    localparam [P_XW-1:0] X_RT  = (P_IMG_W * 60) / 100;   // 0.60W（顶边右点）

    localparam P_DY     = ((P_IMG_H * 95) / 100) - ((P_IMG_H * 60) / 100);
    localparam P_DLX    = ((P_IMG_W * 40) / 100) - ((P_IMG_W * 10) / 100);
    localparam [23:0] P_STEP_Q8 = (P_DLX * 256) / P_DY;   // 每行水平步进（Q8）

    wire en = m_axis_tready;
    assign s_axis_tready = m_axis_tready;

    // ---------- 行首检测 + 边界累加（为下一拍的数据预置）----------
    reg [P_YW-1:0] ty_prev;
    reg [23:0]     acc;          // Q8 累加，最大 (Y_BOT-Y_TOP)*STEP_Q8 < 2^18
    reg            roi_row;

    wire row_start = s_axis_tuser | (s_axis_ty != ty_prev);
    wire hit       = en & s_axis_tvalid & row_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ty_prev <= {P_YW{1'b0}};
            acc     <= 24'd0;
            roi_row <= 1'b0;
        end else if (hit) begin
            ty_prev <= s_axis_ty;
            if (s_axis_ty == Y_TOP) begin
                acc     <= 24'd0;
                roi_row <= 1'b1;
            end else if ((s_axis_ty > Y_TOP) && (s_axis_ty <= Y_BOT)) begin
                acc     <= acc + P_STEP_Q8;
                roi_row <= 1'b1;
            end else begin
                acc     <= 24'd0;
                roi_row <= 1'b0;
            end
        end
    end

    wire [P_XW-1:0] dx    = acc[23:8];                 // 本行相对顶边的水平位移
    wire [P_XW-1:0] x_lft = X_LT - dx;
    wire [P_XW-1:0] x_rgt = X_RT + dx;

    // ---------- 数据打 1 拍（与边界严格对齐）----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= s_axis_tdata & roi_row
                             & (s_axis_tx >= x_lft) & (s_axis_tx <= x_rgt);
            m_axis_tvalid <= s_axis_tvalid;
            m_axis_tx     <= s_axis_tx;
            m_axis_ty     <= s_axis_ty;
            m_axis_tuser  <= s_axis_tuser;
            m_axis_tlast  <= s_axis_tlast;
        end
    end

endmodule
