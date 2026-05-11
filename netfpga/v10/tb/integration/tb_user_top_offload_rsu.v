`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif

module tb_user_top_offload_rsu;

  localparam DATA_WIDTH = 64;
  localparam CTRL_WIDTH = DATA_WIDTH / 8;
  localparam UDP_REG_SRC_WIDTH = 2;

  localparam MAX_FRAME_BYTES = 2048;
  localparam MAX_PKT_WORDS = 300;
  localparam MAX_EXPECTED_WORDS = 512;
  localparam TEST_NAME_WIDTH = 80 * 8;
  localparam TEST_TIMEOUT_CYCLES = 400000;

  localparam integer ANN_IN_DIM = 20;
  localparam integer SAMPLE_WORDS_PER_ENTRY = 23;
  localparam integer MAX_SAMPLE_COUNT = 8;
  localparam integer MAX_SAMPLE_WORDS = MAX_SAMPLE_COUNT * SAMPLE_WORDS_PER_ENTRY;
  localparam integer MAX_CPU_IMAGE_WORDS = 256;
  localparam integer MAX_GPU_IMEM_WORDS = 8192;
  localparam integer MAX_GPU_PARAM_WORDS = 8192;

  localparam BP_NONE = 0;
  localparam BP_PERIODIC = 1;

  localparam [15:0] ANN_UDP_DST_PORT = 16'h88B5;
  localparam [15:0] ANN_TASK_MAGIC = 16'hA11E;
  localparam [15:0] ANN_RESULT_MAGIC = 16'hA11F;
  localparam [7:0] ANN_RESULT_VERSION = 8'h01;
  localparam [7:0] ANN_STATUS_OK = 8'h00;
  localparam [15:0] ANN_RESULT_TYPE_NN = 16'h0002;

  localparam [47:0] TEST_ETH_DST = 48'h001122334455;
  localparam [47:0] TEST_ETH_SRC = 48'h66778899aabb;
  localparam [31:0] TEST_IP_SRC = 32'hc0a80101;
  localparam [31:0] TEST_IP_DST = 32'hc0a80102;
  localparam [15:0] TEST_ANN_UDP_SRC_PORT = 16'h4000;

  localparam integer RESULT_WORD0_TX_IDX = 6;
  localparam integer RESULT_WORD1_TX_IDX = 7;

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
  localparam [31:0] ENGINE_CTRL_DEBUG_CLEAR_MASK = 32'h0000_0004;

  reg clk;
  reg reset;

  reg [DATA_WIDTH-1:0] in_data;
  reg [CTRL_WIDTH-1:0] in_ctrl;
  reg in_wr;
  wire in_rdy;

  wire [DATA_WIDTH-1:0] out_data;
  wire [CTRL_WIDTH-1:0] out_ctrl;
  wire out_wr;
  reg out_rdy;

  reg reg_req_in;
  reg reg_ack_in;
  reg reg_rd_wr_L_in;
  reg [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in;
  reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in;
  reg [UDP_REG_SRC_WIDTH-1:0] reg_src_in;

  wire reg_req_out;
  wire reg_ack_out;
  wire reg_rd_wr_L_out;
  wire [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out;
  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out;
  wire [UDP_REG_SRC_WIDTH-1:0] reg_src_out;

  reg [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];
  reg [DATA_WIDTH-1:0] tx_data [0:MAX_PKT_WORDS-1];
  reg [CTRL_WIDTH-1:0] tx_ctrl [0:MAX_PKT_WORDS-1];
  reg [DATA_WIDTH-1:0] expected_data [0:MAX_EXPECTED_WORDS-1];
  reg [CTRL_WIDTH-1:0] expected_ctrl [0:MAX_EXPECTED_WORDS-1];
  reg [TEST_NAME_WIDTH-1:0] current_test_name;

  reg [31:0] cpu_image_words [0:MAX_CPU_IMAGE_WORDS-1];
  reg [31:0] gpu_imem_words [0:MAX_GPU_IMEM_WORDS-1];
  reg [63:0] gpu_param_words [0:MAX_GPU_PARAM_WORDS-1];
  reg [15:0] sample_words [0:MAX_SAMPLE_WORDS-1];

  reg [1023:0] cpu_image_file;
  reg [1023:0] gpu_imem_file;
  reg [1023:0] gpu_params_file;
  reg [1023:0] sample_words_file;

  integer cpu_image_count;
  integer gpu_imem_count;
  integer gpu_params_base;
  integer gpu_params_count;
  integer sample_count;
  integer runtime_result_base;
  integer runtime_output_count;

  reg hold_check_active;
  reg [DATA_WIDTH-1:0] held_data;
  reg [CTRL_WIDTH-1:0] held_ctrl;
  reg store_forward_guard;
  reg auto_expect_tx_words;

  integer frame_len;
  integer tx_word_count;
  integer expected_words;
  integer observed_words;
  integer fail_count;
  integer test_count;
  integer packet_count_in_test;
  integer bp_mode;
  integer bp_counter;
  integer batch_sample_idx;

  reg [15:0] current_request_id;
  reg [15:0] current_expected_class;
  reg [15:0] current_expected_score;

  user_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) dut (
    .in_data(in_data),
    .in_ctrl(in_ctrl),
    .in_wr(in_wr),
    .in_rdy(in_rdy),
    .out_data(out_data),
    .out_ctrl(out_ctrl),
    .out_wr(out_wr),
    .out_rdy(out_rdy),
    .reg_req_in(reg_req_in),
    .reg_ack_in(reg_ack_in),
    .reg_rd_wr_L_in(reg_rd_wr_L_in),
    .reg_addr_in(reg_addr_in),
    .reg_data_in(reg_data_in),
    .reg_src_in(reg_src_in),
    .reg_req_out(reg_req_out),
    .reg_ack_out(reg_ack_out),
    .reg_rd_wr_L_out(reg_rd_wr_L_out),
    .reg_addr_out(reg_addr_out),
    .reg_data_out(reg_data_out),
    .reg_src_out(reg_src_out),
    .clk(clk),
    .reset(reset)
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

  function [`UDP_REG_ADDR_WIDTH-1:0] pipeline_reg_addr;
    input [3:0] reg_word_index;
    begin
      pipeline_reg_addr = {PIPELINE_BLOCK_TAG, reg_word_index, 2'b00};
    end
  endfunction

  function integer sample_word_index;
    input integer sample_idx;
    input integer word_offset;
    begin
      sample_word_index = sample_idx * SAMPLE_WORDS_PER_ENTRY + word_offset;
    end
  endfunction

  task record_failure;
    input [TEST_NAME_WIDTH-1:0] message;
    begin
      fail_count = fail_count + 1;
      $display("[%0t] FAIL %0s -- %0s", $time, current_test_name, message);
    end
  endtask

  task require_plusarg_string;
    input [8*64-1:0] key;
    output [1023:0] value;
    reg ok;
    begin
      ok = $value$plusargs({key, "=%s"}, value);
      if (!ok) begin
        $display("[TB] missing required plusarg: %0s", key);
        $finish(1);
      end
    end
  endtask

  task require_plusarg_int;
    input [8*64-1:0] key;
    output integer value;
    reg ok;
    begin
      ok = $value$plusargs({key, "=%d"}, value);
      if (!ok) begin
        $display("[TB] missing required plusarg: %0s", key);
        $finish(1);
      end
    end
  endtask

  task load_runtime_configuration;
    begin
      require_plusarg_string("cpu_image_file", cpu_image_file);
      require_plusarg_string("gpu_imem_file", gpu_imem_file);
      require_plusarg_string("gpu_params_file", gpu_params_file);
      require_plusarg_string("sample_words_file", sample_words_file);
      require_plusarg_int("cpu_image_count", cpu_image_count);
      require_plusarg_int("gpu_imem_count", gpu_imem_count);
      require_plusarg_int("gpu_params_base", gpu_params_base);
      require_plusarg_int("gpu_params_count", gpu_params_count);
      require_plusarg_int("sample_count", sample_count);
      require_plusarg_int("result_base", runtime_result_base);
      require_plusarg_int("output_count", runtime_output_count);

      if (cpu_image_count <= 0 || cpu_image_count > MAX_CPU_IMAGE_WORDS)
        begin
          $display("[TB] invalid cpu_image_count=%0d", cpu_image_count);
          $finish(1);
        end
      if (gpu_imem_count <= 0 || gpu_imem_count > MAX_GPU_IMEM_WORDS)
        begin
          $display("[TB] invalid gpu_imem_count=%0d", gpu_imem_count);
          $finish(1);
        end
      if (gpu_params_count <= 0 || gpu_params_count > MAX_GPU_PARAM_WORDS)
        begin
          $display("[TB] invalid gpu_params_count=%0d", gpu_params_count);
          $finish(1);
        end
      if (sample_count <= 0 || sample_count > MAX_SAMPLE_COUNT)
        begin
          $display("[TB] invalid sample_count=%0d", sample_count);
          $finish(1);
        end
      if (runtime_output_count != 4)
        begin
          $display("[TB] unexpected runtime_output_count=%0d", runtime_output_count);
          $finish(1);
        end
    end
  endtask

  task load_bundle_memories;
    begin
      $readmemh(cpu_image_file, cpu_image_words);
      $readmemh(gpu_imem_file, gpu_imem_words);
      $readmemh(gpu_params_file, gpu_param_words);
      $readmemh(sample_words_file, sample_words);
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

  task finalize_packet;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    integer data_word_count;
    integer word_idx;
    integer byte_idx;
    integer valid_bytes;
    integer lane;
    reg [63:0] packed_word;
    begin
      data_word_count = (frame_len + 7) / 8;
      tx_word_count = data_word_count + 1;
      tx_data[0] = {dst_port_mask, data_word_count[15:0], src_port, frame_len[15:0]};
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
      in_wr = 1'b0;
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
          record_failure("Timed out waiting for in_rdy before sending word");
          disable send_word;
        end
      end

      in_data = data_word;
      in_ctrl = ctrl_word;
      in_wr = 1'b1;
      @(posedge clk);
      if (auto_expect_tx_words)
        push_expected_word(data_word, ctrl_word);
      @(negedge clk);
      in_wr = 1'b0;
      in_data = 64'h0;
      in_ctrl = 8'h00;
    end
  endtask

  task send_packet;
    integer word_idx;
    integer pkt_idx;
    begin
      packet_count_in_test = packet_count_in_test + 1;
      pkt_idx = packet_count_in_test;
      for (word_idx = 0; word_idx < tx_word_count; word_idx = word_idx + 1)
        send_word(tx_data[word_idx], tx_ctrl[word_idx], word_idx, pkt_idx);
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
          $display("[%0t] DEBUG %0s wait_for_expected_words timeout observed=%0d expected=%0d ann_state=%0d compute_state=%0d parse_done=%0b compute_done=%0b parse_status=%02h result_status=%02h gpu_busy=%0b gpu_done=%0b",
                   $time,
                   current_test_name,
                   observed_words,
                   expected_words,
                   dut.ann_engine.state,
                   dut.ann_engine.compute_core.state,
                   dut.ann_engine.parse_done,
                   dut.ann_engine.compute_done,
                   dut.ann_engine.parse_status,
                   dut.ann_engine.compute_result_status,
                   dut.ann_engine.compute_core.gpu_busy,
                   dut.ann_engine.compute_core.gpu_done_level);
          record_failure("Timed out waiting for packet drain");
          disable wait_block;
        end
      end
    end
  endtask

  task write_pipeline_reg;
    input [3:0] reg_word_index;
    input [31:0] write_data;
    begin
      @(negedge clk);
      reg_req_in = 1'b1;
      reg_ack_in = 1'b0;
      reg_rd_wr_L_in = 1'b0;
      reg_addr_in = pipeline_reg_addr(reg_word_index);
      reg_data_in = write_data;
      reg_src_in = {UDP_REG_SRC_WIDTH{1'b0}};
      @(posedge clk);
      @(negedge clk);
      reg_req_in = 1'b0;
      reg_rd_wr_L_in = 1'b1;
      reg_addr_in = {(`UDP_REG_ADDR_WIDTH){1'b0}};
      reg_data_in = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
    end
  endtask

  task read_pipeline_reg;
    input [3:0] reg_word_index;
    output [31:0] read_data;
    begin
      @(negedge clk);
      reg_req_in = 1'b1;
      reg_ack_in = 1'b0;
      reg_rd_wr_L_in = 1'b1;
      reg_addr_in = pipeline_reg_addr(reg_word_index);
      reg_data_in = {(`CPCI_NF2_DATA_WIDTH){1'b0}};
      reg_src_in = {UDP_REG_SRC_WIDTH{1'b0}};
      @(posedge clk);
      read_data = reg_data_out;
      @(negedge clk);
      reg_req_in = 1'b0;
      reg_addr_in = {(`UDP_REG_ADDR_WIDTH){1'b0}};
    end
  endtask

  task write_engine_ctrl;
    input [31:0] value;
    begin
      write_pipeline_reg(REG_SW_ENGINE_CTRL, value);
    end
  endtask

  task clear_debug_counters;
    reg [31:0] ctrl_value;
    begin
      read_pipeline_reg(REG_SW_ENGINE_CTRL, ctrl_value);
      write_engine_ctrl(ctrl_value | ENGINE_CTRL_DEBUG_CLEAR_MASK);
      write_engine_ctrl(ctrl_value & ~ENGINE_CTRL_DEBUG_CLEAR_MASK);
      drive_idle_cycles(2);
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

  task init_ann_engine_from_bundle;
    integer i;
    reg [31:0] engine_status;
    reg [31:0] engine_ctrl_value;
    begin
      write_engine_ctrl(32'd0);

      for (i = 0; i < cpu_image_count; i = i + 1)
        write_cpu_imem_word(i, cpu_image_words[i]);

      for (i = 0; i < gpu_imem_count; i = i + 1)
        write_gpu_imem_word(i, gpu_imem_words[i]);

      for (i = 0; i < gpu_params_count; i = i + 1)
        write_gpu_param_word(gpu_params_base + i, gpu_param_words[i]);

      engine_ctrl_value = ((runtime_result_base & 16'hffff) << 16) |
                          ((runtime_output_count & 8'hff) << 8) |
                          32'h0000_0003;
      write_engine_ctrl(engine_ctrl_value);
      drive_idle_cycles(8);

      read_pipeline_reg(REG_HW_ENGINE_STATUS, engine_status);
      if (engine_status[0] !== 1'b1)
        record_failure("ANN engine did not become ready after bundle initialization");
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
          $display("[%0t] DEBUG %0s cpu_replay timeout idx=%0d tx_word_count=%0d ann_state=%0d compute_state=%0d gpu_busy=%0b cpu_done=%0b",
                   $time,
                   current_test_name,
                   replay_word_idx,
                   tx_word_count,
                   dut.ann_engine.state,
                   dut.ann_engine.compute_core.state,
                   dut.ann_engine.compute_core.gpu_busy,
                   dut.ann_engine.compute_core.cpu_done_pulse);
          record_failure("Timed out waiting for CPU replay words");
          disable replay_block;
        end
      end
    end
  endtask

  task expect_debug_snapshot;
    input integer expected_packet_count;
    input integer last_sample_idx;
    input [31:0] expected_flags;
    reg [31:0] expected_request_id;
    begin
      expected_request_id = {16'd0, sample_words[sample_word_index(last_sample_idx, 0)]};
      if (dut.hw_dbg_offload_accept_count !== expected_packet_count[31:0]) begin
        $display("[%0t] DEBUG %0s hw_dbg_offload_accept_count expected=%08h actual=%08h",
                 $time, current_test_name, expected_packet_count[31:0], dut.hw_dbg_offload_accept_count);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_frame_hold_count !== expected_packet_count[31:0]) begin
        $display("[%0t] DEBUG %0s hw_dbg_frame_hold_count expected=%08h actual=%08h",
                 $time, current_test_name, expected_packet_count[31:0], dut.hw_dbg_frame_hold_count);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_compute_start_count !== expected_packet_count[31:0]) begin
        $display("[%0t] DEBUG %0s hw_dbg_compute_start_count expected=%08h actual=%08h",
                 $time, current_test_name, expected_packet_count[31:0], dut.hw_dbg_compute_start_count);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_compute_done_count !== expected_packet_count[31:0]) begin
        $display("[%0t] DEBUG %0s hw_dbg_compute_done_count expected=%08h actual=%08h",
                 $time, current_test_name, expected_packet_count[31:0], dut.hw_dbg_compute_done_count);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_result_emit_count !== expected_packet_count[31:0]) begin
        $display("[%0t] DEBUG %0s hw_dbg_result_emit_count expected=%08h actual=%08h",
                 $time, current_test_name, expected_packet_count[31:0], dut.hw_dbg_result_emit_count);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_last_parse_request_id !== expected_request_id) begin
        $display("[%0t] DEBUG %0s hw_dbg_last_parse_request_id expected=%08h actual=%08h",
                 $time, current_test_name, expected_request_id, dut.hw_dbg_last_parse_request_id);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_last_compute_request_id !== expected_request_id) begin
        $display("[%0t] DEBUG %0s hw_dbg_last_compute_request_id expected=%08h actual=%08h",
                 $time, current_test_name, expected_request_id, dut.hw_dbg_last_compute_request_id);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_last_emit_request_id !== expected_request_id) begin
        $display("[%0t] DEBUG %0s hw_dbg_last_emit_request_id expected=%08h actual=%08h",
                 $time, current_test_name, expected_request_id, dut.hw_dbg_last_emit_request_id);
        record_failure("Debug register mismatch");
      end
      if (dut.hw_dbg_flags !== expected_flags) begin
        $display("[%0t] DEBUG %0s hw_dbg_flags expected=%08h actual=%08h",
                 $time, current_test_name, expected_flags, dut.hw_dbg_flags);
        record_failure("Debug register mismatch");
      end
    end
  endtask

  task build_ann_udp_packet_for_sample;
    input integer sample_idx;
    input [15:0] src_port;
    input [15:0] dst_port_mask;
    input [15:0] task_magic;
    input [15:0] udp_dst_port;
    integer i;
    integer payload_len;
    integer ip_total_len;
    integer udp_len_field;
    begin
      if (sample_idx >= sample_count) begin
        record_failure("Requested sample index exceeds loaded sample_count");
        disable build_ann_udp_packet_for_sample;
      end

      frame_len = 0;
      current_request_id = sample_words[sample_word_index(sample_idx, 0)];
      current_expected_class = sample_words[sample_word_index(sample_idx, 1)];
      current_expected_score = sample_words[sample_word_index(sample_idx, 2)];

      payload_len = 8 + (ANN_IN_DIM * 2);
      ip_total_len = 20 + 8 + payload_len;
      udp_len_field = 8 + payload_len;

      append_be32(TEST_ETH_DST[47:16]);
      append_be16(TEST_ETH_DST[15:0]);
      append_be32(TEST_ETH_SRC[47:16]);
      append_be16(TEST_ETH_SRC[15:0]);
      append_be16(16'h0800);

      append_byte(8'h45);
      append_byte(8'h00);
      append_be16(ip_total_len);
      append_be16(16'h1234);
      append_be16(16'h4000);
      append_byte(8'h40);
      append_byte(8'h11);
      append_be16(16'h0000);
      append_be32(TEST_IP_SRC);
      append_be32(TEST_IP_DST);

      append_be16(TEST_ANN_UDP_SRC_PORT);
      append_be16(udp_dst_port);
      append_be16(udp_len_field);
      append_be16(16'h0000);

      append_be16(task_magic);
      append_be16(current_request_id);
      append_be16(ANN_IN_DIM[15:0]);
      append_be16(16'h0000);

      for (i = 0; i < ANN_IN_DIM; i = i + 1)
        append_be16(sample_words[sample_word_index(sample_idx, 3 + i)]);

      finalize_packet(src_port, dst_port_mask);
    end
  endtask

  task expect_ann_result_packet_words;
    input [7:0] exp_status;
    input [15:0] exp_result_a;
    input [15:0] exp_result_b;
    integer word_idx;
    reg [63:0] result_word_0;
    reg [63:0] result_word_1;
    begin
      if (tx_word_count <= RESULT_WORD1_TX_IDX) begin
        record_failure("ANN packet too short for result rewrite");
      end
      else begin
        result_word_0 = {
          tx_data[RESULT_WORD0_TX_IDX][63:48],
          ANN_RESULT_MAGIC,
          ANN_RESULT_VERSION,
          exp_status,
          current_request_id
        };
        result_word_1 = {ANN_RESULT_TYPE_NN, 16'd4, exp_result_a, exp_result_b};

        for (word_idx = 0; word_idx < tx_word_count; word_idx = word_idx + 1) begin
          if (word_idx == RESULT_WORD0_TX_IDX)
            push_expected_word(result_word_0, tx_ctrl[word_idx]);
          else if (word_idx == RESULT_WORD1_TX_IDX)
            push_expected_word(result_word_1, tx_ctrl[word_idx]);
          else
            push_expected_word(tx_data[word_idx], tx_ctrl[word_idx]);
        end
      end
    end
  endtask

  task expect_ann_compact_result_packet;
    input [7:0] exp_status;
    begin
      expect_ann_result_packet_words(exp_status, current_expected_class, current_expected_score);
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
    if (reset) begin
      bp_counter <= 0;
      out_rdy <= 1'b0;
    end
    else begin
      bp_counter <= bp_counter + 1;
      case (bp_mode)
        BP_PERIODIC: out_rdy <= (bp_counter[1:0] == 2'b11);
        default: out_rdy <= 1'b1;
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
          record_failure("Unexpected output word observed");
        end
        else begin
          if (out_data !== expected_data[observed_words]) begin
            $display("[%0t] DEBUG %0s word=%0d exp_data=%016h act_data=%016h exp_ctrl=%02h act_ctrl=%02h result0=%04h result1=%04h",
                     $time,
                     current_test_name,
                     observed_words,
                     expected_data[observed_words],
                     out_data,
                     expected_ctrl[observed_words],
                     out_ctrl,
                     dut.ann_engine.compute_result_data_0,
                     dut.ann_engine.compute_result_data_1);
            record_failure("Output data mismatch");
          end
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
    auto_expect_tx_words = 1'b1;
    current_request_id = 16'd0;
    current_expected_class = 16'd0;
    current_expected_score = 16'd0;

`ifndef NO_VCD
    $dumpfile("tb_user_top_offload_rsu.vcd");
    $dumpvars(0, tb_user_top_offload_rsu);
`endif

    load_runtime_configuration;
    load_bundle_memories;
    apply_reset;
    init_ann_engine_from_bundle;

    start_test("tc01_rsu_offload_sample0");
    auto_expect_tx_words = 1'b0;
    build_ann_udp_packet_for_sample(0, 16'h0001, 16'h0008, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
    expect_ann_compact_result_packet(ANN_STATUS_OK);
    send_packet;
    expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
    finish_test;

    if (sample_count > 1) begin
      start_test("tc02_rsu_offload_multiple");
      auto_expect_tx_words = 1'b0;
      build_ann_udp_packet_for_sample(1, 16'h0002, 16'h0010, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
      expect_ann_compact_result_packet(ANN_STATUS_OK);
      send_packet;
      expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
      if (sample_count > 2) begin
        build_ann_udp_packet_for_sample(2, 16'h0003, 16'h0002, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
        expect_ann_compact_result_packet(ANN_STATUS_OK);
        send_packet;
        expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
      end
      finish_test;
    end

    start_test("tc03_rsu_wrong_magic_bypass");
    auto_expect_tx_words = 1'b1;
    build_ann_udp_packet_for_sample(0, 16'h0001, 16'h0008, 16'hBEEF, ANN_UDP_DST_PORT);
    send_packet;
    finish_test;

    start_test("tc04_rsu_wrong_port_bypass");
    auto_expect_tx_words = 1'b1;
    build_ann_udp_packet_for_sample(0, 16'h0001, 16'h0008, ANN_TASK_MAGIC, 16'h9999);
    send_packet;
    finish_test;

    if (sample_count > 3) begin
      start_test("tc05_rsu_offload_batch4");
      auto_expect_tx_words = 1'b0;
      clear_debug_counters;
      for (batch_sample_idx = 0; batch_sample_idx < 4; batch_sample_idx = batch_sample_idx + 1) begin
        build_ann_udp_packet_for_sample(batch_sample_idx, 16'h0001, 16'h0008, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
        expect_ann_compact_result_packet(ANN_STATUS_OK);
        send_packet;
        expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
      end
      finish_test;
      expect_debug_snapshot(4, 3, 32'd0);
    end

    if (sample_count > 2) begin
      start_test("tc06_rsu_offload_batch3_debug");
      auto_expect_tx_words = 1'b0;
      clear_debug_counters;
      for (batch_sample_idx = 0; batch_sample_idx < 3; batch_sample_idx = batch_sample_idx + 1) begin
        build_ann_udp_packet_for_sample(batch_sample_idx, 16'h0001, 16'h0008, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
        expect_ann_compact_result_packet(ANN_STATUS_OK);
        send_packet;
        expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
      end
      finish_test;
      expect_debug_snapshot(3, 2, 32'd0);
    end

    if (sample_count > 3) begin
      start_test("tc07_rsu_offload_batch4_backpressure");
      auto_expect_tx_words = 1'b0;
      bp_mode = BP_PERIODIC;
      clear_debug_counters;
      for (batch_sample_idx = 0; batch_sample_idx < 4; batch_sample_idx = batch_sample_idx + 1) begin
        build_ann_udp_packet_for_sample(batch_sample_idx, 16'h0001, 16'h0008, ANN_TASK_MAGIC, ANN_UDP_DST_PORT);
        expect_ann_compact_result_packet(ANN_STATUS_OK);
        send_packet;
        expect_cpu_replay_matches_tx(TEST_TIMEOUT_CYCLES);
      end
      finish_test;
      expect_debug_snapshot(4, 3, 32'd0);
    end

    if (fail_count == 0) begin
      $display("[TB] === PASS: user_top RSU smoke completed ===");
      $finish(0);
    end
    else begin
      $display("[TB] === FAIL: user_top RSU smoke failures=%0d ===", fail_count);
      $finish(1);
    end
  end

endmodule
