// ============================================================
// Module : hough_acc
// Target : ALG-09（车道检测 · 霍夫累加器 + 逐 θ 峰值提取）
// Desc   : 有限theta直线参数投票；下一输入帧开始后扫描上一帧，
//          输出(theta,rho,total-votes,center-strength)，不等价HoughLinesP。
//
//          · 投票对象：ROI 内**降采样**后的边缘点（默认 x/y 各除 4），
//            每点对64个theta投票：两拍乘积/求和预热，随后3拍/theta。
//            降采样是关键：否则每帧票数会淹没时序预算；
//          · theta=45..133.59375度，步进1.40625度；不覆盖任意道路斜率。
//          · ρ 分辨率 = 1 个降采样像素（= P_DECIM 个原始像素）。
//
// LATENCY: 帧内批处理（非逐拍流水）。
// Note   : 1) 默认存储64 x1152 x8bit；四窗实例64 x256 x8bit，计数饱和255。
//          2) ★ 每帧流程（顺序至关重要）：
//               上电 : CLEAR -> VOTE
//               SOF  : SCAN(读出上一帧票数, 约 74 K 拍)
//                      -> CLEAR(约 73728 拍) -> VOTE
//             即"先扫描、后清零"。若写成"先清零再扫描"，会把上一帧刚投完
//             的票清掉，峰值恒为 0（本项目实测踩过此坑，勿改回）。
//             1080P 时 SOF 到 ROI 首行有 747 行 = 1.64 M 拍，远大于 148 K 拍；
//          3) 投票忙时丢弃新请求并计入o_vote_drop。194拍确定性忙窗口
//             会形成输入顺序偏置，不是随机抽样；近距离第二条线须实测。
//          4) 8bit 饱和累加，防止长直线票数回绕；
//          5) 简单双口 RAM：投票端口"隔拍读-改-写"，扫描端口只读，
//             两类访问在时间上完全分离，不存在同址读写冲突。
//          6) scan分成BRAM回读FF、窗口scoreFF、best比较FF；静态min支持
//             过滤后按center票主/窗口总票次评分。调用者帧边界发布通常
//             带来两帧显示延迟，m_peak_valid/ready反压期间所有峰值保持。
// ============================================================
`timescale 1ns / 1ps

module hough_acc #(
    parameter P_IMG_W = 1920,
    parameter P_IMG_H = 1080,
    parameter P_DECIM = 4,               // 必须为 2 的幂
    parameter P_XW    = 11,
    parameter P_YW    = 11,
    parameter P_RHO_BINS = 1152,
    parameter P_RHO_OFF = 576,
    parameter P_MIN_WINDOW_VOTES = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        m_axis_tready,
    output wire        s_axis_tready,

    // ---- 投票输入：ROI 内二值边缘 + 坐标 ----
    input  wire        s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire [P_XW-1:0] s_axis_tx,
    input  wire [P_YW-1:0] s_axis_ty,
    input  wire        s_axis_tuser,      // SOF
    input  wire        s_axis_tlast,

    // ---- 峰值输出：(theta, rho, votes)，每帧 64 个 ----
    // rho 为***有符号的降采样像素单位***（已去掉累加器偏置），
    // 下游直接按 rho = x*cos+y*sin 的物理含义使用。
    output reg         m_peak_valid,
    output reg  [5:0]  m_peak_theta,
    output reg  signed [11:0] m_peak_rho,
    output reg  [7:0]  m_peak_votes,
    output reg  [7:0]  m_peak_strength,
    input  wire        m_peak_ready,

    // ---- 状态 ----
    output reg  [15:0] o_vote_drop,       // 因忙丢弃的投票点计数（饱和）
    output wire        o_scan_start      // Exact accepted previous-frame scan event.
);

    // ------------------------------------------------------------
    // 参数派生
    // ------------------------------------------------------------
    localparam P_DLOG  = (P_DECIM <= 1) ? 0 : $clog2(P_DECIM);
    localparam P_DMASK = P_DECIM - 1;
    localparam P_XD    = (P_IMG_W + P_DECIM - 1) / P_DECIM;   // 480 @1080P
    localparam P_YD    = (P_IMG_H + P_DECIM - 1) / P_DECIM;   // 270 @1080P
    localparam P_DW    = $clog2(P_XD + P_YD + 1);             // 10
    localparam P_TB    = 64;                                  // θ 分档数
    localparam P_TW    = 7;                                   // 计数到 64
    localparam P_TIW   = 6;                                   // θ 索引位宽
    localparam P_RHO_W = P_DW + 2; // Signed rounding and offset calculations.
    localparam P_ACC_N = P_TB * P_RHO_BINS;                   // 73728
    localparam P_AW    = $clog2(P_ACC_N);                     // 17
    localparam P_RW    = $clog2(P_RHO_BINS + 8) - 1;

    localparam [P_RW:0] P_RHO_BINS_C = P_RHO_BINS;
    localparam [P_TW-1:0] P_TB_C = P_TB;

    // FSM
    localparam [1:0] S_CLEAR = 2'd0;
    localparam [1:0] S_SCAN  = 2'd1;
    localparam [1:0] S_VOTE  = 2'd2;

    assign s_axis_tready = m_axis_tready;
    wire en = m_axis_tready;

    // ------------------------------------------------------------
    // θ 查找表：{cos_q15, sin_q15}，theta_k = 45° + k*1.40625°
    // 由 tools/gen_lut.py 生成，勿手改
    // ------------------------------------------------------------
    function [31:0] theta_lut;
        input [5:0] k;
        begin
            case (k)
                6'd0 : theta_lut = { 16'sd23170, 16'sd23170}; //  45.0000 deg
                6'd1 : theta_lut = { 16'sd22595, 16'sd23732}; //  46.4062 deg
                6'd2 : theta_lut = { 16'sd22006, 16'sd24279}; //  47.8125 deg
                6'd3 : theta_lut = { 16'sd21403, 16'sd24812}; //  49.2188 deg
                6'd4 : theta_lut = { 16'sd20788, 16'sd25330}; //  50.6250 deg
                6'd5 : theta_lut = { 16'sd20160, 16'sd25833}; //  52.0312 deg
                6'd6 : theta_lut = { 16'sd19520, 16'sd26320}; //  53.4375 deg
                6'd7 : theta_lut = { 16'sd18868, 16'sd26791}; //  54.8438 deg
                6'd8 : theta_lut = { 16'sd18205, 16'sd27246}; //  56.2500 deg
                6'd9 : theta_lut = { 16'sd17531, 16'sd27684}; //  57.6562 deg
                6'd10: theta_lut = { 16'sd16846, 16'sd28106}; //  59.0625 deg
                6'd11: theta_lut = { 16'sd16151, 16'sd28511}; //  60.4688 deg
                6'd12: theta_lut = { 16'sd15447, 16'sd28899}; //  61.8750 deg
                6'd13: theta_lut = { 16'sd14733, 16'sd29269}; //  63.2812 deg
                6'd14: theta_lut = { 16'sd14010, 16'sd29622}; //  64.6875 deg
                6'd15: theta_lut = { 16'sd13279, 16'sd29957}; //  66.0938 deg
                6'd16: theta_lut = { 16'sd12540, 16'sd30274}; //  67.5000 deg
                6'd17: theta_lut = { 16'sd11793, 16'sd30572}; //  68.9062 deg
                6'd18: theta_lut = { 16'sd11039, 16'sd30853}; //  70.3125 deg
                6'd19: theta_lut = { 16'sd10279, 16'sd31114}; //  71.7188 deg
                6'd20: theta_lut = { 16'sd 9512, 16'sd31357}; //  73.1250 deg
                6'd21: theta_lut = { 16'sd 8740, 16'sd31581}; //  74.5312 deg
                6'd22: theta_lut = { 16'sd 7962, 16'sd31786}; //  75.9375 deg
                6'd23: theta_lut = { 16'sd 7180, 16'sd31972}; //  77.3438 deg
                6'd24: theta_lut = { 16'sd 6393, 16'sd32138}; //  78.7500 deg
                6'd25: theta_lut = { 16'sd 5602, 16'sd32286}; //  80.1562 deg
                6'd26: theta_lut = { 16'sd 4808, 16'sd32413}; //  81.5625 deg
                6'd27: theta_lut = { 16'sd 4011, 16'sd32522}; //  82.9688 deg
                6'd28: theta_lut = { 16'sd 3212, 16'sd32610}; //  84.3750 deg
                6'd29: theta_lut = { 16'sd 2411, 16'sd32679}; //  85.7812 deg
                6'd30: theta_lut = { 16'sd 1608, 16'sd32729}; //  87.1875 deg
                6'd31: theta_lut = { 16'sd  804, 16'sd32758}; //  88.5938 deg
                6'd32: theta_lut = { 16'sd    0, 16'sd32767}; //  90.0000 deg
                6'd33: theta_lut = {-16'sd  804, 16'sd32758}; //  91.4062 deg
                6'd34: theta_lut = {-16'sd 1608, 16'sd32729}; //  92.8125 deg
                6'd35: theta_lut = {-16'sd 2411, 16'sd32679}; //  94.2188 deg
                6'd36: theta_lut = {-16'sd 3212, 16'sd32610}; //  95.6250 deg
                6'd37: theta_lut = {-16'sd 4011, 16'sd32522}; //  97.0312 deg
                6'd38: theta_lut = {-16'sd 4808, 16'sd32413}; //  98.4375 deg
                6'd39: theta_lut = {-16'sd 5602, 16'sd32286}; //  99.8438 deg
                6'd40: theta_lut = {-16'sd 6393, 16'sd32138}; // 101.2500 deg
                6'd41: theta_lut = {-16'sd 7180, 16'sd31972}; // 102.6562 deg
                6'd42: theta_lut = {-16'sd 7962, 16'sd31786}; // 104.0625 deg
                6'd43: theta_lut = {-16'sd 8740, 16'sd31581}; // 105.4688 deg
                6'd44: theta_lut = {-16'sd 9512, 16'sd31357}; // 106.8750 deg
                6'd45: theta_lut = {-16'sd10279, 16'sd31114}; // 108.2812 deg
                6'd46: theta_lut = {-16'sd11039, 16'sd30853}; // 109.6875 deg
                6'd47: theta_lut = {-16'sd11793, 16'sd30572}; // 111.0938 deg
                6'd48: theta_lut = {-16'sd12540, 16'sd30274}; // 112.5000 deg
                6'd49: theta_lut = {-16'sd13279, 16'sd29957}; // 113.9062 deg
                6'd50: theta_lut = {-16'sd14010, 16'sd29622}; // 115.3125 deg
                6'd51: theta_lut = {-16'sd14733, 16'sd29269}; // 116.7188 deg
                6'd52: theta_lut = {-16'sd15447, 16'sd28899}; // 118.1250 deg
                6'd53: theta_lut = {-16'sd16151, 16'sd28511}; // 119.5312 deg
                6'd54: theta_lut = {-16'sd16846, 16'sd28106}; // 120.9375 deg
                6'd55: theta_lut = {-16'sd17531, 16'sd27684}; // 122.3438 deg
                6'd56: theta_lut = {-16'sd18205, 16'sd27246}; // 123.7500 deg
                6'd57: theta_lut = {-16'sd18868, 16'sd26791}; // 125.1562 deg
                6'd58: theta_lut = {-16'sd19520, 16'sd26320}; // 126.5625 deg
                6'd59: theta_lut = {-16'sd20160, 16'sd25833}; // 127.9688 deg
                6'd60: theta_lut = {-16'sd20788, 16'sd25330}; // 129.3750 deg
                6'd61: theta_lut = {-16'sd21403, 16'sd24812}; // 130.7812 deg
                6'd62: theta_lut = {-16'sd22006, 16'sd24279}; // 132.1875 deg
                default: theta_lut = {-16'sd22595, 16'sd23732}; // 133.5938 deg
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // 累加器 RAM（简单双口：1 写口 + 1 读口，读优先）
    // ------------------------------------------------------------
    reg [7:0] mem [0:P_ACC_N-1];

    reg             wr_en;
    reg  [P_AW-1:0] wr_addr;
    reg  [7:0]      wr_data;
    reg  [P_AW-1:0] rd_addr;
    reg  [7:0]      rd_data;

    // LINT-EXCEPTION: 累加器 BRAM 推断块不打复位（读寄存器由状态机门控，
    //   全阵列清零由 S_CLEAR 状态机显式完成，比复位脚更省资源）
    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end

    // ------------------------------------------------------------
    // 投票引擎
    // ------------------------------------------------------------
    reg [P_DW-1:0] xd_r /* synthesis syn_preserve = 1 */;
    reg [P_DW-1:0] yd_r /* synthesis syn_preserve = 1 */;
    reg [P_TW-1:0] vk;             // 0..64
    reg [1:0]      vph;            // 0=发读地址 1=等RAM输出 2=写回
    reg [1:0]      vote_warmup;
    reg            burst;
    reg            vote_addr_v;
    reg [P_AW-1:0] vote_addr_r;
    reg [1:0] state;

    wire [P_DW-1:0] xd_w = s_axis_tx >> P_DLOG;
    wire [P_DW-1:0] yd_w = s_axis_ty >> P_DLOG;

    // ★ 降采样策略：**只按行降采样**（y % DECIM == 0），行内对
    //   "每个降采样列只投 1 票"（按 x>>log2(DECIM) 去重）。
    //   若同时对 x 也做 %DECIM 过滤，1 像素宽的 Canny 细线会被再砍掉 3/4
    //   的票（细线每行只有 1~2 个边缘点），实测会导致峰值淹没在噪声里。
    //   本策略票数提高 4 倍，而 ρ 的取值范围与累加器容量完全不变。
    reg [P_DW-1:0] xd_prev;
    wire col_new = ((s_axis_tx & P_DMASK) == 0) || (xd_w != xd_prev);
    wire dec_hit = ((s_axis_ty & P_DMASK) == 0);
    wire edge_dec = en & s_axis_tvalid & s_axis_tdata & dec_hit;
    wire vote_req = edge_dec & col_new;

    // rho = (x*cos + y*sin) >> 15 —— 2 个 DSP 乘法器
    // 注意：Verilog-2001 不允许直接对函数返回值做位选，必须先落到 wire
    // The first register maps to a synchronous ROM. A second preserved FF
    // cuts its physical tCO/route from the APM input setup path. Look ahead
    // two theta at phase2, otherwise one, so the added stage does not change
    // two warmup + 64*3 busy clocks. Theta63 always preloads theta0: even the
    // nearest next point (only one idle acceptance clock) sees coefficient0.
    wire [P_TIW-1:0] calc_theta = !burst ? 6'd0 :
        ((vote_warmup == 0 && vph == 2'd2 && vk != 7'd63) ?
            vk[P_TIW-1:0] + 6'd2 : vk[P_TIW-1:0] + 6'd1);
    reg [31:0] lut_q;
    reg [31:0] coeff_q /* synthesis syn_preserve = 1 */;
    wire signed [15:0]      lut_cos = coeff_q[31:16];
    wire signed [15:0]      lut_sin = coeff_q[15:0];
    reg signed [P_DW+16:0] p_x_q, p_y_q;
    reg signed [P_DW+17:0] p_sum_q /* synthesis syn_preserve = 1 */;
    // Keep registered DSP products, but put their next-cycle sum in fabric.
    // A fused CPO->CPI MAC uses a zero-route dedicated connection whose hold
    // margin cannot be repaired by adding ordinary route delay. Two kept
    // limbs preserve exact full-width two's-complement addition without an
    // extra clock or a combinational multiplier-to-external-FF stage.
    localparam P_SUM_W=P_DW+18;
    localparam P_SUM_LOW=P_SUM_W/2;
    localparam P_SUM_HIGH=P_SUM_W-P_SUM_LOW;
    wire [P_SUM_W-1:0] product_x_ext={p_x_q[P_DW+16],p_x_q};
    wire [P_SUM_W-1:0] product_y_ext={p_y_q[P_DW+16],p_y_q};
    wire [P_SUM_LOW:0] sum_low /* synthesis syn_keep = 1 */;
    wire [P_SUM_HIGH:0] sum_high /* synthesis syn_keep = 1 */;
    assign sum_low={1'b0,product_x_ext[P_SUM_LOW-1:0]}+
                   {1'b0,product_y_ext[P_SUM_LOW-1:0]};
    assign sum_high={1'b0,product_x_ext[P_SUM_W-1:P_SUM_LOW]}+
                    {1'b0,product_y_ext[P_SUM_W-1:P_SUM_LOW]}+sum_low[P_SUM_LOW];
    always @(posedge clk) begin
        lut_q <= theta_lut(calc_theta);
        coeff_q <= lut_q;
        p_x_q <= $signed({1'b0, xd_r}) * lut_cos;
        p_y_q <= $signed({1'b0, yd_r}) * lut_sin;
        p_sum_q <= {sum_high[P_SUM_HIGH-1:0],sum_low[P_SUM_LOW-1:0]};
    end
    // ★ 四舍五入到最近整数（先加 0.5 LSB 再算术右移），使 rho 的量化误差
    //   由"最大 1 个降采样单位"减半，提升峰值集中度
    wire signed [P_DW+17:0] p_rnd   = p_sum_q + 16384;
    wire signed [P_RHO_W-1:0] rho   = p_rnd >>> 15;

    localparam P_RIW = P_RHO_W + 2;
    localparam [P_AW-1:0] P_ACC_N_C = P_ACC_N;

    // theta 属于 [45,135) => |rho| <= 0.708*(XD+YD) < P_RHO_OFF，
    // 因此 rho_idx 必落在 [0, P_RHO_BINS)。
    // ★ 必须在**加宽后的有符号域**里做符号判断：rho 本身只有 P_RHO_W 位，
    //   加上偏置 576 后会溢出其有符号范围（1080P 时 530+576=1106 > 1023），
    //   直接取 rho_idx 的符号位会误判为无效。
    wire signed [P_RIW-1:0] rho_s   = {{(P_RIW-P_RHO_W){rho[P_RHO_W-1]}}, rho};
    wire signed [P_RIW-1:0] rho_idx = rho_s + P_RHO_OFF;
    wire                    rho_ok  = (~rho_idx[P_RIW-1]) && (rho_idx < P_RHO_BINS);
    wire [P_RIW-1:0]        rho_use = rho_idx;

    wire [P_AW-1:0] th_base   = vk * P_RHO_BINS;
    wire [P_AW-1:0] vote_addr = th_base
                              + {{(P_AW-P_RIW){1'b0}}, rho_use};

    // ------------------------------------------------------------
    // 峰值扫描（全流水，1 拍/rho）
    // ------------------------------------------------------------
    reg [P_AW-1:0]  clr_cnt;
    reg [P_TIW-1:0] sc_th;
    reg [P_RW:0]    sc_rh;         // 0..BINS-1 发读；BINS..BINS+3 流水排空；
                                   // BINS+4 拉起 valid；>=BINS+5 等 ready（封顶）
    reg             sc_v_d;        // 读在途（滞后发址 1 拍）
    reg             sc_v_d2;       // ★ rd_data 本拍有效（滞后发址 2 拍）
    reg             sc_v_d3;       // 排空拍 1（虚拟 bin=BINS，数据按 0 入窗）
    reg             sc_v_d4;       // 排空拍 2（虚拟 bin=BINS+1）
    // ---- P0：±2 bin 滑窗票数和（5 抽头移位链 + 滚动和）----
    // 窗口"以入窗 bin r 结尾、中心 = r-2"，等价于对每个中心 c 求
    // votes[c-2..c+2] 之和；真 θ 处票集中（窗和≈全部票），噪声 θ 处
    // 分散（窗和小）→ 天然分离（见 reports/sim_lane_detect.md §4.3 P0）。
    reg [7:0]       w_s1, w_s2, w_s3, w_s4;   // data(r-1)..data(r-4)
    reg [10:0]      win_sum;       // w_s1+w_s2+w_s3+w_s4（滚动维护）
    reg [10:0]      best_win;      // Selected centre's supporting window sum.
    reg [7:0]       best_strength;
    reg [P_RW:0]    best_rho;      // 最大窗口和的中心 bin
    reg [P_RW:0]    sc_rh_d;       // sc_rh 延 1 拍
    reg [P_RW:0]    sc_rh_d2;      // sc_rh 延 2 拍 = rd_data 对应的 bin（虚拟 bin 可到 BINS+1）

    // Register the physical BRAM output before window arithmetic. The matching
    // valid/bin includes two zero-tail tokens for the final two window centres.
    reg [7:0] scan_data_q;
    reg scan_data_valid_q;
    reg [P_RW:0] scan_bin_q;
    wire scan_read_valid = sc_v_d2 | sc_v_d3 | sc_v_d4;
    wire        upd  = scan_data_valid_q;
    wire [7:0]  w_in = scan_data_q;
    wire [10:0] win_now  = win_sum + {3'b0, w_in};
    wire [P_RW:0] w_ctr  = (scan_bin_q >= 2) ? (scan_bin_q - 2) : {(P_RW+1){1'b0}};
    reg score_valid_q;
    reg [10:0] score_sum_q;
    reg [7:0] score_strength_q;
    reg [P_RW:0] score_rho_q;
    wire [7:0]  votes_sat = (best_win > 11'd255) ? 8'hFF : best_win[7:0];

    wire [P_AW-1:0] sc_base   = sc_th * P_RHO_BINS;
    wire [P_AW-1:0] scan_addr = sc_base
                              + {{(P_AW-(P_RW+1)){1'b0}}, sc_rh};

    reg       sof_d;
    assign o_scan_start = (state == S_VOTE) && sof_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_CLEAR;
            clr_cnt      <= {P_AW{1'b0}};
            sc_th        <= {P_TIW{1'b0}};
            sc_rh        <= {(P_RW+1){1'b0}};
            sc_rh_d      <= {(P_RW+1){1'b0}};
            sc_rh_d2     <= {(P_RW+1){1'b0}};
            sc_v_d       <= 1'b0;
            sc_v_d2      <= 1'b0;
            sc_v_d3      <= 1'b0;
            sc_v_d4      <= 1'b0;
            w_s1         <= 8'd0;
            w_s2         <= 8'd0;
            w_s3         <= 8'd0;
            w_s4         <= 8'd0;
            win_sum      <= 11'd0;
            best_win     <= 11'd0;
            best_strength <= 8'd0;
            scan_data_q <= 8'd0;
            scan_data_valid_q <= 1'b0;
            scan_bin_q <= 0;
            score_valid_q <= 1'b0;
            score_sum_q <= 0;
            score_strength_q <= 0;
            score_rho_q <= 0;
            best_rho     <= {(P_RW+1){1'b0}};
            wr_en        <= 1'b0;
            wr_addr      <= {P_AW{1'b0}};
            wr_data      <= 8'd0;
            rd_addr      <= {P_AW{1'b0}};
            m_peak_valid <= 1'b0;
            m_peak_theta <= 6'd0;
            m_peak_rho   <= {P_RW{1'b0}};
            m_peak_votes <= 8'd0;
            m_peak_strength <= 8'd0;
            o_vote_drop  <= 16'd0;
            xd_r         <= {P_DW{1'b0}};
            yd_r         <= {P_DW{1'b0}};
            vk           <= {P_TW{1'b0}};
            vph          <= 2'd0;
            vote_warmup  <= 2'd0;
            burst        <= 1'b0;
            vote_addr_v  <= 1'b0;
            vote_addr_r  <= {P_AW{1'b0}};
            xd_prev      <= {P_DW{1'b0}};
            sof_d        <= 1'b0;
        end else begin
            sof_d <= en & s_axis_tvalid & s_axis_tuser;
            wr_en <= 1'b0;
            scan_data_valid_q <= (state == S_SCAN) && scan_read_valid;
            scan_data_q <= sc_v_d2 ? rd_data : 8'd0;
            scan_bin_q <= sc_rh_d2;
            score_valid_q <= (state == S_SCAN) && upd;
            if (upd) begin
                score_sum_q <= win_now;
                score_strength_q <= w_s2;
                score_rho_q <= w_ctr;
            end

            case (state)
            // ---------------- 清零 ----------------
            S_CLEAR: begin
                wr_en   <= 1'b1;
                wr_addr <= clr_cnt[P_AW-1:0];
                wr_data <= 8'd0;
                if (clr_cnt == P_ACC_N_C - 1'b1) begin
                    clr_cnt <= {P_AW{1'b0}};
                    sc_th   <= {P_TIW{1'b0}};
                    sc_rh   <= {(P_RW+1){1'b0}};
                    sc_v_d  <= 1'b0;
                    state   <= S_VOTE;              // 清零完成 -> 开始投票
                end else begin
                    clr_cnt <= clr_cnt + 1'b1;
                end
            end
            // ---------------- 逐 theta 峰值扫描 ----------------
            // 流水标号：数据(bin n) 在发址后第 2 拍到达（RAM 输出寄存器），
            // 与 sc_rh_d2 同拍（★ 旧版用 sc_rh_d 差 1 拍，所有峰值 rho 虚高
            // 1 档且最后一档数据从未参与比较 —— 已修复）。
            // 0..BINS-1 issue reads; two zero tails complete the last centres.
            // Extra data/score FFs require two more drain clocks: BINS+6
            // publishes valid, >=BINS+7 waits ready with every field stable.
            S_SCAN: begin
                sc_rh_d  <= sc_rh;
                sc_rh_d2 <= sc_rh_d;
                sc_v_d2  <= sc_v_d;
                sc_v_d3  <= sc_v_d2;
                sc_v_d4  <= sc_v_d3;

                // P0：滑窗票数和。每个 upd 拍一个数据入窗（排空拍入 0），
                // win_now = 最近 5 个数据之和，中心 bin = sc_rh_d2 - 2。
                if (score_valid_q && score_sum_q >= P_MIN_WINDOW_VOTES &&
                    ((score_strength_q > best_strength) ||
                     (score_strength_q == best_strength && score_sum_q > best_win))) begin
                    best_strength <= score_strength_q;
                    best_win <= score_sum_q;
                    best_rho <= score_rho_q;
                end
                if (upd) begin
                    win_sum <= win_now - {3'b0, w_s4};
                    w_s4    <= w_s3;
                    w_s3    <= w_s2;
                    w_s2    <= w_s1;
                    w_s1    <= w_in;
                end

                if (sc_rh < P_RHO_BINS_C) begin
                    rd_addr <= scan_addr;
                    sc_v_d  <= 1'b1;
                    sc_rh   <= sc_rh + 1'b1;
                end else begin
                    sc_v_d <= 1'b0;
                    if (sc_rh < (P_RHO_BINS_C + 12'd6)) begin
                        sc_rh <= sc_rh + 1'b1;            // 排空/延迟拍
                    end else if (sc_rh == (P_RHO_BINS_C + 12'd6)) begin
                        m_peak_valid <= 1'b1;
                        m_peak_theta <= sc_th;
                        m_peak_rho   <= $signed({1'b0, best_rho}) - P_RHO_OFF;
                        m_peak_votes <= votes_sat;
                        m_peak_strength <= best_strength;
                        sc_rh        <= sc_rh + 1'b1;
                    end else begin
                        if (m_peak_ready) begin
                            m_peak_valid <= 1'b0;
                            sc_rh        <= {(P_RW+1){1'b0}};
                            // 换 θ：复位滑窗
                            w_s1     <= 8'd0;
                            w_s2     <= 8'd0;
                            w_s3     <= 8'd0;
                            w_s4     <= 8'd0;
                            win_sum  <= 11'd0;
                            best_win <= 11'd0;
                            best_strength <= 8'd0;
                            scan_data_valid_q <= 1'b0;
                            score_valid_q <= 1'b0;
                            if (sc_th == P_TB_C[P_TIW-1:0] - 1'b1) begin
                                sc_th <= {P_TIW{1'b0}};
                                state <= S_CLEAR;       // 扫描完 -> 清零，等下一帧投票
                            end else begin
                                sc_th <= sc_th + 1'b1;
                            end
                        end
                    end
                end
            end
            // ---------------- 投票 ----------------
            S_VOTE: begin
                if (edge_dec)
                    xd_prev <= xd_w;            // 行内去重游标

                // 2 warm-up clocks + 3-phase RMW (192 clocks for 64 theta).
                //   RAM 输出寄存器滞后地址 1 拍，若 2 相写回会用到上一拍
                //   的陈旧 rd_data（实测把票数写成 1..64 斜坡，累加完全失效，
                //   见 reports/hough_fix_20260923.md）。相 1 空转一拍等数据。
                if (!burst) begin
                    if (vote_req) begin
                        xd_r  <= xd_w;
                        yd_r  <= yd_w;
                        vk    <= {P_TW{1'b0}};
                        vph   <= 2'd0;
                        vote_warmup <= 2'd2;
                        burst <= 1'b1;
                    end
                end else if (vote_warmup != 0) begin
                    vote_warmup <= vote_warmup - 1'b1;
                end else begin
                    case (vph)
                    2'd0: begin                       // 发读地址
                        rd_addr     <= vote_addr;
                        vote_addr_v <= rho_ok;
                        vph         <= 2'd1;
                    end
                    2'd1: begin                       // 等 RAM 寄存输出
                        vote_addr_r <= rd_addr;
                        vph         <= 2'd2;
                    end
                    default: begin                    // 写回（rd_data 已就绪）
                        wr_en         <= vote_addr_v;
                        wr_addr       <= vote_addr_r;
                        wr_data       <= (rd_data == 8'hFF) ? 8'hFF : (rd_data + 8'd1);
                        vph           <= 2'd0;
                        // ★ vk 在相 2 才自增（旧版在相 0），故终止条件必须
                        //   是 63 而不是 64，否则会多投一拍 θ=0（vk=64 时
                        //   vote_addr 用 vk[5:0]=0）
                        if (vk == P_TB_C[P_TW-1:0] - 1'b1) begin
                            burst <= 1'b0;
                        end else begin
                            vk <= vk + 1'b1;
                        end
                    end
                    endcase
                end

                // 忙时丢弃判定：burst 覆盖全部 3×64 拍（含收尾相，burst
                // 在收尾拍仍为 1，次拍才清零），故只判 burst 即可
                if (vote_req && burst) begin
                    if (o_vote_drop != 16'hFFFF)
                        o_vote_drop <= o_vote_drop + 16'd1;
                end

                if (sof_d) begin
                    // 帧首：先扫描上一帧的累加结果，扫描完再清零
                    // ★ 必须中止在途 burst，否则扫描+清零结束回到 S_VOTE 后
                    //   会用陈旧的 vk/xd_r/yd_r 继续投出垃圾票
                    burst    <= 1'b0;
                    vph      <= 2'd0;
                    vote_warmup <= 2'd0;
                    state    <= S_SCAN;
                    sc_th    <= {P_TIW{1'b0}};
                    sc_rh    <= {(P_RW+1){1'b0}};
                    sc_rh_d  <= {(P_RW+1){1'b0}};
                    sc_rh_d2 <= {(P_RW+1){1'b0}};
                    sc_v_d   <= 1'b0;
                    sc_v_d2  <= 1'b0;
                    sc_v_d3  <= 1'b0;
                    sc_v_d4  <= 1'b0;
                    win_sum  <= 11'd0;
                    best_win <= 11'd0;
                    best_strength <= 8'd0;
                    scan_data_valid_q <= 1'b0;
                    score_valid_q <= 1'b0;
                    best_rho <= {(P_RW+1){1'b0}};
                    w_s1     <= 8'd0;
                    w_s2     <= 8'd0;
                    w_s3     <= 8'd0;
                    w_s4     <= 8'd0;
                    clr_cnt  <= {P_AW{1'b0}};
                end
            end
            default: state <= S_CLEAR;
            endcase
        end
    end

endmodule
