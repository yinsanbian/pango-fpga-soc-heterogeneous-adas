// ============================================================
// Module : rgb2gray
// Target : ALG-02（灰度化）· 车道检测链路第 1 级
// Desc   : RGB888 -> 8bit 灰度，对应 OpenCV cv2.cvtColor(img, COLOR_BGR2GRAY)
//          定点式 Y = (77R + 150G + 29B + 128) >> 8      (Q8 系数)
// LATENCY: 3 cycles
// Note   : 1) 浮点系数 0.299 / 0.587 / 0.114 -> Q8 = 77 / 150 / 29，
//             和的绝对误差 <= 0.5 LSB（+128 为四舍五入），满足 ALG-02 判据；
//          2) s_axis_tdata 为 {R,G,B} 各 8bit，MSB 为 R；
//          3) 坐标 (tx,ty) 与数据同拍寄存，供下游"同源"使用（避坑 #9）。
// ============================================================
`timescale 1ns / 1ps

module rgb2gray #(
    parameter P_DATA_W = 8
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- 全局流水使能（与 m_axis_tready 同源，全链路统一冻结）----
    input  wire                    m_axis_tready,
    output wire                    s_axis_tready,

    // ---- 输入流：RGB888 ----
    input  wire [3*P_DATA_W-1:0]   s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire [10:0]             s_axis_tx,
    input  wire [10:0]             s_axis_ty,
    input  wire                    s_axis_tuser,   // SOF（帧首）
    input  wire                    s_axis_tlast,   // EOL（行尾）

    // ---- 输出流：8bit 灰度 ----
    output reg  [P_DATA_W-1:0]     m_axis_tdata,
    output reg                     m_axis_tvalid,
    output reg  [10:0]             m_axis_tx,
    output reg  [10:0]             m_axis_ty,
    output reg                     m_axis_tuser,
    output reg                     m_axis_tlast
);

    localparam COEF_R = 77;      // 0.299 * 256
    localparam COEF_G = 150;     // 0.587 * 256
    localparam COEF_B = 29;      // 0.114 * 256

    assign s_axis_tready = m_axis_tready;
    wire en = m_axis_tready;

    // ---------- 级 1：输入寄存 ----------
    reg [P_DATA_W-1:0] r_r, r_g, r_b;
    reg                v1;
    reg [10:0]         x1, y1;
    reg                u1, l1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_r <= {P_DATA_W{1'b0}};
            r_g <= {P_DATA_W{1'b0}};
            r_b <= {P_DATA_W{1'b0}};
            v1  <= 1'b0;
            x1  <= 11'd0;
            y1  <= 11'd0;
            u1  <= 1'b0;
            l1  <= 1'b0;
        end else if (en) begin
            r_r <= s_axis_tdata[3*P_DATA_W-1 -: P_DATA_W];
            r_g <= s_axis_tdata[2*P_DATA_W-1 -: P_DATA_W];
            r_b <= s_axis_tdata[1*P_DATA_W-1 -: P_DATA_W];
            v1  <= s_axis_tvalid;
            x1  <= s_axis_tx;
            y1  <= s_axis_ty;
            u1  <= s_axis_tuser;
            l1  <= s_axis_tlast;
        end
    end

    // ---------- 级 2：乘法（映射 DSP 切片）----------
    reg [15:0] pr, pg, pb;
    reg        v2;
    reg [10:0] x2, y2;
    reg        u2, l2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pr <= 16'd0;
            pg <= 16'd0;
            pb <= 16'd0;
            v2 <= 1'b0;
            x2 <= 11'd0;
            y2 <= 11'd0;
            u2 <= 1'b0;
            l2 <= 1'b0;
        end else if (en) begin
            pr <= r_r * COEF_R;
            pg <= r_g * COEF_G;
            pb <= r_b * COEF_B;
            v2 <= v1;
            x2 <= x1;
            y2 <= y1;
            u2 <= u1;
            l2 <= l1;
        end
    end

    // ---------- 级 3：累加 + 四舍五入 + 输出寄存 ----------
    // 最大值 (77+150+29)*255 = 65280，+128 后 65408，>>8 = 255 不溢出
    wire [16:0] y_sum = {1'b0, pr} + {1'b0, pg} + {1'b0, pb} + 17'd128;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= {P_DATA_W{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tx     <= 11'd0;
            m_axis_ty     <= 11'd0;
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (en) begin
            m_axis_tdata  <= y_sum[15:8];
            m_axis_tvalid <= v2;
            m_axis_tx     <= x2;
            m_axis_ty     <= y2;
            m_axis_tuser  <= u2;
            m_axis_tlast  <= l2;
        end
    end

endmodule
