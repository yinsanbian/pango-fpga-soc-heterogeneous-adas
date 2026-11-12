// ============================================================
// Module : lane_fit
// Target : ALG-09（车道检测 · 左右车道加权拟合与端点求解）
// Desc   : 复现 OpenCV average_slope_intercept() + pixel_points()：
//            对每个 theta 分档取峰值 (theta, rho, votes)，
//              m = -cot(theta)      直线斜率，Q8
//              c =  rho / sin(theta) y 轴截距，Q8，**降采样单位**
//              w =  votes            权重（对应原码用线段长度做权重）
//            theta < 90 度 -> 左车道(m<0)；theta > 90 度 -> 右车道(m>0)，
//            分别加权平均后求 y=y1(底, P_IMG_H) 与 y=0.6H(顶) 两处 x：
//              x = ((y<<8) - c_full_q8) / m_avg_q8
// LATENCY: 帧内批处理；每次拟合 8 次顺序除法 x (32+2) 拍 约 272 拍/帧
// Note   : 1) 斜率/余割全部查表，无常驻除法器；仅用 div_seq 顺序除法
//             8 次/帧，面积可控；
//          2) 两条车道线参数**帧间保持**（整帧拟合完成才整体更新），
//             供 lane_draw 在下一帧绘制，天然无撕裂；
//          3) 保护：sum_w < cfg_min_weight 或 |m_avg| < 16(Q8，即斜率<0.0625)
//             判为该侧无效，不画线，避免"近水平线横穿整屏"的荒谬结果；
//          4) 坐标最终钳位到 [0, P_IMG_W-1]。
// ============================================================
`timescale 1ns / 1ps

module lane_fit #(
    parameter P_IMG_W = 1920,
    parameter P_IMG_H = 1080,
    parameter P_DECIM = 4,
    parameter P_XW    = 11,
    // 对应 cv2.HoughLinesP 的 threshold：票数低于此值的 theta 分档不参与
    // 加权平均。原码把 HoughLinesP 检出的**所有**线段都拿去平均，硬件里若
    // 把 64 个 theta 分档全拿来平均，噪声分档会把斜率拉偏；加门限等价于
    // 原码 threshold 的筛选作用。降采样后票数按 1/DECIM^2 缩水，故取值 4。
    parameter P_VOTE_THRESH = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 峰值输入（来自 hough_acc，每帧 64 个，theta 由 0 递增）----
    // rho 为有符号的降采样像素单位
    input  wire        s_peak_valid,
    input  wire [5:0]  s_peak_theta,
    input  wire signed [11:0] s_peak_rho,
    input  wire [7:0]  s_peak_votes,
    input  wire [7:0]  s_peak_strength,
    output wire        s_peak_ready,

    // ---- 配置 ----
    input  wire [15:0] cfg_min_weight,

    // ---- 车道线参数（帧间保持，x 为像素坐标）----
    output reg         o_lane_l_valid,
    output reg         o_lane_r_valid,
    output reg  signed [P_XW:0] o_lane_l_x1,     // 底端 (y = P_IMG_H)
    output reg  signed [P_XW:0] o_lane_l_x2,     // 顶端 (y = 0.6*P_IMG_H)
    output reg  signed [P_XW:0] o_lane_r_x1,
    output reg  signed [P_XW:0] o_lane_r_x2,
    output reg         o_params_valid            // 单拍脉冲
);

    localparam P_Y1 = P_IMG_H;                 // 底线（对应 cv2 的 y1 = image.shape[0]）
    localparam P_Y2 = (P_IMG_H * 6) / 10;      // 顶线（y2 = 0.6*y1）
    localparam signed [31:0] P_MSLOPE_MIN = 32'sd16;   // |m_q8| 下限

    // ------------------------------------------------------------
    // theta -> {m_q8, csc_q8} 查找表（由 tools/gen_lut.py 生成）
    // ------------------------------------------------------------
    function [31:0] lut_fit;
        input [5:0] k;
        begin
            case (k)
                6'd0 : lut_fit = {-16'sd256, 16'sd362}; // LEFT  m=-1.0000 csc=1.4142
                6'd1 : lut_fit = {-16'sd244, 16'sd353}; // LEFT  m=-0.9521 csc=1.3807
                6'd2 : lut_fit = {-16'sd232, 16'sd346}; // LEFT  m=-0.9063 csc=1.3496
                6'd3 : lut_fit = {-16'sd221, 16'sd338}; // LEFT  m=-0.8626 csc=1.3206
                6'd4 : lut_fit = {-16'sd210, 16'sd331}; // LEFT  m=-0.8207 csc=1.2936
                6'd5 : lut_fit = {-16'sd200, 16'sd325}; // LEFT  m=-0.7804 csc=1.2685
                6'd6 : lut_fit = {-16'sd190, 16'sd319}; // LEFT  m=-0.7417 csc=1.2450
                6'd7 : lut_fit = {-16'sd180, 16'sd313}; // LEFT  m=-0.7043 csc=1.2231
                6'd8 : lut_fit = {-16'sd171, 16'sd308}; // LEFT  m=-0.6682 csc=1.2027
                6'd9 : lut_fit = {-16'sd162, 16'sd303}; // LEFT  m=-0.6332 csc=1.1836
                6'd10: lut_fit = {-16'sd153, 16'sd298}; // LEFT  m=-0.5994 csc=1.1659
                6'd11: lut_fit = {-16'sd145, 16'sd294}; // LEFT  m=-0.5665 csc=1.1493
                6'd12: lut_fit = {-16'sd137, 16'sd290}; // LEFT  m=-0.5345 csc=1.1339
                6'd13: lut_fit = {-16'sd129, 16'sd287}; // LEFT  m=-0.5034 csc=1.1195
                6'd14: lut_fit = {-16'sd121, 16'sd283}; // LEFT  m=-0.4730 csc=1.1062
                6'd15: lut_fit = {-16'sd113, 16'sd280}; // LEFT  m=-0.4433 csc=1.0938
                6'd16: lut_fit = {-16'sd106, 16'sd277}; // LEFT  m=-0.4142 csc=1.0824
                6'd17: lut_fit = {-16'sd 99, 16'sd274}; // LEFT  m=-0.3857 csc=1.0718
                6'd18: lut_fit = {-16'sd 92, 16'sd272}; // LEFT  m=-0.3578 csc=1.0621
                6'd19: lut_fit = {-16'sd 85, 16'sd270}; // LEFT  m=-0.3304 csc=1.0532
                6'd20: lut_fit = {-16'sd 78, 16'sd268}; // LEFT  m=-0.3033 csc=1.0450
                6'd21: lut_fit = {-16'sd 71, 16'sd266}; // LEFT  m=-0.2767 csc=1.0376
                6'd22: lut_fit = {-16'sd 64, 16'sd264}; // LEFT  m=-0.2505 csc=1.0309
                6'd23: lut_fit = {-16'sd 57, 16'sd262}; // LEFT  m=-0.2246 csc=1.0249
                6'd24: lut_fit = {-16'sd 51, 16'sd261}; // LEFT  m=-0.1989 csc=1.0196
                6'd25: lut_fit = {-16'sd 44, 16'sd260}; // LEFT  m=-0.1735 csc=1.0149
                6'd26: lut_fit = {-16'sd 38, 16'sd259}; // LEFT  m=-0.1483 csc=1.0109
                6'd27: lut_fit = {-16'sd 32, 16'sd258}; // LEFT  m=-0.1233 csc=1.0076
                6'd28: lut_fit = {-16'sd 25, 16'sd257}; // LEFT  m=-0.0985 csc=1.0048
                6'd29: lut_fit = {-16'sd 19, 16'sd257}; // LEFT  m=-0.0738 csc=1.0027
                6'd30: lut_fit = {-16'sd 13, 16'sd256}; // LEFT  m=-0.0491 csc=1.0012
                6'd31: lut_fit = {-16'sd  6, 16'sd256}; // LEFT  m=-0.0245 csc=1.0003
                6'd32: lut_fit = { 16'sd  0, 16'sd256}; // SKIP  m= 0（水平线，弃用）
                6'd33: lut_fit = { 16'sd  6, 16'sd256}; // RIGHT m=+0.0245 csc=1.0003
                6'd34: lut_fit = { 16'sd 13, 16'sd256}; // RIGHT m=+0.0491 csc=1.0012
                6'd35: lut_fit = { 16'sd 19, 16'sd257}; // RIGHT m=+0.0738 csc=1.0027
                6'd36: lut_fit = { 16'sd 25, 16'sd257}; // RIGHT m=+0.0985 csc=1.0048
                6'd37: lut_fit = { 16'sd 32, 16'sd258}; // RIGHT m=+0.1233 csc=1.0076
                6'd38: lut_fit = { 16'sd 38, 16'sd259}; // RIGHT m=+0.1483 csc=1.0109
                6'd39: lut_fit = { 16'sd 44, 16'sd260}; // RIGHT m=+0.1735 csc=1.0149
                6'd40: lut_fit = { 16'sd 51, 16'sd261}; // RIGHT m=+0.1989 csc=1.0196
                6'd41: lut_fit = { 16'sd 57, 16'sd262}; // RIGHT m=+0.2246 csc=1.0249
                6'd42: lut_fit = { 16'sd 64, 16'sd264}; // RIGHT m=+0.2505 csc=1.0309
                6'd43: lut_fit = { 16'sd 71, 16'sd266}; // RIGHT m=+0.2767 csc=1.0376
                6'd44: lut_fit = { 16'sd 78, 16'sd268}; // RIGHT m=+0.3033 csc=1.0450
                6'd45: lut_fit = { 16'sd 85, 16'sd270}; // RIGHT m=+0.3304 csc=1.0532
                6'd46: lut_fit = { 16'sd 92, 16'sd272}; // RIGHT m=+0.3578 csc=1.0621
                6'd47: lut_fit = { 16'sd 99, 16'sd274}; // RIGHT m=+0.3857 csc=1.0718
                6'd48: lut_fit = { 16'sd106, 16'sd277}; // RIGHT m=+0.4142 csc=1.0824
                6'd49: lut_fit = { 16'sd113, 16'sd280}; // RIGHT m=+0.4433 csc=1.0938
                6'd50: lut_fit = { 16'sd121, 16'sd283}; // RIGHT m=+0.4730 csc=1.1062
                6'd51: lut_fit = { 16'sd129, 16'sd287}; // RIGHT m=+0.5034 csc=1.1195
                6'd52: lut_fit = { 16'sd137, 16'sd290}; // RIGHT m=+0.5345 csc=1.1339
                6'd53: lut_fit = { 16'sd145, 16'sd294}; // RIGHT m=+0.5665 csc=1.1493
                6'd54: lut_fit = { 16'sd153, 16'sd298}; // RIGHT m=+0.5994 csc=1.1659
                6'd55: lut_fit = { 16'sd162, 16'sd303}; // RIGHT m=+0.6332 csc=1.1836
                6'd56: lut_fit = { 16'sd171, 16'sd308}; // RIGHT m=+0.6682 csc=1.2027
                6'd57: lut_fit = { 16'sd180, 16'sd313}; // RIGHT m=+0.7043 csc=1.2231
                6'd58: lut_fit = { 16'sd190, 16'sd319}; // RIGHT m=+0.7417 csc=1.2450
                6'd59: lut_fit = { 16'sd200, 16'sd325}; // RIGHT m=+0.7804 csc=1.2685
                6'd60: lut_fit = { 16'sd210, 16'sd331}; // RIGHT m=+0.8207 csc=1.2936
                6'd61: lut_fit = { 16'sd221, 16'sd338}; // RIGHT m=+0.8626 csc=1.3206
                6'd62: lut_fit = { 16'sd232, 16'sd346}; // RIGHT m=+0.9063 csc=1.3496
                default: lut_fit = { 16'sd244, 16'sd353}; // RIGHT m=+0.9521 csc=1.3807
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Keep the strongest centre bin per side, supporting-window sum on ties.
    // （替代原"全部过门限档加权平均"——噪声档会把斜率拉偏，
    //   见 reports/sim_lane_detect.md §4.3 P3）
    // ------------------------------------------------------------
    reg [15:0]        sum_w_l, sum_w_r;   // 每侧选中档的权重（窗口和）
    reg [7:0]         strength_l, strength_r;
    reg signed [31:0] bm_l, bm_r;         // 每侧选中档的 m_q
    reg signed [31:0] bc_l, bc_r;         // 每侧选中档的 c_q = rho*csc（Q8 降采样单位）

    wire [5:0]  th      = s_peak_theta;
    // Verilog-2001 不允许直接对函数返回值做位选，必须先落到 wire
    wire [31:0]        lut_out = lut_fit(th);
    wire signed [15:0] m_q     = lut_out[31:16];
    wire signed [15:0] csc_q   = lut_out[15:0];
    wire               is_l    = (th < 6'd32);
    wire               is_r    = (th > 6'd32);

    wire signed [31:0] m_ext = $signed({{16{m_q[15]}}, m_q});
    // c = rho / sin(theta)：rho 为有符号降采样单位，故须先符号扩展
    wire signed [31:0] rho_s = $signed({{20{s_peak_rho[11]}}, s_peak_rho});
    wire signed [31:0] c_q   = rho_s * $signed({{16{csc_q[15]}}, csc_q});
    wire [15:0]        votes16 = {8'd0, s_peak_votes};
    wire candidate_ok = (s_peak_votes >= P_VOTE_THRESH[7:0]) &&
        (votes16 >= cfg_min_weight) &&
        ((m_ext <= -P_MSLOPE_MIN) || (m_ext >= P_MSLOPE_MIN));

    // ------------------------------------------------------------
    // 顺序除法调度
    // ------------------------------------------------------------
    localparam [3:0] ST_ACC  = 4'd0,
                     ST_M0   = 4'd1,   // 发起 m_avg 除法
                     ST_M1   = 4'd2,   // 等 m_avg + 有效性判据
                     ST_C0   = 4'd3,   // 发起 c_avg 除法
                     ST_C1   = 4'd4,   // 等 c_avg
                     ST_CF   = 4'd5,   // 降采样 -> 全分辨率
                     ST_X10  = 4'd6,   // 发起 x1 除法
                     ST_X11  = 4'd7,   // 等 x1
                     ST_X20  = 4'd8,   // 发起 x2 除法
                     ST_X21  = 4'd9,   // 等 x2
                     ST_FIN  = 4'd10,  // 本侧收尾 / 切换
                     ST_DONE = 4'd11;  // 输出参数脉冲

    reg [3:0]  st;
    reg        side;              // 0 = 左, 1 = 右

    reg        div_start;
    reg signed [31:0] div_a, div_b;
    wire signed [31:0] div_q;
    wire               div_done;
    wire               div_busy;
    wire               div_err;

    div_seq #(.P_W(32)) u_div (
        .clk   (clk      ),
        .rst_n (rst_n    ),
        .start (div_start),
        .a     (div_a    ),
        .b     (div_b    ),
        .q     (div_q    ),
        .done  (div_done ),
        .busy  (div_busy ),
        .err   (div_err  )
    );

    reg signed [31:0] m_avg;
    reg signed [31:0] c_avg;
    reg signed [31:0] c_full;
    reg signed [31:0] x1_t, x2_t;     // 本侧临时结果
    reg               side_bad;

    // 左右两侧最终结果（帧间保持）
    reg signed [P_XW:0] lx1, lx2, rx1, rx2;
    reg                 lv, rv;

    wire signed [31:0] bm_sel = side ? bm_r : bm_l;
    wire signed [31:0] bc_sel = side ? bc_r : bc_l;
    wire        [15:0] sum_w_sel  = side ? sum_w_r  : sum_w_l;

    assign s_peak_ready = (st == ST_ACC);

    // 钳位函数
    function signed [P_XW:0] clamp_x;
        input signed [31:0] v;
        begin
            if (v < 0)
                clamp_x = {1'b0, {P_XW{1'b0}}};
            else if (v > P_IMG_W - 1)
                clamp_x = P_IMG_W - 1;
            else
                clamp_x = v[P_XW:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st             <= ST_ACC;
            side           <= 1'b0;
            div_start      <= 1'b0;
            div_a          <= 32'sd0;
            div_b          <= 32'sd0;
            m_avg          <= 32'sd0;
            c_avg          <= 32'sd0;
            c_full         <= 32'sd0;
            x1_t           <= 32'sd0;
            x2_t           <= 32'sd0;
            side_bad       <= 1'b0;
            lx1            <= {(P_XW+1){1'b0}};
            lx2            <= {(P_XW+1){1'b0}};
            rx1            <= {(P_XW+1){1'b0}};
            rx2            <= {(P_XW+1){1'b0}};
            lv             <= 1'b0;
            rv             <= 1'b0;
            sum_w_l        <= 16'd0;
            sum_w_r        <= 16'd0;
            strength_l     <= 8'd0;
            strength_r     <= 8'd0;
            bm_l           <= 32'sd0;
            bm_r           <= 32'sd0;
            bc_l           <= 32'sd0;
            bc_r           <= 32'sd0;
            o_lane_l_valid <= 1'b0;
            o_lane_r_valid <= 1'b0;
            o_lane_l_x1    <= {(P_XW+1){1'b0}};
            o_lane_l_x2    <= {(P_XW+1){1'b0}};
            o_lane_r_x1    <= {(P_XW+1){1'b0}};
            o_lane_r_x2    <= {(P_XW+1){1'b0}};
            o_params_valid <= 1'b0;
        end else begin
            div_start      <= 1'b0;
            o_params_valid <= 1'b0;

            case (st)
            // Candidate support/slope gate, then centre strength and total.
            ST_ACC: begin
                if (s_peak_valid) begin
                    if (s_peak_theta == 6'd0) begin
                        // 新帧：左侧以 θ=0 档初始化，右侧清零
                        sum_w_l <= candidate_ok ? votes16 : 16'd0;
                        strength_l <= candidate_ok ? s_peak_strength : 8'd0;
                        bm_l    <= m_ext;
                        bc_l    <= c_q;
                        sum_w_r <= 16'd0;
                        strength_r <= 8'd0;
                        bm_r    <= 32'sd0;
                        bc_r    <= 32'sd0;
                    end else begin
                        if (is_l && candidate_ok &&
                            ((s_peak_strength > strength_l) ||
                             (s_peak_strength == strength_l && votes16 > sum_w_l))) begin
                            strength_l <= s_peak_strength;
                            sum_w_l <= votes16;
                            bm_l    <= m_ext;
                            bc_l    <= c_q;
                        end
                        if (is_r && candidate_ok &&
                            ((s_peak_strength > strength_r) ||
                             (s_peak_strength == strength_r && votes16 > sum_w_r))) begin
                            strength_r <= s_peak_strength;
                            sum_w_r <= votes16;
                            bm_r    <= m_ext;
                            bc_r    <= c_q;
                        end
                    end

                    if (s_peak_theta == 6'd63) begin
                        st   <= ST_M0;
                        side <= 1'b0;
                    end
                end
            end
            // ---------------- 斜率：P3 单档选择，m_avg = 选中档 m_q（免除法）----
            ST_M0: begin
                m_avg <= bm_sel;
                st    <= ST_M1;
            end
            ST_M1: begin
                if ((sum_w_sel < cfg_min_weight) ||
                    ((bm_sel > -P_MSLOPE_MIN) && (bm_sel < P_MSLOPE_MIN))) begin
                    side_bad <= 1'b1;
                    st       <= ST_FIN;                 // 本侧无效，直接收尾
                end else begin
                    side_bad <= 1'b0;
                    st       <= ST_C0;
                end
            end
            // ---------------- 截距：c_avg = 选中档 rho*csc（Q8 降采样单位）----
            ST_C0: begin
                c_avg <= bc_sel;
                st    <= ST_C1;
            end
            ST_C1: begin
                st <= ST_CF;
            end
            ST_CF: begin
                c_full <= c_avg * P_DECIM;              // 降采样单位 -> 全分辨率 Q8
                st     <= ST_X10;
            end
            // ---------------- x1 = ((Y1<<8) - c) / m ----------------
            ST_X10: begin
                div_a     <= ($signed(P_Y1) <<< 8) - c_full;
                div_b     <= m_avg;
                div_start <= 1'b1;
                st        <= ST_X11;
            end
            ST_X11: if (div_done) begin
                x1_t <= div_q;
                st   <= ST_X20;
            end
            // ---------------- x2 = ((Y2<<8) - c) / m ----------------
            ST_X20: begin
                div_a     <= ($signed(P_Y2) <<< 8) - c_full;
                div_b     <= m_avg;
                div_start <= 1'b1;
                st        <= ST_X21;
            end
            ST_X21: if (div_done) begin
                x2_t <= div_q;
                st   <= ST_FIN;
            end
            // ---------------- 本侧收尾 ----------------
            ST_FIN: begin
                if (side == 1'b0) begin
                    lv    <= ~side_bad;
                    lx1   <= clamp_x(x1_t);
                    lx2   <= clamp_x(x2_t);
                    side  <= 1'b1;
                    st    <= ST_M0;                     // 继续算右侧
                end else begin
                    rv    <= ~side_bad;
                    rx1   <= clamp_x(x1_t);
                    rx2   <= clamp_x(x2_t);
                    st    <= ST_DONE;
                end
            end
            // ---------------- 输出参数脉冲 ----------------
            ST_DONE: begin
                o_lane_l_valid <= lv;
                o_lane_l_x1    <= lx1;
                o_lane_l_x2    <= lx2;
                o_lane_r_valid <= rv;
                o_lane_r_x1    <= rx1;
                o_lane_r_x2    <= rx2;
                o_params_valid <= 1'b1;
                st             <= ST_ACC;
            end
            default: st <= ST_ACC;
            endcase
        end
    end

endmodule
