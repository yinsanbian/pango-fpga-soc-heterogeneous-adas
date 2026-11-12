`timescale 1ns/1ps
// Pixel-domain-only, non-intrusive camera status HUD. All status inputs must
// already be synchronized into clk. The video input has four raw-pixel-clock
// registers of latency; the HUD also has four, followed by one shared output
// register. Total raw-pixel to output latency is five registers, one pixel/clk.
// No frame storage, arithmetic division, external IO or additional clock.
// LATENCY: 5 cycles from raw pixels; one output pixel per clock.
module camera_debug_overlay #(
    parameter P_ENABLE=1,
    parameter P_VIEW_LABEL=0
)(
    input wire clk,rst_n,
    input wire [11:0] x,
    input wire [10:0] y,
    input wire raw_de,
    input wire [23:0] video_rgb,
    input wire video_de,video_hs,video_vs,
    input wire [13:0] flags0,flags1,
    input wire [119:0] readback0,readback1,
    input wire readback_valid0,readback_valid1,
    input wire [2:0] mode,
    input wire [2:0] process_view,
    output reg [23:0] rgb_out,
    output reg de_out,hs_out,vs_out
);
    localparam [23:0] HEADER_BG=24'h142438, LABEL_BG=24'h203040;
    localparam [23:0] OFF_BG=24'h20242A, ON_BG=24'h14783C;
    localparam [23:0] ERROR_BG=24'hA82828, GRID=24'h40505C;
    localparam [23:0] TEXT=24'hFFFFFF, HEADER_TEXT=24'hD0E8FF;

    // Preserve original three-character flag cells at x=14..49. Readback
    // ID has four hex digits at x=8..55; other values have two at x=20..43.
    // A 5x7 glyph at 2x scale uses 12 pixels including its spacer column.
    // Decode each fixed layout from x in parallel. Vertical row/ID selection
    // is a final mux, never an input to a variable subtract/compare chain.
    wire raw_value_row=y[7:5]==4 || y[7:5]==5;
    wire raw_value_cell=raw_value_row && x[9:6]!=0;
    wire raw_id=raw_value_cell && x[9:6]==1;
    wire label_text=x[5:0]>=14 && x[5:0]<50;
    wire id_text=x[5:0]>=8 && x[5:0]<56;
    wire byte_text=x[5:0]>=20 && x[5:0]<44;
    wire raw_text=raw_id?id_text:(raw_value_cell?byte_text:label_text);
    wire [1:0] label_char=(x[5:0]<26)?0:((x[5:0]<38)?1:2);
    wire [1:0] id_char=(x[5:0]<20)?0:((x[5:0]<32)?1:((x[5:0]<44)?2:3));
    wire [1:0] byte_char=(x[5:0]<32)?0:1;
    wire [1:0] raw_char=raw_id?id_char:(raw_value_cell?byte_char:label_char);
    // All origins are even. In a 12-pixel character window, subtracting
    // origin/2 modulo 8 gives the exact 0..5 half-pixel glyph column.
    wire [2:0] gx_origin8 =x[3:1]-3'd4;
    wire [2:0] gx_origin14=x[3:1]-3'd7;
    wire [2:0] gx_origin20=x[3:1]-3'd2;
    wire [2:0] gx_origin26=x[3:1]-3'd5;
    wire [2:0] gx_origin32=x[3:1];
    wire [2:0] gx_origin38=x[3:1]-3'd3;
    wire [2:0] gx_origin44=x[3:1]-3'd6;
    wire [2:0] label_gx=(x[5:0]<26)?gx_origin14:
                        ((x[5:0]<38)?gx_origin26:gx_origin38);
    wire [2:0] id_gx=(x[5:0]<20)?gx_origin8:
                     ((x[5:0]<32)?gx_origin20:
                     ((x[5:0]<44)?gx_origin32:gx_origin44));
    wire [2:0] byte_gx=(x[5:0]<32)?gx_origin20:gx_origin32;
    wire [2:0] raw_gx=raw_id?id_gx:(raw_value_cell?byte_gx:label_gx);
    wire [4:0] text_v=y[4:0]-5'd9;
    reg s1_active,s1_text,s1_grid;
    reg [2:0] s1_row;
    reg [1:0] s1_char;
    reg [3:0] s1_cell;
    reg [2:0] s1_gx,s1_gy,s1_mode,s1_view;
    reg [13:0] s1_flags;
    reg [15:0] s1_value,s1_reference;
    reg s1_readback_valid;

    // Each readback byte is a constant part-select. Byte index zero is the
    // least significant byte. Avoid a 120-bit variable barrel shifter/mux.
    function [15:0] readback_value;
        input [119:0] snapshot;
        input [3:0] column_index;
        begin
            case(column_index)
                1:readback_value={snapshot[7:0],snapshot[15:8]};
                2:readback_value={8'd0,snapshot[23:16]};
                3:readback_value={8'd0,snapshot[31:24]};
                4:readback_value={8'd0,snapshot[39:32]};
                5:readback_value={8'd0,snapshot[47:40]};
                6:readback_value={8'd0,snapshot[55:48]};
                7:readback_value={8'd0,snapshot[63:56]};
                8:readback_value={8'd0,snapshot[71:64]};
                9:readback_value={8'd0,snapshot[79:72]};
                10:readback_value={8'd0,snapshot[87:80]};
                11:readback_value={8'd0,snapshot[95:88]};
                12:readback_value={8'd0,snapshot[103:96]};
                13:readback_value={8'd0,snapshot[111:104]};
                14:readback_value={8'd0,snapshot[119:112]};
                default:readback_value=0;
            endcase
        end
    endfunction
    function [15:0] reference_value;
        input [3:0] column_index;
        begin
            case(column_index)
                1:reference_value=16'h5640; 2:reference_value=16'h0002;
                3:reference_value=16'h00FF; 4:reference_value=16'h0058;
                5:reference_value=16'h0003; 6:reference_value=16'h001A;
                7:reference_value=16'h0021; 8:reference_value=16'h0069;
                9:reference_value=16'h0013; 10:reference_value=16'h0001;
                // Reset/default references; compare with healthy camera.
                11:reference_value=16'h0000; 12:reference_value=16'h00FF;
                13:reference_value=16'h0000; 14:reference_value=16'h0020;
                default:reference_value=0;
            endcase
        end
    endfunction
    function [7:0] hex_character;
        input [3:0] nibble;
        begin
            case(nibble)
                0:hex_character="0"; 1:hex_character="1"; 2:hex_character="2";
                3:hex_character="3"; 4:hex_character="4"; 5:hex_character="5";
                6:hex_character="6"; 7:hex_character="7"; 8:hex_character="8";
                9:hex_character="9"; 10:hex_character="A"; 11:hex_character="B";
                12:hex_character="C"; 13:hex_character="D"; 14:hex_character="E";
                default:hex_character="F";
            endcase
        end
    endfunction
    function [7:0] value_character;
        input [15:0] value;
        input id_value,completed;
        input [1:0] character;
        reg [3:0] nibble;
        begin
            if(id_value)begin
                case(character)
                    0:nibble=value[15:12];1:nibble=value[11:8];
                    2:nibble=value[7:4];default:nibble=value[3:0];
                endcase
            end else nibble=(character==0)?value[7:4]:value[3:0];
            value_character=completed?hex_character(nibble):"-";
        end
    endfunction

    function [7:0] cell_character;
        input [2:0] row;
        input [3:0] column_index;
        input [1:0] character;
        input [2:0] display_mode;
        input [2:0] display_view;
        reg [23:0] label;
        begin
            if(column_index==0) begin
                if(row==0) begin
                    case(display_mode)
                        0:label="M0 "; 1:label="M1 "; 2:label="M2 ";
                        default:label="MX ";
                    endcase
                end else if(row==3) begin
                    if(P_VIEW_LABEL) label={8'h56,hex_character({1'b0,display_view}),8'h20};
                    else label="RD ";
                end
                else if(row==1 || row==4) label="C0 ";
                else label="C1 ";
            end else if(row==3)begin
                case(column_index)
                    1:label="ID ";2:label="PWR";3:label="OUT";
                    4:label="DVP";5:label="SYS";6:label="P34";
                    7:label="P35";8:label="P36";9:label="P37";
                    10:label="DIV";11:label="RST";12:label="CK ";
                    13:label="SEL";14:label="POL";
                    default:label="   ";
                endcase
            end else begin
                case(column_index)
                    1:label="CFG"; 2:label="CLK"; 3:label="VS ";
                    4:label="HF "; 5:label="EN "; 6:label="RSP";
                    7:label="DAT"; 8:label="OK "; 9:label="DRP";
                    10:label="FUL"; 11:label="LIN"; 12:label="FRM";
                    13:label="DDR"; 14:label="CHG";
                    default:label="   ";
                endcase
            end
            case(character)
                0:cell_character=label[23:16];
                1:cell_character=label[15:8];
                default:cell_character=label[7:0];
            endcase
        end
    endfunction

    // Row zero is bits 34:30. Preserve the complete constant font for exact
    // screenshot decoders; select its row before the stage-3 register so a
    // mapped font ROM's Tco does not also traverse both row and column muxes.
    function [34:0] glyph;
        input [7:0] character;
        begin
            case(character)
                "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G":glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H":glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
                "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W":glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                default:glyph=35'd0;
            endcase
        end
    endfunction
    function [4:0] glyph_row;
        input [34:0] bits;
        input [2:0] gy;
        begin
            case(gy)
                0:glyph_row=bits[34:30]; 1:glyph_row=bits[29:25];
                2:glyph_row=bits[24:20]; 3:glyph_row=bits[19:15];
                4:glyph_row=bits[14:10]; 5:glyph_row=bits[9:5];
                6:glyph_row=bits[4:0]; default:glyph_row=5'd0;
            endcase
        end
    endfunction
    function glyph_pixel;
        input [4:0] row_bits;
        input [2:0] gx;
        begin
            case(gx)
                0:glyph_pixel=row_bits[4];1:glyph_pixel=row_bits[3];
                2:glyph_pixel=row_bits[2];3:glyph_pixel=row_bits[1];
                4:glyph_pixel=row_bits[0];default:glyph_pixel=1'b0;
            endcase
        end
    endfunction

    reg s2_active,s2_text,s2_grid;
    reg [7:0] s2_character;
    reg [2:0] s2_gx,s2_gy;
    reg [23:0] s2_bg,s2_fg;
    wire s1_flag=(s1_cell>=1 && s1_cell<=14) ? s1_flags[s1_cell-1'b1] : 1'b0;
    wire s1_error=s1_cell>=9 && s1_cell<=12;
    reg s3_active,s3_text,s3_grid;
    reg [4:0] s3_glyph_row;
    reg [2:0] s3_gx;
    reg [23:0] s3_bg,s3_fg;
    reg s4_active;
    reg [23:0] s4_rgb;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            s1_active<=0;s1_text<=0;s1_grid<=0;s1_row<=0;s1_char<=0;
            s1_cell<=0;s1_gx<=0;s1_gy<=0;s1_mode<=0;s1_view<=0;s1_flags<=0;
            s1_value<=0;s1_reference<=0;s1_readback_valid<=0;
            s2_active<=0;s2_text<=0;s2_grid<=0;s2_character<=0;
            s2_gx<=0;s2_gy<=0;s2_bg<=0;s2_fg<=0;
            s3_active<=0;s3_text<=0;s3_grid<=0;s3_glyph_row<=0;
            s3_gx<=0;s3_bg<=0;s3_fg<=0;
            s4_active<=0;s4_rgb<=0;rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;
        end else begin
            // Stage 1: geometry/status snapshot. Cell addressing is bitslice.
            s1_active<=P_ENABLE && raw_de && x<960 && y<192;
            s1_text<=raw_text && y[4:0]>=9 && y[4:0]<23;
            s1_grid<=x[5:0]==0 || x[5:0]==63 || y[4:0]==0 || y[4:0]==31;
            s1_row<=y[7:5];s1_cell<=x[9:6];s1_char<=raw_char;
            s1_gx<=raw_gx;s1_gy<=text_v[3:1];s1_mode<=mode;s1_view<=process_view;
            s1_flags<=(y[7:5]==1)?flags0:flags1;
            s1_value<=(y[7:5]==5)?readback_value(readback1,x[9:6]):readback_value(readback0,x[9:6]);
            s1_reference<=reference_value(x[9:6]);
            s1_readback_valid<=(y[7:5]==5)?readback_valid1:readback_valid0;
            // Stage 2: bounded 15-cell label and 14-bit status decode.
            s2_active<=s1_active;s2_text<=s1_text;s2_grid<=s1_grid;
            if(s1_row>=4 && s1_cell!=0)
                s2_character<=value_character(s1_value,s1_cell==1,s1_readback_valid,s1_char);
            else s2_character<=cell_character(s1_row,s1_cell,s1_char,s1_mode,s1_view);
            s2_gx<=s1_gx;s2_gy<=s1_gy;
            s2_fg<=(s1_row==0 || s1_row==3)?HEADER_TEXT:TEXT;
            if(s1_row==0 || s1_row==3) s2_bg<=HEADER_BG;
            else if(s1_cell==0) s2_bg<=LABEL_BG;
            else if(s1_row>=4) s2_bg<=!s1_readback_valid?OFF_BG:
                                        ((s1_value==s1_reference)?ON_BG:ERROR_BG);
            else if(!s1_flag) s2_bg<=OFF_BG;
            else s2_bg<=s1_error?ERROR_BG:ON_BG;
            // Stage 3: font and row selection; register just the chosen row.
            s3_active<=s2_active;s3_text<=s2_text;s3_grid<=s2_grid;
            s3_glyph_row<=glyph_row(glyph(s2_character),s2_gy);s3_gx<=s2_gx;
            s3_bg<=s2_bg;s3_fg<=s2_fg;
            // Stage 4: HUD pixel, now aligned with four-register video.
            s4_active<=s3_active;
            if(s3_grid) s4_rgb<=GRID;
            else if(s3_text && glyph_pixel(s3_glyph_row,s3_gx)) s4_rgb<=s3_fg;
            else s4_rgb<=s3_bg;
            // Stage 5: common RGB and sync output register. Preserve every
            // input RGB outside the HUD, including RGB during blanking.
            rgb_out<=(P_ENABLE && s4_active && video_de)?s4_rgb:video_rgb;
            de_out<=video_de;hs_out<=video_hs;vs_out<=video_vs;
        end
    end
endmodule
