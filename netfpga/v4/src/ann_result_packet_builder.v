`timescale 1ns/1ps

module ann_result_packet_builder #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter RESULT_FRAME_BYTES = 30,
  parameter RESULT_DATA_WORDS = ((RESULT_FRAME_BYTES + 7) / 8),
  parameter RESULT_PKT_WORDS  = RESULT_DATA_WORDS + 1,
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_RESULT_MAGIC = 16'hA11F,
  parameter [7:0]  ANN_RESULT_VERSION = 8'h01
) (
  input                                  clk,
  input                                  reset,
  input                                  start,
  input  [15:0]                          dst_port_mask,
  input  [15:0]                          src_port,
  input  [47:0]                          eth_dst,
  input  [47:0]                          eth_src,
  input  [15:0]                          request_id,
  input  [7:0]                           result_status,
  input  [15:0]                          result_type,
  input  [15:0]                          result_len,
  input  [15:0]                          result_data_0,
  input  [15:0]                          result_data_1,

  output reg                             done,
  output reg [RESULT_PKT_WORDS*DATA_WIDTH-1:0] pkt_data_flat,
  output reg [RESULT_PKT_WORDS*CTRL_WIDTH-1:0] pkt_ctrl_flat
);

  function [CTRL_WIDTH-1:0] eop_ctrl;
    input integer valid_bytes;
    begin
      case (valid_bytes)
        1: eop_ctrl = 8'h80;
        2: eop_ctrl = 8'h40;
        3: eop_ctrl = 8'h20;
        4: eop_ctrl = 8'h10;
        5: eop_ctrl = 8'h08;
        6: eop_ctrl = 8'h04;
        7: eop_ctrl = 8'h02;
        8: eop_ctrl = 8'h01;
        default: eop_ctrl = 8'h00;
      endcase
    end
  endfunction

  integer word_idx;
  integer byte_idx;
  integer valid_bytes;
  reg [RESULT_FRAME_BYTES*8-1:0] result_frame_bytes_flat;
  reg [63:0] packed_word;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      done             <= 1'b0;
      pkt_data_flat    <= {(RESULT_PKT_WORDS*DATA_WIDTH){1'b0}};
      pkt_ctrl_flat    <= {(RESULT_PKT_WORDS*CTRL_WIDTH){1'b0}};
    end
    else begin
      done <= 1'b0;
      if (start) begin
        result_frame_bytes_flat = {(RESULT_FRAME_BYTES*8){1'b0}};
        pkt_data_flat           <= {(RESULT_PKT_WORDS*DATA_WIDTH){1'b0}};
        pkt_ctrl_flat           <= {(RESULT_PKT_WORDS*CTRL_WIDTH){1'b0}};

        result_frame_bytes_flat[(0 * 8) +: 8]  = 8'h00;
        result_frame_bytes_flat[(1 * 8) +: 8]  = 8'h00;
        result_frame_bytes_flat[(2 * 8) +: 8]  = eth_dst[47:40];
        result_frame_bytes_flat[(3 * 8) +: 8]  = eth_dst[39:32];
        result_frame_bytes_flat[(4 * 8) +: 8]  = eth_dst[31:24];
        result_frame_bytes_flat[(5 * 8) +: 8]  = eth_dst[23:16];
        result_frame_bytes_flat[(6 * 8) +: 8]  = eth_dst[15:8];
        result_frame_bytes_flat[(7 * 8) +: 8]  = eth_dst[7:0];
        result_frame_bytes_flat[(8 * 8) +: 8]  = eth_src[47:40];
        result_frame_bytes_flat[(9 * 8) +: 8]  = eth_src[39:32];
        result_frame_bytes_flat[(10 * 8) +: 8] = eth_src[31:24];
        result_frame_bytes_flat[(11 * 8) +: 8] = eth_src[23:16];
        result_frame_bytes_flat[(12 * 8) +: 8] = eth_src[15:8];
        result_frame_bytes_flat[(13 * 8) +: 8] = eth_src[7:0];
        result_frame_bytes_flat[(14 * 8) +: 8] = CUSTOM_ETHERTYPE[15:8];
        result_frame_bytes_flat[(15 * 8) +: 8] = CUSTOM_ETHERTYPE[7:0];
        result_frame_bytes_flat[(16 * 8) +: 8] = ANN_RESULT_MAGIC[15:8];
        result_frame_bytes_flat[(17 * 8) +: 8] = ANN_RESULT_MAGIC[7:0];
        result_frame_bytes_flat[(18 * 8) +: 8] = ANN_RESULT_VERSION;
        result_frame_bytes_flat[(19 * 8) +: 8] = result_status;
        result_frame_bytes_flat[(20 * 8) +: 8] = request_id[15:8];
        result_frame_bytes_flat[(21 * 8) +: 8] = request_id[7:0];
        result_frame_bytes_flat[(22 * 8) +: 8] = result_type[15:8];
        result_frame_bytes_flat[(23 * 8) +: 8] = result_type[7:0];
        result_frame_bytes_flat[(24 * 8) +: 8] = result_len[15:8];
        result_frame_bytes_flat[(25 * 8) +: 8] = result_len[7:0];
        result_frame_bytes_flat[(26 * 8) +: 8] = result_data_0[15:8];
        result_frame_bytes_flat[(27 * 8) +: 8] = result_data_0[7:0];
        result_frame_bytes_flat[(28 * 8) +: 8] = result_data_1[15:8];
        result_frame_bytes_flat[(29 * 8) +: 8] = result_data_1[7:0];

        pkt_data_flat[(0 * DATA_WIDTH) +: DATA_WIDTH] <= {
          dst_port_mask,
          RESULT_DATA_WORDS[15:0],
          src_port,
          RESULT_FRAME_BYTES[15:0]
        };
        pkt_ctrl_flat[(0 * CTRL_WIDTH) +: CTRL_WIDTH] <= 8'hff;

        for (word_idx = 0; word_idx < RESULT_DATA_WORDS; word_idx = word_idx + 1) begin
          packed_word = 64'd0;
          valid_bytes = RESULT_FRAME_BYTES - (word_idx * 8);
          if (valid_bytes > 8)
            valid_bytes = 8;

          for (byte_idx = 0; byte_idx < valid_bytes; byte_idx = byte_idx + 1)
            packed_word = packed_word |
                          ({56'd0, result_frame_bytes_flat[((word_idx * 8) + byte_idx) * 8 +: 8]} << (56 - (byte_idx * 8)));

          pkt_data_flat[((word_idx + 1) * DATA_WIDTH) +: DATA_WIDTH] <= packed_word;
          if (word_idx == RESULT_DATA_WORDS - 1)
            pkt_ctrl_flat[((word_idx + 1) * CTRL_WIDTH) +: CTRL_WIDTH] <= eop_ctrl(valid_bytes);
          else
            pkt_ctrl_flat[((word_idx + 1) * CTRL_WIDTH) +: CTRL_WIDTH] <= 8'h00;
        end

        done <= 1'b1;
      end
    end
  end

endmodule
