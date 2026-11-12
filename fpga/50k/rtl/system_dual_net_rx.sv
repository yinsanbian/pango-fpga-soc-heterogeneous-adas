`timescale 1ns/1ps
// Both MACs finish FCS/IP/UDP validation before any YTM1 video is streamed.
// FIFO resets assert together; release is local. ETH1 MAC/stream may reset
// separately on RX PLL loss, while FIFO pointers retain their shared session.
module system_dual_net_rx #(
    parameter [47:0] LOCAL_MAC0=48'h020000000050,
    parameter [47:0] LOCAL_MAC1=48'h020000000051,
    parameter [31:0] LOCAL_IP0=32'hc0a83214,
    parameter [31:0] LOCAL_IP1=32'h0a0a1402,
    parameter [15:0] LOCAL_PORT0=16'd5000,LOCAL_PORT1=16'd5000,
    parameter [15:0] CONTROL_PORT=16'd5002,
    parameter [3:0] CH_MASK0=4'h3,CH_MASK1=4'hc,
    parameter integer FIFO_ADDR_BITS=8
)(
    input wire net0_clk,net1_clk,core_clk,
    input wire net0_rst_n,net1_rst_n,core_rst_n,
    input wire net1_fifo_rst_n,
    input wire [7:0] gmii0_rxd,gmii1_rxd,
    input wire gmii0_rx_dv,gmii0_rx_er,gmii1_rx_dv,gmii1_rx_er,
    output wire beat_valid,input wire beat_ready,
    output wire [2:0] beat_source,output wire [18:0] beat_block,
    output wire [31:0] beat_frame,output wire [255:0] beat_data,
    output wire control_udp_start,control_udp_valid,
    output wire [7:0] control_udp_data,
    output wire control_udp_end,control_udp_error,
    output wire [10:0] control_udp_length,
    output wire [31:0] net0_rx_packets,net0_rx_rejected,
    output wire [31:0] net0_bad_header_count,net0_dropped_packet_count,
    output wire [31:0] net1_rx_packets,net1_rx_rejected,
    output wire [31:0] net1_bad_header_count,net1_dropped_packet_count,
    output wire [7:0] net0_last_reject_flags,net1_last_reject_flags,
    output wire [2:0] net0_debug_events,net1_debug_events,
    output wire [31:0] net0_debug_state,net1_debug_state,
    output wire [11:0] net0_debug_eof_length,net1_debug_eof_length,
    output wire [258:0] net1_debug_checksums
);
    wire start0,valid0,end0,error0,start1,valid1,end1,error1;
    wire [7:0] data0,data1;
    wire [10:0] length0,length1;
    wire [15:0] port0,port1;
    gmii_udp_rx #(.LOCAL_MAC(LOCAL_MAC0),.LOCAL_IP(LOCAL_IP0),
        .LOCAL_PORT(LOCAL_PORT0),.CONTROL_PORT(CONTROL_PORT)) u_mac0(
        .clk(net0_clk),.rst_n(net0_rst_n),.gmii_rxd(gmii0_rxd),
        .gmii_rx_dv(gmii0_rx_dv),.gmii_rx_er(gmii0_rx_er),
        .udp_start(start0),.udp_valid(valid0),.udp_data(data0),
        .udp_end(end0),.udp_error(error0),.udp_payload_length(length0),
        .udp_destination_port(port0),.rx_packets(net0_rx_packets),.rx_rejected(net0_rx_rejected),
        .last_reject_flags(net0_last_reject_flags),.debug_events(net0_debug_events),
        .debug_state(net0_debug_state),.debug_eof_length(net0_debug_eof_length));
    gmii_udp_rx #(.LOCAL_MAC(LOCAL_MAC1),.LOCAL_IP(LOCAL_IP1),
        .LOCAL_PORT(LOCAL_PORT1)) u_mac1(
        .clk(net1_clk),.rst_n(net1_rst_n),.gmii_rxd(gmii1_rxd),
        .gmii_rx_dv(gmii1_rx_dv),.gmii_rx_er(gmii1_rx_er),
        .udp_start(start1),.udp_valid(valid1),.udp_data(data1),
        .udp_end(end1),.udp_error(error1),.udp_payload_length(length1),
        .udp_destination_port(port1),.rx_packets(net1_rx_packets),.rx_rejected(net1_rx_rejected),
        .last_reject_flags(net1_last_reject_flags),.debug_events(net1_debug_events),
        .debug_state(net1_debug_state),.debug_eof_length(net1_debug_eof_length),
        .debug_checksums(net1_debug_checksums));
    assign control_udp_start=start0 && port0==CONTROL_PORT;
    assign control_udp_valid=valid0 && port0==CONTROL_PORT;
    assign control_udp_data=data0;
    assign control_udp_end=end0 && port0==CONTROL_PORT;
    assign control_udp_error=error0;
    assign control_udp_length=length0;
    wire v0,v1,ready0,ready1;
    wire [2:0] source0,source1;
    wire [18:0] block0,block1;
    wire [31:0] frame0,frame1;
    wire [255:0] pixels0,pixels1;
    udp_video_stream_rx #(.CHANNEL_MASK(CH_MASK0)) u_video0(
        .clk(net0_clk),.rst_n(net0_rst_n),.udp_start(start0 && port0==LOCAL_PORT0),
        .udp_valid(valid0 && port0==LOCAL_PORT0),.udp_data(data0),
        .udp_end(end0 && port0==LOCAL_PORT0),.udp_error(error0),.udp_payload_length(length0),
        .beat_valid(v0),.beat_ready(ready0),.beat_source(source0),.beat_block(block0),
        .beat_frame(frame0),.beat_data(pixels0),.bad_header_count(net0_bad_header_count),
        .dropped_packet_count(net0_dropped_packet_count));
    udp_video_stream_rx #(.CHANNEL_MASK(CH_MASK1)) u_video1(
        .clk(net1_clk),.rst_n(net1_rst_n),.udp_start(start1 && port1==LOCAL_PORT1),
        .udp_valid(valid1 && port1==LOCAL_PORT1),.udp_data(data1),
        .udp_end(end1 && port1==LOCAL_PORT1),.udp_error(error1),.udp_payload_length(length1),
        .beat_valid(v1),.beat_ready(ready1),.beat_source(source1),.beat_block(block1),
        .beat_frame(frame1),.beat_data(pixels1),.bad_header_count(net1_bad_header_count),
        .dropped_packet_count(net1_dropped_packet_count));
    wire qvalid0,qvalid1,qready0,qready1;
    wire [309:0] qdata0,qdata1;
    video_async_fifo #(.WIDTH(310),.ADDR_BITS(FIFO_ADDR_BITS)) u_fifo0(
        .wr_clk(net0_clk),.wr_rst_n(net0_rst_n),.wr_valid(v0),.wr_ready(ready0),
        .wr_data({source0,block0,frame0,pixels0}),
        .rd_clk(core_clk),.rd_rst_n(core_rst_n),.rd_valid(qvalid0),.rd_ready(qready0),.rd_data(qdata0));
    video_async_fifo #(.WIDTH(310),.ADDR_BITS(FIFO_ADDR_BITS)) u_fifo1(
        .wr_clk(net1_clk),.wr_rst_n(net1_fifo_rst_n),.wr_valid(v1),.wr_ready(ready1),
        .wr_data({source1,block1,frame1,pixels1}),
        .rd_clk(core_clk),.rd_rst_n(core_rst_n),.rd_valid(qvalid1),.rd_ready(qready1),.rd_data(qdata1));
    reg round_robin,locked,held_select;
    wire selected=locked ? held_select : (!qvalid0 ? 1'b1 : (!qvalid1 ? 1'b0 : round_robin));
    assign beat_valid=core_rst_n && (selected ? qvalid1 : qvalid0);
    assign {beat_source,beat_block,beat_frame,beat_data}=selected ? qdata1 : qdata0;
    assign qready0=core_rst_n && beat_ready && !selected;
    assign qready1=core_rst_n && beat_ready && selected;
    always @(posedge core_clk or negedge core_rst_n) begin
        if(!core_rst_n) begin round_robin<=0;locked<=0;held_select<=0;end
        else if(beat_valid && beat_ready) begin round_robin<=!selected;locked<=0;end
        else if(beat_valid && !locked) begin locked<=1;held_select<=selected;end
    end
endmodule
