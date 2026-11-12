`timescale 1ns/1ps
// One displayed source, in the existing 148.5 MHz pixel domain. Window tokens
// advance the spatial filters; the histogram and divider continue every clock.
// Detection finishes during the NEXT input frame. The caller commits the
// resulting endpoints at a display frame boundary and clears on source change.
module lane_detector_core #(
    parameter P_IMG_W=960, P_IMG_H=540, P_XW=11, P_YW=11,
    parameter P_DECIM=8, P_RHO_BINS=256, P_RHO_OFF=104,
    parameter P_THR_LOW=50, P_THR_HIGH=150, P_MIN_WEIGHT=16
)(
    input wire clk, rst_n, gray_rst_n, advance,
    input wire [23:0] s_data,
    input wire s_valid,
    input wire [P_XW-1:0] s_x,
    input wire [P_YW-1:0] s_y,
    input wire s_sof, s_eol,
    // Metadata only: never changes numerical processing or video cadence.
    input wire [63:0] s_frame_tag,
    input wire s_tag_valid,
    output wire params_valid, lane_l_valid, lane_r_valid,
    output wire signed [P_XW:0] lane_l_x1, lane_l_x2,
    output wire signed [P_XW:0] lane_r_x1, lane_r_x2,
    output wire [15:0] vote_drop,
    output wire [63:0] params_frame_tag,
    output wire params_tag_valid
);
    wire [7:0] gray, blur;
    wire [11:0] magnitude, suppressed;
    wire [1:0] direction;
    wire edge_pixel, roi_edge;
    wire [5:0] valid_s, sof_s, eol_s;
    wire [P_XW-1:0] x_s[0:5];
    wire [P_YW-1:0] y_s[0:5];

    rgb2gray u_gray (
        .clk(clk),.rst_n(gray_rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .s_axis_tdata(s_data),.s_axis_tvalid(s_valid),.s_axis_tx(s_x),.s_axis_ty(s_y),
        .s_axis_tuser(s_sof),.s_axis_tlast(s_eol),
        .m_axis_tdata(gray),.m_axis_tvalid(valid_s[0]),.m_axis_tx(x_s[0]),.m_axis_ty(y_s[0]),
        .m_axis_tuser(sof_s[0]),.m_axis_tlast(eol_s[0])
    );
    gauss5x5 #(.P_IMG_W(P_IMG_W),.P_XW(P_XW),.P_YW(P_YW)) u_gauss (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .s_axis_tdata(gray),.s_axis_tvalid(valid_s[0]),.s_axis_tx(x_s[0]),.s_axis_ty(y_s[0]),
        .s_axis_tuser(sof_s[0]),.s_axis_tlast(eol_s[0]),
        .m_axis_tdata(blur),.m_axis_tvalid(valid_s[1]),.m_axis_tx(x_s[1]),.m_axis_ty(y_s[1]),
        .m_axis_tuser(sof_s[1]),.m_axis_tlast(eol_s[1])
    );
    sobel_3x3 #(.P_IMG_W(P_IMG_W),.P_XW(P_XW),.P_YW(P_YW)) u_sobel (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .s_axis_tdata(blur),.s_axis_tvalid(valid_s[1]),.s_axis_tx(x_s[1]),.s_axis_ty(y_s[1]),
        .s_axis_tuser(sof_s[1]),.s_axis_tlast(eol_s[1]),
        .m_axis_tdata(magnitude),.m_axis_tdir(direction),.m_axis_tvalid(valid_s[2]),
        .m_axis_tx(x_s[2]),.m_axis_ty(y_s[2]),.m_axis_tuser(sof_s[2]),.m_axis_tlast(eol_s[2])
    );
    canny_nms #(.P_IMG_W(P_IMG_W),.P_XW(P_XW),.P_YW(P_YW)) u_nms (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .s_axis_tdata(magnitude),.s_axis_tdir(direction),.s_axis_tvalid(valid_s[2]),
        .s_axis_tx(x_s[2]),.s_axis_ty(y_s[2]),.s_axis_tuser(sof_s[2]),.s_axis_tlast(eol_s[2]),
        .m_axis_tdata(suppressed),.m_axis_tvalid(valid_s[3]),.m_axis_tx(x_s[3]),.m_axis_ty(y_s[3]),
        .m_axis_tuser(sof_s[3]),.m_axis_tlast(eol_s[3])
    );
    canny_hyst #(.P_IMG_W(P_IMG_W),.P_XW(P_XW),.P_YW(P_YW)) u_hyst (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .cfg_thr_low(P_THR_LOW[11:0]),.cfg_thr_high(P_THR_HIGH[11:0]),
        .s_axis_tdata(suppressed),.s_axis_tvalid(valid_s[3]),.s_axis_tx(x_s[3]),.s_axis_ty(y_s[3]),
        .s_axis_tuser(sof_s[3]),.s_axis_tlast(eol_s[3]),
        .m_axis_tdata(edge_pixel),.m_axis_tvalid(valid_s[4]),.m_axis_tx(x_s[4]),.m_axis_ty(y_s[4]),
        .m_axis_tuser(sof_s[4]),.m_axis_tlast(eol_s[4])
    );
    roi_mask #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_XW(P_XW),.P_YW(P_YW)) u_roi (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(advance),.s_axis_tready(),
        .s_axis_tdata(edge_pixel),.s_axis_tvalid(valid_s[4]),.s_axis_tx(x_s[4]),.s_axis_ty(y_s[4]),
        .s_axis_tuser(sof_s[4]),.s_axis_tlast(eol_s[4]),
        .m_axis_tdata(roi_edge),.m_axis_tvalid(valid_s[5]),.m_axis_tx(x_s[5]),.m_axis_ty(y_s[5]),
        .m_axis_tuser(sof_s[5]),.m_axis_tlast(eol_s[5])
    );
    wire peak_valid, peak_ready,hough_scan_start;
    wire [5:0] peak_theta;
    wire signed [11:0] peak_rho;
    wire [7:0] peak_votes;
    wire [7:0] peak_strength;
    reg [63:0] input_tag,accum_tag,closing_tag,scan_tag,fit_tag;
    reg input_tag_valid,accum_tag_valid,closing_tag_valid,scan_tag_valid,fit_tag_valid;
    reg roi_sof_pending;
    wire roi_sof=valid_s[5] && advance && sof_s[5];
    assign params_frame_tag=fit_tag;
    assign params_tag_valid=fit_tag_valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            input_tag<=0;accum_tag<=0;closing_tag<=0;scan_tag<=0;fit_tag<=0;
            input_tag_valid<=0;accum_tag_valid<=0;closing_tag_valid<=0;
            scan_tag_valid<=0;fit_tag_valid<=0;roi_sof_pending<=0;
        end else begin
            if(advance && s_valid && s_sof) begin
                input_tag<=s_frame_tag;input_tag_valid<=s_tag_valid;
            end
            roi_sof_pending<=roi_sof;
            if(roi_sof) begin
                // This SOF closes the OLD histogram, not the incoming frame.
                closing_tag<=accum_tag;closing_tag_valid<=accum_tag_valid;
                accum_tag<=input_tag;accum_tag_valid<=input_tag_valid;
            end
            // A SOF ignored in CLEAR/SCAN cannot start a complete accumulation
            // epoch. Do not attribute a later partial histogram to that frame.
            if(roi_sof_pending && !hough_scan_start) accum_tag_valid<=0;
            if(hough_scan_start) begin
                scan_tag<=closing_tag;scan_tag_valid<=closing_tag_valid;
            end
            if(peak_valid && peak_ready && peak_theta==0) begin
                fit_tag<=scan_tag;fit_tag_valid<=scan_tag_valid;
            end
        end
    end
    hough_acc #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_XW(P_XW),.P_YW(P_YW),
        .P_DECIM(P_DECIM),.P_RHO_BINS(P_RHO_BINS),.P_RHO_OFF(P_RHO_OFF),
        .P_MIN_WINDOW_VOTES(P_MIN_WEIGHT)) u_hough (
        .clk(clk),.rst_n(rst_n),.m_axis_tready(1'b1),.s_axis_tready(),
        .s_axis_tdata(roi_edge),.s_axis_tvalid(valid_s[5] && advance),
        .s_axis_tx(x_s[5]),.s_axis_ty(y_s[5]),.s_axis_tuser(sof_s[5]),.s_axis_tlast(eol_s[5]),
        .m_peak_valid(peak_valid),.m_peak_theta(peak_theta),.m_peak_rho(peak_rho),
        .m_peak_votes(peak_votes),.m_peak_strength(peak_strength),
        .m_peak_ready(peak_ready),.o_vote_drop(vote_drop),.o_scan_start(hough_scan_start)
    );
    lane_fit #(.P_IMG_W(P_IMG_W),.P_IMG_H(P_IMG_H),.P_XW(P_XW),.P_DECIM(P_DECIM)) u_fit (
        .clk(clk),.rst_n(rst_n),.s_peak_valid(peak_valid),.s_peak_theta(peak_theta),
        .s_peak_rho(peak_rho),.s_peak_votes(peak_votes),.s_peak_strength(peak_strength),
        .s_peak_ready(peak_ready),
        .cfg_min_weight(P_MIN_WEIGHT[15:0]),.o_lane_l_valid(lane_l_valid),.o_lane_r_valid(lane_r_valid),
        .o_lane_l_x1(lane_l_x1),.o_lane_l_x2(lane_l_x2),
        .o_lane_r_x1(lane_r_x1),.o_lane_r_x2(lane_r_x2),.o_params_valid(params_valid)
    );
endmodule
