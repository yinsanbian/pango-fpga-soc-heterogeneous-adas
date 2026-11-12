`timescale 1ns/1ps
// 50MHz board-local power/reset sequencer. The physical adapter holds PWDN
// low; camera_pwnd preserves the original logical timing/debug interface.
module camera_power_sequence #(
    parameter integer POWER_WAIT_CYCLES=262144,
    parameter integer RESET_WAIT_CYCLES=65535,
    parameter integer CONFIG_WAIT_CYCLES=1048575
)(
    input wire clk_50M,reset_n,
    output wire camera1_rstn,camera2_rstn,
    output reg camera_pwnd,initial_en
);
    wire local_reset_n;
    reset_sync u_start_reset(.clk(clk_50M),.async_n(reset_n),.rst_n(local_reset_n));
    localparam [1:0] HOLD_POWER=0,HOLD_RESET=1,WAIT_CONFIG=2,READY=3;
    reg [1:0] state;
    reg [19:0] ticks;
    reg camera_reset;
    assign camera1_rstn=camera_reset;
    assign camera2_rstn=camera_reset;
    always @(posedge clk_50M or negedge local_reset_n) begin
        if(!local_reset_n) begin
            state<=HOLD_POWER;ticks<=0;camera_reset<=0;
            camera_pwnd<=1;initial_en<=0;
        end else begin
            case(state)
                HOLD_POWER: begin
                    camera_reset<=0;initial_en<=0;camera_pwnd<=1;
                    if(ticks>=POWER_WAIT_CYCLES-1) begin
                        ticks<=0;camera_pwnd<=0;state<=HOLD_RESET;
                    end else ticks<=ticks+1'b1;
                end
                HOLD_RESET: begin
                    camera_reset<=0;initial_en<=0;camera_pwnd<=0;
                    if(ticks>=RESET_WAIT_CYCLES-1) begin
                        ticks<=0;camera_reset<=1;state<=WAIT_CONFIG;
                    end else ticks<=ticks+1'b1;
                end
                WAIT_CONFIG: begin
                    camera_reset<=1;initial_en<=0;camera_pwnd<=0;
                    if(ticks>=CONFIG_WAIT_CYCLES-1) begin
                        ticks<=0;initial_en<=1;state<=READY;
                    end else ticks<=ticks+1'b1;
                end
                READY: begin
                    ticks<=0;camera_reset<=1;initial_en<=1;camera_pwnd<=0;
                end
                default: begin
                    state<=HOLD_POWER;ticks<=0;camera_reset<=0;
                    camera_pwnd<=1;initial_en<=0;
                end
            endcase
        end
    end
endmodule
