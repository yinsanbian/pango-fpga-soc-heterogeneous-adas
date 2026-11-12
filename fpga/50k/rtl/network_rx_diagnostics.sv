`timescale 1ns/1ps
// Passive receive-path monitor. The caller supplies shared asynchronous reset
// assertion and local synchronous release for all four domains. In particular,
// net1_fifo_rst_n must NOT be the MAC's PLL-lock-qualified local reset: the
// mailbox toggle session survives a stopped receive clock and a MAC restart.
// LATENCY: MAC events counted one receive edge after their registration;
// snapshot delivery is variable (existing bundled-data handshake), no video delay.
module network_rx_diagnostics #(
    parameter integer P_SAMPLE_COUNTER_BITS = 16,
    parameter integer P_WATCHDOG_BITS = 22,
    parameter integer P_HEADER_CAPTURE = 0,
    parameter integer P_CONTROLLED_RAW = 0,
    parameter integer P_RAW_TIMEOUT_CYCLES = 1875000000,
    parameter integer P_RAW_WARMUP_CYCLES = 0,
    parameter integer P_RAW_PAGE_COUNTER_BITS = 26,
    parameter integer P_MAC_BOUNDARY_DIAGNOSTIC = 0,
    parameter integer P_BOUNDARY_PAGE_COUNTER_BITS = 27,
    parameter integer P_REJECT_CAPTURE = 0
)(
    input wire net0_clk, net1_clk, core_clk, pix_clk,
    input wire net0_rst_n, net1_fifo_rst_n, core_rst_n, pix_rst_n,
    input wire parser0_rst_n, parser1_rst_n, net1_locked,
    input wire gmii0_dv, gmii0_er, gmii1_dv, gmii1_er,
    input wire [7:0] gmii0_data, gmii1_data,
    input wire [31:0] net0_rx_packets, net0_rejected,
    input wire [31:0] net0_bad_header_count, net0_dropped_packet_count,
    input wire [31:0] net1_rx_packets, net1_rejected,
    input wire [31:0] net1_bad_header_count, net1_dropped_packet_count,
    input wire [7:0] net0_last_reject_flags, net1_last_reject_flags,
    input wire [2:0] net0_debug_events, net1_debug_events,
    input wire [31:0] net0_debug_state, net1_debug_state,
    input wire [11:0] net0_debug_eof_length, net1_debug_eof_length,
    input wire [7:0] net1_capture_data,
    input wire net1_capture_dv,net1_capture_er,
    input wire [258:0] net1_capture_checksums,
    input wire core_net_valid, core_net_ready,
    input wire [2:0] core_net_source,
    input wire [5:0] core_frame_valid,
    input wire [31:0] core_drop_count,
    input wire core_protocol_error,
    output wire [207:0] status0, status1,
    output wire [102:0] core_status,
    output reg [1:0] clock_alive,
    output wire pll_locked_pix,
    output wire [3:0] observer_health_pix,
    // Nine N1 receive counters, flat and un-muxed, for the UART beacon.
    // Order: {bank,udp,ip,hdr,pbad,fcs,rejected,good,raw}, all 32-bit.
    output wire [287:0] net1_counter_bundle
);
    reg [P_SAMPLE_COUNTER_BITS-1:0] net0_sample_counter;
    reg [P_SAMPLE_COUNTER_BITS-1:0] net1_sample_counter;
    reg [P_SAMPLE_COUNTER_BITS-1:0] core_sample_counter;
    reg [31:0] net0_raw_frames, net0_raw_errors;
    reg [31:0] net1_raw_frames, net1_raw_errors;
    reg net0_dv_previous, net1_dv_previous;
    reg net0_seen_dv, net1_seen_dv;
    reg [31:0] net0_accepted_beats, net1_accepted_beats;
    reg [P_WATCHDOG_BITS-1:0] net0_watchdog, net1_watchdog;
    // Flat N1 counter bundle for the UART beacon. Driven only by the port-1
    // observer instance below; zero when the boundary observer is not built.
    wire [287:0] net1_counters_p1;
    assign net1_counter_bundle = P_MAC_BOUNDARY_DIAGNOSTIC ? net1_counters_p1 : 288'd0;
    // Ordinary PIX-domain reset distribution, not a new CDC synchronizer.
    // ADS syn_preserve keeps this local fanout separate from equivalent
    // reset-release registers in unrelated pixel-processing branches.
    reg pix_reset_released /* synthesis syn_preserve=1 */;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) pix_reset_released<=0;
        else pix_reset_released<=1;
    end
    (* PAP_ASYNC_REG = 1 *) reg lock_meta, lock_sync;
    wire net0_snapshot_pulse, net1_snapshot_pulse;
    wire [31:0] net0_h00, net0_h04, net0_h08, net0_capture_ctl;
    wire [31:0] net1_h00, net1_h04, net1_h08, net1_capture_ctl;
    wire [127:0] net0_raw_page, net1_raw_page;
    wire [7:0] net0_raw_meta, net1_raw_meta;
    generate if (P_CONTROLLED_RAW) begin : g_controlled_raw
        reg [P_RAW_PAGE_COUNTER_BITS+2:0] page_count0, page_count1;
        wire valid0, valid1, done0, done1, fallback0, fallback1;
        wire timeout0, timeout1;
        wire [3:0] mask0, mask1;
        always @(posedge net0_clk or negedge net0_rst_n) begin
            if (!net0_rst_n) page_count0<=0;
            else page_count0<=page_count0+1'b1;
        end
        always @(posedge net1_clk or negedge net1_fifo_rst_n) begin
            if (!net1_fifo_rst_n) page_count1<=0;
            else page_count1<=page_count1+1'b1;
        end
        // Both complete pages and metadata cross only the existing mailbox.
        // Page number/done/session are already registered with all 120 bits.
        controlled_raw_capture #(.TIMEOUT_CYCLES(P_RAW_TIMEOUT_CYCLES),
            .P_WARMUP_CYCLES(P_RAW_WARMUP_CYCLES)) u_raw0(
            .clk(net0_clk),.rst_n(net0_rst_n),.data(gmii0_data),
            .dv(gmii0_dv),.er(gmii0_er),.session_id(4'h1),
            .preview_page(page_count0[P_RAW_PAGE_COUNTER_BITS+2:P_RAW_PAGE_COUNTER_BITS]),
            .page_bits(net0_raw_page),.page_valid(valid0),.done(done0),
            .matched_mask(mask0),.timed_out(timeout0),.fallback(fallback0),
            .fallback_waiting(),.no_ctl_activity(),.capture_samples());
        controlled_raw_capture #(.TIMEOUT_CYCLES(P_RAW_TIMEOUT_CYCLES),
            .P_WARMUP_CYCLES(P_RAW_WARMUP_CYCLES)) u_raw1(
            .clk(net1_clk),.rst_n(net1_fifo_rst_n),.data(gmii1_data),
            .dv(gmii1_dv),.er(gmii1_er),.session_id(4'h1),
            .preview_page(page_count1[P_RAW_PAGE_COUNTER_BITS+2:P_RAW_PAGE_COUNTER_BITS]),
            .page_bits(net1_raw_page),.page_valid(valid1),.done(done1),
            .matched_mask(mask1),.timed_out(timeout1),.fallback(fallback1),
            .fallback_waiting(),.no_ctl_activity(),.capture_samples());
        assign net0_raw_meta={done0,fallback0,timeout0,valid0,mask0};
        assign net1_raw_meta={done1,fallback1,timeout1,valid1,mask1};
    end else begin : g_no_controlled_raw
        assign net0_raw_page=0, net1_raw_page=0;
        assign net0_raw_meta=0, net1_raw_meta=0;
    end endgenerate
    generate if (P_HEADER_CAPTURE) begin : g_header_capture
        network_rx_prefix_capture u_prefix0 (
            .clk(net0_clk), .rst_n(net0_rst_n),
            .data(gmii0_data), .dv(gmii0_dv), .er(gmii0_er),
            .h00(net0_h00), .h04(net0_h04), .h08(net0_h08), .ctl(net0_capture_ctl));
        network_rx_prefix_capture u_prefix1 (
            .clk(net1_clk), .rst_n(net1_fifo_rst_n),
            .data(gmii1_data), .dv(gmii1_dv), .er(gmii1_er),
            .h00(net1_h00), .h04(net1_h04), .h08(net1_h08), .ctl(net1_capture_ctl));
    end else begin : g_no_header_capture
        assign net0_h00=0, net0_h04=0, net0_h08=0, net0_capture_ctl=0;
        assign net1_h00=0, net1_h04=0, net1_h08=0, net1_capture_ctl=0;
    end endgenerate
    wire [207:0] net0_legacy_snapshot = {
        6'b0, parser0_rst_n, net0_seen_dv,
        (P_CONTROLLED_RAW ? net0_raw_meta : net0_last_reject_flags),
        (P_CONTROLLED_RAW ? net0_raw_page[31:0] : (P_HEADER_CAPTURE ? net0_capture_ctl : net0_dropped_packet_count)),
        (P_CONTROLLED_RAW ? net0_raw_page[63:32] : (P_HEADER_CAPTURE ? net0_h08 : net0_bad_header_count)),
        net0_rejected, net0_rx_packets,
        (P_CONTROLLED_RAW ? net0_raw_page[127:96] : (P_HEADER_CAPTURE ? net0_h00 : net0_raw_errors)),
        (P_CONTROLLED_RAW ? net0_raw_page[95:64] : (P_HEADER_CAPTURE ? net0_h04 : net0_raw_frames))
    };
    wire [207:0] net1_legacy_snapshot = {
        6'b0, parser1_rst_n, net1_seen_dv,
        (P_CONTROLLED_RAW ? net1_raw_meta : net1_last_reject_flags),
        (P_CONTROLLED_RAW ? net1_raw_page[31:0] : (P_HEADER_CAPTURE ? net1_capture_ctl : net1_dropped_packet_count)),
        (P_CONTROLLED_RAW ? net1_raw_page[63:32] : (P_HEADER_CAPTURE ? net1_h08 : net1_bad_header_count)),
        net1_rejected, net1_rx_packets,
        (P_CONTROLLED_RAW ? net1_raw_page[127:96] : (P_HEADER_CAPTURE ? net1_h00 : net1_raw_errors)),
        (P_CONTROLLED_RAW ? net1_raw_page[95:64] : (P_HEADER_CAPTURE ? net1_h04 : net1_raw_frames))
    };
    wire [207:0] net0_snapshot, net1_snapshot;
    wire [1:0] observer_clocks={net1_clk,net0_clk};
    wire [1:0] observer_resets={net1_fifo_rst_n,net0_rst_n};
    wire [1:0] parser_resets={parser1_rst_n,parser0_rst_n};
    wire [5:0] observer_events={net1_debug_events,net0_debug_events};
    wire [63:0] observer_states={net1_debug_state,net0_debug_state};
    wire [23:0] observer_lengths={net1_debug_eof_length,net0_debug_eof_length};
    wire [15:0] observer_flags={net1_last_reject_flags,net0_last_reject_flags};
    wire [63:0] observer_raw_frames={net1_raw_frames,net0_raw_frames};
    wire [63:0] observer_raw_errors={net1_raw_errors,net0_raw_errors};
    wire [15:0] observer_raw_metadata={net1_raw_meta,net0_raw_meta};
    wire [415:0] legacy_snapshots={net1_legacy_snapshot,net0_legacy_snapshot};
    wire [415:0] observer_snapshots;
    wire [2:0] boundary_page[0:1];
    wire net1_snapshot_ready;
    wire [127:0] reject_metadata_page,reject_data_page;
    generate if(P_REJECT_CAPTURE && P_MAC_BOUNDARY_DIAGNOSTIC) begin : g_reject_capture
        gmii_reject_capture u_capture(.clk(net1_clk),.rst_n(net1_fifo_rst_n),
            .parser_rst_n(parser1_rst_n),.data(net1_capture_data),
            .dv(net1_capture_dv),.er(net1_capture_er),.events(net1_debug_events),
            .mac_state(net1_debug_state),.eof_length(net1_debug_eof_length),
            .reject_flags(net1_last_reject_flags),.debug_checksums(net1_capture_checksums),
            .page_is6(boundary_page[1]==3'd6),.page_is7(boundary_page[1]==3'd7),
            .publish_accept((&net1_sample_counter) && net1_snapshot_ready),
            .metadata_page(reject_metadata_page),.data_page(reject_data_page));
    end else begin : g_no_reject_capture
        assign reject_metadata_page=128'd0,reject_data_page=128'd0;
    end endgenerate
    genvar observer_port;
    generate for(observer_port=0;observer_port<2;observer_port=observer_port+1) begin : g_observer
        if(P_MAC_BOUNDARY_DIAGNOSTIC) begin : g_boundary
            wire parser_released=parser_resets[observer_port];
            wire [2:0] events=observer_events[observer_port*3 +:3];
            wire [31:0] mac_state=observer_states[observer_port*32 +:32];
            wire [11:0] eof_length=observer_lengths[observer_port*12 +:12];
            wire [7:0] flags=observer_flags[observer_port*8 +:8];
            wire [207:0] legacy=legacy_snapshots[observer_port*208 +:208];
            reg [31:0] sfd_count,eof_count,mac_dv_eof_count,parser_releases;
            reg [31:0] reject_fcs,reject_packet_bad,reject_header,reject_ip,reject_udp,reject_bank;
            reg [31:0] short_sfd_count,normal_sfd_count,long_sfd_count;
            reg [5:0] last_sfd_prefix;
            reg [31:0] first_reject;
            reg mac_dv_previous,parser_previous,parser_ever_released;
            reg parser_low_seen,parser_restart_seen;
            reg [P_BOUNDARY_PAGE_COUNTER_BITS-1:0] page_counter;
            reg [2:0] page;
            assign boundary_page[observer_port]=page;
            reg [31:0] slot0,slot1,slot2,slot3;
            wire [31:0] health_word={21'd0,parser_released,parser_restart_seen,
                parser_low_seen,observer_raw_metadata[observer_port*8 +:8]};
            always @(posedge observer_clocks[observer_port] or negedge observer_resets[observer_port]) begin
                if(!observer_resets[observer_port]) begin
                    sfd_count<=0;eof_count<=0;mac_dv_eof_count<=0;parser_releases<=0;
                    reject_fcs<=0;reject_packet_bad<=0;reject_header<=0;
                    reject_ip<=0;reject_udp<=0;reject_bank<=0;first_reject<=0;
                    short_sfd_count<=0;normal_sfd_count<=0;long_sfd_count<=0;
                    last_sfd_prefix<=0;
                    mac_dv_previous<=0;parser_previous<=0;parser_ever_released<=0;
                    parser_low_seen<=0;parser_restart_seen<=0;page_counter<=0;page<=0;
                end else begin
                    page_counter<=page_counter+1'b1;
                    if(&page_counter) begin
                        if(P_REJECT_CAPTURE && observer_port==1) page<=page+1'b1;
                        else page<=page==3'd5 ? 3'd0 : page+1'b1;
                    end
                    parser_previous<=parser_released;
                    if(!parser_released) begin
                        parser_low_seen<=1;
                        mac_dv_previous<=0;
                    end else begin
                        if(!parser_previous) begin
                            parser_releases<=parser_releases+1'b1;
                            if(parser_ever_released) parser_restart_seen<=1;
                            parser_ever_released<=1;
                        end
                        mac_dv_previous<=mac_state[20];
                        if(mac_dv_previous && !mac_state[20]) mac_dv_eof_count<=mac_dv_eof_count+1'b1;
                        if(events[0]) begin
                            sfd_count<=sfd_count+1'b1;
                            // Metadata and event are registered together by the
                            // MAC, so this next-edge observation is same-packet.
                            last_sfd_prefix<=mac_state[31:26];
                            if(mac_state[31:28]<4'd7) short_sfd_count<=short_sfd_count+1'b1;
                            else if(mac_state[31:28]==4'd7) normal_sfd_count<=normal_sfd_count+1'b1;
                            else long_sfd_count<=long_sfd_count+1'b1;
                        end
                        if(events[1]) eof_count<=eof_count+1'b1;
                        if(events[2]) begin
                            if(flags[0]) reject_fcs<=reject_fcs+1'b1;
                            if(flags[1]) reject_packet_bad<=reject_packet_bad+1'b1;
                            if(flags[2]) reject_header<=reject_header+1'b1;
                            if(flags[3]) reject_ip<=reject_ip+1'b1;
                            if(flags[4]) reject_udp<=reject_udp+1'b1;
                            if(flags[5]) reject_bank<=reject_bank+1'b1;
                            if(!first_reject[31]) first_reject<={1'b1,11'd0,eof_length,flags};
                        end
                    end
                end
            end
            always @(*) begin
                slot0=legacy[63:32];slot1=legacy[31:0];
                slot2=legacy[159:128];slot3=legacy[191:160];
                case(page)
                    3'd1: begin
                        slot0=observer_raw_frames[observer_port*32 +:32];
                        slot1=mac_dv_eof_count;slot2=sfd_count;slot3=eof_count;
                    end
                    3'd2: begin
                        slot0=reject_fcs;slot1=reject_packet_bad;slot2=reject_header;slot3=reject_bank;
                    end
                    3'd3: begin
                        slot0=reject_ip;slot1=reject_udp;slot2=first_reject;
                        slot3={12'd0,eof_length,flags};
                    end
                    3'd4: begin
                        slot0=parser_releases;slot1=observer_raw_errors[observer_port*32 +:32];
                        slot2=mac_state;slot3=health_word;
                    end
                    3'd5: begin
                        slot0=short_sfd_count;slot1=normal_sfd_count;slot2=long_sfd_count;
                        slot3={16'h5350,10'd0,last_sfd_prefix};
                    end
                    3'd6: if(P_REJECT_CAPTURE && observer_port==1) begin
                        {slot0,slot1,slot2,slot3}=reject_metadata_page;
                    end
                    3'd7: if(P_REJECT_CAPTURE && observer_port==1) begin
                        {slot0,slot1,slot2,slot3}=reject_data_page;
                    end
                    default: begin end
                endcase
            end
            assign observer_snapshots[observer_port*208 +:208]={((P_REJECT_CAPTURE && observer_port==1) ? 3'b110 : 3'b101),page,legacy[201:192],
                slot3,slot2,legacy[127:64],slot0,slot1};
            if(observer_port==1) begin : g_uart_counters
                assign net1_counters_p1={reject_bank,reject_udp,reject_ip,reject_header,
                    reject_packet_bad,reject_fcs,net1_rejected,net1_rx_packets,
                    observer_raw_frames[63:32]};
            end
        end else begin : g_legacy
            assign boundary_page[observer_port]=3'd0;
            assign observer_snapshots[observer_port*208 +:208]=legacy_snapshots[observer_port*208 +:208];
        end
    end endgenerate
    assign net0_snapshot=observer_snapshots[207:0];
    assign net1_snapshot=observer_snapshots[415:208];
    wire [102:0] core_snapshot = {
        core_protocol_error, core_frame_valid, core_drop_count,
        net1_accepted_beats, net0_accepted_beats
    };

    // These are observation counters only; none drive pixel, FIFO or DMA CE.
    // Frame count is the sampled GMII DV falling edge, even for rejected data.
    // RX_ER counts asserted receive-clock cycles, independently of DV.
    always @(posedge net0_clk or negedge net0_rst_n) begin
        if (!net0_rst_n) begin
            net0_sample_counter <= 0;
            net0_raw_frames <= 0; net0_raw_errors <= 0;
            net0_dv_previous <= 0; net0_seen_dv <= 0;
        end else begin
            net0_sample_counter <= net0_sample_counter + 1'b1;
            net0_dv_previous <= gmii0_dv;
            if (gmii0_dv) net0_seen_dv <= 1'b1;
            if (net0_dv_previous && !gmii0_dv)
                net0_raw_frames <= net0_raw_frames + 1'b1;
            if (gmii0_er) net0_raw_errors <= net0_raw_errors + 1'b1;
        end
    end
    always @(posedge net1_clk or negedge net1_fifo_rst_n) begin
        if (!net1_fifo_rst_n) begin
            net1_sample_counter <= 0;
            net1_raw_frames <= 0; net1_raw_errors <= 0;
            net1_dv_previous <= 0; net1_seen_dv <= 0;
        end else begin
            net1_sample_counter <= net1_sample_counter + 1'b1;
            net1_dv_previous <= gmii1_dv;
            if (gmii1_dv) net1_seen_dv <= 1'b1;
            if (net1_dv_previous && !gmii1_dv)
                net1_raw_frames <= net1_raw_frames + 1'b1;
            if (gmii1_er) net1_raw_errors <= net1_raw_errors + 1'b1;
        end
    end
    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            core_sample_counter <= 0;
            net0_accepted_beats <= 0; net1_accepted_beats <= 0;
        end else begin
            core_sample_counter <= core_sample_counter + 1'b1;
            if (core_net_valid && core_net_ready) begin
                case (core_net_source)
                    3'd2, 3'd3: net0_accepted_beats <= net0_accepted_beats + 1'b1;
                    3'd4, 3'd5: net1_accepted_beats <= net1_accepted_beats + 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    // Rollover requests are best effort: a busy mailbox skips that sample.
    // Counters continue running; the next accepted sample remains atomic.
    cdc_snapshot_mailbox #(.W(208)) u_net0_mailbox (
        .src_clk(net0_clk), .src_rst_n(net0_rst_n),
        .src_send(&net0_sample_counter), .src_data(net0_snapshot), .src_ready(),
        .dst_clk(pix_clk), .dst_rst_n(pix_reset_released),
        .dst_data(status0), .dst_pulse(net0_snapshot_pulse)
    );
    cdc_snapshot_mailbox #(.W(208)) u_net1_mailbox (
        .src_clk(net1_clk), .src_rst_n(net1_fifo_rst_n),
        .src_send(&net1_sample_counter), .src_data(net1_snapshot), .src_ready(net1_snapshot_ready),
        .dst_clk(pix_clk), .dst_rst_n(pix_reset_released),
        .dst_data(status1), .dst_pulse(net1_snapshot_pulse)
    );
    cdc_snapshot_mailbox #(.W(103)) u_core_mailbox (
        .src_clk(core_clk), .src_rst_n(core_rst_n),
        .src_send(&core_sample_counter), .src_data(core_snapshot), .src_ready(),
        .dst_clk(pix_clk), .dst_rst_n(pix_reset_released),
        .dst_data(core_status), .dst_pulse()
    );

    // A PIX-domain timeout observes delivered RX snapshots, rather than a
    // free-running counter bus or historical DV. At defaults the RX sample
    // period is 524.288 us (125 MHz) and timeout is 28.244 ms (148.5 MHz).
    always @(posedge pix_clk or negedge pix_reset_released) begin
        if (!pix_reset_released) begin
            net0_watchdog <= {P_WATCHDOG_BITS{1'b1}};
            net1_watchdog <= {P_WATCHDOG_BITS{1'b1}};
            clock_alive <= 0;
            lock_meta <= 0; lock_sync <= 0;
        end else begin
            lock_meta <= net1_locked; lock_sync <= lock_meta;
            if (net0_snapshot_pulse) begin
                net0_watchdog <= 0; clock_alive[0] <= 1'b1;
            end else if (&net0_watchdog) begin
                clock_alive[0] <= 1'b0;
            end else net0_watchdog <= net0_watchdog + 1'b1;
            if (net1_snapshot_pulse) begin
                net1_watchdog <= 0; clock_alive[1] <= 1'b1;
            end else if (&net1_watchdog) begin
                clock_alive[1] <= 1'b0;
            end else net1_watchdog <= net1_watchdog + 1'b1;
        end
    end
    assign pll_locked_pix = lock_sync;
    generate if(P_MAC_BOUNDARY_DIAGNOSTIC) begin : g_observer_health
        reg [1:0] was_alive,timeout_seen;
        reg was_locked,lock_loss_seen;
        always @(posedge pix_clk or negedge pix_reset_released) begin
            if(!pix_reset_released) begin
                was_alive<=0;timeout_seen<=0;was_locked<=0;lock_loss_seen<=0;
            end else begin
                if(clock_alive[0]) was_alive[0]<=1;
                if(clock_alive[1]) was_alive[1]<=1;
                if(was_alive[0] && !clock_alive[0]) timeout_seen[0]<=1;
                if(was_alive[1] && !clock_alive[1]) timeout_seen[1]<=1;
                if(lock_sync) was_locked<=1;
                if(was_locked && !lock_sync) lock_loss_seen<=1;
            end
        end
        assign observer_health_pix={1'b1,lock_loss_seen,timeout_seen};
    end else begin : g_no_observer_health
        assign observer_health_pix=4'd0;
    end endgenerate
endmodule

// A bounded, passive prefix recorder in the existing receive clock domain.
// Twelve 10-bit samples are small observation registers, never a frame store.
// The predecessor includes idle-side ER; all later samples are consecutive,
// even when DV falls early. Only the common session reset rearms capture.
module network_rx_prefix_capture (
    input wire clk, rst_n,
    input wire [7:0] data,
    input wire dv, er,
    output wire [31:0] h00, h04, h08, ctl
);
    reg [9:0] previous_sample;
    reg [9:0] samples [0:11];
    reg [3:0] sample_count;
    reg done;
    integer sample_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_sample<=0;
            sample_count<=0;
            done<=0;
            for (sample_index=0;sample_index<12;sample_index=sample_index+1)
                samples[sample_index]<=0;
        end else if (!done) begin
            previous_sample<={er,dv,data};
            if (sample_count==0) begin
                if (dv && !previous_sample[8]) begin
                    samples[0]<=previous_sample;
                    samples[1]<={er,dv,data};
                    sample_count<=2;
                end
            end else begin
                // Constant destinations avoid a dynamic write-port decoder.
                case (sample_count)
                    2: samples[2]<={er,dv,data};
                    3: samples[3]<={er,dv,data};
                    4: samples[4]<={er,dv,data};
                    5: samples[5]<={er,dv,data};
                    6: samples[6]<={er,dv,data};
                    7: samples[7]<={er,dv,data};
                    8: samples[8]<={er,dv,data};
                    9: samples[9]<={er,dv,data};
                    10: samples[10]<={er,dv,data};
                    11: samples[11]<={er,dv,data};
                    default: begin end
                endcase
                sample_count<=sample_count+1'b1;
                if (sample_count==11) done<=1;
            end
        end
    end
    assign h00={samples[0][7:0],samples[1][7:0],samples[2][7:0],samples[3][7:0]};
    assign h04={samples[4][7:0],samples[5][7:0],samples[6][7:0],samples[7][7:0]};
    assign h08={samples[8][7:0],samples[9][7:0],samples[10][7:0],samples[11][7:0]};
    wire [11:0] dv_mask, er_mask;
    genvar mask_index;
    generate for (mask_index=0;mask_index<12;mask_index=mask_index+1) begin : g_masks
        assign dv_mask[mask_index]=samples[mask_index][8];
        assign er_mask[mask_index]=samples[mask_index][9];
    end endgenerate
    assign ctl={3'b0,done,sample_count,er_mask,dv_mask};
endmodule
