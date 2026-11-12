// PIX-only diagnostic HUD. Every input status is already synchronized.
// Five registers from RGB/DE/HS/VS/first_active input to corresponding output.
// Constant bit-slice cells, no framebuffer, new clock, CDC, or DDR traffic.
// LATENCY: 5 cycles; one pixel/cycle, including passive write-echo fields.
module network_rx_overlay #(
    parameter integer P_HEADER_CAPTURE=0,
    parameter integer P_PHY_DIAGNOSTIC=0,
    parameter integer P_CONTROLLED_RAW=0,
    parameter integer P_PHY_DELAY_STATUS=0,
    parameter integer P_PHY_WRITE_ECHO=0,
    parameter integer P_PHY_READONLY_PROFILE=0,
    parameter integer P_PHY_PAGE_ACCESS_PROBE=0,
    parameter integer P_MAC_BOUNDARY_DIAGNOSTIC=0
) (
    input wire clk, rst_n,
    input wire [23:0] rgb_in,
    input wire de_in, hs_in, vs_in, first_active_in,
    input wire [11:0] x,
    input wire [10:0] y,
    input wire [2:0] mode,
    input wire enable,
    input wire [207:0] status0, status1,
    input wire phy_diagnostic,
    input wire [102:0] core_status,
    input wire [1:0] clock_alive,
    input wire pll_locked_pix,
    input wire [3:0] observer_health_pix,
    output reg [23:0] rgb_out,
    output reg de_out, hs_out, vs_out, first_active_out
);
    localparam [23:0] HEADER_BG=24'h142438, LABEL_BG=24'h203040;
    localparam [23:0] OFF_BG=24'h20242A, ON_BG=24'h14783C;
    localparam [23:0] ERROR_BG=24'hA82828, GRID=24'h40505C;
    localparam [23:0] TEXT=24'hFFFFFF, HEADER_TEXT=24'hD0E8FF;

    wire header_row=(y[10:5]==6'd7);
    wire net0_row=(y[10:5]==6'd8);
    wire net1_row=(y[10:5]==6'd9);
    wire [3:0] column_index=x[10:7];
    wire [207:0] selected_status=net1_row ? status1 : status0;
    wire phy_mode_active=P_PHY_DIAGNOSTIC ? phy_diagnostic : 1'b0;
    wire phy_fault_view=P_PHY_DELAY_STATUS && phy_mode_active &&
        (status0[159:152]!=0 || status1[159:152]!=0);
    wire [4:0] glyph_y=y[4:0]-5'd9;

    // All slices are constants. This mux is registered before hex decode.
    function [31:0] field_value;
        input [3:0] column;
        input [207:0] snapshot;
        input [102:0] core;
        input channel, alive, locked;
        input fault_view;
        input phy_mode;
        input [3:0] observer_health;
        begin
            case(column)
                1:field_value={31'd0,alive};
                2:field_value={31'd0,locked};
                3:field_value={31'd0,snapshot[201]};
                4:field_value={31'd0,snapshot[200]};
                5:field_value=snapshot[63:32];
                6:field_value=snapshot[31:0];
                7:field_value=snapshot[95:64];
                8:field_value=snapshot[127:96];
                9:field_value={24'd0,snapshot[199:192]};
                10:field_value=snapshot[159:128];
                11:field_value=snapshot[191:160];
                12:field_value=channel ? {30'd0,core[101:100]} :
                                        {30'd0,core[99:98]};
                13:field_value=core[95:64];
                14:field_value=channel ? core[63:32] : core[31:0];
                default:field_value=32'd0;
            endcase
            if(P_MAC_BOUNDARY_DIAGNOSTIC && !phy_mode && column==9)
                field_value={20'd0,observer_health,2'b00,snapshot[207:202]};
            if((P_PHY_WRITE_ECHO || P_PHY_READONLY_PROFILE || P_PHY_PAGE_ACCESS_PROBE) && phy_mode) begin
                case(column)
                    12:field_value=core[95:64];
                    13:field_value=core[63:32];
                    14:field_value=core[31:0];
                    default: begin end
                endcase
            end
            // A shared header can cover one faulty and one healthy port. The
            // healthy row has no first failed READ; do not show its old/new
            // words under EXPECTED/ACTUAL headings or invent a zero-valued read.
            if(fault_view && snapshot[159:152]==0) begin
                case(column)
                    6,7:field_value=0;
                    11:field_value=32'h0000cfc0; // kind3, step63, ACK0, reg0
                    default: begin end
                endcase
            end
        end
    endfunction

    function [7:0] label_character;
        input header, channel;
        input [3:0] column;
        input [2:0] slot, display_mode;
        input phy_mode;
        input fault_view;
        reg [63:0] label;
        begin
            if(!header) label=channel ? "N1      " : "N0      ";
            else begin
                case(column)
                    0:case(display_mode)
                        0:label="M0      ";1:label="M1      ";
                        2:label="M2      ";default:label="MX      ";
                    endcase
                    1:label="CLK     ";2:label="PLL     ";
                    3:label=phy_mode ? "DONE    " : "RST     ";
                    4:label=phy_mode ? (P_PHY_DELAY_STATUS ? "ELIGIBLE" : "FOUND   ") : "DV      ";
                    5:label=phy_mode ? "PHYID   " : (P_CONTROLLED_RAW ? "RAW0    " : (P_HEADER_CAPTURE ? "H00     " : "RXER    "));
                    6:label=fault_view ? "EXPECTED" : (phy_mode ? (P_PHY_DELAY_STATUS ? "OLD NEW " : "BMCRBSR ") : (P_CONTROLLED_RAW ? "RAW1    " : (P_HEADER_CAPTURE ? "H04     " : "RAW     ")));
                    7:label=fault_view ? "ACTUAL  " : (phy_mode ? (P_PHY_DELAY_STATUS ? "PAGE EXT" : "BSR AN  ") : "GOOD    ");
                    8:label=phy_mode ? (P_PHY_DELAY_STATUS ? "ADDRMAP " : "ANLP GBC") : "REJ     ";
                    9:label=phy_mode ? "FLAGS   " : (P_CONTROLLED_RAW ? "META    " : "WHY     ");
                    10:label=phy_mode ? (P_PHY_DELAY_STATUS ? "RESULT  " : "GBS EXT ") : (P_CONTROLLED_RAW ? "RAW2    " : (P_HEADER_CAPTURE ? "H08     " : "YTM     "));
                    11:label=fault_view ? "FAULT   " : (phy_mode ? "SCAN    " : (P_CONTROLLED_RAW ? "RAW3    " : (P_HEADER_CAPTURE ? "CTL     " : "DROP    ")));
                    12:label=(P_PHY_WRITE_ECHO && phy_mode) ? "TXCMD   " : "FRM     ";
                    13:label=(P_PHY_WRITE_ECHO && phy_mode) ? "ECHO    " : "DMA     ";
                    14:label=(P_PHY_WRITE_ECHO && phy_mode) ? "ECHOCTL " : "BEAT    ";
                    default:label="        ";
                endcase
                if(P_PHY_READONLY_PROFILE && phy_mode) begin
                    case(column)
                        12:label="ADDRMAP ";
                        13:label="PAGE RXE";
                        14:label="RO ACK  ";
                        default:begin end
                    endcase
                end
                if(P_PHY_PAGE_ACCESS_PROBE && phy_mode) begin
                    case(column)
                        12:label="P31 E L ";
                        13:label="SAMP ACK";
                        14:label="RAW1C   ";
                        default:begin end
                    endcase
                end
            end
            // Each row carries its own page code. Fixed observation headers
            // cannot accidentally label N0 using N1's independently timed page.
            if(header && P_MAC_BOUNDARY_DIAGNOSTIC && !phy_mode) begin
                case(column)
                    5:label="OBS0    ";6:label="OBS1    ";
                    9:label="PAGE    ";10:label="OBS2    ";
                    11:label="OBS3    ";default:begin end
                endcase
            end
            case(slot)
                0:label_character=label[63:56];1:label_character=label[55:48];
                2:label_character=label[47:40];3:label_character=label[39:32];
                4:label_character=label[31:24];5:label_character=label[23:16];
                6:label_character=label[15:8];default:label_character=label[7:0];
            endcase
        end
    endfunction

    function [7:0] value_character;
        input [31:0] value;
        input [2:0] slot;
        reg [3:0] nibble;
        begin
            case(slot)
                0:nibble=value[31:28];1:nibble=value[27:24];
                2:nibble=value[23:20];3:nibble=value[19:16];
                4:nibble=value[15:12];5:nibble=value[11:8];
                6:nibble=value[7:4];default:nibble=value[3:0];
            endcase
            case(nibble)
                0:value_character="0";1:value_character="1";
                2:value_character="2";3:value_character="3";
                4:value_character="4";5:value_character="5";
                6:value_character="6";7:value_character="7";
                8:value_character="8";9:value_character="9";
                10:value_character="A";11:value_character="B";
                12:value_character="C";13:value_character="D";
                14:value_character="E";15:value_character="F";
                default:value_character="?";
            endcase
        end
    endfunction

    // 35-bit constant ROM, registered before row selection. Row zero occupies
    // bits34:30. PDS may implement this as DRM9K; its measured tco is kept in
    // a separate pipeline interval from the final glyph-bit/color/IOFF mux.
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
                "?":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b00000,5'b00100};
                default:glyph=35'd0;
            endcase
        end
    endfunction
    function [4:0] glyph_row;
        input [34:0] bits;
        input [2:0] gy;
        begin
            case(gy)
                0:glyph_row=bits[34:30];1:glyph_row=bits[29:25];
                2:glyph_row=bits[24:20];3:glyph_row=bits[19:15];
                4:glyph_row=bits[14:10];5:glyph_row=bits[9:5];
                6:glyph_row=bits[4:0];default:glyph_row=5'd0;
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

    reg [23:0] video0, video1, video2, video3;
    reg [3:0] sync0, sync1, sync2, sync3;
    reg s1_active, s1_text, s1_grid, s1_header, s1_label, s1_dash;
    reg s1_alarm, s1_protocol_error, s1_capture_control,s1_phy_mode;
    reg s1_write_echo;
    reg [31:0] s1_value;
    reg [7:0] s1_character;
    reg [2:0] s1_slot, s1_gx, s1_gy;
    reg s2_active, s2_text, s2_grid;
    reg [7:0] s2_character;
    reg [2:0] s2_gx, s2_gy;
    reg [23:0] s2_bg, s2_fg;
    reg s3_active, s3_text, s3_grid;
    reg [34:0] s3_glyph;
    reg [2:0] s3_gx, s3_gy;
    reg [23:0] s3_bg, s3_fg;
    reg s4_active, s4_text, s4_grid;
    reg [4:0] s4_row;
    reg [2:0] s4_gx;
    reg [23:0] s4_bg, s4_fg;
    wire selected_alive=net1_row ? clock_alive[1] : clock_alive[0];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            video0<=0;video1<=0;video2<=0;video3<=0;
            sync0<=0;sync1<=0;sync2<=0;sync3<=0;
            s1_active<=0;s1_text<=0;s1_grid<=0;s1_header<=0;
            s1_label<=0;s1_dash<=0;s1_alarm<=0;s1_protocol_error<=0;s1_capture_control<=0;
            s1_phy_mode<=0;
            s1_write_echo<=0;
            s1_value<=0;s1_character<=0;s1_slot<=0;s1_gx<=0;s1_gy<=0;
            s2_active<=0;s2_text<=0;s2_grid<=0;s2_character<=0;
            s2_gx<=0;s2_gy<=0;s2_bg<=0;s2_fg<=0;
            s3_active<=0;s3_text<=0;s3_grid<=0;s3_glyph<=0;
            s3_gx<=0;s3_gy<=0;s3_bg<=0;s3_fg<=0;
            s4_active<=0;s4_text<=0;s4_grid<=0;s4_row<=0;
            s4_gx<=0;s4_bg<=0;s4_fg<=0;
            rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;first_active_out<=0;
        end else begin
            video0<=rgb_in;video1<=video0;video2<=video1;video3<=video2;
            sync0<={de_in,hs_in,vs_in,first_active_in};
            sync1<=sync0;sync2<=sync1;sync3<=sync2;
            // Stage 1: cell/status and geometry. Marker at y0 is untouched.
            s1_active<=enable && de_in && x<12'd1920 &&
                       (header_row || net0_row || net1_row);
            s1_text<=x[3:0]>=4'd2 && x[3:0]<4'd12 &&
                     y[4:0]>=5'd9 && y[4:0]<5'd23;
            s1_grid<=x[6:0]==7'd0 || x[6:0]==7'd127 ||
                     y[4:0]==5'd0 || y[4:0]==5'd31;
            s1_header<=header_row;s1_label<=column_index==0;
            s1_dash<=net0_row && column_index==2;
            s1_alarm<=(!phy_mode_active && (column_index==8 || (!P_CONTROLLED_RAW && column_index==9))) || column_index==13 ||
                      (!P_CONTROLLED_RAW && !P_HEADER_CAPTURE && !phy_mode_active && (column_index==5 || column_index==10 || column_index==11));
            s1_protocol_error<=(column_index==13 && core_status[102]) ||
                (phy_fault_view && selected_status[159:152]!=0 &&
                 (column_index==6 || column_index==7 || column_index==10 || column_index==11));
            s1_capture_control<=((!P_CONTROLLED_RAW && P_HEADER_CAPTURE) || (phy_mode_active && !phy_fault_view)) && column_index==11 ||
                                (P_CONTROLLED_RAW && !P_MAC_BOUNDARY_DIAGNOSTIC && !phy_mode_active && column_index==9);
            s1_phy_mode<=phy_mode_active;
            s1_write_echo<=(P_PHY_WRITE_ECHO || P_PHY_READONLY_PROFILE || P_PHY_PAGE_ACCESS_PROBE) && phy_mode_active &&
                           (column_index==12 || column_index==13 || column_index==14);
            s1_value<=field_value(column_index,selected_status,core_status,
                                  net1_row,selected_alive,pll_locked_pix,phy_fault_view,phy_mode_active,observer_health_pix);
            s1_character<=label_character(header_row,net1_row,column_index,x[6:4],mode,phy_mode_active,phy_fault_view);
            s1_slot<=x[6:4];s1_gx<=x[3:1]-3'd1;s1_gy<=glyph_y[3:1];
            // Stage 2: only 32->4 hex selection plus small ASCII decoding.
            s2_active<=s1_active;s2_text<=s1_text;s2_grid<=s1_grid;
            if(s1_header || s1_label) s2_character<=s1_character;
            else if(s1_dash) s2_character<="-";
            else s2_character<=value_character(s1_value,s1_slot);
            s2_gx<=s1_gx;s2_gy<=s1_gy;
            s2_fg<=s1_header ? HEADER_TEXT : TEXT;
            if(s1_header) s2_bg<=HEADER_BG;
            else if(s1_label) s2_bg<=LABEL_BG;
            else if(s1_dash) s2_bg<=OFF_BG;
            // PHY observations are not DMA error flags or a wide
            // equality/color comparator. Their metadata stays visible as hex.
            else if(s1_write_echo) s2_bg<=OFF_BG;
            else if(s1_protocol_error) s2_bg<=ERROR_BG;
            else if(s1_capture_control) begin
                // The mailbox carries data and completion atomically. A
                // partial/nonzero prefix is never an RX error indication.
                if(s1_phy_mode) begin
                    if(!s1_value[6]) s2_bg<=OFF_BG;
                    else s2_bg<=s1_value[5] ? ON_BG : ERROR_BG;
                end
                else if(P_CONTROLLED_RAW) begin
                    if(s1_value[6] || s1_value[5]) s2_bg<=ERROR_BG;
                    else if(s1_value[7] && s1_value[4]) s2_bg<=ON_BG;
                    else s2_bg<=OFF_BG;
                end
                else if(s1_value[28] && s1_value[27:24]==4'd12) s2_bg<=ON_BG;
                else s2_bg<=OFF_BG;
            end
            else if(s1_value!=0) s2_bg<=s1_alarm ? ERROR_BG : ON_BG;
            else s2_bg<=OFF_BG;
            // Stage 3: font ROM. PDS may infer one DRM9K for this stage.
            s3_active<=s2_active;s3_text<=s2_text;s3_grid<=s2_grid;
            s3_glyph<=glyph(s2_character);s3_gx<=s2_gx;s3_gy<=s2_gy;
            s3_bg<=s2_bg;s3_fg<=s2_fg;
            // Stage 4: register the selected five-bit row near the font ROM.
            // Keep its tco and row mux out of the final RGB output interval.
            s4_active<=s3_active;s4_text<=s3_text;s4_grid<=s3_grid;
            s4_row<=glyph_row(s3_glyph,s3_gy);s4_gx<=s3_gx;
            s4_bg<=s3_bg;s4_fg<=s3_fg;
            // Stage 5: glyph bit/color plus common video/sync output register.
            // Blanking RGB is preserved; all paths have exactly five stages.
            if(!s4_active) rgb_out<=video3;
            else if(s4_grid) rgb_out<=GRID;
            else if(s4_text && glyph_pixel(s4_row,s4_gx)) rgb_out<=s4_fg;
            else rgb_out<=s4_bg;
            {de_out,hs_out,vs_out,first_active_out}<=sync3;
        end
    end
endmodule
