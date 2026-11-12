`timescale 1ns/1ps
// Legacy six-view DISPLAY preprocessing. It does not replace or tap the
// independent Gauss/Canny/Hough detectors. Continuous raster, one pixel/clk.
// Exact centre-packet latency: P_H_TOTAL + 9 clocks, including one source row
// and one source column. Only RGB565-expanded input colours are lossless.
module mosaic_process_views #(
    parameter integer P_IMG_W=960, P_IMG_H=540, P_H_TOTAL=2200,
    parameter integer P_THRESHOLD=120, P_EDGE_THRESHOLD=128,
    parameter integer P_CAMERA_ONLY_LAYOUT=1,
    parameter integer P_M2_ONLY=0
)(
    input wire clk,rst_n,
    input wire [1:0] layout_mode,
    input wire [2:0] view_mode,
    input wire [23:0] rgb_in,
    input wire [11:0] x_in,
    input wire [10:0] y_in,
    input wire de_in,hs_in,vs_in,frame_start_in,pixel_valid_in,
    output reg [23:0] original_rgb_out,view_rgb_out,
    output reg [11:0] x_out,
    output reg [10:0] y_out,
    output reg [1:0] layout_mode_out,
    output wire [2:0] view_mode_out,
    output reg de_out,hs_out,vs_out,frame_start_out,pixel_valid_out
);
    localparam integer BANK_DEPTH=(P_H_TOTAL+1)/2;
    localparam integer AW=$clog2(BANK_DEPTH);
    localparam integer CW=$clog2(P_H_TOTAL);
    localparam integer FW=$clog2(2*P_H_TOTAL+1);
    localparam integer Y_TOP=P_IMG_H*60/100, Y_BOT=P_IMG_H*95/100;
    localparam integer X_LT=P_IMG_W*40/100, X_RT=P_IMG_W*60/100;
    localparam integer X_LB=P_IMG_W*10/100;
    localparam integer ROI_DY=(Y_BOT>Y_TOP)?Y_BOT-Y_TOP:1;
    localparam [23:0] STEP_Q8=(X_LT-X_LB)*256/ROI_DY;

    wire [1:0] effective_layout=P_M2_ONLY ? 2'd2 :
        (P_CAMERA_ONLY_LAYOUT ? layout_mode : (layout_mode==2'd2 ? 2'd2 : 2'd1));
    wire dual=P_CAMERA_ONLY_LAYOUT && (effective_layout!=1 && effective_layout!=2);
    wire right_half=x_in>=P_IMG_W;
    wire bottom_half=!dual && y_in>=P_IMG_H;
    wire [11:0] local_x=right_half ? x_in-P_IMG_W : x_in;
    wire [10:0] local_y=dual ? y_in>>1 : (bottom_half ? y_in-P_IMG_H : y_in);
    wire [1:0] slot={bottom_half,right_half};
    wire border=local_x==0 || local_x==P_IMG_W-1 ||
        (dual ? (y_in==0 || y_in==2*P_IMG_H-1) : (local_y==0 || local_y==P_IMG_H-1));
    reg [23:0] roi_acc;
    reg [10:0] roi_prev_y;
    reg [1:0] roi_prev_layout;
    wire roi_first=de_in && x_in==0;
    wire roi_row_inside=local_y>=Y_TOP && local_y<=Y_BOT;
    wire roi_step=roi_first && local_y!=roi_prev_y;
    // Finish the constant increment before selecting it; keep local-y/step
    // controls out of the carry cone without adding a pixel-clock stage.
    wire [23:0] roi_acc_incremented /* synthesis syn_keep = 1 */;
    assign roi_acc_incremented=roi_acc+STEP_Q8;
    wire [23:0] roi_pixel_acc=!roi_row_inside || local_y==Y_TOP ? 24'd0 :
        (roi_step ? roi_acc_incremented : roi_acc);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin roi_acc<=0;roi_prev_y<=11'h7ff;roi_prev_layout<=0;end
        else if(frame_start_in) begin roi_acc<=0;roi_prev_y<=11'h7ff;roi_prev_layout<=effective_layout;end
        else if(roi_first) begin
            roi_acc<=roi_pixel_acc;roi_prev_y<=local_y;roi_prev_layout<=effective_layout;
        end
    end

    // Three-stage integer gray, with the same Q8 rounding as rgb2gray.
    reg [7:0] r1,g1,b1;
    reg [15:0] pr2,pg2,pb2;
    reg [7:0] gray3;
    reg [15:0] rgb1,rgb2,rgb3;
    reg [10:0] meta1,meta2,meta3;
    // ROI shares the existing three gray stages. Do not combine local-y
    // mapping, row-accumulator selection, bounds and both comparisons into
    // the input metadata FF: the original cone violated 148.5 MHz setup.
    reg [23:0] roi_acc1;
    reg [11:0] roi_x1,roi_x2;
    reg roi_row1,roi_row2,roi3;
    reg [31:0] roi_left2,roi_right2;
    wire [16:0] gray_sum={1'b0,pr2}+{1'b0,pg2}+{1'b0,pb2}+17'd128;
    reg [35:0] packet;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            r1<=0;g1<=0;b1<=0;pr2<=0;pg2<=0;pb2<=0;gray3<=0;
            rgb1<=0;rgb2<=0;rgb3<=0;meta1<=0;meta2<=0;meta3<=0;packet<=0;
            roi_acc1<=0;roi_x1<=0;roi_x2<=0;roi_row1<=0;roi_row2<=0;roi3<=0;
            roi_left2<=0;roi_right2<=0;
        end else begin
            r1<=rgb_in[23:16];g1<=rgb_in[15:8];b1<=rgb_in[7:0];
            rgb1<={rgb_in[23:19],rgb_in[15:10],rgb_in[7:3]};
            meta1<={slot,border,1'b0,effective_layout,pixel_valid_in,frame_start_in,vs_in,hs_in,de_in};
            roi_acc1<=roi_pixel_acc;roi_x1<=local_x;roi_row1<=roi_row_inside;
            pr2<=r1*77;pg2<=g1*150;pb2<=b1*29;
            rgb2<=rgb1;meta2<=meta1;
            roi_left2<=X_LT-roi_acc1[19:8];roi_right2<=X_RT+roi_acc1[19:8];
            roi_x2<=roi_x1;roi_row2<=roi_row1;
            gray3<=gray_sum[15:8];rgb3<=rgb2;meta3<=meta2;
            roi3<=roi_row2 && roi_x2>=roi_left2 && roi_x2<=roi_right2;
            packet<={meta3[10:8],gray3>=P_THRESHOLD,roi3,meta3[6:0],gray3,rgb3};
        end
    end
    // Packet bits: slot35:34, border33, binary32, ROI31, layout30:29,
    // quality28, SOF27, VS26, HS25, DE24, gray23:16, RGB56515:0.
    reg [35:0] even_lo[0:BANK_DEPTH-1],even_hi[0:BANK_DEPTH-1];
    reg [35:0] odd_lo[0:BANK_DEPTH-1],odd_hi[0:BANK_DEPTH-1];
    reg [35:0] rd_even_lo,rd_even_hi,rd_odd_lo,rd_odd_hi;
    reg [CW-1:0] column;
    reg write_odd,read_odd,read_high;
    reg [FW-1:0] filled;
    reg middle_ready,window_ready;
    reg [35:0] row_current;
    wire high_bank=column>=BANK_DEPTH;
    wire [CW-1:0] addr_full=high_bank ? column-BANK_DEPTH : column;
    wire [AW-1:0] addr=addr_full[AW-1:0];
    // One write per physical bank; no address reset or memory clearing.
    // Read-before-write retains both previous rows at the same column.
    always @(posedge clk) begin
        if(rst_n) begin
            if(!write_odd && !high_bank) even_lo[addr]<=packet;
            if(!write_odd && high_bank) even_hi[addr]<=packet;
            if(write_odd && !high_bank) odd_lo[addr]<=packet;
            if(write_odd && high_bank) odd_hi[addr]<=packet;
            rd_even_lo<=even_lo[addr];rd_even_hi<=even_hi[addr];
            rd_odd_lo<=odd_lo[addr];rd_odd_hi<=odd_hi[addr];
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            column<=0;write_odd<=0;read_odd<=0;read_high<=0;
            filled<=0;middle_ready<=0;window_ready<=0;row_current<=0;
        end else begin
            column<=column==P_H_TOTAL-1 ? 0 : column+1'b1;
            if(column==P_H_TOTAL-1) write_odd<=~write_odd;
            read_odd<=write_odd;read_high<=high_bank;row_current<=packet;
            if(filled<2*P_H_TOTAL) filled<=filled+1'b1;
            middle_ready<=filled>=P_H_TOTAL;window_ready<=filled>=2*P_H_TOTAL;
        end
    end
    wire [35:0] row_even=read_high ? rd_even_hi : rd_even_lo;
    wire [35:0] row_odd=read_high ? rd_odd_hi : rd_odd_lo;
    wire [35:0] row_top=read_odd ? row_odd : row_even;
    wire [35:0] row_middle=read_odd ? row_even : row_odd;
    reg [35:0] top_left,top_center,mid_left,mid_center,bot_left,bot_center;
    function automatic neighbor_ok(input [35:0] p,input [35:0] c);
        neighbor_ok=p[24] && p[28] && p[35:34]==c[35:34] && p[30:29]==c[30:29];
    endfunction
    wire window_ok=window_ready && !mid_center[33] &&
        neighbor_ok(top_left,mid_center) && neighbor_ok(top_center,mid_center) && neighbor_ok(row_top,mid_center) &&
        neighbor_ok(mid_left,mid_center) && neighbor_ok(mid_center,mid_center) && neighbor_ok(row_middle,mid_center) &&
        neighbor_ok(bot_left,mid_center) && neighbor_ok(bot_center,mid_center) && neighbor_ok(row_current,mid_center);
    // CSA_WEIGHTED_SUM_BEGIN: 8-bit a + 2*b + c fits in ten bits (max1020).
    // Compress three operands without a carry chain, then propagate once.
    // Keep these named combinational nodes so ADS cannot reassociate them
    // into two dependent full-width additions on the RAM-return path.
    wire [7:0] weighted_a[0:3],weighted_b[0:3],weighted_c[0:3];
    wire [9:0] weighted_sum[0:3];
    assign weighted_a[0]=top_left[23:16];
    assign weighted_b[0]=mid_left[23:16];
    assign weighted_c[0]=bot_left[23:16];
    assign weighted_a[1]=row_top[23:16];
    assign weighted_b[1]=row_middle[23:16];
    assign weighted_c[1]=row_current[23:16];
    assign weighted_a[2]=top_left[23:16];
    assign weighted_b[2]=top_center[23:16];
    assign weighted_c[2]=row_top[23:16];
    assign weighted_a[3]=bot_left[23:16];
    assign weighted_b[3]=bot_center[23:16];
    assign weighted_c[3]=row_current[23:16];
    genvar sum_direction;
    generate for(sum_direction=0;sum_direction<4;sum_direction=sum_direction+1) begin:g_weighted_sum
        wire [9:0] a={2'b0,weighted_a[sum_direction]};
        wire [9:0] b={1'b0,weighted_b[sum_direction],1'b0};
        wire [9:0] c={2'b0,weighted_c[sum_direction]};
        wire [9:0] csa_bits /* synthesis syn_keep = 1 */;
        wire [9:0] csa_carry /* synthesis syn_keep = 1 */;
        assign csa_bits=a^b^c;
        assign csa_carry=((a&b)|(a&c)|(b&c))<<1;
        assign weighted_sum[sum_direction]=csa_bits+csa_carry;
    end endgenerate
    // CSA_WEIGHTED_SUM_END
    reg [9:0] sum_left,sum_right,sum_top,sum_bottom;
    reg valid_sum,valid_grad,valid_mag;
    reg signed [10:0] gx,gy;
    reg [7:0] sobel_value;
    reg edge_value;
    reg [35:0] center_sum,center_grad,center_mag;
    wire [10:0] abs_x=gx[10] ? -gx : gx;
    wire [10:0] abs_y=gy[10] ? -gy : gy;
    wire [11:0] magnitude={1'b0,abs_x}+{1'b0,abs_y};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            top_left<=0;top_center<=0;mid_left<=0;mid_center<=0;bot_left<=0;bot_center<=0;
            sum_left<=0;sum_right<=0;sum_top<=0;sum_bottom<=0;
            valid_sum<=0;valid_grad<=0;valid_mag<=0;gx<=0;gy<=0;sobel_value<=0;edge_value<=0;
            center_sum<=0;center_grad<=0;center_mag<=0;
        end else begin
            top_left<=top_center;top_center<=row_top;
            mid_left<=mid_center;mid_center<=row_middle;
            bot_left<=bot_center;bot_center<=row_current;
            sum_left<=weighted_sum[0];
            sum_right<=weighted_sum[1];
            sum_top<=weighted_sum[2];
            sum_bottom<=weighted_sum[3];
            center_sum<=middle_ready ? mid_center : 36'd0;valid_sum<=window_ok;
            gx<=$signed({1'b0,sum_right})-$signed({1'b0,sum_left});
            gy<=$signed({1'b0,sum_bottom})-$signed({1'b0,sum_top});
            center_grad<=center_sum;valid_grad<=valid_sum;
            sobel_value<=valid_grad && center_grad[31] ? (magnitude>255 ? 8'd255 : magnitude[7:0]) : 8'd0;
            edge_value<=valid_grad && center_grad[31] && magnitude>=P_EDGE_THRESHOLD;
            center_mag<=center_grad;valid_mag<=valid_grad;
        end
    end
    wire [23:0] original_center={center_mag[15:11],center_mag[15:13],
        center_mag[10:5],center_mag[10:9],center_mag[4:0],center_mag[4:2]};
    reg [2:0] active_view;
    assign view_mode_out=active_view;
    reg [11:0] out_next_x;
    reg [10:0] out_next_y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            original_rgb_out<=0;view_rgb_out<=0;x_out<=0;y_out<=0;layout_mode_out<=0;
            de_out<=0;hs_out<=0;vs_out<=0;frame_start_out<=0;pixel_valid_out<=0;
            active_view<=0;out_next_x<=0;out_next_y<=0;
        end else begin
            original_rgb_out<=original_center;
            case(active_view)
                1:view_rgb_out<={3{center_mag[23:16]}};
                2:view_rgb_out<={24{center_mag[32]}};
                3:view_rgb_out<={24{center_mag[32] && center_mag[31]}};
                4:view_rgb_out<={3{sobel_value}};
                5:view_rgb_out<=edge_value ? 24'h00ff00 : original_center;
                default:view_rgb_out<=original_center;
            endcase
            de_out<=center_mag[24];hs_out<=center_mag[25];vs_out<=center_mag[26];
            frame_start_out<=center_mag[27];pixel_valid_out<=center_mag[28];layout_mode_out<=center_mag[30:29];
            x_out<=center_mag[24] ? out_next_x : 12'd0;
            y_out<=center_mag[24] ? out_next_y : 11'd0;
            if(center_mag[27]) begin
                active_view<=view_mode<6 ? view_mode : 3'd0;
                out_next_x<=0;out_next_y<=0;
            end else if(center_mag[24]) begin
                if(out_next_x==2*P_IMG_W-1) begin
                    out_next_x<=0;out_next_y<=out_next_y==2*P_IMG_H-1 ? 0 : out_next_y+1'b1;
                end else out_next_x<=out_next_x+1'b1;
            end
        end
    end
endmodule
