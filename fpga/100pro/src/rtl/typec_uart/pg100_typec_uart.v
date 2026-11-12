// MES2L676-100HP Type-C UART (CP2102), 27 MHz / 115200 8N1.
// Test build owner of B24/C24: byte echo plus a 64-byte status frame.
// Async status inputs are synchronized before use; the frame is latched so a
// status change cannot tear a transmission.
module pg100_typec_uart #(
 parameter DIVISOR=234,
 parameter STATUS_PERIOD=27000000,
 parameter QUIET_CYCLES=13500000
)(
 input wire clk27,rst_n,
 input wire uart_rxd,
 output wire uart_txd,
 input wire pll_lock,phy_pll_lock,gpll_lock,rst_gpll_lock,ddrphy_cpd_lock,
 input wire ddr_init_done,ddr_init_fail,align_error,
 input wire hdmi_init_done,hdmi_init_failed,pixel_clock_good,
 input wire[15:0] pclk_edges,
 input wire[31:0] pclk_losses,
 input wire[2:0] i2c_failure,
 input wire[31:0] i2c_retries,
 input wire link_gigabit,phy_present,
 input wire[31:0] ddr_recoveries,
 input wire[2:0] ddr_recovery_reason,
 input wire[15:0] native_edges,
 input wire run_enable,rgb_confirmed,export_enable,
 input wire[31:0] bad_commands,accepted_commands
);
 // Three-stage synchronizers for status bits that originate in DDR/PHY
 // clock domains. The clk27 status inputs are used directly.
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0] pll_lock_meta,phy_pll_lock_meta;
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0] gpll_lock_meta,rst_gpll_lock_meta;
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0] ddrphy_cpd_lock_meta,ddr_init_done_meta;
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0] ddr_init_fail_meta,align_error_meta;
 (* async_reg="true",syn_preserve=1,syn_allow_retiming=0 *)reg[2:0] link_gigabit_meta,phy_present_meta;
 always @(posedge clk27 or negedge rst_n)begin
  if(!rst_n)begin
   pll_lock_meta<=0;phy_pll_lock_meta<=0;gpll_lock_meta<=0;rst_gpll_lock_meta<=0;
   ddrphy_cpd_lock_meta<=0;ddr_init_done_meta<=0;ddr_init_fail_meta<=0;align_error_meta<=0;
   link_gigabit_meta<=0;phy_present_meta<=0;
  end else begin
   pll_lock_meta<={pll_lock_meta[1:0],pll_lock};
   phy_pll_lock_meta<={phy_pll_lock_meta[1:0],phy_pll_lock};
   gpll_lock_meta<={gpll_lock_meta[1:0],gpll_lock};
   rst_gpll_lock_meta<={rst_gpll_lock_meta[1:0],rst_gpll_lock};
   ddrphy_cpd_lock_meta<={ddrphy_cpd_lock_meta[1:0],ddrphy_cpd_lock};
   ddr_init_done_meta<={ddr_init_done_meta[1:0],ddr_init_done};
   ddr_init_fail_meta<={ddr_init_fail_meta[1:0],ddr_init_fail};
   align_error_meta<={align_error_meta[1:0],align_error};
   link_gigabit_meta<={link_gigabit_meta[1:0],link_gigabit};
   phy_present_meta<={phy_present_meta[1:0],phy_present};
  end
 end
 wire pll_lock_s=pll_lock_meta[2],phy_pll_lock_s=phy_pll_lock_meta[2];
 wire gpll_lock_s=gpll_lock_meta[2],rst_gpll_lock_s=rst_gpll_lock_meta[2];
 wire ddrphy_cpd_lock_s=ddrphy_cpd_lock_meta[2],ddr_init_done_s=ddr_init_done_meta[2];
 wire ddr_init_fail_s=ddr_init_fail_meta[2],align_error_s=align_error_meta[2];
 wire link_gigabit_s=link_gigabit_meta[2],phy_present_s=phy_present_meta[2];

 wire[7:0] rx_data;wire rx_valid,rx_error;
 typec_uart_rx_8n1 #(.DIVISOR(DIVISOR)) rx(.clk(clk27),.rst_n(rst_n),.rxd(uart_rxd),
  .data(rx_data),.valid(rx_valid),.framing_error(rx_error));

 // Echo FIFO: accepted RX bytes wait here while a status frame is on the wire.
 localparam FIFO_AW=7;
 reg[7:0] fifo_mem[0:(1<<FIFO_AW)-1];
 reg[FIFO_AW-1:0] fifo_wr,fifo_rd;
 reg[FIFO_AW:0] fifo_count;
 reg[31:0] echo_bytes,echo_overflow,rx_error_count;
 wire fifo_empty=(fifo_count==0);
 wire fifo_full=(fifo_count==(1<<FIFO_AW));
 wire[7:0] fifo_data=fifo_mem[fifo_rd];
 wire fifo_push=rx_valid&&!fifo_full;
 wire tx_ready;
 wire status_active;
 wire fifo_pop=!status_active&&!fifo_empty&&tx_ready;
 always @(posedge clk27 or negedge rst_n)begin
  if(!rst_n)begin
   fifo_wr<=0;fifo_rd<=0;fifo_count<=0;echo_bytes<=0;echo_overflow<=0;rx_error_count<=0;
  end else begin
   if(fifo_push)fifo_mem[fifo_wr]<=rx_data;
   if(fifo_push)fifo_wr<=fifo_wr+1'b1;
   if(fifo_pop)fifo_rd<=fifo_rd+1'b1;
   if(fifo_push&&!fifo_pop)fifo_count<=fifo_count+1'b1;
   else if(!fifo_push&&fifo_pop)fifo_count<=fifo_count-1'b1;
   if(fifo_pop&&echo_bytes!=32'hffffffff)echo_bytes<=echo_bytes+1'b1;
   if(rx_valid&&fifo_full&&echo_overflow!=32'hffffffff)echo_overflow<=echo_overflow+1'b1;
   if(rx_error&&rx_error_count!=32'hffffffff)rx_error_count<=rx_error_count+1'b1;
  end
 end

 reg[31:0] uptime,period_ticks,quiet_ticks;
 reg status_active_r;
 wire period_tick=(period_ticks==STATUS_PERIOD-1);
 always @(posedge clk27 or negedge rst_n)begin
  if(!rst_n)begin uptime<=0;period_ticks<=0;quiet_ticks<=0;end
  else begin
   uptime<=uptime+1'b1;
   if(period_tick)period_ticks<=0;else period_ticks<=period_ticks+1'b1;
   if(rx_valid)quiet_ticks<=0;
   else if(quiet_ticks<QUIET_CYCLES)quiet_ticks<=quiet_ticks+1'b1;
  end
 end
 assign status_active=status_active_r;

 reg[31:0] snap_flags,snap_pclk_losses,snap_i2c_retries,snap_ddr_recoveries;
 reg[31:0] snap_bad_commands,snap_accepted_commands,snap_echo_bytes,snap_echo_overflow;
 reg[31:0] snap_rx_errors,snap_seq,snap_uptime;
 reg[15:0] snap_pclk_edges,snap_native_edges;
 reg[2:0] snap_i2c_failure,snap_ddr_reason;
 reg[31:0] crc,status_seq;

 function[7:0] status_byte;
  input[5:0] index;
  begin
   case(index)
    6'd0:status_byte=8'h54;
    6'd1:status_byte=8'h59;
    6'd2:status_byte=8'h50;
    6'd3:status_byte=8'h43;
    6'd4:status_byte=8'h01;
    6'd5:status_byte=8'h01;
    6'd6:status_byte=8'h00;
    6'd7:status_byte=8'h40;
    6'd8:status_byte=snap_seq[31:24];
    6'd9:status_byte=snap_seq[23:16];
    6'd10:status_byte=snap_seq[15:8];
    6'd11:status_byte=snap_seq[7:0];
    6'd12:status_byte=snap_uptime[31:24];
    6'd13:status_byte=snap_uptime[23:16];
    6'd14:status_byte=snap_uptime[15:8];
    6'd15:status_byte=snap_uptime[7:0];
    6'd16:status_byte=snap_flags[31:24];
    6'd17:status_byte=snap_flags[23:16];
    6'd18:status_byte=snap_flags[15:8];
    6'd19:status_byte=snap_flags[7:0];
    6'd20:status_byte=snap_pclk_edges[15:8];
    6'd21:status_byte=snap_pclk_edges[7:0];
    6'd22:status_byte={2'b0,snap_ddr_reason,snap_i2c_failure};
    6'd23:status_byte=8'h00;
    6'd24:status_byte=snap_pclk_losses[31:24];
    6'd25:status_byte=snap_pclk_losses[23:16];
    6'd26:status_byte=snap_pclk_losses[15:8];
    6'd27:status_byte=snap_pclk_losses[7:0];
    6'd28:status_byte=snap_i2c_retries[31:24];
    6'd29:status_byte=snap_i2c_retries[23:16];
    6'd30:status_byte=snap_i2c_retries[15:8];
    6'd31:status_byte=snap_i2c_retries[7:0];
    6'd32:status_byte=snap_ddr_recoveries[31:24];
    6'd33:status_byte=snap_ddr_recoveries[23:16];
    6'd34:status_byte=snap_ddr_recoveries[15:8];
    6'd35:status_byte=snap_ddr_recoveries[7:0];
    6'd36:status_byte=snap_native_edges[15:8];
    6'd37:status_byte=snap_native_edges[7:0];
    6'd38:status_byte=8'h00;
    6'd39:status_byte=8'h00;
    6'd40:status_byte=snap_bad_commands[31:24];
    6'd41:status_byte=snap_bad_commands[23:16];
    6'd42:status_byte=snap_bad_commands[15:8];
    6'd43:status_byte=snap_bad_commands[7:0];
    6'd44:status_byte=snap_accepted_commands[31:24];
    6'd45:status_byte=snap_accepted_commands[23:16];
    6'd46:status_byte=snap_accepted_commands[15:8];
    6'd47:status_byte=snap_accepted_commands[7:0];
    6'd48:status_byte=snap_echo_bytes[31:24];
    6'd49:status_byte=snap_echo_bytes[23:16];
    6'd50:status_byte=snap_echo_bytes[15:8];
    6'd51:status_byte=snap_echo_bytes[7:0];
    6'd52:status_byte=snap_echo_overflow[31:24];
    6'd53:status_byte=snap_echo_overflow[23:16];
    6'd54:status_byte=snap_echo_overflow[15:8];
    6'd55:status_byte=snap_echo_overflow[7:0];
    6'd56:status_byte=snap_rx_errors[31:24];
    6'd57:status_byte=snap_rx_errors[23:16];
    6'd58:status_byte=snap_rx_errors[15:8];
    6'd59:status_byte=snap_rx_errors[7:0];
    6'd60:status_byte=~crc[31:24];
    6'd61:status_byte=~crc[23:16];
    6'd62:status_byte=~crc[15:8];
    6'd63:status_byte=~crc[7:0];
    default:status_byte=8'h00;
   endcase
  end
 endfunction

 function[31:0] crc_byte;
  input[31:0] c;
  input[7:0] b;
  reg[31:0] v;
  integer k;
  begin
   v=c^b;
   for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;
   crc_byte=v;
  end
 endfunction

 localparam S_IDLE=0,S_SEND=1,S_CRC=2;
 reg[1:0] status_state;
 reg[5:0] status_index;
 reg[7:0] status_data;
 reg status_valid;
 wire start_status=period_tick&&status_state==S_IDLE&&fifo_empty&&tx_ready&&
  (quiet_ticks>=QUIET_CYCLES);
 always @(posedge clk27 or negedge rst_n)begin
  if(!rst_n)begin
   status_state<=S_IDLE;status_index<=0;status_data<=0;status_valid<=0;crc<=32'hffffffff;
   status_active_r<=0;snap_flags<=0;snap_pclk_edges<=0;snap_pclk_losses<=0;
   snap_i2c_failure<=0;snap_i2c_retries<=0;snap_ddr_recoveries<=0;snap_ddr_reason<=0;
   snap_native_edges<=0;snap_bad_commands<=0;snap_accepted_commands<=0;
   snap_echo_bytes<=0;snap_echo_overflow<=0;snap_rx_errors<=0;snap_seq<=0;snap_uptime<=0;
   status_seq<=0;
  end else begin
   case(status_state)
    S_IDLE:begin
     status_active_r<=0;status_valid<=0;
     if(start_status)begin
      status_active_r<=1;status_seq<=status_seq+1'b1;
      snap_seq<=status_seq;snap_uptime<=uptime;
      snap_flags<={14'b0,(rx_error_count!=0),(echo_overflow!=0),export_enable,rgb_confirmed,run_enable,
       phy_present_s,link_gigabit_s,pixel_clock_good,hdmi_init_failed,hdmi_init_done,
       align_error_s,ddr_init_fail_s,ddr_init_done_s,ddrphy_cpd_lock_s,
       rst_gpll_lock_s,gpll_lock_s,phy_pll_lock_s,pll_lock_s};
      snap_pclk_edges<=pclk_edges;snap_pclk_losses<=pclk_losses;
      snap_i2c_failure<=i2c_failure;snap_i2c_retries<=i2c_retries;
      snap_ddr_recoveries<=ddr_recoveries;snap_ddr_reason<=ddr_recovery_reason;
      snap_native_edges<=native_edges;snap_bad_commands<=bad_commands;
      snap_accepted_commands<=accepted_commands;snap_echo_bytes<=echo_bytes;
      snap_echo_overflow<=echo_overflow;snap_rx_errors<=rx_error_count;
      crc<=32'hffffffff;status_index<=0;status_data<=status_byte(0);
      status_valid<=1;status_state<=S_SEND;
     end
    end
    S_SEND:begin
     status_valid<=1;
     if(tx_ready)begin
      if(status_index<60)crc<=crc_byte(crc,status_data);
      if(status_index==59)begin
       status_index<=60;status_valid<=0;status_state<=S_CRC;
      end else if(status_index==63)begin
       status_valid<=0;status_active_r<=0;status_state<=S_IDLE;
      end else begin
       status_index<=status_index+1'b1;
       status_data<=status_byte(status_index+1'b1);
      end
     end
    end
    S_CRC:begin
     status_data<=status_byte(60);status_index<=60;status_valid<=1;status_state<=S_SEND;
    end
    default:status_state<=S_IDLE;
   endcase
  end
 end

 wire[7:0] tx_data=status_active?status_data:fifo_data;
 wire tx_valid=status_active?status_valid:(!fifo_empty);
 typec_uart_tx_8n1 #(.DIVISOR(DIVISOR)) tx(.clk(clk27),.rst_n(rst_n),
  .data(tx_data),.valid(tx_valid),.ready(tx_ready),.txd(uart_txd));
endmodule

module typec_uart_rx_8n1 #(parameter DIVISOR=234)(
 input wire clk,rst_n,rxd,output reg[7:0]data,output reg valid,output reg framing_error
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

module typec_uart_tx_8n1 #(parameter DIVISOR=234)(
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
