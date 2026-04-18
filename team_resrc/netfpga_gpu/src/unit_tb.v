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

  function [63:0] pack16;
    input [15:0] a0,a1,a2,a3;
    begin
      pack16 = {a3,a2,a1,a0};
    end
  endfunction

  function [15:0] S16;
    input signed [31:0] v;
    begin
      S16 = v[15:0];
    end
  endfunction

  function [63:0] pack_bf16;
    input [15:0] e0,e1,e2,e3;
    begin
      pack_bf16 = {e3,e2,e1,e0};
    end
  endfunction

  localparam [15:0] BF16_1 = 16'h3F80;
  localparam [15:0] BF16_2 = 16'h4000;
  localparam [15:0] BF16_3 = 16'h4040;
  localparam [15:0] BF16_7 = 16'h40E0;

  // ---------------- gpu_control DUT ----------------
  reg rst_ctrl;
  reg mmio_wr_en, mmio_rd_en;
  reg [7:0] mmio_addr;
  reg [31:0] mmio_wdata;
  wire [31:0] mmio_rdata;

  reg hw_done_pulse, hw_error_pulse;
  reg [7:0] hw_error_code;

  wire run_en;
  wire start_pulse, clear_done_pulse, soft_reset_pulse;

  wire [8:0] entry_pc;
  wire [31:0] tid_init, work_size, m, n, k;
  wire [63:0] base_a, base_b, base_c, base_d;

  wire busy, done, error;
  wire [7:0] error_code;

  gpu_control #(.ADDR_W(8)) U_CTRL (
    .clk(clk), .rst(rst_ctrl),
    .mmio_wr_en(mmio_wr_en),
    .mmio_rd_en(mmio_rd_en),
    .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata),
    .mmio_rdata(mmio_rdata),
    .hw_done_pulse(hw_done_pulse),
    .hw_error_pulse(hw_error_pulse),
    .hw_error_code(hw_error_code),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .clear_done_pulse(clear_done_pulse),
    .soft_reset_pulse(soft_reset_pulse),
    .entry_pc(entry_pc),
    .tid_init(tid_init),
    .work_size(work_size),
    .m(m), .n(n), .k(k),
    .base_a(base_a), .base_b(base_b), .base_c(base_c), .base_d(base_d),
    .busy(busy), .done(done), .error(error), .error_code(error_code)
  );

  // ---------------- pc DUT ----------------
  reg rst_pc;
  reg run_en_pc, start_pulse_pc, soft_reset_pc, stall_pc, jump_valid_pc;
  reg [8:0] entry_pc_pc, jump_addr_pc;
  wire [8:0] pc_out;

  pc U_PC (
    .clk(clk), .rst(rst_pc),
    .run_en(run_en_pc),
    .start_pulse(start_pulse_pc),
    .entry_pc(entry_pc_pc),
    .soft_reset_pulse(soft_reset_pc),
    .stall(stall_pc),
    .jump_valid(jump_valid_pc),
    .jump_addr(jump_addr_pc),
    .pc(pc_out)
  );

  // ---------------- imem DUT ----------------
  reg imem_we;
  reg [8:0] imem_addr;
  reg [31:0] imem_wdata;
  wire [31:0] imem_rdata;

  imem U_IMEM (
    .clk(clk),
    .we(imem_we),
    .addr(imem_addr),
    .wdata(imem_wdata),
    .rdata(imem_rdata)
  );

  // ---------------- if_id_reg DUT ----------------
  reg rst_ifid, stall_ifid;
  reg [8:0] pc_in_ifid;
  reg [31:0] instr_in_ifid;
  reg flush_in_ifid;
  wire [8:0] pc_id_ifid;
  wire [31:0] instr_id_ifid;
  wire flush_out_ifid;

  if_id_reg U_IFID (
    .clk(clk), .rst(rst_ifid),
    .stall(stall_ifid),
    .pc_in(pc_in_ifid),
    .instr_in(instr_in_ifid),
    .flush_in(flush_in_ifid),
    .pc_id(pc_id_ifid),
    .instr_id(instr_id_ifid),
    .flush_out(flush_out_ifid)
  );

  // ---------------- dmem DUT ----------------
  reg dmem_re, dmem_we;
  reg [9:0] dmem_addr;
  reg [63:0] dmem_wdata;
  wire [63:0] dmem_rdata;

  dmem #(.AW(10), .DEPTH(1024)) U_DMEM (
    .clk(clk),
    .re(dmem_re),
    .we(dmem_we),
    .addr(dmem_addr),
    .wdata(dmem_wdata),
    .rdata(dmem_rdata)
  );

  // ---------------- wb_stage DUT ----------------
  reg rst_wb;
  reg wb_in_valid;
  reg [15:0] wb_in_ctrl;
  reg [2:0]  wb_in_rd;
  reg [3:0]  wb_in_lane_mask;
  reg [63:0] wb_in_res0,wb_in_res1,wb_in_res2,wb_in_res3;
  reg [63:0] wb_in_load0,wb_in_load1,wb_in_load2,wb_in_load3;
  wire wb_we0,wb_we1,wb_we2,wb_we3;
  wire [2:0] wb_rd_out;
  wire [63:0] wb_wdata0,wb_wdata1,wb_wdata2,wb_wdata3;

  wb_stage U_WB (
    .clk(clk), .rst(rst_wb),
    .in_valid(wb_in_valid),
    .in_ctrl(wb_in_ctrl),
    .in_rd(wb_in_rd),
    .in_lane_mask(wb_in_lane_mask),
    .in_res0(wb_in_res0), .in_res1(wb_in_res1), .in_res2(wb_in_res2), .in_res3(wb_in_res3),
    .in_load0(wb_in_load0), .in_load1(wb_in_load1), .in_load2(wb_in_load2), .in_load3(wb_in_load3),
    .wb_we0(wb_we0), .wb_we1(wb_we1), .wb_we2(wb_we2), .wb_we3(wb_we3),
    .wb_rd(wb_rd_out),
    .wb_wdata0(wb_wdata0), .wb_wdata1(wb_wdata1), .wb_wdata2(wb_wdata2), .wb_wdata3(wb_wdata3)
  );

  // ---------------- ex_stage DUT ----------------
  reg rst_ex;
  reg ex_in_valid;
  reg [15:0] ex_in_ctrl;
  reg [2:0]  ex_in_rd;
  reg ex_in_dtype;
  reg [15:0] ex_in_imm;
  reg [63:0] ex_in_base_sel;
  reg [31:0] ex_in_tid_base;
  reg [3:0]  ex_in_lane_mask;
  reg [63:0] ex_in_op1_0,ex_in_op1_1,ex_in_op1_2,ex_in_op1_3;
  reg [63:0] ex_in_op2_0,ex_in_op2_1,ex_in_op2_2,ex_in_op2_3;
  reg [63:0] ex_in_acc_0,ex_in_acc_1,ex_in_acc_2,ex_in_acc_3;

  wire ex_stall;
  wire ex_consume_pulse;
  wire ex_out_valid;
  wire [15:0] ex_out_ctrl;
  wire [2:0]  ex_out_rd;
  wire [3:0]  ex_out_lane_mask;
  wire [9:0] ex_out_addr0,ex_out_addr1,ex_out_addr2,ex_out_addr3;
  wire [63:0] ex_out_store0,ex_out_store1,ex_out_store2,ex_out_store3;
  wire [63:0] ex_out_res0,ex_out_res1,ex_out_res2,ex_out_res3;

  ex_stage #(.DMEM_AW(10)) U_EX (
    .clk(clk), .rst(rst_ex),
    .in_valid(ex_in_valid),
    .in_ctrl(ex_in_ctrl),
    .in_rd(ex_in_rd),
    .in_dtype(ex_in_dtype),
    .in_imm(ex_in_imm),
    .in_base_sel(ex_in_base_sel),
    .in_tid_base(ex_in_tid_base),
    .in_lane_mask(ex_in_lane_mask),
    .in_op1_0(ex_in_op1_0), .in_op1_1(ex_in_op1_1), .in_op1_2(ex_in_op1_2), .in_op1_3(ex_in_op1_3),
    .in_op2_0(ex_in_op2_0), .in_op2_1(ex_in_op2_1), .in_op2_2(ex_in_op2_2), .in_op2_3(ex_in_op2_3),
    .in_acc_0(ex_in_acc_0), .in_acc_1(ex_in_acc_1), .in_acc_2(ex_in_acc_2), .in_acc_3(ex_in_acc_3),
    .stall(ex_stall),
    .consume_pulse(ex_consume_pulse),
    .out_valid(ex_out_valid),
    .out_ctrl(ex_out_ctrl),
    .out_rd(ex_out_rd),
    .out_lane_mask(ex_out_lane_mask),
    .out_addr0(ex_out_addr0), .out_addr1(ex_out_addr1), .out_addr2(ex_out_addr2), .out_addr3(ex_out_addr3),
    .out_store0(ex_out_store0), .out_store1(ex_out_store1), .out_store2(ex_out_store2), .out_store3(ex_out_store3),
    .out_res0(ex_out_res0), .out_res1(ex_out_res1), .out_res2(ex_out_res2), .out_res3(ex_out_res3)
  );

  // ---------------- mm_stage DUT ----------------
  reg rst_mm;
  reg mm_in_valid;
  reg [15:0] mm_in_ctrl;
  reg [2:0]  mm_in_rd;
  reg [3:0]  mm_in_lane_mask;
  reg [9:0]  mm_in_addr0,mm_in_addr1,mm_in_addr2,mm_in_addr3;
  reg [63:0] mm_in_store0,mm_in_store1,mm_in_store2,mm_in_store3;
  reg [63:0] mm_in_res0,mm_in_res1,mm_in_res2,mm_in_res3;

  wire mm_out_valid;
  wire [15:0] mm_out_ctrl;
  wire [2:0]  mm_out_rd;
  wire [3:0]  mm_out_lane_mask;
  wire [63:0] mm_dmem_r0,mm_dmem_r1,mm_dmem_r2,mm_dmem_r3;
  wire [63:0] mm_out_res0,mm_out_res1,mm_out_res2,mm_out_res3;

  mm_stage #(.DMEM_AW(10), .DMEM_DEPTH(64)) U_MM (
    .clk(clk), .rst(rst_mm),
    .in_valid(mm_in_valid),
    .in_ctrl(mm_in_ctrl),
    .in_rd(mm_in_rd),
    .in_lane_mask(mm_in_lane_mask),
    .in_addr0(mm_in_addr0), .in_addr1(mm_in_addr1), .in_addr2(mm_in_addr2), .in_addr3(mm_in_addr3),
    .in_store0(mm_in_store0), .in_store1(mm_in_store1), .in_store2(mm_in_store2), .in_store3(mm_in_store3),
    .in_res0(mm_in_res0), .in_res1(mm_in_res1), .in_res2(mm_in_res2), .in_res3(mm_in_res3),
    .out_valid(mm_out_valid),
    .out_ctrl(mm_out_ctrl),
    .out_rd(mm_out_rd),
    .out_lane_mask(mm_out_lane_mask),
    .dmem_rdata0(mm_dmem_r0), .dmem_rdata1(mm_dmem_r1), .dmem_rdata2(mm_dmem_r2), .dmem_rdata3(mm_dmem_r3),
    .out_res0(mm_out_res0), .out_res1(mm_out_res1), .out_res2(mm_out_res2), .out_res3(mm_out_res3)
  );

  // ---------------- mm_wb_reg DUT ----------------
  reg rst_mmwbr;
  reg mmwbr_in_valid;
  reg [15:0] mmwbr_in_ctrl;
  reg [2:0]  mmwbr_in_rd;
  reg [3:0]  mmwbr_in_lane_mask;
  reg [63:0] mmwbr_in_res0,mmwbr_in_res1,mmwbr_in_res2,mmwbr_in_res3;
  reg [63:0] mmwbr_in_load0,mmwbr_in_load1,mmwbr_in_load2,mmwbr_in_load3;

  wire mmwbr_out_valid;
  wire [15:0] mmwbr_out_ctrl;
  wire [2:0]  mmwbr_out_rd;
  wire [3:0]  mmwbr_out_lane_mask;
  wire [63:0] mmwbr_out_res0,mmwbr_out_res1,mmwbr_out_res2,mmwbr_out_res3;
  wire [63:0] mmwbr_out_load0,mmwbr_out_load1,mmwbr_out_load2,mmwbr_out_load3;

  mm_wb_reg U_MMWBR (
    .clk(clk), .rst(rst_mmwbr),
    .in_valid(mmwbr_in_valid),
    .in_ctrl(mmwbr_in_ctrl),
    .in_rd(mmwbr_in_rd),
    .in_lane_mask(mmwbr_in_lane_mask),
    .in_res0(mmwbr_in_res0), .in_res1(mmwbr_in_res1), .in_res2(mmwbr_in_res2), .in_res3(mmwbr_in_res3),
    .in_load0(mmwbr_in_load0), .in_load1(mmwbr_in_load1), .in_load2(mmwbr_in_load2), .in_load3(mmwbr_in_load3),
    .out_valid(mmwbr_out_valid),
    .out_ctrl(mmwbr_out_ctrl),
    .out_rd(mmwbr_out_rd),
    .out_lane_mask(mmwbr_out_lane_mask),
    .out_res0(mmwbr_out_res0), .out_res1(mmwbr_out_res1), .out_res2(mmwbr_out_res2), .out_res3(mmwbr_out_res3),
    .out_load0(mmwbr_out_load0), .out_load1(mmwbr_out_load1), .out_load2(mmwbr_out_load2), .out_load3(mmwbr_out_load3)
  );

  // ---------------- helpers for gpu_control ----------------
  task mmio_write;
    input [7:0] a;
    input [31:0] d;
    begin
      mmio_addr = a;
      mmio_wdata = d;
      mmio_wr_en = 1'b1;
      tick();
      mmio_wr_en = 1'b0;
    end
  endtask

