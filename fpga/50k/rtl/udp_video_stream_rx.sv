`timescale 1ns/1ps
// Accept ONLY a replay already validated in full by gmii_udp_rx. Its length
// is known before byte 0; no beat escapes before all 24 YTM1 header bytes pass.
// The upstream GMII receiver cannot be stalled. One held output beat covers a
// transient FIFO stop; if a second beat collides, discard this packet's tail.
// DDR's per-source consecutive-block contract rejects incomplete frames.
module udp_video_stream_rx #(
    parameter integer WIDTH=960, HEIGHT=540,
    parameter [3:0] CHANNEL_MASK=4'hf
)(
    input wire clk,rst_n,
    input wire udp_start,udp_valid,input wire [7:0] udp_data,
    input wire udp_end,udp_error,input wire [10:0] udp_payload_length,
    output reg beat_valid,input wire beat_ready,
    output reg [2:0] beat_source,output reg [18:0] beat_block,
    output reg [31:0] beat_frame,output reg [255:0] beat_data,
    output reg [31:0] bad_header_count,dropped_packet_count
);
    localparam integer FRAME_PIXELS=WIDTH*HEIGHT;
    reg receiving,header_decided,packet_good,packet_dropped;
    reg [11:0] byte_count;
    reg [10:0] packet_length;
    reg [31:0] magic,frame_id,pixel_offset;
    reg [7:0] version,channel,format_code,flags,pixel_high;
    reg [15:0] pixel_count,width_field,height_field,reserved;
    reg [255:0] packed_pixels;
    reg [18:0] next_block;
    wire [11:0] payload_position=byte_count-12'd24;
    wire [255:0] assembled_block={pixel_high,udp_data,packed_pixels[255:16]};
    wire header_good=magic==32'h59544d31 && version==1 && channel<4 &&
        CHANNEL_MASK[channel[1:0]] && format_code==1 && flags==0 &&
        width_field==WIDTH && height_field==HEIGHT && reserved==0 &&
        pixel_count>0 && pixel_count<=512 && pixel_count[3:0]==0 &&
        pixel_offset[3:0]==0 && pixel_offset<FRAME_PIXELS &&
        pixel_count<=FRAME_PIXELS-pixel_offset &&
        {1'b0,packet_length}==(12'd24+{pixel_count[10:0],1'b0});
    // At byte 24, the complete header is already registered. This expression
    // also covers a header/payload with no idle clock between them.
    wire accept_payload=header_decided ? packet_good : header_good;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            receiving<=0;header_decided<=0;packet_good<=0;packet_dropped<=0;
            byte_count<=0;packet_length<=0;magic<=0;frame_id<=0;pixel_offset<=0;
            version<=0;channel<=0;format_code<=0;flags<=0;pixel_high<=0;
            pixel_count<=0;width_field<=0;height_field<=0;reserved<=0;
            packed_pixels<=0;next_block<=0;
            beat_valid<=0;beat_source<=0;beat_block<=0;beat_frame<=0;beat_data<=0;
            bad_header_count<=0;dropped_packet_count<=0;
        end else begin
            if(beat_valid && beat_ready) beat_valid<=0;
            if(udp_start) begin
                receiving<=1;header_decided<=0;packet_good<=0;packet_dropped<=0;
                byte_count<=0;packet_length<=udp_payload_length;
                magic<=0;frame_id<=0;pixel_offset<=0;version<=0;channel<=0;
                format_code<=0;flags<=0;pixel_count<=0;width_field<=0;
                height_field<=0;reserved<=0;packed_pixels<=0;pixel_high<=0;
            end else if(udp_valid && receiving) begin
                byte_count<=byte_count+1'b1;
                case(byte_count)
                    0,1,2,3:magic<={magic[23:0],udp_data};
                    4:version<=udp_data;
                    5:channel<=udp_data;
                    6:format_code<=udp_data;
                    7:flags<=udp_data;
                    8,9,10,11:frame_id<={frame_id[23:0],udp_data};
                    12,13,14,15:pixel_offset<={pixel_offset[23:0],udp_data};
                    16,17:pixel_count<={pixel_count[7:0],udp_data};
                    18,19:width_field<={width_field[7:0],udp_data};
                    20,21:height_field<={height_field[7:0],udp_data};
                    22,23:reserved<={reserved[7:0],udp_data};
                    default:begin
                        if(byte_count==24) begin
                            header_decided<=1;packet_good<=header_good;
                            next_block<=pixel_offset[22:4];
                            if(!header_good) bad_header_count<=bad_header_count+1'b1;
                        end
                        if(accept_payload && !packet_dropped && !udp_error) begin
                            if(!payload_position[0]) pixel_high<=udp_data;
                            else begin
                                packed_pixels<=assembled_block;
                                if(payload_position[4:0]==31) begin
                                    if(!beat_valid || beat_ready) begin
                                        beat_valid<=1;beat_data<=assembled_block;
                                        beat_source<=3'd2+channel[1:0];
                                        beat_block<=next_block;beat_frame<=frame_id;
                                        next_block<=next_block+1'b1;
                                    end else begin
                                        packet_dropped<=1;packet_good<=0;
                                        dropped_packet_count<=dropped_packet_count+1'b1;
                                    end
                                end
                            end
                        end
                    end
                endcase
            end
            if(udp_error && receiving) begin
                packet_good<=0;packet_dropped<=1;
                if(!packet_dropped) dropped_packet_count<=dropped_packet_count+1'b1;
            end
            if(udp_end && receiving) begin
                receiving<=0;
                if(byte_count<24 && !header_decided)
                    bad_header_count<=bad_header_count+1'b1;
            end
        end
    end
endmodule
