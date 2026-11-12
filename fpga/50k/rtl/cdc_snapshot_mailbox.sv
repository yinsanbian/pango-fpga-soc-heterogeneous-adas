`timescale 1ns/1ps
// Bundled-data mailbox. Both resets MUST share their asynchronous assertion;
// each is synchronously released in its own domain by the caller. Independent
// one-sided reset is not supported by the toggle protocol. The held source
// word is stable from send acceptance until the acknowledgement returns.
module cdc_snapshot_mailbox #(
    parameter integer W=32,
    parameter integer P_LOCAL_CAPTURE_RESET_REDUNDANCY=0
)(
    input wire src_clk,src_rst_n,
    input wire src_send,
    input wire [W-1:0] src_data,
    output wire src_ready,
    input wire dst_clk,dst_rst_n,
    output reg [W-1:0] dst_data,
    output reg dst_pulse
);
    reg [W-1:0] held_data;
    reg req_toggle,ack_toggle;
    (* PAP_ASYNC_REG = 1 *) reg req_meta,req_sync;
    (* PAP_ASYNC_REG = 1 *) reg ack_meta,ack_sync;
    reg pending_req;
    reg [1:0] settle;
    assign src_ready=src_rst_n&&(ack_sync==req_toggle);

    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin
            held_data<=0;req_toggle<=0;ack_meta<=0;ack_sync<=0;
        end else begin
            ack_meta<=ack_toggle;ack_sync<=ack_meta;
            if(src_send && (P_LOCAL_CAPTURE_RESET_REDUNDANCY ? (ack_sync==req_toggle) : src_ready)) begin
                held_data<=src_data;req_toggle<=!req_toggle;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if(!dst_rst_n) begin
            req_meta<=0;req_sync<=0;ack_toggle<=0;pending_req<=0;
            settle<=0;dst_data<=0;dst_pulse<=0;
        end else begin
            req_meta<=req_toggle;req_sync<=req_meta;dst_pulse<=0;
            if(settle!=0) begin
                if(settle==1) begin
                    dst_data<=held_data;dst_pulse<=1;
                    ack_toggle<=pending_req;settle<=0;
                end else settle<=settle-1'b1;
            end else if(req_sync!=ack_toggle) begin
                pending_req<=req_sync;
                // Capture only after two additional destination edges.
                settle<=2;
            end
        end
    end
endmodule