task mmio_read_check;
  input [7:0] a;
  input [31:0] exp;
  begin
    mmio_addr  = a;
    mmio_rd_en = 1'b1;
    tick();
    if (mmio_rdata !== exp) begin
      $display("FAIL [mmio_read] cycle=%0d addr=%h GOT=%h EXP=%h", cycle, a, mmio_rdata, exp);
      $finish;
    end else begin
      $display("PASS [mmio_read] cycle=%0d addr=%h = %h", cycle, a, mmio_rdata);
    end
    mmio_rd_en = 1'b0;
    mmio_addr  = 8'h00;
  end
endtask

  // ---------------- tests ----------------
  task test_gpu_control;
    begin
      $display("=== test_gpu_control ===");
      rst_ctrl = 1; tick(); rst_ctrl = 0; tick();

      mmio_wr_en=0; mmio_rd_en=0; mmio_addr=0; mmio_wdata=0;
      hw_done_pulse=0; hw_error_pulse=0; hw_error_code=0;

      mmio_read_check(8'h04, 32'h0);
      `CHECK_FALSE("ctrl_busy_reset", busy);
      `CHECK_FALSE("ctrl_done_reset", done);
      `CHECK_FALSE("ctrl_error_reset", error);
      `CHECK_EQ_HEX("ctrl_errcode_reset", error_code, 8'h00);

      mmio_write(8'h08, 32'h00000015);
      mmio_read_check(8'h08, 32'h00000015);
      `CHECK_EQ_DEC("ctrl_entry_pc_out", entry_pc, 9'd21);

      mmio_write(8'h0C, 32'h00000040);
      mmio_read_check(8'h0C, 32'h00000040);

      mmio_write(8'h10, 32'h00000100);
      mmio_read_check(8'h10, 32'h00000100);

      mmio_write(8'h20, 32'hAAAA0001);
      mmio_write(8'h24, 32'hAAAA0002);
      mmio_read_check(8'h20, 32'hAAAA0001);
      mmio_read_check(8'h24, 32'hAAAA0002);

      mmio_write(8'h40, 32'd7);
      mmio_write(8'h44, 32'd9);
      mmio_write(8'h48, 32'd11);
      mmio_read_check(8'h40, 32'd7);
      mmio_read_check(8'h44, 32'd9);
      mmio_read_check(8'h48, 32'd11);

      mmio_write(8'h00, 32'h1);
      `CHECK_TRUE("ctrl_start_pulse", start_pulse);
      `CHECK_TRUE("ctrl_busy_after_start", busy);
      `CHECK_FALSE("ctrl_done_clear_on_start", done);

      mmio_write(8'h00, 32'h1);
      `CHECK_TRUE("ctrl_error_start_while_busy", error);
      `CHECK_EQ_HEX("ctrl_errcode_start_busy", error_code, 8'h01);

      mmio_write(8'h08, 32'h00000003);
      `CHECK_EQ_HEX("ctrl_errcode_param_write_busy", error_code, 8'h02);

      hw_done_pulse=1; tick(); hw_done_pulse=0;
      `CHECK_FALSE("ctrl_busy_cleared_on_done", busy);
      `CHECK_TRUE("ctrl_done_set_on_done", done);

      mmio_write(8'h00, 32'h2);
      `CHECK_TRUE("ctrl_clear_done_pulse", clear_done_pulse);
      `CHECK_FALSE("ctrl_done_cleared", done);

      mmio_write(8'h00, 32'h1);
      `CHECK_TRUE("ctrl_start_again_ok", start_pulse);
      `CHECK_TRUE("ctrl_busy_again", busy);
      `CHECK_FALSE("ctrl_error_cleared_on_start", error);

      hw_error_code = 8'hAB;
      hw_error_pulse=1; tick(); hw_error_pulse=0;
      `CHECK_FALSE("ctrl_busy_cleared_on_error", busy);
      `CHECK_TRUE("ctrl_error_set", error);
      `CHECK_EQ_HEX("ctrl_error_code_hw", error_code, 8'hAB);

      mmio_write(8'h00, 32'h4);
      `CHECK_TRUE("ctrl_soft_reset_pulse", soft_reset_pulse);
      `CHECK_FALSE("ctrl_busy_after_soft_reset", busy);
      `CHECK_FALSE("ctrl_done_after_soft_reset", done);
      `CHECK_FALSE("ctrl_error_after_soft_reset", error);
      mmio_read_check(8'h08, 32'h0);

      $display("ALL PASS test_gpu_control");
    end
  endtask

  task test_pc_unit;
    begin
      $display("=== test_pc ===");
      rst_pc=1; tick(); rst_pc=0; tick();

      run_en_pc=0; start_pulse_pc=0; soft_reset_pc=0; stall_pc=0; jump_valid_pc=0;
      entry_pc_pc=0; jump_addr_pc=0;

      `CHECK_EQ_DEC("pc_reset", pc_out, 9'd0);

      entry_pc_pc=9'd7; start_pulse_pc=1; run_en_pc=0;
      tick();
      start_pulse_pc=0;
      `CHECK_EQ_DEC("pc_load_entry", pc_out, 9'd7);

      run_en_pc=1;
      tick(); `CHECK_EQ_DEC("pc_inc1", pc_out, 9'd8);
      tick(); `CHECK_EQ_DEC("pc_inc2", pc_out, 9'd9);

      stall_pc=1;
      tick(); `CHECK_EQ_DEC("pc_hold_stall", pc_out, 9'd9);
      stall_pc=0;

      jump_valid_pc=1; jump_addr_pc=9'd20;
      tick(); jump_valid_pc=0;
      `CHECK_EQ_DEC("pc_jump", pc_out, 9'd20);

      run_en_pc=0;
      tick(); `CHECK_EQ_DEC("pc_hold_run0", pc_out, 9'd20);

      soft_reset_pc=1;
      tick(); soft_reset_pc=0;
      `CHECK_EQ_DEC("pc_soft_reset", pc_out, 9'd0);

      $display("ALL PASS test_pc");
    end
  endtask

  task test_imem_unit;
    begin
      $display("=== test_imem ===");
      imem_we=0; imem_addr=0; imem_wdata=0;

      imem_addr=9'd5; imem_we=0;
      tick();
      `CHECK_EQ_HEX("imem_default_nop", imem_rdata, 32'h00000013);

      imem_addr=9'd5; imem_wdata=32'hDEADBEEF; imem_we=1;
      tick();
      imem_we=0;
      `CHECK_EQ_HEX("imem_write_through", imem_rdata, 32'hDEADBEEF);

      imem_addr=9'd5; imem_we=0;
      tick();
      `CHECK_EQ_HEX("imem_read_back", imem_rdata, 32'hDEADBEEF);

      $display("ALL PASS test_imem");
    end
  endtask

  task test_ifid_unit;
    begin
      $display("=== test_if_id_reg ===");
      rst_ifid=1; tick(); rst_ifid=0; tick();

      stall_ifid=0;
      pc_in_ifid=9'd10; instr_in_ifid=32'h11112222; flush_in_ifid=1;
      tick();
      `CHECK_EQ_DEC("ifid_pc_latch", pc_id_ifid, 9'd10);
      `CHECK_EQ_HEX("ifid_instr_passthru", instr_id_ifid, 32'h11112222);
      `CHECK_TRUE("ifid_flush_latch", flush_out_ifid);

      stall_ifid=1;
      pc_in_ifid=9'd20; instr_in_ifid=32'h33334444; flush_in_ifid=0;
      tick();
      `CHECK_EQ_DEC("ifid_pc_hold_stall", pc_id_ifid, 9'd10);
      `CHECK_TRUE("ifid_flush_hold_stall", flush_out_ifid);
      `CHECK_EQ_HEX("ifid_instr_passthru_even_stall", instr_id_ifid, 32'h33334444);

      stall_ifid=0;
      tick();
      `CHECK_EQ_DEC("ifid_pc_update_after_stall", pc_id_ifid, 9'd20);
      `CHECK_FALSE("ifid_flush_update_after_stall", flush_out_ifid);

      $display("ALL PASS test_if_id_reg");
    end
  endtask

  task test_dmem_unit;
    begin
      $display("=== test_dmem ===");
      dmem_re=0; dmem_we=0; dmem_addr=0; dmem_wdata=0;

      dmem_addr=10'd7; dmem_wdata=64'h0123456789ABCDEF; dmem_we=1;
      tick();
      dmem_we=0;

      dmem_addr=10'd7; dmem_re=1;
      tick();
      dmem_re=0;
      `CHECK_EQ_HEX("dmem_read_back", dmem_rdata, 64'h0123456789ABCDEF);

      $display("ALL PASS test_dmem");
    end
  endtask

  task test_wb_unit;
    begin
      $display("=== test_wb_stage ===");
      rst_wb=1; tick(); rst_wb=0; tick();

      wb_in_valid=1;
      wb_in_lane_mask=4'b1011;
      wb_in_rd=3'd3;
      wb_in_ctrl=16'd0; wb_in_ctrl[4]=1;
      wb_in_res0=64'h1; wb_in_res1=64'h2; wb_in_res2=64'h3; wb_in_res3=64'h4;

      wb_in_load0=64'hAA; wb_in_load1=64'hBB; wb_in_load2=64'hCC; wb_in_load3=64'hDD;

      tick();
      `CHECK_EQ_DEC("wb_rd", wb_rd_out, 3'd3);
      `CHECK_TRUE("wb_we0", wb_we0);
      `CHECK_TRUE("wb_we1", wb_we1);
      `CHECK_FALSE("wb_we2_masked", wb_we2);
      `CHECK_TRUE("wb_we3", wb_we3);
      `CHECK_EQ_HEX("wb_wdata0_res", wb_wdata0, 64'h1);

      wb_in_ctrl=16'd0; wb_in_ctrl[0]=1;
      tick();
      `CHECK_EQ_HEX("wb_wdata0_load", wb_wdata0, 64'hAA);
      `CHECK_EQ_HEX("wb_wdata3_load", wb_wdata3, 64'hDD);

      $display("ALL PASS test_wb_stage");
    end
  endtask

  task test_ex_int16_unit;
    integer exp_addr0;
    integer exp_addr3;
    begin
      $display("=== test_ex_stage_int16 ===");
      rst_ex=1; tick(); rst_ex=0; tick();

      ex_in_valid=1;
      ex_in_dtype=0;
      ex_in_lane_mask=4'hF;
      ex_in_base_sel=64'd100;
      ex_in_tid_base=32'd5;
      ex_in_imm=16'd3;

      ex_in_op1_0=0; ex_in_op1_1=0; ex_in_op1_2=0; ex_in_op1_3=0;
      ex_in_op2_0=0; ex_in_op2_1=0; ex_in_op2_2=0; ex_in_op2_3=0;
      ex_in_acc_0=0; ex_in_acc_1=0; ex_in_acc_2=0; ex_in_acc_3=0;

      ex_in_ctrl=16'd0; ex_in_ctrl[2]=1;
      tick();
      `CHECK_FALSE("ex_stall_int16", ex_stall);
      `CHECK_TRUE("ex_out_valid_int16", ex_out_valid);
      `CHECK_EQ_HEX("ex_loadi_lane0", ex_out_res0, pack16(16'd3,16'd3,16'd3,16'd3));

      exp_addr0 = 100+5+0+3;
      exp_addr3 = 100+5+3+3;
      `CHECK_EQ_DEC("ex_addr0", ex_out_addr0, exp_addr0);
      `CHECK_EQ_DEC("ex_addr3", ex_out_addr3, exp_addr3);

      ex_in_ctrl=16'd0; ex_in_ctrl[4]=1;
      ex_in_op1_0=pack16(16'd1,16'd2,16'd3,16'd4);
      ex_in_op2_0=pack16(16'd10,16'd20,16'd30,16'd40);
      tick();
      `CHECK_EQ_HEX("ex_add16x4", ex_out_res0, pack16(16'd11,16'd22,16'd33,16'd44));

      ex_in_ctrl=16'd0; ex_in_ctrl[5]=1;
      tick();
      `CHECK_EQ_HEX("ex_sub16x4", ex_out_res0, pack16(S16(1-10),S16(2-20),S16(3-30),S16(4-40)));

      ex_in_ctrl=16'd0; ex_in_ctrl[6]=1;
      ex_in_op1_0=pack16(16'd2,16'd3,16'd4,16'd5);
      ex_in_op2_0=pack16(16'd6,16'd7,16'd8,16'd9);
      tick();
      `CHECK_EQ_HEX("ex_mul16x4", ex_out_res0, pack16(16'd12,16'd21,16'd32,16'd45));

      ex_in_ctrl=16'd0; ex_in_ctrl[7]=1;
      ex_in_op1_0=pack16(16'hFFFF,16'h8000,16'd7,16'hFFFE);
      tick();
      `CHECK_EQ_HEX("ex_relu16x4", ex_out_res0, pack16(16'd0,16'd0,16'd7,16'd0));

      ex_in_ctrl=16'd0; ex_in_ctrl[8]=1;
      ex_in_op1_0=pack16(16'd2,16'd2,16'd2,16'd2);
      ex_in_op2_0=pack16(16'd3,16'd4,16'd5,16'd6);
      tick();
      `CHECK_EQ_HEX("ex_tensor_mul_int16", ex_out_res0, pack16(16'd6,16'd8,16'd10,16'd12));

      ex_in_ctrl=16'd0; ex_in_ctrl[9]=1;
      ex_in_acc_0=pack16(16'd1,16'd1,16'd1,16'd1);
      tick();
      `CHECK_EQ_HEX("ex_tensor_mac_int16", ex_out_res0, pack16(16'd7,16'd9,16'd11,16'd13));

      $display("ALL PASS test_ex_stage_int16");
    end
  endtask


  task bf16_fire;
    input is_mac;
    input [63:0] op1;
    input [63:0] op2;
    input [63:0] acc;
    integer w;
    begin

      for (w=0; w<200; w=w+1) begin
        if (!ex_stall) w=200;
        else tick();
      end


      ex_in_lane_mask = 4'b0001;
      ex_in_dtype     = 1'b1;
      ex_in_base_sel  = 64'd0;
      ex_in_tid_base  = 32'd0;
      ex_in_imm       = 16'd0;

      ex_in_op1_0 = op1;
      ex_in_op2_0 = op2;
      ex_in_acc_0 = acc;

      ex_in_op1_1 = 64'd0; ex_in_op1_2 = 64'd0; ex_in_op1_3 = 64'd0;
      ex_in_op2_1 = 64'd0; ex_in_op2_2 = 64'd0; ex_in_op2_3 = 64'd0;
      ex_in_acc_1 = 64'd0; ex_in_acc_2 = 64'd0; ex_in_acc_3 = 64'd0;

      ex_in_ctrl = 16'd0;
      if (is_mac) ex_in_ctrl[9] = 1'b1;
      else        ex_in_ctrl[8] = 1'b1;

 
      ex_in_valid = 1'b1;
      for (w=0; w<4; w=w+1) begin
        tick();
        if (ex_stall) w=4;  
      end
      ex_in_valid = 1'b0;


      tick();
    end
  endtask

  task wait_ex_out;
    input [127:0] name;
    input integer timeout;
    output [63:0] res0;
    integer t;
    reg found;
    begin
      found = 0;
      res0  = 64'd0;
      for (t=0; t<timeout; t=t+1) begin
        tick();
        if (ex_out_valid) begin
          found = 1;
          res0  = ex_out_res0;
          $display("INFO [%s] out_valid cycle=%0d res0=%h stall=%b consume=%b",
                   name, cycle, ex_out_res0, ex_stall, ex_consume_pulse);
          t = timeout;
        end
      end
      if (!found) begin
        $display("FAIL [%s] timeout cycle=%0d stall=%b consume=%b",
                 name, cycle, ex_stall, ex_consume_pulse);
        $finish;
      end
    end
  endtask

  task test_ex_bf16_unit;
    reg [63:0] got;
    begin
      $display("=== test_ex_stage_bf16 ===");
      rst_ex=1; tick(); rst_ex=0; tick();

      // bf16 mul: 1 * 2 = 2
      bf16_fire(1'b0,
                pack_bf16(BF16_1,BF16_1,BF16_1,BF16_1),
                pack_bf16(BF16_2,BF16_2,BF16_2,BF16_2),
                pack_bf16(BF16_1,BF16_1,BF16_1,BF16_1));
      wait_ex_out("bf16_mul", 800, got);
      `CHECK_EQ_HEX("bf16_mul_lane0", got, pack_bf16(BF16_2,BF16_2,BF16_2,BF16_2));

      // bf16 mac: 1 + 2*3 = 7
      bf16_fire(1'b1,
                pack_bf16(BF16_2,BF16_2,BF16_2,BF16_2),
                pack_bf16(BF16_3,BF16_3,BF16_3,BF16_3),
                pack_bf16(BF16_1,BF16_1,BF16_1,BF16_1));
      wait_ex_out("bf16_mac", 800, got);
      `CHECK_EQ_HEX("bf16_mac_lane0", got, pack_bf16(BF16_7,BF16_7,BF16_7,BF16_7));

      $display("ALL PASS test_ex_stage_bf16");
    end
  endtask

  task test_mm_unit;
    begin
      $display("=== test_mm_stage ===");
      rst_mm=1; tick(); rst_mm=0; tick();

      mm_in_valid=1;
      mm_in_lane_mask=4'b1111;
      mm_in_ctrl=16'd0; mm_in_ctrl[1]=1;

      mm_in_addr0=10'd3; mm_in_addr1=10'd4; mm_in_addr2=10'd5; mm_in_addr3=10'd6;
      mm_in_store0=64'hA0; mm_in_store1=64'hA1; mm_in_store2=64'hA2; mm_in_store3=64'hA3;
      tick();

      mm_in_ctrl=16'd0; mm_in_ctrl[0]=1;
      tick();
      `CHECK_EQ_HEX("mm_load0", mm_dmem_r0, 64'hA0);
      `CHECK_EQ_HEX("mm_load3", mm_dmem_r3, 64'hA3);

      mm_in_ctrl=16'd0; mm_in_ctrl[1]=1;
      mm_in_lane_mask=4'b0001;
      mm_in_addr0=10'd3;
      mm_in_store0=64'hB0;
      tick();

      mm_in_ctrl=16'd0; mm_in_ctrl[0]=1;
      mm_in_lane_mask=4'b1111;
      tick();
      `CHECK_EQ_HEX("mm_lane0_updated", mm_dmem_r0, 64'hB0);
      `CHECK_EQ_HEX("mm_lane1_unchanged", mm_dmem_r1, 64'hA1);

      $display("ALL PASS test_mm_stage");
    end
  endtask

  task test_mmwbr_unit;
    begin
      $display("=== test_mm_wb_reg ===");
      rst_mmwbr=1; tick(); rst_mmwbr=0; tick();

      mmwbr_in_valid=1;
      mmwbr_in_ctrl=16'h1234;
      mmwbr_in_rd=3'd5;
      mmwbr_in_lane_mask=4'b0101;
      mmwbr_in_res0=64'h10; mmwbr_in_res1=64'h11; mmwbr_in_res2=64'h12; mmwbr_in_res3=64'h13;
      mmwbr_in_load0=64'hA0; mmwbr_in_load1=64'hA1; mmwbr_in_load2=64'hA2; mmwbr_in_load3=64'hA3;

      tick();
      `CHECK_TRUE("mmwbr_valid", mmwbr_out_valid);
      `CHECK_EQ_HEX("mmwbr_ctrl", mmwbr_out_ctrl, 16'h1234);
      `CHECK_EQ_DEC("mmwbr_rd", mmwbr_out_rd, 3'd5);
      `CHECK_EQ_HEX("mmwbr_res0", mmwbr_out_res0, 64'h10);
      `CHECK_EQ_HEX("mmwbr_load2", mmwbr_out_load2, 64'hA2);

      $display("ALL PASS test_mm_wb_reg");
    end
  endtask

  initial begin
    cycle = 0;
    clk   = 0;

    rst_ctrl=0; mmio_wr_en=0; mmio_rd_en=0; mmio_addr=0; mmio_wdata=0;
    hw_done_pulse=0; hw_error_pulse=0; hw_error_code=0;

    rst_pc=0; run_en_pc=0; start_pulse_pc=0; soft_reset_pc=0; stall_pc=0; jump_valid_pc=0;
    entry_pc_pc=0; jump_addr_pc=0;

    imem_we=0; imem_addr=0; imem_wdata=0;

    rst_ifid=0; stall_ifid=0; pc_in_ifid=0; instr_in_ifid=0; flush_in_ifid=0;

    dmem_re=0; dmem_we=0; dmem_addr=0; dmem_wdata=0;

    rst_wb=0; wb_in_valid=0; wb_in_ctrl=0; wb_in_rd=0; wb_in_lane_mask=0;
    wb_in_res0=0; wb_in_res1=0; wb_in_res2=0; wb_in_res3=0;
    wb_in_load0=0; wb_in_load1=0; wb_in_load2=0; wb_in_load3=0;

    rst_ex=0; ex_in_valid=0; ex_in_ctrl=0; ex_in_rd=0; ex_in_dtype=0; ex_in_imm=0;
    ex_in_base_sel=0; ex_in_tid_base=0; ex_in_lane_mask=0;
    ex_in_op1_0=0; ex_in_op1_1=0; ex_in_op1_2=0; ex_in_op1_3=0;
    ex_in_op2_0=0; ex_in_op2_1=0; ex_in_op2_2=0; ex_in_op2_3=0;
    ex_in_acc_0=0; ex_in_acc_1=0; ex_in_acc_2=0; ex_in_acc_3=0;

    rst_mm=0; mm_in_valid=0; mm_in_ctrl=0; mm_in_rd=0; mm_in_lane_mask=0;
    mm_in_addr0=0; mm_in_addr1=0; mm_in_addr2=0; mm_in_addr3=0;
    mm_in_store0=0; mm_in_store1=0; mm_in_store2=0; mm_in_store3=0;
    mm_in_res0=0; mm_in_res1=0; mm_in_res2=0; mm_in_res3=0;

    rst_mmwbr=0; mmwbr_in_valid=0; mmwbr_in_ctrl=0; mmwbr_in_rd=0; mmwbr_in_lane_mask=0;
    mmwbr_in_res0=0; mmwbr_in_res1=0; mmwbr_in_res2=0; mmwbr_in_res3=0;
    mmwbr_in_load0=0; mmwbr_in_load1=0; mmwbr_in_load2=0; mmwbr_in_load3=0;

    tick(); tick();

    test_gpu_control();
    test_pc_unit();
    test_imem_unit();
    test_ifid_unit();
    test_dmem_unit();
    test_wb_unit();
    test_ex_int16_unit();
    test_ex_bf16_unit();
    test_mm_unit();
    test_mmwbr_unit();

    $display("=== ALL UNIT TESTS PASS ===");
    $finish;
  end

endmodule