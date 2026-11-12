`timescale 1ns/1ps
// One finite SCCB read-only snapshot in the existing 25MHz domain.
// A pointer write has three bytes, followed by STOP, read address, data,
// master NACK and STOP. No sensor register data or corrective writes occur.
module camera_sccb_readback #(
    parameter integer P_HALF_PERIOD_CYCLES=1250,
    parameter integer P_WAIT_CYCLES=25000
)(
    input wire clk,rst_n,enable,
    output reg scl,
    inout wire sda,
    output reg done,
    output reg [119:0] values
);
    localparam integer HALF_BITS=P_HALF_PERIOD_CYCLES>1 ? $clog2(P_HALF_PERIOD_CYCLES) : 1;
    localparam integer WAIT_BITS=P_WAIT_CYCLES>1 ? $clog2(P_WAIT_CYCLES) : 1;
    localparam [3:0] WAIT_ENABLE=0,POINTER_START=1,READ_START=2,
        TX_LOW=3,TX_HIGH=4,NINTH_LOW=5,NINTH_HIGH=6,
        RX_LOW=7,RX_HIGH=8,RX_SAMPLE=9,NACK_HIGH=10,
        STOP_LOW=11,STOP_HIGH=12,STOP_RELEASE=13,FINISHED=14;
    reg [3:0] state,register_index;
    reg [HALF_BITS-1:0] half_count;
    reg [WAIT_BITS-1:0] wait_count;
    reg [23:0] tx_shift;
    reg [7:0] rx_shift;
    reg [4:0] tx_bits_left;
    reg [2:0] bit_left;
    reg read_address,sda_low;
    (* PAP_ASYNC_REG=1 *) reg sda_meta,sda_sync;
    assign sda=sda_low ? 1'b0 : 1'bz;

    function automatic [15:0] snapshot_address(input [3:0] index);
        begin
            case(index)
                0:snapshot_address=16'h300a;
                1:snapshot_address=16'h300b;
                2:snapshot_address=16'h3008;
                3:snapshot_address=16'h3017;
                4:snapshot_address=16'h300e;
                5:snapshot_address=16'h3103;
                6:snapshot_address=16'h3034;
                7:snapshot_address=16'h3035;
                8:snapshot_address=16'h3036;
                9:snapshot_address=16'h3037;
                10:snapshot_address=16'h3108;
                11:snapshot_address=16'h3003;
                12:snapshot_address=16'h3007;
                13:snapshot_address=16'h301d;
                14:snapshot_address=16'h4740;
                default:snapshot_address=16'h300a;
            endcase
        end
    endfunction

    // Only the asynchronous external pin enters this 2FF chain. Sampling
    // at the end of SCL high gives the default bus 50us settling time.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin sda_meta<=1;sda_sync<=1;end
        else begin sda_meta<=sda;sda_sync<=sda_meta;end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_ENABLE;register_index<=0;half_count<=0;wait_count<=0;
            tx_shift<=0;rx_shift<=0;tx_bits_left<=0;bit_left<=7;
            read_address<=0;sda_low<=0;scl<=1;done<=0;values<=0;
        end else if(done) begin
            // Snapshot and done remain stable until reset, even if enable
            // is subsequently removed or the physical bus changes.
            state<=FINISHED;half_count<=0;sda_low<=0;scl<=1;
        end else if(!enable) begin
            state<=WAIT_ENABLE;register_index<=0;half_count<=0;wait_count<=0;
            tx_shift<=0;rx_shift<=0;tx_bits_left<=0;bit_left<=7;
            read_address<=0;sda_low<=0;scl<=1;values<=0;
        end else if(state==WAIT_ENABLE) begin
            half_count<=0;sda_low<=0;scl<=1;
            if(wait_count==P_WAIT_CYCLES-1) begin
                wait_count<=0;state<=POINTER_START;
            end else wait_count<=wait_count+1'b1;
        end else if(half_count==P_HALF_PERIOD_CYCLES-1) begin
            half_count<=0;
            case(state)
                POINTER_START: begin
                    scl<=1;sda_low<=1;
                    tx_shift<={8'h78,snapshot_address(register_index)};
                    tx_bits_left<=23;bit_left<=7;read_address<=0;state<=TX_LOW;
                end
                READ_START: begin
                    scl<=1;sda_low<=1;tx_shift<=24'h790000;
                    tx_bits_left<=7;bit_left<=7;read_address<=1;state<=TX_LOW;
                end
                TX_LOW: begin
                    scl<=0;sda_low<=!tx_shift[23];state<=TX_HIGH;
                end
                TX_HIGH: begin
                    scl<=1;
                    if(bit_left==0) state<=NINTH_LOW;
                    else begin
                        bit_left<=bit_left-1'b1;tx_bits_left<=tx_bits_left-1'b1;
                        tx_shift<={tx_shift[22:0],1'b0};state<=TX_LOW;
                    end
                end
                NINTH_LOW: begin
                    scl<=0;sda_low<=0;state<=NINTH_HIGH;
                end
                NINTH_HIGH: begin
                    // SCCB ninth bits are don't-care, not an ACK success
                    // gate. No-response snapshots therefore still finish.
                    scl<=1;sda_low<=0;
                    if(tx_bits_left==0) begin
                        if(read_address) begin bit_left<=7;rx_shift<=0;state<=RX_LOW;end
                        else state<=STOP_LOW;
                    end else begin
                        tx_bits_left<=tx_bits_left-1'b1;bit_left<=7;
                        tx_shift<={tx_shift[22:0],1'b0};state<=TX_LOW;
                    end
                end
                RX_LOW: begin scl<=0;sda_low<=0;state<=RX_HIGH;end
                RX_HIGH: begin scl<=1;sda_low<=0;state<=RX_SAMPLE;end
                RX_SAMPLE: begin
                    // This CE is one full half-period after the rising
                    // edge; lower SCL only after sampling its high phase.
                    scl<=0;sda_low<=0;rx_shift<={rx_shift[6:0],sda_sync};
                    if(bit_left==0) begin
                        values[register_index*8 +:8]<={rx_shift[6:0],sda_sync};
                        state<=NACK_HIGH;
                    end else begin bit_left<=bit_left-1'b1;state<=RX_HIGH;end
                end
                NACK_HIGH: begin
                    // SDA remains released for the master's ninth bit.
                    scl<=1;sda_low<=0;state<=STOP_LOW;
                end
                STOP_LOW: begin scl<=0;sda_low<=1;state<=STOP_HIGH;end
                STOP_HIGH: begin scl<=1;sda_low<=1;state<=STOP_RELEASE;end
                STOP_RELEASE: begin
                    scl<=1;sda_low<=0;
                    if(!read_address) state<=READ_START;
                    else if(register_index==14) begin done<=1;state<=FINISHED;end
                    else begin register_index<=register_index+1'b1;state<=POINTER_START;end
                end
                default: begin
                    state<=WAIT_ENABLE;half_count<=0;wait_count<=0;register_index<=0;
                    scl<=1;sda_low<=0;values<=0;
                end
            endcase
        end else half_count<=half_count+1'b1;
    end
endmodule
