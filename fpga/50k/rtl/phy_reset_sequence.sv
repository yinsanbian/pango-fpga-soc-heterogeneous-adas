`timescale 1ns/1ps
// PHY-only reset hold, independent of DDR/video reset and PLL output clocks.
// At the board's 50MHz reference, 1,000,000 cycles give nominal 20ms LOW,
// exceeding RTL8211E Rev1.7 section7.16's 10ms minimum. MDIO has its own
// post-release 1s settling wait. No GRS/initial value or fabric clock is used.
module phy_reset_sequence #(
    parameter integer P_HOLD_CYCLES = 1000000
)(
    input wire clk50,
    input wire request_n,
    output reg phy_reset_n
);
    localparam integer CW=P_HOLD_CYCLES<2 ? 1 : $clog2(P_HOLD_CYCLES);
    localparam [CW-1:0] LAST_COUNT=P_HOLD_CYCLES-1;
    wire hold_rstn;
    // Asynchronous request assertion is captured even if clk50 is stopped.
    // Only this existing two-FF template synchronously releases local reset;
    // there is no additional single-FF reset-distribution branch.
    reset_sync u_hold_rst(.clk(clk50),.async_n(request_n),.rst_n(hold_rstn));
    reg [CW-1:0] hold_count;
    always @(posedge clk50 or negedge hold_rstn) begin
        if (!hold_rstn) begin
            hold_count<=0;
            phy_reset_n<=0;
        end else if (!phy_reset_n) begin
            if (hold_count==LAST_COUNT) phy_reset_n<=1;
            else hold_count<=hold_count+1'b1;
        end
    end
endmodule
