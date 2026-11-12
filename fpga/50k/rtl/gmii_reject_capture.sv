`timescale 1ns/1ps
// Module: gmii_reject_capture; passive N1 receive evidence, no datapath outputs.
// LATENCY: 0 cycles added to GMII/video; evidence ready after EOF decision and
// a synchronous RAM scan, four RX cycles/sample. Page CRC16 is one byte/cycle.
// RAM is not reset. Validity, length, association and frozen state guard reads.
module gmii_reject_capture(
    input wire clk,rst_n,parser_rst_n,
    input wire [7:0] data,
    input wire dv,er,
    input wire [2:0] events,
    input wire [31:0] mac_state,
    input wire [11:0] eof_length,
    input wire [7:0] reject_flags,
    input wire [258:0] debug_checksums,
    input wire page_is6,page_is7,publish_accept,
    output reg [127:0] metadata_page,data_page
);
    localparam [1:0] RUN=0,WAIT_DECISION=1,FROZEN=2;
    reg [1:0] capture_state;
    reg dv_previous,in_segment,sfd_seen,eof_seen,association_error,overflow,parser_loss,target_valid;
    reg [11:0] write_count,capture_length,sfd_index,mac_length;
    reg [3:0] wait_age;
    reg [31:0] cycle_count,sequence_count,capture_sequence,capture_cycle;
    reg [31:0] received_frame,received_offset;
    reg [15:0] received_udp_dest;
    reg [7:0] prefix,final_flags;
    reg [95:0] early_checksums;
    reg [258:0] frozen_checksums;
    reg [8:0] memory [0:2047];
    wire new_segment=dv && !dv_previous;
    wire [11:0] capture_address=new_segment ? 12'd0 : write_count;
    wire write_enable=rst_n && parser_rst_n && capture_state==RUN && dv &&
        (new_segment || in_segment) && capture_address<12'd2048;
    reg [10:0] read_address;
    reg [8:0] read_sample;
    always @(posedge clk) begin
        if(write_enable) memory[capture_address[10:0]]<={er,data};
        read_sample<=memory[read_address];
    end

    function [31:0] crc32_byte;
        input [31:0] initial_crc;input [7:0] value;
        reg [31:0] c;integer bit_index;
        begin
            c=initial_crc^{24'd0,value};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                c=c[0] ? ((c>>1)^32'hedb88320) : (c>>1);
            crc32_byte=c;
        end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] initial_crc;input [7:0] value;
        reg [15:0] c;integer bit_index;
        begin
            c=initial_crc^{value,8'd0};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                c=c[15] ? ((c<<1)^16'h1021) : (c<<1);
            crc16_byte=c;
        end
    endfunction
    function [7:0] record_byte;
        input [31:0] header;input [63:0] bytes;
        input [7:0] errors;input [3:0] position;
        begin
            if(position<4) record_byte=header[31-position*8 -:8];
            else if(position<12) record_byte=bytes[63-(position-4)*8 -:8];
            else record_byte=errors;
        end
    endfunction

    wire [11:0] current_mac_offset=write_count-sfd_index-12'd1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            capture_state<=RUN;dv_previous<=0;in_segment<=0;
            sfd_seen<=0;eof_seen<=0;association_error<=0;overflow<=0;parser_loss<=0;target_valid<=0;
            write_count<=0;capture_length<=0;sfd_index<=0;mac_length<=0;wait_age<=0;
            cycle_count<=0;sequence_count<=0;capture_sequence<=0;capture_cycle<=0;
            received_frame<=0;received_offset<=0;received_udp_dest<=0;
            prefix<=0;final_flags<=0;early_checksums<=0;frozen_checksums<=0;
        end else begin
            cycle_count<=cycle_count+1'b1;
            dv_previous<=dv;
            if(capture_state==RUN) begin
                if(!parser_rst_n) begin
                    in_segment<=0;write_count<=0;sfd_seen<=0;eof_seen<=0;
                end else begin
                    if(new_segment) begin
                        in_segment<=1;write_count<=12'd1;
                        sfd_seen<=0;eof_seen<=0;association_error<=0;overflow<=0;parser_loss<=0;target_valid<=0;
                        sequence_count<=sequence_count+1'b1;capture_sequence<=sequence_count+1'b1;
                        capture_cycle<=cycle_count;received_frame<=0;received_offset<=0;received_udp_dest<=0;
                        prefix<=0;final_flags<=0;
                    end else if(dv && in_segment) begin
                        if(write_count!=12'hfff) write_count<=write_count+1'b1;
                        if(write_count>=12'd2048) overflow<=1;
                        if(sfd_seen) begin
                            if(current_mac_offset>=12'd50 && current_mac_offset<=12'd53)
                                received_frame<={received_frame[23:0],data};
                            if(current_mac_offset>=12'd54 && current_mac_offset<=12'd57)
                                received_offset<={received_offset[23:0],data};
                            if(current_mac_offset==12'd36 || current_mac_offset==12'd37)
                                received_udp_dest<={received_udp_dest[7:0],data};
                        end
                    end
                    if(events[0]) begin
                        if(!in_segment || sfd_seen || write_count==0) association_error<=1;
                        else begin sfd_seen<=1;sfd_index<=write_count-1'b1;prefix<={2'd0,mac_state[31:26]};end
                    end
                    if(dv_previous && !dv && in_segment) begin
                        capture_state<=WAIT_DECISION;in_segment<=0;wait_age<=0;
                        capture_length<=write_count>12'd2048 ? 12'd2048 : write_count;
                    end
                end
            end else if(capture_state==WAIT_DECISION) begin
                wait_age<=wait_age+1'b1;
                if(events[1]) begin
                    eof_seen<=1;mac_length<=eof_length;early_checksums<=debug_checksums[95:0];
                    if(!sfd_seen || {1'b0,capture_length}!=({1'b0,sfd_index}+13'd1+{1'b0,eof_length}))
                        association_error<=1;
                end
                if(dv || events[0] || !parser_rst_n) begin
                    association_error<=1;parser_loss<=!parser_rst_n;
                    capture_state<=FROZEN;target_valid<=0;
                    final_flags<=events[2] ? reject_flags : 8'd0;
                    frozen_checksums<={debug_checksums[258:96],early_checksums};
                end else if(events[2]) begin
                    if(reject_flags[0] && !reject_flags[2]) begin
                        capture_state<=FROZEN;
                        target_valid<=eof_seen && sfd_seen && !association_error && !overflow;
                        final_flags<=reject_flags;
                        frozen_checksums<={debug_checksums[258:96],early_checksums};
                    end else begin capture_state<=RUN;in_segment<=0;end
                end else if(wait_age>=4) begin
                    // A DV segment never recognized by the actual MAC has no
                    // rejection decision to associate. Keep looking for the
                    // first real target FCS rejection rather than freezing on
                    // a link-start/truncated/no-SFD background segment.
                    if(!sfd_seen && !eof_seen) begin capture_state<=RUN;in_segment<=0;end
                    else if(!eof_seen || association_error || overflow) begin
                        capture_state<=FROZEN;target_valid<=0;association_error<=!eof_seen || association_error;
                        frozen_checksums<={debug_checksums[258:96],early_checksums};
                    end else begin capture_state<=RUN;in_segment<=0;end
                end
            end
            // FROZEN ignores later parser restarts/frames. Shared reset alone
            // clears the evidence. Original health counters report restarts.
        end
    end

    reg image_ready;
    reg [31:0] image_crc,scan_crc;
    reg [11:0] scan_index;
    reg scan_er;
    reg [3:0] read_phase;
    reg [7:0] chunk_index,metadata_index;
    reg data_dirty,metadata_dirty,data_published,metadata_published;
    reg [2:0] byte_index;
    reg [63:0] chunk_bytes;
    reg [7:0] chunk_errors;
    reg [31:0] data_header;
    reg [15:0] data_crc;
    reg [3:0] data_crc_position;
    wire [8:0] chunk_count=({1'b0,capture_length}+13'd7)>>3;
    wire [11:0] chunk_base={1'b0,chunk_index,3'd0};
    wire [11:0] chunk_remaining=capture_length-chunk_base;
    wire [3:0] chunk_valid=chunk_remaining>=8 ? 4'd8 : chunk_remaining[3:0];
    wire [7:0] frozen_status={1'b0,sfd_seen,eof_seen,parser_loss,overflow,association_error,target_valid,image_ready};
    reg [63:0] metadata_word;
    always @(*) begin
        metadata_word=64'd0;
        case(metadata_index)
            0:metadata_word={32'h42464331,8'h01,frozen_status,8'd10,8'd0};
            1:metadata_word={4'd0,capture_length,4'd0,sfd_index,4'd0,mac_length,16'd0};
            2:metadata_word={image_crc,capture_sequence};
            3:metadata_word={final_flags,prefix,5'd0,frozen_checksums[258:256],8'd0,received_frame};
            4:metadata_word={frozen_checksums[31:0],frozen_checksums[63:32]};
            5:metadata_word={frozen_checksums[95:64],frozen_checksums[127:96]};
            6:metadata_word={frozen_checksums[159:128],frozen_checksums[191:160]};
            7:metadata_word={frozen_checksums[223:192],frozen_checksums[255:224]};
            8:metadata_word={received_offset,received_udp_dest,16'd0};
            9:metadata_word={32'h524a0001,capture_cycle};
            default:begin end
        endcase
    end

    reg metadata_crc_active;
    reg [31:0] metadata_header;
    reg [63:0] metadata_bytes;
    reg [15:0] metadata_crc;
    reg [3:0] metadata_crc_position;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            image_ready<=0;image_crc<=0;scan_crc<=32'hffffffff;scan_index<=0;scan_er<=0;
            read_address<=0;read_phase<=0;chunk_index<=0;metadata_index<=0;
            data_dirty<=1;metadata_dirty<=1;data_published<=0;metadata_published<=0;
            byte_index<=0;chunk_bytes<=0;chunk_errors<=0;data_header<=0;data_crc<=16'hffff;data_crc_position<=0;
            metadata_crc_active<=0;metadata_header<=0;metadata_bytes<=0;metadata_crc<=16'hffff;metadata_crc_position<=0;
            metadata_page<=128'hfc000000000000000000000000000000;
            data_page<=128'hfc000000000000000000000000000000;
        end else begin
            case(read_phase)
                0:begin
                    if(capture_state==FROZEN && !image_ready) begin
                        read_address<=0;scan_index<=0;scan_crc<=32'hffffffff;read_phase<=1;
                    end else if(image_ready && data_dirty) begin
                        read_address<=chunk_base[10:0];byte_index<=0;chunk_bytes<=0;chunk_errors<=0;
                        data_header<={8'hfc,capture_sequence[7:0],chunk_index,chunk_valid,4'h1};
                        data_dirty<=0;read_phase<=4;
                    end
                end
                1:read_phase<=2;
                2:begin scan_crc<=crc32_byte(scan_crc,read_sample[7:0]);scan_er<=read_sample[8];read_phase<=3;end
                3:begin
                    scan_crc<=crc32_byte(scan_crc,{7'd0,scan_er});
                    if(scan_index+12'd1>=capture_length) begin
                        image_crc<=~crc32_byte(scan_crc,{7'd0,scan_er});image_ready<=1;read_phase<=0;
                    end else begin scan_index<=scan_index+1'b1;read_address<=scan_index[10:0]+1'b1;read_phase<=1;end
                end
                4:read_phase<=5;
                5:begin
                    if((chunk_base+{9'd0,byte_index})<capture_length) begin
                        chunk_bytes[63-byte_index*8 -:8]<=read_sample[7:0];
                        chunk_errors[byte_index]<=read_sample[8];
                    end
                    if(byte_index==7) read_phase<=6;
                    else begin byte_index<=byte_index+1'b1;read_address<=read_address+1'b1;read_phase<=4;end
                end
                6:begin data_crc<=16'hffff;data_crc_position<=0;read_phase<=7;end
                7:begin
                    data_crc<=crc16_byte(data_crc,record_byte(data_header,chunk_bytes,chunk_errors,data_crc_position));
                    if(data_crc_position==12) begin
                        data_page<={data_header,chunk_bytes,8'd0,
                            crc16_byte(data_crc,record_byte(data_header,chunk_bytes,chunk_errors,data_crc_position)),chunk_errors};
                        read_phase<=0;
                    end else data_crc_position<=data_crc_position+1'b1;
                end
                default:read_phase<=0;
            endcase
            if(image_ready && metadata_dirty && !metadata_crc_active) begin
                metadata_header<={8'hfc,capture_sequence[7:0],metadata_index,4'd8,4'h2};
                metadata_bytes<=metadata_word;metadata_crc<=16'hffff;metadata_crc_position<=0;
                metadata_dirty<=0;metadata_crc_active<=1;
            end else if(metadata_crc_active) begin
                metadata_crc<=crc16_byte(metadata_crc,record_byte(metadata_header,metadata_bytes,8'd0,metadata_crc_position));
                if(metadata_crc_position==12) begin
                    metadata_page<={metadata_header,metadata_bytes,8'd0,
                        crc16_byte(metadata_crc,record_byte(metadata_header,metadata_bytes,8'd0,metadata_crc_position)),8'd0};
                    metadata_crc_active<=0;
                end else metadata_crc_position<=metadata_crc_position+1'b1;
            end

            if(!page_is6) begin
                if(metadata_published) begin
                    metadata_index<=metadata_index==9 ? 8'd0 : metadata_index+1'b1;metadata_dirty<=1;
                end
                metadata_published<=0;
            end else if(publish_accept && image_ready && metadata_page[99:96]==4'h2 &&
                metadata_page[111:104]==metadata_index) metadata_published<=1;
            if(!page_is7) begin
                if(data_published) begin
                    chunk_index<=({1'b0,chunk_index}+9'd1>=chunk_count) ? 8'd0 : chunk_index+1'b1;
                    data_dirty<=1;
                end
                data_published<=0;
            end else if(publish_accept && image_ready && data_page[99:96]==4'h1 &&
                data_page[111:104]==chunk_index) data_published<=1;
        end
    end
endmodule
