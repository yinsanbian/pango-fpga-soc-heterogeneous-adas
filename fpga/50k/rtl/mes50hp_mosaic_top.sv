`timescale 1ns/1ps
module mes50hp_mosaic_top#(
	parameter MEM_ROW_ADDR_WIDTH   = 15         ,
	parameter MEM_COL_ADDR_WIDTH   = 10         ,
	parameter MEM_BADDR_WIDTH      = 3          ,
	parameter MEM_DQ_WIDTH         =  32        ,
	parameter MEM_DQS_WIDTH        =  32/8,
    parameter integer P_PHY_DIAGNOSTIC = 1,
    // N1 RGMII sample-clock phase relative to the recovered RXC edge.
    // Coarse=1 ns per step (VCO cycle), fine=125 ps per step (0..7).
    parameter integer P_RX_SAMPLE_CPHASE = 1,
    parameter integer P_RX_SAMPLE_PHASE  = 4,
    // 0 = clean video mosaic (all counters are on the Type-C UART),
    // 1 = legacy on-screen diagnostic tables.
    parameter integer P_DEBUG_OVERLAY = 0
)(
	input wire sys_clk_27m,
	input                                sys_clk              ,
    input wire key_process_n,
    output  [1:0]                        cmos_init_done       ,
    inout                                cmos1_scl            ,
    inout                                cmos1_sda            ,
    input                                cmos1_vsync          ,
    input                                cmos1_href           ,
    input                                cmos1_pclk           ,
    input   [7:0]                        cmos1_data           ,
    output                               cmos1_reset          ,
    inout                                cmos2_scl            ,
    inout                                cmos2_sda            ,
    input                                cmos2_vsync          ,
    input                                cmos2_href           ,
    input                                cmos2_pclk           ,
    input   [7:0]                        cmos2_data           ,
    output                               cmos2_reset          ,
    output                               mem_rst_n                 ,
    output                               mem_ck                    ,
    output                               mem_ck_n                  ,
    output                               mem_cke                   ,
    output                               mem_cs_n                  ,
    output                               mem_ras_n                 ,
    output                               mem_cas_n                 ,
    output                               mem_we_n                  ,
    output                               mem_odt                   ,
    output      [MEM_ROW_ADDR_WIDTH-1:0] mem_a                     ,
    output      [MEM_BADDR_WIDTH-1:0]    mem_ba                    ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs                   ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n                 ,
    inout       [MEM_DQ_WIDTH-1:0]       mem_dq                    ,
    output      [MEM_DQ_WIDTH/8-1:0]     mem_dm                    ,
    output reg                           heart_beat_led            ,
    output                               ddr_init_done             ,
    output                               rstn_out                  ,
    output                               iic_tx_scl                ,
    inout                                iic_tx_sda                ,
    output                               hdmi_int_led              ,
    output                               pix_clk                   ,
    output wire                       vs_out                    ,
    output wire                       hs_out                    ,
    output wire                       de_out                    ,
    output wire[7:0]                  r_out                     ,
    output wire[7:0]                  g_out                     ,
    output wire[7:0]                  b_out,
    output wire eth_rst_n_0,
    input wire eth_rgmii_rxc_0,eth_rgmii_rx_ctl_0,
    input wire [3:0] eth_rgmii_rxd_0,
    output wire eth_rgmii_txc_0,eth_rgmii_tx_ctl_0,
    output wire [3:0] eth_rgmii_txd_0,
    output wire eth_rst_n_1,
    input wire eth_rgmii_rxc_1,eth_rgmii_rx_ctl_1,
    input wire [3:0] eth_rgmii_rxd_1,
    output wire eth_rgmii_txc_1,eth_rgmii_tx_ctl_1,
    output wire [3:0] eth_rgmii_txd_1,
    output wire eth_mdc_0,eth_mdc_1,
    inout wire eth_mdio_0,eth_mdio_1,
    // Type-C CP2102 debug UART: FPGA UART0_TX=R9, UART0_RX=R8 (board manual
    // table). TX is the only driver; RX is reserved and read but not decoded.
    output wire uart_dbg_tx,
    input wire uart_dbg_rx
);

    localparam CTRL_ADDR_WIDTH=28;
    wire cfg_clk,clk_25M,locked,core_clk,pll_lock,init_over_tx,init_over_rx;
    wire iic_scl,iic_sda,initial_en;
    wire [1:0] cam_response_low;
    wire [5:0] diagnostic_frame_valid;
    wire [27:0] camera_flags;
    wire [1:0] cam_readback_done,pixel_readback_valid;
    wire [239:0] cam_readback_values,pixel_readback_values;
    reg [15:0] reset_count;
    wire net_tx_clk,net_tx_clk90;
    mosaic_pll u_pll(.clkin1(sys_clk),.clkin27(sys_clk_27m),.clkout0(pix_clk),
        .clkout1(cfg_clk),.clkout2(clk_25M),.pll_lock(locked),
        .net_tx_clk(net_tx_clk),.net_tx_clk90(net_tx_clk90));
    always @(posedge cfg_clk) begin
        if(!locked) reset_count<=0;
        else if(reset_count!=16'h2710) reset_count<=reset_count+1;
    end
    assign rstn_out=locked && reset_count==16'h2710;
    ms72xx_ctl u_hdmi_cfg(.clk(cfg_clk),.rst_n(rstn_out),.init_over_tx(init_over_tx),
        .init_over_rx(init_over_rx),.iic_tx_scl(iic_tx_scl),.iic_tx_sda(iic_tx_sda),
        .iic_scl(iic_scl),.iic_sda(iic_sda));
    assign hdmi_int_led=init_over_tx;
    camera_power_sequence u_power(.clk_50M(sys_clk),.reset_n(locked),.camera1_rstn(cmos1_reset),
        .camera2_rstn(cmos2_reset),.camera_pwnd(),.initial_en(initial_en));
    camera_reg_config_540 u_cam_cfg0(.clk_25M(clk_25M),.camera_rstn(cmos1_reset),.initial_en(initial_en),
        .i2c_sclk(cmos1_scl),.i2c_sdat(cmos1_sda),.reg_conf_done(cmos_init_done[0]),.clock_20k(),.reg_index(),
        .response_low_seen(cam_response_low[0]),.readback_done(cam_readback_done[0]),
        .readback_values(cam_readback_values[119:0]));
    camera_reg_config_540 u_cam_cfg1(.clk_25M(clk_25M),.camera_rstn(cmos2_reset),.initial_en(initial_en),
        .i2c_sclk(cmos2_scl),.i2c_sdat(cmos2_sda),.reg_conf_done(cmos_init_done[1]),.clock_20k(),.reg_index(),
        .response_low_seen(cam_response_low[1]),.readback_done(cam_readback_done[1]),
        .readback_values(cam_readback_values[239:120]));
    wire net1_sample_clk,net1_locked,net1_fifo_rstn;
    system_receive_clocks #(.P_SAMPLE_CPHASE(P_RX_SAMPLE_CPHASE),
        .P_SAMPLE_PHASE(P_RX_SAMPLE_PHASE)) u_rx_recovery(.clkin50(sys_clk),.rst(!rstn_out),
        .rxc(eth_rgmii_rxc_1),.sample_clk(net1_sample_clk),.locked(net1_locked),.pll_reset());
    // All FIFO pointers/mailboxes share reset; missing ETH1 never resets HDMI.
    wire common_reset_n=rstn_out && ddr_init_done;
    wire mem_rstn,pixel_rstn,net1_rstn,tx_rstn,tx90_rstn;
    reset_sync u_mem_rst(.clk(core_clk),.async_n(common_reset_n),.rst_n(mem_rstn));
    reset_sync u_pix_rst(.clk(pix_clk),.async_n(common_reset_n),.rst_n(pixel_rstn));
    wire [2:0] wr_valid,wr_ready;
    wire [8:0] wr_source;
    wire [56:0] wr_block;
    wire [95:0] wr_frame;
    wire [767:0] wr_data;
    wire [1:0] cam_clk={cmos2_pclk,cmos1_pclk};
    wire [1:0] cam_vs={cmos2_vsync,cmos1_vsync},cam_href={cmos2_href,cmos1_href};
    wire [15:0] cam_bytes={cmos2_data,cmos1_data};
    wire [1:0] cam_reset={cmos2_reset,cmos1_reset};
    genvar c;
    generate for(c=0;c<2;c=c+1) begin:g_camera
        wire cap_rstn,cap_valid,cap_ready,capture_enable;
        wire [2:0] cap_source;wire [18:0] cap_block;wire [31:0] cap_frame;
        wire [255:0] cap_data;wire [309:0] read_packet;
        wire [31:0] cap_good_frames,cap_dropped_frames;
        // Readback is in clk_25M and remains available with no camera PCLK.
        // The snapshot is held before done and until reset; only done is a
        // continuously synchronized control, not a free-running binary bus.
        camera_readback_bridge u_readback_bridge(.src_data(cam_readback_values[c*120 +:120]),
            .src_done(cam_readback_done[c]),.pix_clk(pix_clk),.pix_rst_n(pixel_rstn),
            .data_snapshot(pixel_readback_values[c*120 +:120]),.valid(pixel_readback_valid[c]));
        // FIFO reset must be shared in both domains. Camera initialization
        // gates pixels, not one side of a live FIFO.
        reset_sync u_rst(.clk(cam_clk[c]),.async_n(common_reset_n),.rst_n(cap_rstn));
        // Configuration/reset controls enter the original PCLK domain through
        // an async-disable / synchronous-enable chain; no clock is gated.
        reset_sync u_capture_enable(.clk(cam_clk[c]),
            .async_n(cap_rstn && cmos_init_done[c] && cam_reset[c]),.rst_n(capture_enable));
        camera_rgb565_packetizer #(.SOURCE_ID(c)) u_capture(.clk(cam_clk[c]),.rst_n(cap_rstn),
            .vsync(cam_vs[c]),.href(cam_href[c] && capture_enable),.data(cam_bytes[c*8 +:8]),
            .beat_valid(cap_valid),.beat_ready(cap_ready),.beat_source(cap_source),.beat_block(cap_block),
            .beat_frame(cap_frame),.beat_data(cap_data),.dropped_frames(cap_dropped_frames),.good_frames(cap_good_frames));
        camera_debug_monitor u_monitor(.pclk(cam_clk[c]),.cap_rst_n(cap_rstn),
            .raw_vsync(cam_vs[c]),.raw_href(cam_href[c]),.raw_data(cam_bytes[c*8 +:8]),
            .capture_enable(capture_enable),.fifo_ready(cap_ready),.good_toggle(cap_good_frames[0]),
            .dropped_low(cap_dropped_frames[1:0]),.cfg_done(cmos_init_done[c]),
            .response_low_seen(cam_response_low[c]),.ddr_frame_valid(diagnostic_frame_valid[c]),
            .pix_clk(pix_clk),.pix_rst_n(pixel_rstn),.flags(camera_flags[c*14 +:14]));
        video_async_fifo #(.WIDTH(310),.ADDR_BITS(8)) u_fifo(.wr_clk(cam_clk[c]),.wr_rst_n(cap_rstn),
            .wr_valid(cap_valid),.wr_ready(cap_ready),.wr_data({cap_source,cap_block,cap_frame,cap_data}),
            .rd_clk(core_clk),.rd_rst_n(mem_rstn),.rd_valid(wr_valid[c]),.rd_ready(wr_ready[c]),.rd_data(read_packet));
        assign {wr_source[c*3 +:3],wr_block[c*19 +:19],wr_frame[c*32 +:32],wr_data[c*256 +:256]}=read_packet;
    end endgenerate
    // N1 is the only Ethernet datapath in this build. The NET0 pins stay in the
    // pin contract but carry no logic: PHY0 keeps its reset released so the pin
    // has a defined state, and its RGMII TX lines are held idle. No NET0 receive
    // tuple, clock or FIFO exists, so NET0 cannot influence N1 in any way.
    wire net1_clk,mac1_rx_error,mac1_rx_valid;
    wire [7:0] mac1_rx_data;
    assign eth_rgmii_txc_0=1'b0;
    assign eth_rgmii_tx_ctl_0=1'b0;
    assign eth_rgmii_txd_0=4'd0;
    // RTL8211E requires >=10ms low. Stable 50MHz logic stretches even a
    // short PLL reset request, independently of DDR readiness.
    wire phy_board_rst_n;
    phy_reset_sequence u_phy_reset(.clk50(sys_clk),.request_n(rstn_out),
        .phy_reset_n(phy_board_rst_n));
    assign eth_rst_n_0=phy_board_rst_n;
    assign eth_rst_n_1=phy_board_rst_n;
    reset_sync u_tx_rst(.clk(net_tx_clk),.async_n(common_reset_n),.rst_n(tx_rstn));
    reset_sync u_tx90_rst(.clk(net_tx_clk90),.async_n(common_reset_n),.rst_n(tx90_rstn));
    system_rgmii #(.P_RX_EXTERNAL(1)) u_system_rgmii1(
        .rx_rst(!net1_rstn),.tx_rst(!tx_rstn),.tx_clock_rst(!tx90_rstn),
        .rx_sample_clk(net1_sample_clk),
        .tx_clk(net_tx_clk),.tx_clk90(net_tx_clk90),.rgmii_clk(net1_clk),
        .mac_tx_data_valid(1'b0),.mac_tx_data(8'd0),.mac_tx_error(1'b0),
        .mac_rx_error(mac1_rx_error),.mac_rx_data_valid(mac1_rx_valid),.mac_rx_data(mac1_rx_data),
        .rgmii_rxc(eth_rgmii_rxc_1),.rgmii_rx_ctl(eth_rgmii_rx_ctl_1),.rgmii_rxd(eth_rgmii_rxd_1),
        .rgmii_txc(eth_rgmii_txc_1),.rgmii_tx_ctl(eth_rgmii_tx_ctl_1),.rgmii_txd(eth_rgmii_txd_1));
    reset_sync u_net1_rst(.clk(net1_clk),.async_n(common_reset_n && net1_locked),.rst_n(net1_rstn));
    // Keep FIFO write/read pointers together across a stopped/relocked PHY clock.
    reset_sync u_net1_fifo_rst(.clk(net1_clk),.async_n(common_reset_n),.rst_n(net1_fifo_rstn));
    // Controlled full-wire/FCS capture proves C2 only for N1. Keep the raw
    // mac1_rx_* tuples unchanged for independent PHY/RAW diagnostics.
    wire [7:0] net1_aligned_data;
    wire net1_aligned_valid,net1_aligned_error;
    rgmii_rx_c2_align u_net1_c2_align(.clk(net1_clk),.rst_n(net1_rstn),
        .raw_data(mac1_rx_data),.raw_dv(mac1_rx_valid),.raw_er(mac1_rx_error),
        .data_out(net1_aligned_data),.dv_out(net1_aligned_valid),.er_out(net1_aligned_error));
    wire [31:0] net1_rx_packets,net1_rx_rejected,net1_bad_header_count,net1_dropped_packet_count;
    wire [7:0] net1_last_reject_flags;
    // Passive, same-RX-domain observations. None feed the receive datapath.
    wire [2:0] net1_debug_events;
    wire [31:0] net1_debug_state;
    wire [11:0] net1_debug_eof_length;
    wire [258:0] net1_debug_checksums;
    wire [287:0] net1_counter_bundle;
    wire [31:0] net1_beat_count;
    wire [31:0] diagnostic_dma_drops;
    wire [31:0] diagnostic_drop_s4,diagnostic_drop_s5;
    wire [31:0] diagnostic_cyc_addr,diagnostic_cyc_data,diagnostic_cyc_drain,diagnostic_cyc_total;
    wire diagnostic_dma_protocol_error;
    // One MAC, one stream parser, one FIFO, one beat source: no arbiter state.
    system_single_net_rx u_single_net(.net1_clk(net1_clk),.core_clk(core_clk),
        .net1_rst_n(net1_rstn),.net1_fifo_rst_n(net1_fifo_rstn),.core_rst_n(mem_rstn),
        .gmii1_rxd(net1_aligned_data),.gmii1_rx_dv(net1_aligned_valid),.gmii1_rx_er(net1_aligned_error),
        .beat_valid(wr_valid[2]),.beat_ready(wr_ready[2]),.beat_source(wr_source[8:6]),
        .beat_block(wr_block[56:38]),.beat_frame(wr_frame[95:64]),.beat_data(wr_data[767:512]),
        .net1_rx_packets(net1_rx_packets),.net1_rx_rejected(net1_rx_rejected),
        .net1_bad_header_count(net1_bad_header_count),.net1_dropped_packet_count(net1_dropped_packet_count),
        .net1_last_reject_flags(net1_last_reject_flags),
        .net1_debug_events(net1_debug_events),.net1_debug_state(net1_debug_state),
        .net1_debug_eof_length(net1_debug_eof_length),
        .net1_debug_checksums(net1_debug_checksums),
        .net1_beat_count(net1_beat_count));
    wire relay_sof;
    // The NET0 control port (UDP 5002) disappeared with the NET0 datapath, so the
    // overlay toggle has no remote source any more. Diagnostics stay permanently
    // visible, which is what this N1-isolation build wants.
    wire debug_overlay_requested=(P_DEBUG_OVERLAY!=0);
    wire raw_hs,raw_vs,raw_de,frame_start,line_end;wire [11:0] x;wire [10:0] y;
    // M2-only copy: retain the key port for the board pin contract, but make
    // the layout ID constant. KEY2 remains the independent process-view key.
    wire [2:0] mode;
    assign mode=3'd2;
    video_timing_1080p u_timing(.clk(pix_clk),.rst_n(pixel_rstn),.hs(raw_hs),.vs(raw_vs),.de(raw_de),
        .x(x),.y(y),.frame_start(frame_start),.line_end(line_end));
    wire pixel_req_valid,pixel_req_ready,pixel_req_start;wire [10:0] pixel_req_y;
    reg [31:0] raw_frame_counter;
    wire [1:0] pixel_req_mode;wire [7:0] pixel_req_epoch;
    wire dma_req_valid,dma_req_ready;wire [45:0] dma_req;
    video_async_fifo #(.WIDTH(46),.ADDR_BITS(4)) u_req_fifo(.wr_clk(pix_clk),.wr_rst_n(pixel_rstn),
        .wr_valid(pixel_req_valid),.wr_ready(pixel_req_ready),.wr_data({pixel_req_start,raw_frame_counter,pixel_req_mode,pixel_req_y}),
        .rd_clk(core_clk),.rd_rst_n(mem_rstn),.rd_valid(dma_req_valid),.rd_ready(dma_req_ready),.rd_data(dma_req));
    wire dma_data_valid,dma_data_ready;wire [255:0] dma_line_data;wire [10:0] dma_line_y;
    wire dma_line_source_valid;
    wire [6:0] dma_line_index;wire [7:0] dma_line_epoch;
    wire pixel_data_valid,pixel_data_ready;wire [282:0] pixel_data;
    video_async_fifo #(.WIDTH(283),.ADDR_BITS(8)) u_line_fifo(.wr_clk(core_clk),.wr_rst_n(mem_rstn),
        .wr_valid(dma_data_valid),.wr_ready(dma_data_ready),.wr_data({dma_line_source_valid,dma_line_epoch,dma_line_y,dma_line_index,dma_line_data}),
        .rd_clk(pix_clk),.rd_rst_n(pixel_rstn),.rd_valid(pixel_data_valid),.rd_ready(pixel_data_ready),.rd_data(pixel_data));
    wire [23:0] rgb;
    wire video_de,video_hs,video_vs;
    wire video_pixel_valid;
    wire [23:0] lane_rgb;
    wire lane_de,lane_hs,lane_vs;
    wire [23:0] diagnostic_rgb;
    mosaic_line_display u_display(.clk(pix_clk),.rst_n(pixel_rstn),.x(x),.y({1'b0,y}),.de(raw_de),.hs(raw_hs),.vs(raw_vs),
        .frame_start(frame_start),.line_end(line_end),.mode(mode[1:0]),.req_valid(pixel_req_valid),.req_ready(pixel_req_ready),
        .req_y(pixel_req_y),.req_mode(pixel_req_mode),.req_frame_start(pixel_req_start),.req_epoch(pixel_req_epoch),
        .data_valid(pixel_data_valid),.data_ready(pixel_data_ready),.data(pixel_data[255:0]),.data_y(pixel_data[273:263]),
        .data_index(pixel_data[262:256]),.data_epoch(pixel_data[281:274]),
        .data_source_valid(pixel_data[282]),.pixel_valid_out(video_pixel_valid),
        .rgb_out(rgb),.de_out(video_de),.hs_out(video_hs),.vs_out(video_vs),.underrun_lines(),.request_overflow());
    // Keep original color detection independent of KEY2 display selection.
    // Shared view processing delays the complete stream and coordinates.
    wire [2:0] process_view;
    wire [23:0] relay_rgb;wire [11:0] relay_x;wire [10:0] relay_y;
    wire [1:0] relay_mode;wire pipeline_de,pipeline_hs,pipeline_vs;
    wire dma_snapshot_pulse;wire [7:0] dma_snapshot_epoch;
    wire [31:0] dma_snapshot_frame_id;
    wire [5:0] dma_display_valid;wire [191:0] dma_snapshot_frames;
    wire context_ready,context_pulse;wire [229:0] context_received;
    cdc_snapshot_mailbox #(.W(230)) u_context_mailbox(.src_clk(core_clk),.src_rst_n(mem_rstn),
        .src_send(dma_snapshot_pulse),.src_data({dma_snapshot_frame_id,dma_display_valid,dma_snapshot_frames}),
        .src_ready(context_ready),.dst_clk(pix_clk),.dst_rst_n(pixel_rstn),
        .dst_data(context_received),.dst_pulse(context_pulse));
    reg [31:0] context_frame_counter;
    reg [191:0] context_frames;reg [5:0] context_source_valid;reg [7:0] context_epoch;
    always @(posedge pix_clk or negedge pixel_rstn) begin
        if(!pixel_rstn) begin
            raw_frame_counter<=0;context_frame_counter<=32'hffffffff;
            context_frames<=0;context_source_valid<=0;context_epoch<=0;
        end else begin
            if(frame_start) raw_frame_counter<=raw_frame_counter+1'b1;
            if(context_pulse && context_received[229:198]==raw_frame_counter && !frame_start) begin
                context_frame_counter<=context_received[229:198];context_epoch<=context_received[205:198];
                context_source_valid<=context_received[197:192];context_frames<=context_received[191:0];
            end
        end
    end
    wire [3:0] result_pulse,result_tag_valid,result_left_valid,result_right_valid;
    wire [127:0] result_frame_ids,result_source_frames;
    wire [11:0] result_sources;wire [7:0] result_mode;wire [191:0] result_endpoints;
    mosaic_video_pipeline #(.P_CAMERA_ONLY_LAYOUT(0),.P_M2_ONLY(1)) u_video_pipeline(.clk(pix_clk),.rst_n(pixel_rstn),
        .key_process_n(key_process_n),.layout_mode(mode[1:0]),
        .raw_x(x),.raw_y(y),.raw_de(raw_de),.raw_frame_start(frame_start),
        .rgb_in(rgb),.video_de(video_de),.video_hs(video_hs),.video_vs(video_vs),
        .pixel_valid_in(video_pixel_valid),.flags0(camera_flags[13:0]),.flags1(camera_flags[27:14]),
        .readback0(pixel_readback_values[119:0]),.readback1(pixel_readback_values[239:120]),
        .readback_valid0(pixel_readback_valid[0]),.readback_valid1(pixel_readback_valid[1]),
        .rgb_out(diagnostic_rgb),.de_out(pipeline_de),.hs_out(pipeline_hs),.vs_out(pipeline_vs),.view_mode(process_view),
        .relay_rgb_out(relay_rgb),.relay_x_out(relay_x),.relay_y_out(relay_y),
        .relay_mode_out(relay_mode),.relay_frame_start_out(relay_sof),
        .context_source_frames(context_frames),.context_epoch(context_epoch),
        .context_source_valid(context_frame_counter==raw_frame_counter ? context_source_valid : 6'd0),
        .result_pulse(result_pulse),.result_tag_valid(result_tag_valid),
        .result_left_valid(result_left_valid),.result_right_valid(result_right_valid),
        .result_frame_ids(result_frame_ids),.result_source_frames(result_source_frames),
        .result_sources(result_sources),.result_mode(result_mode),.result_endpoints(result_endpoints));
    wire [23:0] output_rgb;wire [31:0] output_frame_id;wire [7:0] output_mode_id;
    wire output_first_active,relay_first_active,relay_de,relay_hs,relay_vs,relay_debug_active;
    wire [11:0] relay_output_x;wire [10:0] relay_output_y;
    wire [23:0] network_diagnostic_rgb;
    wire [207:0] network_status0,network_status1;
    wire [191:0] phy_status0,phy_status1;
    wire [127:0] phy_delay_status0,phy_delay_status1;
    wire [47:0] phy_page_probe0,phy_page_probe1;
    // Match management lifetime to the physical PHY reset. A DDR-only reset
    // must not restart the frozen baseline scan while the PHY remains powered.
    wire phy_mgmt_rstn;
    reset_sync u_phy_mgmt_rst(.clk(pix_clk),.async_n(phy_board_rst_n),.rst_n(phy_mgmt_rstn));
    wire [1:0] phy_mdio_o,phy_mdio_oe;
    assign eth_mdio_0=phy_mdio_oe[0] ? phy_mdio_o[0] : 1'bz;
    assign eth_mdio_1=phy_mdio_oe[1] ? phy_mdio_o[1] : 1'bz;
    // All management state and display words use PIX. MDC is a slow CE-driven
    // output, never an additional fabric clock; original PHY reset is retained.
    // Read-only baseline: observe strap defaults without automatic delay writes.
    phy_mdio_diagnostic #(.P_CONFIG_DELAY(0),.P_READONLY_PROFILE(0),.P_PAGE_ACCESS_PROBE(1)) u_phy_diag(.pix_clk(pix_clk),.pix_rst_n(phy_mgmt_rstn),
        .mdio_i({eth_mdio_1,eth_mdio_0}),.mdio_o(phy_mdio_o),.mdio_oe(phy_mdio_oe),
        .mdc({eth_mdc_1,eth_mdc_0}),.status0(phy_status0),.status1(phy_status1),
        .delay_status0(phy_delay_status0),.delay_status1(phy_delay_status1),
        .page_probe0(phy_page_probe0),.page_probe1(phy_page_probe1));
    function [207:0] phy_hud_words;
        input [191:0] snapshot;
        reg [207:0] value;
        begin
            value=208'd0;
            value[63:32]={snapshot[15:0],snapshot[31:16]};
            value[31:0]={snapshot[47:32],snapshot[79:64]};
            value[95:64]={snapshot[63:48],snapshot[95:80]};
            value[127:96]={snapshot[111:96],snapshot[127:112]};
            value[159:128]={snapshot[143:128],snapshot[159:144]};
            value[191:160]=snapshot[191:160];
            value[199:192]=snapshot[167:160];
            value[200]=snapshot[165];
            value[201]=snapshot[166];
            phy_hud_words=value;
        end
    endfunction
    function [207:0] phy_delay_hud_words;
        input [191:0] snapshot;
        input [127:0] configuration;
        reg [207:0] value;
        reg [15:0] fault_mask;
        reg [1:0] fault_kind;
        begin
            value=208'd0;
            value[63:32]={snapshot[15:0],snapshot[31:16]};
            value[31:0]=configuration[63:32];
            value[95:64]=configuration[95:64];
            value[127:96]=configuration[127:96];
            value[159:128]=configuration[31:0];
            value[191:160]=snapshot[191:160];
            value[199:192]=configuration[23:16];
            value[200]=configuration[23];
            // In this selector-only probe, flag6 is the second1C READ ACK;
            // completion remains the independent management-done status bit.
            value[201]=snapshot[166];
            fault_mask=16'hffff; fault_kind=0;
            // Error view: preserve RESULT/final step and show the first READ
            // failure separately. EQ=0, MASK_EQ=1, NOT_EQ=2, ACK_ONLY/NONE=3.
            // Never label the forbidden FFFF (step8) as a required equality.
            if(configuration[31:24]!=0) begin
                case(snapshot[159:154])
                    0: begin fault_mask=16'h0007; fault_kind=1; end
                    8: fault_kind=2;
                    5,63: begin fault_mask=0; fault_kind=3; end
                    default: begin end
                endcase
                value[31:0]={16'd0,snapshot[147:132]};
                value[95:64]={16'd0,snapshot[131:116]};
                value[191:160]={fault_mask,fault_kind,2'd0,snapshot[159:148]};
            end
            phy_delay_hud_words=value;
        end
    endfunction
    // The existing KEY2 process selector leaves both status sources reachable;
    // normal view0 exposes NET counters; view5 shows PHY in this probe.
    wire phy_display_active=P_PHY_DIAGNOSTIC && (process_view==3'd5);
    wire [207:0] hud_status0=phy_display_active ? phy_delay_hud_words(phy_status0,phy_delay_status0) : network_status0;
    wire [207:0] hud_status1=phy_display_active ? phy_delay_hud_words(phy_status1,phy_delay_status1) : network_status1;
    wire [102:0] network_core_status;
    // Same PIX row selector as the HUD. Reuse its three tail words in V5 for
    // the nonzero address bitmap, page/RXERC snapshot and read-only ACK/version.
    // No new CDC: both sources and this row mux use PIX.
    wire [47:0] phy_probe_row=(relay_output_y[10:5]==6'd9) ? phy_page_probe1 : phy_page_probe0;
    wire [127:0] phy_probe_row_metadata=(relay_output_y[10:5]==6'd9) ? phy_delay_status1 : phy_delay_status0;
    // No CDC: all words are frozen in PIX. Schema5031 distinguishes this
    // selector-only probe from the previous OP10-only RO524F snapshot.
    wire [102:0] phy_probe_core={7'd0,phy_probe_row[47:16],16'h5031,
        phy_probe_row[15:0],phy_probe_row_metadata[63:32]};
    wire [102:0] hud_core_status=phy_display_active ? phy_probe_core : network_core_status;
    wire [1:0] network_clock_alive;wire network_pll_locked_pix;
    system_video_relay u_relay(.clk(pix_clk),.rst_n(pixel_rstn),
        .rgb_clean_in(relay_rgb),.rgb_debug_in(diagnostic_rgb),.x_in(relay_x),.y_in(relay_y),
        .layout_mode_in(relay_mode),.view_mode_in(process_view),.frame_start_in(relay_sof),
        .de_in(pipeline_de),.hs_in(pipeline_hs),.vs_in(pipeline_vs),.debug_overlay_requested(debug_overlay_requested),
        .rgb_out(output_rgb),.de_out(relay_de),.hs_out(relay_hs),.vs_out(relay_vs),
        .frame_start_out(),.x_out(relay_output_x),.y_out(relay_output_y),
        .frame_id_out(output_frame_id),.mode_id_out(output_mode_id),
        .debug_active(relay_debug_active),.first_active_out(relay_first_active),.marker_ready_out());
    wire [3:0] network_observer_health_pix;
    network_rx_diagnostics #(.P_HEADER_CAPTURE(0),.P_CONTROLLED_RAW(1),.P_RAW_WARMUP_CYCLES(250000000),
        .P_MAC_BOUNDARY_DIAGNOSTIC(1),.P_REJECT_CAPTURE(1),.P_BOUNDARY_PAGE_COUNTER_BITS(24)) u_network_diag(
        .net0_clk(net1_clk),.net1_clk(net1_clk),.core_clk(core_clk),.pix_clk(pix_clk),
        .net0_rst_n(net1_fifo_rstn),.net1_fifo_rst_n(net1_fifo_rstn),.core_rst_n(mem_rstn),.pix_rst_n(pixel_rstn),
        .parser0_rst_n(net1_rstn),.parser1_rst_n(net1_rstn),.net1_locked(net1_locked),
        // NET0 has no MAC in this build: its observer is driven by constants so
        // the N0 row is provably inert and cannot gate or delay the N1 path.
        .gmii0_data(8'd0),.gmii1_data(mac1_rx_data),
        .gmii0_dv(1'b0),.gmii0_er(1'b0),.gmii1_dv(mac1_rx_valid),.gmii1_er(mac1_rx_error),
        .net0_rx_packets(32'd0),.net0_rejected(32'd0),
        .net0_bad_header_count(32'd0),.net0_dropped_packet_count(32'd0),
        .net1_rx_packets(net1_rx_packets),.net1_rejected(net1_rx_rejected),
        .net1_bad_header_count(net1_bad_header_count),.net1_dropped_packet_count(net1_dropped_packet_count),
        .net0_last_reject_flags(8'd0),.net1_last_reject_flags(net1_last_reject_flags),
        .net0_debug_events(3'd0),.net1_debug_events(net1_debug_events),
        .net0_debug_state(32'd0),.net1_debug_state(net1_debug_state),
        .net0_debug_eof_length(12'd0),.net1_debug_eof_length(net1_debug_eof_length),
        .net1_capture_data(net1_aligned_data),.net1_capture_dv(net1_aligned_valid),
        .net1_capture_er(net1_aligned_error),.net1_capture_checksums(net1_debug_checksums),
        .core_net_valid(wr_valid[2]),.core_net_ready(wr_ready[2]),.core_net_source(wr_source[8:6]),
        .core_frame_valid(diagnostic_frame_valid),.core_drop_count(diagnostic_dma_drops),
        .core_protocol_error(diagnostic_dma_protocol_error),
        .status0(network_status0),.status1(network_status1),.core_status(network_core_status),
        .clock_alive(network_clock_alive),.pll_locked_pix(network_pll_locked_pix),
        .observer_health_pix(network_observer_health_pix),
        .net1_counter_bundle(net1_counter_bundle));
    network_rx_overlay #(.P_HEADER_CAPTURE(0),.P_CONTROLLED_RAW(1),.P_PHY_DIAGNOSTIC(P_PHY_DIAGNOSTIC),
        .P_PHY_DELAY_STATUS(1),.P_PHY_WRITE_ECHO(0),.P_PHY_READONLY_PROFILE(0),.P_PHY_PAGE_ACCESS_PROBE(1),.P_MAC_BOUNDARY_DIAGNOSTIC(1)) u_network_hud(.clk(pix_clk),.rst_n(pixel_rstn),
        .rgb_in(output_rgb),.de_in(relay_de),.hs_in(relay_hs),.vs_in(relay_vs),
        .first_active_in(relay_first_active),.x(relay_output_x),.y(relay_output_y),
        .mode({1'b0,output_mode_id[1:0]}),.enable(relay_debug_active),
        .status0(hud_status0),.status1(hud_status1),.core_status(hud_core_status),
        .phy_diagnostic(phy_display_active),
        .observer_health_pix(network_observer_health_pix),
        .clock_alive(network_clock_alive),.pll_locked_pix(network_pll_locked_pix),
        .rgb_out(network_diagnostic_rgb),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out),
        .first_active_out(output_first_active));
    assign {r_out,g_out,b_out}=network_diagnostic_rgb;
    // ------------------------------------------------------------------
    // Type-C UART beacon: FPGA UART0_TX (R9) -> CP2102 -> PC COM port.
    // The counters live in the NET1 receive domain, so a bundled-data mailbox
    // gives the 50 MHz UART domain one coherent snapshot instead of a raw
    // multi-bit CDC. FRM/DROP come from the core domain through a second
    // mailbox for the same reason.
    // ------------------------------------------------------------------
    wire uart_rstn;
    reset_sync u_uart_rst(.clk(sys_clk),.async_n(common_reset_n),.rst_n(uart_rstn));
    wire [319:0] uart_rx_snapshot;
    cdc_snapshot_mailbox #(.W(320)) u_uart_rx_mailbox(
        .src_clk(net1_clk),.src_rst_n(net1_fifo_rstn),.src_send(1'b1),
        .src_data({net1_beat_count,net1_counter_bundle}),.src_ready(),
        .dst_clk(sys_clk),.dst_rst_n(uart_rstn),
        .dst_data(uart_rx_snapshot),.dst_pulse());
    wire [255:0] uart_core_snapshot;
    // Bit map: [31:0] cyc_total [63:32] cyc_drain [95:64] cyc_data
    // [127:96] cyc_addr [159:128] dma_drops [191:160] drop_s4
    // [223:192] drop_s5 [229:224] frame_valid
    cdc_snapshot_mailbox #(.W(256)) u_uart_core_mailbox(
        .src_clk(core_clk),.src_rst_n(mem_rstn),.src_send(1'b1),
        .src_data({26'd0,diagnostic_frame_valid,diagnostic_drop_s5,diagnostic_drop_s4,
                   diagnostic_dma_drops,diagnostic_cyc_addr,diagnostic_cyc_data,
                   diagnostic_cyc_drain,diagnostic_cyc_total}),.src_ready(),
        .dst_clk(sys_clk),.dst_rst_n(uart_rstn),
        .dst_data(uart_core_snapshot),.dst_pulse());
    uart_status_telemetry #(.P_CLK_HZ(50_000_000),.P_BAUD(115200),.P_PERIOD_MS(500))
        u_uart_beacon(.clk(sys_clk),.rst_n(uart_rstn),
        .raw(uart_rx_snapshot[31:0]),.good(uart_rx_snapshot[63:32]),
        .rej(uart_rx_snapshot[95:64]),.fcs(uart_rx_snapshot[127:96]),
        .pbad(uart_rx_snapshot[159:128]),.hdr(uart_rx_snapshot[191:160]),
        .ip(uart_rx_snapshot[223:192]),.udp(uart_rx_snapshot[255:224]),
        .bank(uart_rx_snapshot[287:256]),.beat(uart_rx_snapshot[319:288]),
        .frm({26'd0,uart_core_snapshot[229:224]}),.drop(uart_core_snapshot[159:128]),
        .d0(uart_core_snapshot[191:160]),.d1(uart_core_snapshot[223:192]),
        .d2(uart_core_snapshot[159:128]),.d3(uart_core_snapshot[127:96]),
        .d4(uart_core_snapshot[95:64]),.d5(uart_core_snapshot[63:32]),
        .d6(uart_core_snapshot[31:0]),
        .uart_tx(uart_dbg_tx));
    wire [27:0] axi_awaddr,axi_araddr;
    wire [3:0] axi_awuser_id,axi_awlen,axi_aruser_id,axi_arlen,axi_rid;
    wire axi_awready,axi_awvalid,axi_wready,axi_wusero_last,axi_arready,axi_arvalid,axi_rvalid,axi_rlast;
    wire [255:0] axi_wdata,axi_rdata;wire [31:0] axi_wstrb;
    mosaic_ddr_dma #(.P_CAMERA_ONLY_LAYOUT(0),.P_M2_ONLY(1)) u_dma(.mem_clk(core_clk),.rst_n(mem_rstn),.wr_valid(wr_valid),.wr_ready(wr_ready),
        .wr_source(wr_source),.wr_block(wr_block),.wr_frame(wr_frame),.wr_data(wr_data),
        .line_req_valid(dma_req_valid),.line_req_ready(dma_req_ready),.line_req_y(dma_req[10:0]),
        .line_req_mode(dma_req[12:11]),.line_req_frame_start(dma_req[45]),
        .line_req_epoch(dma_req[20:13]),.line_req_frame_id(dma_req[44:13]),
        .line_data_valid(dma_data_valid),.line_data_ready(dma_data_ready),.line_data(dma_line_data),
        .line_data_y(dma_line_y),.line_data_index(dma_line_index),.line_data_epoch(dma_line_epoch),
        .line_data_source_valid(dma_line_source_valid),
        .axi_awaddr(axi_awaddr),.axi_awid(axi_awuser_id),.axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_arid(axi_aruser_id),.axi_arlen(axi_arlen),.axi_arready(axi_arready),.axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata),.axi_rvalid(axi_rvalid),.axi_rid(axi_rid),.axi_rlast(axi_rlast),
        .debug_frame_valid(diagnostic_frame_valid),.debug_display_valid(dma_display_valid),
        .debug_drop_count(diagnostic_dma_drops),.debug_protocol_error(diagnostic_dma_protocol_error),
        .debug_drop_s4(diagnostic_drop_s4),.debug_drop_s5(diagnostic_drop_s5),
        .debug_cyc_addr(diagnostic_cyc_addr),.debug_cyc_data(diagnostic_cyc_data),
        .debug_cyc_drain(diagnostic_cyc_drain),.debug_cyc_total(diagnostic_cyc_total),
        .snapshot_pulse(dma_snapshot_pulse),.snapshot_epoch(dma_snapshot_epoch),
        .snapshot_frame_id(dma_snapshot_frame_id),.snapshot_source_frames(dma_snapshot_frames));
        DDR3_50H u_DDR3_50H (
             .ref_clk                   (sys_clk            ),
             .resetn                    (rstn_out           ),
             .ddr_init_done             (ddr_init_done      ),
             .ddrphy_clkin              (core_clk           ),
             .pll_lock                  (pll_lock           ),
             .axi_awaddr                (axi_awaddr         ),
             .axi_awuser_ap             (1'b0               ),
             .axi_awuser_id             (axi_awuser_id      ),
             .axi_awlen                 (axi_awlen          ),
             .axi_awready               (axi_awready        ),
             .axi_awvalid               (axi_awvalid        ),
             .axi_wdata                 (axi_wdata          ),
             .axi_wstrb                 (axi_wstrb          ),
             .axi_wready                (axi_wready         ),
             .axi_wusero_id             (                   ),
             .axi_wusero_last           (axi_wusero_last    ),
             .axi_araddr                (axi_araddr         ),
             .axi_aruser_ap             (1'b0               ),
             .axi_aruser_id             (axi_aruser_id      ),
             .axi_arlen                 (axi_arlen          ),
             .axi_arready               (axi_arready        ),
             .axi_arvalid               (axi_arvalid        ),
             .axi_rdata                 (axi_rdata          ),
             .axi_rid                   (axi_rid            ),
             .axi_rlast                 (axi_rlast          ),
             .axi_rvalid                (axi_rvalid         ),
             .apb_clk                   (1'b0               ),
             .apb_rst_n                 (1'b1               ),
             .apb_sel                   (1'b0               ),
             .apb_enable                (1'b0               ),
             .apb_addr                  (8'b0               ),
             .apb_write                 (1'b0               ),
             .apb_ready                 (                   ),
             .apb_wdata                 (16'b0              ),
             .apb_rdata                 (                   ),
             .apb_int                   (                   ),
             .mem_rst_n                 (mem_rst_n          ),
             .mem_ck                    (mem_ck             ),
             .mem_ck_n                  (mem_ck_n           ),
             .mem_cke                   (mem_cke            ),
             .mem_cs_n                  (mem_cs_n           ),
             .mem_ras_n                 (mem_ras_n          ),
             .mem_cas_n                 (mem_cas_n          ),
             .mem_we_n                  (mem_we_n           ),
             .mem_odt                   (mem_odt            ),
             .mem_a                     (mem_a              ),
             .mem_ba                    (mem_ba             ),
             .mem_dqs                   (mem_dqs            ),
             .mem_dqs_n                 (mem_dqs_n          ),
             .mem_dq                    (mem_dq             ),
             .mem_dm                    (mem_dm             ),
             .debug_data                (                   ),
             .debug_slice_state         (                   ),
             .debug_calib_ctrl          (                   ),
             .ck_dly_set_bin            (                   ),
             .force_ck_dly_en           (1'b0               ),
             .force_ck_dly_set_bin      (8'h05              ),
             .dll_step                  (                   ),
             .dll_lock                  (                   ),
             .init_read_clk_ctrl        (2'b0               ),
             .init_slip_step            (4'b0               ),
             .force_read_clk_ctrl       (1'b0               ),
             .ddrphy_gate_update_en     (1'b0               ),
             .update_com_val_err_flag   (                   ),
             .rd_fake_stop              (1'b0               )
       );

    reg [27:0] heart_count;
    always @(posedge core_clk or negedge mem_rstn) begin
        if(!mem_rstn) begin heart_count<=0;heart_beat_led<=1; end
        else if(heart_count==100000000-1) begin heart_count<=0;heart_beat_led<=~heart_beat_led; end
        else heart_count<=heart_count+1;
    end
endmodule
