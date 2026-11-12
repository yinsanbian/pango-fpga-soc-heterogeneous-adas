`timescale 1ns/1ps
// One fixed six-register pixel pipeline.  Intersections use the CURRENT
// source row, so the two repeated rows of camera mode have identical lines.
// No video backpressure, RAM, derived clock, or predictive row-end state.
module mosaic_lane_draw #(
    parameter integer P_IMG_H=540,
    parameter [23:0] P_COLOR=24'h00ff00,
    parameter integer P_THICKNESS=6
)(
    input wire clk,rst_n,
    input wire [23:0] rgb_in,
    input wire [10:0] x,y,
    // Signed distance from the source bottom, computed directly by the
    // caller's coordinate map. Avoid local-row subtract then bottom subtract.
    input wire signed [11:0] dy_in,
    input wire de_in,hs_in,vs_in,pixel_valid_in,
    input wire lane_l_valid,lane_r_valid,
    input wire signed [11:0] lane_l_x1,lane_l_x2,lane_r_x1,lane_r_x2,
    output reg [23:0] rgb_out,
    output reg de_out,hs_out,vs_out
);
    localparam integer Y_TOP=(P_IMG_H*6)/10;
    localparam integer DY=P_IMG_H-Y_TOP;
    localparam integer KSHIFT=19;
    localparam integer K_VALUE=(1<<KSHIFT)/DY;
    localparam integer KW=$clog2(K_VALUE+1)+1;
    localparam signed [KW-1:0] K=K_VALUE;
    localparam [KW-2:0] K_UNSIGNED=K_VALUE;
    localparam signed [14:0] HALF=(P_THICKNESS+1)/2;
    localparam integer LOW_PRODUCT_W=18+KW-1;
    localparam integer HIGH_PRODUCT_W=7+KW;
    reg [23:0] pixels[0:4];
    reg [10:0] xs[0:3];
    reg [4:0] de_pipe,hs_pipe,vs_pipe;
    reg [3:0] left_enable,right_enable;
    reg signed [11:0] left_base[0:2],right_base[0:2];
    reg signed [12:0] s1_ldx,s1_rdx;
    reg signed [11:0] s1_dy;
    reg signed [24:0] s2_lnum,s2_rnum;
    reg [LOW_PRODUCT_W-1:0] s3_llo,s3_rlo;
    reg signed [HIGH_PRODUCT_W-1:0] s3_lhi,s3_rhi;
    // N=unsigned(N[17:0])+signed(N[24:18])*2^18.  Splitting at
    // the native APM input width removes the unregistered DSP cascade.
    // floor(N*K/2^19)=(hi_product>>>1)+(lo_product>>19)+carry;
    // carry is exact for both signs, including negative odd hi_product.
    wire [13:0] l_low_q=s3_llo>>KSHIFT;
    wire [13:0] r_low_q=s3_rlo>>KSHIFT;
    wire signed [13:0] l_high_q=s3_lhi>>>1;
    wire signed [13:0] r_high_q=s3_rhi>>>1;
    wire [13:0] l_carry={13'b0,s3_lhi[0] && s3_llo[KSHIFT-1]};
    wire [13:0] r_carry={13'b0,s3_rhi[0] && s3_rlo[KSHIFT-1]};
    reg signed [13:0] s4_lx,s4_rx;
    reg s5_on;
    wire signed [14:0] diff_l=$signed({4'b0000,xs[3]})-$signed({s4_lx[13],s4_lx});
    wire signed [14:0] diff_r=$signed({4'b0000,xs[3]})-$signed({s4_rx[13],s4_rx});
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0;i<5;i=i+1) pixels[i]<=0;
            for(i=0;i<4;i=i+1) xs[i]<=0;
            for(i=0;i<3;i=i+1) begin left_base[i]<=0;right_base[i]<=0;end
            de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
            left_enable<=0;right_enable<=0;
            s1_ldx<=0;s1_rdx<=0;s1_dy<=0;
            s2_lnum<=0;s2_rnum<=0;s3_llo<=0;s3_rlo<=0;s3_lhi<=0;s3_rhi<=0;
            s4_lx<=0;s4_rx<=0;s5_on<=0;
            rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;
        end else begin
            // S1: narrow endpoint subtraction, current row, aligned metadata.
            pixels[0]<=rgb_in;xs[0]<=x;
            de_pipe[0]<=de_in;hs_pipe[0]<=hs_in;vs_pipe[0]<=vs_in;
            s1_ldx<=$signed({lane_l_x2[11],lane_l_x2})-$signed({lane_l_x1[11],lane_l_x1});
            s1_rdx<=$signed({lane_r_x2[11],lane_r_x2})-$signed({lane_r_x1[11],lane_r_x1});
            s1_dy<=dy_in;
            left_base[0]<=lane_l_x1;right_base[0]<=lane_r_x1;
            left_enable[0]<=de_in && pixel_valid_in && lane_l_valid && y>=Y_TOP && y<P_IMG_H;
            right_enable[0]<=de_in && pixel_valid_in && lane_r_valid && y>=Y_TOP && y<P_IMG_H;
            // S2: one narrow variable multiplication per side.
            s2_lnum<=s1_dy*s1_ldx;s2_rnum<=s1_dy*s1_rdx;
            // S3: each product fits one native 18x18 APM at 960x540.
            // The low field is UNSIGNED; only the seven-bit high field has sign.
            s3_llo<=s2_lnum[17:0]*K_UNSIGNED;
            s3_rlo<=s2_rnum[17:0]*K_UNSIGNED;
            s3_lhi<=$signed(s2_lnum[24:18])*K;
            s3_rhi<=$signed(s2_rnum[24:18])*K;
            // S4: exact Q19 recombination, shortened to the stored 14 bits.
            // Discarded upper bits match the original signed14 assignment.
            s4_lx<=$signed({{2{left_base[2][11]}},left_base[2]})
                      +l_high_q+$signed(l_low_q)+$signed(l_carry);
            s4_rx<=$signed({{2{right_base[2][11]}},right_base[2]})
                      +r_high_q+$signed(r_low_q)+$signed(r_carry);
            // S5: signed band comparison avoids subtract/abs/add carry chains.
            s5_on<=(left_enable[3] && diff_l>=-HALF && diff_l<=HALF)
                 || (right_enable[3] && diff_r>=-HALF && diff_r<=HALF);
            // S6: final video register, including every blanking pixel.
            rgb_out<=s5_on ? P_COLOR : pixels[4];
            de_out<=de_pipe[4];hs_out<=hs_pipe[4];vs_out<=vs_pipe[4];
            for(i=1;i<5;i=i+1) begin
                pixels[i]<=pixels[i-1];
                de_pipe[i]<=de_pipe[i-1];hs_pipe[i]<=hs_pipe[i-1];vs_pipe[i]<=vs_pipe[i-1];
            end
            for(i=1;i<4;i=i+1) begin
                xs[i]<=xs[i-1];left_enable[i]<=left_enable[i-1];right_enable[i]<=right_enable[i-1];
            end
            for(i=1;i<3;i=i+1) begin
                left_base[i]<=left_base[i-1];right_base[i]<=right_base[i-1];
            end
        end
    end
endmodule
