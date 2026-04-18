`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif

module user_pre_debug_tb;

  localparam DATA_WIDTH = 64;
  localparam CTRL_WIDTH = DATA_WIDTH / 8;
  localparam UDP_REG_SRC_WIDTH = 2;

  localparam [15:0] USER_PRE_DEBUG_BASE_ADDR = 16'h5580;
  localparam integer DEBUG_CTRL_WORD_INDEX = 0;
  localparam integer STATUS_WORD_INDEX = 1;
  localparam integer CTRL_PACK_0_WORD_INDEX = 2;
  localparam integer CTRL_PACK_1_WORD_INDEX = 3;
  localparam integer WORD0_HI_WORD_INDEX = 4;
  localparam integer WORD0_LO_WORD_INDEX = 5;
  localparam integer WORD1_HI_WORD_INDEX = 6;
  localparam integer WORD1_LO_WORD_INDEX = 7;
  localparam integer WORD2_HI_WORD_INDEX = 8;
  localparam integer WORD2_LO_WORD_INDEX = 9;
  localparam integer WORD3_HI_WORD_INDEX = 10;
  localparam integer WORD3_LO_WORD_INDEX = 11;
  localparam integer WORD4_HI_WORD_INDEX = 12;
  localparam integer WORD4_LO_WORD_INDEX = 13;
  localparam integer WORD5_HI_WORD_INDEX = 14;
  localparam integer WORD5_LO_WORD_INDEX = 15;

  reg                         clk;
  reg                         reset;
  reg  [DATA_WIDTH-1:0]       mon_data;
  reg  [CTRL_WIDTH-1:0]       mon_ctrl;
  reg                         mon_wr;
  reg                         mon_rdy;

  reg                         reg_req_in;
  reg                         reg_ack_in;
  reg                         reg_rd_wr_L_in;
  reg  [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in;
  reg  [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in;
  reg  [UDP_REG_SRC_WIDTH-1:0] reg_src_in;

  wire                        reg_req_out;
  wire                        reg_ack_out;
  wire                        reg_rd_wr_L_out;
  wire [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out;
  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out;
  wire [UDP_REG_SRC_WIDTH-1:0] reg_src_out;

  integer fail_count;

  user_pre_debug #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) dut (
    .mon_data       (mon_data),
    .mon_ctrl       (mon_ctrl),
    .mon_wr         (mon_wr),
    .mon_rdy        (mon_rdy),
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

  task record_failure;
    input [255:0] message;
    begin
      fail_count = fail_count + 1;
      $display("[%0t] FAIL %0s", $time, message);
    end
  endtask

  task reg_local_write;
    input integer word_index;
    input [31:0] write_data;
    reg [`UDP_REG_ADDR_WIDTH-1:0] local_addr;
    begin
      local_addr = USER_PRE_DEBUG_BASE_ADDR + (word_index * 4);
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
    input [255:0] message;
    reg [`UDP_REG_ADDR_WIDTH-1:0] local_addr;
    begin
      local_addr = USER_PRE_DEBUG_BASE_ADDR + (word_index * 4);
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

  task drive_word;
    input [63:0] data_word;
    input [7:0]  ctrl_word;
    begin
      @(negedge clk);
      mon_data <= data_word;
      mon_ctrl <= ctrl_word;
      mon_wr   <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      mon_wr   <= 1'b0;
      mon_data <= 64'h0;
      mon_ctrl <= 8'h00;
    end
  endtask

  task expect_zero_snapshot;
    begin
      expect_local_reg_read(STATUS_WORD_INDEX, 32'h0000_0000, "status should reset to zero");
      expect_local_reg_read(CTRL_PACK_0_WORD_INDEX, 32'h0000_0000, "ctrl_pack_0 should reset to zero");
      expect_local_reg_read(CTRL_PACK_1_WORD_INDEX, 32'h0000_0000, "ctrl_pack_1 should reset to zero");
      expect_local_reg_read(WORD0_HI_WORD_INDEX, 32'h0000_0000, "word0 hi should reset to zero");
      expect_local_reg_read(WORD5_LO_WORD_INDEX, 32'h0000_0000, "word5 lo should reset to zero");
    end
  endtask

  task test_capture_first_packet_and_lock;
    begin
      $display("TEST user_pre_debug capture_first_packet_and_lock");
      clear_debug_regs;

      drive_word(64'h1111_2222_3333_4444, 8'hff);
      drive_word(64'h5555_6666_7777_8888, 8'h00);
      drive_word(64'h9999_aaaa_bbbb_cccc, 8'h00);
      drive_word(64'hdddd_eeee_ffff_0000, 8'h00);
      drive_word(64'h1234_5678_9abc_def0, 8'h00);
      drive_word(64'h0fed_cba9_8765_4321, 8'h00);

      expect_local_reg_read(STATUS_WORD_INDEX, 32'h0001_0605, "status should show valid six-word capture");
      expect_local_reg_read(CTRL_PACK_0_WORD_INDEX, 32'h0000_00ff, "ctrl_pack_0 mismatch");
      expect_local_reg_read(CTRL_PACK_1_WORD_INDEX, 32'h0000_0000, "ctrl_pack_1 mismatch");
      expect_local_reg_read(WORD0_HI_WORD_INDEX, 32'h1111_2222, "word0 hi mismatch");
      expect_local_reg_read(WORD0_LO_WORD_INDEX, 32'h3333_4444, "word0 lo mismatch");
      expect_local_reg_read(WORD5_HI_WORD_INDEX, 32'h0fed_cba9, "word5 hi mismatch");
      expect_local_reg_read(WORD5_LO_WORD_INDEX, 32'h8765_4321, "word5 lo mismatch");

      drive_word(64'haaaa_bbbb_cccc_dddd, 8'hff);
      drive_word(64'heeee_ffff_1111_2222, 8'h00);
      drive_word(64'h3333_4444_5555_6666, 8'h40);

      expect_local_reg_read(STATUS_WORD_INDEX, 32'h0001_0605, "second packet must not overwrite locked snapshot");
      expect_local_reg_read(WORD0_HI_WORD_INDEX, 32'h1111_2222, "locked word0 hi changed unexpectedly");
    end
  endtask

  task test_clear_rearms_short_packet_capture;
    begin
      $display("TEST user_pre_debug clear_rearms_short_packet_capture");
      clear_debug_regs;

      drive_word(64'h0102_0304_0506_0708, 8'hff);
      drive_word(64'h1112_1314_1516_1718, 8'h00);
      drive_word(64'h2122_2324_2526_2728, 8'h20);

      expect_local_reg_read(STATUS_WORD_INDEX, 32'h0001_0305, "status should show three-word capture");
      expect_local_reg_read(CTRL_PACK_0_WORD_INDEX, 32'h0020_00ff, "short packet ctrl pack mismatch");
      expect_local_reg_read(CTRL_PACK_1_WORD_INDEX, 32'h0000_0000, "short packet ctrl pack 1 mismatch");
      expect_local_reg_read(WORD0_HI_WORD_INDEX, 32'h0102_0304, "short packet word0 hi mismatch");
      expect_local_reg_read(WORD1_HI_WORD_INDEX, 32'h1112_1314, "short packet word1 hi mismatch");
      expect_local_reg_read(WORD2_HI_WORD_INDEX, 32'h2122_2324, "short packet word2 hi mismatch");
      expect_local_reg_read(WORD3_HI_WORD_INDEX, 32'h0000_0000, "word3 hi should remain zero after short packet");
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    mon_data = 64'h0;
    mon_ctrl = 8'h00;
    mon_wr = 1'b0;
    mon_rdy = 1'b1;
    reg_req_in = 1'b0;
    reg_ack_in = 1'b0;
    reg_rd_wr_L_in = 1'b1;
    reg_addr_in = {(`UDP_REG_ADDR_WIDTH){1'b0}};
    reg_data_in = 32'h0;
    reg_src_in = {UDP_REG_SRC_WIDTH{1'b0}};
    fail_count = 0;

    repeat (3) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    expect_zero_snapshot;
    test_capture_first_packet_and_lock;
    test_clear_rearms_short_packet_capture;

    if (fail_count == 0) begin
      $display("PASS user_pre_debug_tb");
    end
    else begin
      $display("FAIL user_pre_debug_tb fail_count=%0d", fail_count);
      $fatal;
    end

    $finish;
  end

endmodule
