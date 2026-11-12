`timescale 1ns/1ps
// Asynchronous assertion, two destination-clock cycles to release.
module reset_sync(input wire clk, input wire async_n, output wire rst_n);
    (* PAP_ASYNC_REG = 1 *) reg [1:0] stages;
    always @(posedge clk or negedge async_n)
        if (!async_n) stages <= 0;
        else stages <= {stages[0],1'b1};
    assign rst_n = stages[1];
endmodule
