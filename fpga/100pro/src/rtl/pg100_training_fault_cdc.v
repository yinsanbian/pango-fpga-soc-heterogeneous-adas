// Capture the reset-PLL training-failure indication even when the native
// clock is stopped, or when the indication lasts only one source clock.
// Native reset must remain low for >=one native edge before its synchronous
// release (the board supplies three). No running-domain clear/ack can race
// an event. Consumers see only the third native synchronizer stage.
module pg100_training_fault_cdc(
 input wire clk,rst_n,fault_async,
 output wire fault_native
);
 (* syn_preserve=1,syn_allow_retiming=0 *)reg event_latch;
 (* async_reg=1,syn_preserve=1,syn_allow_retiming=0 *)reg sync0,sync1,sync2;
 // One physical asynchronous SET, synchronous clear, and clock enable.
 // During normal operation clock enable is inactive, so SET deassertion
 // cannot clear a captured event. Native reset clears it only at a clock
 // edge; the board's three-cycle reset release masks this clearing interval.
 always @(posedge clk or posedge fault_async)
  if(fault_async)event_latch<=1'b1;
  else if(!rst_n)event_latch<=1'b0;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin sync0<=0;sync1<=0;sync2<=0;end
  else begin sync0<=event_latch;sync1<=sync0;sync2<=sync1;end
 assign fault_native=sync2;
endmodule
