`timescale 1ns/1ps
// Four independent VISIBLE-window detector contexts in the existing pixel
// domain. Source bindings never share line RAM, histogram, or fit state.
// Video has a fixed six-clock pipeline irrespective of mode/detector status.
module mosaic_four_lane_video #(
    parameter integer P_IMG_W=960,P_IMG_H=540,P_DECIM=8,
    parameter integer P_RHO_BINS=256,P_RHO_OFF=104,
    parameter [23:0] P_DRAW_COLOR=24'h00ff00,
    parameter integer P_DRAW_THICKNESS=6,
    parameter integer P_PROCESS_VIEWS=0,
    parameter integer P_CAMERA_ONLY_LAYOUT=1,
    parameter integer P_M2_ONLY=0
)(
    input wire clk,rst_n,
    input wire [1:0] mode,
    input wire frame_start,
    input wire [23:0] rgb_in,
    // Detection always consumes rgb_in. Display processing is a separate
    // aligned plane; view changes never alter detector tokens or fit state.
    input wire [23:0] process_rgb_in,
    input wire [2:0] process_view,
    input wire [11:0] x,
    input wire [10:0] y,
    input wire de_in,hs_in,vs_in,pixel_valid_in,
    input wire [191:0] context_source_frames,
    input wire [5:0] context_source_valid,
    input wire [7:0] context_epoch,
    output wire [23:0] rgb_out,
    output wire de_out,hs_out,vs_out,
    output reg [3:0] active_l_valid,active_r_valid,
    output wire [63:0] vote_drop,
    output reg [11:0] bound_source,
    output wire [3:0] result_pulse,
    output wire [127:0] result_frame_ids,result_source_frames,
    output wire [11:0] result_sources,
    output wire [7:0] result_mode,
    output wire [3:0] result_tag_valid,result_left_valid,result_right_valid,
    output wire [191:0] result_endpoints
);
    reg [1:0] bound_mode;
    reg [3:0] bad_window,pending_new,pending_l_valid,pending_r_valid;
    reg signed [11:0] pending_lx1[0:3],pending_lx2[0:3],pending_rx1[0:3],pending_rx2[0:3];
    reg signed [11:0] active_lx1[0:3],active_lx2[0:3],active_rx1[0:3],active_rx2[0:3];
    wire [1:0] effective_mode=P_M2_ONLY ? 2'd2 :
        (P_CAMERA_ONLY_LAYOUT ? mode : (mode==2'd2 ? 2'd2 : 2'd1));
    wire mode_changed=(effective_mode!=bound_mode);
    wire dual_mode=P_CAMERA_ONLY_LAYOUT && (effective_mode!=2'd1 && effective_mode!=2'd2);
    wire right_half=x>=P_IMG_W;
    wire bottom_half=!dual_mode && y>=P_IMG_H;
    wire [1:0] slot={bottom_half,right_half};
    wire [10:0] local_x=right_half ? x-P_IMG_W : x;
    wire [10:0] local_y=dual_mode ? y>>1 : (bottom_half ? y-P_IMG_H : y);
    // One subtract into the draw APM input register. The original local_y
    // remains the detector/ROI coordinate, including camera row repetition.
    localparam signed [11:0] DRAW_HALF_BOTTOM=P_IMG_H;
    localparam signed [11:0] DRAW_FULL_BOTTOM=2*P_IMG_H;
    wire [10:0] draw_row=dual_mode ? y>>1 : y;
    wire signed [11:0] draw_bottom=bottom_half ? DRAW_FULL_BOTTOM : DRAW_HALF_BOTTOM;
    wire signed [11:0] draw_dy=draw_bottom-$signed({1'b0,draw_row});
    wire in_geometry=x<2*P_IMG_W && y<2*P_IMG_H;
    wire sample_row=!dual_mode || !y[0];
    wire [3:0] core_params_valid,core_l_valid,core_r_valid;
    wire signed [11:0] core_lx1[0:3],core_lx2[0:3],core_rx1[0:3],core_rx2[0:3];
    wire [63:0] core_frame_tag[0:3];
    wire [3:0] core_tag_valid;
    reg [31:0] composite_frame_id;
    reg [191:0] frame_source_frames;
    reg [5:0] frame_source_valid;
    wire [31:0] next_composite_frame_id=composite_frame_id+1'b1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            composite_frame_id<=0;frame_source_frames<=0;frame_source_valid<=0;
        end else if(frame_start) begin
            composite_frame_id<=next_composite_frame_id;
            frame_source_frames<=context_source_frames;
            frame_source_valid<=context_source_valid&{6{context_epoch==next_composite_frame_id[7:0]}};
        end
    end
    function automatic [11:0] sources_for_mode(input [1:0] m);
        if(P_M2_ONLY) sources_for_mode={3'd1,3'd0,3'd5,3'd4};
        else case(m)
            2'd1:sources_for_mode={3'd5,3'd4,3'd3,3'd2};
            2'd2:sources_for_mode={3'd1,3'd0,3'd5,3'd4};
            default:sources_for_mode=P_CAMERA_ONLY_LAYOUT ? {3'd7,3'd7,3'd1,3'd0} : {3'd5,3'd4,3'd3,3'd2};
        endcase
    endfunction
    genvar g;
    generate for(g=0;g<4;g=g+1) begin:g_lane
        wire enabled=!dual_mode || g<2;
        // Elaboration-constant rectangles avoid the shared geometry/slot
        // decode in the high-fanout advance path; all boundaries are unchanged.
        wire lane_x_selected=(g%2==0) ? (x<P_IMG_W) :
            ((x>=P_IMG_W) && (x<2*P_IMG_W));
        wire lane_y_selected=(g/2==0) ?
            (dual_mode ? (y<2*P_IMG_H) : (y<P_IMG_H)) :
            (!dual_mode && (y>=P_IMG_H) && (y<2*P_IMG_H));
        wire selected=de_in && lane_x_selected && lane_y_selected;
        // Same PIX edge and reset value as global bound_mode, with an
        // unconditional D=effective_mode. This local copy adds no mode delay.
        reg [1:0] local_bound_mode /* synthesis syn_preserve=1 */;
        always @(posedge clk or negedge rst_n)
            if(!rst_n) local_bound_mode<=P_M2_ONLY ? 2'd2 : (P_CAMERA_ONLY_LAYOUT ? 2'd0 : 2'd1);
            else local_bound_mode<=effective_mode;
        wire local_mode_changed=(effective_mode!=local_bound_mode);
        // SOF is a window-origin comparison, not subtract-then-zero logic.
        // g is an elaboration constant. Under this slot's unchanged advance,
        // this equals local_x==0 && local_y==0; dual y0/y1 both map to row0,
        // and the unchanged sample_row permits only y0 to be consumed.
        wire local_sof=(x==(g%2)*P_IMG_W) &&
            (dual_mode ? (y[10:1]==10'd0) : (y==(g/2)*P_IMG_H));
        // A failed window remains reset for the rest of this output frame.
        // Next frame_start releases it only after history/results were cleared.
        wire core_reset_request_n=rst_n && enabled && !local_mode_changed && !bad_window[g];
        // Local reset distribution breaks global-reset -> qualify gate ->
        // thousands of async-reset loads into two normally timed paths.
        // The request is already in this pixel domain; this is one ordinary
        // distribution FF, not a new asynchronous CDC synchronizer.
        reg core_reset_released /* synthesis syn_preserve=1 */;
        always @(posedge clk or negedge core_reset_request_n)
            if(!core_reset_request_n) core_reset_released<=1'b0;
            else core_reset_released<=1'b1;
        // Parallel physical reset branch for the gray FF/APM loads. Both
        // replicas assert from the same request and release on the same edge;
        // this does not add a token wait or another CDC stage.
        reg gray_reset_released /* synthesis syn_preserve=1 */;
        always @(posedge clk or negedge core_reset_request_n)
            if(!core_reset_request_n) gray_reset_released<=1'b0;
            else gray_reset_released<=1'b1;
        wire core_rst_n=core_reset_released;
        wire advance=selected && enabled && sample_row && core_reset_request_n && core_reset_released;
        wire [2:0] source_id=bound_source[g*3 +:3];
        wire [31:0] source_frame=(source_id<6)?frame_source_frames[source_id*32 +:32]:32'd0;
        wire source_tag_valid=(source_id<6) && frame_source_valid[source_id];
        wire result_enabled=core_reset_request_n && core_reset_released;
        assign result_pulse[g]=core_params_valid[g] && result_enabled;
        assign result_frame_ids[g*32 +:32]=core_frame_tag[g][63:32];
        assign result_source_frames[g*32 +:32]=core_frame_tag[g][31:0];
        assign result_sources[g*3 +:3]=source_id;
        assign result_mode[g*2 +:2]=bound_mode;
        assign result_tag_valid[g]=core_tag_valid[g] && result_enabled;
        assign result_left_valid[g]=core_l_valid[g] && core_tag_valid[g] && result_enabled;
        assign result_right_valid[g]=core_r_valid[g] && core_tag_valid[g] && result_enabled;
        assign result_endpoints[g*48 +:48]={core_rx2[g],core_rx1[g],core_lx2[g],core_lx1[g]};
        lane_detector_core #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_DECIM(P_DECIM),
            .P_RHO_BINS(P_RHO_BINS),.P_RHO_OFF(P_RHO_OFF)) u_detector(
            .clk(clk),.rst_n(core_rst_n),.gray_rst_n(gray_reset_released),.advance(advance),
            .s_data(rgb_in),.s_valid(pixel_valid_in),.s_x(local_x),.s_y(local_y),
            .s_sof(local_sof),.s_eol(local_x==P_IMG_W-1),
            .s_frame_tag({composite_frame_id,source_frame}),.s_tag_valid(source_tag_valid),
            .params_valid(core_params_valid[g]),.lane_l_valid(core_l_valid[g]),
            .lane_r_valid(core_r_valid[g]),.lane_l_x1(core_lx1[g]),.lane_l_x2(core_lx2[g]),
            .lane_r_x1(core_rx1[g]),.lane_r_x2(core_rx2[g]),.vote_drop(vote_drop[g*16 +:16]),
            .params_frame_tag(core_frame_tag[g]),.params_tag_valid(core_tag_valid[g])
        );
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                bad_window[g]<=0;pending_new[g]<=0;
                pending_l_valid[g]<=0;pending_r_valid[g]<=0;
                active_l_valid[g]<=0;active_r_valid[g]<=0;
                pending_lx1[g]<=0;pending_lx2[g]<=0;pending_rx1[g]<=0;pending_rx2[g]<=0;
                active_lx1[g]<=0;active_lx2[g]<=0;active_rx1[g]<=0;active_rx2[g]<=0;
            end else if(mode_changed) begin
                bad_window[g]<=0;pending_new[g]<=0;
                pending_l_valid[g]<=0;pending_r_valid[g]<=0;
                active_l_valid[g]<=0;active_r_valid[g]<=0;
            end else if(selected && !pixel_valid_in) begin
                bad_window[g]<=1;pending_new[g]<=0;
                pending_l_valid[g]<=0;pending_r_valid[g]<=0;
                active_l_valid[g]<=0;active_r_valid[g]<=0;
            end else begin
                if(frame_start) begin
                    bad_window[g]<=0;
                    if(bad_window[g] || !enabled) begin
                        active_l_valid[g]<=0;active_r_valid[g]<=0;
                    end else if(pending_new[g]) begin
                        active_l_valid[g]<=pending_l_valid[g];active_r_valid[g]<=pending_r_valid[g];
                        active_lx1[g]<=pending_lx1[g];active_lx2[g]<=pending_lx2[g];
                        active_rx1[g]<=pending_rx1[g];active_rx2[g]<=pending_rx2[g];
                    end
                    pending_new[g]<=0;
                end
                // frame_start takes an OLD pending snapshot. A simultaneous
                // new result remains pending for the NEXT boundary.
                if(core_params_valid[g] && !bad_window[g] && enabled) begin
                    pending_new[g]<=1;
                    pending_l_valid[g]<=core_l_valid[g];pending_r_valid[g]<=core_r_valid[g];
                    pending_lx1[g]<=core_lx1[g];pending_lx2[g]<=core_lx2[g];
                    pending_rx1[g]<=core_rx1[g];pending_rx2[g]<=core_rx2[g];
                end
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin bound_mode<=P_M2_ONLY ? 2 : (P_CAMERA_ONLY_LAYOUT ? 0 : 1);bound_source<=sources_for_mode(P_M2_ONLY ? 2 : 0);end
        else if(mode_changed) begin bound_mode<=effective_mode;bound_source<=sources_for_mode(effective_mode);end
    end
    wire draw_good=pixel_valid_in && in_geometry && !mode_changed && !bad_window[slot];
    wire show_lanes = !P_PROCESS_VIEWS || process_view==3'd0;
    wire [23:0] render_rgb = P_PROCESS_VIEWS ? process_rgb_in : rgb_in;
    mosaic_lane_draw #(.P_IMG_H(P_IMG_H),.P_COLOR(P_DRAW_COLOR),.P_THICKNESS(P_DRAW_THICKNESS)) u_draw(
        .clk(clk),.rst_n(rst_n),.rgb_in(render_rgb),.x(local_x),.y(local_y),.dy_in(draw_dy),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.pixel_valid_in(draw_good),
        .lane_l_valid(active_l_valid[slot] && show_lanes),.lane_r_valid(active_r_valid[slot] && show_lanes),
        .lane_l_x1(active_lx1[slot]),.lane_l_x2(active_lx2[slot]),
        .lane_r_x1(active_rx1[slot]),.lane_r_x2(active_rx2[slot]),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out)
    );
endmodule
