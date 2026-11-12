`timescale 1ns/1ps
// One-shot bundled-data CDC for the immutable SCCB readback snapshot.
// Producer contract: all 120 bits settle for multiple SCCB phases before
// src_done rises and stay unchanged while src_done is high. This is not a
// bridge for a freely changing bus. The source may rewrite after done drops;
// the consumer hides the old snapshot after observing that drop.
module camera_readback_bridge(
    input wire [119:0] src_data,
    input wire src_done,
    input wire pix_clk,pix_rst_n,
    output reg [119:0] data_snapshot,
    output reg valid
);
    (* PAP_ASYNC_REG=1 *) reg done_meta,done_sync;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin
            done_meta<=0;done_sync<=0;
            data_snapshot<=0;valid<=0;
        end else begin
            done_meta<=src_done;
            done_sync<=done_meta;
            // Use only the second synchronizer stage. Capture on the next
            // destination edge after done_sync rises, once per done interval.
            if(!done_sync) valid<=0;
            else if(!valid) begin
                data_snapshot<=src_data;
                valid<=1;
            end
        end
    end
endmodule
