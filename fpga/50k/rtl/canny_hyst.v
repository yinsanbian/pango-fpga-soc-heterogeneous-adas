// ============================================================
// Module : canny_hyst
// Target : ALG-06+（Canny 双阈值 + 滞后连接）· 车道检测链路第 5 级
// Desc   : 双阈值判定 + 3x3 邻域强边连接（滞后），输出二值边缘图
//              strong = mag >= cfg_thr_high        -> 直接输出边缘
//              weak   = low <= mag <  high         -> 仅当 3x3 邻域存在强边才输出
// LATENCY: 2 行 + 3 cycles
// Note   : 1) 阈值为运行时寄存器，默认 low=50 / high=150，与 OpenCV
//             cv2.Canny(blur, 50, 150) **同值**（因为幅值同为 L1 口径）；
//          2) ⚠ 与 OpenCV 的差异：OpenCV 的滞后是"全图 8 连通迭代传播"，
//             本设计为**单次 3x3 邻域连接**的硬件近似。
//             实际车道线是连续长边，3x3 连接已能保留主体边缘；
//             该近似已写入 reports/lint 与设计说明，不隐瞒；
//          3) {valid,weak,strong} 同走 line_buffer_3x3(DW=3)，
//             弱边取窗口中心 q11，避免用右下输入像素判断中心。
// ============================================================
`timescale 1ns / 1ps

module canny_hyst #(
    parameter P_MAG_W = 12,
    parameter P_IMG_W = 1920,
    parameter P_XW    = 11,
    parameter P_YW    = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    m_axis_tready,
    output wire                    s_axis_tready,

    // ---- 配置（来自 AXI4-Lite 寄存器，需与 clk 同域或已同步）----
    input  wire [P_MAG_W-1:0]      cfg_thr_low,
    input  wire [P_MAG_W-1:0]      cfg_thr_high,

    // ---- 输入流：NMS 后幅值 ----
    input  wire [P_MAG_W-1:0]      s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire [P_XW-1:0]         s_axis_tx,
    input  wire [P_YW-1:0]         s_axis_ty,
    input  wire                    s_axis_tuser,
    input  wire                    s_axis_tlast,

    // ---- 输出流：二值边缘 ----
    output reg                     m_axis_tdata,
    output reg                     m_axis_tvalid,
    output reg  [P_XW-1:0]         m_axis_tx,
    output reg  [P_YW-1:0]         m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    wire en = m_axis_tready;

    // Preserve frame identity across border suppression in the 3x3 window.
    reg  frame_tag_in_q;
    wire frame_tag_in = frame_tag_in_q ^ (s_axis_tvalid & s_axis_tuser);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_tag_in_q <= 1'b0;
        else if (en && s_axis_tvalid && s_axis_tuser)
            frame_tag_in_q <= ~frame_tag_in_q;
    end

    // ---------- 级 1：阈值判定 ----------
    wire strong_pixel = (s_axis_tdata >= cfg_thr_high);
    wire weak_pixel   = (s_axis_tdata >= cfg_thr_low) && (s_axis_tdata < cfg_thr_high);

    // ---------- 级 2~3：同源 strong/weak/valid 3x3 窗口 ----------
    wire [2:0] q00, q01, q02;
    wire [2:0] q10, q11, q12;
    wire [2:0] q20, q21, q22;
    wire       v_win;
    wire [P_XW-1:0] x_win;
    wire [P_YW-1:0] y_win;
    wire       frame_tag_win, l_win;

    line_buffer_3x3 #(
        .P_DATA_W (3      ),
        .P_IMG_W  (P_IMG_W),
        .P_XW     (P_XW   ),
        .P_YW     (P_YW   )
    ) u_win (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .m_axis_tready (m_axis_tready),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  ({s_axis_tvalid, weak_pixel, strong_pixel}),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tx     (s_axis_tx    ),
        .s_axis_ty     (s_axis_ty    ),
        .s_axis_tuser  (frame_tag_in ),
        .s_axis_tlast  (s_axis_tlast ),
        .m_axis_tvalid (v_win        ),
        .m_axis_tx     (x_win        ),
        .m_axis_ty     (y_win        ),
        .m_axis_tuser  (frame_tag_win),
        .m_axis_tlast  (l_win        ),
        .w00 (q00), .w01 (q01), .w02 (q02),
        .w10 (q10), .w11 (q11), .w12 (q12),
        .w20 (q20), .w21 (q21), .w22 (q22)
    );

    wire s00 = q00[0], s01 = q01[0], s02 = q02[0];
    wire s10 = q10[0], s11 = q11[0], s12 = q12[0];
    wire s20 = q20[0], s21 = q21[0], s22 = q22[0];

    wire v9 = q00[2] & q01[2] & q02[2]
            & q10[2] & q11[2] & q12[2]
            & q20[2] & q21[2] & q22[2];

    wire v_ok = v_win & v9;

    wire nb_strong = s00 | s01 | s02 | s10 | s11 | s12 | s20 | s21 | s22;
    // Both predicates describe the SAME centre (x_win,y_win). Window
    // completeness is applied to m_axis_tvalid; no extra token is inserted.
    wire edge_n    = s11 | (q11[1] & q11[2] & nb_strong);
    reg  frame_tag_out_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
            frame_tag_out_q <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= edge_n;
            m_axis_tvalid <= v_ok;
            m_axis_tx     <= x_win;
            m_axis_ty     <= y_win;
            m_axis_tuser  <= v_ok & (frame_tag_win != frame_tag_out_q);
            m_axis_tlast  <= v_ok & l_win;
            if (v_ok)
                frame_tag_out_q <= frame_tag_win;
        end
    end

endmodule
