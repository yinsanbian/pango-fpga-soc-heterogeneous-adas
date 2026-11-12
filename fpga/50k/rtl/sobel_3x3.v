// ============================================================
// Module : sobel_3x3
// Target : ALG-06（Sobel 边缘检测）· 车道检测链路第 3 级
// Desc   : 3x3 Sobel 梯度 + L1 幅值 + 4 方向量化（供 Canny NMS 使用）
//              Gx = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)
//              Gy = (p20 + 2*p21 + p22) - (p00 + 2*p01 + p02)
//              |G| = |Gx| + |Gy|      ← 与 OpenCV cv2.Canny 默认
//                                        (L2gradient=False) 的 L1 口径一致
// LATENCY: 2 行 + 5 advance tokens（暂停保持；每token一像素）
// Note   : 1) 幅值用 |Gx|+|Gy| 避免开方，与 ALG-06 判据及 OpenCV 默认一致，
//             因此 cv2.Canny 的阈值 50/150 **可直接使用**，无需换算；
//          2) 方向量化阈值按 tan(22.5°)=0.414 / tan(67.5°)=2.414 取有理近似
//             5/12 与 12/5，只用常数乘加，不占 DSP；
//                dir = 2'b00 : 0°   （|Gx| 主导，边缘近垂直 → 比左右）
//                dir = 2'b01 : 45°
//                dir = 2'b10 : 90°  （|Gy| 主导，边缘近水平 → 比上下）
//                dir = 2'b11 : 135°
//          3) 窗口边界由 line_buffer_3x3 内部裁剪，输出坐标即窗口中心坐标。
// ============================================================
`timescale 1ns / 1ps

module sobel_3x3 #(
    parameter P_DATA_W = 8,
    parameter P_IMG_W  = 1920,
    parameter P_XW     = 11,
    parameter P_YW     = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    m_axis_tready,
    output wire                    s_axis_tready,

    // ---- 输入流：8bit 灰度 ----
    input  wire [P_DATA_W-1:0]     s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire [P_XW-1:0]         s_axis_tx,
    input  wire [P_YW-1:0]         s_axis_ty,
    input  wire                    s_axis_tuser,
    input  wire                    s_axis_tlast,

    // ---- 输出流：梯度幅值 + 方向 ----
    output reg  [P_DATA_W+3:0]     m_axis_tdata,      // |Gx|+|Gy|，12bit
    output reg  [1:0]              m_axis_tdir,       // 方向量化
    output reg                     m_axis_tvalid,
    output reg  [P_XW-1:0]         m_axis_tx,
    output reg  [P_YW-1:0]         m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    localparam P_MAG_W = P_DATA_W + 4;                // 12
    localparam P_SUM_W = P_DATA_W + 2;                // 10（列/行和最大值 1020）

    wire en = m_axis_tready;

    // Window warm-up suppresses the input SOF beat.  Carry a persistent
    // frame tag through the same sideband path as the window coordinates.
    reg  frame_tag_in_q;
    wire frame_tag_in = frame_tag_in_q ^ (s_axis_tvalid & s_axis_tuser);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_tag_in_q <= 1'b0;
        else if (en && s_axis_tvalid && s_axis_tuser)
            frame_tag_in_q <= ~frame_tag_in_q;
    end

    // ---------- 级 1~2：3x3 窗口（★ valid 随窗口一起缓存并传播）----------
    wire [P_DATA_W:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    wire              v_win;
    wire [P_XW-1:0]   x_win;
    wire [P_YW-1:0]   y_win;
    wire              u_win, l_win;

    line_buffer_3x3 #(
        .P_DATA_W (P_DATA_W + 1),
        .P_IMG_W  (P_IMG_W     ),
        .P_XW     (P_XW        ),
        .P_YW     (P_YW        )
    ) u_winbuf (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .m_axis_tready (m_axis_tready),
        .s_axis_tready (s_axis_tready),
        .s_axis_tdata  ({s_axis_tvalid, s_axis_tdata}),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tx     (s_axis_tx    ),
        .s_axis_ty     (s_axis_ty    ),
        .s_axis_tuser  (frame_tag_in ),
        .s_axis_tlast  (s_axis_tlast ),
        .m_axis_tvalid (v_win        ),
        .m_axis_tx     (x_win        ),
        .m_axis_ty     (y_win        ),
        .m_axis_tuser  (u_win        ),
        .m_axis_tlast  (l_win        ),
        .w00 (p00), .w01 (p01), .w02 (p02),
        .w10 (p10), .w11 (p11), .w12 (p12),
        .w20 (p20), .w21 (p21), .w22 (p22)
    );

    wire [P_DATA_W-1:0] w00 = p00[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w01 = p01[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w02 = p02[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w10 = p10[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w11 = p11[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w12 = p12[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w20 = p20[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w21 = p21[P_DATA_W-1:0];
    wire [P_DATA_W-1:0] w22 = p22[P_DATA_W-1:0];

    // 9 个输入像素全部有效，3x3 结果才有定义（valid 随窗口传播）
    wire v9 = p00[P_DATA_W] & p01[P_DATA_W] & p02[P_DATA_W]
            & p10[P_DATA_W] & p11[P_DATA_W] & p12[P_DATA_W]
            & p20[P_DATA_W] & p21[P_DATA_W] & p22[P_DATA_W];

    wire v_ok = v_win & v9;

    // ---------- 级 3：列和 / 行和（2 倍权重用移位）----------
    // ★ 位宽显式对齐到 P_SUM_W(10)，避免 Verilog 表达式按最宽操作数截断
    reg [P_SUM_W-1:0] col_r, col_l, row_b, row_t;
    reg               v3;
    reg [P_XW-1:0]    x3;
    reg [P_YW-1:0]    y3;
    reg               u3, l3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_r <= {P_SUM_W{1'b0}};
            col_l <= {P_SUM_W{1'b0}};
            row_b <= {P_SUM_W{1'b0}};
            row_t <= {P_SUM_W{1'b0}};
            v3    <= 1'b0;
            x3    <= {P_XW{1'b0}};
            y3    <= {P_YW{1'b0}};
            u3    <= 1'b0;
            l3    <= 1'b0;
        end else if (en) begin
            // ★ 权重必须靠"补 0 的位数"表达：{1'b0,x,1'b0} = 2*x，{2'b00,x,2'b00} = 4*x
            col_r <= {2'b00, w02} + {1'b0, w12, 1'b0} + {2'b00, w22};   // 右列 1,2,1
            col_l <= {2'b00, w00} + {1'b0, w10, 1'b0} + {2'b00, w20};   // 左列 1,2,1
            row_b <= {2'b00, w20} + {1'b0, w21, 1'b0} + {2'b00, w22};   // 下行 1,2,1
            row_t <= {2'b00, w00} + {1'b0, w01, 1'b0} + {2'b00, w02};   // 上行 1,2,1
            v3    <= v_ok;
            x3    <= x_win;
            y3    <= y_win;
            u3    <= u_win;
            l3    <= l_win;
        end
    end

    // ---------- 级 4：梯度寄存，切断减法→abs→方向比较长路径 ----------
    reg signed [P_SUM_W:0] gx, gy;
    reg v4,u4,l4;
    reg [P_XW-1:0] x4;
    reg [P_YW-1:0] y4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx <= 0;gy <= 0;
            v4 <= 0;u4 <= 0;l4 <= 0;
            x4 <= 0;y4 <= 0;
        end else if (en) begin
            gx <= $signed({1'b0, col_r}) - $signed({1'b0, col_l});
            gy <= $signed({1'b0, row_b}) - $signed({1'b0, row_t});
            v4 <= v3;x4 <= x3;y4 <= y3;u4 <= u3;l4 <= l3;
        end
    end

    // ---------- 级 5：同源的绝对值、幅值、方向及裁剪后帧标志 ----------
    wire [P_SUM_W:0] ax = gx[P_SUM_W] ? (~gx + 1'b1) : gx;   // |Gx|
    wire [P_SUM_W:0] ay = gy[P_SUM_W] ? (~gy + 1'b1) : gy;   // |Gy|

    wire [P_MAG_W-1:0] mag = {1'b0, ax} + {1'b0, ay};

    // 方向量化：12*|Gy| >  5*|Gx|  -> 90°（近水平边缘）
    //           12*|Gy| <= 5*|Gx|  -> 0° （近垂直边缘）
    wire [P_SUM_W+4:0] ay_x12 = {ay, 3'b000} + {ay, 2'b00};       // ay*12（最大 12240）
    wire [P_SUM_W+4:0] ay_x5  = {ay, 2'b00} + ay;                 // ay*5
    wire [P_SUM_W+4:0] ax_x12 = {ax, 3'b000} + {ax, 2'b00};       // ax*12
    wire [P_SUM_W+4:0] ax_x5  = {ax, 2'b00} + ax;                 // ax*5

    wire [1:0] dir_n = (ay_x5 > ax_x12)      ? 2'b10 :
                       (ay_x12 <= ax_x5)     ? 2'b00 :
                       (gx[P_SUM_W] ^ gy[P_SUM_W]) ? 2'b11 : 2'b01;

    reg frame_tag_out_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {P_MAG_W{1'b0}};
            m_axis_tdir   <= 2'b00;
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
            frame_tag_out_q <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= mag;
            m_axis_tdir   <= dir_n;
            m_axis_tvalid <= v4;
            m_axis_tx     <= x4;
            m_axis_ty     <= y4;
            m_axis_tuser  <= v4 & (u4 != frame_tag_out_q);
            m_axis_tlast  <= v4 & l4;
            if (v4)
                frame_tag_out_q <= u4;
        end
    end

endmodule
