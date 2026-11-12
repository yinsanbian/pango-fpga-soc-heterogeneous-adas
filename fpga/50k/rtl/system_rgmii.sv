`timescale 1ns/1ps
// GMII TX has an independent 125MHz domain; PHY RXC cannot stall TX.
// Forwarded TXC lags TXD by 2ns at the PLL outputs. PHY TXDLY must be OFF;
// actual package/PCB skew and PHY variant remain separate board signoff.
module system_rgmii #(
    parameter integer P_RX_GLOBAL=0,
    parameter integer P_RX_EXTERNAL=0,
    parameter integer P_RX_DELAY_STEP=0
)(
    input wire rx_rst,tx_rst,tx_clock_rst,tx_clk,tx_clk90,rx_sample_clk,
    input wire mac_tx_data_valid,mac_tx_error,
    input wire [7:0] mac_tx_data,
    output wire rgmii_clk,
    output reg mac_rx_error,mac_rx_data_valid,
    output reg [7:0] mac_rx_data,
    input wire rgmii_rxc,rgmii_rx_ctl,
    input wire [3:0] rgmii_rxd,
    output wire rgmii_txc,rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);
    wire [3:0] txd_do,txd_tq;
    genvar i;
    generate for(i=0;i<4;i=i+1) begin:g_tx
        GTP_OSERDES #(.OSERDES_MODE("ODDR"),.WL_EXTEND("FALSE"),
            .GRS_EN("TRUE"),.LRS_EN("TRUE"),.TSDDR_INIT(1'b0)) u_ddr(
            .DO(txd_do[i]),.TQ(txd_tq[i]),
            .DI({6'd0,mac_tx_data[i+4],mac_tx_data[i]}),.TI(4'd0),
            .RCLK(tx_clk),.SERCLK(tx_clk),.OCLK(1'b0),.RST(tx_rst));
        GTP_OUTBUFT u_out(.I(txd_do[i]),.T(txd_tq[i]),.O(rgmii_txd[i]));
    end endgenerate
    wire txctl_do,txctl_tq,txc_do,txc_tq;
    GTP_OSERDES #(.OSERDES_MODE("ODDR"),.WL_EXTEND("FALSE"),
        .GRS_EN("TRUE"),.LRS_EN("TRUE"),.TSDDR_INIT(1'b0)) u_tx_ctl(
        .DO(txctl_do),.TQ(txctl_tq),
        .DI({6'd0,mac_tx_data_valid^mac_tx_error,mac_tx_data_valid}),.TI(4'd0),
        .RCLK(tx_clk),.SERCLK(tx_clk),.OCLK(1'b0),.RST(tx_rst));
    GTP_OUTBUFT u_tx_ctl_out(.I(txctl_do),.T(txctl_tq),.O(rgmii_tx_ctl));
    GTP_OSERDES #(.OSERDES_MODE("ODDR"),.WL_EXTEND("FALSE"),
        .GRS_EN("TRUE"),.LRS_EN("TRUE"),.TSDDR_INIT(1'b0)) u_tx_clock(
        .DO(txc_do),.TQ(txc_tq),.DI(8'b00000001),.TI(4'd0),
        .RCLK(tx_clk90),.SERCLK(tx_clk90),.OCLK(1'b0),.RST(tx_clock_rst));
    GTP_OUTBUFT u_tx_clock_out(.I(txc_do),.T(txc_tq),.O(rgmii_txc));

    // Ethernet1's fixed pads cannot share a single regional clock footprint
    // with all RX loaders (observed Place-0086). Give that entire RX domain a
    // global clock; Ethernet2 retains the qualified regional implementation.
    generate if(P_RX_EXTERNAL) begin:g_external_rx
        assign rgmii_clk=rx_sample_clk;
    end else if(P_RX_GLOBAL) begin:g_global_rx
        GTP_CLKBUFG u_rx_clkbufg(.CLKIN(rgmii_rxc),.CLKOUT(rgmii_clk));
    end else begin:g_regional_rx
        GTP_CLKBUFR u_rx_clkbufr(.CLKIN(rgmii_rxc),.CLKOUT(rgmii_clk));
    end endgenerate
    wire rxctl_i;
    wire rxctl_pad;
    wire [3:0] rxd_i,rxd_pad;
    wire [7:0] gmii_rxd;
    wire gmii_ctl,gmii_ctl_xor_error;
    wire [5:0] unused_ctl;
    GTP_INBUF #(.IOSTANDARD("DEFAULT"),.TERM_DDR("ON")) u_rx_ctl_in(.I(rgmii_rx_ctl),.O(rxctl_pad));
    generate if(P_RX_DELAY_STEP!=0) begin:g_ctl_delay
        GTP_IODELAY #(.DELAY_DEPTH(4),.DELAY_STEP(P_RX_DELAY_STEP)) u_delay(
            .DI(rxctl_pad),.DO(rxctl_i),.LOAD_N(1'b0),.MOVE(1'b0),.DIRECTION(1'b0),.DELAY_OB());
    end else begin:g_ctl_direct
        assign rxctl_i=rxctl_pad;
    end endgenerate
    GTP_ISERDES #(.ISERDES_MODE("IDDR"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) u_rx_ctl(
        .DO({gmii_ctl_xor_error,gmii_ctl,unused_ctl}),.DI(rxctl_i),
        .RADDR(3'd0),.WADDR(3'd0),.DESCLK(rgmii_clk),.ICLK(1'b0),.RCLK(rgmii_clk),.RST(rx_rst));
    generate for(i=0;i<4;i=i+1) begin:g_rx
        wire [5:0] unused_data;
        GTP_INBUF #(.IOSTANDARD("DEFAULT"),.TERM_DDR("ON")) u_in(.I(rgmii_rxd[i]),.O(rxd_pad[i]));
        if(P_RX_DELAY_STEP!=0) begin:g_data_delay
            GTP_IODELAY #(.DELAY_DEPTH(4),.DELAY_STEP(P_RX_DELAY_STEP)) u_delay(
                .DI(rxd_pad[i]),.DO(rxd_i[i]),.LOAD_N(1'b0),.MOVE(1'b0),.DIRECTION(1'b0),.DELAY_OB());
        end else begin:g_data_direct
            assign rxd_i[i]=rxd_pad[i];
        end
        GTP_ISERDES #(.ISERDES_MODE("IDDR"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) u_ddr(
            .DO({gmii_rxd[i+4],gmii_rxd[i],unused_data}),.DI(rxd_i[i]),
            .RADDR(3'd0),.WADDR(3'd0),.DESCLK(rgmii_clk),.ICLK(1'b0),.RCLK(rgmii_clk),.RST(rx_rst));
    end endgenerate
    always @(posedge rgmii_clk) begin
        if(rx_rst) begin mac_rx_data<=0;mac_rx_data_valid<=0;mac_rx_error<=0;end
        else begin mac_rx_data<=gmii_rxd;mac_rx_data_valid<=gmii_ctl;mac_rx_error<=gmii_ctl^gmii_ctl_xor_error;end
    end
endmodule
