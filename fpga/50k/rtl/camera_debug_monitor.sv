`timescale 1ns/1ps
// Passive diagnostics only: never gates DVP, FIFO traffic or DDR publication.
// Counters stay in PCLK. Each status is an independent single-bit CDC signal.
module camera_debug_monitor #(
    parameter integer SRC_W=960, SRC_H=540,
    parameter integer HEARTBEAT_BITS=12, WATCH_BITS=24
)(
    input wire pclk,cap_rst_n,raw_vsync,raw_href,
    input wire [7:0] raw_data,
    input wire capture_enable,fifo_ready,good_toggle,
    input wire [1:0] dropped_low,
    input wire cfg_done,response_low_seen,ddr_frame_valid,
    input wire pix_clk,pix_rst_n,
    output wire [13:0] flags
);
    reg [HEARTBEAT_BITS-1:0] pclk_div;
    reg [8:0] observed;
    reg vs_d,href_d,good_d;
    reg [1:0] dropped_d;
    reg [7:0] data_d;
    reg data_d_valid,started,drop_armed;
    reg [11:0] line_bytes;
    reg [9:0] frame_rows;
    wire sof=raw_vsync && !vs_d;
    always @(posedge pclk or negedge cap_rst_n) begin
        if(!cap_rst_n) begin
            pclk_div<=0;observed<=0;vs_d<=0;href_d<=0;good_d<=0;
            dropped_d<=0;data_d<=0;data_d_valid<=0;started<=0;drop_armed<=0;
            line_bytes<=0;frame_rows<=0;
        end else begin
            pclk_div<=pclk_div+1'b1;
            vs_d<=raw_vsync;href_d<=raw_href;
            good_d<=good_toggle;dropped_d<=dropped_low;
            if(sof) observed[0]<=1;
            if(raw_href && !raw_vsync) observed[1]<=1;
            if(good_toggle!=good_d) observed[3]<=1;
            // Ignore disabled/partial startup frames, including the count
            // update one cycle after the first enabled SOF. Later SOFs must
            // retain arming so actual rejected frames are still observed.
            if(capture_enable && drop_armed && dropped_low!=dropped_d) observed[4]<=1;
            if(capture_enable && raw_href && !raw_vsync) begin
                if(raw_data!=0) observed[2]<=1;
                if(!fifo_ready) observed[5]<=1;
                if(data_d_valid && raw_data!=data_d) observed[8]<=1;
                data_d<=raw_data;data_d_valid<=1;
            end else data_d_valid<=0;
            // Start geometry at the first enabled SOF, not a partial line.
            if(!capture_enable) begin
                started<=0;drop_armed<=0;line_bytes<=0;frame_rows<=0;
            end else if(sof) begin
                if(started && (frame_rows!=SRC_H || line_bytes!=0)) observed[7]<=1;
                started<=1;line_bytes<=0;frame_rows<=0;
            end else if(started && !raw_vsync) begin
                drop_armed<=1;
                if(raw_href) begin
                    if(line_bytes!=12'hfff) line_bytes<=line_bytes+1'b1;
                end else if(href_d) begin
                    if(line_bytes!=2*SRC_W) observed[6]<=1;
                    line_bytes<=0;
                    if(frame_rows!=10'h3ff) frame_rows<=frame_rows+1'b1;
                end
            end
        end
    end

    // Bits 13/12/11 are memory/config-domain levels; bits 9:1 are PCLK
    // sticky levels and bit0 is a slow PCLK heartbeat. No bus is decoded
    // until after local observations have become independent flags.
    wire [13:0] async_status={ddr_frame_valid,cfg_done,response_low_seen,
        capture_enable,observed,pclk_div[HEARTBEAT_BITS-1]};
    (* PAP_ASYNC_REG=1 *) reg [13:0] status_meta,status_sync;
    reg heartbeat_d,clock_recent;
    reg [WATCH_BITS-1:0] heartbeat_age;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin
            status_meta<=0;status_sync<=0;heartbeat_d<=0;
            heartbeat_age<=0;clock_recent<=0;
        end else begin
            status_meta<=async_status;status_sync<=status_meta;
            heartbeat_d<=status_sync[0];
            if(status_sync[0]!=heartbeat_d) begin
                heartbeat_age<=0;clock_recent<=1;
            end else if(&heartbeat_age) clock_recent<=0;
            else heartbeat_age<=heartbeat_age+1'b1;
        end
    end
    // Low to high: CFG CLK VS HF EN RSP DAT OK DRP FUL LIN FRM DDR CHG.
    assign flags={status_sync[9],status_sync[13],status_sync[8],status_sync[7],
        status_sync[6],status_sync[5],status_sync[4],status_sync[3],
        status_sync[11],status_sync[10],status_sync[2],status_sync[1],
        clock_recent,status_sync[12]};
endmodule
