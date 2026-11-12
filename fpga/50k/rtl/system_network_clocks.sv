`timescale 1ns/1ps
// UG020007 E3: coarse phase is in VCO cycles (E3 has no IP GUI +2 offset).
// Shared auxiliary VCO: 10MHz,25MHz and two independent 125MHz outputs.
// 50MHz *20 /8 =125MHz, output3 lags output2 by 2ns.
// Each destination must synchronize reset release after this PLL locks.
module system_network_clocks(
    input wire clkin50,rst,
    output wire tx_clk,tx_clk90,locked,cfg_clk,clk_25M
);
    wire data_clock,shift_clock;
    GTP_PLL_E3 #(
        .CLKIN_FREQ(50.0),
        .STATIC_RATIOI(1),.STATIC_RATIOM(1),.STATIC_RATIOF(20),
        .STATIC_RATIO0(100),.STATIC_RATIO1(40),.STATIC_RATIO2(8),
        .STATIC_RATIO3(8),.STATIC_RATIO4(16),
        .STATIC_DUTY0(100),.STATIC_DUTY1(40),.STATIC_DUTY2(8),
        .STATIC_DUTY3(8),.STATIC_DUTY4(16),
        .STATIC_CPHASE2(0),.STATIC_CPHASE3(2),
        .INTERNAL_FB("ENABLE"),.EXTERNAL_FB("DISABLE"),
        .BANDWIDTH("HIGH")
    ) u_pll(
        .CLKIN1(clkin50),.CLKIN2(1'b0),.CLKFB(1'b0),
        .CLKIN_SEL(1'b0),.CLKIN_SEL_EN(1'b0),.PFDEN(1'b1),
        .CLKOUT0(cfg_clk),.CLKOUT0_EXT(),.CLKOUT1(clk_25M),
        .CLKOUT2(data_clock),.CLKOUT3(shift_clock),.CLKOUT4(),.CLKOUT5(),.CLKSWITCH_FLAG(),
        .LOCK(locked),
        .ICP_BASE(1'b0),.ICP_SEL(4'd0),.LPFRES_SEL(3'd0),.CRIPPLE_SEL(1'b0),
        .PHASE_SEL(3'd0),.PHASE_DIR(1'b0),.PHASE_STEP_N(1'b0),.LOAD_PHASE(1'b0),
        .RATIOI(10'd0),.RATIOM(7'd0),.RATIO0(10'd0),.RATIO1(10'd0),
        .RATIO2(10'd0),.RATIO3(10'd0),.RATIO4(10'd0),.RATIOF(10'd0),
        .DUTY0(10'd0),.DUTY1(10'd0),.DUTY2(10'd0),.DUTY3(10'd0),.DUTY4(10'd0),
        .CLKOUT0_SYN(1'b1),.CLKOUT0_EXT_SYN(1'b1),.CLKOUT1_SYN(1'b1),
        .CLKOUT2_SYN(1'b1),.CLKOUT3_SYN(1'b1),.CLKOUT4_SYN(1'b1),.CLKOUT5_SYN(1'b1),
        .PLL_PWD(1'b0),.RST(rst),.RSTODIV(1'b0)
    );
    GTP_CLKBUFG u_data_buf(.CLKIN(data_clock),.CLKOUT(tx_clk));
    GTP_CLKBUFG u_shift_buf(.CLKIN(shift_clock),.CLKOUT(tx_clk90));
endmodule

// External-feedback RX clock recovery: OUT1 +1ns at the PLL. The pad/tree
// residual and both-corner capture aperture are checked by actual STA.
// The feedback output stays ungated.
// Loss of reference resets only the packet decoder, not either FIFO pointer.
module system_receive_clocks #(
    // Sample-clock phase relative to the recovered RXC edge.
    // STATIC_CPHASE is in whole VCO cycles (1 ns at VCO=1000 MHz),
    // STATIC_PHASE is the fine phase inside a VCO cycle (125 ps steps, 0..7).
    // The feedback output stays at CPHASE0=0 so only the sampling instant moves.
    parameter integer P_SAMPLE_CPHASE = 1,
    parameter integer P_SAMPLE_PHASE  = 0
)(
    input wire clkin50,rst,rxc,
    output wire sample_clk,locked,
    output wire pll_reset
);
    wire feedback_raw,feedback_clk,sample_raw;
    wire control_rst_n;
    reset_sync u_control_rst(.clk(clkin50),.async_n(!rst),.rst_n(control_rst_n));
    (* PAP_ASYNC_REG=1 *) reg [1:0] lock_sync;
    reg [1:0] state;
    reg [15:0] retry_count;
    always @(posedge clkin50 or negedge control_rst_n) begin
        if(!control_rst_n) lock_sync<=0;
        else lock_sync<={lock_sync[0],locked};
    end
    // 640ns reset; allow 1.31ms to acquire, retry after a missing source.
    always @(posedge clkin50 or negedge control_rst_n) begin
        if(!control_rst_n) begin state<=0;retry_count<=0;end
        else case(state)
            0: if(retry_count==31) begin state<=1;retry_count<=0;end
               else retry_count<=retry_count+1'b1;
            1: if(lock_sync[1]) begin state<=2;retry_count<=0;end
               else if(&retry_count) begin state<=0;retry_count<=0;end
               else retry_count<=retry_count+1'b1;
            2: if(!lock_sync[1]) begin state<=0;retry_count<=0;end
            default: begin state<=0;retry_count<=0;end
        endcase
    end
    assign pll_reset=!control_rst_n || state==0;
    GTP_PLL_E3 #(
        .CLKIN_FREQ(125.0),
        .STATIC_RATIOI(1),.STATIC_RATIOM(1),.STATIC_RATIOF(8),
        .STATIC_RATIO0(8),.STATIC_RATIO1(8),.STATIC_RATIO2(16),
        .STATIC_RATIO3(16),.STATIC_RATIO4(16),
        .STATIC_DUTY0(8),.STATIC_DUTY1(8),.STATIC_DUTY2(16),
        .STATIC_DUTY3(16),.STATIC_DUTY4(16),
        .STATIC_CPHASE0(0),.STATIC_CPHASE1(P_SAMPLE_CPHASE),
        .STATIC_PHASE0(0),.STATIC_PHASE1(P_SAMPLE_PHASE),
        .INTERNAL_FB("DISABLE"),.EXTERNAL_FB("CLKOUT0"),
        .BANDWIDTH("HIGH")
    ) u_pll(
        .CLKIN1(rxc),.CLKIN2(1'b0),.CLKFB(feedback_clk),
        .CLKIN_SEL(1'b0),.CLKIN_SEL_EN(1'b0),.PFDEN(1'b1),
        .CLKOUT0(feedback_raw),.CLKOUT0_EXT(),.CLKOUT1(sample_raw),
        .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKSWITCH_FLAG(),
        .LOCK(locked),
        .ICP_BASE(1'b0),.ICP_SEL(4'd0),.LPFRES_SEL(3'd0),.CRIPPLE_SEL(1'b0),
        .PHASE_SEL(3'd0),.PHASE_DIR(1'b0),.PHASE_STEP_N(1'b0),.LOAD_PHASE(1'b0),
        .RATIOI(10'd0),.RATIOM(7'd0),.RATIO0(10'd0),.RATIO1(10'd0),
        .RATIO2(10'd0),.RATIO3(10'd0),.RATIO4(10'd0),.RATIOF(10'd0),
        .DUTY0(10'd0),.DUTY1(10'd0),.DUTY2(10'd0),.DUTY3(10'd0),.DUTY4(10'd0),
        .CLKOUT0_SYN(1'b1),.CLKOUT0_EXT_SYN(1'b1),.CLKOUT1_SYN(1'b1),
        .CLKOUT2_SYN(1'b1),.CLKOUT3_SYN(1'b1),.CLKOUT4_SYN(1'b1),.CLKOUT5_SYN(1'b1),
        .PLL_PWD(1'b0),.RST(pll_reset),.RSTODIV(1'b0)
    );
    GTP_CLKBUFG u_feedback_buf(.CLKIN(feedback_raw),.CLKOUT(feedback_clk));
    GTP_CLKBUFGCE #(.DEFAULT_VALUE(1'b0),.SIM_DEVICE("LOGOS")) u_sample_buf(
        .CLKIN(sample_raw),.CE(locked),.CLKOUT(sample_clk));
endmodule
