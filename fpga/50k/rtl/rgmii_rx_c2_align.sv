`timescale 1ns/1ps
// Module : rgmii_rx_c2_align
// Target : SYS-NET1-C2; board-proven adjacent IDDR slot pairing, N1 only.
// LATENCY: 0 cycles of additional output registers @ 125MHz; 1 raw-cycle history.
// This is a non-backpressured GMII tuple interface, not a pixel AXIS pipeline.
// Existing IDDR/output FFs and the receiving MAC remain the register boundaries.
// Reset must assert asynchronously and release synchronously in this same domain.
module rgmii_rx_c2_align(
    input wire clk,
    input wire rst_n,
    input wire [7:0] raw_data,
    input wire raw_dv,
    input wire raw_er,
    output wire [7:0] data_out,
    output wire dv_out,
    output wire er_out
);
    reg [3:0] previous_high;
    reg previous_fall;
    reg armed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_high <= 4'd0;
            previous_fall <= 1'b0;
            armed <= 1'b0;
        end else begin
            previous_high <= raw_data[7:4];
            previous_fall <= raw_dv ^ raw_er;
            // Both raw CTL samples must be idle before a new RX session.
            // A reset/relock in a frame cannot publish its truncated suffix.
            if (!raw_dv && !raw_er) armed <= 1'b1;
        end
    end

    assign data_out = {raw_data[3:0], previous_high};
    assign dv_out = armed && previous_fall;
    // Preserve genuine errors, including DV=0/ER=1 after arming.
    assign er_out = armed && (previous_fall ^ raw_dv);
endmodule
