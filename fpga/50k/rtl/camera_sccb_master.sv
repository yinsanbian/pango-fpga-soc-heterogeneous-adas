`timescale 1ns/1ps
// OV5640 SCCB write engine. The only clock is clk; slow bus phases use CE.
// The ninth bit is diagnostic don't-care for SCCB, never a success gate.
module camera_sccb_master #(
    parameter integer P_HALF_PERIOD_CYCLES=1250
)(
    input wire clk, rst_n,
    input wire start,
    input wire [31:0] write_word,
    output reg busy, done,
    output reg scl,
    inout wire sda,
    output reg [3:0] ninth_bits
);
    localparam [3:0] ST_IDLE=0,ST_START=1,ST_BIT_LOW=2,ST_BIT_HIGH=3,
        ST_NINTH_LOW=4,ST_NINTH_HIGH=5,ST_STOP_LOW=6,
        ST_STOP_HIGH=7,ST_STOP_RELEASE=8;
    reg [3:0] state;
    reg [15:0] half_count;
    reg [31:0] shift_word;
    reg [2:0] bit_left;
    reg [1:0] byte_index;
    reg sda_low;
    assign sda=sda_low ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;half_count<=0;shift_word<=0;
            bit_left<=7;byte_index<=0;sda_low<=0;scl<=1;
            busy<=0;done<=0;ninth_bits<=0;
        end else begin
            done<=0;
            if(!busy) begin
                half_count<=0;
                if(start) begin
                    shift_word<=write_word;bit_left<=7;byte_index<=0;
                    ninth_bits<=0;busy<=1;state<=ST_START;
                end
            end else if(half_count==P_HALF_PERIOD_CYCLES-1) begin
                half_count<=0;
                case(state)
                    ST_START: begin
                        scl<=1;sda_low<=1;state<=ST_BIT_LOW;
                    end
                    ST_BIT_LOW: begin
                        scl<=0;sda_low<=!shift_word[31];state<=ST_BIT_HIGH;
                    end
                    ST_BIT_HIGH: begin
                        scl<=1;
                        if(bit_left==0) state<=ST_NINTH_LOW;
                        else begin
                            bit_left<=bit_left-1'b1;
                            shift_word<={shift_word[30:0],1'b0};
                            state<=ST_BIT_LOW;
                        end
                    end
                    ST_NINTH_LOW: begin
                        scl<=0;sda_low<=0;state<=ST_NINTH_HIGH;
                    end
                    ST_NINTH_HIGH: begin
                        scl<=1;ninth_bits[byte_index]<=sda;
                        if(byte_index==3) state<=ST_STOP_LOW;
                        else begin
                            byte_index<=byte_index+1'b1;bit_left<=7;
                            shift_word<={shift_word[30:0],1'b0};state<=ST_BIT_LOW;
                        end
                    end
                    ST_STOP_LOW: begin
                        scl<=0;sda_low<=1;state<=ST_STOP_HIGH;
                    end
                    ST_STOP_HIGH: begin
                        scl<=1;state<=ST_STOP_RELEASE;
                    end
                    ST_STOP_RELEASE: begin
                        sda_low<=0;scl<=1;busy<=0;done<=1;state<=ST_IDLE;
                    end
                    default: begin
                        sda_low<=0;scl<=1;busy<=0;state<=ST_IDLE;
                    end
                endcase
            end else half_count<=half_count+1'b1;
        end
    end
endmodule
