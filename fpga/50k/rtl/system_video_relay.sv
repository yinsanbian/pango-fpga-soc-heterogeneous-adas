`timescale 1ns/1ps
// Clean inter-board video and a final in-band 64-bit frame marker. All pixel
// outputs add exactly one register. frame_start_in is a blanking SOF with at
// least 57 clocks before the first active pixel (the production raster has
// much more). A short blank produces an invalid black marker, never a false
// valid header. Decode the marker before scaling/cropping downstream.
module system_video_relay #(
    parameter integer P_PIXELS_PER_BIT=8
)(
    input wire clk,rst_n,
    input wire [23:0] rgb_clean_in,rgb_debug_in,
    input wire [11:0] x_in,
    input wire [10:0] y_in,
    input wire [1:0] layout_mode_in,
    input wire [2:0] view_mode_in,
    input wire frame_start_in,de_in,hs_in,vs_in,
    input wire debug_overlay_requested,
    output reg [23:0] rgb_out,
    output reg de_out,hs_out,vs_out,frame_start_out,
    output reg [11:0] x_out,
    output reg [10:0] y_out,
    output reg [31:0] frame_id_out,
    output reg [7:0] mode_id_out,
    output reg debug_active,
    output reg first_active_out,
    output reg marker_ready_out
);
    localparam integer BIT_SHIFT=$clog2(P_PIXELS_PER_BIT);
    localparam integer MARKER_PIXELS=64*P_PIXELS_PER_BIT;
    reg [55:0] marker_header,crc_shift;
    reg [7:0] marker_crc;
    reg [5:0] crc_remaining;
    wire [7:0] requested_mode={2'b00,debug_overlay_requested,
                              (debug_overlay_requested?view_mode_in:3'd0),layout_mode_in};
    wire crc_feedback=marker_crc[7]^crc_shift[55];
    wire [7:0] crc_next={marker_crc[6:0],1'b0}^(crc_feedback?8'h07:8'h00);
    wire [63:0] marker_word={marker_header,marker_crc};
    wire [5:0] marker_bit_index=x_in>>BIT_SHIFT;
    wire marker_pixel=marker_word[6'd63-marker_bit_index];
    wire in_marker=de_in&&(y_in==0)&&(x_in<MARKER_PIXELS);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            marker_header<=0;crc_shift<=0;marker_crc<=0;crc_remaining<=0;
            marker_ready_out<=0;frame_id_out<=0;mode_id_out<=0;debug_active<=0;
            rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;frame_start_out<=0;
            x_out<=0;y_out<=0;first_active_out<=0;
        end else begin
            if(frame_start_in) begin
                frame_id_out<=frame_id_out+1'b1;
                mode_id_out<=requested_mode;
                debug_active<=debug_overlay_requested;
                marker_header<={16'h5954,frame_id_out+32'd1,requested_mode};
                crc_shift<={16'h5954,frame_id_out+32'd1,requested_mode};
                marker_crc<=0;crc_remaining<=6'd56;marker_ready_out<=0;
            end else if(crc_remaining!=0) begin
                marker_crc<=crc_next;crc_shift<={crc_shift[54:0],1'b0};
                crc_remaining<=crc_remaining-1'b1;
                if(crc_remaining==1) marker_ready_out<=1;
            end
            // No bypass changes the cadence of sync/coordinates. The marker
            // comes after the complete debug/HUD renderer in the real top.
            // OSD text and colour processing are independent choices. The clean
            // build turns the text tables off but KEY2 must still be able to
            // select grayscale/binarize, so the processed plane is used whenever
            // a non-zero view is requested even with the overlay disabled.
            rgb_out<=(debug_active||(view_mode_in!=3'd0))?rgb_debug_in:rgb_clean_in;
            if(in_marker) rgb_out<=(marker_ready_out&&marker_pixel)?24'hffffff:24'h000000;
            de_out<=de_in;hs_out<=hs_in;vs_out<=vs_in;
            frame_start_out<=frame_start_in;x_out<=x_in;y_out<=y_in;
            first_active_out<=de_in&&(x_in==0)&&(y_in==0);
        end
    end

`ifndef SYNTHESIS
    initial begin
        if(P_PIXELS_PER_BIT<1 || (P_PIXELS_PER_BIT&(P_PIXELS_PER_BIT-1))!=0 || MARKER_PIXELS>4096)
            $fatal(1,"system_video_relay P_PIXELS_PER_BIT must be a power of two in [1,64]");
    end
`endif
endmodule
