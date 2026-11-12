`timescale 1ns/1ps
// Module : system_single_net_rx
// N1-only receive path for the N1-isolated diagnostic build. Derived from
// system_dual_net_rx by deleting the whole NET0 branch (MAC0, video0, FIFO0,
// port-0 control decode) and the two-way beat arbiter. With one source there is
// no round-robin, no held_select lock and no cross-port back-pressure: the beat
// stream is exactly FIFO1's output.
module system_single_net_rx #(
    parameter [47:0] LOCAL_MAC1=48'h020000000051,
    parameter [31:0] LOCAL_IP1=32'h0a0a1402,
    parameter [15:0] LOCAL_PORT1=16'd5000,
    parameter [3:0] CH_MASK1=4'hc,
    parameter integer FIFO_ADDR_BITS=8
)(
    input wire net1_clk,core_clk,
    input wire net1_rst_n,net1_fifo_rst_n,core_rst_n,
    input wire [7:0] gmii1_rxd,
    input wire gmii1_rx_dv,gmii1_rx_er,
    output wire beat_valid,input wire beat_ready,
    output wire [2:0] beat_source,output wire [18:0] beat_block,
    output wire [31:0] beat_frame,output wire [255:0] beat_data,
    output wire [31:0] net1_rx_packets,net1_rx_rejected,
    output wire [31:0] net1_bad_header_count,net1_dropped_packet_count,
    output wire [7:0] net1_last_reject_flags,
    output wire [2:0] net1_debug_events,
    output wire [31:0] net1_debug_state,
    output wire [11:0] net1_debug_eof_length,
    output wire [258:0] net1_debug_checksums,
    // Beat-producing count in the RX domain. Observation only.
    output reg [31:0] net1_beat_count
);
    wire start1,valid1,end1,error1;
    wire [7:0] data1;
    wire [10:0] length1;
    wire [15:0] port1;
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
    wire v1,ready1;
    wire [2:0] source1;
    wire [18:0] block1;
    wire [31:0] frame1;
    wire [255:0] pixels1;
    udp_video_stream_rx #(.CHANNEL_MASK(CH_MASK1)) u_video1(
        .clk(net1_clk),.rst_n(net1_rst_n),.udp_start(start1 && port1==LOCAL_PORT1),
        .udp_valid(valid1 && port1==LOCAL_PORT1),.udp_data(data1),
        .udp_end(end1 && port1==LOCAL_PORT1),.udp_error(error1),.udp_payload_length(length1),
        .beat_valid(v1),.beat_ready(ready1),.beat_source(source1),.beat_block(block1),
        .beat_frame(frame1),.beat_data(pixels1),.bad_header_count(net1_bad_header_count),
        .dropped_packet_count(net1_dropped_packet_count));
    wire qvalid1,qready1;
    wire [309:0] qdata1;
    video_async_fifo #(.WIDTH(310),.ADDR_BITS(FIFO_ADDR_BITS)) u_fifo1(
        .wr_clk(net1_clk),.wr_rst_n(net1_fifo_rst_n),.wr_valid(v1),.wr_ready(ready1),
        .wr_data({source1,block1,frame1,pixels1}),
        .rd_clk(core_clk),.rd_rst_n(core_rst_n),.rd_valid(qvalid1),.rd_ready(qready1),.rd_data(qdata1));
    // One source only: no arbiter state, no lock, no cross-port priority.
    assign beat_valid=core_rst_n && qvalid1;
    assign {beat_source,beat_block,beat_frame,beat_data}=qdata1;
    assign qready1=core_rst_n && beat_ready;
    always @(posedge net1_clk or negedge net1_fifo_rst_n) begin
        if(!net1_fifo_rst_n) net1_beat_count<=0;
        else if(v1) net1_beat_count<=net1_beat_count+1'b1;
    end
endmodule
