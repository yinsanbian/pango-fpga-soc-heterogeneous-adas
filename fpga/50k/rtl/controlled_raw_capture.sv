`timescale 1ns/1ps
// Standalone observer only. All ports belong to clk; rst_n releases locally.
// There is deliberately no ready/CE output to any production data path.
module controlled_raw_capture #(
    parameter integer TIMEOUT_CYCLES = 125000000,
    parameter integer P_WARMUP_CYCLES = 0,
    parameter [63:0] SYNC_TAG = 64'hD369A51CE742B806
)(
    input wire clk, rst_n,
    input wire [7:0] data,
    input wire dv, er,
    input wire [3:0] session_id,
    input wire [2:0] preview_page,
    output reg [127:0] page_bits,
    output reg page_valid,
    output reg done,
    output reg [3:0] matched_mask,
    output reg timed_out, fallback,
    output wire fallback_waiting, no_ctl_activity,
    output reg [6:0] capture_samples
);
    localparam [1:0] SEARCH=0, WAIT_ACTIVITY=1, TAIL=2, FROZEN=3;
    localparam integer TIMEOUT_BITS = $clog2(TIMEOUT_CYCLES+1);
    reg [1:0] state;
    reg [TIMEOUT_BITS-1:0] search_cycles;
    reg [6:0] history_count, tail_remaining;
    reg activity_previous, activity_seen;
    reg session_latched;
    reg [3:0] token;
    reg [9:0] samples [0:95];
    wire [9:0] incoming={er,dv,data};
    wire activity=dv || er;
    // Settle only this passive observer. Count actual local RX edges; a stopped
    // clock pauses the wait. Do not reset/gate the MAC, FIFO or mailbox session.
    // Default zero elaborates no counter and retains the original behaviour.
    wire warmup_armed;
    generate if(P_WARMUP_CYCLES>0) begin:g_warmup
        localparam integer WARMUP_BITS=$clog2(P_WARMUP_CYCLES+1);
        reg [WARMUP_BITS-1:0] count;
        assign warmup_armed=(count==P_WARMUP_CYCLES);
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) count<=0;
            else if(!warmup_armed) count<=count+1'b1;
        end
    end else begin:g_no_warmup
        assign warmup_armed=1'b1;
    end endgenerate
    wire [63:0] sequence0,sequence1,sequence2,sequence3;
    wire [3:0] tag_hits;
    genvar b;
    generate for(b=0;b<8;b=b+1) begin:g_tag
        // samples[95] is the previous clock, samples[89] seven clocks ago.
        wire [7:0] current_byte;
        if(b==7)assign current_byte=data;
        else assign current_byte=samples[89+b][7:0];
        wire [7:0] previous_byte=samples[88+b][7:0];
        assign sequence0[63-b*8 -:8]=current_byte;
        assign sequence1[63-b*8 -:8]={current_byte[3:0],current_byte[7:4]};
        assign sequence2[63-b*8 -:8]={current_byte[3:0],previous_byte[7:4]};
        assign sequence3[63-b*8 -:8]={current_byte[7:4],previous_byte[3:0]};
    end endgenerate
    assign tag_hits={(sequence3==SYNC_TAG),(sequence2==SYNC_TAG),
                     (sequence1==SYNC_TAG),(sequence0==SYNC_TAG)};

    // Fixed FF shifts; payload bits need no reset. Valid history/session gates
    // prevent stale/uninitialised data becoming a published capture.
    integer i;
    always @(posedge clk) begin
        if(rst_n && state!=FROZEN) begin
            for(i=0;i<95;i=i+1) samples[i]<=samples[i+1];
            samples[95]<=incoming;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=SEARCH; search_cycles<=0; history_count<=0;
            tail_remaining<=0; activity_previous<=0; activity_seen<=0;
            session_latched<=0; token<=0;
            done<=0; matched_mask<=0; timed_out<=0; fallback<=0;
            capture_samples<=0;
        end else if(!warmup_armed) begin
            // None of the pre-arm history/activity can trigger, time out or
            // form a published capture. Payload FFs still shift unfiltered.
            state<=SEARCH; search_cycles<=0; history_count<=0;
            tail_remaining<=0; activity_previous<=0; activity_seen<=0;
            session_latched<=0; token<=0;
            done<=0; matched_mask<=0; timed_out<=0; fallback<=0;
            capture_samples<=0;
        end else begin
            if(!session_latched) begin token<=session_id;session_latched<=1;end
            if(state!=FROZEN) begin
                if(history_count<96)history_count<=history_count+1'b1;
                activity_previous<=activity;
                if(activity)activity_seen<=1;
            end
            case(state)
                SEARCH: begin
                    // Current input plus 31 prior words make the 32-word head.
                    // Matching on the exact timeout edge has priority.
                    if(history_count>=31 && |tag_hits) begin
                        matched_mask<=tag_hits;
                        tail_remaining<=64;state<=TAIL;
                    end else if(search_cycles==TIMEOUT_CYCLES-1) begin
                        timed_out<=1;state<=WAIT_ACTIVITY;
                    end else search_cycles<=search_cycles+1'b1;
                end
                WAIT_ACTIVITY: begin
                    // This is the NEXT activity edge after timeout, not an old
                    // last-DV pointer into already overwritten circular data.
                    if(activity && !activity_previous) begin
                        fallback<=1;tail_remaining<=64;state<=TAIL;
                    end
                end
                TAIL: begin
                    if(tail_remaining==1) begin
                        tail_remaining<=0;state<=FROZEN;done<=1;
                        capture_samples<=fallback ? 80 : 96;
                    end else tail_remaining<=tail_remaining-1'b1;
                end
                default: begin end
            endcase
        end
    end
    assign fallback_waiting=(state==WAIT_ACTIVITY);
    assign no_ctl_activity=timed_out && !activity_seen;

    wire [959:0] chronological;
    generate for(b=0;b<96;b=b+1) begin:g_flat
        assign chronological[959-b*10 -:10]=samples[b];
    end endgenerate
    // Matched block=32 predecessors(including trigger)+64 later samples.
    // Fallback publishes only its final 16+64 samples, zeroing unused slots.
    wire [959:0] visible=fallback ? {chronological[799:0],160'd0} : chronological;
    reg [119:0] page_data;
    always @* begin
        case(preview_page)
            0:page_data=visible[959:840];
            1:page_data=visible[839:720];
            2:page_data=visible[719:600];
            3:page_data=visible[599:480];
            4:page_data=visible[479:360];
            5:page_data=visible[359:240];
            6:page_data=visible[239:120];
            default:page_data=visible[119:0];
        endcase
    end
    // Synchronous one-clock preview. Header and payload form one atomic word.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin page_bits<=0;page_valid<=0;end
        else begin
            page_bits<={preview_page,done,token,(done ? page_data : 120'd0)};
            page_valid<=done;
        end
    end
endmodule
