`timescale 1ns/1ps
// Frame snapshots and real detector results cross only in acknowledged bundles.
// HEALTH has one pending slot; LANE has four pixel slots plus four FF TX slots.
// Queue overflow is counted; a held event is never silently overwritten.
module system_metadata_bridge(
    input wire pix_clk,pix_rst_n,tx_clk,tx_rst_n,
    input wire first_active,
    input wire [31:0] frame_id,
    input wire [7:0] mode_id,
    input wire [15:0] calibration_id,
    input wire [7:0] context_epoch,
    input wire [5:0] context_valid,
    input wire [191:0] context_frames,
    input wire [3:0] result_pulse,result_tag_valid,result_left_valid,result_right_valid,
    input wire [127:0] result_frame_ids,result_source_frames,
    input wire [11:0] result_sources,
    input wire [7:0] result_mode,
    input wire [191:0] result_endpoints,
    output reg app_valid,
    input wire app_ready,
    output reg [7:0] app_length,
    output reg [1023:0] app_payload,
    output reg [31:0] pixel_drops,tx_drops
);
    reg [63:0] ticks;
    reg health_send,lane_send;
    wire health_ready,lane_ready,health_pulse,lane_pulse;
    reg [325:0] health_data;
    wire [325:0] health_received;
    reg [279:0] lane_data;
    wire [279:0] lane_received;
    reg [3:0] lane_pending;
    reg [279:0] lane_hold[0:3];
    reg [1:0] round_robin;
    reg found;
    reg [1:0] chosen;
    integer offset,slot;
    reg [159:0] event_payload;
    function automatic [15:0] sign16(input [11:0] value);
        sign16={{4{value[11]}},value};
    endfunction
    always @* begin
        found=0;chosen=round_robin;
        for(offset=0;offset<4;offset=offset+1) begin
            slot=(round_robin+offset)&3;
            if(!found && lane_pending[slot]) begin found=1;chosen=slot;end
        end
    end
    integer g;
    reg [3:0] drops_this_cycle;
    // Preview the selected slot every cycle. Registered lane_send makes the
    // mailbox capture this value on the following edge; its own held_data
    // then remains immutable until ACK. Invalid previews need no reset/CE.
    always @(posedge pix_clk) lane_data<=lane_hold[chosen];
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin
            ticks<=0;health_send<=0;lane_send<=0;health_data<=0;
            lane_pending<=0;round_robin<=0;pixel_drops<=0;
            for(g=0;g<4;g=g+1) lane_hold[g]<=0;
        end else begin
            ticks<=ticks+1'b1;health_send<=0;lane_send<=0;drops_this_cycle=0;
            // Registered send consumes ready on the following edge. Suppress
            // a second scheduling while the previous send is being accepted.
            if(first_active) begin
                if(health_ready && !health_send) begin
                    health_data<={frame_id,ticks,mode_id,calibration_id,context_epoch,
                        (context_epoch==frame_id[7:0] ? context_valid : 6'd0),context_frames};
                    health_send<=1;
                end else drops_this_cycle=drops_this_cycle+1'b1;
            end
            if(found && lane_ready && !lane_send) begin
                lane_send<=1;lane_pending[chosen]<=0;
                round_robin<=chosen+1'b1;
            end
            for(g=0;g<4;g=g+1) if(result_pulse[g]) begin
                if(!lane_pending[g]) begin
                    event_payload={g[7:0],{5'd0,result_sources[g*3 +:3]},8'd1,
                        {6'd0,(result_right_valid[g]&&result_tag_valid[g]),
                              (result_left_valid[g]&&result_tag_valid[g])},
                        result_source_frames[g*32 +:32],
                        sign16(result_endpoints[g*48 +:12]),
                        sign16(result_endpoints[g*48+12 +:12]),
                        sign16(result_endpoints[g*48+24 +:12]),
                        sign16(result_endpoints[g*48+36 +:12]),16'd960,16'd540};
                    // Calibration is not implemented by the linear detector.
                    // Its packet calibration_id stays zero, rather than
                    // assigning a new CTRL label to an older detection frame.
                    lane_hold[g]<={result_frame_ids[g*32 +:32],ticks,
                        {result_tag_valid[g]?4'd1:4'd4,2'd0,result_mode[g*2 +:2]},16'd0,event_payload};
                    lane_pending[g]<=1;
                end else drops_this_cycle=drops_this_cycle+1'b1;
            end
            if(drops_this_cycle!=0) pixel_drops<=pixel_drops+drops_this_cycle;
        end
    end
    cdc_snapshot_mailbox #(.W(326)) u_health_mailbox(
        .src_clk(pix_clk),.src_rst_n(pix_rst_n),.src_send(health_send),.src_data(health_data),.src_ready(health_ready),
        .dst_clk(tx_clk),.dst_rst_n(tx_rst_n),.dst_data(health_received),.dst_pulse(health_pulse));
    cdc_snapshot_mailbox #(.W(280),.P_LOCAL_CAPTURE_RESET_REDUNDANCY(1)) u_lane_mailbox(
        .src_clk(pix_clk),.src_rst_n(pix_rst_n),.src_send(lane_send),.src_data(lane_data),.src_ready(lane_ready),
        .dst_clk(tx_clk),.dst_rst_n(tx_rst_n),.dst_data(lane_received),.dst_pulse(lane_pulse));

    reg health_pending_tx;
    reg [2:0] lane_count_tx;
    reg [1:0] lane_read_tx,lane_write_tx;
    // Four explicitly named FF words keep normal simultaneous four-window
    // results while serial CRC builds packets, without inferring new DRM.
    reg [279:0] lane_q0,lane_q1,lane_q2,lane_q3;
    wire lane_pending_tx=(lane_count_tx!=0);
    wire [279:0] lane_hold_tx=(lane_read_tx==0)?lane_q0:(lane_read_tx==1)?lane_q1:
        (lane_read_tx==2)?lane_q2:lane_q3;
    reg [325:0] health_hold_tx;
    reg [1023:0] packet,crc_shift;
    reg [7:0] bytes_left;
    reg [31:0] packet_sequence,crc;
    // State 4 holds an immutable application packet until the TX accepts it.
    // Two bits truncate 4 to IDLE and allow replacement under backpressure.
    reg [2:0] build_state;
    reg prefer_lane;
    reg [31:0] selected_frame;
    reg [63:0] selected_ticks;
    reg [7:0] selected_mode,selected_status,selected_type;
    reg [15:0] selected_cal;
    reg [287:0] selected_payload;
    reg [15:0] selected_length;
    reg [255:0] selected_header;
    reg [287:0] health_payload;
    wire lane_dequeue_tx=(build_state==0)&&(health_pending_tx||lane_pending_tx)&&(selected_type==1);
    wire lane_accept_tx=lane_pulse&&((lane_count_tx<4)||lane_dequeue_tx);
    integer s;
    function automatic [31:0] crc_byte(input [31:0] old,input [7:0] data);
        reg [31:0] v;integer b;
        begin
            v=old^{24'd0,data};
            for(b=0;b<8;b=b+1) v=v[0] ? (v>>1)^32'hedb88320 : v>>1;
            crc_byte=v;
        end
    endfunction
    always @* begin
        // Each stored source_frame word is low-index first. Wire payload is
        // source0,source1,... in network byte order.
        health_payload={16'd1920,16'd1080,2'd0,health_hold_tx[197:192],
            6'd0,health_hold_tx[223:222],health_hold_tx[205:198],8'd0,192'd0,32'd148500000};
        for(s=0;s<6;s=s+1) health_payload[223-s*32 -:32]=health_hold_tx[s*32 +:32];
        selected_frame=health_hold_tx[325:294];selected_ticks=health_hold_tx[293:230];
        selected_mode=health_hold_tx[229:222];selected_cal=health_hold_tx[221:206];
        selected_status=1;selected_type=7;selected_payload=health_payload;selected_length=36;
        if(lane_pending_tx && (!health_pending_tx || prefer_lane)) begin
            selected_frame=lane_hold_tx[279:248];selected_ticks=lane_hold_tx[247:184];
            selected_mode={6'd0,lane_hold_tx[177:176]};
            selected_status={4'd0,lane_hold_tx[183:180]};
            selected_cal=0;selected_type=1;selected_payload={lane_hold_tx[159:0],128'd0};selected_length=20;
        end
        selected_header={32'h59544931,8'd1,selected_type,8'h50,selected_status,
            selected_frame,selected_ticks,selected_mode,8'd0,selected_cal,packet_sequence,selected_length,16'd32};
    end
    always @(posedge tx_clk or negedge tx_rst_n) begin
        if(!tx_rst_n) begin
            health_pending_tx<=0;health_hold_tx<=0;
            lane_count_tx<=0;lane_read_tx<=0;lane_write_tx<=0;
            lane_q0<=0;lane_q1<=0;lane_q2<=0;lane_q3<=0;
            packet<=0;crc_shift<=0;bytes_left<=0;packet_sequence<=0;crc<=32'hffffffff;
            build_state<=0;prefer_lane<=0;app_valid<=0;app_length<=0;app_payload<=0;tx_drops<=0;
        end else begin
            case(build_state)
                0:if(health_pending_tx || lane_pending_tx) begin
                    packet<={selected_header,selected_payload,480'd0};
                    crc_shift<={selected_header,selected_payload,480'd0};
                    bytes_left<=32+selected_length;app_length<=36+selected_length;
                    crc<=32'hffffffff;build_state<=1;packet_sequence<=packet_sequence+1'b1;
                    if(selected_type==1) begin prefer_lane<=0;end
                    else begin health_pending_tx<=0;prefer_lane<=1;end
                end
                1:begin
                    crc<=crc_byte(crc,crc_shift[1023:1016]);crc_shift<={crc_shift[1015:0],8'd0};
                    bytes_left<=bytes_left-1'b1;
                    if(bytes_left==1) build_state<=2;
                end
                2:begin
                    if(app_length==72) packet[479:448]<=~crc;
                    else packet[607:576]<=~crc;
                    build_state<=3;
                end
                3:begin app_payload<=packet;app_valid<=1;build_state<=4;end
                4:if(app_valid && app_ready) begin app_valid<=0;build_state<=0;end
                default:build_state<=0;
            endcase
            if(health_pulse) begin
                if(!health_pending_tx) begin health_hold_tx<=health_received;health_pending_tx<=1;end
            end
            if(lane_dequeue_tx)lane_read_tx<=lane_read_tx+1'b1;
            if(lane_accept_tx) begin
                case(lane_write_tx)
                    0:lane_q0<=lane_received;
                    1:lane_q1<=lane_received;
                    2:lane_q2<=lane_received;
                    3:lane_q3<=lane_received;
                endcase
                lane_write_tx<=lane_write_tx+1'b1;
            end
            case({lane_accept_tx,lane_dequeue_tx})
                2'b10:lane_count_tx<=lane_count_tx+1'b1;
                2'b01:lane_count_tx<=lane_count_tx-1'b1;
                default:;
            endcase
            if((health_pulse && health_pending_tx)||(lane_pulse && !lane_accept_tx))
                tx_drops<=tx_drops+{31'd0,(health_pulse && health_pending_tx)}+
                    {31'd0,(lane_pulse && !lane_accept_tx)};
        end
    end
endmodule
