// ============================================================
// Module : gauss5x5
// Target : ALG-03（高斯滤波）· 车道检测链路第 2 级
// Desc   : 5x5 高斯平滑，对应 OpenCV cv2.GaussianBlur(gray,(5,5),0)
//          采用可分离实现  [1 4 6 4 1]/16 ⊗ [1 4 6 4 1]/16 = /256
// LATENCY: 2 行 + 5 cycles
// Note   : 1) OpenCV 在 sigma=0 时按 ksize 反算 sigma=1.16，核并非严格二项式；
//             本设计取二项式核 [1 4 6 4 1]（σ≈1.0），
//             与 Python 参考模型 max|diff| <= 2 LSB，已在 reports/ 记录；
//          2) 二项式核只需加/移位，**不消耗 DSP**；
//          3) 边界策略：中心点必须满足 x>=2 且 y>=2（5x5 完整可采），
//             越界像素 tvalid 拉低；与 Python 参考模型的 'edge'（复制边缘）
//             不同，比对时按有效区域裁剪（见 model/ref_lane_detect.py）；
//          4) 坐标链与数据链严格等长：h 级 4 拍（2 列空间移位 + 2 拍寄存），
//             v 级 1 拍，算术 2 拍。
// ============================================================
`timescale 1ns / 1ps

module gauss5x5 #(
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

    // ---- 输出流：8bit 灰度 ----
    output reg  [P_DATA_W-1:0]     m_axis_tdata,
    output reg                     m_axis_tvalid,
    output reg  [P_XW-1:0]         m_axis_tx,
    output reg  [P_YW-1:0]         m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    localparam P_HW = P_DATA_W + 4;    // 水平 5 抽头和位宽：255*16 = 4080 -> 12bit
    localparam P_VW = P_HW + 4;        // 垂直 5 抽头和位宽：4080*16 = 65280 -> 16bit

    wire en = m_axis_tready;

    assign s_axis_tready = m_axis_tready;

    // A one-cycle SOF pulse is lost while the 5x5 window is warming up.
    // Convert it to a frame tag that stays with every sample, then recreate
    // SOF on the first valid output carrying the new tag.
    reg  frame_tag_in_q;
    wire frame_tag_in = frame_tag_in_q ^ (s_axis_tvalid & s_axis_tuser);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_tag_in_q <= 1'b0;
        else if (en && s_axis_tvalid && s_axis_tuser)
            frame_tag_in_q <= ~frame_tag_in_q;
    end

    // ============================================================
    // 级 1：水平 5 抽头 [1 4 6 4 1]
    // ============================================================
    reg [P_DATA_W-1:0] sr0, sr1, sr2, sr3, sr4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr0 <= {P_DATA_W{1'b0}}; sr1 <= {P_DATA_W{1'b0}};
            sr2 <= {P_DATA_W{1'b0}}; sr3 <= {P_DATA_W{1'b0}};
            sr4 <= {P_DATA_W{1'b0}};
        end else if (en) begin
            sr0 <= s_axis_tdata;
            sr1 <= sr0;
            sr2 <= sr1;
            sr3 <= sr2;
            sr4 <= sr3;
        end
    end

    // 中心和 = sr0 + 4*sr1 + 6*sr2 + 4*sr3 + sr4（中心为 sr2，即左移 2 列）
    // 6*sr2 = 4*sr2 + 2*sr2，全部用移位加法，不占 DSP
    wire [P_HW-1:0] h_sum = {4'b0, sr0}
                          + {2'b0, sr1, 2'b00}
                          + {2'b0, sr2, 1'b0} + {1'b0, sr2, 2'b00}
                          + {2'b0, sr3, 2'b00}
                          + {4'b0, sr4};

    // 坐标延迟 4 拍 = 2（列空间移位）+ 2（寄存对齐）
    reg [P_XW-1:0] xd1, xd2, xd3, xd4;
    reg [P_YW-1:0] yd1, yd2, yd3, yd4;
    reg            vd1, vd2, vd3, vd4;
    reg            ud1, ud2, ud3, ud4;
    reg            ld1, ld2, ld3, ld4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xd1 <= {P_XW{1'b0}}; xd2 <= {P_XW{1'b0}};
            xd3 <= {P_XW{1'b0}}; xd4 <= {P_XW{1'b0}};
            yd1 <= {P_YW{1'b0}}; yd2 <= {P_YW{1'b0}};
            yd3 <= {P_YW{1'b0}}; yd4 <= {P_YW{1'b0}};
            vd1 <= 1'b0; vd2 <= 1'b0; vd3 <= 1'b0; vd4 <= 1'b0;
            ud1 <= 1'b0; ud2 <= 1'b0; ud3 <= 1'b0; ud4 <= 1'b0;
            ld1 <= 1'b0; ld2 <= 1'b0; ld3 <= 1'b0; ld4 <= 1'b0;
        end else if (en) begin
            xd1 <= s_axis_tx;    xd2 <= xd1;    xd3 <= xd2;    xd4 <= xd3;
            yd1 <= s_axis_ty;    yd2 <= yd1;    yd3 <= yd2;    yd4 <= yd3;
            vd1 <= s_axis_tvalid; vd2 <= vd1;   vd3 <= vd2;    vd4 <= vd3;
            ud1 <= frame_tag_in;  ud2 <= ud1;   ud3 <= ud2;    ud4 <= ud3;
            ld1 <= s_axis_tlast;  ld2 <= ld1;   ld3 <= ld2;    ld4 <= ld3;
        end
    end

    // h 级输出寄存：h_sum 在 t+1 形成（中心 = t-3 时刻的输入列），
    // 寄存后 t+2 有效；坐标链 xd4 在 t+2 恰好等于 tx(t-2)=X-2，
    // 因此 v_h/x_h/y_h 必须直接取自 4 级延迟链，**不可再寄存一拍**。
    reg [P_HW-1:0] h_sum_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_sum_r <= {P_HW{1'b0}};
        end else if (en) begin
            h_sum_r <= h_sum;
        end
    end

    wire            v_h = vd4;
    wire [P_XW-1:0] x_h = xd4;
    wire [P_YW-1:0] y_h = yd4;

    // ============================================================
    // 级 2：垂直 5 抽头 [1 4 6 4 1]（复用 line_buffer_rows，P_ROWS=5）
    // ============================================================
    wire [5*P_HW-1:0] rows_flat;
    wire              v_rows;
    wire [P_XW-1:0]   x_rows;
    wire [P_YW-1:0]   y_rows;
    wire              frame_tag_rows;

    line_buffer_rows #(
        .P_DATA_W (P_HW   ),
        .P_IMG_W  (P_IMG_W),
        .P_ROWS   (5      ),
        .P_XW     (P_XW   ),
        .P_YW     (P_YW   )
    ) u_rows (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .m_axis_tready (m_axis_tready),
        .s_axis_tready (             ),
        .s_axis_tdata  (h_sum_r      ),
        .s_axis_tvalid (v_h          ),
        .s_axis_tx     (x_h          ),
        .s_axis_ty     (y_h          ),
        .s_axis_tuser  (ud4        ),
        .s_axis_tlast  (ld4        ),
        .m_axis_tdata  (             ),
        .m_axis_tvalid (v_rows       ),
        .m_axis_tx     (x_rows       ),
        .m_axis_ty     (y_rows       ),
        .m_axis_tuser  (frame_tag_rows),
        .m_axis_tlast  (             ),
        .m_row_flat    (rows_flat    )
    );

    // First register the BRAM row vector, then three independent partial
    // sums. This removes the measured BRAM->six-addends->round critical path.
    reg [5*P_HW-1:0] rows_q;
    reg rows_valid_q, rows_tag_q;
    reg [P_XW-1:0] rows_x_q;
    reg [P_YW-1:0] rows_y_q;
    wire [P_HW-1:0] r0 = rows_q[0*P_HW +: P_HW];
    wire [P_HW-1:0] r1 = rows_q[1*P_HW +: P_HW];
    wire [P_HW-1:0] r2 = rows_q[2*P_HW +: P_HW];
    wire [P_HW-1:0] r3 = rows_q[3*P_HW +: P_HW];
    wire [P_HW-1:0] r4 = rows_q[4*P_HW +: P_HW];
    reg [P_VW-1:0] outer_sum_q, adjacent_sum_q, center_sum_q;
    reg partial_valid_q, partial_tag_q;
    reg [P_XW-1:0] partial_x_q;
    reg [P_YW-1:0] partial_y_q;
    wire [P_VW-1:0] v_sum = outer_sum_q + adjacent_sum_q + center_sum_q;

    // ============================================================
    // 级 3~4：舍入 + 归一化 + 输出寄存
    // ============================================================
    localparam [P_XW-1:0] C_XMIN = 2;                 // 中心列 >= 2（5 列完整）
    localparam [P_XW-1:0] C_XMAX = P_IMG_W - 3;       // 中心列 <= W-3（右侧 5 列完整）
    localparam [P_YW-1:0] C_YMIN = 4;                 // 输入行 >= 4（5 行完整）

    wire             v_ok = v_rows & (x_rows >= C_XMIN) & (x_rows <= C_XMAX)
                                   & (y_rows >= C_YMIN);
    reg              frame_tag_out_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rows_q <= 0; rows_valid_q <= 0; rows_tag_q <= 0;
            rows_x_q <= 0; rows_y_q <= 0;
            outer_sum_q <= 0; adjacent_sum_q <= 0; center_sum_q <= 0;
            partial_valid_q <= 0; partial_tag_q <= 0;
            partial_x_q <= 0; partial_y_q <= 0;
        end else if (en) begin
            rows_q <= rows_flat;
            rows_valid_q <= v_ok;
            rows_tag_q <= frame_tag_rows;
            rows_x_q <= x_rows;
            rows_y_q <= y_rows - 2;
            outer_sum_q <= {4'b0,r0} + {4'b0,r4} + 128;
            adjacent_sum_q <= ({4'b0,r1} + {4'b0,r3}) << 2;
            center_sum_q <= ({4'b0,r2} << 2) + ({4'b0,r2} << 1);
            partial_valid_q <= rows_valid_q;
            partial_tag_q <= rows_tag_q;
            partial_x_q <= rows_x_q;
            partial_y_q <= rows_y_q;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {P_DATA_W{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= {P_XW{1'b0}};
            m_axis_ty     <= {P_YW{1'b0}};
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
            frame_tag_out_q <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= v_sum[P_VW-1:8];
            m_axis_tvalid <= partial_valid_q;
            m_axis_tx     <= partial_x_q;
            m_axis_ty     <= partial_y_q;
            m_axis_tuser  <= partial_valid_q & (partial_tag_q != frame_tag_out_q);
            // Horizontal windowing removes the final two source columns, so
            // the raw input TLAST no longer coincides with a valid output.
            m_axis_tlast  <= partial_valid_q & (partial_x_q == C_XMAX);
            if (partial_valid_q)
                frame_tag_out_q <= partial_tag_q;
        end
    end

endmodule
