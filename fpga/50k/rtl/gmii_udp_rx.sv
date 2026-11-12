`timescale 1ns/1ps
// GMII has no backpressure. A packet becomes visible only after its FCS,
// fixed IPv4 header, optional UDP checksum and destination have been checked.
// LATENCY: existing EOF/check/replay pipeline unchanged; debug_events register
// the actual decision edge and are consumed with same-packet flags next edge.
module gmii_udp_rx #(
    parameter [47:0] LOCAL_MAC = 48'h020000000050,
    parameter [31:0] LOCAL_IP = 32'hc0a80132,
    parameter [15:0] LOCAL_PORT = 16'd5000,
    parameter [15:0] CONTROL_PORT = 16'd0
)(
    input wire clk, input wire rst_n,
    input wire [7:0] gmii_rxd, input wire gmii_rx_dv, input wire gmii_rx_er,
    output reg udp_start, output reg udp_valid, output reg [7:0] udp_data,
    output reg udp_end, output reg udp_error,
    output reg [10:0] udp_payload_length,
    output reg [15:0] udp_destination_port,
    output reg [31:0] rx_packets, output reg [31:0] rx_rejected,
    output reg [7:0] last_reject_flags,
    output reg [2:0] debug_events,
    output wire [31:0] debug_state,
    output reg [11:0] debug_eof_length,
    output wire [258:0] debug_checksums
);
    reg [7:0] packet0 [0:2047];
    reg [7:0] packet1 [0:2047];
    reg [1:0] pending;
    reg pending_priority;
    reg [10:0] payload_len0, payload_len1;
    reg [15:0] payload_port0, payload_port1;
    reg receiving, writer_bank, writer_drop, packet_bad;
    // Prefix length/flags are observations only. GMII receivers must support
    // preamble shrinkage, including D5 as the first valid byte.
    reg [3:0] preamble_count;
    reg prefix_non55_seen, prefix_er_seen;
    reg [5:0] debug_sfd_prefix;
    reg [11:0] byte_count;
    reg [31:0] crc, ip_sum, udp_sum;
    reg [7:0] pair_high;
    reg [47:0] destination_mac;
    reg [31:0] source_ip, destination_ip;
    reg [15:0] ethertype, ip_length, ip_fragment, destination_port, udp_length, udp_checksum;
    reg [7:0] ip_vihl, ip_protocol;
    reg out_active, out_bank;
    reg [10:0] out_address, out_remaining;
    reg error_pending;
    reg [2:0] check_stage;
    reg check_bank, check_basic, check_ip_good, check_udp_zero;
    // These observations belong to the packet at EOF, not the next writer.
    // The original acceptance expression and its pipeline remain unchanged.
    reg [7:0] check_reject_flags_early;
    reg [10:0] check_payload_len;
    reg [15:0] check_destination_port;
    reg [31:0] check_ip_fold, check_udp_a, check_udp_b, check_udp_total, check_udp_fold;
    // Observation-only fanout. These bits never feed receive/replay control.
    assign debug_state={debug_sfd_prefix,preamble_count,gmii_rx_er,gmii_rx_dv,
        packet_bad,writer_drop,pending,receiving,check_stage,byte_count};
    // Passive existing-Q export only; no new receive/check/replay state.
    assign debug_checksums={check_basic,check_ip_good,check_udp_zero,
        check_udp_fold,check_udp_total,check_udp_b,check_udp_a,
        check_ip_fold,udp_sum,ip_sum,crc};
    wire bank0_busy = pending[0] || (out_active && !out_bank);
    wire bank1_busy = pending[1] || (out_active && out_bank);
    // A replay reads from Ethernet byte 42, one byte/clock. Incoming writes
    // start at byte 0, one byte/clock. When both banks are occupied, reuse
    // the bank being read (or selected for replay this clock): every write
    // remains strictly behind its old read address. This handles consecutive
    // short final packets following a full-sized packet without a third RAM.
    wire pending_bank = pending[0] && (!pending[1] || !pending_priority) ? 1'b0 : 1'b1;
    wire replay_bank = out_active ? out_bank : pending_bank;
    wire [1:0] waiting_pending = !out_active && pending!=0 ?
        (pending & (pending_bank ? 2'b01 : 2'b10)) : pending;
    // A bank can contain the tail of an old replay AND a newer complete
    // pending packet in already-read addresses. Never overwrite that packet.
    wire recycle_blocked = out_active && pending[out_bank];
    wire next_writer_bank = !bank0_busy ? 1'b0 : (!bank1_busy ? 1'b1 : replay_bank);

    function [31:0] crc_byte;
        input [31:0] old_crc; input [7:0] value;
        reg [31:0] c; integer k;
        begin
            c = old_crc ^ {24'd0,value};
            for (k=0; k<8; k=k+1) c = c[0] ? ((c >> 1) ^ 32'hedb88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction
    function [15:0] fold_sum;
        input [31:0] value;
        reg [31:0] t;
        begin
            t = (value & 32'hffff) + (value >> 16);
            t = (t & 32'hffff) + (t >> 16);
            fold_sum = t[15:0];
        end
    endfunction
    wire [15:0] expected_frame_length = (ip_length < 16'd46) ? 16'd64 : (ip_length + 16'd18);
    wire header_basic = (destination_mac == LOCAL_MAC || destination_mac == 48'hffffffffffff) &&
        ethertype == 16'h0800 && ip_vihl == 8'h45 && ip_protocol == 8'd17 &&
        (ip_fragment & 16'hbfff) == 0 && destination_ip == LOCAL_IP &&
        (destination_port == LOCAL_PORT || (CONTROL_PORT != 0 && destination_port == CONTROL_PORT)) &&
        ip_length >= 16'd28 && ip_length <= 16'd1500 && udp_length >= 16'd8 &&
        udp_length == (ip_length - 16'd20) && byte_count == expected_frame_length;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending<=0; pending_priority<=0; receiving<=0; preamble_count<=0; writer_bank<=0; writer_drop<=0; packet_bad<=0;
            prefix_non55_seen<=0;prefix_er_seen<=0;debug_sfd_prefix<=0;
            byte_count<=0; crc<=32'hffffffff; ip_sum<=0; udp_sum<=0; pair_high<=0;
            destination_mac<=0; source_ip<=0; destination_ip<=0; ethertype<=0; ip_length<=0;
            ip_fragment<=0; destination_port<=0; udp_length<=0; udp_checksum<=0; ip_vihl<=0; ip_protocol<=0;
            out_active<=0; out_bank<=0; out_address<=0; out_remaining<=0;
            payload_len0<=0; payload_len1<=0; payload_port0<=0; payload_port1<=0; error_pending<=0;
            udp_payload_length<=0; udp_destination_port<=0; check_destination_port<=0;
            check_stage<=0; check_bank<=0; check_basic<=0; check_ip_good<=0; check_udp_zero<=0;
            check_reject_flags_early<=0;last_reject_flags<=0;
            check_payload_len<=0;check_ip_fold<=0;check_udp_a<=0;check_udp_b<=0;check_udp_total<=0;check_udp_fold<=0;
            udp_start<=0; udp_valid<=0; udp_data<=0; udp_end<=0; udp_error<=0; rx_packets<=0; rx_rejected<=0;
            debug_events<=3'd0;debug_eof_length<=12'd0;
        end else begin
            udp_start<=0; udp_valid<=0; udp_end<=0; udp_error<=0;
            debug_events<=3'd0;
            // Four clocks after EOF, well inside the minimum 12-byte IFG plus
            // eight preamble/SFD clocks. Keep the end-around carry off the
            // destination-IP -> packet-publication critical path.
            case(check_stage)
                1:begin
                    check_udp_total<=check_udp_a+check_udp_b;
                    check_ip_good<=(check_ip_fold==32'hffff || check_ip_fold==32'h1fffe);
                    check_stage<=2;
                end
                2:begin
                    check_udp_fold<={16'd0,check_udp_total[15:0]}+{16'd0,check_udp_total[31:16]};
                    check_stage<=3;
                end
                3:begin
                    check_stage<=0;
                    // A single folded sum is at most 0x1fffe. Both of these
                    // values fold to 0xffff; no second carry chain is needed.
                    if(check_basic && check_ip_good && (check_udp_zero ||
                        check_udp_fold==32'hffff || check_udp_fold==32'h1fffe))begin
                        pending[check_bank]<=1;rx_packets<=rx_packets+1'b1;
                        if(waiting_pending==0)pending_priority<=check_bank;
                        else if(waiting_pending==1)pending_priority<=0;
                        else if(waiting_pending==2)pending_priority<=1;
                        if(check_bank)begin payload_len1<=check_payload_len;payload_port1<=check_destination_port;end
                        else begin payload_len0<=check_payload_len;payload_port0<=check_destination_port;end
                    end else begin
                        rx_rejected<=rx_rejected+1'b1;error_pending<=1;
                        debug_events[2]<=1'b1;
                        // Bits 0/1/2/5 were captured at this packet's EOF.
                        // Bits 3/4 use this packet's existing checksum stages.
                        // Successful packets retain the latest rejection.
                        last_reject_flags<={check_reject_flags_early[7:5],
                            !(check_udp_zero || check_udp_fold==32'hffff || check_udp_fold==32'h1fffe),
                            !check_ip_good,check_reject_flags_early[2:0]};
                    end
                end
                default:begin end
            endcase
            // A rejected packet's notification cannot interrupt an older valid replay.
            if (!out_active && pending == 0 && error_pending) begin udp_error<=1; error_pending<=0; end
            if (!out_active) begin
                if (pending!=0) begin
                    out_active<=1;out_bank<=pending_bank;out_address<=11'd42;
                    out_remaining<=pending_bank ? payload_len1 : payload_len0;
                    pending[pending_bank]<=0;udp_start<=1;
                    udp_payload_length<=pending_bank ? payload_len1 : payload_len0;
                    udp_destination_port<=pending_bank ? payload_port1 : payload_port0;
                end
            end else begin
                udp_valid<=1;
                udp_data<=out_bank ? packet1[out_address] : packet0[out_address];
                out_address<=out_address+1'b1; out_remaining<=out_remaining-1'b1;
                if (out_remaining == 1) begin out_active<=0; udp_end<=1; end
            end
            if (gmii_rx_dv) begin
                if (!receiving) begin
                    prefix_er_seen<=prefix_er_seen || gmii_rx_er;
                    if (gmii_rxd == 8'h55) begin
                        if (preamble_count != 4'hf) preamble_count<=preamble_count+1'b1;
                    end else if (gmii_rxd == 8'hd5) begin
                        receiving<=1; preamble_count<=0; byte_count<=0;
                        debug_events[0]<=1'b1;
                        debug_sfd_prefix<={preamble_count,prefix_non55_seen,
                            prefix_er_seen || gmii_rx_er};
                        writer_bank<=next_writer_bank;
                        writer_drop<=bank0_busy && bank1_busy && recycle_blocked;packet_bad<=gmii_rx_er;
                        crc<=32'hffffffff; ip_sum<=0; udp_sum<=0; pair_high<=0;
                        destination_mac<=0; source_ip<=0; destination_ip<=0; ethertype<=0; ip_length<=0;
                        ip_fragment<=0; destination_port<=0; udp_length<=0; udp_checksum<=0; ip_vihl<=0; ip_protocol<=0;
                    end else begin preamble_count<=0;prefix_non55_seen<=1;end
                end else begin
                    if (byte_count < 2048 && !writer_drop) begin
                        if (writer_bank) packet1[byte_count[10:0]]<=gmii_rxd;
                        else packet0[byte_count[10:0]]<=gmii_rxd;
                    end
                    if (byte_count < 4095) byte_count<=byte_count+1'b1;
                    if (byte_count >= 1518 || gmii_rx_er) packet_bad<=1;
                    crc<=crc_byte(crc,gmii_rxd);
                    if (byte_count < 6) destination_mac<={destination_mac[39:0],gmii_rxd};
                    case (byte_count)
                        12,13: ethertype<={ethertype[7:0],gmii_rxd};
                        14: ip_vihl<=gmii_rxd;
                        16,17: ip_length<={ip_length[7:0],gmii_rxd};
                        20,21: ip_fragment<={ip_fragment[7:0],gmii_rxd};
                        23: ip_protocol<=gmii_rxd;
                        26,27,28,29: source_ip<={source_ip[23:0],gmii_rxd};
                        30,31,32,33: destination_ip<={destination_ip[23:0],gmii_rxd};
                        36,37: destination_port<={destination_port[7:0],gmii_rxd};
                        38,39: udp_length<={udp_length[7:0],gmii_rxd};
                        40,41: udp_checksum<={udp_checksum[7:0],gmii_rxd};
                        default: begin end
                    endcase
                    if (byte_count >= 14 && byte_count < 34) begin
                        if (!byte_count[0]) pair_high<=gmii_rxd;
                        else ip_sum<=ip_sum+{16'd0,pair_high,gmii_rxd};
                    end else if (byte_count >= 34 && byte_count < (14+ip_length)) begin
                        if (!byte_count[0]) pair_high<=gmii_rxd;
                        else udp_sum<=udp_sum+{16'd0,pair_high,gmii_rxd};
                    end
                end
            end else begin
                preamble_count<=0;
                prefix_non55_seen<=0;prefix_er_seen<=0;
                if (receiving) begin
                    receiving<=0;
                    debug_events[1]<=1'b1;debug_eof_length<=byte_count;
                    check_stage<=1;check_bank<=writer_bank;
                    check_payload_len<=udp_length-16'd8;
                    check_destination_port<=destination_port;
                    check_basic<=!packet_bad && !writer_drop && crc==32'hdebb20e3 && header_basic && udp_length>8;
                    check_reject_flags_early<={2'b00,writer_drop,2'b00,
                        !(header_basic && udp_length>8),packet_bad,crc!=32'hdebb20e3};
                    check_udp_zero<=udp_checksum==0;
                    check_ip_fold<={16'd0,ip_sum[15:0]}+{16'd0,ip_sum[31:16]};
                    check_udp_a<=({16'd0,source_ip[31:16]}+{16'd0,source_ip[15:0]})+
                        ({16'd0,destination_ip[31:16]}+{16'd0,destination_ip[15:0]});
                    check_udp_b<=udp_sum+(32'd17+{16'd0,udp_length})+
                        (udp_length[0]?{16'd0,pair_high,8'd0}:32'd0);
                end
            end
        end
    end
endmodule
