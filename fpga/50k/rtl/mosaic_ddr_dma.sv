`timescale 1ns/1ps

// DDR3_50H uses a trimmed AXI interface: addresses are 32-bit words,
// each 256-bit beat advances by eight words, WREADY consumes a beat, and
// the read channel cannot be stalled. This module reserves a complete
// read burst before issuing AR and drains that burst through ready/valid.
module mosaic_ddr_dma #(
    parameter integer SRC_W = 960,
    parameter integer SRC_H = 540,
    parameter integer OUT_W = 1920,
    parameter integer OUT_H = 1080,
    parameter integer ADDR_W = 28,
    parameter integer FRAME_BLOCKS = (SRC_W * SRC_H) / 16,
    // Set zero in the two-layout production top: prune camera-only mapping.
    parameter integer P_CAMERA_ONLY_LAYOUT = 1,
    parameter integer P_M2_ONLY = 0
) (
    input  wire                 mem_clk,
    input  wire                 rst_n,
    input  wire [2:0]           wr_valid,
    output reg  [2:0]           wr_ready,
    input  wire [8:0]           wr_source,
    input  wire [56:0]          wr_block,
    input  wire [95:0]          wr_frame,
    input  wire [767:0]         wr_data,
    input  wire                 line_req_valid,
    output wire                 line_req_ready,
    input  wire [10:0]          line_req_y,
    input  wire [1:0]           line_req_mode,
    input  wire                 line_req_frame_start,
    input  wire [7:0]           line_req_epoch,
    input  wire [31:0]          line_req_frame_id,
    output wire                 line_data_valid,
    input  wire                 line_data_ready,
    output wire [255:0]         line_data,
    output wire [10:0]          line_data_y,
    output wire [6:0]           line_data_index,
    output wire [7:0]           line_data_epoch,
    output wire                 line_data_source_valid,
    output reg  [ADDR_W-1:0]    axi_awaddr,
    output wire [3:0]          axi_awid,
    output wire [3:0]          axi_awlen,
    input  wire                 axi_awready,
    output wire                 axi_awvalid,
    output wire [255:0]        axi_wdata,
    output wire [31:0]         axi_wstrb,
    input  wire                 axi_wready,
    input  wire                 axi_wusero_last,
    output reg  [ADDR_W-1:0]    axi_araddr,
    output wire [3:0]          axi_arid,
    output wire [3:0]          axi_arlen,
    input  wire                 axi_arready,
    output wire                 axi_arvalid,
    input  wire [255:0]        axi_rdata,
    input  wire                 axi_rvalid,
    input  wire [3:0]          axi_rid,
    input  wire                 axi_rlast,
    output wire [5:0]          debug_frame_valid,
    output wire [5:0]          debug_display_valid,
    output reg  [31:0]         debug_drop_count,
    // Write-path diagnosis: rejections split by source, and how many cycles the
    // write FSM spends waiting on the DDR address/data channels versus how many
    // the read path spends draining. Ratios between two UART samples show which
    // side actually owns the bus.
    output reg  [31:0]         debug_drop_s4,
    output reg  [31:0]         debug_drop_s5,
    output reg  [31:0]         debug_cyc_addr,
    output reg  [31:0]         debug_cyc_data,
    output reg  [31:0]         debug_cyc_drain,
    output reg  [31:0]         debug_cyc_total,
    output reg                  debug_protocol_error,
    output reg                  snapshot_pulse,
    output reg [7:0]            snapshot_epoch,
    output reg [31:0]           snapshot_frame_id,
    output wire [191:0]         snapshot_source_frames
);
    localparam integer HALF_BLOCKS = SRC_W / 16;
    localparam integer LINE_BLOCKS = OUT_W / 16;
    localparam integer PAGE_WORDS = FRAME_BLOCKS * 8;
    localparam integer SOURCE_WORDS = PAGE_WORDS * 3;
    localparam [2:0] W_IDLE = 3'd0, W_ADDR = 3'd1, W_DATA = 3'd2,
                     W_PREP = 3'd3, W_VALIDATE = 3'd4, W_COLLECT = 3'd5;
    // Eight consecutive 16-pixel blocks form one 256-byte AXI burst. Addresses
    // inside a burst are contiguous, so one AW handshake covers 8 beats.
    localparam integer BW = 8;
    localparam [2:0] R_IDLE = 3'd0, R_PREP = 3'd1, R_ADDR = 3'd2,
                     R_RECV = 3'd3, R_DRAIN = 3'd4;

    reg [2:0] write_state;
    reg [1:0] round_robin;
    reg [255:0] write_data;
    reg [2:0] write_source;
    reg [18:0] write_block;
    reg [31:0] write_frame;
    reg [1:0] write_commit_page;
    reg write_is_last;
    reg [255:0] bbuf [0:BW-1];
    reg [3:0]  bcnt, blen, widx;
    reg [1:0]  bport, bpage;
    reg [2:0]  bsrc;
    reg [18:0] bblk;
    reg [31:0] bfrm;
    reg        bactive, b_last;
    reg [1:0]  write_port;
    reg [5:0] frame_valid, display_valid, source_active;
    reg [1:0] latest_page [0:5];
    reg [1:0] display_page [0:5];
    reg [1:0] source_write_page [0:5];
    reg [31:0] source_frame [0:5];
    reg [31:0] latest_frame [0:5];
    reg [31:0] display_frame [0:5];
    reg [18:0] source_next_block [0:5];
    reg [2:0] read_state;
    reg [10:0] read_y;
    reg [7:0] read_epoch;
    reg [10:0] read_row;
    reg [2:0] read_left_source, read_right_source;
    reg [1:0] read_left_page, read_right_page;
    reg read_left_valid, read_right_valid;
    reg [6:0] read_index;
    reg [4:0] burst_beats;
    reg [4:0] receive_count;
    reg [4:0] drain_count;
    reg [255:0] read_buffer [0:15];
    reg buffer_is_zero;
    reg read_protocol_error;

    function automatic [ADDR_W-1:0] block_address;
        input [2:0] source;
        input [1:0] page;
        input [18:0] block_number;
        begin
            block_address = source * SOURCE_WORDS + page * PAGE_WORDS
                          + block_number * 8;
        end
    endfunction

    // A writer never reuses the latest complete frame or a frame held by
    // the HDMI reader. The remaining page is available even if input and
    // output frame rates differ.
    function automatic [1:0] free_page;
        input [2:0] source;
        integer candidate;
        reg found;
        begin
            free_page = 2'd0;
            found = 1'b0;
            for (candidate = 0; candidate < 3; candidate = candidate + 1) begin
                if (!found && (!frame_valid[source] || latest_page[source] != candidate)
                           && (!display_valid[source] || display_page[source] != candidate)) begin
                    free_page = candidate;
                    found = 1'b1;
                end
            end
        end
    endfunction

    integer candidate_port, offset;
    reg chosen_valid;
    reg [1:0] chosen_port;
    reg [2:0] chosen_source;
    reg [18:0] chosen_block;
    reg [31:0] chosen_frame;
    // Next beat from the port that owns the open burst, and whether it keeps
    // the run contiguous. Only a contiguous run may share one AW handshake.
    wire [2:0]  cs_source = wr_source[bport*3 +: 3];
    wire [18:0] cs_block  = wr_block[bport*19 +: 19];
    wire [31:0] cs_frame  = wr_frame[bport*32 +: 32];
    wire burst_more = bactive && (bcnt < BW) && wr_valid[bport]
                   && (cs_source == bsrc) && (cs_frame == bfrm)
                   && (cs_block == bblk + bcnt);
    always @(*) begin
        chosen_valid = 1'b0;
        chosen_port = 2'd0;
        wr_ready = 3'b000;
        if (rst_n && (write_state == W_COLLECT || write_state == W_IDLE)) begin
            if (bactive) begin
                if (burst_more) wr_ready[bport] = 1'b1;
            end else if (write_state == W_IDLE) begin
                for (offset = 0; offset < 3; offset = offset + 1) begin
                    candidate_port = round_robin + offset;
                    if (candidate_port >= 3)
                        candidate_port = candidate_port - 3;
                    if (!chosen_valid && wr_valid[candidate_port]) begin
                        chosen_port = candidate_port;
                        chosen_valid = 1'b1;
                        wr_ready[candidate_port] = 1'b1;
                    end
                end
            end
        end
        chosen_source = wr_source[chosen_port*3 +: 3];
        chosen_block = wr_block[chosen_port*19 +: 19];
        chosen_frame = wr_frame[chosen_port*32 +: 32];
    end

    // Validate only the registered token. FIFO RAM outputs must not feed
    // sequence/page comparators and the 256-bit write-data clock enable
    // in one cycle. Ownership is selected when validation occurs.
    reg [1:0] token_page;
    reg token_sequence_ok;
    always @(*) begin
        token_page = 2'd0;
        token_sequence_ok = 1'b0;
        if (write_source < 6 && write_block < FRAME_BLOCKS) begin
            if (write_block == 0) begin
                token_page = free_page(write_source);
                token_sequence_ok = 1'b1;
            end else begin
                token_page = source_write_page[write_source];
                token_sequence_ok = source_active[write_source]
                                  && source_frame[write_source] == write_frame
                                  && source_next_block[write_source] == write_block;
            end
        end
    end

    wire write_accepted = axi_wready &&
        ((write_state == W_DATA) || (write_state == W_ADDR && axi_awready));
    assign axi_awvalid = rst_n && write_state == W_ADDR;
    assign axi_awid = 4'd0;
    assign axi_awlen = blen - 1'b1;
    assign axi_wdata = bbuf[widx];
    assign axi_wstrb = 32'hffffffff;
    assign debug_frame_valid = frame_valid;
    assign debug_display_valid = display_valid;
    genvar sf;
    generate for(sf=0;sf<6;sf=sf+1) begin:g_snapshot
        assign snapshot_source_frames[sf*32 +:32]=display_frame[sf];
    end endgenerate

    integer source_number;
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) begin
            write_state <= W_IDLE;
            round_robin <= 2'd0;
            write_data <= 256'd0;
            write_source <= 3'd0;
            write_block <= 19'd0;
            write_frame <= 32'd0;
            write_commit_page <= 2'd0;
            write_is_last <= 1'b0;
            axi_awaddr <= {ADDR_W{1'b0}};
            frame_valid <= 6'd0;
            display_valid <= 6'd0;
            source_active <= 6'd0;
            debug_drop_count <= 32'd0;
            debug_drop_s4 <= 32'd0;
            debug_drop_s5 <= 32'd0;
            debug_cyc_addr <= 32'd0;
            debug_cyc_data <= 32'd0;
            debug_cyc_drain <= 32'd0;
            debug_cyc_total <= 32'd0;
            debug_protocol_error <= 1'b0;
            snapshot_pulse <= 1'b0;
            snapshot_epoch <= 8'd0;
            snapshot_frame_id <= 32'd0;
            for (source_number = 0; source_number < 6; source_number = source_number + 1) begin
                latest_page[source_number] <= 2'd0;
                display_page[source_number] <= 2'd0;
                source_write_page[source_number] <= 2'd0;
                source_frame[source_number] <= 32'd0;
                latest_frame[source_number] <= 32'd0;
                display_frame[source_number] <= 32'd0;
                source_next_block[source_number] <= 19'd0;
            end
        end else begin
            snapshot_pulse <= 1'b0;
            // Busy-cycle accounting. Ratios between two UART samples say which
            // side owns the DDR port, so the throughput fix targets the right one.
            debug_cyc_total <= debug_cyc_total + 1'b1;
            if (write_state == W_ADDR) debug_cyc_addr <= debug_cyc_addr + 1'b1;
            if (write_state == W_DATA) debug_cyc_data <= debug_cyc_data + 1'b1;
            if (read_state == R_RECV || read_state == R_DRAIN)
                debug_cyc_drain <= debug_cyc_drain + 1'b1;
            if (read_protocol_error)
                debug_protocol_error <= 1'b1;
            if (line_req_valid && line_req_ready && line_req_frame_start) begin
                display_valid <= frame_valid;
                snapshot_pulse <= 1'b1;
                snapshot_epoch <= line_req_epoch;
                snapshot_frame_id <= line_req_frame_id;
                for (source_number = 0; source_number < 6; source_number = source_number + 1) begin
                    display_page[source_number] <= latest_page[source_number];
                    display_frame[source_number] <= latest_frame[source_number];
                end
            end
            if (write_state == W_IDLE && chosen_valid) begin
                round_robin <= chosen_port == 2 ? 2'd0 : chosen_port + 1'b1;
                write_data <= wr_data[chosen_port*256 +: 256];
                write_source <= chosen_source;
                write_block <= chosen_block;
                write_frame <= chosen_frame;
                write_port <= chosen_port;
                write_state <= W_VALIDATE;
            end else if (write_state == W_VALIDATE) begin
                if (!token_sequence_ok) begin
                    debug_drop_count <= debug_drop_count + 1'b1;
                    if (write_source == 3'd4) debug_drop_s4 <= debug_drop_s4 + 1'b1;
                    else if (write_source == 3'd5) debug_drop_s5 <= debug_drop_s5 + 1'b1;
                    if (write_source < 6)
                        source_active[write_source] <= 1'b0;
                    write_state <= W_IDLE;
                end else begin
                    if (write_block == 0 && source_active[write_source])
                        debug_drop_count <= debug_drop_count + 1'b1;
                    source_active[write_source] <= 1'b1;
                    source_frame[write_source] <= write_frame;
                    source_write_page[write_source] <= token_page;
                    bsrc <= write_source;
                    bfrm <= write_frame;
                    bblk <= write_block;
                    bpage <= token_page;
                    bport <= write_port;
                    bbuf[0] <= write_data;
                    bcnt <= 4'd1;
                    bactive <= 1'b1;
                    write_state <= W_COLLECT;
                end
            end else if (write_state == W_COLLECT) begin
                if (bcnt == BW) write_state <= W_PREP;
                else if (burst_more) begin
                    bbuf[bcnt] <= wr_data[bport*256 +: 256];
                    bcnt <= bcnt + 1'b1;
                end else write_state <= W_PREP;
            end else if (write_state == W_PREP) begin
                axi_awaddr <= block_address(bsrc, bpage, bblk);
                blen <= bcnt;
                b_last <= ((bblk + bcnt) == FRAME_BLOCKS);
                widx <= 4'd0;
                write_state <= W_ADDR;
            end else if (write_state == W_ADDR && axi_awready) begin
                write_state <= W_DATA;
            end else if (write_state == W_DATA && axi_wready) begin
                if (widx + 1'b1 == blen) begin
                    // One burst finished: publish only when it carried the very
                    // last block, and only after its final beat reached DDR.
                    source_next_block[bsrc] <= bblk + bcnt;
                    bactive <= 1'b0;
                    write_state <= W_IDLE;
                    if (b_last) begin
                        latest_page[bsrc] <= bpage;
                        latest_frame[bsrc] <= bfrm;
                        frame_valid[bsrc] <= 1'b1;
                        source_active[bsrc] <= 1'b0;
                    end
                end else widx <= widx + 1'b1;
            end
        end
    end

    reg [2:0] request_left_source, request_right_source;
    reg [10:0] request_row;
    always @(*) begin
        // M2-only copy: upper half is N1 sources4/5, lower half is camera0/1.
        request_left_source = (P_M2_ONLY || P_CAMERA_ONLY_LAYOUT) ? 3'd0 : (line_req_y < SRC_H ? 3'd2 : 3'd4);
        request_right_source = (P_M2_ONLY || P_CAMERA_ONLY_LAYOUT) ? 3'd1 : (line_req_y < SRC_H ? 3'd3 : 3'd5);
        request_row = P_CAMERA_ONLY_LAYOUT ? line_req_y >> 1 : (line_req_y < SRC_H ? line_req_y : line_req_y - SRC_H);
        if(P_M2_ONLY) begin
            request_left_source = line_req_y < SRC_H ? 3'd4 : 3'd0;
            request_right_source = line_req_y < SRC_H ? 3'd5 : 3'd1;
            request_row = line_req_y < SRC_H ? line_req_y : line_req_y - SRC_H;
        end else case (line_req_mode)
            2'd1: begin
                request_left_source = line_req_y < SRC_H ? 3'd2 : 3'd4;
                request_right_source = line_req_y < SRC_H ? 3'd3 : 3'd5;
                request_row = line_req_y < SRC_H ? line_req_y : line_req_y - SRC_H;
            end
            2'd2: begin
                request_left_source = line_req_y < SRC_H ? 3'd4 : 3'd0;
                request_right_source = line_req_y < SRC_H ? 3'd5 : 3'd1;
                request_row = line_req_y < SRC_H ? line_req_y : line_req_y - SRC_H;
            end
            default: begin end
        endcase
    end

    wire reading_right = read_index >= HALF_BLOCKS;
    wire [6:0] half_index = reading_right ? read_index - HALF_BLOCKS : read_index;
    wire [6:0] half_remaining = HALF_BLOCKS - half_index;
    wire [2:0] read_selected_source = reading_right ? read_right_source : read_left_source;
    wire [1:0] read_selected_page = reading_right ? read_right_page : read_left_page;
    wire read_selected_valid = reading_right ? read_right_valid : read_left_valid;
    wire [18:0] read_block_number = read_row * HALF_BLOCKS + half_index;
    assign line_req_ready = rst_n && read_state == R_IDLE;
    assign line_data_valid = rst_n && read_state == R_DRAIN;
    assign line_data = buffer_is_zero ? 256'd0 : read_buffer[drain_count[3:0]];
    assign line_data_y = read_y;
    assign line_data_epoch = read_epoch;
    assign line_data_index = read_index + drain_count;
    // Keep source completeness with every response beat, including the
    // deliberate zero-fill path for a source without a committed frame.
    // This is not an online/age flag: a previously committed page is retained.
    assign line_data_source_valid = !buffer_is_zero;
    assign axi_arvalid = rst_n && read_state == R_ADDR;
    assign axi_arid = 4'd0;
    assign axi_arlen = burst_beats - 1'b1;

    // One explicit RAM write port. PDS incorrectly merged the two case-local
    // writes into an ARREADY-gated address in the old routed netlist, so every
    // delayed R beat overwrote index zero. R_PREP resets receive_count to zero;
    // it also supplies the correct index for a first beat on the AR handshake.
    wire receive_accept = rst_n && axi_rvalid
        && (read_state == R_RECV || (read_state == R_ADDR && axi_arready));
    always @(posedge mem_clk) begin
        if (receive_accept)
            read_buffer[receive_count[3:0]] <= axi_rdata;
    end

    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= R_IDLE;
            read_y <= 11'd0;
            read_epoch <= 8'd0;
            read_row <= 11'd0;
            read_left_source <= 3'd0;
            read_right_source <= 3'd1;
            read_left_page <= 2'd0;
            read_right_page <= 2'd0;
            read_left_valid <= 1'b0;
            read_right_valid <= 1'b0;
            read_index <= 7'd0;
            burst_beats <= 5'd1;
            receive_count <= 5'd0;
            drain_count <= 5'd0;
            axi_araddr <= {ADDR_W{1'b0}};
            buffer_is_zero <= 1'b0;
            read_protocol_error <= 1'b0;
        end else begin
            case (read_state)
                R_IDLE: if (line_req_valid) begin
                    read_y <= line_req_y;
                    read_epoch <= line_req_epoch;
                    read_row <= request_row;
                    read_left_source <= request_left_source;
                    read_right_source <= request_right_source;
                    read_left_page <= line_req_frame_start ? latest_page[request_left_source]
                                                         : display_page[request_left_source];
                    read_right_page <= line_req_frame_start ? latest_page[request_right_source]
                                                          : display_page[request_right_source];
                    read_left_valid <= (line_req_y < OUT_H) && request_row < SRC_H
                        && (line_req_frame_start ? frame_valid[request_left_source]
                                                 : display_valid[request_left_source]);
                    read_right_valid <= (line_req_y < OUT_H) && request_row < SRC_H
                        && (line_req_frame_start ? frame_valid[request_right_source]
                                                 : display_valid[request_right_source]);
                    read_index <= 7'd0;
                    read_state <= R_PREP;
                end
                R_PREP: begin
                    burst_beats <= half_remaining > 16 ? 5'd16 : half_remaining[4:0];
                    receive_count <= 5'd0;
                    drain_count <= 5'd0;
                    buffer_is_zero <= !read_selected_valid;
                    axi_araddr <= block_address(read_selected_source, read_selected_page, read_block_number);
                    read_state <= read_selected_valid ? R_ADDR : R_DRAIN;
                end
                R_ADDR: if (axi_arready) begin
                    read_state <= R_RECV;
                    // DDR may return the first beat on the AR handshake.
                    if (axi_rvalid) begin
                        receive_count <= 5'd1;
                        if (axi_rid != 0 || axi_rlast != (burst_beats == 1))
                            read_protocol_error <= 1'b1;
                        if (burst_beats == 1)
                            read_state <= R_DRAIN;
                    end
                end
                R_RECV: if (axi_rvalid) begin
                    receive_count <= receive_count + 1'b1;
                    if (axi_rid != 0 || axi_rlast != (receive_count == burst_beats - 1'b1))
                        read_protocol_error <= 1'b1;
                    if (receive_count == burst_beats - 1'b1)
                        read_state <= R_DRAIN;
                end
                R_DRAIN: if (line_data_ready) begin
                    if (drain_count == burst_beats - 1'b1) begin
                        read_index <= read_index + burst_beats;
                        drain_count <= 5'd0;
                        read_state <= read_index + burst_beats == LINE_BLOCKS ? R_IDLE : R_PREP;
                    end else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end
                default: read_state <= R_IDLE;
            endcase
        end
    end
endmodule
