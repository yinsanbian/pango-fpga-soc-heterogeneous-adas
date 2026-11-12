// ============================================================
// Module : div_seq
// Target : ALG-09  (车道线检测 · 定点除法支撑)
// Desc   : 有符号顺序（恢复余数法）除法器  q = a / b
// LATENCY: P_W + 2 cycles（start 拉高后 busy 有效，done 单拍脉冲）
// Note   : 1) b == 0 时 q 饱和到 ±最大值 并置 err，不会挂死；
//          2) a == MIN 时 |a| 溢出，按饱和处理（本设计 a 远小于 MIN）；
//          3) 除法结果为"向零截断"，与 Python / Verilog `/` 语义一致，
//             便于与参考模型逐位对齐。
//          4) 每帧只调用 <10 次（lane_fit），面积优先，非流水实现。
// ============================================================
`timescale 1ns / 1ps

module div_seq #(
    parameter P_W = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,          // 单拍启动脉冲
    input  wire signed [P_W-1:0] a,              // 被除数
    input  wire signed [P_W-1:0] b,              // 除数
    output reg  signed [P_W-1:0] q,              // 商（向零截断）
    output reg                   done,           // 单拍完成脉冲
    output reg                   busy,
    output reg                   err             // 除零
);

    localparam P_CNT_W = (P_W <= 1) ? 1 : $clog2(P_W + 1);

    reg  [2*P_W-1:0]   sr;        // {余数[P_W], 商[P_W]} ★ 必须 2*P_W 位
    reg  [P_W-1:0]     dv;        // 除数绝对值
    reg                q_sign;
    reg                q_err;
    reg  [P_CNT_W-1:0] cnt;
    reg                run;

    // ---------- 组合：一次试减（恢复余数法的一步） ----------
    reg [2*P_W-1:0] sr_sh;
    reg [2*P_W-1:0] sr_nxt;
    always @(*) begin
        sr_sh  = {sr[2*P_W-2:0], 1'b0};                     // 左移一位，商位补 0
        sr_nxt = sr_sh;
        if (sr_sh[2*P_W-1:P_W] >= dv) begin                 // 够减：商位写 1
            sr_nxt[2*P_W-1:P_W] = sr_sh[2*P_W-1:P_W] - dv;
            sr_nxt[0]           = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr     <= {2*P_W{1'b0}};
            dv     <= {P_W{1'b0}};
            q      <= {P_W{1'b0}};
            q_sign <= 1'b0;
            q_err  <= 1'b0;
            cnt    <= {P_CNT_W{1'b0}};
            run    <= 1'b0;
            busy   <= 1'b0;
            done   <= 1'b0;
            err    <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !run) begin
                // 取绝对值（符号-幅值法）
                sr     <= {{P_W{1'b0}}, a[P_W-1] ? (~a + 1'b1) : a};
                dv     <=               b[P_W-1] ? (~b + 1'b1) : b;
                q_sign <= a[P_W-1] ^ b[P_W-1];
                q_err  <= (b == {P_W{1'b0}});
                cnt    <= P_W[P_CNT_W-1:0];
                run    <= 1'b1;
                busy   <= 1'b1;
                err    <= (b == {P_W{1'b0}});
            end else if (run) begin
                if (cnt == {P_CNT_W{1'b0}}) begin
                    run  <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    // 除零：饱和到最大正数；否则按符号还原（向零截断）
                    q    <= q_err ? {1'b0, {(P_W-1){1'b1}}}
                                  : (q_sign ? (~sr[P_W-1:0] + 1'b1) : sr[P_W-1:0]);
                end else begin
                    sr  <= sr_nxt;
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end

endmodule
