`timescale 1ns/1ps
// Uses the original PCLK, no fabric-derived pixel clock. RGB565 is two
// successive HREF bytes. Each beat holds 16 pixels, pixel zero in low bits.
// The last beat is withheld until the next VSYNC validates all row lengths.
// DVP cannot be backpressured. Overflow invalidates the whole current frame.
module camera_rgb565_packetizer #(
    parameter SRC_W=960,SRC_H=540,SOURCE_ID=0,SWAP_RB=1
)(
    input wire clk,rst_n,input wire vsync,href,input wire [7:0] data,
    output reg beat_valid,input wire beat_ready,
    output wire [2:0] beat_source, output reg [18:0] beat_block,
    output reg [31:0] beat_frame,output reg [255:0] beat_data,
    output reg [31:0] dropped_frames,good_frames
);
    reg vs_d,href_d,started,half,bad,last_pending,beat_is_eof;
    reg [7:0] first_byte;
    reg [11:0] col,row;
    reg [19:0] pixels;
    reg [3:0] slot;
    reg [18:0] block_index;
    reg [31:0] frame_id;
    reg [255:0] packed_pixels,last_data;
    wire [15:0] raw_pixel={first_byte,data};
    wire [15:0] rgb_pixel=SWAP_RB?{raw_pixel[4:0],raw_pixel[10:5],raw_pixel[15:11]}:raw_pixel;
    wire sof=vsync && !vs_d;
    wire ordinary_rejected=beat_valid && !beat_ready && !beat_is_eof;
    wire eof_accepted=beat_valid && beat_ready && beat_is_eof;
    wire eof_rejected=beat_valid && !beat_ready && beat_is_eof;
    wire complete_at_sof=!bad && !ordinary_rejected && !half && row==SRC_H
        && pixels==SRC_W*SRC_H && last_pending && beat_ready;
    wire discard_at_sof=sof && started && !complete_at_sof;
    assign beat_source=SOURCE_ID;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;href_d<=0;started<=0;half<=0;bad<=0;last_pending<=0;beat_is_eof<=0;
            col<=0;row<=0;pixels<=0;slot<=0;block_index<=0;frame_id<=0;
            first_byte<=0;packed_pixels<=0;last_data<=0;
            beat_valid<=0;beat_block<=0;beat_frame<=0;beat_data<=0;
            dropped_frames<=0;good_frames<=0;
        end else begin
            vs_d<=vsync;href_d<=href;beat_valid<=0;beat_is_eof<=0;
            // EOF at SOF belongs to the previous frame. Its next-cycle
            // FIFO rejection must never poison the new frame's geometry.
            if(ordinary_rejected) bad<=1;
            if(eof_accepted) good_frames<=good_frames+1;
            if(eof_rejected || discard_at_sof)
                dropped_frames<=dropped_frames+{31'b0,eof_rejected}+{31'b0,discard_at_sof};
            if(sof) begin
                if(started) begin
                    if(complete_at_sof) begin
                        beat_valid<=1;beat_block<=(SRC_W*SRC_H/16)-1;
                        beat_data<=last_data;beat_frame<=frame_id;beat_is_eof<=1;
                    end
                end
                started<=1;half<=0;bad<=0;last_pending<=0;
                col<=0;row<=0;pixels<=0;slot<=0;block_index<=0;frame_id<=frame_id+1;
            end else if(started && !vsync) begin
                if(href_d && !href) begin
                    if(col!=SRC_W || half) bad<=1;
                    col<=0;row<=row+1;half<=0;
                end
                if(href) begin
                    if(!half) begin first_byte<=data;half<=1; end
                    else begin
                        half<=0;col<=col+1;pixels<=pixels+1;
                        if(col>=SRC_W || row>=SRC_H || pixels>=SRC_W*SRC_H) bad<=1;
                        packed_pixels[slot*16 +:16]<=rgb_pixel;
                        slot<=slot+1;
                        if(slot==15) begin
                            if(pixels==SRC_W*SRC_H-1) begin
                                last_data<={rgb_pixel,packed_pixels[239:0]};last_pending<=1;
                            end else if(!bad && beat_ready) begin
                                beat_valid<=1;beat_block<=block_index;beat_frame<=frame_id;
                                beat_data<={rgb_pixel,packed_pixels[239:0]};
                            end else if(!bad) bad<=1;
                            block_index<=block_index+1;
                        end
                    end
                end
            end
        end
    end
endmodule
