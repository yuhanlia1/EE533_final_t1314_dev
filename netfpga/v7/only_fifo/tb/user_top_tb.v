`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif

module user_top_tb;

  localparam DATA_WIDTH = 64;
  localparam CTRL_WIDTH = DATA_WIDTH / 8;
  localparam UDP_REG_SRC_WIDTH = 2;

  localparam MAX_FRAME_BYTES = 2048;
  localparam MAX_PKT_WORDS = 300;
  localparam MAX_EXPECTED_WORDS = 512;
  localparam MAX_EXPECTED_PACKETS = 32;
  localparam TEST_NAME_WIDTH = 64 * 8;

  localparam BP_NONE = 0;
  localparam BP_LIGHT = 1;
  localparam BP_HEAVY = 2;

  localparam LOG_TX_WORDS = 0;
  localparam LOG_RX_COMPARE = 0;
  localparam LOG_PKT_SUMMARY = 1;

  localparam [15:0] IPV4_ETHERTYPE = 16'h0800;
  localparam [15:0] ARP_ETHERTYPE = 16'h0806;
  localparam [7:0] IP_PROTOCOL_TCP = 8'h06;
  localparam [7:0] IP_PROTOCOL_UDP = 8'h11;
  localparam [15:0] ANN_UDP_DST_PORT = 16'h88B5;
  localparam [15:0] ANN_TASK_MAGIC = 16'hA11E;
  localparam [15:0] OFFLOAD_RESULT_MAGIC = 16'hF11E;
  localparam [1:0] ACTION_BYPASS = 2'b00;
  localparam [1:0] ACTION_OFFLOAD = 2'b10;
  localparam integer LEGACY_OFFLOAD_REWRITE_STREAM_WORD_INDEX = 6;
  localparam integer RAW_OFFLOAD_REWRITE_STREAM_WORD_INDEX = 5;
  localparam integer LEGACY_DEBUG_WORD5_STREAM_INDEX = 5;
  localparam integer LEGACY_DEBUG_WORD6_STREAM_INDEX = 6;
  localparam integer RAW_DEBUG_WORD5_STREAM_INDEX = 4;
  localparam integer RAW_DEBUG_WORD6_STREAM_INDEX = 5;
  localparam integer REWRITE_MODE_31_16 = 0;
  localparam integer REWRITE_MODE_47_32 = 1;
  localparam [15:0] USER_TOP_BASE_ADDR = 16'h5540;
  localparam integer DEBUG_CTRL_WORD_INDEX = 0;
  localparam integer DEBUG_LAST_ACTION_WORD_INDEX = 1;
  localparam integer DEBUG_OFFLOAD_MATCH_COUNT_WORD_INDEX = 2;
  localparam integer DEBUG_REWRITE_FIRE_COUNT_WORD_INDEX = 3;
  localparam integer DEBUG_LAST_UDP_DST_PORT_WORD_INDEX = 4;
  localparam integer DEBUG_LAST_PAYLOAD_MAGIC_WORD_INDEX = 5;
  localparam integer DEBUG_LAST_HEADER_WORD5_HI_WORD_INDEX = 6;
  localparam integer DEBUG_LAST_HEADER_WORD5_LO_WORD_INDEX = 7;
  localparam integer DEBUG_LAST_HEADER_WORD6_HI_WORD_INDEX = 8;
  localparam integer DEBUG_LAST_HEADER_WORD6_LO_WORD_INDEX = 9;
  localparam integer DEBUG_LAST_REWRITE_WORD_HI_WORD_INDEX = 10;
  localparam integer DEBUG_LAST_REWRITE_WORD_LO_WORD_INDEX = 11;

  localparam [47:0] DEFAULT_DST_MAC = 48'h0bad_c0de_0001;
  localparam [47:0] DEFAULT_SRC_MAC = 48'hf00d_cafe_0002;
  localparam [31:0] DEFAULT_SRC_IP = 32'hc0a8_0101;
  localparam [31:0] DEFAULT_DST_IP = 32'hc0a8_0102;
  localparam [47:0] BOARD_STYLE_DST_MAC = 48'ha036_9f0a_5c65;
  localparam [47:0] BOARD_STYLE_SRC_MAC = 48'h004e_4632_4302;
  localparam [31:0] BOARD_STYLE_SRC_IP = 32'h0a00_0c03;
  localparam [31:0] BOARD_STYLE_DST_IP = 32'h0a00_0e03;
  localparam [15:0] DEFAULT_REQUEST_ID = 16'h1234;
  localparam [15:0] DEFAULT_TASK_TYPE = 16'h0000;
  localparam integer DEFAULT_FEATURE_COUNT = 8;

  reg                          clk;
  reg                          reset;

  reg  [DATA_WIDTH-1:0]        in_data;
  reg  [CTRL_WIDTH-1:0]        in_ctrl;
  reg                          in_wr;
  wire                         in_rdy;

  wire [DATA_WIDTH-1:0]        out_data;
  wire [CTRL_WIDTH-1:0]        out_ctrl;
  wire                         out_wr;
  reg                          out_rdy;

  reg                          reg_req_in;
  reg                          reg_ack_in;
  reg                          reg_rd_wr_L_in;
  reg  [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in;
  reg  [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in;
  reg  [UDP_REG_SRC_WIDTH-1:0] reg_src_in;

  wire                         reg_req_out;
  wire                         reg_ack_out;
  wire                         reg_rd_wr_L_out;
  wire [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out;
  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out;
  wire [UDP_REG_SRC_WIDTH-1:0] reg_src_out;

  reg  [7:0]                  frame_bytes [0:MAX_FRAME_BYTES-1];
  reg  [DATA_WIDTH-1:0]       tx_data [0:MAX_PKT_WORDS-1];
  reg  [CTRL_WIDTH-1:0]       tx_ctrl [0:MAX_PKT_WORDS-1];
  reg  [DATA_WIDTH-1:0]       expected_data [0:MAX_EXPECTED_WORDS-1];
  reg  [CTRL_WIDTH-1:0]       expected_ctrl [0:MAX_EXPECTED_WORDS-1];
  reg  [1:0]                  expected_packet_action [0:MAX_EXPECTED_PACKETS-1];
  reg  [1:0]                  observed_packet_action [0:MAX_EXPECTED_PACKETS-1];

  reg  [TEST_NAME_WIDTH-1:0]  current_test_name;

  reg                         hold_check_active;
  reg  [DATA_WIDTH-1:0]       held_data;
  reg  [CTRL_WIDTH-1:0]       held_ctrl;
  reg                         store_forward_guard;

  integer                     frame_len;
  integer                     tx_word_count;
  integer                     expected_words;
  integer                     observed_words;
  integer                     expected_packets;
  integer                     observed_packets;
  integer                     fail_count;
  integer                     test_count;
  integer                     packet_count_in_test;
  integer                     bp_mode;
  integer                     bp_counter;
  integer                     expected_rewrite_stream_word_index;
  integer                     expected_rewrite_mode;
  integer                     expected_debug_word5_stream_index;
  integer                     expected_debug_word6_stream_index;

  user_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) dut (
    .in_data        (in_data),
    .in_ctrl        (in_ctrl),
    .in_wr          (in_wr),
    .in_rdy         (in_rdy),
    .out_data       (out_data),
    .out_ctrl       (out_ctrl),
    .out_wr         (out_wr),
    .out_rdy        (out_rdy),
    .reg_req_in     (reg_req_in),
    .reg_ack_in     (reg_ack_in),
    .reg_rd_wr_L_in (reg_rd_wr_L_in),
    .reg_addr_in    (reg_addr_in),
    .reg_data_in    (reg_data_in),
    .reg_src_in     (reg_src_in),
    .reg_req_out    (reg_req_out),
    .reg_ack_out    (reg_ack_out),
    .reg_rd_wr_L_out(reg_rd_wr_L_out),
    .reg_addr_out   (reg_addr_out),
    .reg_data_out   (reg_data_out),
    .reg_src_out    (reg_src_out),
    .clk            (clk),
    .reset          (reset)
  );

  always #5 clk = ~clk;

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

  task record_failure;
    input [TEST_NAME_WIDTH-1:0] message;
    begin
      fail_count = fail_count + 1;
      $display("[%0t] FAIL %0s -- %0s", $time, current_test_name, message);
    end
  endtask

  task clear_scoreboard;
    begin
      expected_words = 0;
      observed_words = 0;
      expected_packets = 0;
      observed_packets = 0;
      packet_count_in_test = 0;
      hold_check_active = 1'b0;
      store_forward_guard = 1'b0;
    end
  endtask

  task append_byte;
    input [7:0] value;
    begin
      if (frame_len >= MAX_FRAME_BYTES)
        record_failure("Frame byte buffer overflow");
      else begin
        frame_bytes[frame_len] = value;
        frame_len = frame_len + 1;
      end
    end
  endtask

  task append_be16;
    input [15:0] value;
    begin
      append_byte(value[15:8]);
      append_byte(value[7:0]);
    end
  endtask

  task append_be32;
    input [31:0] value;
    begin
      append_byte(value[31:24]);
      append_byte(value[23:16]);
      append_byte(value[15:8]);
      append_byte(value[7:0]);
    end
  endtask

  task append_be48;
    input [47:0] value;
    begin
      append_byte(value[47:40]);
      append_byte(value[39:32]);
      append_byte(value[31:24]);
      append_byte(value[23:16]);
      append_byte(value[15:8]);
      append_byte(value[7:0]);
    end
  endtask

  task append_pattern;
    input integer count;
    input [7:0] seed;
    integer idx;
    begin
      for (idx = 0; idx < count; idx = idx + 1)
        append_byte(seed + idx[7:0]);
    end
  endtask

  task append_l2_header_ex;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [15:0] ethertype;
    begin
      frame_len = 0;
      append_byte(8'h00);
      append_byte(8'h00);
      append_be48(dst_mac);
      append_be48(src_mac);
      append_be16(ethertype);
    end
  endtask

  task append_l2_header;
    input [15:0] ethertype;
    begin
      append_l2_header_ex(DEFAULT_DST_MAC, DEFAULT_SRC_MAC, ethertype);
    end
  endtask

  task append_l2_header_nopad_ex;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [15:0] ethertype;
    begin
      frame_len = 0;
      append_be48(dst_mac);
      append_be48(src_mac);
      append_be16(ethertype);
    end
  endtask

  task append_l2_header_nopad;
    input [15:0] ethertype;
    begin
      append_l2_header_nopad_ex(DEFAULT_DST_MAC, DEFAULT_SRC_MAC, ethertype);
    end
  endtask

  task append_ipv4_header_ex;
    input [7:0] protocol;
    input integer ip_payload_len;
    input integer ip_options_bytes;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    input [7:0] ttl;
    input [15:0] ip_checksum;
    integer ip_total_len;
    integer ihl_words;
    integer option_idx;
    begin
      ip_total_len = 20 + ip_options_bytes + ip_payload_len;
      ihl_words = (20 + ip_options_bytes) / 4;

      append_byte({4'h4, ihl_words[3:0]});
      append_byte(8'h00);
      append_be16(ip_total_len[15:0]);
      append_be16(16'h1234);
      append_be16(16'h4000);
      append_byte(ttl);
      append_byte(protocol);
      append_be16(ip_checksum);
      append_be32(src_ip);
      append_be32(dst_ip);

      for (option_idx = 0; option_idx < ip_options_bytes; option_idx = option_idx + 1)
        append_byte(8'he0 + option_idx[7:0]);
    end
  endtask

  task append_ipv4_header;
    input [7:0] protocol;
    input integer ip_payload_len;
    input integer ip_options_bytes;
    begin
      append_ipv4_header_ex(
        protocol,
        ip_payload_len,
        ip_options_bytes,
        DEFAULT_SRC_IP,
        DEFAULT_DST_IP,
        8'h40,
        16'h0000
      );
    end
  endtask

  task finalize_packet;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    integer data_word_count;
    integer word_idx;
    integer byte_idx;
    integer valid_bytes;
    integer lane;
    reg [63:0] packed_word;
    reg [15:0] byte_len_field;
    reg [15:0] word_len_field;
    begin
      data_word_count = (frame_len + 7) / 8;
      tx_word_count = data_word_count + 1;
      byte_len_field = frame_len[15:0];
      word_len_field = data_word_count[15:0];

      if (tx_word_count > MAX_PKT_WORDS) begin
        record_failure("Packet word buffer overflow");
        tx_word_count = MAX_PKT_WORDS;
      end

      tx_data[0] = {dst_port_mask, word_len_field, src_port, byte_len_field};
      tx_ctrl[0] = 8'hff;
      expected_rewrite_stream_word_index = LEGACY_OFFLOAD_REWRITE_STREAM_WORD_INDEX;
      expected_rewrite_mode = REWRITE_MODE_31_16;
      expected_debug_word5_stream_index = LEGACY_DEBUG_WORD5_STREAM_INDEX;
      expected_debug_word6_stream_index = LEGACY_DEBUG_WORD6_STREAM_INDEX;

      byte_idx = 0;
      for (word_idx = 0; word_idx < data_word_count; word_idx = word_idx + 1) begin
        packed_word = 64'h0;
        valid_bytes = frame_len - byte_idx;
        if (valid_bytes > 8)
          valid_bytes = 8;

        for (lane = 0; lane < valid_bytes; lane = lane + 1)
          packed_word = packed_word | ({56'h0, frame_bytes[byte_idx + lane]} << (56 - lane * 8));

        tx_data[word_idx + 1] = packed_word;
        if (word_idx == data_word_count - 1)
          tx_ctrl[word_idx + 1] = eop_ctrl(valid_bytes);
        else
          tx_ctrl[word_idx + 1] = 8'h00;

        byte_idx = byte_idx + valid_bytes;
      end
    end
  endtask

  task finalize_packet_no_module_header;
    integer data_word_count;
    integer word_idx;
    integer byte_idx;
    integer valid_bytes;
    integer lane;
    reg [63:0] packed_word;
    begin
      data_word_count = (frame_len + 7) / 8;
      tx_word_count = data_word_count;

      if (tx_word_count > MAX_PKT_WORDS) begin
        record_failure("Packet word buffer overflow");
        tx_word_count = MAX_PKT_WORDS;
      end

      byte_idx = 0;
      for (word_idx = 0; word_idx < data_word_count; word_idx = word_idx + 1) begin
        packed_word = 64'h0;
        valid_bytes = frame_len - byte_idx;
        if (valid_bytes > 8)
          valid_bytes = 8;

        for (lane = 0; lane < valid_bytes; lane = lane + 1)
          packed_word = packed_word | ({56'h0, frame_bytes[byte_idx + lane]} << (56 - lane * 8));

        tx_data[word_idx] = packed_word;
        if (word_idx == 0)
          tx_ctrl[word_idx] = 8'hff;
        else if (word_idx == data_word_count - 1)
          tx_ctrl[word_idx] = eop_ctrl(valid_bytes);
        else
          tx_ctrl[word_idx] = 8'h00;

        byte_idx = byte_idx + valid_bytes;
      end

      expected_rewrite_stream_word_index = RAW_OFFLOAD_REWRITE_STREAM_WORD_INDEX;
      expected_rewrite_mode = REWRITE_MODE_47_32;
      expected_debug_word5_stream_index = RAW_DEBUG_WORD5_STREAM_INDEX;
      expected_debug_word6_stream_index = RAW_DEBUG_WORD6_STREAM_INDEX;
    end
  endtask

  task build_ipv4_udp_packet;
    input integer udp_payload_len;
    input integer ip_options_bytes;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [7:0] payload_seed;
    integer udp_len_field;
    begin
      append_l2_header(IPV4_ETHERTYPE);
      udp_len_field = 8 + udp_payload_len;
      append_ipv4_header(IP_PROTOCOL_UDP, udp_len_field, ip_options_bytes);
      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field[15:0]);
      append_be16(16'h0000);
      append_pattern(udp_payload_len, payload_seed);
      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_ipv4_tcp_packet;
    input integer tcp_payload_len;
    input integer ip_options_bytes;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] tcp_src_port;
    input [15:0] tcp_dst_port;
    input [7:0] payload_seed;
    begin
      append_l2_header(IPV4_ETHERTYPE);
      append_ipv4_header(IP_PROTOCOL_TCP, 20 + tcp_payload_len, ip_options_bytes);
      append_be16(tcp_src_port);
      append_be16(tcp_dst_port);
      append_be32(32'h0102_0304);
      append_be32(32'h0506_0708);
      append_byte(8'h50);
      append_byte(8'h18);
      append_be16(16'h1000);
      append_be16(16'h0000);
      append_be16(16'h0000);
      append_pattern(tcp_payload_len, payload_seed);
      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_non_ipv4_packet;
    input integer payload_len;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] ethertype;
    input [7:0] payload_seed;
    begin
      append_l2_header(ethertype);
      append_pattern(payload_len, payload_seed);
      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_short_ipv4_udp_prefix_packet;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    begin
      append_l2_header(IPV4_ETHERTYPE);
      append_byte(8'h45);
      append_byte(8'h00);
      append_be16(16'h0020);
      append_be16(16'h1234);
      append_be16(16'h4000);
      append_byte(8'h40);
      append_byte(8'h11);
      append_be16(16'h0000);
      append_be32(DEFAULT_SRC_IP);
      append_byte(8'hc0);
      append_byte(8'ha8);
      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_ipv4_udp_ann_packet_ex;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [15:0] task_magic;
    input [15:0] request_id;
    input integer feature_count_field;
    input integer emitted_feature_count;
    input [15:0] task_type;
    input integer feature_seed;
    integer ann_payload_len;
    integer udp_len_field;
    integer feature_idx;
    integer feature_val;
    begin
      append_l2_header(IPV4_ETHERTYPE);
      ann_payload_len = 8 + (emitted_feature_count * 2);
      udp_len_field = 8 + ann_payload_len;
      append_ipv4_header(IP_PROTOCOL_UDP, udp_len_field, 0);
      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field[15:0]);
      append_be16(16'h0000);

      append_be16(task_magic);
      append_be16(request_id);
      append_be16(feature_count_field[15:0]);
      append_be16(task_type);
      for (feature_idx = 0; feature_idx < emitted_feature_count; feature_idx = feature_idx + 1) begin
        if ((feature_idx % 2) == 0)
          feature_val = feature_seed + feature_idx + 1;
        else
          feature_val = -(feature_seed + feature_idx + 1);
        append_be16(feature_val[15:0]);
      end

      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_ipv4_udp_ann_packet_headers_ex;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    input [7:0] ttl;
    input [15:0] ip_checksum;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [15:0] task_magic;
    input [15:0] request_id;
    input integer feature_count_field;
    input integer emitted_feature_count;
    input [15:0] task_type;
    input integer feature_seed;
    integer ann_payload_len;
    integer udp_len_field;
    integer feature_idx;
    integer feature_val;
    begin
      append_l2_header_ex(dst_mac, src_mac, IPV4_ETHERTYPE);
      ann_payload_len = 8 + (emitted_feature_count * 2);
      udp_len_field = 8 + ann_payload_len;
      append_ipv4_header_ex(
        IP_PROTOCOL_UDP,
        udp_len_field,
        0,
        src_ip,
        dst_ip,
        ttl,
        ip_checksum
      );
      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field[15:0]);
      append_be16(16'h0000);

      append_be16(task_magic);
      append_be16(request_id);
      append_be16(feature_count_field[15:0]);
      append_be16(task_type);
      for (feature_idx = 0; feature_idx < emitted_feature_count; feature_idx = feature_idx + 1) begin
        if ((feature_idx % 2) == 0)
          feature_val = feature_seed + feature_idx + 1;
        else
          feature_val = -(feature_seed + feature_idx + 1);
        append_be16(feature_val[15:0]);
      end

      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_ipv4_udp_ann_packet_headers_nopad_ex;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    input [7:0] ttl;
    input [15:0] ip_checksum;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [15:0] task_magic;
    input [15:0] request_id;
    input integer feature_count_field;
    input integer emitted_feature_count;
    input [15:0] task_type;
    input integer feature_seed;
    integer ann_payload_len;
    integer udp_len_field;
    integer feature_idx;
    integer feature_val;
    begin
      append_l2_header_nopad_ex(dst_mac, src_mac, IPV4_ETHERTYPE);
      ann_payload_len = 8 + (emitted_feature_count * 2);
      udp_len_field = 8 + ann_payload_len;
      append_ipv4_header_ex(
        IP_PROTOCOL_UDP,
        udp_len_field,
        0,
        src_ip,
        dst_ip,
        ttl,
        ip_checksum
      );
      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field[15:0]);
      append_be16(16'h0000);

      append_be16(task_magic);
      append_be16(request_id);
      append_be16(feature_count_field[15:0]);
      append_be16(task_type);
      for (feature_idx = 0; feature_idx < emitted_feature_count; feature_idx = feature_idx + 1) begin
        if ((feature_idx % 2) == 0)
          feature_val = feature_seed + feature_idx + 1;
        else
          feature_val = -(feature_seed + feature_idx + 1);
        append_be16(feature_val[15:0]);
      end

      finalize_packet(src_port, dst_port_mask);
      expected_rewrite_stream_word_index = LEGACY_OFFLOAD_REWRITE_STREAM_WORD_INDEX;
      expected_rewrite_mode = REWRITE_MODE_47_32;
      expected_debug_word5_stream_index = LEGACY_DEBUG_WORD5_STREAM_INDEX;
      expected_debug_word6_stream_index = LEGACY_DEBUG_WORD6_STREAM_INDEX;
    end
  endtask

  task build_ipv4_udp_ann_raw_packet_headers_ex;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    input [7:0] ttl;
    input [15:0] ip_checksum;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [15:0] task_magic;
    input [15:0] request_id;
    input integer feature_count_field;
    input integer emitted_feature_count;
    input [15:0] task_type;
    input integer feature_seed;
    integer ann_payload_len;
    integer udp_len_field;
    integer feature_idx;
    integer feature_val;
    begin
      append_l2_header_nopad_ex(dst_mac, src_mac, IPV4_ETHERTYPE);
      ann_payload_len = 8 + (emitted_feature_count * 2);
      udp_len_field = 8 + ann_payload_len;
      append_ipv4_header_ex(
        IP_PROTOCOL_UDP,
        udp_len_field,
        0,
        src_ip,
        dst_ip,
        ttl,
        ip_checksum
      );
      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field[15:0]);
      append_be16(16'h0000);

      append_be16(task_magic);
      append_be16(request_id);
      append_be16(feature_count_field[15:0]);
      append_be16(task_type);
      for (feature_idx = 0; feature_idx < emitted_feature_count; feature_idx = feature_idx + 1) begin
        if ((feature_idx % 2) == 0)
          feature_val = feature_seed + feature_idx + 1;
        else
          feature_val = -(feature_seed + feature_idx + 1);
        append_be16(feature_val[15:0]);
      end

      finalize_packet_no_module_header;
    end
  endtask

  task build_ipv4_udp_ann_packet;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] request_id;
    input integer feature_seed;
    begin
      build_ipv4_udp_ann_packet_ex(
        src_port,
        dst_port_mask,
        16'h4001,
        ANN_UDP_DST_PORT,
        ANN_TASK_MAGIC,
        request_id,
        DEFAULT_FEATURE_COUNT,
        DEFAULT_FEATURE_COUNT,
        DEFAULT_TASK_TYPE,
        feature_seed
      );
    end
  endtask

  function [DATA_WIDTH-1:0] rewrite_data_word;
    input [DATA_WIDTH-1:0] data_word;
    input integer rewrite_mode;
    begin
      rewrite_data_word = data_word;
      if (rewrite_mode == REWRITE_MODE_47_32)
        rewrite_data_word = {data_word[63:48], OFFLOAD_RESULT_MAGIC, data_word[31:0]};
      else
        rewrite_data_word = {data_word[63:32], OFFLOAD_RESULT_MAGIC, data_word[15:0]};
    end
  endfunction

  function [DATA_WIDTH-1:0] expected_output_word;
    input [DATA_WIDTH-1:0] data_word;
    input integer word_idx;
    input [1:0] packet_action;
    begin
      expected_output_word = data_word;
      if ((packet_action == ACTION_OFFLOAD) &&
          (word_idx == expected_rewrite_stream_word_index))
        expected_output_word = rewrite_data_word(data_word, expected_rewrite_mode);
    end
  endfunction

  task expect_unknown_reg_passthrough;
    begin
      reg_req_in      = 1'b1;
      reg_ack_in      = 1'b1;
      reg_rd_wr_L_in  = 1'b0;
      reg_addr_in     = {(`UDP_REG_ADDR_WIDTH){1'b1}};
      reg_data_in     = {(`CPCI_NF2_DATA_WIDTH){1'b1}};
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b1}};
      #1;

      if (reg_req_out !== reg_req_in)
        record_failure("Register req path mismatch");
      if (reg_ack_out !== reg_ack_in)
        record_failure("Register ack path mismatch");
      if (reg_rd_wr_L_out !== reg_rd_wr_L_in)
        record_failure("Register rd_wr path mismatch");
      if (reg_addr_out !== reg_addr_in)
        record_failure("Register addr path mismatch");
      if (reg_data_out !== reg_data_in)
        record_failure("Register data path mismatch");
      if (reg_src_out !== reg_src_in)
        record_failure("Register src path mismatch");

      reg_req_in      = 1'b0;
      reg_ack_in      = 1'b0;
      reg_rd_wr_L_in  = 1'b1;
      reg_addr_in     = {(`UDP_REG_ADDR_WIDTH){1'b0}};
      reg_data_in     = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b0}};
    end
  endtask

  task reg_local_write;
    input integer word_index;
    input [31:0] write_data;
    reg [`UDP_REG_ADDR_WIDTH-1:0] local_addr;
    begin
      local_addr = USER_TOP_BASE_ADDR + (word_index * 4);
      @(negedge clk);
      reg_req_in      = 1'b1;
      reg_ack_in      = 1'b0;
      reg_rd_wr_L_in  = 1'b0;
      reg_addr_in     = local_addr;
      reg_data_in     = write_data;
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b0}};
      #1;
      if (reg_ack_out !== 1'b1)
        record_failure("Local register write ack missing");
      @(posedge clk);
      @(negedge clk);
      reg_req_in      = 1'b0;
      reg_ack_in      = 1'b0;
      reg_rd_wr_L_in  = 1'b1;
      reg_addr_in     = {(`UDP_REG_ADDR_WIDTH){1'b0}};
      reg_data_in     = 32'h0;
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b0}};
    end
  endtask

  task expect_local_reg_read;
    input integer word_index;
    input [31:0] exp_data;
    input [TEST_NAME_WIDTH-1:0] message;
    reg [`UDP_REG_ADDR_WIDTH-1:0] local_addr;
    begin
      local_addr = USER_TOP_BASE_ADDR + (word_index * 4);
      @(negedge clk);
      reg_req_in      = 1'b1;
      reg_ack_in      = 1'b0;
      reg_rd_wr_L_in  = 1'b1;
      reg_addr_in     = local_addr;
      reg_data_in     = 32'h0;
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b0}};
      #1;
      if (reg_ack_out !== 1'b1)
        record_failure("Local register read ack missing");
      if (reg_data_out !== exp_data)
        record_failure(message);
      @(posedge clk);
      @(negedge clk);
      reg_req_in      = 1'b0;
      reg_ack_in      = 1'b0;
      reg_rd_wr_L_in  = 1'b1;
      reg_addr_in     = {(`UDP_REG_ADDR_WIDTH){1'b0}};
      reg_data_in     = 32'h0;
      reg_src_in      = {UDP_REG_SRC_WIDTH{1'b0}};
    end
  endtask

  task clear_debug_regs;
    begin
      reg_local_write(DEBUG_CTRL_WORD_INDEX, 32'h0000_0001);
      reg_local_write(DEBUG_CTRL_WORD_INDEX, 32'h0000_0000);
    end
  endtask

  task expect_debug_snapshot;
    input [1:0] exp_action;
    input [31:0] exp_offload_count;
    input [31:0] exp_rewrite_count;
    input [15:0] exp_udp_dst_port;
    input [15:0] exp_payload_magic;
    begin
      expect_local_reg_read(
        DEBUG_LAST_ACTION_WORD_INDEX,
        {{30{1'b0}}, exp_action},
        "Debug last_action mismatch"
      );
      expect_local_reg_read(
        DEBUG_OFFLOAD_MATCH_COUNT_WORD_INDEX,
        exp_offload_count,
        "Debug offload_match_count mismatch"
      );
      expect_local_reg_read(
        DEBUG_REWRITE_FIRE_COUNT_WORD_INDEX,
        exp_rewrite_count,
        "Debug rewrite_fire_count mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_UDP_DST_PORT_WORD_INDEX,
        {16'h0000, exp_udp_dst_port},
        "Debug last_udp_dst_port mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_PAYLOAD_MAGIC_WORD_INDEX,
        {16'h0000, exp_payload_magic},
        "Debug last_payload_magic mismatch"
      );
    end
  endtask

  task expect_debug_words;
    input [63:0] exp_header_word5;
    input [63:0] exp_header_word6;
    input [63:0] exp_rewrite_word;
    begin
      expect_local_reg_read(
        DEBUG_LAST_HEADER_WORD5_HI_WORD_INDEX,
        exp_header_word5[63:32],
        "Debug last_header_word5 hi mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_HEADER_WORD5_LO_WORD_INDEX,
        exp_header_word5[31:0],
        "Debug last_header_word5 lo mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_HEADER_WORD6_HI_WORD_INDEX,
        exp_header_word6[63:32],
        "Debug last_header_word6 hi mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_HEADER_WORD6_LO_WORD_INDEX,
        exp_header_word6[31:0],
        "Debug last_header_word6 lo mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_REWRITE_WORD_HI_WORD_INDEX,
        exp_rewrite_word[63:32],
        "Debug last_rewrite_word hi mismatch"
      );
      expect_local_reg_read(
        DEBUG_LAST_REWRITE_WORD_LO_WORD_INDEX,
        exp_rewrite_word[31:0],
        "Debug last_rewrite_word lo mismatch"
      );
    end
  endtask

  task expect_current_debug_words;
    input integer rewrite_expected;
    reg [63:0] exp_rewrite_word;
    begin
      if (rewrite_expected != 0)
        exp_rewrite_word = rewrite_data_word(
          tx_data[expected_rewrite_stream_word_index],
          expected_rewrite_mode
        );
      else
        exp_rewrite_word = 64'h0;

      expect_debug_words(
        tx_data[expected_debug_word5_stream_index],
        tx_data[expected_debug_word6_stream_index],
        exp_rewrite_word
      );
    end
  endtask

  task expect_opl_packet_layout;
    input [15:0] exp_src_port;
    input [15:0] exp_dst_port_mask;
    integer data_word_count;
    integer word_idx;
    integer tail_valid_bytes;
    reg [63:0] exp_module_header;
    begin
      data_word_count = (frame_len + 7) / 8;
      exp_module_header = {exp_dst_port_mask, data_word_count[15:0], exp_src_port, frame_len[15:0]};

      if (tx_word_count !== (data_word_count + 1))
        record_failure("OPL word count encoding mismatch");

      if (tx_ctrl[0] !== 8'hff)
        record_failure("OPL module header ctrl must be ff");

      if (tx_data[0] !== exp_module_header)
        record_failure("OPL module header data mismatch");

      if (data_word_count > 0) begin
        for (word_idx = 1; word_idx < tx_word_count - 1; word_idx = word_idx + 1) begin
          if (tx_ctrl[word_idx] !== 8'h00)
            record_failure("Intermediate frame word ctrl must be 00");
        end

        tail_valid_bytes = frame_len - ((data_word_count - 1) * 8);
        if (tail_valid_bytes <= 0)
          tail_valid_bytes = 8;

        if (tx_ctrl[tx_word_count - 1] !== eop_ctrl(tail_valid_bytes))
          record_failure("EOP ctrl encoding mismatch");
      end
    end
  endtask

  task push_expected_word;
    input [DATA_WIDTH-1:0] data_word;
    input [CTRL_WIDTH-1:0] ctrl_word;
    begin
      if (expected_words >= MAX_EXPECTED_WORDS)
        record_failure("Expected word buffer overflow");
      else begin
        expected_data[expected_words] = data_word;
        expected_ctrl[expected_words] = ctrl_word;
        expected_words = expected_words + 1;
      end
    end
  endtask

  task push_expected_current_tx;
    input integer word_idx;
    begin
      push_expected_word(tx_data[word_idx], tx_ctrl[word_idx]);
    end
  endtask

  task push_expected_packet_action;
    input [1:0] packet_action;
    begin
      if (expected_packets >= MAX_EXPECTED_PACKETS)
        record_failure("Expected packet-action buffer overflow");
      else begin
        expected_packet_action[expected_packets] = packet_action;
        expected_packets = expected_packets + 1;
      end
    end
  endtask

  task drive_idle_cycles;
    input integer count;
    integer cycle_idx;
    begin
      in_wr = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
      for (cycle_idx = 0; cycle_idx < count; cycle_idx = cycle_idx + 1)
        @(posedge clk);
    end
  endtask

  task send_word;
    input [DATA_WIDTH-1:0] data_word;
    input [CTRL_WIDTH-1:0] ctrl_word;
    input integer word_idx;
    input integer pkt_idx;
    integer waited;
    begin
      waited = 0;
      while (in_rdy !== 1'b1) begin
        @(negedge clk);
        waited = waited + 1;
        if (waited > 200000) begin
          record_failure("Timed out waiting for in_rdy before sending word");
          disable send_word;
        end
      end

      in_data = data_word;
      in_ctrl = ctrl_word;
      in_wr = 1'b1;

      @(posedge clk);
      if (LOG_TX_WORDS != 0) begin
        $display("[%0t] TX  %0s pkt=%0d word=%0d data=%016h ctrl=%02h",
                 $time, current_test_name, pkt_idx, word_idx, data_word, ctrl_word);
      end

      @(negedge clk);
      in_wr = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
    end
  endtask

  task send_packet;
    input [1:0] exp_action;
    input integer stall_after_word;
    input integer stall_cycles;
    input integer check_store_forward;
    integer word_idx;
    integer pkt_idx;
    begin
      packet_count_in_test = packet_count_in_test + 1;
      pkt_idx = packet_count_in_test;
      if (LOG_PKT_SUMMARY != 0) begin
        $display("[%0t] PKT %0s pkt=%0d frame_bytes=%0d total_words=%0d action=%0d stall_after=%0d stall_cycles=%0d store_forward_check=%0d",
                 $time, current_test_name, pkt_idx, frame_len, tx_word_count, exp_action,
                 stall_after_word, stall_cycles, check_store_forward);
        $display("[%0t] PKT %0s pkt=%0d module_header data=%016h ctrl=%02h",
                 $time, current_test_name, pkt_idx, tx_data[0], tx_ctrl[0]);
      end

      push_expected_packet_action(exp_action);
      if (check_store_forward != 0)
        store_forward_guard = 1'b1;

      for (word_idx = 0; word_idx < tx_word_count; word_idx = word_idx + 1) begin
        push_expected_word(expected_output_word(tx_data[word_idx], word_idx, exp_action), tx_ctrl[word_idx]);
        send_word(tx_data[word_idx], tx_ctrl[word_idx], word_idx, pkt_idx);
        if (word_idx == stall_after_word)
          drive_idle_cycles(stall_cycles);
      end

      store_forward_guard = 1'b0;
    end
  endtask

  task wait_for_expected_words;
    input integer timeout_cycles;
    integer waited;
    begin : wait_block
      waited = 0;
      while (observed_words < expected_words) begin
        @(posedge clk);
        waited = waited + 1;
        if (waited > timeout_cycles) begin
          record_failure("Timed out waiting for packet drain");
          disable wait_block;
        end
      end
    end
  endtask

  task start_test;
    input [TEST_NAME_WIDTH-1:0] name;
    begin
      current_test_name = name;
      test_count = test_count + 1;
      clear_scoreboard;
      bp_mode = BP_NONE;
      $display("\nTEST %0d START %0s", test_count, current_test_name);
      drive_idle_cycles(3);
    end
  endtask

  task finish_test;
    integer idle_cycles;
    integer pkt_idx;
    begin
      wait_for_expected_words(50000);

      if (observed_words !== expected_words)
        record_failure("Expected/output word counts differ at end of test");
      if (observed_packets !== expected_packets)
        record_failure("Expected/output packet counts differ at end of test");

      for (pkt_idx = 0; pkt_idx < expected_packets; pkt_idx = pkt_idx + 1) begin
        if (observed_packet_action[pkt_idx] !== expected_packet_action[pkt_idx])
          record_failure("Packet action mismatch");
      end

      bp_mode = BP_NONE;
      for (idle_cycles = 0; idle_cycles < 3; idle_cycles = idle_cycles + 1) begin
        @(posedge clk);
        if (out_wr !== 1'b0)
          record_failure("Output should be idle after drain completion");
      end

      clear_scoreboard;
      $display("TEST %0d END   %0s", test_count, current_test_name);
    end
  endtask

  task apply_reset;
    begin
      reset = 1'b1;
      in_wr = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
      bp_mode = BP_NONE;
      out_rdy = 1'b0;
      expected_rewrite_stream_word_index = LEGACY_OFFLOAD_REWRITE_STREAM_WORD_INDEX;
      expected_rewrite_mode = REWRITE_MODE_31_16;
      expected_debug_word5_stream_index = LEGACY_DEBUG_WORD5_STREAM_INDEX;
      expected_debug_word6_stream_index = LEGACY_DEBUG_WORD6_STREAM_INDEX;
      clear_scoreboard;
      repeat (4) @(posedge clk);
      reset = 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  always @(posedge clk) begin
    if (reset) begin
      bp_counter <= 0;
      out_rdy <= 1'b0;
    end
    else begin
      bp_counter <= bp_counter + 1;
      case (bp_mode)
        BP_NONE:  out_rdy <= 1'b1;
        BP_LIGHT: out_rdy <= (bp_counter % 4) != 0;
        BP_HEAVY: out_rdy <= (bp_counter % 4) == 0;
        default:  out_rdy <= 1'b1;
      endcase
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      hold_check_active <= 1'b0;
      observed_packets <= 0;
    end
    else begin
      if (dut.action_out_wr && dut.action_out_rdy && (dut.action_out_ctrl == 8'hff)) begin
        if (observed_packets >= MAX_EXPECTED_PACKETS)
          record_failure("Observed packet-action buffer overflow");
        else begin
          observed_packet_action[observed_packets] <= dut.selector_action;
          observed_packets <= observed_packets + 1;
        end
      end

      if (store_forward_guard && out_wr)
        record_failure("Output asserted before the packet was fully written");

      if (out_wr && !out_rdy) begin
        if (!hold_check_active) begin
          hold_check_active <= 1'b1;
          held_data <= out_data;
          held_ctrl <= out_ctrl;
        end
        else if ((out_data !== held_data) || (out_ctrl !== held_ctrl)) begin
          record_failure("Output changed while downstream backpressure was active");
          held_data <= out_data;
          held_ctrl <= out_ctrl;
        end
      end
      else begin
        hold_check_active <= 1'b0;
      end

      if (out_wr && out_rdy) begin
        if (observed_words >= expected_words) begin
          if (LOG_RX_COMPARE != 0) begin
            $display("[%0t] CMP %0s word=%0d unexpected actual_data=%016h actual_ctrl=%02h action=%0d",
                     $time, current_test_name, observed_words, out_data, out_ctrl, dut.selector_action);
          end
          record_failure("Unexpected output word observed");
        end
        else begin
          if (LOG_RX_COMPARE != 0) begin
            $display("[%0t] CMP %0s word=%0d exp_data=%016h exp_ctrl=%02h act_data=%016h act_ctrl=%02h action=%0d %0s",
                     $time, current_test_name, observed_words,
                     expected_data[observed_words], expected_ctrl[observed_words],
                     out_data, out_ctrl, dut.selector_action,
                     ((out_data === expected_data[observed_words]) &&
                      (out_ctrl === expected_ctrl[observed_words])) ? "OK" : "BAD");
          end
          if (out_data !== expected_data[observed_words])
            record_failure("Output data mismatch");
          if (out_ctrl !== expected_ctrl[observed_words])
            record_failure("Output ctrl mismatch");
        end
        observed_words <= observed_words + 1;
      end
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b0;
    in_data = 64'h0;
    in_ctrl = 8'h00;
    in_wr = 1'b0;
    out_rdy = 1'b0;
    reg_req_in = 1'b0;
    reg_ack_in = 1'b0;
    reg_rd_wr_L_in = 1'b1;
    reg_addr_in = {(`UDP_REG_ADDR_WIDTH){1'b0}};
    reg_data_in = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
    reg_src_in = {UDP_REG_SRC_WIDTH{1'b0}};
    current_test_name = "boot";
    hold_check_active = 1'b0;
    held_data = 64'h0;
    held_ctrl = 8'h00;
    store_forward_guard = 1'b0;
    frame_len = 0;
    tx_word_count = 0;
    expected_words = 0;
    observed_words = 0;
    expected_packets = 0;
    observed_packets = 0;
    fail_count = 0;
    test_count = 0;
    packet_count_in_test = 0;
    bp_mode = BP_NONE;
    bp_counter = 0;
    expected_rewrite_stream_word_index = LEGACY_OFFLOAD_REWRITE_STREAM_WORD_INDEX;
    expected_rewrite_mode = REWRITE_MODE_31_16;
    expected_debug_word5_stream_index = LEGACY_DEBUG_WORD5_STREAM_INDEX;
    expected_debug_word6_stream_index = LEGACY_DEBUG_WORD6_STREAM_INDEX;

`ifndef NO_VCD
    $dumpfile("build/user_top_tb.vcd");
    $dumpvars(0, user_top_tb);
`endif

    apply_reset;

    start_test("tc01_reg_path_smoke");
    expect_unknown_reg_passthrough;
    finish_test;

    start_test("tc02_debug_reg_reset_smoke");
    expect_debug_snapshot(ACTION_BYPASS, 32'd0, 32'd0, 16'h0000, 16'h0000);
    expect_debug_words(64'h0, 64'h0, 64'h0);
    finish_test;

    start_test("tc03_opl_format_smoke");
    build_ipv4_udp_packet(8, 0, 16'h0003, 16'h0002, 16'h0101, 16'h0202, 8'h10);
    expect_opl_packet_layout(16'h0003, 16'h0002);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc04_selector_udp_ann_offload_smoke");
    clear_debug_regs;
    build_ipv4_udp_ann_packet(16'h0001, 16'h0008, DEFAULT_REQUEST_ID, 3);
    send_packet(ACTION_OFFLOAD, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_OFFLOAD, 32'd1, 32'd1, ANN_UDP_DST_PORT, ANN_TASK_MAGIC);
    expect_current_debug_words(1);
    finish_test;

    start_test("tc05_selector_wrong_magic_bypass");
    clear_debug_regs;
    build_ipv4_udp_ann_packet_ex(
      16'h0002, 16'h0010, 16'h4002, ANN_UDP_DST_PORT, 16'hBEEF, 16'h2233,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT, DEFAULT_TASK_TYPE, 5
    );
    send_packet(ACTION_BYPASS, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_BYPASS, 32'd0, 32'd0, ANN_UDP_DST_PORT, 16'hBEEF);
    expect_current_debug_words(0);
    finish_test;

    start_test("tc06_selector_wrong_port_bypass");
    build_ipv4_udp_ann_packet_ex(
      16'h0003, 16'h0004, 16'h4003, 16'h9999, ANN_TASK_MAGIC, 16'h3344,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT, DEFAULT_TASK_TYPE, 7
    );
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc07_selector_non_udp_ipv4_bypass");
    build_ipv4_tcp_packet(20, 0, 16'h0001, 16'h0008, 16'h5001, ANN_UDP_DST_PORT, 8'h20);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc08_selector_non_ipv4_ethertype_bypass");
    build_non_ipv4_packet(32, 16'h0002, 16'h0010, ARP_ETHERTYPE, 8'h30);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc09_selector_ip_options_bypass");
    build_ipv4_udp_packet(16, 8, 16'h0003, 16'h0002, 16'h6001, ANN_UDP_DST_PORT, 8'h40);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc10_selector_short_header_bypass");
    build_short_ipv4_udp_prefix_packet(16'h0001, 16'h0008);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc11_selector_backpressure_header_replay");
    bp_mode = BP_HEAVY;
    build_ipv4_udp_ann_packet(16'h0002, 16'h0010, 16'h4455, 9);
    send_packet(ACTION_OFFLOAD, -1, 0, 1);
    finish_test;

    start_test("tc12_selector_back_to_back_mixed");
    build_ipv4_udp_packet(12, 0, 16'h0000, 16'h0004, 16'h7001, 16'h7002, 8'h50);
    send_packet(ACTION_BYPASS, -1, 0, 0);
    build_ipv4_udp_ann_packet(16'h0001, 16'h0008, 16'h5566, 4);
    send_packet(ACTION_OFFLOAD, -1, 0, 0);
    build_ipv4_tcp_packet(24, 0, 16'h0002, 16'h0010, 16'h7003, 16'h7004, 8'h60);
    send_packet(ACTION_BYPASS, -1, 0, 0);
    finish_test;

    start_test("tc13_selector_reset_recovery");
    build_ipv4_udp_ann_packet(16'h0003, 16'h0002, 16'h6677, 6);
    send_packet(ACTION_OFFLOAD, -1, 0, 1);
    wait_for_expected_words(50000);
    apply_reset;
    build_ipv4_udp_packet(10, 0, 16'h0000, 16'h0004, 16'h7101, 16'h7102, 8'h70);
    send_packet(ACTION_BYPASS, -1, 0, 1);
    finish_test;

    start_test("tc14_module_nopad_udp_ann_offload_smoke");
    clear_debug_regs;
    build_ipv4_udp_ann_packet_headers_nopad_ex(
      16'h0001, 16'h0004,
      BOARD_STYLE_DST_MAC, BOARD_STYLE_SRC_MAC,
      BOARD_STYLE_SRC_IP, BOARD_STYLE_DST_IP,
      8'h3f, 16'hfb7f,
      16'h4001, ANN_UDP_DST_PORT,
      ANN_TASK_MAGIC, 16'h1234,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT,
      DEFAULT_TASK_TYPE, 3
    );
    send_packet(ACTION_OFFLOAD, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_OFFLOAD, 32'd1, 32'd1, ANN_UDP_DST_PORT, ANN_TASK_MAGIC);
    expect_current_debug_words(1);
    finish_test;

    start_test("tc15_module_nopad_wrong_magic_bypass");
    clear_debug_regs;
    build_ipv4_udp_ann_packet_headers_nopad_ex(
      16'h0001, 16'h0004,
      BOARD_STYLE_DST_MAC, BOARD_STYLE_SRC_MAC,
      BOARD_STYLE_SRC_IP, BOARD_STYLE_DST_IP,
      8'h3f, 16'hfb7f,
      16'h4001, ANN_UDP_DST_PORT,
      16'hBEEF, 16'h1234,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT,
      DEFAULT_TASK_TYPE, 3
    );
    send_packet(ACTION_BYPASS, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_BYPASS, 32'd0, 32'd0, ANN_UDP_DST_PORT, 16'hBEEF);
    expect_current_debug_words(0);
    finish_test;

    start_test("tc16_raw_nopad_udp_ann_offload_smoke");
    clear_debug_regs;
    build_ipv4_udp_ann_raw_packet_headers_ex(
      BOARD_STYLE_DST_MAC, BOARD_STYLE_SRC_MAC,
      BOARD_STYLE_SRC_IP, BOARD_STYLE_DST_IP,
      8'h3f, 16'hfb7f,
      16'h4001, ANN_UDP_DST_PORT,
      ANN_TASK_MAGIC, 16'h1234,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT,
      DEFAULT_TASK_TYPE, 3
    );
    send_packet(ACTION_OFFLOAD, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_OFFLOAD, 32'd1, 32'd1, ANN_UDP_DST_PORT, ANN_TASK_MAGIC);
    expect_current_debug_words(1);
    finish_test;

    start_test("tc17_raw_nopad_wrong_port_bypass");
    clear_debug_regs;
    build_ipv4_udp_ann_raw_packet_headers_ex(
      BOARD_STYLE_DST_MAC, BOARD_STYLE_SRC_MAC,
      BOARD_STYLE_SRC_IP, BOARD_STYLE_DST_IP,
      8'h3f, 16'hfb7f,
      16'h4001, 16'h9999,
      ANN_TASK_MAGIC, 16'h1234,
      DEFAULT_FEATURE_COUNT, DEFAULT_FEATURE_COUNT,
      DEFAULT_TASK_TYPE, 3
    );
    send_packet(ACTION_BYPASS, -1, 0, 1);
    wait_for_expected_words(50000);
    expect_debug_snapshot(ACTION_BYPASS, 32'd0, 32'd0, 16'h9999, ANN_TASK_MAGIC);
    expect_current_debug_words(0);
    finish_test;

    if (fail_count == 0) begin
      $display("\nPASS: %0d tests completed with no failures", test_count);
      $finish_and_return(0);
    end
    else begin
      $display("\nFAIL: %0d tests completed with %0d failures", test_count, fail_count);
      $finish_and_return(1);
    end
  end

endmodule
