`timescale 1ns/1ps
// Four 1920-pixel lines (122,880 bits), not an on-chip frame buffer.
// DDR fills a bank after its previous scan has finished. Tags include an
// epoch, so late lines from an earlier HDMI frame are discarded.
// RGB/DE/HS/VS latency: four pixel-clock registers; missing rows output black.
// The 16:1 lane selector is split into two registered 4:1 selectors.
module mosaic_line_display #(
    parameter OUT_W=1920,OUT_H=1080
)(
    input wire clk,rst_n, input wire [11:0] x,y,
    input wire de,hs,vs,frame_start,line_end,input wire [1:0] mode,
    output reg req_valid,input wire req_ready,output reg [10:0] req_y,
    output reg [1:0] req_mode,output reg req_frame_start,output reg [7:0] req_epoch,
    input wire data_valid,output wire data_ready,input wire [255:0] data,
    input wire [10:0] data_y,input wire [6:0] data_index,input wire [7:0] data_epoch,
    input wire data_source_valid,
    output reg [23:0] rgb_out,output reg de_out,hs_out,vs_out,
    output reg pixel_valid_out,
    output reg [31:0] underrun_lines,request_overflow
);
    localparam ROW_BEATS=OUT_W/16;
    function integer address_bits;
        input integer depth;
        integer remaining;
        begin
            remaining=depth-1;
            address_bits=0;
            while(remaining>0) begin
                address_bits=address_bits+1;
                remaining=remaining>>1;
            end
            if(address_bits==0) address_bits=1;
        end
    endfunction
    localparam BANK_ADDR_BITS=address_bits(ROW_BEATS);
    localparam BANK_WORDS=1<<BANK_ADDR_BITS;
    // Pad each bank to a power-of-two stride (128 beats at 1920 pixels).
    // Concatenated bank/beat addresses avoid a y-bank * 120 + x-beat
    // carry chain at the block-RAM input, without adding pixel latency.
    reg [255:0] lines[0:4*BANK_WORDS-1];
    reg [BANK_ADDR_BITS+1:0] fill_address;
    reg [255:0] fill_pixels;
    reg [10:0] fill_y;
    reg [7:0] fill_epoch;
    reg fill_valid,fill_last;
    reg fill_source_valid;
    reg [1:0] source_valid[0:3];
    wire [BANK_ADDR_BITS+1:0] scan_address={y[1:0],x[BANK_ADDR_BITS+3:4]};
    reg [10:0] tags[0:3];reg [7:0] epochs[0:3];reg [3:0] ready_lines;
    reg [7:0] epoch;
    reg [2:0] initial_state;
    reg [1:0] initial_row;
    reg [255:0] read_word;
    reg [3:0] read_lane;
    reg read_good,de_d,hs_d,vs_d;
    reg good_d,good_d2,de_d2,hs_d2,vs_d2,de_d3,hs_d3,vs_d3;
    reg read_source_good,source_good_d,source_good_d2;
    reg [15:0] pixel_d;
    reg [63:0] group_pixels;
    reg [1:0] lane_hi;
    reg scan_row_good;
    wire row_available=ready_lines[y[1:0]] && tags[y[1:0]]==y && epochs[y[1:0]]==epoch;
    // Epoch advances only on frame_start. Cancel a pending token on that
    // edge and do not accept an incoming token for the retiring epoch.
    wire fill_commit=fill_valid && !frame_start;
    assign data_ready=1'b1;
    always @(posedge clk) begin
        // Register both payload and the filtered write enable before the
        // RAM write port. The line becomes ready on this commit edge,
        // never on the preceding input-token capture edge.
        fill_pixels<=data;
        fill_address<={data_y[1:0],data_index[BANK_ADDR_BITS-1:0]};
        fill_y<=data_y;fill_epoch<=data_epoch;
        fill_last<=data_index==ROW_BEATS-1;
        fill_source_valid<=data_source_valid;
        if(fill_commit) lines[fill_address]<=fill_pixels;
        if(de) read_word<=lines[scan_address];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ready_lines<=0;tags[0]<=0;tags[1]<=0;tags[2]<=0;tags[3]<=0;
            epochs[0]<=0;epochs[1]<=0;epochs[2]<=0;epochs[3]<=0;
            epoch<=0;initial_state<=0;initial_row<=0;req_valid<=0;req_y<=0;req_mode<=0;req_frame_start<=0;req_epoch<=0;
            fill_valid<=0;
            source_valid[0]<=0;source_valid[1]<=0;source_valid[2]<=0;source_valid[3]<=0;
            read_source_good<=0;source_good_d<=0;source_good_d2<=0;pixel_valid_out<=0;
            read_lane<=0;read_good<=0;scan_row_good<=0;de_d<=0;hs_d<=0;vs_d<=0;
            good_d<=0;good_d2<=0;de_d2<=0;hs_d2<=0;vs_d2<=0;pixel_d<=0;
            de_d3<=0;hs_d3<=0;vs_d3<=0;group_pixels<=0;lane_hi<=0;
            rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;underrun_lines<=0;request_overflow<=0;
        end else begin
            fill_valid<=data_valid && data_epoch==epoch && data_index<ROW_BEATS
                        && data_y<OUT_H && !frame_start;
            if(req_valid && req_ready) req_valid<=0;
            if(frame_start) begin
                epoch<=epoch+1;ready_lines<=0;initial_state<=1;initial_row<=0;
            end else if(initial_state==1) initial_state<=2;
            else if(initial_state==2 && !req_valid) begin
                req_valid<=1;req_y<={9'b0,initial_row};req_mode<=mode;
                req_frame_start<=(initial_row==0);req_epoch<=epoch;initial_state<=3;
            end else if(initial_state==3 && req_valid && req_ready) begin
                if(initial_row==3) initial_state<=0;
                else begin initial_row<=initial_row+1;initial_state<=2;end
            end
            if(fill_commit && fill_last) begin
                ready_lines[fill_y[1:0]]<=1;tags[fill_y[1:0]]<=fill_y;epochs[fill_y[1:0]]<=fill_epoch;
            end
            // A row becomes readable only after its final beat is committed.
            // Record the completeness of each half on its own final beat.
            if(fill_commit && fill_address[BANK_ADDR_BITS-1:0]==ROW_BEATS/2-1)
                source_valid[fill_y[1:0]][0]<=fill_source_valid;
            if(fill_commit && fill_last)
                source_valid[fill_y[1:0]][1]<=fill_source_valid;
            if(de && x==0 && !row_available) underrun_lines<=underrun_lines+1;
            if(de && x==0) scan_row_good<=row_available;
            if(line_end && y<OUT_H) begin
                ready_lines[y[1:0]]<=0;
                // Keep the row+4 adder off the request-register CE path.
                // y is unsigned; OUT_H>=4 preserves the frame-end bound.
                if(y<OUT_H-4) begin
                    if(!req_valid || req_ready) begin
                        req_valid<=1;req_y<=y+4;req_mode<=mode;req_frame_start<=0;req_epoch<=epoch;
                    end else request_overflow<=request_overflow+1;
                end
            end
            read_lane<=x[3:0];read_good<=de && ((x==0)?row_available:scan_row_good);
            read_source_good<=source_valid[y[1:0]][x>=OUT_W/2];
            de_d<=de;hs_d<=hs;vs_d<=vs;
            group_pixels[15:0]<=read_word[read_lane[1:0]*16 +:16];
            group_pixels[31:16]<=read_word[64+read_lane[1:0]*16 +:16];
            group_pixels[47:32]<=read_word[128+read_lane[1:0]*16 +:16];
            group_pixels[63:48]<=read_word[192+read_lane[1:0]*16 +:16];
            lane_hi<=read_lane[3:2];good_d<=read_good;
            source_good_d<=read_source_good;source_good_d2<=source_good_d;
            pixel_d<=group_pixels[lane_hi*16 +:16];good_d2<=good_d;
            de_d2<=de_d;hs_d2<=hs_d;vs_d2<=vs_d;
            de_d3<=de_d2;hs_d3<=hs_d2;vs_d3<=vs_d2;
            de_out<=de_d3;hs_out<=hs_d3;vs_out<=vs_d3;
            pixel_valid_out<=good_d2 && source_good_d2;
            if(good_d2) rgb_out<={pixel_d[15:11],pixel_d[15:13],pixel_d[10:5],pixel_d[10:9],pixel_d[4:0],pixel_d[4:2]};
            else rgb_out<=0;
        end
    end
endmodule
