`timescale 1ns/1ps
// PGL50H uses the Logos GTP_PLL_E3 (UG020007 table 7-34).
// Official installed ipml_pll/createDivideParam.tcl: VCO 600..1250 MHz,
// PFD 5..320 MHz; UG021001 table 2-11 defines the integer divider formula.
// Pixel: 27 MHz * 33 / 6 = 148.5 MHz, VCO 891 MHz, PFD 27 MHz.
// Auxiliary: 50 MHz * 20 / 100 = 10 MHz; /40 = 25 MHz, VCO 1000 MHz.
module mosaic_pll (
    input  wire clkin1,
    input  wire clkin27,
    output wire clkout0,
    output wire clkout1,
    output wire clkout2,
    output wire net_tx_clk,
    output wire net_tx_clk90,
    output wire pll_lock
);
    wire pixel_lock, aux_lock;
    GTP_PLL_E3 #(
        .CLKIN_FREQ(27.0),
        .STATIC_RATIOI(1), .STATIC_RATIOM(1), .STATIC_RATIOF(33),
        .STATIC_RATIO0(6), .STATIC_RATIO1(16), .STATIC_RATIO2(16),
        .STATIC_RATIO3(16), .STATIC_RATIO4(16),
        .STATIC_DUTY0(6), .STATIC_DUTY1(16), .STATIC_DUTY2(16),
        .STATIC_DUTY3(16), .STATIC_DUTY4(16),
        .INTERNAL_FB("ENABLE"), .EXTERNAL_FB("DISABLE"),
        .BANDWIDTH("OPTIMIZED")
    ) u_pixel_pll (
        .CLKIN1(clkin27), .CLKIN2(1'b0), .CLKFB(1'b0),
        .CLKIN_SEL(1'b0), .CLKIN_SEL_EN(1'b0), .PFDEN(1'b1),
        .CLKOUT0(clkout0), .CLKOUT0_EXT(), .CLKOUT1(), .CLKOUT2(),
        .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKSWITCH_FLAG(),
        .LOCK(pixel_lock),
        .ICP_BASE(1'b0), .ICP_SEL(4'd0), .LPFRES_SEL(3'd0), .CRIPPLE_SEL(1'b0),
        .PHASE_SEL(3'd0), .PHASE_DIR(1'b0), .PHASE_STEP_N(1'b0), .LOAD_PHASE(1'b0),
        .RATIOI(10'd0), .RATIOM(7'd0), .RATIO0(10'd0), .RATIO1(10'd0),
        .RATIO2(10'd0), .RATIO3(10'd0), .RATIO4(10'd0), .RATIOF(10'd0),
        .DUTY0(10'd0), .DUTY1(10'd0), .DUTY2(10'd0), .DUTY3(10'd0), .DUTY4(10'd0),
        .CLKOUT0_SYN(1'b1), .CLKOUT0_EXT_SYN(1'b1), .CLKOUT1_SYN(1'b1),
        .CLKOUT2_SYN(1'b1), .CLKOUT3_SYN(1'b1), .CLKOUT4_SYN(1'b1), .CLKOUT5_SYN(1'b1),
        .PLL_PWD(1'b0), .RST(1'b0), .RSTODIV(1'b0)
    );
    system_network_clocks u_aux_clocks(.clkin50(clkin1),.rst(1'b0),
        .tx_clk(net_tx_clk),.tx_clk90(net_tx_clk90),.locked(aux_lock),
        .cfg_clk(clkout1),.clk_25M(clkout2));
    // Clock-domain reset releases must additionally be synchronized by the top.
    assign pll_lock = pixel_lock && aux_lock;
endmodule
