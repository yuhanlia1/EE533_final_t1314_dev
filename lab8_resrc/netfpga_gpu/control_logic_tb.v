`timescale 1ns/1ps

`define CHECK_EQ_HEX(TAG, GOT, EXP) \
  if ((GOT) !== (EXP)) begin \
    $display("FAIL [%s] cycle=%0d GOT=%h EXP=%h", (TAG), cycle, (GOT), (EXP)); \
    $finish; \
  end else begin \
    $display("PASS [%s] cycle=%0d = %h", (TAG), cycle, (GOT)); \
  end

`define CHECK_EQ_DEC(TAG, GOT, EXP) \
  if ((GOT) !== (EXP)) begin \
    $display("FAIL [%s] cycle=%0d GOT=%0d EXP=%0d", (TAG), cycle, (GOT), (EXP)); \
    $finish; \
  end else begin \
    $display("PASS [%s] cycle=%0d = %0d", (TAG), cycle, (GOT)); \
  end

`define CHECK_TRUE(TAG, COND) \
  if (!(COND)) begin \
    $display("FAIL [%s] cycle=%0d COND=false", (TAG), cycle); \
    $finish; \
  end else begin \
    $display("PASS [%s] cycle=%0d", (TAG), cycle); \
  end

`define CHECK_FALSE(TAG, COND) \
  if ((COND)) begin \
    $display("FAIL [%s] cycle=%0d COND=true", (TAG), cycle); \
    $finish; \
  end else begin \
    $display("PASS [%s] cycle=%0d", (TAG), cycle); \
  end

module testbench;
  integer cycle;
  reg clk;

  task tick;
    begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      cycle = cycle + 1;
    end
  endtask

  function [31:0] enc;
    input [3:0]  op;
    input [2:0]  rd;
    input [2:0]  rs1;
    input [2:0]  rs2;
    input [1:0]  bsel;
    input        dtype;
    input [15:0] imm;
    begin
      enc = {op, rd, rs1, rs2, bsel, dtype, imm};
    end
  endfunction

  function [63:0] pack16;
    input [15:0] a0,a1,a2,a3;
    begin
      pack16 = {a3,a2,a1,a0};
    end
  endfunction

  function [63:0] pack_bf16;
    input [15:0] e0,e1,e2,e3;
    begin
      pack_bf16 = {e3,e2,e1,e0};
    end
  endfunction

  localparam [31:0] NOP = 32'h00000013;

  localparam [15:0] BF16_1 = 16'h3F80;
  localparam [15:0] BF16_2 = 16'h4000;
  localparam [15:0] BF16_3 = 16'h4040;
  localparam [15:0] BF16_7 = 16'h40E0;

  reg  rst_idex;
  reg  stall_idex;
  reg  consume_idex;
  reg  in_valid_idex;
  reg  [8:0]  in_pc_idex;
  reg  [15:0] in_ctrl_idex;
  reg  [2:0]  in_rd_idex;
  reg         in_dtype_idex;
  reg  [15:0] in_imm_idex;
  reg  [63:0] in_base_idex;
  reg  [31:0] in_tid_idex;
  reg  [3:0]  in_mask_idex;
  reg  [63:0] in_op1_0_idex,in_op1_1_idex,in_op1_2_idex,in_op1_3_idex;
  reg  [63:0] in_op2_0_idex,in_op2_1_idex,in_op2_2_idex,in_op2_3_idex;
  reg  [63:0] in_acc_0_idex,in_acc_1_idex,in_acc_2_idex,in_acc_3_idex;

  wire out_valid_idex;
  wire [8:0]  out_pc_idex;
  wire [15:0] out_ctrl_idex;
  wire [2:0]  out_rd_idex;
  wire        out_dtype_idex;
  wire [15:0] out_imm_idex;
  wire [63:0] out_base_idex;
  wire [31:0] out_tid_idex;
  wire [3:0]  out_mask_idex;
  wire [63:0] out_op1_0_idex,out_op1_1_idex,out_op1_2_idex,out_op1_3_idex;
  wire [63:0] out_op2_0_idex,out_op2_1_idex,out_op2_2_idex,out_op2_3_idex;
  wire [63:0] out_acc_0_idex,out_acc_1_idex,out_acc_2_idex,out_acc_3_idex;

  id_ex_reg U_IDEX (
    .clk(clk), .rst(rst_idex),
    .stall(stall_idex),
    .consume_pulse(consume_idex),
    .in_valid(in_valid_idex),
    .in_pc(in_pc_idex),
    .in_ctrl(in_ctrl_idex),
    .in_rd(in_rd_idex),
    .in_dtype(in_dtype_idex),
    .in_imm(in_imm_idex),
    .in_base_sel(in_base_idex),
    .in_tid_base(in_tid_idex),
    .in_lane_mask(in_mask_idex),
    .in_op1_0(in_op1_0_idex), .in_op1_1(in_op1_1_idex), .in_op1_2(in_op1_2_idex), .in_op1_3(in_op1_3_idex),
    .in_op2_0(in_op2_0_idex), .in_op2_1(in_op2_1_idex), .in_op2_2(in_op2_2_idex), .in_op2_3(in_op2_3_idex),
    .in_acc_0(in_acc_0_idex), .in_acc_1(in_acc_1_idex), .in_acc_2(in_acc_2_idex), .in_acc_3(in_acc_3_idex),
    .out_valid(out_valid_idex),
    .out_pc(out_pc_idex),
    .out_ctrl(out_ctrl_idex),
    .out_rd(out_rd_idex),
    .out_dtype(out_dtype_idex),
    .out_imm(out_imm_idex),
    .out_base_sel(out_base_idex),
    .out_tid_base(out_tid_idex),
    .out_lane_mask(out_mask_idex),
    .out_op1_0(out_op1_0_idex), .out_op1_1(out_op1_1_idex), .out_op1_2(out_op1_2_idex), .out_op1_3(out_op1_3_idex),
    .out_op2_0(out_op2_0_idex), .out_op2_1(out_op2_1_idex), .out_op2_2(out_op2_2_idex), .out_op2_3(out_op2_3_idex),
    .out_acc_0(out_acc_0_idex), .out_acc_1(out_acc_1_idex), .out_acc_2(out_acc_2_idex), .out_acc_3(out_acc_3_idex)
  );

  reg  rst_exmm;
  reg  in_valid_exmm;
  reg  [15:0] in_ctrl_exmm;
  reg  [2:0]  in_rd_exmm;
  reg  [3:0]  in_mask_exmm;
  reg  [9:0]  in_a0_exmm,in_a1_exmm,in_a2_exmm,in_a3_exmm;
  reg  [63:0] in_s0_exmm,in_s1_exmm,in_s2_exmm,in_s3_exmm;
  reg  [63:0] in_r0_exmm,in_r1_exmm,in_r2_exmm,in_r3_exmm;

  wire out_valid_exmm;
  wire [15:0] out_ctrl_exmm;
  wire [2:0]  out_rd_exmm;
  wire [3:0]  out_mask_exmm;
  wire [9:0]  out_a0_exmm,out_a1_exmm,out_a2_exmm,out_a3_exmm;
  wire [63:0] out_s0_exmm,out_s1_exmm,out_s2_exmm,out_s3_exmm;
  wire [63:0] out_r0_exmm,out_r1_exmm,out_r2_exmm,out_r3_exmm;

  ex_mm_reg #(.DMEM_AW(10)) U_EXMM (
    .clk(clk), .rst(rst_exmm),
    .in_valid(in_valid_exmm),
    .in_ctrl(in_ctrl_exmm),
    .in_rd(in_rd_exmm),
    .in_lane_mask(in_mask_exmm),
    .in_addr0(in_a0_exmm), .in_addr1(in_a1_exmm), .in_addr2(in_a2_exmm), .in_addr3(in_a3_exmm),
    .in_store0(in_s0_exmm), .in_store1(in_s1_exmm), .in_store2(in_s2_exmm), .in_store3(in_s3_exmm),
    .in_res0(in_r0_exmm), .in_res1(in_r1_exmm), .in_res2(in_r2_exmm), .in_res3(in_r3_exmm),
    .out_valid(out_valid_exmm),
    .out_ctrl(out_ctrl_exmm),
    .out_rd(out_rd_exmm),
    .out_lane_mask(out_mask_exmm),
    .out_addr0(out_a0_exmm), .out_addr1(out_a1_exmm), .out_addr2(out_a2_exmm), .out_addr3(out_a3_exmm),
    .out_store0(out_s0_exmm), .out_store1(out_s1_exmm), .out_store2(out_s2_exmm), .out_store3(out_s3_exmm),
    .out_res0(out_r0_exmm), .out_res1(out_r1_exmm), .out_res2(out_r2_exmm), .out_res3(out_r3_exmm)
  );

  task test_id_ex_reg_unit;
    begin
      $display("=== test_id_ex_reg_unit ===");
      rst_idex = 1; tick(); rst_idex = 0; tick();

      stall_idex = 0;
      consume_idex = 0;

      in_valid_idex = 1;
      in_pc_idex    = 9'd12;
      in_ctrl_idex  = 16'h00F0;
      in_rd_idex    = 3'd5;
      in_dtype_idex = 1'b1;
      in_imm_idex   = 16'h1234;
      in_base_idex  = 64'h00000000000000AA;
      in_tid_idex   = 32'h00000011;
      in_mask_idex  = 4'hF;
      in_op1_0_idex = 64'h1; in_op1_1_idex = 64'h2; in_op1_2_idex = 64'h3; in_op1_3_idex = 64'h4;
      in_op2_0_idex = 64'h5; in_op2_1_idex = 64'h6; in_op2_2_idex = 64'h7; in_op2_3_idex = 64'h8;
      in_acc_0_idex = 64'h9; in_acc_1_idex = 64'hA; in_acc_2_idex = 64'hB; in_acc_3_idex = 64'hC;

      tick();
      `CHECK_TRUE("idex_latch_valid", out_valid_idex);
      `CHECK_EQ_DEC("idex_latch_pc", out_pc_idex, 9'd12);
      `CHECK_EQ_HEX("idex_latch_ctrl", out_ctrl_idex, 16'h00F0);

      stall_idex = 1;
      in_pc_idex = 9'd33;
      tick();
      `CHECK_EQ_DEC("idex_hold_on_stall", out_pc_idex, 9'd12);

      stall_idex = 0;
      consume_idex = 1;
      tick();
      consume_idex = 0;
      `CHECK_FALSE("idex_consume_clears_valid", out_valid_idex);

      $display("ALL PASS test_id_ex_reg_unit");
    end
  endtask

  task test_ex_mm_reg_unit;
    begin
      $display("=== test_ex_mm_reg_unit ===");
      rst_exmm = 1; tick(); rst_exmm = 0; tick();

      in_valid_exmm = 1;
      in_ctrl_exmm  = 16'hBEEF;
      in_rd_exmm    = 3'd6;
      in_mask_exmm  = 4'b1010;
      in_a0_exmm = 10'd1; in_a1_exmm = 10'd2; in_a2_exmm = 10'd3; in_a3_exmm = 10'd4;
      in_s0_exmm = 64'h00000000000000A0;
      in_s1_exmm = 64'h00000000000000A1;
      in_s2_exmm = 64'h00000000000000A2;
      in_s3_exmm = 64'h00000000000000A3;

      in_r0_exmm = 64'h00000000000000D0;
      in_r1_exmm = 64'h00000000000000D1;
      in_r2_exmm = 64'h00000000000000D2;
      in_r3_exmm = 64'h00000000000000D3;

      tick();
      `CHECK_TRUE("exmm_valid", out_valid_exmm);
      `CHECK_EQ_HEX("exmm_ctrl", out_ctrl_exmm, 16'hBEEF);
      `CHECK_EQ_DEC("exmm_rd", out_rd_exmm, 3'd6);
      `CHECK_EQ_DEC("exmm_addr2", out_a2_exmm, 10'd3);
      `CHECK_EQ_HEX("exmm_res3", out_r3_exmm, 64'h00000000000000D3);

      $display("ALL PASS test_ex_mm_reg_unit");
    end
  endtask

  initial begin
    cycle = 0;
    clk   = 0;

    rst_idex=0; stall_idex=0; consume_idex=0; in_valid_idex=0;
    rst_exmm=0; in_valid_exmm=0;

    tick(); tick();

    test_id_ex_reg_unit();
    test_ex_mm_reg_unit();

    $display("=== EXTRA UNIT TESTS PASS ===");
    $finish;
  end

endmodule