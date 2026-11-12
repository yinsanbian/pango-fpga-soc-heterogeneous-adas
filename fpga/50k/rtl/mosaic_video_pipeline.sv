`timescale 1ns/1ps
// Real production display path. The four-cycle DMA display input is aligned
// with raw coordinates before shared process views; detectors receive the
// delayed original color plane, independently of the selected display view.
module mosaic_video_pipeline #(
    parameter integer P_IMG_W=960,P_IMG_H=540,P_H_TOTAL=2200,
    parameter integer P_KEY_DEBOUNCE_CYCLES=1485000,
    parameter integer P_HUD_ENABLE=1,
    parameter integer P_CAMERA_ONLY_LAYOUT=1,
    parameter integer P_M2_ONLY=0
)(
    input wire clk,rst_n,key_process_n,
    input wire [1:0] layout_mode,
    input wire [11:0] raw_x,
    input wire [10:0] raw_y,
    input wire raw_de,raw_frame_start,
    input wire [23:0] rgb_in,
    input wire video_de,video_hs,video_vs,pixel_valid_in,
    input wire [13:0] flags0,flags1,
    input wire [119:0] readback0,readback1,
    input wire readback_valid0,readback_valid1,
    input wire [191:0] context_source_frames,
    input wire [5:0] context_source_valid,
    input wire [7:0] context_epoch,
    output wire [23:0] rgb_out,
    output wire de_out,hs_out,vs_out,
    output wire [2:0] view_mode,
    // Original color plane aligned with the existing lane/HUD output. The
    // downstream relay may select it without changing the debug path latency.
    output wire [23:0] relay_rgb_out,
    output wire [11:0] relay_x_out,
    output wire [10:0] relay_y_out,
    output wire [1:0] relay_mode_out,
    output wire relay_frame_start_out,
    output wire [3:0] result_pulse,
    output wire [127:0] result_frame_ids,result_source_frames,
    output wire [11:0] result_sources,
    output wire [7:0] result_mode,
    output wire [3:0] result_tag_valid,result_left_valid,result_right_valid,
    output wire [191:0] result_endpoints
);
    reg [11:0] base_x[0:3];
    reg [10:0] base_y[0:3];
    reg [1:0] base_mode[0:3];
    reg [3:0] base_sof;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            base_sof<=0;
            for(k=0;k<4;k=k+1) begin base_x[k]<=0;base_y[k]<=0;base_mode[k]<=0;end
        end else begin
            base_x[0]<=raw_x;base_y[0]<=raw_y;base_mode[0]<=layout_mode;
            base_sof<={base_sof[2:0],raw_frame_start};
            for(k=1;k<4;k=k+1) begin
                base_x[k]<=base_x[k-1];base_y[k]<=base_y[k-1];base_mode[k]<=base_mode[k-1];
            end
        end
    end
    wire [23:0] original_rgb,process_rgb,lane_rgb;
    wire [11:0] process_x;
    wire [10:0] process_y;
    wire [1:0] process_layout;
    wire process_de,process_hs,process_vs,process_sof,process_valid;
    wire lane_de,lane_hs,lane_vs;
    wire [2:0] requested_view;
    reg [23:0] relay_rgb[0:6];
    reg [11:0] relay_x[0:6];
    reg [10:0] relay_y[0:6];
    reg [1:0] relay_mode[0:6];
    reg [6:0] relay_sof;
    integer r;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            relay_sof<=0;
            for(r=0;r<7;r=r+1) begin
                relay_rgb[r]<=0;relay_x[r]<=0;relay_y[r]<=0;relay_mode[r]<=0;
            end
        end else begin
            relay_rgb[0]<=original_rgb;relay_x[0]<=process_x;relay_y[0]<=process_y;
            relay_mode[0]<=process_layout;relay_sof<={relay_sof[5:0],process_sof};
            for(r=1;r<7;r=r+1) begin
                relay_rgb[r]<=relay_rgb[r-1];relay_x[r]<=relay_x[r-1];
                relay_y[r]<=relay_y[r-1];relay_mode[r]<=relay_mode[r-1];
            end
        end
    end
    assign relay_rgb_out=relay_rgb[6];
    assign relay_x_out=relay_x[6];
    assign relay_y_out=relay_y[6];
    assign relay_mode_out=relay_mode[6];
    assign relay_frame_start_out=relay_sof[6];
    // One ordinary pixel-domain reset distribution FF isolates the process
    // branch from the global high-fanout reset. Base coordinates/SOF retain
    // their four-cycle pre-alignment; normal video latency is unchanged.
    reg process_reset_released;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) process_reset_released<=1'b0;
        else process_reset_released<=1'b1;
    mosaic_process_views #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_H_TOTAL(P_H_TOTAL),.P_CAMERA_ONLY_LAYOUT(P_CAMERA_ONLY_LAYOUT),.P_M2_ONLY(P_M2_ONLY)) u_process(
        .clk(clk),.rst_n(process_reset_released),.layout_mode(base_mode[3]),.view_mode(requested_view),
        .rgb_in(rgb_in),.x_in(base_x[3]),.y_in(base_y[3]),
        .de_in(video_de),.hs_in(video_hs),.vs_in(video_vs),
        .frame_start_in(base_sof[3]),.pixel_valid_in(pixel_valid_in),
        .original_rgb_out(original_rgb),.view_rgb_out(process_rgb),
        .x_out(process_x),.y_out(process_y),.layout_mode_out(process_layout),
        .de_out(process_de),.hs_out(process_hs),.vs_out(process_vs),
        .frame_start_out(process_sof),.pixel_valid_out(process_valid),.view_mode_out(view_mode)
    );
    video_mode_control #(.P_MODE_COUNT(6),.P_DEBOUNCE_CYCLES(P_KEY_DEBOUNCE_CYCLES)) u_view_mode(
        // Publish the request before the line-delayed SOF. u_process then
        // exposes the actual active view atomically with its output SOF/VS.
        .clk(clk),.rst_n(rst_n),.key_n(key_process_n),.vsync(video_vs),.display_mode(requested_view)
    );
    mosaic_four_lane_video #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_PROCESS_VIEWS(1),.P_CAMERA_ONLY_LAYOUT(P_CAMERA_ONLY_LAYOUT),.P_M2_ONLY(P_M2_ONLY)) u_four_lane(
        .clk(clk),.rst_n(rst_n),.mode(process_layout),.frame_start(process_sof),
        .rgb_in(original_rgb),.process_rgb_in(process_rgb),.process_view(view_mode),
        .x(process_x),.y(process_y),.de_in(process_de),.hs_in(process_hs),.vs_in(process_vs),
        .pixel_valid_in(process_valid),.rgb_out(lane_rgb),.de_out(lane_de),.hs_out(lane_hs),.vs_out(lane_vs),
        .context_source_frames(context_source_frames),.context_source_valid(context_source_valid),.context_epoch(context_epoch),
        .result_pulse(result_pulse),.result_frame_ids(result_frame_ids),.result_source_frames(result_source_frames),
        .result_sources(result_sources),.result_mode(result_mode),.result_tag_valid(result_tag_valid),
        .result_left_valid(result_left_valid),.result_right_valid(result_right_valid),.result_endpoints(result_endpoints),
        .active_l_valid(),.active_r_valid(),.vote_drop(),.bound_source()
    );
    // Glyph decoding is four clocks. For six-clock drawing, HUD coordinates
    // must be two clocks later than the detector input, then one output FF.
    reg [11:0] hud_x[0:1];
    reg [10:0] hud_y[0:1];
    reg [1:0] hud_layout[0:1];
    reg [2:0] hud_view[0:1];
    reg [1:0] hud_de;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hud_x[0]<=0;hud_x[1]<=0;hud_y[0]<=0;hud_y[1]<=0;
            hud_layout[0]<=0;hud_layout[1]<=0;hud_view[0]<=0;hud_view[1]<=0;hud_de<=0;
        end else begin
            hud_x[0]<=process_x;hud_x[1]<=hud_x[0];hud_y[0]<=process_y;hud_y[1]<=hud_y[0];
            hud_layout[0]<=process_layout;hud_layout[1]<=hud_layout[0];
            hud_view[0]<=view_mode;hud_view[1]<=hud_view[0];hud_de<={hud_de[0],process_de};
        end
    end
    camera_debug_overlay #(.P_ENABLE(P_HUD_ENABLE),.P_VIEW_LABEL(1)) u_debug_overlay(
        .clk(clk),.rst_n(rst_n),.x(hud_x[1]),.y(hud_y[1]),.raw_de(hud_de[1]),
        .video_rgb(lane_rgb),.video_de(lane_de),.video_hs(lane_hs),.video_vs(lane_vs),
        .flags0(flags0),.flags1(flags1),.mode({1'b0,hud_layout[1]}),.process_view(hud_view[1]),
        .readback0(readback0),.readback1(readback1),.readback_valid0(readback_valid0),.readback_valid1(readback_valid1),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out)
    );
endmodule
