`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif

module tb_user_top_offload;

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
  localparam TEST_TIMEOUT_CYCLES = 200000;

  localparam LOG_TX_WORDS    = 0;
  localparam LOG_RX_COMPARE  = 0;
  localparam LOG_PKT_SUMMARY = 1;
  localparam [15:0] CUSTOM_ETHERTYPE = 16'h88B5;
  localparam [15:0] ANN_TASK_MAGIC   = 16'hA11E;
  localparam [15:0] ANN_RESULT_MAGIC = 16'hA11F;
  localparam [7:0]  ANN_RESULT_VERSION = 8'h01;
  localparam [7:0]  ANN_STATUS_OK = 8'h00;
  localparam [7:0]  ANN_STATUS_TRUNCATED = 8'h05;
  localparam [15:0] ANN_RESULT_TYPE_NN = 16'h0002;
  localparam integer ANN_IN_DIM = 8;
  localparam integer CPU_PROG_DEPTH = 13;
  localparam integer GPU_PROG_DEPTH = 64;
  localparam integer ANN_OUT_DIM = 2;
  localparam [9:0] PIPELINE_BLOCK_TAG = 10'h155;
  localparam [3:0] REG_SW_I_MEM_WDATA       = 4'd1;
  localparam [3:0] REG_SW_I_MEM_ADDR        = 4'd2;
  localparam [3:0] REG_SW_ENGINE_CTRL       = 4'd3;
  localparam [3:0] REG_SW_GPU_I_MEM_WDATA   = 4'd4;
  localparam [3:0] REG_SW_GPU_I_MEM_ADDR    = 4'd5;
  localparam [3:0] REG_SW_GPU_W_MEM_WDATA_1 = 4'd6;
  localparam [3:0] REG_SW_GPU_W_MEM_WDATA_0 = 4'd7;
  localparam [3:0] REG_SW_GPU_W_MEM_ADDR    = 4'd8;
  localparam [3:0] REG_HW_ENGINE_STATUS     = 4'd10;
  localparam integer ACT_BASE_ADDR = 16;
  localparam integer WGT_BASE_ADDR = 64;
  localparam integer BIAS_BASE_ADDR = 96;
  localparam integer Y_OFF = 16;

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
  reg                         auto_expect_tx_words;

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
  integer                     ann_expected_sum;
  integer                     ann_expected_positive_count;
  integer                     ann_feature_count;
  reg  [15:0]                 ann_expected_request_id;
  reg  [7:0]                  result_frame_bytes [0:31];
  reg signed [15:0]           ann_feature_values [0:ANN_IN_DIM-1];
  reg  [31:0]                 cpu_program [0:CPU_PROG_DEPTH-1];
  reg  [31:0]                 gpu_program [0:GPU_PROG_DEPTH-1];
  reg  [15:0]                 ann_weight_values [0:(ANN_OUT_DIM*ANN_IN_DIM)-1];
  reg  [15:0]                 ann_bias_values [0:ANN_OUT_DIM-1];
  integer                     gpu_program_words;

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

  function [31:0] arm_mov_imm;
    input [3:0] rd;
    input [7:0] imm8;
    begin
      arm_mov_imm = 32'hE3A00000 | (rd << 12) | imm8;
    end
  endfunction

  function [31:0] arm_str_imm;
    input [3:0]  rd;
    input [3:0]  rn;
    input [11:0] imm12;
    begin
      arm_str_imm = 32'hE5800000 | (rn << 16) | (rd << 12) | imm12;
    end
  endfunction

  function [31:0] gpu_instr;
    input [3:0]  opcode;
    input [2:0]  rd;
    input [2:0]  rs1;
    input [2:0]  rs2;
    input [1:0]  bsel;
    input        dtype;
    input [15:0] imm;
    begin
      gpu_instr = {opcode, rd, rs1, rs2, bsel, dtype, imm};
    end
  endfunction

  function [`UDP_REG_ADDR_WIDTH-1:0] pipeline_reg_addr;
    input [3:0] reg_word_index;
    begin
      pipeline_reg_addr = {PIPELINE_BLOCK_TAG, reg_word_index, 2'b00};
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

  task write_pipeline_reg;
    input [3:0] reg_word_index;
    input [31:0] write_data;
    begin
      @(negedge clk);
      reg_req_in     = 1'b1;
      reg_ack_in     = 1'b0;
      reg_rd_wr_L_in = 1'b0;
      reg_addr_in    = pipeline_reg_addr(reg_word_index);
      reg_data_in    = write_data;
      reg_src_in     = {UDP_REG_SRC_WIDTH{1'b0}};
      @(posedge clk);
      @(negedge clk);
      reg_req_in     = 1'b0;
      reg_rd_wr_L_in = 1'b1;
      reg_addr_in    = {(`UDP_REG_ADDR_WIDTH){1'b0}};
      reg_data_in    = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
    end
  endtask

  task read_pipeline_reg;
    input [3:0] reg_word_index;
    output [31:0] read_data;
    begin
      @(negedge clk);
      reg_req_in     = 1'b1;
      reg_ack_in     = 1'b0;
      reg_rd_wr_L_in = 1'b1;
      reg_addr_in    = pipeline_reg_addr(reg_word_index);
      reg_data_in    = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
      reg_src_in     = {UDP_REG_SRC_WIDTH{1'b0}};
      @(posedge clk);
      read_data      = reg_data_out;
      @(negedge clk);
      reg_req_in     = 1'b0;
      reg_addr_in    = {(`UDP_REG_ADDR_WIDTH){1'b0}};
    end
  endtask

  task write_cpu_imem_word;
    input integer addr;
    input [31:0] write_data;
    begin
      write_pipeline_reg(REG_SW_I_MEM_ADDR, 32'd0);
      write_pipeline_reg(REG_SW_I_MEM_WDATA, write_data);
      write_pipeline_reg(REG_SW_I_MEM_ADDR, 32'h8000_0000 | addr[31:0]);
      write_pipeline_reg(REG_SW_I_MEM_ADDR, 32'd0);
    end
  endtask

  task write_gpu_imem_word;
    input integer addr;
    input [31:0] write_data;
    begin
      write_pipeline_reg(REG_SW_GPU_I_MEM_ADDR, 32'd0);
      write_pipeline_reg(REG_SW_GPU_I_MEM_WDATA, write_data);
      write_pipeline_reg(REG_SW_GPU_I_MEM_ADDR, 32'h8000_0000 | addr[31:0]);
      write_pipeline_reg(REG_SW_GPU_I_MEM_ADDR, 32'd0);
    end
  endtask

  task write_gpu_param_word;
    input integer addr;
    input [63:0] write_data;
    begin
      write_pipeline_reg(REG_SW_GPU_W_MEM_ADDR, 32'd0);
      write_pipeline_reg(REG_SW_GPU_W_MEM_WDATA_1, write_data[63:32]);
      write_pipeline_reg(REG_SW_GPU_W_MEM_WDATA_0, write_data[31:0]);
      write_pipeline_reg(REG_SW_GPU_W_MEM_ADDR, 32'h8000_0000 | addr[31:0]);
      write_pipeline_reg(REG_SW_GPU_W_MEM_ADDR, 32'd0);
    end
  endtask

  task prepare_ann_programs;
    integer i;
    integer pc;
    integer out_idx;
    integer in_idx;
    begin
      for (i = 0; i < CPU_PROG_DEPTH; i = i + 1)
        cpu_program[i] = 32'hE1A00000;

      for (i = 0; i < GPU_PROG_DEPTH; i = i + 1)
        gpu_program[i] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);

      for (i = 0; i < ANN_IN_DIM; i = i + 1)
        ann_weight_values[i] = ((i % 4) - 1) & 16'hffff;

      for (i = 0; i < ANN_IN_DIM; i = i + 1)
        ann_weight_values[ANN_IN_DIM + i] = (((i + 1) % 5) - 2) & 16'hffff;

      ann_bias_values[0] = 16'sd1;
      ann_bias_values[1] = -16'sd2;

      cpu_program[0]  = arm_mov_imm(4'd10, 8'h80);
      cpu_program[1]  = arm_mov_imm(4'd0,  8'd0);
      cpu_program[2]  = arm_mov_imm(4'd1,  8'd1);
      cpu_program[3]  = arm_mov_imm(4'd2,  ACT_BASE_ADDR[7:0]);
      cpu_program[4]  = arm_mov_imm(4'd3,  WGT_BASE_ADDR[7:0]);
      cpu_program[5]  = arm_mov_imm(4'd4,  BIAS_BASE_ADDR[7:0]);
      cpu_program[6]  = arm_mov_imm(4'd5,  8'd0);
      cpu_program[7]  = arm_str_imm(4'd0,  4'd10, 12'd8);
      cpu_program[8]  = arm_str_imm(4'd1,  4'd10, 12'd16);
      cpu_program[9]  = arm_str_imm(4'd2,  4'd10, 12'd32);
      cpu_program[10] = arm_str_imm(4'd3,  4'd10, 12'd40);
      cpu_program[11] = arm_str_imm(4'd4,  4'd10, 12'd48);
      cpu_program[12] = arm_str_imm(4'd5,  4'd10, 12'd56);

      pc = 0;
      for (out_idx = 0; out_idx < ANN_OUT_DIM; out_idx = out_idx + 1) begin
        gpu_program[pc] = gpu_instr(4'h1, 3'd6, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
        pc = pc + 1;

        for (in_idx = 0; in_idx < ANN_IN_DIM; in_idx = in_idx + 1) begin
          gpu_program[pc] = gpu_instr(4'h2, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, in_idx[15:0]);
          pc = pc + 1;
          gpu_program[pc] = gpu_instr(4'h2, 3'd1, 3'd0, 3'd0, 2'b01, 1'b0,
                                      out_idx * ANN_IN_DIM + in_idx);
          pc = pc + 1;
          gpu_program[pc] = gpu_instr(4'hC, 3'd6, 3'd0, 3'd1, 2'b00, 1'b0, 16'h0000);
          pc = pc + 1;
        end

        gpu_program[pc] = gpu_instr(4'h2, 3'd2, 3'd0, 3'd0, 2'b10, 1'b0, out_idx[15:0]);
        pc = pc + 1;
        gpu_program[pc] = gpu_instr(4'h4, 3'd6, 3'd6, 3'd2, 2'b00, 1'b0, 16'h0000);
        pc = pc + 1;
        gpu_program[pc] = gpu_instr(4'h3, 3'd0, 3'd0, 3'd6, 2'b00, 1'b0, Y_OFF + out_idx);
        pc = pc + 1;
      end
      gpu_program[pc] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
      gpu_program_words = pc + 1;
    end
  endtask

  task init_ann_engine;
    integer i;
    reg [31:0] engine_status;
    begin
      write_pipeline_reg(REG_SW_ENGINE_CTRL, 32'd0);

      for (i = 0; i < CPU_PROG_DEPTH; i = i + 1)
        write_cpu_imem_word(i, cpu_program[i]);

      for (i = 0; i < gpu_program_words; i = i + 1)
        write_gpu_imem_word(i, gpu_program[i]);

      for (i = 0; i < ANN_OUT_DIM * ANN_IN_DIM; i = i + 1)
        write_gpu_param_word(WGT_BASE_ADDR + i, {48'd0, ann_weight_values[i]});

      for (i = 0; i < ANN_OUT_DIM; i = i + 1)
        write_gpu_param_word(BIAS_BASE_ADDR + i, {48'd0, ann_bias_values[i]});

      write_pipeline_reg(REG_SW_ENGINE_CTRL, 32'h0000_0001);
      drive_idle_cycles(8);

      read_pipeline_reg(REG_HW_ENGINE_STATUS, engine_status);
      if (engine_status[0] !== 1'b1)
        record_failure("ANN engine did not become ready after register initialization");
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

  task push_expected_current_tx;
    input integer word_idx;
    begin
      push_expected_word(tx_data[word_idx], tx_ctrl[word_idx]);
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
    integer waited;
    begin
      waited = 0;
      while (in_rdy !== 1'b1) begin
        @(negedge clk);
        waited = waited + 1;
        if (waited > 200000) begin
          $display("[%0t] DEBUG send_word timeout test=%0s pkt=%0d word=%0d in_rdy=%0b ingress_state=%0d selector_state=%0d dispatcher_state=%0d ann_state=%0d egress_state=%0d compute_state=%0d gpu_busy=%0b gpu_done=%0b gpu_done_d=%0b",
                   $time,
                   current_test_name,
                   pkt_idx,
                   word_idx,
                   in_rdy,
                   dut.ingress_fifo.state,
                   dut.selector.state,
                   dut.dispatcher.state,
                   dut.ann_engine.state,
                   dut.egress_fifo.state,
                   dut.ann_engine.compute_core.state,
                   dut.ann_engine.compute_core.gpu_busy,
                   dut.ann_engine.compute_core.gpu_done_level,
                   dut.ann_engine.compute_core.gpu_done_d);
          record_failure("Timed out waiting for in_rdy before sending word");
          disable send_word;
        end
      end

      in_data = data_word;
      in_ctrl = ctrl_word;
      in_wr   = 1'b1;

      @(posedge clk);
      if (LOG_TX_WORDS != 0) begin
        $display("[%0t] TX  %0s pkt=%0d word=%0d data=%016h ctrl=%02h",
                 $time, current_test_name, pkt_idx, word_idx, data_word, ctrl_word);
      end
      if (auto_expect_tx_words)
        push_expected_word(data_word, ctrl_word);

      @(negedge clk);
      in_wr   = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
    end
  endtask

  task build_ann_ethertype_packet_ex;
    input integer feature_count_field;
    input integer emitted_feature_count;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] request_id;
    input integer feature_seed;
    input [15:0] task_magic;
    input [15:0] task_type;
    integer i;
    integer feature_val;
    integer bias0;
    integer bias1;
    begin
      frame_len = 0;
      ann_expected_request_id = request_id;
      ann_expected_sum = 0;
      ann_expected_positive_count = 0;
      ann_feature_count = emitted_feature_count;

      for (i = 0; i < ANN_IN_DIM; i = i + 1)
        ann_feature_values[i] = 16'sd0;

      append_byte(8'h00);
      append_byte(8'h00);
      append_be32(32'h0badc0de);
      append_be16(16'h0001);
      append_be32(32'hf00dcafe);
      append_be16(16'h0002);
      append_be16(CUSTOM_ETHERTYPE);

      append_be16(task_magic);
      append_be16(request_id);
      append_be16(feature_count_field[15:0]);
      append_be16(task_type);

      for (i = 0; i < emitted_feature_count; i = i + 1) begin
        if ((i % 2) == 0)
          feature_val = feature_seed + i + 1;
        else
          feature_val = -(feature_seed + i + 1);

        if (i < ANN_IN_DIM)
          ann_feature_values[i] = feature_val[15:0];

        append_be16(feature_val[15:0]);
      end

      bias0 = 1;
      bias1 = -2;
      ann_expected_sum = bias0;
      ann_expected_positive_count = bias1;
      for (i = 0; i < ANN_IN_DIM; i = i + 1) begin
        ann_expected_sum = ann_expected_sum + ann_feature_values[i] * ((i % 4) - 1);
        ann_expected_positive_count = ann_expected_positive_count + ann_feature_values[i] * (((i + 1) % 5) - 2);
      end

      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task build_ann_ethertype_packet;
    input integer feature_count;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] request_id;
    input integer feature_seed;
    begin
      build_ann_ethertype_packet_ex(
        feature_count,
        feature_count,
        src_port,
        dst_port_mask,
        request_id,
        feature_seed,
        ANN_TASK_MAGIC,
        16'h0000
      );
    end
  endtask

  task expect_ann_result_packet;
    input [15:0] exp_src_port;
    input [15:0] exp_dst_port_mask;
    input [7:0] exp_status;
    integer i;
    integer valid_bytes;
    integer word_idx;
    integer lane;
    reg [63:0] packed_word;
    reg [15:0] result_a;
    reg [15:0] result_b;
    begin
      result_a = ann_expected_sum[15:0];
      result_b = ann_expected_positive_count[15:0];

      for (i = 0; i < 32; i = i + 1)
        result_frame_bytes[i] = 8'h00;

      for (i = 0; i < 16; i = i + 1)
        result_frame_bytes[i] = frame_bytes[i];

      result_frame_bytes[16] = ANN_RESULT_MAGIC[15:8];
      result_frame_bytes[17] = ANN_RESULT_MAGIC[7:0];
      result_frame_bytes[18] = ANN_RESULT_VERSION;
      result_frame_bytes[19] = exp_status;
      result_frame_bytes[20] = ann_expected_request_id[15:8];
      result_frame_bytes[21] = ann_expected_request_id[7:0];
      result_frame_bytes[22] = ANN_RESULT_TYPE_NN[15:8];
      result_frame_bytes[23] = ANN_RESULT_TYPE_NN[7:0];
      result_frame_bytes[24] = 8'h00;
      result_frame_bytes[25] = 8'h04;
      result_frame_bytes[26] = result_a[15:8];
      result_frame_bytes[27] = result_a[7:0];
      result_frame_bytes[28] = result_b[15:8];
      result_frame_bytes[29] = result_b[7:0];

      push_expected_word({exp_dst_port_mask, 16'd4, exp_src_port, 16'd30}, 8'hff);

      for (word_idx = 0; word_idx < 4; word_idx = word_idx + 1) begin
        packed_word = 64'h0;
        valid_bytes = 30 - (word_idx * 8);
        if (valid_bytes > 8)
          valid_bytes = 8;

        for (lane = 0; lane < valid_bytes; lane = lane + 1)
          packed_word = packed_word |
                        ({56'h0, result_frame_bytes[word_idx * 8 + lane]} << (56 - lane * 8));

        if (word_idx == 3)
          push_expected_word(packed_word, eop_ctrl(valid_bytes));
        else
          push_expected_word(packed_word, 8'h00);
      end
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

  task expect_cpu_replay_matches_tx;
    input integer timeout_cycles;
    integer waited;
    integer replay_word_idx;
    begin : replay_block
      waited = 0;
      replay_word_idx = 0;
      while (replay_word_idx < tx_word_count) begin
        @(posedge clk);
        waited = waited + 1;
        if (dut.ann_engine.compute_core.cpu_nw_in_wr &&
            dut.ann_engine.compute_core.cpu_nw_in_rdy) begin
          if (dut.ann_engine.compute_core.cpu_nw_in_data !== tx_data[replay_word_idx])
            record_failure("CPU replay data mismatch");
          if (dut.ann_engine.compute_core.cpu_nw_in_ctrl !== tx_ctrl[replay_word_idx])
            record_failure("CPU replay ctrl mismatch");
          replay_word_idx = replay_word_idx + 1;
        end
        if (waited > timeout_cycles) begin
          record_failure("Timed out waiting for CPU replay words");
          disable replay_block;
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
      auto_expect_tx_words = 1'b1;
      $display("\nTEST %0d START %0s", test_count, current_test_name);
      drive_idle_cycles(3);
    end
  endtask

  task finish_test;
    integer idle_cycles;
    begin
      wait_for_expected_words(TEST_TIMEOUT_CYCLES);
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
    auto_expect_tx_words = 1'b1;
    ann_expected_sum = 0;
    ann_expected_positive_count = 0;
    ann_feature_count = 0;
    ann_expected_request_id = 16'd0;
    gpu_program_words = 0;

`ifndef NO_VCD
    $dumpfile("tb_user_top_offload.vcd");
    $dumpvars(0, tb_user_top_offload);
`endif

    prepare_ann_programs;
    apply_reset;

    init_ann_engine;

    start_test("tc01_ann_ethertype_offload_smoke");
    auto_expect_tx_words = 1'b0;
    build_ann_ethertype_packet(8, 16'h0001, 16'h0008, 16'h1234, 3);
    expect_ann_result_packet(16'h0001, 16'h0008, ANN_STATUS_OK);
    send_packet(-1, 0, 1);
    expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
    finish_test;

    start_test("tc02_ann_ethertype_mixed_with_bypass");
    build_ipv4_udp_packet(16, 16'h0000, 16'h0004, 16'hb001, 16'hb002, 8'h11);
    auto_expect_tx_words = 1'b1;
    send_packet(-1, 0, 0);
    build_ann_ethertype_packet(8, 16'h0002, 16'h0010, 16'h5678, 5);
    auto_expect_tx_words = 1'b0;
    expect_ann_result_packet(16'h0002, 16'h0010, ANN_STATUS_OK);
    send_packet(-1, 0, 0);
    build_ipv4_tcp_packet(20, 0, 16'h0003, 16'h0002, 16'hc001, 16'hc002, 8'h22);
    auto_expect_tx_words = 1'b1;
    send_packet(-1, 0, 0);
    finish_test;

    start_test("tc03_ann_wrong_magic_bypasses");
    auto_expect_tx_words = 1'b1;
    build_ann_ethertype_packet_ex(4, 4, 16'h0001, 16'h0008, 16'h9abc, 2, 16'hbeef, 16'h0000);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc04_ann_truncated_payload_status");
    auto_expect_tx_words = 1'b0;
    build_ann_ethertype_packet_ex(8, 5, 16'h0002, 16'h0010, 16'h2468, 4, ANN_TASK_MAGIC, 16'h0000);
    expect_ann_result_packet(16'h0002, 16'h0010, ANN_STATUS_TRUNCATED);
    send_packet(-1, 0, 1);
    expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
    finish_test;

    start_test("tc05_ann_offload_backpressure");
    bp_mode = BP_HEAVY;
    auto_expect_tx_words = 1'b0;
    build_ann_ethertype_packet(8, 16'h0003, 16'h0002, 16'h55aa, 6);
    expect_ann_result_packet(16'h0003, 16'h0002, ANN_STATUS_OK);
    send_packet(-1, 0, 1);
    finish_test;

    start_test("tc06_ann_repeated_offload");
    auto_expect_tx_words = 1'b0;
    build_ann_ethertype_packet(8, 16'h0001, 16'h0008, 16'h1357, 7);
    expect_ann_result_packet(16'h0001, 16'h0008, ANN_STATUS_OK);
    send_packet(-1, 0, 1);
    expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
    build_ann_ethertype_packet(8, 16'h0002, 16'h0010, 16'h2468, 8);
    expect_ann_result_packet(16'h0002, 16'h0010, ANN_STATUS_OK);
    send_packet(-1, 0, 1);
    expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
    finish_test;

    if (fail_count == 0) begin
      $display("\n[TB] === PASS: user_top offload end-to-end scenarios completed ===");
      $finish_and_return(0);
    end
    else begin
      $display("\nFAIL: %0d tests completed with %0d failures", test_count, fail_count);
      $finish_and_return(1);
    end
  end

endmodule
