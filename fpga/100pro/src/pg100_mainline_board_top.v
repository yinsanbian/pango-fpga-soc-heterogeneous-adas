// Source snapshot: rtl/mainline/pg100_mainline_board_top.v
// MES2L676-100HP V1.2 physical top. Each external pin has one owner.
// 27 MHz always-on control, continuous 125 MHz DDR reference for MAC TX/MDIO,
// independent native DDR application clock and source-synchronous HDMI/RGMII.
module pg100_mainline_board_top #(
 parameter FEATURE_PROFILE=2,
 parameter TYPEC_UART_TEST=0
)(
 input wire ref_clk_p,ref_clk_n,free_clk,rst_board,
 input wire uart_rxd,output wire uart_txd,
 input wire hd_rx_pclk,hd_rx_hs,hd_rx_vs,hd_rx_de,input wire[23:0]hd_rx_rgb,
 output wire hd_tx_pclk,hd_tx_hs,hd_tx_vs,hd_tx_de,output wire[23:0]hd_tx_rgb,
 inout wire hd_scl,hd_sda,output wire rstn_out,
 input wire rgmii_rxc,rgmii_rx_ctl,input wire[3:0]rgmii_rxd,
 output wire rgmii_txc,rgmii_tx_ctl,output wire[3:0]rgmii_txd,
 output wire mdc,inout wire mdio,
 output wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
 output wire[14:0]mem_a,output wire[2:0]mem_ba,
 inout wire[3:0]mem_dqs,mem_dqs_n,inout wire[31:0]mem_dq,output wire[3:0]mem_dm,
 output wire[5:0]led
);
 GTP_GRS grs(.GRS_N(1'b1));
 wire ref_clk,clk27,native_clk;
 GTP_INBUFDS refclk_inbuf(.O(ref_clk),.I(ref_clk_p),.IB(ref_clk_n));
 GTP_CLKBUFG freeclk_buffer(.CLKIN(free_clk),.CLKOUT(clk27));
 wire pll_lock,phy_pll_lock,gpll_lock,rst_gpll_lock,ddrphy_cpd_lock,ddr_init_done,align_error,ddr_init_fail;
 wire ddr_reset_n,native_clock_good,ddr_reinit_request,soft_reset_toggle;
 wire[31:0]ddr_recoveries;wire[2:0]ddr_recovery_reason;wire[15:0]native_edges;
 pg100_ddr_recovery_supervisor ddr_reset_owner(.clk27(clk27),.por_n(rst_board),.native_clk(native_clk),
  .pll_lock(pll_lock),.ddr_init_done(ddr_init_done),.native_reinit_request(ddr_reinit_request),.soft_reset_toggle(soft_reset_toggle),
  .ddr_reset_n(ddr_reset_n),.native_clock_good(native_clock_good),.recovery_count(ddr_recoveries),.last_reason(ddr_recovery_reason),.measured_native_edges(native_edges));
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]native_reset_sync;
 wire native_reset_async_n=rst_board&&ddr_reset_n&&pll_lock;
 always @(posedge native_clk or negedge native_reset_async_n)
  if(!native_reset_async_n)native_reset_sync<=0;else native_reset_sync<={native_reset_sync[1:0],1'b1};
 wire native_rst_n=native_reset_sync[2];
 wire training_fault_native;
 pg100_training_fault_cdc training_fault_receiver(.clk(native_clk),.rst_n(native_rst_n),
  .fault_async(ddr_init_fail),.fault_native(training_fault_native));
 wire run_enable,rgb_confirmed,export_enable,config_update,native_soft_reset;
 wire[7:0]cfg_origin;wire[63:0]cfg_session;wire[15:0]cfg_mode;wire[31:0]cfg_calib,cfg_epoch,bad_commands,accepted_commands;
 wire[1279:0]native_status_words;
 wire local_uart_rxd,local_uart_txd,typec_uart_txd;
 assign local_uart_rxd=TYPEC_UART_TEST?1'b1:uart_rxd;
 assign uart_txd=TYPEC_UART_TEST?typec_uart_txd:local_uart_txd;
 pg100_local_control local_control(.clk27(clk27),.por_n(rst_board),.uart_rxd(local_uart_rxd),.clk_native(native_clk),.native_rst_n(native_rst_n),
  .native_status_words(native_status_words),
  .uart_txd(local_uart_txd),.cfg_run_enable(run_enable),.cfg_rgb888_confirmed(rgb_confirmed),.cfg_export_enable(export_enable),
  .cfg_origin(cfg_origin),.cfg_session(cfg_session),.cfg_mode(cfg_mode),.cfg_calib(cfg_calib),.cfg_epoch(cfg_epoch),
  .cfg_update(config_update),.native_soft_reset(native_soft_reset),.soft_reset_toggle(soft_reset_toggle),.bad_commands(bad_commands),.accepted_commands(accepted_commands));
 wire ctrl_rst_n,pixel_rst_n,net_rst_n,pixel_clock_good,hdmi_init_done,hdmi_init_failed;
 wire[2:0]i2c_failure;wire[31:0]i2c_retries,pclk_losses;wire[15:0]pclk_edges;
 wire[23:0]pix_rgb;wire pv,sof,eol,eof,fs,fe,fc,fd;wire[11:0]px,py;wire[31:0]capture_tag,capture_commit_tag;
 wire bridge_fault,control_overflow,storage_fault,reader_fault,pixel_control_overflow;
 wire[31:0]diag_captured_frames,diag_discarded_frames,diag_good_identity,diag_bad_identity;
 wire[31:0]nat_cap_frames,nat_dis_frames,nat_good_identity,nat_bad_identity;
 wire[31:0]dbg_frame_cycles;wire[12:0]dbg_active_lines;wire[15:0]dbg_line_cycles;wire dbg_bad_frame;wire[3:0]dbg_sync;wire[15:0]dbg_vs_count;wire dbg_ready;wire[7:0]dbg_bad_reason;wire[3:0]dbg_commit_reason;
 wire[7:0]dbg_freq_value;wire[15:0]dbg_freq_tries;wire[3:0]dbg_freq_state;wire dbg_freq_forced;
 wire[31:0]dbg_rx_vs_cnt,dbg_rx_hs_cnt,dbg_rx_de_cnt,dbg_rx_de_high;
 pg100_hdmi_frontend hdmi(.clk27(clk27),.por_n(rst_board),.hard_reset_request(1'b0),.netclk(ref_clk),
  .rx_pclk(hd_rx_pclk),.rx_rgb(hd_rx_rgb),.rx_hs(hd_rx_hs),.rx_vs(hd_rx_vs),.rx_de(hd_rx_de),
  .rgb888_format_confirmed(rgb_confirmed),.pixel_storage_overflow(pixel_control_overflow),.hd_scl(hd_scl),.hd_sda(hd_sda),
  .shared_rst_n(rstn_out),.ctrl_rst_n(ctrl_rst_n),.pixel_rst_n(pixel_rst_n),.net_rst_n(net_rst_n),.tx_pclk(),
  .tx_rgb(hd_tx_rgb),.tx_hs(hd_tx_hs),.tx_vs(hd_tx_vs),.tx_de(hd_tx_de),
  .pixel_clock_good(pixel_clock_good),.init_done(hdmi_init_done),.init_failed(hdmi_init_failed),.i2c_failure_code(i2c_failure),
  .i2c_retry_count(i2c_retries),.pixel_clock_loss_count(pclk_losses),.measured_pclk_edges(pclk_edges),
  .dbg_frame_cycles(dbg_frame_cycles),.dbg_active_lines(dbg_active_lines),.dbg_line_cycles(dbg_line_cycles),
  .dbg_bad_frame(dbg_bad_frame),.dbg_sync(dbg_sync),.dbg_vs_count(dbg_vs_count),.dbg_ready(dbg_ready),.dbg_bad_reason(dbg_bad_reason),.dbg_commit_reason(dbg_commit_reason),
  .dbg_freq_value(dbg_freq_value),.dbg_freq_tries(dbg_freq_tries),.dbg_freq_state(dbg_freq_state),.dbg_freq_forced(dbg_freq_forced),
  .dbg_rx_vs_cnt(dbg_rx_vs_cnt),.dbg_rx_hs_cnt(dbg_rx_hs_cnt),.dbg_rx_de_cnt(dbg_rx_de_cnt),.dbg_rx_de_high(dbg_rx_de_high),
  .pix_rgb(pix_rgb),.pix_valid(pv),.pix_sof(sof),.pix_eol(eol),.pix_eof(eof),.pix_x(px),.pix_y(py),
  .frame_start(fs),.frame_end(fe),.frame_commit(fc),.frame_discard(fd),.capture_tag(capture_tag),.commit_tag(capture_commit_tag),
  .captured_frames(diag_captured_frames),.discarded_frames(diag_discarded_frames),.mono(),.mono_valid(),.mono_mask(),.mono_sof(),.mono_eol(),.mono_eof(),.work_x(),.work_y());
 // Continuous source-frequency clock, physical ODDR primitive rather than a
 // fabric combinational clock assign. Same-edge phase retains vendor mode.
 GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET"))
  hdmi_output_clock(.CLK(hd_rx_pclk),.CE(1'b1),.RS(1'b0),.D0(1'b1),.D1(1'b0),.Q(hd_tx_pclk));
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]video_ready_sync,link_ready_sync;
 always @(posedge native_clk or negedge native_rst_n)
  if(!native_rst_n)video_ready_sync<=0;else video_ready_sync<={video_ready_sync[1:0],pixel_clock_good&&hdmi_init_done};
 always @(posedge hd_rx_pclk or negedge pixel_rst_n)
  if(!pixel_rst_n)link_ready_sync<=0;else link_ready_sync<={link_ready_sync[1:0],hdmi_init_done&&rgb_confirmed};
 reg[6:0]us_ticks;reg[63:0]now_us;
 always @(posedge native_clk or negedge native_rst_n)
  if(!native_rst_n)begin us_ticks<=0;now_us<=0;end
  else if(us_ticks==124)begin us_ticks<=0;if(now_us!=64'hffffffffffffffff)now_us<=now_us+1'b1;end
  else us_ticks<=us_ticks+1'b1;
 wire publish_valid;wire[1:0]publish_slot;wire[31:0]publish_generation;wire[151:0]publish_key;
 wire selected_valid,selected_ready;wire[1:0]selected_slot;wire[31:0]selected_generation,selected_epoch,sequence_base;
 wire[151:0]selected_key,permit_key;wire[31:0]permit_epoch;wire permit_valid;
 wire[63:0]selected_timestamp,selected_deadline;
 wire warm_reset,invalidate,result_busy,core_quiescent,native_idle,selected_complete,selected_dropped,export_current,recovering;
 wire[7:0]result_count;wire[31:0]accepted_frames,completed_frames,dropped_frames,superseded_frames,rejected_frames,recovery_events;
 wire[63:0]completed_points;
 wire network_quiescent;
 wire telemetry_sequence_request,telemetry_sequence_ready;
 wire[31:0]telemetry_sequence_base;
 pg100_single_board_controller controller(.clk(native_clk),.rst_n(native_rst_n),.init_done(ddr_init_done),
  .run_enable(run_enable),.rgb888_confirmed(rgb_confirmed),.video_clock_good(video_ready_sync[2]),
  .soft_reset(native_soft_reset),.config_update(config_update),.core_fault(storage_fault||reader_fault||bridge_fault||control_overflow||align_error||training_fault_native),
  .core_quiescent(core_quiescent&&network_quiescent),.now_us(now_us),
  .cfg_export_enable(export_enable),.cfg_origin(cfg_origin),.cfg_session(cfg_session),.cfg_mode(cfg_mode),.cfg_calib(cfg_calib),.cfg_epoch(cfg_epoch),
  .publish_valid(publish_valid),.publish_slot(publish_slot),.publish_generation(publish_generation),.publish_key(publish_key),
  .result_busy(result_busy),.selected_complete(selected_complete),.selected_dropped(selected_dropped),.result_count(result_count),
  .selected_valid(selected_valid),.selected_ready(selected_ready),.selected_slot(selected_slot),.selected_generation(selected_generation),.selected_key(selected_key),.selected_epoch(selected_epoch),
  .selected_timestamp_us(selected_timestamp),.selected_deadline_us(selected_deadline),.permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),
  .warm_reset(warm_reset),.invalidate(invalidate),.ddr_reinit_request(ddr_reinit_request),.export_current(export_current),.sequence_base(sequence_base),
  .telemetry_sequence_request(telemetry_sequence_request),.telemetry_sequence_ready(telemetry_sequence_ready),.telemetry_sequence_base(telemetry_sequence_base),
  .accepted_frames(accepted_frames),.completed_frames(completed_frames),.dropped_frames(dropped_frames),.superseded_frames(superseded_frames),
  .rejected_identity_frames(rejected_frames),.recovery_events(recovery_events),.completed_points(completed_points),.recovering(recovering));
 wire rhv,rhr,rv,rr,rl,ra;wire[10:0]rlen;wire[1:0]peer;wire[7:0]rdata;
 wire[31:0]stored_drops,reader_drops,pixel_drops,read_bursts;wire[63:0]read_bytes,active_cycles;
 wire[27:0]awa,ara;wire[3:0]awid,arid,awlen,arlen,wid,rid;wire awap,arap,awv,arv,awready,arready,wready,wlast,rvalid,rlast;
 wire[255:0]wdata,rddr;wire[31:0]wstrb;
 pg100_mainline_core #(.FEATURE_PROFILE(FEATURE_PROFILE)) core(.clk(native_clk),.rst_n(native_rst_n),.init_done(ddr_init_done),.warm_reset(warm_reset),.invalidate(invalidate),
  .pclk(hd_rx_pclk),.pixel_rst_n(pixel_rst_n),.link_locked(link_ready_sync[2]),.pix_rgb(pix_rgb),.pix_valid(pv),.pix_sof(sof),.pix_eol(eol),.pix_eof(eof),.pix_x(px),.pix_y(py),
  .frame_start(fs),.frame_end(fe),.frame_commit(fc),.frame_discard(fd),.capture_tag(capture_tag),.capture_commit_tag(capture_commit_tag),
  .publish_valid(publish_valid),.publish_slot(publish_slot),.publish_generation(publish_generation),.publish_key(publish_key),
  .diag_good_identity(diag_good_identity),.diag_bad_identity(diag_bad_identity),
  .diag_captured_frames(diag_captured_frames),.diag_discarded_frames(diag_discarded_frames),
  .nat_cap_frames(nat_cap_frames),.nat_dis_frames(nat_dis_frames),
  .nat_good_identity(nat_good_identity),.nat_bad_identity(nat_bad_identity),
  .selected_valid(selected_valid),.selected_ready(selected_ready),.selected_slot(selected_slot),.selected_generation(selected_generation),.selected_key(selected_key),.selected_epoch(selected_epoch),
  .selected_timestamp_us(selected_timestamp),.selected_deadline_us(selected_deadline),.now_us(now_us),.permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.sequence_base(sequence_base),
  .result_hdr_valid(rhv),.result_hdr_ready(rhr),.result_length(rlen),.result_peer(peer),.result_data(rdata),.result_valid(rv),.result_ready(rr),.result_last(rl),.result_abort(ra),
  .result_busy(result_busy),.quiescent(core_quiescent),.native_idle(native_idle),.selected_complete(selected_complete),.selected_dropped(selected_dropped),
  .stored_dropped_frames(stored_drops),.reader_dropped_frames(reader_drops),.algorithm_read_bytes(read_bytes),.algorithm_active_cycles(active_cycles),.algorithm_read_bursts(read_bursts),.result_count(result_count),
  .storage_fault(storage_fault),.reader_fault(reader_fault),.bridge_fault(bridge_fault),.control_overflow(control_overflow),.pixel_control_overflow(pixel_control_overflow),.pixel_dropped_frames(pixel_drops),
  .axi_awaddr(awa),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awv),.axi_awready(awready),.axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(ara),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arv),.axi_arready(arready),.axi_rdata(rddr),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid));
 // Exact repaired PHY hierarchy retained so each placement repair remains
 // auditable. New whole-design placement and every STA corner are mandatory.
 ddr3_test I_ips_ddr_top(.ref_clk(ref_clk),.resetn(ddr_reset_n&&rst_board),.core_clk(native_clk),.pll_lock(pll_lock),.phy_pll_lock(phy_pll_lock),.gpll_lock(gpll_lock),.rst_gpll_lock(rst_gpll_lock),
  .ddrphy_cpd_lock(ddrphy_cpd_lock),.ddr_init_done(ddr_init_done),
  .axi_awaddr(awa),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awv),.axi_awready(awready),.axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(ara),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arv),.axi_arready(arready),.axi_rdata(rddr),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid),
  .apb_clk(1'b0),.apb_rst_n(1'b0),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'b0),.apb_write(1'b0),.apb_ready(),.apb_wdata(16'b0),.apb_rdata(),
  .mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),.mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),.mem_odt(mem_odt),
  .mem_a(mem_a),.mem_ba(mem_ba),.mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
  .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
  .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'b0),.init_samp_position_odd(32'b0),.wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'b0),
  .force_read_clk_ctrl(1'b0),.init_slip_step(16'b0),.init_read_clk_ctrl(12'b0),
  .debug_calib_ctrl(),.dbg_slice_status(),.dbg_slice_state(),.debug_data(),.dbg_dll_upd_state(),.debug_gpll_dps_phase(),.dbg_rst_dps_state(),.dbg_tran_err_rst_cnt(),.dbg_ddrphy_init_fail(ddr_init_fail),
  .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'b0),.debug_dps_cnt_dir0(),.debug_dps_cnt_dir1(),
  .ck_dly_en(1'b0),.init_ck_dly_step(8'b0),.ck_dly_set_bin(),.align_error(align_error),.debug_rst_state(),.debug_cpd_state());
 wire link_gigabit,phy_present,delay_verified,net_hr,net_ready,mdio_out,mdio_oe;
 wire[31:0]rx_accepted,rx_rejected,mdio_errors;wire bad_fcs,rx_overflow,arp_failed;
 wire ctl_hdr_valid,ctl_hdr_ready,ctl_valid,ctl_ready,ctl_last,ctl_abort;
 wire[10:0]ctl_length;wire[1:0]ctl_peer;wire[7:0]ctl_data;
 wire[31:0]telemetry_packets,telemetry_cancelled,telemetry_coalesced,last_duration,timing_samples,fps_q16;
 wire timing_measured,fps_valid;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]native_good_sync,hdmi_config_sync,cpd_lock_sync;
 always @(posedge native_clk or negedge native_rst_n)
  if(!native_rst_n)begin native_good_sync<=0;hdmi_config_sync<=0;cpd_lock_sync<=0;end
  else begin native_good_sync<={native_good_sync[1:0],native_clock_good};hdmi_config_sync<={hdmi_config_sync[1:0],hdmi_init_done};cpd_lock_sync<={cpd_lock_sync[1:0],ddrphy_cpd_lock};end
 wire rx_hdr_valid,rx_hdr_ready,rx_valid,rx_ready,rx_last;
 wire[10:0]rx_length;wire[1:0]rx_peer;wire[7:0]rx_data;
 wire[31:0]rx_good_envelopes,rx_bad_envelopes,rx_bad_crc,rx_metadata_frames,rx_bad_metadata,rx_receive_timeouts;
 wire[151:0]last_metadata_key;wire[7:0]last_message_type;
 pg100_rx_local_monitor receive_inspector(.clk(native_clk),.rst_n(native_rst_n),
  .s_hdr_valid(rx_hdr_valid),.s_hdr_ready(rx_hdr_ready),.s_length(rx_length),.s_peer(rx_peer),.s_data(rx_data),.s_valid(rx_valid),.s_ready(rx_ready),.s_last(rx_last),
  .cfg_export_enable(export_enable),.cfg_origin(cfg_origin),.cfg_session(cfg_session),.cfg_mode(cfg_mode),.cfg_calib(cfg_calib),
  .envelope_accepted(),.frame_meta_accepted(),.frame_meta_matches_config(),.last_metadata_key(last_metadata_key),.last_message_type(last_message_type),
  .good_envelopes(rx_good_envelopes),.bad_envelopes(rx_bad_envelopes),.bad_crc(rx_bad_crc),.frame_metadata_packets(rx_metadata_frames),.bad_frame_metadata(rx_bad_metadata),.receive_timeouts(rx_receive_timeouts));
 reg[151:0]timing_key;reg[31:0]timing_epoch;reg[63:0]timing_deadline;
 reg[31:0]tx_queued_packets,deadline_expiries;
 wire[31:0]crc_error_count,rx_overflow_events,tx_wire_frames;
 wire result_queued=rv&&rr&&rl&&export_current&&!ra&&!invalidate;
 wire telemetry_queued=ctl_valid&&ctl_ready&&ctl_last&&!ctl_abort&&!invalidate;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]link_gigabit_sync;
 always @(posedge native_clk or negedge native_rst_n)
  if(!native_rst_n)begin timing_key<=0;timing_epoch<=0;timing_deadline<=0;link_gigabit_sync<=0;tx_queued_packets<=0;deadline_expiries<=0;end
  else begin
   link_gigabit_sync<={link_gigabit_sync[1:0],link_gigabit};
   if(selected_valid&&selected_ready)begin timing_key<=selected_key;timing_epoch<=selected_epoch;timing_deadline<=selected_deadline;end
   if(result_queued&&telemetry_queued)tx_queued_packets<=tx_queued_packets>=32'hfffffffe ? 32'hffffffff : tx_queued_packets+2;
   else if((result_queued||telemetry_queued)&&tx_queued_packets!=32'hffffffff)tx_queued_packets<=tx_queued_packets+1'b1;
   if(selected_dropped&&now_us>=timing_deadline&&deadline_expiries!=32'hffffffff)deadline_expiries<=deadline_expiries+1'b1;
  end
 pg100_mainline_telemetry telemetry(.clk(native_clk),.rst_n(native_rst_n),.enabled(export_enable),.invalidate(invalidate),.now_us(now_us),.cfg_epoch(cfg_epoch),
  .frame_begin(selected_valid&&selected_ready),.frame_complete(selected_complete),.frame_dropped(selected_dropped),
  .frame_key(selected_valid&&selected_ready?selected_key:timing_key),.frame_epoch(selected_valid&&selected_ready?selected_epoch:timing_epoch),
  .link_up(link_gigabit_sync[2]),.video_ready(video_ready_sync[2]&&rgb_confirmed),.memory_ready(ddr_init_done),.core_fault(storage_fault||reader_fault||bridge_fault||control_overflow||align_error||training_fault_native),
  .frame_count(completed_frames),.drop_count(dropped_frames),.rx_packets(rx_accepted),
  .tx_packets(tx_queued_packets),.crc_errors(crc_error_count),.source_timeouts(deadline_expiries),.recovery_events(recovery_events),
  .sequence_request(telemetry_sequence_request),.sequence_ready(telemetry_sequence_ready),.sequence_base(telemetry_sequence_base),
  .m_hdr_valid(ctl_hdr_valid),.m_hdr_ready(ctl_hdr_ready),.m_length(ctl_length),.m_peer(ctl_peer),.m_data(ctl_data),.m_valid(ctl_valid),.m_ready(ctl_ready),.m_last(ctl_last),.m_abort(ctl_abort),
  .completed_packets(telemetry_packets),.cancelled_packets(telemetry_cancelled),.coalesced_timings(telemetry_coalesced),
  .last_duration_us(last_duration),.timing_samples(timing_samples),.timing_measured(timing_measured),.fps_q16(fps_q16),.fps_valid(fps_valid));
 assign mdio=mdio_oe?mdio_out:1'bz;
 assign rhr=export_current?net_hr:1'b1;assign rr=export_current?net_ready:1'b1;
 pg100_mainline_network network(.clk125(ref_clk),.clk_logic(native_clk),.rst(!net_rst_n||!native_rst_n),
  .rgmii_rxc(rgmii_rxc),.rgmii_rxd(rgmii_rxd),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_txc(rgmii_txc),.rgmii_txd(rgmii_txd),.rgmii_tx_ctl(rgmii_tx_ctl),
  .mdc(mdc),.mdio_out(mdio_out),.mdio_oe(mdio_oe),.mdio_in(mdio),.link_gigabit(link_gigabit),.phy_present(phy_present),.delay_verified(delay_verified),
  .rx_hdr_valid(rx_hdr_valid),.rx_hdr_ready(rx_hdr_ready),.rx_peer(rx_peer),.rx_length(rx_length),.rx_data(rx_data),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_last(rx_last),
  .ctl_hdr_valid(ctl_hdr_valid),.ctl_hdr_ready(ctl_hdr_ready),.ctl_peer(ctl_peer),.ctl_length(ctl_length),.ctl_abort(ctl_abort||invalidate),.ctl_data(ctl_data),.ctl_valid(ctl_valid),.ctl_ready(ctl_ready),.ctl_last(ctl_last),
  .result_hdr_valid(rhv&&export_current),.result_hdr_ready(net_hr),.result_peer(peer),.result_length(rlen),.result_abort(ra||invalidate),
  .result_data(rdata),.result_valid(rv&&export_current),.result_ready(net_ready),.result_last(rl),
  .rx_accepted(rx_accepted),.rx_rejected(rx_rejected),.mdio_errors(mdio_errors),.rx_bad_fcs(bad_fcs),.rx_fifo_overflow(rx_overflow),.tx_arp_failed(arp_failed),.tx_quiescent(network_quiescent),
  .rx_crc_errors_native(crc_error_count),.rx_overflow_events_native(rx_overflow_events),.tx_wire_frames(tx_wire_frames));
 // PGS2 opcode4 word0 is the least-significant word. Every field below is
 // native-domain state or an explicitly synchronized/atomic source snapshot.
 assign native_status_words[0*32+:32]=FEATURE_PROFILE;
 assign native_status_words[1*32+:32]=32'd125000000;
 assign native_status_words[2*32+:32]={20'b0,native_good_sync[2],storage_fault||reader_fault||bridge_fault||control_overflow||align_error||training_fault_native,recovering,result_busy,export_enable,run_enable,rgb_confirmed,link_gigabit_sync[2],video_ready_sync[2],hdmi_config_sync[2],cpd_lock_sync[2],ddr_init_done};
 assign native_status_words[3*32+:32]=accepted_frames;
 assign native_status_words[4*32+:32]=completed_frames;
 // TEMPORARY DEBUG MAPPING (dead-RX diagnosis). These words are placeholders
 // until the delivery bitstream; the protocol meanings are restored there.
 //   w5 = raw RX VS rising count     w6  = raw RX DE rising count
 //   w11= capture frame_cycles       w12 = capture active_lines
 //   w13= capture line_cycles        w14 = {bad_frame, commit_reason, bad_reason}
 //   w15= capture VS count           w17 = raw RX HS rising count
 //   w18= {3'b0, freq_forced, freq_state[3:0], freq_value[7:0], freq_tries[15:0]}
 assign native_status_words[5*32+:32]=dbg_rx_vs_cnt;
 assign native_status_words[6*32+:32]=dbg_rx_de_cnt;
 assign native_status_words[11*32+:32]=dbg_frame_cycles;
 assign native_status_words[12*32+:32]={19'b0,dbg_active_lines};
 assign native_status_words[13*32+:32]={16'b0,dbg_line_cycles};
 assign native_status_words[14*32+:32]={19'b0,dbg_bad_reason,dbg_commit_reason,dbg_bad_frame};
 assign native_status_words[15*32+:32]={16'b0,dbg_vs_count};
 assign native_status_words[17*32+:32]=dbg_rx_hs_cnt;
 assign native_status_words[18*32+:32]={3'b0,dbg_freq_forced,dbg_freq_state,dbg_freq_value,dbg_freq_tries};
 assign native_status_words[7*32+:32]=rejected_frames;
 assign native_status_words[8*32+:32]=recovery_events;
 assign native_status_words[9*32+:64]=completed_points;
 assign native_status_words[16*32+:32]=pixel_drops;
 assign native_status_words[19*32+:32]=tx_queued_packets;
 assign native_status_words[20*32+:32]=tx_wire_frames;
 assign native_status_words[21*32+:32]=rx_accepted;
 assign native_status_words[22*32+:32]=rx_rejected;
 assign native_status_words[23*32+:32]=crc_error_count;
 assign native_status_words[24*32+:32]=rx_overflow_events;
 assign native_status_words[25*32+:32]=mdio_errors;
 assign native_status_words[26*32+:32]=rx_good_envelopes;
 assign native_status_words[27*32+:32]=rx_bad_envelopes;
 assign native_status_words[28*32+:32]=rx_bad_crc;
 assign native_status_words[29*32+:32]=rx_metadata_frames;
 assign native_status_words[30*32+:32]=rx_bad_metadata;
 assign native_status_words[31*32+:32]=rx_receive_timeouts;
 assign native_status_words[32*32+:32]=last_duration;
 assign native_status_words[33*32+:32]=timing_samples;
 assign native_status_words[34*32+:32]=fps_q16;
 assign native_status_words[35*32+:32]={30'b0,timing_measured,fps_valid};
 assign native_status_words[36*32+:32]=telemetry_cancelled;
 assign native_status_words[37*32+:32]=telemetry_packets;
 assign native_status_words[38*32+:32]=timing_key[79:48];
 assign native_status_words[39*32+:32]=last_metadata_key[79:48];
 reg[2:0]rx_vs_27;reg rx_vs_27_d;reg[31:0]rx_vs_rises;
 always @(posedge clk27 or negedge rst_board)begin
  if(!rst_board)begin rx_vs_27<=0;rx_vs_27_d<=0;rx_vs_rises<=0;end
  else begin
   rx_vs_27<={rx_vs_27[1:0],hd_rx_vs};rx_vs_27_d<=rx_vs_27[2];
   if(rx_vs_27[2]&&!rx_vs_27_d)rx_vs_rises<=rx_vs_rises+1'b1;
  end
 end
 reg[24:0]heartbeat27;always @(posedge clk27 or negedge rst_board)if(!rst_board)heartbeat27<=0;else heartbeat27<=heartbeat27+1'b1;
 assign led={heartbeat27[24],storage_fault||reader_fault||bridge_fault||control_overflow||align_error||ddr_init_fail,
  result_busy,link_gigabit,hdmi_init_done&&pixel_clock_good,ddr_init_done};
 pg100_typec_uart typec_uart(.clk27(clk27),.rst_n(rst_board),.uart_rxd(uart_rxd),.uart_txd(typec_uart_txd),
  .pll_lock(pll_lock),.phy_pll_lock(phy_pll_lock),.gpll_lock(gpll_lock),.rst_gpll_lock(rst_gpll_lock),.ddrphy_cpd_lock(ddrphy_cpd_lock),
  .ddr_init_done(ddr_init_done),.ddr_init_fail(ddr_init_fail),.align_error(align_error),
  .hdmi_init_done(hdmi_init_done),.hdmi_init_failed(hdmi_init_failed),.pixel_clock_good(pixel_clock_good),
  .pclk_edges(pclk_edges),.pclk_losses(pclk_losses),.i2c_failure(i2c_failure),.i2c_retries(i2c_retries),
  .link_gigabit(link_gigabit),.phy_present(phy_present),
  .ddr_recoveries(ddr_recoveries),.ddr_recovery_reason(ddr_recovery_reason),.native_edges(native_edges),
  .run_enable(run_enable),.rgb_confirmed(rgb_confirmed),.export_enable(export_enable),
  .bad_commands(bad_commands),.accepted_commands(accepted_commands));
endmodule

// Source snapshot: rtl/mainline/pg100_mainline_core.v
// Physical capture -> complete line CDC -> native DDR committed slot -> leased
// work-image reader -> FEATURE datagrams. Authority/metadata association owns
// selected_* and permit_*. HDMI/RGMII chips are instantiated by board_top.
module pg100_mainline_core #(parameter FEATURE_PROFILE=1)(
 input wire clk,rst_n,init_done,warm_reset,invalidate,
 input wire pclk,pixel_rst_n,link_locked,
 input wire[23:0]pix_rgb,input wire pix_valid,pix_sof,pix_eol,pix_eof,
 input wire[11:0]pix_x,pix_y,
 input wire frame_start,frame_end,frame_commit,frame_discard,
 input wire[31:0]capture_tag,capture_commit_tag,
 output wire publish_valid,output wire[1:0]publish_slot,
 output wire[31:0]publish_generation,output wire[151:0]publish_key,
 output wire[31:0]diag_good_identity,diag_bad_identity,
 input wire[31:0]diag_captured_frames,diag_discarded_frames,
 output wire[31:0]nat_cap_frames,nat_dis_frames,nat_good_identity,nat_bad_identity,
 input wire selected_valid,output wire selected_ready,
 input wire[1:0]selected_slot,input wire[31:0]selected_generation,
 input wire[151:0]selected_key,input wire[31:0]selected_epoch,
 input wire[63:0]selected_timestamp_us,selected_deadline_us,now_us,
 input wire permit_valid,input wire[151:0]permit_key,input wire[31:0]permit_epoch,
 input wire[31:0]sequence_base,
 output wire result_hdr_valid,input wire result_hdr_ready,
 output wire[10:0]result_length,output wire[1:0]result_peer,
 output wire[7:0]result_data,output wire result_valid,input wire result_ready,
 output wire result_last,result_abort,
 output reg result_busy,output wire quiescent,
 output reg selected_complete,selected_dropped,
 output wire[31:0]stored_dropped_frames,reader_dropped_frames,
 output wire[63:0]algorithm_read_bytes,algorithm_active_cycles,
 output wire[31:0]algorithm_read_bursts,
 output wire[7:0]result_count,
 output wire storage_fault,reader_fault,bridge_fault,control_overflow,native_idle,pixel_control_overflow,
 output wire[31:0]pixel_dropped_frames,
 output wire[27:0]axi_awaddr,output wire axi_awuser_ap,output wire[3:0]axi_awuser_id,axi_awlen,
 output wire axi_awvalid,input wire axi_awready,output wire[255:0]axi_wdata,
 output wire[31:0]axi_wstrb,input wire axi_wready,input wire[3:0]axi_wusero_id,input wire axi_wusero_last,
 output wire[27:0]axi_araddr,output wire axi_aruser_ap,output wire[3:0]axi_aruser_id,axi_arlen,
 output wire axi_arvalid,input wire axi_arready,input wire[255:0]axi_rdata,
 input wire[3:0]axi_rid,input wire axi_rlast,axi_rvalid
);
 wire fifo_rst_n=rst_n&&pixel_rst_n&&!warm_reset;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]pclk_reset_sync;
 always @(posedge pclk or negedge fifo_rst_n)
  if(!fifo_rst_n)pclk_reset_sync<=0;else pclk_reset_sync<={pclk_reset_sync[1:0],1'b1};
 wire[31:0]pclk_dropped_frames;wire pclk_bridge_fault;
 // One held mailbox carries every PCLK-domain counter; each 32-bit field is
 // captured and released atomically by the toggle handshake, so no counter bus
 // is ever sampled asynchronously.
 pg100_pclk_status_cdc status_cdc(.rst_n(fifo_rst_n),.s_clk(pclk),.m_clk(clk),
  .s_status({diag_good_identity,diag_bad_identity,diag_captured_frames,diag_discarded_frames,
             pclk_bridge_fault,pixel_control_overflow,pclk_dropped_frames}),
  .m_status({nat_good_identity,nat_bad_identity,nat_cap_frames,nat_dis_frames,
             bridge_fault,control_overflow,pixel_dropped_frames}));
 wire[31:0]active_tag,commit_tag;
 wire[151:0]commit_key;
 wire commit_valid,commit_good,identity_valid,marker_error;
 pg100_capture_store_bridge capture_bridge(.pclk(pclk),.rst_n(pclk_reset_sync[2]),.link_locked(link_locked),
  .pix_rgb(pix_rgb),.pix_valid(pix_valid),.pix_sof(pix_sof),.pix_x(pix_x),.pix_y(pix_y),
  .frame_start(frame_start),.frame_end(frame_end),.frame_commit(frame_commit),.frame_discard(frame_discard),
  .capture_tag(capture_tag),.capture_commit_tag(capture_commit_tag),
  .cdc_active_tag(active_tag),.cdc_dropped_frames(pclk_dropped_frames),.cdc_control_overflow(pixel_control_overflow),
  .commit_valid(commit_valid),.commit_good(commit_good),.commit_tag(commit_tag),.commit_key(commit_key),
  .identity_valid(identity_valid),.marker_error(marker_error),.decoded_key(),
  .no_sof_frames(),.bad_identity_frames(diag_bad_identity),.good_identity_frames(diag_good_identity),.bridge_fault(pclk_bridge_fault));
 wire[23:0]stored_rgb;wire stored_valid,stored_ready,stored_sof,stored_eol,stored_eof;
 wire[31:0]stored_tag,stored_commit_tag;wire[151:0]stored_commit_key;
 wire stored_commit_valid,stored_commit_ready,stored_commit_good;
 pg100_pixel_line_cdc line_cdc(.rst_n(fifo_rst_n),.s_clk(pclk),.m_clk(clk),
  .s_rgb(pix_rgb),.s_valid(pix_valid),.s_sof(pix_sof),.s_eol(pix_eol),.s_eof(pix_eof),
  .s_bad(frame_discard||!link_locked),.s_active_tag(active_tag),
  .commit_valid(commit_valid),.commit_tag(commit_tag),.commit_key(commit_key),.commit_good(commit_good),
  .m_rgb(stored_rgb),.m_valid(stored_valid),.m_ready(stored_ready),.m_sof(stored_sof),.m_eol(stored_eol),.m_eof(stored_eof),.m_tag(stored_tag),
  .m_commit_valid(stored_commit_valid),.m_commit_ready(stored_commit_ready),.m_commit_tag(stored_commit_tag),.m_commit_key(stored_commit_key),.m_commit_good(stored_commit_good),
  .dropped_frames(pclk_dropped_frames),.control_overflow(pixel_control_overflow));
 wire aq,aok,rel,alg_valid,alg_ready,alg_reserved;
 wire[1:0]aq_slot,rel_slot,alg_slot;wire[31:0]aq_generation,rel_generation,alg_generation;
 wire[2:0]aq_mask,rel_mask;wire[27:0]alg_offset;wire[3:0]alg_len;
 wire[255:0]rd_data;wire alg_data_valid,rd_last;
 pg100_video_frame_store store(.clk(clk),.rst_n(rst_n),.warm_reset(warm_reset),.init_done(init_done),
  .s_rgb(stored_rgb),.s_valid(stored_valid),.s_ready(stored_ready),.s_sof(stored_sof),.s_eol(stored_eol),.s_eof(stored_eof),.s_tag(stored_tag),
  .commit_valid(stored_commit_valid),.commit_ready(stored_commit_ready),.commit_tag(stored_commit_tag),.commit_key(stored_commit_key),.commit_good(stored_commit_good),
  .publish_valid(publish_valid),.publish_slot(publish_slot),.publish_generation(publish_generation),.publish_key(publish_key),
  .acquire_valid(aq),.acquire_slot(aq_slot),.acquire_generation(aq_generation),.acquire_mask(aq_mask),.acquire_ok(aok),
  .release_valid(rel),.release_slot(rel_slot),.release_generation(rel_generation),.release_mask(rel_mask),
  .tx_valid(1'b0),.tx_ready(),.tx_slot(2'b0),.tx_generation(32'b0),.tx_byte_offset(28'b0),.tx_len(4'b0),.tx_reserved(1'b0),
  .alg_valid(alg_valid),.alg_ready(alg_ready),.alg_slot(alg_slot),.alg_generation(alg_generation),.alg_byte_offset(alg_offset),.alg_len(alg_len),.alg_reserved(alg_reserved),
  .rd_data(rd_data),.tx_data_valid(),.alg_data_valid(alg_data_valid),.rd_last(rd_last),.idle(native_idle),.dropped_frames(stored_dropped_frames),.invalid_request(reader_fault),.fault(storage_fault),
  .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(axi_awready),
  .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),.axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
  .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(axi_arready),
  .axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid));
 reg[151:0]active_key;reg[31:0]active_epoch;reg[63:0]active_timestamp,active_deadline;
 wire reader_ready,reader_busy,reader_completed,reader_dropped,reader_abort;
 wire mono_valid,mono_ready,mono_sof,mono_eol,mono_eof,feature_commit_valid,feature_commit_ready;
 wire[7:0]mono,work_y;wire[8:0]work_x;wire[151:0]work_key,feature_commit_key;
 wire context_cancel=invalidate||warm_reset||!permit_valid||permit_key!=active_key||permit_epoch!=active_epoch||now_us>=active_deadline;
 assign selected_ready=!result_busy&&reader_ready&&!invalidate&&!warm_reset&&permit_valid&&
  selected_key==permit_key&&selected_epoch==permit_epoch&&now_us<selected_deadline_us;
 pg100_ddr_work_reader work_reader(.clk(clk),.rst_n(rst_n),.init_done(init_done),
  .cancel(result_busy&&context_cancel),.native_idle(native_idle),.native_fault(storage_fault||reader_fault),
  .selected_valid(selected_valid&&selected_ready),.selected_ready(reader_ready),.selected_slot(selected_slot),.selected_generation(selected_generation),.selected_key(selected_key),
  .acquire_valid(aq),.acquire_slot(aq_slot),.acquire_generation(aq_generation),.acquire_mask(aq_mask),.acquire_ok(aok),
  .release_valid(rel),.release_slot(rel_slot),.release_generation(rel_generation),.release_mask(rel_mask),
  .alg_valid(alg_valid),.alg_ready(alg_ready),.alg_slot(alg_slot),.alg_generation(alg_generation),.alg_byte_offset(alg_offset),.alg_len(alg_len),.alg_reserved(alg_reserved),
  .rd_data(rd_data),.alg_data_valid(alg_data_valid),.rd_last(rd_last),
  .m_valid(mono_valid),.m_ready(mono_ready),.m_mono(mono),.m_x(work_x),.m_y(work_y),.m_sof(mono_sof),.m_eol(mono_eol),.m_eof(mono_eof),.m_key(work_key),
  .commit_valid(feature_commit_valid),.commit_ready(feature_commit_ready),.commit_key(feature_commit_key),
  .busy(reader_busy),.completed(reader_completed),.dropped(reader_dropped),.abort_frame(reader_abort),
  .completed_frames(),.dropped_frames(reader_dropped_frames),.read_bursts(algorithm_read_bursts),.read_bytes(algorithm_read_bytes),.active_cycles(algorithm_active_cycles));
 wire published,discarded;
 generate if(FEATURE_PROFILE==2)begin:feature_v2
 pg100_feature_transport_v2 algorithm(.clk(clk),.rst(!rst_n),.s_valid(mono_valid),.s_ready(mono_ready),
  .s_mono(mono),.s_x(work_x),.s_y(work_y),.s_sof(mono_sof),.s_eol(mono_eol),.s_eof(mono_eof),.s_key(work_key),.abort_frame(reader_abort||result_busy&&context_cancel),
  .commit_valid(feature_commit_valid),.commit_ready(feature_commit_ready),.commit_good(1'b1),.commit_key(feature_commit_key),
  .now_us(now_us),.frame_timestamp_us(active_timestamp),.frame_deadline_us(active_deadline),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.invalidate(invalidate||warm_reset||reader_abort),.sequence_base(sequence_base),
  .m_hdr_valid(result_hdr_valid),.m_hdr_ready(result_hdr_ready),.m_length(result_length),.m_peer(result_peer),
  .m_data(result_data),.m_valid(result_valid),.m_ready(result_ready),.m_last(result_last),.m_abort(result_abort),
  .published(published),.discarded(discarded),.result_count(result_count),.input_errors(),.commit_errors(),.malformed_frames(),.cancelled_frames(),.rejected_packets());
 end else begin:feature_v1
 pg100_feature_transport algorithm(.clk(clk),.rst(!rst_n),.s_valid(mono_valid),.s_ready(mono_ready),
  .s_mono(mono),.s_x(work_x),.s_y(work_y),.s_sof(mono_sof),.s_eol(mono_eol),.s_eof(mono_eof),.s_key(work_key),.abort_frame(reader_abort||result_busy&&context_cancel),
  .commit_valid(feature_commit_valid),.commit_ready(feature_commit_ready),.commit_good(1'b1),.commit_key(feature_commit_key),
  .now_us(now_us),.frame_timestamp_us(active_timestamp),.frame_deadline_us(active_deadline),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.invalidate(invalidate||warm_reset||reader_abort),.sequence_base(sequence_base),
  .m_hdr_valid(result_hdr_valid),.m_hdr_ready(result_hdr_ready),.m_length(result_length),.m_peer(result_peer),
  .m_data(result_data),.m_valid(result_valid),.m_ready(result_ready),.m_last(result_last),.m_abort(result_abort),
  .published(published),.discarded(discarded),.result_count(result_count),.input_errors(),.commit_errors(),.malformed_frames(),.cancelled_frames(),.rejected_packets());
 end endgenerate
 assign quiescent=!result_busy&&!reader_busy&&native_idle;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin result_busy<=0;selected_complete<=0;selected_dropped<=0;active_key<=0;active_epoch<=0;active_timestamp<=0;active_deadline<=0;end
  else begin
   selected_complete<=0;selected_dropped<=0;
   if(selected_valid&&selected_ready)begin
    result_busy<=1;active_key<=selected_key;active_epoch<=selected_epoch;
    active_timestamp<=selected_timestamp_us;active_deadline<=selected_deadline_us;
   end
   if(result_busy&&published)begin result_busy<=0;selected_complete<=1;end
   if(result_busy&&(reader_dropped||discarded))begin result_busy<=0;selected_dropped<=1;end
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_pclk_status_cdc.v
// Atomic status snapshot. Source bus is captured once and held until a
// three-flop ack returns; no binary counter bus is sampled asynchronously.
module pg100_pclk_status_cdc(
 input wire rst_n,s_clk,m_clk,input wire[129:0]s_status,
 output reg[129:0]m_status
);
 reg request_toggle,acknowledge_toggle;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]request_sync,acknowledge_sync;
 reg[129:0]held_status;
 reg[7:0]poll_ticks;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]sr,mr;
 always @(posedge s_clk or negedge rst_n)
  if(!rst_n)sr<=0;else sr<={sr[1:0],1'b1};
 always @(posedge m_clk or negedge rst_n)
  if(!rst_n)mr<=0;else mr<={mr[1:0],1'b1};
 // Assert the local release reset asynchronously as well: if PCLK stops
 // while ack=1, common reset must clear that old mailbox before native
 // polling resumes. Deassertion still waits for three source clock edges.
 always @(posedge s_clk or negedge sr[2])begin
  if(!sr[2])begin request_sync<=0;acknowledge_toggle<=0;held_status<=0;end
  else begin
   request_sync<={request_sync[1:0],request_toggle};
   if(request_sync[2]!=acknowledge_toggle)begin
    held_status<=s_status;acknowledge_toggle<=request_sync[2];
   end
  end
 end
 reg acknowledge_seen;
 always @(posedge m_clk)begin
  if(!mr[2])begin request_toggle<=0;acknowledge_sync<=0;acknowledge_seen<=0;poll_ticks<=0;m_status<=0;end
  else begin
   acknowledge_sync<={acknowledge_sync[1:0],acknowledge_toggle};poll_ticks<=poll_ticks+1'b1;
   if(acknowledge_sync[2]!=acknowledge_seen)begin
    m_status<=held_status;acknowledge_seen<=acknowledge_sync[2];
   end
   if(poll_ticks==255 && acknowledge_sync[2]==request_toggle)request_toggle<=!request_toggle;
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_ddr_work_reader.v
// A generation-qualified committed RGB frame is leased before any native AR.
// Reads only the 240 nearest-centre source rows. Native DDR has no RREADY:
// each <=16 beat request owns the entire 512-byte synchronous RAM in advance.
module pg100_ddr_work_reader #(
 parameter WATCHDOG_CYCLES=5000000
)(
 input wire clk,rst_n,init_done,cancel,native_idle,native_fault,
 input wire selected_valid,output wire selected_ready,
 input wire [1:0] selected_slot,input wire [31:0] selected_generation,
 input wire [151:0] selected_key,
 output wire acquire_valid,output wire [1:0] acquire_slot,
 output wire [31:0] acquire_generation,output wire [2:0] acquire_mask,
 input wire acquire_ok,
 output wire release_valid,output wire [1:0] release_slot,
 output wire [31:0] release_generation,output wire [2:0] release_mask,
 output wire alg_valid,input wire alg_ready,output wire [1:0] alg_slot,
 output wire [31:0] alg_generation,output wire [27:0] alg_byte_offset,
 output wire [3:0] alg_len,output wire alg_reserved,
 input wire [255:0] rd_data,input wire alg_data_valid,rd_last,
 output wire m_valid,input wire m_ready,output reg [7:0] m_mono,
 output wire [8:0] m_x,output wire [7:0] m_y,
 output wire m_sof,m_eol,m_eof,output wire [151:0] m_key,
 output wire commit_valid,input wire commit_ready,output wire [151:0] commit_key,
 output wire busy,output reg completed,dropped,abort_frame,
 output reg [31:0] completed_frames,dropped_frames,read_bursts,
 output reg [63:0] read_bytes,active_cycles
);
 localparam IDLE=0,ACQUIRE=1,WAIT_ACQUIRE=2,PREPARE=3,REQUEST=4,
  RETURN_DATA=5,PREFETCH=6,WAIT_RAM=7,PIXEL=8,GRAY_ADD=9,GRAY_OUT=10,
  OUTPUT_PIXEL=11,COMMIT=12,RELEASE=13,DRAIN=14;
 reg [3:0] state;
 reg [1:0] slot_q;
 reg [31:0] generation_q;
 reg [151:0] key_q;
 reg leased,abort_pending;
 reg [1:0] acquire_wait;
 reg [22:0] watchdog;
 reg [27:0] row_base,offset_q;
 reg [8:0] row_beats_left;
 reg [4:0] burst_beats,return_count;
 reg [3:0] read_index;
 reg [2:0] lane;
 reg [11:0] source_x,next_sample_x;
 reg [8:0] work_x;
 reg [7:0] work_y;
 reg [1:0] row_phase;
 reg [15:0] r_product,g_product,b_product;
 reg [16:0] mono_sum;
 reg [255:0] burst_ram[0:15] /* synthesis syn_ramstyle="block_ram" */;
 reg [255:0] beat_q;
 always @(posedge clk) begin
  if(alg_data_valid && state==RETURN_DATA) burst_ram[return_count[3:0]]<=rd_data;
  beat_q<=burst_ram[read_index];
 end
 wire [31:0] word_q=beat_q[lane*32+:32];
 wire [7:0] page_beats=8'd128-{1'b0,offset_q[11:5]};
 wire [4:0] capped_page=page_beats>16 ? 5'd16 : page_beats[4:0];
 wire [4:0] planned_beats=row_beats_left<capped_page ? row_beats_left[4:0] : capped_page;
 assign selected_ready=state==IDLE && init_done && !cancel && !native_fault;
 assign acquire_valid=state==ACQUIRE;
 assign acquire_slot=slot_q;assign acquire_generation=generation_q;assign acquire_mask=3'b010;
 assign release_valid=state==RELEASE && leased;
 assign release_slot=slot_q;assign release_generation=generation_q;assign release_mask=3'b010;
 assign alg_valid=state==REQUEST && !cancel && !native_fault;
 assign alg_slot=slot_q;assign alg_generation=generation_q;
 assign alg_byte_offset=offset_q;assign alg_len=burst_beats[3:0]-1'b1;
 assign alg_reserved=state==REQUEST;
 assign m_valid=state==OUTPUT_PIXEL && !cancel && !native_fault;
 assign m_x=work_x;assign m_y=work_y;assign m_key=key_q;
 assign m_sof=work_x==0 && work_y==0;
 assign m_eol=work_x==319;assign m_eof=work_x==319 && work_y==239;
 assign commit_valid=state==COMMIT && !cancel && !native_fault;
 assign commit_key=key_q;assign busy=state!=IDLE;
 // Advance source serialization after either an unselected pixel or an
 // accepted selected pixel. Held downstream pixels never move RAM/address.
 task advance_pixel;
  begin
   source_x<=source_x+1'b1;
   if(lane==7) begin
    lane<=0;
    if({1'b0,read_index}+1==burst_beats) begin
     if(row_beats_left==0) begin
      if(work_y==239) state<=COMMIT;
      else begin
       work_y<=work_y+1'b1;work_x<=0;source_x<=0;next_sample_x<=3;
       row_phase<=row_phase+1'b1;
       // y(v)=floor((2*v+1)*9/4): initial row2; increments 4,5,4,5.
       row_base<=row_base+(row_phase[0] ? 28'd38400 : 28'd30720);
       offset_q<=row_base+(row_phase[0] ? 28'd38400 : 28'd30720);
       row_beats_left<=240;state<=PREPARE;
      end
     end else state<=PREPARE;
    end else begin read_index<=read_index+1'b1;state<=PREFETCH;end
   end else begin lane<=lane+1'b1;state<=PIXEL;end
  end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;slot_q<=0;generation_q<=0;key_q<=0;leased<=0;abort_pending<=0;
   acquire_wait<=0;watchdog<=0;row_base<=0;offset_q<=0;row_beats_left<=0;
   burst_beats<=0;return_count<=0;read_index<=0;lane<=0;
   source_x<=0;next_sample_x<=3;work_x<=0;work_y<=0;row_phase<=0;
   r_product<=0;g_product<=0;b_product<=0;mono_sum<=0;m_mono<=0;
   completed<=0;dropped<=0;abort_frame<=0;completed_frames<=0;dropped_frames<=0;
   read_bursts<=0;read_bytes<=0;active_cycles<=0;
  end else begin
   completed<=0;dropped<=0;abort_frame<=0;
   if(state!=IDLE) active_cycles<=active_cycles+1'b1;
   if(state==IDLE) watchdog<=0;
   else if(watchdog<WATCHDOG_CYCLES) watchdog<=watchdog+1'b1;
   case(state)
    IDLE:if(selected_valid&&selected_ready) begin
     slot_q<=selected_slot;generation_q<=selected_generation;key_q<=selected_key;
     leased<=0;abort_pending<=0;state<=ACQUIRE;acquire_wait<=0;
     row_base<=15360;offset_q<=15360;row_beats_left<=240;
     source_x<=0;next_sample_x<=3;work_x<=0;work_y<=0;row_phase<=0;
    end
    ACQUIRE:state<=WAIT_ACQUIRE;
    WAIT_ACQUIRE:begin
     acquire_wait<=acquire_wait+1'b1;
     if(acquire_ok) begin leased<=1;state<=abort_pending||cancel||native_fault ? DRAIN:PREPARE;end
     else if(acquire_wait==2) begin abort_pending<=1;abort_frame<=1;state<=DRAIN;end
    end
    PREPARE:begin burst_beats<=planned_beats;return_count<=0;state<=REQUEST;end
    REQUEST:if(alg_valid&&alg_ready) begin
     state<=RETURN_DATA;read_bursts<=read_bursts+1'b1;
     row_beats_left<=row_beats_left-burst_beats;offset_q<=offset_q+({23'b0,burst_beats}<<5);
    end
    RETURN_DATA:if(alg_data_valid) begin
     read_bytes<=read_bytes+32;return_count<=return_count+1'b1;
     if(rd_last!=({1'b0,return_count}+1==burst_beats)) begin
      abort_pending<=1;abort_frame<=1;state<=DRAIN;
     end else if(rd_last) begin read_index<=0;lane<=0;state<=PREFETCH;end
    end
    PREFETCH:state<=WAIT_RAM;
    WAIT_RAM:state<=PIXEL;
    PIXEL:if(source_x==next_sample_x) begin
     r_product<=word_q[23:16]*8'd77;g_product<=word_q[15:8]*8'd150;b_product<=word_q[7:0]*8'd29;
     state<=GRAY_ADD;
    end else advance_pixel();
    GRAY_ADD:begin mono_sum<={1'b0,r_product}+{1'b0,g_product}+{1'b0,b_product}+17'd128;state<=GRAY_OUT;end
    GRAY_OUT:begin m_mono<=mono_sum[15:8];state<=OUTPUT_PIXEL;end
    OUTPUT_PIXEL:if(m_valid&&m_ready) begin work_x<=work_x+1'b1;next_sample_x<=next_sample_x+6;advance_pixel();end
    COMMIT:if(commit_valid&&commit_ready) begin state<=RELEASE;completed<=1;completed_frames<=completed_frames+1'b1;end
    RELEASE:begin
     leased<=0;state<=IDLE;
     if(abort_pending) begin dropped<=1;dropped_frames<=dropped_frames+1'b1;end
    end
    DRAIN:if(native_idle) state<=RELEASE;
    default:begin abort_pending<=1;abort_frame<=1;state<=DRAIN;end
   endcase
   if(state!=IDLE && state!=DRAIN && state!=RELEASE &&
      (cancel||native_fault||watchdog==WATCHDOG_CYCLES)) begin
    abort_pending<=1;abort_frame<=!abort_pending;
    // Acquisition is a registered response: finish it before releasing so a
    // same-edge cancellation cannot leak a newly acquired slot.
    if(state!=ACQUIRE && state!=WAIT_ACQUIRE) state<=DRAIN;
   end
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_ddr_recovery_supervisor.v
// Always-on 27 MHz recovery owner. No dependence on a running native clock
// to assert/release the physical DDR reset. G25 is owned elsewhere and is
// deliberately unaffected by a local DDR fault or operator re-train command.
module pg100_ddr_recovery_supervisor #(
 parameter WINDOW_CYCLES=27000,HOLD_WINDOWS=10,STARTUP_WINDOWS=2000,
 parameter NATIVE_TOGGLE_DIV=256,MIN_EDGES=460,MAX_EDGES=516
)(
 input wire clk27,por_n,native_clk,pll_lock,ddr_init_done,
 input wire native_reinit_request,soft_reset_toggle,
 output reg ddr_reset_n,native_clock_good,
 output reg[31:0]recovery_count,output reg[2:0]last_reason,
 output reg[15:0]measured_native_edges
);
 reg[15:0]native_div;
 reg native_toggle;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]heartbeat_release;
 always @(posedge native_clk or negedge ddr_reset_n)
  if(!ddr_reset_n)heartbeat_release<=0;else heartbeat_release<={heartbeat_release[1:0],1'b1};
 always @(posedge native_clk or negedge heartbeat_release[2])
  if(!heartbeat_release[2])begin native_div<=0;native_toggle<=0;end
  else if(native_div==NATIVE_TOGGLE_DIV-1)begin native_div<=0;native_toggle<=!native_toggle;end
  else native_div<=native_div+1'b1;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]heartbeat_sync,pll_sync,init_sync,request_sync;
 reg heartbeat_d,operator_d;
 reg[15:0]window_edges;
 reg[14:0]window_ticks;
 reg[11:0]wait_windows;
 reg[1:0]good_windows,lost_windows;
 reg[1:0]state;
 localparam HOLD=0,STARTUP=1,RUN=2;
 wire window_end=window_ticks==WINDOW_CYCLES-1;
 wire edge_seen=heartbeat_sync[2]!=heartbeat_d;
 // 125MHz / 256 * 1ms = 488.28125 toggles. 460..516 tolerates window
 // quantization and oscillator error while rejecting 100/62.5MHz clocks.
 wire healthy_window=window_edges>=MIN_EDGES&&window_edges<=MAX_EDGES&&pll_sync[2];
 function[31:0]inc32;input[31:0]v;begin inc32=&v?v:v+1'b1;end endfunction
 always @(posedge clk27 or negedge por_n)begin
  if(!por_n)begin
   heartbeat_sync<=0;pll_sync<=0;init_sync<=0;request_sync<=0;heartbeat_d<=0;operator_d<=0;
   ddr_reset_n<=0;native_clock_good<=0;recovery_count<=0;last_reason<=0;
   window_edges<=0;window_ticks<=0;wait_windows<=0;good_windows<=0;lost_windows<=0;
   state<=HOLD;measured_native_edges<=0;
  end else begin
   heartbeat_sync<={heartbeat_sync[1:0],native_toggle};heartbeat_d<=heartbeat_sync[2];
   pll_sync<={pll_sync[1:0],pll_lock};init_sync<={init_sync[1:0],ddr_init_done};
   request_sync<={request_sync[1:0],native_reinit_request};operator_d<=soft_reset_toggle;
   if(edge_seen&&window_edges!=16'hffff)window_edges<=window_edges+1'b1;
   if(window_end)begin window_ticks<=0;window_edges<=0;measured_native_edges<=window_edges;end
   else window_ticks<=window_ticks+1'b1;
   case(state)
    HOLD:if(window_end)begin
     if(wait_windows==HOLD_WINDOWS-1)begin ddr_reset_n<=1;state<=STARTUP;wait_windows<=0;good_windows<=0;lost_windows<=0;end
     else wait_windows<=wait_windows+1'b1;
    end
    STARTUP:if(window_end)begin
     if(healthy_window)begin
      if(good_windows<3)good_windows<=good_windows+1'b1;
      if(good_windows>=2)native_clock_good<=1;
     end else begin good_windows<=0;native_clock_good<=0;end
     if(healthy_window&&init_sync[2]&&good_windows>=2)begin state<=RUN;wait_windows<=0;lost_windows<=0;end
     else if(wait_windows==STARTUP_WINDOWS-1)begin
      state<=HOLD;ddr_reset_n<=0;native_clock_good<=0;wait_windows<=0;
      recovery_count<=inc32(recovery_count);last_reason<=4;
     end else wait_windows<=wait_windows+1'b1;
    end
    RUN:if(window_end)begin
     if(healthy_window&&init_sync[2])lost_windows<=0;
     else if(lost_windows==1)begin
      state<=HOLD;ddr_reset_n<=0;native_clock_good<=0;wait_windows<=0;
      recovery_count<=inc32(recovery_count);last_reason<=1;lost_windows<=0;
     end else lost_windows<=lost_windows+1'b1;
    end
    default:begin state<=HOLD;ddr_reset_n<=0;native_clock_good<=0;wait_windows<=0;end
   endcase
   if(state!=HOLD&&(request_sync[2]||soft_reset_toggle!=operator_d))begin
    state<=HOLD;ddr_reset_n<=0;native_clock_good<=0;wait_windows<=0;good_windows<=0;lost_windows<=0;
    recovery_count<=inc32(recovery_count);last_reason<=soft_reset_toggle!=operator_d?3:2;
   end
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_local_control.v
// Operator control, UART B24/C24. PGC2 v1 fixed 32-byte, big-endian frame:
// magic(4),version,opcode,flags,origin,session64,mode16,calib32,epoch32,
// reserved16=0,CRC32(28 bytes). SET=1, SOFT_RESET=2, READ_STATUS=3, DIAGNOSTICS=4.
// DIAGNOSTICS: unchanged ACK16, then atomic PGS2 176-byte CRC-protected record.
// UART trust is local operator provisioning, not remote SESSION authorization.
module pg100_local_control #(
 parameter UART_DIVISOR=234,parameter FRAME_GAP_CYCLES=2700000,
 parameter DIAGNOSTIC_TIMEOUT_CYCLES=270000
)(
 input wire clk27,por_n,uart_rxd,clk_native,native_rst_n,
 input wire [1279:0] native_status_words,
 output wire uart_txd,
 output reg cfg_run_enable,cfg_rgb888_confirmed,cfg_export_enable,
 output reg[7:0]cfg_origin,output reg[63:0]cfg_session,
 output reg[15:0]cfg_mode,output reg[31:0]cfg_calib,cfg_epoch,
 output reg cfg_update,native_soft_reset,output reg soft_reset_toggle,
 output reg[31:0]bad_commands,accepted_commands
);
 function[31:0]crc_byte;
  input[31:0]c;input[7:0]b;reg[31:0]v;integer k;
  begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 function[31:0]inc32;input[31:0]v;begin inc32=&v?v:v+1'b1;end endfunction
 wire[7:0]rx_data;wire rx_valid,rx_error;
 pg100_uart_rx_8n1 #(.DIVISOR(UART_DIVISOR)) rx(.clk(clk27),.rst_n(por_n),.rxd(uart_rxd),.data(rx_data),.valid(rx_valid),.framing_error(rx_error));
 reg[7:0]frame[0:31];reg[5:0]position;reg[31:0]crc,gap_ticks;
 reg checking;
 reg run27,rgb27,export27;reg[7:0]origin27;reg[63:0]session27;
 reg[15:0]mode27;reg[31:0]calib27,epoch27;
 reg request_toggle,ack_native;
 reg[2:0]ack_sync,req_sync,soft_sync;reg soft_seen;
 reg[2:0]boot_wait;
 // The source bus is held until ack returns. req/ack are three-flop crossings.
 // Native reset forces a fresh stable-bus load even if req's level is unchanged.
 always @(posedge clk_native or negedge native_rst_n)begin
  if(!native_rst_n)begin
   req_sync<=0;soft_sync<=0;soft_seen<=0;ack_native<=0;boot_wait<=0;
   cfg_run_enable<=0;cfg_rgb888_confirmed<=0;cfg_export_enable<=0;
   cfg_origin<=0;cfg_session<=0;cfg_mode<=0;cfg_calib<=0;cfg_epoch<=0;
   cfg_update<=0;native_soft_reset<=0;
  end else begin
   req_sync<={req_sync[1:0],request_toggle};soft_sync<={soft_sync[1:0],soft_reset_toggle};
   cfg_update<=0;native_soft_reset<=0;
   if(boot_wait<7)begin
    boot_wait<=boot_wait+1'b1;
    if(boot_wait==6)begin
     cfg_run_enable<=run27;cfg_rgb888_confirmed<=rgb27;cfg_export_enable<=export27;
     cfg_origin<=origin27;cfg_session<=session27;cfg_mode<=mode27;cfg_calib<=calib27;cfg_epoch<=epoch27;
     ack_native<=req_sync[2];soft_seen<=soft_sync[2];
     // Boot load must not look like an operator config change: the core is
     // already reset and a cfg_update here re-triggers DDR recovery forever.
    end
   end else begin
    if(req_sync[2]!=ack_native)begin
     cfg_run_enable<=run27;cfg_rgb888_confirmed<=rgb27;cfg_export_enable<=export27;
     cfg_origin<=origin27;cfg_session<=session27;cfg_mode<=mode27;cfg_calib<=calib27;cfg_epoch<=epoch27;
     ack_native<=req_sync[2];cfg_update<=1;
    end
    if(soft_sync[2]!=soft_seen)begin soft_seen<=soft_sync[2];native_soft_reset<=1;end
   end
  end
 end
 reg reply_pending,reply_active;reg[7:0]reply_status,reply_flags;
 reg[2:0]reply_state;
 reg[31:0]reply_serial,reply_crc;
 reg[4:0]reply_index;
 reg[7:0]reply_mem[0:15];
 reg diag_launch,reply_diag_pending,reply_diag_active;
 localparam D_IDLE=0,D_WAIT=1,D_COPY=2,D_ZERO=3,D_CRC=4,D_TRAILER=5,D_READY=6;
 reg [2:0]diag_state;
 reg [7:0]diag_mem[0:175];reg[7:0]diag_tx_index,diag_crc_index;
 reg[5:0]diag_copy_word;reg[31:0]diag_ticks,diag_crc,diag_generation,diag_previous_generation;
 reg snapshot_request;reg[5:0]snapshot_word;
 wire snapshot_busy,snapshot_valid,snapshot_rejected;wire[31:0]snapshot_generation,snapshot_data;
 // This is a reset-release synchronizer, not application state. The native
 // reset asserts availability loss immediately; only clk27 releases it.
 // Keep all three stages so PDS exceptions can target these reset receivers
 // without excluding recovery/removal of the downstream diagnostic state.
 wire native_presence_raw_n=por_n&&native_rst_n;
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]native_available27;
 always @(posedge clk27 or negedge native_presence_raw_n)
  if(!native_presence_raw_n)native_available27<=0;else native_available27<={native_available27[1:0],1'b1};
 pg100_mainline_atomic_snapshot snapshot(.native_clk(clk_native),.native_rst_n(native_rst_n),
  .native_status(native_status_words),.bus_clk(clk27),.bus_rst_n(por_n),.request(snapshot_request),
  .read_word(snapshot_word),.busy(snapshot_busy),.snapshot_valid(snapshot_valid),
  .request_rejected(snapshot_rejected),.generation(snapshot_generation),.read_data(snapshot_data));
 wire diagnostic_busy=diag_state!=D_IDLE||diag_launch;
 wire diagnostic_ready=diag_state==D_READY;
 wire tx_ready;wire tx_valid=reply_active||(reply_state==5&&diagnostic_ready);
 pg100_uart_tx_8n1 #(.DIVISOR(UART_DIVISOR)) tx(.clk(clk27),.rst_n(por_n),
  .data(reply_state==5 ? diag_mem[diag_tx_index] : reply_mem[reply_index]),.valid(tx_valid),.ready(tx_ready),.txd(uart_txd));
 reg[3:0]reply_build_index;
 wire crc_ok={frame[28],frame[29],frame[30],frame[31]}==~crc;
 wire schema_ok=frame[4]==1&&frame[5]>=1&&frame[5]<=4&&frame[6][7:3]==0&&
  frame[26]==0&&frame[27]==0;
 wire context_ok=!frame[6][2]||(frame[7]==50&&{frame[8],frame[9],frame[10],frame[11],frame[12],frame[13],frame[14],frame[15]}!=0&&
  {frame[16],frame[17]}==1&&{frame[22],frame[23],frame[24],frame[25]}!=0);
 // Copy the ENTIRE snapshot into a separate transmission buffer. A native
 // reset during capture/copy yields unavailable/all-zero; a reset after copy
 // cannot tear an already prepared/streaming record. Timeout never means zero.
 always @(posedge clk27 or negedge por_n)begin
  if(!por_n)begin
   diag_state<=D_IDLE;snapshot_request<=0;snapshot_word<=0;diag_copy_word<=0;
   diag_ticks<=0;diag_crc<=0;diag_crc_index<=0;diag_generation<=0;diag_previous_generation<=0;
  end else begin
   snapshot_request<=0;
   case(diag_state)
    D_IDLE:if(diag_launch)begin
     diag_mem[0]<=8'h50;diag_mem[1]<=8'h47;diag_mem[2]<=8'h53;diag_mem[3]<=8'h32;
     diag_mem[4]<=1;diag_mem[5]<=40;diag_mem[6]<=0;diag_mem[7]<=0;
     diag_mem[8]<=0;diag_mem[9]<=0;diag_mem[10]<=0;diag_mem[11]<=0;
     diag_ticks<=0;diag_copy_word<=0;snapshot_word<=0;
     if(native_available27[2]&&!snapshot_busy)begin
      diag_previous_generation<=snapshot_generation;snapshot_request<=1;diag_state<=D_WAIT;
     end else diag_state<=D_ZERO;
    end
    D_WAIT:begin
     if(!native_available27[2]||diag_ticks>=DIAGNOSTIC_TIMEOUT_CYCLES-1)begin
      diag_copy_word<=0;diag_state<=D_ZERO;
     end else if(snapshot_valid&&!snapshot_busy&&snapshot_generation!=diag_previous_generation)begin
      diag_generation<=snapshot_generation;diag_mem[6]<=1;
      diag_mem[8]<=snapshot_generation[31:24];diag_mem[9]<=snapshot_generation[23:16];
      diag_mem[10]<=snapshot_generation[15:8];diag_mem[11]<=snapshot_generation[7:0];
      diag_copy_word<=0;snapshot_word<=0;diag_state<=D_COPY;
     end else diag_ticks<=diag_ticks+1'b1;
    end
    D_COPY:begin
     if(!native_available27[2]||!snapshot_valid||snapshot_generation!=diag_generation)begin
      diag_mem[6]<=0;diag_mem[8]<=0;diag_mem[9]<=0;diag_mem[10]<=0;diag_mem[11]<=0;
      diag_copy_word<=0;diag_state<=D_ZERO;
     end else begin
      diag_mem[12+diag_copy_word*4]<=snapshot_data[31:24];diag_mem[13+diag_copy_word*4]<=snapshot_data[23:16];
      diag_mem[14+diag_copy_word*4]<=snapshot_data[15:8];diag_mem[15+diag_copy_word*4]<=snapshot_data[7:0];
      if(diag_copy_word==39)begin diag_crc<=32'hffffffff;diag_crc_index<=0;diag_state<=D_CRC;end
      else begin diag_copy_word<=diag_copy_word+1'b1;snapshot_word<=snapshot_word+1'b1;end
     end
    end
    D_ZERO:begin
     diag_mem[12+diag_copy_word*4]<=0;diag_mem[13+diag_copy_word*4]<=0;
     diag_mem[14+diag_copy_word*4]<=0;diag_mem[15+diag_copy_word*4]<=0;
     if(diag_copy_word==39)begin diag_crc<=32'hffffffff;diag_crc_index<=0;diag_state<=D_CRC;end
     else diag_copy_word<=diag_copy_word+1'b1;
    end
    D_CRC:begin
     diag_crc<=crc_byte(diag_crc,diag_mem[diag_crc_index]);
     if(diag_crc_index==171)diag_state<=D_TRAILER;else diag_crc_index<=diag_crc_index+1'b1;
    end
    D_TRAILER:begin
     diag_mem[172]<=~diag_crc[31:24];diag_mem[173]<=~diag_crc[23:16];
     diag_mem[174]<=~diag_crc[15:8];diag_mem[175]<=~diag_crc[7:0];diag_state<=D_READY;
    end
    D_READY:if(reply_state==5&&tx_ready&&diag_tx_index==175)diag_state<=D_IDLE;
   endcase
  end
 end
 always @(posedge clk27 or negedge por_n)begin
  if(!por_n)begin
   position<=0;crc<=32'hffffffff;gap_ticks<=0;checking<=0;
   run27<=0;rgb27<=0;export27<=0;origin27<=0;session27<=0;mode27<=0;calib27<=0;epoch27<=0;
   request_toggle<=0;ack_sync<=0;soft_reset_toggle<=0;bad_commands<=0;accepted_commands<=0;
   reply_pending<=0;reply_active<=0;reply_status<=0;reply_flags<=0;reply_serial<=0;
   reply_state<=0;reply_index<=0;reply_build_index<=0;reply_crc<=0;
   diag_launch<=0;reply_diag_pending<=0;reply_diag_active<=0;diag_tx_index<=0;
  end else begin
   diag_launch<=0;
   ack_sync<={ack_sync[1:0],ack_native};
   if(position!=0)begin
    if(gap_ticks>=FRAME_GAP_CYCLES-1)begin position<=0;crc<=32'hffffffff;gap_ticks<=0;bad_commands<=inc32(bad_commands);end
    else gap_ticks<=gap_ticks+1'b1;
   end
   if(rx_error)begin position<=0;crc<=32'hffffffff;gap_ticks<=0;bad_commands<=inc32(bad_commands);end
   if(rx_valid&&!checking)begin
    gap_ticks<=0;
    case(position)
     0:if(rx_data==8'h50)begin frame[0]<=rx_data;crc<=crc_byte(32'hffffffff,rx_data);position<=1;end
     1:if(rx_data==8'h47)begin frame[1]<=rx_data;crc<=crc_byte(crc,rx_data);position<=2;end
       else begin position<=rx_data==8'h50 ? 1:0;crc<=rx_data==8'h50 ? crc_byte(32'hffffffff,rx_data):32'hffffffff;end
     2:if(rx_data==8'h43)begin frame[2]<=rx_data;crc<=crc_byte(crc,rx_data);position<=3;end
       else begin position<=0;crc<=32'hffffffff;end
     3:if(rx_data==8'h32)begin frame[3]<=rx_data;crc<=crc_byte(crc,rx_data);position<=4;end
       else begin position<=0;crc<=32'hffffffff;end
     default:begin
      frame[position]<=rx_data;if(position<28)crc<=crc_byte(crc,rx_data);
      if(position==31)begin checking<=1;position<=0;end else position<=position+1'b1;
     end
    endcase
   end
   if(checking)begin
    checking<=0;crc<=32'hffffffff;
    if(diagnostic_busy||reply_state!=0||reply_pending)begin
     bad_commands<=inc32(bad_commands);
     // One bounded BUSY acknowledgement may wait after the current record.
     // Further overlapping commands increment the counter without overwriting it.
     if(!reply_pending)begin reply_pending<=1;reply_status<=3;reply_diag_pending<=0;
      reply_flags<={5'b0,export27,rgb27,run27};reply_serial<=accepted_commands;end
    end else begin
    reply_pending<=1;reply_diag_pending<=0;
    reply_flags<={5'b0,export27,rgb27,run27};reply_serial<=accepted_commands;
    if(!crc_ok)begin bad_commands<=inc32(bad_commands);reply_status<=1;end
    else if(!schema_ok||frame[5]!=1&&({frame[6],frame[7],frame[8],frame[9],frame[10],frame[11],frame[12],frame[13],frame[14],frame[15],frame[16],frame[17],frame[18],frame[19],frame[20],frame[21],frame[22],frame[23],frame[24],frame[25]}!=0))begin
     bad_commands<=inc32(bad_commands);reply_status<=2;
    end else if(frame[5]==1&&request_toggle!=ack_sync[2])begin bad_commands<=inc32(bad_commands);reply_status<=3;end
    else if(frame[5]==1&&!context_ok)begin bad_commands<=inc32(bad_commands);reply_status<=4;end
    else begin
     accepted_commands<=inc32(accepted_commands);reply_serial<=inc32(accepted_commands);reply_status<=0;
     if(frame[5]==1)begin
      run27<=frame[6][0];rgb27<=frame[6][1];export27<=frame[6][2];origin27<=frame[7];
      session27<={frame[8],frame[9],frame[10],frame[11],frame[12],frame[13],frame[14],frame[15]};
      mode27<={frame[16],frame[17]};calib27<={frame[18],frame[19],frame[20],frame[21]};epoch27<={frame[22],frame[23],frame[24],frame[25]};
      request_toggle<=!request_toggle;reply_flags<=frame[6];
     end else if(frame[5]==2)soft_reset_toggle<=!soft_reset_toggle;
     else if(frame[5]==4)begin diag_launch<=1;reply_diag_pending<=1;end
    end
    end
   end
   case(reply_state)
    0:if(reply_pending)begin
     reply_diag_active<=reply_diag_pending;
     reply_pending<=0;reply_mem[0]<=8'h50;reply_mem[1]<=8'h47;reply_mem[2]<=8'h41;reply_mem[3]<=8'h32;
     reply_mem[4]<=1;reply_mem[5]<=reply_status;reply_mem[6]<=reply_flags;reply_mem[7]<=0;
     reply_mem[8]<=reply_serial[31:24];reply_mem[9]<=reply_serial[23:16];reply_mem[10]<=reply_serial[15:8];reply_mem[11]<=reply_serial[7:0];
     reply_crc<=32'hffffffff;reply_build_index<=0;reply_state<=1;
    end
    1:begin
     reply_crc<=crc_byte(reply_crc,reply_mem[reply_build_index]);
     if(reply_build_index==11)reply_state<=2;else reply_build_index<=reply_build_index+1'b1;
    end
    2:begin
     reply_mem[12]<=~reply_crc[31:24];reply_mem[13]<=~reply_crc[23:16];reply_mem[14]<=~reply_crc[15:8];reply_mem[15]<=~reply_crc[7:0];
     reply_index<=0;reply_active<=1;reply_state<=3;
    end
    3:if(tx_ready)begin
     if(reply_index==15)begin reply_active<=0;reply_state<=reply_diag_active ? 4 : 0;end else reply_index<=reply_index+1'b1;
    end
    4:if(diagnostic_ready&&tx_ready)begin diag_tx_index<=0;reply_state<=5;end
    5:if(tx_ready)begin
     if(diag_tx_index==175)begin reply_state<=0;diag_tx_index<=0;end else diag_tx_index<=diag_tx_index+1'b1;
    end
   endcase
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_uart_8n1.v
// 27 MHz / 115200 baud, rounded divisor 234 (0.16% baud error).
module pg100_uart_rx_8n1 #(parameter DIVISOR=234)(
 input wire clk,rst_n,rxd,output reg[7:0]data,output reg valid,framing_error
);
 reg[2:0]sync_rx;reg[15:0]ticks;reg[3:0]bit_index;reg[7:0]shift;reg[1:0]state;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sync_rx<=7;ticks<=0;bit_index<=0;shift<=0;state<=0;data<=0;valid<=0;framing_error<=0;end
  else begin
   sync_rx<={sync_rx[1:0],rxd};valid<=0;framing_error<=0;
   case(state)
    0:if(!sync_rx[2])begin ticks<=DIVISOR/2-1;state<=1;end
    1:if(ticks!=0)ticks<=ticks-1'b1;else if(sync_rx[2])state<=0;
      else begin ticks<=DIVISOR-1;bit_index<=0;state<=2;end
    2:if(ticks!=0)ticks<=ticks-1'b1;else begin
       shift[bit_index]<=sync_rx[2];ticks<=DIVISOR-1;
       if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;
      end
    3:if(ticks!=0)ticks<=ticks-1'b1;else begin
       state<=0;if(sync_rx[2])begin data<=shift;valid<=1;end else framing_error<=1;
      end
   endcase
  end
 end
endmodule
module pg100_uart_tx_8n1 #(parameter DIVISOR=234)(
 input wire clk,rst_n,input wire[7:0]data,input wire valid,output wire ready,output reg txd
);
 reg[15:0]ticks;reg[3:0]bit_index;reg[9:0]shift;reg busy;
 assign ready=!busy;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ticks<=0;bit_index<=0;shift<=10'h3ff;busy<=0;txd<=1;end
  else if(!busy)begin
   if(valid)begin shift<={1'b1,data,1'b0};bit_index<=0;ticks<=DIVISOR-1;busy<=1;txd<=0;end
  end else if(ticks!=0)ticks<=ticks-1'b1;
  else if(bit_index==9)begin busy<=0;txd<=1;end
  else begin shift<={1'b1,shift[9:1]};txd<=shift[1];bit_index<=bit_index+1'b1;ticks<=DIVISOR-1;end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_single_board_controller.v
// Local PG100 frame scheduling. A CRC-valid marker proves identity integrity,
// not remote authority. UART provisioned source context gates network export.
// The pending descriptor owns no lease: the DDR reader verifies generation and
// acquires ALG=010 itself. A replacement cannot revoke the active frame.
module pg100_single_board_controller #(
 parameter FRAME_TTL_US=100000, parameter DRAIN_LIMIT_CYCLES=12500000
)(
 input wire clk,rst_n,init_done,run_enable,rgb888_confirmed,video_clock_good,
 input wire soft_reset,config_update,core_fault,core_quiescent,
 input wire[63:0]now_us,
 input wire cfg_export_enable,input wire[7:0]cfg_origin,
 input wire[63:0]cfg_session,input wire[15:0]cfg_mode,
 input wire[31:0]cfg_calib,cfg_epoch,
 input wire publish_valid,input wire[1:0]publish_slot,
 input wire[31:0]publish_generation,input wire[151:0]publish_key,
 input wire result_busy,selected_complete,selected_dropped,input wire[7:0]result_count,
 output wire selected_valid,input wire selected_ready,
 output wire[1:0]selected_slot,output wire[31:0]selected_generation,
 output wire[151:0]selected_key,output wire[31:0]selected_epoch,
 output wire[63:0]selected_timestamp_us,selected_deadline_us,
 output wire permit_valid,output wire[151:0]permit_key,output wire[31:0]permit_epoch,
 output wire warm_reset,invalidate,output reg ddr_reinit_request,
 output wire export_current,output reg[31:0]sequence_base,
 input wire telemetry_sequence_request,output wire telemetry_sequence_ready,
 output wire[31:0]telemetry_sequence_base,
 output reg[31:0]accepted_frames,completed_frames,dropped_frames,
 output reg[31:0]superseded_frames,rejected_identity_frames,recovery_events,
 output reg[63:0]completed_points,output wire recovering
);
 localparam RUN=0,DRAIN=1,WAIT_MEMORY=2,HALT=3;
 reg[1:0]state;
 reg q_valid,active_valid,active_export,seen_frame;
 reg[1:0]q_slot;
 reg[31:0]q_generation,q_epoch,active_epoch,last_frame,local_epoch,drain_count;
 reg[151:0]q_key,active_key,last_source;
 reg[63:0]q_timestamp,q_deadline,active_deadline;
 reg enable_d;
 reg[31:0]next_sequence;
 wire enabled=run_enable&&rgb888_confirmed&&video_clock_good&&init_done;
 wire trust_context=cfg_export_enable&&cfg_origin==8'd50&&cfg_session!=0&&
  cfg_mode==1&&cfg_epoch!=0;
 wire identity_valid=(publish_key[151:144]==50||publish_key[151:144]==100||
  publish_key[151:144]==68||publish_key[151:144]==40)&&publish_key[143:80]!=0&&publish_key[47:32]==1;
 wire identity_matches=publish_key[151:144]==cfg_origin&&publish_key[143:80]==cfg_session&&
  publish_key[47:32]==cfg_mode&&publish_key[31:0]==cfg_calib;
 wire[31:0]frame_delta=publish_key[79:48]-last_frame;
 wire frame_new=!seen_frame||(frame_delta!=0&&!frame_delta[31]);
 wire source_changed=publish_valid&&seen_frame&&!cfg_export_enable&&
  ({publish_key[151:80],publish_key[47:0]}!={last_source[151:80],last_source[47:0]});
 wire recovery_trigger=soft_reset||config_update||core_fault||(enable_d&&!enabled)||source_changed;
 wire q_expired=q_valid&&now_us>=q_deadline;
 wire active_expired=active_valid&&now_us>=active_deadline;
 assign recovering=state!=RUN;
 assign warm_reset=state==DRAIN||state==WAIT_MEMORY||state==HALT;
 assign invalidate=recovering||recovery_trigger||!enabled||active_expired;
 assign selected_valid=q_valid&&state==RUN&&enabled&&!recovery_trigger&&!q_expired&&
  !active_valid&&!result_busy;
 assign selected_slot=q_slot;assign selected_generation=q_generation;
 assign selected_key=q_key;assign selected_epoch=q_epoch;
 assign selected_timestamp_us=q_timestamp;assign selected_deadline_us=q_deadline;
 assign permit_key=active_valid?active_key:q_key;
 assign permit_epoch=active_valid?active_epoch:q_epoch;
 assign permit_valid=!invalidate&&(active_valid||q_valid&&!q_expired);
 // Keep routing fixed until the active packet is complete or cancelled. Abort
 // is also forwarded to the network queue independently of this route bit.
 assign export_current=active_valid?active_export:trust_context;
 assign telemetry_sequence_ready=state==RUN&&!recovery_trigger&&!(selected_valid&&selected_ready);
 assign telemetry_sequence_base=next_sequence;
 function[31:0]inc32;input[31:0]v;begin inc32=&v?v:v+1'b1;end endfunction
 // The drain budget is relevant only in DRAIN. Clearing it every other
 // cycle avoids a wide publication-identity comparator on the counter CE,
 // while source changes still cancel permits immediately in recovery_trigger.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)drain_count<=0;
  else if(state==DRAIN&&!core_fault&&!core_quiescent&&drain_count<DRAIN_LIMIT_CYCLES-1)
   drain_count<=drain_count+1'b1;
  else drain_count<=0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_MEMORY;q_valid<=0;active_valid<=0;active_export<=0;seen_frame<=0;
   q_slot<=0;q_generation<=0;q_epoch<=0;q_key<=0;q_timestamp<=0;q_deadline<=0;
   active_key<=0;active_epoch<=0;active_deadline<=0;last_frame<=0;last_source<=0;local_epoch<=1;
   enable_d<=0;ddr_reinit_request<=0;sequence_base<=0;next_sequence<=0;
   accepted_frames<=0;completed_frames<=0;dropped_frames<=0;superseded_frames<=0;
   rejected_identity_frames<=0;recovery_events<=0;completed_points<=0;
  end else begin
   enable_d<=enabled;
   if(selected_complete&&active_valid)begin
    active_valid<=0;completed_frames<=inc32(completed_frames);
    if(completed_points>64'hffffffffffffffff-result_count)completed_points<=64'hffffffffffffffff;
    else completed_points<=completed_points+result_count;
   end
   if(selected_dropped&&active_valid)begin active_valid<=0;dropped_frames<=inc32(dropped_frames);end
   case(state)
    WAIT_MEMORY:begin
     q_valid<=0;
     if(core_fault)ddr_reinit_request<=1;
     else ddr_reinit_request<=0;
     if(init_done&&core_quiescent&&!core_fault)begin state<=RUN;ddr_reinit_request<=0;end
    end
    DRAIN:begin
     q_valid<=0;
     if(core_fault||drain_count>=DRAIN_LIMIT_CYCLES-1)begin
      ddr_reinit_request<=1;state<=WAIT_MEMORY;
     end else if(core_quiescent)begin active_valid<=0;state<=WAIT_MEMORY;end
    end
    HALT:begin q_valid<=0;end
    RUN:begin
     if(telemetry_sequence_request&&telemetry_sequence_ready)next_sequence<=next_sequence+2;
     if(q_expired)begin q_valid<=0;dropped_frames<=inc32(dropped_frames);end
     if(selected_valid&&selected_ready)begin
      q_valid<=0;active_valid<=1;active_export<=trust_context;
      active_key<=q_key;active_epoch<=q_epoch;active_deadline<=q_deadline;
      // V2 fanout allocates exactly two datagrams, even for LOW_TEXTURE.
      sequence_base<=next_sequence;next_sequence<=next_sequence+2;
     end
     if(publish_valid&&enabled&&!recovery_trigger)begin
      if(!identity_valid||cfg_export_enable&&(!trust_context||!identity_matches)||!frame_new||
         now_us>64'hffffffffffffffff-FRAME_TTL_US)rejected_identity_frames<=inc32(rejected_identity_frames);
      else begin
       q_valid<=1;q_slot<=publish_slot;q_generation<=publish_generation;q_key<=publish_key;
       q_epoch<=trust_context?cfg_epoch:local_epoch;q_timestamp<=now_us;q_deadline<=now_us+FRAME_TTL_US;
       accepted_frames<=inc32(accepted_frames);seen_frame<=1;last_frame<=publish_key[79:48];last_source<=publish_key;
       if(q_valid&&!(selected_valid&&selected_ready))superseded_frames<=inc32(superseded_frames);
      end
     end
     if(recovery_trigger)begin
      q_valid<=0;state<=DRAIN;seen_frame<=0;
      recovery_events<=inc32(recovery_events);
      if(local_epoch==32'hffffffff)state<=HALT;else local_epoch<=local_epoch+1'b1;
     end
    end
   endcase
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_mainline_telemetry.v
// Real native-domain events -> atomic, bounded PGT2 telemetry. Never subtract
// independent board clocks. Sensors and unimplemented stages remain unavailable.
// HEALTH keys refer to the last genuinely observed selected source frame.
module pg100_mainline_telemetry #(
 parameter WINDOW_CYCLES=125000000,parameter WINDOW_US=1000000,
 parameter CLOCK_HZ=125000000,parameter PACKET_TTL_US=100000,
 parameter[31:0]FIRMWARE_VERSION=32'h00020000,BUILD_ID=32'h20261013
)(
 input wire clk,rst_n,enabled,invalidate,input wire[63:0]now_us,
 input wire[31:0]cfg_epoch,input wire frame_begin,frame_complete,frame_dropped,
 input wire[151:0]frame_key,input wire[31:0]frame_epoch,
 input wire link_up,video_ready,memory_ready,core_fault,
 input wire[31:0]frame_count,drop_count,rx_packets,tx_packets,crc_errors,source_timeouts,recovery_events,
 output wire sequence_request,input wire sequence_ready,input wire[31:0]sequence_base,
 output wire m_hdr_valid,input wire m_hdr_ready,output wire[10:0]m_length,output wire[1:0]m_peer,
 output wire[7:0]m_data,output wire m_valid,input wire m_ready,output wire m_last,m_abort,
 output reg[31:0]completed_packets,cancelled_packets,coalesced_timings,
 output reg[31:0]last_duration_us,timing_samples,output reg timing_measured,
 output reg[31:0]fps_q16,output reg fps_valid
);
 function[31:0]inc32;input[31:0]v;begin inc32=&v?v:v+1'b1;end endfunction
 reg[31:0]window_ticks,window_frames,heartbeat;
 reg health_pending,health_ext_pending,timing_pending,has_frame,timing_active;
 reg[151:0]last_key,active_key,measured_key,timing_key;
 reg[31:0]active_epoch,measured_epoch,timing_epoch,timing_duration,timing_sample;
 reg[63:0]active_start,measured_start,timing_start;
 reg[2:0]state;
 localparam IDLE=0,ALLOCATE=1,REQUEST=2,PAYLOAD=3,WAIT_DONE=4;
 reg[7:0]kind_q,status_q;reg[15:0]reason_q;
 reg[511:0]body_q;reg[10:0]body_length;reg[6:0]body_index;
 reg[151:0]packet_key;reg[31:0]packet_epoch,packet_sequence;reg[63:0]packet_timestamp,packet_deadline;
 reg[1:0]peer_q;
 wire request_ready,body_ready,send_done,send_abort,req_rejected;
 wire packet_live=enabled&&!invalidate&&cfg_epoch==packet_epoch;
 wire healthy=link_up&&video_ready&&memory_ready&&!core_fault;
 wire[7:0]board_status=healthy?8'd0:!link_up?8'd6:core_fault?8'd8:8'd7;
 wire[15:0]board_reason=healthy?16'd0:!link_up?16'd9:core_fault?16'd11:16'd10;
 assign sequence_request=state==ALLOCATE&&packet_live;
 pg_pgt2_datagram_tx #(.PRODUCER_ID(100)) serializer(.clk(clk),.rst(!rst_n),
  .req_valid(state==REQUEST&&packet_live),.req_ready(request_ready),.req_message_type(kind_q),.req_status(status_q),.req_reason(reason_q),
  .req_payload_length(body_length),.req_key(packet_key),.req_sequence(packet_sequence+(peer_q==2)),.req_epoch(packet_epoch),
  .req_timestamp_us(packet_timestamp),.req_deadline_us(packet_deadline),.req_fragment_index(16'd0),.req_fragment_count(16'd1),.req_peer(peer_q),
  .permit_valid(packet_live),.permit_key(packet_key),.permit_epoch(packet_epoch),.now_us(now_us),.invalidate(invalidate||!enabled),
  .payload_data(body_q[511-body_index*8-:8]),.payload_valid(state==PAYLOAD),.payload_ready(body_ready),.payload_last(body_index+1==body_length),
  .m_hdr_valid(m_hdr_valid),.m_hdr_ready(m_hdr_ready),.m_length(m_length),.m_peer(m_peer),
  .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),.m_abort(m_abort),
  .busy(),.send_done(send_done),.send_abort(send_abort),.req_rejected(req_rejected),.rejected_packets());
 wire[31:0]validity=(fps_valid?32'd1:32'd0)|32'd56; // counters+firmware+real window; no temperature/voltage
 localparam[31:0]LOCAL_CLOCK_HZ=CLOCK_HZ,LOCAL_WINDOW_US=WINDOW_US;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   window_ticks<=0;window_frames<=0;heartbeat<=0;health_pending<=0;health_ext_pending<=0;timing_pending<=0;
   has_frame<=0;timing_active<=0;last_key<=0;active_key<=0;measured_key<=0;timing_key<=0;
   active_epoch<=0;measured_epoch<=0;timing_epoch<=0;active_start<=0;measured_start<=0;timing_start<=0;
   timing_duration<=0;timing_sample<=0;last_duration_us<=0;timing_samples<=0;timing_measured<=0;
   fps_q16<=0;fps_valid<=0;state<=IDLE;kind_q<=0;status_q<=0;reason_q<=0;
   body_q<=0;body_length<=0;body_index<=0;packet_key<=0;packet_epoch<=0;packet_sequence<=0;
   packet_timestamp<=0;packet_deadline<=0;peer_q<=1;completed_packets<=0;cancelled_packets<=0;coalesced_timings<=0;
  end else begin
   if(window_ticks==WINDOW_CYCLES-1)begin
    window_ticks<=0;window_frames<=0;heartbeat<=inc32(heartbeat);
    // Production WINDOW_US=1e6; the simulator may accelerate wall-clock windows
    // with a proportionately changed CLOCK_HZ, preserving a one-second window.
    fps_q16<=window_frames>=65535 ? 32'hffff0000 : {window_frames[15:0],16'b0}+(frame_complete?32'd65536:0);fps_valid<=1;
    if(enabled&&has_frame)begin health_pending<=1;health_ext_pending<=1;end
   end else begin window_ticks<=window_ticks+1'b1;if(frame_complete)window_frames<=inc32(window_frames);end
   if(frame_begin)begin
    active_key<=frame_key;active_epoch<=frame_epoch;active_start<=now_us;timing_active<=1;
    timing_measured<=0;last_key<=frame_key;has_frame<=1;
   end
   if(frame_dropped)begin timing_active<=0;timing_measured<=0;last_duration_us<=0;end
   if(frame_complete&&!frame_begin)begin
    timing_active<=0;
    if(timing_active&&active_epoch==frame_epoch&&active_key==frame_key&&now_us>=active_start&&now_us-active_start<=64'hffffffff)begin
     timing_measured<=1;last_duration_us<=now_us-active_start;timing_samples<=inc32(timing_samples);
     measured_key<=active_key;measured_epoch<=active_epoch;measured_start<=active_start;
     timing_key<=active_key;timing_epoch<=active_epoch;timing_start<=active_start;
     timing_duration<=now_us-active_start;timing_sample<=inc32(timing_samples);timing_pending<=enabled;
     if(timing_pending)coalesced_timings<=inc32(coalesced_timings);
    end else begin timing_measured<=0;last_duration_us<=0;end
   end
   case(state)
    IDLE:if(enabled&&!invalidate&&has_frame&&now_us<=64'hffffffffffffffff-PACKET_TTL_US)begin
     packet_epoch<=cfg_epoch;packet_timestamp<=now_us;packet_deadline<=now_us+PACKET_TTL_US;peer_q<=1;body_index<=0;
     if(health_pending)begin
      health_pending<=0;kind_q<=9;status_q<=board_status;reason_q<=board_reason;packet_key<=last_key;body_length<=32;
      body_q<={board_status,8'd1,8'd9,{7'b0,link_up},{15'b0,core_fault},16'd23,cfg_epoch,heartbeat,drop_count,crc_errors,recovery_events,32'b0,256'b0};
      state<=ALLOCATE;
     end else if(health_ext_pending)begin
      health_ext_pending<=0;kind_q<=12;status_q<=board_status;reason_q<=board_reason;packet_key<=last_key;body_length<=64;
      body_q<={FIRMWARE_VERSION,BUILD_ID,32'd1,validity,fps_valid?fps_q16:32'b0,32'b0,
       frame_count,drop_count,rx_packets,tx_packets,crc_errors,source_timeouts,cfg_epoch,LOCAL_CLOCK_HZ,LOCAL_WINDOW_US,32'b0};
      state<=ALLOCATE;
     end else if(timing_pending)begin
      timing_pending<=0;kind_q<=10;status_q<=0;reason_q<=0;packet_key<=timing_key;packet_epoch<=timing_epoch;body_length<=24;
      body_q<={8'd3,8'd100,16'd1,timing_duration,timing_sample,timing_start,32'b0,320'b0};state<=ALLOCATE;
     end
    end
    ALLOCATE:if(sequence_request&&sequence_ready)begin packet_sequence<=sequence_base;state<=REQUEST;end
    REQUEST:if(request_ready&&packet_live)begin body_index<=0;state<=PAYLOAD;end
    PAYLOAD:if(body_ready)begin if(body_index+1==body_length)state<=WAIT_DONE;else body_index<=body_index+1'b1;end
    WAIT_DONE:if(send_done)begin
     completed_packets<=inc32(completed_packets);
     if(peer_q==1)begin peer_q<=2;body_index<=0;state<=REQUEST;end else state<=IDLE;
    end
   endcase
   if(state!=IDLE&&(!packet_live||now_us>=packet_deadline||send_abort||req_rejected))begin
    state<=IDLE;cancelled_packets<=inc32(cancelled_packets);
   end
   if(invalidate||!enabled)begin
    health_pending<=0;health_ext_pending<=0;timing_pending<=0;
    if(invalidate)begin has_frame<=0;timing_active<=0;timing_measured<=0;last_duration_us<=0;timing_samples<=0;fps_valid<=0;fps_q16<=0;window_ticks<=0;window_frames<=0;end
   end
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_mainline_atomic_snapshot.v
// Whole-board variant: either reset asserts both domains, but each domain
// releases its state/buffer reset synchronously to its OWN physical clock.
// Only raw reset release synchronizer endpoints need asynchronous exceptions;
// all state/held-buffer recovery paths remain timed within the local domain.
module pg100_mainline_atomic_snapshot #(parameter integer WORDS=40)(
    input wire native_clk,input wire native_rst_n,
    input wire [WORDS*32-1:0] native_status,
    input wire bus_clk,input wire bus_rst_n,
    input wire request,input wire [5:0] read_word,
    output reg busy,output reg snapshot_valid,output reg request_rejected,
    output reg [31:0] generation,output wire [31:0] read_data
);
    wire raw_reset_n=native_rst_n && bus_rst_n;
    (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]native_release,bus_release;
    always @(posedge native_clk or negedge raw_reset_n)
        if(!raw_reset_n)native_release<=0;else native_release<={native_release[1:0],1'b1};
    always @(posedge bus_clk or negedge raw_reset_n)
        if(!raw_reset_n)bus_release<=0;else bus_release<={bus_release[1:0],1'b1};
    wire native_reset_n=native_release[2],bus_reset_n=bus_release[2];
    reg request_toggle,ack_toggle;
    (* async_reg="true" *)reg req_meta,req_sync,ack_meta,ack_sync;
    reg[WORDS*32-1:0]held_native,held_bus;
    reg[1:0]settle;
    assign read_data=snapshot_valid && read_word<WORDS ? held_bus[read_word*32+:32] : 32'd0;
    always @(posedge native_clk or negedge native_reset_n)begin
        if(!native_reset_n)begin req_meta<=0;req_sync<=0;ack_toggle<=0;held_native<=0;end
        else begin
            req_meta<=request_toggle;req_sync<=req_meta;
            if(req_sync!=ack_toggle)begin held_native<=native_status;ack_toggle<=req_sync;end
        end
    end
    always @(posedge bus_clk or negedge bus_reset_n)begin
        if(!bus_reset_n)begin
            request_toggle<=0;ack_meta<=0;ack_sync<=0;busy<=0;snapshot_valid<=0;
            request_rejected<=0;generation<=0;held_bus<=0;settle<=0;
        end else begin
            ack_meta<=ack_toggle;ack_sync<=ack_meta;request_rejected<=0;
            if(request)begin
                if(busy)request_rejected<=1;
                else begin request_toggle<=!request_toggle;busy<=1;settle<=0;end
            end
            if(busy && ack_sync==request_toggle)begin
                if(settle==2)begin held_bus<=held_native;generation<=generation+1'b1;
                    snapshot_valid<=1;busy<=0;settle<=0;end
                else settle<=settle+1'b1;
            end
        end
    end
endmodule

// Source snapshot: rtl/mainline/pg100_rx_local_monitor.v
// Local receive inspection only. UDP/FCS/IP validation belongs to the MAC.
// PGT2 envelope integrity never grants SESSION/CONTROL authority. Remote-board
// application transactions are deliberately left for subsequent commissioning.
module pg100_rx_local_monitor #(parameter WATCHDOG_CYCLES=12500000)(
 input wire clk,rst_n,input wire s_hdr_valid,output wire s_hdr_ready,
 input wire[10:0]s_length,input wire[1:0]s_peer,input wire[7:0]s_data,
 input wire s_valid,output wire s_ready,input wire s_last,
 input wire cfg_export_enable,input wire[7:0]cfg_origin,input wire[63:0]cfg_session,
 input wire[15:0]cfg_mode,input wire[31:0]cfg_calib,
 output reg envelope_accepted,frame_meta_accepted,frame_meta_matches_config,
 output reg[151:0]last_metadata_key,output reg[7:0]last_message_type,
 output reg[31:0]good_envelopes,bad_envelopes,bad_crc,frame_metadata_packets,
 output reg[31:0]bad_frame_metadata,receive_timeouts
);
 localparam IDLE=0,COLLECT=1,CHECK=2;
 reg[1:0]state,peer_q;reg[10:0]length_q,count;
 reg[511:0]header_q;reg[255:0]prefix_q;reg[31:0]crc,trailer,watchdog;
 reg bad;
 function[31:0]crc_byte;input[31:0]c;input[7:0]b;reg[31:0]v;integer k;
  begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 function[31:0]inc32;input[31:0]v;begin inc32=&v?v:v+1'b1;end endfunction
 wire[7:0]producer=header_q[447:440],origin=header_q[439:432];
 wire[7:0]kind=header_q[471:464],status=header_q[423:416];
 wire[15:0]reason=header_q[415:400];
 wire[7:0]expected_producer=peer_q==0?8'd50:peer_q==1?8'd68:8'd40;
 wire[151:0]source_key={origin,header_q[351:288],header_q[287:256],header_q[399:384],header_q[383:352]};
 wire envelope_ok=header_q[511:480]==32'h50475432&&header_q[479:472]==1&&kind>=1&&kind<=12&&
  (header_q[463:448]&16'hfffe)==0&&producer==expected_producer&&
  (origin==50||origin==100||origin==68||origin==40)&&header_q[351:288]!=0&&
  (header_q[431:424]==0||header_q[431:424]==40||header_q[431:424]==50||header_q[431:424]==68||header_q[431:424]==100)&&
  status<=10&&reason<=23&&((status==0)==(reason==0))&&header_q[399:384]<=255&&
  header_q[159:144]+68==length_q&&header_q[159:144]<=956&&header_q[127:112]>=1&&header_q[127:112]<=32&&
  header_q[143:128]<header_q[127:112]&&header_q[111:96]==64&&header_q[95:0]==0;
 // Fixed mode1 full-source geometry; no metadata or ACK may imply RGB proof.
 wire meta_ok=kind==7&&producer==50&&origin==50&&status==0&&header_q[399:384]==1&&length_q==100&&
  header_q[143:128]==0&&header_q[127:112]==1&&
  prefix_q=={16'd1920,16'd1080,8'd1,8'd1,16'd320,16'd240,16'd0,16'd0,
             16'd1920,16'd1080,16'd30,16'd1,32'd74250000,16'd1,32'd0};
 assign s_hdr_ready=state==IDLE;
 assign s_ready=state!=CHECK; // harmlessly drain stale bytes after a timeout
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;peer_q<=0;length_q<=0;count<=0;header_q<=0;prefix_q<=0;crc<=32'hffffffff;trailer<=0;watchdog<=0;bad<=0;
   envelope_accepted<=0;frame_meta_accepted<=0;frame_meta_matches_config<=0;last_metadata_key<=0;last_message_type<=0;
   good_envelopes<=0;bad_envelopes<=0;bad_crc<=0;frame_metadata_packets<=0;bad_frame_metadata<=0;receive_timeouts<=0;
  end else begin
   envelope_accepted<=0;frame_meta_accepted<=0;frame_meta_matches_config<=0;
   case(state)
    IDLE:if(s_hdr_valid)begin
     length_q<=s_length;peer_q<=s_peer;count<=0;header_q<=0;prefix_q<=0;crc<=32'hffffffff;trailer<=0;watchdog<=0;
     bad<=s_length<76||s_length>1024||s_peer>2;state<=COLLECT;
    end
    COLLECT:begin
     watchdog<=watchdog+1'b1;
     if(s_valid)begin
      if(count<64)header_q[511-count*8-:8]<=s_data;
      if(count>=64&&count<96)prefix_q[255-(count-64)*8-:8]<=s_data;
      if(count>=4&&count+4<length_q)crc<=crc_byte(crc,s_data);
      if(count+4>=length_q)trailer<={trailer[23:0],s_data};
      if(count!=2047)count<=count+1'b1;else bad<=1;
      if(count>=length_q)bad<=1;
      if(s_last)begin if(count+1!=length_q)bad<=1;state<=CHECK;end
     end
     if(watchdog>=WATCHDOG_CYCLES-1)begin state<=IDLE;receive_timeouts<=inc32(receive_timeouts);bad_envelopes<=inc32(bad_envelopes);end
    end
    CHECK:begin
     state<=IDLE;
     if(bad||!envelope_ok||trailer!=~crc)begin
      bad_envelopes<=inc32(bad_envelopes);if(trailer!=~crc)bad_crc<=inc32(bad_crc);
     end else begin
      envelope_accepted<=1;good_envelopes<=inc32(good_envelopes);last_message_type<=kind;
      if(kind==7)begin
       if(meta_ok)begin
        frame_meta_accepted<=1;frame_metadata_packets<=inc32(frame_metadata_packets);last_metadata_key<=source_key;
        frame_meta_matches_config<=cfg_export_enable&&origin==cfg_origin&&header_q[351:288]==cfg_session&&
         header_q[399:384]==cfg_mode&&header_q[383:352]==cfg_calib;
       end else bad_frame_metadata<=inc32(bad_frame_metadata);
      end
     end
    end
   endcase
  end
 end
endmodule

// Source snapshot: rtl/mainline/pg100_mainline_network.v
`timescale 1ns/1ps
module pg100_mainline_network (
 input wire clk125,input wire clk_logic,input wire rst,
 input wire rgmii_rxc,input wire [3:0] rgmii_rxd,input wire rgmii_rx_ctl,
 output wire rgmii_txc,output wire [3:0] rgmii_txd,output wire rgmii_tx_ctl,
 output wire mdc,output wire mdio_out,output wire mdio_oe,input wire mdio_in,
 output wire link_gigabit,output wire phy_present,output wire delay_verified,
 output wire rx_hdr_valid,input wire rx_hdr_ready,output wire [1:0] rx_peer,output wire [10:0] rx_length,
 output wire [7:0] rx_data,output wire rx_valid,input wire rx_ready,output wire rx_last,
 input wire ctl_hdr_valid,output wire ctl_hdr_ready,input wire [1:0] ctl_peer,input wire [10:0] ctl_length,input wire ctl_abort,
 input wire [7:0] ctl_data,input wire ctl_valid,output wire ctl_ready,input wire ctl_last,
 input wire result_hdr_valid,output wire result_hdr_ready,input wire [1:0] result_peer,input wire [10:0] result_length,input wire result_abort,
 input wire [7:0] result_data,input wire result_valid,output wire result_ready,input wire result_last,
 output wire [31:0] rx_accepted,output wire [31:0] rx_rejected,output wire [31:0] mdio_errors,
 output wire rx_bad_fcs,output wire rx_fifo_overflow,output wire tx_arp_failed,output wire tx_quiescent,
 output reg[31:0]rx_crc_errors_native,rx_overflow_events_native,tx_wire_frames
);
 localparam [47:0] LOCAL_MAC=48'h025000000064;
 localparam [31:0] LOCAL_IP=32'hc0a8321e;

 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]management_reset_ref,tx_reset_ref;
 always @(posedge clk125 or posedge rst)
  if(rst)management_reset_ref<=7;else management_reset_ref<={management_reset_ref[1:0],1'b0};
 wire network_rst=rst||!link_gigabit;
 always @(posedge clk125 or posedge network_rst)
  if(network_rst)tx_reset_ref<=7;else tx_reset_ref<={tx_reset_ref[1:0],1'b0};
 wire[31:0]mdio_errors_ref;

 reg[2:0] logic_reset_sync;
 always @(posedge clk_logic or posedge network_rst)
  if(network_rst)logic_reset_sync<=7;else logic_reset_sync<={logic_reset_sync[1:0],1'b0};
 wire logic_rst=logic_reset_sync[2];
 wire [7:0] gmii_rxd,gmii_txd;wire gmii_rx_dv,gmii_rx_er,gmii_tx_en,gmii_tx_er,rx_clk;
 reg [2:0] rx_reset_sync;
 always @(posedge rx_clk or posedge network_rst)
  if(network_rst) rx_reset_sync<=7;else rx_reset_sync<={rx_reset_sync[1:0],1'b0};
 pg100_rtl8211f_init management(.clk(clk125),.rst(management_reset_ref[2]),.mdc(mdc),.mdio_out(mdio_out),.mdio_oe(mdio_oe),.mdio_in(mdio_in),
  .link_gigabit(link_gigabit),.phy_present(phy_present),.delay_verified(delay_verified),.link_up(),.speed(),.full_duplex(),.mdio_errors(mdio_errors_ref));
 pg100_rgmii pins(.tx_clk125(clk125),.tx_rst(tx_reset_ref[2]),.rgmii_rxc(rgmii_rxc),.rx_rst(rx_reset_sync[2]),
  .rgmii_rxd(rgmii_rxd),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_txd(rgmii_txd),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txc(rgmii_txc),
  .rx_clk(rx_clk),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),.gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er));
 wire [8-1:0] tx_axis_tdata;
 wire [1-1:0] tx_axis_tkeep;
 wire  tx_axis_tvalid;
 wire  tx_axis_tready;
 wire  tx_axis_tlast;
 wire  tx_axis_tuser;
 wire [8-1:0] rx_axis_tdata;
 wire [1-1:0] rx_axis_tkeep;
 wire  rx_axis_tvalid;
 wire  rx_axis_tready;
 wire  rx_axis_tlast;
 wire  rx_axis_tuser;
 wire r_eth_hdr_valid,r_eth_hdr_ready,t_eth_hdr_valid,t_eth_hdr_ready;
 wire eth_tx_busy,ip_tx_busy,udp_tx_busy;
 wire [47:0] r_eth_dest_mac;
 wire [47:0] r_eth_src_mac;
 wire [15:0] r_eth_type;
 wire [7:0] r_eth_payload_axis_tdata;
 wire  r_eth_payload_axis_tvalid;
 wire  r_eth_payload_axis_tready;
 wire  r_eth_payload_axis_tlast;
 wire  r_eth_payload_axis_tuser;
 wire [47:0] t_eth_dest_mac;
 wire [47:0] t_eth_src_mac;
 wire [15:0] t_eth_type;
 wire [7:0] t_eth_payload_axis_tdata;
 wire  t_eth_payload_axis_tvalid;
 wire  t_eth_payload_axis_tready;
 wire  t_eth_payload_axis_tlast;
 wire  t_eth_payload_axis_tuser;
pg100_network_eth_mac_1g_fifo #(.TX_FIFO_DEPTH(2048),.RX_FIFO_DEPTH(2048)) mac(
 .rx_clk(rx_clk),
 .rx_rst(rx_reset_sync[2]),
 .tx_clk(clk125),
 .tx_rst(tx_reset_ref[2]),
 .logic_clk(clk_logic),
 .logic_rst(logic_rst),
 .tx_axis_tdata(tx_axis_tdata),
 .tx_axis_tkeep(1'b1),
 .tx_axis_tvalid(tx_axis_tvalid),
 .tx_axis_tready(tx_axis_tready),
 .tx_axis_tlast(tx_axis_tlast),
 .tx_axis_tuser(tx_axis_tuser),
 .rx_axis_tdata(rx_axis_tdata),
 .rx_axis_tkeep(rx_axis_tkeep),
 .rx_axis_tvalid(rx_axis_tvalid),
 .rx_axis_tready(rx_axis_tready),
 .rx_axis_tlast(rx_axis_tlast),
 .rx_axis_tuser(rx_axis_tuser),
 .gmii_rxd(gmii_rxd),
 .gmii_rx_dv(gmii_rx_dv),
 .gmii_rx_er(gmii_rx_er),
 .gmii_txd(gmii_txd),
 .gmii_tx_en(gmii_tx_en),
 .gmii_tx_er(gmii_tx_er),
 .rx_clk_enable(1'b1),
 .tx_clk_enable(1'b1),
 .rx_mii_select(1'b0),
 .tx_mii_select(1'b0),
 .tx_error_underflow(),
 .tx_fifo_overflow(),
 .tx_fifo_bad_frame(),
 .tx_fifo_good_frame(),
 .rx_error_bad_frame(),
 .rx_error_bad_fcs(rx_bad_fcs),
 .rx_fifo_overflow(rx_fifo_overflow),
 .rx_fifo_bad_frame(),
 .rx_fifo_good_frame(),
 .cfg_ifg(8'd12),
 .cfg_tx_enable(1'b1),
 .cfg_rx_enable(1'b1)
);
eth_axis_rx eth_axis_rx_inst(
 .clk(clk_logic),
 .rst(logic_rst),
 .s_axis_tdata(rx_axis_tdata),
 .s_axis_tkeep(1'b1),
 .s_axis_tvalid(rx_axis_tvalid),
 .s_axis_tready(rx_axis_tready),
 .s_axis_tlast(rx_axis_tlast),
 .s_axis_tuser(rx_axis_tuser),
 .m_eth_hdr_valid(r_eth_hdr_valid),
 .m_eth_hdr_ready(r_eth_hdr_ready),
 .m_eth_dest_mac(r_eth_dest_mac),
 .m_eth_src_mac(r_eth_src_mac),
 .m_eth_type(r_eth_type),
 .m_eth_payload_axis_tdata(r_eth_payload_axis_tdata),
 .m_eth_payload_axis_tkeep(),
 .m_eth_payload_axis_tvalid(r_eth_payload_axis_tvalid),
 .m_eth_payload_axis_tready(r_eth_payload_axis_tready),
 .m_eth_payload_axis_tlast(r_eth_payload_axis_tlast),
 .m_eth_payload_axis_tuser(r_eth_payload_axis_tuser),
 .busy(),
 .error_header_early_termination()
);
eth_axis_tx eth_axis_tx_inst(
 .clk(clk_logic),
 .rst(logic_rst),
 .s_eth_hdr_valid(t_eth_hdr_valid),
 .s_eth_hdr_ready(t_eth_hdr_ready),
 .s_eth_dest_mac(t_eth_dest_mac),
 .s_eth_src_mac(t_eth_src_mac),
 .s_eth_type(t_eth_type),
 .s_eth_payload_axis_tdata(t_eth_payload_axis_tdata),
 .s_eth_payload_axis_tkeep(1'b1),
 .s_eth_payload_axis_tvalid(t_eth_payload_axis_tvalid),
 .s_eth_payload_axis_tready(t_eth_payload_axis_tready),
 .s_eth_payload_axis_tlast(t_eth_payload_axis_tlast),
 .s_eth_payload_axis_tuser(t_eth_payload_axis_tuser),
 .m_axis_tdata(tx_axis_tdata),
 .m_axis_tkeep(),
 .m_axis_tvalid(tx_axis_tvalid),
 .m_axis_tready(tx_axis_tready),
 .m_axis_tlast(tx_axis_tlast),
 .m_axis_tuser(tx_axis_tuser),
 .busy(eth_tx_busy)
);
 wire  u_m_udp_hdr_valid;
 wire  u_m_udp_hdr_ready;
 wire [47:0] u_m_udp_eth_dest_mac;
 wire [47:0] u_m_udp_eth_src_mac;
 wire [15:0] u_m_udp_eth_type;
 wire [3:0] u_m_udp_ip_version;
 wire [3:0] u_m_udp_ip_ihl;
 wire [5:0] u_m_udp_ip_dscp;
 wire [1:0] u_m_udp_ip_ecn;
 wire [15:0] u_m_udp_ip_length;
 wire [15:0] u_m_udp_ip_identification;
 wire [2:0] u_m_udp_ip_flags;
 wire [12:0] u_m_udp_ip_fragment_offset;
 wire [7:0] u_m_udp_ip_ttl;
 wire [7:0] u_m_udp_ip_protocol;
 wire [15:0] u_m_udp_ip_header_checksum;
 wire [31:0] u_m_udp_ip_source_ip;
 wire [31:0] u_m_udp_ip_dest_ip;
 wire [15:0] u_m_udp_source_port;
 wire [15:0] u_m_udp_dest_port;
 wire [15:0] u_m_udp_length;
 wire [15:0] u_m_udp_checksum;
 wire [7:0] u_m_udp_payload_axis_tdata;
 wire  u_m_udp_payload_axis_tvalid;
 wire  u_m_udp_payload_axis_tready;
 wire  u_m_udp_payload_axis_tlast;
 wire  u_m_udp_payload_axis_tuser;
 wire out_hdr_valid,out_hdr_ready;wire [1:0] out_peer;wire [10:0] out_length;wire [7:0] out_data;wire out_valid,out_ready,out_last;
udp_complete #(.ARP_CACHE_ADDR_WIDTH(4),.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH(2048),.UDP_CHECKSUM_HEADER_FIFO_DEPTH(2)) stack(
 .clk(clk_logic),
 .rst(logic_rst),
 .s_eth_hdr_valid(r_eth_hdr_valid),
 .s_eth_hdr_ready(r_eth_hdr_ready),
 .s_eth_dest_mac(r_eth_dest_mac),
 .s_eth_src_mac(r_eth_src_mac),
 .s_eth_type(r_eth_type),
 .s_eth_payload_axis_tdata(r_eth_payload_axis_tdata),
 .s_eth_payload_axis_tvalid(r_eth_payload_axis_tvalid),
 .s_eth_payload_axis_tready(r_eth_payload_axis_tready),
 .s_eth_payload_axis_tlast(r_eth_payload_axis_tlast),
 .s_eth_payload_axis_tuser(r_eth_payload_axis_tuser),
 .m_eth_hdr_valid(t_eth_hdr_valid),
 .m_eth_hdr_ready(t_eth_hdr_ready),
 .m_eth_dest_mac(t_eth_dest_mac),
 .m_eth_src_mac(t_eth_src_mac),
 .m_eth_type(t_eth_type),
 .m_eth_payload_axis_tdata(t_eth_payload_axis_tdata),
 .m_eth_payload_axis_tvalid(t_eth_payload_axis_tvalid),
 .m_eth_payload_axis_tready(t_eth_payload_axis_tready),
 .m_eth_payload_axis_tlast(t_eth_payload_axis_tlast),
 .m_eth_payload_axis_tuser(t_eth_payload_axis_tuser),
 .s_ip_hdr_valid(1'b0),
 .s_ip_hdr_ready(),
 .s_ip_dscp(6'd0),
 .s_ip_ecn(2'd0),
 .s_ip_length(16'd0),
 .s_ip_ttl(8'd0),
 .s_ip_protocol(8'd0),
 .s_ip_source_ip(32'd0),
 .s_ip_dest_ip(32'd0),
 .s_ip_payload_axis_tdata(8'd0),
 .s_ip_payload_axis_tvalid(1'b0),
 .s_ip_payload_axis_tready(),
 .s_ip_payload_axis_tlast(1'b0),
 .s_ip_payload_axis_tuser(1'b0),
 .m_ip_hdr_valid(),
 .m_ip_hdr_ready(1'b1),
 .m_ip_eth_dest_mac(),
 .m_ip_eth_src_mac(),
 .m_ip_eth_type(),
 .m_ip_version(),
 .m_ip_ihl(),
 .m_ip_dscp(),
 .m_ip_ecn(),
 .m_ip_length(),
 .m_ip_identification(),
 .m_ip_flags(),
 .m_ip_fragment_offset(),
 .m_ip_ttl(),
 .m_ip_protocol(),
 .m_ip_header_checksum(),
 .m_ip_source_ip(),
 .m_ip_dest_ip(),
 .m_ip_payload_axis_tdata(),
 .m_ip_payload_axis_tvalid(),
 .m_ip_payload_axis_tready(1'b1),
 .m_ip_payload_axis_tlast(),
 .m_ip_payload_axis_tuser(),
 .s_udp_hdr_valid(out_hdr_valid),
 .s_udp_hdr_ready(out_hdr_ready),
 .s_udp_ip_dscp(6'd0),
 .s_udp_ip_ecn(2'd0),
 .s_udp_ip_ttl(8'd64),
 .s_udp_ip_source_ip(LOCAL_IP),
 .s_udp_ip_dest_ip(out_peer==0 ? 32'hc0a83214 : out_peer==1 ? 32'hc0a8320a : 32'hc0a83228),
 .s_udp_source_port(16'd5100),
 .s_udp_dest_port(16'd5100),
 .s_udp_length({5'b0,out_length}+16'd8),
 .s_udp_checksum(16'd0),
 .s_udp_payload_axis_tdata(out_data),
 .s_udp_payload_axis_tvalid(out_valid),
 .s_udp_payload_axis_tready(out_ready),
 .s_udp_payload_axis_tlast(out_last),
 .s_udp_payload_axis_tuser(1'b0),
 .m_udp_hdr_valid(u_m_udp_hdr_valid),
 .m_udp_hdr_ready(u_m_udp_hdr_ready),
 .m_udp_eth_dest_mac(u_m_udp_eth_dest_mac),
 .m_udp_eth_src_mac(u_m_udp_eth_src_mac),
 .m_udp_eth_type(u_m_udp_eth_type),
 .m_udp_ip_version(u_m_udp_ip_version),
 .m_udp_ip_ihl(u_m_udp_ip_ihl),
 .m_udp_ip_dscp(u_m_udp_ip_dscp),
 .m_udp_ip_ecn(u_m_udp_ip_ecn),
 .m_udp_ip_length(u_m_udp_ip_length),
 .m_udp_ip_identification(u_m_udp_ip_identification),
 .m_udp_ip_flags(u_m_udp_ip_flags),
 .m_udp_ip_fragment_offset(u_m_udp_ip_fragment_offset),
 .m_udp_ip_ttl(u_m_udp_ip_ttl),
 .m_udp_ip_protocol(u_m_udp_ip_protocol),
 .m_udp_ip_header_checksum(u_m_udp_ip_header_checksum),
 .m_udp_ip_source_ip(u_m_udp_ip_source_ip),
 .m_udp_ip_dest_ip(u_m_udp_ip_dest_ip),
 .m_udp_source_port(u_m_udp_source_port),
 .m_udp_dest_port(u_m_udp_dest_port),
 .m_udp_length(u_m_udp_length),
 .m_udp_checksum(u_m_udp_checksum),
 .m_udp_payload_axis_tdata(u_m_udp_payload_axis_tdata),
 .m_udp_payload_axis_tvalid(u_m_udp_payload_axis_tvalid),
 .m_udp_payload_axis_tready(u_m_udp_payload_axis_tready),
 .m_udp_payload_axis_tlast(u_m_udp_payload_axis_tlast),
 .m_udp_payload_axis_tuser(u_m_udp_payload_axis_tuser),
 .ip_rx_busy(),
 .ip_tx_busy(ip_tx_busy),
 .udp_rx_busy(),
 .udp_tx_busy(udp_tx_busy),
 .ip_rx_error_header_early_termination(),
 .ip_rx_error_payload_early_termination(),
 .ip_rx_error_invalid_header(),
 .ip_rx_error_invalid_checksum(),
 .ip_tx_error_payload_early_termination(),
 .ip_tx_error_arp_failed(tx_arp_failed),
 .udp_rx_error_header_early_termination(),
 .udp_rx_error_payload_early_termination(),
 .udp_tx_error_payload_early_termination(),
 .local_mac(LOCAL_MAC),
 .local_ip(LOCAL_IP),
 .gateway_ip(32'hc0a83201),
 .subnet_mask(32'hffffff00),
 .clear_arp_cache(logic_rst)
);

 pg100_udp_rx_guard guard(.clk(clk_logic),.rst(logic_rst),.hdr_valid(u_m_udp_hdr_valid),.hdr_ready(u_m_udp_hdr_ready),
 .dest_mac(u_m_udp_eth_dest_mac),.ip_version(u_m_udp_ip_version),.ip_ihl(u_m_udp_ip_ihl),.ip_length(u_m_udp_ip_length),.ip_flags(u_m_udp_ip_flags),.ip_fragment_offset(u_m_udp_ip_fragment_offset),
 .source_ip(u_m_udp_ip_source_ip),.dest_ip(u_m_udp_ip_dest_ip),.source_port(u_m_udp_source_port),.dest_port(u_m_udp_dest_port),.udp_length(u_m_udp_length),.udp_checksum(u_m_udp_checksum),
 .s_data(u_m_udp_payload_axis_tdata),.s_valid(u_m_udp_payload_axis_tvalid),.s_ready(u_m_udp_payload_axis_tready),.s_last(u_m_udp_payload_axis_tlast),.s_user(u_m_udp_payload_axis_tuser),
 .m_hdr_valid(rx_hdr_valid),.m_hdr_ready(rx_hdr_ready),.m_peer(rx_peer),.m_length(rx_length),.m_data(rx_data),.m_valid(rx_valid),.m_ready(rx_ready),.m_last(rx_last),.accepted(rx_accepted),.rejected(rx_rejected));
 wire [1:0] q_hdr,q_hdr_ready,q_valid,q_ready,q_last;
 wire [3:0] q_peer;wire [21:0] q_length;wire [15:0] q_data;
 wire ctl_hdr_ready_int,result_hdr_ready_int,ctl_ready_int,result_ready_int;
 assign ctl_hdr_ready=ctl_hdr_ready_int&&!logic_rst;assign result_hdr_ready=result_hdr_ready_int&&!logic_rst;
 assign ctl_ready=ctl_ready_int&&!logic_rst;assign result_ready=result_ready_int&&!logic_rst;
 wire control_idle,result_idle;
 pg100_mainline_udp_tx_slot control_queue(.clk(clk_logic),.rst(logic_rst),.abort(ctl_abort),.idle(control_idle),.s_hdr_valid(ctl_hdr_valid),.s_hdr_ready(ctl_hdr_ready_int),.s_peer(ctl_peer),.s_length(ctl_length),.s_data(ctl_data),.s_valid(ctl_valid),.s_ready(ctl_ready_int),.s_last(ctl_last),
 .m_hdr_valid(q_hdr[0]),.m_hdr_ready(q_hdr_ready[0]),.m_peer(q_peer[1:0]),.m_length(q_length[10:0]),.m_data(q_data[7:0]),.m_valid(q_valid[0]),.m_ready(q_ready[0]),.m_last(q_last[0]),.rejected());
 pg100_mainline_udp_tx_slot result_queue(.clk(clk_logic),.rst(logic_rst),.abort(result_abort),.idle(result_idle),.s_hdr_valid(result_hdr_valid),.s_hdr_ready(result_hdr_ready_int),.s_peer(result_peer),.s_length(result_length),.s_data(result_data),.s_valid(result_valid),.s_ready(result_ready_int),.s_last(result_last),
 .m_hdr_valid(q_hdr[1]),.m_hdr_ready(q_hdr_ready[1]),.m_peer(q_peer[3:2]),.m_length(q_length[21:11]),.m_data(q_data[15:8]),.m_valid(q_valid[1]),.m_ready(q_ready[1]),.m_last(q_last[1]),.rejected());
 reg active,selected,last_grant;
 always @(posedge clk_logic) begin
  if(logic_rst) begin active<=0;selected<=0;last_grant<=1;end
  else if(!active) begin
   if(|q_hdr) begin selected<=q_hdr[~last_grant] ? ~last_grant : last_grant;active<=1;end
  end else if(out_valid&&out_ready&&out_last) begin active<=0;last_grant<=selected;end
 end
 assign out_hdr_valid=active&&q_hdr[selected];
 assign out_peer=selected?q_peer[3:2]:q_peer[1:0];assign out_length=selected?q_length[21:11]:q_length[10:0];
 assign out_data=selected?q_data[15:8]:q_data[7:0];assign out_valid=active&&q_valid[selected];assign out_last=q_last[selected];
 assign q_hdr_ready={active&&selected&&out_hdr_ready,active&&!selected&&out_hdr_ready};
 assign q_ready={active&&selected&&out_ready,active&&!selected&&out_ready};
 // All Ethernet frames, including ARP, cross the same TX FIFO. Count commits
 // at its actual input and physical finishes after the GMII final FCS byte.
 // A registered Gray completion counter crosses into the native application clock domain.
 // This fence never considers a packet finished at its UDP-slot handshake.
 reg[31:0]tx_committed,tx_finished,finished_gray;
 reg tx_partial,tx_en_previous;
 reg[31:0]finished_sync1,finished_sync2 /* synthesis syn_preserve=1 */;
 always @(posedge clk125 or posedge tx_reset_ref[2])begin
  if(tx_reset_ref[2])begin tx_finished<=0;finished_gray<=0;tx_en_previous<=0;end
  else begin
   tx_en_previous<=gmii_tx_en;
   if(tx_en_previous&&!gmii_tx_en)begin
    tx_finished<=tx_finished+1'b1;finished_gray<=((tx_finished+1'b1)>>1)^(tx_finished+1'b1);
   end
  end
 end
 always @(posedge clk_logic or posedge logic_rst)begin
  if(logic_rst)begin tx_committed<=0;tx_partial<=0;finished_sync1<=0;finished_sync2<=0;end
  else begin
   finished_sync1<=finished_gray;finished_sync2<=finished_sync1;
   if(tx_axis_tvalid&&tx_axis_tready)begin
    tx_partial<=!tx_axis_tlast;if(tx_axis_tlast)tx_committed<=tx_committed+1'b1;
   end
  end
 end
 assign tx_quiescent=logic_rst || (control_idle&&result_idle&&!active&&!eth_tx_busy&&!ip_tx_busy&&!udp_tx_busy&&
  !tx_partial&&!tx_axis_tvalid&&finished_sync2==((tx_committed>>1)^tx_committed)); // Error events belong to recovered RXC. Registered Gray counters cross to
 // native; never count raw one-cycle PHY pulses in a different clock domain.
 reg[31:0]crc_rx,overflow_rx,crc_gray_rx,overflow_gray_rx,mdio_gray_ref,wire_total,wire_total_gray;
 reg wire_tx_previous;
 reg[31:0]wire_total_sync1,wire_total_sync2 /* synthesis syn_preserve=1 */;
 (* syn_preserve=1,syn_allow_retiming=0 *)reg[2:0]counter_reset_rx,counter_reset_logic;
 always @(posedge rx_clk or posedge rst)
  if(rst)counter_reset_rx<=7;else counter_reset_rx<={counter_reset_rx[1:0],1'b0};
 always @(posedge clk_logic or posedge rst)
  if(rst)counter_reset_logic<=7;else counter_reset_logic<={counter_reset_logic[1:0],1'b0};
 reg[31:0]crc_sync1,crc_sync2,overflow_sync1,overflow_sync2,mdio_sync1,mdio_sync2 /* synthesis syn_preserve=1 */;
 function[31:0]gray_binary;
  input[31:0]v;integer j;begin gray_binary[31]=v[31];for(j=30;j>=0;j=j-1)gray_binary[j]=gray_binary[j+1]^v[j];end
 endfunction
 wire[31:0]crc_next=&crc_rx?crc_rx:crc_rx+1'b1;
 wire[31:0]overflow_next=&overflow_rx?overflow_rx:overflow_rx+1'b1;
 always @(posedge rx_clk or posedge counter_reset_rx[2])begin
  if(counter_reset_rx[2])begin crc_rx<=0;overflow_rx<=0;crc_gray_rx<=0;overflow_gray_rx<=0;end
  else begin
   if(!rx_reset_sync[2]&&rx_bad_fcs)begin crc_rx<=crc_next;crc_gray_rx<=(crc_next>>1)^crc_next;end
   if(!rx_reset_sync[2]&&rx_fifo_overflow)begin overflow_rx<=overflow_next;overflow_gray_rx<=(overflow_next>>1)^overflow_next;end
  end
 end
 always @(posedge clk125 or posedge management_reset_ref[2])begin
  if(management_reset_ref[2])begin mdio_gray_ref<=0;wire_total<=0;wire_total_gray<=0;wire_tx_previous<=0;end
  else begin
   mdio_gray_ref<=(mdio_errors_ref>>1)^mdio_errors_ref;
   wire_tx_previous<=tx_reset_ref[2]?1'b0:gmii_tx_en;
   if(!tx_reset_ref[2]&&wire_tx_previous&&!gmii_tx_en&&wire_total!=32'hffffffff)begin
    wire_total<=wire_total+1'b1;wire_total_gray<=((wire_total+1'b1)>>1)^(wire_total+1'b1);
   end
  end
 end
 always @(posedge clk_logic or posedge counter_reset_logic[2])begin
  if(counter_reset_logic[2])begin
   crc_sync1<=0;crc_sync2<=0;overflow_sync1<=0;overflow_sync2<=0;mdio_sync1<=0;mdio_sync2<=0;
   wire_total_sync1<=0;wire_total_sync2<=0;
   rx_crc_errors_native<=0;rx_overflow_events_native<=0;tx_wire_frames<=0;
  end else begin
   crc_sync1<=crc_gray_rx;crc_sync2<=crc_sync1;overflow_sync1<=overflow_gray_rx;overflow_sync2<=overflow_sync1;
   mdio_sync1<=mdio_gray_ref;mdio_sync2<=mdio_sync1;
   wire_total_sync1<=wire_total_gray;wire_total_sync2<=wire_total_sync1;
   rx_crc_errors_native<=gray_binary(crc_sync2);rx_overflow_events_native<=gray_binary(overflow_sync2);
   tx_wire_frames<=gray_binary(wire_total_sync2);
  end
 end
 assign mdio_errors=gray_binary(mdio_sync2);

endmodule

// Source snapshot: rtl/mainline/pg100_mainline_udp_tx_slot.v
`timescale 1ns/1ps
// Abort has priority while collecting a datagram. A committed datagram must
// drain intact; a configuration fence waits for idle instead of resetting it.
module pg100_mainline_udp_tx_slot(
 input wire clk,rst,abort,
 input wire s_hdr_valid,output wire s_hdr_ready,input wire[1:0]s_peer,input wire[10:0]s_length,
 input wire[7:0]s_data,input wire s_valid,output wire s_ready,input wire s_last,
 output wire m_hdr_valid,input wire m_hdr_ready,output reg[1:0]m_peer,output reg[10:0]m_length,
 output reg[7:0]m_data,output wire m_valid,input wire m_ready,output wire m_last,
 output wire idle,output reg[31:0]rejected
);
 localparam IDLE=0,COLLECT=1,HEADER=2,READ=3,SEND=4;
 reg[2:0]state;reg[10:0]wr,rd;reg bad;
 reg[7:0]memory[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 always @(posedge clk)begin
  if(state==COLLECT&&s_valid&&!abort&&wr<1024)memory[wr[9:0]]<=s_data;
  if(state==READ)m_data<=memory[rd[9:0]];
 end
 assign idle=state==IDLE;
 assign s_hdr_ready=idle&&!abort;
 assign s_ready=state==COLLECT&&!abort;
 assign m_hdr_valid=state==HEADER;assign m_valid=state==SEND;assign m_last=rd+1==m_length;
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;wr<=0;rd<=0;bad<=0;m_peer<=0;m_length<=0;rejected<=0;end
  else if(abort&&state==COLLECT)begin state<=IDLE;wr<=0;rejected<=rejected+1'b1;end
  else case(state)
   IDLE:if(s_hdr_valid&&!abort)begin
    m_peer<=s_peer;m_length<=s_length;wr<=0;bad<=s_length<68||s_length>1024||s_peer>2;state<=COLLECT;
   end
   COLLECT:if(s_valid)begin
    if(wr>=1024)bad<=1;if(wr!=2047)wr<=wr+1'b1;
    if(s_last)begin
     if(bad||wr+1!=m_length)begin rejected<=rejected+1'b1;state<=IDLE;end
     else begin state<=HEADER;rd<=0;end
    end
   end
   HEADER:if(m_hdr_ready)state<=READ;
   READ:state<=SEND;
   SEND:if(m_ready)begin if(m_last)state<=IDLE;else begin rd<=rd+1'b1;state<=READ;end end
   default:state<=IDLE;
  endcase
 end
endmodule

// Source snapshot: rtl/network/hardware/pg100_network_async_fifo.v
// Network-specific MIT derivative: RAM read stage made explicit for ADS; identical handshake/latency.
/*

Copyright (c) 2014-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream asynchronous FIFO
 */
module pg100_network_async_fifo #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    // Propagate tlast signal
    parameter LAST_ENABLE = 1,
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    /*
     * AXI input
     */
    input  wire                   s_clk,
    input  wire                   s_rst,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                   m_clk,
    input  wire                   m_rst,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /*
     * Pause
     */
    input  wire                   s_pause_req,
    output wire                   s_pause_ack,
    input  wire                   m_pause_req,
    output wire                   m_pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0] s_status_depth,
    output wire [$clog2(DEPTH):0] s_status_depth_commit,
    output wire                   s_status_overflow,
    output wire                   s_status_bad_frame,
    output wire                   s_status_good_frame,
    output wire [$clog2(DEPTH):0] m_status_depth,
    output wire [$clog2(DEPTH):0] m_status_depth_commit,
    output wire                   m_status_overflow,
    output wire                   m_status_bad_frame,
    output wire                   m_status_good_frame
);

parameter ADDR_WIDTH = (KEEP_ENABLE && KEEP_WIDTH > 1) ? $clog2(DEPTH/KEEP_WIDTH) : $clog2(DEPTH);
parameter CL_KEEP_WDITH = $clog2(KEEP_WIDTH);

parameter OUTPUT_FIFO_ADDR_WIDTH = RAM_PIPELINE < 2 ? 3 : $clog2(RAM_PIPELINE*2+7);

// check configuration
initial begin
    if (FRAME_FIFO && !LAST_ENABLE) begin
        $display("Error: FRAME_FIFO set requires LAST_ENABLE set (instance %m)");
        $finish;
    end

    if (DROP_OVERSIZE_FRAME && !FRAME_FIFO) begin
        $display("Error: DROP_OVERSIZE_FRAME set requires FRAME_FIFO set (instance %m)");
        $finish;
    end

    if (DROP_BAD_FRAME && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_BAD_FRAME set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if (DROP_WHEN_FULL && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_WHEN_FULL set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if ((DROP_BAD_FRAME || MARK_WHEN_FULL) && (USER_BAD_FRAME_MASK & {USER_WIDTH{1'b1}}) == 0) begin
        $display("Error: Invalid USER_BAD_FRAME_MASK value (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && FRAME_FIFO) begin
        $display("Error: MARK_WHEN_FULL is not compatible with FRAME_FIFO (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && !LAST_ENABLE) begin
        $display("Error: MARK_WHEN_FULL set requires LAST_ENABLE set (instance %m)");
        $finish;
    end
end

localparam KEEP_OFFSET = DATA_WIDTH;
localparam LAST_OFFSET = KEEP_OFFSET + (KEEP_ENABLE ? KEEP_WIDTH : 0);
localparam ID_OFFSET   = LAST_OFFSET + (LAST_ENABLE ? 1          : 0);
localparam DEST_OFFSET = ID_OFFSET   + (ID_ENABLE   ? ID_WIDTH   : 0);
localparam USER_OFFSET = DEST_OFFSET + (DEST_ENABLE ? DEST_WIDTH : 0);
localparam WIDTH       = USER_OFFSET + (USER_ENABLE ? USER_WIDTH : 0);

function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = b ^ (b >> 1);
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    for (i = 0; i <= ADDR_WIDTH; i = i + 1) begin
        gray2bin[i] = ^(g >> i);
    end
endfunction

reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_sync_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};

reg [ADDR_WIDTH:0] wr_ptr_temp;
reg [ADDR_WIDTH:0] rd_ptr_temp;

(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_commit_sync_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};

reg wr_ptr_update_valid_reg = 1'b0;
reg wr_ptr_update_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync1_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync2_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync3_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_ack_sync1_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_ack_sync2_reg = 1'b0;

(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync1_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync2_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync3_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync1_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync2_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync3_reg = 1'b1;

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0] /* synthesis syn_ramstyle="block_ram" */;
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [WIDTH-1:0] mem_read_data /* synthesis syn_ramstyle="block_ram" */;
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first TWO MSBs do NOT match, but rest matches
// (gray code equivalent of first MSB different but rest same)
wire full = wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}});
// empty when pointers match exactly
wire empty = FRAME_FIFO ? (rd_ptr_reg == wr_ptr_commit_sync_reg) : (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg);
// overflow within packet
wire full_wr = wr_ptr_reg == (wr_ptr_commit_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});

// control signals
reg write;
reg read;
reg store_output;

reg s_frame_reg = 1'b0;
reg m_frame_reg = 1'b0;

reg drop_frame_reg = 1'b0;
reg mark_frame_reg = 1'b0;
reg send_frame_reg = 1'b0;
reg overflow_reg = 1'b0;
reg bad_frame_reg = 1'b0;
reg good_frame_reg = 1'b0;

reg m_drop_frame_reg = 1'b0;
reg m_terminate_frame_reg = 1'b0;

reg [ADDR_WIDTH:0] s_depth_reg = 0;
reg [ADDR_WIDTH:0] s_depth_commit_reg = 0;
reg [ADDR_WIDTH:0] m_depth_reg = 0;
reg [ADDR_WIDTH:0] m_depth_commit_reg = 0;

reg overflow_sync1_reg = 1'b0;
reg overflow_sync2_reg = 1'b0;
reg overflow_sync3_reg = 1'b0;
reg overflow_sync4_reg = 1'b0;
reg bad_frame_sync1_reg = 1'b0;
reg bad_frame_sync2_reg = 1'b0;
reg bad_frame_sync3_reg = 1'b0;
reg bad_frame_sync4_reg = 1'b0;
reg good_frame_sync1_reg = 1'b0;
reg good_frame_sync2_reg = 1'b0;
reg good_frame_sync3_reg = 1'b0;
reg good_frame_sync4_reg = 1'b0;

assign s_axis_tready = (FRAME_FIFO ? (!full || (full_wr && DROP_OVERSIZE_FRAME) || DROP_WHEN_FULL) : (!full || MARK_WHEN_FULL)) && !s_rst_sync3_reg;

wire [WIDTH-1:0] s_axis;

generate
    assign s_axis[DATA_WIDTH-1:0] = s_axis_tdata;
    if (KEEP_ENABLE) assign s_axis[KEEP_OFFSET +: KEEP_WIDTH] = s_axis_tkeep;
    if (LAST_ENABLE) assign s_axis[LAST_OFFSET]               = s_axis_tlast | mark_frame_reg;
    if (ID_ENABLE)   assign s_axis[ID_OFFSET   +: ID_WIDTH]   = s_axis_tid;
    if (DEST_ENABLE) assign s_axis[DEST_OFFSET +: DEST_WIDTH] = s_axis_tdest;
    if (USER_ENABLE) assign s_axis[USER_OFFSET +: USER_WIDTH] = mark_frame_reg ? USER_BAD_FRAME_VALUE : s_axis_tuser;
endgenerate

wire [WIDTH-1:0] m_axis = RAM_PIPELINE==0 ? mem_read_data : m_axis_pipe_reg[RAM_PIPELINE+1-1];

wire                   m_axis_tready_pipe;
wire                   m_axis_tvalid_pipe = m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1];

wire [DATA_WIDTH-1:0]  m_axis_tdata_pipe  = m_axis[DATA_WIDTH-1:0];
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_pipe  = KEEP_ENABLE ? m_axis[KEEP_OFFSET +: KEEP_WIDTH] : {KEEP_WIDTH{1'b1}};
wire                   m_axis_tlast_pipe  = LAST_ENABLE ? m_axis[LAST_OFFSET] | m_terminate_frame_reg : 1'b1;
wire [ID_WIDTH-1:0]    m_axis_tid_pipe    = ID_ENABLE   ? m_axis[ID_OFFSET +: ID_WIDTH] : {ID_WIDTH{1'b0}};
wire [DEST_WIDTH-1:0]  m_axis_tdest_pipe  = DEST_ENABLE ? m_axis[DEST_OFFSET +: DEST_WIDTH] : {DEST_WIDTH{1'b0}};
wire [USER_WIDTH-1:0]  m_axis_tuser_pipe  = USER_ENABLE ? (m_terminate_frame_reg ? USER_BAD_FRAME_VALUE : m_axis[USER_OFFSET +: USER_WIDTH]) : {USER_WIDTH{1'b0}};

wire                   m_axis_tready_out;
wire                   m_axis_tvalid_out;

wire [DATA_WIDTH-1:0]  m_axis_tdata_out;
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_out;
wire                   m_axis_tlast_out;
wire [ID_WIDTH-1:0]    m_axis_tid_out;
wire [DEST_WIDTH-1:0]  m_axis_tdest_out;
wire [USER_WIDTH-1:0]  m_axis_tuser_out;

wire pipe_ready;

assign s_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_reg, {CL_KEEP_WDITH{1'b0}}} : s_depth_reg;
assign s_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_commit_reg, {CL_KEEP_WDITH{1'b0}}} : s_depth_commit_reg;
assign s_status_overflow = overflow_reg;
assign s_status_bad_frame = bad_frame_reg;
assign s_status_good_frame = good_frame_reg;

assign m_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_reg, {CL_KEEP_WDITH{1'b0}}} : m_depth_reg;
assign m_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_commit_reg, {CL_KEEP_WDITH{1'b0}}} : m_depth_commit_reg;
assign m_status_overflow = overflow_sync3_reg ^ overflow_sync4_reg;
assign m_status_bad_frame = bad_frame_sync3_reg ^ bad_frame_sync4_reg;
assign m_status_good_frame = good_frame_sync3_reg ^ good_frame_sync4_reg;

// reset synchronization
always @(posedge m_clk or posedge m_rst) begin
    if (m_rst) begin
        s_rst_sync1_reg <= 1'b1;
    end else begin
        s_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge s_clk) begin
    s_rst_sync2_reg <= s_rst_sync1_reg;
    s_rst_sync3_reg <= s_rst_sync2_reg;
end

always @(posedge s_clk or posedge s_rst) begin
    if (s_rst) begin
        m_rst_sync1_reg <= 1'b1;
    end else begin
        m_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    m_rst_sync2_reg <= m_rst_sync1_reg;
    m_rst_sync3_reg <= m_rst_sync2_reg;
end

// Write logic
always @(posedge s_clk) begin
    overflow_reg <= 1'b0;
    bad_frame_reg <= 1'b0;
    good_frame_reg <= 1'b0;

    if (FRAME_FIFO && wr_ptr_update_valid_reg) begin
        // have updated pointer to sync
        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
            // no sync in progress; sync update
            wr_ptr_update_valid_reg <= 1'b0;
            wr_ptr_sync_commit_reg <= wr_ptr_commit_reg;
            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
        end
    end

    if (s_axis_tready && s_axis_tvalid && LAST_ENABLE) begin
        // track input frame status
        s_frame_reg <= !s_axis_tlast;
    end

    if (s_rst_sync3_reg && LAST_ENABLE) begin
        // if sink side is reset during transfer, drop partial frame
        if (s_frame_reg && !(s_axis_tready && s_axis_tvalid && s_axis_tlast)) begin
            drop_frame_reg <= 1'b1;
        end
        if (s_axis_tready && s_axis_tvalid && !s_axis_tlast) begin
            drop_frame_reg <= 1'b1;
        end
    end

    if (FRAME_FIFO) begin
        // frame FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            // transfer in
            if ((full && DROP_WHEN_FULL) || (full_wr && DROP_OVERSIZE_FRAME) || drop_frame_reg) begin
                // full, packet overflow, or currently dropping frame
                // drop frame
                drop_frame_reg <= 1'b1;
                if (s_axis_tlast) begin
                    // end of frame, reset write pointer
                    wr_ptr_temp = wr_ptr_commit_reg;
                    wr_ptr_reg <= wr_ptr_temp;
                    wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                if (s_axis_tlast || (!DROP_OVERSIZE_FRAME && (full_wr || send_frame_reg))) begin
                    // end of frame or send frame
                    send_frame_reg <= !s_axis_tlast;
                    if (s_axis_tlast && DROP_BAD_FRAME && USER_BAD_FRAME_MASK & ~(s_axis_tuser ^ USER_BAD_FRAME_VALUE)) begin
                        // bad packet, reset write pointer
                        wr_ptr_temp = wr_ptr_commit_reg;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                        bad_frame_reg <= 1'b1;
                    end else begin
                        // good packet or packet overflow, update write pointer
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

                        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                            // no sync in progress; sync update
                            wr_ptr_update_valid_reg <= 1'b0;
                            wr_ptr_sync_commit_reg <= wr_ptr_temp;
                            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
                        end else begin
                            // sync in progress; flag it for later
                            wr_ptr_update_valid_reg <= 1'b1;
                        end

                        good_frame_reg <= s_axis_tlast;
                    end
                end
            end
        end else if (s_axis_tvalid && full_wr && FRAME_FIFO && !DROP_OVERSIZE_FRAME) begin
            // data valid with packet overflow
            // update write pointer
            send_frame_reg <= 1'b1;
            wr_ptr_temp = wr_ptr_reg;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

            if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                // no sync in progress; sync update
                wr_ptr_update_valid_reg <= 1'b0;
                wr_ptr_sync_commit_reg <= wr_ptr_temp;
                wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
            end else begin
                // sync in progress; flag it for later
                wr_ptr_update_valid_reg <= 1'b1;
            end
        end
    end else begin
        // normal FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            if (drop_frame_reg && LAST_ENABLE) begin
                // currently dropping frame
                if (s_axis_tlast) begin
                    // end of frame
                    if (!full && mark_frame_reg && MARK_WHEN_FULL) begin
                        // terminate marked frame
                        mark_frame_reg <= 1'b0;
                        mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    end
                    // end of frame, clear drop flag
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else if ((full || mark_frame_reg) && MARK_WHEN_FULL) begin
                // full or marking frame
                // drop frame; mark if this isn't the first cycle
                drop_frame_reg <= 1'b1;
                mark_frame_reg <= mark_frame_reg || s_frame_reg;
                if (s_axis_tlast) begin
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                // transfer in
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_commit_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
            end
        end else if ((!full && !drop_frame_reg && mark_frame_reg) && MARK_WHEN_FULL) begin
            // terminate marked frame
            mark_frame_reg <= 1'b0;
            mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
            wr_ptr_temp = wr_ptr_reg + 1;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
        end
    end

    if (s_rst_sync3_reg) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;
    end

    if (s_rst) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;

        s_frame_reg <= 1'b0;

        drop_frame_reg <= 1'b0;
        mark_frame_reg <= 1'b0;
        send_frame_reg <= 1'b0;
        overflow_reg <= 1'b0;
        bad_frame_reg <= 1'b0;
        good_frame_reg <= 1'b0;
    end
end

// Write-side status
always @(posedge s_clk) begin
    rd_ptr_conv_reg <= gray2bin(rd_ptr_gray_sync2_reg);
    s_depth_reg <= wr_ptr_reg - rd_ptr_conv_reg;
    s_depth_commit_reg <= wr_ptr_commit_reg - rd_ptr_conv_reg;
end

// pointer synchronization
always @(posedge s_clk) begin
    rd_ptr_gray_sync1_reg <= rd_ptr_gray_reg;
    rd_ptr_gray_sync2_reg <= rd_ptr_gray_sync1_reg;
    wr_ptr_update_ack_sync1_reg <= wr_ptr_update_sync3_reg;
    wr_ptr_update_ack_sync2_reg <= wr_ptr_update_ack_sync1_reg;

    if (s_rst) begin
        rd_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_ack_sync1_reg <= 1'b0;
        wr_ptr_update_ack_sync2_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    wr_ptr_gray_sync1_reg <= wr_ptr_gray_reg;
    wr_ptr_gray_sync2_reg <= wr_ptr_gray_sync1_reg;
    if (FRAME_FIFO && wr_ptr_update_sync2_reg ^ wr_ptr_update_sync3_reg) begin
        wr_ptr_commit_sync_reg <= wr_ptr_sync_commit_reg;
    end
    wr_ptr_update_sync1_reg <= wr_ptr_update_reg;
    wr_ptr_update_sync2_reg <= wr_ptr_update_sync1_reg;
    wr_ptr_update_sync3_reg <= wr_ptr_update_sync2_reg;

    if (FRAME_FIFO && m_rst_sync3_reg) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_sync_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_sync1_reg <= 1'b0;
        wr_ptr_update_sync2_reg <= 1'b0;
        wr_ptr_update_sync3_reg <= 1'b0;
    end
end

// status synchronization
always @(posedge s_clk) begin
    overflow_sync1_reg <= overflow_sync1_reg ^ overflow_reg;
    bad_frame_sync1_reg <= bad_frame_sync1_reg ^ bad_frame_reg;
    good_frame_sync1_reg <= good_frame_sync1_reg ^ good_frame_reg;

    if (s_rst) begin
        overflow_sync1_reg <= 1'b0;
        bad_frame_sync1_reg <= 1'b0;
        good_frame_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    overflow_sync2_reg <= overflow_sync1_reg;
    overflow_sync3_reg <= overflow_sync2_reg;
    overflow_sync4_reg <= overflow_sync3_reg;
    bad_frame_sync2_reg <= bad_frame_sync1_reg;
    bad_frame_sync3_reg <= bad_frame_sync2_reg;
    bad_frame_sync4_reg <= bad_frame_sync3_reg;
    good_frame_sync2_reg <= good_frame_sync1_reg;
    good_frame_sync3_reg <= good_frame_sync2_reg;
    good_frame_sync4_reg <= good_frame_sync3_reg;

    if (m_rst) begin
        overflow_sync2_reg <= 1'b0;
        overflow_sync3_reg <= 1'b0;
        overflow_sync4_reg <= 1'b0;
        bad_frame_sync2_reg <= 1'b0;
        bad_frame_sync3_reg <= 1'b0;
        bad_frame_sync4_reg <= 1'b0;
        good_frame_sync2_reg <= 1'b0;
        good_frame_sync3_reg <= 1'b0;
        good_frame_sync4_reg <= 1'b0;
    end
end

// Read logic
integer j;

always @(posedge m_clk) begin
    if (m_axis_tready_pipe) begin
        // output ready; invalidate stage
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end

    for (j = RAM_PIPELINE+1-1; j > 0; j = j - 1) begin
        if (m_axis_tready_pipe || ((~m_axis_tvalid_pipe_reg) >> j)) begin
            // output ready or bubble in pipeline; transfer down pipeline
            m_axis_tvalid_pipe_reg[j] <= m_axis_tvalid_pipe_reg[j-1];
            m_axis_pipe_reg[j] <= j==1 ? mem_read_data : m_axis_pipe_reg[j-1];
            m_axis_tvalid_pipe_reg[j-1] <= 1'b0;
        end
    end

    if (m_axis_tready_pipe || ~m_axis_tvalid_pipe_reg) begin
        // output ready or bubble in pipeline; read new data from FIFO
        m_axis_tvalid_pipe_reg[0] <= 1'b0;
        mem_read_data <= mem[rd_ptr_reg[ADDR_WIDTH-1:0]];
        if (!empty && !m_rst_sync3_reg && !m_drop_frame_reg && pipe_ready) begin
            // not empty, increment pointer
            m_axis_tvalid_pipe_reg[0] <= 1'b1;
            rd_ptr_temp = rd_ptr_reg + 1;
            rd_ptr_reg <= rd_ptr_temp;
            rd_ptr_gray_reg <= rd_ptr_temp ^ (rd_ptr_temp >> 1);
        end
    end

    if (m_axis_tvalid_pipe && LAST_ENABLE) begin
        // track output frame status
        if (m_axis_tlast_pipe && m_axis_tready_pipe) begin
            m_frame_reg <= 1'b0;
        end else begin
            m_frame_reg <= 1'b1;
        end
    end

    if (m_drop_frame_reg && (OUTPUT_FIFO_ENABLE ? pipe_ready : m_axis_tready_pipe || !m_axis_tvalid_pipe) && LAST_ENABLE) begin
        // terminate frame
        // (only for frame transfers interrupted by source reset)
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b1;
        m_terminate_frame_reg <= 1'b1;
        m_drop_frame_reg <= 1'b0;
    end

    if (m_rst_sync3_reg && LAST_ENABLE) begin
        // if source side is reset during transfer, drop partial frame

        // empty output pipeline, except for last stage
        if (RAM_PIPELINE > 0) begin
            m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-2:0] <= 0;
        end

        if (m_frame_reg && (!m_axis_tvalid_pipe || (m_axis_tvalid_pipe && !m_axis_tlast_pipe)) &&
                !(m_drop_frame_reg || m_terminate_frame_reg)) begin
            // terminate frame
            m_drop_frame_reg <= 1'b1;
        end
    end

    if (m_rst_sync3_reg) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        m_axis_tvalid_pipe_reg <= 0;
        m_frame_reg <= 1'b0;
        m_drop_frame_reg <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end
end

// Read-side status
always @(posedge m_clk) begin
    wr_ptr_conv_reg <= gray2bin(wr_ptr_gray_sync2_reg);
    m_depth_reg <= wr_ptr_conv_reg - rd_ptr_reg;
    m_depth_commit_reg <= FRAME_FIFO ? wr_ptr_commit_sync_reg - rd_ptr_reg : wr_ptr_conv_reg - rd_ptr_reg;
end

generate

if (!OUTPUT_FIFO_ENABLE) begin

    assign pipe_ready = 1'b1;

    assign m_axis_tready_pipe = m_axis_tready_out;
    assign m_axis_tvalid_out = m_axis_tvalid_pipe;

    assign m_axis_tdata_out = m_axis_tdata_pipe;
    assign m_axis_tkeep_out = m_axis_tkeep_pipe;
    assign m_axis_tlast_out = m_axis_tlast_pipe;
    assign m_axis_tid_out   = m_axis_tid_pipe;
    assign m_axis_tdest_out = m_axis_tdest_pipe;
    assign m_axis_tuser_out = m_axis_tuser_pipe;

end else begin : output_fifo

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0;
    reg                  m_axis_tlast_reg  = 1'b0;
    reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
    reg out_fifo_half_full_reg = 1'b0;

    wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
    wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

    (* syn_ramstyle="lut_ram" *)
    reg [DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [KEEP_WIDTH-1:0] out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg                  out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [ID_WIDTH-1:0]   out_fifo_tid[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [DEST_WIDTH-1:0] out_fifo_tdest[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

    assign pipe_ready = !out_fifo_half_full_reg;

    assign m_axis_tready_pipe = 1'b1;

    assign m_axis_tdata_out  = m_axis_tdata_reg;
    assign m_axis_tkeep_out  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid_out = m_axis_tvalid_reg;
    assign m_axis_tlast_out  = LAST_ENABLE ? m_axis_tlast_reg : 1'b1;
    assign m_axis_tid_out    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest_out  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser_out  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge m_clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready_out;

        out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

        if (!out_fifo_full && m_axis_tvalid_pipe) begin
            out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdata_pipe;
            out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tkeep_pipe;
            out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlast_pipe;
            out_fifo_tid[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tid_pipe;
            out_fifo_tdest[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdest_pipe;
            out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tuser_pipe;
            out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
        end

        if (!out_fifo_empty && (!m_axis_tvalid_reg || m_axis_tready_out)) begin
            m_axis_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tvalid_reg <= 1'b1;
            m_axis_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tid_reg <= out_fifo_tid[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tdest_reg <= out_fifo_tdest[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        end

        if (m_rst) begin
            out_fifo_wr_ptr_reg <= 0;
            out_fifo_rd_ptr_reg <= 0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end

if (PAUSE_ENABLE) begin : pause

    // Pause logic
    reg pause_reg = 1'b0;
    reg pause_frame_reg = 1'b0;

    reg s_pause_req_sync1_reg;
    reg s_pause_req_sync2_reg;
    reg s_pause_req_sync3_reg;
    reg s_pause_ack_sync1_reg;
    reg s_pause_ack_sync2_reg;
    reg s_pause_ack_sync3_reg;

    always @(posedge s_clk) begin
        s_pause_req_sync1_reg <= s_pause_req;
        s_pause_ack_sync2_reg <= s_pause_ack_sync1_reg;
        s_pause_ack_sync3_reg <= s_pause_ack_sync2_reg;
    end

    always @(posedge m_clk) begin
        s_pause_req_sync2_reg <= s_pause_req_sync1_reg;
        s_pause_req_sync3_reg <= s_pause_req_sync2_reg;
        s_pause_ack_sync1_reg <= pause_reg;
    end

    assign m_axis_tready_out = m_axis_tready && !pause_reg;
    assign m_axis_tvalid = m_axis_tvalid_out && !pause_reg;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = s_pause_ack_sync3_reg;
    assign m_pause_ack = pause_reg;

    always @(posedge m_clk) begin
        if (FRAME_PAUSE) begin
            if (pause_reg) begin
                // paused; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end else if (m_axis_tvalid_out) begin
                // frame transfer; set frame bit
                pause_frame_reg <= 1'b1;
                if (m_axis_tready && m_axis_tlast) begin
                    // end of frame; clear frame bit and update pause status
                    pause_frame_reg <= 1'b0;
                    pause_reg <= m_pause_req || s_pause_req_sync3_reg;
                end
            end else if (!pause_frame_reg) begin
                // idle; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end
        end else begin
            pause_reg <= m_pause_req || s_pause_req_sync3_reg;
        end

        if (m_rst) begin
            pause_frame_reg <= 1'b0;
            pause_reg <= 1'b0;
        end
    end

end else begin

    assign m_axis_tready_out = m_axis_tready;
    assign m_axis_tvalid = m_axis_tvalid_out;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = 1'b0;
    assign m_pause_ack = 1'b0;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/hardware/pg100_network_async_fifo_adapter.v
/*

Copyright (c) 2019 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream asynchronous FIFO with width converter
 */
module pg100_network_async_fifo_adapter #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of input AXI stream interface in bits
    parameter S_DATA_WIDTH = 8,
    // Propagate tkeep signal on input interface
    // If disabled, tkeep assumed to be 1'b1
    parameter S_KEEP_ENABLE = (S_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on input interface
    parameter S_KEEP_WIDTH = ((S_DATA_WIDTH+7)/8),
    // Width of output AXI stream interface in bits
    parameter M_DATA_WIDTH = 8,
    // Propagate tkeep signal on output interface
    // If disabled, tkeep assumed to be 1'b1
    parameter M_KEEP_ENABLE = (M_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on output interface
    parameter M_KEEP_WIDTH = ((M_DATA_WIDTH+7)/8),
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers in FIFO
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    /*
     * AXI input
     */
    input  wire                     s_clk,
    input  wire                     s_rst,
    input  wire [S_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [S_KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,
    input  wire [ID_WIDTH-1:0]      s_axis_tid,
    input  wire [DEST_WIDTH-1:0]    s_axis_tdest,
    input  wire [USER_WIDTH-1:0]    s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                     m_clk,
    input  wire                     m_rst,
    output wire [M_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [M_KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast,
    output wire [ID_WIDTH-1:0]      m_axis_tid,
    output wire [DEST_WIDTH-1:0]    m_axis_tdest,
    output wire [USER_WIDTH-1:0]    m_axis_tuser,

    /*
     * Pause
     */
    input  wire                     s_pause_req,
    output wire                     s_pause_ack,
    input  wire                     m_pause_req,
    output wire                     m_pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0]   s_status_depth,
    output wire [$clog2(DEPTH):0]   s_status_depth_commit,
    output wire                     s_status_overflow,
    output wire                     s_status_bad_frame,
    output wire                     s_status_good_frame,
    output wire [$clog2(DEPTH):0]   m_status_depth,
    output wire [$clog2(DEPTH):0]   m_status_depth_commit,
    output wire                     m_status_overflow,
    output wire                     m_status_bad_frame,
    output wire                     m_status_good_frame
);

// force keep width to 1 when disabled
localparam S_BYTE_LANES = S_KEEP_ENABLE ? S_KEEP_WIDTH : 1;
localparam M_BYTE_LANES = M_KEEP_ENABLE ? M_KEEP_WIDTH : 1;

// bus byte sizes (must be identical)
localparam S_BYTE_SIZE = S_DATA_WIDTH / S_BYTE_LANES;
localparam M_BYTE_SIZE = M_DATA_WIDTH / M_BYTE_LANES;
// output bus is wider
localparam EXPAND_BUS = M_BYTE_LANES > S_BYTE_LANES;
// total data and keep widths
localparam DATA_WIDTH = EXPAND_BUS ? M_DATA_WIDTH : S_DATA_WIDTH;
localparam KEEP_WIDTH = EXPAND_BUS ? M_BYTE_LANES : S_BYTE_LANES;

// bus width assertions
initial begin
    if (S_BYTE_SIZE * S_BYTE_LANES != S_DATA_WIDTH) begin
        $display("Error: input data width not evenly divisible (instance %m)");
        $finish;
    end

    if (M_BYTE_SIZE * M_BYTE_LANES != M_DATA_WIDTH) begin
        $display("Error: output data width not evenly divisible (instance %m)");
        $finish;
    end

    if (S_BYTE_SIZE != M_BYTE_SIZE) begin
        $display("Error: byte size mismatch (instance %m)");
        $finish;
    end
end

wire [DATA_WIDTH-1:0]  pre_fifo_axis_tdata;
wire [KEEP_WIDTH-1:0]  pre_fifo_axis_tkeep;
wire                   pre_fifo_axis_tvalid;
wire                   pre_fifo_axis_tready;
wire                   pre_fifo_axis_tlast;
wire [ID_WIDTH-1:0]    pre_fifo_axis_tid;
wire [DEST_WIDTH-1:0]  pre_fifo_axis_tdest;
wire [USER_WIDTH-1:0]  pre_fifo_axis_tuser;

wire [DATA_WIDTH-1:0]  post_fifo_axis_tdata;
wire [KEEP_WIDTH-1:0]  post_fifo_axis_tkeep;
wire                   post_fifo_axis_tvalid;
wire                   post_fifo_axis_tready;
wire                   post_fifo_axis_tlast;
wire [ID_WIDTH-1:0]    post_fifo_axis_tid;
wire [DEST_WIDTH-1:0]  post_fifo_axis_tdest;
wire [USER_WIDTH-1:0]  post_fifo_axis_tuser;

generate

if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize_pre

    // output wider, adapt width before FIFO

    axis_adapter #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .S_KEEP_ENABLE(S_KEEP_ENABLE),
        .S_KEEP_WIDTH(S_KEEP_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
        .M_KEEP_ENABLE(M_KEEP_ENABLE),
        .M_KEEP_WIDTH(M_KEEP_WIDTH),
        .ID_ENABLE(ID_ENABLE),
        .ID_WIDTH(ID_WIDTH),
        .DEST_ENABLE(DEST_ENABLE),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(USER_ENABLE),
        .USER_WIDTH(USER_WIDTH)
    )
    adapter_inst (
        .clk(s_clk),
        .rst(s_rst),
        // AXI input
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(s_axis_tid),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tuser(s_axis_tuser),
        // AXI output
        .m_axis_tdata(pre_fifo_axis_tdata),
        .m_axis_tkeep(pre_fifo_axis_tkeep),
        .m_axis_tvalid(pre_fifo_axis_tvalid),
        .m_axis_tready(pre_fifo_axis_tready),
        .m_axis_tlast(pre_fifo_axis_tlast),
        .m_axis_tid(pre_fifo_axis_tid),
        .m_axis_tdest(pre_fifo_axis_tdest),
        .m_axis_tuser(pre_fifo_axis_tuser)
    );

end else begin : bypass_pre

    assign pre_fifo_axis_tdata = s_axis_tdata;
    assign pre_fifo_axis_tkeep = s_axis_tkeep;
    assign pre_fifo_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = pre_fifo_axis_tready;
    assign pre_fifo_axis_tlast = s_axis_tlast;
    assign pre_fifo_axis_tid = s_axis_tid;
    assign pre_fifo_axis_tdest = s_axis_tdest;
    assign pre_fifo_axis_tuser = s_axis_tuser;

end

pg100_network_async_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(EXPAND_BUS ? M_KEEP_ENABLE : S_KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH),
    .LAST_ENABLE(1),
    .ID_ENABLE(ID_ENABLE),
    .ID_WIDTH(ID_WIDTH),
    .DEST_ENABLE(DEST_ENABLE),
    .DEST_WIDTH(DEST_WIDTH),
    .USER_ENABLE(USER_ENABLE),
    .USER_WIDTH(USER_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .OUTPUT_FIFO_ENABLE(OUTPUT_FIFO_ENABLE),
    .FRAME_FIFO(FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(USER_BAD_FRAME_VALUE),
    .USER_BAD_FRAME_MASK(USER_BAD_FRAME_MASK),
    .DROP_OVERSIZE_FRAME(DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(DROP_BAD_FRAME),
    .DROP_WHEN_FULL(DROP_WHEN_FULL),
    .MARK_WHEN_FULL(MARK_WHEN_FULL),
    .PAUSE_ENABLE(PAUSE_ENABLE),
    .FRAME_PAUSE(FRAME_PAUSE)
)
fifo_inst (
    // AXI input
    .s_clk(s_clk),
    .s_rst(s_rst),
    .s_axis_tdata(pre_fifo_axis_tdata),
    .s_axis_tkeep(pre_fifo_axis_tkeep),
    .s_axis_tvalid(pre_fifo_axis_tvalid),
    .s_axis_tready(pre_fifo_axis_tready),
    .s_axis_tlast(pre_fifo_axis_tlast),
    .s_axis_tid(pre_fifo_axis_tid),
    .s_axis_tdest(pre_fifo_axis_tdest),
    .s_axis_tuser(pre_fifo_axis_tuser),
    // AXI output
    .m_clk(m_clk),
    .m_rst(m_rst),
    .m_axis_tdata(post_fifo_axis_tdata),
    .m_axis_tkeep(post_fifo_axis_tkeep),
    .m_axis_tvalid(post_fifo_axis_tvalid),
    .m_axis_tready(post_fifo_axis_tready),
    .m_axis_tlast(post_fifo_axis_tlast),
    .m_axis_tid(post_fifo_axis_tid),
    .m_axis_tdest(post_fifo_axis_tdest),
    .m_axis_tuser(post_fifo_axis_tuser),
    // Pause
    .s_pause_req(s_pause_req),
    .s_pause_ack(s_pause_ack),
    .m_pause_req(m_pause_req),
    .m_pause_ack(m_pause_ack),
    // Status
    .s_status_depth(s_status_depth),
    .s_status_depth_commit(s_status_depth_commit),
    .s_status_overflow(s_status_overflow),
    .s_status_bad_frame(s_status_bad_frame),
    .s_status_good_frame(s_status_good_frame),
    .m_status_depth(m_status_depth),
    .m_status_depth_commit(m_status_depth_commit),
    .m_status_overflow(m_status_overflow),
    .m_status_bad_frame(m_status_bad_frame),
    .m_status_good_frame(m_status_good_frame)
);

if (M_BYTE_LANES < S_BYTE_LANES) begin : downsize_post

    // input wider, adapt width after FIFO

    axis_adapter #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .S_KEEP_ENABLE(S_KEEP_ENABLE),
        .S_KEEP_WIDTH(S_KEEP_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
        .M_KEEP_ENABLE(M_KEEP_ENABLE),
        .M_KEEP_WIDTH(M_KEEP_WIDTH),
        .ID_ENABLE(ID_ENABLE),
        .ID_WIDTH(ID_WIDTH),
        .DEST_ENABLE(DEST_ENABLE),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(USER_ENABLE),
        .USER_WIDTH(USER_WIDTH)
    )
    adapter_inst (
        .clk(m_clk),
        .rst(m_rst),
        // AXI input
        .s_axis_tdata(post_fifo_axis_tdata),
        .s_axis_tkeep(post_fifo_axis_tkeep),
        .s_axis_tvalid(post_fifo_axis_tvalid),
        .s_axis_tready(post_fifo_axis_tready),
        .s_axis_tlast(post_fifo_axis_tlast),
        .s_axis_tid(post_fifo_axis_tid),
        .s_axis_tdest(post_fifo_axis_tdest),
        .s_axis_tuser(post_fifo_axis_tuser),
        // AXI output
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tid(m_axis_tid),
        .m_axis_tdest(m_axis_tdest),
        .m_axis_tuser(m_axis_tuser)
    );

end else begin : bypass_post

    assign m_axis_tdata = post_fifo_axis_tdata;
    assign m_axis_tkeep = post_fifo_axis_tkeep;
    assign m_axis_tvalid = post_fifo_axis_tvalid;
    assign post_fifo_axis_tready = m_axis_tready;
    assign m_axis_tlast = post_fifo_axis_tlast;
    assign m_axis_tid = post_fifo_axis_tid;
    assign m_axis_tdest = post_fifo_axis_tdest;
    assign m_axis_tuser = post_fifo_axis_tuser;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/hardware/pg100_network_eth_mac_1g_fifo.v
/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 1G Ethernet MAC with TX and RX FIFOs
 */
module pg100_network_eth_mac_1g_fifo #
(
    parameter AXIS_DATA_WIDTH = 8,
    parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
    parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
    parameter ENABLE_PADDING = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter TX_FIFO_DEPTH = 4096,
    parameter TX_FIFO_RAM_PIPELINE = 1,
    parameter TX_FRAME_FIFO = 1,
    parameter TX_DROP_OVERSIZE_FRAME = TX_FRAME_FIFO,
    parameter TX_DROP_BAD_FRAME = TX_DROP_OVERSIZE_FRAME,
    parameter TX_DROP_WHEN_FULL = 0,
    parameter RX_FIFO_DEPTH = 4096,
    parameter RX_FIFO_RAM_PIPELINE = 1,
    parameter RX_FRAME_FIFO = 1,
    parameter RX_DROP_OVERSIZE_FRAME = RX_FRAME_FIFO,
    parameter RX_DROP_BAD_FRAME = RX_DROP_OVERSIZE_FRAME,
    parameter RX_DROP_WHEN_FULL = RX_DROP_OVERSIZE_FRAME
)
(
    input  wire                       rx_clk,
    input  wire                       rx_rst,
    input  wire                       tx_clk,
    input  wire                       tx_rst,
    input  wire                       logic_clk,
    input  wire                       logic_rst,

    /*
     * AXI input
     */
    input  wire [AXIS_DATA_WIDTH-1:0] tx_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0] tx_axis_tkeep,
    input  wire                       tx_axis_tvalid,
    output wire                       tx_axis_tready,
    input  wire                       tx_axis_tlast,
    input  wire                       tx_axis_tuser,

    /*
     * AXI output
     */
    output wire [AXIS_DATA_WIDTH-1:0] rx_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] rx_axis_tkeep,
    output wire                       rx_axis_tvalid,
    input  wire                       rx_axis_tready,
    output wire                       rx_axis_tlast,
    output wire                       rx_axis_tuser,

    /*
     * GMII interface
     */
    input  wire [7:0]                 gmii_rxd,
    input  wire                       gmii_rx_dv,
    input  wire                       gmii_rx_er,
    output wire [7:0]                 gmii_txd,
    output wire                       gmii_tx_en,
    output wire                       gmii_tx_er,

    /*
     * Control
     */
    input  wire                       rx_clk_enable,
    input  wire                       tx_clk_enable,
    input  wire                       rx_mii_select,
    input  wire                       tx_mii_select,

    /*
     * Status
     */
    output wire                       tx_error_underflow,
    output wire                       tx_fifo_overflow,
    output wire                       tx_fifo_bad_frame,
    output wire                       tx_fifo_good_frame,
    output wire                       rx_error_bad_frame,
    output wire                       rx_error_bad_fcs,
    output wire                       rx_fifo_overflow,
    output wire                       rx_fifo_bad_frame,
    output wire                       rx_fifo_good_frame,

    /*
     * Configuration
     */
    input  wire [7:0]                 cfg_ifg,
    input  wire                       cfg_tx_enable,
    input  wire                       cfg_rx_enable
);

wire [7:0]  tx_fifo_axis_tdata;
wire        tx_fifo_axis_tvalid;
wire        tx_fifo_axis_tready;
wire        tx_fifo_axis_tlast;
wire        tx_fifo_axis_tuser;

wire [7:0]  rx_fifo_axis_tdata;
wire        rx_fifo_axis_tvalid;
wire        rx_fifo_axis_tlast;
wire        rx_fifo_axis_tuser;

// synchronize MAC status signals into logic clock domain
wire tx_error_underflow_int;

reg [0:0] tx_sync_reg_1 = 1'b0;
reg [0:0] tx_sync_reg_2 = 1'b0;
reg [0:0] tx_sync_reg_3 = 1'b0;
reg [0:0] tx_sync_reg_4 = 1'b0;

assign tx_error_underflow = tx_sync_reg_3[0] ^ tx_sync_reg_4[0];

always @(posedge tx_clk or posedge tx_rst) begin
    if (tx_rst) begin
        tx_sync_reg_1 <= 1'b0;
    end else begin
        tx_sync_reg_1 <= tx_sync_reg_1 ^ {tx_error_underflow_int};
    end
end

always @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        tx_sync_reg_2 <= 1'b0;
        tx_sync_reg_3 <= 1'b0;
        tx_sync_reg_4 <= 1'b0;
    end else begin
        tx_sync_reg_2 <= tx_sync_reg_1;
        tx_sync_reg_3 <= tx_sync_reg_2;
        tx_sync_reg_4 <= tx_sync_reg_3;
    end
end

wire rx_error_bad_frame_int;
wire rx_error_bad_fcs_int;

reg [1:0] rx_sync_reg_1 = 2'd0;
reg [1:0] rx_sync_reg_2 = 2'd0;
reg [1:0] rx_sync_reg_3 = 2'd0;
reg [1:0] rx_sync_reg_4 = 2'd0;

assign rx_error_bad_frame = rx_sync_reg_3[0] ^ rx_sync_reg_4[0];
assign rx_error_bad_fcs = rx_sync_reg_3[1] ^ rx_sync_reg_4[1];

always @(posedge rx_clk or posedge rx_rst) begin
    if (rx_rst) begin
        rx_sync_reg_1 <= 2'd0;
    end else begin
        rx_sync_reg_1 <= rx_sync_reg_1 ^ {rx_error_bad_fcs_int, rx_error_bad_frame_int};
    end
end

always @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        rx_sync_reg_2 <= 2'd0;
        rx_sync_reg_3 <= 2'd0;
        rx_sync_reg_4 <= 2'd0;
    end else begin
        rx_sync_reg_2 <= rx_sync_reg_1;
        rx_sync_reg_3 <= rx_sync_reg_2;
        rx_sync_reg_4 <= rx_sync_reg_3;
    end
end

eth_mac_1g #(
    .ENABLE_PADDING(ENABLE_PADDING),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH)
)
eth_mac_1g_inst (
    .tx_clk(tx_clk),
    .tx_rst(tx_rst),
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),
    .tx_axis_tdata(tx_fifo_axis_tdata),
    .tx_axis_tvalid(tx_fifo_axis_tvalid),
    .tx_axis_tready(tx_fifo_axis_tready),
    .tx_axis_tlast(tx_fifo_axis_tlast),
    .tx_axis_tuser(tx_fifo_axis_tuser),
    .rx_axis_tdata(rx_fifo_axis_tdata),
    .rx_axis_tvalid(rx_fifo_axis_tvalid),
    .rx_axis_tlast(rx_fifo_axis_tlast),
    .rx_axis_tuser(rx_fifo_axis_tuser),
    .gmii_rxd(gmii_rxd),
    .gmii_rx_dv(gmii_rx_dv),
    .gmii_rx_er(gmii_rx_er),
    .gmii_txd(gmii_txd),
    .gmii_tx_en(gmii_tx_en),
    .gmii_tx_er(gmii_tx_er),
    .rx_clk_enable(rx_clk_enable),
    .tx_clk_enable(tx_clk_enable),
    .rx_mii_select(rx_mii_select),
    .tx_mii_select(tx_mii_select),
    .tx_error_underflow(tx_error_underflow_int),
    .rx_error_bad_frame(rx_error_bad_frame_int),
    .rx_error_bad_fcs(rx_error_bad_fcs_int),
    .cfg_ifg(cfg_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .cfg_rx_enable(cfg_rx_enable)
);

pg100_network_async_fifo_adapter #(
    .DEPTH(TX_FIFO_DEPTH),
    .S_DATA_WIDTH(AXIS_DATA_WIDTH),
    .S_KEEP_ENABLE(AXIS_KEEP_ENABLE),
    .S_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .M_DATA_WIDTH(8),
    .M_KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(TX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(TX_DROP_WHEN_FULL)
)
tx_fifo (
    // AXI input
    .s_clk(logic_clk),
    .s_rst(logic_rst),
    .s_axis_tdata(tx_axis_tdata),
    .s_axis_tkeep(tx_axis_tkeep),
    .s_axis_tvalid(tx_axis_tvalid),
    .s_axis_tready(tx_axis_tready),
    .s_axis_tlast(tx_axis_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(tx_axis_tuser),
    // AXI output
    .m_clk(tx_clk),
    .m_rst(tx_rst),
    .m_axis_tdata(tx_fifo_axis_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(tx_fifo_axis_tvalid),
    .m_axis_tready(tx_fifo_axis_tready),
    .m_axis_tlast(tx_fifo_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(tx_fifo_axis_tuser),
    // Status
    .s_status_overflow(tx_fifo_overflow),
    .s_status_bad_frame(tx_fifo_bad_frame),
    .s_status_good_frame(tx_fifo_good_frame),
    .m_status_overflow(),
    .m_status_bad_frame(),
    .m_status_good_frame()
);

pg100_network_async_fifo_adapter #(
    .DEPTH(RX_FIFO_DEPTH),
    .S_DATA_WIDTH(8),
    .S_KEEP_ENABLE(0),
    .M_DATA_WIDTH(AXIS_DATA_WIDTH),
    .M_KEEP_ENABLE(AXIS_KEEP_ENABLE),
    .M_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(RX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(RX_DROP_WHEN_FULL)
)
rx_fifo (
    // AXI input
    .s_clk(rx_clk),
    .s_rst(rx_rst),
    .s_axis_tdata(rx_fifo_axis_tdata),
    .s_axis_tkeep(0),
    .s_axis_tvalid(rx_fifo_axis_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(rx_fifo_axis_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(rx_fifo_axis_tuser),
    // AXI output
    .m_clk(logic_clk),
    .m_rst(logic_rst),
    .m_axis_tdata(rx_axis_tdata),
    .m_axis_tkeep(rx_axis_tkeep),
    .m_axis_tvalid(rx_axis_tvalid),
    .m_axis_tready(rx_axis_tready),
    .m_axis_tlast(rx_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(rx_axis_tuser),
    // Status
    .s_status_overflow(),
    .s_status_bad_frame(),
    .s_status_good_frame(),
    .m_status_overflow(rx_fifo_overflow),
    .m_status_bad_frame(rx_fifo_bad_frame),
    .m_status_good_frame(rx_fifo_good_frame)
);

endmodule

`resetall

// Source snapshot: rtl/video/pg100_hdmi_frontend.v
// Board-facing HDMI wrapper; external AC I/O timing still requires SW38 signoff.
// PHY/G25 is owned here ONCE; an integrated top must share this output with PHY.
module pg100_hdmi_frontend(
    input wire clk27,por_n,hard_reset_request,netclk,
    input wire rx_pclk,
    input wire [23:0] rx_rgb,
    input wire rx_hs,rx_vs,rx_de,
    input wire rgb888_format_confirmed,pixel_storage_overflow,
    inout wire hd_scl,hd_sda,
    output wire shared_rst_n,ctrl_rst_n,pixel_rst_n,net_rst_n,
    output wire tx_pclk,
    output wire [23:0] tx_rgb,
    output wire tx_hs,tx_vs,tx_de,
    output wire pixel_clock_good,init_done,init_failed,
    output wire [2:0] i2c_failure_code,
    output wire [31:0] i2c_retry_count,pixel_clock_loss_count,
    output wire [15:0] measured_pclk_edges,
    output wire [31:0] dbg_frame_cycles,
    output wire [12:0] dbg_active_lines,
    output wire [15:0] dbg_line_cycles,
    output wire dbg_bad_frame,
    output wire [3:0] dbg_sync,
    output wire [15:0] dbg_vs_count,
    output wire dbg_ready,
    output wire [7:0] dbg_bad_reason,
    output wire [3:0] dbg_commit_reason,
    output wire [7:0] dbg_freq_value,
    output wire [15:0] dbg_freq_tries,
    output wire [3:0] dbg_freq_state,
    output wire dbg_freq_forced,
    output reg [31:0] dbg_rx_vs_cnt,
    output reg [31:0] dbg_rx_hs_cnt,
    output reg [31:0] dbg_rx_de_cnt,
    output reg [31:0] dbg_rx_de_high,
    output wire [23:0] pix_rgb,
    output wire pix_valid,pix_sof,pix_eol,pix_eof,
    output wire [11:0] pix_x,pix_y,
    output wire frame_start,frame_end,frame_commit,frame_discard,
    output wire [31:0] capture_tag,commit_tag,
    output wire [31:0] captured_frames,discarded_frames,
    output wire [7:0] mono,
    output wire mono_valid,mono_mask,mono_sof,mono_eol,mono_eof,
    output wire [8:0] work_x,
    output wire [7:0] work_y
);
    wire[15:0]edges;wire[31:0]losses;
    pg100_board_reset reset_owner(.clk27(clk27),.por_n(por_n),.hard_reset_request(hard_reset_request),
        .pclk(rx_pclk),.netclk(netclk),.shared_rst_n(shared_rst_n),.ctrl_rst_n(ctrl_rst_n),
        .pixel_rst_n(pixel_rst_n),.net_rst_n(net_rst_n),.pixel_clock_good(pixel_clock_good),
        .measured_edges(edges),.clock_loss_count(losses));
    // 1080p60 gives ~580 edges/ms, 1080p30 ~290. Decimate 60 to 30 for the
    // native 125MHz core; the hdmi_pclk passthrough still runs at 60.
    wire rate60=edges>16'd400;
    reg[2:0]rate60_sync;
    always @(posedge rx_pclk or negedge pixel_rst_n)
        if(!pixel_rst_n)rate60_sync<=0;else rate60_sync<={rate60_sync[1:0],rate60};
    wire[2:0]error;wire[31:0]retries;wire busy,sl,sdl;
    // RX watchdog: a reconfiguration or source glitch can leave the HDMI
    // receiver unlocked with no VS. Re-run the receiver I2C init after 2 s of
    // VS inactivity so the passthrough and capture recover without a board
    // power cycle.
    reg[2:0]de_sync27;reg de_d27;reg[26:0]de_idle;reg[18:0]reinit_hold;reg reinit_pulse;
    always @(posedge clk27 or negedge por_n)begin
        if(!por_n)begin de_sync27<=0;de_d27<=0;de_idle<=0;reinit_hold<=0;reinit_pulse<=0;end
        else begin
            de_sync27<={de_sync27[1:0],rx_de};
            if(reinit_pulse)begin
                if(reinit_hold==19'd270000)begin reinit_pulse<=0;reinit_hold<=0;end
                else reinit_hold<=reinit_hold+1'b1;
            end else if(de_sync27[2]!=de_d27)begin
                de_d27<=de_sync27[2];de_idle<=0;
            end else if(de_idle<27'd27000000)de_idle<=de_idle+1'b1;
            else if(init_done)begin de_idle<=0;reinit_hold<=0;reinit_pulse<=1;end
        end
    end
    // Stage-2 observation: raw RX sync counters in the pclk domain, latched by
    // a toggle handshake into clk27 so the native snapshot never samples a
    // changing multi-bit counter directly.
    reg [31:0] rx_vs_cnt,rx_hs_cnt,rx_de_cnt,rx_de_high;
    reg rx_vs_q,rx_hs_q,rx_de_q;
    reg [24:0] snap_timer;reg snap_toggle;
    reg snap_req_s1,snap_req_s2,snap_req_d;reg snap_ack;
    reg [31:0] hold_vs,hold_hs,hold_de,hold_high;
    reg snap_ack_s1,snap_ack_s2,snap_ack_d;
    always @(posedge rx_pclk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            rx_vs_cnt<=0;rx_hs_cnt<=0;rx_de_cnt<=0;rx_de_high<=0;
            rx_vs_q<=0;rx_hs_q<=0;rx_de_q<=0;
            snap_req_s1<=0;snap_req_s2<=0;snap_req_d<=0;snap_ack<=0;
            hold_vs<=0;hold_hs<=0;hold_de<=0;hold_high<=0;
        end else begin
            rx_vs_q<=rx_vs;rx_hs_q<=rx_hs;rx_de_q<=rx_de;
            if(rx_vs&&!rx_vs_q)rx_vs_cnt<=rx_vs_cnt+1'b1;
            if(rx_hs&&!rx_hs_q)rx_hs_cnt<=rx_hs_cnt+1'b1;
            if(rx_de&&!rx_de_q)rx_de_cnt<=rx_de_cnt+1'b1;
            if(rx_de)rx_de_high<=rx_de_high+1'b1;
            snap_req_s1<=snap_toggle;snap_req_s2<=snap_req_s1;
            if(snap_req_s2!=snap_req_d)begin
                snap_req_d<=snap_req_s2;
                hold_vs<=rx_vs_cnt;hold_hs<=rx_hs_cnt;hold_de<=rx_de_cnt;hold_high<=rx_de_high;
                snap_ack<=!snap_ack;
            end
        end
    end
    always @(posedge clk27 or negedge por_n) begin
        if(!por_n) begin
            snap_timer<=0;snap_toggle<=0;snap_ack_s1<=0;snap_ack_s2<=0;snap_ack_d<=0;
            dbg_rx_vs_cnt<=0;dbg_rx_hs_cnt<=0;dbg_rx_de_cnt<=0;dbg_rx_de_high<=0;
        end else begin
            if(snap_timer==25'd13499999)begin snap_timer<=0;snap_toggle<=!snap_toggle;end
            else snap_timer<=snap_timer+1'b1;
            snap_ack_s1<=snap_ack;snap_ack_s2<=snap_ack_s1;
            if(snap_ack_s2!=snap_ack_d)begin
                snap_ack_d<=snap_ack_s2;
                dbg_rx_vs_cnt<=hold_vs;dbg_rx_hs_cnt<=hold_hs;dbg_rx_de_cnt<=hold_de;dbg_rx_de_high<=hold_high;
            end
        end
    end
    assign i2c_failure_code=error;assign i2c_retry_count=retries;
    assign pixel_clock_loss_count=losses;assign measured_pclk_edges=edges;
    pg100_hdmi_config config_owner(.clk27(clk27),.rst_n(ctrl_rst_n),.reinitialize(reinit_pulse),.scl(hd_scl),.sda(hd_sda),
        .init_done(init_done),.init_failed(init_failed),.failure_code(error),.retry_count(retries),
        .dbg_freq_value(dbg_freq_value),.dbg_freq_tries(dbg_freq_tries),.dbg_freq_state(dbg_freq_state),.dbg_freq_forced(dbg_freq_forced),
        .scl_drive_low(sl),.sda_drive_low(sdl),.bus_busy(busy));
    reg[2:0]config_sync,format_sync;
    always @(posedge rx_pclk or negedge pixel_rst_n)
        if(!pixel_rst_n)begin config_sync<=0;format_sync<=0;end
        else begin config_sync<={config_sync[1:0],init_done};format_sync<={format_sync[1:0],rgb888_format_confirmed};end
    wire ready_rgb=config_sync[2] && format_sync[2];
    assign dbg_ready=ready_rgb;
    reg tx_active,vs_d;
    always @(posedge rx_pclk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin tx_active<=0;vs_d<=0;end
        else begin
            vs_d<=rx_vs;
            if(!ready_rgb)tx_active<=0;
            else if(rx_vs && !vs_d)tx_active<=1;
        end
    end
    wire bad;
    pg100_hdmi_capture capture(.pclk(rx_pclk),.rst_n(pixel_rst_n),.link_locked(ready_rgb),
        .rgb888_format(format_sync[2]),.overflow(pixel_storage_overflow),.frame_skip(rate60_sync[2]),
        .rgb_in(rx_rgb),.hs_in(rx_hs),.vs_in(rx_vs),.de_in(rx_de),
        .rgb(pix_rgb),.pixel_valid(pix_valid),.sof(pix_sof),.eol(pix_eol),.eof(pix_eof),.x(pix_x),.y(pix_y),
        .frame_start(frame_start),.frame_end(frame_end),.frame_commit(frame_commit),.frame_discard(frame_discard),
        .captured_frames(captured_frames),.discarded_frames(discarded_frames),.capture_tag(capture_tag),
        .commit_tag(commit_tag),.bad_frame(bad),
        .dbg_frame_cycles(dbg_frame_cycles),.dbg_active_lines(dbg_active_lines),.dbg_line_cycles(dbg_line_cycles),
        .dbg_bad_frame(dbg_bad_frame),.dbg_sync(dbg_sync),.dbg_vs_count(dbg_vs_count),.dbg_bad_reason(dbg_bad_reason),.dbg_commit_reason(dbg_commit_reason));
    pg100_rgb_tx normal_tx(.pclk(rx_pclk),.rst_n(pixel_rst_n),.enable(tx_active && ready_rgb),
        .rgb_in(rx_rgb),.hs_in(rx_hs),.vs_in(rx_vs),.de_in(rx_de),
        .rgb_out(tx_rgb),.hs_out(tx_hs),.vs_out(tx_vs),.de_out(tx_de));
    // Actual PCLK forwarded continuously; use device output-clock primitive and
    // AC min/max constraints in the final physical top. No fabricated PLL ratio.
    assign tx_pclk=rx_pclk;
    pg100_mono_sampler work_branch(.pclk(rx_pclk),.rst_n(pixel_rst_n),.frame_start(frame_start),
        .pixel_valid(pix_valid),.rgb(pix_rgb),.x(pix_x),.y(pix_y),.mono_valid(mono_valid),.mono(mono),
        .work_x(work_x),.work_y(work_y),.mask(mono_mask),.mono_sof(mono_sof),.mono_eol(mono_eol),.mono_eof(mono_eof));
endmodule

// Source snapshot: rtl/video/pg100_hdmi_capture.v
// MS7200 RGB888 SDR capture. Speculative pixels require frame_commit before use.
// SOF/EOL/EOF delimit storage only; source identity comes from the PGM1 decoder.
module pg100_hdmi_capture #(
    parameter WIDTH=1920, HEIGHT=1080, HTOTAL=2200, VTOTAL=1125
)(
    input wire pclk, rst_n, link_locked, rgb888_format, overflow, frame_skip,
    input wire [23:0] rgb_in,
    input wire hs_in, vs_in, de_in,
    output reg [23:0] rgb,
    output reg pixel_valid, sof, eol, eof,
    output reg [11:0] x, y,
    output reg frame_start, frame_end, frame_commit, frame_discard,
    output reg [31:0] captured_frames, discarded_frames,
    output reg [31:0] capture_tag, commit_tag,
    output reg bad_frame,
    output reg [31:0] dbg_frame_cycles,
    output reg [12:0] dbg_active_lines,
    output reg [15:0] dbg_line_cycles,
    output reg dbg_bad_frame,
    output reg [3:0] dbg_sync,
    output reg [15:0] dbg_vs_count,
    output reg [7:0] dbg_bad_reason,
    output reg [3:0] dbg_commit_reason
);
    reg hs_d, vs_d, de_d, active, line_seen, hs_seen, start_pending, skip_toggle;
    reg [12:0] line_pixels, active_lines;
    reg [31:0] frame_cycles;
    reg [15:0] line_cycles;
    reg [7:0] bad_reason;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hs_d<=0; vs_d<=0; de_d<=0; active<=0; line_seen<=0; hs_seen<=0;start_pending<=0;skip_toggle<=0;
            line_pixels<=0; active_lines<=0; frame_cycles<=0; line_cycles<=0;
            rgb<=0; pixel_valid<=0; sof<=0; eol<=0; eof<=0; x<=0; y<=0;
            frame_start<=0; frame_end<=0; frame_commit<=0; frame_discard<=0;
            captured_frames<=0; discarded_frames<=0; capture_tag<=0;commit_tag<=0; bad_frame<=0;
            dbg_frame_cycles<=0; dbg_active_lines<=0; dbg_line_cycles<=0; dbg_bad_frame<=0; dbg_sync<=0; dbg_vs_count<=0;
            bad_reason<=0; dbg_bad_reason<=0; dbg_commit_reason<=0;
        end else begin
            hs_d<=hs_in; vs_d<=vs_in; de_d<=de_in;
            if (vs_in && !vs_d) dbg_vs_count<=dbg_vs_count+1'b1;
            pixel_valid<=0; sof<=0; eol<=0; eof<=0;
            frame_start<=start_pending;start_pending<=0; frame_end<=0; frame_commit<=0; frame_discard<=0;
            if (!link_locked || !rgb888_format) begin
                if (active) begin
                    frame_end<=1;commit_tag<=capture_tag; frame_discard<=1; discarded_frames<=discarded_frames+1'b1;
                end
                active<=0; bad_frame<=1; line_seen<=0; hs_seen<=0;start_pending<=0;frame_start<=0;
                line_pixels<=0; active_lines<=0; frame_cycles<=0; line_cycles<=0;
            end else if (vs_in && !vs_d) begin
                dbg_frame_cycles<=frame_cycles;
                dbg_active_lines<=active_lines;
                dbg_line_cycles<=line_cycles;
                dbg_bad_frame<=bad_frame;
                dbg_sync<={de_in,de_d,hs_in,vs_in};
                dbg_bad_reason<=bad_reason;
                if (active) begin
                    dbg_commit_reason<={1'b0,
                        (frame_cycles<32'd2000000||frame_cycles>32'd2800000),
                        (active_lines<12'd1000||active_lines>12'd1088),
                        1'b0};
                    frame_end<=1;commit_tag<=capture_tag;
                    if (!bad_frame && !overflow &&
                        active_lines>=12'd1000 && active_lines<=12'd1088 &&
                        frame_cycles>=32'd2000000 &&
                        frame_cycles<=32'd2800000) begin
                        frame_commit<=1; captured_frames<=captured_frames+1'b1;
                    end else begin
                        frame_discard<=1; discarded_frames<=discarded_frames+1'b1;
                    end
                end
                if (frame_skip && skip_toggle) begin
                    skip_toggle<=1'b0;
                    active<=0; start_pending<=0; bad_frame<=1'b0; bad_reason<=8'b0; dbg_commit_reason<=0;
                    line_pixels<=0; active_lines<=0; frame_cycles<=0;
                    line_cycles<=0; hs_seen<=1'b0; line_seen<=0;
                end else begin
                    skip_toggle<=frame_skip;
                    active<=1; start_pending<=1; capture_tag<=capture_tag+1'b1;
                    bad_frame<=overflow; bad_reason<=de_in ? 8'h40 : 8'h00;
                    line_pixels<=0; active_lines<=0; frame_cycles<=0;
                    line_cycles<=0; hs_seen<=hs_in && !hs_d; line_seen<=0;
                end
            end else if (active) begin
                if (frame_cycles<32'd2600000) frame_cycles<=frame_cycles+1'b1;
                else bad_reason[5]<=1'b1;
                if (line_cycles<HTOTAL+64) line_cycles<=line_cycles+1'b1;
                else bad_reason[5]<=1'b1;
                if (overflow) begin bad_frame<=1; bad_reason[7]<=1'b1; end
                if (de_in && (vs_in || hs_in)) bad_reason[0]<=1'b1;
                if (hs_in && !hs_d) begin
                    if (hs_seen && (line_cycles<HTOTAL-64 || line_cycles>HTOTAL+64)) bad_reason[4]<=1'b1;
                    if (de_in || de_d) bad_reason[1]<=1'b1;
                    hs_seen<=1; line_cycles<=0; line_seen<=0;
                end
                if (de_in) begin
                    if (!de_d) begin
                        if (line_seen || active_lines>=HEIGHT || !hs_seen) bad_reason[3]<=1'b1;
                        line_seen<=1; line_pixels<=1;
                        x<=0; y<=active_lines[11:0]; sof<=active_lines==0;
                        pixel_valid<=!bad_frame && !overflow && !line_seen && active_lines<HEIGHT;
                    end else begin
                        if (line_pixels<WIDTH+1) line_pixels<=line_pixels+1'b1;
                        if (line_pixels>=WIDTH) bad_reason[2]<=1'b1;
                        x<=line_pixels[11:0]; y<=active_lines[11:0];
                        pixel_valid<=!bad_frame && !overflow && line_pixels<WIDTH && active_lines<HEIGHT;
                    end
                    rgb<=rgb_in;
                    eol<=((!de_d && WIDTH==1) || (de_d && line_pixels==WIDTH-1));
                    eof<=((!de_d && WIDTH==1) || (de_d && line_pixels==WIDTH-1)) && active_lines==HEIGHT-1;
                end else if (de_d) begin
                    if (line_pixels!=WIDTH) bad_reason[2]<=1'b1;
                    if (active_lines<HEIGHT+1) active_lines<=active_lines+1'b1;
                    line_pixels<=0;
                end
            end
        end
    end
endmodule

// Source snapshot: rtl/video/pg100_rgb_tx.v
// Same-PCLK, fixed one-cycle RGB888 passthrough. No algorithms change this path.
// This does not reconstruct invalid timing or silently repeat/scale frames.
module pg100_rgb_tx(
    input wire pclk, rst_n, enable,
    input wire [23:0] rgb_in,
    input wire hs_in, vs_in, de_in,
    output reg [23:0] rgb_out,
    output reg hs_out, vs_out, de_out
);
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin rgb_out<=0; hs_out<=0; vs_out<=0; de_out<=0; end
        else begin
            rgb_out<=enable ? rgb_in : 24'd0;
            hs_out<=hs_in; vs_out<=vs_in; de_out<=enable && de_in;
        end
    end
endmodule

// Source snapshot: rtl/video/pg100_mono_sampler.v
// Frozen 1920x1080 -> 320x240 nearest pixel-center sampling, no frame RAM.
// The output is speculative until capture/marker commit. Marker footprints mask.
module pg100_mono_sampler(
    input wire pclk, rst_n, frame_start,
    input wire pixel_valid,
    input wire [23:0] rgb,
    input wire [11:0] x, y,
    output reg mono_valid,
    output reg [7:0] mono,
    output reg [8:0] work_x,
    output reg [7:0] work_y,
    output reg mask, mono_sof, mono_eol, mono_eof
);
    reg [11:0] target_x, target_y;
    reg [8:0] u;
    reg [7:0] v;
    reg row_even;
    reg [15:0] rprod, gprod, bprod;
    reg [16:0] sum;
    reg [2:0] valid_pipe, mask_pipe, sof_pipe, eol_pipe, eof_pipe;
    reg [8:0] ux0,ux1;
    reg [7:0] vy0,vy1;
    wire selected=pixel_valid && x==target_x && y==target_y;
    // Pixel footprint: u=0..191 and v=1..5 overlap x0..1151,y8..23.
    wire marked=u<192 && v>=1 && v<=5;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            target_x<=3; target_y<=2; u<=0; v<=0; row_even<=1;
            rprod<=0; gprod<=0; bprod<=0; sum<=0;
            valid_pipe<=0; mask_pipe<=0; sof_pipe<=0; eol_pipe<=0; eof_pipe<=0;
            ux0<=0;ux1<=0;vy0<=0;vy1<=0;
            mono_valid<=0; mono<=0;work_x<=0;work_y<=0; mask<=0;mono_sof<=0;mono_eol<=0;mono_eof<=0;
        end else begin
            valid_pipe<={valid_pipe[1:0],selected};
            mask_pipe<={mask_pipe[1:0],marked};
            sof_pipe<={sof_pipe[1:0],selected && u==0 && v==0};
            eol_pipe<={eol_pipe[1:0],selected && u==319};
            eof_pipe<={eof_pipe[1:0],selected && u==319 && v==239};
            rprod<=rgb[23:16]*16'd77; gprod<=rgb[15:8]*16'd150; bprod<=rgb[7:0]*16'd29;
            sum<={1'b0,rprod}+{1'b0,gprod}+{1'b0,bprod}+17'd128;
            ux0<=u;ux1<=ux0;vy0<=v;vy1<=vy0;
            mono_valid<=valid_pipe[1]; mono<=mask_pipe[1] ? 0 : sum[15:8];
            work_x<=ux1;work_y<=vy1; mask<=mask_pipe[1];
            mono_sof<=sof_pipe[1];mono_eol<=eol_pipe[1];mono_eof<=eof_pipe[1];
            if (frame_start) begin target_x<=3;target_y<=2;u<=0;v<=0;row_even<=1; valid_pipe<=0; end
            else if (selected) begin
                if (u==319) begin
                    target_x<=3;u<=0;
                    if (v<239) begin
                        target_y<=target_y+(row_even ? 12'd4 : 12'd5);
                        v<=v+1'b1;row_even<=!row_even;
                    end else target_y<=12'hfff;
                end else begin target_x<=target_x+6;u<=u+1'b1; end
            end
        end
    end
endmodule

// Source snapshot: rtl/control/pg100_board_reset.v
// Exactly one physical G25 owner; video faults only assert local PCLK reset.
module pg100_board_reset #(
    parameter HOLD_CYCLES=2700000,
    parameter WINDOW_CYCLES=27000,
    parameter MIN_EDGES=270, MAX_EDGES=630
)(
    input wire clk27, por_n, hard_reset_request,
    input wire pclk, netclk,
    output reg shared_rst_n,
    output wire ctrl_rst_n, pixel_rst_n, net_rst_n,
    output reg pixel_clock_good,
    output reg [15:0] measured_edges,
    output reg [31:0] clock_loss_count
);
    reg [31:0] hold_count, window_count;
    reg [7:0] pdiv;
    reg phb;
    reg [2:0] hb_sync;
    reg hb_d;
    reg [15:0] edges;
    reg [2:0] good_windows;
    reg [2:0] cr,pr,nr;
    wire pixel_assert_n=shared_rst_n && pixel_clock_good;
    always @(posedge pclk or negedge por_n) begin
        if (!por_n) begin pdiv<=0;phb<=0;end
        else begin pdiv<=pdiv+1'b1;if(pdiv==255) phb<=!phb;end
    end
    always @(posedge clk27 or negedge por_n) begin
        if (!por_n) begin
            shared_rst_n<=0;hold_count<=0;window_count<=0;hb_sync<=0;hb_d<=0;edges<=0;
            pixel_clock_good<=0;measured_edges<=0;clock_loss_count<=0;good_windows<=0;
        end else begin
            hb_sync<={hb_sync[1:0],phb}; hb_d<=hb_sync[2];
            if (hard_reset_request) begin shared_rst_n<=0;hold_count<=0;end
            else if(!shared_rst_n) begin
                if (hold_count==HOLD_CYCLES-1) shared_rst_n<=1;
                else hold_count<=hold_count+1'b1;
            end
            if (window_count==WINDOW_CYCLES-1) begin
                window_count<=0;measured_edges<=edges;edges<=0;
                if (edges>=MIN_EDGES && edges<=MAX_EDGES && shared_rst_n) begin
                    if(good_windows<3) good_windows<=good_windows+1'b1;
                    if(good_windows>=2) pixel_clock_good<=1;
                end else begin
                    if(pixel_clock_good) clock_loss_count<=clock_loss_count+1'b1;
                    pixel_clock_good<=0;good_windows<=0;
                end
            end else begin
                window_count<=window_count+1'b1;
                if(hb_sync[2]!=hb_d && edges!=65535) edges<=edges+1'b1;
            end
        end
    end
    always @(posedge clk27 or negedge shared_rst_n)
        if(!shared_rst_n) cr<=0; else cr<={cr[1:0],1'b1};
    always @(posedge pclk or negedge pixel_assert_n)
        if(!pixel_assert_n) pr<=0; else pr<={pr[1:0],1'b1};
    always @(posedge netclk or negedge shared_rst_n)
        if(!shared_rst_n) nr<=0; else nr<={nr[1:0],1'b1};
    assign ctrl_rst_n=cr[2];assign pixel_rst_n=pr[2];assign net_rst_n=nr[2];
endmodule

// Source snapshot: rtl/control/pg100_hdmi_config.v
// One physical I2C owner. Probe scratch register, configure RX then TX, bounded retry.
module pg100_hdmi_config #(
    parameter QUARTER_CYCLES=135, STRETCH_LIMIT=270000,
    parameter SETTLE_CYCLES=9450000, RETRY_LIMIT=3
)(
    input wire clk27,rst_n,reinitialize,
    inout wire scl,sda,
    output reg init_done,init_failed,
    output reg [2:0] failure_code,
    output reg [31:0] retry_count,
    output reg [7:0] dbg_freq_value,
    output reg [15:0] dbg_freq_tries,
    output reg [3:0] dbg_freq_state,
    output reg dbg_freq_forced,
    output wire scl_drive_low,sda_drive_low,
    output wire bus_busy
);
    `include "hdmi_config_rom.vh"
    localparam PREPARE=0,WAIT_CMD=1,RECOVER=2,WAIT_RECOVER=3,SETTLE=4,FINISH=5,
               FREQ_WAIT=6,FREQ_RD=7,FREQ_GAP=8;
    reg [3:0] state;
    reg [2:0] probe_stage;
    reg [8:0] index;
    reg [3:0] retry;
    reg [31:0] wait_count;
    reg [15:0] freq_tries;
    reg freq_forced;
    reg request,reading,recover;
    reg [6:0] device;
    reg [15:0] reg_addr;
    reg [7:0] value;
    wire done,success;
    wire [7:0] read_value;
    wire [2:0] master_error;
    wire [31:0] entry=hdmi_config_word(index);
    pg100_i2c_master #(.QUARTER_CYCLES(QUARTER_CYCLES),.STRETCH_LIMIT(STRETCH_LIMIT)) master(
        .clk(clk27),.rst_n(rst_n),.request(request),.read_request(reading),.recover_request(recover),
        .address(device),.reg_address(reg_addr),.write_data(value),.scl(scl),.sda(sda),
        .busy(bus_busy),.done(done),.success(success),.read_data(read_value),.error_code(master_error),
        .scl_drive_low(scl_drive_low),.sda_drive_low(sda_drive_low));
    always @(posedge clk27 or negedge rst_n) begin
        if(!rst_n) begin
            state<=PREPARE;probe_stage<=0;index<=0;retry<=0;wait_count<=0;
            request<=0;reading<=0;recover<=0;device<=0;reg_addr<=0;value<=0;
            init_done<=0;init_failed<=0;failure_code<=0;retry_count<=0;
            freq_tries<=0;freq_forced<=0;dbg_freq_value<=0;dbg_freq_tries<=0;dbg_freq_state<=PREPARE;dbg_freq_forced<=0;
        end else begin
            request<=0;recover<=0;dbg_freq_state<=state;
            if(reinitialize && !bus_busy) begin
                state<=PREPARE;probe_stage<=0;index<=0;retry<=0;wait_count<=0;
                init_done<=0;init_failed<=0;failure_code<=0;freq_tries<=0;
            end else case(state)
                PREPARE: if(!bus_busy) begin
                    if(probe_stage<4) begin
                        device<=probe_stage<2 ? 7'h2b : 7'h59;
                        reg_addr<=16'h0003;value<=8'h5a;reading<=probe_stage[0];
                        request<=1;state<=WAIT_CMD;
                    end else if(index<HDMI_CONFIG_COUNT) begin
                        device<=entry[30:24];reg_addr<=entry[23:8];value<=entry[7:0];reading<=0;
                        if(entry[31] && wait_count==0) begin wait_count<=SETTLE_CYCLES;state<=SETTLE;end
                        else begin request<=1;state<=WAIT_CMD;end
                    end else begin init_done<=1;failure_code<=0;state<=FINISH;end
                end
                WAIT_CMD: if(done) begin
                    if(success && !(probe_stage<4 && probe_stage[0] && read_value!=8'h5a)) begin
                        retry<=0;wait_count<=0;
                        if(probe_stage<4) begin probe_stage<=probe_stage+1'b1; state<=PREPARE; end
                        else if(index==9'd299) begin wait_count<=SETTLE_CYCLES; state<=FREQ_WAIT; end
                        else begin index<=index+1'b1; state<=PREPARE; end
                    end else if(retry<RETRY_LIMIT) begin
                        retry<=retry+1'b1;retry_count<=retry_count+1'b1;
                        failure_code<=success ? 3'd5 : master_error;state<=RECOVER;
                    end else begin
                        init_failed<=1;failure_code<=success ? 3'd5 : master_error;state<=FINISH;
                    end
                end
                RECOVER: if(!bus_busy) begin recover<=1;state<=WAIT_RECOVER;end
                WAIT_RECOVER: if(done) state<=PREPARE;
                SETTLE: if(wait_count==1) begin wait_count<=1;state<=PREPARE;end
                        else wait_count<=wait_count-1'b1;
                FREQ_WAIT: if(wait_count==1) begin
                        device<=7'h2b;reg_addr<=16'h209e;value<=0;reading<=1;request<=1;
                        state<=FREQ_RD;
                    end else wait_count<=wait_count-1'b1;
                FREQ_RD: if(done) begin
                        dbg_freq_value<=read_value;
                        if(success && read_value[1:0]==2'b10) begin
                            reading<=0;index<=9'd304;retry<=0;state<=PREPARE;
                        end else if(freq_tries>=16'd99) begin
                            freq_forced<=1;dbg_freq_forced<=1;reading<=0;index<=9'd304;state<=PREPARE;
                        end else begin
                            freq_tries<=freq_tries+1'b1;dbg_freq_tries<=freq_tries+1'b1;
                            wait_count<=32'd2700000;state<=FREQ_GAP;
                        end
                    end
                FREQ_GAP: if(wait_count==1) begin
                        device<=7'h2b;reg_addr<=16'h209e;value<=0;reading<=1;request<=1;
                        state<=FREQ_RD;
                    end else wait_count<=wait_count-1'b1;
                FINISH: begin end
                default: begin init_failed<=1;failure_code<=7;state<=FINISH;end
            endcase
        end
    end
endmodule

// Source snapshot: rtl/control/pg100_i2c_master.v
// Original single-owner open-drain MS72xx register master.
// 7-bit slave address; 16-bit register address LOW BYTE FIRST per vendor demo.
module pg100_i2c_master #(
    // This tick is one SCL half period: 27MHz/(2*135)=100kHz.
    parameter QUARTER_CYCLES=135, STRETCH_LIMIT=270000
)(
    input wire clk, rst_n,
    input wire request, read_request, recover_request,
    input wire [6:0] address,
    input wire [15:0] reg_address,
    input wire [7:0] write_data,
    inout wire scl, sda,
    output wire busy,
    output reg done, success,
    output reg [7:0] read_data,
    output reg [2:0] error_code,
    output wire scl_drive_low, sda_drive_low
);
    localparam IDLE=0, START0=1, START1=2, LOW=3, HIGH=4,
        ACKLOW=5, ACKHIGH=6, STOP0=7, STOP1=8, STOP2=9,
        RESTART0=10, RESTART1=11, RESTART2=12,
        READLOW=13, READHIGH=14, NACKLOW=15, NACKHIGH=16,
        CLEARLOW=17, CLEARHIGH=18;
    reg [4:0] state;
    reg [15:0] divider;
    reg [31:0] stretch_count;
    reg [1:0] scl_sync,sda_sync;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg [2:0] byte_index;
    reg [3:0] clear_index;
    reg [6:0] slave;
    reg [15:0] register_word;
    reg [7:0] value;
    reg is_read, failed, clearing, recover_only;
    wire high_phase=state==START0 || state==START1 || state==HIGH || state==ACKHIGH ||
        state==STOP1 || state==STOP2 || state==RESTART1 || state==RESTART2 ||
        state==READHIGH || state==NACKHIGH || state==CLEARHIGH;
    wire waiting=high_phase && !scl_sync[1];
    assign scl_drive_low=state==LOW || state==ACKLOW || state==STOP0 || state==RESTART0 ||
        state==READLOW || state==NACKLOW || state==CLEARLOW;
    assign sda_drive_low=state==START1 || state==RESTART2 || state==STOP0 || state==STOP1 ||
        ((state==LOW || state==HIGH) && !shift[7]);
    assign scl=scl_drive_low ? 1'b0 : 1'bz;
    assign sda=sda_drive_low ? 1'b0 : 1'bz;
    assign busy=state!=IDLE;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;divider<=0;stretch_count<=0;scl_sync<=3;sda_sync<=3;
            shift<=0;bit_index<=0;byte_index<=0;clear_index<=0;slave<=0;
            register_word<=0;value<=0;is_read<=0;failed<=0;clearing<=0;recover_only<=0;
            done<=0;success<=0;read_data<=0;error_code<=0;
        end else begin
            scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};done<=0;
            if(state==IDLE) begin
                divider<=0;stretch_count<=0;
                if(request || recover_request) begin
                    slave<=address;register_word<=reg_address;value<=write_data;is_read<=read_request;
                    shift<={address,1'b0};bit_index<=7;byte_index<=0;clear_index<=0;
                    failed<=0;success<=0;error_code<=0;
                    clearing<=recover_request || !sda_sync[1];
                    recover_only<=recover_request;
                    state<=(recover_request || !sda_sync[1]) ? CLEARLOW : START0;
                end
            end else if(waiting) begin
                divider<=0;
                if(stretch_count>=STRETCH_LIMIT-1) begin
                    // A stuck SCL cannot produce STOP; release both wires explicitly.
                    state<=IDLE;done<=1;success<=0;error_code<=2;stretch_count<=0;
                end else stretch_count<=stretch_count+1'b1;
            end else if(divider==QUARTER_CYCLES-1) begin
                divider<=0;stretch_count<=0;
                case(state)
                    START0: if(!sda_sync[1]) begin state<=CLEARLOW;clearing<=1;end else state<=START1;
                    START1: state<=LOW;
                    LOW: state<=HIGH;
                    HIGH: begin
                        if(bit_index==0) state<=ACKLOW;
                        else begin bit_index<=bit_index-1'b1;shift<={shift[6:0],1'b0};state<=LOW;end
                    end
                    ACKLOW: state<=ACKHIGH;
                    ACKHIGH: begin
                        if(sda_sync[1]) begin failed<=1;error_code<=1;state<=STOP0;end
                        else begin
                            bit_index<=7;
                            case(byte_index)
                                0: begin shift<=register_word[7:0];byte_index<=1;state<=LOW;end
                                1: begin shift<=register_word[15:8];byte_index<=2;state<=LOW;end
                                2: if(is_read) begin state<=RESTART0;end
                                   else begin shift<=value;byte_index<=3;state<=LOW;end
                                3: state<=STOP0;
                                4: begin shift<=0;state<=READLOW;end
                                default: begin failed<=1;error_code<=4;state<=STOP0;end
                            endcase
                        end
                    end
                    RESTART0: state<=RESTART1;
                    RESTART1: state<=RESTART2;
                    RESTART2: begin shift<={slave,1'b1};byte_index<=4;bit_index<=7;state<=LOW;end
                    READLOW: state<=READHIGH;
                    READHIGH: begin
                        shift<={shift[6:0],sda_sync[1]};
                        if(bit_index==0) begin read_data<={shift[6:0],sda_sync[1]};state<=NACKLOW;end
                        else begin bit_index<=bit_index-1'b1;state<=READLOW;end
                    end
                    NACKLOW: state<=NACKHIGH;
                    NACKHIGH: state<=STOP0;
                    CLEARLOW: state<=CLEARHIGH;
                    CLEARHIGH: begin
                        if(clear_index==8) state<=STOP0;
                        else begin clear_index<=clear_index+1'b1;state<=CLEARLOW;end
                    end
                    STOP0: state<=STOP1;
                    STOP1: state<=STOP2;
                    STOP2: begin
                        state<=IDLE;done<=1;
                        success<=!failed && sda_sync[1] && (!clearing || recover_only);
                        if(!sda_sync[1]) error_code<=3;
                        else if(clearing && !recover_only) error_code<=3;
                        // Recover is a completed bus-clear operation; caller retries command.
                    end
                    default: begin state<=IDLE;done<=1;success<=0;error_code<=4;end
                endcase
            end else divider<=divider+1'b1;
        end
    end
endmodule

// Source snapshot: rtl/integration/pg100_capture_store_bridge.v
// PCLK-domain bounded source-identity/ownership bridge.
// capture_tag advances on VS; storage tag advances on SOF. They are NOT equal.
// CRC-valid PGM1 identifies a source frame; trusted session approval is external.
module pg100_capture_store_bridge(
    input wire pclk,rst_n,link_locked,
    input wire [23:0] pix_rgb,
    input wire pix_valid,pix_sof,
    input wire [11:0] pix_x,pix_y,
    input wire frame_start,frame_end,frame_commit,frame_discard,
    input wire [31:0] capture_tag,capture_commit_tag,
    input wire [31:0] cdc_active_tag,cdc_dropped_frames,
    input wire cdc_control_overflow,
    output reg commit_valid,commit_good,
    output reg [31:0] commit_tag,
    output reg [151:0] commit_key,
    output wire identity_valid,marker_error,
    output wire [151:0] decoded_key,
    output reg [31:0] no_sof_frames,bad_identity_frames,good_identity_frames,
    output reg bridge_fault
);
    wire[7:0]origin;wire[63:0]session;wire[31:0]frame,calibration;wire[15:0]mode;
    pg100_frame_marker_decode decoder(.clk(pclk),.rst_n(rst_n),.link_locked(link_locked),
        .frame_start(frame_start),.frame_end(frame_end),.de(pix_valid),.x(pix_x),.y(pix_y),.rgb(pix_rgb),
        .identity_valid(identity_valid),.marker_error(marker_error),.origin_source_id(origin),
        .origin_session_id(session),.frame_id(frame),.mode_id(mode),.calibration_id(calibration));
    assign decoded_key={origin,session,frame,mode,calibration};
    reg owner_valid;
    reg [31:0] owner_capture_tag,owner_storage_tag,owner_drop_baseline;
    reg pending,pending_good;
    reg [31:0] pending_tag;
    always @(posedge pclk or negedge rst_n)begin
        if(!rst_n)begin
            owner_valid<=0;owner_capture_tag<=0;owner_storage_tag<=0;owner_drop_baseline<=0;
            pending<=0;pending_good<=0;pending_tag<=0;
            commit_valid<=0;commit_good<=0;commit_tag<=0;commit_key<=0;
            no_sof_frames<=0;bad_identity_frames<=0;good_identity_frames<=0;bridge_fault<=0;
        end else begin
            commit_valid<=0;
            if(cdc_control_overflow)bridge_fault<=1;
            // Decoder's result belongs to the immediately previous end event.
            if(pending)begin
                commit_valid<=1;commit_tag<=pending_tag;pending<=0;
                commit_good<=pending_good && identity_valid && !marker_error && !cdc_control_overflow;
                commit_key<=identity_valid ? decoded_key : 152'b0;
                if(pending_good && identity_valid && !marker_error && !cdc_control_overflow)
                    good_identity_frames<=good_identity_frames+1'b1;
                else bad_identity_frames<=bad_identity_frames+1'b1;
            end
            if(frame_start)owner_valid<=0;
            if(pix_valid && pix_sof)begin
                // CDC accepts this same SOF edge and increments its local tag.
                owner_valid<=1;owner_capture_tag<=capture_tag;
                owner_storage_tag<=cdc_active_tag+1'b1;
                owner_drop_baseline<=cdc_dropped_frames;
            end
            if(frame_end)begin
                owner_valid<=0;
                if(owner_valid && owner_capture_tag==capture_commit_tag)begin
                    if(pending)bridge_fault<=1;
                    pending<=1;pending_tag<=owner_storage_tag;
                    pending_good<=frame_commit && !frame_discard && link_locked &&
                        cdc_dropped_frames==owner_drop_baseline && !cdc_control_overflow;
                end else begin
                    no_sof_frames<=no_sof_frames+1'b1;
                    if(owner_valid)bridge_fault<=1;
                end
            end
        end
    end
endmodule

// Source snapshot: rtl/memory/pg100_memory_async_fifo.v
// Memory-specific MIT derivative: RAM read stage made explicit for ADS; identical handshake/latency.
/*

Copyright (c) 2014-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream asynchronous FIFO
 */
module pg100_memory_async_fifo #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    // Propagate tlast signal
    parameter LAST_ENABLE = 1,
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    /*
     * AXI input
     */
    input  wire                   s_clk,
    input  wire                   s_rst,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                   m_clk,
    input  wire                   m_rst,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /*
     * Pause
     */
    input  wire                   s_pause_req,
    output wire                   s_pause_ack,
    input  wire                   m_pause_req,
    output wire                   m_pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0] s_status_depth,
    output wire [$clog2(DEPTH):0] s_status_depth_commit,
    output wire                   s_status_overflow,
    output wire                   s_status_bad_frame,
    output wire                   s_status_good_frame,
    output wire [$clog2(DEPTH):0] m_status_depth,
    output wire [$clog2(DEPTH):0] m_status_depth_commit,
    output wire                   m_status_overflow,
    output wire                   m_status_bad_frame,
    output wire                   m_status_good_frame
);

parameter ADDR_WIDTH = (KEEP_ENABLE && KEEP_WIDTH > 1) ? $clog2(DEPTH/KEEP_WIDTH) : $clog2(DEPTH);
parameter CL_KEEP_WDITH = $clog2(KEEP_WIDTH);

parameter OUTPUT_FIFO_ADDR_WIDTH = RAM_PIPELINE < 2 ? 3 : $clog2(RAM_PIPELINE*2+7);

// check configuration
initial begin
    if (FRAME_FIFO && !LAST_ENABLE) begin
        $display("Error: FRAME_FIFO set requires LAST_ENABLE set (instance %m)");
        $finish;
    end

    if (DROP_OVERSIZE_FRAME && !FRAME_FIFO) begin
        $display("Error: DROP_OVERSIZE_FRAME set requires FRAME_FIFO set (instance %m)");
        $finish;
    end

    if (DROP_BAD_FRAME && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_BAD_FRAME set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if (DROP_WHEN_FULL && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_WHEN_FULL set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if ((DROP_BAD_FRAME || MARK_WHEN_FULL) && (USER_BAD_FRAME_MASK & {USER_WIDTH{1'b1}}) == 0) begin
        $display("Error: Invalid USER_BAD_FRAME_MASK value (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && FRAME_FIFO) begin
        $display("Error: MARK_WHEN_FULL is not compatible with FRAME_FIFO (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && !LAST_ENABLE) begin
        $display("Error: MARK_WHEN_FULL set requires LAST_ENABLE set (instance %m)");
        $finish;
    end
end

localparam KEEP_OFFSET = DATA_WIDTH;
localparam LAST_OFFSET = KEEP_OFFSET + (KEEP_ENABLE ? KEEP_WIDTH : 0);
localparam ID_OFFSET   = LAST_OFFSET + (LAST_ENABLE ? 1          : 0);
localparam DEST_OFFSET = ID_OFFSET   + (ID_ENABLE   ? ID_WIDTH   : 0);
localparam USER_OFFSET = DEST_OFFSET + (DEST_ENABLE ? DEST_WIDTH : 0);
localparam WIDTH       = USER_OFFSET + (USER_ENABLE ? USER_WIDTH : 0);

function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = b ^ (b >> 1);
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    for (i = 0; i <= ADDR_WIDTH; i = i + 1) begin
        gray2bin[i] = ^(g >> i);
    end
endfunction

reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_sync_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};

reg [ADDR_WIDTH:0] wr_ptr_temp;
reg [ADDR_WIDTH:0] rd_ptr_temp;

(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] wr_ptr_commit_sync_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* syn_preserve=1, syn_allow_retiming=0 *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};

reg wr_ptr_update_valid_reg = 1'b0;
reg wr_ptr_update_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync1_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync2_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_sync3_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_ack_sync1_reg = 1'b0;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg wr_ptr_update_ack_sync2_reg = 1'b0;

(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync1_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync2_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg s_rst_sync3_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync1_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync2_reg = 1'b1;
(* syn_preserve=1, syn_allow_retiming=0 *)
reg m_rst_sync3_reg = 1'b1;

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0] /* synthesis syn_ramstyle="block_ram" */;
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [WIDTH-1:0] mem_read_data /* synthesis syn_ramstyle="block_ram" */;
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first TWO MSBs do NOT match, but rest matches
// (gray code equivalent of first MSB different but rest same)
wire full = wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}});
// empty when pointers match exactly
wire empty = FRAME_FIFO ? (rd_ptr_reg == wr_ptr_commit_sync_reg) : (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg);
// overflow within packet
wire full_wr = wr_ptr_reg == (wr_ptr_commit_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});

// control signals
reg write;
reg read;
reg store_output;

reg s_frame_reg = 1'b0;
reg m_frame_reg = 1'b0;

reg drop_frame_reg = 1'b0;
reg mark_frame_reg = 1'b0;
reg send_frame_reg = 1'b0;
reg overflow_reg = 1'b0;
reg bad_frame_reg = 1'b0;
reg good_frame_reg = 1'b0;

reg m_drop_frame_reg = 1'b0;
reg m_terminate_frame_reg = 1'b0;

reg [ADDR_WIDTH:0] s_depth_reg = 0;
reg [ADDR_WIDTH:0] s_depth_commit_reg = 0;
reg [ADDR_WIDTH:0] m_depth_reg = 0;
reg [ADDR_WIDTH:0] m_depth_commit_reg = 0;

reg overflow_sync1_reg = 1'b0;
reg overflow_sync2_reg = 1'b0;
reg overflow_sync3_reg = 1'b0;
reg overflow_sync4_reg = 1'b0;
reg bad_frame_sync1_reg = 1'b0;
reg bad_frame_sync2_reg = 1'b0;
reg bad_frame_sync3_reg = 1'b0;
reg bad_frame_sync4_reg = 1'b0;
reg good_frame_sync1_reg = 1'b0;
reg good_frame_sync2_reg = 1'b0;
reg good_frame_sync3_reg = 1'b0;
reg good_frame_sync4_reg = 1'b0;

assign s_axis_tready = (FRAME_FIFO ? (!full || (full_wr && DROP_OVERSIZE_FRAME) || DROP_WHEN_FULL) : (!full || MARK_WHEN_FULL)) && !s_rst_sync3_reg;

wire [WIDTH-1:0] s_axis;

generate
    assign s_axis[DATA_WIDTH-1:0] = s_axis_tdata;
    if (KEEP_ENABLE) assign s_axis[KEEP_OFFSET +: KEEP_WIDTH] = s_axis_tkeep;
    if (LAST_ENABLE) assign s_axis[LAST_OFFSET]               = s_axis_tlast | mark_frame_reg;
    if (ID_ENABLE)   assign s_axis[ID_OFFSET   +: ID_WIDTH]   = s_axis_tid;
    if (DEST_ENABLE) assign s_axis[DEST_OFFSET +: DEST_WIDTH] = s_axis_tdest;
    if (USER_ENABLE) assign s_axis[USER_OFFSET +: USER_WIDTH] = mark_frame_reg ? USER_BAD_FRAME_VALUE : s_axis_tuser;
endgenerate

wire [WIDTH-1:0] m_axis = RAM_PIPELINE==0 ? mem_read_data : m_axis_pipe_reg[RAM_PIPELINE+1-1];

wire                   m_axis_tready_pipe;
wire                   m_axis_tvalid_pipe = m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1];

wire [DATA_WIDTH-1:0]  m_axis_tdata_pipe  = m_axis[DATA_WIDTH-1:0];
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_pipe  = KEEP_ENABLE ? m_axis[KEEP_OFFSET +: KEEP_WIDTH] : {KEEP_WIDTH{1'b1}};
wire                   m_axis_tlast_pipe  = LAST_ENABLE ? m_axis[LAST_OFFSET] | m_terminate_frame_reg : 1'b1;
wire [ID_WIDTH-1:0]    m_axis_tid_pipe    = ID_ENABLE   ? m_axis[ID_OFFSET +: ID_WIDTH] : {ID_WIDTH{1'b0}};
wire [DEST_WIDTH-1:0]  m_axis_tdest_pipe  = DEST_ENABLE ? m_axis[DEST_OFFSET +: DEST_WIDTH] : {DEST_WIDTH{1'b0}};
wire [USER_WIDTH-1:0]  m_axis_tuser_pipe  = USER_ENABLE ? (m_terminate_frame_reg ? USER_BAD_FRAME_VALUE : m_axis[USER_OFFSET +: USER_WIDTH]) : {USER_WIDTH{1'b0}};

wire                   m_axis_tready_out;
wire                   m_axis_tvalid_out;

wire [DATA_WIDTH-1:0]  m_axis_tdata_out;
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_out;
wire                   m_axis_tlast_out;
wire [ID_WIDTH-1:0]    m_axis_tid_out;
wire [DEST_WIDTH-1:0]  m_axis_tdest_out;
wire [USER_WIDTH-1:0]  m_axis_tuser_out;

wire pipe_ready;

assign s_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_reg, {CL_KEEP_WDITH{1'b0}}} : s_depth_reg;
assign s_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_commit_reg, {CL_KEEP_WDITH{1'b0}}} : s_depth_commit_reg;
assign s_status_overflow = overflow_reg;
assign s_status_bad_frame = bad_frame_reg;
assign s_status_good_frame = good_frame_reg;

assign m_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_reg, {CL_KEEP_WDITH{1'b0}}} : m_depth_reg;
assign m_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_commit_reg, {CL_KEEP_WDITH{1'b0}}} : m_depth_commit_reg;
assign m_status_overflow = overflow_sync3_reg ^ overflow_sync4_reg;
assign m_status_bad_frame = bad_frame_sync3_reg ^ bad_frame_sync4_reg;
assign m_status_good_frame = good_frame_sync3_reg ^ good_frame_sync4_reg;

// reset synchronization
always @(posedge m_clk or posedge m_rst) begin
    if (m_rst) begin
        s_rst_sync1_reg <= 1'b1;
    end else begin
        s_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge s_clk) begin
    s_rst_sync2_reg <= s_rst_sync1_reg;
    s_rst_sync3_reg <= s_rst_sync2_reg;
end

always @(posedge s_clk or posedge s_rst) begin
    if (s_rst) begin
        m_rst_sync1_reg <= 1'b1;
    end else begin
        m_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    m_rst_sync2_reg <= m_rst_sync1_reg;
    m_rst_sync3_reg <= m_rst_sync2_reg;
end

// Write logic
always @(posedge s_clk) begin
    overflow_reg <= 1'b0;
    bad_frame_reg <= 1'b0;
    good_frame_reg <= 1'b0;

    if (FRAME_FIFO && wr_ptr_update_valid_reg) begin
        // have updated pointer to sync
        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
            // no sync in progress; sync update
            wr_ptr_update_valid_reg <= 1'b0;
            wr_ptr_sync_commit_reg <= wr_ptr_commit_reg;
            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
        end
    end

    if (s_axis_tready && s_axis_tvalid && LAST_ENABLE) begin
        // track input frame status
        s_frame_reg <= !s_axis_tlast;
    end

    if (s_rst_sync3_reg && LAST_ENABLE) begin
        // if sink side is reset during transfer, drop partial frame
        if (s_frame_reg && !(s_axis_tready && s_axis_tvalid && s_axis_tlast)) begin
            drop_frame_reg <= 1'b1;
        end
        if (s_axis_tready && s_axis_tvalid && !s_axis_tlast) begin
            drop_frame_reg <= 1'b1;
        end
    end

    if (FRAME_FIFO) begin
        // frame FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            // transfer in
            if ((full && DROP_WHEN_FULL) || (full_wr && DROP_OVERSIZE_FRAME) || drop_frame_reg) begin
                // full, packet overflow, or currently dropping frame
                // drop frame
                drop_frame_reg <= 1'b1;
                if (s_axis_tlast) begin
                    // end of frame, reset write pointer
                    wr_ptr_temp = wr_ptr_commit_reg;
                    wr_ptr_reg <= wr_ptr_temp;
                    wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                if (s_axis_tlast || (!DROP_OVERSIZE_FRAME && (full_wr || send_frame_reg))) begin
                    // end of frame or send frame
                    send_frame_reg <= !s_axis_tlast;
                    if (s_axis_tlast && DROP_BAD_FRAME && USER_BAD_FRAME_MASK & ~(s_axis_tuser ^ USER_BAD_FRAME_VALUE)) begin
                        // bad packet, reset write pointer
                        wr_ptr_temp = wr_ptr_commit_reg;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                        bad_frame_reg <= 1'b1;
                    end else begin
                        // good packet or packet overflow, update write pointer
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

                        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                            // no sync in progress; sync update
                            wr_ptr_update_valid_reg <= 1'b0;
                            wr_ptr_sync_commit_reg <= wr_ptr_temp;
                            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
                        end else begin
                            // sync in progress; flag it for later
                            wr_ptr_update_valid_reg <= 1'b1;
                        end

                        good_frame_reg <= s_axis_tlast;
                    end
                end
            end
        end else if (s_axis_tvalid && full_wr && FRAME_FIFO && !DROP_OVERSIZE_FRAME) begin
            // data valid with packet overflow
            // update write pointer
            send_frame_reg <= 1'b1;
            wr_ptr_temp = wr_ptr_reg;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

            if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                // no sync in progress; sync update
                wr_ptr_update_valid_reg <= 1'b0;
                wr_ptr_sync_commit_reg <= wr_ptr_temp;
                wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
            end else begin
                // sync in progress; flag it for later
                wr_ptr_update_valid_reg <= 1'b1;
            end
        end
    end else begin
        // normal FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            if (drop_frame_reg && LAST_ENABLE) begin
                // currently dropping frame
                if (s_axis_tlast) begin
                    // end of frame
                    if (!full && mark_frame_reg && MARK_WHEN_FULL) begin
                        // terminate marked frame
                        mark_frame_reg <= 1'b0;
                        mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    end
                    // end of frame, clear drop flag
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else if ((full || mark_frame_reg) && MARK_WHEN_FULL) begin
                // full or marking frame
                // drop frame; mark if this isn't the first cycle
                drop_frame_reg <= 1'b1;
                mark_frame_reg <= mark_frame_reg || s_frame_reg;
                if (s_axis_tlast) begin
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                // transfer in
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_commit_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
            end
        end else if ((!full && !drop_frame_reg && mark_frame_reg) && MARK_WHEN_FULL) begin
            // terminate marked frame
            mark_frame_reg <= 1'b0;
            mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
            wr_ptr_temp = wr_ptr_reg + 1;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
        end
    end

    if (s_rst_sync3_reg) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;
    end

    if (s_rst) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;

        s_frame_reg <= 1'b0;

        drop_frame_reg <= 1'b0;
        mark_frame_reg <= 1'b0;
        send_frame_reg <= 1'b0;
        overflow_reg <= 1'b0;
        bad_frame_reg <= 1'b0;
        good_frame_reg <= 1'b0;
    end
end

// Write-side status
always @(posedge s_clk) begin
    rd_ptr_conv_reg <= gray2bin(rd_ptr_gray_sync2_reg);
    s_depth_reg <= wr_ptr_reg - rd_ptr_conv_reg;
    s_depth_commit_reg <= wr_ptr_commit_reg - rd_ptr_conv_reg;
end

// pointer synchronization
always @(posedge s_clk) begin
    rd_ptr_gray_sync1_reg <= rd_ptr_gray_reg;
    rd_ptr_gray_sync2_reg <= rd_ptr_gray_sync1_reg;
    wr_ptr_update_ack_sync1_reg <= wr_ptr_update_sync3_reg;
    wr_ptr_update_ack_sync2_reg <= wr_ptr_update_ack_sync1_reg;

    if (s_rst) begin
        rd_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_ack_sync1_reg <= 1'b0;
        wr_ptr_update_ack_sync2_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    wr_ptr_gray_sync1_reg <= wr_ptr_gray_reg;
    wr_ptr_gray_sync2_reg <= wr_ptr_gray_sync1_reg;
    if (FRAME_FIFO && wr_ptr_update_sync2_reg ^ wr_ptr_update_sync3_reg) begin
        wr_ptr_commit_sync_reg <= wr_ptr_sync_commit_reg;
    end
    wr_ptr_update_sync1_reg <= wr_ptr_update_reg;
    wr_ptr_update_sync2_reg <= wr_ptr_update_sync1_reg;
    wr_ptr_update_sync3_reg <= wr_ptr_update_sync2_reg;

    if (FRAME_FIFO && m_rst_sync3_reg) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_sync_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_sync1_reg <= 1'b0;
        wr_ptr_update_sync2_reg <= 1'b0;
        wr_ptr_update_sync3_reg <= 1'b0;
    end
end

// status synchronization
always @(posedge s_clk) begin
    overflow_sync1_reg <= overflow_sync1_reg ^ overflow_reg;
    bad_frame_sync1_reg <= bad_frame_sync1_reg ^ bad_frame_reg;
    good_frame_sync1_reg <= good_frame_sync1_reg ^ good_frame_reg;

    if (s_rst) begin
        overflow_sync1_reg <= 1'b0;
        bad_frame_sync1_reg <= 1'b0;
        good_frame_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    overflow_sync2_reg <= overflow_sync1_reg;
    overflow_sync3_reg <= overflow_sync2_reg;
    overflow_sync4_reg <= overflow_sync3_reg;
    bad_frame_sync2_reg <= bad_frame_sync1_reg;
    bad_frame_sync3_reg <= bad_frame_sync2_reg;
    bad_frame_sync4_reg <= bad_frame_sync3_reg;
    good_frame_sync2_reg <= good_frame_sync1_reg;
    good_frame_sync3_reg <= good_frame_sync2_reg;
    good_frame_sync4_reg <= good_frame_sync3_reg;

    if (m_rst) begin
        overflow_sync2_reg <= 1'b0;
        overflow_sync3_reg <= 1'b0;
        overflow_sync4_reg <= 1'b0;
        bad_frame_sync2_reg <= 1'b0;
        bad_frame_sync3_reg <= 1'b0;
        bad_frame_sync4_reg <= 1'b0;
        good_frame_sync2_reg <= 1'b0;
        good_frame_sync3_reg <= 1'b0;
        good_frame_sync4_reg <= 1'b0;
    end
end

// Read logic
integer j;

always @(posedge m_clk) begin
    if (m_axis_tready_pipe) begin
        // output ready; invalidate stage
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end

    for (j = RAM_PIPELINE+1-1; j > 0; j = j - 1) begin
        if (m_axis_tready_pipe || ((~m_axis_tvalid_pipe_reg) >> j)) begin
            // output ready or bubble in pipeline; transfer down pipeline
            m_axis_tvalid_pipe_reg[j] <= m_axis_tvalid_pipe_reg[j-1];
            m_axis_pipe_reg[j] <= j==1 ? mem_read_data : m_axis_pipe_reg[j-1];
            m_axis_tvalid_pipe_reg[j-1] <= 1'b0;
        end
    end

    if (m_axis_tready_pipe || ~m_axis_tvalid_pipe_reg) begin
        // output ready or bubble in pipeline; read new data from FIFO
        m_axis_tvalid_pipe_reg[0] <= 1'b0;
        mem_read_data <= mem[rd_ptr_reg[ADDR_WIDTH-1:0]];
        if (!empty && !m_rst_sync3_reg && !m_drop_frame_reg && pipe_ready) begin
            // not empty, increment pointer
            m_axis_tvalid_pipe_reg[0] <= 1'b1;
            rd_ptr_temp = rd_ptr_reg + 1;
            rd_ptr_reg <= rd_ptr_temp;
            rd_ptr_gray_reg <= rd_ptr_temp ^ (rd_ptr_temp >> 1);
        end
    end

    if (m_axis_tvalid_pipe && LAST_ENABLE) begin
        // track output frame status
        if (m_axis_tlast_pipe && m_axis_tready_pipe) begin
            m_frame_reg <= 1'b0;
        end else begin
            m_frame_reg <= 1'b1;
        end
    end

    if (m_drop_frame_reg && (OUTPUT_FIFO_ENABLE ? pipe_ready : m_axis_tready_pipe || !m_axis_tvalid_pipe) && LAST_ENABLE) begin
        // terminate frame
        // (only for frame transfers interrupted by source reset)
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b1;
        m_terminate_frame_reg <= 1'b1;
        m_drop_frame_reg <= 1'b0;
    end

    if (m_rst_sync3_reg && LAST_ENABLE) begin
        // if source side is reset during transfer, drop partial frame

        // empty output pipeline, except for last stage
        if (RAM_PIPELINE > 0) begin
            m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-2:0] <= 0;
        end

        if (m_frame_reg && (!m_axis_tvalid_pipe || (m_axis_tvalid_pipe && !m_axis_tlast_pipe)) &&
                !(m_drop_frame_reg || m_terminate_frame_reg)) begin
            // terminate frame
            m_drop_frame_reg <= 1'b1;
        end
    end

    if (m_rst_sync3_reg) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        m_axis_tvalid_pipe_reg <= 0;
        m_frame_reg <= 1'b0;
        m_drop_frame_reg <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end
end

// Read-side status
always @(posedge m_clk) begin
    wr_ptr_conv_reg <= gray2bin(wr_ptr_gray_sync2_reg);
    m_depth_reg <= wr_ptr_conv_reg - rd_ptr_reg;
    m_depth_commit_reg <= FRAME_FIFO ? wr_ptr_commit_sync_reg - rd_ptr_reg : wr_ptr_conv_reg - rd_ptr_reg;
end

generate

if (!OUTPUT_FIFO_ENABLE) begin

    assign pipe_ready = 1'b1;

    assign m_axis_tready_pipe = m_axis_tready_out;
    assign m_axis_tvalid_out = m_axis_tvalid_pipe;

    assign m_axis_tdata_out = m_axis_tdata_pipe;
    assign m_axis_tkeep_out = m_axis_tkeep_pipe;
    assign m_axis_tlast_out = m_axis_tlast_pipe;
    assign m_axis_tid_out   = m_axis_tid_pipe;
    assign m_axis_tdest_out = m_axis_tdest_pipe;
    assign m_axis_tuser_out = m_axis_tuser_pipe;

end else begin : output_fifo

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0;
    reg                  m_axis_tlast_reg  = 1'b0;
    reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
    reg out_fifo_half_full_reg = 1'b0;

    wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
    wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

    (* syn_ramstyle="lut_ram" *)
    reg [DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [KEEP_WIDTH-1:0] out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg                  out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [ID_WIDTH-1:0]   out_fifo_tid[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [DEST_WIDTH-1:0] out_fifo_tdest[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* syn_ramstyle="lut_ram" *)
    reg [USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

    assign pipe_ready = !out_fifo_half_full_reg;

    assign m_axis_tready_pipe = 1'b1;

    assign m_axis_tdata_out  = m_axis_tdata_reg;
    assign m_axis_tkeep_out  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid_out = m_axis_tvalid_reg;
    assign m_axis_tlast_out  = LAST_ENABLE ? m_axis_tlast_reg : 1'b1;
    assign m_axis_tid_out    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest_out  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser_out  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge m_clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready_out;

        out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

        if (!out_fifo_full && m_axis_tvalid_pipe) begin
            out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdata_pipe;
            out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tkeep_pipe;
            out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlast_pipe;
            out_fifo_tid[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tid_pipe;
            out_fifo_tdest[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdest_pipe;
            out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tuser_pipe;
            out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
        end

        if (!out_fifo_empty && (!m_axis_tvalid_reg || m_axis_tready_out)) begin
            m_axis_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tvalid_reg <= 1'b1;
            m_axis_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tid_reg <= out_fifo_tid[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tdest_reg <= out_fifo_tdest[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        end

        if (m_rst) begin
            out_fifo_wr_ptr_reg <= 0;
            out_fifo_rd_ptr_reg <= 0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end

if (PAUSE_ENABLE) begin : pause

    // Pause logic
    reg pause_reg = 1'b0;
    reg pause_frame_reg = 1'b0;

    reg s_pause_req_sync1_reg;
    reg s_pause_req_sync2_reg;
    reg s_pause_req_sync3_reg;
    reg s_pause_ack_sync1_reg;
    reg s_pause_ack_sync2_reg;
    reg s_pause_ack_sync3_reg;

    always @(posedge s_clk) begin
        s_pause_req_sync1_reg <= s_pause_req;
        s_pause_ack_sync2_reg <= s_pause_ack_sync1_reg;
        s_pause_ack_sync3_reg <= s_pause_ack_sync2_reg;
    end

    always @(posedge m_clk) begin
        s_pause_req_sync2_reg <= s_pause_req_sync1_reg;
        s_pause_req_sync3_reg <= s_pause_req_sync2_reg;
        s_pause_ack_sync1_reg <= pause_reg;
    end

    assign m_axis_tready_out = m_axis_tready && !pause_reg;
    assign m_axis_tvalid = m_axis_tvalid_out && !pause_reg;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = s_pause_ack_sync3_reg;
    assign m_pause_ack = pause_reg;

    always @(posedge m_clk) begin
        if (FRAME_PAUSE) begin
            if (pause_reg) begin
                // paused; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end else if (m_axis_tvalid_out) begin
                // frame transfer; set frame bit
                pause_frame_reg <= 1'b1;
                if (m_axis_tready && m_axis_tlast) begin
                    // end of frame; clear frame bit and update pause status
                    pause_frame_reg <= 1'b0;
                    pause_reg <= m_pause_req || s_pause_req_sync3_reg;
                end
            end else if (!pause_frame_reg) begin
                // idle; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end
        end else begin
            pause_reg <= m_pause_req || s_pause_req_sync3_reg;
        end

        if (m_rst) begin
            pause_frame_reg <= 1'b0;
            pause_reg <= 1'b0;
        end
    end

end else begin

    assign m_axis_tready_out = m_axis_tready;
    assign m_axis_tvalid = m_axis_tvalid_out;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = 1'b0;
    assign m_pause_ack = 1'b0;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/memory/pg100_pixel_line_cdc.v
// HDMI has no ready. Only COMPLETE LINES cross the bounded asynchronous RAM.
// tag is LOCAL capture ownership, never a protocol source frame identity.
module pg100_pixel_line_cdc #(
    parameter DEPTH=8192, parameter KEY_WIDTH=152
)(
    input wire rst_n, input wire s_clk, input wire m_clk,
    input wire [23:0] s_rgb, input wire s_valid,
    input wire s_sof, input wire s_eol, input wire s_eof, input wire s_bad,
    output reg [31:0] s_active_tag,
    input wire commit_valid, input wire [31:0] commit_tag,
    input wire [KEY_WIDTH-1:0] commit_key, input wire commit_good,
    output wire [23:0] m_rgb, output wire m_valid, input wire m_ready,
    output wire m_sof, output wire m_eol, output wire m_eof,
    output wire [31:0] m_tag,
    output wire m_commit_valid, input wire m_commit_ready,
    output wire [31:0] m_commit_tag,
    output wire [KEY_WIDTH-1:0] m_commit_key, output wire m_commit_good,
    output reg [31:0] dropped_frames, output reg control_overflow
);
    (* syn_preserve=1, syn_allow_retiming=0 *) reg [1:0] sr, mr;
    always @(posedge s_clk or negedge rst_n)
        if(!rst_n) sr<=3; else sr<={sr[0],1'b0};
    always @(posedge m_clk or negedge rst_n)
        if(!rst_n) mr<=3; else mr<={mr[0],1'b0};
    reg dropping;
    wire ready, overflow, bad_line, unused_bad;
    wire [31:0] incoming_tag = s_sof ? s_active_tag+1'b1 : s_active_tag;
    // Keep presenting EOL even while dropping: it terminates the FIFO's
    // internal discard state. Bad rows roll their tentative write pointer back.
    wire admitted = s_valid;
    wire drop_mark = s_sof ? s_bad : (dropping || s_bad);
    always @(posedge s_clk) begin
        if(sr[1]) begin
            s_active_tag<=0; dropping<=1; dropped_frames<=0;
        end else begin
            if(s_valid && s_sof) begin s_active_tag<=incoming_tag; dropping<=s_bad; end
            if(s_bad || overflow || bad_line) begin
                if(!dropping) dropped_frames<=dropped_frames+1'b1;
                dropping<=1;
            end
        end
    end
    pg100_memory_async_fifo #(
        .DEPTH(DEPTH), .DATA_WIDTH(24), .KEEP_ENABLE(1), .KEEP_WIDTH(1),
        .LAST_ENABLE(1), .ID_ENABLE(1), .ID_WIDTH(32),
        .DEST_ENABLE(1), .DEST_WIDTH(1), .USER_ENABLE(1), .USER_WIDTH(3),
        .FRAME_FIFO(1), .DROP_OVERSIZE_FRAME(1), .DROP_BAD_FRAME(1),
        .DROP_WHEN_FULL(1), .USER_BAD_FRAME_VALUE(3'b100), .USER_BAD_FRAME_MASK(3'b100)
    ) line_fifo (
        .s_clk(s_clk),.s_rst(sr[1]),.s_axis_tdata(s_rgb),.s_axis_tkeep(1'b1),
        .s_axis_tvalid(admitted),.s_axis_tready(ready),.s_axis_tlast(s_eol),
        .s_axis_tid(incoming_tag),.s_axis_tdest(1'b0),.s_axis_tuser({drop_mark,s_eof,s_sof}),
        .m_clk(m_clk),.m_rst(mr[1]),.m_axis_tdata(m_rgb),.m_axis_tkeep(),
        .m_axis_tvalid(m_valid),.m_axis_tready(m_ready),.m_axis_tlast(m_eol),
        .m_axis_tid(m_tag),.m_axis_tdest(),.m_axis_tuser({unused_bad,m_eof,m_sof}),
        .s_pause_req(1'b0),.m_pause_req(1'b0),.s_pause_ack(),.m_pause_ack(),
        .s_status_depth(),.s_status_depth_commit(),.s_status_overflow(overflow),
        .s_status_bad_frame(bad_line),.s_status_good_frame(),
        .m_status_depth(),.m_status_depth_commit(),.m_status_overflow(),
        .m_status_bad_frame(),.m_status_good_frame()
    );
    // Metadata is a separate eight-entry mailbox, not repeated in pixel RAM.
    wire control_ready;
    always @(posedge s_clk) begin
        if(sr[1]) control_overflow<=0;
        else if(commit_valid && !control_ready) control_overflow<=1;
    end
    pg100_memory_async_fifo #(
        .DEPTH(8),.DATA_WIDTH(KEY_WIDTH+33),.KEEP_ENABLE(1),.KEEP_WIDTH(1),
        .LAST_ENABLE(1),.ID_ENABLE(1),.ID_WIDTH(1),.DEST_ENABLE(1),.DEST_WIDTH(1),
        .USER_ENABLE(1),.USER_WIDTH(1),.FRAME_FIFO(0),.DROP_OVERSIZE_FRAME(0),
        .DROP_BAD_FRAME(0),.DROP_WHEN_FULL(0)
    ) commit_fifo (
        .s_clk(s_clk),.s_rst(sr[1]),.s_axis_tdata({commit_good,commit_tag,commit_key}),
        .s_axis_tkeep(1'b1),.s_axis_tvalid(commit_valid),.s_axis_tready(control_ready),
        .s_axis_tlast(1'b1),.s_axis_tid(1'b0),.s_axis_tdest(1'b0),.s_axis_tuser(1'b0),
        .m_clk(m_clk),.m_rst(mr[1]),.m_axis_tdata({m_commit_good,m_commit_tag,m_commit_key}),
        .m_axis_tkeep(),.m_axis_tvalid(m_commit_valid),.m_axis_tready(m_commit_ready),
        .m_axis_tlast(),.m_axis_tid(),.m_axis_tdest(),.m_axis_tuser(),
        .s_pause_req(1'b0),.m_pause_req(1'b0),.s_pause_ack(),.m_pause_ack(),
        .s_status_depth(),.s_status_depth_commit(),.s_status_overflow(),
        .s_status_bad_frame(),.s_status_good_frame(),.m_status_depth(),
        .m_status_depth_commit(),.m_status_overflow(),.m_status_bad_frame(),.m_status_good_frame()
    );
endmodule

// Source snapshot: rtl/memory/pg100_ddr_burst_arbiter.v
// Native PG2L DDR interface: 256 bits, addr in 32-bit words, len 0..15.
// No WVALID/BRESP/RREADY. Writer MUST preload every beat before wr_valid.
// Readers MUST reserve a complete burst before asserting *_valid.
// At most one DDR transaction outstanding. Round-robin grants <=16 beats.
module pg100_ddr_burst_arbiter(
    input wire clk,input wire rst_n,input wire warm_reset,input wire init_done,
    input wire wr_valid,output wire wr_ready,input wire [27:0] wr_addr,
    input wire [3:0] wr_len,input wire [255:0] wr_data,input wire [31:0] wr_strb,
    output wire wr_take,output reg wr_done,
    input wire tx_valid,output wire tx_ready,input wire [27:0] tx_addr,input wire [3:0] tx_len,
    input wire alg_valid,output wire alg_ready,input wire [27:0] alg_addr,input wire [3:0] alg_len,
    output wire [255:0] rd_data,output wire tx_data_valid,output wire alg_data_valid,
    output wire rd_last,output reg rd_done,output reg fault,output wire idle,
    output reg [27:0] axi_awaddr,output wire axi_awuser_ap,output wire [3:0] axi_awuser_id,
    output reg [3:0] axi_awlen,output wire axi_awvalid,input wire axi_awready,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,input wire axi_wusero_last,
    output reg [27:0] axi_araddr,output wire axi_aruser_ap,output wire [3:0] axi_aruser_id,
    output reg [3:0] axi_arlen,output wire axi_arvalid,input wire axi_arready,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,
    input wire axi_rlast,input wire axi_rvalid
);
    localparam IDLE=0,AW=1,WD=2,AR=3,RD=4;
    reg [2:0] state;
    reg [1:0] turn,owner;
    reg [4:0] remaining;
    reg cancelled;
    reg [1:0] choice;
    reg chosen;
    always @* begin
        chosen=1; choice=0;
        case(turn)
            0: if(wr_valid) choice=0; else if(tx_valid) choice=1; else if(alg_valid) choice=2; else chosen=0;
            1: if(tx_valid) choice=1; else if(alg_valid) choice=2; else if(wr_valid) choice=0; else chosen=0;
            default: if(alg_valid) choice=2; else if(wr_valid) choice=0; else if(tx_valid) choice=1; else chosen=0;
        endcase
    end
    wire grant = state==IDLE && init_done && !warm_reset && chosen;
    assign wr_ready=grant && choice==0;
    assign tx_ready=grant && choice==1;
    assign alg_ready=grant && choice==2;
    assign idle=state==IDLE;
    // Once launched, warm reset drains the old native transaction. Never reuse
    // its identity or grant new traffic until the final old beat has arrived.
    assign axi_awvalid=state==AW;
    assign axi_arvalid=state==AR;
    assign axi_awuser_ap=1'b0;assign axi_aruser_ap=1'b0;
    assign axi_awuser_id=4'd0;
    assign axi_aruser_id={2'b00,owner};
    assign axi_wdata=wr_data;assign axi_wstrb=wr_strb;
    assign wr_take=state==WD && axi_wready;
    assign rd_data=axi_rdata;
    wire response_correct=axi_rid=={2'b00,owner} && axi_rlast==(remaining==1);
    assign tx_data_valid=state==RD && owner==1 && axi_rvalid && !cancelled && !warm_reset && response_correct && !fault;
    assign alg_data_valid=state==RD && owner==2 && axi_rvalid && !cancelled && !warm_reset && response_correct && !fault;
    assign rd_last=remaining==1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;turn<=0;owner<=0;remaining<=0;cancelled<=0;
            wr_done<=0;rd_done<=0;fault<=0;axi_awaddr<=0;axi_awlen<=0;axi_araddr<=0;axi_arlen<=0;
        end else begin
            wr_done<=0;rd_done<=0;
            if(warm_reset) cancelled<=1;
            if(grant) begin
                owner<=choice;cancelled<=0;
                turn <= choice==2 ? 0 : choice+1'b1;
                if(choice==0) begin
                    axi_awaddr<=wr_addr;axi_awlen<=wr_len;remaining<={1'b0,wr_len}+1'b1;state<=AW;
                end else begin
                    axi_araddr<=choice==1 ? tx_addr : alg_addr;
                    axi_arlen<=choice==1 ? tx_len : alg_len;
                    remaining<={1'b0,(choice==1 ? tx_len : alg_len)}+1'b1;state<=AR;
                end
            end
            if(state==AW && axi_awready) state<=WD;
            if(state==WD && axi_wready) begin
                if(axi_wusero_id!=0 || axi_wusero_last!=(remaining==1)) fault<=1;
                remaining<=remaining-1'b1;
                if(remaining==1) begin
                    state<=IDLE;
                    if(!cancelled && !warm_reset) wr_done<=1;
                end
            end
            if(state==AR && axi_arready) state<=RD;
            if(state==RD && axi_rvalid) begin
                if(axi_rid!={2'b00,owner} || axi_rlast!=(remaining==1)) fault<=1;
                remaining<=remaining-1'b1;
                if(remaining==1) begin
                    state<=IDLE;
                    if(!cancelled && !warm_reset) rd_done<=1;
                end
            end
            // Unexpected RVALID is never exposed to clients.
            if(axi_rvalid && state!=RD) fault<=1;
        end
    end
endmodule

// Source snapshot: rtl/memory/pg100_video_frame_store.v
// Four DDR frame slots. RGB888 occupies a 32-bit native DDR word per pixel.
// No full-frame FPGA RAM. The writer preloads <=16 256-bit words before AW.
// commit_key arrives AFTER marker/raster validation; it is never guessed at SOF.
module pg100_video_frame_store #(
    parameter WIDTH=1920, HEIGHT=1080, KEY_WIDTH=152,
    parameter STRIDE_WORDS=((WIDTH+7)/8)*8,
    parameter SLOT_WORDS=2097152
)(
    input wire clk,input wire rst_n,input wire warm_reset,input wire init_done,
    input wire [23:0] s_rgb,input wire s_valid,output wire s_ready,
    input wire s_sof,input wire s_eol,input wire s_eof,input wire [31:0] s_tag,
    input wire commit_valid,output wire commit_ready,input wire [31:0] commit_tag,
    input wire [KEY_WIDTH-1:0] commit_key,input wire commit_good,
    output reg publish_valid,output reg [1:0] publish_slot,
    output reg [31:0] publish_generation,output reg [KEY_WIDTH-1:0] publish_key,
    input wire acquire_valid,input wire [1:0] acquire_slot,
    input wire [31:0] acquire_generation,input wire [2:0] acquire_mask,
    output reg acquire_ok,
    input wire release_valid,input wire [1:0] release_slot,
    input wire [31:0] release_generation,input wire [2:0] release_mask,
    input wire tx_valid,output wire tx_ready,input wire [1:0] tx_slot,
    input wire [31:0] tx_generation,input wire [27:0] tx_byte_offset,input wire [3:0] tx_len,
    input wire tx_reserved,
    input wire alg_valid,output wire alg_ready,input wire [1:0] alg_slot,
    input wire [31:0] alg_generation,input wire [27:0] alg_byte_offset,input wire [3:0] alg_len,
    input wire alg_reserved,
    output wire [255:0] rd_data,output wire tx_data_valid,output wire alg_data_valid,
    output wire rd_last,output wire idle,output reg [31:0] dropped_frames,
    output reg invalid_request,output wire fault,
    output wire [27:0] axi_awaddr,output wire axi_awuser_ap,output wire [3:0] axi_awuser_id,
    output wire [3:0] axi_awlen,output wire axi_awvalid,input wire axi_awready,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,input wire axi_wusero_last,
    output wire [27:0] axi_araddr,output wire axi_aruser_ap,output wire [3:0] axi_aruser_id,
    output wire [3:0] axi_arlen,output wire axi_arvalid,input wire axi_arready,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,
    input wire axi_rlast,input wire axi_rvalid
);
    localparam FREE=0,WRITING=1,PENDING=2,COMMITTED=3;
    // synthesis translate_off
    initial begin
        if(WIDTH<1 || WIDTH>4096 || HEIGHT<1 || HEIGHT>4096 ||
            STRIDE_WORDS<WIDTH || STRIDE_WORDS%8!=0 ||
            STRIDE_WORDS*HEIGHT>SLOT_WORDS || SLOT_WORDS%8!=0 || 4*SLOT_WORDS>268435456)
            $display("INVALID_VIDEO_MEMORY_GEOMETRY_OR_SLOT_RANGE");
    end
    // synthesis translate_on
    reg [1:0] slot_state[0:3];reg [31:0] slot_gen[0:3],slot_tag[0:3];
    reg [KEY_WIDTH-1:0] slot_key[0:3];reg [2:0] slot_lease[0:3];
    reg slot_good[0:3],slot_confirmed[0:3];
    reg [31:0] generation_counter;
    reg active;reg [1:0] current_slot;reg [31:0] active_tag;
    reg [11:0] x,y;reg geometry_bad,final_buffer;
    reg [2:0] lane;reg [255:0] pack;
    reg [4:0] buffer_words;reg [27:0] buffer_addr,line_addr,next_addr;
    reg [2:0] write_state;
    localparam FILL=0,PREFETCH=1,REQUEST=2,SEND=3,DRAIN=4;
    reg [255:0] burst_ram[0:15] /* synthesis syn_ramstyle="block_ram" */;
    reg [31:0] mask_ram[0:15] /* synthesis syn_ramstyle="block_ram" */;
    reg [255:0] burst_data;reg [31:0] burst_mask;
    reg [3:0] beat_index;
    wire wr_ready,wr_take,wr_done,rd_done;
    wire [3:0] ram_read_addr = wr_take ? beat_index+1'b1 : beat_index;
    always @(posedge clk) begin
        burst_data<=burst_ram[ram_read_addr];burst_mask<=mask_ram[ram_read_addr];
    end
    reg [255:0] pack_next;
    always @* begin
        pack_next=lane==0 ? 256'b0 : pack;
        pack_next[lane*32+:32]={8'b0,s_rgb};
    end
    wire start_needed=s_valid && s_sof && active_tag!=s_tag;
    reg free_found;reg [1:0] free_slot;integer i,j,k;
    always @* begin
        free_found=0;free_slot=0;
        for(j=3;j>=0;j=j-1)
            if(slot_state[j]==COMMITTED && slot_lease[j]==0 &&
                !(acquire_valid && acquire_slot==j && acquire_generation==slot_gen[j])) begin
                free_found=1;free_slot=j;
            end
        // Preserve completed frames while an unused slot exists.
        for(j=3;j>=0;j=j-1)
            if(slot_state[j]==FREE) begin free_found=1;free_slot=j;end
        if(active && slot_state[current_slot]==WRITING && start_needed) begin
            free_found=1;free_slot=current_slot;
        end
    end
    // Drain orphan rows after a lost SOF; they must not block the next frame.
    assign s_ready=write_state==FILL && !warm_reset && !start_needed;
    wire take=s_valid && s_ready && active && active_tag==s_tag;
    reg commit_match;
    always @* begin
        commit_match=0;
        for(k=0;k<4;k=k+1)
            if(slot_tag[k]==commit_tag && (slot_state[k]==WRITING || slot_state[k]==PENDING)) commit_match=1;
    end
    assign commit_ready=commit_match || $signed(commit_tag-active_tag)<=0;
    wire word_end=lane==7 || s_eol;
    wire [31:0] current_mask=32'hffffffff >> ((7-lane)*4);
    wire [31:0] frame_bytes=STRIDE_WORDS*HEIGHT*4;
    wire tx_legal=slot_state[tx_slot]==COMMITTED && slot_gen[tx_slot]==tx_generation &&
        slot_lease[tx_slot][0] && tx_reserved && tx_byte_offset[4:0]==0 &&
        ({1'b0,tx_byte_offset}+({29'b0,tx_len}+1)*32<=frame_bytes) &&
        ({1'b0,tx_byte_offset[11:0]}+({9'b0,tx_len}+1)*32<=4096);
    wire alg_legal=slot_state[alg_slot]==COMMITTED && slot_gen[alg_slot]==alg_generation &&
        (|slot_lease[alg_slot][2:1]) && alg_reserved && alg_byte_offset[4:0]==0 &&
        ({1'b0,alg_byte_offset}+({29'b0,alg_len}+1)*32<=frame_bytes) &&
        ({1'b0,alg_byte_offset[11:0]}+({9'b0,alg_len}+1)*32<=4096);
    wire [27:0] tx_addr=tx_slot*SLOT_WORDS+(tx_byte_offset>>2);
    wire [27:0] alg_addr=alg_slot*SLOT_WORDS+(alg_byte_offset>>2);
    pg100_ddr_burst_arbiter arbiter(
        .clk(clk),.rst_n(rst_n),.warm_reset(warm_reset),.init_done(init_done),
        .wr_valid(write_state==REQUEST),.wr_ready(wr_ready),.wr_addr(buffer_addr),
        .wr_len(buffer_words[3:0]-1'b1),.wr_data(burst_data),.wr_strb(burst_mask),
        .wr_take(wr_take),.wr_done(wr_done),
        .tx_valid(tx_valid&&tx_legal),.tx_ready(tx_ready),.tx_addr(tx_addr),.tx_len(tx_len),
        .alg_valid(alg_valid&&alg_legal),.alg_ready(alg_ready),.alg_addr(alg_addr),.alg_len(alg_len),
        .rd_data(rd_data),.tx_data_valid(tx_data_valid),.alg_data_valid(alg_data_valid),
        .rd_last(rd_last),.rd_done(rd_done),.fault(fault),.idle(idle),
        .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),
        .axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(axi_awready),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
        .axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),
        .axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(axi_arready),
        .axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid)
    );
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;current_slot<=0;active_tag<=0;generation_counter<=0;
            x<=0;y<=0;lane<=0;pack<=0;geometry_bad<=0;final_buffer<=0;
            buffer_words<=0;buffer_addr<=0;line_addr<=0;next_addr<=0;
            write_state<=FILL;beat_index<=0;publish_valid<=0;publish_slot<=0;
            publish_generation<=0;publish_key<=0;acquire_ok<=0;invalid_request<=0;dropped_frames<=0;
            for(i=0;i<4;i=i+1) begin
                slot_state[i]<=FREE;slot_gen[i]<=0;slot_tag[i]<=0;slot_key[i]<=0;
                slot_lease[i]<=0;slot_good[i]<=0;slot_confirmed[i]<=0;
            end
        end else begin
            publish_valid<=0;acquire_ok<=0;
            if((tx_valid&&!tx_legal)||(alg_valid&&!alg_legal)) invalid_request<=1;
            if(release_valid && slot_gen[release_slot]==release_generation)
                slot_lease[release_slot]<=slot_lease[release_slot]&~release_mask;
            if(acquire_valid && slot_state[acquire_slot]==COMMITTED &&
                slot_gen[acquire_slot]==acquire_generation && acquire_mask!=0) begin
                slot_lease[acquire_slot]<=
                    (slot_lease[acquire_slot]&~((release_valid&&release_slot==acquire_slot&&
                    release_generation==acquire_generation)?release_mask:3'b000))|acquire_mask;
                acquire_ok<=1;
            end
            if(commit_valid&&commit_ready) for(i=0;i<4;i=i+1)
                if(slot_tag[i]==commit_tag && (slot_state[i]==WRITING || slot_state[i]==PENDING)) begin
                    slot_confirmed[i]<=1;slot_good[i]<=commit_good;slot_key[i]<=commit_key;
                end
            for(i=0;i<4;i=i+1) if(slot_state[i]==PENDING && slot_confirmed[i]) begin
                if(slot_good[i]) begin
                    slot_state[i]<=COMMITTED;publish_valid<=1;publish_slot<=i;
                    publish_generation<=slot_gen[i];publish_key<=slot_key[i];
                end else begin slot_state[i]<=FREE;dropped_frames<=dropped_frames+1'b1;end
            end
            if(start_needed && write_state==FILL && init_done && !warm_reset) begin
                if(active) begin slot_state[current_slot]<=FREE;dropped_frames<=dropped_frames+1'b1;end
                if(free_found && generation_counter!=32'hffffffff) begin
                    active<=1;current_slot<=free_slot;active_tag<=s_tag;
                    generation_counter<=generation_counter+1'b1;
                    slot_state[free_slot]<=WRITING;slot_gen[free_slot]<=generation_counter+1'b1;
                    slot_tag[free_slot]<=s_tag;slot_lease[free_slot]<=0;slot_good[free_slot]<=0;
                    slot_confirmed[free_slot]<=0;slot_key[free_slot]<=0;
                    x<=0;y<=0;lane<=0;pack<=0;buffer_words<=0;geometry_bad<=0;final_buffer<=0;
                    line_addr<=free_slot*SLOT_WORDS;next_addr<=free_slot*SLOT_WORDS;
                    buffer_addr<=free_slot*SLOT_WORDS;
                end else begin
                    active<=0;active_tag<=s_tag;dropped_frames<=dropped_frames+1'b1;
                end
            end
            if(take) begin
                if(s_eol!=(x==WIDTH-1) || s_eof!=(x==WIDTH-1&&y==HEIGHT-1) ||
                    s_sof!=(x==0&&y==0)) geometry_bad<=1;
                pack<=pack_next;lane<=lane+1'b1;
                if(word_end) begin
                    burst_ram[buffer_words[3:0]]<=pack_next;
                    mask_ram[buffer_words[3:0]]<=current_mask;
                    buffer_words<=buffer_words+1'b1;lane<=0;
                    next_addr<=next_addr+8;
                    if(buffer_words==15 || s_eol) begin
                        write_state<=PREFETCH;beat_index<=0;
                        final_buffer<=s_eof;
                    end
                end
                if(s_eol) begin
                    x<=0;y<=y+1'b1;line_addr<=line_addr+STRIDE_WORDS;
                end else x<=x+1'b1;
            end
            if(write_state==PREFETCH) write_state<=REQUEST;
            if(write_state==REQUEST && wr_ready) write_state<=SEND;
            if(wr_take) beat_index<=beat_index+1'b1;
            if(write_state==SEND && wr_done) begin
                write_state<=FILL;buffer_words<=0;
                buffer_addr <= x==0 ? line_addr : next_addr;
                next_addr <= x==0 ? line_addr : next_addr;
                if(final_buffer) begin
                    active<=0;
                    if(!geometry_bad && !fault) slot_state[current_slot]<=PENDING;
                    else begin slot_state[current_slot]<=FREE;dropped_frames<=dropped_frames+1'b1;end
                end
            end
            if(warm_reset) begin
                active<=0;publish_valid<=0;
                for(i=0;i<4;i=i+1) begin slot_state[i]<=FREE;slot_lease[i]<=0;slot_confirmed[i]<=0;end
                // Keep preloaded RAM and its read pointer until any accepted
                // native write is drained; controller itself is not reset.
                write_state<=DRAIN;
            end else if(write_state==DRAIN && idle) begin
                write_state<=FILL;buffer_words<=0;lane<=0;final_buffer<=0;
            end
        end
    end
endmodule

// Source snapshot: rtl/transport/pg100_frame_marker_decode.v
// Decode PGM1 from already framed HDMI pixels. This is NOT MS7200 capture,
// external video timing signoff, or a stopped-PCLK watchdog. All inputs are
// synchronous to clk; an always-on external supervisor must flush link_locked
// after loss of PCLK. Complete raster + >=2 matching CRC-valid rows required.
module pg100_frame_marker_decode #(
    parameter WIDTH = 1920,
    parameter HEIGHT = 1080
)(
    input wire clk,
    input wire rst_n,
    input wire link_locked,
    input wire frame_start,
    input wire frame_end,
    input wire de,
    input wire [11:0] x,
    input wire [11:0] y,
    input wire [23:0] rgb,
    output reg identity_valid,
    output reg marker_error,
    output reg [7:0] origin_source_id,
    output reg [63:0] origin_session_id,
    output reg [31:0] frame_id,
    output reg [15:0] mode_id,
    output reg [31:0] calibration_id
);
    reg active;
    reg geometry_error;
    reg raster_complete;
    reg [11:0] expect_x, expect_y;
    reg [287:0] row_bits;
    reg row_error;
    reg first_cell, second_cell;
    reg [223:0] crc_data;
    reg [31:0] crc_state, wanted_crc;
    reg [7:0] crc_count;
    reg crc_busy;
    reg [151:0] pending_identity, candidate_identity;
    reg [4:0] valid_rows;
    reg conflicting;
    wire black = rgb[23:16]<=8'd64 && rgb[15:8]<=8'd64 && rgb[7:0]<=8'd64;
    wire white = rgb[23:16]>=8'd192 && rgb[15:8]>=8'd192 && rgb[7:0]>=8'd192;
    wire in_region = x<12'd1152 && y>=12'd8 && y<12'd24;
    wire [287:0] assembled_row = {row_bits[286:0],first_cell};
    wire [255:0] assembled_packet = assembled_row[255:0];
    wire crc_bit = crc_data[216 + crc_count[2:0]];
    wire [31:0] crc_next = (crc_state >> 1) ^
        ((crc_state[0]^crc_bit) ? 32'hedb88320 : 32'h0);
    wire [151:0] decoded_identity = {assembled_packet[215:208],assembled_packet[191:128],
        assembled_packet[127:96],assembled_packet[207:192],assembled_packet[95:64]};
    wire packet_header_ok = assembled_row[287:256]==32'hd391c5a7 &&
        assembled_packet[255:224]==32'h50474d31 && assembled_packet[223:216]==8'h01 &&
        assembled_packet[215:208]!=0 && assembled_packet[207:200]==0 &&
        assembled_packet[191:128]!=0 && assembled_packet[63:56]==8'h01 &&
        assembled_packet[55:32]==0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active<=0; geometry_error<=0; raster_complete<=0; expect_x<=0; expect_y<=0;
            row_bits<=0; row_error<=0; first_cell<=0; second_cell<=0;
            crc_data<=0; crc_state<=32'hffffffff; wanted_crc<=0; crc_count<=0; crc_busy<=0;
            pending_identity<=0; candidate_identity<=0; valid_rows<=0; conflicting<=0;
            identity_valid<=0; marker_error<=0;
            origin_source_id<=0; origin_session_id<=0; frame_id<=0; mode_id<=0; calibration_id<=0;
        end else begin
            identity_valid<=0;
            if (!link_locked) begin
                active<=0; crc_busy<=0; valid_rows<=0; marker_error<=1;
            end else if (frame_start) begin
                active<=1; geometry_error<=de; raster_complete<=0;
                expect_x<=0; expect_y<=0; valid_rows<=0; conflicting<=0;
                crc_busy<=0; marker_error<=0; row_error<=0;
            end else if (active) begin
                if (de) begin
                    if (raster_complete || x!=expect_x || y!=expect_y) geometry_error<=1;
                    if (expect_x==WIDTH-1) begin
                        expect_x<=0;
                        if (expect_y==HEIGHT-1) raster_complete<=1;
                        else expect_y<=expect_y+1'b1;
                    end else expect_x<=expect_x+1'b1;
                    if (in_region) begin
                        if (x==0) begin
                            row_bits<=0; row_error<=!(black||white);
                            first_cell<=white;
                        end else begin
                            if (!(black||white)) row_error<=1;
                            case (x[1:0])
                                2'd0: first_cell<=white;
                                2'd1: if (white!=first_cell) row_error<=1;
                                2'd2: begin
                                    second_cell<=white;
                                    if (white==first_cell) row_error<=1;
                                end
                                2'd3: begin
                                    if (white!=second_cell) row_error<=1;
                                    row_bits<=assembled_row;
                                    if (x==12'd1151 && !row_error && (black||white) &&
                                        white==second_cell && packet_header_ok) begin
                                        if (crc_busy) conflicting<=1;
                                        else begin
                                            crc_data<=assembled_packet[255:32];
                                            wanted_crc<=assembled_packet[31:0];
                                            crc_state<=32'hffffffff; crc_count<=0; crc_busy<=1;
                                            pending_identity<=decoded_identity;
                                        end
                                    end
                                end
                            endcase
                        end
                    end
                end
                if (crc_busy) begin
                    crc_state<=crc_next; crc_count<=crc_count+1'b1;
                    if (crc_count[2:0]==3'd7) crc_data<={crc_data[215:0],8'h0};
                    if (crc_count==8'd223) begin
                        crc_busy<=0;
                        if ((~crc_next)==wanted_crc) begin
                            if (valid_rows==0) candidate_identity<=pending_identity;
                            else if (candidate_identity!=pending_identity) conflicting<=1;
                            if (valid_rows<5'd16) valid_rows<=valid_rows+1'b1;
                        end
                    end
                end
                if (frame_end) begin
                    active<=0; crc_busy<=0;
                    if (!geometry_error && raster_complete && valid_rows>=2 && !conflicting && !crc_busy) begin
                        identity_valid<=1; marker_error<=0;
                        {origin_source_id,origin_session_id,frame_id,mode_id,calibration_id}<=candidate_identity;
                    end else marker_error<=1;
                end
            end
        end
    end
endmodule

// Source snapshot: rtl/transport/pg_pgt2_datagram_tx.v
// Hardware preflight: reports/sw21_sw24_preflight_20261012.md.
// Bounded byte-payload collector -> complete PGT2 datagram -> UDP complete-slot.
// m_abort cancels the downstream collecting slot and has priority over data.
// Control authority changes must fence already-committed transport packets.
module pg_pgt2_datagram_tx #(
 parameter [7:0] PRODUCER_ID=8'd100,
 parameter WATCHDOG_CYCLES=12500000
)(
 input wire clk,rst,
 input wire req_valid,output wire req_ready,
 input wire [7:0] req_message_type,req_status,
 input wire [15:0] req_reason,
 input wire [10:0] req_payload_length,
 input wire [151:0] req_key,
 input wire [31:0] req_sequence,req_epoch,
 input wire [63:0] req_timestamp_us,req_deadline_us,
 input wire [15:0] req_fragment_index,req_fragment_count,
 input wire [1:0] req_peer,
 input wire permit_valid,input wire [151:0] permit_key,
 input wire [31:0] permit_epoch,input wire [63:0] now_us,
 input wire invalidate,
 input wire [7:0] payload_data,input wire payload_valid,
 output wire payload_ready,input wire payload_last,
 output wire m_hdr_valid,input wire m_hdr_ready,
 output wire [10:0] m_length,output wire [1:0] m_peer,
 output wire [7:0] m_data,output wire m_valid,input wire m_ready,
 output wire m_last,output reg m_abort,
 output wire busy,output reg send_done,send_abort,req_rejected,
 output reg [31:0] rejected_packets
);
 localparam IDLE=0,HEADER_CRC=1,COLLECT=2,CHECK=3,OUT_HEADER=4,OUT_DATA=5,READ=6,DRAIN=7;
 reg [3:0] state;
 reg [511:0] header_q,body_context;
 reg [7:0] memory[0:955] /* synthesis syn_ramstyle="block_ram" */;
 reg [7:0] body_q;
 reg [10:0] length_q,wr_index,send_index;
 reg [9:0] read_addr;
 reg [5:0] header_index;
 reg [31:0] crc,trailer,epoch_q;
 reg [151:0] key_q;
 reg [63:0] deadline_q;
 reg [1:0] peer_q;
 reg [7:0] type_q;
 reg [15:0] fragment_index_q,fragment_count_q;
 reg [23:0] watchdog;
 wire context_current=permit_valid && permit_key==key_q && permit_epoch==epoch_q &&
                      now_us<deadline_q && !invalidate;
 wire transaction_current=context_current && watchdog<WATCHDOG_CYCLES-1 && !rst;
 assign busy=state!=IDLE;
 assign req_ready=state==IDLE && !invalidate && !m_abort && !rst;
 assign payload_ready=(state==COLLECT || state==DRAIN) && transaction_current;
 assign m_hdr_valid=state==OUT_HEADER && transaction_current;
 assign m_length=length_q+11'd68;
 assign m_peer=peer_q;
 // Authority/expiry must suppress the SAME-cycle final-byte handshake;
 // a registered abort alone would arrive after a downstream slot committed.
 assign m_valid=state==OUT_DATA && transaction_current;
 assign m_last=m_valid && send_index==length_q+11'd67;
 assign m_data=send_index<64 ? header_q[511-send_index*8-:8] :
               send_index<length_q+64 ? body_q : trailer[31-(send_index-length_q-64)*8-:8];
 always @(posedge clk)begin
  if(payload_valid && payload_ready && state==COLLECT && wr_index<956) memory[wr_index[9:0]]<=payload_data;
  if(state==READ)body_q<=memory[read_addr];
 end
 function [31:0] crc_byte;
  input [31:0] previous;input [7:0] value;reg [31:0] c;integer bitno;
  begin c=previous^{24'd0,value};for(bitno=0;bitno<8;bitno=bitno+1)c=(c>>1)^(c[0]?32'hedb88320:0);crc_byte=c;end
 endfunction
 wire [15:0] total_records=body_context[511:496];
 wire [15:0] here_records=fragment_index_q==0 ? (total_records>118?16'd118:total_records) : total_records-118;
 wire prefix_ok=body_context[495:488]==1 && body_context[487:480]==1 &&
                body_context[479:464]==1920 && body_context[463:448]==1080;
 wire feature_ok=total_records<=128 && prefix_ok &&
   fragment_count_q==(total_records>118?2:1) && fragment_index_q<fragment_count_q &&
   length_q==8+here_records*8;
 wire lane_ok=total_records<=8 && prefix_ok && fragment_count_q==1 && fragment_index_q==0 && length_q==8+total_records*12;
 wire fixed_ok=fragment_count_q==1 && fragment_index_q==0 &&
  ((type_q==6 && length_q==24)||(type_q==8 && length_q==24)||
   (type_q==9 && length_q==32)||(type_q==10 && length_q==24)||
   (type_q==12 && length_q==64)||(type_q==7 && length_q==32));
 wire typed_ok=type_q==2?feature_ok:type_q==1?lane_ok:fixed_ok;
 wire req_envelope_ok=(req_message_type==1 || req_message_type==2 || req_message_type==6 ||
   req_message_type==7 || req_message_type==8 || req_message_type==9 || req_message_type==10 || req_message_type==12) &&
   req_payload_length>=8 && req_payload_length<=956 && req_peer<=2 &&
   req_key[143:80]!=0 && req_key[47:32]<=255 &&
   (req_key[151:144]==50 || req_key[151:144]==100 || req_key[151:144]==68 || req_key[151:144]==40) &&
   req_status<=10 && req_reason<=23 && ((req_status==0)==(req_reason==0)) &&
   (!(req_message_type==6 || req_message_type==8) || req_status==0) &&
   req_fragment_count>=1 && req_fragment_count<=32 && req_fragment_index<req_fragment_count &&
   permit_valid && req_key==permit_key && req_epoch==permit_epoch && now_us<req_deadline_us;
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;header_q<=0;body_context<=0;length_q<=0;wr_index<=0;send_index<=0;read_addr<=0;
   header_index<=0;crc<=32'hffffffff;trailer<=0;epoch_q<=0;key_q<=0;deadline_q<=0;peer_q<=0;
   type_q<=0;fragment_index_q<=0;fragment_count_q<=0;watchdog<=0;
   m_abort<=0;send_done<=0;send_abort<=0;req_rejected<=0;rejected_packets<=0;
  end else begin
   m_abort<=0;send_done<=0;send_abort<=0;req_rejected<=0;
   if(busy)watchdog<=watchdog+1'b1;else watchdog<=0;
   if(busy && (!context_current || watchdog>=WATCHDOG_CYCLES-1))begin
    // A collecting UDP slot must consume this abort before any simultaneous
    // final-byte handshake. No partial packet may become a committed slot.
    state<=IDLE;m_abort<=1;send_abort<=1;rejected_packets<=rejected_packets+1'b1;
   end else case(state)
    IDLE:if(req_valid && req_ready)begin
     if(!req_envelope_ok)begin req_rejected<=1;send_abort<=1;rejected_packets<=rejected_packets+1'b1;end
     else begin
      key_q<=req_key;epoch_q<=req_epoch;deadline_q<=req_deadline_us;type_q<=req_message_type;
      length_q<=req_payload_length;peer_q<=req_peer;fragment_index_q<=req_fragment_index;fragment_count_q<=req_fragment_count;
      header_q<={32'h50475432,8'd1,req_message_type,16'd0,PRODUCER_ID,req_key[151:144],PRODUCER_ID,req_status,
       req_reason,req_key[47:32],req_key[31:0],req_key[143:80],req_key[79:48],req_sequence,req_timestamp_us,
       5'd0,req_payload_length,req_fragment_index,req_fragment_count,16'd64,96'd0};
      crc<=32'hffffffff;header_index<=4;wr_index<=0;body_context<=0;state<=HEADER_CRC;
     end
    end
    HEADER_CRC:begin
     crc<=crc_byte(crc,header_q[511-header_index*8-:8]);header_index<=header_index+1'b1;
     if(header_index==63)state<=COLLECT;
    end
    COLLECT:if(payload_valid)begin
     if(wr_index<64)body_context[511-wr_index*8-:8]<=payload_data;
     crc<=crc_byte(crc,payload_data);wr_index<=wr_index+1'b1;
     if(payload_last)begin
      if(wr_index+1!=length_q)begin state<=IDLE;send_abort<=1;req_rejected<=1;rejected_packets<=rejected_packets+1'b1;end
      else begin trailer<=~crc_byte(crc,payload_data);state<=CHECK;end
     end else if(wr_index+1>=length_q)state<=DRAIN;
    end
    DRAIN:if(payload_valid && payload_last)begin state<=IDLE;send_abort<=1;req_rejected<=1;rejected_packets<=rejected_packets+1'b1;end
    CHECK:if(typed_ok)begin state<=OUT_HEADER;send_index<=0;end
      else begin state<=IDLE;send_abort<=1;req_rejected<=1;rejected_packets<=rejected_packets+1'b1;end
    OUT_HEADER:if(m_hdr_ready)state<=OUT_DATA;
    READ:state<=OUT_DATA;
    OUT_DATA:if(m_ready)begin
     send_index<=send_index+1'b1;
     if(m_last)begin state<=IDLE;send_done<=1;end
     else if(send_index==63 || (send_index>=64 && send_index<length_q+63))begin
      read_addr<=send_index==63 ? 0 : read_addr+1'b1;state<=READ;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Source snapshot: rtl/feature/pg100_feature_core.v
// MC_FAST9_TILE128_V1. Hardware preflight: docs/feature_rtl_v1.md.
// Full 320x240 mono8, one accepted pixel per clock. Speculative results are
// invisible until a matching complete-frame marker/capture commit arrives.
module pg100_feature_core(
 input wire clk, rst,
 input wire s_valid, output wire s_ready,
 input wire [7:0] s_mono, input wire [8:0] s_x,
 input wire [7:0] s_y, input wire s_sof,s_eol,s_eof,
 input wire [151:0] s_key, input wire abort_frame,
 input wire commit_valid, output wire commit_ready,
 input wire commit_good, input wire [151:0] commit_key,
 output wire frame_valid, input wire frame_ready,
 output reg [151:0] frame_key, output reg [7:0] frame_count,
 output reg [16:0] candidate_count,
 output wire m_valid, input wire m_ready,
 output wire [8:0] m_x, output wire [7:0] m_y,m_score,
 output wire [6:0] m_tile,
 output reg frame_done,frame_dropped,
 output reg [31:0] input_errors,commit_errors,
 output reg score_valid, output reg [8:0] score_x,
 output reg [7:0] score_y,score_value
);
 localparam IDLE=0,RECV=1,DRAIN=2,COUNT=3,WAIT_COMMIT=4,HEADER=5,EMIT=6;
 reg [2:0] state;
 reg [8:0] expect_x; reg [7:0] expect_y;
 reg frame_bad,commit_seen,commit_value;
 reg [5:0] drain_count;
 reg [7:0] scan_index;
 reg [7:0] best_score[0:127];
 reg [8:0] best_x[0:127]; reg [7:0] best_y[0:127];
 wire take=s_valid&&s_ready;
 assign s_ready=(state==IDLE || state==RECV)&&!abort_frame;
 assign commit_ready=(state>=RECV&&state<=WAIT_COMMIT)&&!commit_seen&&!abort_frame;
 assign frame_valid=state==HEADER;
 assign m_valid=state==EMIT&&scan_index<128&&best_score[scan_index[6:0]]!=0;
 assign m_x=best_x[scan_index[6:0]];
 assign m_y=best_y[scan_index[6:0]];
 assign m_score=best_score[scan_index[6:0]];
 assign m_tile=scan_index[6:0];

 // Six prior rows at each column, one synchronous block RAM read and write.
 // No reset on RAM contents: eligibility starts only after six fresh rows.
 reg [47:0] line_memory[0:319] /* synthesis syn_ramstyle="block_ram" */;
 reg [47:0] line_q;
 reg rd_valid; reg [7:0] rd_mono,rd_y;reg [8:0] rd_x;
 reg [7:0] window[0:6][0:6];
 wire ingest=take&&(state==RECV || s_sof);
 always @(posedge clk) begin
  if(ingest) line_q<=line_memory[s_x];
  if(rd_valid) line_memory[rd_x]<={line_q[39:0],rd_mono};
 end
 integer r,c,i,j;
 // Ring mapping in the oldest-to-newest 7x7 window (center [3][3]).
 function [7:0] ring;
  input integer n;
  begin
   case(n)
    0:ring=window[0][3]; 1:ring=window[0][4];
    2:ring=window[1][5]; 3:ring=window[2][6];
    4:ring=window[3][6]; 5:ring=window[4][6];
    6:ring=window[5][5]; 7:ring=window[6][4];
    8:ring=window[6][3]; 9:ring=window[6][2];
    10:ring=window[5][1]; 11:ring=window[4][0];
    12:ring=window[3][0]; 13:ring=window[2][0];
    14:ring=window[1][1]; default:ring=window[0][2];
   endcase
  end
 endfunction
 function [7:0] mn; input[7:0]a,b;begin mn=a<b?a:b;end endfunction
 function [7:0] mx; input[7:0]a,b;begin mx=a>b?a:b;end endfunction
 // Width stays unsigned 8-bit after clamped signed contrast. The score is
 // maximum over bright/dark 16 cyclic nine-point minimum contrasts.
 reg [7:0] bright[0:15],dark[0:15];
 reg [7:0] b2[0:15],d2[0:15],b4[0:15],d4[0:15],b8[0:15],d8[0:15];
 reg [7:0] bdelay0[0:15],ddelay0[0:15],bdelay1[0:15],ddelay1[0:15],bdelay2[0:15],ddelay2[0:15];
 reg [7:0] arc[0:15],max8[0:7],max4[0:3],max2[0:1],max1;
 reg [8:0] px[0:8]; reg[7:0]py[0:8]; reg[8:0]pv;
 reg win_valid; reg [8:0]win_x;reg[7:0]win_y;
 reg [6:0] tile_index;reg eligible;
 reg winner_valid;reg[6:0]winner_tile;reg[7:0]winner_value,winner_old,winner_y;
 reg[8:0]winner_x;reg forwarding_valid;reg[6:0]forwarding_tile;reg[7:0]forwarding_score;
 // Precompute the constant tile division/geometry with the preceding score
 // stage. This keeps division and the 128-record winner mux off one path.
 wire [6:0] score_tile=tile_index;
 wire [7:0] final_score=eligible&&max1>20?max1:0;
 wire [7:0] winner_reference=forwarding_valid&&forwarding_tile==winner_tile
      ?mx(winner_old,forwarding_score):winner_old;
 always @(posedge clk) begin
  if(rst||abort_frame) begin
   rd_valid<=0;win_valid<=0;pv<=0;score_valid<=0;score_x<=0;score_y<=0;score_value<=0;tile_index<=0;eligible<=0;
   for(r=0;r<7;r=r+1)for(c=0;c<7;c=c+1)window[r][c]<=0;
  end else begin
   rd_valid<=ingest;
   if(ingest)begin rd_mono<=s_mono;rd_x<=s_x;rd_y<=s_y;end
   win_valid<=rd_valid&&rd_x>=6&&rd_y>=6;
   if(rd_valid)begin
    for(r=0;r<7;r=r+1)begin
     for(c=0;c<6;c=c+1)window[r][c]<=rd_x==0?0:window[r][c+1];
     if(r<6) window[r][6]<=line_q[(5-r)*8+:8];
     else window[r][6]<=rd_mono;
    end
    win_x<=rd_x-3;win_y<=rd_y-3;
   end
   pv<={pv[7:0],win_valid};px[0]<=win_x;py[0]<=win_y;
   for(j=1;j<9;j=j+1)begin px[j]<=px[j-1];py[j]<=py[j-1];end
   for(i=0;i<16;i=i+1)begin
    bright[i]<=ring(i)>window[3][3]?ring(i)-window[3][3]:0;
    dark[i]<=window[3][3]>ring(i)?window[3][3]-ring(i):0;
    b2[i]<=mn(bright[i],bright[(i+1)%16]);d2[i]<=mn(dark[i],dark[(i+1)%16]);
    b4[i]<=mn(b2[i],b2[(i+2)%16]);d4[i]<=mn(d2[i],d2[(i+2)%16]);
    b8[i]<=mn(b4[i],b4[(i+4)%16]);d8[i]<=mn(d4[i],d4[(i+4)%16]);
    bdelay0[i]<=bright[i];ddelay0[i]<=dark[i];
    bdelay1[i]<=bdelay0[i];ddelay1[i]<=ddelay0[i];
    bdelay2[i]<=bdelay1[i];ddelay2[i]<=ddelay1[i];
    arc[i]<=mx(mn(b8[i],bdelay2[(i+8)%16]),mn(d8[i],ddelay2[(i+8)%16]));
   end
   for(i=0;i<8;i=i+1)max8[i]<=mx(arc[2*i],arc[2*i+1]);
   for(i=0;i<4;i=i+1)max4[i]<=mx(max8[2*i],max8[2*i+1]);
   for(i=0;i<2;i=i+1)max2[i]<=mx(max4[2*i],max4[2*i+1]);
   max1<=mx(max2[0],max2[1]);
   tile_index<=(px[7]/20)+16*(py[7]/30);
   eligible<=px[7]>=4&&px[7]<316&&py[7]>=4&&py[7]<236
               &&!(px[7]<=194&&py[7]<=8);
   score_valid<=pv[8];score_x<=px[8];score_y<=py[8];score_value<=final_score;
  end
 end
 always @(posedge clk) begin
  if(rst)begin
   state<=IDLE;frame_key<=0;frame_count<=0;candidate_count<=0;
   expect_x<=0;expect_y<=0;frame_bad<=0;commit_seen<=0;commit_value<=0;
   drain_count<=0;scan_index<=0;frame_done<=0;frame_dropped<=0;input_errors<=0;commit_errors<=0;
   winner_valid<=0;forwarding_valid<=0;winner_tile<=0;winner_value<=0;winner_old<=0;winner_x<=0;winner_y<=0;
   forwarding_tile<=0;forwarding_score<=0;
   for(i=0;i<128;i=i+1)begin best_score[i]<=0;best_x[i]<=0;best_y[i]<=0;end
  end else begin
   frame_done<=0;frame_dropped<=0;
   winner_valid<=0;forwarding_valid<=0;
   if(abort_frame)begin state<=IDLE;frame_dropped<=state!=IDLE;frame_bad<=0;commit_seen<=0;end
   else begin
    if(commit_valid&&commit_ready)begin
     if(commit_key==frame_key)begin commit_seen<=1;commit_value<=commit_good;end
     else commit_errors<=commit_errors+1'b1;
    end
    if(pv[8]&&(state==RECV||state==DRAIN)&&!frame_bad&&final_score!=0)begin
     candidate_count<=candidate_count+1'b1;
     winner_valid<=1;winner_tile<=score_tile;winner_value<=final_score;
     winner_old<=best_score[score_tile];winner_x<=px[8];winner_y<=py[8];
    end
    // Read the selected winner in its own cycle. A same-tile write from the
    // previous cycle bypasses the read-before-write snapshot; no pixel stalls.
    if(winner_valid&&(state==RECV||state==DRAIN)&&!frame_bad)begin
     if(winner_value>winner_reference)begin
      best_score[winner_tile]<=winner_value;best_x[winner_tile]<=winner_x;best_y[winner_tile]<=winner_y;
      forwarding_valid<=1;forwarding_tile<=winner_tile;forwarding_score<=winner_value;
     end
    end
    case(state)
     IDLE:if(take)begin
      if(s_sof&&s_x==0&&s_y==0&&!s_eol&&!s_eof&&s_key[143:80]!=0&&s_key[47:32]<=255)begin
       state<=RECV;frame_key<=s_key;frame_count<=0;candidate_count<=0;
       frame_bad<=0;commit_seen<=0;expect_x<=1;expect_y<=0;
       for(i=0;i<128;i=i+1)best_score[i]<=0;
      end else input_errors<=input_errors+1'b1;
     end
     RECV:if(take)begin
      if(s_sof||s_x!=expect_x||s_y!=expect_y||s_key!=frame_key
         ||s_eol!=(s_x==319)||s_eof!=(s_x==319&&s_y==239))begin
       frame_bad<=1;input_errors<=input_errors+1'b1;
      end
      if(s_eof||expect_x==319&&expect_y==239)begin state<=DRAIN;drain_count<=0;end
      if(expect_x==319)begin expect_x<=0;expect_y<=expect_y+1'b1;end
      else expect_x<=expect_x+1'b1;
     end
     DRAIN:if(drain_count==20)begin
      if(frame_bad)begin state<=IDLE;frame_dropped<=1;end
      else begin state<=COUNT;scan_index<=0;frame_count<=0;end
     end else drain_count<=drain_count+1'b1;
     COUNT:begin
      if(best_score[scan_index[6:0]]!=0)frame_count<=frame_count+1'b1;
      if(scan_index==127)state<=WAIT_COMMIT;else scan_index<=scan_index+1'b1;
     end
     WAIT_COMMIT:if(commit_seen)begin
      if(commit_value)state<=HEADER;else begin state<=IDLE;frame_dropped<=1;end
     end
     HEADER:if(frame_ready)begin state<=EMIT;scan_index<=0;end
     EMIT:if(scan_index==128)begin state<=IDLE;frame_done<=1;end
      else if(!m_valid||m_ready)scan_index<=scan_index+1'b1;
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule

// Source snapshot: rtl/feature/pg100_feature_publisher.v
// Bounded SW-24 FEATURE payload producer. Caller serializer supplies PGT2
// envelope/CRC and aborts an active datagram when cancel_packet is asserted.
module pg100_feature_publisher(
 input wire clk,rst,
 input wire core_frame_valid,output wire core_frame_ready,
 input wire[151:0]core_frame_key,input wire[7:0]core_frame_count,
 input wire[16:0]core_candidate_count,
 input wire core_record_valid,output wire core_record_ready,
 input wire[8:0]core_x,input wire[7:0]core_y,core_score,input wire[6:0]core_tile,
 input wire core_frame_done,core_frame_dropped,output reg abort_core,
 input wire[63:0]now_us,frame_timestamp_us,frame_deadline_us,
 input wire permit_valid,input wire[151:0]permit_key,input wire[31:0]permit_epoch,
 input wire invalidate,input wire[31:0]sequence_base,
 output wire request_valid,input wire request_ready,
 output wire[7:0]message_type,output wire[151:0]origin_key,
 output wire[31:0]packet_epoch,tx_sequence,
 output wire[63:0]timestamp_us,deadline_us,
 output wire[7:0]status,output wire[15:0]invalid_reason,payload_length,
 output wire[15:0]fragment_index,fragment_count,
 output wire[1:0]destination_peer,
 output wire[7:0]payload_data,output wire payload_valid,
 input wire payload_ready,output wire payload_last,
 input wire send_done,send_abort,output reg cancel_packet,
 output reg published,discarded,output reg[31:0]malformed_frames,cancelled_frames
);
 localparam IDLE=0,COLLECT=1,REQUEST=2,PAYLOAD=3,WAIT_TX=4;
 reg[2:0]state;
 reg[151:0]key;reg[31:0]epoch,seq;reg[63:0]stamp,deadline;
 reg[7:0]count,received;reg[6:0]last_tile;reg have_tile;
 reg frag;reg[1:0]peer;reg[9:0]byte_index;
 // Source record RAM is bounded to 128x64, one synchronous block read port.
 reg[63:0]record_memory[0:127] /* synthesis syn_ramstyle="block_ram" */;
 reg[6:0]read_address;reg[63:0]read_q,current_word;
 always @(posedge clk) read_q<=record_memory[read_address];
 wire take_record=core_record_valid&&core_record_ready;
 wire[15:0]qx=({7'd0,core_x}<<6)+({7'd0,core_x}<<5)+16'd40;
 wire[15:0]qy=({8'd0,core_y}<<6)+({8'd0,core_y}<<3)+16'd28;
 always @(posedge clk)if(take_record)record_memory[received[6:0]]<={qx,qy,8'd0,core_score,16'd1};
 wire active=state!=IDLE;
 wire stale=active&&(!permit_valid||permit_key!=key||permit_epoch!=epoch||now_us>=deadline||invalidate);
 wire bad_header=core_frame_count>128||core_candidate_count<core_frame_count||core_candidate_count>76800
      ||((core_frame_count==0)!=(core_candidate_count==0))||core_frame_key[143:80]==0||core_frame_key[47:32]>255
      ||!permit_valid||permit_key!=core_frame_key||frame_timestamp_us>now_us||frame_deadline_us<=now_us||invalidate;
 wire[6:0]record_tile=core_x/20+16*(core_y/30);
 wire bad_record=state==COLLECT&&core_record_valid&&(
      received>=count||core_score<=20||core_x<4||core_x>=316||core_y<4||core_y>=236
      ||(core_x<=194&&core_y<=8)||core_tile!=record_tile||(have_tile&&core_tile<=last_tile));
 assign core_frame_ready=state==IDLE;
 assign core_record_ready=state==COLLECT&&!stale&&received<count;
 wire[7:0]nrecords=count>118?(frag?count-118:8'd118):count;
 assign request_valid=state==REQUEST&&!stale;
 assign message_type=8'd2;assign origin_key=key;assign packet_epoch=epoch;
 assign tx_sequence=seq+frag;assign timestamp_us=stamp;assign deadline_us=deadline;
 assign status=count==0?8'd2:8'd0;assign invalid_reason=count==0?16'd12:16'd0;
 assign payload_length=16'd8+{5'd0,nrecords,3'd0};
 assign fragment_count=count>118?16'd2:16'd1;assign fragment_index={15'd0,frag};
 assign destination_peer=peer;
 wire[63:0]prefix={8'd0,count,8'd1,8'd1,16'd1920,16'd1080};
 assign payload_valid=state==PAYLOAD&&!stale;
 assign payload_last=byte_index==payload_length-1;
 assign payload_data=byte_index<8?prefix[63-byte_index[2:0]*8-:8]:current_word[63-byte_index[2:0]*8-:8];
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;key<=0;epoch<=0;seq<=0;stamp<=0;deadline<=0;count<=0;received<=0;last_tile<=0;have_tile<=0;
   frag<=0;peer<=1;byte_index<=0;read_address<=0;current_word<=0;
   abort_core<=0;cancel_packet<=0;published<=0;discarded<=0;malformed_frames<=0;cancelled_frames<=0;
  end else begin
   abort_core<=0;cancel_packet<=0;published<=0;discarded<=0;
   if(active&&(stale||send_abort||(state==COLLECT&&core_frame_dropped)||(state==COLLECT&&core_frame_key!=key)||bad_record))begin
    state<=IDLE;abort_core<=1;cancel_packet<=1;discarded<=1;
    if(bad_record||(state==COLLECT&&core_frame_key!=key))malformed_frames<=malformed_frames+1'b1;
    else cancelled_frames<=cancelled_frames+1'b1;
   end else case(state)
    IDLE:if(core_frame_valid)begin
     if(bad_header)begin abort_core<=1;discarded<=1;malformed_frames<=malformed_frames+1'b1;end
     else begin
      state<=COLLECT;key<=core_frame_key;count<=core_frame_count;epoch<=permit_epoch;seq<=sequence_base;
      stamp<=frame_timestamp_us;deadline<=frame_deadline_us;received<=0;have_tile<=0;peer<=1;frag<=0;
     end
    end
    COLLECT:begin
     if(take_record)begin received<=received+1'b1;last_tile<=core_tile;have_tile<=1;end
     if(core_frame_done)begin
      if(received+take_record!=count)begin
       state<=IDLE;abort_core<=1;discarded<=1;malformed_frames<=malformed_frames+1'b1;
      end else begin state<=REQUEST;read_address<=0;end
     end
    end
    REQUEST:if(request_ready)begin state<=PAYLOAD;byte_index<=0;end
    PAYLOAD:if(payload_ready)begin
     byte_index<=byte_index+1'b1;
     if(byte_index==7)current_word<=read_q;
     else if(byte_index>=8)begin
      // Prefetch on the first byte and switch only after accepted last byte.
      // Thus a stalled last byte never changes despite the RAM read advancing.
      if(byte_index[2:0]==0)read_address<=read_address+1'b1;
      if(byte_index[2:0]==7)current_word<=read_q;
     end
     if(payload_last)state<=WAIT_TX;
    end
    WAIT_TX:if(send_done)begin
     if(!frag&&count>118)begin frag<=1;read_address<=118;state<=REQUEST;end
     else if(peer==1)begin peer<=2;frag<=0;read_address<=0;state<=REQUEST;end
     else begin state<=IDLE;published<=1;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Source snapshot: rtl/feature/pg100_feature_transport.v
// SW-23/24 compute -> validated records -> PGT2 UDP datagram producer.
// A leased, complete DDR frame supplies key and pixel ready contract. Physical
// HDMI input, DDR reader/scheduler and abort-aware network-slot owner are SW-38.
module pg100_feature_transport(
 input wire clk,rst,s_valid,output wire s_ready,
 input wire[7:0]s_mono,input wire[8:0]s_x,input wire[7:0]s_y,
 input wire s_sof,s_eol,s_eof,input wire[151:0]s_key,input wire abort_frame,
 input wire commit_valid,output wire commit_ready,input wire commit_good,input wire[151:0]commit_key,
 input wire[63:0]now_us,frame_timestamp_us,frame_deadline_us,
 input wire permit_valid,input wire[151:0]permit_key,input wire[31:0]permit_epoch,
 input wire invalidate,input wire[31:0]sequence_base,
 output wire m_hdr_valid,input wire m_hdr_ready,output wire[10:0]m_length,output wire[1:0]m_peer,
 output wire[7:0]m_data,output wire m_valid,input wire m_ready,output wire m_last,m_abort,
 output wire published,discarded,output wire[7:0]result_count,
 output wire[31:0]input_errors,commit_errors,malformed_frames,cancelled_frames,rejected_packets
);
 wire cfv,cfr,crv,crr,cfd,cfx,abort_core;
 wire[151:0]cfk;wire[7:0]cy,cs;wire[8:0]cx;wire[6:0]ct;wire[16:0]cc;
 pg100_feature_core core(.clk(clk),.rst(rst),.s_valid(s_valid),.s_ready(s_ready),.s_mono(s_mono),.s_x(s_x),.s_y(s_y),
  .s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_key(s_key),.abort_frame(abort_frame||abort_core),
  .commit_valid(commit_valid),.commit_ready(commit_ready),.commit_good(commit_good),.commit_key(commit_key),
  .frame_valid(cfv),.frame_ready(cfr),.frame_key(cfk),.frame_count(result_count),.candidate_count(cc),
  .m_valid(crv),.m_ready(crr),.m_x(cx),.m_y(cy),.m_score(cs),.m_tile(ct),
  .frame_done(cfd),.frame_dropped(cfx),.input_errors(input_errors),.commit_errors(commit_errors),
  .score_valid(),.score_x(),.score_y(),.score_value());
 wire request_valid,request_ready,payload_valid,payload_ready,payload_last,send_done,send_abort,cancel_packet;
 wire[7:0]message_type,status,payload_data;wire[151:0]origin_key;
 wire[31:0]packet_epoch,tx_sequence;wire[63:0]timestamp_us,deadline_us;
 wire[15:0]invalid_reason,payload_length,fragment_index,fragment_count;wire[1:0]destination_peer;
 wire pub_discarded,req_rejected;
 pg100_feature_publisher publisher(.clk(clk),.rst(rst),.core_frame_valid(cfv),.core_frame_ready(cfr),
  .core_frame_key(cfk),.core_frame_count(result_count),.core_candidate_count(cc),
  .core_record_valid(crv),.core_record_ready(crr),.core_x(cx),.core_y(cy),.core_score(cs),.core_tile(ct),
  .core_frame_done(cfd),.core_frame_dropped(cfx),.abort_core(abort_core),
  .now_us(now_us),.frame_timestamp_us(frame_timestamp_us),.frame_deadline_us(frame_deadline_us),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.invalidate(invalidate),.sequence_base(sequence_base),
  .request_valid(request_valid),.request_ready(request_ready),.message_type(message_type),.origin_key(origin_key),
  .packet_epoch(packet_epoch),.tx_sequence(tx_sequence),.timestamp_us(timestamp_us),.deadline_us(deadline_us),
  .status(status),.invalid_reason(invalid_reason),.payload_length(payload_length),.fragment_index(fragment_index),.fragment_count(fragment_count),
  .destination_peer(destination_peer),.payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),.payload_last(payload_last),
  .send_done(send_done),.send_abort(send_abort||req_rejected),.cancel_packet(cancel_packet),
  .published(published),.discarded(pub_discarded),.malformed_frames(malformed_frames),.cancelled_frames(cancelled_frames));
 pg_pgt2_datagram_tx #(.PRODUCER_ID(100)) serializer(.clk(clk),.rst(rst),
  .req_valid(request_valid),.req_ready(request_ready),.req_message_type(message_type),.req_status(status),.req_reason(invalid_reason),
  .req_payload_length(payload_length[10:0]),.req_key(origin_key),.req_sequence(tx_sequence),.req_epoch(packet_epoch),
  .req_timestamp_us(timestamp_us),.req_deadline_us(deadline_us),.req_fragment_index(fragment_index),.req_fragment_count(fragment_count),.req_peer(destination_peer),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.now_us(now_us),.invalidate(invalidate||cancel_packet),
  .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),.payload_last(payload_last),
  .m_hdr_valid(m_hdr_valid),.m_hdr_ready(m_hdr_ready),.m_length(m_length),.m_peer(m_peer),
  .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),.m_abort(m_abort),
  .busy(),.send_done(send_done),.send_abort(send_abort),.req_rejected(req_rejected),.rejected_packets(rejected_packets));
 assign discarded=pub_discarded||cfx;
endmodule

// Source snapshot: rtl/feature_v2/pg100_work_ram_v2.v
// 5 explicit 16K banks avoid ADS rounding a 76,800-deep frame to 128K.
// One registered read address/port; shared across NMS and selection passes.
module pg100_work_ram_v2 #(parameter WIDTH=8)(
 input wire clk,input wire wr_en,input wire[16:0]wr_address,input wire[WIDTH-1:0]wr_data,
 input wire rd_en,input wire[16:0]rd_address,output reg[WIDTH-1:0]rd_data);
 reg[2:0]bank_q;
 wire[WIDTH-1:0]q[0:4];
 genvar bank;
 generate for(bank=0;bank<5;bank=bank+1)begin:banked
  reg[WIDTH-1:0]memory[0:16383] /* synthesis syn_ramstyle="block_ram" */;
  reg[WIDTH-1:0]read_q;
  always @(posedge clk)begin
   if(wr_en&&wr_address[16:14]==bank)memory[wr_address[13:0]]<=wr_data;
   if(rd_en&&rd_address[16:14]==bank)read_q<=memory[rd_address[13:0]];
  end
  assign q[bank]=read_q;
 end endgenerate
 always @(posedge clk)if(rd_en)bank_q<=rd_address[16:14];
 always @*case(bank_q)
  0:rd_data=q[0];1:rd_data=q[1];2:rd_data=q[2];3:rd_data=q[3];4:rd_data=q[4];default:rd_data=0;
 endcase
endmodule

// Source snapshot: rtl/feature_v2/pg100_fast9_score_v2.v
// Independent V2 score pipeline: no tile winner CAM or output selection.
// Geometry is masked before NMS to the full R5 support and border6.
module pg100_fast9_score_v2(
 input wire clk,rst,s_valid,input wire[7:0]s_mono,
 input wire[8:0]s_x,input wire[7:0]s_y,
 output reg score_valid,output reg[8:0]score_x,
 output reg[7:0]score_y,score_value);
 // Six prior rows at each column, one synchronous block RAM read and write.
 // No reset on RAM contents: eligibility starts only after six fresh rows.
 reg [47:0] line_memory[0:319] /* synthesis syn_ramstyle="block_ram" */;
 reg [47:0] line_q;
 reg rd_valid; reg [7:0] rd_mono,rd_y;reg [8:0] rd_x;
 reg [7:0] window[0:6][0:6];
 wire ingest=s_valid;
 always @(posedge clk) begin
  if(ingest) line_q<=line_memory[s_x];
  if(rd_valid) line_memory[rd_x]<={line_q[39:0],rd_mono};
 end
 integer r,c,i,j;
 // Ring mapping in the oldest-to-newest 7x7 window (center [3][3]).
 function [7:0] ring;
  input integer n;
  begin
   case(n)
    0:ring=window[0][3]; 1:ring=window[0][4];
    2:ring=window[1][5]; 3:ring=window[2][6];
    4:ring=window[3][6]; 5:ring=window[4][6];
    6:ring=window[5][5]; 7:ring=window[6][4];
    8:ring=window[6][3]; 9:ring=window[6][2];
    10:ring=window[5][1]; 11:ring=window[4][0];
    12:ring=window[3][0]; 13:ring=window[2][0];
    14:ring=window[1][1]; default:ring=window[0][2];
   endcase
  end
 endfunction
 function [7:0] mn; input[7:0]a,b;begin mn=a<b?a:b;end endfunction
 function [7:0] mx; input[7:0]a,b;begin mx=a>b?a:b;end endfunction
 // Width stays unsigned 8-bit after clamped signed contrast. The score is
 // maximum over bright/dark 16 cyclic nine-point minimum contrasts.
 reg [7:0] bright[0:15],dark[0:15];
 reg [7:0] b2[0:15],d2[0:15],b4[0:15],d4[0:15],b8[0:15],d8[0:15];
 reg [7:0] bdelay0[0:15],ddelay0[0:15],bdelay1[0:15],ddelay1[0:15],bdelay2[0:15],ddelay2[0:15];
 reg [7:0] arc[0:15],max8[0:7],max4[0:3],max2[0:1],max1;
 reg [8:0] px[0:8]; reg[7:0]py[0:8]; reg[8:0]pv;
 reg win_valid; reg [8:0]win_x;reg[7:0]win_y;
 reg eligible;
 wire[7:0]final_score=eligible&&max1>20?max1:0;
 always @(posedge clk) begin
  if(rst) begin
   rd_valid<=0;win_valid<=0;pv<=0;score_valid<=0;score_x<=0;score_y<=0;score_value<=0;eligible<=0;
   for(r=0;r<7;r=r+1)for(c=0;c<7;c=c+1)window[r][c]<=0;
  end else begin
   rd_valid<=ingest;
   if(ingest)begin rd_mono<=s_mono;rd_x<=s_x;rd_y<=s_y;end
   win_valid<=rd_valid&&rd_x>=6&&rd_y>=6;
   if(rd_valid)begin
    for(r=0;r<7;r=r+1)begin
     for(c=0;c<6;c=c+1)window[r][c]<=rd_x==0?0:window[r][c+1];
     if(r<6) window[r][6]<=line_q[(5-r)*8+:8];
     else window[r][6]<=rd_mono;
    end
    win_x<=rd_x-3;win_y<=rd_y-3;
   end
   pv<={pv[7:0],win_valid};px[0]<=win_x;py[0]<=win_y;
   for(j=1;j<9;j=j+1)begin px[j]<=px[j-1];py[j]<=py[j-1];end
   for(i=0;i<16;i=i+1)begin
    bright[i]<=ring(i)>window[3][3]?ring(i)-window[3][3]:0;
    dark[i]<=window[3][3]>ring(i)?window[3][3]-ring(i):0;
    b2[i]<=mn(bright[i],bright[(i+1)%16]);d2[i]<=mn(dark[i],dark[(i+1)%16]);
    b4[i]<=mn(b2[i],b2[(i+2)%16]);d4[i]<=mn(d2[i],d2[(i+2)%16]);
    b8[i]<=mn(b4[i],b4[(i+4)%16]);d8[i]<=mn(d4[i],d4[(i+4)%16]);
    bdelay0[i]<=bright[i];ddelay0[i]<=dark[i];
    bdelay1[i]<=bdelay0[i];ddelay1[i]<=ddelay0[i];
    bdelay2[i]<=bdelay1[i];ddelay2[i]<=ddelay1[i];
    arc[i]<=mx(mn(b8[i],bdelay2[(i+8)%16]),mn(d8[i],ddelay2[(i+8)%16]));
   end
   for(i=0;i<8;i=i+1)max8[i]<=mx(arc[2*i],arc[2*i+1]);
   for(i=0;i<4;i=i+1)max4[i]<=mx(max8[2*i],max8[2*i+1]);
   for(i=0;i<2;i=i+1)max2[i]<=mx(max4[2*i],max4[2*i+1]);
   max1<=mx(max2[0],max2[1]);
   eligible<=px[7]>=6&&px[7]<314&&py[7]>=6&&py[7]<234
               &&!(px[7]<=196&&py[7]<=10);
   score_valid<=pv[8];score_x<=px[8];score_y<=py[8];score_value<=final_score;
  end
 end
endmodule

// Source snapshot: rtl/feature_v2/pg100_feature_core_v2.v
// MC_GAUSS_FAST9_NMS_TOP96_V2. Hardware-First budget: feature_v2_hardware_preflight.
// Complete committed, ready-capable working frame; single-frame bounded RAM.
module pg100_feature_core_v2(
 input wire clk,rst,s_valid,output wire s_ready,
 input wire[7:0]s_mono,input wire[8:0]s_x,input wire[7:0]s_y,
 input wire s_sof,s_eol,s_eof,input wire[151:0]s_key,input wire abort_frame,
 input wire commit_valid,output wire commit_ready,input wire commit_good,input wire[151:0]commit_key,
 output wire frame_valid,input wire frame_ready,output reg[151:0]frame_key,
 output reg[7:0]frame_count,output reg[16:0]candidate_count,
 output wire m_valid,input wire m_ready,output wire[8:0]m_x,output wire[7:0]m_y,m_score,
 output wire[6:0]m_tile,output reg frame_done,frame_dropped,
 output reg[31:0]input_errors,commit_errors,
 output wire score_valid,output wire[8:0]score_x,output wire[7:0]score_y,score_value
);
 localparam IDLE=0,RECV=1,WAIT_COMMIT=2,CLEAR_HIST=3,BLUR_BEGIN=4,BLUR_READ=5,
   BLUR_DRAIN=6,BLUR_FEED=7,SCORE_DRAIN=8,NMS_BEGIN=9,NMS_READ=10,NMS_DRAIN=11,
   HIST_READ=12,HIST_WRITE=13,CUTOFF_READ=14,CUTOFF_WAIT=15,CUTOFF_TEST=16,
   SELECT_READ=17,SELECT_WAIT=18,SELECT_TEST=19,HEADER=20,EMIT_PREFETCH=21,EMIT_WAIT=22,EMIT=23;
 reg[4:0]state;
 reg[8:0]expect_x,x;reg[7:0]expect_y,y;
 reg[16:0]input_address,center_address;
 reg bad_frame,commit_seen,commit_value;
 reg[3:0]tap,pipe_tap;reg pipe_valid;
 reg[11:0]sum;reg[7:0]filtered;
 reg[5:0]drain;
 reg[7:0]center_score,cutoff,cutoff_index;
 reg peak,clear_done;reg[16:0]remaining,ties_left;
 reg[7:0]selected;reg[6:0]emit_index;
 wire take=s_valid&&s_ready;
 assign s_ready=(state==IDLE||state==RECV)&&!abort_frame;
 assign commit_ready=(state==RECV||state==WAIT_COMMIT)&&!commit_seen&&!abort_frame;
 assign frame_valid=state==HEADER;
 assign m_valid=state==EMIT;
 assign m_tile=emit_index; // V2 row-major record ordinal, NOT the V1 tile ID.

 reg[16:0]histogram[0:255] /* synthesis syn_ramstyle="block_ram" */;
 reg[24:0]records[0:95] /* synthesis syn_ramstyle="block_ram" */;
 wire[7:0]mono_q,score_q;wire peak_q;reg[16:0]hist_q;
 reg[24:0]record_q;
 assign m_x=record_q[24:16];assign m_y=record_q[15:8];assign m_score=record_q[7:0];
 wire blur_valid=state==BLUR_FEED;
 pg100_fast9_score_v2 scorer(.clk(clk),.rst(rst||abort_frame||state==CLEAR_HIST),
   .s_valid(blur_valid),.s_mono(filtered),.s_x(x),.s_y(y),
   .score_valid(score_valid),.score_x(score_x),.score_y(score_y),.score_value(score_value));

 // Nine serial, registered block reads; no giant mux/parallel sorter.
 function[16:0]tap_address;
   input[16:0]a;input[3:0]t;
   begin case(t)
    0:tap_address=a-321;1:tap_address=a-320;2:tap_address=a-319;
    3:tap_address=a-1;4:tap_address=a;5:tap_address=a+1;
    6:tap_address=a+319;7:tap_address=a+320;default:tap_address=a+321;
   endcase end
 endfunction
 function[11:0]weighted;
   input[7:0]v;input[3:0]t;
   begin case(t)
    4:weighted={2'b0,v,2'b0};1,3,5,7:weighted={3'b0,v,1'b0};default:weighted={4'b0,v};
   endcase end
 endfunction
 wire[11:0]sum_next=sum+weighted(mono_q,pipe_tap);
 wire[16:0]mono_read_address=tap_address(center_address,tap);
 wire[16:0]score_read_address=state==NMS_READ?tap_address(center_address,tap):center_address;
 wire[16:0]score_write_address=score_y*320+score_x;
 wire[7:0]hist_read_address=state==HIST_READ?center_score:cutoff_index;
 pg100_work_ram_v2 #(.WIDTH(8)) mono_ram(.clk(clk),.wr_en(take),
  .wr_address(state==IDLE?17'd0:input_address),.wr_data(s_mono),
  .rd_en(state==BLUR_READ),.rd_address(mono_read_address),.rd_data(mono_q));
 pg100_work_ram_v2 #(.WIDTH(8)) score_ram(.clk(clk),.wr_en(score_valid),
  .wr_address(score_write_address),.wr_data(score_value),
  .rd_en(state==NMS_READ||state==SELECT_READ),.rd_address(score_read_address),.rd_data(score_q));
 pg100_work_ram_v2 #(.WIDTH(1)) peak_ram(.clk(clk),
  .wr_en(state==NMS_DRAIN&&!pipe_valid),.wr_address(center_address),.wr_data(peak&&center_score!=0),
  .rd_en(state==SELECT_READ),.rd_address(center_address),.rd_data(peak_q));
 always @(posedge clk)begin
  if(state==CLEAR_HIST)histogram[cutoff_index]<=0;
  else if(state==HIST_WRITE)histogram[center_score]<=hist_q+1'b1;
  if(state==HIST_READ||state==CUTOFF_READ)hist_q<=histogram[hist_read_address];
  if(state==SELECT_TEST&&peak_q&&(score_q>cutoff||score_q==cutoff&&ties_left!=0)&&selected<96)
    records[selected[6:0]]<={x,y,score_q};
  if(state==EMIT_PREFETCH)record_q<=records[emit_index];
 end
 task next_pixel;
  begin
   center_address<=center_address+1'b1;
   if(x==319)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
  end
 endtask
 task next_nms_pixel;
  begin
   if(x==313)begin x<=6;y<=y+1'b1;center_address<=center_address+17'd13;end
   else begin x<=x+1'b1;center_address<=center_address+1'b1;end
  end
 endtask
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;frame_key<=0;frame_count<=0;candidate_count<=0;
   frame_done<=0;frame_dropped<=0;input_errors<=0;commit_errors<=0;
   expect_x<=0;expect_y<=0;input_address<=0;bad_frame<=0;commit_seen<=0;commit_value<=0;
   x<=0;y<=0;center_address<=0;tap<=0;pipe_tap<=0;pipe_valid<=0;sum<=0;filtered<=0;
   drain<=0;center_score<=0;peak<=0;cutoff<=0;cutoff_index<=0;remaining<=0;ties_left<=0;selected<=0;emit_index<=0;clear_done<=0;
  end else begin
   frame_done<=0;frame_dropped<=0;
   if(abort_frame)begin state<=IDLE;frame_dropped<=state!=IDLE;pipe_valid<=0;commit_seen<=0;end
   else begin
    if(commit_valid&&commit_ready)begin
     if(commit_key==frame_key)begin commit_seen<=1;commit_value<=commit_good;end
     else commit_errors<=commit_errors+1'b1;
    end
    case(state)
     IDLE:if(take)begin
      if(s_sof&&s_x==0&&s_y==0&&!s_eol&&!s_eof&&s_key[143:80]!=0&&s_key[47:32]<=255)begin
       state<=RECV;frame_key<=s_key;frame_count<=0;candidate_count<=0;input_address<=1;
       expect_x<=1;expect_y<=0;commit_seen<=0;bad_frame<=0;
      end else input_errors<=input_errors+1'b1;
     end
     RECV:if(take)begin
      if(s_sof||s_x!=expect_x||s_y!=expect_y||s_key!=frame_key||s_eol!=(s_x==319)||s_eof!=(s_x==319&&s_y==239))begin
       bad_frame<=1;input_errors<=input_errors+1'b1;
      end
      if(s_eof||input_address==76799)state<=WAIT_COMMIT;
      input_address<=input_address+1'b1;
      if(expect_x==319)begin expect_x<=0;expect_y<=expect_y+1'b1;end else expect_x<=expect_x+1'b1;
     end
     WAIT_COMMIT:if(bad_frame||commit_seen&&!commit_value)begin state<=IDLE;frame_dropped<=1;end
      else if(commit_seen)begin state<=CLEAR_HIST;cutoff_index<=0;end
     CLEAR_HIST:if(cutoff_index==255)begin state<=BLUR_BEGIN;x<=0;y<=0;center_address<=0;end
      else cutoff_index<=cutoff_index+1'b1;
     BLUR_BEGIN:begin
      sum<=0;tap<=0;pipe_valid<=0;
      if(x==0||x==319||y==0||y==239)begin filtered<=0;state<=BLUR_FEED;end
      else state<=BLUR_READ;
     end
     BLUR_READ:begin
      if(pipe_valid)sum<=sum_next;
      pipe_valid<=1;pipe_tap<=tap;
      if(tap==8)state<=BLUR_DRAIN;else tap<=tap+1'b1;
     end
     BLUR_DRAIN:begin
      filtered<=(sum_next+12'd8)>>4;pipe_valid<=0;state<=BLUR_FEED;
     end
     BLUR_FEED:if(center_address==76799)begin state<=SCORE_DRAIN;drain<=0;end
      else begin next_pixel;state<=BLUR_BEGIN;end
     SCORE_DRAIN:if(drain==24)begin state<=NMS_BEGIN;x<=6;y<=6;center_address<=1926;candidate_count<=0;end
      else drain<=drain+1'b1;
     NMS_BEGIN:begin tap<=0;pipe_valid<=0;peak<=1;center_score<=0;state<=NMS_READ;end
     NMS_READ:begin
      pipe_valid<=1;pipe_tap<=tap;
      if(pipe_valid)begin
       if(pipe_tap==4)center_score<=score_q;
       // First four neighbours use a strict comparison, resolving ties to
       // earliest row-major point. Center is captured halfway through reads.
       if(pipe_tap<4)begin
        // Keep the earlier neighbour maximum until the center arrives.
        if(score_q>=center_score)center_score<=score_q;
       end
       if(pipe_tap==4)peak<=score_q>center_score;
       else if(pipe_tap>4&&score_q>center_score)peak<=0;
      end
      if(tap==8)state<=NMS_DRAIN;else tap<=tap+1'b1;
     end
     NMS_DRAIN:begin
      if(pipe_valid)begin
       if(score_q>center_score)peak<=0;pipe_valid<=0;
      end else begin
       if(peak&&center_score!=0)begin candidate_count<=candidate_count+1'b1;state<=HIST_READ;end
       else if(x==313&&y==233)begin cutoff_index<=255;remaining<=96;state<=CUTOFF_READ;end
       else begin next_nms_pixel;state<=NMS_BEGIN;end
      end
     end
     HIST_READ:state<=HIST_WRITE;
     HIST_WRITE:if(x==313&&y==233)begin cutoff_index<=255;remaining<=96;state<=CUTOFF_READ;end
      else begin next_nms_pixel;state<=NMS_BEGIN;end
     CUTOFF_READ:state<=CUTOFF_WAIT;
     CUTOFF_WAIT:state<=CUTOFF_TEST;
     CUTOFF_TEST:if(hist_q>=remaining||cutoff_index==21)begin
      cutoff<=cutoff_index;ties_left<=remaining;x<=6;y<=6;center_address<=1926;selected<=0;state<=SELECT_READ;
     end else begin remaining<=remaining-hist_q;cutoff_index<=cutoff_index-1'b1;state<=CUTOFF_READ;end
     SELECT_READ:state<=SELECT_WAIT;
     SELECT_WAIT:state<=SELECT_TEST;
     SELECT_TEST:begin
      if(peak_q&&(score_q>cutoff||score_q==cutoff&&ties_left!=0)&&selected<96)begin
       selected<=selected+1'b1;if(score_q==cutoff)ties_left<=ties_left-1'b1;
      end
      if(x==313&&y==233)begin frame_count<=selected+(peak_q&&(score_q>cutoff||score_q==cutoff&&ties_left!=0)&&selected<96);state<=HEADER;end
      else begin next_nms_pixel;state<=SELECT_READ;end
     end
     HEADER:if(frame_ready)begin
      if(frame_count==0)begin state<=IDLE;frame_done<=1;end
      else begin emit_index<=0;state<=EMIT_PREFETCH;end
     end
     EMIT_PREFETCH:state<=EMIT_WAIT;
     EMIT_WAIT:state<=EMIT;
     EMIT:if(m_ready)begin
      if(emit_index==frame_count-1)begin state<=IDLE;frame_done<=1;end
      else begin emit_index<=emit_index+1'b1;state<=EMIT_PREFETCH;end
     end
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule

// Source snapshot: rtl/feature_v2/pg100_feature_publisher_v2.v
// Bounded V2 row-major FEATURE payload producer. Caller serializer supplies PGT2
// envelope/CRC and aborts an active datagram when cancel_packet is asserted.
module pg100_feature_publisher_v2(
 input wire clk,rst,
 input wire core_frame_valid,output wire core_frame_ready,
 input wire[151:0]core_frame_key,input wire[7:0]core_frame_count,
 input wire[16:0]core_candidate_count,
 input wire core_record_valid,output wire core_record_ready,
 input wire[8:0]core_x,input wire[7:0]core_y,core_score,input wire[6:0]core_tile,
 input wire core_frame_done,core_frame_dropped,output reg abort_core,
 input wire[63:0]now_us,frame_timestamp_us,frame_deadline_us,
 input wire permit_valid,input wire[151:0]permit_key,input wire[31:0]permit_epoch,
 input wire invalidate,input wire[31:0]sequence_base,
 output wire request_valid,input wire request_ready,
 output wire[7:0]message_type,output wire[151:0]origin_key,
 output wire[31:0]packet_epoch,tx_sequence,
 output wire[63:0]timestamp_us,deadline_us,
 output wire[7:0]status,output wire[15:0]invalid_reason,payload_length,
 output wire[15:0]fragment_index,fragment_count,
 output wire[1:0]destination_peer,
 output wire[7:0]payload_data,output wire payload_valid,
 input wire payload_ready,output wire payload_last,
 input wire send_done,send_abort,output reg cancel_packet,
 output reg published,discarded,output reg[31:0]malformed_frames,cancelled_frames
);
 localparam IDLE=0,COLLECT=1,REQUEST=2,PAYLOAD=3,WAIT_TX=4;
 reg[2:0]state;
 reg[151:0]key;reg[31:0]epoch,seq;reg[63:0]stamp,deadline;
 reg[7:0]count,received;reg[8:0]last_x;reg[7:0]last_y;reg have_tile;
 reg frag;reg[1:0]peer;reg[9:0]byte_index;
 // Source record RAM is bounded to 128x64, one synchronous block read port.
 reg[63:0]record_memory[0:127] /* synthesis syn_ramstyle="block_ram" */;
 reg[6:0]read_address;reg[63:0]read_q,current_word;
 always @(posedge clk) read_q<=record_memory[read_address];
 wire take_record=core_record_valid&&core_record_ready;
 wire[15:0]qx=({7'd0,core_x}<<6)+({7'd0,core_x}<<5)+16'd40;
 wire[15:0]qy=({8'd0,core_y}<<6)+({8'd0,core_y}<<3)+16'd28;
 always @(posedge clk)if(take_record)record_memory[received[6:0]]<={qx,qy,8'd0,core_score,16'd1};
 wire active=state!=IDLE;
 wire stale=active&&(!permit_valid||permit_key!=key||permit_epoch!=epoch||now_us>=deadline||invalidate);
 wire bad_header=core_frame_count>96||core_candidate_count<core_frame_count||core_candidate_count>76800
      ||((core_frame_count==0)!=(core_candidate_count==0))||core_frame_key[143:80]==0||core_frame_key[47:32]>255
      ||!permit_valid||permit_key!=core_frame_key||frame_timestamp_us>now_us||frame_deadline_us<=now_us||invalidate;
 wire bad_record=state==COLLECT&&core_record_valid&&(
      received>=count||core_score<=20||core_x<6||core_x>=314||core_y<6||core_y>=234
      ||(core_x<=196&&core_y<=10)||core_tile!=received[6:0]||(have_tile&&(core_y<last_y||core_y==last_y&&core_x<=last_x)));
 assign core_frame_ready=state==IDLE;
 assign core_record_ready=state==COLLECT&&!stale&&received<count;
 wire[7:0]nrecords=count>118?(frag?count-118:8'd118):count;
 assign request_valid=state==REQUEST&&!stale;
 assign message_type=8'd2;assign origin_key=key;assign packet_epoch=epoch;
 assign tx_sequence=seq+frag;assign timestamp_us=stamp;assign deadline_us=deadline;
 assign status=count==0?8'd2:8'd0;assign invalid_reason=count==0?16'd12:16'd0;
 assign payload_length=16'd8+{5'd0,nrecords,3'd0};
 assign fragment_count=count>118?16'd2:16'd1;assign fragment_index={15'd0,frag};
 assign destination_peer=peer;
 wire[63:0]prefix={8'd0,count,8'd1,8'd1,16'd1920,16'd1080};
 assign payload_valid=state==PAYLOAD&&!stale;
 assign payload_last=byte_index==payload_length-1;
 assign payload_data=byte_index<8?prefix[63-byte_index[2:0]*8-:8]:current_word[63-byte_index[2:0]*8-:8];
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;key<=0;epoch<=0;seq<=0;stamp<=0;deadline<=0;count<=0;received<=0;last_x<=0;last_y<=0;have_tile<=0;
   frag<=0;peer<=1;byte_index<=0;read_address<=0;current_word<=0;
   abort_core<=0;cancel_packet<=0;published<=0;discarded<=0;malformed_frames<=0;cancelled_frames<=0;
  end else begin
   abort_core<=0;cancel_packet<=0;published<=0;discarded<=0;
   if(active&&(stale||send_abort||(state==COLLECT&&core_frame_dropped)||(state==COLLECT&&core_frame_key!=key)||bad_record))begin
    state<=IDLE;abort_core<=1;cancel_packet<=1;discarded<=1;
    if(bad_record||(state==COLLECT&&core_frame_key!=key))malformed_frames<=malformed_frames+1'b1;
    else cancelled_frames<=cancelled_frames+1'b1;
   end else case(state)
    IDLE:if(core_frame_valid)begin
     if(bad_header)begin abort_core<=1;discarded<=1;malformed_frames<=malformed_frames+1'b1;end
     else begin
      state<=COLLECT;key<=core_frame_key;count<=core_frame_count;epoch<=permit_epoch;seq<=sequence_base;
      stamp<=frame_timestamp_us;deadline<=frame_deadline_us;received<=0;have_tile<=0;peer<=1;frag<=0;
     end
    end
    COLLECT:begin
     if(take_record)begin received<=received+1'b1;last_x<=core_x;last_y<=core_y;have_tile<=1;end
     if(core_frame_done)begin
      if(received+take_record!=count)begin
       state<=IDLE;abort_core<=1;discarded<=1;malformed_frames<=malformed_frames+1'b1;
      end else begin state<=REQUEST;read_address<=0;end
     end
    end
    REQUEST:if(request_ready)begin state<=PAYLOAD;byte_index<=0;end
    PAYLOAD:if(payload_ready)begin
     byte_index<=byte_index+1'b1;
     if(byte_index==7)current_word<=read_q;
     else if(byte_index>=8)begin
      // Prefetch on the first byte and switch only after accepted last byte.
      // Thus a stalled last byte never changes despite the RAM read advancing.
      if(byte_index[2:0]==0)read_address<=read_address+1'b1;
      if(byte_index[2:0]==7)current_word<=read_q;
     end
     if(payload_last)state<=WAIT_TX;
    end
    WAIT_TX:if(send_done)begin
     if(!frag&&count>118)begin frag<=1;read_address<=118;state<=REQUEST;end
     else if(peer==1)begin peer<=2;frag<=0;read_address<=0;state<=REQUEST;end
     else begin state<=IDLE;published<=1;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Source snapshot: rtl/feature_v2/pg100_feature_transport_v2.v
// SW-23/24 compute -> validated records -> PGT2 UDP datagram producer.
// A leased, complete DDR frame supplies key and pixel ready contract. Physical
// HDMI input, DDR reader/scheduler and abort-aware network-slot owner are SW-38.
module pg100_feature_transport_v2(
 input wire clk,rst,s_valid,output wire s_ready,
 input wire[7:0]s_mono,input wire[8:0]s_x,input wire[7:0]s_y,
 input wire s_sof,s_eol,s_eof,input wire[151:0]s_key,input wire abort_frame,
 input wire commit_valid,output wire commit_ready,input wire commit_good,input wire[151:0]commit_key,
 input wire[63:0]now_us,frame_timestamp_us,frame_deadline_us,
 input wire permit_valid,input wire[151:0]permit_key,input wire[31:0]permit_epoch,
 input wire invalidate,input wire[31:0]sequence_base,
 output wire m_hdr_valid,input wire m_hdr_ready,output wire[10:0]m_length,output wire[1:0]m_peer,
 output wire[7:0]m_data,output wire m_valid,input wire m_ready,output wire m_last,m_abort,
 output wire published,discarded,output wire[7:0]result_count,
 output wire[31:0]input_errors,commit_errors,malformed_frames,cancelled_frames,rejected_packets
);
 wire cfv,cfr,crv,crr,cfd,cfx,abort_core;
 wire[151:0]cfk;wire[7:0]cy,cs;wire[8:0]cx;wire[6:0]ct;wire[16:0]cc;
 pg100_feature_core_v2 core(.clk(clk),.rst(rst),.s_valid(s_valid),.s_ready(s_ready),.s_mono(s_mono),.s_x(s_x),.s_y(s_y),
  .s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_key(s_key),.abort_frame(abort_frame||abort_core),
  .commit_valid(commit_valid),.commit_ready(commit_ready),.commit_good(commit_good),.commit_key(commit_key),
  .frame_valid(cfv),.frame_ready(cfr),.frame_key(cfk),.frame_count(result_count),.candidate_count(cc),
  .m_valid(crv),.m_ready(crr),.m_x(cx),.m_y(cy),.m_score(cs),.m_tile(ct),
  .frame_done(cfd),.frame_dropped(cfx),.input_errors(input_errors),.commit_errors(commit_errors),
  .score_valid(),.score_x(),.score_y(),.score_value());
 wire request_valid,request_ready,payload_valid,payload_ready,payload_last,send_done,send_abort,cancel_packet;
 wire[7:0]message_type,status,payload_data;wire[151:0]origin_key;
 wire[31:0]packet_epoch,tx_sequence;wire[63:0]timestamp_us,deadline_us;
 wire[15:0]invalid_reason,payload_length,fragment_index,fragment_count;wire[1:0]destination_peer;
 wire pub_discarded,req_rejected;
 pg100_feature_publisher_v2 publisher(.clk(clk),.rst(rst),.core_frame_valid(cfv),.core_frame_ready(cfr),
  .core_frame_key(cfk),.core_frame_count(result_count),.core_candidate_count(cc),
  .core_record_valid(crv),.core_record_ready(crr),.core_x(cx),.core_y(cy),.core_score(cs),.core_tile(ct),
  .core_frame_done(cfd),.core_frame_dropped(cfx),.abort_core(abort_core),
  .now_us(now_us),.frame_timestamp_us(frame_timestamp_us),.frame_deadline_us(frame_deadline_us),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.invalidate(invalidate),.sequence_base(sequence_base),
  .request_valid(request_valid),.request_ready(request_ready),.message_type(message_type),.origin_key(origin_key),
  .packet_epoch(packet_epoch),.tx_sequence(tx_sequence),.timestamp_us(timestamp_us),.deadline_us(deadline_us),
  .status(status),.invalid_reason(invalid_reason),.payload_length(payload_length),.fragment_index(fragment_index),.fragment_count(fragment_count),
  .destination_peer(destination_peer),.payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),.payload_last(payload_last),
  .send_done(send_done),.send_abort(send_abort||req_rejected),.cancel_packet(cancel_packet),
  .published(published),.discarded(pub_discarded),.malformed_frames(malformed_frames),.cancelled_frames(cancelled_frames));
 pg_pgt2_datagram_tx #(.PRODUCER_ID(100)) serializer(.clk(clk),.rst(rst),
  .req_valid(request_valid),.req_ready(request_ready),.req_message_type(message_type),.req_status(status),.req_reason(invalid_reason),
  .req_payload_length(payload_length[10:0]),.req_key(origin_key),.req_sequence(tx_sequence),.req_epoch(packet_epoch),
  .req_timestamp_us(timestamp_us),.req_deadline_us(deadline_us),.req_fragment_index(fragment_index),.req_fragment_count(fragment_count),.req_peer(destination_peer),
  .permit_valid(permit_valid),.permit_key(permit_key),.permit_epoch(permit_epoch),.now_us(now_us),.invalidate(invalidate||cancel_packet),
  .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),.payload_last(payload_last),
  .m_hdr_valid(m_hdr_valid),.m_hdr_ready(m_hdr_ready),.m_length(m_length),.m_peer(m_peer),
  .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),.m_abort(m_abort),
  .busy(),.send_done(send_done),.send_abort(send_abort),.req_rejected(req_rejected),.rejected_packets(rejected_packets));
 assign discarded=pub_discarded||cfx;
endmodule

// Source snapshot: rtl/network/pg100_rgmii.v
`timescale 1ns/1ps
// Gigabit-only RGMII. The PHY must provide the RX clock skew and delay TXC
// internally (RGMII-ID). SW-11 owns MDIO, negotiation and the shared reset.
// SAME_PIPELINED puts both halves of one byte on the same RXC edge.
// Board-proven RGMII RX clock from the 100Pro+ ethernet demo: 125MHz
// reference from PHY RXC, 30-degree static phase, lock gates the RX IDDR.
module pg100_rx_pll (
 input wire clkin,
 output wire clkout,
 output wire lock
);
 GTP_GPLL #(
  .CLKIN_FREQ(125.0),.LOCK_MODE(1'b0),
  .STATIC_RATIOI(5),.STATIC_RATIOM(2),
  .STATIC_RATIO0(8.0),.STATIC_RATIO1(8),.STATIC_RATIO2(20),.STATIC_RATIO3(20),
  .STATIC_RATIO4(20),.STATIC_RATIO5(20),.STATIC_RATIO6(20),.STATIC_RATIOF(20.0),
  .STATIC_DUTY0(8),.STATIC_DUTY1(8),.STATIC_DUTY2(20),.STATIC_DUTY3(20),
  .STATIC_DUTY4(20),.STATIC_DUTY5(20),.STATIC_DUTY6(20),.STATIC_DUTYF(20),
  .STATIC_PHASE(0),.STATIC_PHASE0(5),.STATIC_PHASE1(5),.STATIC_PHASE2(0),.STATIC_PHASE3(0),
  .STATIC_PHASE4(0),.STATIC_PHASE5(0),.STATIC_PHASE6(0),.STATIC_PHASEF(0),
  .STATIC_CPHASE0(0),.STATIC_CPHASE1(2),.STATIC_CPHASE2(0),.STATIC_CPHASE3(0),
  .STATIC_CPHASE4(0),.STATIC_CPHASE5(0),.STATIC_CPHASE6(0),.STATIC_CPHASEF(0),
  .CLK_DPS0_EN("FALSE"),.CLK_DPS1_EN("FALSE"),.CLK_DPS2_EN("FALSE"),.CLK_DPS3_EN("FALSE"),
  .CLK_DPS4_EN("FALSE"),.CLK_DPS5_EN("FALSE"),.CLK_DPS6_EN("FALSE"),.CLK_DPSF_EN("FALSE"),
  .CLK_CAS5_EN("FALSE"),.CLKOUT0_SYN_EN("FALSE"),.CLKOUT1_SYN_EN("FALSE"),.CLKOUT2_SYN_EN("FALSE"),
  .CLKOUT3_SYN_EN("FALSE"),.CLKOUT4_SYN_EN("FALSE"),.CLKOUT5_SYN_EN("FALSE"),.CLKOUT6_SYN_EN("FALSE"),
  .CLKOUTF_SYN_EN("FALSE"),.SSC_MODE("DISABLE"),.SSC_FREQ(25.0),
  .INTERNAL_FB("CLKOUTF"),.EXTERNAL_FB("DISABLE"),.BANDWIDTH("OPTIMIZED")
 ) u_gpll(
  .CLKOUT0(clkout),.CLKOUT0N(),.CLKOUT1(),.CLKOUT1N(),.CLKOUT2(),.CLKOUT2N(),
  .CLKOUT3(),.CLKOUT3N(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKOUTF(),.CLKOUTFN(),
  .LOCK(lock),.DPS_DONE(),.APB_RDATA(),.APB_READY(),
  .CLKIN1(clkin),.CLKIN2(1'b0),.CLKFB(1'b0),.CLKIN_SEL(1'b0),
  .DPS_CLK(1'b0),.DPS_EN(1'b0),.DPS_DIR(1'b0),
  .CLKOUT0_SYN(1'b0),.CLKOUT1_SYN(1'b0),.CLKOUT2_SYN(1'b0),.CLKOUT3_SYN(1'b0),
  .CLKOUT4_SYN(1'b0),.CLKOUT5_SYN(1'b0),.CLKOUT6_SYN(1'b0),.CLKOUTF_SYN(1'b0),
  .PLL_PWD(1'b0),.RST(1'b0),
  .APB_CLK(1'b0),.APB_RST_N(1'b0),.APB_ADDR(5'd0),.APB_SEL(1'b0),
  .APB_EN(1'b0),.APB_WRITE(1'b0),.APB_WDATA(16'd0)
 );
endmodule

module pg100_rgmii (
 input wire tx_clk125, input wire tx_rst,
 input wire rgmii_rxc, input wire rx_rst,
 input wire [3:0] rgmii_rxd, input wire rgmii_rx_ctl,
 output wire [3:0] rgmii_txd, output wire rgmii_tx_ctl, output wire rgmii_txc,
 output wire rx_clk, output wire [7:0] gmii_rxd,
 output wire gmii_rx_dv, output wire gmii_rx_er,
 input wire [7:0] gmii_txd, input wire gmii_tx_en, input wire gmii_tx_er
);
 wire [4:0] rise,fall;
 wire rx_pll_clk,rx_pll_lock;
 pg100_rx_pll rx_pll(.clkin(rgmii_rxc),.clkout(rx_pll_clk),.lock(rx_pll_lock));
 wire rx_rst_pll=rx_rst||!rx_pll_lock;
 GTP_CLKBUFG rx_buf(.CLKIN(rx_pll_clk),.CLKOUT(rx_clk));
 wire [3:0] rxd_ibuf,rxd_delay;
 wire rxctl_ibuf,rxctl_delay;
 localparam [7:0] RX_DELAY_STEP=8'h8c;
 genvar n;
 generate for(n=0;n<4;n=n+1) begin: pins
  GTP_INBUF #(.IOSTANDARD("LVCMOS33"),.TERM_DDR()) u_rxd_ibuf(.O(rxd_ibuf[n]),.I(rgmii_rxd[n]));
  GTP_IODELAY_E2 #(.DELAY_STEP_VALUE(8'he6),.DELAY_STEP_SEL("PORT"),.TDELAY_EN("FALSE"))
   u_rxd_delay(.DI(rxd_ibuf[n]),.DELAY_SEL(1'b1),.DELAY_STEP(RX_DELAY_STEP),.DO(rxd_delay[n]),.EN_N(1'b0));
  GTP_IDDR_E1 #(.GRS_EN("TRUE"),.IDDR_MODE("SAME_PIPELINED"),.RS_TYPE("ASYNC_RESET"))
   rx(.CLK(rx_clk),.CE(1'b1),.RS(rx_rst_pll),.D(rxd_delay[n]),.Q0(rise[n]),.Q1(fall[n]));
  GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET"))
   tx(.CLK(tx_clk125),.CE(1'b1),.RS(tx_rst),.D0(gmii_txd[n]),.D1(gmii_txd[n+4]),.Q(rgmii_txd[n]));
 end endgenerate
 GTP_INBUF #(.IOSTANDARD("LVCMOS33"),.TERM_DDR()) u_rxctl_ibuf(.O(rxctl_ibuf),.I(rgmii_rx_ctl));
 GTP_IODELAY_E2 #(.DELAY_STEP_VALUE(8'he6),.DELAY_STEP_SEL("PORT"),.TDELAY_EN("FALSE"))
  u_rxctl_delay(.DI(rxctl_ibuf),.DELAY_SEL(1'b1),.DELAY_STEP(RX_DELAY_STEP),.DO(rxctl_delay),.EN_N(1'b0));
 GTP_IDDR_E1 #(.GRS_EN("TRUE"),.IDDR_MODE("SAME_PIPELINED"),.RS_TYPE("ASYNC_RESET"))
  rxctl(.CLK(rx_clk),.CE(1'b1),.RS(rx_rst_pll),.D(rxctl_delay),.Q0(rise[4]),.Q1(fall[4]));
 GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET"))
  txctl(.CLK(tx_clk125),.CE(1'b1),.RS(tx_rst),.D0(gmii_tx_en),.D1(gmii_tx_en^gmii_tx_er),.Q(rgmii_tx_ctl));
 GTP_ODDR_E1 #(.GRS_EN("FALSE"),.ODDR_MODE("SAME_EDGE"),.RS_TYPE("ASYNC_RESET"))
  txclock(.CLK(tx_clk125),.CE(1'b1),.RS(tx_rst),.D0(1'b1),.D1(1'b0),.Q(rgmii_txc));
 assign gmii_rxd={fall[3:0],rise[3:0]};
 assign gmii_rx_dv=rise[4];
 assign gmii_rx_er=rise[4]^fall[4];
endmodule

// Source snapshot: rtl/network/pg100_mdio_master.v
`timescale 1ns/1ps
// Clause 22 MDC <= 2.5 MHz at 125 MHz. Read TA is checked; high is
// driven only by this push-pull MDIO master during master-owned fields.
module pg100_mdio_master #(parameter HALF_PERIOD=25)(
 input wire clk,input wire rst,
 input wire start,input wire write,input wire [4:0] phy_addr,input wire [4:0] reg_addr,input wire [15:0] write_data,
 output reg busy,output reg done,output reg error,output reg [15:0] read_data,
 output reg mdc,output wire mdio_out,output wire mdio_oe,input wire mdio_in
);
 reg [63:0] frame;
 reg [6:0] bitno;
 reg [7:0] divider;
 reg write_latched;
 // synthesis translate_off
 initial if(HALF_PERIOD<25 || HALF_PERIOD>255)$fatal(1,"MDC divider outside 125MHz/Clause22 bounds");
 // synthesis translate_on
 assign mdio_out=frame[63-bitno];
 assign mdio_oe=busy && (write_latched || bitno<46);
 always @(posedge clk) begin
  if(rst) begin busy<=0;done<=0;error<=0;read_data<=0;mdc<=0;frame<=0;bitno<=0;divider<=0;write_latched<=0;end
  else begin
   done<=0;
   if(!busy) begin
    mdc<=0;divider<=0;
    if(start) begin busy<=1;bitno<=0;error<=0;read_data<=0;write_latched<=write;
     frame<={32'hffffffff,2'b01,write ? 2'b01 : 2'b10,phy_addr,reg_addr,2'b10,write_data};
    end
   end else if(divider==HALF_PERIOD-1) begin
    divider<=0;mdc<=~mdc;
    if(!mdc) begin
     if(!write_latched) begin
      if(bitno==47 && mdio_in!=1'b0) error<=1;
      if(bitno>=48) read_data<={read_data[14:0],mdio_in};
     end
    end else if(bitno==63) begin busy<=0;done<=1;end
    else bitno<=bitno+1;
   end else divider<=divider+1;
  end
 end
endmodule

// Source snapshot: rtl/network/pg100_rtl8211f_init.v
`timescale 1ns/1ps
// Board-specific management. Reads actual PHY ID, enables and verifies both
// internal RGMII delays, then polls negotiated link/speed/duplex. No reset pin
// here: the shared board reset owner supplies rst after G25 has been released.
module pg100_rtl8211f_init #(parameter [4:0] PHY_ADDR=5'd1,parameter POLL_CYCLES=12500000,parameter MDC_HALF_PERIOD=25)(
 input wire clk,input wire rst,
 output wire mdc,output wire mdio_out,output wire mdio_oe,input wire mdio_in,
 output wire link_gigabit,output reg phy_present,output reg delay_verified,
 output reg link_up,output reg [1:0] speed,output reg full_duplex,output reg [31:0] mdio_errors
);
 reg start,write;reg [4:0] addr;reg [15:0] value;
 wire busy,done,error;wire [15:0] data;
 reg [4:0] step;reg waiting;reg [15:0] saved;reg [23:0] poll;
 reg id_high_ok;
 pg100_mdio_master #(.HALF_PERIOD(MDC_HALF_PERIOD)) master(.clk(clk),.rst(rst),.start(start),.write(write),.phy_addr(PHY_ADDR),.reg_addr(addr),.write_data(value),
 .busy(busy),.done(done),.error(error),.read_data(data),.mdc(mdc),.mdio_out(mdio_out),.mdio_oe(mdio_oe),.mdio_in(mdio_in));
 assign link_gigabit=phy_present&&delay_verified&&link_up&&speed==2&&full_duplex;
 always @(posedge clk) begin
  if(rst) begin start<=0;write<=0;addr<=0;value<=0;step<=0;waiting<=0;saved<=0;poll<=0;id_high_ok<=0;
   phy_present<=0;delay_verified<=0;link_up<=0;speed<=0;full_duplex<=0;mdio_errors<=0;end
  else begin
   start<=0;
   if(step==17) begin
    if(poll==POLL_CYCLES-1) begin poll<=0;step<=phy_present&&delay_verified?11:0;end else poll<=poll+1;
   end else if(!waiting && !busy && !start) begin
    waiting<=1;start<=1;write<=0;value<=0;
    case(step)
     // PHY identification registers are standard and readable before any
     // vendor-page write. Board owner has already completed the hard reset.
     0: addr<=2;
     1: addr<=2;
     2: addr<=3;
     3: begin write<=1;addr<=31;value<=16'h0d08;end
     4: addr<=17;
     5: begin write<=1;addr<=17;value<=saved|16'h0100;end
     6: addr<=17;
     7: addr<=21;
     8: begin write<=1;addr<=21;value<=saved|16'h0008;end
     9: addr<=21;
     10: begin write<=1;addr<=31;value<=0;end
     11: addr<=1;
     12: addr<=1;
     13: begin write<=1;addr<=31;value<=16'h0a43;end
     14: addr<=26;
     15: begin write<=1;addr<=31;value<=0;end
     16: addr<=1;
     default: addr<=1;
    endcase
   end else if(done) begin
    waiting<=0;
    if(error) begin mdio_errors<=mdio_errors+1;phy_present<=0;delay_verified<=0;link_up<=0;step<=0;end
    else begin
     step<=step+1;
     case(step)
      1: id_high_ok<=data==16'h001c;
      2: begin
       // Realtek B/E/F use adjacent low ID values. A family mask would
       // authorize F-only delay registers on a different physical model.
       phy_present<=id_high_ok&&data==16'hc916;
       if(!id_high_ok||data!=16'hc916)begin step<=17;delay_verified<=0;link_up<=0;end
      end
      4,7: saved<=data;
      6: delay_verified<=data[8];
      9: delay_verified<=delay_verified&&data[3];
      12: link_up<=data[2]&&data[5];
      14: begin speed<=data[5:4];full_duplex<=data[3];end
      16: link_up<=data[2]&&data[5];
     endcase
    end
   end
  end
 end
endmodule

// Source snapshot: rtl/network/pg100_udp_rx_guard.v
`timescale 1ns/1ps
// Whole-datagram release, after MAC FCS, IPv4 checksum and UDP checksum.
// One 1024-byte DRM buffer. Backpressure never publishes an incomplete packet.
module pg100_udp_rx_guard #(
 parameter [47:0] LOCAL_MAC=48'h025000000064,
 parameter [31:0] LOCAL_IP=32'hc0a8321e,
 parameter [15:0] UDP_PORT=16'd5100
)(
 input wire clk,input wire rst,
 input wire hdr_valid,output wire hdr_ready,
 input wire [47:0] dest_mac,
 input wire [3:0] ip_version,input wire [3:0] ip_ihl,
 input wire [15:0] ip_length,input wire [2:0] ip_flags,input wire [12:0] ip_fragment_offset,
 input wire [31:0] source_ip,input wire [31:0] dest_ip,
 input wire [15:0] source_port,input wire [15:0] dest_port,
 input wire [15:0] udp_length,input wire [15:0] udp_checksum,
 input wire [7:0] s_data,input wire s_valid,output wire s_ready,input wire s_last,input wire s_user,
 output wire m_hdr_valid,input wire m_hdr_ready,output reg [1:0] m_peer,output reg [10:0] m_length,
 output reg [7:0] m_data,output wire m_valid,input wire m_ready,output wire m_last,
 output reg [31:0] accepted,output reg [31:0] rejected
);
 function [15:0] add16;
  input [15:0] a,b; reg [16:0] s;
  begin s={1'b0,a}+{1'b0,b}; add16=s[15:0]+s[16]; end
 endfunction
 reg [7:0] mem [0:1023];
 localparam IDLE=0,INIT=1,COLLECT=2,CHECK=3,HEADER=4,READ=5,SEND=6;
 reg [2:0] state;
 reg [10:0] count,rd;
 reg [15:0] sum;
 reg [7:0] high_byte;
 reg bad;
 reg [15:0] init_words[0:9];reg [3:0] init_index;
 wire peer_ok=(source_ip==32'hc0a83214)||(source_ip==32'hc0a8320a)||(source_ip==32'hc0a83228);
 assign hdr_ready=state==IDLE;
 assign s_ready=state==COLLECT;
 assign m_hdr_valid=state==HEADER;
 assign m_valid=state==SEND;
 assign m_last=rd+1==m_length;
 always @(posedge clk) begin
  if(rst) begin state<=IDLE;count<=0;rd<=0;sum<=0;bad<=0;accepted<=0;rejected<=0;m_peer<=0;m_length<=0;m_data<=0;high_byte<=0;init_index<=0;end
  else case(state)
   IDLE: if(hdr_valid) begin
    state<=INIT;count<=0;rd<=0;sum<=0;init_index<=0;
    m_peer<=source_ip==32'hc0a83214 ? 0 : source_ip==32'hc0a8320a ? 1 : 2;
    m_length<=udp_length-8;
    bad<=!peer_ok || dest_mac!=LOCAL_MAC || dest_ip!=LOCAL_IP || source_port!=UDP_PORT || dest_port!=UDP_PORT ||
     ip_version!=4 || ip_ihl!=5 || ip_length!=udp_length+20 || (ip_flags&3'b101)!=0 || ip_fragment_offset!=0 ||
     udp_length<76 || udp_length>1032 || udp_checksum==0;
    // Time-multiplex ONE 17-bit adder. A nested ten-word combinational sum
    // failed real PDS at 125MHz (-10.183ns); input payload is backpressured
    // for ten clocks while this fixed header checksum is initialized.
    init_words[0]<=source_ip[31:16];init_words[1]<=source_ip[15:0];
    init_words[2]<=dest_ip[31:16];init_words[3]<=dest_ip[15:0];
    init_words[4]<=16'h0011;init_words[5]<=udp_length;
    init_words[6]<=source_port;init_words[7]<=dest_port;
    init_words[8]<=udp_length;init_words[9]<=udp_checksum;
   end
   INIT: begin
    sum<=add16(sum,init_words[init_index]);
    if(init_index==9)state<=COLLECT;else init_index<=init_index+1;
   end
   COLLECT: if(s_valid) begin
    if(count<1024) mem[count[9:0]]<=s_data;
    else bad<=1;
    if(count!=2047) count<=count+1;
    if(s_user) bad<=1;
    if(!count[0]) begin
     high_byte<=s_data;
     if(s_last) sum<=add16(sum,{s_data,8'b0});
    end else sum<=add16(sum,{high_byte,s_data});
    if(s_last) begin
     if(count+1!=m_length) bad<=1;
     state<=CHECK;
    end
   end
   CHECK: if(bad || sum!=16'hffff) begin rejected<=rejected+1;state<=IDLE;end
    else begin accepted<=accepted+1;state<=HEADER;end
   HEADER: if(m_hdr_ready) begin rd<=0;state<=READ;end
   READ: begin m_data<=mem[rd[9:0]];state<=SEND;end
   SEND: if(m_ready) begin
    if(m_last) state<=IDLE;else begin rd<=rd+1;state<=READ;end
   end
   default: state<=IDLE;
  endcase
 end
endmodule

// Source snapshot: rtl/network/vendor/arbiter.v
/*

Copyright (c) 2014-2021 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Arbiter module
 */
module arbiter #
(
    parameter PORTS = 4,
    // select round robin arbitration
    parameter ARB_TYPE_ROUND_ROBIN = 0,
    // blocking arbiter enable
    parameter ARB_BLOCK = 0,
    // block on acknowledge assert when nonzero, request deassert when 0
    parameter ARB_BLOCK_ACK = 1,
    // LSB priority selection
    parameter ARB_LSB_HIGH_PRIORITY = 0
)
(
    input  wire                     clk,
    input  wire                     rst,

    input  wire [PORTS-1:0]         request,
    input  wire [PORTS-1:0]         acknowledge,

    output wire [PORTS-1:0]         grant,
    output wire                     grant_valid,
    output wire [$clog2(PORTS)-1:0] grant_encoded
);

reg [PORTS-1:0] grant_reg = 0, grant_next;
reg grant_valid_reg = 0, grant_valid_next;
reg [$clog2(PORTS)-1:0] grant_encoded_reg = 0, grant_encoded_next;

assign grant_valid = grant_valid_reg;
assign grant = grant_reg;
assign grant_encoded = grant_encoded_reg;

wire request_valid;
wire [$clog2(PORTS)-1:0] request_index;
wire [PORTS-1:0] request_mask;

priority_encoder #(
    .WIDTH(PORTS),
    .LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
)
priority_encoder_inst (
    .input_unencoded(request),
    .output_valid(request_valid),
    .output_encoded(request_index),
    .output_unencoded(request_mask)
);

reg [PORTS-1:0] mask_reg = 0, mask_next;

wire masked_request_valid;
wire [$clog2(PORTS)-1:0] masked_request_index;
wire [PORTS-1:0] masked_request_mask;

priority_encoder #(
    .WIDTH(PORTS),
    .LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
)
priority_encoder_masked (
    .input_unencoded(request & mask_reg),
    .output_valid(masked_request_valid),
    .output_encoded(masked_request_index),
    .output_unencoded(masked_request_mask)
);

always @* begin
    grant_next = 0;
    grant_valid_next = 0;
    grant_encoded_next = 0;
    mask_next = mask_reg;

    if (ARB_BLOCK && !ARB_BLOCK_ACK && grant_reg & request) begin
        // granted request still asserted; hold it
        grant_valid_next = grant_valid_reg;
        grant_next = grant_reg;
        grant_encoded_next = grant_encoded_reg;
    end else if (ARB_BLOCK && ARB_BLOCK_ACK && grant_valid && !(grant_reg & acknowledge)) begin
        // granted request not yet acknowledged; hold it
        grant_valid_next = grant_valid_reg;
        grant_next = grant_reg;
        grant_encoded_next = grant_encoded_reg;
    end else if (request_valid) begin
        if (ARB_TYPE_ROUND_ROBIN) begin
            if (masked_request_valid) begin
                grant_valid_next = 1;
                grant_next = masked_request_mask;
                grant_encoded_next = masked_request_index;
                if (ARB_LSB_HIGH_PRIORITY) begin
                    mask_next = {PORTS{1'b1}} << (masked_request_index + 1);
                end else begin
                    mask_next = {PORTS{1'b1}} >> (PORTS - masked_request_index);
                end
            end else begin
                grant_valid_next = 1;
                grant_next = request_mask;
                grant_encoded_next = request_index;
                if (ARB_LSB_HIGH_PRIORITY) begin
                    mask_next = {PORTS{1'b1}} << (request_index + 1);
                end else begin
                    mask_next = {PORTS{1'b1}} >> (PORTS - request_index);
                end
            end
        end else begin
            grant_valid_next = 1;
            grant_next = request_mask;
            grant_encoded_next = request_index;
        end
    end
end

always @(posedge clk) begin
    grant_reg <= grant_next;
    grant_valid_reg <= grant_valid_next;
    grant_encoded_reg <= grant_encoded_next;
    mask_reg <= mask_next;

    if (rst) begin
        grant_reg <= 0;
        grant_valid_reg <= 0;
        grant_encoded_reg <= 0;
        mask_reg <= 0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/arp.v
/*

Copyright (c) 2014-2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ARP block for IPv4, ethernet frame interface
 */
module arp #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // Log2 of ARP cache size
    parameter CACHE_ADDR_WIDTH = 9,
    // ARP request retry count
    parameter REQUEST_RETRY_COUNT = 4,
    // ARP request retry interval (in cycles)
    parameter REQUEST_RETRY_INTERVAL = 125000000*2,
    // ARP request timeout (in cycles)
    parameter REQUEST_TIMEOUT = 125000000*30
)
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * Ethernet frame input
     */
    input  wire                   s_eth_hdr_valid,
    output wire                   s_eth_hdr_ready,
    input  wire [47:0]            s_eth_dest_mac,
    input  wire [47:0]            s_eth_src_mac,
    input  wire [15:0]            s_eth_type,
    input  wire [DATA_WIDTH-1:0]  s_eth_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_eth_payload_axis_tkeep,
    input  wire                   s_eth_payload_axis_tvalid,
    output wire                   s_eth_payload_axis_tready,
    input  wire                   s_eth_payload_axis_tlast,
    input  wire                   s_eth_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire                   m_eth_hdr_valid,
    input  wire                   m_eth_hdr_ready,
    output wire [47:0]            m_eth_dest_mac,
    output wire [47:0]            m_eth_src_mac,
    output wire [15:0]            m_eth_type,
    output wire [DATA_WIDTH-1:0]  m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_eth_payload_axis_tkeep,
    output wire                   m_eth_payload_axis_tvalid,
    input  wire                   m_eth_payload_axis_tready,
    output wire                   m_eth_payload_axis_tlast,
    output wire                   m_eth_payload_axis_tuser,

    /*
     * ARP requests
     */
    input  wire                   arp_request_valid,
    output wire                   arp_request_ready,
    input  wire [31:0]            arp_request_ip,
    output wire                   arp_response_valid,
    input  wire                   arp_response_ready,
    output wire                   arp_response_error,
    output wire [47:0]            arp_response_mac,

    /*
     * Configuration
     */
    input  wire [47:0]            local_mac,
    input  wire [31:0]            local_ip,
    input  wire [31:0]            gateway_ip,
    input  wire [31:0]            subnet_mask,
    input  wire                   clear_cache
);

localparam [15:0]
    ARP_OPER_ARP_REQUEST = 16'h0001,
    ARP_OPER_ARP_REPLY = 16'h0002,
    ARP_OPER_INARP_REQUEST = 16'h0008,
    ARP_OPER_INARP_REPLY = 16'h0009;

wire incoming_frame_valid;
reg incoming_frame_ready;
wire [47:0] incoming_eth_dest_mac;
wire [47:0] incoming_eth_src_mac;
wire [15:0] incoming_eth_type;
wire [15:0] incoming_arp_htype;
wire [15:0] incoming_arp_ptype;
wire [7:0]  incoming_arp_hlen;
wire [7:0]  incoming_arp_plen;
wire [15:0] incoming_arp_oper;
wire [47:0] incoming_arp_sha;
wire [31:0] incoming_arp_spa;
wire [47:0] incoming_arp_tha;
wire [31:0] incoming_arp_tpa;

/*
 * ARP frame processing
 */
arp_eth_rx #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH)
)
arp_eth_rx_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(s_eth_hdr_valid),
    .s_eth_hdr_ready(s_eth_hdr_ready),
    .s_eth_dest_mac(s_eth_dest_mac),
    .s_eth_src_mac(s_eth_src_mac),
    .s_eth_type(s_eth_type),
    .s_eth_payload_axis_tdata(s_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep(s_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(s_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(s_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(s_eth_payload_axis_tuser),
    // ARP frame output
    .m_frame_valid(incoming_frame_valid),
    .m_frame_ready(incoming_frame_ready),
    .m_eth_dest_mac(incoming_eth_dest_mac),
    .m_eth_src_mac(incoming_eth_src_mac),
    .m_eth_type(incoming_eth_type),
    .m_arp_htype(incoming_arp_htype),
    .m_arp_ptype(incoming_arp_ptype),
    .m_arp_hlen(incoming_arp_hlen),
    .m_arp_plen(incoming_arp_plen),
    .m_arp_oper(incoming_arp_oper),
    .m_arp_sha(incoming_arp_sha),
    .m_arp_spa(incoming_arp_spa),
    .m_arp_tha(incoming_arp_tha),
    .m_arp_tpa(incoming_arp_tpa),
    // Status signals
    .busy(),
    .error_header_early_termination(),
    .error_invalid_header()
);

reg outgoing_frame_valid_reg = 1'b0, outgoing_frame_valid_next;
wire outgoing_frame_ready;
reg [47:0] outgoing_eth_dest_mac_reg = 48'd0, outgoing_eth_dest_mac_next;
reg [15:0] outgoing_arp_oper_reg = 16'd0, outgoing_arp_oper_next;
reg [47:0] outgoing_arp_tha_reg = 48'd0, outgoing_arp_tha_next;
reg [31:0] outgoing_arp_tpa_reg = 32'd0, outgoing_arp_tpa_next;

arp_eth_tx #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH)
)
arp_eth_tx_inst (
    .clk(clk),
    .rst(rst),
    // ARP frame input
    .s_frame_valid(outgoing_frame_valid_reg),
    .s_frame_ready(outgoing_frame_ready),
    .s_eth_dest_mac(outgoing_eth_dest_mac_reg),
    .s_eth_src_mac(local_mac),
    .s_eth_type(16'h0806),
    .s_arp_htype(16'h0001),
    .s_arp_ptype(16'h0800),
    .s_arp_oper(outgoing_arp_oper_reg),
    .s_arp_sha(local_mac),
    .s_arp_spa(local_ip),
    .s_arp_tha(outgoing_arp_tha_reg),
    .s_arp_tpa(outgoing_arp_tpa_reg),
    // Ethernet frame output
    .m_eth_hdr_valid(m_eth_hdr_valid),
    .m_eth_hdr_ready(m_eth_hdr_ready),
    .m_eth_dest_mac(m_eth_dest_mac),
    .m_eth_src_mac(m_eth_src_mac),
    .m_eth_type(m_eth_type),
    .m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(m_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(m_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(m_eth_payload_axis_tuser),
    // Status signals
    .busy()
);

reg cache_query_request_valid_reg = 1'b0, cache_query_request_valid_next;
reg [31:0] cache_query_request_ip_reg = 32'd0, cache_query_request_ip_next;
wire cache_query_response_valid;
wire cache_query_response_error;
wire [47:0] cache_query_response_mac;

reg cache_write_request_valid_reg = 1'b0, cache_write_request_valid_next;
reg [31:0] cache_write_request_ip_reg = 32'd0, cache_write_request_ip_next;
reg [47:0] cache_write_request_mac_reg = 48'd0, cache_write_request_mac_next;

/*
 * ARP cache
 */
arp_cache #(
    .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH)
)
arp_cache_inst (
    .clk(clk),
    .rst(rst),
    // Query cache
    .query_request_valid(cache_query_request_valid_reg),
    .query_request_ready(),
    .query_request_ip(cache_query_request_ip_reg),
    .query_response_valid(cache_query_response_valid),
    .query_response_ready(1'b1),
    .query_response_error(cache_query_response_error),
    .query_response_mac(cache_query_response_mac),
    // Write cache
    .write_request_valid(cache_write_request_valid_reg),
    .write_request_ready(),
    .write_request_ip(cache_write_request_ip_reg),
    .write_request_mac(cache_write_request_mac_reg),
    // Configuration
    .clear_cache(clear_cache)
);

reg arp_request_operation_reg = 1'b0, arp_request_operation_next;

reg arp_request_ready_reg = 1'b0, arp_request_ready_next;
reg [31:0] arp_request_ip_reg = 32'd0, arp_request_ip_next;

reg arp_response_valid_reg = 1'b0, arp_response_valid_next;
reg arp_response_error_reg = 1'b0, arp_response_error_next;
reg [47:0] arp_response_mac_reg = 48'd0, arp_response_mac_next;

reg [5:0] arp_request_retry_cnt_reg = 6'd0, arp_request_retry_cnt_next;
reg [35:0] arp_request_timer_reg = 36'd0, arp_request_timer_next;

assign arp_request_ready = arp_request_ready_reg;

assign arp_response_valid = arp_response_valid_reg;
assign arp_response_error = arp_response_error_reg;
assign arp_response_mac = arp_response_mac_reg;

always @* begin
    incoming_frame_ready = 1'b0;

    outgoing_frame_valid_next = outgoing_frame_valid_reg && !outgoing_frame_ready;
    outgoing_eth_dest_mac_next = outgoing_eth_dest_mac_reg;
    outgoing_arp_oper_next = outgoing_arp_oper_reg;
    outgoing_arp_tha_next = outgoing_arp_tha_reg;
    outgoing_arp_tpa_next = outgoing_arp_tpa_reg;

    cache_query_request_valid_next = 1'b0;
    cache_query_request_ip_next = cache_query_request_ip_reg;

    cache_write_request_valid_next = 1'b0;
    cache_write_request_mac_next = cache_write_request_mac_reg;
    cache_write_request_ip_next = cache_write_request_ip_reg;

    arp_request_ready_next = 1'b0;
    arp_request_ip_next = arp_request_ip_reg;
    arp_request_operation_next = arp_request_operation_reg;
    arp_request_retry_cnt_next = arp_request_retry_cnt_reg;
    arp_request_timer_next = arp_request_timer_reg;
    arp_response_valid_next = arp_response_valid_reg && !arp_response_ready;
    arp_response_error_next = 1'b0;
    arp_response_mac_next = 48'd0;

    // manage incoming frames
    incoming_frame_ready = outgoing_frame_ready;
    if (incoming_frame_valid && incoming_frame_ready) begin
        if (incoming_eth_type == 16'h0806 && incoming_arp_htype == 16'h0001 && incoming_arp_ptype == 16'h0800) begin
            // store sender addresses in cache
            cache_write_request_valid_next = 1'b1;
            cache_write_request_ip_next = incoming_arp_spa;
            cache_write_request_mac_next = incoming_arp_sha;
            if (incoming_arp_oper == ARP_OPER_ARP_REQUEST) begin
                // ARP request
                if (incoming_arp_tpa == local_ip) begin
                    // send reply frame to valid incoming request
                    outgoing_frame_valid_next = 1'b1;
                    outgoing_eth_dest_mac_next = incoming_eth_src_mac;
                    outgoing_arp_oper_next = ARP_OPER_ARP_REPLY;
                    outgoing_arp_tha_next = incoming_arp_sha;
                    outgoing_arp_tpa_next = incoming_arp_spa;
                end
            end else if (incoming_arp_oper == ARP_OPER_INARP_REQUEST) begin
                // INARP request
                if (incoming_arp_tha == local_mac) begin
                    // send reply frame to valid incoming request
                    outgoing_frame_valid_next = 1'b1;
                    outgoing_eth_dest_mac_next = incoming_eth_src_mac;
                    outgoing_arp_oper_next = ARP_OPER_INARP_REPLY;
                    outgoing_arp_tha_next = incoming_arp_sha;
                    outgoing_arp_tpa_next = incoming_arp_spa;
                end 
            end
        end
    end

    // manage ARP lookup requests
    if (arp_request_operation_reg) begin
        arp_request_ready_next = 1'b0;
        cache_query_request_valid_next = 1'b1;
        arp_request_timer_next = arp_request_timer_reg - 1;
        // if we got a response, it will go in the cache, so when the query succeds, we're done
        if (cache_query_response_valid && !cache_query_response_error) begin
            arp_request_operation_next = 1'b0;
            cache_query_request_valid_next = 1'b0;
            arp_response_valid_next = 1'b1;
            arp_response_error_next = 1'b0;
            arp_response_mac_next = cache_query_response_mac;
        end
        // timer timeout
        if (arp_request_timer_reg == 0) begin
            if (arp_request_retry_cnt_reg > 0) begin
                // have more retries
                // send ARP request frame
                outgoing_frame_valid_next = 1'b1;
                outgoing_eth_dest_mac_next = 48'hffffffffffff;
                outgoing_arp_oper_next = ARP_OPER_ARP_REQUEST;
                outgoing_arp_tha_next = 48'h000000000000;
                outgoing_arp_tpa_next = arp_request_ip_reg;
                arp_request_retry_cnt_next = arp_request_retry_cnt_reg - 1;
                if (arp_request_retry_cnt_reg > 1) begin
                    arp_request_timer_next = REQUEST_RETRY_INTERVAL;
                end else begin
                    arp_request_timer_next = REQUEST_TIMEOUT;
                end
            end else begin
                // out of retries
                arp_request_operation_next = 1'b0;
                arp_response_valid_next = 1'b1;
                arp_response_error_next = 1'b1;
                cache_query_request_valid_next = 1'b0;
            end
        end
    end else begin
        arp_request_ready_next = !arp_response_valid_next;
        if (cache_query_request_valid_reg) begin
            cache_query_request_valid_next = 1'b1;
            if (cache_query_response_valid) begin
                if (cache_query_response_error) begin
                    arp_request_operation_next = 1'b1;
                    // send ARP request frame
                    outgoing_frame_valid_next = 1'b1;
                    outgoing_eth_dest_mac_next = 48'hffffffffffff;
                    outgoing_arp_oper_next = ARP_OPER_ARP_REQUEST;
                    outgoing_arp_tha_next = 48'h000000000000;
                    outgoing_arp_tpa_next = arp_request_ip_reg;
                    arp_request_retry_cnt_next = REQUEST_RETRY_COUNT-1;
                    arp_request_timer_next = REQUEST_RETRY_INTERVAL;
                end else begin
                    cache_query_request_valid_next = 1'b0;
                    arp_response_valid_next = 1'b1;
                    arp_response_error_next = 1'b0;
                    arp_response_mac_next = cache_query_response_mac;
                end
            end
        end else if (arp_request_valid && arp_request_ready) begin
            if (arp_request_ip == 32'hffffffff) begin
                // broadcast address; use broadcast MAC address
                arp_response_valid_next = 1'b1;
                arp_response_error_next = 1'b0;
                arp_response_mac_next = 48'hffffffffffff;
            end else if (((arp_request_ip ^ gateway_ip) & subnet_mask) == 0) begin
                // within subnet
                // (no bits differ between request IP and gateway IP where subnet mask is set)
                if (~(arp_request_ip | subnet_mask) == 0) begin
                    // broadcast address; use broadcast MAC address
                    // (all bits in request IP set where subnet mask is clear)
                    arp_response_valid_next = 1'b1;
                    arp_response_error_next = 1'b0;
                    arp_response_mac_next = 48'hffffffffffff;
                end else begin
                    // unicast address; look up IP directly
                    cache_query_request_valid_next = 1'b1;
                    cache_query_request_ip_next = arp_request_ip;
                    arp_request_ip_next = arp_request_ip;
                end
            end else begin
                // outside of subnet, so look up gateway address
                cache_query_request_valid_next = 1'b1;
                cache_query_request_ip_next = gateway_ip;
                arp_request_ip_next = gateway_ip;
            end
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        outgoing_frame_valid_reg <= 1'b0;
        cache_query_request_valid_reg <= 1'b0;
        cache_write_request_valid_reg <= 1'b0;
        arp_request_ready_reg <= 1'b0;
        arp_request_operation_reg <= 1'b0;
        arp_request_retry_cnt_reg <= 6'd0;
        arp_request_timer_reg <= 36'd0;
        arp_response_valid_reg <= 1'b0;
    end else begin
        outgoing_frame_valid_reg <= outgoing_frame_valid_next;
        cache_query_request_valid_reg <= cache_query_request_valid_next;
        cache_write_request_valid_reg <= cache_write_request_valid_next;
        arp_request_ready_reg <= arp_request_ready_next;
        arp_request_operation_reg <= arp_request_operation_next;
        arp_request_retry_cnt_reg <= arp_request_retry_cnt_next;
        arp_request_timer_reg <= arp_request_timer_next;
        arp_response_valid_reg <= arp_response_valid_next;
    end

    cache_query_request_ip_reg <= cache_query_request_ip_next;
    outgoing_eth_dest_mac_reg <= outgoing_eth_dest_mac_next;
    outgoing_arp_oper_reg <= outgoing_arp_oper_next;
    outgoing_arp_tha_reg <= outgoing_arp_tha_next;
    outgoing_arp_tpa_reg <= outgoing_arp_tpa_next;
    cache_write_request_mac_reg <= cache_write_request_mac_next;
    cache_write_request_ip_reg <= cache_write_request_ip_next;
    arp_request_ip_reg <= arp_request_ip_next;
    arp_response_error_reg <= arp_response_error_next;
    arp_response_mac_reg <= arp_response_mac_next;
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/arp_cache.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ARP cache
 */
module arp_cache #(
    parameter CACHE_ADDR_WIDTH = 9
)
(
    input  wire        clk,
    input  wire        rst,

    /*
     * Cache query
     */
    input  wire        query_request_valid,
    output wire        query_request_ready,
    input  wire [31:0] query_request_ip,

    output wire        query_response_valid,
    input  wire        query_response_ready,
    output wire        query_response_error,
    output wire [47:0] query_response_mac,

    /*
     * Cache write
     */
    input  wire        write_request_valid,
    output wire        write_request_ready,
    input  wire [31:0] write_request_ip,
    input  wire [47:0] write_request_mac,

    /*
     * Configuration
     */
    input  wire        clear_cache
);

reg mem_write = 0;
reg store_query = 0;
reg store_write = 0;

reg query_ip_valid_reg = 0, query_ip_valid_next;
reg [31:0] query_ip_reg = 0;
reg write_ip_valid_reg = 0, write_ip_valid_next;
reg [31:0] write_ip_reg = 0;
reg [47:0] write_mac_reg = 0;
reg clear_cache_reg = 0, clear_cache_next;

reg [CACHE_ADDR_WIDTH-1:0] wr_ptr_reg = {CACHE_ADDR_WIDTH{1'b0}}, wr_ptr_next;
reg [CACHE_ADDR_WIDTH-1:0] rd_ptr_reg = {CACHE_ADDR_WIDTH{1'b0}}, rd_ptr_next;

reg valid_mem[(2**CACHE_ADDR_WIDTH)-1:0];
reg [31:0] ip_addr_mem[(2**CACHE_ADDR_WIDTH)-1:0];
reg [47:0] mac_addr_mem[(2**CACHE_ADDR_WIDTH)-1:0];

reg query_request_ready_reg = 0, query_request_ready_next;

reg query_response_valid_reg = 0, query_response_valid_next;
reg query_response_error_reg = 0, query_response_error_next;
reg [47:0] query_response_mac_reg = 0;

reg write_request_ready_reg = 0, write_request_ready_next;

wire [31:0] query_request_hash;
wire [31:0] write_request_hash;

assign query_request_ready = query_request_ready_reg;

assign query_response_valid = query_response_valid_reg;
assign query_response_error = query_response_error_reg;
assign query_response_mac = query_response_mac_reg;

assign write_request_ready = write_request_ready_reg;

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(32),
    .STYLE("AUTO")
)
rd_hash (
    .data_in(query_request_ip),
    .state_in(32'hffffffff),
    .data_out(),
    .state_out(query_request_hash)
);

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(32),
    .STYLE("AUTO")
)
wr_hash (
    .data_in(write_request_ip),
    .state_in(32'hffffffff),
    .data_out(),
    .state_out(write_request_hash)
);

integer i;

initial begin
    for (i = 0; i < 2**CACHE_ADDR_WIDTH; i = i + 1) begin
        valid_mem[i] = 1'b0;
        ip_addr_mem[i] = 32'd0;
        mac_addr_mem[i] = 48'd0;
    end
end

always @* begin
    mem_write = 1'b0;
    store_query = 1'b0;
    store_write = 1'b0;

    wr_ptr_next = wr_ptr_reg;
    rd_ptr_next = rd_ptr_reg;

    clear_cache_next = clear_cache_reg | clear_cache;

    query_ip_valid_next = query_ip_valid_reg;

    query_request_ready_next = (~query_ip_valid_reg || ~query_request_valid || query_response_ready) && !clear_cache_next;

    query_response_valid_next = query_response_valid_reg & ~query_response_ready;
    query_response_error_next = query_response_error_reg;

    if (query_ip_valid_reg && (~query_request_valid || query_response_ready)) begin
        query_response_valid_next = 1;
        query_ip_valid_next = 0;
        if (valid_mem[rd_ptr_reg] && ip_addr_mem[rd_ptr_reg] == query_ip_reg) begin
            query_response_error_next = 0;
        end else begin
            query_response_error_next = 1;
        end
    end

    if (query_request_valid && query_request_ready && (~query_ip_valid_reg || ~query_request_valid || query_response_ready)) begin
        store_query = 1;
        query_ip_valid_next = 1;
        rd_ptr_next = query_request_hash[CACHE_ADDR_WIDTH-1:0];
    end

    write_ip_valid_next = write_ip_valid_reg;

    write_request_ready_next = !clear_cache_next;

    if (write_ip_valid_reg) begin
        write_ip_valid_next = 0;
        mem_write = 1;
    end

    if (write_request_valid && write_request_ready) begin
        store_write = 1;
        write_ip_valid_next = 1;
        wr_ptr_next = write_request_hash[CACHE_ADDR_WIDTH-1:0];
    end

    if (clear_cache) begin
        clear_cache_next = 1'b1;
        wr_ptr_next = 0;
    end else if (clear_cache_reg) begin
        wr_ptr_next = wr_ptr_reg + 1;
        clear_cache_next = wr_ptr_next != 0;
        mem_write = 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        query_ip_valid_reg <= 1'b0;
        query_request_ready_reg <= 1'b0;
        query_response_valid_reg <= 1'b0;
        write_ip_valid_reg <= 1'b0;
        write_request_ready_reg <= 1'b0;
        clear_cache_reg <= 1'b1;
        wr_ptr_reg <= 0;
    end else begin
        query_ip_valid_reg <= query_ip_valid_next;
        query_request_ready_reg <= query_request_ready_next;
        query_response_valid_reg <= query_response_valid_next;
        write_ip_valid_reg <= write_ip_valid_next;
        write_request_ready_reg <= write_request_ready_next;
        clear_cache_reg <= clear_cache_next;
        wr_ptr_reg <= wr_ptr_next;
    end

    query_response_error_reg <= query_response_error_next;

    if (store_query) begin
        query_ip_reg <= query_request_ip;
    end

    if (store_write) begin
        write_ip_reg <= write_request_ip;
        write_mac_reg <= write_request_mac;
    end

    rd_ptr_reg <= rd_ptr_next;

    query_response_mac_reg <= mac_addr_mem[rd_ptr_reg];

    if (mem_write) begin
        valid_mem[wr_ptr_reg] <= !clear_cache_reg;
        ip_addr_mem[wr_ptr_reg] <= write_ip_reg;
        mac_addr_mem[wr_ptr_reg] <= write_mac_reg;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/arp_eth_rx.v
/*

Copyright (c) 2014-2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ARP ethernet frame receiver (Ethernet frame in, ARP frame out)
 */
module arp_eth_rx #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * Ethernet frame input
     */
    input  wire                   s_eth_hdr_valid,
    output wire                   s_eth_hdr_ready,
    input  wire [47:0]            s_eth_dest_mac,
    input  wire [47:0]            s_eth_src_mac,
    input  wire [15:0]            s_eth_type,
    input  wire [DATA_WIDTH-1:0]  s_eth_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_eth_payload_axis_tkeep,
    input  wire                   s_eth_payload_axis_tvalid,
    output wire                   s_eth_payload_axis_tready,
    input  wire                   s_eth_payload_axis_tlast,
    input  wire                   s_eth_payload_axis_tuser,

    /*
     * ARP frame output
     */
    output wire                   m_frame_valid,
    input  wire                   m_frame_ready,
    output wire [47:0]            m_eth_dest_mac,
    output wire [47:0]            m_eth_src_mac,
    output wire [15:0]            m_eth_type,
    output wire [15:0]            m_arp_htype,
    output wire [15:0]            m_arp_ptype,
    output wire [7:0]             m_arp_hlen,
    output wire [7:0]             m_arp_plen,
    output wire [15:0]            m_arp_oper,
    output wire [47:0]            m_arp_sha,
    output wire [31:0]            m_arp_spa,
    output wire [47:0]            m_arp_tha,
    output wire [31:0]            m_arp_tpa,

    /*
     * Status signals
     */
    output wire                   busy,
    output wire                   error_header_early_termination,
    output wire                   error_invalid_header
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 28;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// bus width assertions
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

/*

ARP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0806)          2 octets
 HTYPE (1)                   2 octets
 PTYPE (0x0800)              2 octets
 HLEN (6)                    1 octets
 PLEN (4)                    1 octets
 OPER                        2 octets
 SHA Sender MAC              6 octets
 SPA Sender IP               4 octets
 THA Target MAC              6 octets
 TPA Target IP               4 octets

This module receives an Ethernet frame with header fields in parallel and
payload on an AXI stream interface, decodes the ARP packet fields, and
produces the frame fields in parallel.  

*/

// datapath control signals
reg store_eth_hdr;

reg read_eth_header_reg = 1'b1, read_eth_header_next;
reg read_arp_header_reg = 1'b0, read_arp_header_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg s_eth_hdr_ready_reg = 1'b0, s_eth_hdr_ready_next;
reg s_eth_payload_axis_tready_reg = 1'b0, s_eth_payload_axis_tready_next;

reg m_frame_valid_reg = 1'b0, m_frame_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;
reg [15:0] m_arp_htype_reg = 16'd0, m_arp_htype_next;
reg [15:0] m_arp_ptype_reg = 16'd0, m_arp_ptype_next;
reg [7:0]  m_arp_hlen_reg = 8'd0, m_arp_hlen_next;
reg [7:0]  m_arp_plen_reg = 8'd0, m_arp_plen_next;
reg [15:0] m_arp_oper_reg = 16'd0, m_arp_oper_next;
reg [47:0] m_arp_sha_reg = 48'd0, m_arp_sha_next;
reg [31:0] m_arp_spa_reg = 32'd0, m_arp_spa_next;
reg [47:0] m_arp_tha_reg = 48'd0, m_arp_tha_next;
reg [31:0] m_arp_tpa_reg = 32'd0, m_arp_tpa_next;

reg busy_reg = 1'b0;
reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;
reg error_invalid_header_reg = 1'b0, error_invalid_header_next;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg;
assign s_eth_payload_axis_tready = s_eth_payload_axis_tready_reg;

assign m_frame_valid = m_frame_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_arp_htype = m_arp_htype_reg;
assign m_arp_ptype = m_arp_ptype_reg;
assign m_arp_hlen = m_arp_hlen_reg;
assign m_arp_plen = m_arp_plen_reg;
assign m_arp_oper = m_arp_oper_reg;
assign m_arp_sha = m_arp_sha_reg;
assign m_arp_spa = m_arp_spa_reg;
assign m_arp_tha = m_arp_tha_reg;
assign m_arp_tpa = m_arp_tpa_reg;

assign busy = busy_reg;
assign error_header_early_termination = error_header_early_termination_reg;
assign error_invalid_header = error_invalid_header_reg;

always @* begin
    read_eth_header_next = read_eth_header_reg;
    read_arp_header_next = read_arp_header_reg;
    ptr_next = ptr_reg;

    s_eth_hdr_ready_next = 1'b0;
    s_eth_payload_axis_tready_next = 1'b0;

    store_eth_hdr = 1'b0;

    m_frame_valid_next = m_frame_valid_reg && !m_frame_ready;

    m_arp_htype_next = m_arp_htype_reg;
    m_arp_ptype_next = m_arp_ptype_reg;
    m_arp_hlen_next = m_arp_hlen_reg;
    m_arp_plen_next = m_arp_plen_reg;
    m_arp_oper_next = m_arp_oper_reg;
    m_arp_sha_next = m_arp_sha_reg;
    m_arp_spa_next = m_arp_spa_reg;
    m_arp_tha_next = m_arp_tha_reg;
    m_arp_tpa_next = m_arp_tpa_reg;

    error_header_early_termination_next = 1'b0;
    error_invalid_header_next = 1'b0;

    if (s_eth_hdr_ready && s_eth_hdr_valid) begin
        if (read_eth_header_reg) begin
            store_eth_hdr = 1'b1;
            ptr_next = 0;
            read_eth_header_next = 1'b0;
            read_arp_header_next = 1'b1;
        end
    end

    if (s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) begin
        if (read_arp_header_reg) begin
            // word transfer in - store it
            ptr_next = ptr_reg + 1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_eth_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_eth_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

            `_HEADER_FIELD_(0,  m_arp_htype_next[1*8 +: 8])
            `_HEADER_FIELD_(1,  m_arp_htype_next[0*8 +: 8])
            `_HEADER_FIELD_(2,  m_arp_ptype_next[1*8 +: 8])
            `_HEADER_FIELD_(3,  m_arp_ptype_next[0*8 +: 8])
            `_HEADER_FIELD_(4,  m_arp_hlen_next[0*8 +: 8])
            `_HEADER_FIELD_(5,  m_arp_plen_next[0*8 +: 8])
            `_HEADER_FIELD_(6,  m_arp_oper_next[1*8 +: 8])
            `_HEADER_FIELD_(7,  m_arp_oper_next[0*8 +: 8])
            `_HEADER_FIELD_(8,  m_arp_sha_next[5*8 +: 8])
            `_HEADER_FIELD_(9,  m_arp_sha_next[4*8 +: 8])
            `_HEADER_FIELD_(10, m_arp_sha_next[3*8 +: 8])
            `_HEADER_FIELD_(11, m_arp_sha_next[2*8 +: 8])
            `_HEADER_FIELD_(12, m_arp_sha_next[1*8 +: 8])
            `_HEADER_FIELD_(13, m_arp_sha_next[0*8 +: 8])
            `_HEADER_FIELD_(14, m_arp_spa_next[3*8 +: 8])
            `_HEADER_FIELD_(15, m_arp_spa_next[2*8 +: 8])
            `_HEADER_FIELD_(16, m_arp_spa_next[1*8 +: 8])
            `_HEADER_FIELD_(17, m_arp_spa_next[0*8 +: 8])
            `_HEADER_FIELD_(18, m_arp_tha_next[5*8 +: 8])
            `_HEADER_FIELD_(19, m_arp_tha_next[4*8 +: 8])
            `_HEADER_FIELD_(20, m_arp_tha_next[3*8 +: 8])
            `_HEADER_FIELD_(21, m_arp_tha_next[2*8 +: 8])
            `_HEADER_FIELD_(22, m_arp_tha_next[1*8 +: 8])
            `_HEADER_FIELD_(23, m_arp_tha_next[0*8 +: 8])
            `_HEADER_FIELD_(24, m_arp_tpa_next[3*8 +: 8])
            `_HEADER_FIELD_(25, m_arp_tpa_next[2*8 +: 8])
            `_HEADER_FIELD_(26, m_arp_tpa_next[1*8 +: 8])
            `_HEADER_FIELD_(27, m_arp_tpa_next[0*8 +: 8])

            if (ptr_reg == 27/BYTE_LANES && (!KEEP_ENABLE || s_eth_payload_axis_tkeep[27%BYTE_LANES])) begin
                read_arp_header_next = 1'b0;
            end

            `undef _HEADER_FIELD_
        end

        if (s_eth_payload_axis_tlast) begin
            if (read_arp_header_next) begin
                // don't have the whole header
                error_header_early_termination_next = 1'b1;
            end else if (m_arp_hlen_next != 4'd6 || m_arp_plen_next != 4'd4) begin
                // lengths not valid
                error_invalid_header_next = 1'b1;
            end else begin
                // otherwise, transfer tuser
                m_frame_valid_next = !s_eth_payload_axis_tuser;
            end

            ptr_next = 1'b0;
            read_eth_header_next = 1'b1;
            read_arp_header_next = 1'b0;
        end
    end

    if (read_eth_header_next) begin
        s_eth_hdr_ready_next = !m_frame_valid_next;
    end else begin
        s_eth_payload_axis_tready_next = 1'b1;
    end
end

always @(posedge clk) begin
    read_eth_header_reg <= read_eth_header_next;
    read_arp_header_reg <= read_arp_header_next;
    ptr_reg <= ptr_next;

    s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;
    s_eth_payload_axis_tready_reg <= s_eth_payload_axis_tready_next;

    m_frame_valid_reg <= m_frame_valid_next;

    m_arp_htype_reg <= m_arp_htype_next;
    m_arp_ptype_reg <= m_arp_ptype_next;
    m_arp_hlen_reg <= m_arp_hlen_next;
    m_arp_plen_reg <= m_arp_plen_next;
    m_arp_oper_reg <= m_arp_oper_next;
    m_arp_sha_reg <= m_arp_sha_next;
    m_arp_spa_reg <= m_arp_spa_next;
    m_arp_tha_reg <= m_arp_tha_next;
    m_arp_tpa_reg <= m_arp_tpa_next;

    error_header_early_termination_reg <= error_header_early_termination_next;
    error_invalid_header_reg <= error_invalid_header_next;

    busy_reg <= read_arp_header_next;

    // datapath
    if (store_eth_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
    end

    if (rst) begin
        read_eth_header_reg <= 1'b1;
        read_arp_header_reg <= 1'b0;
        ptr_reg <= 0;
        s_eth_payload_axis_tready_reg <= 1'b0;
        m_frame_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_header_early_termination_reg <= 1'b0;
        error_invalid_header_reg <= 1'b0;
    end 
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/arp_eth_tx.v
/*

Copyright (c) 2014-2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ARP ethernet frame transmitter (ARP frame in, Ethernet frame out)
 */
module arp_eth_tx #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * ARP frame input
     */
    input  wire                   s_frame_valid,
    output wire                   s_frame_ready,
    input  wire [47:0]            s_eth_dest_mac,
    input  wire [47:0]            s_eth_src_mac,
    input  wire [15:0]            s_eth_type,
    input  wire [15:0]            s_arp_htype,
    input  wire [15:0]            s_arp_ptype,
    input  wire [15:0]            s_arp_oper,
    input  wire [47:0]            s_arp_sha,
    input  wire [31:0]            s_arp_spa,
    input  wire [47:0]            s_arp_tha,
    input  wire [31:0]            s_arp_tpa,

    /*
     * Ethernet frame output
     */
    output wire                   m_eth_hdr_valid,
    input  wire                   m_eth_hdr_ready,
    output wire [47:0]            m_eth_dest_mac,
    output wire [47:0]            m_eth_src_mac,
    output wire [15:0]            m_eth_type,
    output wire [DATA_WIDTH-1:0]  m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_eth_payload_axis_tkeep,
    output wire                   m_eth_payload_axis_tvalid,
    input  wire                   m_eth_payload_axis_tready,
    output wire                   m_eth_payload_axis_tlast,
    output wire                   m_eth_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire                   busy
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 28;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// bus width assertions
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

/*

ARP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0806)          2 octets
 HTYPE (1)                   2 octets
 PTYPE (0x0800)              2 octets
 HLEN (6)                    1 octets
 PLEN (4)                    1 octets
 OPER                        2 octets
 SHA Sender MAC              6 octets
 SPA Sender IP               4 octets
 THA Target MAC              6 octets
 TPA Target IP               4 octets

This module receives an ARP frame with header fields in parallel  and
transmits the complete Ethernet payload on an AXI interface.

*/

// datapath control signals
reg store_frame;

reg send_arp_header_reg = 1'b0, send_arp_header_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg [15:0] arp_htype_reg = 16'd0;
reg [15:0] arp_ptype_reg = 16'd0;
reg [15:0] arp_oper_reg = 16'd0;
reg [47:0] arp_sha_reg = 48'd0;
reg [31:0] arp_spa_reg = 32'd0;
reg [47:0] arp_tha_reg = 48'd0;
reg [31:0] arp_tpa_reg = 32'd0;

reg s_frame_ready_reg = 1'b0, s_frame_ready_next;

reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;

reg busy_reg = 1'b0;

// internal datapath
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_int;
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_int;
reg                  m_eth_payload_axis_tvalid_int;
reg                  m_eth_payload_axis_tready_int_reg = 1'b0;
reg                  m_eth_payload_axis_tlast_int;
reg                  m_eth_payload_axis_tuser_int;
wire                 m_eth_payload_axis_tready_int_early;

assign s_frame_ready = s_frame_ready_reg;

assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;

assign busy = busy_reg;

always @* begin
    send_arp_header_next = send_arp_header_reg;
    ptr_next = ptr_reg;

    s_frame_ready_next = 1'b0;

    store_frame = 1'b0;

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg && !m_eth_hdr_ready;

    m_eth_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
    m_eth_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int = 1'b0;
    m_eth_payload_axis_tuser_int = 1'b0;

    if (s_frame_ready && s_frame_valid) begin
        store_frame = 1'b1;
        m_eth_hdr_valid_next = 1'b1;
        ptr_next = 0;
        send_arp_header_next = 1'b1;
    end

    if (m_eth_payload_axis_tready_int_reg) begin
        if (send_arp_header_reg) begin
            ptr_next = ptr_reg + 1;

            m_eth_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
            m_eth_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
            m_eth_payload_axis_tvalid_int = 1'b1;
            m_eth_payload_axis_tlast_int = 1'b0;
            m_eth_payload_axis_tuser_int = 1'b0;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_eth_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_eth_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end

            `_HEADER_FIELD_(0,  arp_htype_reg[1*8 +: 8])
            `_HEADER_FIELD_(1,  arp_htype_reg[0*8 +: 8])
            `_HEADER_FIELD_(2,  arp_ptype_reg[1*8 +: 8])
            `_HEADER_FIELD_(3,  arp_ptype_reg[0*8 +: 8])
            `_HEADER_FIELD_(4,  8'd6)
            `_HEADER_FIELD_(5,  8'd4)
            `_HEADER_FIELD_(6,  arp_oper_reg[1*8 +: 8])
            `_HEADER_FIELD_(7,  arp_oper_reg[0*8 +: 8])
            `_HEADER_FIELD_(8,  arp_sha_reg[5*8 +: 8])
            `_HEADER_FIELD_(9,  arp_sha_reg[4*8 +: 8])
            `_HEADER_FIELD_(10, arp_sha_reg[3*8 +: 8])
            `_HEADER_FIELD_(11, arp_sha_reg[2*8 +: 8])
            `_HEADER_FIELD_(12, arp_sha_reg[1*8 +: 8])
            `_HEADER_FIELD_(13, arp_sha_reg[0*8 +: 8])
            `_HEADER_FIELD_(14, arp_spa_reg[3*8 +: 8])
            `_HEADER_FIELD_(15, arp_spa_reg[2*8 +: 8])
            `_HEADER_FIELD_(16, arp_spa_reg[1*8 +: 8])
            `_HEADER_FIELD_(17, arp_spa_reg[0*8 +: 8])
            `_HEADER_FIELD_(18, arp_tha_reg[5*8 +: 8])
            `_HEADER_FIELD_(19, arp_tha_reg[4*8 +: 8])
            `_HEADER_FIELD_(20, arp_tha_reg[3*8 +: 8])
            `_HEADER_FIELD_(21, arp_tha_reg[2*8 +: 8])
            `_HEADER_FIELD_(22, arp_tha_reg[1*8 +: 8])
            `_HEADER_FIELD_(23, arp_tha_reg[0*8 +: 8])
            `_HEADER_FIELD_(24, arp_tpa_reg[3*8 +: 8])
            `_HEADER_FIELD_(25, arp_tpa_reg[2*8 +: 8])
            `_HEADER_FIELD_(26, arp_tpa_reg[1*8 +: 8])
            `_HEADER_FIELD_(27, arp_tpa_reg[0*8 +: 8])

            if (ptr_reg == 27/BYTE_LANES) begin
                m_eth_payload_axis_tlast_int = 1'b1;
                send_arp_header_next = 1'b0;
            end

            `undef _HEADER_FIELD_
        end
    end

    s_frame_ready_next = !m_eth_hdr_valid_next && !send_arp_header_next;
end

always @(posedge clk) begin
    send_arp_header_reg <= send_arp_header_next;
    ptr_reg <= ptr_next;

    s_frame_ready_reg <= s_frame_ready_next;

    m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;

    busy_reg <= send_arp_header_next;

    if (store_frame) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
        arp_htype_reg <= s_arp_htype;
        arp_ptype_reg <= s_arp_ptype;
        arp_oper_reg <= s_arp_oper;
        arp_sha_reg <= s_arp_sha;
        arp_spa_reg <= s_arp_spa;
        arp_tha_reg <= s_arp_tha;
        arp_tpa_reg <= s_arp_tpa;
    end

    if (rst) begin
        send_arp_header_reg <= 1'b0;
        ptr_reg <= 0;
        s_frame_ready_reg <= 1'b0;
        m_eth_hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
reg                  m_eth_payload_axis_tlast_reg = 1'b0;
reg                  m_eth_payload_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] temp_m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
reg                  temp_m_eth_payload_axis_tlast_reg = 1'b0;
reg                  temp_m_eth_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_eth_payload_int_to_output;
reg store_eth_payload_int_to_temp;
reg store_eth_payload_axis_temp_to_output;

assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
assign m_eth_payload_axis_tkeep = KEEP_ENABLE ? m_eth_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_eth_payload_int_to_output = 1'b0;
    store_eth_payload_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_temp = 1'b1;
        end
    end else if (m_eth_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
        temp_m_eth_payload_axis_tvalid_next = 1'b0;
        store_eth_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_eth_payload_int_to_output) begin
        m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
        m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
        m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
        m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
        m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_eth_payload_int_to_temp) begin
        temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
        m_eth_payload_axis_tvalid_reg <= 1'b0;
        m_eth_payload_axis_tready_int_reg <= 1'b0;
        temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_adapter.v
/*

Copyright (c) 2014-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream bus width adapter
 */
module axis_adapter #
(
    // Width of input AXI stream interface in bits
    parameter S_DATA_WIDTH = 8,
    // Propagate tkeep signal on input interface
    // If disabled, tkeep assumed to be 1'b1
    parameter S_KEEP_ENABLE = (S_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on input interface
    parameter S_KEEP_WIDTH = ((S_DATA_WIDTH+7)/8),
    // Width of output AXI stream interface in bits
    parameter M_DATA_WIDTH = 8,
    // Propagate tkeep signal on output interface
    // If disabled, tkeep assumed to be 1'b1
    parameter M_KEEP_ENABLE = (M_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on output interface
    parameter M_KEEP_WIDTH = ((M_DATA_WIDTH+7)/8),
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1
)
(
    input  wire                     clk,
    input  wire                     rst,

    /*
     * AXI input
     */
    input  wire [S_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [S_KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,
    input  wire [ID_WIDTH-1:0]      s_axis_tid,
    input  wire [DEST_WIDTH-1:0]    s_axis_tdest,
    input  wire [USER_WIDTH-1:0]    s_axis_tuser,

    /*
     * AXI output
     */
    output wire [M_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [M_KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast,
    output wire [ID_WIDTH-1:0]      m_axis_tid,
    output wire [DEST_WIDTH-1:0]    m_axis_tdest,
    output wire [USER_WIDTH-1:0]    m_axis_tuser
);

// force keep width to 1 when disabled
localparam S_BYTE_LANES = S_KEEP_ENABLE ? S_KEEP_WIDTH : 1;
localparam M_BYTE_LANES = M_KEEP_ENABLE ? M_KEEP_WIDTH : 1;

// bus byte sizes (must be identical)
localparam S_BYTE_SIZE = S_DATA_WIDTH / S_BYTE_LANES;
localparam M_BYTE_SIZE = M_DATA_WIDTH / M_BYTE_LANES;

// bus width assertions
initial begin
    if (S_BYTE_SIZE * S_BYTE_LANES != S_DATA_WIDTH) begin
        $display("Error: input data width not evenly divisible (instance %m)");
        $finish;
    end

    if (M_BYTE_SIZE * M_BYTE_LANES != M_DATA_WIDTH) begin
        $display("Error: output data width not evenly divisible (instance %m)");
        $finish;
    end

    if (S_BYTE_SIZE != M_BYTE_SIZE) begin
        $display("Error: byte size mismatch (instance %m)");
        $finish;
    end
end

generate

if (M_BYTE_LANES == S_BYTE_LANES) begin : bypass
    // same width; bypass

    assign s_axis_tready = m_axis_tready;

    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tkeep  = M_KEEP_ENABLE ? s_axis_tkeep : {M_KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tlast  = s_axis_tlast;
    assign m_axis_tid    = ID_ENABLE   ? s_axis_tid   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest  = DEST_ENABLE ? s_axis_tdest : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser  = USER_ENABLE ? s_axis_tuser : {USER_WIDTH{1'b0}};

end else if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize
    // output is wider; upsize

    // required number of segments in wider bus
    localparam SEG_COUNT = M_BYTE_LANES / S_BYTE_LANES;
    // data width and keep width per segment
    localparam SEG_DATA_WIDTH = M_DATA_WIDTH / SEG_COUNT;
    localparam SEG_KEEP_WIDTH = M_BYTE_LANES / SEG_COUNT;

    reg [$clog2(SEG_COUNT)-1:0] seg_reg = 0;

    reg [S_DATA_WIDTH-1:0] s_axis_tdata_reg = {S_DATA_WIDTH{1'b0}};
    reg [S_KEEP_WIDTH-1:0] s_axis_tkeep_reg = {S_KEEP_WIDTH{1'b0}};
    reg s_axis_tvalid_reg = 1'b0;
    reg s_axis_tlast_reg = 1'b0;
    reg [ID_WIDTH-1:0] s_axis_tid_reg = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] s_axis_tdest_reg = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] s_axis_tuser_reg = {USER_WIDTH{1'b0}};

    reg [M_DATA_WIDTH-1:0] m_axis_tdata_reg = {M_DATA_WIDTH{1'b0}};
    reg [M_KEEP_WIDTH-1:0] m_axis_tkeep_reg = {M_KEEP_WIDTH{1'b0}};
    reg m_axis_tvalid_reg = 1'b0;
    reg m_axis_tlast_reg = 1'b0;
    reg [ID_WIDTH-1:0] m_axis_tid_reg = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg = {USER_WIDTH{1'b0}};

    assign s_axis_tready = !s_axis_tvalid_reg;

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tkeep  = M_KEEP_ENABLE ? m_axis_tkeep_reg : {M_KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tlast_reg;
    assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready;

        if (!m_axis_tvalid_reg || m_axis_tready) begin
            // output register empty

            if (seg_reg == 0) begin
                m_axis_tdata_reg[seg_reg*SEG_DATA_WIDTH +: SEG_DATA_WIDTH] <= s_axis_tvalid_reg ? s_axis_tdata_reg : s_axis_tdata;
                m_axis_tkeep_reg <= s_axis_tvalid_reg ? s_axis_tkeep_reg : s_axis_tkeep;
            end else begin
                m_axis_tdata_reg[seg_reg*SEG_DATA_WIDTH +: SEG_DATA_WIDTH] <= s_axis_tdata;
                m_axis_tkeep_reg[seg_reg*SEG_KEEP_WIDTH +: SEG_KEEP_WIDTH] <= s_axis_tkeep;
            end
            m_axis_tlast_reg <= s_axis_tvalid_reg ? s_axis_tlast_reg : s_axis_tlast;
            m_axis_tid_reg <= s_axis_tvalid_reg ? s_axis_tid_reg : s_axis_tid;
            m_axis_tdest_reg <= s_axis_tvalid_reg ? s_axis_tdest_reg : s_axis_tdest;
            m_axis_tuser_reg <= s_axis_tvalid_reg ? s_axis_tuser_reg : s_axis_tuser;

            if (s_axis_tvalid_reg) begin
                // consume data from buffer
                s_axis_tvalid_reg <= 1'b0;

                if (s_axis_tlast_reg || seg_reg == SEG_COUNT-1) begin
                    seg_reg <= 0;
                    m_axis_tvalid_reg <= 1'b1;
                end else begin
                    seg_reg <= seg_reg + 1;
                end
            end else if (s_axis_tvalid) begin
                // data direct from input
                if (s_axis_tlast || seg_reg == SEG_COUNT-1) begin
                    seg_reg <= 0;
                    m_axis_tvalid_reg <= 1'b1;
                end else begin
                    seg_reg <= seg_reg + 1;
                end
            end
        end else if (s_axis_tvalid && s_axis_tready) begin
            // store input data in skid buffer
            s_axis_tdata_reg <= s_axis_tdata;
            s_axis_tkeep_reg <= s_axis_tkeep;
            s_axis_tvalid_reg <= 1'b1;
            s_axis_tlast_reg <= s_axis_tlast;
            s_axis_tid_reg <= s_axis_tid;
            s_axis_tdest_reg <= s_axis_tdest;
            s_axis_tuser_reg <= s_axis_tuser;
        end

        if (rst) begin
            seg_reg <= 0;
            s_axis_tvalid_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end else begin : downsize
    // output is narrower; downsize

    // required number of segments in wider bus
    localparam SEG_COUNT = S_BYTE_LANES / M_BYTE_LANES;
    // data width and keep width per segment
    localparam SEG_DATA_WIDTH = S_DATA_WIDTH / SEG_COUNT;
    localparam SEG_KEEP_WIDTH = S_BYTE_LANES / SEG_COUNT;

    reg [S_DATA_WIDTH-1:0] s_axis_tdata_reg = {S_DATA_WIDTH{1'b0}};
    reg [S_KEEP_WIDTH-1:0] s_axis_tkeep_reg = {S_KEEP_WIDTH{1'b0}};
    reg s_axis_tvalid_reg = 1'b0;
    reg s_axis_tlast_reg = 1'b0;
    reg [ID_WIDTH-1:0] s_axis_tid_reg = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] s_axis_tdest_reg = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] s_axis_tuser_reg = {USER_WIDTH{1'b0}};

    reg [M_DATA_WIDTH-1:0] m_axis_tdata_reg = {M_DATA_WIDTH{1'b0}};
    reg [M_KEEP_WIDTH-1:0] m_axis_tkeep_reg = {M_KEEP_WIDTH{1'b0}};
    reg m_axis_tvalid_reg = 1'b0;
    reg m_axis_tlast_reg = 1'b0;
    reg [ID_WIDTH-1:0] m_axis_tid_reg = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg = {USER_WIDTH{1'b0}};

    assign s_axis_tready = !s_axis_tvalid_reg;

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tkeep  = M_KEEP_ENABLE ? m_axis_tkeep_reg : {M_KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tlast_reg;
    assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready;

        if (!m_axis_tvalid_reg || m_axis_tready) begin
            // output register empty

            m_axis_tdata_reg <= s_axis_tvalid_reg ? s_axis_tdata_reg : s_axis_tdata;
            m_axis_tkeep_reg <= s_axis_tvalid_reg ? s_axis_tkeep_reg : s_axis_tkeep;
            m_axis_tlast_reg <= 1'b0;
            m_axis_tid_reg <= s_axis_tvalid_reg ? s_axis_tid_reg : s_axis_tid;
            m_axis_tdest_reg <= s_axis_tvalid_reg ? s_axis_tdest_reg : s_axis_tdest;
            m_axis_tuser_reg <= s_axis_tvalid_reg ? s_axis_tuser_reg : s_axis_tuser;

            if (s_axis_tvalid_reg) begin
                // buffer has data; shift out from buffer
                s_axis_tdata_reg <= s_axis_tdata_reg >> SEG_DATA_WIDTH;
                s_axis_tkeep_reg <= s_axis_tkeep_reg >> SEG_KEEP_WIDTH;

                m_axis_tvalid_reg <= 1'b1;

                if ((s_axis_tkeep_reg >> SEG_KEEP_WIDTH) == 0) begin
                    s_axis_tvalid_reg <= 1'b0;
                    m_axis_tlast_reg <= s_axis_tlast_reg;
                end
            end else if (s_axis_tvalid && s_axis_tready) begin
                // buffer is empty; store from input
                s_axis_tdata_reg <= s_axis_tdata >> SEG_DATA_WIDTH;
                s_axis_tkeep_reg <= s_axis_tkeep >> SEG_KEEP_WIDTH;
                s_axis_tlast_reg <= s_axis_tlast;
                s_axis_tid_reg <= s_axis_tid;
                s_axis_tdest_reg <= s_axis_tdest;
                s_axis_tuser_reg <= s_axis_tuser;

                m_axis_tvalid_reg <= 1'b1;

                if ((s_axis_tkeep >> SEG_KEEP_WIDTH) == 0) begin
                    s_axis_tvalid_reg <= 1'b0;
                    m_axis_tlast_reg <= s_axis_tlast;
                end else begin
                    s_axis_tvalid_reg <= 1'b1;
                end
            end
        end else if (s_axis_tvalid && s_axis_tready) begin
            // store input data
            s_axis_tdata_reg <= s_axis_tdata;
            s_axis_tkeep_reg <= s_axis_tkeep;
            s_axis_tvalid_reg <= 1'b1;
            s_axis_tlast_reg <= s_axis_tlast;
            s_axis_tid_reg <= s_axis_tid;
            s_axis_tdest_reg <= s_axis_tdest;
            s_axis_tuser_reg <= s_axis_tuser;
        end

        if (rst) begin
            s_axis_tvalid_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_async_fifo.v
/*

Copyright (c) 2014-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream asynchronous FIFO
 */
module axis_async_fifo #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    // Propagate tlast signal
    parameter LAST_ENABLE = 1,
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    /*
     * AXI input
     */
    input  wire                   s_clk,
    input  wire                   s_rst,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                   m_clk,
    input  wire                   m_rst,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /*
     * Pause
     */
    input  wire                   s_pause_req,
    output wire                   s_pause_ack,
    input  wire                   m_pause_req,
    output wire                   m_pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0] s_status_depth,
    output wire [$clog2(DEPTH):0] s_status_depth_commit,
    output wire                   s_status_overflow,
    output wire                   s_status_bad_frame,
    output wire                   s_status_good_frame,
    output wire [$clog2(DEPTH):0] m_status_depth,
    output wire [$clog2(DEPTH):0] m_status_depth_commit,
    output wire                   m_status_overflow,
    output wire                   m_status_bad_frame,
    output wire                   m_status_good_frame
);

parameter ADDR_WIDTH = (KEEP_ENABLE && KEEP_WIDTH > 1) ? $clog2(DEPTH/KEEP_WIDTH) : $clog2(DEPTH);

parameter OUTPUT_FIFO_ADDR_WIDTH = RAM_PIPELINE < 2 ? 3 : $clog2(RAM_PIPELINE*2+7);

// check configuration
initial begin
    if (FRAME_FIFO && !LAST_ENABLE) begin
        $display("Error: FRAME_FIFO set requires LAST_ENABLE set (instance %m)");
        $finish;
    end

    if (DROP_OVERSIZE_FRAME && !FRAME_FIFO) begin
        $display("Error: DROP_OVERSIZE_FRAME set requires FRAME_FIFO set (instance %m)");
        $finish;
    end

    if (DROP_BAD_FRAME && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_BAD_FRAME set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if (DROP_WHEN_FULL && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_WHEN_FULL set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if ((DROP_BAD_FRAME || MARK_WHEN_FULL) && (USER_BAD_FRAME_MASK & {USER_WIDTH{1'b1}}) == 0) begin
        $display("Error: Invalid USER_BAD_FRAME_MASK value (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && FRAME_FIFO) begin
        $display("Error: MARK_WHEN_FULL is not compatible with FRAME_FIFO (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && !LAST_ENABLE) begin
        $display("Error: MARK_WHEN_FULL set requires LAST_ENABLE set (instance %m)");
        $finish;
    end
end

localparam KEEP_OFFSET = DATA_WIDTH;
localparam LAST_OFFSET = KEEP_OFFSET + (KEEP_ENABLE ? KEEP_WIDTH : 0);
localparam ID_OFFSET   = LAST_OFFSET + (LAST_ENABLE ? 1          : 0);
localparam DEST_OFFSET = ID_OFFSET   + (ID_ENABLE   ? ID_WIDTH   : 0);
localparam USER_OFFSET = DEST_OFFSET + (DEST_ENABLE ? DEST_WIDTH : 0);
localparam WIDTH       = USER_OFFSET + (USER_ENABLE ? USER_WIDTH : 0);

function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = b ^ (b >> 1);
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    for (i = 0; i <= ADDR_WIDTH; i = i + 1) begin
        gray2bin[i] = ^(g >> i);
    end
endfunction

reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_sync_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};

reg [ADDR_WIDTH:0] wr_ptr_temp;
reg [ADDR_WIDTH:0] rd_ptr_temp;

(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_commit_sync_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};

reg wr_ptr_update_valid_reg = 1'b0;
reg wr_ptr_update_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync1_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync2_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync3_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_ack_sync1_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_ack_sync2_reg = 1'b0;

(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync1_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync2_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync3_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync1_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync2_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync3_reg = 1'b1;

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0];
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first TWO MSBs do NOT match, but rest matches
// (gray code equivalent of first MSB different but rest same)
wire full = wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}});
// empty when pointers match exactly
wire empty = FRAME_FIFO ? (rd_ptr_reg == wr_ptr_commit_sync_reg) : (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg);
// overflow within packet
wire full_wr = wr_ptr_reg == (wr_ptr_commit_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});

// control signals
reg write;
reg read;
reg store_output;

reg s_frame_reg = 1'b0;
reg m_frame_reg = 1'b0;

reg drop_frame_reg = 1'b0;
reg mark_frame_reg = 1'b0;
reg send_frame_reg = 1'b0;
reg overflow_reg = 1'b0;
reg bad_frame_reg = 1'b0;
reg good_frame_reg = 1'b0;

reg m_drop_frame_reg = 1'b0;
reg m_terminate_frame_reg = 1'b0;

reg [ADDR_WIDTH:0] s_depth_reg = 0;
reg [ADDR_WIDTH:0] s_depth_commit_reg = 0;
reg [ADDR_WIDTH:0] m_depth_reg = 0;
reg [ADDR_WIDTH:0] m_depth_commit_reg = 0;

reg overflow_sync1_reg = 1'b0;
reg overflow_sync2_reg = 1'b0;
reg overflow_sync3_reg = 1'b0;
reg overflow_sync4_reg = 1'b0;
reg bad_frame_sync1_reg = 1'b0;
reg bad_frame_sync2_reg = 1'b0;
reg bad_frame_sync3_reg = 1'b0;
reg bad_frame_sync4_reg = 1'b0;
reg good_frame_sync1_reg = 1'b0;
reg good_frame_sync2_reg = 1'b0;
reg good_frame_sync3_reg = 1'b0;
reg good_frame_sync4_reg = 1'b0;

assign s_axis_tready = (FRAME_FIFO ? (!full || (full_wr && DROP_OVERSIZE_FRAME) || DROP_WHEN_FULL) : (!full || MARK_WHEN_FULL)) && !s_rst_sync3_reg;

wire [WIDTH-1:0] s_axis;

generate
    assign s_axis[DATA_WIDTH-1:0] = s_axis_tdata;
    if (KEEP_ENABLE) assign s_axis[KEEP_OFFSET +: KEEP_WIDTH] = s_axis_tkeep;
    if (LAST_ENABLE) assign s_axis[LAST_OFFSET]               = s_axis_tlast | mark_frame_reg;
    if (ID_ENABLE)   assign s_axis[ID_OFFSET   +: ID_WIDTH]   = s_axis_tid;
    if (DEST_ENABLE) assign s_axis[DEST_OFFSET +: DEST_WIDTH] = s_axis_tdest;
    if (USER_ENABLE) assign s_axis[USER_OFFSET +: USER_WIDTH] = mark_frame_reg ? USER_BAD_FRAME_VALUE : s_axis_tuser;
endgenerate

wire [WIDTH-1:0] m_axis = m_axis_pipe_reg[RAM_PIPELINE+1-1];

wire                   m_axis_tready_pipe;
wire                   m_axis_tvalid_pipe = m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1];

wire [DATA_WIDTH-1:0]  m_axis_tdata_pipe  = m_axis[DATA_WIDTH-1:0];
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_pipe  = KEEP_ENABLE ? m_axis[KEEP_OFFSET +: KEEP_WIDTH] : {KEEP_WIDTH{1'b1}};
wire                   m_axis_tlast_pipe  = LAST_ENABLE ? m_axis[LAST_OFFSET] | m_terminate_frame_reg : 1'b1;
wire [ID_WIDTH-1:0]    m_axis_tid_pipe    = ID_ENABLE   ? m_axis[ID_OFFSET +: ID_WIDTH] : {ID_WIDTH{1'b0}};
wire [DEST_WIDTH-1:0]  m_axis_tdest_pipe  = DEST_ENABLE ? m_axis[DEST_OFFSET +: DEST_WIDTH] : {DEST_WIDTH{1'b0}};
wire [USER_WIDTH-1:0]  m_axis_tuser_pipe  = USER_ENABLE ? (m_terminate_frame_reg ? USER_BAD_FRAME_VALUE : m_axis[USER_OFFSET +: USER_WIDTH]) : {USER_WIDTH{1'b0}};

wire                   m_axis_tready_out;
wire                   m_axis_tvalid_out;

wire [DATA_WIDTH-1:0]  m_axis_tdata_out;
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_out;
wire                   m_axis_tlast_out;
wire [ID_WIDTH-1:0]    m_axis_tid_out;
wire [DEST_WIDTH-1:0]  m_axis_tdest_out;
wire [USER_WIDTH-1:0]  m_axis_tuser_out;

wire pipe_ready;

assign s_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_reg, {$clog2(KEEP_WIDTH){1'b0}}} : s_depth_reg;
assign s_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {s_depth_commit_reg, {$clog2(KEEP_WIDTH){1'b0}}} : s_depth_commit_reg;
assign s_status_overflow = overflow_reg;
assign s_status_bad_frame = bad_frame_reg;
assign s_status_good_frame = good_frame_reg;

assign m_status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_reg, {$clog2(KEEP_WIDTH){1'b0}}} : m_depth_reg;
assign m_status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {m_depth_commit_reg, {$clog2(KEEP_WIDTH){1'b0}}} : m_depth_commit_reg;
assign m_status_overflow = overflow_sync3_reg ^ overflow_sync4_reg;
assign m_status_bad_frame = bad_frame_sync3_reg ^ bad_frame_sync4_reg;
assign m_status_good_frame = good_frame_sync3_reg ^ good_frame_sync4_reg;

// reset synchronization
always @(posedge m_clk or posedge m_rst) begin
    if (m_rst) begin
        s_rst_sync1_reg <= 1'b1;
    end else begin
        s_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge s_clk) begin
    s_rst_sync2_reg <= s_rst_sync1_reg;
    s_rst_sync3_reg <= s_rst_sync2_reg;
end

always @(posedge s_clk or posedge s_rst) begin
    if (s_rst) begin
        m_rst_sync1_reg <= 1'b1;
    end else begin
        m_rst_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    m_rst_sync2_reg <= m_rst_sync1_reg;
    m_rst_sync3_reg <= m_rst_sync2_reg;
end

// Write logic
always @(posedge s_clk) begin
    overflow_reg <= 1'b0;
    bad_frame_reg <= 1'b0;
    good_frame_reg <= 1'b0;

    if (FRAME_FIFO && wr_ptr_update_valid_reg) begin
        // have updated pointer to sync
        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
            // no sync in progress; sync update
            wr_ptr_update_valid_reg <= 1'b0;
            wr_ptr_sync_commit_reg <= wr_ptr_commit_reg;
            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
        end
    end

    if (s_axis_tready && s_axis_tvalid && LAST_ENABLE) begin
        // track input frame status
        s_frame_reg <= !s_axis_tlast;
    end

    if (s_rst_sync3_reg && LAST_ENABLE) begin
        // if sink side is reset during transfer, drop partial frame
        if (s_frame_reg && !(s_axis_tready && s_axis_tvalid && s_axis_tlast)) begin
            drop_frame_reg <= 1'b1;
        end
        if (s_axis_tready && s_axis_tvalid && !s_axis_tlast) begin
            drop_frame_reg <= 1'b1;
        end
    end

    if (FRAME_FIFO) begin
        // frame FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            // transfer in
            if ((full && DROP_WHEN_FULL) || (full_wr && DROP_OVERSIZE_FRAME) || drop_frame_reg) begin
                // full, packet overflow, or currently dropping frame
                // drop frame
                drop_frame_reg <= 1'b1;
                if (s_axis_tlast) begin
                    // end of frame, reset write pointer
                    wr_ptr_temp = wr_ptr_commit_reg;
                    wr_ptr_reg <= wr_ptr_temp;
                    wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                if (s_axis_tlast || (!DROP_OVERSIZE_FRAME && (full_wr || send_frame_reg))) begin
                    // end of frame or send frame
                    send_frame_reg <= !s_axis_tlast;
                    if (s_axis_tlast && DROP_BAD_FRAME && USER_BAD_FRAME_MASK & ~(s_axis_tuser ^ USER_BAD_FRAME_VALUE)) begin
                        // bad packet, reset write pointer
                        wr_ptr_temp = wr_ptr_commit_reg;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                        bad_frame_reg <= 1'b1;
                    end else begin
                        // good packet or packet overflow, update write pointer
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

                        if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                            // no sync in progress; sync update
                            wr_ptr_update_valid_reg <= 1'b0;
                            wr_ptr_sync_commit_reg <= wr_ptr_temp;
                            wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
                        end else begin
                            // sync in progress; flag it for later
                            wr_ptr_update_valid_reg <= 1'b1;
                        end

                        good_frame_reg <= s_axis_tlast;
                    end
                end
            end
        end else if (s_axis_tvalid && full_wr && FRAME_FIFO && !DROP_OVERSIZE_FRAME) begin
            // data valid with packet overflow
            // update write pointer
            send_frame_reg <= 1'b1;
            wr_ptr_temp = wr_ptr_reg;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);

            if (wr_ptr_update_reg == wr_ptr_update_ack_sync2_reg) begin
                // no sync in progress; sync update
                wr_ptr_update_valid_reg <= 1'b0;
                wr_ptr_sync_commit_reg <= wr_ptr_temp;
                wr_ptr_update_reg <= !wr_ptr_update_ack_sync2_reg;
            end else begin
                // sync in progress; flag it for later
                wr_ptr_update_valid_reg <= 1'b1;
            end
        end
    end else begin
        // normal FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            if (drop_frame_reg && LAST_ENABLE) begin
                // currently dropping frame
                if (s_axis_tlast) begin
                    // end of frame
                    if (!full && mark_frame_reg && MARK_WHEN_FULL) begin
                        // terminate marked frame
                        mark_frame_reg <= 1'b0;
                        mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                        wr_ptr_temp = wr_ptr_reg + 1;
                        wr_ptr_reg <= wr_ptr_temp;
                        wr_ptr_commit_reg <= wr_ptr_temp;
                        wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
                    end
                    // end of frame, clear drop flag
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else if ((full || mark_frame_reg) && MARK_WHEN_FULL) begin
                // full or marking frame
                // drop frame; mark if this isn't the first cycle
                drop_frame_reg <= 1'b1;
                mark_frame_reg <= mark_frame_reg || s_frame_reg;
                if (s_axis_tlast) begin
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                // transfer in
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_temp = wr_ptr_reg + 1;
                wr_ptr_reg <= wr_ptr_temp;
                wr_ptr_commit_reg <= wr_ptr_temp;
                wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
            end
        end else if ((!full && !drop_frame_reg && mark_frame_reg) && MARK_WHEN_FULL) begin
            // terminate marked frame
            mark_frame_reg <= 1'b0;
            mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
            wr_ptr_temp = wr_ptr_reg + 1;
            wr_ptr_reg <= wr_ptr_temp;
            wr_ptr_commit_reg <= wr_ptr_temp;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_temp);
        end
    end

    if (s_rst_sync3_reg) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;
    end

    if (s_rst) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_sync_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        wr_ptr_update_valid_reg <= 1'b0;
        wr_ptr_update_reg <= 1'b0;

        s_frame_reg <= 1'b0;

        drop_frame_reg <= 1'b0;
        mark_frame_reg <= 1'b0;
        send_frame_reg <= 1'b0;
        overflow_reg <= 1'b0;
        bad_frame_reg <= 1'b0;
        good_frame_reg <= 1'b0;
    end
end

// Write-side status
always @(posedge s_clk) begin
    rd_ptr_conv_reg <= gray2bin(rd_ptr_gray_sync2_reg);
    s_depth_reg <= wr_ptr_reg - rd_ptr_conv_reg;
    s_depth_commit_reg <= wr_ptr_commit_reg - rd_ptr_conv_reg;
end

// pointer synchronization
always @(posedge s_clk) begin
    rd_ptr_gray_sync1_reg <= rd_ptr_gray_reg;
    rd_ptr_gray_sync2_reg <= rd_ptr_gray_sync1_reg;
    wr_ptr_update_ack_sync1_reg <= wr_ptr_update_sync3_reg;
    wr_ptr_update_ack_sync2_reg <= wr_ptr_update_ack_sync1_reg;

    if (s_rst) begin
        rd_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_ack_sync1_reg <= 1'b0;
        wr_ptr_update_ack_sync2_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    wr_ptr_gray_sync1_reg <= wr_ptr_gray_reg;
    wr_ptr_gray_sync2_reg <= wr_ptr_gray_sync1_reg;
    if (FRAME_FIFO && wr_ptr_update_sync2_reg ^ wr_ptr_update_sync3_reg) begin
        wr_ptr_commit_sync_reg <= wr_ptr_sync_commit_reg;
    end
    wr_ptr_update_sync1_reg <= wr_ptr_update_reg;
    wr_ptr_update_sync2_reg <= wr_ptr_update_sync1_reg;
    wr_ptr_update_sync3_reg <= wr_ptr_update_sync2_reg;

    if (FRAME_FIFO && m_rst_sync3_reg) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_sync_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_update_sync1_reg <= 1'b0;
        wr_ptr_update_sync2_reg <= 1'b0;
        wr_ptr_update_sync3_reg <= 1'b0;
    end
end

// status synchronization
always @(posedge s_clk) begin
    overflow_sync1_reg <= overflow_sync1_reg ^ overflow_reg;
    bad_frame_sync1_reg <= bad_frame_sync1_reg ^ bad_frame_reg;
    good_frame_sync1_reg <= good_frame_sync1_reg ^ good_frame_reg;

    if (s_rst) begin
        overflow_sync1_reg <= 1'b0;
        bad_frame_sync1_reg <= 1'b0;
        good_frame_sync1_reg <= 1'b0;
    end
end

always @(posedge m_clk) begin
    overflow_sync2_reg <= overflow_sync1_reg;
    overflow_sync3_reg <= overflow_sync2_reg;
    overflow_sync4_reg <= overflow_sync3_reg;
    bad_frame_sync2_reg <= bad_frame_sync1_reg;
    bad_frame_sync3_reg <= bad_frame_sync2_reg;
    bad_frame_sync4_reg <= bad_frame_sync3_reg;
    good_frame_sync2_reg <= good_frame_sync1_reg;
    good_frame_sync3_reg <= good_frame_sync2_reg;
    good_frame_sync4_reg <= good_frame_sync3_reg;

    if (m_rst) begin
        overflow_sync2_reg <= 1'b0;
        overflow_sync3_reg <= 1'b0;
        overflow_sync4_reg <= 1'b0;
        bad_frame_sync2_reg <= 1'b0;
        bad_frame_sync3_reg <= 1'b0;
        bad_frame_sync4_reg <= 1'b0;
        good_frame_sync2_reg <= 1'b0;
        good_frame_sync3_reg <= 1'b0;
        good_frame_sync4_reg <= 1'b0;
    end
end

// Read logic
integer j;

always @(posedge m_clk) begin
    if (m_axis_tready_pipe) begin
        // output ready; invalidate stage
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end

    for (j = RAM_PIPELINE+1-1; j > 0; j = j - 1) begin
        if (m_axis_tready_pipe || ((~m_axis_tvalid_pipe_reg) >> j)) begin
            // output ready or bubble in pipeline; transfer down pipeline
            m_axis_tvalid_pipe_reg[j] <= m_axis_tvalid_pipe_reg[j-1];
            m_axis_pipe_reg[j] <= m_axis_pipe_reg[j-1];
            m_axis_tvalid_pipe_reg[j-1] <= 1'b0;
        end
    end

    if (m_axis_tready_pipe || ~m_axis_tvalid_pipe_reg) begin
        // output ready or bubble in pipeline; read new data from FIFO
        m_axis_tvalid_pipe_reg[0] <= 1'b0;
        m_axis_pipe_reg[0] <= mem[rd_ptr_reg[ADDR_WIDTH-1:0]];
        if (!empty && !m_rst_sync3_reg && !m_drop_frame_reg && pipe_ready) begin
            // not empty, increment pointer
            m_axis_tvalid_pipe_reg[0] <= 1'b1;
            rd_ptr_temp = rd_ptr_reg + 1;
            rd_ptr_reg <= rd_ptr_temp;
            rd_ptr_gray_reg <= rd_ptr_temp ^ (rd_ptr_temp >> 1);
        end
    end

    if (m_axis_tvalid_pipe && LAST_ENABLE) begin
        // track output frame status
        if (m_axis_tlast_pipe && m_axis_tready_pipe) begin
            m_frame_reg <= 1'b0;
        end else begin
            m_frame_reg <= 1'b1;
        end
    end

    if (m_drop_frame_reg && (OUTPUT_FIFO_ENABLE ? pipe_ready : m_axis_tready_pipe || !m_axis_tvalid_pipe) && LAST_ENABLE) begin
        // terminate frame
        // (only for frame transfers interrupted by source reset)
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b1;
        m_terminate_frame_reg <= 1'b1;
        m_drop_frame_reg <= 1'b0;
    end

    if (m_rst_sync3_reg && LAST_ENABLE) begin
        // if source side is reset during transfer, drop partial frame

        // empty output pipeline, except for last stage
        if (RAM_PIPELINE > 0) begin
            m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-2:0] <= 0;
        end

        if (m_frame_reg && (!m_axis_tvalid_pipe || (m_axis_tvalid_pipe && !m_axis_tlast_pipe)) &&
                !(m_drop_frame_reg || m_terminate_frame_reg)) begin
            // terminate frame
            m_drop_frame_reg <= 1'b1;
        end
    end

    if (m_rst_sync3_reg) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
    end

    if (m_rst) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        m_axis_tvalid_pipe_reg <= 0;
        m_frame_reg <= 1'b0;
        m_drop_frame_reg <= 1'b0;
        m_terminate_frame_reg <= 1'b0;
    end
end

// Read-side status
always @(posedge m_clk) begin
    wr_ptr_conv_reg <= gray2bin(wr_ptr_gray_sync2_reg);
    m_depth_reg <= wr_ptr_conv_reg - rd_ptr_reg;
    m_depth_commit_reg <= FRAME_FIFO ? wr_ptr_commit_sync_reg - rd_ptr_reg : wr_ptr_conv_reg - rd_ptr_reg;
end

generate

if (!OUTPUT_FIFO_ENABLE) begin

    assign pipe_ready = 1'b1;

    assign m_axis_tready_pipe = m_axis_tready_out;
    assign m_axis_tvalid_out = m_axis_tvalid_pipe;

    assign m_axis_tdata_out = m_axis_tdata_pipe;
    assign m_axis_tkeep_out = m_axis_tkeep_pipe;
    assign m_axis_tlast_out = m_axis_tlast_pipe;
    assign m_axis_tid_out   = m_axis_tid_pipe;
    assign m_axis_tdest_out = m_axis_tdest_pipe;
    assign m_axis_tuser_out = m_axis_tuser_pipe;

end else begin : output_fifo

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0;
    reg                  m_axis_tlast_reg  = 1'b0;
    reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
    reg out_fifo_half_full_reg = 1'b0;

    wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
    wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [KEEP_WIDTH-1:0] out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg                  out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [ID_WIDTH-1:0]   out_fifo_tid[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [DEST_WIDTH-1:0] out_fifo_tdest[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

    assign pipe_ready = !out_fifo_half_full_reg;

    assign m_axis_tready_pipe = 1'b1;

    assign m_axis_tdata_out  = m_axis_tdata_reg;
    assign m_axis_tkeep_out  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid_out = m_axis_tvalid_reg;
    assign m_axis_tlast_out  = LAST_ENABLE ? m_axis_tlast_reg : 1'b1;
    assign m_axis_tid_out    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest_out  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser_out  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge m_clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready_out;

        out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

        if (!out_fifo_full && m_axis_tvalid_pipe) begin
            out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdata_pipe;
            out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tkeep_pipe;
            out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlast_pipe;
            out_fifo_tid[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tid_pipe;
            out_fifo_tdest[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdest_pipe;
            out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tuser_pipe;
            out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
        end

        if (!out_fifo_empty && (!m_axis_tvalid_reg || m_axis_tready_out)) begin
            m_axis_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tvalid_reg <= 1'b1;
            m_axis_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tid_reg <= out_fifo_tid[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tdest_reg <= out_fifo_tdest[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        end

        if (m_rst) begin
            out_fifo_wr_ptr_reg <= 0;
            out_fifo_rd_ptr_reg <= 0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end

if (PAUSE_ENABLE) begin : pause

    // Pause logic
    reg pause_reg = 1'b0;
    reg pause_frame_reg = 1'b0;

    reg s_pause_req_sync1_reg;
    reg s_pause_req_sync2_reg;
    reg s_pause_req_sync3_reg;
    reg s_pause_ack_sync1_reg;
    reg s_pause_ack_sync2_reg;
    reg s_pause_ack_sync3_reg;

    always @(posedge s_clk) begin
        s_pause_req_sync1_reg <= s_pause_req;
        s_pause_ack_sync2_reg <= s_pause_ack_sync1_reg;
        s_pause_ack_sync3_reg <= s_pause_ack_sync2_reg;
    end

    always @(posedge m_clk) begin
        s_pause_req_sync2_reg <= s_pause_req_sync1_reg;
        s_pause_req_sync3_reg <= s_pause_req_sync2_reg;
        s_pause_ack_sync1_reg <= pause_reg;
    end

    assign m_axis_tready_out = m_axis_tready && !pause_reg;
    assign m_axis_tvalid = m_axis_tvalid_out && !pause_reg;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = s_pause_ack_sync3_reg;
    assign m_pause_ack = pause_reg;

    always @(posedge m_clk) begin
        if (FRAME_PAUSE) begin
            if (pause_reg) begin
                // paused; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end else if (m_axis_tvalid_out) begin
                // frame transfer; set frame bit
                pause_frame_reg <= 1'b1;
                if (m_axis_tready && m_axis_tlast) begin
                    // end of frame; clear frame bit and update pause status
                    pause_frame_reg <= 1'b0;
                    pause_reg <= m_pause_req || s_pause_req_sync3_reg;
                end
            end else if (!pause_frame_reg) begin
                // idle; update pause status
                pause_reg <= m_pause_req || s_pause_req_sync3_reg;
            end
        end else begin
            pause_reg <= m_pause_req || s_pause_req_sync3_reg;
        end

        if (m_rst) begin
            pause_frame_reg <= 1'b0;
            pause_reg <= 1'b0;
        end
    end

end else begin

    assign m_axis_tready_out = m_axis_tready;
    assign m_axis_tvalid = m_axis_tvalid_out;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign s_pause_ack = 1'b0;
    assign m_pause_ack = 1'b0;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_async_fifo_adapter.v
/*

Copyright (c) 2019 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream asynchronous FIFO with width converter
 */
module axis_async_fifo_adapter #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of input AXI stream interface in bits
    parameter S_DATA_WIDTH = 8,
    // Propagate tkeep signal on input interface
    // If disabled, tkeep assumed to be 1'b1
    parameter S_KEEP_ENABLE = (S_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on input interface
    parameter S_KEEP_WIDTH = ((S_DATA_WIDTH+7)/8),
    // Width of output AXI stream interface in bits
    parameter M_DATA_WIDTH = 8,
    // Propagate tkeep signal on output interface
    // If disabled, tkeep assumed to be 1'b1
    parameter M_KEEP_ENABLE = (M_DATA_WIDTH>8),
    // tkeep signal width (words per cycle) on output interface
    parameter M_KEEP_WIDTH = ((M_DATA_WIDTH+7)/8),
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers in FIFO
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    /*
     * AXI input
     */
    input  wire                     s_clk,
    input  wire                     s_rst,
    input  wire [S_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [S_KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,
    input  wire [ID_WIDTH-1:0]      s_axis_tid,
    input  wire [DEST_WIDTH-1:0]    s_axis_tdest,
    input  wire [USER_WIDTH-1:0]    s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                     m_clk,
    input  wire                     m_rst,
    output wire [M_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [M_KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast,
    output wire [ID_WIDTH-1:0]      m_axis_tid,
    output wire [DEST_WIDTH-1:0]    m_axis_tdest,
    output wire [USER_WIDTH-1:0]    m_axis_tuser,

    /*
     * Pause
     */
    input  wire                     s_pause_req,
    output wire                     s_pause_ack,
    input  wire                     m_pause_req,
    output wire                     m_pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0]   s_status_depth,
    output wire [$clog2(DEPTH):0]   s_status_depth_commit,
    output wire                     s_status_overflow,
    output wire                     s_status_bad_frame,
    output wire                     s_status_good_frame,
    output wire [$clog2(DEPTH):0]   m_status_depth,
    output wire [$clog2(DEPTH):0]   m_status_depth_commit,
    output wire                     m_status_overflow,
    output wire                     m_status_bad_frame,
    output wire                     m_status_good_frame
);

// force keep width to 1 when disabled
localparam S_BYTE_LANES = S_KEEP_ENABLE ? S_KEEP_WIDTH : 1;
localparam M_BYTE_LANES = M_KEEP_ENABLE ? M_KEEP_WIDTH : 1;

// bus byte sizes (must be identical)
localparam S_BYTE_SIZE = S_DATA_WIDTH / S_BYTE_LANES;
localparam M_BYTE_SIZE = M_DATA_WIDTH / M_BYTE_LANES;
// output bus is wider
localparam EXPAND_BUS = M_BYTE_LANES > S_BYTE_LANES;
// total data and keep widths
localparam DATA_WIDTH = EXPAND_BUS ? M_DATA_WIDTH : S_DATA_WIDTH;
localparam KEEP_WIDTH = EXPAND_BUS ? M_BYTE_LANES : S_BYTE_LANES;

// bus width assertions
initial begin
    if (S_BYTE_SIZE * S_BYTE_LANES != S_DATA_WIDTH) begin
        $display("Error: input data width not evenly divisible (instance %m)");
        $finish;
    end

    if (M_BYTE_SIZE * M_BYTE_LANES != M_DATA_WIDTH) begin
        $display("Error: output data width not evenly divisible (instance %m)");
        $finish;
    end

    if (S_BYTE_SIZE != M_BYTE_SIZE) begin
        $display("Error: byte size mismatch (instance %m)");
        $finish;
    end
end

wire [DATA_WIDTH-1:0]  pre_fifo_axis_tdata;
wire [KEEP_WIDTH-1:0]  pre_fifo_axis_tkeep;
wire                   pre_fifo_axis_tvalid;
wire                   pre_fifo_axis_tready;
wire                   pre_fifo_axis_tlast;
wire [ID_WIDTH-1:0]    pre_fifo_axis_tid;
wire [DEST_WIDTH-1:0]  pre_fifo_axis_tdest;
wire [USER_WIDTH-1:0]  pre_fifo_axis_tuser;

wire [DATA_WIDTH-1:0]  post_fifo_axis_tdata;
wire [KEEP_WIDTH-1:0]  post_fifo_axis_tkeep;
wire                   post_fifo_axis_tvalid;
wire                   post_fifo_axis_tready;
wire                   post_fifo_axis_tlast;
wire [ID_WIDTH-1:0]    post_fifo_axis_tid;
wire [DEST_WIDTH-1:0]  post_fifo_axis_tdest;
wire [USER_WIDTH-1:0]  post_fifo_axis_tuser;

generate

if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize_pre

    // output wider, adapt width before FIFO

    axis_adapter #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .S_KEEP_ENABLE(S_KEEP_ENABLE),
        .S_KEEP_WIDTH(S_KEEP_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
        .M_KEEP_ENABLE(M_KEEP_ENABLE),
        .M_KEEP_WIDTH(M_KEEP_WIDTH),
        .ID_ENABLE(ID_ENABLE),
        .ID_WIDTH(ID_WIDTH),
        .DEST_ENABLE(DEST_ENABLE),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(USER_ENABLE),
        .USER_WIDTH(USER_WIDTH)
    )
    adapter_inst (
        .clk(s_clk),
        .rst(s_rst),
        // AXI input
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(s_axis_tid),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tuser(s_axis_tuser),
        // AXI output
        .m_axis_tdata(pre_fifo_axis_tdata),
        .m_axis_tkeep(pre_fifo_axis_tkeep),
        .m_axis_tvalid(pre_fifo_axis_tvalid),
        .m_axis_tready(pre_fifo_axis_tready),
        .m_axis_tlast(pre_fifo_axis_tlast),
        .m_axis_tid(pre_fifo_axis_tid),
        .m_axis_tdest(pre_fifo_axis_tdest),
        .m_axis_tuser(pre_fifo_axis_tuser)
    );

end else begin : bypass_pre

    assign pre_fifo_axis_tdata = s_axis_tdata;
    assign pre_fifo_axis_tkeep = s_axis_tkeep;
    assign pre_fifo_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = pre_fifo_axis_tready;
    assign pre_fifo_axis_tlast = s_axis_tlast;
    assign pre_fifo_axis_tid = s_axis_tid;
    assign pre_fifo_axis_tdest = s_axis_tdest;
    assign pre_fifo_axis_tuser = s_axis_tuser;

end

axis_async_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(EXPAND_BUS ? M_KEEP_ENABLE : S_KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH),
    .LAST_ENABLE(1),
    .ID_ENABLE(ID_ENABLE),
    .ID_WIDTH(ID_WIDTH),
    .DEST_ENABLE(DEST_ENABLE),
    .DEST_WIDTH(DEST_WIDTH),
    .USER_ENABLE(USER_ENABLE),
    .USER_WIDTH(USER_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .OUTPUT_FIFO_ENABLE(OUTPUT_FIFO_ENABLE),
    .FRAME_FIFO(FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(USER_BAD_FRAME_VALUE),
    .USER_BAD_FRAME_MASK(USER_BAD_FRAME_MASK),
    .DROP_OVERSIZE_FRAME(DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(DROP_BAD_FRAME),
    .DROP_WHEN_FULL(DROP_WHEN_FULL),
    .MARK_WHEN_FULL(MARK_WHEN_FULL),
    .PAUSE_ENABLE(PAUSE_ENABLE),
    .FRAME_PAUSE(FRAME_PAUSE)
)
fifo_inst (
    // AXI input
    .s_clk(s_clk),
    .s_rst(s_rst),
    .s_axis_tdata(pre_fifo_axis_tdata),
    .s_axis_tkeep(pre_fifo_axis_tkeep),
    .s_axis_tvalid(pre_fifo_axis_tvalid),
    .s_axis_tready(pre_fifo_axis_tready),
    .s_axis_tlast(pre_fifo_axis_tlast),
    .s_axis_tid(pre_fifo_axis_tid),
    .s_axis_tdest(pre_fifo_axis_tdest),
    .s_axis_tuser(pre_fifo_axis_tuser),
    // AXI output
    .m_clk(m_clk),
    .m_rst(m_rst),
    .m_axis_tdata(post_fifo_axis_tdata),
    .m_axis_tkeep(post_fifo_axis_tkeep),
    .m_axis_tvalid(post_fifo_axis_tvalid),
    .m_axis_tready(post_fifo_axis_tready),
    .m_axis_tlast(post_fifo_axis_tlast),
    .m_axis_tid(post_fifo_axis_tid),
    .m_axis_tdest(post_fifo_axis_tdest),
    .m_axis_tuser(post_fifo_axis_tuser),
    // Pause
    .s_pause_req(s_pause_req),
    .s_pause_ack(s_pause_ack),
    .m_pause_req(m_pause_req),
    .m_pause_ack(m_pause_ack),
    // Status
    .s_status_depth(s_status_depth),
    .s_status_depth_commit(s_status_depth_commit),
    .s_status_overflow(s_status_overflow),
    .s_status_bad_frame(s_status_bad_frame),
    .s_status_good_frame(s_status_good_frame),
    .m_status_depth(m_status_depth),
    .m_status_depth_commit(m_status_depth_commit),
    .m_status_overflow(m_status_overflow),
    .m_status_bad_frame(m_status_bad_frame),
    .m_status_good_frame(m_status_good_frame)
);

if (M_BYTE_LANES < S_BYTE_LANES) begin : downsize_post

    // input wider, adapt width after FIFO

    axis_adapter #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .S_KEEP_ENABLE(S_KEEP_ENABLE),
        .S_KEEP_WIDTH(S_KEEP_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
        .M_KEEP_ENABLE(M_KEEP_ENABLE),
        .M_KEEP_WIDTH(M_KEEP_WIDTH),
        .ID_ENABLE(ID_ENABLE),
        .ID_WIDTH(ID_WIDTH),
        .DEST_ENABLE(DEST_ENABLE),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(USER_ENABLE),
        .USER_WIDTH(USER_WIDTH)
    )
    adapter_inst (
        .clk(m_clk),
        .rst(m_rst),
        // AXI input
        .s_axis_tdata(post_fifo_axis_tdata),
        .s_axis_tkeep(post_fifo_axis_tkeep),
        .s_axis_tvalid(post_fifo_axis_tvalid),
        .s_axis_tready(post_fifo_axis_tready),
        .s_axis_tlast(post_fifo_axis_tlast),
        .s_axis_tid(post_fifo_axis_tid),
        .s_axis_tdest(post_fifo_axis_tdest),
        .s_axis_tuser(post_fifo_axis_tuser),
        // AXI output
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tid(m_axis_tid),
        .m_axis_tdest(m_axis_tdest),
        .m_axis_tuser(m_axis_tuser)
    );

end else begin : bypass_post

    assign m_axis_tdata = post_fifo_axis_tdata;
    assign m_axis_tkeep = post_fifo_axis_tkeep;
    assign m_axis_tvalid = post_fifo_axis_tvalid;
    assign post_fifo_axis_tready = m_axis_tready;
    assign m_axis_tlast = post_fifo_axis_tlast;
    assign m_axis_tid = post_fifo_axis_tid;
    assign m_axis_tdest = post_fifo_axis_tdest;
    assign m_axis_tuser = post_fifo_axis_tuser;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_fifo.v
/*

Copyright (c) 2013-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream FIFO
 */
module axis_fifo #
(
    // FIFO depth in words
    // KEEP_WIDTH words per cycle if KEEP_ENABLE set
    // Rounded up to nearest power of 2 cycles
    parameter DEPTH = 4096,
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    // Propagate tlast signal
    parameter LAST_ENABLE = 1,
    // Propagate tid signal
    parameter ID_ENABLE = 0,
    // tid signal width
    parameter ID_WIDTH = 8,
    // Propagate tdest signal
    parameter DEST_ENABLE = 0,
    // tdest signal width
    parameter DEST_WIDTH = 8,
    // Propagate tuser signal
    parameter USER_ENABLE = 1,
    // tuser signal width
    parameter USER_WIDTH = 1,
    // number of RAM pipeline registers
    parameter RAM_PIPELINE = 1,
    // use output FIFO
    // When set, the RAM read enable and pipeline clock enables are removed
    parameter OUTPUT_FIFO_ENABLE = 0,
    // Frame FIFO mode - operate on frames instead of cycles
    // When set, m_axis_tvalid will not be deasserted within a frame
    // Requires LAST_ENABLE set
    parameter FRAME_FIFO = 0,
    // tuser value for bad frame marker
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    // tuser mask for bad frame marker
    parameter USER_BAD_FRAME_MASK = 1'b1,
    // Drop frames larger than FIFO
    // Requires FRAME_FIFO set
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    // Drop frames marked bad
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_BAD_FRAME = 0,
    // Drop incoming frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO and DROP_OVERSIZE_FRAME set
    parameter DROP_WHEN_FULL = 0,
    // Mark incoming frames as bad frames when full
    // When set, s_axis_tready is always asserted
    // Requires FRAME_FIFO to be clear
    parameter MARK_WHEN_FULL = 0,
    // Enable pause request input
    parameter PAUSE_ENABLE = 0,
    // Pause between frames
    parameter FRAME_PAUSE = FRAME_FIFO
)
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /*
     * Pause
     */
    input  wire                   pause_req,
    output wire                   pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0] status_depth,
    output wire [$clog2(DEPTH):0] status_depth_commit,
    output wire                   status_overflow,
    output wire                   status_bad_frame,
    output wire                   status_good_frame
);

parameter ADDR_WIDTH = (KEEP_ENABLE && KEEP_WIDTH > 1) ? $clog2(DEPTH/KEEP_WIDTH) : $clog2(DEPTH);

parameter OUTPUT_FIFO_ADDR_WIDTH = RAM_PIPELINE < 2 ? 3 : $clog2(RAM_PIPELINE*2+7);

// check configuration
initial begin
    if (FRAME_FIFO && !LAST_ENABLE) begin
        $display("Error: FRAME_FIFO set requires LAST_ENABLE set (instance %m)");
        $finish;
    end

    if (DROP_OVERSIZE_FRAME && !FRAME_FIFO) begin
        $display("Error: DROP_OVERSIZE_FRAME set requires FRAME_FIFO set (instance %m)");
        $finish;
    end

    if (DROP_BAD_FRAME && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_BAD_FRAME set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if (DROP_WHEN_FULL && !(FRAME_FIFO && DROP_OVERSIZE_FRAME)) begin
        $display("Error: DROP_WHEN_FULL set requires FRAME_FIFO and DROP_OVERSIZE_FRAME set (instance %m)");
        $finish;
    end

    if ((DROP_BAD_FRAME || MARK_WHEN_FULL) && (USER_BAD_FRAME_MASK & {USER_WIDTH{1'b1}}) == 0) begin
        $display("Error: Invalid USER_BAD_FRAME_MASK value (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && FRAME_FIFO) begin
        $display("Error: MARK_WHEN_FULL is not compatible with FRAME_FIFO (instance %m)");
        $finish;
    end

    if (MARK_WHEN_FULL && !LAST_ENABLE) begin
        $display("Error: MARK_WHEN_FULL set requires LAST_ENABLE set (instance %m)");
        $finish;
    end
end

localparam KEEP_OFFSET = DATA_WIDTH;
localparam LAST_OFFSET = KEEP_OFFSET + (KEEP_ENABLE ? KEEP_WIDTH : 0);
localparam ID_OFFSET   = LAST_OFFSET + (LAST_ENABLE ? 1          : 0);
localparam DEST_OFFSET = ID_OFFSET   + (ID_ENABLE   ? ID_WIDTH   : 0);
localparam USER_OFFSET = DEST_OFFSET + (DEST_ENABLE ? DEST_WIDTH : 0);
localparam WIDTH       = USER_OFFSET + (USER_ENABLE ? USER_WIDTH : 0);

reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0];
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first MSB different but rest same
wire full = wr_ptr_reg == (rd_ptr_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});
// empty when pointers match exactly
wire empty = wr_ptr_commit_reg == rd_ptr_reg;
// overflow within packet
wire full_wr = wr_ptr_reg == (wr_ptr_commit_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});

reg s_frame_reg = 1'b0;

reg drop_frame_reg = 1'b0;
reg mark_frame_reg = 1'b0;
reg send_frame_reg = 1'b0;
reg [ADDR_WIDTH:0] depth_reg = 0;
reg [ADDR_WIDTH:0] depth_commit_reg = 0;
reg overflow_reg = 1'b0;
reg bad_frame_reg = 1'b0;
reg good_frame_reg = 1'b0;

assign s_axis_tready = FRAME_FIFO ? (!full || (full_wr && DROP_OVERSIZE_FRAME) || DROP_WHEN_FULL) : (!full || MARK_WHEN_FULL);

wire [WIDTH-1:0] s_axis;

generate
    assign s_axis[DATA_WIDTH-1:0] = s_axis_tdata;
    if (KEEP_ENABLE) assign s_axis[KEEP_OFFSET +: KEEP_WIDTH] = s_axis_tkeep;
    if (LAST_ENABLE) assign s_axis[LAST_OFFSET]               = s_axis_tlast | mark_frame_reg;
    if (ID_ENABLE)   assign s_axis[ID_OFFSET   +: ID_WIDTH]   = s_axis_tid;
    if (DEST_ENABLE) assign s_axis[DEST_OFFSET +: DEST_WIDTH] = s_axis_tdest;
    if (USER_ENABLE) assign s_axis[USER_OFFSET +: USER_WIDTH] = mark_frame_reg ? USER_BAD_FRAME_VALUE : s_axis_tuser;
endgenerate

wire [WIDTH-1:0] m_axis = m_axis_pipe_reg[RAM_PIPELINE+1-1];

wire                   m_axis_tready_pipe;
wire                   m_axis_tvalid_pipe = m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1];

wire [DATA_WIDTH-1:0]  m_axis_tdata_pipe  = m_axis[DATA_WIDTH-1:0];
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_pipe  = KEEP_ENABLE ? m_axis[KEEP_OFFSET +: KEEP_WIDTH] : {KEEP_WIDTH{1'b1}};
wire                   m_axis_tlast_pipe  = LAST_ENABLE ? m_axis[LAST_OFFSET] : 1'b1;
wire [ID_WIDTH-1:0]    m_axis_tid_pipe    = ID_ENABLE   ? m_axis[ID_OFFSET +: ID_WIDTH] : {ID_WIDTH{1'b0}};
wire [DEST_WIDTH-1:0]  m_axis_tdest_pipe  = DEST_ENABLE ? m_axis[DEST_OFFSET +: DEST_WIDTH] : {DEST_WIDTH{1'b0}};
wire [USER_WIDTH-1:0]  m_axis_tuser_pipe  = USER_ENABLE ? m_axis[USER_OFFSET +: USER_WIDTH] : {USER_WIDTH{1'b0}};

wire                   m_axis_tready_out;
wire                   m_axis_tvalid_out;

wire [DATA_WIDTH-1:0]  m_axis_tdata_out;
wire [KEEP_WIDTH-1:0]  m_axis_tkeep_out;
wire                   m_axis_tlast_out;
wire [ID_WIDTH-1:0]    m_axis_tid_out;
wire [DEST_WIDTH-1:0]  m_axis_tdest_out;
wire [USER_WIDTH-1:0]  m_axis_tuser_out;

wire pipe_ready;

assign status_depth = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {depth_reg, {$clog2(KEEP_WIDTH){1'b0}}} : depth_reg;
assign status_depth_commit = (KEEP_ENABLE && KEEP_WIDTH > 1) ? {depth_commit_reg, {$clog2(KEEP_WIDTH){1'b0}}} : depth_commit_reg;
assign status_overflow = overflow_reg;
assign status_bad_frame = bad_frame_reg;
assign status_good_frame = good_frame_reg;

// Write logic
always @(posedge clk) begin
    overflow_reg <= 1'b0;
    bad_frame_reg <= 1'b0;
    good_frame_reg <= 1'b0;

    if (s_axis_tready && s_axis_tvalid && LAST_ENABLE) begin
        // track input frame status
        s_frame_reg <= !s_axis_tlast;
    end

    if (FRAME_FIFO) begin
        // frame FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            // transfer in
            if ((full && DROP_WHEN_FULL) || (full_wr && DROP_OVERSIZE_FRAME) || drop_frame_reg) begin
                // full, packet overflow, or currently dropping frame
                // drop frame
                drop_frame_reg <= 1'b1;
                if (s_axis_tlast) begin
                    // end of frame, reset write pointer
                    wr_ptr_reg <= wr_ptr_commit_reg;
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                // store it
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_reg <= wr_ptr_reg + 1;
                if (s_axis_tlast || (!DROP_OVERSIZE_FRAME && (full_wr || send_frame_reg))) begin
                    // end of frame or send frame
                    send_frame_reg <= !s_axis_tlast;
                    if (s_axis_tlast && DROP_BAD_FRAME && USER_BAD_FRAME_MASK & ~(s_axis_tuser ^ USER_BAD_FRAME_VALUE)) begin
                        // bad packet, reset write pointer
                        wr_ptr_reg <= wr_ptr_commit_reg;
                        bad_frame_reg <= 1'b1;
                    end else begin
                        // good packet or packet overflow, update write pointer
                        wr_ptr_commit_reg <= wr_ptr_reg + 1;
                        good_frame_reg <= s_axis_tlast;
                    end
                end
            end
        end else if (s_axis_tvalid && full_wr && !DROP_OVERSIZE_FRAME) begin
            // data valid with packet overflow
            // update write pointer
            send_frame_reg <= 1'b1;
            wr_ptr_commit_reg <= wr_ptr_reg;
        end
    end else begin
        // normal FIFO mode
        if (s_axis_tready && s_axis_tvalid) begin
            if (drop_frame_reg && MARK_WHEN_FULL) begin
                // currently dropping frame
                if (s_axis_tlast) begin
                    // end of frame
                    if (!full && mark_frame_reg) begin
                        // terminate marked frame
                        mark_frame_reg <= 1'b0;
                        mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                        wr_ptr_reg <= wr_ptr_reg + 1;
                        wr_ptr_commit_reg <= wr_ptr_reg + 1;
                    end
                    // end of frame, clear drop flag
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else if ((full || mark_frame_reg) && MARK_WHEN_FULL) begin
                // full or marking frame
                // drop frame; mark if this isn't the first cycle
                drop_frame_reg <= 1'b1;
                mark_frame_reg <= mark_frame_reg || s_frame_reg;
                if (s_axis_tlast) begin
                    drop_frame_reg <= 1'b0;
                    overflow_reg <= 1'b1;
                end
            end else begin
                // transfer in
                mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
                wr_ptr_reg <= wr_ptr_reg + 1;
                wr_ptr_commit_reg <= wr_ptr_reg + 1;
            end
        end else if ((!full && !drop_frame_reg && mark_frame_reg) && MARK_WHEN_FULL) begin
            // terminate marked frame
            mark_frame_reg <= 1'b0;
            mem[wr_ptr_reg[ADDR_WIDTH-1:0]] <= s_axis;
            wr_ptr_reg <= wr_ptr_reg + 1;
            wr_ptr_commit_reg <= wr_ptr_reg + 1;
        end
    end

    if (rst) begin
        wr_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_commit_reg <= {ADDR_WIDTH+1{1'b0}};

        s_frame_reg <= 1'b0;

        drop_frame_reg <= 1'b0;
        mark_frame_reg <= 1'b0;
        send_frame_reg <= 1'b0;
        overflow_reg <= 1'b0;
        bad_frame_reg <= 1'b0;
        good_frame_reg <= 1'b0;
    end
end

// Status
always @(posedge clk) begin
    depth_reg <= wr_ptr_reg - rd_ptr_reg;
    depth_commit_reg <= wr_ptr_commit_reg - rd_ptr_reg;
end

// Read logic
integer j;

always @(posedge clk) begin
    if (m_axis_tready_pipe) begin
        // output ready; invalidate stage
        m_axis_tvalid_pipe_reg[RAM_PIPELINE+1-1] <= 1'b0;
    end

    for (j = RAM_PIPELINE+1-1; j > 0; j = j - 1) begin
        if (m_axis_tready_pipe || ((~m_axis_tvalid_pipe_reg) >> j)) begin
            // output ready or bubble in pipeline; transfer down pipeline
            m_axis_tvalid_pipe_reg[j] <= m_axis_tvalid_pipe_reg[j-1];
            m_axis_pipe_reg[j] <= m_axis_pipe_reg[j-1];
            m_axis_tvalid_pipe_reg[j-1] <= 1'b0;
        end
    end

    if (m_axis_tready_pipe || ~m_axis_tvalid_pipe_reg) begin
        // output ready or bubble in pipeline; read new data from FIFO
        m_axis_tvalid_pipe_reg[0] <= 1'b0;
        m_axis_pipe_reg[0] <= mem[rd_ptr_reg[ADDR_WIDTH-1:0]];
        if (!empty && pipe_ready) begin
            // not empty, increment pointer
            m_axis_tvalid_pipe_reg[0] <= 1'b1;
            rd_ptr_reg <= rd_ptr_reg + 1;
        end
    end

    if (rst) begin
        rd_ptr_reg <= {ADDR_WIDTH+1{1'b0}};
        m_axis_tvalid_pipe_reg <= 0;
    end
end

generate

if (!OUTPUT_FIFO_ENABLE) begin

    assign pipe_ready = 1'b1;

    assign m_axis_tready_pipe = m_axis_tready_out;
    assign m_axis_tvalid_out = m_axis_tvalid_pipe;

    assign m_axis_tdata_out = m_axis_tdata_pipe;
    assign m_axis_tkeep_out = m_axis_tkeep_pipe;
    assign m_axis_tlast_out = m_axis_tlast_pipe;
    assign m_axis_tid_out   = m_axis_tid_pipe;
    assign m_axis_tdest_out = m_axis_tdest_pipe;
    assign m_axis_tuser_out = m_axis_tuser_pipe;

end else begin : output_fifo

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0;
    reg                  m_axis_tlast_reg  = 1'b0;
    reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
    reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
    reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
    reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
    reg out_fifo_half_full_reg = 1'b0;

    wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
    wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [KEEP_WIDTH-1:0] out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg                  out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [ID_WIDTH-1:0]   out_fifo_tid[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [DEST_WIDTH-1:0] out_fifo_tdest[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

    assign pipe_ready = !out_fifo_half_full_reg;

    assign m_axis_tready_pipe = 1'b1;

    assign m_axis_tdata_out  = m_axis_tdata_reg;
    assign m_axis_tkeep_out  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_axis_tvalid_out = m_axis_tvalid_reg;
    assign m_axis_tlast_out  = LAST_ENABLE ? m_axis_tlast_reg : 1'b1;
    assign m_axis_tid_out    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
    assign m_axis_tdest_out  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
    assign m_axis_tuser_out  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_reg && !m_axis_tready_out;

        out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

        if (!out_fifo_full && m_axis_tvalid_pipe) begin
            out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdata_pipe;
            out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tkeep_pipe;
            out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlast_pipe;
            out_fifo_tid[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tid_pipe;
            out_fifo_tdest[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tdest_pipe;
            out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tuser_pipe;
            out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
        end

        if (!out_fifo_empty && (!m_axis_tvalid_reg || m_axis_tready_out)) begin
            m_axis_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tvalid_reg <= 1'b1;
            m_axis_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tid_reg <= out_fifo_tid[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tdest_reg <= out_fifo_tdest[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            m_axis_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
            out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        end

        if (rst) begin
            out_fifo_wr_ptr_reg <= 0;
            out_fifo_rd_ptr_reg <= 0;
            m_axis_tvalid_reg <= 1'b0;
        end
    end

end

if (PAUSE_ENABLE) begin : pause

    // Pause logic
    reg pause_reg = 1'b0;
    reg pause_frame_reg = 1'b0;

    assign m_axis_tready_out = m_axis_tready && !pause_reg;
    assign m_axis_tvalid = m_axis_tvalid_out && !pause_reg;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign pause_ack = pause_reg;

    always @(posedge clk) begin
        if (FRAME_PAUSE) begin
            if (pause_reg) begin
                // paused; update pause status
                pause_reg <= pause_req;
            end else if (m_axis_tvalid_out) begin
                // frame transfer; set frame bit
                pause_frame_reg <= 1'b1;
                if (m_axis_tready && m_axis_tlast) begin
                    // end of frame; clear frame bit and update pause status
                    pause_frame_reg <= 1'b0;
                    pause_reg <= pause_req;
                end
            end else if (!pause_frame_reg) begin
                // idle; update pause status
                pause_reg <= pause_req;
            end
        end else begin
            pause_reg <= pause_req;
        end

        if (rst) begin
            pause_frame_reg <= 1'b0;
            pause_reg <= 1'b0;
        end
    end

end else begin

    assign m_axis_tready_out = m_axis_tready;
    assign m_axis_tvalid = m_axis_tvalid_out;

    assign m_axis_tdata = m_axis_tdata_out;
    assign m_axis_tkeep = m_axis_tkeep_out;
    assign m_axis_tlast = m_axis_tlast_out;
    assign m_axis_tid   = m_axis_tid_out;
    assign m_axis_tdest = m_axis_tdest_out;
    assign m_axis_tuser = m_axis_tuser_out;

    assign pause_ack = 1'b0;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_gmii_rx.v
/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream GMII frame receiver (GMII in, AXI out)
 */
module axis_gmii_rx #
(
    parameter DATA_WIDTH = 8,
    parameter PTP_TS_ENABLE = 0,
    parameter PTP_TS_WIDTH = 96,
    parameter USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1
)
(
    input  wire                     clk,
    input  wire                     rst,

    /*
     * GMII input
     */
    input  wire [DATA_WIDTH-1:0]    gmii_rxd,
    input  wire                     gmii_rx_dv,
    input  wire                     gmii_rx_er,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]    m_axis_tdata,
    output wire                     m_axis_tvalid,
    output wire                     m_axis_tlast,
    output wire [USER_WIDTH-1:0]    m_axis_tuser,

    /*
     * PTP
     */
    input  wire [PTP_TS_WIDTH-1:0]  ptp_ts,

    /*
     * Control
     */
    input  wire                     clk_enable,
    input  wire                     mii_select,

    /*
     * Configuration
     */
    input  wire                     cfg_rx_enable,

    /*
     * Status
     */
    output wire                     start_packet,
    output wire                     error_bad_frame,
    output wire                     error_bad_fcs
);

// bus width assertions
initial begin
    if (DATA_WIDTH != 8) begin
        $display("Error: Interface width must be 8");
        $finish;
    end
end

localparam [7:0]
    ETH_PRE = 8'h55,
    ETH_SFD = 8'hD5;

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_PAYLOAD = 3'd1,
    STATE_WAIT_LAST = 3'd2;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg reset_crc;
reg update_crc;

reg mii_odd = 1'b0;
reg in_frame = 1'b0;

reg [DATA_WIDTH-1:0] gmii_rxd_d0 = {DATA_WIDTH{1'b0}};
reg [DATA_WIDTH-1:0] gmii_rxd_d1 = {DATA_WIDTH{1'b0}};
reg [DATA_WIDTH-1:0] gmii_rxd_d2 = {DATA_WIDTH{1'b0}};
reg [DATA_WIDTH-1:0] gmii_rxd_d3 = {DATA_WIDTH{1'b0}};
reg [DATA_WIDTH-1:0] gmii_rxd_d4 = {DATA_WIDTH{1'b0}};

reg gmii_rx_dv_d0 = 1'b0;
reg gmii_rx_dv_d1 = 1'b0;
reg gmii_rx_dv_d2 = 1'b0;
reg gmii_rx_dv_d3 = 1'b0;
reg gmii_rx_dv_d4 = 1'b0;

reg gmii_rx_er_d0 = 1'b0;
reg gmii_rx_er_d1 = 1'b0;
reg gmii_rx_er_d2 = 1'b0;
reg gmii_rx_er_d3 = 1'b0;
reg gmii_rx_er_d4 = 1'b0;

reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}}, m_axis_tdata_next;
reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
reg m_axis_tlast_reg = 1'b0, m_axis_tlast_next;
reg m_axis_tuser_reg = 1'b0, m_axis_tuser_next;

reg start_packet_int_reg = 1'b0;
reg start_packet_reg = 1'b0;
reg error_bad_frame_reg = 1'b0, error_bad_frame_next;
reg error_bad_fcs_reg = 1'b0, error_bad_fcs_next;

reg [PTP_TS_WIDTH-1:0] ptp_ts_reg = 0;

reg [31:0] crc_state = 32'hFFFFFFFF;
wire [31:0] crc_next;

assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast = m_axis_tlast_reg;
assign m_axis_tuser = PTP_TS_ENABLE ? {ptp_ts_reg, m_axis_tuser_reg} : m_axis_tuser_reg;

assign start_packet = start_packet_reg;
assign error_bad_frame = error_bad_frame_reg;
assign error_bad_fcs = error_bad_fcs_reg;

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(8),
    .STYLE("AUTO")
)
eth_crc_8 (
    .data_in(gmii_rxd_d4),
    .state_in(crc_state),
    .data_out(),
    .state_out(crc_next)
);

always @* begin
    state_next = STATE_IDLE;

    reset_crc = 1'b0;
    update_crc = 1'b0;

    m_axis_tdata_next = {DATA_WIDTH{1'b0}};
    m_axis_tvalid_next = 1'b0;
    m_axis_tlast_next = 1'b0;
    m_axis_tuser_next = 1'b0;

    error_bad_frame_next = 1'b0;
    error_bad_fcs_next = 1'b0;

    if (!clk_enable) begin
        // clock disabled - hold state
        state_next = state_reg;
    end else if (mii_select && !mii_odd) begin
        // MII even cycle - hold state
        state_next = state_reg;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                // idle state - wait for packet
                reset_crc = 1'b1;

                if (gmii_rx_dv_d4 && !gmii_rx_er_d4 && gmii_rxd_d4 == ETH_SFD && cfg_rx_enable) begin
                    state_next = STATE_PAYLOAD;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_PAYLOAD: begin
                // read payload
                update_crc = 1'b1;

                m_axis_tdata_next = gmii_rxd_d4;
                m_axis_tvalid_next = 1'b1;

                if (gmii_rx_dv_d4 && gmii_rx_er_d4) begin
                    // error
                    m_axis_tlast_next = 1'b1;
                    m_axis_tuser_next = 1'b1;
                    error_bad_frame_next = 1'b1;
                    state_next = STATE_WAIT_LAST;
                end else if (!gmii_rx_dv) begin
                    // end of packet
                    m_axis_tlast_next = 1'b1;
                    if (gmii_rx_er_d0 || gmii_rx_er_d1 || gmii_rx_er_d2 || gmii_rx_er_d3) begin
                        // error received in FCS bytes
                        m_axis_tuser_next = 1'b1;
                        error_bad_frame_next = 1'b1;
                    end else if ({gmii_rxd_d0, gmii_rxd_d1, gmii_rxd_d2, gmii_rxd_d3} == ~crc_next) begin
                        // FCS good
                        m_axis_tuser_next = 1'b0;
                    end else begin
                        // FCS bad
                        m_axis_tuser_next = 1'b1;
                        error_bad_frame_next = 1'b1;
                        error_bad_fcs_next = 1'b1;
                    end
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_PAYLOAD;
                end
            end
            STATE_WAIT_LAST: begin
                // wait for end of packet

                if (~gmii_rx_dv) begin
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end
        endcase
    end
end

always @(posedge clk) begin
    state_reg <= state_next;

    m_axis_tdata_reg <= m_axis_tdata_next;
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tlast_reg <= m_axis_tlast_next;
    m_axis_tuser_reg <= m_axis_tuser_next;

    start_packet_int_reg <= 1'b0;
    start_packet_reg <= 1'b0;

    if (start_packet_int_reg) begin
        ptp_ts_reg <= ptp_ts;
        start_packet_reg <= 1'b1;
    end

    if (clk_enable) begin
        if (mii_select) begin
            mii_odd <= !mii_odd;

            if (in_frame) begin
                in_frame <= gmii_rx_dv;
            end else if (gmii_rx_dv && {gmii_rxd[3:0], gmii_rxd_d0[7:4]} == ETH_SFD) begin
                in_frame <= 1'b1;
                start_packet_int_reg <= 1'b1;
                mii_odd <= 1'b1;
            end

            gmii_rxd_d0 <= {gmii_rxd[3:0], gmii_rxd_d0[7:4]};

            if (mii_odd) begin
                gmii_rxd_d1 <= gmii_rxd_d0;
                gmii_rxd_d2 <= gmii_rxd_d1;
                gmii_rxd_d3 <= gmii_rxd_d2;
                gmii_rxd_d4 <= gmii_rxd_d3;

                gmii_rx_dv_d0 <= gmii_rx_dv & gmii_rx_dv_d0;
                gmii_rx_dv_d1 <= gmii_rx_dv_d0 & gmii_rx_dv;
                gmii_rx_dv_d2 <= gmii_rx_dv_d1 & gmii_rx_dv;
                gmii_rx_dv_d3 <= gmii_rx_dv_d2 & gmii_rx_dv;
                gmii_rx_dv_d4 <= gmii_rx_dv_d3 & gmii_rx_dv;

                gmii_rx_er_d0 <= gmii_rx_er | gmii_rx_er_d0;
                gmii_rx_er_d1 <= gmii_rx_er_d0;
                gmii_rx_er_d2 <= gmii_rx_er_d1;
                gmii_rx_er_d3 <= gmii_rx_er_d2;
                gmii_rx_er_d4 <= gmii_rx_er_d3;
            end else begin
                gmii_rx_dv_d0 <= gmii_rx_dv;
                gmii_rx_er_d0 <= gmii_rx_er;
            end
        end else begin
            if (in_frame) begin
                in_frame <= gmii_rx_dv;
            end else if (gmii_rx_dv && gmii_rxd == ETH_SFD) begin
                in_frame <= 1'b1;
                start_packet_int_reg <= 1'b1;
            end

            gmii_rxd_d0 <= gmii_rxd;
            gmii_rxd_d1 <= gmii_rxd_d0;
            gmii_rxd_d2 <= gmii_rxd_d1;
            gmii_rxd_d3 <= gmii_rxd_d2;
            gmii_rxd_d4 <= gmii_rxd_d3;

            gmii_rx_dv_d0 <= gmii_rx_dv;
            gmii_rx_dv_d1 <= gmii_rx_dv_d0 & gmii_rx_dv;
            gmii_rx_dv_d2 <= gmii_rx_dv_d1 & gmii_rx_dv;
            gmii_rx_dv_d3 <= gmii_rx_dv_d2 & gmii_rx_dv;
            gmii_rx_dv_d4 <= gmii_rx_dv_d3 & gmii_rx_dv;

            gmii_rx_er_d0 <= gmii_rx_er;
            gmii_rx_er_d1 <= gmii_rx_er_d0;
            gmii_rx_er_d2 <= gmii_rx_er_d1;
            gmii_rx_er_d3 <= gmii_rx_er_d2;
            gmii_rx_er_d4 <= gmii_rx_er_d3;
        end
    end

    if (reset_crc) begin
        crc_state <= 32'hFFFFFFFF;
    end else if (update_crc) begin
        crc_state <= crc_next;
    end

    error_bad_frame_reg <= error_bad_frame_next;
    error_bad_fcs_reg <= error_bad_fcs_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        m_axis_tvalid_reg <= 1'b0;

        start_packet_int_reg <= 1'b0;
        start_packet_reg <= 1'b0;
        error_bad_frame_reg <= 1'b0;
        error_bad_fcs_reg <= 1'b0;

        in_frame <= 1'b0;
        mii_odd <= 1'b0;

        gmii_rx_dv_d0 <= 1'b0;
        gmii_rx_dv_d1 <= 1'b0;
        gmii_rx_dv_d2 <= 1'b0;
        gmii_rx_dv_d3 <= 1'b0;
        gmii_rx_dv_d4 <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/axis_gmii_tx.v
/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream GMII frame transmitter (AXI in, GMII out)
 */
module axis_gmii_tx #
(
    parameter DATA_WIDTH = 8,
    parameter ENABLE_PADDING = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter PTP_TS_ENABLE = 0,
    parameter PTP_TS_WIDTH = 96,
    parameter PTP_TS_CTRL_IN_TUSER = 0,
    parameter PTP_TAG_ENABLE = PTP_TS_ENABLE,
    parameter PTP_TAG_WIDTH = 16,
    parameter USER_WIDTH = (PTP_TS_ENABLE ? (PTP_TAG_ENABLE ? PTP_TAG_WIDTH : 0) + (PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1
)
(
    input  wire                      clk,
    input  wire                      rst,

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH-1:0]     s_axis_tdata,
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire                      s_axis_tlast,
    input  wire [USER_WIDTH-1:0]     s_axis_tuser,

    /*
     * GMII output
     */
    output wire [DATA_WIDTH-1:0]     gmii_txd,
    output wire                      gmii_tx_en,
    output wire                      gmii_tx_er,

    /*
     * PTP
     */
    input  wire [PTP_TS_WIDTH-1:0]   ptp_ts,
    output wire [PTP_TS_WIDTH-1:0]   m_axis_ptp_ts,
    output wire [PTP_TAG_WIDTH-1:0]  m_axis_ptp_ts_tag,
    output wire                      m_axis_ptp_ts_valid,

    /*
     * Control
     */
    input  wire                      clk_enable,
    input  wire                      mii_select,

    /*
     * Configuration
     */
    input  wire [7:0]                cfg_ifg,
    input  wire                      cfg_tx_enable,

    /*
     * Status
     */
    output wire                      start_packet,
    output wire                      error_underflow
);

parameter MIN_LEN_WIDTH = $clog2(MIN_FRAME_LENGTH-4-1+1);

// bus width assertions
initial begin
    if (DATA_WIDTH != 8) begin
        $display("Error: Interface width must be 8");
        $finish;
    end
end

localparam [7:0]
    ETH_PRE = 8'h55,
    ETH_SFD = 8'hD5;

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_PREAMBLE = 3'd1,
    STATE_PAYLOAD = 3'd2,
    STATE_LAST = 3'd3,
    STATE_PAD = 3'd4,
    STATE_FCS = 3'd5,
    STATE_IFG = 3'd6;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg reset_crc;
reg update_crc;

reg [7:0] s_tdata_reg = 8'd0, s_tdata_next;

reg mii_odd_reg = 1'b0, mii_odd_next;
reg [3:0] mii_msn_reg = 4'b0, mii_msn_next;

reg frame_reg = 1'b0, frame_next;
reg frame_error_reg = 1'b0, frame_error_next;
reg [7:0] frame_ptr_reg = 0, frame_ptr_next;
reg [MIN_LEN_WIDTH-1:0] frame_min_count_reg = 0, frame_min_count_next;

reg [7:0] gmii_txd_reg = 8'd0, gmii_txd_next;
reg gmii_tx_en_reg = 1'b0, gmii_tx_en_next;
reg gmii_tx_er_reg = 1'b0, gmii_tx_er_next;

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

reg [PTP_TS_WIDTH-1:0] m_axis_ptp_ts_reg = 0, m_axis_ptp_ts_next;
reg [PTP_TAG_WIDTH-1:0] m_axis_ptp_ts_tag_reg = 0, m_axis_ptp_ts_tag_next;
reg m_axis_ptp_ts_valid_reg = 1'b0, m_axis_ptp_ts_valid_next;

reg start_packet_int_reg = 1'b0, start_packet_int_next;
reg start_packet_reg = 1'b0, start_packet_next;
reg error_underflow_reg = 1'b0, error_underflow_next;

reg [31:0] crc_state = 32'hFFFFFFFF;
wire [31:0] crc_next;

assign s_axis_tready = s_axis_tready_reg;

assign gmii_txd = gmii_txd_reg;
assign gmii_tx_en = gmii_tx_en_reg;
assign gmii_tx_er = gmii_tx_er_reg;

assign m_axis_ptp_ts = PTP_TS_ENABLE ? m_axis_ptp_ts_reg : 0;
assign m_axis_ptp_ts_tag = PTP_TAG_ENABLE ? m_axis_ptp_ts_tag_reg : 0;
assign m_axis_ptp_ts_valid = PTP_TS_ENABLE || PTP_TAG_ENABLE ? m_axis_ptp_ts_valid_reg : 1'b0;

assign start_packet = start_packet_reg;
assign error_underflow = error_underflow_reg;

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(8),
    .STYLE("AUTO")
)
eth_crc_8 (
    .data_in(s_tdata_reg),
    .state_in(crc_state),
    .data_out(),
    .state_out(crc_next)
);

always @* begin
    state_next = STATE_IDLE;

    reset_crc = 1'b0;
    update_crc = 1'b0;

    mii_odd_next = mii_odd_reg;
    mii_msn_next = mii_msn_reg;

    frame_next = frame_reg;
    frame_error_next = frame_error_reg;
    frame_ptr_next = frame_ptr_reg;
    frame_min_count_next = frame_min_count_reg;

    s_axis_tready_next = 1'b0;

    s_tdata_next = s_tdata_reg;

    m_axis_ptp_ts_next = m_axis_ptp_ts_reg;
    m_axis_ptp_ts_tag_next = m_axis_ptp_ts_tag_reg;
    m_axis_ptp_ts_valid_next = 1'b0;

    if (start_packet_reg && PTP_TS_ENABLE) begin
        m_axis_ptp_ts_next = ptp_ts;
        if (PTP_TS_CTRL_IN_TUSER) begin
            m_axis_ptp_ts_tag_next = s_axis_tuser >> 2;
            m_axis_ptp_ts_valid_next = s_axis_tuser[1];
        end else begin
            m_axis_ptp_ts_tag_next = s_axis_tuser >> 1;
            m_axis_ptp_ts_valid_next = 1'b1;
        end
    end

    gmii_txd_next = {DATA_WIDTH{1'b0}};
    gmii_tx_en_next = 1'b0;
    gmii_tx_er_next = 1'b0;

    start_packet_int_next = start_packet_int_reg;
    start_packet_next = 1'b0;
    error_underflow_next = 1'b0;

    if (s_axis_tvalid && s_axis_tready) begin
        frame_next = !s_axis_tlast;
    end

    if (!clk_enable) begin
        // clock disabled - hold state and outputs
        gmii_txd_next = gmii_txd_reg;
        gmii_tx_en_next = gmii_tx_en_reg;
        gmii_tx_er_next = gmii_tx_er_reg;
        state_next = state_reg;
    end else if (mii_select && mii_odd_reg) begin
        // MII odd cycle - hold state, output MSN
        mii_odd_next = 1'b0;
        gmii_txd_next = {4'd0, mii_msn_reg};
        gmii_tx_en_next = gmii_tx_en_reg;
        gmii_tx_er_next = gmii_tx_er_reg;
        state_next = state_reg;
        if (start_packet_int_reg) begin
            start_packet_int_next = 1'b0;
            start_packet_next = 1'b1;
        end
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                // idle state - wait for packet
                reset_crc = 1'b1;

                mii_odd_next = 1'b0;
                frame_ptr_next = 1;

                frame_error_next = 1'b0;
                frame_min_count_next = MIN_FRAME_LENGTH-4-1;

                if (s_axis_tvalid && cfg_tx_enable) begin
                    mii_odd_next = 1'b1;
                    gmii_txd_next = ETH_PRE;
                    gmii_tx_en_next = 1'b1;
                    state_next = STATE_PREAMBLE;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_PREAMBLE: begin
                // send preamble
                reset_crc = 1'b1;

                mii_odd_next = 1'b1;
                frame_ptr_next = frame_ptr_reg + 1;

                gmii_txd_next = ETH_PRE;
                gmii_tx_en_next = 1'b1;

                if (frame_ptr_reg == 6) begin
                    s_axis_tready_next = 1'b1;
                    s_tdata_next = s_axis_tdata;
                    state_next = STATE_PREAMBLE;
                end else if (frame_ptr_reg == 7) begin
                    // end of preamble; start payload
                    frame_ptr_next = 0;
                    if (s_axis_tready_reg) begin
                        s_axis_tready_next = 1'b1;
                        s_tdata_next = s_axis_tdata;
                    end
                    gmii_txd_next = ETH_SFD;
                    if (mii_select) begin
                        start_packet_int_next = 1'b1;
                    end else begin
                        start_packet_next = 1'b1;
                    end
                    state_next = STATE_PAYLOAD;
                end else begin
                    state_next = STATE_PREAMBLE;
                end
            end
            STATE_PAYLOAD: begin
                // send payload

                update_crc = 1'b1;
                s_axis_tready_next = 1'b1;

                mii_odd_next = 1'b1;

                if (frame_min_count_reg) begin
                    frame_min_count_next = frame_min_count_reg - 1;
                end

                gmii_txd_next = s_tdata_reg;
                gmii_tx_en_next = 1'b1;

                s_tdata_next = s_axis_tdata;

                if (!s_axis_tvalid || s_axis_tlast) begin
                    s_axis_tready_next = frame_next; // drop frame
                    frame_error_next = !s_axis_tvalid || s_axis_tuser[0];
                    error_underflow_next = !s_axis_tvalid;

                    state_next = STATE_LAST;
                end else begin
                    state_next = STATE_PAYLOAD;
                end
            end
            STATE_LAST: begin
                // last payload word

                update_crc = 1'b1;
                s_axis_tready_next = 1'b0;

                mii_odd_next = 1'b1;

                gmii_txd_next = s_tdata_reg;
                gmii_tx_en_next = 1'b1;

                if (ENABLE_PADDING && frame_min_count_reg) begin
                    frame_min_count_next = frame_min_count_reg - 1;
                    s_tdata_next = 8'd0;
                    state_next = STATE_PAD;
                end else begin
                    frame_ptr_next = 0;
                    state_next = STATE_FCS;
                end
            end
            STATE_PAD: begin
                // send padding
                s_axis_tready_next = frame_next; // drop frame

                update_crc = 1'b1;
                mii_odd_next = 1'b1;

                gmii_txd_next = 8'd0;
                gmii_tx_en_next = 1'b1;

                s_tdata_next = 8'd0;

                if (frame_min_count_reg) begin
                    frame_min_count_next = frame_min_count_reg - 1;
                    state_next = STATE_PAD;
                end else begin
                    frame_ptr_next = 0;
                    state_next = STATE_FCS;
                end
            end
            STATE_FCS: begin
                // send FCS
                s_axis_tready_next = frame_next; // drop frame

                mii_odd_next = 1'b1;
                frame_ptr_next = frame_ptr_reg + 1;

                case (frame_ptr_reg)
                    2'd0: gmii_txd_next = ~crc_state[7:0];
                    2'd1: gmii_txd_next = ~crc_state[15:8];
                    2'd2: gmii_txd_next = ~crc_state[23:16];
                    2'd3: gmii_txd_next = ~crc_state[31:24];
                endcase
                gmii_tx_en_next = 1'b1;
                gmii_tx_er_next = frame_error_reg;

                if (frame_ptr_reg < 3) begin
                    state_next = STATE_FCS;
                end else begin
                    frame_ptr_next = 0;
                    state_next = STATE_IFG;
                end
            end
            STATE_IFG: begin
                // send IFG
                s_axis_tready_next = frame_next; // drop frame

                mii_odd_next = 1'b1;
                frame_ptr_next = frame_ptr_reg + 1;

                if (frame_ptr_reg < cfg_ifg-1 || frame_reg) begin
                    state_next = STATE_IFG;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
        endcase

        if (mii_select) begin
            mii_msn_next = gmii_txd_next[7:4];
            gmii_txd_next[7:4] = 4'd0;
        end
    end
end

always @(posedge clk) begin
    state_reg <= state_next;

    frame_reg <= frame_next;
    frame_error_reg <= frame_error_next;
    frame_ptr_reg <= frame_ptr_next;
    frame_min_count_reg <= frame_min_count_next;

    m_axis_ptp_ts_reg <= m_axis_ptp_ts_next;
    m_axis_ptp_ts_tag_reg <= m_axis_ptp_ts_tag_next;
    m_axis_ptp_ts_valid_reg <= m_axis_ptp_ts_valid_next;

    mii_odd_reg <= mii_odd_next;
    mii_msn_reg <= mii_msn_next;

    s_tdata_reg <= s_tdata_next;

    s_axis_tready_reg <= s_axis_tready_next;

    gmii_txd_reg <= gmii_txd_next;
    gmii_tx_en_reg <= gmii_tx_en_next;
    gmii_tx_er_reg <= gmii_tx_er_next;

    if (reset_crc) begin
        crc_state <= 32'hFFFFFFFF;
    end else if (update_crc) begin
        crc_state <= crc_next;
    end

    start_packet_int_reg <= start_packet_int_next;
    start_packet_reg <= start_packet_next;
    error_underflow_reg <= error_underflow_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        frame_reg <= 1'b0;

        s_axis_tready_reg <= 1'b0;

        m_axis_ptp_ts_valid_reg <= 1'b0;

        gmii_tx_en_reg <= 1'b0;
        gmii_tx_er_reg <= 1'b0;

        start_packet_int_reg <= 1'b0;
        start_packet_reg <= 1'b0;
        error_underflow_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/eth_arb_mux.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Ethernet arbitrated multiplexer
 */
module eth_arb_mux #
(
    parameter S_COUNT = 4,
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    // select round robin arbitration
    parameter ARB_TYPE_ROUND_ROBIN = 0,
    // LSB priority selection
    parameter ARB_LSB_HIGH_PRIORITY = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * Ethernet frame inputs
     */
    input  wire [S_COUNT-1:0]            s_eth_hdr_valid,
    output wire [S_COUNT-1:0]            s_eth_hdr_ready,
    input  wire [S_COUNT*48-1:0]         s_eth_dest_mac,
    input  wire [S_COUNT*48-1:0]         s_eth_src_mac,
    input  wire [S_COUNT*16-1:0]         s_eth_type,
    input  wire [S_COUNT*DATA_WIDTH-1:0] s_eth_payload_axis_tdata,
    input  wire [S_COUNT*KEEP_WIDTH-1:0] s_eth_payload_axis_tkeep,
    input  wire [S_COUNT-1:0]            s_eth_payload_axis_tvalid,
    output wire [S_COUNT-1:0]            s_eth_payload_axis_tready,
    input  wire [S_COUNT-1:0]            s_eth_payload_axis_tlast,
    input  wire [S_COUNT*ID_WIDTH-1:0]   s_eth_payload_axis_tid,
    input  wire [S_COUNT*DEST_WIDTH-1:0] s_eth_payload_axis_tdest,
    input  wire [S_COUNT*USER_WIDTH-1:0] s_eth_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire                          m_eth_hdr_valid,
    input  wire                          m_eth_hdr_ready,
    output wire [47:0]                   m_eth_dest_mac,
    output wire [47:0]                   m_eth_src_mac,
    output wire [15:0]                   m_eth_type,
    output wire [DATA_WIDTH-1:0]         m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0]         m_eth_payload_axis_tkeep,
    output wire                          m_eth_payload_axis_tvalid,
    input  wire                          m_eth_payload_axis_tready,
    output wire                          m_eth_payload_axis_tlast,
    output wire [ID_WIDTH-1:0]           m_eth_payload_axis_tid,
    output wire [DEST_WIDTH-1:0]         m_eth_payload_axis_tdest,
    output wire [USER_WIDTH-1:0]         m_eth_payload_axis_tuser
);

parameter CL_S_COUNT = $clog2(S_COUNT);

reg frame_reg = 1'b0, frame_next;

reg [S_COUNT-1:0] s_eth_hdr_ready_reg = {S_COUNT{1'b0}}, s_eth_hdr_ready_next;

reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0, m_eth_dest_mac_next;
reg [47:0] m_eth_src_mac_reg = 48'd0, m_eth_src_mac_next;
reg [15:0] m_eth_type_reg = 16'd0, m_eth_type_next;

wire [S_COUNT-1:0] request;
wire [S_COUNT-1:0] acknowledge;
wire [S_COUNT-1:0] grant;
wire grant_valid;
wire [CL_S_COUNT-1:0] grant_encoded;

// internal datapath
reg  [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_int;
reg                   m_eth_payload_axis_tvalid_int;
reg                   m_eth_payload_axis_tready_int_reg = 1'b0;
reg                   m_eth_payload_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_eth_payload_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_eth_payload_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_eth_payload_axis_tuser_int;
wire                  m_eth_payload_axis_tready_int_early;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg;

assign s_eth_payload_axis_tready = (m_eth_payload_axis_tready_int_reg && grant_valid) << grant_encoded;

assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;

// mux for incoming packet
wire [DATA_WIDTH-1:0] current_s_tdata  = s_eth_payload_axis_tdata[grant_encoded*DATA_WIDTH +: DATA_WIDTH];
wire [KEEP_WIDTH-1:0] current_s_tkeep  = s_eth_payload_axis_tkeep[grant_encoded*KEEP_WIDTH +: KEEP_WIDTH];
wire                  current_s_tvalid = s_eth_payload_axis_tvalid[grant_encoded];
wire                  current_s_tready = s_eth_payload_axis_tready[grant_encoded];
wire                  current_s_tlast  = s_eth_payload_axis_tlast[grant_encoded];
wire [ID_WIDTH-1:0]   current_s_tid    = s_eth_payload_axis_tid[grant_encoded*ID_WIDTH +: ID_WIDTH];
wire [DEST_WIDTH-1:0] current_s_tdest  = s_eth_payload_axis_tdest[grant_encoded*DEST_WIDTH +: DEST_WIDTH];
wire [USER_WIDTH-1:0] current_s_tuser  = s_eth_payload_axis_tuser[grant_encoded*USER_WIDTH +: USER_WIDTH];

// arbiter instance
arbiter #(
    .PORTS(S_COUNT),
    .ARB_TYPE_ROUND_ROBIN(ARB_TYPE_ROUND_ROBIN),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .ARB_LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
)
arb_inst (
    .clk(clk),
    .rst(rst),
    .request(request),
    .acknowledge(acknowledge),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_encoded(grant_encoded)
);

assign request = s_eth_hdr_valid & ~grant;
assign acknowledge = grant & s_eth_payload_axis_tvalid & s_eth_payload_axis_tready & s_eth_payload_axis_tlast;

always @* begin
    frame_next = frame_reg;

    s_eth_hdr_ready_next = {S_COUNT{1'b0}};

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg && !m_eth_hdr_ready;
    m_eth_dest_mac_next = m_eth_dest_mac_reg;
    m_eth_src_mac_next = m_eth_src_mac_reg;
    m_eth_type_next = m_eth_type_reg;

    if (s_eth_payload_axis_tvalid[grant_encoded] && s_eth_payload_axis_tready[grant_encoded]) begin
        // end of frame detection
        if (s_eth_payload_axis_tlast[grant_encoded]) begin
            frame_next = 1'b0;
        end
    end

    if (!frame_reg && grant_valid && (m_eth_hdr_ready || !m_eth_hdr_valid)) begin
        // start of frame
        frame_next = 1'b1;

        s_eth_hdr_ready_next = grant;

        m_eth_hdr_valid_next = 1'b1;
        m_eth_dest_mac_next = s_eth_dest_mac[grant_encoded*48 +: 48];
        m_eth_src_mac_next = s_eth_src_mac[grant_encoded*48 +: 48];
        m_eth_type_next = s_eth_type[grant_encoded*16 +: 16];
    end

    // pass through selected packet data
    m_eth_payload_axis_tdata_int  = current_s_tdata;
    m_eth_payload_axis_tkeep_int  = current_s_tkeep;
    m_eth_payload_axis_tvalid_int = current_s_tvalid && m_eth_payload_axis_tready_int_reg && grant_valid;
    m_eth_payload_axis_tlast_int  = current_s_tlast;
    m_eth_payload_axis_tid_int    = current_s_tid;
    m_eth_payload_axis_tdest_int  = current_s_tdest;
    m_eth_payload_axis_tuser_int  = current_s_tuser;
end

always @(posedge clk) begin
    frame_reg <= frame_next;

    s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;

    m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;
    m_eth_dest_mac_reg <= m_eth_dest_mac_next;
    m_eth_src_mac_reg <= m_eth_src_mac_next;
    m_eth_type_reg <= m_eth_type_next;

    if (rst) begin
        frame_reg <= 1'b0;
        s_eth_hdr_ready_reg <= {S_COUNT{1'b0}};
        m_eth_hdr_valid_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
reg                  m_eth_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_eth_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_eth_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_eth_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_eth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_eth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
reg                  temp_m_eth_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_eth_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_eth_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_eth_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_eth_payload_axis_temp_to_output;

assign m_eth_payload_axis_tdata  = m_eth_payload_axis_tdata_reg;
assign m_eth_payload_axis_tkeep  = KEEP_ENABLE ? m_eth_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
assign m_eth_payload_axis_tlast  = m_eth_payload_axis_tlast_reg;
assign m_eth_payload_axis_tid    = ID_ENABLE   ? m_eth_payload_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_eth_payload_axis_tdest  = DEST_ENABLE ? m_eth_payload_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_eth_payload_axis_tuser  = USER_ENABLE ? m_eth_payload_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_eth_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
        temp_m_eth_payload_axis_tvalid_next = 1'b0;
        store_eth_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        m_eth_payload_axis_tid_reg   <= m_eth_payload_axis_tid_int;
        m_eth_payload_axis_tdest_reg <= m_eth_payload_axis_tdest_int;
        m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
        m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
        m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
        m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
        m_eth_payload_axis_tid_reg   <= temp_m_eth_payload_axis_tid_reg;
        m_eth_payload_axis_tdest_reg <= temp_m_eth_payload_axis_tdest_reg;
        m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        temp_m_eth_payload_axis_tid_reg   <= m_eth_payload_axis_tid_int;
        temp_m_eth_payload_axis_tdest_reg <= m_eth_payload_axis_tdest_int;
        temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
        m_eth_payload_axis_tvalid_reg <= 1'b0;
        m_eth_payload_axis_tready_int_reg <= 1'b0;
        temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/eth_axis_rx.v
/*

Copyright (c) 2014-2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream ethernet frame receiver (AXI in, Ethernet frame out)
 */
module eth_axis_rx #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_axis_tkeep,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,
    input  wire                  s_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire                  m_eth_hdr_valid,
    input  wire                  m_eth_hdr_ready,
    output wire [47:0]           m_eth_dest_mac,
    output wire [47:0]           m_eth_src_mac,
    output wire [15:0]           m_eth_type,
    output wire [DATA_WIDTH-1:0] m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep,
    output wire                  m_eth_payload_axis_tvalid,
    input  wire                  m_eth_payload_axis_tready,
    output wire                  m_eth_payload_axis_tlast,
    output wire                  m_eth_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire                  busy,
    output wire                  error_header_early_termination
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 14;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// bus width assertions
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

/*

Ethernet frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype                   2 octets

This module receives an Ethernet frame on an AXI stream interface, decodes
and strips the headers, then produces the header fields in parallel along
with the payload in a separate AXI stream.

*/

reg read_eth_header_reg = 1'b1, read_eth_header_next;
reg read_eth_payload_reg = 1'b0, read_eth_payload_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg flush_save;
reg transfer_in_save;

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0, m_eth_dest_mac_next;
reg [47:0] m_eth_src_mac_reg = 48'd0, m_eth_src_mac_next;
reg [15:0] m_eth_type_reg = 16'd0, m_eth_type_next;

reg busy_reg = 1'b0;
reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;

reg [DATA_WIDTH-1:0] save_axis_tdata_reg = 64'd0;
reg [KEEP_WIDTH-1:0] save_axis_tkeep_reg = 8'd0;
reg save_axis_tlast_reg = 1'b0;
reg save_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] shift_axis_tdata;
reg [KEEP_WIDTH-1:0] shift_axis_tkeep;
reg shift_axis_tvalid;
reg shift_axis_tlast;
reg shift_axis_tuser;
reg shift_axis_input_tready;
reg shift_axis_extra_cycle_reg = 1'b0;

// internal datapath
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_int;
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_int;
reg                  m_eth_payload_axis_tvalid_int;
reg                  m_eth_payload_axis_tready_int_reg = 1'b0;
reg                  m_eth_payload_axis_tlast_int;
reg                  m_eth_payload_axis_tuser_int;
wire                 m_eth_payload_axis_tready_int_early;

assign s_axis_tready = s_axis_tready_reg;

assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;

assign busy = busy_reg;
assign error_header_early_termination = error_header_early_termination_reg;

always @* begin
    if (OFFSET == 0) begin
        // passthrough if no overlap
        shift_axis_tdata = s_axis_tdata;
        shift_axis_tkeep = s_axis_tkeep;
        shift_axis_tvalid = s_axis_tvalid;
        shift_axis_tlast = s_axis_tlast;
        shift_axis_tuser = s_axis_tuser;
        shift_axis_input_tready = 1'b1;
    end else if (shift_axis_extra_cycle_reg) begin
        shift_axis_tdata = {s_axis_tdata, save_axis_tdata_reg} >> (OFFSET*8);
        shift_axis_tkeep = {{KEEP_WIDTH{1'b0}}, save_axis_tkeep_reg} >> OFFSET;
        shift_axis_tvalid = 1'b1;
        shift_axis_tlast = save_axis_tlast_reg;
        shift_axis_tuser = save_axis_tuser_reg;
        shift_axis_input_tready = flush_save;
    end else begin
        shift_axis_tdata = {s_axis_tdata, save_axis_tdata_reg} >> (OFFSET*8);
        shift_axis_tkeep = {s_axis_tkeep, save_axis_tkeep_reg} >> OFFSET;
        shift_axis_tvalid = s_axis_tvalid;
        shift_axis_tlast = (s_axis_tlast && ((s_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
        shift_axis_tuser = (s_axis_tuser && ((s_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
        shift_axis_input_tready = !(s_axis_tlast && s_axis_tready && s_axis_tvalid);
    end
end

always @* begin
    read_eth_header_next = read_eth_header_reg;
    read_eth_payload_next = read_eth_payload_reg;
    ptr_next = ptr_reg;

    s_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_axis_input_tready && (!m_eth_hdr_valid || m_eth_hdr_ready);

    flush_save = 1'b0;
    transfer_in_save = 1'b0;

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg && !m_eth_hdr_ready;

    m_eth_dest_mac_next = m_eth_dest_mac_reg;
    m_eth_src_mac_next = m_eth_src_mac_reg;
    m_eth_type_next = m_eth_type_reg;

    error_header_early_termination_next = 1'b0;

    m_eth_payload_axis_tdata_int = shift_axis_tdata;
    m_eth_payload_axis_tkeep_int = shift_axis_tkeep;
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int = shift_axis_tlast;
    m_eth_payload_axis_tuser_int = shift_axis_tuser;

    if ((s_axis_tready && s_axis_tvalid) || (m_eth_payload_axis_tready_int_reg && shift_axis_extra_cycle_reg)) begin
        transfer_in_save = 1'b1;

        if (read_eth_header_reg) begin
            // word transfer in - store it
            ptr_next = ptr_reg + 1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

            `_HEADER_FIELD_(0,  m_eth_dest_mac_next[5*8 +: 8])
            `_HEADER_FIELD_(1,  m_eth_dest_mac_next[4*8 +: 8])
            `_HEADER_FIELD_(2,  m_eth_dest_mac_next[3*8 +: 8])
            `_HEADER_FIELD_(3,  m_eth_dest_mac_next[2*8 +: 8])
            `_HEADER_FIELD_(4,  m_eth_dest_mac_next[1*8 +: 8])
            `_HEADER_FIELD_(5,  m_eth_dest_mac_next[0*8 +: 8])
            `_HEADER_FIELD_(6,  m_eth_src_mac_next[5*8 +: 8])
            `_HEADER_FIELD_(7,  m_eth_src_mac_next[4*8 +: 8])
            `_HEADER_FIELD_(8,  m_eth_src_mac_next[3*8 +: 8])
            `_HEADER_FIELD_(9,  m_eth_src_mac_next[2*8 +: 8])
            `_HEADER_FIELD_(10, m_eth_src_mac_next[1*8 +: 8])
            `_HEADER_FIELD_(11, m_eth_src_mac_next[0*8 +: 8])
            `_HEADER_FIELD_(12, m_eth_type_next[1*8 +: 8])
            `_HEADER_FIELD_(13, m_eth_type_next[0*8 +: 8])

            if (ptr_reg == 13/BYTE_LANES && (!KEEP_ENABLE || s_axis_tkeep[13%BYTE_LANES])) begin
                if (!shift_axis_tlast) begin
                    m_eth_hdr_valid_next = 1'b1;
                    read_eth_header_next = 1'b0;
                    read_eth_payload_next = 1'b1;
                end
            end

            `undef _HEADER_FIELD_
        end

        if (read_eth_payload_reg) begin
            // transfer payload
            m_eth_payload_axis_tdata_int = shift_axis_tdata;
            m_eth_payload_axis_tkeep_int = shift_axis_tkeep;
            m_eth_payload_axis_tvalid_int = 1'b1;
            m_eth_payload_axis_tlast_int = shift_axis_tlast;
            m_eth_payload_axis_tuser_int = shift_axis_tuser;
        end

        if (shift_axis_tlast) begin
            if (read_eth_header_next) begin
                // don't have the whole header
                error_header_early_termination_next = 1'b1;
            end

            flush_save = 1'b1;
            ptr_next = 1'b0;
            read_eth_header_next = 1'b1;
            read_eth_payload_next = 1'b0;
        end
    end
end

always @(posedge clk) begin
    read_eth_header_reg <= read_eth_header_next;
    read_eth_payload_reg <= read_eth_payload_next;
    ptr_reg <= ptr_next;

    s_axis_tready_reg <= s_axis_tready_next;

    m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;
    m_eth_dest_mac_reg <= m_eth_dest_mac_next;
    m_eth_src_mac_reg <= m_eth_src_mac_next;
    m_eth_type_reg <= m_eth_type_next;

    error_header_early_termination_reg <= error_header_early_termination_next;

    busy_reg <= (read_eth_payload_next || ptr_next != 0);

    if (transfer_in_save) begin
        save_axis_tdata_reg <= s_axis_tdata;
        save_axis_tkeep_reg <= s_axis_tkeep;
        save_axis_tuser_reg <= s_axis_tuser;
    end

    if (flush_save) begin
        save_axis_tlast_reg <= 1'b0;
        shift_axis_extra_cycle_reg <= 1'b0;
    end else if (transfer_in_save) begin
        save_axis_tlast_reg <= s_axis_tlast;
        shift_axis_extra_cycle_reg <= OFFSET ? s_axis_tlast && ((s_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) != 0) : 1'b0;
    end

    if (rst) begin
        read_eth_header_reg <= 1'b1;
        read_eth_payload_reg <= 1'b0;
        ptr_reg <= 0;
        s_axis_tready_reg <= 1'b0;
        m_eth_hdr_valid_reg <= 1'b0;
        save_axis_tlast_reg <= 1'b0;
        shift_axis_extra_cycle_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_header_early_termination_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
reg                  m_eth_payload_axis_tlast_reg = 1'b0;
reg                  m_eth_payload_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] temp_m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
reg                  temp_m_eth_payload_axis_tlast_reg = 1'b0;
reg                  temp_m_eth_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_eth_payload_int_to_output;
reg store_eth_payload_int_to_temp;
reg store_eth_payload_axis_temp_to_output;

assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
assign m_eth_payload_axis_tkeep = KEEP_ENABLE ? m_eth_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_eth_payload_int_to_output = 1'b0;
    store_eth_payload_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;
    
    if (m_eth_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_temp = 1'b1;
        end
    end else if (m_eth_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
        temp_m_eth_payload_axis_tvalid_next = 1'b0;
        store_eth_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_eth_payload_int_to_output) begin
        m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
        m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
        m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
        m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
        m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_eth_payload_int_to_temp) begin
        temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
        temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
        m_eth_payload_axis_tvalid_reg <= 1'b0;
        m_eth_payload_axis_tready_int_reg <= 1'b0;
        temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/eth_axis_tx.v
/*

Copyright (c) 2014-2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream ethernet frame transmitter (Ethernet frame in, AXI out)
 */
module eth_axis_tx #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * Ethernet frame input
     */
    input  wire                  s_eth_hdr_valid,
    output wire                  s_eth_hdr_ready,
    input  wire [47:0]           s_eth_dest_mac,
    input  wire [47:0]           s_eth_src_mac,
    input  wire [15:0]           s_eth_type,
    input  wire [DATA_WIDTH-1:0] s_eth_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_eth_payload_axis_tkeep,
    input  wire                  s_eth_payload_axis_tvalid,
    output wire                  s_eth_payload_axis_tready,
    input  wire                  s_eth_payload_axis_tlast,
    input  wire                  s_eth_payload_axis_tuser,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire                  m_axis_tuser,

    /*
     * Status signals
     */
    output wire                  busy
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 14;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// bus width assertions
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

/*

Ethernet frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype                   2 octets

This module receives an Ethernet frame with header fields in parallel along
with the payload in an AXI stream, combines the header with the payload, and
transmits the complete Ethernet frame on the output AXI stream interface.

*/

// datapath control signals
reg store_eth_hdr;

reg send_eth_header_reg = 1'b0, send_eth_header_next;
reg send_eth_payload_reg = 1'b0, send_eth_payload_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg flush_save;
reg transfer_in_save;

reg [47:0] eth_dest_mac_reg = 48'd0;
reg [47:0] eth_src_mac_reg = 48'd0;
reg [15:0] eth_type_reg = 16'd0;

reg s_eth_hdr_ready_reg = 1'b0, s_eth_hdr_ready_next;
reg s_eth_payload_axis_tready_reg = 1'b0, s_eth_payload_axis_tready_next;

reg busy_reg = 1'b0;

reg [DATA_WIDTH-1:0] save_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] save_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg save_eth_payload_axis_tlast_reg = 1'b0;
reg save_eth_payload_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] shift_eth_payload_axis_tdata;
reg [KEEP_WIDTH-1:0] shift_eth_payload_axis_tkeep;
reg shift_eth_payload_axis_tvalid;
reg shift_eth_payload_axis_tlast;
reg shift_eth_payload_axis_tuser;
reg shift_eth_payload_axis_input_tready;
reg shift_eth_payload_axis_extra_cycle_reg = 1'b0;

// internal datapath
reg [DATA_WIDTH-1:0] m_axis_tdata_int;
reg [KEEP_WIDTH-1:0] m_axis_tkeep_int;
reg                  m_axis_tvalid_int;
reg                  m_axis_tready_int_reg = 1'b0;
reg                  m_axis_tlast_int;
reg                  m_axis_tuser_int;
wire                 m_axis_tready_int_early;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg;
assign s_eth_payload_axis_tready = s_eth_payload_axis_tready_reg;

assign busy = busy_reg;

always @* begin
    if (OFFSET == 0) begin
        // passthrough if no overlap
        shift_eth_payload_axis_tdata = s_eth_payload_axis_tdata;
        shift_eth_payload_axis_tkeep = s_eth_payload_axis_tkeep;
        shift_eth_payload_axis_tvalid = s_eth_payload_axis_tvalid;
        shift_eth_payload_axis_tlast = s_eth_payload_axis_tlast;
        shift_eth_payload_axis_tuser = s_eth_payload_axis_tuser;
        shift_eth_payload_axis_input_tready = 1'b1;
    end else if (shift_eth_payload_axis_extra_cycle_reg) begin
        shift_eth_payload_axis_tdata = {s_eth_payload_axis_tdata, save_eth_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET)*8);
        shift_eth_payload_axis_tkeep = {{KEEP_WIDTH{1'b0}}, save_eth_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET);
        shift_eth_payload_axis_tvalid = 1'b1;
        shift_eth_payload_axis_tlast = save_eth_payload_axis_tlast_reg;
        shift_eth_payload_axis_tuser = save_eth_payload_axis_tuser_reg;
        shift_eth_payload_axis_input_tready = flush_save;
    end else begin
        shift_eth_payload_axis_tdata = {s_eth_payload_axis_tdata, save_eth_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET)*8);
        shift_eth_payload_axis_tkeep = {s_eth_payload_axis_tkeep, save_eth_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET);
        shift_eth_payload_axis_tvalid = s_eth_payload_axis_tvalid;
        shift_eth_payload_axis_tlast = (s_eth_payload_axis_tlast && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) == 0));
        shift_eth_payload_axis_tuser = (s_eth_payload_axis_tuser && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) == 0));
        shift_eth_payload_axis_input_tready = !(s_eth_payload_axis_tlast && s_eth_payload_axis_tready && s_eth_payload_axis_tvalid);
    end
end

always @* begin
    send_eth_header_next = send_eth_header_reg;
    send_eth_payload_next = send_eth_payload_reg;
    ptr_next = ptr_reg;

    s_eth_hdr_ready_next = 1'b0;
    s_eth_payload_axis_tready_next = 1'b0;

    store_eth_hdr = 1'b0;

    flush_save = 1'b0;
    transfer_in_save = 1'b0;

    m_axis_tdata_int = {DATA_WIDTH{1'b0}};
    m_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
    m_axis_tvalid_int = 1'b0;
    m_axis_tlast_int = 1'b0;
    m_axis_tuser_int = 1'b0;

    if (s_eth_hdr_ready && s_eth_hdr_valid) begin
        store_eth_hdr = 1'b1;
        ptr_next = 0;
        send_eth_header_next = 1'b1;
        send_eth_payload_next = (OFFSET != 0) && (CYCLE_COUNT == 1);
        s_eth_payload_axis_tready_next = send_eth_payload_next && m_axis_tready_int_early;
    end

    if (send_eth_payload_reg) begin
        s_eth_payload_axis_tready_next = m_axis_tready_int_early && shift_eth_payload_axis_input_tready;

        m_axis_tdata_int = shift_eth_payload_axis_tdata;
        m_axis_tkeep_int = shift_eth_payload_axis_tkeep;
        m_axis_tlast_int = shift_eth_payload_axis_tlast;
        m_axis_tuser_int = shift_eth_payload_axis_tuser;

        if ((s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) || (m_axis_tready_int_reg && shift_eth_payload_axis_extra_cycle_reg)) begin
            transfer_in_save = 1'b1;

            m_axis_tvalid_int = 1'b1;

            if (shift_eth_payload_axis_tlast) begin
                flush_save = 1'b1;
                s_eth_payload_axis_tready_next = 1'b0;
                ptr_next = 0;
                send_eth_payload_next = 1'b0;
            end
        end
    end

    if (m_axis_tready_int_reg && (!OFFSET || !send_eth_payload_reg || m_axis_tvalid_int)) begin
        if (send_eth_header_reg) begin
            ptr_next = ptr_reg + 1;

            if ((OFFSET != 0) && (CYCLE_COUNT == 1 || ptr_next == CYCLE_COUNT-1) && !send_eth_payload_reg) begin
                send_eth_payload_next = 1'b1;
                s_eth_payload_axis_tready_next = m_axis_tready_int_early && shift_eth_payload_axis_input_tready;
            end

            m_axis_tvalid_int = 1'b1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end

            `_HEADER_FIELD_(0,  eth_dest_mac_reg[5*8 +: 8])
            `_HEADER_FIELD_(1,  eth_dest_mac_reg[4*8 +: 8])
            `_HEADER_FIELD_(2,  eth_dest_mac_reg[3*8 +: 8])
            `_HEADER_FIELD_(3,  eth_dest_mac_reg[2*8 +: 8])
            `_HEADER_FIELD_(4,  eth_dest_mac_reg[1*8 +: 8])
            `_HEADER_FIELD_(5,  eth_dest_mac_reg[0*8 +: 8])
            `_HEADER_FIELD_(6,  eth_src_mac_reg[5*8 +: 8])
            `_HEADER_FIELD_(7,  eth_src_mac_reg[4*8 +: 8])
            `_HEADER_FIELD_(8,  eth_src_mac_reg[3*8 +: 8])
            `_HEADER_FIELD_(9,  eth_src_mac_reg[2*8 +: 8])
            `_HEADER_FIELD_(10, eth_src_mac_reg[1*8 +: 8])
            `_HEADER_FIELD_(11, eth_src_mac_reg[0*8 +: 8])
            `_HEADER_FIELD_(12, eth_type_reg[1*8 +: 8])
            `_HEADER_FIELD_(13, eth_type_reg[0*8 +: 8])

            if (ptr_reg == 13/BYTE_LANES) begin
                if (!send_eth_payload_reg) begin
                    s_eth_payload_axis_tready_next = m_axis_tready_int_early;
                    send_eth_payload_next = 1'b1;
                end
                send_eth_header_next = 1'b0;
            end

            `undef _HEADER_FIELD_
        end
    end

    s_eth_hdr_ready_next = !(send_eth_header_next || send_eth_payload_next);
end

always @(posedge clk) begin
    send_eth_header_reg <= send_eth_header_next;
    send_eth_payload_reg <= send_eth_payload_next;
    ptr_reg <= ptr_next;

    s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;
    s_eth_payload_axis_tready_reg <= s_eth_payload_axis_tready_next;

    busy_reg <= send_eth_header_next || send_eth_payload_next;

    if (store_eth_hdr) begin
        eth_dest_mac_reg <= s_eth_dest_mac;
        eth_src_mac_reg <= s_eth_src_mac;
        eth_type_reg <= s_eth_type;
    end

    if (transfer_in_save) begin
        save_eth_payload_axis_tdata_reg <= s_eth_payload_axis_tdata;
        save_eth_payload_axis_tkeep_reg <= s_eth_payload_axis_tkeep;
        save_eth_payload_axis_tuser_reg <= s_eth_payload_axis_tuser;
    end

    if (flush_save) begin
        save_eth_payload_axis_tlast_reg <= 1'b0;
        shift_eth_payload_axis_extra_cycle_reg <= 1'b0;
    end else if (transfer_in_save) begin
        save_eth_payload_axis_tlast_reg <= s_eth_payload_axis_tlast;
        shift_eth_payload_axis_extra_cycle_reg <= OFFSET ? s_eth_payload_axis_tlast && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) != 0) : 1'b0;
    end

    if (rst) begin
        send_eth_header_reg <= 1'b0;
        send_eth_payload_reg <= 1'b0;
        ptr_reg <= 0;
        s_eth_hdr_ready_reg <= 1'b0;
        s_eth_payload_axis_tready_reg <= 1'b0;
        busy_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
reg                  m_axis_tlast_reg = 1'b0;
reg                  m_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
reg                  temp_m_axis_tlast_reg = 1'b0;
reg                  temp_m_axis_tuser_reg = 1'b0;

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tkeep = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast = m_axis_tlast_reg;
assign m_axis_tuser = m_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_axis_tready_int_early = m_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_axis_tvalid_next = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;
    
    if (m_axis_tready_int_reg) begin
        // input is ready
        if (m_axis_tready || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_tready) begin
        // input is not ready, but output is ready
        m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tready_int_reg <= m_axis_tready_int_early;
    temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_tdata_reg <= m_axis_tdata_int;
        m_axis_tkeep_reg <= m_axis_tkeep_int;
        m_axis_tlast_reg <= m_axis_tlast_int;
        m_axis_tuser_reg <= m_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_tdata_reg <= temp_m_axis_tdata_reg;
        m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
        m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_tdata_reg <= m_axis_tdata_int;
        temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
        temp_m_axis_tlast_reg <= m_axis_tlast_int;
        temp_m_axis_tuser_reg <= m_axis_tuser_int;
    end

    if (rst) begin
        m_axis_tvalid_reg <= 1'b0;
        m_axis_tready_int_reg <= 1'b0;
        temp_m_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/eth_mac_1g.v
/*

Copyright (c) 2015-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 1G Ethernet MAC
 */
module eth_mac_1g #
(
    parameter DATA_WIDTH = 8,
    parameter ENABLE_PADDING = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter PTP_TS_ENABLE = 0,
    parameter PTP_TS_FMT_TOD = 1,
    parameter PTP_TS_WIDTH = PTP_TS_FMT_TOD ? 96 : 64,
    parameter TX_PTP_TS_CTRL_IN_TUSER = 0,
    parameter TX_PTP_TAG_ENABLE = PTP_TS_ENABLE,
    parameter TX_PTP_TAG_WIDTH = 16,
    parameter TX_USER_WIDTH = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1,
    parameter RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1,
    parameter PFC_ENABLE = 0,
    parameter PAUSE_ENABLE = PFC_ENABLE
)
(
    input  wire                         rx_clk,
    input  wire                         rx_rst,
    input  wire                         tx_clk,
    input  wire                         tx_rst,

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH-1:0]        tx_axis_tdata,
    input  wire                         tx_axis_tvalid,
    output wire                         tx_axis_tready,
    input  wire                         tx_axis_tlast,
    input  wire [TX_USER_WIDTH-1:0]     tx_axis_tuser,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]        rx_axis_tdata,
    output wire                         rx_axis_tvalid,
    output wire                         rx_axis_tlast,
    output wire [RX_USER_WIDTH-1:0]     rx_axis_tuser,

    /*
     * GMII interface
     */
    input  wire [DATA_WIDTH-1:0]        gmii_rxd,
    input  wire                         gmii_rx_dv,
    input  wire                         gmii_rx_er,
    output wire [DATA_WIDTH-1:0]        gmii_txd,
    output wire                         gmii_tx_en,
    output wire                         gmii_tx_er,

    /*
     * PTP
     */
    input  wire [PTP_TS_WIDTH-1:0]      tx_ptp_ts,
    input  wire [PTP_TS_WIDTH-1:0]      rx_ptp_ts,
    output wire [PTP_TS_WIDTH-1:0]      tx_axis_ptp_ts,
    output wire [TX_PTP_TAG_WIDTH-1:0]  tx_axis_ptp_ts_tag,
    output wire                         tx_axis_ptp_ts_valid,

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire                         tx_lfc_req,
    input  wire                         tx_lfc_resend,
    input  wire                         rx_lfc_en,
    output wire                         rx_lfc_req,
    input  wire                         rx_lfc_ack,

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    input  wire [7:0]                   tx_pfc_req,
    input  wire                         tx_pfc_resend,
    input  wire [7:0]                   rx_pfc_en,
    output wire [7:0]                   rx_pfc_req,
    input  wire [7:0]                   rx_pfc_ack,

    /*
     * Pause interface
     */
    input  wire                         tx_lfc_pause_en,
    input  wire                         tx_pause_req,
    output wire                         tx_pause_ack,

    /*
     * Control
     */
    input  wire                         rx_clk_enable,
    input  wire                         tx_clk_enable,
    input  wire                         rx_mii_select,
    input  wire                         tx_mii_select,

    /*
     * Status
     */
    output wire                         tx_start_packet,
    output wire                         tx_error_underflow,
    output wire                         rx_start_packet,
    output wire                         rx_error_bad_frame,
    output wire                         rx_error_bad_fcs,
    output wire                         stat_tx_mcf,
    output wire                         stat_rx_mcf,
    output wire                         stat_tx_lfc_pkt,
    output wire                         stat_tx_lfc_xon,
    output wire                         stat_tx_lfc_xoff,
    output wire                         stat_tx_lfc_paused,
    output wire                         stat_tx_pfc_pkt,
    output wire [7:0]                   stat_tx_pfc_xon,
    output wire [7:0]                   stat_tx_pfc_xoff,
    output wire [7:0]                   stat_tx_pfc_paused,
    output wire                         stat_rx_lfc_pkt,
    output wire                         stat_rx_lfc_xon,
    output wire                         stat_rx_lfc_xoff,
    output wire                         stat_rx_lfc_paused,
    output wire                         stat_rx_pfc_pkt,
    output wire [7:0]                   stat_rx_pfc_xon,
    output wire [7:0]                   stat_rx_pfc_xoff,
    output wire [7:0]                   stat_rx_pfc_paused,

    /*
     * Configuration
     */
    input  wire [7:0]                   cfg_ifg,
    input  wire                         cfg_tx_enable,
    input  wire                         cfg_rx_enable,
    input  wire [47:0]                  cfg_mcf_rx_eth_dst_mcast,
    input  wire                         cfg_mcf_rx_check_eth_dst_mcast,
    input  wire [47:0]                  cfg_mcf_rx_eth_dst_ucast,
    input  wire                         cfg_mcf_rx_check_eth_dst_ucast,
    input  wire [47:0]                  cfg_mcf_rx_eth_src,
    input  wire                         cfg_mcf_rx_check_eth_src,
    input  wire [15:0]                  cfg_mcf_rx_eth_type,
    input  wire [15:0]                  cfg_mcf_rx_opcode_lfc,
    input  wire                         cfg_mcf_rx_check_opcode_lfc,
    input  wire [15:0]                  cfg_mcf_rx_opcode_pfc,
    input  wire                         cfg_mcf_rx_check_opcode_pfc,
    input  wire                         cfg_mcf_rx_forward,
    input  wire                         cfg_mcf_rx_enable,
    input  wire [47:0]                  cfg_tx_lfc_eth_dst,
    input  wire [47:0]                  cfg_tx_lfc_eth_src,
    input  wire [15:0]                  cfg_tx_lfc_eth_type,
    input  wire [15:0]                  cfg_tx_lfc_opcode,
    input  wire                         cfg_tx_lfc_en,
    input  wire [15:0]                  cfg_tx_lfc_quanta,
    input  wire [15:0]                  cfg_tx_lfc_refresh,
    input  wire [47:0]                  cfg_tx_pfc_eth_dst,
    input  wire [47:0]                  cfg_tx_pfc_eth_src,
    input  wire [15:0]                  cfg_tx_pfc_eth_type,
    input  wire [15:0]                  cfg_tx_pfc_opcode,
    input  wire                         cfg_tx_pfc_en,
    input  wire [8*16-1:0]              cfg_tx_pfc_quanta,
    input  wire [8*16-1:0]              cfg_tx_pfc_refresh,
    input  wire [15:0]                  cfg_rx_lfc_opcode,
    input  wire                         cfg_rx_lfc_en,
    input  wire [15:0]                  cfg_rx_pfc_opcode,
    input  wire                         cfg_rx_pfc_en
);

parameter MAC_CTRL_ENABLE = PAUSE_ENABLE || PFC_ENABLE;
parameter TX_USER_WIDTH_INT = MAC_CTRL_ENABLE ? (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + 1 : 0) + 1 : TX_USER_WIDTH;

wire [DATA_WIDTH-1:0]         tx_axis_tdata_int;
wire                          tx_axis_tvalid_int;
wire                          tx_axis_tready_int;
wire                          tx_axis_tlast_int;
wire [TX_USER_WIDTH_INT-1:0]  tx_axis_tuser_int;

wire [DATA_WIDTH-1:0]     rx_axis_tdata_int;
wire                      rx_axis_tvalid_int;
wire                      rx_axis_tlast_int;
wire [RX_USER_WIDTH-1:0]  rx_axis_tuser_int;

axis_gmii_rx #(
    .DATA_WIDTH(DATA_WIDTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .USER_WIDTH(RX_USER_WIDTH)
)
axis_gmii_rx_inst (
    .clk(rx_clk),
    .rst(rx_rst),
    .gmii_rxd(gmii_rxd),
    .gmii_rx_dv(gmii_rx_dv),
    .gmii_rx_er(gmii_rx_er),
    .m_axis_tdata(rx_axis_tdata_int),
    .m_axis_tvalid(rx_axis_tvalid_int),
    .m_axis_tlast(rx_axis_tlast_int),
    .m_axis_tuser(rx_axis_tuser_int),
    .ptp_ts(rx_ptp_ts),
    .clk_enable(rx_clk_enable),
    .mii_select(rx_mii_select),
    .cfg_rx_enable(cfg_rx_enable),
    .start_packet(rx_start_packet),
    .error_bad_frame(rx_error_bad_frame),
    .error_bad_fcs(rx_error_bad_fcs)
);

axis_gmii_tx #(
    .DATA_WIDTH(DATA_WIDTH),
    .ENABLE_PADDING(ENABLE_PADDING),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .PTP_TS_CTRL_IN_TUSER(MAC_CTRL_ENABLE ? PTP_TS_ENABLE : TX_PTP_TS_CTRL_IN_TUSER),
    .PTP_TAG_ENABLE(TX_PTP_TAG_ENABLE),
    .PTP_TAG_WIDTH(TX_PTP_TAG_WIDTH),
    .USER_WIDTH(TX_USER_WIDTH_INT)
)
axis_gmii_tx_inst (
    .clk(tx_clk),
    .rst(tx_rst),
    .s_axis_tdata(tx_axis_tdata_int),
    .s_axis_tvalid(tx_axis_tvalid_int),
    .s_axis_tready(tx_axis_tready_int),
    .s_axis_tlast(tx_axis_tlast_int),
    .s_axis_tuser(tx_axis_tuser_int),
    .gmii_txd(gmii_txd),
    .gmii_tx_en(gmii_tx_en),
    .gmii_tx_er(gmii_tx_er),
    .ptp_ts(tx_ptp_ts),
    .m_axis_ptp_ts(tx_axis_ptp_ts),
    .m_axis_ptp_ts_tag(tx_axis_ptp_ts_tag),
    .m_axis_ptp_ts_valid(tx_axis_ptp_ts_valid),
    .clk_enable(tx_clk_enable),
    .mii_select(tx_mii_select),
    .cfg_ifg(cfg_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .start_packet(tx_start_packet),
    .error_underflow(tx_error_underflow)
);

generate

if (MAC_CTRL_ENABLE) begin : mac_ctrl

    localparam MCF_PARAMS_SIZE = PFC_ENABLE ? 18 : 2;

    wire                          tx_mcf_valid;
    wire                          tx_mcf_ready;
    wire [47:0]                   tx_mcf_eth_dst;
    wire [47:0]                   tx_mcf_eth_src;
    wire [15:0]                   tx_mcf_eth_type;
    wire [15:0]                   tx_mcf_opcode;
    wire [MCF_PARAMS_SIZE*8-1:0]  tx_mcf_params;

    wire                          rx_mcf_valid;
    wire [47:0]                   rx_mcf_eth_dst;
    wire [47:0]                   rx_mcf_eth_src;
    wire [15:0]                   rx_mcf_eth_type;
    wire [15:0]                   rx_mcf_opcode;
    wire [MCF_PARAMS_SIZE*8-1:0]  rx_mcf_params;

    // terminate LFC pause requests from RX internally on TX side
    wire                          tx_pause_req_int;
    wire                          rx_lfc_ack_int;

    reg tx_lfc_req_sync_reg_1 = 1'b0;
    reg tx_lfc_req_sync_reg_2 = 1'b0;
    reg tx_lfc_req_sync_reg_3 = 1'b0;

    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            tx_lfc_req_sync_reg_1 <= 1'b0;
        end else begin
            tx_lfc_req_sync_reg_1 <= rx_lfc_req;
        end
    end

    always @(posedge tx_clk or posedge tx_rst) begin
        if (tx_rst) begin
            tx_lfc_req_sync_reg_2 <= 1'b0;
            tx_lfc_req_sync_reg_3 <= 1'b0;
        end else begin
            tx_lfc_req_sync_reg_2 <= tx_lfc_req_sync_reg_1;
            tx_lfc_req_sync_reg_3 <= tx_lfc_req_sync_reg_2;
        end
    end

    reg rx_lfc_ack_sync_reg_1 = 1'b0;
    reg rx_lfc_ack_sync_reg_2 = 1'b0;
    reg rx_lfc_ack_sync_reg_3 = 1'b0;

    always @(posedge tx_clk or posedge tx_rst) begin
        if (tx_rst) begin
            rx_lfc_ack_sync_reg_1 <= 1'b0;
        end else begin
            rx_lfc_ack_sync_reg_1 <= tx_lfc_pause_en ? tx_pause_ack : 0;
        end
    end

    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            rx_lfc_ack_sync_reg_2 <= 1'b0;
            rx_lfc_ack_sync_reg_3 <= 1'b0;
        end else begin
            rx_lfc_ack_sync_reg_2 <= rx_lfc_ack_sync_reg_1;
            rx_lfc_ack_sync_reg_3 <= rx_lfc_ack_sync_reg_2;
        end
    end

    assign tx_pause_req_int = tx_pause_req || (tx_lfc_pause_en ? tx_lfc_req_sync_reg_3 : 0);

    assign rx_lfc_ack_int = rx_lfc_ack || rx_lfc_ack_sync_reg_3;

    // handle PTP TS enable bit in tuser
    wire [TX_USER_WIDTH_INT-1:0] tx_axis_tuser_in;

    if (PTP_TS_ENABLE && !TX_PTP_TS_CTRL_IN_TUSER) begin
        assign tx_axis_tuser_in = {tx_axis_tuser[TX_USER_WIDTH-1:1], 1'b1, tx_axis_tuser[0]};
    end else begin
        assign tx_axis_tuser_in = tx_axis_tuser;
    end

    mac_ctrl_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(TX_USER_WIDTH_INT),
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE)
    )
    mac_ctrl_tx_inst (
        .clk(tx_clk),
        .rst(tx_rst),

        /*
         * AXI stream input
         */
        .s_axis_tdata(tx_axis_tdata),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(tx_axis_tvalid),
        .s_axis_tready(tx_axis_tready),
        .s_axis_tlast(tx_axis_tlast),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(tx_axis_tuser_in),

        /*
         * AXI stream output
         */
        .m_axis_tdata(tx_axis_tdata_int),
        .m_axis_tkeep(),
        .m_axis_tvalid(tx_axis_tvalid_int),
        .m_axis_tready(tx_axis_tready_int),
        .m_axis_tlast(tx_axis_tlast_int),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(tx_axis_tuser_int),

        /*
         * MAC control frame interface
         */
        .mcf_valid(tx_mcf_valid),
        .mcf_ready(tx_mcf_ready),
        .mcf_eth_dst(tx_mcf_eth_dst),
        .mcf_eth_src(tx_mcf_eth_src),
        .mcf_eth_type(tx_mcf_eth_type),
        .mcf_opcode(tx_mcf_opcode),
        .mcf_params(tx_mcf_params),
        .mcf_id(0),
        .mcf_dest(0),
        .mcf_user(0),

        /*
         * Pause interface
         */
        .tx_pause_req(tx_pause_req_int),
        .tx_pause_ack(tx_pause_ack),

        /*
         * Status
         */
        .stat_tx_mcf(stat_tx_mcf)
    );

    mac_ctrl_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(RX_USER_WIDTH),
        .USE_READY(0),
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE)
    )
    mac_ctrl_rx_inst (
        .clk(rx_clk),
        .rst(rx_rst),

        /*
         * AXI stream input
         */
        .s_axis_tdata(rx_axis_tdata_int),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(rx_axis_tvalid_int),
        .s_axis_tready(),
        .s_axis_tlast(rx_axis_tlast_int),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(rx_axis_tuser_int),

        /*
         * AXI stream output
         */
        .m_axis_tdata(rx_axis_tdata),
        .m_axis_tkeep(),
        .m_axis_tvalid(rx_axis_tvalid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(rx_axis_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(rx_axis_tuser),

        /*
         * MAC control frame interface
         */
        .mcf_valid(rx_mcf_valid),
        .mcf_eth_dst(rx_mcf_eth_dst),
        .mcf_eth_src(rx_mcf_eth_src),
        .mcf_eth_type(rx_mcf_eth_type),
        .mcf_opcode(rx_mcf_opcode),
        .mcf_params(rx_mcf_params),
        .mcf_id(),
        .mcf_dest(),
        .mcf_user(),

        /*
         * Configuration
         */
        .cfg_mcf_rx_eth_dst_mcast(cfg_mcf_rx_eth_dst_mcast),
        .cfg_mcf_rx_check_eth_dst_mcast(cfg_mcf_rx_check_eth_dst_mcast),
        .cfg_mcf_rx_eth_dst_ucast(cfg_mcf_rx_eth_dst_ucast),
        .cfg_mcf_rx_check_eth_dst_ucast(cfg_mcf_rx_check_eth_dst_ucast),
        .cfg_mcf_rx_eth_src(cfg_mcf_rx_eth_src),
        .cfg_mcf_rx_check_eth_src(cfg_mcf_rx_check_eth_src),
        .cfg_mcf_rx_eth_type(cfg_mcf_rx_eth_type),
        .cfg_mcf_rx_opcode_lfc(cfg_mcf_rx_opcode_lfc),
        .cfg_mcf_rx_check_opcode_lfc(cfg_mcf_rx_check_opcode_lfc),
        .cfg_mcf_rx_opcode_pfc(cfg_mcf_rx_opcode_pfc),
        .cfg_mcf_rx_check_opcode_pfc(cfg_mcf_rx_check_opcode_pfc),
        .cfg_mcf_rx_forward(cfg_mcf_rx_forward),
        .cfg_mcf_rx_enable(cfg_mcf_rx_enable),

        /*
         * Status
         */
        .stat_rx_mcf(stat_rx_mcf)
    );

    mac_pause_ctrl_tx #(
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE),
        .PFC_ENABLE(PFC_ENABLE)
    )
    mac_pause_ctrl_tx_inst (
        .clk(tx_clk),
        .rst(tx_rst),

        /*
         * MAC control frame interface
         */
        .mcf_valid(tx_mcf_valid),
        .mcf_ready(tx_mcf_ready),
        .mcf_eth_dst(tx_mcf_eth_dst),
        .mcf_eth_src(tx_mcf_eth_src),
        .mcf_eth_type(tx_mcf_eth_type),
        .mcf_opcode(tx_mcf_opcode),
        .mcf_params(tx_mcf_params),

        /*
         * Pause (IEEE 802.3 annex 31B)
         */
        .tx_lfc_req(tx_lfc_req),
        .tx_lfc_resend(tx_lfc_resend),

        /*
         * Priority Flow Control (PFC) (IEEE 802.3 annex 31D)
         */
        .tx_pfc_req(tx_pfc_req),
        .tx_pfc_resend(tx_pfc_resend),

        /*
         * Configuration
         */
        .cfg_tx_lfc_eth_dst(cfg_tx_lfc_eth_dst),
        .cfg_tx_lfc_eth_src(cfg_tx_lfc_eth_src),
        .cfg_tx_lfc_eth_type(cfg_tx_lfc_eth_type),
        .cfg_tx_lfc_opcode(cfg_tx_lfc_opcode),
        .cfg_tx_lfc_en(cfg_tx_lfc_en),
        .cfg_tx_lfc_quanta(cfg_tx_lfc_quanta),
        .cfg_tx_lfc_refresh(cfg_tx_lfc_refresh),
        .cfg_tx_pfc_eth_dst(cfg_tx_pfc_eth_dst),
        .cfg_tx_pfc_eth_src(cfg_tx_pfc_eth_src),
        .cfg_tx_pfc_eth_type(cfg_tx_pfc_eth_type),
        .cfg_tx_pfc_opcode(cfg_tx_pfc_opcode),
        .cfg_tx_pfc_en(cfg_tx_pfc_en),
        .cfg_tx_pfc_quanta(cfg_tx_pfc_quanta),
        .cfg_tx_pfc_refresh(cfg_tx_pfc_refresh),
        .cfg_quanta_step(tx_mii_select ? (4*256)/512 : (8*256)/512),
        .cfg_quanta_clk_en(tx_clk_enable),

        /*
         * Status
         */
        .stat_tx_lfc_pkt(stat_tx_lfc_pkt),
        .stat_tx_lfc_xon(stat_tx_lfc_xon),
        .stat_tx_lfc_xoff(stat_tx_lfc_xoff),
        .stat_tx_lfc_paused(stat_tx_lfc_paused),
        .stat_tx_pfc_pkt(stat_tx_pfc_pkt),
        .stat_tx_pfc_xon(stat_tx_pfc_xon),
        .stat_tx_pfc_xoff(stat_tx_pfc_xoff),
        .stat_tx_pfc_paused(stat_tx_pfc_paused)
    );

    mac_pause_ctrl_rx #(
        .MCF_PARAMS_SIZE(18),
        .PFC_ENABLE(PFC_ENABLE)
    )
    mac_pause_ctrl_rx_inst (
        .clk(rx_clk),
        .rst(rx_rst),

        /*
         * MAC control frame interface
         */
        .mcf_valid(rx_mcf_valid),
        .mcf_eth_dst(rx_mcf_eth_dst),
        .mcf_eth_src(rx_mcf_eth_src),
        .mcf_eth_type(rx_mcf_eth_type),
        .mcf_opcode(rx_mcf_opcode),
        .mcf_params(rx_mcf_params),

        /*
         * Pause (IEEE 802.3 annex 31B)
         */
        .rx_lfc_en(rx_lfc_en),
        .rx_lfc_req(rx_lfc_req),
        .rx_lfc_ack(rx_lfc_ack_int),

        /*
         * Priority Flow Control (PFC) (IEEE 802.3 annex 31D)
         */
        .rx_pfc_en(rx_pfc_en),
        .rx_pfc_req(rx_pfc_req),
        .rx_pfc_ack(rx_pfc_ack),

        /*
         * Configuration
         */
        .cfg_rx_lfc_opcode(cfg_rx_lfc_opcode),
        .cfg_rx_lfc_en(cfg_rx_lfc_en),
        .cfg_rx_pfc_opcode(cfg_rx_pfc_opcode),
        .cfg_rx_pfc_en(cfg_rx_pfc_en),
        .cfg_quanta_step(rx_mii_select ? (4*256)/512 : (8*256)/512),
        .cfg_quanta_clk_en(rx_clk_enable),

        /*
         * Status
         */
        .stat_rx_lfc_pkt(stat_rx_lfc_pkt),
        .stat_rx_lfc_xon(stat_rx_lfc_xon),
        .stat_rx_lfc_xoff(stat_rx_lfc_xoff),
        .stat_rx_lfc_paused(stat_rx_lfc_paused),
        .stat_rx_pfc_pkt(stat_rx_pfc_pkt),
        .stat_rx_pfc_xon(stat_rx_pfc_xon),
        .stat_rx_pfc_xoff(stat_rx_pfc_xoff),
        .stat_rx_pfc_paused(stat_rx_pfc_paused)
    );

end else begin

    assign tx_axis_tdata_int = tx_axis_tdata;
    assign tx_axis_tvalid_int = tx_axis_tvalid;
    assign tx_axis_tready = tx_axis_tready_int;
    assign tx_axis_tlast_int = tx_axis_tlast;
    assign tx_axis_tuser_int = tx_axis_tuser;

    assign rx_axis_tdata = rx_axis_tdata_int;
    assign rx_axis_tvalid = rx_axis_tvalid_int;
    assign rx_axis_tlast = rx_axis_tlast_int;
    assign rx_axis_tuser = rx_axis_tuser_int;

    assign rx_lfc_req = 0;
    assign rx_pfc_req = 0;
    assign tx_pause_ack = 0;

    assign stat_tx_mcf = 0;
    assign stat_rx_mcf = 0;
    assign stat_tx_lfc_pkt = 0;
    assign stat_tx_lfc_xon = 0;
    assign stat_tx_lfc_xoff = 0;
    assign stat_tx_lfc_paused = 0;
    assign stat_tx_pfc_pkt = 0;
    assign stat_tx_pfc_xon = 0;
    assign stat_tx_pfc_xoff = 0;
    assign stat_tx_pfc_paused = 0;
    assign stat_rx_lfc_pkt = 0;
    assign stat_rx_lfc_xon = 0;
    assign stat_rx_lfc_xoff = 0;
    assign stat_rx_lfc_paused = 0;
    assign stat_rx_pfc_pkt = 0;
    assign stat_rx_pfc_xon = 0;
    assign stat_rx_pfc_xoff = 0;
    assign stat_rx_pfc_paused = 0;

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/eth_mac_1g_fifo.v
/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 1G Ethernet MAC with TX and RX FIFOs
 */
module eth_mac_1g_fifo #
(
    parameter AXIS_DATA_WIDTH = 8,
    parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
    parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
    parameter ENABLE_PADDING = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter TX_FIFO_DEPTH = 4096,
    parameter TX_FIFO_RAM_PIPELINE = 1,
    parameter TX_FRAME_FIFO = 1,
    parameter TX_DROP_OVERSIZE_FRAME = TX_FRAME_FIFO,
    parameter TX_DROP_BAD_FRAME = TX_DROP_OVERSIZE_FRAME,
    parameter TX_DROP_WHEN_FULL = 0,
    parameter RX_FIFO_DEPTH = 4096,
    parameter RX_FIFO_RAM_PIPELINE = 1,
    parameter RX_FRAME_FIFO = 1,
    parameter RX_DROP_OVERSIZE_FRAME = RX_FRAME_FIFO,
    parameter RX_DROP_BAD_FRAME = RX_DROP_OVERSIZE_FRAME,
    parameter RX_DROP_WHEN_FULL = RX_DROP_OVERSIZE_FRAME
)
(
    input  wire                       rx_clk,
    input  wire                       rx_rst,
    input  wire                       tx_clk,
    input  wire                       tx_rst,
    input  wire                       logic_clk,
    input  wire                       logic_rst,

    /*
     * AXI input
     */
    input  wire [AXIS_DATA_WIDTH-1:0] tx_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0] tx_axis_tkeep,
    input  wire                       tx_axis_tvalid,
    output wire                       tx_axis_tready,
    input  wire                       tx_axis_tlast,
    input  wire                       tx_axis_tuser,

    /*
     * AXI output
     */
    output wire [AXIS_DATA_WIDTH-1:0] rx_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] rx_axis_tkeep,
    output wire                       rx_axis_tvalid,
    input  wire                       rx_axis_tready,
    output wire                       rx_axis_tlast,
    output wire                       rx_axis_tuser,

    /*
     * GMII interface
     */
    input  wire [7:0]                 gmii_rxd,
    input  wire                       gmii_rx_dv,
    input  wire                       gmii_rx_er,
    output wire [7:0]                 gmii_txd,
    output wire                       gmii_tx_en,
    output wire                       gmii_tx_er,

    /*
     * Control
     */
    input  wire                       rx_clk_enable,
    input  wire                       tx_clk_enable,
    input  wire                       rx_mii_select,
    input  wire                       tx_mii_select,

    /*
     * Status
     */
    output wire                       tx_error_underflow,
    output wire                       tx_fifo_overflow,
    output wire                       tx_fifo_bad_frame,
    output wire                       tx_fifo_good_frame,
    output wire                       rx_error_bad_frame,
    output wire                       rx_error_bad_fcs,
    output wire                       rx_fifo_overflow,
    output wire                       rx_fifo_bad_frame,
    output wire                       rx_fifo_good_frame,

    /*
     * Configuration
     */
    input  wire [7:0]                 cfg_ifg,
    input  wire                       cfg_tx_enable,
    input  wire                       cfg_rx_enable
);

wire [7:0]  tx_fifo_axis_tdata;
wire        tx_fifo_axis_tvalid;
wire        tx_fifo_axis_tready;
wire        tx_fifo_axis_tlast;
wire        tx_fifo_axis_tuser;

wire [7:0]  rx_fifo_axis_tdata;
wire        rx_fifo_axis_tvalid;
wire        rx_fifo_axis_tlast;
wire        rx_fifo_axis_tuser;

// synchronize MAC status signals into logic clock domain
wire tx_error_underflow_int;

reg [0:0] tx_sync_reg_1 = 1'b0;
reg [0:0] tx_sync_reg_2 = 1'b0;
reg [0:0] tx_sync_reg_3 = 1'b0;
reg [0:0] tx_sync_reg_4 = 1'b0;

assign tx_error_underflow = tx_sync_reg_3[0] ^ tx_sync_reg_4[0];

always @(posedge tx_clk or posedge tx_rst) begin
    if (tx_rst) begin
        tx_sync_reg_1 <= 1'b0;
    end else begin
        tx_sync_reg_1 <= tx_sync_reg_1 ^ {tx_error_underflow_int};
    end
end

always @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        tx_sync_reg_2 <= 1'b0;
        tx_sync_reg_3 <= 1'b0;
        tx_sync_reg_4 <= 1'b0;
    end else begin
        tx_sync_reg_2 <= tx_sync_reg_1;
        tx_sync_reg_3 <= tx_sync_reg_2;
        tx_sync_reg_4 <= tx_sync_reg_3;
    end
end

wire rx_error_bad_frame_int;
wire rx_error_bad_fcs_int;

reg [1:0] rx_sync_reg_1 = 2'd0;
reg [1:0] rx_sync_reg_2 = 2'd0;
reg [1:0] rx_sync_reg_3 = 2'd0;
reg [1:0] rx_sync_reg_4 = 2'd0;

assign rx_error_bad_frame = rx_sync_reg_3[0] ^ rx_sync_reg_4[0];
assign rx_error_bad_fcs = rx_sync_reg_3[1] ^ rx_sync_reg_4[1];

always @(posedge rx_clk or posedge rx_rst) begin
    if (rx_rst) begin
        rx_sync_reg_1 <= 2'd0;
    end else begin
        rx_sync_reg_1 <= rx_sync_reg_1 ^ {rx_error_bad_fcs_int, rx_error_bad_frame_int};
    end
end

always @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        rx_sync_reg_2 <= 2'd0;
        rx_sync_reg_3 <= 2'd0;
        rx_sync_reg_4 <= 2'd0;
    end else begin
        rx_sync_reg_2 <= rx_sync_reg_1;
        rx_sync_reg_3 <= rx_sync_reg_2;
        rx_sync_reg_4 <= rx_sync_reg_3;
    end
end

eth_mac_1g #(
    .ENABLE_PADDING(ENABLE_PADDING),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH)
)
eth_mac_1g_inst (
    .tx_clk(tx_clk),
    .tx_rst(tx_rst),
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),
    .tx_axis_tdata(tx_fifo_axis_tdata),
    .tx_axis_tvalid(tx_fifo_axis_tvalid),
    .tx_axis_tready(tx_fifo_axis_tready),
    .tx_axis_tlast(tx_fifo_axis_tlast),
    .tx_axis_tuser(tx_fifo_axis_tuser),
    .rx_axis_tdata(rx_fifo_axis_tdata),
    .rx_axis_tvalid(rx_fifo_axis_tvalid),
    .rx_axis_tlast(rx_fifo_axis_tlast),
    .rx_axis_tuser(rx_fifo_axis_tuser),
    .gmii_rxd(gmii_rxd),
    .gmii_rx_dv(gmii_rx_dv),
    .gmii_rx_er(gmii_rx_er),
    .gmii_txd(gmii_txd),
    .gmii_tx_en(gmii_tx_en),
    .gmii_tx_er(gmii_tx_er),
    .rx_clk_enable(rx_clk_enable),
    .tx_clk_enable(tx_clk_enable),
    .rx_mii_select(rx_mii_select),
    .tx_mii_select(tx_mii_select),
    .tx_error_underflow(tx_error_underflow_int),
    .rx_error_bad_frame(rx_error_bad_frame_int),
    .rx_error_bad_fcs(rx_error_bad_fcs_int),
    .cfg_ifg(cfg_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .cfg_rx_enable(cfg_rx_enable)
);

axis_async_fifo_adapter #(
    .DEPTH(TX_FIFO_DEPTH),
    .S_DATA_WIDTH(AXIS_DATA_WIDTH),
    .S_KEEP_ENABLE(AXIS_KEEP_ENABLE),
    .S_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .M_DATA_WIDTH(8),
    .M_KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(TX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(TX_DROP_WHEN_FULL)
)
tx_fifo (
    // AXI input
    .s_clk(logic_clk),
    .s_rst(logic_rst),
    .s_axis_tdata(tx_axis_tdata),
    .s_axis_tkeep(tx_axis_tkeep),
    .s_axis_tvalid(tx_axis_tvalid),
    .s_axis_tready(tx_axis_tready),
    .s_axis_tlast(tx_axis_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(tx_axis_tuser),
    // AXI output
    .m_clk(tx_clk),
    .m_rst(tx_rst),
    .m_axis_tdata(tx_fifo_axis_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(tx_fifo_axis_tvalid),
    .m_axis_tready(tx_fifo_axis_tready),
    .m_axis_tlast(tx_fifo_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(tx_fifo_axis_tuser),
    // Status
    .s_status_overflow(tx_fifo_overflow),
    .s_status_bad_frame(tx_fifo_bad_frame),
    .s_status_good_frame(tx_fifo_good_frame),
    .m_status_overflow(),
    .m_status_bad_frame(),
    .m_status_good_frame()
);

axis_async_fifo_adapter #(
    .DEPTH(RX_FIFO_DEPTH),
    .S_DATA_WIDTH(8),
    .S_KEEP_ENABLE(0),
    .M_DATA_WIDTH(AXIS_DATA_WIDTH),
    .M_KEEP_ENABLE(AXIS_KEEP_ENABLE),
    .M_KEEP_WIDTH(AXIS_KEEP_WIDTH),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(RX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(RX_DROP_WHEN_FULL)
)
rx_fifo (
    // AXI input
    .s_clk(rx_clk),
    .s_rst(rx_rst),
    .s_axis_tdata(rx_fifo_axis_tdata),
    .s_axis_tkeep(0),
    .s_axis_tvalid(rx_fifo_axis_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(rx_fifo_axis_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(rx_fifo_axis_tuser),
    // AXI output
    .m_clk(logic_clk),
    .m_rst(logic_rst),
    .m_axis_tdata(rx_axis_tdata),
    .m_axis_tkeep(rx_axis_tkeep),
    .m_axis_tvalid(rx_axis_tvalid),
    .m_axis_tready(rx_axis_tready),
    .m_axis_tlast(rx_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(rx_axis_tuser),
    // Status
    .s_status_overflow(),
    .s_status_bad_frame(),
    .s_status_good_frame(),
    .m_status_overflow(rx_fifo_overflow),
    .m_status_bad_frame(rx_fifo_bad_frame),
    .m_status_good_frame(rx_fifo_good_frame)
);

endmodule

`resetall

// Source snapshot: rtl/network/vendor/ip.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IPv4 block, ethernet frame interface
 */
module ip
(
    input  wire        clk,
    input  wire        rst,

    /*
     * Ethernet frame input
     */
    input  wire        s_eth_hdr_valid,
    output wire        s_eth_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [7:0]  s_eth_payload_axis_tdata,
    input  wire        s_eth_payload_axis_tvalid,
    output wire        s_eth_payload_axis_tready,
    input  wire        s_eth_payload_axis_tlast,
    input  wire        s_eth_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire        m_eth_hdr_valid,
    input  wire        m_eth_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [7:0]  m_eth_payload_axis_tdata,
    output wire        m_eth_payload_axis_tvalid,
    input  wire        m_eth_payload_axis_tready,
    output wire        m_eth_payload_axis_tlast,
    output wire        m_eth_payload_axis_tuser,

    /*
     * ARP requests
     */
    output wire        arp_request_valid,
    input  wire        arp_request_ready,
    output wire [31:0] arp_request_ip,
    input  wire        arp_response_valid,
    output wire        arp_response_ready,
    input  wire        arp_response_error,
    input  wire [47:0] arp_response_mac,

    /*
     * IP input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,

    /*
     * IP output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_ip_eth_dest_mac,
    output wire [47:0] m_ip_eth_src_mac,
    output wire [15:0] m_ip_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,

    /*
     * Status
     */
    output wire rx_busy,
    output wire tx_busy,
    output wire rx_error_header_early_termination,
    output wire rx_error_payload_early_termination,
    output wire rx_error_invalid_header,
    output wire rx_error_invalid_checksum,
    output wire tx_error_payload_early_termination,
    output wire tx_error_arp_failed,

    /*
     * Configuration
     */
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip
);

localparam [1:0]
    STATE_IDLE = 2'd0,
    STATE_ARP_QUERY = 2'd1,
    STATE_WAIT_PACKET = 2'd2;

reg [1:0] state_reg = STATE_IDLE, state_next;

reg outgoing_ip_hdr_valid_reg = 1'b0, outgoing_ip_hdr_valid_next;
wire outgoing_ip_hdr_ready;
reg [47:0] outgoing_eth_dest_mac_reg = 48'h000000000000, outgoing_eth_dest_mac_next;
wire outgoing_ip_payload_axis_tready;

/*
 * IP frame processing
 */
ip_eth_rx
ip_eth_rx_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(s_eth_hdr_valid),
    .s_eth_hdr_ready(s_eth_hdr_ready),
    .s_eth_dest_mac(s_eth_dest_mac),
    .s_eth_src_mac(s_eth_src_mac),
    .s_eth_type(s_eth_type),
    .s_eth_payload_axis_tdata(s_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(s_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(s_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(s_eth_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(m_ip_hdr_valid),
    .m_ip_hdr_ready(m_ip_hdr_ready),
    .m_eth_dest_mac(m_ip_eth_dest_mac),
    .m_eth_src_mac(m_ip_eth_src_mac),
    .m_eth_type(m_ip_eth_type),
    .m_ip_version(m_ip_version),
    .m_ip_ihl(m_ip_ihl),
    .m_ip_dscp(m_ip_dscp),
    .m_ip_ecn(m_ip_ecn),
    .m_ip_length(m_ip_length),
    .m_ip_identification(m_ip_identification),
    .m_ip_flags(m_ip_flags),
    .m_ip_fragment_offset(m_ip_fragment_offset),
    .m_ip_ttl(m_ip_ttl),
    .m_ip_protocol(m_ip_protocol),
    .m_ip_header_checksum(m_ip_header_checksum),
    .m_ip_source_ip(m_ip_source_ip),
    .m_ip_dest_ip(m_ip_dest_ip),
    .m_ip_payload_axis_tdata(m_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(m_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(m_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(m_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(m_ip_payload_axis_tuser),
    // Status signals
    .busy(rx_busy),
    .error_header_early_termination(rx_error_header_early_termination),
    .error_payload_early_termination(rx_error_payload_early_termination),
    .error_invalid_header(rx_error_invalid_header),
    .error_invalid_checksum(rx_error_invalid_checksum)
);

ip_eth_tx
ip_eth_tx_inst (
    .clk(clk),
    .rst(rst),
    // IP frame input
    .s_ip_hdr_valid(outgoing_ip_hdr_valid_reg),
    .s_ip_hdr_ready(outgoing_ip_hdr_ready),
    .s_eth_dest_mac(outgoing_eth_dest_mac_reg),
    .s_eth_src_mac(local_mac),
    .s_eth_type(16'h0800),
    .s_ip_dscp(s_ip_dscp),
    .s_ip_ecn(s_ip_ecn),
    .s_ip_length(s_ip_length),
    .s_ip_identification(16'd0),
    .s_ip_flags(3'b010),
    .s_ip_fragment_offset(13'd0),
    .s_ip_ttl(s_ip_ttl),
    .s_ip_protocol(s_ip_protocol),
    .s_ip_source_ip(s_ip_source_ip),
    .s_ip_dest_ip(s_ip_dest_ip),
    .s_ip_payload_axis_tdata(s_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(s_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(outgoing_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(s_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(s_ip_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(m_eth_hdr_valid),
    .m_eth_hdr_ready(m_eth_hdr_ready),
    .m_eth_dest_mac(m_eth_dest_mac),
    .m_eth_src_mac(m_eth_src_mac),
    .m_eth_type(m_eth_type),
    .m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(m_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(m_eth_payload_axis_tuser),
    // Status signals
    .busy(tx_busy),
    .error_payload_early_termination(tx_error_payload_early_termination)
);

reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;

reg arp_request_valid_reg = 1'b0, arp_request_valid_next;

reg arp_response_ready_reg = 1'b0, arp_response_ready_next;

reg drop_packet_reg = 1'b0, drop_packet_next;

assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
assign s_ip_payload_axis_tready = outgoing_ip_payload_axis_tready || drop_packet_reg;

assign arp_request_valid = arp_request_valid_reg;
assign arp_request_ip = s_ip_dest_ip;
assign arp_response_ready = arp_response_ready_reg;

assign tx_error_arp_failed = arp_response_error;

always @* begin
    state_next = STATE_IDLE;

    arp_request_valid_next = arp_request_valid_reg && !arp_request_ready;
    arp_response_ready_next = 1'b0;
    drop_packet_next = 1'b0;

    s_ip_hdr_ready_next = 1'b0;

    outgoing_ip_hdr_valid_next = outgoing_ip_hdr_valid_reg && !outgoing_ip_hdr_ready;
    outgoing_eth_dest_mac_next = outgoing_eth_dest_mac_reg;

    case (state_reg)
        STATE_IDLE: begin
            // wait for outgoing packet
            if (s_ip_hdr_valid) begin
                // initiate ARP request
                arp_request_valid_next = 1'b1;
                arp_response_ready_next = 1'b1;
                state_next = STATE_ARP_QUERY;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_ARP_QUERY: begin
            arp_response_ready_next = 1'b1;

            if (arp_response_valid) begin
                // wait for ARP reponse
                if (arp_response_error) begin
                    // did not get MAC address; drop packet
                    s_ip_hdr_ready_next = 1'b1;
                    drop_packet_next = 1'b1;
                    state_next = STATE_WAIT_PACKET;
                end else begin
                    // got MAC address; send packet
                    s_ip_hdr_ready_next = 1'b1;
                    outgoing_ip_hdr_valid_next = 1'b1;
                    outgoing_eth_dest_mac_next = arp_response_mac;
                    state_next = STATE_WAIT_PACKET;
                end
            end else begin
                state_next = STATE_ARP_QUERY;
            end
        end
        STATE_WAIT_PACKET: begin
            drop_packet_next = drop_packet_reg;

            // wait for packet transfer to complete
            if (s_ip_payload_axis_tlast && s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                state_next = STATE_IDLE;
            end else begin
                state_next = STATE_WAIT_PACKET;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        arp_request_valid_reg <= 1'b0;
        arp_response_ready_reg <= 1'b0;
        drop_packet_reg <= 1'b0;
        s_ip_hdr_ready_reg <= 1'b0;
        outgoing_ip_hdr_valid_reg <= 1'b0;
    end else begin
        state_reg <= state_next;

        arp_request_valid_reg <= arp_request_valid_next;
        arp_response_ready_reg <= arp_response_ready_next;
        drop_packet_reg <= drop_packet_next;

        s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;

        outgoing_ip_hdr_valid_reg <= outgoing_ip_hdr_valid_next;
    end

    outgoing_eth_dest_mac_reg <= outgoing_eth_dest_mac_next;
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/ip_arb_mux.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IP arbitrated multiplexer
 */
module ip_arb_mux #
(
    parameter S_COUNT = 4,
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    // select round robin arbitration
    parameter ARB_TYPE_ROUND_ROBIN = 0,
    // LSB priority selection
    parameter ARB_LSB_HIGH_PRIORITY = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * IP frame inputs
     */
    input  wire [S_COUNT-1:0]            s_ip_hdr_valid,
    output wire [S_COUNT-1:0]            s_ip_hdr_ready,
    input  wire [S_COUNT*48-1:0]         s_eth_dest_mac,
    input  wire [S_COUNT*48-1:0]         s_eth_src_mac,
    input  wire [S_COUNT*16-1:0]         s_eth_type,
    input  wire [S_COUNT*4-1:0]          s_ip_version,
    input  wire [S_COUNT*4-1:0]          s_ip_ihl,
    input  wire [S_COUNT*6-1:0]          s_ip_dscp,
    input  wire [S_COUNT*2-1:0]          s_ip_ecn,
    input  wire [S_COUNT*16-1:0]         s_ip_length,
    input  wire [S_COUNT*16-1:0]         s_ip_identification,
    input  wire [S_COUNT*3-1:0]          s_ip_flags,
    input  wire [S_COUNT*13-1:0]         s_ip_fragment_offset,
    input  wire [S_COUNT*8-1:0]          s_ip_ttl,
    input  wire [S_COUNT*8-1:0]          s_ip_protocol,
    input  wire [S_COUNT*16-1:0]         s_ip_header_checksum,
    input  wire [S_COUNT*32-1:0]         s_ip_source_ip,
    input  wire [S_COUNT*32-1:0]         s_ip_dest_ip,
    input  wire [S_COUNT*DATA_WIDTH-1:0] s_ip_payload_axis_tdata,
    input  wire [S_COUNT*KEEP_WIDTH-1:0] s_ip_payload_axis_tkeep,
    input  wire [S_COUNT-1:0]            s_ip_payload_axis_tvalid,
    output wire [S_COUNT-1:0]            s_ip_payload_axis_tready,
    input  wire [S_COUNT-1:0]            s_ip_payload_axis_tlast,
    input  wire [S_COUNT*ID_WIDTH-1:0]   s_ip_payload_axis_tid,
    input  wire [S_COUNT*DEST_WIDTH-1:0] s_ip_payload_axis_tdest,
    input  wire [S_COUNT*USER_WIDTH-1:0] s_ip_payload_axis_tuser,

    /*
     * IP frame output
     */
    output wire                          m_ip_hdr_valid,
    input  wire                          m_ip_hdr_ready,
    output wire [47:0]                   m_eth_dest_mac,
    output wire [47:0]                   m_eth_src_mac,
    output wire [15:0]                   m_eth_type,
    output wire [3:0]                    m_ip_version,
    output wire [3:0]                    m_ip_ihl,
    output wire [5:0]                    m_ip_dscp,
    output wire [1:0]                    m_ip_ecn,
    output wire [15:0]                   m_ip_length,
    output wire [15:0]                   m_ip_identification,
    output wire [2:0]                    m_ip_flags,
    output wire [12:0]                   m_ip_fragment_offset,
    output wire [7:0]                    m_ip_ttl,
    output wire [7:0]                    m_ip_protocol,
    output wire [15:0]                   m_ip_header_checksum,
    output wire [31:0]                   m_ip_source_ip,
    output wire [31:0]                   m_ip_dest_ip,
    output wire [DATA_WIDTH-1:0]         m_ip_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0]         m_ip_payload_axis_tkeep,
    output wire                          m_ip_payload_axis_tvalid,
    input  wire                          m_ip_payload_axis_tready,
    output wire                          m_ip_payload_axis_tlast,
    output wire [ID_WIDTH-1:0]           m_ip_payload_axis_tid,
    output wire [DEST_WIDTH-1:0]         m_ip_payload_axis_tdest,
    output wire [USER_WIDTH-1:0]         m_ip_payload_axis_tuser
);

parameter CL_S_COUNT = $clog2(S_COUNT);

reg frame_reg = 1'b0, frame_next;

reg [S_COUNT-1:0] s_ip_hdr_ready_reg = {S_COUNT{1'b0}}, s_ip_hdr_ready_next;

reg m_ip_hdr_valid_reg = 1'b0, m_ip_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0, m_eth_dest_mac_next;
reg [47:0] m_eth_src_mac_reg = 48'd0, m_eth_src_mac_next;
reg [15:0] m_eth_type_reg = 16'd0, m_eth_type_next;
reg [3:0]  m_ip_version_reg = 4'd0, m_ip_version_next;
reg [3:0]  m_ip_ihl_reg = 4'd0, m_ip_ihl_next;
reg [5:0]  m_ip_dscp_reg = 6'd0, m_ip_dscp_next;
reg [1:0]  m_ip_ecn_reg = 2'd0, m_ip_ecn_next;
reg [15:0] m_ip_length_reg = 16'd0, m_ip_length_next;
reg [15:0] m_ip_identification_reg = 16'd0, m_ip_identification_next;
reg [2:0]  m_ip_flags_reg = 3'd0, m_ip_flags_next;
reg [12:0] m_ip_fragment_offset_reg = 13'd0, m_ip_fragment_offset_next;
reg [7:0]  m_ip_ttl_reg = 8'd0, m_ip_ttl_next;
reg [7:0]  m_ip_protocol_reg = 8'd0, m_ip_protocol_next;
reg [15:0] m_ip_header_checksum_reg = 16'd0, m_ip_header_checksum_next;
reg [31:0] m_ip_source_ip_reg = 32'd0, m_ip_source_ip_next;
reg [31:0] m_ip_dest_ip_reg = 32'd0, m_ip_dest_ip_next;

wire [S_COUNT-1:0] request;
wire [S_COUNT-1:0] acknowledge;
wire [S_COUNT-1:0] grant;
wire grant_valid;
wire [CL_S_COUNT-1:0] grant_encoded;

// internal datapath
reg  [DATA_WIDTH-1:0] m_ip_payload_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep_int;
reg                   m_ip_payload_axis_tvalid_int;
reg                   m_ip_payload_axis_tready_int_reg = 1'b0;
reg                   m_ip_payload_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_ip_payload_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_ip_payload_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_ip_payload_axis_tuser_int;
wire                  m_ip_payload_axis_tready_int_early;

assign s_ip_hdr_ready = s_ip_hdr_ready_reg;

assign s_ip_payload_axis_tready = (m_ip_payload_axis_tready_int_reg && grant_valid) << grant_encoded;

assign m_ip_hdr_valid = m_ip_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_ip_version = m_ip_version_reg;
assign m_ip_ihl = m_ip_ihl_reg;
assign m_ip_dscp = m_ip_dscp_reg;
assign m_ip_ecn = m_ip_ecn_reg;
assign m_ip_length = m_ip_length_reg;
assign m_ip_identification = m_ip_identification_reg;
assign m_ip_flags = m_ip_flags_reg;
assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
assign m_ip_ttl = m_ip_ttl_reg;
assign m_ip_protocol = m_ip_protocol_reg;
assign m_ip_header_checksum = m_ip_header_checksum_reg;
assign m_ip_source_ip = m_ip_source_ip_reg;
assign m_ip_dest_ip = m_ip_dest_ip_reg;

// mux for incoming packet
wire [DATA_WIDTH-1:0] current_s_tdata  = s_ip_payload_axis_tdata[grant_encoded*DATA_WIDTH +: DATA_WIDTH];
wire [KEEP_WIDTH-1:0] current_s_tkeep  = s_ip_payload_axis_tkeep[grant_encoded*KEEP_WIDTH +: KEEP_WIDTH];
wire                  current_s_tvalid = s_ip_payload_axis_tvalid[grant_encoded];
wire                  current_s_tready = s_ip_payload_axis_tready[grant_encoded];
wire                  current_s_tlast  = s_ip_payload_axis_tlast[grant_encoded];
wire [ID_WIDTH-1:0]   current_s_tid    = s_ip_payload_axis_tid[grant_encoded*ID_WIDTH +: ID_WIDTH];
wire [DEST_WIDTH-1:0] current_s_tdest  = s_ip_payload_axis_tdest[grant_encoded*DEST_WIDTH +: DEST_WIDTH];
wire [USER_WIDTH-1:0] current_s_tuser  = s_ip_payload_axis_tuser[grant_encoded*USER_WIDTH +: USER_WIDTH];

// arbiter instance
arbiter #(
    .PORTS(S_COUNT),
    .ARB_TYPE_ROUND_ROBIN(ARB_TYPE_ROUND_ROBIN),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .ARB_LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
)
arb_inst (
    .clk(clk),
    .rst(rst),
    .request(request),
    .acknowledge(acknowledge),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_encoded(grant_encoded)
);

assign request = s_ip_hdr_valid & ~grant;
assign acknowledge = grant & s_ip_payload_axis_tvalid & s_ip_payload_axis_tready & s_ip_payload_axis_tlast;

always @* begin
    frame_next = frame_reg;

    s_ip_hdr_ready_next = {S_COUNT{1'b0}};

    m_ip_hdr_valid_next = m_ip_hdr_valid_reg && !m_ip_hdr_ready;
    m_eth_dest_mac_next = m_eth_dest_mac_reg;
    m_eth_src_mac_next = m_eth_src_mac_reg;
    m_eth_type_next = m_eth_type_reg;
    m_ip_version_next = m_ip_version_reg;
    m_ip_ihl_next = m_ip_ihl_reg;
    m_ip_dscp_next = m_ip_dscp_reg;
    m_ip_ecn_next = m_ip_ecn_reg;
    m_ip_length_next = m_ip_length_reg;
    m_ip_identification_next = m_ip_identification_reg;
    m_ip_flags_next = m_ip_flags_reg;
    m_ip_fragment_offset_next = m_ip_fragment_offset_reg;
    m_ip_ttl_next = m_ip_ttl_reg;
    m_ip_protocol_next = m_ip_protocol_reg;
    m_ip_header_checksum_next = m_ip_header_checksum_reg;
    m_ip_source_ip_next = m_ip_source_ip_reg;
    m_ip_dest_ip_next = m_ip_dest_ip_reg;

    if (s_ip_payload_axis_tvalid[grant_encoded] && s_ip_payload_axis_tready[grant_encoded]) begin
        // end of frame detection
        if (s_ip_payload_axis_tlast[grant_encoded]) begin
            frame_next = 1'b0;
        end
    end

    if (!frame_reg && grant_valid && (m_ip_hdr_ready || !m_ip_hdr_valid)) begin
        // start of frame
        frame_next = 1'b1;

        s_ip_hdr_ready_next = grant;

        m_ip_hdr_valid_next = 1'b1;
        m_eth_dest_mac_next = s_eth_dest_mac[grant_encoded*48 +: 48];
        m_eth_src_mac_next = s_eth_src_mac[grant_encoded*48 +: 48];
        m_eth_type_next = s_eth_type[grant_encoded*16 +: 16];
        m_ip_version_next = s_ip_version[grant_encoded*4 +: 4];
        m_ip_ihl_next = s_ip_ihl[grant_encoded*4 +: 4];
        m_ip_dscp_next = s_ip_dscp[grant_encoded*6 +: 6];
        m_ip_ecn_next = s_ip_ecn[grant_encoded*2 +: 2];
        m_ip_length_next = s_ip_length[grant_encoded*16 +: 16];
        m_ip_identification_next = s_ip_identification[grant_encoded*16 +: 16];
        m_ip_flags_next = s_ip_flags[grant_encoded*3 +: 3];
        m_ip_fragment_offset_next = s_ip_fragment_offset[grant_encoded*13 +: 13];
        m_ip_ttl_next = s_ip_ttl[grant_encoded*8 +: 8];
        m_ip_protocol_next = s_ip_protocol[grant_encoded*8 +: 8];
        m_ip_header_checksum_next = s_ip_header_checksum[grant_encoded*16 +: 16];
        m_ip_source_ip_next = s_ip_source_ip[grant_encoded*32 +: 32];
        m_ip_dest_ip_next = s_ip_dest_ip[grant_encoded*32 +: 32];
    end

    // pass through selected packet data
    m_ip_payload_axis_tdata_int  = current_s_tdata;
    m_ip_payload_axis_tkeep_int  = current_s_tkeep;
    m_ip_payload_axis_tvalid_int = current_s_tvalid && m_ip_payload_axis_tready_int_reg && grant_valid;
    m_ip_payload_axis_tlast_int  = current_s_tlast;
    m_ip_payload_axis_tid_int    = current_s_tid;
    m_ip_payload_axis_tdest_int  = current_s_tdest;
    m_ip_payload_axis_tuser_int  = current_s_tuser;
end

always @(posedge clk) begin
    frame_reg <= frame_next;

    s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;

    m_ip_hdr_valid_reg <= m_ip_hdr_valid_next;
    m_eth_dest_mac_reg <= m_eth_dest_mac_next;
    m_eth_src_mac_reg <= m_eth_src_mac_next;
    m_eth_type_reg <= m_eth_type_next;
    m_ip_version_reg <= m_ip_version_next;
    m_ip_ihl_reg <= m_ip_ihl_next;
    m_ip_dscp_reg <= m_ip_dscp_next;
    m_ip_ecn_reg <= m_ip_ecn_next;
    m_ip_length_reg <= m_ip_length_next;
    m_ip_identification_reg <= m_ip_identification_next;
    m_ip_flags_reg <= m_ip_flags_next;
    m_ip_fragment_offset_reg <= m_ip_fragment_offset_next;
    m_ip_ttl_reg <= m_ip_ttl_next;
    m_ip_protocol_reg <= m_ip_protocol_next;
    m_ip_header_checksum_reg <= m_ip_header_checksum_next;
    m_ip_source_ip_reg <= m_ip_source_ip_next;
    m_ip_dest_ip_reg <= m_ip_dest_ip_next;

    if (rst) begin
        frame_reg <= 1'b0;
        s_ip_hdr_ready_reg <= {S_COUNT{1'b0}};
        m_ip_hdr_valid_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_ip_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  m_ip_payload_axis_tvalid_reg = 1'b0, m_ip_payload_axis_tvalid_next;
reg                  m_ip_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_ip_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_ip_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_ip_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_ip_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_ip_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  temp_m_ip_payload_axis_tvalid_reg = 1'b0, temp_m_ip_payload_axis_tvalid_next;
reg                  temp_m_ip_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_ip_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_ip_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_ip_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_ip_payload_axis_temp_to_output;

assign m_ip_payload_axis_tdata  = m_ip_payload_axis_tdata_reg;
assign m_ip_payload_axis_tkeep  = KEEP_ENABLE ? m_ip_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_ip_payload_axis_tvalid = m_ip_payload_axis_tvalid_reg;
assign m_ip_payload_axis_tlast  = m_ip_payload_axis_tlast_reg;
assign m_ip_payload_axis_tid    = ID_ENABLE   ? m_ip_payload_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_ip_payload_axis_tdest  = DEST_ENABLE ? m_ip_payload_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_ip_payload_axis_tuser  = USER_ENABLE ? m_ip_payload_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_ip_payload_axis_tready_int_early = m_ip_payload_axis_tready || (!temp_m_ip_payload_axis_tvalid_reg && !m_ip_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_reg;
    temp_m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_ip_payload_axis_temp_to_output = 1'b0;

    if (m_ip_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_ip_payload_axis_tready || !m_ip_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_ip_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;
        temp_m_ip_payload_axis_tvalid_next = 1'b0;
        store_ip_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_ip_payload_axis_tvalid_reg <= m_ip_payload_axis_tvalid_next;
    m_ip_payload_axis_tready_int_reg <= m_ip_payload_axis_tready_int_early;
    temp_m_ip_payload_axis_tvalid_reg <= temp_m_ip_payload_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        m_ip_payload_axis_tkeep_reg <= m_ip_payload_axis_tkeep_int;
        m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        m_ip_payload_axis_tid_reg   <= m_ip_payload_axis_tid_int;
        m_ip_payload_axis_tdest_reg <= m_ip_payload_axis_tdest_int;
        m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end else if (store_ip_payload_axis_temp_to_output) begin
        m_ip_payload_axis_tdata_reg <= temp_m_ip_payload_axis_tdata_reg;
        m_ip_payload_axis_tkeep_reg <= temp_m_ip_payload_axis_tkeep_reg;
        m_ip_payload_axis_tlast_reg <= temp_m_ip_payload_axis_tlast_reg;
        m_ip_payload_axis_tid_reg   <= temp_m_ip_payload_axis_tid_reg;
        m_ip_payload_axis_tdest_reg <= temp_m_ip_payload_axis_tdest_reg;
        m_ip_payload_axis_tuser_reg <= temp_m_ip_payload_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        temp_m_ip_payload_axis_tkeep_reg <= m_ip_payload_axis_tkeep_int;
        temp_m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        temp_m_ip_payload_axis_tid_reg   <= m_ip_payload_axis_tid_int;
        temp_m_ip_payload_axis_tdest_reg <= m_ip_payload_axis_tdest_int;
        temp_m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end

    if (rst) begin
        m_ip_payload_axis_tvalid_reg <= 1'b0;
        m_ip_payload_axis_tready_int_reg <= 1'b0;
        temp_m_ip_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/ip_complete.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IPv4 and ARP block, ethernet frame interface
 */
module ip_complete #(
    parameter ARP_CACHE_ADDR_WIDTH = 9,
    parameter ARP_REQUEST_RETRY_COUNT = 4,
    parameter ARP_REQUEST_RETRY_INTERVAL = 125000000*2,
    parameter ARP_REQUEST_TIMEOUT = 125000000*30
)
(
    input  wire        clk,
    input  wire        rst,

    /*
     * Ethernet frame input
     */
    input  wire        s_eth_hdr_valid,
    output wire        s_eth_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [7:0]  s_eth_payload_axis_tdata,
    input  wire        s_eth_payload_axis_tvalid,
    output wire        s_eth_payload_axis_tready,
    input  wire        s_eth_payload_axis_tlast,
    input  wire        s_eth_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire        m_eth_hdr_valid,
    input  wire        m_eth_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [7:0]  m_eth_payload_axis_tdata,
    output wire        m_eth_payload_axis_tvalid,
    input  wire        m_eth_payload_axis_tready,
    output wire        m_eth_payload_axis_tlast,
    output wire        m_eth_payload_axis_tuser,

    /*
     * IP input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,

    /*
     * IP output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_ip_eth_dest_mac,
    output wire [47:0] m_ip_eth_src_mac,
    output wire [15:0] m_ip_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,

    /*
     * Status
     */
    output wire rx_busy,
    output wire tx_busy,
    output wire rx_error_header_early_termination,
    output wire rx_error_payload_early_termination,
    output wire rx_error_invalid_header,
    output wire rx_error_invalid_checksum,
    output wire tx_error_payload_early_termination,
    output wire tx_error_arp_failed,

    /*
     * Configuration
     */
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,
    input  wire [31:0] gateway_ip,
    input  wire [31:0] subnet_mask,
    input  wire        clear_arp_cache
);

/*

This module integrates the IP and ARP modules for a complete IP stack

*/

wire arp_request_valid;
wire arp_request_ready;
wire [31:0] arp_request_ip;
wire arp_response_valid;
wire arp_response_ready;
wire arp_response_error;
wire [47:0] arp_response_mac;

wire ip_rx_eth_hdr_valid;
wire ip_rx_eth_hdr_ready;
wire [47:0] ip_rx_eth_dest_mac;
wire [47:0] ip_rx_eth_src_mac;
wire [15:0] ip_rx_eth_type;
wire [7:0] ip_rx_eth_payload_axis_tdata;
wire ip_rx_eth_payload_axis_tvalid;
wire ip_rx_eth_payload_axis_tready;
wire ip_rx_eth_payload_axis_tlast;
wire ip_rx_eth_payload_axis_tuser;

wire ip_tx_eth_hdr_valid;
wire ip_tx_eth_hdr_ready;
wire [47:0] ip_tx_eth_dest_mac;
wire [47:0] ip_tx_eth_src_mac;
wire [15:0] ip_tx_eth_type;
wire [7:0] ip_tx_eth_payload_axis_tdata;
wire ip_tx_eth_payload_axis_tvalid;
wire ip_tx_eth_payload_axis_tready;
wire ip_tx_eth_payload_axis_tlast;
wire ip_tx_eth_payload_axis_tuser;

wire arp_rx_eth_hdr_valid;
wire arp_rx_eth_hdr_ready;
wire [47:0] arp_rx_eth_dest_mac;
wire [47:0] arp_rx_eth_src_mac;
wire [15:0] arp_rx_eth_type;
wire [7:0] arp_rx_eth_payload_axis_tdata;
wire arp_rx_eth_payload_axis_tvalid;
wire arp_rx_eth_payload_axis_tready;
wire arp_rx_eth_payload_axis_tlast;
wire arp_rx_eth_payload_axis_tuser;

wire arp_tx_eth_hdr_valid;
wire arp_tx_eth_hdr_ready;
wire [47:0] arp_tx_eth_dest_mac;
wire [47:0] arp_tx_eth_src_mac;
wire [15:0] arp_tx_eth_type;
wire [7:0] arp_tx_eth_payload_axis_tdata;
wire arp_tx_eth_payload_axis_tvalid;
wire arp_tx_eth_payload_axis_tready;
wire arp_tx_eth_payload_axis_tlast;
wire arp_tx_eth_payload_axis_tuser;

/*
 * Input classifier (eth_type)
 */
wire s_select_ip = (s_eth_type == 16'h0800);
wire s_select_arp = (s_eth_type == 16'h0806);
wire s_select_none = !(s_select_ip || s_select_arp);

reg s_select_ip_reg = 1'b0;
reg s_select_arp_reg = 1'b0;
reg s_select_none_reg = 1'b0;

always @(posedge clk) begin
    if (rst) begin
        s_select_ip_reg <= 1'b0;
        s_select_arp_reg <= 1'b0;
        s_select_none_reg <= 1'b0;
    end else begin
        if (s_eth_payload_axis_tvalid) begin
            if ((!s_select_ip_reg && !s_select_arp_reg && !s_select_none_reg) ||
                (s_eth_payload_axis_tvalid && s_eth_payload_axis_tready && s_eth_payload_axis_tlast)) begin
                s_select_ip_reg <= s_select_ip;
                s_select_arp_reg <= s_select_arp;
                s_select_none_reg <= s_select_none;
            end
        end else begin
            s_select_ip_reg <= 1'b0;
            s_select_arp_reg <= 1'b0;
            s_select_none_reg <= 1'b0;
        end
    end
end

assign ip_rx_eth_hdr_valid = s_select_ip && s_eth_hdr_valid;
assign ip_rx_eth_dest_mac = s_eth_dest_mac;
assign ip_rx_eth_src_mac = s_eth_src_mac;
assign ip_rx_eth_type = 16'h0800;
assign ip_rx_eth_payload_axis_tdata = s_eth_payload_axis_tdata;
assign ip_rx_eth_payload_axis_tvalid = s_select_ip_reg && s_eth_payload_axis_tvalid;
assign ip_rx_eth_payload_axis_tlast = s_eth_payload_axis_tlast;
assign ip_rx_eth_payload_axis_tuser = s_eth_payload_axis_tuser;

assign arp_rx_eth_hdr_valid = s_select_arp && s_eth_hdr_valid;
assign arp_rx_eth_dest_mac = s_eth_dest_mac;
assign arp_rx_eth_src_mac = s_eth_src_mac;
assign arp_rx_eth_type = 16'h0806;
assign arp_rx_eth_payload_axis_tdata = s_eth_payload_axis_tdata;
assign arp_rx_eth_payload_axis_tvalid = s_select_arp_reg && s_eth_payload_axis_tvalid;
assign arp_rx_eth_payload_axis_tlast = s_eth_payload_axis_tlast;
assign arp_rx_eth_payload_axis_tuser = s_eth_payload_axis_tuser;

assign s_eth_hdr_ready = (s_select_ip && ip_rx_eth_hdr_ready) ||
                         (s_select_arp && arp_rx_eth_hdr_ready) ||
                         (s_select_none);

assign s_eth_payload_axis_tready = (s_select_ip_reg && ip_rx_eth_payload_axis_tready) ||
                                   (s_select_arp_reg && arp_rx_eth_payload_axis_tready) ||
                                   s_select_none_reg;

/*
 * Output arbiter
 */
eth_arb_mux #(
    .S_COUNT(2),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .ARB_TYPE_ROUND_ROBIN(0),
    .ARB_LSB_HIGH_PRIORITY(1)
)
eth_arb_mux_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame inputs
    .s_eth_hdr_valid({ip_tx_eth_hdr_valid, arp_tx_eth_hdr_valid}),
    .s_eth_hdr_ready({ip_tx_eth_hdr_ready, arp_tx_eth_hdr_ready}),
    .s_eth_dest_mac({ip_tx_eth_dest_mac, arp_tx_eth_dest_mac}),
    .s_eth_src_mac({ip_tx_eth_src_mac, arp_tx_eth_src_mac}),
    .s_eth_type({ip_tx_eth_type, arp_tx_eth_type}),
    .s_eth_payload_axis_tdata({ip_tx_eth_payload_axis_tdata, arp_tx_eth_payload_axis_tdata}),
    .s_eth_payload_axis_tkeep(0),
    .s_eth_payload_axis_tvalid({ip_tx_eth_payload_axis_tvalid, arp_tx_eth_payload_axis_tvalid}),
    .s_eth_payload_axis_tready({ip_tx_eth_payload_axis_tready, arp_tx_eth_payload_axis_tready}),
    .s_eth_payload_axis_tlast({ip_tx_eth_payload_axis_tlast, arp_tx_eth_payload_axis_tlast}),
    .s_eth_payload_axis_tid(0),
    .s_eth_payload_axis_tdest(0),
    .s_eth_payload_axis_tuser({ip_tx_eth_payload_axis_tuser, arp_tx_eth_payload_axis_tuser}),
    // Ethernet frame output
    .m_eth_hdr_valid(m_eth_hdr_valid),
    .m_eth_hdr_ready(m_eth_hdr_ready),
    .m_eth_dest_mac(m_eth_dest_mac),
    .m_eth_src_mac(m_eth_src_mac),
    .m_eth_type(m_eth_type),
    .m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(),
    .m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(m_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
    .m_eth_payload_axis_tid(),
    .m_eth_payload_axis_tdest(),
    .m_eth_payload_axis_tuser(m_eth_payload_axis_tuser)
);

/*
 * IP module
 */
ip
ip_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(ip_rx_eth_hdr_valid),
    .s_eth_hdr_ready(ip_rx_eth_hdr_ready),
    .s_eth_dest_mac(ip_rx_eth_dest_mac),
    .s_eth_src_mac(ip_rx_eth_src_mac),
    .s_eth_type(ip_rx_eth_type),
    .s_eth_payload_axis_tdata(ip_rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(ip_rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(ip_rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(ip_rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(ip_rx_eth_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(ip_tx_eth_hdr_valid),
    .m_eth_hdr_ready(ip_tx_eth_hdr_ready),
    .m_eth_dest_mac(ip_tx_eth_dest_mac),
    .m_eth_src_mac(ip_tx_eth_src_mac),
    .m_eth_type(ip_tx_eth_type),
    .m_eth_payload_axis_tdata(ip_tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(ip_tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(ip_tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(ip_tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(ip_tx_eth_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(m_ip_hdr_valid),
    .m_ip_hdr_ready(m_ip_hdr_ready),
    .m_ip_eth_dest_mac(m_ip_eth_dest_mac),
    .m_ip_eth_src_mac(m_ip_eth_src_mac),
    .m_ip_eth_type(m_ip_eth_type),
    .m_ip_version(m_ip_version),
    .m_ip_ihl(m_ip_ihl),
    .m_ip_dscp(m_ip_dscp),
    .m_ip_ecn(m_ip_ecn),
    .m_ip_length(m_ip_length),
    .m_ip_identification(m_ip_identification),
    .m_ip_flags(m_ip_flags),
    .m_ip_fragment_offset(m_ip_fragment_offset),
    .m_ip_ttl(m_ip_ttl),
    .m_ip_protocol(m_ip_protocol),
    .m_ip_header_checksum(m_ip_header_checksum),
    .m_ip_source_ip(m_ip_source_ip),
    .m_ip_dest_ip(m_ip_dest_ip),
    .m_ip_payload_axis_tdata(m_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(m_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(m_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(m_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(m_ip_payload_axis_tuser),
    // IP frame input
    .s_ip_hdr_valid(s_ip_hdr_valid),
    .s_ip_hdr_ready(s_ip_hdr_ready),
    .s_ip_dscp(s_ip_dscp),
    .s_ip_ecn(s_ip_ecn),
    .s_ip_length(s_ip_length),
    .s_ip_ttl(s_ip_ttl),
    .s_ip_protocol(s_ip_protocol),
    .s_ip_source_ip(s_ip_source_ip),
    .s_ip_dest_ip(s_ip_dest_ip),
    .s_ip_payload_axis_tdata(s_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(s_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(s_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(s_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(s_ip_payload_axis_tuser),
    // ARP requests
    .arp_request_valid(arp_request_valid),
    .arp_request_ready(arp_request_ready),
    .arp_request_ip(arp_request_ip),
    .arp_response_valid(arp_response_valid),
    .arp_response_ready(arp_response_ready),
    .arp_response_error(arp_response_error),
    .arp_response_mac(arp_response_mac),
    // Status
    .rx_busy(rx_busy),
    .tx_busy(tx_busy),
    .rx_error_header_early_termination(rx_error_header_early_termination),
    .rx_error_payload_early_termination(rx_error_payload_early_termination),
    .rx_error_invalid_header(rx_error_invalid_header),
    .rx_error_invalid_checksum(rx_error_invalid_checksum),
    .tx_error_payload_early_termination(tx_error_payload_early_termination),
    .tx_error_arp_failed(tx_error_arp_failed),
    // Configuration
    .local_mac(local_mac),
    .local_ip(local_ip)
);

/*
 * ARP module
 */
arp #(
    .CACHE_ADDR_WIDTH(ARP_CACHE_ADDR_WIDTH),
    .REQUEST_RETRY_COUNT(ARP_REQUEST_RETRY_COUNT),
    .REQUEST_RETRY_INTERVAL(ARP_REQUEST_RETRY_INTERVAL),
    .REQUEST_TIMEOUT(ARP_REQUEST_TIMEOUT)
)
arp_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(arp_rx_eth_hdr_valid),
    .s_eth_hdr_ready(arp_rx_eth_hdr_ready),
    .s_eth_dest_mac(arp_rx_eth_dest_mac),
    .s_eth_src_mac(arp_rx_eth_src_mac),
    .s_eth_type(arp_rx_eth_type),
    .s_eth_payload_axis_tdata(arp_rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(arp_rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(arp_rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(arp_rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(arp_rx_eth_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(arp_tx_eth_hdr_valid),
    .m_eth_hdr_ready(arp_tx_eth_hdr_ready),
    .m_eth_dest_mac(arp_tx_eth_dest_mac),
    .m_eth_src_mac(arp_tx_eth_src_mac),
    .m_eth_type(arp_tx_eth_type),
    .m_eth_payload_axis_tdata(arp_tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(arp_tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(arp_tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(arp_tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(arp_tx_eth_payload_axis_tuser),
    // ARP requests
    .arp_request_valid(arp_request_valid),
    .arp_request_ready(arp_request_ready),
    .arp_request_ip(arp_request_ip),
    .arp_response_valid(arp_response_valid),
    .arp_response_ready(arp_response_ready),
    .arp_response_error(arp_response_error),
    .arp_response_mac(arp_response_mac),
    // Configuration
    .local_mac(local_mac),
    .local_ip(local_ip),
    .gateway_ip(gateway_ip),
    .subnet_mask(subnet_mask),
    .clear_cache(clear_arp_cache)
);

endmodule

`resetall

// Source snapshot: rtl/network/vendor/ip_eth_rx.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IP ethernet frame receiver (Ethernet frame in, IP frame out)
 */
module ip_eth_rx
(
    input  wire        clk,
    input  wire        rst,

    /*
     * Ethernet frame input
     */
    input  wire        s_eth_hdr_valid,
    output wire        s_eth_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [7:0]  s_eth_payload_axis_tdata,
    input  wire        s_eth_payload_axis_tvalid,
    output wire        s_eth_payload_axis_tready,
    input  wire        s_eth_payload_axis_tlast,
    input  wire        s_eth_payload_axis_tuser,

    /*
     * IP frame output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_header_early_termination,
    output wire        error_payload_early_termination,
    output wire        error_invalid_header,
    output wire        error_invalid_checksum
);

/*

IP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets
 payload                     length octets

This module receives an Ethernet frame with header fields in parallel and
payload on an AXI stream interface, decodes and strips the IP header fields,
then produces the header fields in parallel along with the IP payload in a
separate AXI stream.

*/

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_READ_HEADER = 3'd1,
    STATE_READ_PAYLOAD = 3'd2,
    STATE_READ_PAYLOAD_LAST = 3'd3,
    STATE_WAIT_LAST = 3'd4;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg store_eth_hdr;
reg store_ip_version_ihl;
reg store_ip_dscp_ecn;
reg store_ip_length_0;
reg store_ip_length_1;
reg store_ip_identification_0;
reg store_ip_identification_1;
reg store_ip_flags_fragment_offset_0;
reg store_ip_flags_fragment_offset_1;
reg store_ip_ttl;
reg store_ip_protocol;
reg store_ip_header_checksum_0;
reg store_ip_header_checksum_1;
reg store_ip_source_ip_0;
reg store_ip_source_ip_1;
reg store_ip_source_ip_2;
reg store_ip_source_ip_3;
reg store_ip_dest_ip_0;
reg store_ip_dest_ip_1;
reg store_ip_dest_ip_2;
reg store_ip_dest_ip_3;
reg store_last_word;

reg [5:0] hdr_ptr_reg = 6'd0, hdr_ptr_next;
reg [15:0] word_count_reg = 16'd0, word_count_next;

reg [15:0] hdr_sum_reg = 16'd0, hdr_sum_next;

reg [7:0] last_word_data_reg = 8'd0;

reg s_eth_hdr_ready_reg = 1'b0, s_eth_hdr_ready_next;
reg s_eth_payload_axis_tready_reg = 1'b0, s_eth_payload_axis_tready_next;

reg m_ip_hdr_valid_reg = 1'b0, m_ip_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;
reg [3:0] m_ip_version_reg = 4'd0;
reg [3:0] m_ip_ihl_reg = 4'd0;
reg [5:0] m_ip_dscp_reg = 6'd0;
reg [1:0] m_ip_ecn_reg = 2'd0;
reg [15:0] m_ip_length_reg = 16'd0;
reg [15:0] m_ip_identification_reg = 16'd0;
reg [2:0] m_ip_flags_reg = 3'd0;
reg [12:0] m_ip_fragment_offset_reg = 13'd0;
reg [7:0] m_ip_ttl_reg = 8'd0;
reg [7:0] m_ip_protocol_reg = 8'd0;
reg [15:0] m_ip_header_checksum_reg = 16'd0;
reg [31:0] m_ip_source_ip_reg = 32'd0;
reg [31:0] m_ip_dest_ip_reg = 32'd0;

reg busy_reg = 1'b0;
reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;
reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;
reg error_invalid_header_reg = 1'b0, error_invalid_header_next;
reg error_invalid_checksum_reg = 1'b0, error_invalid_checksum_next;

// internal datapath
reg [7:0] m_ip_payload_axis_tdata_int;
reg       m_ip_payload_axis_tvalid_int;
reg       m_ip_payload_axis_tready_int_reg = 1'b0;
reg       m_ip_payload_axis_tlast_int;
reg       m_ip_payload_axis_tuser_int;
wire      m_ip_payload_axis_tready_int_early;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg;
assign s_eth_payload_axis_tready = s_eth_payload_axis_tready_reg;

assign m_ip_hdr_valid = m_ip_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_ip_version = m_ip_version_reg;
assign m_ip_ihl = m_ip_ihl_reg;
assign m_ip_dscp = m_ip_dscp_reg;
assign m_ip_ecn = m_ip_ecn_reg;
assign m_ip_length = m_ip_length_reg;
assign m_ip_identification = m_ip_identification_reg;
assign m_ip_flags = m_ip_flags_reg;
assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
assign m_ip_ttl = m_ip_ttl_reg;
assign m_ip_protocol = m_ip_protocol_reg;
assign m_ip_header_checksum = m_ip_header_checksum_reg;
assign m_ip_source_ip = m_ip_source_ip_reg;
assign m_ip_dest_ip = m_ip_dest_ip_reg;

assign busy = busy_reg;
assign error_header_early_termination = error_header_early_termination_reg;
assign error_payload_early_termination = error_payload_early_termination_reg;
assign error_invalid_header = error_invalid_header_reg;
assign error_invalid_checksum = error_invalid_checksum_reg;

function [15:0] add1c16b;
    input [15:0] a, b;
    reg [16:0] t;
    begin
        t = a+b;
        add1c16b = t[15:0] + t[16];
    end
endfunction

always @* begin
    state_next = STATE_IDLE;

    s_eth_hdr_ready_next = 1'b0;
    s_eth_payload_axis_tready_next = 1'b0;

    store_eth_hdr = 1'b0;
    store_ip_version_ihl = 1'b0;
    store_ip_dscp_ecn = 1'b0;
    store_ip_length_0 = 1'b0;
    store_ip_length_1 = 1'b0;
    store_ip_identification_0 = 1'b0;
    store_ip_identification_1 = 1'b0;
    store_ip_flags_fragment_offset_0 = 1'b0;
    store_ip_flags_fragment_offset_1 = 1'b0;
    store_ip_ttl = 1'b0;
    store_ip_protocol = 1'b0;
    store_ip_header_checksum_0 = 1'b0;
    store_ip_header_checksum_1 = 1'b0;
    store_ip_source_ip_0 = 1'b0;
    store_ip_source_ip_1 = 1'b0;
    store_ip_source_ip_2 = 1'b0;
    store_ip_source_ip_3 = 1'b0;
    store_ip_dest_ip_0 = 1'b0;
    store_ip_dest_ip_1 = 1'b0;
    store_ip_dest_ip_2 = 1'b0;
    store_ip_dest_ip_3 = 1'b0;

    store_last_word = 1'b0;

    hdr_ptr_next = hdr_ptr_reg;
    word_count_next = word_count_reg;

    hdr_sum_next = hdr_sum_reg;

    m_ip_hdr_valid_next = m_ip_hdr_valid_reg && !m_ip_hdr_ready;

    error_header_early_termination_next = 1'b0;
    error_payload_early_termination_next = 1'b0;
    error_invalid_header_next = 1'b0;
    error_invalid_checksum_next = 1'b0;

    m_ip_payload_axis_tdata_int = 8'd0;
    m_ip_payload_axis_tvalid_int = 1'b0;
    m_ip_payload_axis_tlast_int = 1'b0;
    m_ip_payload_axis_tuser_int = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - wait for header
            hdr_ptr_next = 16'd0;
            hdr_sum_next = 16'd0;
            s_eth_hdr_ready_next = !m_ip_hdr_valid_next;

            if (s_eth_hdr_ready && s_eth_hdr_valid) begin
                s_eth_hdr_ready_next = 1'b0;
                s_eth_payload_axis_tready_next = 1'b1;
                store_eth_hdr = 1'b1;
                state_next = STATE_READ_HEADER;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_READ_HEADER: begin
            // read header
            s_eth_payload_axis_tready_next = 1'b1;
            word_count_next = m_ip_length_reg - 5*4;

            if (s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) begin
                // word transfer in - store it
                hdr_ptr_next = hdr_ptr_reg + 6'd1;
                state_next = STATE_READ_HEADER;

                if (hdr_ptr_reg[0]) begin
                    hdr_sum_next = add1c16b(hdr_sum_reg, {8'd0, s_eth_payload_axis_tdata});
                end else begin
                    hdr_sum_next = add1c16b(hdr_sum_reg, {s_eth_payload_axis_tdata, 8'd0});
                end

                case (hdr_ptr_reg)
                    6'h00: store_ip_version_ihl = 1'b1;
                    6'h01: store_ip_dscp_ecn = 1'b1;
                    6'h02: store_ip_length_1 = 1'b1;
                    6'h03: store_ip_length_0 = 1'b1;
                    6'h04: store_ip_identification_1 = 1'b1;
                    6'h05: store_ip_identification_0 = 1'b1;
                    6'h06: store_ip_flags_fragment_offset_1 = 1'b1;
                    6'h07: store_ip_flags_fragment_offset_0 = 1'b1;
                    6'h08: store_ip_ttl = 1'b1;
                    6'h09: store_ip_protocol = 1'b1;
                    6'h0A: store_ip_header_checksum_1 = 1'b1;
                    6'h0B: store_ip_header_checksum_0 = 1'b1;
                    6'h0C: store_ip_source_ip_3 = 1'b1;
                    6'h0D: store_ip_source_ip_2 = 1'b1;
                    6'h0E: store_ip_source_ip_1 = 1'b1;
                    6'h0F: store_ip_source_ip_0 = 1'b1;
                    6'h10: store_ip_dest_ip_3 = 1'b1;
                    6'h11: store_ip_dest_ip_2 = 1'b1;
                    6'h12: store_ip_dest_ip_1 = 1'b1;
                    6'h13: begin
                        store_ip_dest_ip_0 = 1'b1;
                        if (m_ip_version_reg != 4'd4 || m_ip_ihl_reg != 4'd5) begin
                            error_invalid_header_next = 1'b1;
                            state_next = STATE_WAIT_LAST;
                        end else if (hdr_sum_next != 16'hffff) begin
                            error_invalid_checksum_next = 1'b1;
                            state_next = STATE_WAIT_LAST;
                        end else begin
                            m_ip_hdr_valid_next = 1'b1;
                            s_eth_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;
                            state_next = STATE_READ_PAYLOAD;
                        end
                    end
                endcase

                if (s_eth_payload_axis_tlast) begin
                    error_header_early_termination_next = 1'b1;
                    m_ip_hdr_valid_next = 1'b0;
                    s_eth_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_eth_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end

            end else begin
                state_next = STATE_READ_HEADER;
            end
        end
        STATE_READ_PAYLOAD: begin
            // read payload
            s_eth_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;

            m_ip_payload_axis_tdata_int = s_eth_payload_axis_tdata;
            m_ip_payload_axis_tlast_int = s_eth_payload_axis_tlast;
            m_ip_payload_axis_tuser_int = s_eth_payload_axis_tuser;

            if (s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) begin
                // word transfer through
                word_count_next = word_count_reg - 16'd1;
                m_ip_payload_axis_tvalid_int = 1'b1;
                if (s_eth_payload_axis_tlast) begin
                    if (word_count_reg > 16'd1) begin
                        // end of frame, but length does not match
                        m_ip_payload_axis_tuser_int = 1'b1;
                        error_payload_early_termination_next = 1'b1;
                    end
                    s_eth_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_eth_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    if (word_count_reg == 16'd1) begin
                        store_last_word = 1'b1;
                        m_ip_payload_axis_tvalid_int = 1'b0;
                        state_next = STATE_READ_PAYLOAD_LAST;
                    end else begin
                        state_next = STATE_READ_PAYLOAD;
                    end
                end
            end else begin
                state_next = STATE_READ_PAYLOAD;
            end
        end
        STATE_READ_PAYLOAD_LAST: begin
            // read and discard until end of frame
            s_eth_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;

            m_ip_payload_axis_tdata_int = last_word_data_reg;
            m_ip_payload_axis_tlast_int = s_eth_payload_axis_tlast;
            m_ip_payload_axis_tuser_int = s_eth_payload_axis_tuser;

            if (s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) begin
                if (s_eth_payload_axis_tlast) begin
                    s_eth_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_eth_payload_axis_tready_next = 1'b0;
                    m_ip_payload_axis_tvalid_int = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_READ_PAYLOAD_LAST;
                end
            end else begin
                state_next = STATE_READ_PAYLOAD_LAST;
            end
        end
        STATE_WAIT_LAST: begin
            // read and discard until end of frame
            s_eth_payload_axis_tready_next = 1'b1;

            if (s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) begin
                if (s_eth_payload_axis_tlast) begin
                    s_eth_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_eth_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_WAIT_LAST;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_eth_hdr_ready_reg <= 1'b0;
        s_eth_payload_axis_tready_reg <= 1'b0;
        m_ip_hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_header_early_termination_reg <= 1'b0;
        error_payload_early_termination_reg <= 1'b0;
        error_invalid_header_reg <= 1'b0;
        error_invalid_checksum_reg <= 1'b0;
    end else begin
        state_reg <= state_next;

        s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;
        s_eth_payload_axis_tready_reg <= s_eth_payload_axis_tready_next;

        m_ip_hdr_valid_reg <= m_ip_hdr_valid_next;

        error_header_early_termination_reg <= error_header_early_termination_next;
        error_payload_early_termination_reg <= error_payload_early_termination_next;
        error_invalid_header_reg <= error_invalid_header_next;
        error_invalid_checksum_reg <= error_invalid_checksum_next;

        busy_reg <= state_next != STATE_IDLE;
    end

    hdr_ptr_reg <= hdr_ptr_next;
    word_count_reg <= word_count_next;

    hdr_sum_reg <= hdr_sum_next;

    // datapath
    if (store_eth_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
    end

    if (store_last_word) begin
        last_word_data_reg <= m_ip_payload_axis_tdata_int;
    end

    if (store_ip_version_ihl) {m_ip_version_reg, m_ip_ihl_reg} <= s_eth_payload_axis_tdata;
    if (store_ip_dscp_ecn) {m_ip_dscp_reg, m_ip_ecn_reg} <= s_eth_payload_axis_tdata;
    if (store_ip_length_0) m_ip_length_reg[ 7: 0] <= s_eth_payload_axis_tdata;
    if (store_ip_length_1) m_ip_length_reg[15: 8] <= s_eth_payload_axis_tdata;
    if (store_ip_identification_0) m_ip_identification_reg[ 7: 0] <= s_eth_payload_axis_tdata;
    if (store_ip_identification_1) m_ip_identification_reg[15: 8] <= s_eth_payload_axis_tdata;
    if (store_ip_flags_fragment_offset_0) m_ip_fragment_offset_reg[ 7:0] <= s_eth_payload_axis_tdata;
    if (store_ip_flags_fragment_offset_1) {m_ip_flags_reg, m_ip_fragment_offset_reg[12:8]} <= s_eth_payload_axis_tdata;
    if (store_ip_ttl) m_ip_ttl_reg <= s_eth_payload_axis_tdata;
    if (store_ip_protocol) m_ip_protocol_reg <= s_eth_payload_axis_tdata;
    if (store_ip_header_checksum_0) m_ip_header_checksum_reg[ 7: 0] <= s_eth_payload_axis_tdata;
    if (store_ip_header_checksum_1) m_ip_header_checksum_reg[15: 8] <= s_eth_payload_axis_tdata;
    if (store_ip_source_ip_0) m_ip_source_ip_reg[ 7: 0] <= s_eth_payload_axis_tdata;
    if (store_ip_source_ip_1) m_ip_source_ip_reg[15: 8] <= s_eth_payload_axis_tdata;
    if (store_ip_source_ip_2) m_ip_source_ip_reg[23:16] <= s_eth_payload_axis_tdata;
    if (store_ip_source_ip_3) m_ip_source_ip_reg[31:24] <= s_eth_payload_axis_tdata;
    if (store_ip_dest_ip_0) m_ip_dest_ip_reg[ 7: 0] <= s_eth_payload_axis_tdata;
    if (store_ip_dest_ip_1) m_ip_dest_ip_reg[15: 8] <= s_eth_payload_axis_tdata;
    if (store_ip_dest_ip_2) m_ip_dest_ip_reg[23:16] <= s_eth_payload_axis_tdata;
    if (store_ip_dest_ip_3) m_ip_dest_ip_reg[31:24] <= s_eth_payload_axis_tdata;
end

// output datapath logic
reg [7:0] m_ip_payload_axis_tdata_reg = 8'd0;
reg       m_ip_payload_axis_tvalid_reg = 1'b0, m_ip_payload_axis_tvalid_next;
reg       m_ip_payload_axis_tlast_reg = 1'b0;
reg       m_ip_payload_axis_tuser_reg = 1'b0;

reg [7:0] temp_m_ip_payload_axis_tdata_reg = 8'd0;
reg       temp_m_ip_payload_axis_tvalid_reg = 1'b0, temp_m_ip_payload_axis_tvalid_next;
reg       temp_m_ip_payload_axis_tlast_reg = 1'b0;
reg       temp_m_ip_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_ip_payload_int_to_output;
reg store_ip_payload_int_to_temp;
reg store_ip_payload_axis_temp_to_output;

assign m_ip_payload_axis_tdata = m_ip_payload_axis_tdata_reg;
assign m_ip_payload_axis_tvalid = m_ip_payload_axis_tvalid_reg;
assign m_ip_payload_axis_tlast = m_ip_payload_axis_tlast_reg;
assign m_ip_payload_axis_tuser = m_ip_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_ip_payload_axis_tready_int_early = m_ip_payload_axis_tready || (!temp_m_ip_payload_axis_tvalid_reg && !m_ip_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_reg;
    temp_m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;

    store_ip_payload_int_to_output = 1'b0;
    store_ip_payload_int_to_temp = 1'b0;
    store_ip_payload_axis_temp_to_output = 1'b0;
    
    if (m_ip_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_ip_payload_axis_tready || !m_ip_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_temp = 1'b1;
        end
    end else if (m_ip_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;
        temp_m_ip_payload_axis_tvalid_next = 1'b0;
        store_ip_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_ip_payload_axis_tvalid_reg <= m_ip_payload_axis_tvalid_next;
    m_ip_payload_axis_tready_int_reg <= m_ip_payload_axis_tready_int_early;
    temp_m_ip_payload_axis_tvalid_reg <= temp_m_ip_payload_axis_tvalid_next;

    // datapath
    if (store_ip_payload_int_to_output) begin
        m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end else if (store_ip_payload_axis_temp_to_output) begin
        m_ip_payload_axis_tdata_reg <= temp_m_ip_payload_axis_tdata_reg;
        m_ip_payload_axis_tlast_reg <= temp_m_ip_payload_axis_tlast_reg;
        m_ip_payload_axis_tuser_reg <= temp_m_ip_payload_axis_tuser_reg;
    end

    if (store_ip_payload_int_to_temp) begin
        temp_m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        temp_m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        temp_m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end

    if (rst) begin
        m_ip_payload_axis_tvalid_reg <= 1'b0;
        m_ip_payload_axis_tready_int_reg <= 1'b0;
        temp_m_ip_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/ip_eth_tx.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IP ethernet frame transmitter (IP frame in, Ethernet frame out)
 */
module ip_eth_tx
(
    input  wire        clk,
    input  wire        rst,

    /*
     * IP frame input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire        m_eth_hdr_valid,
    input  wire        m_eth_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [7:0]  m_eth_payload_axis_tdata,
    output wire        m_eth_payload_axis_tvalid,
    input  wire        m_eth_payload_axis_tready,
    output wire        m_eth_payload_axis_tlast,
    output wire        m_eth_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_payload_early_termination
);

/*

IP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets
 payload                     length octets

This module receives an IP frame with header fields in parallel along with the
payload in an AXI stream, combines the header with the payload, passes through
the Ethernet headers, and transmits the complete Ethernet payload on an AXI
interface.

*/

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_WRITE_HEADER = 3'd1,
    STATE_WRITE_PAYLOAD = 3'd2,
    STATE_WRITE_PAYLOAD_LAST = 3'd3,
    STATE_WAIT_LAST = 3'd4;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg store_ip_hdr;
reg store_last_word;

reg [5:0] hdr_ptr_reg = 6'd0, hdr_ptr_next;
reg [15:0] word_count_reg = 16'd0, word_count_next;

reg [15:0] hdr_sum_reg = 16'd0, hdr_sum_next;

reg [7:0] last_word_data_reg = 8'd0;

reg [5:0] ip_dscp_reg = 6'd0;
reg [1:0] ip_ecn_reg = 2'd0;
reg [15:0] ip_length_reg = 16'd0;
reg [15:0] ip_identification_reg = 16'd0;
reg [2:0] ip_flags_reg = 3'd0;
reg [12:0] ip_fragment_offset_reg = 13'd0;
reg [7:0] ip_ttl_reg = 8'd0;
reg [7:0] ip_protocol_reg = 8'd0;
reg [31:0] ip_source_ip_reg = 32'd0;
reg [31:0] ip_dest_ip_reg = 32'd0;

reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;
reg s_ip_payload_axis_tready_reg = 1'b0, s_ip_payload_axis_tready_next;

reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;

reg busy_reg = 1'b0;
reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

// internal datapath
reg [7:0] m_eth_payload_axis_tdata_int;
reg       m_eth_payload_axis_tvalid_int;
reg       m_eth_payload_axis_tready_int_reg = 1'b0;
reg       m_eth_payload_axis_tlast_int;
reg       m_eth_payload_axis_tuser_int;
wire      m_eth_payload_axis_tready_int_early;

assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
assign s_ip_payload_axis_tready = s_ip_payload_axis_tready_reg;

assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;

assign busy = busy_reg;
assign error_payload_early_termination = error_payload_early_termination_reg;

function [15:0] add1c16b;
    input [15:0] a, b;
    reg [16:0] t;
    begin
        t = a+b;
        add1c16b = t[15:0] + t[16];
    end
endfunction

always @* begin
    state_next = STATE_IDLE;

    s_ip_hdr_ready_next = 1'b0;
    s_ip_payload_axis_tready_next = 1'b0;

    store_ip_hdr = 1'b0;

    store_last_word = 1'b0;

    hdr_ptr_next = hdr_ptr_reg;
    word_count_next = word_count_reg;

    hdr_sum_next = hdr_sum_reg;

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg && !m_eth_hdr_ready;

    error_payload_early_termination_next = 1'b0;

    m_eth_payload_axis_tdata_int = 8'd0;
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int = 1'b0;
    m_eth_payload_axis_tuser_int = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - wait for data
            hdr_ptr_next = 6'd0;
            s_ip_hdr_ready_next = !m_eth_hdr_valid_next;

            if (s_ip_hdr_ready && s_ip_hdr_valid) begin
                store_ip_hdr = 1'b1;
                s_ip_hdr_ready_next = 1'b0;
                m_eth_hdr_valid_next = 1'b1;
                if (m_eth_payload_axis_tready_int_reg) begin
                    m_eth_payload_axis_tvalid_int = 1'b1;
                    m_eth_payload_axis_tdata_int = {4'd4, 4'd5}; // ip_version, ip_ihl
                    hdr_ptr_next = 6'd1;
                end
                state_next = STATE_WRITE_HEADER;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_WRITE_HEADER: begin
            // write header
            word_count_next = ip_length_reg - 5*4;

            if (m_eth_payload_axis_tready_int_reg) begin
                hdr_ptr_next = hdr_ptr_reg + 6'd1;
                m_eth_payload_axis_tvalid_int = 1;
                state_next = STATE_WRITE_HEADER;
                case (hdr_ptr_reg)
                    6'h00: begin
                        m_eth_payload_axis_tdata_int = {4'd4, 4'd5}; // ip_version, ip_ihl
                    end
                    6'h01: begin
                        m_eth_payload_axis_tdata_int = {ip_dscp_reg, ip_ecn_reg};
                        hdr_sum_next = {4'd4, 4'd5, ip_dscp_reg, ip_ecn_reg};
                    end
                    6'h02: begin
                        m_eth_payload_axis_tdata_int = ip_length_reg[15: 8];
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_length_reg);
                    end
                    6'h03: begin
                        m_eth_payload_axis_tdata_int = ip_length_reg[ 7: 0];
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_identification_reg);
                    end
                    6'h04: begin
                        m_eth_payload_axis_tdata_int = ip_identification_reg[15: 8];
                        hdr_sum_next = add1c16b(hdr_sum_reg, {ip_flags_reg, ip_fragment_offset_reg});
                    end
                    6'h05: begin
                        m_eth_payload_axis_tdata_int = ip_identification_reg[ 7: 0];
                        hdr_sum_next = add1c16b(hdr_sum_reg, {ip_ttl_reg, ip_protocol_reg});
                    end
                    6'h06: begin
                        m_eth_payload_axis_tdata_int = {ip_flags_reg, ip_fragment_offset_reg[12:8]};
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_source_ip_reg[31:16]);
                    end
                    6'h07: begin
                        m_eth_payload_axis_tdata_int = ip_fragment_offset_reg[ 7: 0];
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_source_ip_reg[15:0]);
                    end
                    6'h08: begin
                        m_eth_payload_axis_tdata_int = ip_ttl_reg;
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_dest_ip_reg[31:16]);
                    end
                    6'h09: begin
                        m_eth_payload_axis_tdata_int = ip_protocol_reg;
                        hdr_sum_next = add1c16b(hdr_sum_reg, ip_dest_ip_reg[15:0]);
                    end
                    6'h0A: m_eth_payload_axis_tdata_int = ~hdr_sum_reg[15: 8];
                    6'h0B: m_eth_payload_axis_tdata_int = ~hdr_sum_reg[ 7: 0];
                    6'h0C: m_eth_payload_axis_tdata_int = ip_source_ip_reg[31:24];
                    6'h0D: m_eth_payload_axis_tdata_int = ip_source_ip_reg[23:16];
                    6'h0E: m_eth_payload_axis_tdata_int = ip_source_ip_reg[15: 8];
                    6'h0F: m_eth_payload_axis_tdata_int = ip_source_ip_reg[ 7: 0];
                    6'h10: m_eth_payload_axis_tdata_int = ip_dest_ip_reg[31:24];
                    6'h11: m_eth_payload_axis_tdata_int = ip_dest_ip_reg[23:16];
                    6'h12: m_eth_payload_axis_tdata_int = ip_dest_ip_reg[15: 8];
                    6'h13: begin
                        m_eth_payload_axis_tdata_int = ip_dest_ip_reg[ 7: 0];
                        s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;
                        state_next = STATE_WRITE_PAYLOAD;
                    end
                endcase
            end else begin
                state_next = STATE_WRITE_HEADER;
            end
        end
        STATE_WRITE_PAYLOAD: begin
            // write payload
            s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;

            m_eth_payload_axis_tdata_int = s_ip_payload_axis_tdata;
            m_eth_payload_axis_tlast_int = s_ip_payload_axis_tlast;
            m_eth_payload_axis_tuser_int = s_ip_payload_axis_tuser;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                // word transfer through
                word_count_next = word_count_reg - 6'd1;
                m_eth_payload_axis_tvalid_int = 1'b1;
                if (s_ip_payload_axis_tlast) begin
                    if (word_count_reg != 16'd1) begin
                        // end of frame, but length does not match
                        m_eth_payload_axis_tuser_int = 1'b1;
                        error_payload_early_termination_next = 1'b1;
                    end
                    s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    if (word_count_reg == 16'd1) begin
                        store_last_word = 1'b1;
                        m_eth_payload_axis_tvalid_int = 1'b0;
                        state_next = STATE_WRITE_PAYLOAD_LAST;
                    end else begin
                        state_next = STATE_WRITE_PAYLOAD;
                    end
                end
            end else begin
                state_next = STATE_WRITE_PAYLOAD;
            end
        end
        STATE_WRITE_PAYLOAD_LAST: begin
            // read and discard until end of frame
            s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;

            m_eth_payload_axis_tdata_int = last_word_data_reg;
            m_eth_payload_axis_tlast_int = s_ip_payload_axis_tlast;
            m_eth_payload_axis_tuser_int = s_ip_payload_axis_tuser;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                if (s_ip_payload_axis_tlast) begin
                    s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    m_eth_payload_axis_tvalid_int = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WRITE_PAYLOAD_LAST;
                end
            end else begin
                state_next = STATE_WRITE_PAYLOAD_LAST;
            end
        end
        STATE_WAIT_LAST: begin
            // read and discard until end of frame
            s_ip_payload_axis_tready_next = 1'b1;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                if (s_ip_payload_axis_tlast) begin
                    s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_WAIT_LAST;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_ip_hdr_ready_reg <= 1'b0;
        s_ip_payload_axis_tready_reg <= 1'b0;
        m_eth_hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_payload_early_termination_reg <= 1'b0;
    end else begin
        state_reg <= state_next;

        s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;
        s_ip_payload_axis_tready_reg <= s_ip_payload_axis_tready_next;

        m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;

        busy_reg <= state_next != STATE_IDLE;

        error_payload_early_termination_reg <= error_payload_early_termination_next;
    end

    hdr_ptr_reg <= hdr_ptr_next;
    word_count_reg <= word_count_next;

    hdr_sum_reg <= hdr_sum_next;

    // datapath
    if (store_ip_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
        ip_dscp_reg <= s_ip_dscp;
        ip_ecn_reg <= s_ip_ecn;
        ip_length_reg <= s_ip_length;
        ip_identification_reg <= s_ip_identification;
        ip_flags_reg <= s_ip_flags;
        ip_fragment_offset_reg <= s_ip_fragment_offset;
        ip_ttl_reg <= s_ip_ttl;
        ip_protocol_reg <= s_ip_protocol;
        ip_source_ip_reg <= s_ip_source_ip;
        ip_dest_ip_reg <= s_ip_dest_ip;
    end

    if (store_last_word) begin
        last_word_data_reg <= m_eth_payload_axis_tdata_int;
    end
end

// output datapath logic
reg [7:0] m_eth_payload_axis_tdata_reg = 8'd0;
reg       m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
reg       m_eth_payload_axis_tlast_reg = 1'b0;
reg       m_eth_payload_axis_tuser_reg = 1'b0;

reg [7:0] temp_m_eth_payload_axis_tdata_reg = 8'd0;
reg       temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
reg       temp_m_eth_payload_axis_tlast_reg = 1'b0;
reg       temp_m_eth_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_eth_payload_int_to_output;
reg store_eth_payload_int_to_temp;
reg store_eth_payload_axis_temp_to_output;

assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_eth_payload_int_to_output = 1'b0;
    store_eth_payload_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;
    
    if (m_eth_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
            store_eth_payload_int_to_temp = 1'b1;
        end
    end else if (m_eth_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
        temp_m_eth_payload_axis_tvalid_next = 1'b0;
        store_eth_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_eth_payload_int_to_output) begin
        m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
        m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
        m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
        m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_eth_payload_int_to_temp) begin
        temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
        temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
        temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
        m_eth_payload_axis_tvalid_reg <= 1'b0;
        m_eth_payload_axis_tready_int_reg <= 1'b0;
        temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/lfsr.v
/*

Copyright (c) 2016-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Parametrizable combinatorial parallel LFSR/CRC
 */
module lfsr #
(
    // width of LFSR
    parameter LFSR_WIDTH = 31,
    // LFSR polynomial
    parameter LFSR_POLY = 31'h10000001,
    // LFSR configuration: "GALOIS", "FIBONACCI"
    parameter LFSR_CONFIG = "FIBONACCI",
    // LFSR feed forward enable
    parameter LFSR_FEED_FORWARD = 0,
    // bit-reverse input and output
    parameter REVERSE = 0,
    // width of data input
    parameter DATA_WIDTH = 8,
    // implementation style: "AUTO", "LOOP", "REDUCTION"
    parameter STYLE = "AUTO"
)
(
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire [LFSR_WIDTH-1:0] state_in,
    output wire [DATA_WIDTH-1:0] data_out,
    output wire [LFSR_WIDTH-1:0] state_out
);

/*

Fully parametrizable combinatorial parallel LFSR/CRC module.  Implements an unrolled LFSR
next state computation, shifting DATA_WIDTH bits per pass through the module.  Input data
is XORed with LFSR feedback path, tie data_in to zero if this is not required.

Works in two parts: statically computes a set of bit masks, then uses these bit masks to
select bits for XORing to compute the next state.  

Ports:

data_in

Data bits to be shifted through the LFSR (DATA_WIDTH bits)

state_in

LFSR/CRC current state input (LFSR_WIDTH bits)

data_out

Data bits shifted out of LFSR (DATA_WIDTH bits)

state_out

LFSR/CRC next state output (LFSR_WIDTH bits)

Parameters:

LFSR_WIDTH

Specify width of LFSR/CRC register

LFSR_POLY

Specify the LFSR/CRC polynomial in hex format.  For example, the polynomial

x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1

would be represented as

32'h04c11db7

Note that the largest term (x^32) is suppressed.  This term is generated automatically based
on LFSR_WIDTH.

LFSR_CONFIG

Specify the LFSR configuration, either Fibonacci or Galois.  Fibonacci is generally used
for linear-feedback shift registers (LFSR) for pseudorandom binary sequence (PRBS) generators,
scramblers, and descrambers, while Galois is generally used for cyclic redundancy check
generators and checkers.

Fibonacci style (example for 64b66b scrambler, 0x8000000001)

   DIN (LSB first)
    |
    V
   (+)<---------------------------(+)<-----------------------------.
    |                              ^                               |
    |  .----.  .----.       .----. |  .----.       .----.  .----.  |
    +->|  0 |->|  1 |->...->| 38 |-+->| 39 |->...->| 56 |->| 57 |--'
    |  '----'  '----'       '----'    '----'       '----'  '----'
    V
   DOUT

Galois style (example for CRC16, 0x8005)

    ,-------------------+-------------------------+----------(+)<-- DIN (MSB first)
    |                   |                         |           ^
    |  .----.  .----.   V   .----.       .----.   V   .----.  |
    `->|  0 |->|  1 |->(+)->|  2 |->...->| 14 |->(+)->| 15 |--+---> DOUT
       '----'  '----'       '----'       '----'       '----'

LFSR_FEED_FORWARD

Generate feed forward instead of feed back LFSR.  Enable this for PRBS checking and self-
synchronous descrambling.

Fibonacci feed-forward style (example for 64b66b descrambler, 0x8000000001)

   DIN (LSB first)
    |
    |  .----.  .----.       .----.    .----.       .----.  .----.
    +->|  0 |->|  1 |->...->| 38 |-+->| 39 |->...->| 56 |->| 57 |--.
    |  '----'  '----'       '----' |  '----'       '----'  '----'  |
    |                              V                               |
   (+)<---------------------------(+)------------------------------'
    |
    V
   DOUT

Galois feed-forward style

    ,-------------------+-------------------------+------------+--- DIN (MSB first)
    |                   |                         |            |
    |  .----.  .----.   V   .----.       .----.   V   .----.   V
    `->|  0 |->|  1 |->(+)->|  2 |->...->| 14 |->(+)->| 15 |->(+)-> DOUT
       '----'  '----'       '----'       '----'       '----'

REVERSE

Bit-reverse LFSR input and output.  Shifts MSB first by default, set REVERSE for LSB first.

DATA_WIDTH

Specify width of input and output data bus.  The module will perform one shift per input
data bit, so if the input data bus is not required tie data_in to zero and set DATA_WIDTH
to the required number of shifts per clock cycle.  

STYLE

Specify implementation style.  Can be "AUTO", "LOOP", or "REDUCTION".  When "AUTO"
is selected, implemenation will be "LOOP" or "REDUCTION" based on synthesis translate
directives.  "REDUCTION" and "LOOP" are functionally identical, however they simulate
and synthesize differently.  "REDUCTION" is implemented with a loop over a Verilog
reduction operator.  "LOOP" is implemented as a doubly-nested loop with no reduction
operator.  "REDUCTION" is very fast for simulation in iverilog and synthesizes well in
Quartus but synthesizes poorly in ISE, likely due to large inferred XOR gates causing
problems with the optimizer.  "LOOP" synthesizes will in both ISE and Quartus.  "AUTO"
will default to "REDUCTION" when simulating and "LOOP" for synthesizers that obey
synthesis translate directives.

Settings for common LFSR/CRC implementations:

Name        Configuration           Length  Polynomial      Initial value   Notes
CRC16-IBM   Galois, bit-reverse     16      16'h8005        16'hffff
CRC16-CCITT Galois                  16      16'h1021        16'h1d0f
CRC32       Galois, bit-reverse     32      32'h04c11db7    32'hffffffff    Ethernet FCS; invert final output
CRC32C      Galois, bit-reverse     32      32'h1edc6f41    32'hffffffff    iSCSI, Intel CRC32 instruction; invert final output
PRBS6       Fibonacci               6       6'h21           any
PRBS7       Fibonacci               7       7'h41           any
PRBS9       Fibonacci               9       9'h021          any             ITU V.52
PRBS10      Fibonacci               10      10'h081         any             ITU
PRBS11      Fibonacci               11      11'h201         any             ITU O.152
PRBS15      Fibonacci, inverted     15      15'h4001        any             ITU O.152
PRBS17      Fibonacci               17      17'h04001       any
PRBS20      Fibonacci               20      20'h00009       any             ITU V.57
PRBS23      Fibonacci, inverted     23      23'h040001      any             ITU O.151
PRBS29      Fibonacci, inverted     29      29'h08000001    any
PRBS31      Fibonacci, inverted     31      31'h10000001    any
64b66b      Fibonacci, bit-reverse  58      58'h8000000001  any             10G Ethernet
128b130b    Galois, bit-reverse     23      23'h210125      any             PCIe gen 3

*/

function [LFSR_WIDTH+DATA_WIDTH-1:0] lfsr_mask(input [31:0] index);
    reg [LFSR_WIDTH-1:0] lfsr_mask_state[LFSR_WIDTH-1:0];
    reg [DATA_WIDTH-1:0] lfsr_mask_data[LFSR_WIDTH-1:0];
    reg [LFSR_WIDTH-1:0] output_mask_state[DATA_WIDTH-1:0];
    reg [DATA_WIDTH-1:0] output_mask_data[DATA_WIDTH-1:0];

    reg [LFSR_WIDTH-1:0] state_val;
    reg [DATA_WIDTH-1:0] data_val;

    reg [DATA_WIDTH-1:0] data_mask;

    integer i, j;

    begin
        // init bit masks
        for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
            lfsr_mask_state[i] = 0;
            lfsr_mask_state[i][i] = 1'b1;
            lfsr_mask_data[i] = 0;
        end
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            output_mask_state[i] = 0;
            if (i < LFSR_WIDTH) begin
                output_mask_state[i][i] = 1'b1;
            end
            output_mask_data[i] = 0;
        end

        // simulate shift register
        if (LFSR_CONFIG == "FIBONACCI") begin
            // Fibonacci configuration
            for (data_mask = {1'b1, {DATA_WIDTH-1{1'b0}}}; data_mask != 0; data_mask = data_mask >> 1) begin
                // determine shift in value
                // current value in last FF, XOR with input data bit (MSB first)
                state_val = lfsr_mask_state[LFSR_WIDTH-1];
                data_val = lfsr_mask_data[LFSR_WIDTH-1];
                data_val = data_val ^ data_mask;

                // add XOR inputs from correct indicies
                for (j = 1; j < LFSR_WIDTH; j = j + 1) begin
                    if ((LFSR_POLY >> j) & 1) begin
                        state_val = lfsr_mask_state[j-1] ^ state_val;
                        data_val = lfsr_mask_data[j-1] ^ data_val;
                    end
                end

                // shift
                for (j = LFSR_WIDTH-1; j > 0; j = j - 1) begin
                    lfsr_mask_state[j] = lfsr_mask_state[j-1];
                    lfsr_mask_data[j] = lfsr_mask_data[j-1];
                end
                for (j = DATA_WIDTH-1; j > 0; j = j - 1) begin
                    output_mask_state[j] = output_mask_state[j-1];
                    output_mask_data[j] = output_mask_data[j-1];
                end
                output_mask_state[0] = state_val;
                output_mask_data[0] = data_val;
                if (LFSR_FEED_FORWARD) begin
                    // only shift in new input data
                    state_val = {LFSR_WIDTH{1'b0}};
                    data_val = data_mask;
                end
                lfsr_mask_state[0] = state_val;
                lfsr_mask_data[0] = data_val;
            end
        end else if (LFSR_CONFIG == "GALOIS") begin
            // Galois configuration
            for (data_mask = {1'b1, {DATA_WIDTH-1{1'b0}}}; data_mask != 0; data_mask = data_mask >> 1) begin
                // determine shift in value
                // current value in last FF, XOR with input data bit (MSB first)
                state_val = lfsr_mask_state[LFSR_WIDTH-1];
                data_val = lfsr_mask_data[LFSR_WIDTH-1];
                data_val = data_val ^ data_mask;

                // shift
                for (j = LFSR_WIDTH-1; j > 0; j = j - 1) begin
                    lfsr_mask_state[j] = lfsr_mask_state[j-1];
                    lfsr_mask_data[j] = lfsr_mask_data[j-1];
                end
                for (j = DATA_WIDTH-1; j > 0; j = j - 1) begin
                    output_mask_state[j] = output_mask_state[j-1];
                    output_mask_data[j] = output_mask_data[j-1];
                end
                output_mask_state[0] = state_val;
                output_mask_data[0] = data_val;
                if (LFSR_FEED_FORWARD) begin
                    // only shift in new input data
                    state_val = {LFSR_WIDTH{1'b0}};
                    data_val = data_mask;
                end
                lfsr_mask_state[0] = state_val;
                lfsr_mask_data[0] = data_val;

                // add XOR inputs at correct indicies
                for (j = 1; j < LFSR_WIDTH; j = j + 1) begin
                    if ((LFSR_POLY >> j) & 1) begin
                        lfsr_mask_state[j] = lfsr_mask_state[j] ^ state_val;
                        lfsr_mask_data[j] = lfsr_mask_data[j] ^ data_val;
                    end
                end
            end
        end else begin
            $display("Error: unknown configuration setting!");
            $finish;
        end

        // reverse bits if selected
        if (REVERSE) begin
            if (index < LFSR_WIDTH) begin
                state_val = 0;
                for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                    state_val[i] = lfsr_mask_state[LFSR_WIDTH-index-1][LFSR_WIDTH-i-1];
                end

                data_val = 0;
                for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                    data_val[i] = lfsr_mask_data[LFSR_WIDTH-index-1][DATA_WIDTH-i-1];
                end
            end else begin
                state_val = 0;
                for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                    state_val[i] = output_mask_state[DATA_WIDTH-(index-LFSR_WIDTH)-1][LFSR_WIDTH-i-1];
                end

                data_val = 0;
                for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                    data_val[i] = output_mask_data[DATA_WIDTH-(index-LFSR_WIDTH)-1][DATA_WIDTH-i-1];
                end
            end
        end else begin
            if (index < LFSR_WIDTH) begin
                state_val = lfsr_mask_state[index];
                data_val = lfsr_mask_data[index];
            end else begin
                state_val = output_mask_state[index-LFSR_WIDTH];
                data_val = output_mask_data[index-LFSR_WIDTH];
            end
        end
        lfsr_mask = {data_val, state_val};
    end
endfunction

// synthesis translate_off
`define SIMULATION
// synthesis translate_on

`ifdef SIMULATION
// "AUTO" style is "REDUCTION" for faster simulation
parameter STYLE_INT = (STYLE == "AUTO") ? "REDUCTION" : STYLE;
`else
// "AUTO" style is "LOOP" for better synthesis result
parameter STYLE_INT = (STYLE == "AUTO") ? "LOOP" : STYLE;
`endif

genvar n;

generate

if (STYLE_INT == "REDUCTION") begin

    // use Verilog reduction operator
    // fast in iverilog
    // significantly larger than generated code with ISE (inferred wide XORs may be tripping up optimizer)
    // slightly smaller than generated code with Quartus
    // --> better for simulation

    for (n = 0; n < LFSR_WIDTH; n = n + 1) begin : lfsr_state
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n);
        assign state_out[n] = ^({data_in, state_in} & mask);
    end
    for (n = 0; n < DATA_WIDTH; n = n + 1) begin : lfsr_data
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n+LFSR_WIDTH);
        assign data_out[n] = ^({data_in, state_in} & mask);
    end

end else if (STYLE_INT == "LOOP") begin

    // use nested loops
    // very slow in iverilog
    // slightly smaller than generated code with ISE
    // same size as generated code with Quartus
    // --> better for synthesis

    for (n = 0; n < LFSR_WIDTH; n = n + 1) begin : lfsr_state
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n);

        reg state_reg;

        assign state_out[n] = state_reg;

        integer i;

        always @* begin
            state_reg = 1'b0;
            for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                if (mask[i]) begin
                    state_reg = state_reg ^ state_in[i];
                end
            end
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (mask[i+LFSR_WIDTH]) begin
                    state_reg = state_reg ^ data_in[i];
                end
            end
        end
    end
    for (n = 0; n < DATA_WIDTH; n = n + 1) begin : lfsr_data
        wire [LFSR_WIDTH+DATA_WIDTH-1:0] mask = lfsr_mask(n+LFSR_WIDTH);

        reg data_reg;

        assign data_out[n] = data_reg;

        integer i;

        always @* begin
            data_reg = 1'b0;
            for (i = 0; i < LFSR_WIDTH; i = i + 1) begin
                if (mask[i]) begin
                    data_reg = data_reg ^ state_in[i];
                end
            end
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (mask[i+LFSR_WIDTH]) begin
                    data_reg = data_reg ^ data_in[i];
                end
            end
        end
    end

end else begin

    initial begin
        $display("Error: unknown style setting!");
        $finish;
    end

end

endgenerate

endmodule

`resetall

// Source snapshot: rtl/network/vendor/mac_ctrl_rx.v
/*

Copyright (c) 2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * MAC control receive
 */
module mac_ctrl_rx #
(
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = DATA_WIDTH>8,
    parameter KEEP_WIDTH = DATA_WIDTH/8,
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    parameter USE_READY = 0,
    parameter MCF_PARAMS_SIZE = 18
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * AXI stream input
     */
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]         s_axis_tkeep,
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire                          s_axis_tlast,
    input  wire [ID_WIDTH-1:0]           s_axis_tid,
    input  wire [DEST_WIDTH-1:0]         s_axis_tdest,
    input  wire [USER_WIDTH-1:0]         s_axis_tuser,

    /*
     * AXI stream output
     */
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]         m_axis_tkeep,
    output wire                          m_axis_tvalid,
    input  wire                          m_axis_tready,
    output wire                          m_axis_tlast,
    output wire [ID_WIDTH-1:0]           m_axis_tid,
    output wire [DEST_WIDTH-1:0]         m_axis_tdest,
    output wire [USER_WIDTH-1:0]         m_axis_tuser,

    /*
     * MAC control frame interface
     */
    output wire                          mcf_valid,
    output wire [47:0]                   mcf_eth_dst,
    output wire [47:0]                   mcf_eth_src,
    output wire [15:0]                   mcf_eth_type,
    output wire [15:0]                   mcf_opcode,
    output wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,
    output wire [ID_WIDTH-1:0]           mcf_id,
    output wire [DEST_WIDTH-1:0]         mcf_dest,
    output wire [USER_WIDTH-1:0]         mcf_user,

    /*
     * Configuration
     */
    input  wire [47:0]                   cfg_mcf_rx_eth_dst_mcast,
    input  wire                          cfg_mcf_rx_check_eth_dst_mcast,
    input  wire [47:0]                   cfg_mcf_rx_eth_dst_ucast,
    input  wire                          cfg_mcf_rx_check_eth_dst_ucast,
    input  wire [47:0]                   cfg_mcf_rx_eth_src,
    input  wire                          cfg_mcf_rx_check_eth_src,
    input  wire [15:0]                   cfg_mcf_rx_eth_type,
    input  wire [15:0]                   cfg_mcf_rx_opcode_lfc,
    input  wire                          cfg_mcf_rx_check_opcode_lfc,
    input  wire [15:0]                   cfg_mcf_rx_opcode_pfc,
    input  wire                          cfg_mcf_rx_check_opcode_pfc,
    input  wire                          cfg_mcf_rx_forward,
    input  wire                          cfg_mcf_rx_enable,

    /*
     * Status
     */
    output wire                          stat_rx_mcf
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 60;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// check configuration
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end

    if (MCF_PARAMS_SIZE > 44) begin
        $display("Error: Maximum MCF_PARAMS_SIZE is 44 bytes (instance %m)");
        $finish;
    end
end

/*

MAC control frame

 Field                       Length
 Destination MAC address     6 octets [01:80:C2:00:00:01]
 Source MAC address          6 octets
 Ethertype                   2 octets [0x8808]
 Opcode                      2 octets
 Parameters                  0-44 octets

This module manages the reception of MAC control frames.  Incoming frames are
checked based on the ethertype and (optionally) MAC addresses.  Matching control
frames are marked by setting tuser[0] on the data output and forwarded through
a separate interface for processing.

*/

reg read_mcf_reg = 1'b1, read_mcf_next;
reg mcf_frame_reg = 1'b0, mcf_frame_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

// internal datapath
reg  [DATA_WIDTH-1:0] m_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_axis_tkeep_int;
reg                   m_axis_tvalid_int;
reg                   m_axis_tready_int_reg = 1'b0;
reg                   m_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_axis_tuser_int;
wire                  m_axis_tready_int_early;

reg                          mcf_valid_reg = 0, mcf_valid_next;
reg [47:0]                   mcf_eth_dst_reg = 0, mcf_eth_dst_next;
reg [47:0]                   mcf_eth_src_reg = 0, mcf_eth_src_next;
reg [15:0]                   mcf_eth_type_reg = 0, mcf_eth_type_next;
reg [15:0]                   mcf_opcode_reg = 0, mcf_opcode_next;
reg [MCF_PARAMS_SIZE*8-1:0]  mcf_params_reg = 0, mcf_params_next;
reg [ID_WIDTH-1:0]           mcf_id_reg = 0, mcf_id_next;
reg [DEST_WIDTH-1:0]         mcf_dest_reg = 0, mcf_dest_next;
reg [USER_WIDTH-1:0]         mcf_user_reg = 0, mcf_user_next;

reg stat_rx_mcf_reg = 1'b0, stat_rx_mcf_next;

assign s_axis_tready = s_axis_tready_reg;

assign mcf_valid = mcf_valid_reg;
assign mcf_eth_dst = mcf_eth_dst_reg;
assign mcf_eth_src = mcf_eth_src_reg;
assign mcf_eth_type = mcf_eth_type_reg;
assign mcf_opcode = mcf_opcode_reg;
assign mcf_params = mcf_params_reg;
assign mcf_id = mcf_id_reg;
assign mcf_dest = mcf_dest_reg;
assign mcf_user = mcf_user_reg;

assign stat_rx_mcf = stat_rx_mcf_reg;

wire mcf_eth_dst_mcast_match = mcf_eth_dst_next == cfg_mcf_rx_eth_dst_mcast;
wire mcf_eth_dst_ucast_match = mcf_eth_dst_next == cfg_mcf_rx_eth_dst_ucast;
wire mcf_eth_src_match = mcf_eth_src_next == cfg_mcf_rx_eth_src;
wire mcf_eth_type_match = mcf_eth_type_next == cfg_mcf_rx_eth_type;
wire mcf_opcode_lfc_match = mcf_opcode_next == cfg_mcf_rx_opcode_lfc;
wire mcf_opcode_pfc_match = mcf_opcode_next == cfg_mcf_rx_opcode_pfc;

wire mcf_eth_dst_match = ((mcf_eth_dst_mcast_match && cfg_mcf_rx_check_eth_dst_mcast) ||
    (mcf_eth_dst_ucast_match && cfg_mcf_rx_check_eth_dst_ucast) ||
    (!cfg_mcf_rx_check_eth_dst_mcast && !cfg_mcf_rx_check_eth_dst_ucast));

wire mcf_opcode_match = ((mcf_opcode_lfc_match && cfg_mcf_rx_check_opcode_lfc) ||
    (mcf_opcode_pfc_match && cfg_mcf_rx_check_opcode_pfc) ||
    (!cfg_mcf_rx_check_opcode_lfc && !cfg_mcf_rx_check_opcode_pfc));

wire mcf_match = (mcf_eth_dst_match &&
    (mcf_eth_src_match || !cfg_mcf_rx_check_eth_src) &&
    mcf_eth_type_match && mcf_opcode_match);

integer k;

always @* begin
    read_mcf_next = read_mcf_reg;
    mcf_frame_next = mcf_frame_reg;
    ptr_next = ptr_reg;

    // pass through data
    m_axis_tdata_int = s_axis_tdata;
    m_axis_tkeep_int = s_axis_tkeep;
    m_axis_tvalid_int = s_axis_tvalid;
    m_axis_tlast_int = s_axis_tlast;
    m_axis_tid_int = s_axis_tid;
    m_axis_tdest_int = s_axis_tdest;
    m_axis_tuser_int = s_axis_tuser;

    s_axis_tready_next = m_axis_tready_int_early || !USE_READY;

    mcf_valid_next = 1'b0;
    mcf_eth_dst_next = mcf_eth_dst_reg;
    mcf_eth_src_next = mcf_eth_src_reg;
    mcf_eth_type_next = mcf_eth_type_reg;
    mcf_opcode_next = mcf_opcode_reg;
    mcf_params_next = mcf_params_reg;
    mcf_id_next = mcf_id_reg;
    mcf_dest_next = mcf_dest_reg;
    mcf_user_next = mcf_user_reg;

    stat_rx_mcf_next = 1'b0;

    if ((s_axis_tready || !USE_READY) && s_axis_tvalid) begin
        if (read_mcf_reg) begin
            ptr_next = ptr_reg + 1;

            mcf_id_next = s_axis_tid;
            mcf_dest_next = s_axis_tdest;
            mcf_user_next = s_axis_tuser;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    field = s_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

            `_HEADER_FIELD_(0,  mcf_eth_dst_next[5*8 +: 8])
            `_HEADER_FIELD_(1,  mcf_eth_dst_next[4*8 +: 8])
            `_HEADER_FIELD_(2,  mcf_eth_dst_next[3*8 +: 8])
            `_HEADER_FIELD_(3,  mcf_eth_dst_next[2*8 +: 8])
            `_HEADER_FIELD_(4,  mcf_eth_dst_next[1*8 +: 8])
            `_HEADER_FIELD_(5,  mcf_eth_dst_next[0*8 +: 8])
            `_HEADER_FIELD_(6,  mcf_eth_src_next[5*8 +: 8])
            `_HEADER_FIELD_(7,  mcf_eth_src_next[4*8 +: 8])
            `_HEADER_FIELD_(8,  mcf_eth_src_next[3*8 +: 8])
            `_HEADER_FIELD_(9,  mcf_eth_src_next[2*8 +: 8])
            `_HEADER_FIELD_(10, mcf_eth_src_next[1*8 +: 8])
            `_HEADER_FIELD_(11, mcf_eth_src_next[0*8 +: 8])
            `_HEADER_FIELD_(12, mcf_eth_type_next[1*8 +: 8])
            `_HEADER_FIELD_(13, mcf_eth_type_next[0*8 +: 8])
            `_HEADER_FIELD_(14, mcf_opcode_next[1*8 +: 8])
            `_HEADER_FIELD_(15, mcf_opcode_next[0*8 +: 8])

            if (ptr_reg == 0/BYTE_LANES) begin
                // ensure params field gets cleared
                mcf_params_next = 0;
            end

            for (k = 0; k < MCF_PARAMS_SIZE; k = k + 1) begin
                if (ptr_reg == (16+k)/BYTE_LANES) begin
                    mcf_params_next[k*8 +: 8] = s_axis_tdata[((16+k)%BYTE_LANES)*8 +: 8];
                end
            end

            if (ptr_reg == 15/BYTE_LANES && (!KEEP_ENABLE || s_axis_tkeep[13%BYTE_LANES])) begin
                // record match at end of opcode field
                mcf_frame_next = mcf_match && cfg_mcf_rx_enable;
            end

            if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES) begin
                read_mcf_next = 1'b0;
            end

            `undef _HEADER_FIELD_
        end

        if (s_axis_tlast) begin
            if (s_axis_tuser[0]) begin
                // frame marked invalid
            end else if (mcf_frame_next) begin
                if (!cfg_mcf_rx_forward) begin
                    // mark frame invalid
                    m_axis_tuser_int[0] = 1'b1;
                end
                // transfer out MAC control frame
                mcf_valid_next = 1'b1;
                stat_rx_mcf_next = 1'b1;
            end

            read_mcf_next = 1'b1;
            mcf_frame_next = 1'b0;
            ptr_next = 0;
        end
    end
end

always @(posedge clk) begin
    read_mcf_reg <= read_mcf_next;
    mcf_frame_reg <= mcf_frame_next;
    ptr_reg <= ptr_next;

    s_axis_tready_reg <= s_axis_tready_next;

    mcf_valid_reg <= mcf_valid_next;
    mcf_eth_dst_reg <= mcf_eth_dst_next;
    mcf_eth_src_reg <= mcf_eth_src_next;
    mcf_eth_type_reg <= mcf_eth_type_next;
    mcf_opcode_reg <= mcf_opcode_next;
    mcf_params_reg <= mcf_params_next;
    mcf_id_reg <= mcf_id_next;
    mcf_dest_reg <= mcf_dest_next;
    mcf_user_reg <= mcf_user_next;

    stat_rx_mcf_reg <= stat_rx_mcf_next;

    if (rst) begin
        read_mcf_reg <= 1'b1;
        mcf_frame_reg <= 1'b0;
        ptr_reg <= 0;
        s_axis_tready_reg <= 1'b0;
        mcf_valid_reg <= 1'b0;
        stat_rx_mcf_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
reg                  m_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
reg                  temp_m_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_axis_tdata  = m_axis_tdata_reg;
assign m_axis_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast  = m_axis_tlast_reg;
assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_tready_int_early = m_axis_tready || !USE_READY || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

always @* begin
    // transfer sink ready state to source
    m_axis_tvalid_next = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_tready_int_reg) begin
        // input is ready
        if (m_axis_tready || !USE_READY || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_tready || !USE_READY) begin
        // input is not ready, but output is ready
        m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tready_int_reg <= m_axis_tready_int_early;
    temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_tdata_reg <= m_axis_tdata_int;
        m_axis_tkeep_reg <= m_axis_tkeep_int;
        m_axis_tlast_reg <= m_axis_tlast_int;
        m_axis_tid_reg   <= m_axis_tid_int;
        m_axis_tdest_reg <= m_axis_tdest_int;
        m_axis_tuser_reg <= m_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_tdata_reg <= temp_m_axis_tdata_reg;
        m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
        m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        m_axis_tid_reg   <= temp_m_axis_tid_reg;
        m_axis_tdest_reg <= temp_m_axis_tdest_reg;
        m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_tdata_reg <= m_axis_tdata_int;
        temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
        temp_m_axis_tlast_reg <= m_axis_tlast_int;
        temp_m_axis_tid_reg   <= m_axis_tid_int;
        temp_m_axis_tdest_reg <= m_axis_tdest_int;
        temp_m_axis_tuser_reg <= m_axis_tuser_int;
    end

    if (rst) begin
        m_axis_tvalid_reg <= 1'b0;
        m_axis_tready_int_reg <= 1'b0;
        temp_m_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/mac_ctrl_tx.v
/*

Copyright (c) 2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * MAC control transmit
 */
module mac_ctrl_tx #
(
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = DATA_WIDTH>8,
    parameter KEEP_WIDTH = DATA_WIDTH/8,
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    parameter MCF_PARAMS_SIZE = 18
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * AXI stream input
     */
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]         s_axis_tkeep,
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire                          s_axis_tlast,
    input  wire [ID_WIDTH-1:0]           s_axis_tid,
    input  wire [DEST_WIDTH-1:0]         s_axis_tdest,
    input  wire [USER_WIDTH-1:0]         s_axis_tuser,

    /*
     * AXI stream output
     */
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]         m_axis_tkeep,
    output wire                          m_axis_tvalid,
    input  wire                          m_axis_tready,
    output wire                          m_axis_tlast,
    output wire [ID_WIDTH-1:0]           m_axis_tid,
    output wire [DEST_WIDTH-1:0]         m_axis_tdest,
    output wire [USER_WIDTH-1:0]         m_axis_tuser,

    /*
     * MAC control frame interface
     */
    input  wire                          mcf_valid,
    output wire                          mcf_ready,
    input  wire [47:0]                   mcf_eth_dst,
    input  wire [47:0]                   mcf_eth_src,
    input  wire [15:0]                   mcf_eth_type,
    input  wire [15:0]                   mcf_opcode,
    input  wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,
    input  wire [ID_WIDTH-1:0]           mcf_id,
    input  wire [DEST_WIDTH-1:0]         mcf_dest,
    input  wire [USER_WIDTH-1:0]         mcf_user,

    /*
     * Pause interface
     */
    input  wire                          tx_pause_req,
    output wire                          tx_pause_ack,

    /*
     * Status
     */
    output wire                          stat_tx_mcf
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 60;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// check configuration
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $display("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end

    if (MCF_PARAMS_SIZE > 44) begin
        $display("Error: Maximum MCF_PARAMS_SIZE is 44 bytes (instance %m)");
        $finish;
    end
end

/*

MAC control frame

 Field                       Length
 Destination MAC address     6 octets [01:80:C2:00:00:01]
 Source MAC address          6 octets
 Ethertype                   2 octets [0x8808]
 Opcode                      2 octets
 Parameters                  0-44 octets

This module manages the transmission of MAC control frames.  Control frames
are accepted in parallel, serialized, and merged at a higher priority with
data traffic.

*/

reg send_data_reg = 1'b0, send_data_next;
reg send_mcf_reg = 1'b0, send_mcf_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;
reg mcf_ready_reg = 1'b0, mcf_ready_next;
reg tx_pause_ack_reg = 1'b0, tx_pause_ack_next;
reg stat_tx_mcf_reg = 1'b0, stat_tx_mcf_next;

// internal datapath
reg  [DATA_WIDTH-1:0] m_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_axis_tkeep_int;
reg                   m_axis_tvalid_int;
reg                   m_axis_tready_int_reg = 1'b0;
reg                   m_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_axis_tuser_int;
wire                  m_axis_tready_int_early;

assign s_axis_tready = s_axis_tready_reg;
assign mcf_ready = mcf_ready_reg;
assign tx_pause_ack = tx_pause_ack_reg;
assign stat_tx_mcf = stat_tx_mcf_reg;

integer k;

always @* begin
    send_data_next = send_data_reg;
    send_mcf_next = send_mcf_reg;
    ptr_next = ptr_reg;

    s_axis_tready_next = 1'b0;
    mcf_ready_next = 1'b0;
    tx_pause_ack_next = tx_pause_ack_reg;
    stat_tx_mcf_next = 1'b0;

    m_axis_tdata_int = 0;
    m_axis_tkeep_int = 0;
    m_axis_tvalid_int = 1'b0;
    m_axis_tlast_int = 1'b0;
    m_axis_tid_int = 0;
    m_axis_tdest_int = 0;
    m_axis_tuser_int = 0;

    if (!send_data_reg && !send_mcf_reg) begin
        m_axis_tdata_int = s_axis_tdata;
        m_axis_tkeep_int = s_axis_tkeep;
        m_axis_tvalid_int = 1'b0;
        m_axis_tlast_int = s_axis_tlast;
        m_axis_tid_int = s_axis_tid;
        m_axis_tdest_int = s_axis_tdest;
        m_axis_tuser_int = s_axis_tuser;
        s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;
        tx_pause_ack_next = tx_pause_req;
        if (s_axis_tvalid && s_axis_tready) begin
            s_axis_tready_next = m_axis_tready_int_early;
            tx_pause_ack_next = 1'b0;
            m_axis_tvalid_int = 1'b1;
            if (s_axis_tlast) begin
                s_axis_tready_next = m_axis_tready_int_early && !mcf_valid && !mcf_ready;
                send_data_next = 1'b0;
            end else begin
                send_data_next = 1'b1;
            end
        end else if (mcf_valid) begin
            s_axis_tready_next = 1'b0;
            ptr_next = 0;
            send_mcf_next = 1'b1;
            mcf_ready_next = (CYCLE_COUNT == 1) && m_axis_tready_int_early;
        end
    end

    if (send_data_reg) begin
        m_axis_tdata_int = s_axis_tdata;
        m_axis_tkeep_int = s_axis_tkeep;
        m_axis_tvalid_int = 1'b0;
        m_axis_tlast_int = s_axis_tlast;
        m_axis_tid_int = s_axis_tid;
        m_axis_tdest_int = s_axis_tdest;
        m_axis_tuser_int = s_axis_tuser;
        s_axis_tready_next = m_axis_tready_int_early;
        if (s_axis_tvalid && s_axis_tready) begin
            m_axis_tvalid_int = 1'b1;
            if (s_axis_tlast) begin
                s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;
                send_data_next = 1'b0;
                if (mcf_valid) begin
                    s_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_mcf_next = 1'b1;
                    mcf_ready_next = (CYCLE_COUNT == 1) && m_axis_tready_int_early;
                end
            end else begin
                send_data_next = 1'b1;
            end
        end
    end

    if (send_mcf_reg) begin
        mcf_ready_next = (CYCLE_COUNT == 1 || ptr_reg == CYCLE_COUNT-1) && m_axis_tready_int_early;
        if (m_axis_tready_int_reg) begin
            ptr_next = ptr_reg + 1;

            m_axis_tvalid_int = 1'b1;
            m_axis_tid_int = mcf_id;
            m_axis_tdest_int = mcf_dest;
            m_axis_tuser_int = mcf_user;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end

            `_HEADER_FIELD_(0,  mcf_eth_dst[5*8 +: 8])
            `_HEADER_FIELD_(1,  mcf_eth_dst[4*8 +: 8])
            `_HEADER_FIELD_(2,  mcf_eth_dst[3*8 +: 8])
            `_HEADER_FIELD_(3,  mcf_eth_dst[2*8 +: 8])
            `_HEADER_FIELD_(4,  mcf_eth_dst[1*8 +: 8])
            `_HEADER_FIELD_(5,  mcf_eth_dst[0*8 +: 8])
            `_HEADER_FIELD_(6,  mcf_eth_src[5*8 +: 8])
            `_HEADER_FIELD_(7,  mcf_eth_src[4*8 +: 8])
            `_HEADER_FIELD_(8,  mcf_eth_src[3*8 +: 8])
            `_HEADER_FIELD_(9,  mcf_eth_src[2*8 +: 8])
            `_HEADER_FIELD_(10, mcf_eth_src[1*8 +: 8])
            `_HEADER_FIELD_(11, mcf_eth_src[0*8 +: 8])
            `_HEADER_FIELD_(12, mcf_eth_type[1*8 +: 8])
            `_HEADER_FIELD_(13, mcf_eth_type[0*8 +: 8])
            `_HEADER_FIELD_(14, mcf_opcode[1*8 +: 8])
            `_HEADER_FIELD_(15, mcf_opcode[0*8 +: 8])

            for (k = 0; k < HDR_SIZE-16; k = k + 1) begin
                if (ptr_reg == (16+k)/BYTE_LANES) begin
                    if (k < MCF_PARAMS_SIZE) begin
                        m_axis_tdata_int[((16+k)%BYTE_LANES)*8 +: 8] = mcf_params[k*8 +: 8];
                    end else begin
                        m_axis_tdata_int[((16+k)%BYTE_LANES)*8 +: 8] = 0;
                    end
                    m_axis_tkeep_int[(16+k)%BYTE_LANES] = 1'b1;
                end
            end

            if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES) begin
                s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;
                mcf_ready_next = 1'b0;
                m_axis_tlast_int = 1'b1;
                send_mcf_next = 1'b0;
                stat_tx_mcf_next = 1'b1;
            end else begin
                mcf_ready_next = (ptr_next == CYCLE_COUNT-1) && m_axis_tready_int_early;
            end

            `undef _HEADER_FIELD_
        end
    end
end

always @(posedge clk) begin
    send_data_reg <= send_data_next;
    send_mcf_reg <= send_mcf_next;
    ptr_reg <= ptr_next;

    s_axis_tready_reg <= s_axis_tready_next;
    mcf_ready_reg <= mcf_ready_next;
    tx_pause_ack_reg <= tx_pause_ack_next;
    stat_tx_mcf_reg <= stat_tx_mcf_next;

    if (rst) begin
        send_data_reg <= 1'b0;
        send_mcf_reg <= 1'b0;
        ptr_reg <= 0;
        s_axis_tready_reg <= 1'b0;
        mcf_ready_reg <= 1'b0;
        tx_pause_ack_reg <= 1'b0;
        stat_tx_mcf_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
reg                  m_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
reg                  temp_m_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_axis_tdata  = m_axis_tdata_reg;
assign m_axis_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast  = m_axis_tlast_reg;
assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_tready_int_early = m_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

always @* begin
    // transfer sink ready state to source
    m_axis_tvalid_next = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_tready_int_reg) begin
        // input is ready
        if (m_axis_tready || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_tready) begin
        // input is not ready, but output is ready
        m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tready_int_reg <= m_axis_tready_int_early;
    temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_tdata_reg <= m_axis_tdata_int;
        m_axis_tkeep_reg <= m_axis_tkeep_int;
        m_axis_tlast_reg <= m_axis_tlast_int;
        m_axis_tid_reg   <= m_axis_tid_int;
        m_axis_tdest_reg <= m_axis_tdest_int;
        m_axis_tuser_reg <= m_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_tdata_reg <= temp_m_axis_tdata_reg;
        m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
        m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        m_axis_tid_reg   <= temp_m_axis_tid_reg;
        m_axis_tdest_reg <= temp_m_axis_tdest_reg;
        m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_tdata_reg <= m_axis_tdata_int;
        temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
        temp_m_axis_tlast_reg <= m_axis_tlast_int;
        temp_m_axis_tid_reg   <= m_axis_tid_int;
        temp_m_axis_tdest_reg <= m_axis_tdest_int;
        temp_m_axis_tuser_reg <= m_axis_tuser_int;
    end

    if (rst) begin
        m_axis_tvalid_reg <= 1'b0;
        m_axis_tready_int_reg <= 1'b0;
        temp_m_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/mac_pause_ctrl_rx.v
/*

Copyright (c) 2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * PFC and pause frame receive handling
 */
module mac_pause_ctrl_rx #
(
    parameter MCF_PARAMS_SIZE = 18,
    parameter PFC_ENABLE = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * MAC control frame interface
     */
    input  wire                          mcf_valid,
    input  wire [47:0]                   mcf_eth_dst,
    input  wire [47:0]                   mcf_eth_src,
    input  wire [15:0]                   mcf_eth_type,
    input  wire [15:0]                   mcf_opcode,
    input  wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire                          rx_lfc_en,
    output wire                          rx_lfc_req,
    input  wire                          rx_lfc_ack,

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    input  wire [7:0]                    rx_pfc_en,
    output wire [7:0]                    rx_pfc_req,
    input  wire [7:0]                    rx_pfc_ack,

    /*
     * Configuration
     */
    input  wire [15:0]                   cfg_rx_lfc_opcode,
    input  wire                          cfg_rx_lfc_en,
    input  wire [15:0]                   cfg_rx_pfc_opcode,
    input  wire                          cfg_rx_pfc_en,
    input  wire [9:0]                    cfg_quanta_step,
    input  wire                          cfg_quanta_clk_en,

    /*
     * Status
     */
    output wire                          stat_rx_lfc_pkt,
    output wire                          stat_rx_lfc_xon,
    output wire                          stat_rx_lfc_xoff,
    output wire                          stat_rx_lfc_paused,
    output wire                          stat_rx_pfc_pkt,
    output wire [7:0]                    stat_rx_pfc_xon,
    output wire [7:0]                    stat_rx_pfc_xoff,
    output wire [7:0]                    stat_rx_pfc_paused
);

localparam QFB = 8;

// check configuration
initial begin
    if (MCF_PARAMS_SIZE < (PFC_ENABLE ? 18 : 2)) begin
        $display("Error: MCF_PARAMS_SIZE too small for requested configuration (instance %m)");
        $finish;
    end
end

reg lfc_req_reg = 1'b0, lfc_req_next;
reg [7:0] pfc_req_reg = 8'd0, pfc_req_next;

reg [16+QFB-1:0] lfc_quanta_reg = 0, lfc_quanta_next;
reg [16+QFB-1:0] pfc_quanta_reg[0:7], pfc_quanta_next[0:7];

reg stat_rx_lfc_pkt_reg = 1'b0, stat_rx_lfc_pkt_next;
reg stat_rx_lfc_xon_reg = 1'b0, stat_rx_lfc_xon_next;
reg stat_rx_lfc_xoff_reg = 1'b0, stat_rx_lfc_xoff_next;
reg stat_rx_pfc_pkt_reg = 1'b0, stat_rx_pfc_pkt_next;
reg [7:0] stat_rx_pfc_xon_reg = 0, stat_rx_pfc_xon_next;
reg [7:0] stat_rx_pfc_xoff_reg = 0, stat_rx_pfc_xoff_next;

assign rx_lfc_req = lfc_req_reg;
assign rx_pfc_req = pfc_req_reg;

assign stat_rx_lfc_pkt = stat_rx_lfc_pkt_reg;
assign stat_rx_lfc_xon = stat_rx_lfc_xon_reg;
assign stat_rx_lfc_xoff = stat_rx_lfc_xoff_reg;
assign stat_rx_lfc_paused = lfc_req_reg;
assign stat_rx_pfc_pkt = stat_rx_pfc_pkt_reg;
assign stat_rx_pfc_xon = stat_rx_pfc_xon_reg;
assign stat_rx_pfc_xoff = stat_rx_pfc_xoff_reg;
assign stat_rx_pfc_paused = pfc_req_reg;

integer k;

initial begin
    for (k = 0; k < 8; k = k + 1) begin
        pfc_quanta_reg[k] = 0;
    end
end

always @* begin
    stat_rx_lfc_pkt_next = 1'b0;
    stat_rx_lfc_xon_next = 1'b0;
    stat_rx_lfc_xoff_next = 1'b0;
    stat_rx_pfc_pkt_next = 1'b0;
    stat_rx_pfc_xon_next = 0;
    stat_rx_pfc_xoff_next = 0;

    if (cfg_quanta_clk_en && rx_lfc_ack) begin
        if (lfc_quanta_reg > cfg_quanta_step) begin
            lfc_quanta_next = lfc_quanta_reg - cfg_quanta_step;
        end else begin
            lfc_quanta_next = 0;
        end
    end else begin
        lfc_quanta_next = lfc_quanta_reg;
    end

    lfc_req_next = (lfc_quanta_reg != 0) && rx_lfc_en && cfg_rx_lfc_en;

    for (k = 0; k < 8; k = k + 1) begin
        if (cfg_quanta_clk_en && rx_pfc_ack[k]) begin
            if (pfc_quanta_reg[k] > cfg_quanta_step) begin
                pfc_quanta_next[k] = pfc_quanta_reg[k] - cfg_quanta_step;
            end else begin
                pfc_quanta_next[k] = 0;
            end
        end else begin
            pfc_quanta_next[k] = pfc_quanta_reg[k];
        end

        pfc_req_next[k] = (pfc_quanta_reg[k] != 0) && rx_pfc_en[k] && cfg_rx_pfc_en;
    end

    if (mcf_valid) begin
        if (mcf_opcode == cfg_rx_lfc_opcode && cfg_rx_lfc_en) begin
            stat_rx_lfc_pkt_next = 1'b1;
            stat_rx_lfc_xon_next = {mcf_params[7:0], mcf_params[15:8]} == 0;
            stat_rx_lfc_xoff_next = {mcf_params[7:0], mcf_params[15:8]} != 0;
            lfc_quanta_next = {mcf_params[7:0], mcf_params[15:8], {QFB{1'b0}}};
        end else if (PFC_ENABLE && mcf_opcode == cfg_rx_pfc_opcode && cfg_rx_pfc_en) begin
            stat_rx_pfc_pkt_next = 1'b1;
            for (k = 0; k < 8; k = k + 1) begin
                if (mcf_params[k+8]) begin
                    stat_rx_pfc_xon_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8]} == 0;
                    stat_rx_pfc_xoff_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8]} != 0;
                    pfc_quanta_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8], {QFB{1'b0}}};
                end
            end
        end
    end
end

always @(posedge clk) begin
    lfc_req_reg <= lfc_req_next;
    pfc_req_reg <= pfc_req_next;

    lfc_quanta_reg <= lfc_quanta_next;
    for (k = 0; k < 8; k = k + 1) begin
        pfc_quanta_reg[k] <= pfc_quanta_next[k];
    end

    stat_rx_lfc_pkt_reg <= stat_rx_lfc_pkt_next;
    stat_rx_lfc_xon_reg <= stat_rx_lfc_xon_next;
    stat_rx_lfc_xoff_reg <= stat_rx_lfc_xoff_next;
    stat_rx_pfc_pkt_reg <= stat_rx_pfc_pkt_next;
    stat_rx_pfc_xon_reg <= stat_rx_pfc_xon_next;
    stat_rx_pfc_xoff_reg <= stat_rx_pfc_xoff_next;

    if (rst) begin
        lfc_req_reg <= 1'b0;
        pfc_req_reg <= 8'd0;
        lfc_quanta_reg <= 0;
        for (k = 0; k < 8; k = k + 1) begin
            pfc_quanta_reg[k] <= 0;
        end

        stat_rx_lfc_pkt_reg <= 1'b0;
        stat_rx_lfc_xon_reg <= 1'b0;
        stat_rx_lfc_xoff_reg <= 1'b0;
        stat_rx_pfc_pkt_reg <= 1'b0;
        stat_rx_pfc_xon_reg <= 0;
        stat_rx_pfc_xoff_reg <= 0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/mac_pause_ctrl_tx.v
/*

Copyright (c) 2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * PFC and pause frame transmit handling
 */
module mac_pause_ctrl_tx #
(
    parameter MCF_PARAMS_SIZE = 18,
    parameter PFC_ENABLE = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * MAC control frame interface
     */
    output wire                          mcf_valid,
    input  wire                          mcf_ready,
    output wire [47:0]                   mcf_eth_dst,
    output wire [47:0]                   mcf_eth_src,
    output wire [15:0]                   mcf_eth_type,
    output wire [15:0]                   mcf_opcode,
    output wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire                          tx_lfc_req,
    input  wire                          tx_lfc_resend,

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D)
     */
    input  wire [7:0]                    tx_pfc_req,
    input  wire                          tx_pfc_resend,

    /*
     * Configuration
     */
    input  wire [47:0]                   cfg_tx_lfc_eth_dst,
    input  wire [47:0]                   cfg_tx_lfc_eth_src,
    input  wire [15:0]                   cfg_tx_lfc_eth_type,
    input  wire [15:0]                   cfg_tx_lfc_opcode,
    input  wire                          cfg_tx_lfc_en,
    input  wire [15:0]                   cfg_tx_lfc_quanta,
    input  wire [15:0]                   cfg_tx_lfc_refresh,
    input  wire [47:0]                   cfg_tx_pfc_eth_dst,
    input  wire [47:0]                   cfg_tx_pfc_eth_src,
    input  wire [15:0]                   cfg_tx_pfc_eth_type,
    input  wire [15:0]                   cfg_tx_pfc_opcode,
    input  wire                          cfg_tx_pfc_en,
    input  wire [8*16-1:0]               cfg_tx_pfc_quanta,
    input  wire [8*16-1:0]               cfg_tx_pfc_refresh,
    input  wire [9:0]                    cfg_quanta_step,
    input  wire                          cfg_quanta_clk_en,

    /*
     * Status
     */
    output wire                          stat_tx_lfc_pkt,
    output wire                          stat_tx_lfc_xon,
    output wire                          stat_tx_lfc_xoff,
    output wire                          stat_tx_lfc_paused,
    output wire                          stat_tx_pfc_pkt,
    output wire [7:0]                    stat_tx_pfc_xon,
    output wire [7:0]                    stat_tx_pfc_xoff,
    output wire [7:0]                    stat_tx_pfc_paused
);

localparam QFB = 8;

// check configuration
initial begin
    if (MCF_PARAMS_SIZE < (PFC_ENABLE ? 18 : 2)) begin
        $display("Error: MCF_PARAMS_SIZE too small for requested configuration (instance %m)");
        $finish;
    end
end

reg lfc_req_reg = 1'b0, lfc_req_next;
reg lfc_act_reg = 1'b0, lfc_act_next;
reg lfc_send_reg = 1'b0, lfc_send_next;
reg [7:0] pfc_req_reg = 8'd0, pfc_req_next;
reg [7:0] pfc_act_reg = 8'd0, pfc_act_next;
reg [7:0] pfc_en_reg = 8'd0, pfc_en_next;
reg pfc_send_reg = 1'b0, pfc_send_next;

reg [16+QFB-1:0] lfc_refresh_reg = 0, lfc_refresh_next;
reg [16+QFB-1:0] pfc_refresh_reg[0:7], pfc_refresh_next[0:7];

reg stat_tx_lfc_pkt_reg = 1'b0, stat_tx_lfc_pkt_next;
reg stat_tx_lfc_xon_reg = 1'b0, stat_tx_lfc_xon_next;
reg stat_tx_lfc_xoff_reg = 1'b0, stat_tx_lfc_xoff_next;
reg stat_tx_pfc_pkt_reg = 1'b0, stat_tx_pfc_pkt_next;
reg [7:0] stat_tx_pfc_xon_reg = 0, stat_tx_pfc_xon_next;
reg [7:0] stat_tx_pfc_xoff_reg = 0, stat_tx_pfc_xoff_next;

// MAC control interface
reg             mcf_pfc_sel_reg = PFC_ENABLE != 0, mcf_pfc_sel_next;
reg             mcf_valid_reg = 1'b0, mcf_valid_next;

wire [2*8-1:0] mcf_lfc_params;
assign mcf_lfc_params[16*0 +: 16] = lfc_req_reg ? {cfg_tx_lfc_quanta[0 +: 8], cfg_tx_lfc_quanta[8 +: 8]} : 0;

wire [18*8-1:0] mcf_pfc_params;
assign mcf_pfc_params[16*0 +: 16] = {pfc_en_reg, 8'd0};
assign mcf_pfc_params[16*1 +: 16] = pfc_req_reg[0] ? {cfg_tx_pfc_quanta[16*0+0 +: 8], cfg_tx_pfc_quanta[16*0+8 +: 8]} : 0;
assign mcf_pfc_params[16*2 +: 16] = pfc_req_reg[1] ? {cfg_tx_pfc_quanta[16*1+0 +: 8], cfg_tx_pfc_quanta[16*1+8 +: 8]} : 0;
assign mcf_pfc_params[16*3 +: 16] = pfc_req_reg[2] ? {cfg_tx_pfc_quanta[16*2+0 +: 8], cfg_tx_pfc_quanta[16*2+8 +: 8]} : 0;
assign mcf_pfc_params[16*4 +: 16] = pfc_req_reg[3] ? {cfg_tx_pfc_quanta[16*3+0 +: 8], cfg_tx_pfc_quanta[16*3+8 +: 8]} : 0;
assign mcf_pfc_params[16*5 +: 16] = pfc_req_reg[4] ? {cfg_tx_pfc_quanta[16*4+0 +: 8], cfg_tx_pfc_quanta[16*4+8 +: 8]} : 0;
assign mcf_pfc_params[16*6 +: 16] = pfc_req_reg[5] ? {cfg_tx_pfc_quanta[16*5+0 +: 8], cfg_tx_pfc_quanta[16*5+8 +: 8]} : 0;
assign mcf_pfc_params[16*7 +: 16] = pfc_req_reg[6] ? {cfg_tx_pfc_quanta[16*6+0 +: 8], cfg_tx_pfc_quanta[16*6+8 +: 8]} : 0;
assign mcf_pfc_params[16*8 +: 16] = pfc_req_reg[7] ? {cfg_tx_pfc_quanta[16*7+0 +: 8], cfg_tx_pfc_quanta[16*7+8 +: 8]} : 0;

assign mcf_valid = mcf_valid_reg;
assign mcf_eth_dst  = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_dst  : cfg_tx_lfc_eth_dst;
assign mcf_eth_src  = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_src  : cfg_tx_lfc_eth_src;
assign mcf_eth_type = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_type : cfg_tx_lfc_eth_type;
assign mcf_opcode   = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_opcode   : cfg_tx_lfc_opcode;
assign mcf_params   = (PFC_ENABLE && mcf_pfc_sel_reg) ? mcf_pfc_params      : mcf_lfc_params;

assign stat_tx_lfc_pkt = stat_tx_lfc_pkt_reg;
assign stat_tx_lfc_xon = stat_tx_lfc_xon_reg;
assign stat_tx_lfc_xoff = stat_tx_lfc_xoff_reg;
assign stat_tx_lfc_paused = lfc_req_reg;
assign stat_tx_pfc_pkt = stat_tx_pfc_pkt_reg;
assign stat_tx_pfc_xon = stat_tx_pfc_xon_reg;
assign stat_tx_pfc_xoff = stat_tx_pfc_xoff_reg;
assign stat_tx_pfc_paused = pfc_req_reg;

integer k;

initial begin
    for (k = 0; k < 8; k = k + 1) begin
        pfc_refresh_reg[k] = 0;
    end
end

always @* begin
    lfc_req_next = lfc_req_reg;
    lfc_act_next = lfc_act_reg;
    lfc_send_next = lfc_send_reg | tx_lfc_resend;
    pfc_req_next = pfc_req_reg;
    pfc_act_next = pfc_act_reg;
    pfc_en_next = pfc_en_reg;
    pfc_send_next = pfc_send_reg | tx_pfc_resend;

    mcf_pfc_sel_next = mcf_pfc_sel_reg;
    mcf_valid_next = mcf_valid_reg && !mcf_ready;

    stat_tx_lfc_pkt_next = 1'b0;
    stat_tx_lfc_xon_next = 1'b0;
    stat_tx_lfc_xoff_next = 1'b0;
    stat_tx_pfc_pkt_next = 1'b0;
    stat_tx_pfc_xon_next = 0;
    stat_tx_pfc_xoff_next = 0;

    if (cfg_quanta_clk_en) begin
        if (lfc_refresh_reg > cfg_quanta_step) begin
            lfc_refresh_next = lfc_refresh_reg - cfg_quanta_step;
        end else begin
            lfc_refresh_next = 0;
            if (lfc_req_reg) begin
                lfc_send_next = 1'b1;
            end
        end
    end else begin
        lfc_refresh_next = lfc_refresh_reg;
    end

    for (k = 0; k < 8; k = k + 1) begin
        if (cfg_quanta_clk_en) begin
            if (pfc_refresh_reg[k] > cfg_quanta_step) begin
                pfc_refresh_next[k] = pfc_refresh_reg[k] - cfg_quanta_step;
            end else begin
                pfc_refresh_next[k] = 0;
                if (pfc_req_reg[k]) begin
                    pfc_send_next = 1'b1;
                end
            end
        end else begin
            pfc_refresh_next[k] = pfc_refresh_reg[k];
        end
    end

    if (cfg_tx_lfc_en) begin
        if (!mcf_valid_reg) begin
            if (lfc_req_reg != tx_lfc_req) begin
                lfc_req_next = tx_lfc_req;
                lfc_act_next = lfc_act_reg | tx_lfc_req;
                lfc_send_next = 1'b1;
            end

            if (lfc_send_reg && !(PFC_ENABLE && cfg_tx_pfc_en && pfc_send_reg)) begin
                mcf_pfc_sel_next = 1'b0;
                mcf_valid_next = lfc_act_reg;
                lfc_act_next = lfc_req_reg;
                lfc_refresh_next = lfc_req_reg ? {cfg_tx_lfc_refresh, {QFB{1'b0}}} : 0;
                lfc_send_next = 1'b0;

                stat_tx_lfc_pkt_next = lfc_act_reg;
                stat_tx_lfc_xon_next = lfc_act_reg && !lfc_req_reg;
                stat_tx_lfc_xoff_next = lfc_act_reg && lfc_req_reg;
            end
        end
    end

    if (PFC_ENABLE && cfg_tx_pfc_en) begin
        if (!mcf_valid_reg) begin
            if (pfc_req_reg != tx_pfc_req) begin
                pfc_req_next = tx_pfc_req;
                pfc_act_next = pfc_act_reg | tx_pfc_req;
                pfc_send_next = 1'b1;
            end

            if (pfc_send_reg) begin
                mcf_pfc_sel_next = 1'b1;
                mcf_valid_next = pfc_act_reg != 0;
                pfc_en_next = pfc_act_reg;
                pfc_act_next = pfc_req_reg;
                for (k = 0; k < 8; k = k + 1) begin
                    pfc_refresh_next[k] = pfc_req_reg[k] ? {cfg_tx_pfc_refresh[16*k +: 16], {QFB{1'b0}}} : 0;
                end
                pfc_send_next = 1'b0;

                stat_tx_pfc_pkt_next = pfc_act_reg != 0;
                stat_tx_pfc_xon_next = pfc_act_reg & ~pfc_req_reg;
                stat_tx_pfc_xoff_next = pfc_act_reg & pfc_req_reg;
            end
        end
    end
end

always @(posedge clk) begin
    lfc_req_reg <= lfc_req_next;
    lfc_act_reg <= lfc_act_next;
    lfc_send_reg <= lfc_send_next;
    pfc_req_reg <= pfc_req_next;
    pfc_act_reg <= pfc_act_next;
    pfc_en_reg <= pfc_en_next;
    pfc_send_reg <= pfc_send_next;

    mcf_pfc_sel_reg <= mcf_pfc_sel_next;
    mcf_valid_reg <= mcf_valid_next;

    lfc_refresh_reg <= lfc_refresh_next;
    for (k = 0; k < 8; k = k + 1) begin
        pfc_refresh_reg[k] <= pfc_refresh_next[k];
    end

    stat_tx_lfc_pkt_reg <= stat_tx_lfc_pkt_next;
    stat_tx_lfc_xon_reg <= stat_tx_lfc_xon_next;
    stat_tx_lfc_xoff_reg <= stat_tx_lfc_xoff_next;
    stat_tx_pfc_pkt_reg <= stat_tx_pfc_pkt_next;
    stat_tx_pfc_xon_reg <= stat_tx_pfc_xon_next;
    stat_tx_pfc_xoff_reg <= stat_tx_pfc_xoff_next;

    if (rst) begin
        lfc_req_reg <= 1'b0;
        lfc_act_reg <= 1'b0;
        lfc_send_reg <= 1'b0;
        pfc_req_reg <= 0;
        pfc_act_reg <= 0;
        pfc_send_reg <= 0;
        mcf_pfc_sel_reg <= PFC_ENABLE != 0;
        mcf_valid_reg <= 1'b0;
        lfc_refresh_reg <= 0;
        for (k = 0; k < 8; k = k + 1) begin
            pfc_refresh_reg[k] <= 0;
        end

        stat_tx_lfc_pkt_reg <= 1'b0;
        stat_tx_lfc_xon_reg <= 1'b0;
        stat_tx_lfc_xoff_reg <= 1'b0;
        stat_tx_pfc_pkt_reg <= 1'b0;
        stat_tx_pfc_xon_reg <= 0;
        stat_tx_pfc_xoff_reg <= 0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/priority_encoder.v
/*

Copyright (c) 2014-2021 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Priority encoder module
 */
module priority_encoder #
(
    parameter WIDTH = 4,
    // LSB priority selection
    parameter LSB_HIGH_PRIORITY = 0
)
(
    input  wire [WIDTH-1:0]         input_unencoded,
    output wire                     output_valid,
    output wire [$clog2(WIDTH)-1:0] output_encoded,
    output wire [WIDTH-1:0]         output_unencoded
);

parameter LEVELS = WIDTH > 2 ? $clog2(WIDTH) : 1;
parameter W = 2**LEVELS;

// pad input to even power of two
wire [W-1:0] input_padded = {{W-WIDTH{1'b0}}, input_unencoded};

wire [W/2-1:0] stage_valid[LEVELS-1:0];
wire [W/2-1:0] stage_enc[LEVELS-1:0];

generate
    genvar l, n;

    // process input bits; generate valid bit and encoded bit for each pair
    for (n = 0; n < W/2; n = n + 1) begin : loop_in
        assign stage_valid[0][n] = |input_padded[n*2+1:n*2];
        if (LSB_HIGH_PRIORITY) begin
            // bit 0 is highest priority
            assign stage_enc[0][n] = !input_padded[n*2+0];
        end else begin
            // bit 0 is lowest priority
            assign stage_enc[0][n] = input_padded[n*2+1];
        end
    end

    // compress down to single valid bit and encoded bus
    for (l = 1; l < LEVELS; l = l + 1) begin : loop_levels
        for (n = 0; n < W/(2*2**l); n = n + 1) begin : loop_compress
            assign stage_valid[l][n] = |stage_valid[l-1][n*2+1:n*2];
            if (LSB_HIGH_PRIORITY) begin
                // bit 0 is highest priority
                assign stage_enc[l][(n+1)*(l+1)-1:n*(l+1)] = stage_valid[l-1][n*2+0] ? {1'b0, stage_enc[l-1][(n*2+1)*l-1:(n*2+0)*l]} : {1'b1, stage_enc[l-1][(n*2+2)*l-1:(n*2+1)*l]};
            end else begin
                // bit 0 is lowest priority
                assign stage_enc[l][(n+1)*(l+1)-1:n*(l+1)] = stage_valid[l-1][n*2+1] ? {1'b1, stage_enc[l-1][(n*2+2)*l-1:(n*2+1)*l]} : {1'b0, stage_enc[l-1][(n*2+1)*l-1:(n*2+0)*l]};
            end
        end
    end
endgenerate

assign output_valid = stage_valid[LEVELS-1];
assign output_encoded = stage_enc[LEVELS-1];
assign output_unencoded = 1 << output_encoded;

endmodule

`resetall

// Source snapshot: rtl/network/vendor/udp.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * UDP block, IP interface
 */
module udp #
(
    parameter CHECKSUM_GEN_ENABLE = 1,
    parameter CHECKSUM_PAYLOAD_FIFO_DEPTH = 2048,
    parameter CHECKSUM_HEADER_FIFO_DEPTH = 8
)
(
    input  wire        clk,
    input  wire        rst,
    
    /*
     * IP frame input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [47:0] s_ip_eth_dest_mac,
    input  wire [47:0] s_ip_eth_src_mac,
    input  wire [15:0] s_ip_eth_type,
    input  wire [3:0]  s_ip_version,
    input  wire [3:0]  s_ip_ihl,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,
    
    /*
     * IP frame output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_ip_eth_dest_mac,
    output wire [47:0] m_ip_eth_src_mac,
    output wire [15:0] m_ip_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,
    
    /*
     * UDP frame input
     */
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [47:0] s_udp_eth_dest_mac,
    input  wire [47:0] s_udp_eth_src_mac,
    input  wire [15:0] s_udp_eth_type,
    input  wire [3:0]  s_udp_ip_version,
    input  wire [3:0]  s_udp_ip_ihl,
    input  wire [5:0]  s_udp_ip_dscp,
    input  wire [1:0]  s_udp_ip_ecn,
    input  wire [15:0] s_udp_ip_identification,
    input  wire [2:0]  s_udp_ip_flags,
    input  wire [12:0] s_udp_ip_fragment_offset,
    input  wire [7:0]  s_udp_ip_ttl,
    input  wire [15:0] s_udp_ip_header_checksum,
    input  wire [31:0] s_udp_ip_source_ip,
    input  wire [31:0] s_udp_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [15:0] s_udp_length,
    input  wire [15:0] s_udp_checksum,
    input  wire [7:0]  s_udp_payload_axis_tdata,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,
    
    /*
     * UDP frame output
     */
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [47:0] m_udp_eth_dest_mac,
    output wire [47:0] m_udp_eth_src_mac,
    output wire [15:0] m_udp_eth_type,
    output wire [3:0]  m_udp_ip_version,
    output wire [3:0]  m_udp_ip_ihl,
    output wire [5:0]  m_udp_ip_dscp,
    output wire [1:0]  m_udp_ip_ecn,
    output wire [15:0] m_udp_ip_length,
    output wire [15:0] m_udp_ip_identification,
    output wire [2:0]  m_udp_ip_flags,
    output wire [12:0] m_udp_ip_fragment_offset,
    output wire [7:0]  m_udp_ip_ttl,
    output wire [7:0]  m_udp_ip_protocol,
    output wire [15:0] m_udp_ip_header_checksum,
    output wire [31:0] m_udp_ip_source_ip,
    output wire [31:0] m_udp_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    output wire [7:0]  m_udp_payload_axis_tdata,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser,
    
    /*
     * Status signals
     */
    output wire        rx_busy,
    output wire        tx_busy,
    output wire        rx_error_header_early_termination,
    output wire        rx_error_payload_early_termination,
    output wire        tx_error_payload_early_termination
);

wire        tx_udp_hdr_valid;
wire        tx_udp_hdr_ready;
wire [47:0] tx_udp_eth_dest_mac;
wire [47:0] tx_udp_eth_src_mac;
wire [15:0] tx_udp_eth_type;
wire [3:0]  tx_udp_ip_version;
wire [3:0]  tx_udp_ip_ihl;
wire [5:0]  tx_udp_ip_dscp;
wire [1:0]  tx_udp_ip_ecn;
wire [15:0] tx_udp_ip_identification;
wire [2:0]  tx_udp_ip_flags;
wire [12:0] tx_udp_ip_fragment_offset;
wire [7:0]  tx_udp_ip_ttl;
wire [15:0] tx_udp_ip_header_checksum;
wire [31:0] tx_udp_ip_source_ip;
wire [31:0] tx_udp_ip_dest_ip;
wire [15:0] tx_udp_source_port;
wire [15:0] tx_udp_dest_port;
wire [15:0] tx_udp_length;
wire [15:0] tx_udp_checksum;
wire [7:0]  tx_udp_payload_axis_tdata;
wire        tx_udp_payload_axis_tvalid;
wire        tx_udp_payload_axis_tready;
wire        tx_udp_payload_axis_tlast;
wire        tx_udp_payload_axis_tuser;

udp_ip_rx
udp_ip_rx_inst (
    .clk(clk),
    .rst(rst),
    // IP frame input
    .s_ip_hdr_valid(s_ip_hdr_valid),
    .s_ip_hdr_ready(s_ip_hdr_ready),
    .s_eth_dest_mac(s_ip_eth_dest_mac),
    .s_eth_src_mac(s_ip_eth_src_mac),
    .s_eth_type(s_ip_eth_type),
    .s_ip_version(s_ip_version),
    .s_ip_ihl(s_ip_ihl),
    .s_ip_dscp(s_ip_dscp),
    .s_ip_ecn(s_ip_ecn),
    .s_ip_length(s_ip_length),
    .s_ip_identification(s_ip_identification),
    .s_ip_flags(s_ip_flags),
    .s_ip_fragment_offset(s_ip_fragment_offset),
    .s_ip_ttl(s_ip_ttl),
    .s_ip_protocol(s_ip_protocol),
    .s_ip_header_checksum(s_ip_header_checksum),
    .s_ip_source_ip(s_ip_source_ip),
    .s_ip_dest_ip(s_ip_dest_ip),
    .s_ip_payload_axis_tdata(s_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(s_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(s_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(s_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(s_ip_payload_axis_tuser),
    // UDP frame output
    .m_udp_hdr_valid(m_udp_hdr_valid),
    .m_udp_hdr_ready(m_udp_hdr_ready),
    .m_eth_dest_mac(m_udp_eth_dest_mac),
    .m_eth_src_mac(m_udp_eth_src_mac),
    .m_eth_type(m_udp_eth_type),
    .m_ip_version(m_udp_ip_version),
    .m_ip_ihl(m_udp_ip_ihl),
    .m_ip_dscp(m_udp_ip_dscp),
    .m_ip_ecn(m_udp_ip_ecn),
    .m_ip_length(m_udp_ip_length),
    .m_ip_identification(m_udp_ip_identification),
    .m_ip_flags(m_udp_ip_flags),
    .m_ip_fragment_offset(m_udp_ip_fragment_offset),
    .m_ip_ttl(m_udp_ip_ttl),
    .m_ip_protocol(m_udp_ip_protocol),
    .m_ip_header_checksum(m_udp_ip_header_checksum),
    .m_ip_source_ip(m_udp_ip_source_ip),
    .m_ip_dest_ip(m_udp_ip_dest_ip),
    .m_udp_source_port(m_udp_source_port),
    .m_udp_dest_port(m_udp_dest_port),
    .m_udp_length(m_udp_length),
    .m_udp_checksum(m_udp_checksum),
    .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
    .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
    // Status signals
    .busy(rx_busy),
    .error_header_early_termination(rx_error_header_early_termination),
    .error_payload_early_termination(rx_error_payload_early_termination)
);

generate

if (CHECKSUM_GEN_ENABLE) begin

    udp_checksum_gen #(
        .PAYLOAD_FIFO_DEPTH(CHECKSUM_PAYLOAD_FIFO_DEPTH),
        .HEADER_FIFO_DEPTH(CHECKSUM_HEADER_FIFO_DEPTH)
    )
    udp_checksum_gen_inst (
        .clk(clk),
        .rst(rst),
        // UDP frame input
        .s_udp_hdr_valid(s_udp_hdr_valid),
        .s_udp_hdr_ready(s_udp_hdr_ready),
        .s_eth_dest_mac(s_udp_eth_dest_mac),
        .s_eth_src_mac(s_udp_eth_src_mac),
        .s_eth_type(s_udp_eth_type),
        .s_ip_version(s_udp_ip_version),
        .s_ip_ihl(s_udp_ip_ihl),
        .s_ip_dscp(s_udp_ip_dscp),
        .s_ip_ecn(s_udp_ip_ecn),
        .s_ip_identification(s_udp_ip_identification),
        .s_ip_flags(s_udp_ip_flags),
        .s_ip_fragment_offset(s_udp_ip_fragment_offset),
        .s_ip_ttl(s_udp_ip_ttl),
        .s_ip_header_checksum(s_udp_ip_header_checksum),
        .s_ip_source_ip(s_udp_ip_source_ip),
        .s_ip_dest_ip(s_udp_ip_dest_ip),
        .s_udp_source_port(s_udp_source_port),
        .s_udp_dest_port(s_udp_dest_port),
        .s_udp_payload_axis_tdata(s_udp_payload_axis_tdata),
        .s_udp_payload_axis_tvalid(s_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready(s_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast(s_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser(s_udp_payload_axis_tuser),
        // UDP frame output
        .m_udp_hdr_valid(tx_udp_hdr_valid),
        .m_udp_hdr_ready(tx_udp_hdr_ready),
        .m_eth_dest_mac(tx_udp_eth_dest_mac),
        .m_eth_src_mac(tx_udp_eth_src_mac),
        .m_eth_type(tx_udp_eth_type),
        .m_ip_version(tx_udp_ip_version),
        .m_ip_ihl(tx_udp_ip_ihl),
        .m_ip_dscp(tx_udp_ip_dscp),
        .m_ip_ecn(tx_udp_ip_ecn),
        .m_ip_length(),
        .m_ip_identification(tx_udp_ip_identification),
        .m_ip_flags(tx_udp_ip_flags),
        .m_ip_fragment_offset(tx_udp_ip_fragment_offset),
        .m_ip_ttl(tx_udp_ip_ttl),
        .m_ip_protocol(),
        .m_ip_header_checksum(tx_udp_ip_header_checksum),
        .m_ip_source_ip(tx_udp_ip_source_ip),
        .m_ip_dest_ip(tx_udp_ip_dest_ip),
        .m_udp_source_port(tx_udp_source_port),
        .m_udp_dest_port(tx_udp_dest_port),
        .m_udp_length(tx_udp_length),
        .m_udp_checksum(tx_udp_checksum),
        .m_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
        .m_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(tx_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
        // Status signals
        .busy()
    );

end else begin

    assign tx_udp_hdr_valid = s_udp_hdr_valid;
    assign s_udp_hdr_ready = tx_udp_hdr_ready;
    assign tx_udp_eth_dest_mac = s_udp_eth_dest_mac;
    assign tx_udp_eth_src_mac = s_udp_eth_src_mac;
    assign tx_udp_eth_type = s_udp_eth_type;
    assign tx_udp_ip_version = s_udp_ip_version;
    assign tx_udp_ip_ihl = s_udp_ip_ihl;
    assign tx_udp_ip_dscp = s_udp_ip_dscp;
    assign tx_udp_ip_ecn = s_udp_ip_ecn;
    assign tx_udp_ip_identification = s_udp_ip_identification;
    assign tx_udp_ip_flags = s_udp_ip_flags;
    assign tx_udp_ip_fragment_offset = s_udp_ip_fragment_offset;
    assign tx_udp_ip_ttl = s_udp_ip_ttl;
    assign tx_udp_ip_header_checksum = s_udp_ip_header_checksum;
    assign tx_udp_ip_source_ip = s_udp_ip_source_ip;
    assign tx_udp_ip_dest_ip = s_udp_ip_dest_ip;
    assign tx_udp_source_port = s_udp_source_port;
    assign tx_udp_dest_port = s_udp_dest_port;
    assign tx_udp_length = s_udp_length;
    assign tx_udp_checksum = s_udp_checksum;
    assign tx_udp_payload_axis_tdata = s_udp_payload_axis_tdata;
    assign tx_udp_payload_axis_tvalid = s_udp_payload_axis_tvalid;
    assign s_udp_payload_axis_tready = tx_udp_payload_axis_tready;
    assign tx_udp_payload_axis_tlast = s_udp_payload_axis_tlast;
    assign tx_udp_payload_axis_tuser = s_udp_payload_axis_tuser;

end

endgenerate

udp_ip_tx
udp_ip_tx_inst (
    .clk(clk),
    .rst(rst),
    // UDP frame input
    .s_udp_hdr_valid(tx_udp_hdr_valid),
    .s_udp_hdr_ready(tx_udp_hdr_ready),
    .s_eth_dest_mac(tx_udp_eth_dest_mac),
    .s_eth_src_mac(tx_udp_eth_src_mac),
    .s_eth_type(tx_udp_eth_type),
    .s_ip_version(tx_udp_ip_version),
    .s_ip_ihl(tx_udp_ip_ihl),
    .s_ip_dscp(tx_udp_ip_dscp),
    .s_ip_ecn(tx_udp_ip_ecn),
    .s_ip_identification(tx_udp_ip_identification),
    .s_ip_flags(tx_udp_ip_flags),
    .s_ip_fragment_offset(tx_udp_ip_fragment_offset),
    .s_ip_ttl(tx_udp_ip_ttl),
    .s_ip_protocol(8'h11),
    .s_ip_header_checksum(tx_udp_ip_header_checksum),
    .s_ip_source_ip(tx_udp_ip_source_ip),
    .s_ip_dest_ip(tx_udp_ip_dest_ip),
    .s_udp_source_port(tx_udp_source_port),
    .s_udp_dest_port(tx_udp_dest_port),
    .s_udp_length(tx_udp_length),
    .s_udp_checksum(tx_udp_checksum),
    .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(m_ip_hdr_valid),
    .m_ip_hdr_ready(m_ip_hdr_ready),
    .m_eth_dest_mac(m_ip_eth_dest_mac),
    .m_eth_src_mac(m_ip_eth_src_mac),
    .m_eth_type(m_ip_eth_type),
    .m_ip_version(m_ip_version),
    .m_ip_ihl(m_ip_ihl),
    .m_ip_dscp(m_ip_dscp),
    .m_ip_ecn(m_ip_ecn),
    .m_ip_length(m_ip_length),
    .m_ip_identification(m_ip_identification),
    .m_ip_flags(m_ip_flags),
    .m_ip_fragment_offset(m_ip_fragment_offset),
    .m_ip_ttl(m_ip_ttl),
    .m_ip_protocol(m_ip_protocol),
    .m_ip_header_checksum(m_ip_header_checksum),
    .m_ip_source_ip(m_ip_source_ip),
    .m_ip_dest_ip(m_ip_dest_ip),
    .m_ip_payload_axis_tdata(m_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(m_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(m_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(m_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(m_ip_payload_axis_tuser),
    // Status signals
    .busy(tx_busy),
    .error_payload_early_termination(tx_error_payload_early_termination)
);

endmodule

`resetall

// Source snapshot: rtl/network/vendor/udp_checksum_gen.v
/*

Copyright (c) 2016-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * UDP checksum calculation module
 */
module udp_checksum_gen #
(
    parameter PAYLOAD_FIFO_DEPTH = 2048,
    parameter HEADER_FIFO_DEPTH = 8
)
(
    input  wire        clk,
    input  wire        rst,
    
    /*
     * UDP frame input
     */
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [3:0]  s_ip_version,
    input  wire [3:0]  s_ip_ihl,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [7:0]  s_udp_payload_axis_tdata,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,
    
    /*
     * UDP frame output
     */
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    output wire [7:0]  m_udp_payload_axis_tdata,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser,
    
    /*
     * Status signals
     */
    output wire        busy
);

/*

UDP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets

 source port                 2 octets
 desination port             2 octets
 length                      2 octets
 checksum                    2 octets

 payload                     length octets

This module receives a UDP frame with header fields in parallel and payload on
an AXI stream interface, calculates the length and checksum, then produces the
header fields in parallel along with the UDP payload in a separate AXI stream.

*/

parameter HEADER_FIFO_ADDR_WIDTH = $clog2(HEADER_FIFO_DEPTH);

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_SUM_HEADER_1 = 3'd1,
    STATE_SUM_HEADER_2 = 3'd2,
    STATE_SUM_HEADER_3 = 3'd3,
    STATE_SUM_PAYLOAD = 3'd4,
    STATE_FINISH_SUM = 3'd5;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg store_udp_hdr;
reg shift_payload_in;
reg [31:0] checksum_part;

reg [15:0] frame_ptr_reg = 16'd0, frame_ptr_next;

reg [31:0] checksum_reg = 32'd0, checksum_next;

reg [47:0] eth_dest_mac_reg = 48'd0;
reg [47:0] eth_src_mac_reg = 48'd0;
reg [15:0] eth_type_reg = 16'd0;
reg [3:0]  ip_version_reg = 4'd0;
reg [3:0]  ip_ihl_reg = 4'd0;
reg [5:0]  ip_dscp_reg = 6'd0;
reg [1:0]  ip_ecn_reg = 2'd0;
reg [15:0] ip_identification_reg = 16'd0;
reg [2:0]  ip_flags_reg = 3'd0;
reg [12:0] ip_fragment_offset_reg = 13'd0;
reg [7:0]  ip_ttl_reg = 8'd0;
reg [15:0] ip_header_checksum_reg = 16'd0;
reg [31:0] ip_source_ip_reg = 32'd0;
reg [31:0] ip_dest_ip_reg = 32'd0;
reg [15:0] udp_source_port_reg = 16'd0;
reg [15:0] udp_dest_port_reg = 16'd0;

reg hdr_valid_reg = 0, hdr_valid_next;

reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

reg busy_reg = 1'b0;

/*
 * UDP Payload FIFO
 */
wire [7:0] s_udp_payload_fifo_tdata;
wire s_udp_payload_fifo_tvalid;
wire s_udp_payload_fifo_tready;
wire s_udp_payload_fifo_tlast;
wire s_udp_payload_fifo_tuser;

wire [7:0] m_udp_payload_fifo_tdata;
wire m_udp_payload_fifo_tvalid;
wire m_udp_payload_fifo_tready;
wire m_udp_payload_fifo_tlast;
wire m_udp_payload_fifo_tuser;

axis_fifo #(
    .DEPTH(PAYLOAD_FIFO_DEPTH),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .FRAME_FIFO(0)
)
payload_fifo (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata(s_udp_payload_fifo_tdata),
    .s_axis_tkeep(0),
    .s_axis_tvalid(s_udp_payload_fifo_tvalid),
    .s_axis_tready(s_udp_payload_fifo_tready),
    .s_axis_tlast(s_udp_payload_fifo_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(s_udp_payload_fifo_tuser),
    // AXI output
    .m_axis_tdata(m_udp_payload_fifo_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(m_udp_payload_fifo_tvalid),
    .m_axis_tready(m_udp_payload_fifo_tready),
    .m_axis_tlast(m_udp_payload_fifo_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(m_udp_payload_fifo_tuser),
    // Status
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

assign s_udp_payload_fifo_tdata = s_udp_payload_axis_tdata;
assign s_udp_payload_fifo_tvalid = s_udp_payload_axis_tvalid && shift_payload_in;
assign s_udp_payload_axis_tready = s_udp_payload_fifo_tready && shift_payload_in;
assign s_udp_payload_fifo_tlast = s_udp_payload_axis_tlast;
assign s_udp_payload_fifo_tuser = s_udp_payload_axis_tuser;

assign m_udp_payload_axis_tdata = m_udp_payload_fifo_tdata;
assign m_udp_payload_axis_tvalid = m_udp_payload_fifo_tvalid;
assign m_udp_payload_fifo_tready = m_udp_payload_axis_tready;
assign m_udp_payload_axis_tlast = m_udp_payload_fifo_tlast;
assign m_udp_payload_axis_tuser = m_udp_payload_fifo_tuser;

/*
 * UDP Header FIFO
 */
reg [HEADER_FIFO_ADDR_WIDTH:0] header_fifo_wr_ptr_reg = {HEADER_FIFO_ADDR_WIDTH+1{1'b0}}, header_fifo_wr_ptr_next;
reg [HEADER_FIFO_ADDR_WIDTH:0] header_fifo_rd_ptr_reg = {HEADER_FIFO_ADDR_WIDTH+1{1'b0}}, header_fifo_rd_ptr_next;

reg [47:0] eth_dest_mac_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [47:0] eth_src_mac_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] eth_type_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [3:0] ip_version_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [3:0] ip_ihl_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [5:0] ip_dscp_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [1:0] ip_ecn_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] ip_identification_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [2:0] ip_flags_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [12:0] ip_fragment_offset_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [7:0] ip_ttl_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] ip_header_checksum_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [31:0] ip_source_ip_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [31:0] ip_dest_ip_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] udp_source_port_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] udp_dest_port_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] udp_length_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
reg [15:0] udp_checksum_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];

reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;
reg [3:0]  m_ip_version_reg = 4'd0;
reg [3:0]  m_ip_ihl_reg = 4'd0;
reg [5:0]  m_ip_dscp_reg = 6'd0;
reg [1:0]  m_ip_ecn_reg = 2'd0;
reg [15:0] m_ip_identification_reg = 16'd0;
reg [2:0]  m_ip_flags_reg = 3'd0;
reg [12:0] m_ip_fragment_offset_reg = 13'd0;
reg [7:0]  m_ip_ttl_reg = 8'd0;
reg [15:0] m_ip_header_checksum_reg = 16'd0;
reg [31:0] m_ip_source_ip_reg = 32'd0;
reg [31:0] m_ip_dest_ip_reg = 32'd0;
reg [15:0] m_udp_source_port_reg = 16'd0;
reg [15:0] m_udp_dest_port_reg = 16'd0;
reg [15:0] m_udp_length_reg = 16'd0;
reg [15:0] m_udp_checksum_reg = 16'd0;

reg m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;

// full when first MSB different but rest same
wire header_fifo_full = ((header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH] != header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH]) &&
                         (header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0] == header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]));
// empty when pointers match exactly
wire header_fifo_empty = header_fifo_wr_ptr_reg == header_fifo_rd_ptr_reg;

// control signals
reg header_fifo_write;
reg header_fifo_read;

wire header_fifo_ready = !header_fifo_full;

assign m_udp_hdr_valid = m_udp_hdr_valid_reg;

assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_ip_version = m_ip_version_reg;
assign m_ip_ihl = m_ip_ihl_reg;
assign m_ip_dscp = m_ip_dscp_reg;
assign m_ip_ecn = m_ip_ecn_reg;
assign m_ip_length = m_udp_length_reg + 16'd20;
assign m_ip_identification = m_ip_identification_reg;
assign m_ip_flags = m_ip_flags_reg;
assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
assign m_ip_ttl = m_ip_ttl_reg;
assign m_ip_protocol = 8'h11;
assign m_ip_header_checksum = m_ip_header_checksum_reg;
assign m_ip_source_ip = m_ip_source_ip_reg;
assign m_ip_dest_ip = m_ip_dest_ip_reg;
assign m_udp_source_port = m_udp_source_port_reg;
assign m_udp_dest_port = m_udp_dest_port_reg;
assign m_udp_length = m_udp_length_reg;
assign m_udp_checksum = m_udp_checksum_reg;

// Write logic
always @* begin
    header_fifo_write = 1'b0;

    header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg;

    if (hdr_valid_reg) begin
        // input data valid
        if (~header_fifo_full) begin
            // not full, perform write
            header_fifo_write = 1'b1;
            header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg + 1;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        header_fifo_wr_ptr_reg <= {HEADER_FIFO_ADDR_WIDTH+1{1'b0}};
    end else begin
        header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_next;
    end

    if (header_fifo_write) begin
        eth_dest_mac_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_dest_mac_reg;
        eth_src_mac_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_src_mac_reg;
        eth_type_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_type_reg;
        ip_version_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_version_reg;
        ip_ihl_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ihl_reg;
        ip_dscp_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_dscp_reg;
        ip_ecn_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ecn_reg;
        ip_identification_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_identification_reg;
        ip_flags_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_flags_reg;
        ip_fragment_offset_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_fragment_offset_reg;
        ip_ttl_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ttl_reg;
        ip_header_checksum_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_header_checksum_reg;
        ip_source_ip_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_source_ip_reg;
        ip_dest_ip_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_dest_ip_reg;
        udp_source_port_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= udp_source_port_reg;
        udp_dest_port_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= udp_dest_port_reg;
        udp_length_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= frame_ptr_reg;
        udp_checksum_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= checksum_reg[15:0];
    end
end

// Read logic
always @* begin
    header_fifo_read = 1'b0;

    header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg;

    m_udp_hdr_valid_next = m_udp_hdr_valid_reg;

    if (m_udp_hdr_ready || !m_udp_hdr_valid) begin
        // output data not valid OR currently being transferred
        if (!header_fifo_empty) begin
            // not empty, perform read
            header_fifo_read = 1'b1;
            m_udp_hdr_valid_next = 1'b1;
            header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg + 1;
        end else begin
            // empty, invalidate
            m_udp_hdr_valid_next = 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        header_fifo_rd_ptr_reg <= {HEADER_FIFO_ADDR_WIDTH+1{1'b0}};
        m_udp_hdr_valid_reg <= 1'b0;
    end else begin
        header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_next;
        m_udp_hdr_valid_reg <= m_udp_hdr_valid_next;
    end

    if (header_fifo_read) begin
        m_eth_dest_mac_reg <= eth_dest_mac_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_eth_src_mac_reg <= eth_src_mac_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_eth_type_reg <= eth_type_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_version_reg <= ip_version_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_ihl_reg <= ip_ihl_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_dscp_reg <= ip_dscp_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_ecn_reg <= ip_ecn_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_identification_reg <= ip_identification_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_flags_reg <= ip_flags_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_fragment_offset_reg <= ip_fragment_offset_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_ttl_reg <= ip_ttl_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_header_checksum_reg <= ip_header_checksum_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_source_ip_reg <= ip_source_ip_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_ip_dest_ip_reg <= ip_dest_ip_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_udp_source_port_reg <= udp_source_port_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_udp_dest_port_reg <= udp_dest_port_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_udp_length_reg <= udp_length_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        m_udp_checksum_reg <= udp_checksum_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
    end
end

assign s_udp_hdr_ready = s_udp_hdr_ready_reg;

assign busy = busy_reg;

always @* begin
    state_next = STATE_IDLE;

    s_udp_hdr_ready_next = 1'b0;
    s_udp_payload_axis_tready_next = 1'b0;

    store_udp_hdr = 1'b0;
    shift_payload_in = 1'b0;

    frame_ptr_next = frame_ptr_reg;
    checksum_next = checksum_reg;

    hdr_valid_next = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state
            s_udp_hdr_ready_next = header_fifo_ready;

            if (s_udp_hdr_ready && s_udp_hdr_valid) begin
                store_udp_hdr = 1'b1;
                frame_ptr_next = 0;
                // 16'h0011 = zero padded type field
                // 16'h0010 = header length times two
                checksum_next = 16'h0011 + 16'h0010;
                s_udp_hdr_ready_next = 1'b0;
                state_next = STATE_SUM_HEADER_1;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_SUM_HEADER_1: begin
            // sum pseudo header and header
            checksum_next = checksum_reg + ip_source_ip_reg[31:16] + ip_source_ip_reg[15:0];
            state_next = STATE_SUM_HEADER_2;
        end
        STATE_SUM_HEADER_2: begin
            // sum pseudo header and header
            checksum_next = checksum_reg + ip_dest_ip_reg[31:16] + ip_dest_ip_reg[15:0];
            state_next = STATE_SUM_HEADER_3;
        end
        STATE_SUM_HEADER_3: begin
            // sum pseudo header and header
            checksum_next = checksum_reg + udp_source_port_reg + udp_dest_port_reg;
            frame_ptr_next = 8;
            state_next = STATE_SUM_PAYLOAD;
        end
        STATE_SUM_PAYLOAD: begin
            // sum payload
            shift_payload_in = 1'b1;

            if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
                // checksum computation for payload - alternately store and accumulate
                // add 2 for length calculation (two length fields in pseudo header)
                if (frame_ptr_reg[0]) begin
                    checksum_next = checksum_reg + {8'h00, s_udp_payload_axis_tdata} + 2;
                end else begin
                    checksum_next = checksum_reg + {s_udp_payload_axis_tdata, 8'h00} + 2;
                end

                frame_ptr_next = frame_ptr_reg + 1;

                if (s_udp_payload_axis_tlast) begin
                    state_next = STATE_FINISH_SUM;
                end else begin
                    state_next = STATE_SUM_PAYLOAD;
                end
            end else begin
                state_next = STATE_SUM_PAYLOAD;
            end
        end
        STATE_FINISH_SUM: begin
            // add MSW (twice!) for proper ones complement sum
            checksum_part = checksum_reg[15:0] + checksum_reg[31:16];
            checksum_next = ~(checksum_part[15:0] + checksum_part[16]);
            hdr_valid_next = 1;
            state_next = STATE_IDLE;
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_udp_hdr_ready_reg <= 1'b0;
        s_udp_payload_axis_tready_reg <= 1'b0;
        hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
    end else begin
        state_reg <= state_next;

        s_udp_hdr_ready_reg <= s_udp_hdr_ready_next;
        s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

        hdr_valid_reg <= hdr_valid_next;

        busy_reg <= state_next != STATE_IDLE;
    end

    frame_ptr_reg <= frame_ptr_next;
    checksum_reg <= checksum_next;

    // datapath
    if (store_udp_hdr) begin
        eth_dest_mac_reg <= s_eth_dest_mac;
        eth_src_mac_reg <= s_eth_src_mac;
        eth_type_reg <= s_eth_type;
        ip_version_reg <= s_ip_version;
        ip_ihl_reg <= s_ip_ihl;
        ip_dscp_reg <= s_ip_dscp;
        ip_ecn_reg <= s_ip_ecn;
        ip_identification_reg <= s_ip_identification;
        ip_flags_reg <= s_ip_flags;
        ip_fragment_offset_reg <= s_ip_fragment_offset;
        ip_ttl_reg <= s_ip_ttl;
        ip_header_checksum_reg <= s_ip_header_checksum;
        ip_source_ip_reg <= s_ip_source_ip;
        ip_dest_ip_reg <= s_ip_dest_ip;
        udp_source_port_reg <= s_udp_source_port;
        udp_dest_port_reg <= s_udp_dest_port;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/udp_complete.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IPv4 and ARP block with UDP support, ethernet frame interface
 */
module udp_complete #(
    parameter ARP_CACHE_ADDR_WIDTH = 9,
    parameter ARP_REQUEST_RETRY_COUNT = 4,
    parameter ARP_REQUEST_RETRY_INTERVAL = 125000000*2,
    parameter ARP_REQUEST_TIMEOUT = 125000000*30,
    parameter UDP_CHECKSUM_GEN_ENABLE = 1,
    parameter UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH = 2048,
    parameter UDP_CHECKSUM_HEADER_FIFO_DEPTH = 8
)
(
    input  wire        clk,
    input  wire        rst,
    
    /*
     * Ethernet frame input
     */
    input  wire        s_eth_hdr_valid,
    output wire        s_eth_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [7:0]  s_eth_payload_axis_tdata,
    input  wire        s_eth_payload_axis_tvalid,
    output wire        s_eth_payload_axis_tready,
    input  wire        s_eth_payload_axis_tlast,
    input  wire        s_eth_payload_axis_tuser,
    
    /*
     * Ethernet frame output
     */
    output wire        m_eth_hdr_valid,
    input  wire        m_eth_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [7:0]  m_eth_payload_axis_tdata,
    output wire        m_eth_payload_axis_tvalid,
    input  wire        m_eth_payload_axis_tready,
    output wire        m_eth_payload_axis_tlast,
    output wire        m_eth_payload_axis_tuser,
    
    /*
     * IP input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,
    
    /*
     * IP output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_ip_eth_dest_mac,
    output wire [47:0] m_ip_eth_src_mac,
    output wire [15:0] m_ip_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,
    
    /*
     * UDP input
     */
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [5:0]  s_udp_ip_dscp,
    input  wire [1:0]  s_udp_ip_ecn,
    input  wire [7:0]  s_udp_ip_ttl,
    input  wire [31:0] s_udp_ip_source_ip,
    input  wire [31:0] s_udp_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [15:0] s_udp_length,
    input  wire [15:0] s_udp_checksum,
    input  wire [7:0]  s_udp_payload_axis_tdata,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,
    
    /*
     * UDP output
     */
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [47:0] m_udp_eth_dest_mac,
    output wire [47:0] m_udp_eth_src_mac,
    output wire [15:0] m_udp_eth_type,
    output wire [3:0]  m_udp_ip_version,
    output wire [3:0]  m_udp_ip_ihl,
    output wire [5:0]  m_udp_ip_dscp,
    output wire [1:0]  m_udp_ip_ecn,
    output wire [15:0] m_udp_ip_length,
    output wire [15:0] m_udp_ip_identification,
    output wire [2:0]  m_udp_ip_flags,
    output wire [12:0] m_udp_ip_fragment_offset,
    output wire [7:0]  m_udp_ip_ttl,
    output wire [7:0]  m_udp_ip_protocol,
    output wire [15:0] m_udp_ip_header_checksum,
    output wire [31:0] m_udp_ip_source_ip,
    output wire [31:0] m_udp_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    output wire [7:0]  m_udp_payload_axis_tdata,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser,

    /*
     * Status
     */
    output wire        ip_rx_busy,
    output wire        ip_tx_busy,
    output wire        udp_rx_busy,
    output wire        udp_tx_busy,
    output wire        ip_rx_error_header_early_termination,
    output wire        ip_rx_error_payload_early_termination,
    output wire        ip_rx_error_invalid_header,
    output wire        ip_rx_error_invalid_checksum,
    output wire        ip_tx_error_payload_early_termination,
    output wire        ip_tx_error_arp_failed,
    output wire        udp_rx_error_header_early_termination,
    output wire        udp_rx_error_payload_early_termination,
    output wire        udp_tx_error_payload_early_termination,

    /*
     * Configuration
     */
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,
    input  wire [31:0] gateway_ip,
    input  wire [31:0] subnet_mask,
    input  wire        clear_arp_cache
);

wire ip_rx_ip_hdr_valid;
wire ip_rx_ip_hdr_ready;
wire [47:0] ip_rx_ip_eth_dest_mac;
wire [47:0] ip_rx_ip_eth_src_mac;
wire [15:0] ip_rx_ip_eth_type;
wire [3:0] ip_rx_ip_version;
wire [3:0] ip_rx_ip_ihl;
wire [5:0] ip_rx_ip_dscp;
wire [1:0] ip_rx_ip_ecn;
wire [15:0] ip_rx_ip_length;
wire [15:0] ip_rx_ip_identification;
wire [2:0] ip_rx_ip_flags;
wire [12:0] ip_rx_ip_fragment_offset;
wire [7:0] ip_rx_ip_ttl;
wire [7:0] ip_rx_ip_protocol;
wire [15:0] ip_rx_ip_header_checksum;
wire [31:0] ip_rx_ip_source_ip;
wire [31:0] ip_rx_ip_dest_ip;
wire [7:0] ip_rx_ip_payload_axis_tdata;
wire ip_rx_ip_payload_axis_tvalid;
wire ip_rx_ip_payload_axis_tlast;
wire ip_rx_ip_payload_axis_tuser;
wire ip_rx_ip_payload_axis_tready;

wire ip_tx_ip_hdr_valid;
wire ip_tx_ip_hdr_ready;
wire [5:0] ip_tx_ip_dscp;
wire [1:0] ip_tx_ip_ecn;
wire [15:0] ip_tx_ip_length;
wire [7:0] ip_tx_ip_ttl;
wire [7:0] ip_tx_ip_protocol;
wire [31:0] ip_tx_ip_source_ip;
wire [31:0] ip_tx_ip_dest_ip;
wire [7:0] ip_tx_ip_payload_axis_tdata;
wire ip_tx_ip_payload_axis_tvalid;
wire ip_tx_ip_payload_axis_tlast;
wire ip_tx_ip_payload_axis_tuser;
wire ip_tx_ip_payload_axis_tready;

wire udp_rx_ip_hdr_valid;
wire udp_rx_ip_hdr_ready;
wire [47:0] udp_rx_ip_eth_dest_mac;
wire [47:0] udp_rx_ip_eth_src_mac;
wire [15:0] udp_rx_ip_eth_type;
wire [3:0] udp_rx_ip_version;
wire [3:0] udp_rx_ip_ihl;
wire [5:0] udp_rx_ip_dscp;
wire [1:0] udp_rx_ip_ecn;
wire [15:0] udp_rx_ip_length;
wire [15:0] udp_rx_ip_identification;
wire [2:0] udp_rx_ip_flags;
wire [12:0] udp_rx_ip_fragment_offset;
wire [7:0] udp_rx_ip_ttl;
wire [7:0] udp_rx_ip_protocol;
wire [15:0] udp_rx_ip_header_checksum;
wire [31:0] udp_rx_ip_source_ip;
wire [31:0] udp_rx_ip_dest_ip;
wire [7:0] udp_rx_ip_payload_axis_tdata;
wire udp_rx_ip_payload_axis_tvalid;
wire udp_rx_ip_payload_axis_tlast;
wire udp_rx_ip_payload_axis_tuser;
wire udp_rx_ip_payload_axis_tready;

wire udp_tx_ip_hdr_valid;
wire udp_tx_ip_hdr_ready;
wire [5:0] udp_tx_ip_dscp;
wire [1:0] udp_tx_ip_ecn;
wire [15:0] udp_tx_ip_length;
wire [7:0] udp_tx_ip_ttl;
wire [7:0] udp_tx_ip_protocol;
wire [31:0] udp_tx_ip_source_ip;
wire [31:0] udp_tx_ip_dest_ip;
wire [7:0] udp_tx_ip_payload_axis_tdata;
wire udp_tx_ip_payload_axis_tvalid;
wire udp_tx_ip_payload_axis_tlast;
wire udp_tx_ip_payload_axis_tuser;
wire udp_tx_ip_payload_axis_tready;

/*
 * Input classifier (ip_protocol)
 */
wire s_select_udp = (ip_rx_ip_protocol == 8'h11);
wire s_select_ip = !s_select_udp;

reg s_select_udp_reg = 1'b0;
reg s_select_ip_reg = 1'b0;

always @(posedge clk) begin
    if (rst) begin
        s_select_udp_reg <= 1'b0;
        s_select_ip_reg <= 1'b0;
    end else begin
        if (ip_rx_ip_payload_axis_tvalid) begin
            if ((!s_select_udp_reg && !s_select_ip_reg) ||
                (ip_rx_ip_payload_axis_tvalid && ip_rx_ip_payload_axis_tready && ip_rx_ip_payload_axis_tlast)) begin
                s_select_udp_reg <= s_select_udp;
                s_select_ip_reg <= s_select_ip;
            end
        end else begin
            s_select_udp_reg <= 1'b0;
            s_select_ip_reg <= 1'b0;
        end
    end
end

// IP frame to UDP module
assign udp_rx_ip_hdr_valid = s_select_udp && ip_rx_ip_hdr_valid;
assign udp_rx_ip_eth_dest_mac = ip_rx_ip_eth_dest_mac;
assign udp_rx_ip_eth_src_mac = ip_rx_ip_eth_src_mac;
assign udp_rx_ip_eth_type = ip_rx_ip_eth_type;
assign udp_rx_ip_version = ip_rx_ip_version;
assign udp_rx_ip_ihl = ip_rx_ip_ihl;
assign udp_rx_ip_dscp = ip_rx_ip_dscp;
assign udp_rx_ip_ecn = ip_rx_ip_ecn;
assign udp_rx_ip_length = ip_rx_ip_length;
assign udp_rx_ip_identification = ip_rx_ip_identification;
assign udp_rx_ip_flags = ip_rx_ip_flags;
assign udp_rx_ip_fragment_offset = ip_rx_ip_fragment_offset;
assign udp_rx_ip_ttl = ip_rx_ip_ttl;
assign udp_rx_ip_protocol = 8'h11;
assign udp_rx_ip_header_checksum = ip_rx_ip_header_checksum;
assign udp_rx_ip_source_ip = ip_rx_ip_source_ip;
assign udp_rx_ip_dest_ip = ip_rx_ip_dest_ip;
assign udp_rx_ip_payload_axis_tdata = ip_rx_ip_payload_axis_tdata;
assign udp_rx_ip_payload_axis_tvalid = s_select_udp_reg && ip_rx_ip_payload_axis_tvalid;
assign udp_rx_ip_payload_axis_tlast = ip_rx_ip_payload_axis_tlast;
assign udp_rx_ip_payload_axis_tuser = ip_rx_ip_payload_axis_tuser;

// External IP frame output
assign m_ip_hdr_valid = s_select_ip && ip_rx_ip_hdr_valid;
assign m_ip_eth_dest_mac = ip_rx_ip_eth_dest_mac;
assign m_ip_eth_src_mac = ip_rx_ip_eth_src_mac;
assign m_ip_eth_type = ip_rx_ip_eth_type;
assign m_ip_version = ip_rx_ip_version;
assign m_ip_ihl = ip_rx_ip_ihl;
assign m_ip_dscp = ip_rx_ip_dscp;
assign m_ip_ecn = ip_rx_ip_ecn;
assign m_ip_length = ip_rx_ip_length;
assign m_ip_identification = ip_rx_ip_identification;
assign m_ip_flags = ip_rx_ip_flags;
assign m_ip_fragment_offset = ip_rx_ip_fragment_offset;
assign m_ip_ttl = ip_rx_ip_ttl;
assign m_ip_protocol = ip_rx_ip_protocol;
assign m_ip_header_checksum = ip_rx_ip_header_checksum;
assign m_ip_source_ip = ip_rx_ip_source_ip;
assign m_ip_dest_ip = ip_rx_ip_dest_ip;
assign m_ip_payload_axis_tdata = ip_rx_ip_payload_axis_tdata;
assign m_ip_payload_axis_tvalid = s_select_ip_reg && ip_rx_ip_payload_axis_tvalid;
assign m_ip_payload_axis_tlast = ip_rx_ip_payload_axis_tlast;
assign m_ip_payload_axis_tuser = ip_rx_ip_payload_axis_tuser;

assign ip_rx_ip_hdr_ready = (s_select_udp && udp_rx_ip_hdr_ready) ||
                            (s_select_ip && m_ip_hdr_ready);

assign ip_rx_ip_payload_axis_tready = (s_select_udp_reg && udp_rx_ip_payload_axis_tready) ||
                                      (s_select_ip_reg && m_ip_payload_axis_tready);

/*
 * Output arbiter
 */
ip_arb_mux #(
    .S_COUNT(2),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .ARB_TYPE_ROUND_ROBIN(0),
    .ARB_LSB_HIGH_PRIORITY(1)
)
ip_arb_mux_inst (
    .clk(clk),
    .rst(rst),
    // IP frame inputs
    .s_ip_hdr_valid({s_ip_hdr_valid, udp_tx_ip_hdr_valid}),
    .s_ip_hdr_ready({s_ip_hdr_ready, udp_tx_ip_hdr_ready}),
    .s_eth_dest_mac(0),
    .s_eth_src_mac(0),
    .s_eth_type(0),
    .s_ip_version(0),
    .s_ip_ihl(0),
    .s_ip_dscp({s_ip_dscp, udp_tx_ip_dscp}),
    .s_ip_ecn({s_ip_ecn, udp_tx_ip_ecn}),
    .s_ip_length({s_ip_length, udp_tx_ip_length}),
    .s_ip_identification(0),
    .s_ip_flags(0),
    .s_ip_fragment_offset(0),
    .s_ip_ttl({s_ip_ttl, udp_tx_ip_ttl}),
    .s_ip_protocol({s_ip_protocol, udp_tx_ip_protocol}),
    .s_ip_header_checksum(0),
    .s_ip_source_ip({s_ip_source_ip, udp_tx_ip_source_ip}),
    .s_ip_dest_ip({s_ip_dest_ip, udp_tx_ip_dest_ip}),
    .s_ip_payload_axis_tdata({s_ip_payload_axis_tdata, udp_tx_ip_payload_axis_tdata}),
    .s_ip_payload_axis_tkeep(0),
    .s_ip_payload_axis_tvalid({s_ip_payload_axis_tvalid, udp_tx_ip_payload_axis_tvalid}),
    .s_ip_payload_axis_tready({s_ip_payload_axis_tready, udp_tx_ip_payload_axis_tready}),
    .s_ip_payload_axis_tlast({s_ip_payload_axis_tlast, udp_tx_ip_payload_axis_tlast}),
    .s_ip_payload_axis_tid(0),
    .s_ip_payload_axis_tdest(0),
    .s_ip_payload_axis_tuser({s_ip_payload_axis_tuser, udp_tx_ip_payload_axis_tuser}),
    // IP frame output
    .m_ip_hdr_valid(ip_tx_ip_hdr_valid),
    .m_ip_hdr_ready(ip_tx_ip_hdr_ready),
    .m_eth_dest_mac(),
    .m_eth_src_mac(),
    .m_eth_type(),
    .m_ip_version(),
    .m_ip_ihl(),
    .m_ip_dscp(ip_tx_ip_dscp),
    .m_ip_ecn(ip_tx_ip_ecn),
    .m_ip_length(ip_tx_ip_length),
    .m_ip_identification(),
    .m_ip_flags(),
    .m_ip_fragment_offset(),
    .m_ip_ttl(ip_tx_ip_ttl),
    .m_ip_protocol(ip_tx_ip_protocol),
    .m_ip_header_checksum(),
    .m_ip_source_ip(ip_tx_ip_source_ip),
    .m_ip_dest_ip(ip_tx_ip_dest_ip),
    .m_ip_payload_axis_tdata(ip_tx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tkeep(),
    .m_ip_payload_axis_tvalid(ip_tx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(ip_tx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(ip_tx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tid(),
    .m_ip_payload_axis_tdest(),
    .m_ip_payload_axis_tuser(ip_tx_ip_payload_axis_tuser)
);

/*
 * IP stack
 */
ip_complete #(
    .ARP_CACHE_ADDR_WIDTH(ARP_CACHE_ADDR_WIDTH),
    .ARP_REQUEST_RETRY_COUNT(ARP_REQUEST_RETRY_COUNT),
    .ARP_REQUEST_RETRY_INTERVAL(ARP_REQUEST_RETRY_INTERVAL),
    .ARP_REQUEST_TIMEOUT(ARP_REQUEST_TIMEOUT)
)
ip_complete_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(s_eth_hdr_valid),
    .s_eth_hdr_ready(s_eth_hdr_ready),
    .s_eth_dest_mac(s_eth_dest_mac),
    .s_eth_src_mac(s_eth_src_mac),
    .s_eth_type(s_eth_type),
    .s_eth_payload_axis_tdata(s_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(s_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(s_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(s_eth_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(m_eth_hdr_valid),
    .m_eth_hdr_ready(m_eth_hdr_ready),
    .m_eth_dest_mac(m_eth_dest_mac),
    .m_eth_src_mac(m_eth_src_mac),
    .m_eth_type(m_eth_type),
    .m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(m_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(m_eth_payload_axis_tuser),
    // IP frame input
    .s_ip_hdr_valid(ip_tx_ip_hdr_valid),
    .s_ip_hdr_ready(ip_tx_ip_hdr_ready),
    .s_ip_dscp(ip_tx_ip_dscp),
    .s_ip_ecn(ip_tx_ip_ecn),
    .s_ip_length(ip_tx_ip_length),
    .s_ip_ttl(ip_tx_ip_ttl),
    .s_ip_protocol(ip_tx_ip_protocol),
    .s_ip_source_ip(ip_tx_ip_source_ip),
    .s_ip_dest_ip(ip_tx_ip_dest_ip),
    .s_ip_payload_axis_tdata(ip_tx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(ip_tx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(ip_tx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(ip_tx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(ip_tx_ip_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(ip_rx_ip_hdr_valid),
    .m_ip_hdr_ready(ip_rx_ip_hdr_ready),
    .m_ip_eth_dest_mac(ip_rx_ip_eth_dest_mac),
    .m_ip_eth_src_mac(ip_rx_ip_eth_src_mac),
    .m_ip_eth_type(ip_rx_ip_eth_type),
    .m_ip_version(ip_rx_ip_version),
    .m_ip_ihl(ip_rx_ip_ihl),
    .m_ip_dscp(ip_rx_ip_dscp),
    .m_ip_ecn(ip_rx_ip_ecn),
    .m_ip_length(ip_rx_ip_length),
    .m_ip_identification(ip_rx_ip_identification),
    .m_ip_flags(ip_rx_ip_flags),
    .m_ip_fragment_offset(ip_rx_ip_fragment_offset),
    .m_ip_ttl(ip_rx_ip_ttl),
    .m_ip_protocol(ip_rx_ip_protocol),
    .m_ip_header_checksum(ip_rx_ip_header_checksum),
    .m_ip_source_ip(ip_rx_ip_source_ip),
    .m_ip_dest_ip(ip_rx_ip_dest_ip),
    .m_ip_payload_axis_tdata(ip_rx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(ip_rx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(ip_rx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(ip_rx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(ip_rx_ip_payload_axis_tuser),
    // Status
    .rx_busy(ip_rx_busy),
    .tx_busy(ip_tx_busy),
    .rx_error_header_early_termination(ip_rx_error_header_early_termination),
    .rx_error_payload_early_termination(ip_rx_error_payload_early_termination),
    .rx_error_invalid_header(ip_rx_error_invalid_header),
    .rx_error_invalid_checksum(ip_rx_error_invalid_checksum),
    .tx_error_payload_early_termination(ip_tx_error_payload_early_termination),
    .tx_error_arp_failed(ip_tx_error_arp_failed),
    // Configuration
    .local_mac(local_mac),
    .local_ip(local_ip),
    .gateway_ip(gateway_ip),
    .subnet_mask(subnet_mask),
    .clear_arp_cache(clear_arp_cache)
);

/*
 * UDP interface
 */
udp #(
    .CHECKSUM_GEN_ENABLE(UDP_CHECKSUM_GEN_ENABLE),
    .CHECKSUM_PAYLOAD_FIFO_DEPTH(UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH),
    .CHECKSUM_HEADER_FIFO_DEPTH(UDP_CHECKSUM_HEADER_FIFO_DEPTH)
)
udp_inst (
    .clk(clk),
    .rst(rst),
    // IP frame input
    .s_ip_hdr_valid(udp_rx_ip_hdr_valid),
    .s_ip_hdr_ready(udp_rx_ip_hdr_ready),
    .s_ip_eth_dest_mac(udp_rx_ip_eth_dest_mac),
    .s_ip_eth_src_mac(udp_rx_ip_eth_src_mac),
    .s_ip_eth_type(udp_rx_ip_eth_type),
    .s_ip_version(udp_rx_ip_version),
    .s_ip_ihl(udp_rx_ip_ihl),
    .s_ip_dscp(udp_rx_ip_dscp),
    .s_ip_ecn(udp_rx_ip_ecn),
    .s_ip_length(udp_rx_ip_length),
    .s_ip_identification(udp_rx_ip_identification),
    .s_ip_flags(udp_rx_ip_flags),
    .s_ip_fragment_offset(udp_rx_ip_fragment_offset),
    .s_ip_ttl(udp_rx_ip_ttl),
    .s_ip_protocol(udp_rx_ip_protocol),
    .s_ip_header_checksum(udp_rx_ip_header_checksum),
    .s_ip_source_ip(udp_rx_ip_source_ip),
    .s_ip_dest_ip(udp_rx_ip_dest_ip),
    .s_ip_payload_axis_tdata(udp_rx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tvalid(udp_rx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(udp_rx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(udp_rx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(udp_rx_ip_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(udp_tx_ip_hdr_valid),
    .m_ip_hdr_ready(udp_tx_ip_hdr_ready),
    .m_ip_eth_dest_mac(),
    .m_ip_eth_src_mac(),
    .m_ip_eth_type(),
    .m_ip_version(),
    .m_ip_ihl(),
    .m_ip_dscp(udp_tx_ip_dscp),
    .m_ip_ecn(udp_tx_ip_ecn),
    .m_ip_length(udp_tx_ip_length),
    .m_ip_identification(),
    .m_ip_flags(),
    .m_ip_fragment_offset(),
    .m_ip_ttl(udp_tx_ip_ttl),
    .m_ip_protocol(udp_tx_ip_protocol),
    .m_ip_header_checksum(),
    .m_ip_source_ip(udp_tx_ip_source_ip),
    .m_ip_dest_ip(udp_tx_ip_dest_ip),
    .m_ip_payload_axis_tdata(udp_tx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tvalid(udp_tx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(udp_tx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(udp_tx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(udp_tx_ip_payload_axis_tuser),
    // UDP frame input
    .s_udp_hdr_valid(s_udp_hdr_valid),
    .s_udp_hdr_ready(s_udp_hdr_ready),
    .s_udp_eth_dest_mac(48'd0),
    .s_udp_eth_src_mac(48'd0),
    .s_udp_eth_type(16'd0),
    .s_udp_ip_version(4'd0),
    .s_udp_ip_ihl(4'd0),
    .s_udp_ip_dscp(s_udp_ip_dscp),
    .s_udp_ip_ecn(s_udp_ip_ecn),
    .s_udp_ip_identification(16'd0),
    .s_udp_ip_flags(3'd0),
    .s_udp_ip_fragment_offset(13'd0),
    .s_udp_ip_ttl(s_udp_ip_ttl),
    .s_udp_ip_header_checksum(16'd0),
    .s_udp_ip_source_ip(s_udp_ip_source_ip),
    .s_udp_ip_dest_ip(s_udp_ip_dest_ip),
    .s_udp_source_port(s_udp_source_port),
    .s_udp_dest_port(s_udp_dest_port),
    .s_udp_length(s_udp_length),
    .s_udp_checksum(s_udp_checksum),
    .s_udp_payload_axis_tdata(s_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid(s_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(s_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast(s_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser(s_udp_payload_axis_tuser),
    // UDP frame output
    .m_udp_hdr_valid(m_udp_hdr_valid),
    .m_udp_hdr_ready(m_udp_hdr_ready),
    .m_udp_eth_dest_mac(m_udp_eth_dest_mac),
    .m_udp_eth_src_mac(m_udp_eth_src_mac),
    .m_udp_eth_type(m_udp_eth_type),
    .m_udp_ip_version(m_udp_ip_version),
    .m_udp_ip_ihl(m_udp_ip_ihl),
    .m_udp_ip_dscp(m_udp_ip_dscp),
    .m_udp_ip_ecn(m_udp_ip_ecn),
    .m_udp_ip_length(m_udp_ip_length),
    .m_udp_ip_identification(m_udp_ip_identification),
    .m_udp_ip_flags(m_udp_ip_flags),
    .m_udp_ip_fragment_offset(m_udp_ip_fragment_offset),
    .m_udp_ip_ttl(m_udp_ip_ttl),
    .m_udp_ip_protocol(m_udp_ip_protocol),
    .m_udp_ip_header_checksum(m_udp_ip_header_checksum),
    .m_udp_ip_source_ip(m_udp_ip_source_ip),
    .m_udp_ip_dest_ip(m_udp_ip_dest_ip),
    .m_udp_source_port(m_udp_source_port),
    .m_udp_dest_port(m_udp_dest_port),
    .m_udp_length(m_udp_length),
    .m_udp_checksum(m_udp_checksum),
    .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
    .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
    // Status
    .rx_busy(udp_rx_busy),
    .tx_busy(udp_tx_busy),
    .rx_error_header_early_termination(udp_rx_error_header_early_termination),
    .rx_error_payload_early_termination(udp_rx_error_payload_early_termination),
    .tx_error_payload_early_termination(udp_tx_error_payload_early_termination)
);

endmodule

`resetall

// Source snapshot: rtl/network/vendor/udp_ip_rx.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * UDP ethernet frame receiver (IP frame in, UDP frame out)
 */
module udp_ip_rx
(
    input  wire        clk,
    input  wire        rst,

    /*
     * IP frame input
     */
    input  wire        s_ip_hdr_valid,
    output wire        s_ip_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [3:0]  s_ip_version,
    input  wire [3:0]  s_ip_ihl,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [7:0]  s_ip_payload_axis_tdata,
    input  wire        s_ip_payload_axis_tvalid,
    output wire        s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,

    /*
     * UDP frame output
     */
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    output wire [7:0]  m_udp_payload_axis_tdata,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_header_early_termination,
    output wire        error_payload_early_termination
);

/*

UDP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets

 source port                 2 octets
 desination port             2 octets
 length                      2 octets
 checksum                    2 octets

 payload                     length octets

This module receives an IP frame with header fields in parallel and payload on
an AXI stream interface, decodes and strips the UDP header fields, then
produces the header fields in parallel along with the UDP payload in a
separate AXI stream.

*/

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_READ_HEADER = 3'd1,
    STATE_READ_PAYLOAD = 3'd2,
    STATE_READ_PAYLOAD_LAST = 3'd3,
    STATE_WAIT_LAST = 3'd4;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg store_ip_hdr;
reg store_udp_source_port_0;
reg store_udp_source_port_1;
reg store_udp_dest_port_0;
reg store_udp_dest_port_1;
reg store_udp_length_0;
reg store_udp_length_1;
reg store_udp_checksum_0;
reg store_udp_checksum_1;
reg store_last_word;

reg [2:0] hdr_ptr_reg = 3'd0, hdr_ptr_next;
reg [15:0] word_count_reg = 16'd0, word_count_next;

reg [7:0] last_word_data_reg = 8'd0;

reg m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;
reg [3:0] m_ip_version_reg = 4'd0;
reg [3:0] m_ip_ihl_reg = 4'd0;
reg [5:0] m_ip_dscp_reg = 6'd0;
reg [1:0] m_ip_ecn_reg = 2'd0;
reg [15:0] m_ip_length_reg = 16'd0;
reg [15:0] m_ip_identification_reg = 16'd0;
reg [2:0] m_ip_flags_reg = 3'd0;
reg [12:0] m_ip_fragment_offset_reg = 13'd0;
reg [7:0] m_ip_ttl_reg = 8'd0;
reg [7:0] m_ip_protocol_reg = 8'd0;
reg [15:0] m_ip_header_checksum_reg = 16'd0;
reg [31:0] m_ip_source_ip_reg = 32'd0;
reg [31:0] m_ip_dest_ip_reg = 32'd0;
reg [15:0] m_udp_source_port_reg = 16'd0;
reg [15:0] m_udp_dest_port_reg = 16'd0;
reg [15:0] m_udp_length_reg = 16'd0;
reg [15:0] m_udp_checksum_reg = 16'd0;

reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;
reg s_ip_payload_axis_tready_reg = 1'b0, s_ip_payload_axis_tready_next;

reg busy_reg = 1'b0;
reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;
reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

// internal datapath
reg [7:0] m_udp_payload_axis_tdata_int;
reg       m_udp_payload_axis_tvalid_int;
reg       m_udp_payload_axis_tready_int_reg = 1'b0;
reg       m_udp_payload_axis_tlast_int;
reg       m_udp_payload_axis_tuser_int;
wire      m_udp_payload_axis_tready_int_early;

assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
assign s_ip_payload_axis_tready = s_ip_payload_axis_tready_reg;

assign m_udp_hdr_valid = m_udp_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_ip_version = m_ip_version_reg;
assign m_ip_ihl = m_ip_ihl_reg;
assign m_ip_dscp = m_ip_dscp_reg;
assign m_ip_ecn = m_ip_ecn_reg;
assign m_ip_length = m_ip_length_reg;
assign m_ip_identification = m_ip_identification_reg;
assign m_ip_flags = m_ip_flags_reg;
assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
assign m_ip_ttl = m_ip_ttl_reg;
assign m_ip_protocol = m_ip_protocol_reg;
assign m_ip_header_checksum = m_ip_header_checksum_reg;
assign m_ip_source_ip = m_ip_source_ip_reg;
assign m_ip_dest_ip = m_ip_dest_ip_reg;
assign m_udp_source_port = m_udp_source_port_reg;
assign m_udp_dest_port = m_udp_dest_port_reg;
assign m_udp_length = m_udp_length_reg;
assign m_udp_checksum = m_udp_checksum_reg;

assign busy = busy_reg;
assign error_header_early_termination = error_header_early_termination_reg;
assign error_payload_early_termination = error_payload_early_termination_reg;

always @* begin
    state_next = STATE_IDLE;

    s_ip_hdr_ready_next = 1'b0;
    s_ip_payload_axis_tready_next = 1'b0;

    store_ip_hdr = 1'b0;
    store_udp_source_port_0 = 1'b0;
    store_udp_source_port_1 = 1'b0;
    store_udp_dest_port_0 = 1'b0;
    store_udp_dest_port_1 = 1'b0;
    store_udp_length_0 = 1'b0;
    store_udp_length_1 = 1'b0;
    store_udp_checksum_0 = 1'b0;
    store_udp_checksum_1 = 1'b0;

    store_last_word = 1'b0;

    hdr_ptr_next = hdr_ptr_reg;
    word_count_next = word_count_reg;

    m_udp_hdr_valid_next = m_udp_hdr_valid_reg && !m_udp_hdr_ready;

    error_header_early_termination_next = 1'b0;
    error_payload_early_termination_next = 1'b0;

    m_udp_payload_axis_tdata_int = 8'd0;
    m_udp_payload_axis_tvalid_int = 1'b0;
    m_udp_payload_axis_tlast_int = 1'b0;
    m_udp_payload_axis_tuser_int = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - wait for header
            hdr_ptr_next = 3'd0;
            s_ip_hdr_ready_next = !m_udp_hdr_valid_next;

            if (s_ip_hdr_ready && s_ip_hdr_valid) begin
                s_ip_hdr_ready_next = 1'b0;
                s_ip_payload_axis_tready_next = 1'b1;
                store_ip_hdr = 1'b1;
                state_next = STATE_READ_HEADER;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_READ_HEADER: begin
            // read header state
            s_ip_payload_axis_tready_next = 1'b1;
            word_count_next = m_udp_length_reg - 16'd8;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                // word transfer in - store it
                hdr_ptr_next = hdr_ptr_reg + 3'd1;
                state_next = STATE_READ_HEADER;

                case (hdr_ptr_reg)
                    3'h0: store_udp_source_port_1 = 1'b1;
                    3'h1: store_udp_source_port_0 = 1'b1;
                    3'h2: store_udp_dest_port_1 = 1'b1;
                    3'h3: store_udp_dest_port_0 = 1'b1;
                    3'h4: store_udp_length_1 = 1'b1;
                    3'h5: store_udp_length_0 = 1'b1;
                    3'h6: store_udp_checksum_1 = 1'b1;
                    3'h7: begin
                        store_udp_checksum_0 = 1'b1;
                        m_udp_hdr_valid_next = 1'b1;
                        s_ip_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
                        state_next = STATE_READ_PAYLOAD;
                    end
                endcase

                if (s_ip_payload_axis_tlast) begin
                    error_header_early_termination_next = 1'b1;
                    m_udp_hdr_valid_next = 1'b0;
                    s_ip_hdr_ready_next = !m_udp_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end

            end else begin
                state_next = STATE_READ_HEADER;
            end
        end
        STATE_READ_PAYLOAD: begin
            // read payload
            s_ip_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

            m_udp_payload_axis_tdata_int = s_ip_payload_axis_tdata;
            m_udp_payload_axis_tlast_int = s_ip_payload_axis_tlast;
            m_udp_payload_axis_tuser_int = s_ip_payload_axis_tuser;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                // word transfer through
                word_count_next = word_count_reg - 16'd1;
                m_udp_payload_axis_tvalid_int = 1'b1;
                if (s_ip_payload_axis_tlast) begin
                    if (word_count_reg != 16'd1) begin
                        // end of frame, but length does not match
                        m_udp_payload_axis_tuser_int = 1'b1;
                        error_payload_early_termination_next = 1'b1;
                    end
                    s_ip_hdr_ready_next = !m_udp_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    if (word_count_reg == 16'd1) begin
                        store_last_word = 1'b1;
                        m_udp_payload_axis_tvalid_int = 1'b0;
                        state_next = STATE_READ_PAYLOAD_LAST;
                    end else begin
                        state_next = STATE_READ_PAYLOAD;
                    end
                end
            end else begin
                state_next = STATE_READ_PAYLOAD;
            end
        end
        STATE_READ_PAYLOAD_LAST: begin
            // read and discard until end of frame
            s_ip_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

            m_udp_payload_axis_tdata_int = last_word_data_reg;
            m_udp_payload_axis_tlast_int = s_ip_payload_axis_tlast;
            m_udp_payload_axis_tuser_int = s_ip_payload_axis_tuser;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                if (s_ip_payload_axis_tlast) begin
                    s_ip_hdr_ready_next = !m_udp_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    m_udp_payload_axis_tvalid_int = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_READ_PAYLOAD_LAST;
                end
            end else begin
                state_next = STATE_READ_PAYLOAD_LAST;
            end
        end
        STATE_WAIT_LAST: begin
            // wait for end of frame; read and discard
            s_ip_payload_axis_tready_next = 1'b1;

            if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
                if (s_ip_payload_axis_tlast) begin
                    s_ip_hdr_ready_next = !m_udp_hdr_valid_next;
                    s_ip_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_WAIT_LAST;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_ip_hdr_ready_reg <= 1'b0;
        s_ip_payload_axis_tready_reg <= 1'b0;
        m_udp_hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_header_early_termination_reg <= 1'b0;
        error_payload_early_termination_reg <= 1'b0;
    end else begin
        state_reg <= state_next;


        s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;
        s_ip_payload_axis_tready_reg <= s_ip_payload_axis_tready_next;

        m_udp_hdr_valid_reg <= m_udp_hdr_valid_next;

        error_header_early_termination_reg <= error_header_early_termination_next;
        error_payload_early_termination_reg <= error_payload_early_termination_next;

        busy_reg <= state_next != STATE_IDLE;
    end

    hdr_ptr_reg <= hdr_ptr_next;
    word_count_reg <= word_count_next;

    // datapath
    if (store_ip_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
        m_ip_version_reg <= s_ip_version;
        m_ip_ihl_reg <= s_ip_ihl;
        m_ip_dscp_reg <= s_ip_dscp;
        m_ip_ecn_reg <= s_ip_ecn;
        m_ip_length_reg <= s_ip_length;
        m_ip_identification_reg <= s_ip_identification;
        m_ip_flags_reg <= s_ip_flags;
        m_ip_fragment_offset_reg <= s_ip_fragment_offset;
        m_ip_ttl_reg <= s_ip_ttl;
        m_ip_protocol_reg <= s_ip_protocol;
        m_ip_header_checksum_reg <= s_ip_header_checksum;
        m_ip_source_ip_reg <= s_ip_source_ip;
        m_ip_dest_ip_reg <= s_ip_dest_ip;
    end

    if (store_last_word) begin
        last_word_data_reg <= m_udp_payload_axis_tdata_int;
    end

    if (store_udp_source_port_0) m_udp_source_port_reg[ 7: 0] <= s_ip_payload_axis_tdata;
    if (store_udp_source_port_1) m_udp_source_port_reg[15: 8] <= s_ip_payload_axis_tdata;
    if (store_udp_dest_port_0) m_udp_dest_port_reg[ 7: 0] <= s_ip_payload_axis_tdata;
    if (store_udp_dest_port_1) m_udp_dest_port_reg[15: 8] <= s_ip_payload_axis_tdata;
    if (store_udp_length_0) m_udp_length_reg[ 7: 0] <= s_ip_payload_axis_tdata;
    if (store_udp_length_1) m_udp_length_reg[15: 8] <= s_ip_payload_axis_tdata;
    if (store_udp_checksum_0) m_udp_checksum_reg[ 7: 0] <= s_ip_payload_axis_tdata;
    if (store_udp_checksum_1) m_udp_checksum_reg[15: 8] <= s_ip_payload_axis_tdata;
end

// output datapath logic
reg [7:0] m_udp_payload_axis_tdata_reg = 8'd0;
reg       m_udp_payload_axis_tvalid_reg = 1'b0, m_udp_payload_axis_tvalid_next;
reg       m_udp_payload_axis_tlast_reg = 1'b0;
reg       m_udp_payload_axis_tuser_reg = 1'b0;

reg [7:0] temp_m_udp_payload_axis_tdata_reg = 8'd0;
reg       temp_m_udp_payload_axis_tvalid_reg = 1'b0, temp_m_udp_payload_axis_tvalid_next;
reg       temp_m_udp_payload_axis_tlast_reg = 1'b0;
reg       temp_m_udp_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_udp_payload_int_to_output;
reg store_udp_payload_int_to_temp;
reg store_udp_payload_axis_temp_to_output;

assign m_udp_payload_axis_tdata = m_udp_payload_axis_tdata_reg;
assign m_udp_payload_axis_tvalid = m_udp_payload_axis_tvalid_reg;
assign m_udp_payload_axis_tlast = m_udp_payload_axis_tlast_reg;
assign m_udp_payload_axis_tuser = m_udp_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_udp_payload_axis_tready_int_early = m_udp_payload_axis_tready || (!temp_m_udp_payload_axis_tvalid_reg && !m_udp_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_reg;
    temp_m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;

    store_udp_payload_int_to_output = 1'b0;
    store_udp_payload_int_to_temp = 1'b0;
    store_udp_payload_axis_temp_to_output = 1'b0;
    
    if (m_udp_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_udp_payload_axis_tready || !m_udp_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
            store_udp_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
            store_udp_payload_int_to_temp = 1'b1;
        end
    end else if (m_udp_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;
        temp_m_udp_payload_axis_tvalid_next = 1'b0;
        store_udp_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_udp_payload_axis_tvalid_reg <= m_udp_payload_axis_tvalid_next;
    m_udp_payload_axis_tready_int_reg <= m_udp_payload_axis_tready_int_early;
    temp_m_udp_payload_axis_tvalid_reg <= temp_m_udp_payload_axis_tvalid_next;

    // datapath
    if (store_udp_payload_int_to_output) begin
        m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
        m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
        m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
    end else if (store_udp_payload_axis_temp_to_output) begin
        m_udp_payload_axis_tdata_reg <= temp_m_udp_payload_axis_tdata_reg;
        m_udp_payload_axis_tlast_reg <= temp_m_udp_payload_axis_tlast_reg;
        m_udp_payload_axis_tuser_reg <= temp_m_udp_payload_axis_tuser_reg;
    end

    if (store_udp_payload_int_to_temp) begin
        temp_m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
        temp_m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
        temp_m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
    end

    if (rst) begin
        m_udp_payload_axis_tvalid_reg <= 1'b0;
        m_udp_payload_axis_tready_int_reg <= 1'b0;
        temp_m_udp_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall

// Source snapshot: rtl/network/vendor/udp_ip_tx.v
/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * UDP ethernet frame transmitter (UDP frame in, IP frame out)
 */
module udp_ip_tx
(
    input  wire        clk,
    input  wire        rst,

    /*
     * UDP frame input
     */
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [3:0]  s_ip_version,
    input  wire [3:0]  s_ip_ihl,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [15:0] s_udp_length,
    input  wire [15:0] s_udp_checksum,
    input  wire [7:0]  s_udp_payload_axis_tdata,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,

    /*
     * IP frame output
     */
    output wire        m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [3:0]  m_ip_version,
    output wire [3:0]  m_ip_ihl,
    output wire [5:0]  m_ip_dscp,
    output wire [1:0]  m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [7:0]  m_ip_ttl,
    output wire [7:0]  m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [7:0]  m_ip_payload_axis_tdata,
    output wire        m_ip_payload_axis_tvalid,
    input  wire        m_ip_payload_axis_tready,
    output wire        m_ip_payload_axis_tlast,
    output wire        m_ip_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_payload_early_termination
);

/*

UDP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets

 source port                 2 octets
 desination port             2 octets
 length                      2 octets
 checksum                    2 octets

 payload                     length octets

This module receives a UDP frame with header fields in parallel along with the
payload in an AXI stream, combines the header with the payload, passes through
the IP headers, and transmits the complete IP payload on an AXI interface.

*/

localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_WRITE_HEADER = 3'd1,
    STATE_WRITE_PAYLOAD = 3'd2,
    STATE_WRITE_PAYLOAD_LAST = 3'd3,
    STATE_WAIT_LAST = 3'd4;

reg [2:0] state_reg = STATE_IDLE, state_next;

// datapath control signals
reg store_udp_hdr;
reg store_last_word;

reg [2:0] hdr_ptr_reg = 3'd0, hdr_ptr_next;
reg [15:0] word_count_reg = 16'd0, word_count_next;

reg [7:0] last_word_data_reg = 8'd0;

reg [15:0] udp_source_port_reg = 16'd0;
reg [15:0] udp_dest_port_reg = 16'd0;
reg [15:0] udp_length_reg = 16'd0;
reg [15:0] udp_checksum_reg = 16'd0;

reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

reg m_ip_hdr_valid_reg = 1'b0, m_ip_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0;
reg [47:0] m_eth_src_mac_reg = 48'd0;
reg [15:0] m_eth_type_reg = 16'd0;
reg [3:0] m_ip_version_reg = 4'd0;
reg [3:0] m_ip_ihl_reg = 4'd0;
reg [5:0] m_ip_dscp_reg = 6'd0;
reg [1:0] m_ip_ecn_reg = 2'd0;
reg [15:0] m_ip_length_reg = 16'd0;
reg [15:0] m_ip_identification_reg = 16'd0;
reg [2:0] m_ip_flags_reg = 3'd0;
reg [12:0] m_ip_fragment_offset_reg = 13'd0;
reg [7:0] m_ip_ttl_reg = 8'd0;
reg [7:0] m_ip_protocol_reg = 8'd0;
reg [15:0] m_ip_header_checksum_reg = 16'd0;
reg [31:0] m_ip_source_ip_reg = 32'd0;
reg [31:0] m_ip_dest_ip_reg = 32'd0;

reg busy_reg = 1'b0;
reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

// internal datapath
reg [7:0] m_ip_payload_axis_tdata_int;
reg       m_ip_payload_axis_tvalid_int;
reg       m_ip_payload_axis_tready_int_reg = 1'b0;
reg       m_ip_payload_axis_tlast_int;
reg       m_ip_payload_axis_tuser_int;
wire      m_ip_payload_axis_tready_int_early;

assign s_udp_hdr_ready = s_udp_hdr_ready_reg;
assign s_udp_payload_axis_tready = s_udp_payload_axis_tready_reg;

assign m_ip_hdr_valid = m_ip_hdr_valid_reg;
assign m_eth_dest_mac = m_eth_dest_mac_reg;
assign m_eth_src_mac = m_eth_src_mac_reg;
assign m_eth_type = m_eth_type_reg;
assign m_ip_version = m_ip_version_reg;
assign m_ip_ihl = m_ip_ihl_reg;
assign m_ip_dscp = m_ip_dscp_reg;
assign m_ip_ecn = m_ip_ecn_reg;
assign m_ip_length = m_ip_length_reg;
assign m_ip_identification = m_ip_identification_reg;
assign m_ip_flags = m_ip_flags_reg;
assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
assign m_ip_ttl = m_ip_ttl_reg;
assign m_ip_protocol = m_ip_protocol_reg;
assign m_ip_header_checksum = m_ip_header_checksum_reg;
assign m_ip_source_ip = m_ip_source_ip_reg;
assign m_ip_dest_ip = m_ip_dest_ip_reg;

assign busy = busy_reg;
assign error_payload_early_termination = error_payload_early_termination_reg;

always @* begin
    state_next = STATE_IDLE;

    s_udp_hdr_ready_next = 1'b0;
    s_udp_payload_axis_tready_next = 1'b0;

    store_udp_hdr = 1'b0;

    store_last_word = 1'b0;

    hdr_ptr_next = hdr_ptr_reg;
    word_count_next = word_count_reg;

    m_ip_hdr_valid_next = m_ip_hdr_valid_reg && !m_ip_hdr_ready;

    error_payload_early_termination_next = 1'b0;

    m_ip_payload_axis_tdata_int = 8'd0;
    m_ip_payload_axis_tvalid_int = 1'b0;
    m_ip_payload_axis_tlast_int = 1'b0;
    m_ip_payload_axis_tuser_int = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - wait for data
            hdr_ptr_next = 3'd0;
            s_udp_hdr_ready_next = !m_ip_hdr_valid_next;

            if (s_udp_hdr_ready && s_udp_hdr_valid) begin
                store_udp_hdr = 1'b1;
                s_udp_hdr_ready_next = 1'b0;
                m_ip_hdr_valid_next = 1'b1;
                if (m_ip_payload_axis_tready_int_reg) begin
                    m_ip_payload_axis_tvalid_int = 1'b1;
                    m_ip_payload_axis_tdata_int = s_udp_source_port[15: 8];
                    hdr_ptr_next = 3'd1;
                end
                state_next = STATE_WRITE_HEADER;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_WRITE_HEADER: begin
            // write header state
            word_count_next = udp_length_reg - 16'd8;

            if (m_ip_payload_axis_tready_int_reg) begin
                // word transfer out
                hdr_ptr_next = hdr_ptr_reg + 3'd1;
                m_ip_payload_axis_tvalid_int = 1'b1;
                state_next = STATE_WRITE_HEADER;
                case (hdr_ptr_reg)
                    3'h0: m_ip_payload_axis_tdata_int = udp_source_port_reg[15: 8];
                    3'h1: m_ip_payload_axis_tdata_int = udp_source_port_reg[ 7: 0];
                    3'h2: m_ip_payload_axis_tdata_int = udp_dest_port_reg[15: 8];
                    3'h3: m_ip_payload_axis_tdata_int = udp_dest_port_reg[ 7: 0];
                    3'h4: m_ip_payload_axis_tdata_int = udp_length_reg[15: 8];
                    3'h5: m_ip_payload_axis_tdata_int = udp_length_reg[ 7: 0];
                    3'h6: m_ip_payload_axis_tdata_int = udp_checksum_reg[15: 8];
                    3'h7: begin
                        m_ip_payload_axis_tdata_int = udp_checksum_reg[ 7: 0];
                        s_udp_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;
                        state_next = STATE_WRITE_PAYLOAD;
                    end
                endcase
            end else begin
                state_next = STATE_WRITE_HEADER;
            end
        end
        STATE_WRITE_PAYLOAD: begin
            // write payload
            s_udp_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;

            m_ip_payload_axis_tdata_int = s_udp_payload_axis_tdata;
            m_ip_payload_axis_tlast_int = s_udp_payload_axis_tlast;
            m_ip_payload_axis_tuser_int = s_udp_payload_axis_tuser;

            if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
                // word transfer through
                word_count_next = word_count_reg - 16'd1;
                m_ip_payload_axis_tvalid_int = 1'b1;
                if (s_udp_payload_axis_tlast) begin
                    if (word_count_reg != 16'd1) begin
                        // end of frame, but length does not match
                        m_ip_payload_axis_tuser_int = 1'b1;
                        error_payload_early_termination_next = 1'b1;
                    end
                    s_udp_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_udp_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    if (word_count_reg == 16'd1) begin
                        store_last_word = 1'b1;
                        m_ip_payload_axis_tvalid_int = 1'b0;
                        state_next = STATE_WRITE_PAYLOAD_LAST;
                    end else begin
                        state_next = STATE_WRITE_PAYLOAD;
                    end
                end
            end else begin
                state_next = STATE_WRITE_PAYLOAD;
            end
        end
        STATE_WRITE_PAYLOAD_LAST: begin
            // read and discard until end of frame
            s_udp_payload_axis_tready_next = m_ip_payload_axis_tready_int_early;

            m_ip_payload_axis_tdata_int = last_word_data_reg;
            m_ip_payload_axis_tlast_int = s_udp_payload_axis_tlast;
            m_ip_payload_axis_tuser_int = s_udp_payload_axis_tuser;

            if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
                if (s_udp_payload_axis_tlast) begin
                    s_udp_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_udp_payload_axis_tready_next = 1'b0;
                    m_ip_payload_axis_tvalid_int = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WRITE_PAYLOAD_LAST;
                end
            end else begin
                state_next = STATE_WRITE_PAYLOAD_LAST;
            end
        end
        STATE_WAIT_LAST: begin
            // wait for end of frame; read and discard
            s_udp_payload_axis_tready_next = 1'b1;

            if (s_udp_payload_axis_tvalid) begin
                if (s_udp_payload_axis_tlast) begin
                    s_udp_hdr_ready_next = !m_ip_hdr_valid_next;
                    s_udp_payload_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_WAIT_LAST;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_udp_hdr_ready_reg <= 1'b0;
        s_udp_payload_axis_tready_reg <= 1'b0;
        m_ip_hdr_valid_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_payload_early_termination_reg <= 1'b0;
    end else begin
        state_reg <= state_next;

        s_udp_hdr_ready_reg <= s_udp_hdr_ready_next;
        s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

        m_ip_hdr_valid_reg <= m_ip_hdr_valid_next;

        busy_reg <= state_next != STATE_IDLE;

        error_payload_early_termination_reg <= error_payload_early_termination_next;
    end

    hdr_ptr_reg <= hdr_ptr_next;
    word_count_reg <= word_count_next;

    // datapath
    if (store_udp_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
        m_ip_version_reg <= s_ip_version;
        m_ip_ihl_reg <= s_ip_ihl;
        m_ip_dscp_reg <= s_ip_dscp;
        m_ip_ecn_reg <= s_ip_ecn;
        m_ip_length_reg <= s_udp_length + 20;
        m_ip_identification_reg <= s_ip_identification;
        m_ip_flags_reg <= s_ip_flags;
        m_ip_fragment_offset_reg <= s_ip_fragment_offset;
        m_ip_ttl_reg <= s_ip_ttl;
        m_ip_protocol_reg <= s_ip_protocol;
        m_ip_header_checksum_reg <= s_ip_header_checksum;
        m_ip_source_ip_reg <= s_ip_source_ip;
        m_ip_dest_ip_reg <= s_ip_dest_ip;
        udp_source_port_reg <= s_udp_source_port;
        udp_dest_port_reg <= s_udp_dest_port;
        udp_length_reg <= s_udp_length;
        udp_checksum_reg <= s_udp_checksum;
    end

    if (store_last_word) begin
        last_word_data_reg <= m_ip_payload_axis_tdata_int;
    end
end

// output datapath logic
reg [7:0] m_ip_payload_axis_tdata_reg = 8'd0;
reg       m_ip_payload_axis_tvalid_reg = 1'b0, m_ip_payload_axis_tvalid_next;
reg       m_ip_payload_axis_tlast_reg = 1'b0;
reg       m_ip_payload_axis_tuser_reg = 1'b0;

reg [7:0] temp_m_ip_payload_axis_tdata_reg = 8'd0;
reg       temp_m_ip_payload_axis_tvalid_reg = 1'b0, temp_m_ip_payload_axis_tvalid_next;
reg       temp_m_ip_payload_axis_tlast_reg = 1'b0;
reg       temp_m_ip_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_ip_payload_int_to_output;
reg store_ip_payload_int_to_temp;
reg store_ip_payload_axis_temp_to_output;

assign m_ip_payload_axis_tdata = m_ip_payload_axis_tdata_reg;
assign m_ip_payload_axis_tvalid = m_ip_payload_axis_tvalid_reg;
assign m_ip_payload_axis_tlast = m_ip_payload_axis_tlast_reg;
assign m_ip_payload_axis_tuser = m_ip_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_ip_payload_axis_tready_int_early = m_ip_payload_axis_tready || (!temp_m_ip_payload_axis_tvalid_reg && !m_ip_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_reg;
    temp_m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;

    store_ip_payload_int_to_output = 1'b0;
    store_ip_payload_int_to_temp = 1'b0;
    store_ip_payload_axis_temp_to_output = 1'b0;
    
    if (m_ip_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_ip_payload_axis_tready || !m_ip_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_temp = 1'b1;
        end
    end else if (m_ip_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;
        temp_m_ip_payload_axis_tvalid_next = 1'b0;
        store_ip_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_ip_payload_axis_tvalid_reg <= m_ip_payload_axis_tvalid_next;
    m_ip_payload_axis_tready_int_reg <= m_ip_payload_axis_tready_int_early;
    temp_m_ip_payload_axis_tvalid_reg <= temp_m_ip_payload_axis_tvalid_next;

    // datapath
    if (store_ip_payload_int_to_output) begin
        m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end else if (store_ip_payload_axis_temp_to_output) begin
        m_ip_payload_axis_tdata_reg <= temp_m_ip_payload_axis_tdata_reg;
        m_ip_payload_axis_tlast_reg <= temp_m_ip_payload_axis_tlast_reg;
        m_ip_payload_axis_tuser_reg <= temp_m_ip_payload_axis_tuser_reg;
    end

    if (store_ip_payload_int_to_temp) begin
        temp_m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        temp_m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        temp_m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end

    if (rst) begin
        m_ip_payload_axis_tvalid_reg <= 1'b0;
        m_ip_payload_axis_tready_int_reg <= 1'b0;
        temp_m_ip_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
