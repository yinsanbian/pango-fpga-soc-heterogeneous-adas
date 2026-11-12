`timescale 1ns/1ps
// Gray pointer CDC. Both resets must assert together; release is local.
// Registered RAM read and output register: valid/ready is a held stream.
// No combinational data path crosses a clock domain.
module video_async_fifo #(
    parameter WIDTH=310, parameter ADDR_BITS=8
) (
    input wire wr_clk,wr_rst_n, input wire [WIDTH-1:0] wr_data,
    input wire wr_valid, output wire wr_ready,
    input wire rd_clk,rd_rst_n, output reg [WIDTH-1:0] rd_data,
    output reg rd_valid, input wire rd_ready
);
    localparam DEPTH=1<<ADDR_BITS;
    reg [WIDTH-1:0] mem[0:DEPTH-1];
    reg [ADDR_BITS:0] wbin,wgray,rbin,rgray;
    // ADS recognizes PAP_ASYNC_REG numeric 1 and protects/places each chain.
    // Generic async_reg is ignored by this installed PDS frontend.
    (* PAP_ASYNC_REG=1 *) reg [ADDR_BITS:0] rgray_w1,rgray_w2,wgray_r1,wgray_r2;
    reg full;
    wire push=wr_valid && wr_ready;
    wire [ADDR_BITS:0] wn=wbin+push;
    wire [ADDR_BITS:0] wgn=(wn>>1)^wn;
    wire empty=(rgray==wgray_r2);
    wire fetch=(!rd_valid || rd_ready) && !empty;
    wire [ADDR_BITS:0] rn=rbin+fetch;
    assign wr_ready=!full;
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            wbin<=0;wgray<=0;full<=0;rgray_w1<=0;rgray_w2<=0;
        end else begin
            rgray_w1<=rgray;rgray_w2<=rgray_w1;
            wbin<=wn;wgray<=wgn;
            full<=(wgn=={~rgray_w2[ADDR_BITS:ADDR_BITS-1],rgray_w2[ADDR_BITS-2:0]});
        end
    end
    always @(posedge wr_clk) if(push) mem[wbin[ADDR_BITS-1:0]]<=wr_data;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            rbin<=0;rgray<=0;rd_valid<=0;wgray_r1<=0;wgray_r2<=0;
        end else begin
            wgray_r1<=wgray;wgray_r2<=wgray_r1;
            rbin<=rn;rgray<=(rn>>1)^rn;
            if(!rd_valid || rd_ready) rd_valid<=!empty;
        end
    end
    always @(posedge rd_clk) if(fetch) rd_data<=mem[rbin[ADDR_BITS-1:0]];
endmodule
