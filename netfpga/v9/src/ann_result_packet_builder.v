`timescale 1ns/1ps

module ann_result_packet_builder #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter RESULT_FRAME_BYTES = 56,
  parameter RESULT_DATA_WORDS = ((RESULT_FRAME_BYTES + 7) / 8),
  parameter RESULT_PKT_WORDS  = RESULT_DATA_WORDS + 1,
  parameter WORD_INDEX_WIDTH = 3,
  parameter [15:0] IPV4_ETHERTYPE = 16'h0800,
  parameter [15:0] ANN_RESULT_MAGIC = 16'hA11F,
  parameter [7:0]  ANN_RESULT_VERSION = 8'h01
) (
  input  [WORD_INDEX_WIDTH-1:0]          word_index,
  input  [15:0]                          dst_port_mask,
  input  [15:0]                          src_port,
  input  [47:0]                          eth_dst,
  input  [47:0]                          eth_src,
  input  [31:0]                          ip_src_addr,
  input  [31:0]                          ip_dst_addr,
  input  [15:0]                          udp_src_port,
  input  [15:0]                          udp_dst_port,
  input  [15:0]                          request_id,
  input  [7:0]                           result_status,
  input  [15:0]                          result_type,
  input  [15:0]                          result_len,
  input  [15:0]                          result_data_0,
  input  [15:0]                          result_data_1,

  output reg [DATA_WIDTH-1:0]            word_data,
  output reg [CTRL_WIDTH-1:0]            word_ctrl
);

  localparam [15:0] IPV4_TOTAL_LEN = 16'd42;
  localparam [15:0] UDP_TOTAL_LEN = 16'd22;
  localparam [15:0] IPV4_IDENTIFICATION = 16'h0000;
  localparam [15:0] IPV4_FLAGS_FRAG = 16'h4000;
  localparam [15:0] IPV4_TTL_PROTOCOL = 16'h4011;

  wire [47:0] result_eth_dst;
  wire [47:0] result_eth_src;
  wire [31:0] result_ip_src;
  wire [31:0] result_ip_dst;
  wire [15:0] result_udp_src_port;
  wire [15:0] result_udp_dst_port;
  wire [15:0] ipv4_checksum;
  wire [63:0] frame_word_0;
  wire [63:0] frame_word_1;
  wire [63:0] frame_word_2;
  wire [63:0] frame_word_3;
  wire [63:0] frame_word_4;
  wire [63:0] frame_word_5;
  wire [63:0] frame_word_6;
  wire [63:0] module_header_word;

  function [15:0] compute_ipv4_checksum;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    reg [19:0] sum;
    begin
      sum = 20'd0;
      sum = sum + 16'h4500;
      sum = sum + IPV4_TOTAL_LEN;
      sum = sum + IPV4_IDENTIFICATION;
      sum = sum + IPV4_FLAGS_FRAG;
      sum = sum + IPV4_TTL_PROTOCOL;
      sum = sum + src_ip[31:16];
      sum = sum + src_ip[15:0];
      sum = sum + dst_ip[31:16];
      sum = sum + dst_ip[15:0];
      sum = (sum[15:0] + sum[19:16]);
      sum = (sum[15:0] + sum[19:16]);
      compute_ipv4_checksum = ~sum[15:0];
    end
  endfunction

  assign result_eth_dst      = eth_src;
  assign result_eth_src      = eth_dst;
  assign result_ip_src       = ip_dst_addr;
  assign result_ip_dst       = ip_src_addr;
  assign result_udp_src_port = udp_dst_port;
  assign result_udp_dst_port = udp_src_port;
  assign ipv4_checksum       = compute_ipv4_checksum(ip_dst_addr, ip_src_addr);

  assign frame_word_0 = {result_eth_dst, result_eth_src[47:32]};
  assign frame_word_1 = {result_eth_src[31:0], IPV4_ETHERTYPE, 8'h45, 8'h00};
  assign frame_word_2 = {IPV4_TOTAL_LEN, IPV4_IDENTIFICATION, IPV4_FLAGS_FRAG, IPV4_TTL_PROTOCOL};
  assign frame_word_3 = {ipv4_checksum, result_ip_src, result_ip_dst[31:16]};
  assign frame_word_4 = {result_ip_dst[15:0], result_udp_src_port, result_udp_dst_port, UDP_TOTAL_LEN};
  assign frame_word_5 = {16'h0000, ANN_RESULT_MAGIC, ANN_RESULT_VERSION, result_status, request_id};
  assign frame_word_6 = {result_type, result_len, result_data_0, result_data_1};
  assign module_header_word = {dst_port_mask, RESULT_DATA_WORDS[15:0], src_port, RESULT_FRAME_BYTES[15:0]};

  always @(*) begin
    case (word_index)
      3'd0: begin
        word_data = module_header_word;
        word_ctrl = {CTRL_WIDTH{1'b1}};
      end
      3'd1: begin
        word_data = frame_word_0;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      3'd2: begin
        word_data = frame_word_1;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      3'd3: begin
        word_data = frame_word_2;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      3'd4: begin
        word_data = frame_word_3;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      3'd5: begin
        word_data = frame_word_4;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      3'd6: begin
        word_data = frame_word_5;
        word_ctrl = {CTRL_WIDTH{1'b0}};
      end
      default: begin
        word_data = frame_word_6;
        word_ctrl = {{(CTRL_WIDTH-1){1'b0}}, 1'b1};
      end
    endcase
  end

endmodule
