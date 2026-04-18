`timescale 1ns/1ps
`define UDP_REG_ADDR_WIDTH 23
`define CPCI_NF2_DATA_WIDTH 32

module tb_user_top_gpu_ptx_v3;

  localparam DATA_WIDTH = 64;
  localparam CTRL_WIDTH = DATA_WIDTH/8;
  localparam UDP_REG_SRC_WIDTH = 2;

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

  reg clk;
  reg reset;

  localparam [7:0] REG_CONTROL    = 8'h00;
  localparam [7:0] REG_ENTRY_PC   = 8'h08;
  localparam [7:0] REG_TID_INIT   = 8'h0C;
  localparam [7:0] REG_WORK_SIZE  = 8'h10;
  localparam [7:0] REG_BASE_A_LO  = 8'h20;
  localparam [7:0] REG_BASE_A_HI  = 8'h24;
  localparam [7:0] REG_BASE_B_LO  = 8'h28;
  localparam [7:0] REG_BASE_B_HI  = 8'h2C;
  localparam [7:0] REG_BASE_C_LO  = 8'h30;
  localparam [7:0] REG_BASE_C_HI  = 8'h34;
  localparam [7:0] REG_BASE_D_LO  = 8'h38;
  localparam [7:0] REG_BASE_D_HI  = 8'h3C;
  localparam [7:0] REG_M          = 8'h40;
  localparam [7:0] REG_N          = 8'h44;
  localparam [7:0] REG_K          = 8'h48;

  localparam [31:0] BASE_A = 32'd0;
  localparam [31:0] BASE_B = 32'd64;
  localparam [31:0] BASE_C = 32'd128;
  localparam [31:0] BASE_D = 32'd192;

  localparam [8:0] ENTRY_ADD  = 9'd0;
  localparam [8:0] ENTRY_SUB  = 9'd32;
  localparam [8:0] ENTRY_RELU = 9'd64;
  localparam [8:0] ENTRY_MUL  = 9'd96;
  localparam [8:0] ENTRY_FMA  = 9'd128;

  localparam [63:0] SENTINEL = 64'hDEADBEEFCAFEBABE;

  localparam [15:0] BF16_0P5 = 16'h3F00;
  localparam [15:0] BF16_1   = 16'h3F80;
  localparam [15:0] BF16_2   = 16'h4000;
  localparam [15:0] BF16_3   = 16'h4040;
  localparam [15:0] BF16_4   = 16'h4080;
  localparam [15:0] BF16_5   = 16'h40A0;
  localparam [15:0] BF16_6   = 16'h40C0;
  localparam [15:0] BF16_7   = 16'h40E0;
  localparam [15:0] BF16_8   = 16'h4100;
  localparam [15:0] BF16_9   = 16'h4110;
  localparam [15:0] BF16_10  = 16'h4120;
  localparam [15:0] BF16_11  = 16'h4130;
  localparam [15:0] BF16_12  = 16'h4140;
  localparam [15:0] BF16_13  = 16'h4150;
  localparam [15:0] BF16_14  = 16'h4160;
  localparam [15:0] BF16_16  = 16'h4180;
  localparam [15:0] BF16_17  = 16'h4188;
  localparam [15:0] BF16_18  = 16'h4190;
  localparam [15:0] BF16_21  = 16'h41A8;
  localparam [15:0] BF16_22  = 16'h41B0;
  localparam [15:0] BF16_25  = 16'h41C8;
  localparam [15:0] BF16_28  = 16'h41E0;
  localparam [15:0] BF16_32  = 16'h4200;
  localparam [15:0] BF16_33  = 16'h4204;
  localparam [15:0] BF16_36  = 16'h4210;
  localparam [15:0] BF16_40  = 16'h4220;

  reg [63:0] expected [0:7];
  reg [63:0] pkt_mem [0:255];
  reg [71:0] out_cap [0:255];

  integer fail_count;
  integer pass_count;
  integer cycle_count;
  integer out_count;
  integer i;

  reg [1:0] prev_df_state;
  reg prev_proc_active;
  reg prev_pkt_ready;
  reg prev_gpu_done;

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

  function [63:0] pack4;
    input [15:0] x0;
    input [15:0] x1;
    input [15:0] x2;
    input [15:0] x3;
    begin
      pack4 = {x3, x2, x1, x0};
    end
  endfunction

  function [31:0] inst_enc;
    input [3:0]  opcode;
    input [2:0]  rd;
    input [2:0]  rs1;
    input [2:0]  rs2;
    input [1:0]  bsel;
    input        dtype;
    input [15:0] imm;
    begin
      inst_enc = {opcode, rd, rs1, rs2, bsel, dtype, imm};
    end
  endfunction

  task clear_imem;
    integer j;
    begin
      for (j = 0; j < 512; j = j + 1)
        dut.u_gpu.u_if.u_imem.mem[j] = 32'h00000013;
    end
  endtask

  task load_programs_v4;
    integer a;
    integer n;
    begin
      clear_imem();

      a = ENTRY_ADD;
      dut.u_gpu.u_if.u_imem.mem[a+0]  = inst_enc(4'h2, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);
      dut.u_gpu.u_if.u_imem.mem[a+1]  = inst_enc(4'h2, 3'd1, 3'd0, 3'd0, 2'd1, 1'b0, 16'd0);
      for (n = 2; n <= 7; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+8]  = inst_enc(4'h4, 3'd2, 3'd0, 3'd1, 2'd0, 1'b0, 16'd0);
      for (n = 9; n <= 14; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+15] = inst_enc(4'h3, 3'd0, 3'd0, 3'd2, 2'd2, 1'b0, 16'd0);
      for (n = 16; n <= 26; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+27] = inst_enc(4'hF, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);

      a = ENTRY_SUB;
      dut.u_gpu.u_if.u_imem.mem[a+0]  = inst_enc(4'h2, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);
      dut.u_gpu.u_if.u_imem.mem[a+1]  = inst_enc(4'h2, 3'd1, 3'd0, 3'd0, 2'd1, 1'b0, 16'd0);
      for (n = 2; n <= 7; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+8]  = inst_enc(4'h5, 3'd2, 3'd0, 3'd1, 2'd0, 1'b0, 16'd0);
      for (n = 9; n <= 14; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+15] = inst_enc(4'h3, 3'd0, 3'd0, 3'd2, 2'd2, 1'b0, 16'd0);
      for (n = 16; n <= 26; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+27] = inst_enc(4'hF, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);

      a = ENTRY_RELU;
      dut.u_gpu.u_if.u_imem.mem[a+0]  = inst_enc(4'h2, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);
      for (n = 1; n <= 6; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+7]  = inst_enc(4'h7, 3'd2, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);
      for (n = 8; n <= 13; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+14] = inst_enc(4'h3, 3'd0, 3'd0, 3'd2, 2'd1, 1'b0, 16'd0);
      for (n = 15; n <= 25; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+26] = inst_enc(4'hF, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);

      a = ENTRY_MUL;
      dut.u_gpu.u_if.u_imem.mem[a+0]  = inst_enc(4'h2, 3'd0, 3'd0, 3'd0, 2'd0, 1'b1, 16'd0);
      dut.u_gpu.u_if.u_imem.mem[a+1]  = inst_enc(4'h2, 3'd1, 3'd0, 3'd0, 2'd1, 1'b1, 16'd0);
      for (n = 2; n <= 7; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+8]  = inst_enc(4'h6, 3'd2, 3'd0, 3'd1, 2'd0, 1'b1, 16'd0);
      for (n = 9; n <= 14; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+15] = inst_enc(4'h3, 3'd0, 3'd0, 3'd2, 2'd2, 1'b1, 16'd0);
      for (n = 16; n <= 26; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+27] = inst_enc(4'hF, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);

      a = ENTRY_FMA;
      dut.u_gpu.u_if.u_imem.mem[a+0]  = inst_enc(4'h2, 3'd2, 3'd0, 3'd0, 2'd2, 1'b1, 16'd0);
      for (n = 1; n <= 4; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+5]  = inst_enc(4'h2, 3'd0, 3'd0, 3'd0, 2'd0, 1'b1, 16'd0);
      for (n = 6; n <= 9; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+10] = inst_enc(4'h2, 3'd1, 3'd0, 3'd0, 2'd1, 1'b1, 16'd0);
      for (n = 11; n <= 18; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+19] = inst_enc(4'hC, 3'd2, 3'd0, 3'd1, 2'd0, 1'b1, 16'd0);
      for (n = 20; n <= 27; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+28] = inst_enc(4'h3, 3'd0, 3'd0, 3'd2, 2'd3, 1'b1, 16'd0);
      for (n = 29; n <= 40; n = n + 1) dut.u_gpu.u_if.u_imem.mem[a+n] = 32'h00000013;
      dut.u_gpu.u_if.u_imem.mem[a+41] = inst_enc(4'hF, 3'd0, 3'd0, 3'd0, 2'd0, 1'b0, 16'd0);
    end
  endtask

  task clear_expected;
    integer j;
    begin
      for (j = 0; j < 8; j = j + 1)
        expected[j] = 64'd0;
    end
  endtask

  task clear_pkt_mem;
    integer j;
    begin
      for (j = 0; j < 256; j = j + 1)
        pkt_mem[j] = 64'd0;
    end
  endtask

  task clear_outputs;
    integer j;
    begin
      out_count = 0;
      for (j = 0; j < 256; j = j + 1)
        out_cap[j] = 72'd0;
    end
  endtask

  task pkt_write_global;
    input integer base;
    input integer idx;
    input [63:0] data;
    begin
      pkt_mem[base + idx] = data;
    end
  endtask

  task fill_output_sentinel;
    input integer base;
    integer j;
    begin
      for (j = 0; j < 4; j = j + 1)
        pkt_mem[base + 4 + j] = SENTINEL;
    end
  endtask

  task gpu_mmio_write_force;
    input [7:0] addr;
    input [31:0] data;
    begin
      @(negedge clk);
      force dut.sw_gpu_mmio_addr  = {24'd0, addr};
      force dut.sw_gpu_mmio_wdata = data;
      force dut.gpu_mmio_wr_pulse = 1'b1;
      @(posedge clk);
      @(negedge clk);
      release dut.gpu_mmio_wr_pulse;
      release dut.sw_gpu_mmio_addr;
      release dut.sw_gpu_mmio_wdata;
    end
  endtask

  task gpu_prepare_kernel;
    input [8:0]  entry_pc;
    input [31:0] work_size;
    input [31:0] base_a;
    input [31:0] base_b;
    input [31:0] base_c;
    input [31:0] base_d;
    begin
      gpu_mmio_write_force(REG_CONTROL, 32'h00000004);
      gpu_mmio_write_force(REG_ENTRY_PC, {23'd0, entry_pc});
      gpu_mmio_write_force(REG_TID_INIT, 32'd0);
      gpu_mmio_write_force(REG_WORK_SIZE, work_size);

      gpu_mmio_write_force(REG_BASE_A_LO, base_a);
      gpu_mmio_write_force(REG_BASE_A_HI, 32'd0);
      gpu_mmio_write_force(REG_BASE_B_LO, base_b);
      gpu_mmio_write_force(REG_BASE_B_HI, 32'd0);
      gpu_mmio_write_force(REG_BASE_C_LO, base_c);
      gpu_mmio_write_force(REG_BASE_C_HI, 32'd0);
      gpu_mmio_write_force(REG_BASE_D_LO, base_d);
      gpu_mmio_write_force(REG_BASE_D_HI, 32'd0);

      gpu_mmio_write_force(REG_M, 32'd0);
      gpu_mmio_write_force(REG_N, 32'd0);
      gpu_mmio_write_force(REG_K, 32'd0);
    end
  endtask

  task gpu_start_kernel;
    begin
      gpu_mmio_write_force(REG_CONTROL, 32'h00000001);
    end
  endtask


  task clear_gpu_regfiles;
    integer j;
    begin
      for (j = 0; j < 8; j = j + 1) begin
        dut.u_gpu.u_id.rf0[j] = 64'd0;
        dut.u_gpu.u_id.rf1[j] = 64'd0;
        dut.u_gpu.u_id.rf2[j] = 64'd0;
        dut.u_gpu.u_id.rf3[j] = 64'd0;
      end
    end
  endtask

  task do_reset;
    begin
      in_data = 64'd0;
      in_ctrl = 8'd0;
      in_wr = 1'b0;
      out_rdy = 1'b1;
      reg_req_in = 1'b0;
      reg_ack_in = 1'b0;
      reg_rd_wr_L_in = 1'b0;
      reg_addr_in = 0;
      reg_data_in = 0;
      reg_src_in = 0;
      clear_outputs();
      reset = 1'b1;
      force dut.proc_owner_gpu_cfg = 1'b1;
      repeat (6) @(posedge clk);
      clear_gpu_regfiles();
      load_programs_v4();
      repeat (2) @(posedge clk);
      reset = 1'b0;
      @(posedge clk);
    end
  endtask

  task print_packet_preview;
    input [127:0] name;
    input integer total_words;
    integer j;
    begin
      $display("---- PACKET PREVIEW %0s total_words=%0d ----", name, total_words);
      for (j = 0; j < total_words; j = j + 1)
        if (j < 12 || j >= total_words-8)
          $display("  PKT[%0d] = %h", j, pkt_mem[j]);
    end
  endtask

  task send_packet_words;
    input integer nwords;
    integer j;
    begin
      while (in_rdy !== 1'b1) @(posedge clk);
      for (j = 0; j < nwords; j = j + 1) begin
        @(negedge clk);
        in_wr   = 1'b1;
        in_ctrl = (j == 0) ? 8'hff : 8'h00;
        in_data = pkt_mem[j];
        @(posedge clk);
      end
      @(negedge clk);
      in_wr   = 1'b0;
      in_ctrl = 8'h00;
      in_data = 64'd0;
    end
  endtask

  task wait_for_proc_active;
    input integer limit;
    integer k;
    reg ok;
    begin
      ok = 1'b0;
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (dut.u_fifo.proc_active) begin
          ok = 1'b1;
          k = limit;
        end
      end
      if (!ok) begin
        $display("FAIL: timeout waiting for GPU proc_active at cycle %0d", cycle_count);
        $finish;
      end
    end
  endtask

  task wait_gpu_done;
    input integer limit;
    integer k;
    reg ok;
    begin
      ok = 1'b0;
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (dut.u_gpu.u_ctrl.error) begin
          $display("FAIL: GPU error_code=%02h", dut.u_gpu.u_ctrl.error_code);
          $finish;
        end
        if (dut.u_gpu.u_ctrl.done) begin
          ok = 1'b1;
          k = limit;
        end
      end
      if (!ok) begin
        $display("FAIL: timeout waiting for GPU done at cycle %0d pc=%0d", cycle_count, dut.gpu_dbg_pc);
        $finish;
      end
    end
  endtask

  task wait_for_idle;
    input integer limit;
    integer k;
    reg ok;
    begin
      ok = 1'b0;
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (dut.u_fifo.hold_valid == 1'b0 && dut.u_fifo.drop_fifo.state == 2'b00) begin
          ok = 1'b1;
          k = limit;
        end
      end
      if (!ok) begin
        $display("FAIL: timeout waiting idle at cycle %0d", cycle_count);
        $finish;
      end
    end
  endtask

  task check_packet_region;
    input [127:0] name;
    input integer base;
    input integer n;
    input integer total_words;
    integer j;
    reg local_fail;
    reg [63:0] got;
    begin
      local_fail = 1'b0;

      if (out_count != total_words) begin
        $display("FAIL %0s: expected out_count=%0d got=%0d", name, total_words, out_count);
        $finish;
      end

      if (out_cap[0][71:64] !== 8'hff) begin
        $display("FAIL %0s: first ctrl is not ff", name);
        $finish;
      end

      for (j = 1; j < out_count; j = j + 1) begin
        if (out_cap[j][71:64] !== 8'h00) begin
          $display("FAIL %0s: ctrl[%0d] = %h, expected 00", name, j, out_cap[j][71:64]);
          $finish;
        end
      end

      $display("---- VERIFY %0s ----", name);
      for (j = 0; j < n; j = j + 1) begin
        got = out_cap[base + j][63:0];
        $display("%0s idx=%0d got=%h {%h %h %h %h} exp=%h {%h %h %h %h}",
                 name, j,
                 got, got[63:48], got[47:32], got[31:16], got[15:0],
                 expected[j], expected[j][63:48], expected[j][47:32], expected[j][31:16], expected[j][15:0]);
        if (got !== expected[j])
          local_fail = 1'b1;
      end

      for (j = 0; j < 4; j = j + 1) begin
        got = out_cap[base + n + j][63:0];
        $display("%0s sentinel[%0d] got=%h exp=%h", name, j, got, SENTINEL);
        if (got !== SENTINEL)
          local_fail = 1'b1;
      end

      if (local_fail) begin
        $display("RESULT %0s : FAIL", name);
        fail_count = fail_count + 1;
      end else begin
        $display("RESULT %0s : PASS", name);
        pass_count = pass_count + 1;
      end
    end
  endtask

  task setup_add_case;
    begin
      clear_pkt_mem();
      clear_expected();
      fill_output_sentinel(BASE_C);

      pkt_write_global(BASE_A, 0, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      pkt_write_global(BASE_B, 0, pack4(16'd10,   16'd20,   16'd30,   16'd40));
      expected[0] =                pack4(16'd11,   16'd22,   16'd33,   16'd44);

      pkt_write_global(BASE_A, 1, pack4(16'd100,  16'd200,  16'd300,  16'd400));
      pkt_write_global(BASE_B, 1, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[1] =                pack4(16'd101,  16'd202,  16'd303,  16'd404);

      pkt_write_global(BASE_A, 2, pack4(16'hFFFF, 16'hFFFE, 16'd5,    16'd6));
      pkt_write_global(BASE_B, 2, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[2] =                pack4(16'd0,    16'd0,    16'd8,    16'd10);

      pkt_write_global(BASE_A, 3, pack4(16'd7,    16'd8,    16'd9,    16'd10));
      pkt_write_global(BASE_B, 3, pack4(16'd11,   16'd12,   16'd13,   16'd14));
      expected[3] =                pack4(16'd18,   16'd20,   16'd22,   16'd24);
    end
  endtask

  task setup_sub_case;
    begin
      clear_pkt_mem();
      clear_expected();
      fill_output_sentinel(BASE_C);

      pkt_write_global(BASE_A, 0, pack4(16'd10,   16'd20,   16'd30,   16'd40));
      pkt_write_global(BASE_B, 0, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[0] =                pack4(16'd9,    16'd18,   16'd27,   16'd36);

      pkt_write_global(BASE_A, 1, pack4(16'd100,  16'd50,   16'd0,    16'hFFFF));
      pkt_write_global(BASE_B, 1, pack4(16'd5,    16'd10,   16'd1,    16'd1));
      expected[1] =                pack4(16'd95,   16'd40,   16'hFFFF, 16'hFFFE);

      pkt_write_global(BASE_A, 2, pack4(16'd0,    16'd1,    16'd2,    16'd3));
      pkt_write_global(BASE_B, 2, pack4(16'd10,   16'd20,   16'd30,   16'd40));
      expected[2] =                pack4(16'hFFF6, 16'hFFED, 16'hFFE4, 16'hFFDB);

      pkt_write_global(BASE_A, 3, pack4(16'd300,  16'd400,  16'd500,  16'd600));
      pkt_write_global(BASE_B, 3, pack4(16'd100,  16'd110,  16'd120,  16'd130));
      expected[3] =                pack4(16'd200,  16'd290,  16'd380,  16'd470);
    end
  endtask

  task setup_relu_case;
    begin
      clear_pkt_mem();
      clear_expected();
      fill_output_sentinel(BASE_B);

      pkt_write_global(BASE_A, 0, pack4(16'hFFFF, 16'd1,    16'hFFFE, 16'd2));
      expected[0] =                pack4(16'd0,    16'd1,    16'd0,    16'd2);

      pkt_write_global(BASE_A, 1, pack4(16'h8000, 16'h7FFF, 16'd0,    16'hFFFF));
      expected[1] =                pack4(16'd0,    16'h7FFF, 16'd0,    16'd0);

      pkt_write_global(BASE_A, 2, pack4(16'd5,    16'd6,    16'd7,    16'd8));
      expected[2] =                pack4(16'd5,    16'd6,    16'd7,    16'd8);

      pkt_write_global(BASE_A, 3, pack4(16'hFFF0, 16'hFFF1, 16'hFFF2, 16'hFFF3));
      expected[3] =                pack4(16'd0,    16'd0,    16'd0,    16'd0);
    end
  endtask

  task setup_mul_case;
    begin
      clear_pkt_mem();
      clear_expected();
      fill_output_sentinel(BASE_C);

      pkt_write_global(BASE_A, 0, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      pkt_write_global(BASE_B, 0, pack4(BF16_5,   BF16_6,   BF16_7,   BF16_8));
      expected[0] =                pack4(BF16_5,   BF16_12,  BF16_21,  BF16_32);

      pkt_write_global(BASE_A, 1, pack4(BF16_2,   BF16_2,   BF16_2,   BF16_2));
      pkt_write_global(BASE_B, 1, pack4(BF16_2,   BF16_3,   BF16_4,   BF16_5));
      expected[1] =                pack4(BF16_4,   BF16_6,   BF16_8,   BF16_10);

      pkt_write_global(BASE_A, 2, pack4(BF16_0P5, BF16_1,   BF16_2,   BF16_4));
      pkt_write_global(BASE_B, 2, pack4(BF16_8,   BF16_4,   BF16_2,   BF16_1));
      expected[2] =                pack4(BF16_4,   BF16_4,   BF16_4,   BF16_4);

      pkt_write_global(BASE_A, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      pkt_write_global(BASE_B, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      expected[3] =                pack4(BF16_9,   BF16_16,  BF16_25,  BF16_36);
    end
  endtask

  task setup_fma_case;
    begin
      clear_pkt_mem();
      clear_expected();
      fill_output_sentinel(BASE_D);

      pkt_write_global(BASE_A, 0, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      pkt_write_global(BASE_B, 0, pack4(BF16_5,   BF16_6,   BF16_7,   BF16_8));
      pkt_write_global(BASE_C, 0, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[0] =                pack4(BF16_6,   BF16_13,  BF16_22,  BF16_33);

      pkt_write_global(BASE_A, 1, pack4(BF16_2,   BF16_2,   BF16_2,   BF16_2));
      pkt_write_global(BASE_B, 1, pack4(BF16_2,   BF16_3,   BF16_4,   BF16_5));
      pkt_write_global(BASE_C, 1, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[1] =                pack4(BF16_5,   BF16_8,   BF16_11,  BF16_14);

      pkt_write_global(BASE_A, 2, pack4(BF16_0P5, BF16_1,   BF16_2,   BF16_4));
      pkt_write_global(BASE_B, 2, pack4(BF16_8,   BF16_4,   BF16_2,   BF16_1));
      pkt_write_global(BASE_C, 2, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[2] =                pack4(BF16_5,   BF16_5,   BF16_5,   BF16_5);

      pkt_write_global(BASE_A, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      pkt_write_global(BASE_B, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      pkt_write_global(BASE_C, 3, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[3] =                pack4(BF16_10,  BF16_18,  BF16_28,  BF16_40);
    end
  endtask

  task run_packet_kernel;
    input [127:0] name;
    input [8:0]  entry_pc;
    input [31:0] work_size;
    input [31:0] base_a;
    input [31:0] base_b;
    input [31:0] base_c;
    input [31:0] base_d;
    input integer total_words;
    input integer verify_base;
    begin
      do_reset();
      gpu_prepare_kernel(entry_pc, work_size, base_a, base_b, base_c, base_d);
      $display("");
      $display("========== TEST %0s ==========", name);
      print_packet_preview(name, total_words);
      send_packet_words(total_words);
      wait_for_proc_active(300);
      gpu_start_kernel();
      wait_gpu_done(12000);
      wait_for_idle(2000);
      check_packet_region(name, verify_base, 4, total_words);
    end
  endtask

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (reset)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  always @(posedge clk) begin
    if (reset) begin
      prev_df_state    <= 2'b11;
      prev_proc_active <= 1'b0;
      prev_pkt_ready   <= 1'b0;
      prev_gpu_done    <= 1'b0;
    end else begin
      if (prev_df_state != dut.u_fifo.drop_fifo.state)
        $display("[%0t] DFSM %0d -> %0d", $time, prev_df_state, dut.u_fifo.drop_fifo.state);
      if (prev_proc_active != dut.u_fifo.proc_active)
        $display("[%0t] proc_active -> %b", $time, dut.u_fifo.proc_active);
      if (prev_pkt_ready != dut.u_fifo.pkt_ready)
        $display("[%0t] pkt_ready -> %b", $time, dut.u_fifo.pkt_ready);
      if (prev_gpu_done != dut.gpu_proc_done)
        $display("[%0t] gpu_proc_done -> %b", $time, dut.gpu_proc_done);
      prev_df_state    <= dut.u_fifo.drop_fifo.state;
      prev_proc_active <= dut.u_fifo.proc_active;
      prev_pkt_ready   <= dut.u_fifo.pkt_ready;
      prev_gpu_done    <= dut.gpu_proc_done;
    end
  end

  always @(posedge clk) begin
    if (!reset && dut.gpu_mem_req_valid && dut.gpu_mem_req_ready) begin
      if (dut.gpu_mem_req_we) begin
        $display("[%0t] GPU STORE mask=%b a0=%0d d0=%h a1=%0d d1=%h a2=%0d d2=%h a3=%0d d3=%h",
                 $time,
                 dut.gpu_mem_lane_mask,
                 dut.gpu_mem_addr0, dut.gpu_mem_wdata0,
                 dut.gpu_mem_addr1, dut.gpu_mem_wdata1,
                 dut.gpu_mem_addr2, dut.gpu_mem_wdata2,
                 dut.gpu_mem_addr3, dut.gpu_mem_wdata3);
      end else begin
        $display("[%0t] GPU LOAD  mask=%b a0=%0d a1=%0d a2=%0d a3=%0d",
                 $time,
                 dut.gpu_mem_lane_mask,
                 dut.gpu_mem_addr0,
                 dut.gpu_mem_addr1,
                 dut.gpu_mem_addr2,
                 dut.gpu_mem_addr3);
      end
    end
  end

  always @(posedge clk) begin
    if (!reset && out_wr && out_rdy) begin
      out_cap[out_count] <= {out_ctrl, out_data};
      out_count <= out_count + 1;
      if (out_count < 12 || out_count >= 120)
        $display("[%0t] OUT[%0d] ctrl=%h data=%h", $time, out_count, out_ctrl, out_data);
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    fail_count = 0;
    pass_count = 0;
    cycle_count = 0;
    out_count = 0;

    $dumpfile("tb_user_top_gpu_ptx_v3.vcd");
    $dumpvars(0, tb_user_top_gpu_ptx_v3);

    setup_add_case;
    run_packet_kernel("vec_add_i16x4", ENTRY_ADD, 32'd4, BASE_A, BASE_B, BASE_C, 32'd0, BASE_C + 8, BASE_C);

    setup_sub_case;
    run_packet_kernel("vec_sub_i16x4", ENTRY_SUB, 32'd4, BASE_A, BASE_B, BASE_C, 32'd0, BASE_C + 8, BASE_C);

    setup_relu_case;
    run_packet_kernel("relu_i16x4", ENTRY_RELU, 32'd4, BASE_A, BASE_B, 32'd0, 32'd0, BASE_B + 8, BASE_B);

    setup_mul_case;
    run_packet_kernel("vec_mul_bf16x4", ENTRY_MUL, 32'd4, BASE_A, BASE_B, BASE_C, 32'd0, BASE_C + 8, BASE_C);

    setup_fma_case;
    run_packet_kernel("fma_bf16x4", ENTRY_FMA, 32'd4, BASE_A, BASE_B, BASE_C, BASE_D, BASE_D + 8, BASE_D);

    $display("");
    $display("========== SUMMARY ==========");
    $display("PASS = %0d", pass_count);
    $display("FAIL = %0d", fail_count);

    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED");

    #50;
    $finish;
  end

endmodule
