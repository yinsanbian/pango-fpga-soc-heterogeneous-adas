`timescale 1ns/1ps
// YTM1: 24-byte network-order header, then network-order RGB565 pixels.
// The DDR writer must check frame_id and consecutive block numbers per source.
module udp_video_rx #(
    parameter integer WIDTH=960, parameter integer HEIGHT=540
)(
    input wire clk, input wire rst_n,
    input wire udp_start, input wire udp_valid, input wire [7:0] udp_data,
    input wire udp_end, input wire udp_error,
    output reg beat_valid, input wire beat_ready,
    output reg [2:0] beat_source, output reg [18:0] beat_block,
    output reg [31:0] beat_frame, output reg [255:0] beat_data,
    output reg [31:0] bad_header_count, output reg [31:0] dropped_packet_count
);
    reg [255:0] blocks0 [0:31];
    reg [255:0] blocks1 [0:31];
    reg [255:0] packed_pixels;
    reg [1:0] pending;
    reg receiving, writer_bank, packet_bad, finish_pending;
    reg [11:0] byte_count;
    reg [31:0] magic, frame_id, pixel_offset;
    reg [7:0] version, channel, format_code, flags, pixel_high;
    reg [15:0] pixel_count, width_field, height_field, reserved;
    reg [2:0] source0, source1;
    reg [18:0] first_block0, first_block1;
    reg [31:0] frame0, frame1;
    reg [5:0] count0,count1;
    reg out_active,out_bank;
    reg [5:0] out_index,out_count;
    wire bank0_busy = pending[0] || (out_active && !out_bank);
    wire bank1_busy = pending[1] || (out_active && out_bank);
    wire [11:0] payload_position = byte_count-12'd24;
    // Fixed wiring, no 256-bit barrel shifter: after sixteen pixels, pixel 0
    // has shifted into the low 16 bits and pixel 15 is in the high 16 bits.
    wire [255:0] assembled_block = {pixel_high,udp_data,packed_pixels[255:16]};
    wire header_good = magic == 32'h59544d31 && version==1 && channel<4 && format_code==1 && flags==0 &&
        width_field==WIDTH && height_field==HEIGHT && reserved==0 && pixel_count>0 && pixel_count<=512 &&
        pixel_count[3:0]==0 && pixel_offset[3:0]==0 && pixel_offset<WIDTH*HEIGHT &&
        pixel_count <= WIDTH*HEIGHT-pixel_offset && byte_count==(24+({16'd0,pixel_count}<<1));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending<=0; receiving<=0; writer_bank<=0; packet_bad<=0; finish_pending<=0; byte_count<=0;
            magic<=0; frame_id<=0; pixel_offset<=0; version<=0; channel<=0; format_code<=0; flags<=0;
            pixel_count<=0; width_field<=0; height_field<=0; reserved<=0; pixel_high<=0; packed_pixels<=0;
            source0<=0; source1<=0; first_block0<=0; first_block1<=0; frame0<=0; frame1<=0; count0<=0; count1<=0;
            out_active<=0; out_bank<=0; out_index<=0; out_count<=0;
            beat_valid<=0; beat_source<=0; beat_block<=0; beat_frame<=0; beat_data<=0;
            bad_header_count<=0; dropped_packet_count<=0;
        end else begin
            beat_valid<=0;
            if (!out_active) begin
                if (pending[0]) begin
                    pending[0]<=0; out_active<=1; out_bank<=0; out_index<=0; out_count<=count0;
                end else if (pending[1]) begin
                    pending[1]<=0; out_active<=1; out_bank<=1; out_index<=0; out_count<=count1;
                end
            end else if (!beat_ready) begin
                // The physical receiver cannot wait. A block gap makes DDR discard the frame.
                out_active<=0; dropped_packet_count<=dropped_packet_count+1'b1;
            end else begin
                beat_valid<=1; beat_data<=out_bank ? blocks1[out_index[4:0]] : blocks0[out_index[4:0]];
                beat_source<=out_bank ? source1 : source0; beat_frame<=out_bank ? frame1 : frame0;
                beat_block<=(out_bank ? first_block1 : first_block0)+out_index;
                out_index<=out_index+1'b1;
                if (out_index+1'b1 == out_count) out_active<=0;
            end
            if (finish_pending) begin
                finish_pending<=0;
                if (header_good && !packet_bad) begin
                    pending[writer_bank]<=1;
                    if (writer_bank) begin source1<=3'd2+channel[1:0]; first_block1<=pixel_offset[22:4]; frame1<=frame_id; count1<=pixel_count[9:4]; end
                    else begin source0<=3'd2+channel[1:0]; first_block0<=pixel_offset[22:4]; frame0<=frame_id; count0<=pixel_count[9:4]; end
                end else bad_header_count<=bad_header_count+1'b1;
            end
            if (udp_start) begin
                receiving<=1; writer_bank<=bank0_busy; packet_bad<=bank0_busy&&bank1_busy; byte_count<=0;
                magic<=0; frame_id<=0; pixel_offset<=0; version<=0; channel<=0; format_code<=0; flags<=0;
                pixel_count<=0; width_field<=0; height_field<=0; reserved<=0; packed_pixels<=0;
            end else if (udp_valid && receiving) begin
                byte_count<=byte_count+1'b1;
                if (byte_count >= 1048) packet_bad<=1;
                case (byte_count)
                    0,1,2,3: magic<={magic[23:0],udp_data};
                    4: version<=udp_data;
                    5: channel<=udp_data;
                    6: format_code<=udp_data;
                    7: flags<=udp_data;
                    8,9,10,11: frame_id<={frame_id[23:0],udp_data};
                    12,13,14,15: pixel_offset<={pixel_offset[23:0],udp_data};
                    16,17: pixel_count<={pixel_count[7:0],udp_data};
                    18,19: width_field<={width_field[7:0],udp_data};
                    20,21: height_field<={height_field[7:0],udp_data};
                    22,23: reserved<={reserved[7:0],udp_data};
                    default: begin
                        if (byte_count < 1048) begin
                            if (!payload_position[0]) pixel_high<=udp_data;
                            else begin
                                packed_pixels<=assembled_block;
                                if (payload_position[4:0]==31) begin
                                    if (writer_bank) blocks1[payload_position[9:5]]<=assembled_block;
                                    else blocks0[payload_position[9:5]]<=assembled_block;
                                end
                            end
                        end
                    end
                endcase
            end
            if (udp_end && receiving) begin receiving<=0; finish_pending<=1; end
            if (udp_error && receiving) packet_bad<=1;
        end
    end
endmodule
