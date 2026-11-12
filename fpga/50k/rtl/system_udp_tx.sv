`timescale 1ns/1ps
// Broadcast IPv4/UDP transmitter. No packet RAM, no dependence on RXC.
// Payload byte0 is app_payload[1023:1016]. One packet is held in shift FF.
module system_udp_tx #(
    parameter [47:0] LOCAL_MAC=48'h020000000050,
    parameter [31:0] LOCAL_IP=32'hc0a83214,
    parameter [31:0] DEST_IP=32'hc0a832ff,
    parameter [15:0] PORT=16'd5001
)(
    input wire clk,rst_n,
    input wire app_valid,
    output wire app_ready,
    input wire [7:0] app_length,
    input wire [1023:0] app_payload,
    output reg [7:0] gmii_txd,
    output reg gmii_tx_en,
    output wire gmii_tx_er
);
    localparam IDLE=0,PREAMBLE=1,HEADER=2,PAYLOAD=3,PADDING=4,FCS=5,GAP=6;
    reg [2:0] state;
    reg [7:0] count,length;
    reg [1023:0] shift_data;
    reg [15:0] ip_checksum,ident,packet_ident;
    reg [31:0] crc,fcs;
    wire [15:0] ip_length=16'd28+length;
    wire [15:0] udp_length=16'd8+length;
    reg [7:0] header_byte;
    assign app_ready=state==IDLE && rst_n;
    assign gmii_tx_er=1'b0;
    function automatic [31:0] crc_byte(input [31:0] old,input [7:0] data);
        reg [31:0] v;integer b;
        begin
            v=old^{24'd0,data};
            for(b=0;b<8;b=b+1) v=v[0] ? (v>>1)^32'hedb88320 : v>>1;
            crc_byte=v;
        end
    endfunction
    function automatic [15:0] checksum(input [7:0] n,input [15:0] id);
        reg [31:0] sum;
        begin
            sum=32'h4500+28+n+id+32'h4000+32'h4011+
                LOCAL_IP[31:16]+LOCAL_IP[15:0]+DEST_IP[31:16]+DEST_IP[15:0];
            sum=(sum&32'hffff)+(sum>>16);sum=(sum&32'hffff)+(sum>>16);
            checksum=~sum[15:0];
        end
    endfunction
    always @* begin
        header_byte=0;
        case(count)
            0,1,2,3,4,5:header_byte=8'hff;
            6:header_byte=LOCAL_MAC[47:40];7:header_byte=LOCAL_MAC[39:32];
            8:header_byte=LOCAL_MAC[31:24];9:header_byte=LOCAL_MAC[23:16];
            10:header_byte=LOCAL_MAC[15:8];11:header_byte=LOCAL_MAC[7:0];
            12:header_byte=8'h08;13:header_byte=0;
            14:header_byte=8'h45;15:header_byte=0;
            16:header_byte=ip_length[15:8];17:header_byte=ip_length[7:0];
            18:header_byte=packet_ident[15:8];19:header_byte=packet_ident[7:0];
            20:header_byte=8'h40;21:header_byte=0;22:header_byte=64;23:header_byte=17;
            24:header_byte=ip_checksum[15:8];25:header_byte=ip_checksum[7:0];
            26:header_byte=LOCAL_IP[31:24];27:header_byte=LOCAL_IP[23:16];
            28:header_byte=LOCAL_IP[15:8];29:header_byte=LOCAL_IP[7:0];
            30:header_byte=DEST_IP[31:24];31:header_byte=DEST_IP[23:16];
            32:header_byte=DEST_IP[15:8];33:header_byte=DEST_IP[7:0];
            34,36:header_byte=PORT[15:8];35,37:header_byte=PORT[7:0];
            38:header_byte=udp_length[15:8];39:header_byte=udp_length[7:0];
            default:header_byte=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;count<=0;length<=0;shift_data<=0;ident<=0;packet_ident<=0;
            ip_checksum<=0;crc<=32'hffffffff;fcs<=0;gmii_txd<=0;gmii_tx_en<=0;
        end else begin
            gmii_tx_en<=0;gmii_txd<=0;
            case(state)
                IDLE:if(app_valid && app_ready && app_length!=0 && app_length<=128) begin
                    shift_data<=app_payload;length<=app_length;ip_checksum<=checksum(app_length,ident);
                    packet_ident<=ident;ident<=ident+1'b1;count<=0;crc<=32'hffffffff;state<=PREAMBLE;
                end
                PREAMBLE:begin
                    gmii_tx_en<=1;gmii_txd<=count==7 ? 8'hd5 : 8'h55;
                    if(count==7) begin count<=0;state<=HEADER;end else count<=count+1'b1;
                end
                HEADER:begin
                    gmii_tx_en<=1;gmii_txd<=header_byte;crc<=crc_byte(crc,header_byte);
                    if(count==41) begin count<=0;state<=PAYLOAD;end else count<=count+1'b1;
                end
                PAYLOAD:begin
                    gmii_tx_en<=1;gmii_txd<=shift_data[1023:1016];
                    crc<=crc_byte(crc,shift_data[1023:1016]);shift_data<={shift_data[1015:0],8'd0};
                    if(count==length-1) begin
                        count<=0;
                        if(length<18) state<=PADDING;
                        else begin fcs<=~crc_byte(crc,shift_data[1023:1016]);state<=FCS;end
                    end else count<=count+1'b1;
                end
                PADDING:begin
                    gmii_tx_en<=1;gmii_txd<=0;crc<=crc_byte(crc,0);
                    if(count==17-length) begin count<=0;fcs<=~crc_byte(crc,0);state<=FCS;end
                    else count<=count+1'b1;
                end
                FCS:begin
                    gmii_tx_en<=1;gmii_txd<=fcs[7:0];fcs<={8'd0,fcs[31:8]};
                    if(count==3) begin count<=0;state<=GAP;end else count<=count+1'b1;
                end
                GAP:if(count==11) begin count<=0;state<=IDLE;end else count<=count+1'b1;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
