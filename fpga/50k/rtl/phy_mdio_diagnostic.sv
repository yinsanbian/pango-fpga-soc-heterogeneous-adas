`timescale 1ns/1ps
// Clause 22 scanner with optional, bounded RTL8211E delay initialization.
// All state/CE/status use PIX; MDC remains an IO waveform, never a clock.
// P_CONFIG_DELAY=0 retains the original OP10-only wire sequence.
module phy_mdio_diagnostic #(
    parameter integer P_QUARTER_CYCLES = 372,
    parameter integer P_STARTUP_CYCLES = 148500000,
    parameter integer P_CONFIG_DELAY = 0,
    parameter integer P_READONLY_PROFILE = 0,
    parameter integer P_PAGE_ACCESS_PROBE = 0
)(
    input wire pix_clk, pix_rst_n,
    input wire [1:0] mdio_i,
    output reg [1:0] mdio_o, mdio_oe, mdc,
    output wire [191:0] status0, status1,
    output wire [127:0] delay_status0, delay_status1,
    output wire [47:0] page_probe0, page_probe1
);
    // Read-only profile wins if both parameters are accidentally enabled.
    localparam integer PROBE_ACTIVE=P_PAGE_ACCESS_PROBE && !P_READONLY_PROFILE;
    localparam integer CONFIG_ACTIVE=P_CONFIG_DELAY && !P_READONLY_PROFILE && !PROBE_ACTIVE;
    localparam integer TRANSACTION_ACTIVE=CONFIG_ACTIVE || PROBE_ACTIVE;
    localparam integer QW = P_QUARTER_CYCLES < 2 ? 1 : $clog2(P_QUARTER_CYCLES);
    localparam integer SW = P_STARTUP_CYCLES < 2 ? 1 : $clog2(P_STARTUP_CYCLES);
    localparam [3:0] S_WAIT=0, S_BEGIN=1, S_BITS=2, S_FINISH=3,
        S_SCAN_COMPLETE=4, S_PORT_DONE=5, S_FROZEN=6, S_FLUSH=7, S_TAIL=8;

    // Ordinary local reset distribution; independent of all existing branches.
    reg pix_reset_released /* synthesis syn_preserve=1 */;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) pix_reset_released<=0;
        else pix_reset_released<=1;
    end
    // Scalar compile objects allow an exact pad-to-first-stage timing exception
    // for each bus, while the meta-to-sync paths remain fully timed.
    (* PAP_ASYNC_REG = 1 *) reg mdio0_meta /* synthesis syn_preserve=1 */;
    (* PAP_ASYNC_REG = 1 *) reg mdio1_meta /* synthesis syn_preserve=1 */;
    (* PAP_ASYNC_REG = 1 *) reg mdio0_sync /* synthesis syn_preserve=1 */;
    (* PAP_ASYNC_REG = 1 *) reg mdio1_sync /* synthesis syn_preserve=1 */;
    wire [1:0] mdio_sync={mdio1_sync,mdio0_sync};
    always @(posedge pix_clk or negedge pix_reset_released) begin
        if (!pix_reset_released) begin
            mdio0_meta<=1;mdio1_meta<=1;mdio0_sync<=1;mdio1_sync<=1;
        end else begin
            mdio0_meta<=mdio_i[0];mdio1_meta<=mdio_i[1];
            mdio0_sync<=mdio0_meta;mdio1_sync<=mdio1_meta;
        end
    end

    reg [159:0] registers [0:1];
    reg [4:0] found_address [0:1];
    reg [1:0] found, done, any_id_ack;
    reg [7:0] ta_errors [0:1], zero_ids [0:1], ones_ids [0:1];
    // First failing READ, never the later cleanup observation. Step63 means no
    // failing READ (including scan eligibility failures). All 44 bits/port use
    // the existing PIX reset/CE; legacy read-only status retains its full map.
    reg [5:0] first_step [0:1];
    reg [1:0] first_ack;
    reg [4:0] first_register [0:1];
    reg [15:0] first_expected [0:1], first_observed [0:1];
    // Passive observation only: the FIRST existing page-select WRITE's
    // ST/OP/PHYAD/REGAD/TA/DATA are sampled through the real pad input sync.
    // No output, OE, MDC, command, read sampling or state transition uses it.
    // LATENCY: sampled at existing phase3 CE; frozen at that WRITE's FINISH.
    reg [31:0] echo_shift;
    reg [5:0] echo_count;
    reg echo_oe_all;
    reg [31:0] write_echo_expected [0:1], write_echo_observed [0:1];
    reg [5:0] write_echo_count [0:1];
    reg [1:0] write_echo_valid, write_echo_oe_all;
    // PIX-only passive snapshot of the SAME first page-verification READ.
    // [47:32] early, [31:16] primary late; metadata [15] frozen,
    // [14:13] ACK sampled early/late, [12:11] ACK early/late,
    // [10:6]/[5:1] data counts, [0] first WRITE echo complete and equal.
    // LATENCY: frozen at existing S_FINISH; never feeds command/verification.
    reg [47:0] page_probe [0:1];
    reg early_ack_sampled,late_ack_sampled;
    reg [4:0] late_data_count;
    assign page_probe0=page_probe[0];
    assign page_probe1=page_probe[1];
    wire [159:0] reported_registers0=TRANSACTION_ACTIVE ?
        {first_step[0],first_ack[0],first_register[0],first_expected[0],first_observed[0],
         12'd0,write_echo_valid[0],write_echo_oe_all[0],write_echo_count[0],
         write_echo_expected[0],write_echo_observed[0],registers[0][31:0]} : registers[0];
    wire [159:0] reported_registers1=TRANSACTION_ACTIVE ?
        {first_step[1],first_ack[1],first_register[1],first_expected[1],first_observed[1],
         12'd0,write_echo_valid[1],write_echo_oe_all[1],write_echo_count[1],
         write_echo_expected[1],write_echo_observed[1],registers[1][31:0]} : registers[1];
    assign status0={ones_ids[0],zero_ids[0],ta_errors[0],any_id_ack[0],done[0],found[0],found_address[0],reported_registers0};
    assign status1={ones_ids[1],zero_ids[1],ta_errors[1],any_id_ack[1],done[1],found[1],found_address[1],reported_registers1};

    // Default-page 1C is NOT the delay register. Only the acknowledged 7/A4
    // selection below permits 1C accesses, at one exact-ID nonzero address.
    localparam [5:0] C_PAGE_R=0, C_ID1_R=1, C_ID2_R=2,
        C_PAGE_W=3, C_PAGE_V=4, C_EXT_R=5, C_EXT_W=6, C_EXT_V=7,
        C_BEFORE_R=8, C_BEFORE_V=9, C_DELAY_W=10,
        C_DELAY_V=11, C_DELAY_V2=12, C_EXT_RESTORE_W=13,
        C_EXT_RESTORE_V=14, C_PAGE_RESTORE_W=15, C_PAGE_RESTORE_V=16,
        C_RB_PAGE_W=24, C_RB_PAGE_V=25, C_RB_EXT_W=26, C_RB_EXT_V=27,
        C_RB_DELAY_W=28, C_RB_DELAY_V=29,
        C_CL_PAGE_W=32, C_CL_PAGE_V=33, C_CL_EXT_W=34, C_CL_EXT_V=35,
        C_CL_FINAL_PAGE_W=36, C_CL_FINAL_PAGE_V=37;
    localparam [7:0] E_NONE=8'h00, E_NO_NONZERO=8'h01,
        E_AMBIGUOUS=8'h02, E_SCAN_ID=8'h03, E_NO_ACK=8'h04,
        E_ORIGINAL_PAGE=8'h05, E_ID_CHANGED=8'h06,
        E_PAGE_VERIFY=8'h07, E_EXT_VERIFY=8'h08,
        E_BEFORE_INVALID=8'h09, E_BEFORE_CHANGED=8'h0a,
        E_CONFIG_VERIFY=8'h0b, E_EXT_RESTORE=8'h0c,
        E_PAGE_RESTORE=8'h0d, E_RB_PAGE=8'h0e, E_RB_EXT=8'h0f,
        E_RB_CONFIG=8'h10, E_CL_PAGE=8'h11, E_CL_EXT=8'h12,
        E_CL_FINAL_PAGE=8'h13, E_INTERNAL=8'h14;
    reg [31:0] nonzero_bitmap [0:1];
    reg [4:0] nonzero_count [0:1], delay_address [0:1];
    reg [1:0] candidate_exact;
    reg [15:0] saved_page [0:1], saved_ext [0:1];
    reg [15:0] delay_before [0:1], delay_after [0:1];
    reg [7:0] delay_error [0:1], delay_flags [0:1];
    reg [5:0] last_step [0:1], delay_step;
    reg delay_mode, command_write;
    reg [15:0] command_data;
    // Register the selected comparison target with the command, before the
    // long MDIO frame. Readback verification never traverses the live port
    // context mux and a 16-bit comparison in the same CE path.
    reg [15:0] command_expected /* synthesis syn_preserve=1 */;
    // One port runs at a time. These validity bits are local transaction
    // state, not new reset branches or CDC status. Unknown snapshots are 0
    // placeholders and must not be interpreted as measured configuration.
    reg page_valid, ext_valid, before_valid, page_touched, config_touched;
    // Default-page snapshots are observations, never inputs to RX/control.
    reg [15:0] readonly_page [0:1], readonly_rxerc [0:1];
    reg [9:0] readonly_ack [0:1];
    reg [1:0] readonly_scan_done, readonly_snapshot_done, readonly_page0;
    reg [3:0] readonly_step;
    wire [31:0] readonly_flags0={16'h524f,readonly_scan_done[0],
        (nonzero_count[0]==1),readonly_snapshot_done[0],readonly_page0[0],
        readonly_ack[0],(candidate_exact[0] && nonzero_count[0]==1),1'b1};
    wire [31:0] readonly_flags1={16'h524f,readonly_scan_done[1],
        (nonzero_count[1]==1),readonly_snapshot_done[1],readonly_page0[1],
        readonly_ack[1],(candidate_exact[1] && nonzero_count[1]==1),1'b1};
    assign delay_status0=P_READONLY_PROFILE ?
        {nonzero_bitmap[0],readonly_page[0],readonly_rxerc[0],readonly_flags0,
         22'd0,delay_address[0],nonzero_count[0]} : TRANSACTION_ACTIVE ?
        {nonzero_bitmap[0],saved_page[0],saved_ext[0],delay_before[0],delay_after[0],
         delay_error[0],delay_flags[0],delay_address[0],nonzero_count[0],last_step[0]} : 128'b0;
    assign delay_status1=P_READONLY_PROFILE ?
        {nonzero_bitmap[1],readonly_page[1],readonly_rxerc[1],readonly_flags1,
         22'd0,delay_address[1],nonzero_count[1]} : TRANSACTION_ACTIVE ?
        {nonzero_bitmap[1],saved_page[1],saved_ext[1],delay_before[1],delay_after[1],
         delay_error[1],delay_flags[1],delay_address[1],nonzero_count[1],last_step[1]} : 128'b0;

    reg [3:0] state;
    reg [SW-1:0] startup_count;
    reg [QW-1:0] quarter_count;
    reg [1:0] phase;
    reg active_port, scan_mode, scan_id_phase;
    reg [4:0] scan_address, command_address, command_register;
    reg [2:0] config_index;
    reg [6:0] bit_index;
    reg [15:0] read_shift, scan_id1;
    reg read_ack, scan_ack1;
    wire valid_scan_id = scan_ack1 && read_ack &&
        {scan_id1,read_shift}!=32'h00000000 && {scan_id1,read_shift}!=32'hffffffff;
    integer reset_port;

    function automatic [4:0] standard_register(input [2:0] index);
        begin
            case (index)
                0: standard_register=0;
                1,2: standard_register=1;
                3: standard_register=4;
                4: standard_register=5;
                5: standard_register=9;
                6: standard_register=10;
                default: standard_register=15;
            endcase
        end
    endfunction
    function automatic transmitted_bit(input [6:0] index,
        input [4:0] phy_address, input [4:0] reg_address,
        input is_write, input [15:0] write_data);
        begin
            if (index<32) transmitted_bit=1;
            else case (index)
                32: transmitted_bit=0; // ST=01
                33: transmitted_bit=1;
                34: transmitted_bit=!is_write; // READ=10, WRITE=01
                35: transmitted_bit=is_write;
                36: transmitted_bit=phy_address[4];
                37: transmitted_bit=phy_address[3];
                38: transmitted_bit=phy_address[2];
                39: transmitted_bit=phy_address[1];
                40: transmitted_bit=phy_address[0];
                41: transmitted_bit=reg_address[4];
                42: transmitted_bit=reg_address[3];
                43: transmitted_bit=reg_address[2];
                44: transmitted_bit=reg_address[1];
                45: transmitted_bit=reg_address[0];
                46: transmitted_bit=1; // WRITE TA=10, driven by host
                47: transmitted_bit=0;
                default: begin
                    if (is_write && index>=48 && index<=63)
                        transmitted_bit=write_data[63-index];
                    else transmitted_bit=1;
                end
            endcase
        end
    endfunction

    reg planned_write;
    reg [4:0] planned_register;
    reg [15:0] planned_data;
    reg verification_ok;
    reg [7:0] verification_error;
    reg [15:0] verification_expected;
    wire [15:0] selected_page=(saved_page[active_port]&16'hfff8)|16'h0007;
    wire [15:0] selected_ext=(saved_ext[active_port]&16'hff00)|16'h00a4;
    wire [15:0] configured_delay=(delay_before[active_port]&16'hc7ff)|16'h2000;
    // Fixed-width decode/muxes; no indexed register-file storage or clock.
    always @* begin
        planned_write=0; planned_register=31; planned_data=0;
        case (delay_step)
            C_ID1_R: planned_register=2;
            C_ID2_R: planned_register=3;
            C_PAGE_W,C_RB_PAGE_W,C_CL_PAGE_W: begin
                planned_write=1; planned_register=31; planned_data=selected_page;
            end
            C_EXT_R,C_EXT_V,C_EXT_RESTORE_V,C_RB_EXT_V,C_CL_EXT_V:
                planned_register=30;
            C_EXT_W,C_RB_EXT_W: begin
                planned_write=1; planned_register=30; planned_data=selected_ext;
            end
            C_BEFORE_R,C_BEFORE_V,C_DELAY_V,C_DELAY_V2,C_RB_DELAY_V:
                planned_register=28;
            C_DELAY_W: begin
                planned_write=1; planned_register=28; planned_data=configured_delay;
            end
            C_RB_DELAY_W: begin
                planned_write=1; planned_register=28; planned_data=delay_before[active_port];
            end
            C_EXT_RESTORE_W,C_CL_EXT_W: begin
                planned_write=1; planned_register=30; planned_data=saved_ext[active_port];
            end
            C_PAGE_RESTORE_W,C_CL_FINAL_PAGE_W: begin
                planned_write=1; planned_register=31; planned_data=saved_page[active_port];
            end
            default: begin end
        endcase
        // This is the actual comparison target, not READ command_data (zero).
        // Step0 compares only mask0007; step8 forbids FFFF; step5 only checks
        // ACK. The HUD encodes these kinds from the captured step, without
        // storing a second mask/kind register or changing verification logic.
        verification_expected=0;
        case (delay_step)
            C_ID1_R: verification_expected=16'h001c;
            C_ID2_R: verification_expected=16'hc915;
            C_PAGE_V,C_RB_PAGE_V,C_CL_PAGE_V: verification_expected=selected_page;
            C_EXT_V,C_RB_EXT_V: verification_expected=selected_ext;
            C_BEFORE_R: verification_expected=16'hffff;
            C_BEFORE_V,C_RB_DELAY_V: verification_expected=delay_before[active_port];
            C_DELAY_V,C_DELAY_V2: verification_expected=configured_delay;
            C_EXT_RESTORE_V,C_CL_EXT_V: verification_expected=saved_ext[active_port];
            C_PAGE_RESTORE_V,C_CL_FINAL_PAGE_V: verification_expected=saved_page[active_port];
            default: begin end
        endcase
        verification_ok=read_ack; verification_error=E_NONE;
        case (delay_step)
            C_PAGE_R: begin
                verification_ok=read_ack && read_shift[2:0]==command_expected[2:0];
                verification_error=E_ORIGINAL_PAGE;
            end
            C_ID1_R: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=E_ID_CHANGED;
            end
            C_ID2_R: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=E_ID_CHANGED;
            end
            C_PAGE_V,C_RB_PAGE_V,C_CL_PAGE_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                if (delay_step==C_RB_PAGE_V) verification_error=E_RB_PAGE;
                else if (delay_step==C_CL_PAGE_V) verification_error=E_CL_PAGE;
                else verification_error=E_PAGE_VERIFY;
            end
            C_EXT_V,C_RB_EXT_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=delay_step==C_RB_EXT_V ? E_RB_EXT : E_EXT_VERIFY;
            end
            C_BEFORE_R: begin
                verification_ok=read_ack && read_shift!=command_expected;
                verification_error=E_BEFORE_INVALID;
            end
            C_BEFORE_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=E_BEFORE_CHANGED;
            end
            C_DELAY_V,C_DELAY_V2: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=E_CONFIG_VERIFY;
            end
            C_EXT_RESTORE_V,C_CL_EXT_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=delay_step==C_CL_EXT_V ? E_CL_EXT : E_EXT_RESTORE;
            end
            C_PAGE_RESTORE_V,C_CL_FINAL_PAGE_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=delay_step==C_CL_FINAL_PAGE_V ? E_CL_FINAL_PAGE : E_PAGE_RESTORE;
            end
            C_RB_DELAY_V: begin
                verification_ok=read_ack && read_shift==command_expected;
                verification_error=E_RB_CONFIG;
            end
            default: begin end
        endcase
        if (!read_ack) verification_error=E_NO_ACK;
    end

    always @(posedge pix_clk or negedge pix_reset_released) begin
        if (!pix_reset_released) begin
            state<=S_WAIT; startup_count<=0; quarter_count<=0; phase<=0;
            active_port<=0; scan_mode<=1; scan_id_phase<=0; scan_address<=0;
            command_address<=0; command_register<=0; config_index<=0;
            bit_index<=0; read_shift<=0; read_ack<=0; scan_id1<=0; scan_ack1<=0;
            delay_mode<=0; delay_step<=C_PAGE_R; command_write<=0; command_data<=0;
            command_expected<=0;
            candidate_exact<=0; page_valid<=0; ext_valid<=0; before_valid<=0;
            readonly_scan_done<=0;readonly_snapshot_done<=0;readonly_page0<=0;readonly_step<=0;
            page_touched<=0; config_touched<=0;
            echo_shift<=32'd0; echo_count<=6'd0; echo_oe_all<=1'b0;
            write_echo_valid<=2'b00; write_echo_oe_all<=2'b00;
            early_ack_sampled<=0;late_ack_sampled<=0;late_data_count<=0;
            mdio_o<=2'b11; mdio_oe<=0; mdc<=0; found<=0; done<=0; any_id_ack<=0;
            for (reset_port=0;reset_port<2;reset_port=reset_port+1) begin
                registers[reset_port]<=0; found_address[reset_port]<=0;
                ta_errors[reset_port]<=0; zero_ids[reset_port]<=0; ones_ids[reset_port]<=0;
                nonzero_bitmap[reset_port]<=0; nonzero_count[reset_port]<=0;
                delay_address[reset_port]<=0; saved_page[reset_port]<=0;
                saved_ext[reset_port]<=0; delay_before[reset_port]<=0;
                delay_after[reset_port]<=0; delay_error[reset_port]<=E_NONE;
                delay_flags[reset_port]<=0; last_step[reset_port]<=6'd63;
                first_step[reset_port]<=6'd63; first_ack[reset_port]<=0;
                first_register[reset_port]<=0; first_expected[reset_port]<=0;
                first_observed[reset_port]<=0;
                write_echo_expected[reset_port]<=32'd0; write_echo_observed[reset_port]<=32'd0;
                write_echo_count[reset_port]<=6'd0;
                page_probe[reset_port]<=48'd0;
                readonly_page[reset_port]<=0;readonly_rxerc[reset_port]<=0;
                readonly_ack[reset_port]<=0;
            end
        end else begin
            case (state)
                S_WAIT: begin
                    if (P_STARTUP_CYCLES==0 || startup_count==P_STARTUP_CYCLES-1) begin
                        phase<=3;quarter_count<=0;bit_index<=0;state<=S_FLUSH;
                    end
                    else startup_count<=startup_count+1'b1;
                end
                S_FLUSH: begin
                    // PIX reset need not reset the PHY. Clock out any old read
                    // response before driving a new preamble; no bus contention.
                    mdio_oe<=0;
                    if (quarter_count==P_QUARTER_CYCLES-1) begin
                        quarter_count<=0;phase<=phase+1'b1;
                        if (phase==0) mdc[active_port]<=1;
                        if (phase==2) begin
                            mdc[active_port]<=0;
                            if (bit_index==31) state<=S_BEGIN;
                            else bit_index<=bit_index+1'b1;
                        end
                    end else quarter_count<=quarter_count+1'b1;
                end
                S_BEGIN: begin
                    if (P_READONLY_PROFILE && !scan_mode) begin
                        command_address<=delay_address[active_port];
                        command_register<=readonly_step==0 ? 5'd31 :
                            (readonly_step==9 ? 5'd24 : standard_register(readonly_step[2:0]-3'd1));
                        command_write<=0;command_data<=0;command_expected<=0;
                    end else if (TRANSACTION_ACTIVE && delay_mode) begin
                        command_address<=delay_address[active_port];
                        command_register<=planned_register;
                        // Structural second gate: probe may only write the two
                        // addressing selectors, even if an obsolete config or
                        // rollback step is reached. Never WRITE1C/BMCR/RXERC.
                        command_write<=planned_write && (!PROBE_ACTIVE ||
                            planned_register==5'd31 || planned_register==5'd30);
                        command_data<=planned_data;
                        command_expected<=verification_expected;
                    end else begin
                        command_address<=scan_mode ? scan_address :
                            (PROBE_ACTIVE ? delay_address[active_port] : found_address[active_port]);
                        command_register<=scan_mode ? (scan_id_phase ? 5'd3 : 5'd2) : standard_register(config_index);
                        command_write<=0; command_data<=0; command_expected<=0;
                    end
                    bit_index<=0; read_shift<=0; read_ack<=0;
                    echo_shift<=32'd0; echo_count<=6'd0; echo_oe_all<=1'b1;
                    early_ack_sampled<=0;late_ack_sampled<=0;late_data_count<=0;
                    // Start with a complete low interval, including between frames.
                    phase<=3; quarter_count<=0; mdc<=0;
                    mdio_o<=2'b11; mdio_oe<=active_port ? 2'b10 : 2'b01;
                    state<=S_BITS;
                end
                S_BITS: begin
                    if (quarter_count==P_QUARTER_CYCLES-1) begin
                        quarter_count<=0; phase<=phase+1'b1;
                        case (phase)
                            0: mdc[active_port]<=1;
                            1: begin
                                if (PROBE_ACTIVE && delay_mode && delay_step==C_PAGE_V &&
                                    !command_write && !page_probe[active_port][15]) begin
                                    // PHY launches on rising46..62. This early
                                    // high-quarter sample and next-index phase3
                                    // sample observe the same physical response bit.
                                    if (bit_index==46) begin
                                        echo_oe_all<=!mdio_sync[active_port];
                                        early_ack_sampled<=1;
                                    end
                                    if (bit_index>=47 && bit_index<=62) begin
                                        echo_shift<={16'd0,echo_shift[14:0],mdio_sync[active_port]};
                                        echo_count<=echo_count+6'd1;
                                    end
                                end
                            end
                            3: begin
                                if (TRANSACTION_ACTIVE && delay_mode && delay_step==C_PAGE_W &&
                                    command_write && !write_echo_valid[active_port] &&
                                    bit_index>=32 && bit_index<=63) begin
                                    echo_shift<={echo_shift[30:0],mdio_sync[active_port]};
                                    echo_count<=echo_count+6'd1;
                                    echo_oe_all<=echo_oe_all && mdio_oe[active_port];
                                end
                                // PHY launches TA0 after rise46 and data15..0 after
                                // rises47..62. Sample the following low midpoint,
                                // before rise47/48..63; high-phase would be one bit late.
                                // tCO<=300ns and two PIX sync cycles have elapsed.
                                if (!command_write && bit_index==47) read_ack<=!mdio_sync[active_port];
                                if (!command_write && bit_index>=48 && bit_index<=63)
                                    read_shift<={read_shift[14:0],mdio_sync[active_port]};
                                if (PROBE_ACTIVE && delay_mode && delay_step==C_PAGE_V &&
                                    !command_write && !page_probe[active_port][15]) begin
                                    if (bit_index==47) late_ack_sampled<=1;
                                    if (bit_index>=48 && bit_index<=63)
                                        late_data_count<=late_data_count+5'd1;
                                end
                            end
                            2: begin
                                mdc[active_port]<=0;
                                if (bit_index==64) begin mdio_oe<=0; state<=S_FINISH; end
                                else begin
                                    bit_index<=bit_index+1'b1;
                                    mdio_oe[active_port]<=command_write ? bit_index<63 : bit_index<45;
                                    mdio_o[active_port]<=transmitted_bit(bit_index+1'b1,command_address,command_register,command_write,command_data);
                                end
                            end
                            default: begin end
                        endcase
                    end else quarter_count<=quarter_count+1'b1;
                end
                S_FINISH: begin
                    if (PROBE_ACTIVE && delay_mode && delay_step==C_PAGE_V &&
                        !command_write && !page_probe[active_port][15]) begin
                        // Preserve raw bits even for missing ACK. Cleanup never
                        // overwrites this first-read snapshot.
                        page_probe[active_port]<={echo_shift[15:0],read_shift,
                            1'b1,early_ack_sampled,late_ack_sampled,echo_oe_all,read_ack,
                            echo_count[4:0],late_data_count,
                            (write_echo_valid[active_port] && write_echo_oe_all[active_port] &&
                             write_echo_count[active_port]==32 &&
                             write_echo_expected[active_port]==write_echo_observed[active_port])};
                    end
                    if (TRANSACTION_ACTIVE && delay_mode && delay_step==C_PAGE_W &&
                        command_write && !write_echo_valid[active_port]) begin
                        write_echo_expected[active_port]<={2'b01,2'b01,command_address,
                            command_register,2'b10,command_data};
                        write_echo_observed[active_port]<=echo_shift;
                        write_echo_count[active_port]<=echo_count;
                        write_echo_oe_all[active_port]<=echo_oe_all;
                        write_echo_valid[active_port]<=1'b1;
                    end
                    if (!command_write && !read_ack && ta_errors[active_port]!=8'hff)
                        ta_errors[active_port]<=ta_errors[active_port]+1'b1;
                    if (P_READONLY_PROFILE && !scan_mode) begin
                        if (readonly_step==0) begin
                            readonly_ack[active_port][8]<=read_ack;
                            readonly_page[active_port]<=read_ack ? read_shift : 16'd0;
                            readonly_page0[active_port]<=read_ack && read_shift[2:0]==0;
                            // Unknown page or PHY: do not mislabel a page-specific
                            // or unrelated read-clear register as RTL8211E RXERC.
                            if (!read_ack || read_shift[2:0]!=0 || !candidate_exact[active_port]) begin
                                readonly_snapshot_done[active_port]<=1;
                                state<=S_PORT_DONE;
                            end else begin readonly_step<=1;state<=S_BEGIN;end
                        end else if (readonly_step==9) begin
                            readonly_ack[active_port][9]<=read_ack;
                            readonly_rxerc[active_port]<=read_ack ? read_shift : 16'd0;
                            readonly_snapshot_done[active_port]<=1;
                            state<=S_PORT_DONE;
                        end else begin
                            readonly_ack[active_port][readonly_step-1'b1]<=read_ack;
                            case(readonly_step)
                                1:registers[active_port][47:32]<=read_ack ? read_shift : 16'd0;
                                2:registers[active_port][63:48]<=read_ack ? read_shift : 16'd0;
                                3:registers[active_port][79:64]<=read_ack ? read_shift : 16'd0;
                                4:registers[active_port][95:80]<=read_ack ? read_shift : 16'd0;
                                5:registers[active_port][111:96]<=read_ack ? read_shift : 16'd0;
                                6:registers[active_port][127:112]<=read_ack ? read_shift : 16'd0;
                                7:registers[active_port][143:128]<=read_ack ? read_shift : 16'd0;
                                8:registers[active_port][159:144]<=read_ack ? read_shift : 16'd0;
                                default:begin end
                            endcase
                            readonly_step<=readonly_step+1'b1;state<=S_BEGIN;
                        end
                    end else if (TRANSACTION_ACTIVE && delay_mode) begin
                        last_step[active_port]<=delay_step;
                        // Retain only acknowledged observations. Zero reset
                        // placeholders are never advertised as valid readback.
                        if (read_ack && delay_step==C_PAGE_R)
                            saved_page[active_port]<=read_shift;
                        if (read_ack && (delay_step==C_DELAY_V || delay_step==C_DELAY_V2))
                            delay_after[active_port]<=read_shift;
                        if (PROBE_ACTIVE && delay_step==C_BEFORE_V) begin
                            // Raw second observation survives mismatch/no-ACK;
                            // bit6 qualifies ACK, first-error/result qualifies equality.
                            delay_after[active_port]<=read_shift;
                            delay_flags[active_port][6]<=read_ack;
                        end
                        if (command_write) begin
                            // WRITE TA10 has no PHY ACK. A distinct following
                            // READ is mandatory for every selector/data write.
                            delay_step<=delay_step+1'b1; state<=S_BEGIN;
                            case (delay_step)
                                C_PAGE_W,C_RB_PAGE_W,C_CL_PAGE_W: begin
                                    page_touched<=1; delay_flags[active_port][4]<=0;
                                end
                                C_EXT_W,C_RB_EXT_W:
                                    delay_flags[active_port][5]<=0;
                                C_DELAY_W: begin
                                    config_touched<=1; delay_flags[active_port][0]<=1;
                                end
                                default: begin end
                            endcase
                        end else if (!verification_ok) begin
                            if (delay_error[active_port]==E_NONE) begin
                                delay_error[active_port]<=verification_error;
                                first_step[active_port]<=delay_step;
                                first_ack[active_port]<=read_ack;
                                first_register[active_port]<=command_register;
                                first_expected[active_port]<=command_expected;
                                first_observed[active_port]<=read_shift;
                            end
                            delay_flags[active_port][1]<=0;
                            if (delay_step<C_RB_PAGE_W) begin
                                if (config_touched && before_valid) begin
                                    delay_flags[active_port][2]<=1;
                                    delay_step<=C_RB_PAGE_W; state<=S_BEGIN;
                                end else if (page_touched && page_valid) begin
                                    delay_step<=ext_valid ? C_CL_PAGE_W : C_CL_FINAL_PAGE_W;
                                    state<=S_BEGIN;
                                end else state<=S_PORT_DONE;
                            end else if (delay_step<C_CL_PAGE_W) begin
                                // A rollback selection failure forbids 1C writes;
                                // a fresh, separately verified cleanup is bounded.
                                delay_step<=ext_valid ? C_CL_PAGE_W : C_CL_FINAL_PAGE_W;
                                state<=S_BEGIN;
                            end else if (delay_step!=C_CL_FINAL_PAGE_V) begin
                                // In particular, failed CL_PAGE_V skips WRITE30.
                                delay_step<=C_CL_FINAL_PAGE_W; state<=S_BEGIN;
                            end else state<=S_PORT_DONE;
                        end else begin
                            state<=S_BEGIN; delay_step<=delay_step+1'b1;
                            case (delay_step)
                                C_PAGE_R: begin saved_page[active_port]<=read_shift; page_valid<=1; end
                                C_EXT_R: begin saved_ext[active_port]<=read_shift; ext_valid<=1; end
                                C_BEFORE_R: begin delay_before[active_port]<=read_shift; before_valid<=1; end
                                C_EXT_RESTORE_V,C_CL_EXT_V:
                                    delay_flags[active_port][5]<=1;
                                C_PAGE_RESTORE_V: begin
                                    delay_flags[active_port][4]<=1;
                                    delay_flags[active_port][1]<=1;
                                    page_touched<=0; state<=S_PORT_DONE;
                                end
                                C_RB_DELAY_V: begin
                                    delay_flags[active_port][3]<=1; config_touched<=0;
                                    delay_step<=C_CL_PAGE_W;
                                end
                                C_CL_FINAL_PAGE_V: begin
                                    delay_flags[active_port][4]<=1;
                                    page_touched<=0; state<=S_PORT_DONE;
                                end
                                C_BEFORE_V: begin
                                    if (PROBE_ACTIVE) begin
                                        // Two actual acknowledged reads; leave all
                                        // delay bits untouched and restore selectors.
                                        delay_step<=C_EXT_RESTORE_W;
                                    end
                                end
                                C_ID1_R,C_ID2_R,C_PAGE_V,C_EXT_V,
                                C_DELAY_V,C_DELAY_V2,C_RB_PAGE_V,C_RB_EXT_V,
                                C_CL_PAGE_V: begin end
                                default: begin
                                    if (delay_error[active_port]==E_NONE)
                                        delay_error[active_port]<=E_INTERNAL;
                                    state<=S_PORT_DONE;
                                end
                            endcase
                        end
                    end else if (scan_mode) begin
                        if (read_ack) any_id_ack[active_port]<=1;
                        if (!scan_id_phase) begin
                            scan_id1<=read_shift; scan_ack1<=read_ack;
                            if (scan_address==0) registers[active_port][15:0]<=read_shift;
                            scan_id_phase<=1; state<=S_BEGIN;
                        end else begin
                            if (scan_address==0) registers[active_port][31:16]<=read_shift;
                            if (scan_ack1 && read_ack) begin
                                if ({scan_id1,read_shift}==0) zero_ids[active_port]<=zero_ids[active_port]+1'b1;
                                if ({scan_id1,read_shift}==32'hffffffff) ones_ids[active_port]<=ones_ids[active_port]+1'b1;
                            end
                            if (!found[active_port] && valid_scan_id) begin
                                found[active_port]<=1; found_address[active_port]<=scan_address;
                                registers[active_port][31:0]<={read_shift,scan_id1};
                            end
                            if ((TRANSACTION_ACTIVE || P_READONLY_PROFILE) && scan_address!=0 && valid_scan_id) begin
                                nonzero_bitmap[active_port][scan_address]<=1;
                                nonzero_count[active_port]<=nonzero_count[active_port]+1'b1;
                                if (nonzero_count[active_port]==0) begin
                                    delay_address[active_port]<=scan_address;
                                    candidate_exact[active_port]<={scan_id1,read_shift}==32'h001cc915;
                                    if(P_READONLY_PROFILE)
                                        registers[active_port][31:0]<={read_shift,scan_id1};
                                end
                            end
                            scan_id_phase<=0;
                            if (scan_address==31) state<=S_SCAN_COMPLETE;
                            else begin scan_address<=scan_address+1'b1; state<=S_BEGIN; end
                        end
                    end else begin
                        // Constant destinations keep the small status store in FFs.
                        case (config_index)
                            0: registers[active_port][47:32]<=read_shift;
                            1: registers[active_port][63:48]<=read_shift;
                            2: registers[active_port][79:64]<=read_shift;
                            3: registers[active_port][95:80]<=read_shift;
                            4: registers[active_port][111:96]<=read_shift;
                            5: registers[active_port][127:112]<=read_shift;
                            6: registers[active_port][143:128]<=read_shift;
                            7: registers[active_port][159:144]<=read_shift;
                        endcase
                        if (config_index==7) begin
                            if (TRANSACTION_ACTIVE && delay_flags[active_port][7]) begin
                                delay_mode<=1; delay_step<=C_PAGE_R; state<=S_BEGIN;
                            end else state<=S_PORT_DONE;
                        end
                        else begin config_index<=config_index+1'b1; state<=S_BEGIN; end
                    end
                end
                S_SCAN_COMPLETE: begin
                    if (TRANSACTION_ACTIVE) begin
                        if (nonzero_count[active_port]==0)
                            delay_error[active_port]<=E_NO_NONZERO;
                        else if (nonzero_count[active_port]!=1)
                            delay_error[active_port]<=E_AMBIGUOUS;
                        else if (!candidate_exact[active_port])
                            delay_error[active_port]<=E_SCAN_ID;
                        else delay_flags[active_port][7]<=1;
                    end
                    if (P_READONLY_PROFILE) begin
                        readonly_scan_done[active_port]<=1;
                        found[active_port]<=nonzero_count[active_port]==1;
                        if (nonzero_count[active_port]==1) begin
                            found_address[active_port]<=delay_address[active_port];
                            scan_mode<=0;readonly_step<=0;state<=S_BEGIN;
                        end else begin
                            readonly_snapshot_done[active_port]<=1;state<=S_PORT_DONE;
                        end
                    end else if (PROBE_ACTIVE) begin
                        // A selector-only probe needs no broadcast/default-page
                        // status sweep. Enter only after unique exact-ID selection;
                        // ineligible targets receive no further transaction.
                        if (nonzero_count[active_port]==1 && candidate_exact[active_port]) begin
                            scan_mode<=0;delay_mode<=1;delay_step<=C_PAGE_R;state<=S_BEGIN;
                        end else state<=S_PORT_DONE;
                    end else if (found[active_port]) begin
                        scan_mode<=0; config_index<=0; state<=S_BEGIN;
                    end else state<=S_PORT_DONE;
                end
                S_PORT_DONE: begin
                    // The last command already supplied one released idle clock
                    // (bit64). Add six complete high/released clocks before stop,
                    // satisfying RTL8211E 7.10.4 without a new clock or counter.
                    mdio_oe<=0;phase<=3;quarter_count<=0;bit_index<=0;state<=S_TAIL;
                end
                S_TAIL: begin
                    mdio_oe<=0;
                    if (quarter_count==P_QUARTER_CYCLES-1) begin
                        quarter_count<=0;phase<=phase+1'b1;
                        if (phase==0) mdc[active_port]<=1;
                        if (phase==2) begin
                            mdc[active_port]<=0;
                            if (bit_index==5) begin
                                done[active_port]<=1;
                            if (CONFIG_ACTIVE) delay_flags[active_port][6]<=1;
                                if (!active_port) begin
                                    active_port<=1;scan_mode<=1;scan_id_phase<=0;
                                    delay_mode<=0;page_valid<=0;ext_valid<=0;before_valid<=0;
                                    page_touched<=0;config_touched<=0;
                                    scan_address<=0;phase<=3;quarter_count<=0;bit_index<=0;state<=S_FLUSH;
                                end else state<=S_FROZEN;
                            end else bit_index<=bit_index+1'b1;
                        end
                    end else quarter_count<=quarter_count+1'b1;
                end
                default: begin mdio_oe<=0; mdc<=0; end
            endcase
        end
    end
endmodule
