`timescale 1ns/1ps
// Fixed YTI1 CTRL. Input is the MAC's already FCS-validated UDP replay.
// Publication occurs only after all 40 bytes and independent application CRC.
module system_control_rx(
    input wire clk,rst_n,
    input wire udp_start,udp_valid,udp_end,udp_error,
    input wire [7:0] udp_data,
    input wire [10:0] udp_length,
    input wire command_ready,
    output reg command_send,
    output reg [16:0] command_data,
    output reg [31:0] accepted,rejected
);
    reg active,finish,bad,length_ok;
    reg [5:0] index;
    reg [255:0] header;
    reg [31:0] payload,received_crc,crc,last_sequence;
    reg have_sequence;
    reg [31:0] command_sequence;
    wire [5:0] pos=udp_start ? 6'd0 : index;
    wire [31:0] delta=header[63:32]-last_sequence;
    function automatic [31:0] crc_byte(input [31:0] old,input [7:0] data);
        reg [31:0] v;integer b;
        begin
            v=old^{24'd0,data};
            for(b=0;b<8;b=b+1) v=v[0] ? (v>>1)^32'hedb88320 : v>>1;
            crc_byte=v;
        end
    endfunction
    wire good=length_ok && !bad && index==40 &&
        header[255:224]==32'h59544931 && header[223:216]==1 && header[215:208]==9 &&
        (header[207:200]==8'h68 || header[207:200]==8'h40) && header[199:192]==0 &&
        header[95:88]==0 && header[87:80]==0 && header[31:16]==4 && header[15:0]==32 &&
        payload[31:24]==1 && payload[23:16]<2 && header[79:64]==payload[15:0] &&
        received_crc==~crc && (!have_sequence || (delta!=0 && !delta[31]));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;finish<=0;bad<=0;length_ok<=0;index<=0;header<=0;payload<=0;
            received_crc<=0;crc<=32'hffffffff;last_sequence<=0;have_sequence<=0;
            command_send<=0;command_data<=0;command_sequence<=0;accepted<=0;rejected<=0;
        end else begin
            // The mailbox samples the registered request on this edge. Count
            // acceptance and consume the sequence only on that real handshake.
            command_send<=command_send && !command_ready;finish<=0;
            if(command_send && command_ready)begin
                accepted<=accepted+1'b1;last_sequence<=command_sequence;have_sequence<=1;
            end
            if(finish) begin
                if(good && command_ready && !command_send) begin
                    command_data<={payload[15:0],payload[16]};command_send<=1;
                    command_sequence<=header[63:32];
                end else rejected<=rejected+1'b1;
            end
            if(udp_start) begin
                active<=1;bad<=udp_error;length_ok<=udp_length==40;index<=0;
                header<=0;payload<=0;received_crc<=0;crc<=32'hffffffff;
            end
            if((active || udp_start) && udp_valid) begin
                index<=pos+1'b1;
                if(pos<32) header<={header[247:0],udp_data};
                else if(pos<36) payload<={payload[23:0],udp_data};
                else if(pos<40) received_crc<={received_crc[23:0],udp_data};
                else bad<=1;
                if(pos<36) crc<=crc_byte(udp_start ? 32'hffffffff : crc,udp_data);
            end
            if(udp_error && (active || udp_start)) bad<=1;
            if(udp_end && (active || udp_start)) begin active<=0;finish<=1;end
        end
    end
endmodule
