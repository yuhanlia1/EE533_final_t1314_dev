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

  localparam MAX_FRAME_BYTES    = 2048;
  localparam MAX_PKT_WORDS      = 300;
  localparam MAX_EXPECTED_WORDS = 512;
  localparam TEST_NAME_WIDTH    = 64 * 8;

  localparam BP_NONE  = 0;
  localparam BP_LIGHT = 1;
  localparam BP_HEAVY = 2;

  localparam LOG_TX_WORDS    = 1;
  localparam LOG_RX_COMPARE  = 1;
  localparam LOG_PKT_SUMMARY = 1;

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

  reg  [TEST_NAME_WIDTH-1:0]  current_test_name;

  reg                         hold_check_active;
  reg  [DATA_WIDTH-1:0]       held_data;
  reg  [CTRL_WIDTH-1:0]       held_ctrl;

  reg                         store_forward_guard;

  integer                     frame_len;
  integer                     tx_word_count;
  integer                     expected_words;
  integer                     observed_words;
  integer                     fail_count;
  integer                     test_count;
  integer                     packet_count_in_test;
  integer                     bp_mode;
  integer                     bp_counter;
  integer                     cycle_count;

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
      packet_count_in_test = 0;
      hold_check_active = 1'b0;
      store_forward_guard = 1'b0;
    end
  endtask

  task log_packet_summary;
    input integer pkt_idx;
    input integer stall_after_word;
    input integer stall_cycles;
    input integer check_store_forward;
    begin
      if (LOG_PKT_SUMMARY != 0) begin
        $display("[%0t] PKT %0s pkt=%0d frame_bytes=%0d total_words=%0d stall_after=%0d stall_cycles=%0d store_forward_check=%0d",
                 $time, current_test_name, pkt_idx, frame_len, tx_word_count,
                 stall_after_word, stall_cycles, check_store_forward);
        $display("[%0t] PKT %0s pkt=%0d module_header data=%016h ctrl=%02h",
                 $time, current_test_name, pkt_idx, tx_data[0], tx_ctrl[0]);
      end
    end
  endtask

  task append_byte;
    input [7:0] value;
    begin
      if (frame_len >= MAX_FRAME_BYTES) begin
        record_failure("Frame byte buffer overflow");
      end
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

  task append_pattern;
    input integer count;
    input [7:0] seed;
    integer i;
    begin
      for (i = 0; i < count; i = i + 1)
        append_byte(seed + i[7:0]);
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
      byte_len_field = frame_len;
      word_len_field = data_word_count;

      if (tx_word_count > MAX_PKT_WORDS) begin
        record_failure("Packet word buffer overflow");
        tx_word_count = MAX_PKT_WORDS;
      end

      tx_data[0] = {dst_port_mask, word_len_field, src_port, byte_len_field};
      tx_ctrl[0] = 8'hff;

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

  task build_ipv4_udp_packet;
    input integer udp_payload_len;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] udp_src_port;
    input [15:0] udp_dst_port;
    input [7:0] payload_seed;
    integer ip_total_len;
    integer udp_len_field;
    begin
      frame_len = 0;

      append_be32(32'h00112233);
      append_be16(16'h4455);
      append_be32(32'h66778899);
      append_be16(16'haabb);
      append_be16(16'h0800);

      ip_total_len = 20 + 8 + udp_payload_len;
      udp_len_field = 8 + udp_payload_len;
      append_byte(8'h45);
      append_byte(8'h00);
      append_be16(ip_total_len);
      append_be16(16'h1234);
      append_be16(16'h4000);
      append_byte(8'h40);
      append_byte(8'h11);
      append_be16(16'h0000);
      append_be32(32'hc0a80101);
      append_be32(32'hc0a80102);

      append_be16(udp_src_port);
      append_be16(udp_dst_port);
      append_be16(udp_len_field);
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
    integer ip_header_len;
    integer ip_total_len;
    integer ihl_words;
    integer option_idx;
    integer tcp_data_offset;
    begin
      frame_len = 0;

      append_be32(32'h10203040);
      append_be16(16'h5060);
      append_be32(32'h708090a0);
      append_be16(16'hb0c0);
      append_be16(16'h0800);

      ip_header_len = 20 + ip_options_bytes;
      ip_total_len = ip_header_len + 20 + tcp_payload_len;
      ihl_words = ip_header_len / 4;

      append_byte(8'h40 | (ihl_words & 8'h0f));
      append_byte(8'h00);
      append_be16(ip_total_len);
      append_be16(16'h5678);
      append_be16(16'h4000);
      append_byte(8'h40);
      append_byte(8'h06);
      append_be16(16'h0000);
      append_be32(32'h0a000001);
      append_be32(32'h0a000002);

      for (option_idx = 0; option_idx < ip_options_bytes; option_idx = option_idx + 1)
        append_byte(8'he0 + option_idx[7:0]);

      append_be16(tcp_src_port);
      append_be16(tcp_dst_port);
      append_be32(32'h01020304);
      append_be32(32'h05060708);
      tcp_data_offset = 5;
      append_byte((tcp_data_offset & 8'h0f) << 4);
      append_byte(8'h18);
      append_be16(16'h1000);
      append_be16(16'h0000);
      append_be16(16'h0000);

      append_pattern(tcp_payload_len, payload_seed);
      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task expect_reg_passthrough;
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

  task push_expected_word;
    input [DATA_WIDTH-1:0] data_word;
    input [CTRL_WIDTH-1:0] ctrl_word;
    begin
      if (expected_words >= MAX_EXPECTED_WORDS) begin
        record_failure("Expected word buffer overflow");
      end
      else begin
        expected_data[expected_words] = data_word;
        expected_ctrl[expected_words] = ctrl_word;
        expected_words = expected_words + 1;
      end
    end
  endtask

  task drive_idle_cycles;
    input integer count;
    integer i;
    begin
      in_wr   = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
      for (i = 0; i < count; i = i + 1)
        @(posedge clk);
    end
  endtask

  task send_word;
    input [DATA_WIDTH-1:0] data_word;
    input [CTRL_WIDTH-1:0] ctrl_word;
    input integer word_idx;
    input integer pkt_idx;
    begin
      while (in_rdy !== 1'b1)
        @(negedge clk);

      in_data = data_word;
      in_ctrl = ctrl_word;
      in_wr   = 1'b1;

      @(posedge clk);
      if (LOG_TX_WORDS != 0) begin
        $display("[%0t] TX  %0s pkt=%0d word=%0d data=%016h ctrl=%02h",
                 $time, current_test_name, pkt_idx, word_idx, data_word, ctrl_word);
      end
      push_expected_word(data_word, ctrl_word);

      @(negedge clk);
      in_wr   = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
    end
  endtask

  task send_packet;
    input integer stall_after_word;
    input integer stall_cycles;
    input integer check_store_forward;
    integer word_idx;
    integer pkt_idx;
    begin
      packet_count_in_test = packet_count_in_test + 1;
      pkt_idx = packet_count_in_test;
      log_packet_summary(pkt_idx, stall_after_word, stall_cycles, check_store_forward);
      if (check_store_forward != 0)
        store_forward_guard = 1'b1;
      for (word_idx = 0; word_idx < tx_word_count; word_idx = word_idx + 1) begin
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
    begin
      wait_for_expected_words(50000);
      if (observed_words !== expected_words)
        record_failure("Expected/output word counts differ at end of test");

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
      clear_scoreboard;
      repeat (4) @(posedge clk);
      reset = 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

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
    end
    else begin
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
            $display("[%0t] CMP %0s word=%0d unexpected actual_data=%016h actual_ctrl=%02h",
                     $time, current_test_name, observed_words, out_data, out_ctrl);
          end
          record_failure("Unexpected output word observed");
        end
        else begin
          if (LOG_RX_COMPARE != 0) begin
            $display("[%0t] CMP %0s word=%0d exp_data=%016h exp_ctrl=%02h act_data=%016h act_ctrl=%02h %0s",
                     $time, current_test_name, observed_words,
                     expected_data[observed_words], expected_ctrl[observed_words],
                     out_data, out_ctrl,
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
    fail_count = 0;
    test_count = 0;
    packet_count_in_test = 0;
    bp_mode = BP_NONE;
    bp_counter = 0;
    cycle_count = 0;

    $dumpfile("build/user_top_tb.vcd");
    $dumpvars(0, user_top_tb);

    apply_reset;

    // Baseline and interface path.
    start_test("tc01_reg_path_smoke");
    expect_reg_passthrough;
    finish_test;

    start_test("tc02_opl_format_smoke");
    build_ipv4_udp_packet(1, 16'h0003, 16'h0002, 16'h0101, 16'h0202, 8'h01);
    expect_opl_packet_layout(16'h0003, 16'h0002);
    send_packet(-1, 0, 1);
    finish_test;

    // Front-buffer coverage through nominal end-to-end traffic.
    start_test("tc03_front_buffer_single_udp");
    build_ipv4_udp_packet(12, 16'h0000, 16'h0004, 16'h1111, 16'h2222, 8'h10);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc04_front_buffer_single_tcp");
    build_ipv4_tcp_packet(18, 0, 16'h0001, 16'h0008, 16'h3333, 16'h4444, 8'h20);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc05_front_buffer_long_packet");
    build_ipv4_udp_packet(1472, 16'h0002, 16'h0010, 16'h5555, 16'h6666, 8'h30);
    send_packet(-1, 0, 1);
    finish_test;

    // Selector default-bypass coverage.
    start_test("tc06_selector_bypass_tcp_with_ip_options");
    build_ipv4_tcp_packet(15, 8, 16'h0003, 16'h0002, 16'h7777, 16'h8888, 8'h40);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc07_selector_back_to_back_packets");
    build_ipv4_udp_packet(20, 16'h0000, 16'h0004, 16'h1001, 16'h1002, 8'h50);
    send_packet(-1, 0, 0);
    build_ipv4_tcp_packet(32, 0, 16'h0001, 16'h0008, 16'h2001, 16'h2002, 8'h60);
    send_packet(-1, 0, 0);
    build_ipv4_udp_packet(5, 16'h0002, 16'h0010, 16'h3001, 16'h3002, 8'h70);
    send_packet(-1, 0, 0);
    finish_test;

    // Backend-buffer and end-to-end backpressure coverage.
    start_test("tc08_output_light_backpressure");
    bp_mode = BP_LIGHT;
    build_ipv4_udp_packet(64, 16'h0000, 16'h0004, 16'h4001, 16'h4002, 8'h80);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc09_output_heavy_backpressure");
    bp_mode = BP_HEAVY;
    build_ipv4_tcp_packet(48, 0, 16'h0001, 16'h0008, 16'h5001, 16'h5002, 8'h90);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc10_front_buffer_input_stall");
    build_ipv4_udp_packet(96, 16'h0002, 16'h0010, 16'h6001, 16'h6002, 8'ha0);
    send_packet(3, 5, 1);
    finish_test;

    start_test("tc11_min_frame_endword");
    build_ipv4_udp_packet(18, 16'h0000, 16'h0004, 16'h7001, 16'h7002, 8'hb0);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc12_selector_reset_recovery");
    build_ipv4_udp_packet(24, 16'h0003, 16'h0002, 16'h8001, 16'h8002, 8'hc0);
    send_packet(-1, 0, 1);
    wait_for_expected_words(50000);
    apply_reset;
    build_ipv4_tcp_packet(24, 0, 16'h0001, 16'h0008, 16'h9001, 16'h9002, 8'hd0);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc13_mixed_packets_with_backpressure");
    bp_mode = BP_LIGHT;
    build_ipv4_udp_packet(24, 16'h0000, 16'h0004, 16'ha001, 16'ha002, 8'he0);
    send_packet(-1, 0, 0);
    build_ipv4_tcp_packet(40, 8, 16'h0001, 16'h0008, 16'ha101, 16'ha102, 8'he8);
    send_packet(-1, 0, 0);
    build_ipv4_udp_packet(9, 16'h0002, 16'h0010, 16'ha201, 16'ha202, 8'hf0);
    send_packet(-1, 0, 0);
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
