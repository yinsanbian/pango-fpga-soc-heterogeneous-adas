`timescale 1ns / 1ps

module video_mode_control #(
    parameter P_DEBOUNCE_CYCLES = 1500000,
    // The existing lane-demo top keeps its six diagnostic display modes.
    // FIRST/COUNT select consecutive on-wire IDs without renumbering.
    parameter P_MODE_COUNT = 6,
    parameter P_MODE_FIRST = 0
)(
    input wire clk,
    input wire rst_n,
    input wire key_n,
    input wire vsync,
    output reg [2:0] display_mode
);
    localparam P_COUNT_W = (P_DEBOUNCE_CYCLES < 2) ? 1 : $clog2(P_DEBOUNCE_CYCLES + 1);
    reg key_meta;
    reg key_sync;
    reg key_stable;
    reg [P_COUNT_W-1:0] stable_count;
    reg [2:0] requested_mode;
    reg vsync_d;
    wire frame_start = vsync && !vsync_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
            key_stable <= 1'b1;
            stable_count <= 0;
            requested_mode <= P_MODE_FIRST;
            display_mode <= P_MODE_FIRST;
            vsync_d <= 1'b0;
        end else begin
            vsync_d <= vsync;
            key_meta <= key_n;
            key_sync <= key_meta;
            if (key_sync == key_stable)
                stable_count <= 0;
            else if (stable_count == P_DEBOUNCE_CYCLES - 1) begin
                stable_count <= 0;
                key_stable <= key_sync;
                if (!key_sync)
                    requested_mode <= (requested_mode == P_MODE_FIRST + P_MODE_COUNT - 1) ?
                        P_MODE_FIRST : requested_mode + 1'b1;
            end else
                stable_count <= stable_count + 1'b1;
            // Apply a requested mode only at the beginning of a frame.
            if (frame_start)
                display_mode <= requested_mode;
        end
    end
endmodule
