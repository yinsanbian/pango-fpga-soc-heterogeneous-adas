`timescale 1ns/1ps
// Module : uart_status_telemetry
// 8N1 ASCII counter beacon for the Type-C CP2102 path (FPGA UART0_TX = R9).
// One fixed-format line per P_PERIOD_MS, LSB-first, no flow control:
//   N1 RAW=........ GOOD=........ REJ=........ FCS=........ PBAD=........
//   HDR=........ IP=........ UDP=........ BANK=........ BEAT=........
//   FRM=........ DROP=........\r\n
// Every value is printed as 8 uppercase hex digits so no binary-to-decimal
// divider is needed and the line is exactly LINE_BYTES long.
// LATENCY: transmit-only, no datapath input other than the counter bundle.
module uart_status_telemetry #(
    parameter integer P_CLK_HZ   = 50_000_000,
    parameter integer P_BAUD     = 115200,
    parameter integer P_PERIOD_MS= 500
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] raw,good,rej,fcs,pbad,hdr,ip,udp,bank,beat,frm,drop,
    // Second diagnostic bank, emitted on alternating lines with the "N2" prefix.
    input  wire [31:0] d0,d1,d2,d3,d4,d5,d6,
    output reg  uart_tx
);
    localparam integer DIV = (P_CLK_HZ + P_BAUD/2) / P_BAUD;
    localparam integer PERIOD_CYCLES = (P_CLK_HZ/1000)*P_PERIOD_MS;
    localparam integer FIELDS = 12;
    localparam integer LINE_BYTES = 3 + FIELDS*14 + 2; // "N1 " + fields + CR LF

    // Line sequencer state must be declared before the combinational byte mux.
    localparam [2:0] S_IDLE=0,S_PREFIX=1,S_FIELD=2,S_CR=3,S_LF=4;
    reg [2:0] state;
    reg [3:0] field,chr;      // chr 0..3 label, 4 '=', 5..12 hex, 13 space
    reg [1:0] prefix;         // 0..2 -> 'N','1',' '

    // ---------------------------------------------------------------- value mux
    reg [31:0] field_value;
    reg bank_sel;             // 0 -> N1 counter line, 1 -> N2 diagnostic line
    always @(*) begin
        if (bank_sel) begin
            case(field)
                4'd0: field_value=d0;  4'd1: field_value=d1;
                4'd2: field_value=d2;  4'd3: field_value=d3;
                4'd4: field_value=d4;  4'd5: field_value=d5;
                4'd6: field_value=d6;  default: field_value=32'd0;
            endcase
        end else begin
        case(field)
            4'd0: field_value=raw;   4'd1: field_value=good;
            4'd2: field_value=rej;   4'd3: field_value=fcs;
            4'd4: field_value=pbad;  4'd5: field_value=hdr;
            4'd6: field_value=ip;    4'd7: field_value=udp;
            4'd8: field_value=bank;  4'd9: field_value=beat;
            4'd10:field_value=frm;   default: field_value=drop;
        endcase
        end
    end

    // Four-letter label per field, MSB first.
    function [31:0] field_label;
        input [3:0] f;
        begin
            if (bank_sel) begin
                case(f)
                    4'd0: field_label="S4DP";
                    4'd1: field_label="S5DP";
                    4'd2: field_label="DMA ";
                    4'd3: field_label="DAW ";
                    4'd4: field_label="DWD ";
                    4'd5: field_label="DRAN";
                    4'd6: field_label="CYCL";
                    default: field_label="NONE";
                endcase
            end else
            case(f)
                4'd0: field_label="RAW ";
                4'd1: field_label="GOOD";
                4'd2: field_label="REJ ";
                4'd3: field_label="FCS ";
                4'd4: field_label="PBAD";
                4'd5: field_label="HDR ";
                4'd6: field_label="IP  ";
                4'd7: field_label="UDP ";
                4'd8: field_label="BANK";
                4'd9: field_label="BEAT";
                4'd10:field_label="FRM ";
                default: field_label="DROP";
            endcase
        end
    endfunction

    // ------------------------------------------------------------ byte assembly
    reg [7:0] line_byte;

    function [7:0] hex_digit;
        input [3:0] nib;
        begin
            hex_digit = nib < 4'd10 ? (8'h30 + {4'd0,nib}) : (8'h37 + {4'd0,nib});
        end
    endfunction

    wire [31:0] label = field_label(field);
    always @(*) begin
        if(state==S_PREFIX) begin
            case(prefix)
                2'd0: line_byte="N";
                2'd1: line_byte=bank_sel ? "2" : "1";
                default: line_byte=" ";
            endcase
        end else begin
            case(chr)
                4'd0: line_byte=label[31:24];
                4'd1: line_byte=label[23:16];
                4'd2: line_byte=label[15:8];
                4'd3: line_byte=label[7:0];
                4'd4: line_byte="=";
                4'd5: line_byte=hex_digit(field_value[31:28]);
                4'd6: line_byte=hex_digit(field_value[27:24]);
                4'd7: line_byte=hex_digit(field_value[23:20]);
                4'd8: line_byte=hex_digit(field_value[19:16]);
                4'd9: line_byte=hex_digit(field_value[15:12]);
                4'd10:line_byte=hex_digit(field_value[11:8]);
                4'd11:line_byte=hex_digit(field_value[7:4]);
                4'd12:line_byte=hex_digit(field_value[3:0]);
                default: line_byte=" ";
            endcase
        end
    end

    // ---------------------------------------------------------------- tx engine
    // A space inside the four-character label is padding: skip it instead of
    // transmitting, so the line reads RAW=... / IP=... without double spacing.
    wire label_pad = (chr < 4'd4) && (line_byte == 8'h20);
    reg [15:0] baud_cnt;
    reg [3:0] bitpos;
    reg [9:0] shifter;
    reg tx_active,tx_start,tx_done;
    reg [7:0] shifter_in;
    reg [31:0] period_cnt;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE;prefix<=0;field<=0;chr<=0;period_cnt<=0;bank_sel<=0;
            baud_cnt<=0;bitpos<=0;shifter<=10'h3ff;tx_active<=0;tx_start<=0;
            tx_done<=0;shifter_in<=0;uart_tx<=1'b1;
        end else begin
            tx_done<=1'b0;tx_start<=1'b0;
            // ---- byte-level transmit
            if(!tx_active) begin
                uart_tx<=1'b1;
                if(tx_start) begin
                    shifter<={1'b1,shifter_in,1'b0};
                    tx_active<=1'b1;bitpos<=4'd1;baud_cnt<=0;
                    uart_tx<=1'b0;              // start bit
                end
            end else if(baud_cnt==DIV-1) begin
                baud_cnt<=0;
                if(bitpos==4'd10) begin
                    tx_active<=1'b0;uart_tx<=1'b1;bitpos<=0;tx_done<=1'b1;
                end else begin
                    uart_tx<=shifter[bitpos];
                    bitpos<=bitpos+1'b1;
                end
            end else begin
                baud_cnt<=baud_cnt+1'b1;
            end
            // ---- line sequencer
            if(!tx_active && !tx_start) begin
                case(state)
                    S_IDLE: begin
                        if(period_cnt>=PERIOD_CYCLES-1) begin
                            period_cnt<=0;state<=S_PREFIX;prefix<=0;
                        end else period_cnt<=period_cnt+1'b1;
                    end
                    S_PREFIX: begin
                        shifter_in<=line_byte;tx_start<=1'b1;
                        if(prefix==2'd2) begin prefix<=0;field<=0;chr<=0;state<=S_FIELD;end
                        else prefix<=prefix+1'b1;
                    end
                    S_FIELD: begin
                        if(label_pad) begin
                            chr<=chr+1'b1;          // skip label padding, no byte sent
                        end else begin
                            shifter_in<=line_byte;tx_start<=1'b1;
                            if(chr==4'd13) begin
                                chr<=0;
                                if(field==FIELDS-1) state<=S_CR;
                                else field<=field+1'b1;
                            end else chr<=chr+1'b1;
                        end
                    end
                    S_CR: begin shifter_in<=8'h0d;tx_start<=1'b1;state<=S_LF;end
                    S_LF: begin shifter_in<=8'h0a;tx_start<=1'b1;state<=S_IDLE;bank_sel<=~bank_sel;end
                    default: state<=S_IDLE;
                endcase
            end
        end
    end
endmodule
