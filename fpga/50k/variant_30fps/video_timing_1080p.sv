`timescale 1ns/1ps
// CEA 1920x1080 progressive raster. At 74.25 MHz the frame rate is 30 Hz
// (30 fps variant; the 60 fps build uses 148.5 MHz with the same raster).
// Pulse convention: positive HS and VS; frame_start is at the VS rising edge.
module video_timing_1080p (
    input  wire        clk,
    input  wire        rst_n,
    output wire        hs,
    output wire        vs,
    output wire        de,
    output wire [11:0] x,
    output wire [10:0] y,
    output wire        frame_start,
    output wire        line_end
);
    localparam integer H_ACTIVE = 1920;
    localparam integer H_SYNC = 44;
    localparam integer H_BACK = 148;
    localparam integer H_FRONT = 88;
    localparam integer H_TOTAL = H_ACTIVE + H_SYNC + H_BACK + H_FRONT;
    localparam integer V_ACTIVE = 1080;
    localparam integer V_SYNC = 5;
    localparam integer V_BACK = 36;
    localparam integer V_FRONT = 4;
    localparam integer V_TOTAL = V_ACTIVE + V_SYNC + V_BACK + V_FRONT;

    reg [11:0] h_count;
    reg [10:0] v_count;
    wire h_active = h_count >= H_SYNC + H_BACK &&
                    h_count < H_SYNC + H_BACK + H_ACTIVE;
    wire v_active = v_count >= V_SYNC + V_BACK &&
                    v_count < V_SYNC + V_BACK + V_ACTIVE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 12'd0;
            v_count <= 11'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 12'd0;
            if (v_count == V_TOTAL - 1)
                v_count <= 11'd0;
            else
                v_count <= v_count + 11'd1;
        end else begin
            h_count <= h_count + 12'd1;
        end
    end

    assign hs = rst_n && h_count < H_SYNC;
    assign vs = rst_n && v_count < V_SYNC;
    assign de = rst_n && h_active && v_active;
    assign x = de ? h_count - (H_SYNC + H_BACK) : 12'd0;
    assign y = de ? v_count - (V_SYNC + V_BACK) : 11'd0;
    assign frame_start = rst_n && h_count == 0 && v_count == 0;
    assign line_end = de && h_count == H_SYNC + H_BACK + H_ACTIVE - 1;
endmodule
