// ============================================================
// Module : canny_nms
// Target : ALG-06+（Canny 非极大值抑制）· 车道检测链路第 4 级
// Desc   : 按 Sobel 量化方向在 3x3 邻域内做非极大值抑制（NMS）
//              dir=00 (0°  ) : 比较 w10 / w12   （左 - 右）
//              dir=01 (45° ) : 比较 w00 / w22   （左上 - 右下）
//              dir=10 (90° ) : 比较 w01 / w21   （上 - 下）
//              dir=11 (135°) : 比较 w02 / w20   （右上 - 左下）
// LATENCY: 2 行 + 3 cycles
// Note   : 1) 判据为"不小于两侧"即保留（>=），与 OpenCV Canny 一致，
//             避免平台相等时弱边被误删；
//          2) mag 与 dir **打包成同一字**一起进 line_buffer_3x3，
//             保证幅值与方向永远同源同拍，结构上不可能错位；
//          3) 被抑制像素输出 0（而非拉低 valid），下游按幅值阈值筛选。
// ============================================================
`timescale 1ns / 1ps

module canny_nms #(
    parameter P_MAG_W = 12,
    parameter P_IMG_W = 1920,
    parameter P_XW    = 11,
    parameter P_YW    = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    m_axis_tready,
    output wire                    s_axis_tready,

    // ---- 输入流：Sobel 幅值 + 方向 ----
    input  wire [P_MAG_W-1:0]      s_axis_tdata,
    input  wire [1:0]              s_axis_tdir,
    input  wire                    s_axis_tvalid,
    input  wire [P_XW-1:0]         s_axis_tx,
    input  wire [P_YW-1:0]         s_axis_ty,
    input  wire                    s_axis_tuser,
    input  wire                    s_axis_tlast,

    // ---- 输出流：NMS 后幅值（被抑制的为 0）----
    output reg  [P_MAG_W-1:0]      m_axis_tdata,
    output reg                     m_axis_tvalid,
    output reg  [P_XW-1:0]         m_axis_tx,
    output reg  [P_YW-1:0]         m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    localparam P_PACK_W = P_MAG_W + 2;

    wire en = m_axis_tready;

    // Keep frame identity alive while the 3x3 window discards border beats.
    // The output SOF is rebuilt when the first valid sample of a new tag exits.
    reg  frame_tag_in_q;
    wire frame_tag_in = frame_tag_in_q ^ (s_axis_tvalid & s_axis_tuser);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_tag_in_q <= 1'b0;
        else if (en && s_axis_tvalid && s_axis_tuser)
            frame_tag_in_q <= ~frame_tag_in_q;
    end

    // ---------- 级 1~2：打包 + 3x3 窗口（★ valid 随窗口一起传播）----------
    wire [P_PACK_W:0] p00, p01, p02;
    wire [P_PACK_W:0] p10, p11, p12;
    wire [P_PACK_W:0] p20, p21, p22;
    wire              v_win;
    wire [P_XW-1:0]   x_win;
    wire [P_YW-1:0]   y_win;
    wire              frame_tag_win, l_win;

    line_buffer_3x3 #(
        .P_DATA_W (P_PACK_W + 1),
        .P_IMG_W  (P_IMG_W     ),
        .P_XW     (P_XW        ),
        .P_YW     (P_YW        )
    ) u_win (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .m_axis_tready (m_axis_tready),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  ({s_axis_tvalid, s_axis_tdir, s_axis_tdata}),
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
        .w00 (p00), .w01 (p01), .w02 (p02),
        .w10 (p10), .w11 (p11), .w12 (p12),
        .w20 (p20), .w21 (p21), .w22 (p22)
    );

    // 剥离 valid 位（最高位），只保留 {dir, mag}
    wire [P_PACK_W-1:0] q00 = p00[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q01 = p01[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q02 = p02[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q10 = p10[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q11 = p11[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q12 = p12[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q20 = p20[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q21 = p21[P_PACK_W-1:0];
    wire [P_PACK_W-1:0] q22 = p22[P_PACK_W-1:0];

    wire v9 = p00[P_PACK_W] & p01[P_PACK_W] & p02[P_PACK_W]
            & p10[P_PACK_W] & p11[P_PACK_W] & p12[P_PACK_W]
            & p20[P_PACK_W] & p21[P_PACK_W] & p22[P_PACK_W];

    wire v_ok = v_win & v9;

    // ---------- 级 3：方向选择 + 非极大抑制 ----------
    wire [P_MAG_W-1:0] m00 = q00[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m01 = q01[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m02 = q02[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m10 = q10[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m11 = q11[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m12 = q12[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m20 = q20[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m21 = q21[P_MAG_W-1:0];
    wire [P_MAG_W-1:0] m22 = q22[P_MAG_W-1:0];

    wire [1:0] dir_c = q11[P_PACK_W-1:P_MAG_W];

    wire [P_MAG_W-1:0] nb_a = (dir_c == 2'b00) ? m10 :
                              (dir_c == 2'b01) ? m00 :
                              (dir_c == 2'b10) ? m01 : m20;

    wire [P_MAG_W-1:0] nb_b = (dir_c == 2'b00) ? m12 :
                              (dir_c == 2'b01) ? m22 :
                              (dir_c == 2'b10) ? m21 : m02;

    wire               keep  = (m11 >= nb_a) && (m11 >= nb_b);
    wire [P_MAG_W-1:0] nms_m = keep ? m11 : {P_MAG_W{1'b0}};
    reg                frame_tag_out_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {P_MAG_W{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
            frame_tag_out_q <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= nms_m;
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
