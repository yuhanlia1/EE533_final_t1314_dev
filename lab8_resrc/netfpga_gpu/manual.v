`timescale 1ns/1ps

`define CHECK_EQ_HEX(TAG, GOT, EXP) \
  if ((GOT) !== (EXP)) begin \
    $display("FAIL [%s] cycle=%0d GOT=%h EXP=%h", (TAG), cycle, (GOT), (EXP)); \
    $finish; \
  end else begin \
    $display("PASS [%s] cycle=%0d = %h", (TAG), cycle, (GOT)); \
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

  localparam [7:0] REG_CONTROL   = 8'h00;
  localparam [7:0] REG_STATUS    = 8'h04;
  localparam [7:0] REG_ENTRY_PC  = 8'h08;
  localparam [7:0] REG_TID_INIT  = 8'h0C;
  localparam [7:0] REG_WORK_SIZE = 8'h10;

  localparam [7:0] REG_BASE_A_LO = 8'h20;
  localparam [7:0] REG_BASE_A_HI = 8'h24;
  localparam [7:0] REG_BASE_B_LO = 8'h28;
  localparam [7:0] REG_BASE_B_HI = 8'h2C;
  localparam [7:0] REG_BASE_C_LO = 8'h30;
  localparam [7:0] REG_BASE_C_HI = 8'h34;
  localparam [7:0] REG_BASE_D_LO = 8'h38;
  localparam [7:0] REG_BASE_D_HI = 8'h3C;

  localparam [7:0] REG_M         = 8'h40;
  localparam [7:0] REG_N         = 8'h44;
  localparam [7:0] REG_K         = 8'h48;

  localparam [3:0] OP_NOP        = 4'h0;
  localparam [3:0] OP_LOADI      = 4'h1;
  localparam [3:0] OP_LOAD       = 4'h2;
  localparam [3:0] OP_STORE      = 4'h3;
  localparam [3:0] OP_TENSOR_MAC = 4'hC;
  localparam [3:0] OP_HALT       = 4'hF;

  localparam [1:0] BSEL_A = 2'b00;
  localparam [1:0] BSEL_B = 2'b01;
  localparam [1:0] BSEL_C = 2'b10;

  localparam [31:0] BASE_A = 32'd0;
  localparam [31:0] BASE_B = 32'd64;
  localparam [31:0] BASE_C = 32'd128;

  reg rst;

  reg  mmio_wr_en, mmio_rd_en;
  reg  [7:0]  mmio_addr;
  reg  [31:0] mmio_wdata;
  wire [31:0] mmio_rdata;

  gpu_top dut (
    .clk(clk),
    .rst(rst),
    .mmio_wr_en(mmio_wr_en),
    .mmio_rd_en(mmio_rd_en),
    .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata),
    .mmio_rdata(mmio_rdata)
  );

  task mmio_write;
    input [7:0] a;
    input [31:0] d;
    begin
      mmio_addr  = a;
      mmio_wdata = d;
      mmio_wr_en = 1'b1;
      tick();
      mmio_wr_en = 1'b0;
    end
  endtask

  task mmio_read;
    input  [7:0] a;
    output [31:0] d;
    begin
      mmio_addr  = a;
      mmio_rd_en = 1'b1;
      tick();
      #1 d = mmio_rdata;
      mmio_rd_en = 1'b0;
      mmio_addr  = 8'h00;
    end
  endtask

  task imem_write_hier;
    input integer addr;
    input [31:0] instr;
    begin
      dut.u_if.u_imem.mem[addr] = instr;
    end
  endtask

  task dmem_write_lane;
    input integer lane;
    input integer addr;
    input [63:0] data;
    begin
      case (lane)
        0: dut.u_mm.u_dmem0.mem[addr] = data;
        1: dut.u_mm.u_dmem1.mem[addr] = data;
        2: dut.u_mm.u_dmem2.mem[addr] = data;
        default: dut.u_mm.u_dmem3.mem[addr] = data;
      endcase
    end
  endtask

  function [63:0] dmem_read_lane;
    input integer lane;
    input integer addr;
    begin
      case (lane)
        0: dmem_read_lane = dut.u_mm.u_dmem0.mem[addr];
        1: dmem_read_lane = dut.u_mm.u_dmem1.mem[addr];
        2: dmem_read_lane = dut.u_mm.u_dmem2.mem[addr];
        default: dmem_read_lane = dut.u_mm.u_dmem3.mem[addr];
      endcase
    end
  endfunction

  integer i,j,k;
  integer a[0:3][0:3];
  integer b[0:3][0:3];
  integer cexp[0:3][0:3];

  reg [63:0] exp_row[0:3];
  reg [63:0] got_row;
  reg [31:0] st;

  task build_mats;
    begin
      a[0][0]=1; a[0][1]=2; a[0][2]=3; a[0][3]=1;
      a[1][0]=0; a[1][1]=1; a[1][2]=2; a[1][3]=3;
      a[2][0]=2; a[2][1]=1; a[2][2]=0; a[2][3]=1;
      a[3][0]=3; a[3][1]=0; a[3][2]=1; a[3][3]=2;

      b[0][0]=1; b[0][1]=0; b[0][2]=2; b[0][3]=1;
      b[1][0]=3; b[1][1]=1; b[1][2]=0; b[1][3]=2;
      b[2][0]=1; b[2][1]=2; b[2][2]=1; b[2][3]=0;
      b[3][0]=0; b[3][1]=1; b[3][2]=3; b[3][3]=1;

      for (i=0;i<4;i=i+1) begin
        for (j=0;j<4;j=j+1) begin
          cexp[i][j]=0;
          for (k=0;k<4;k=k+1) begin
            cexp[i][j] = cexp[i][j] + a[i][k]*b[k][j];
          end
        end
      end

      exp_row[0] = pack16(cexp[0][0][15:0], cexp[0][1][15:0], cexp[0][2][15:0], cexp[0][3][15:0]);
      exp_row[1] = pack16(cexp[1][0][15:0], cexp[1][1][15:0], cexp[1][2][15:0], cexp[1][3][15:0]);
      exp_row[2] = pack16(cexp[2][0][15:0], cexp[2][1][15:0], cexp[2][2][15:0], cexp[2][3][15:0]);
      exp_row[3] = pack16(cexp[3][0][15:0], cexp[3][1][15:0], cexp[3][2][15:0], cexp[3][3][15:0]);
    end
  endtask

  task init_dmem_for_matmul;
    reg [63:0] brow;
    reg [63:0] arep;
    integer lane;
    integer kk;
    begin
      for (lane=0; lane<4; lane=lane+1) begin
        for (kk=0; kk<4; kk=kk+1) begin
          arep = pack16(a[lane][kk][15:0], a[lane][kk][15:0], a[lane][kk][15:0], a[lane][kk][15:0]);
          dmem_write_lane(lane, BASE_A + lane + 4*kk, arep);

          brow = pack16(b[kk][0][15:0], b[kk][1][15:0], b[kk][2][15:0], b[kk][3][15:0]);
          dmem_write_lane(lane, BASE_B + lane + 4*kk, brow);
        end
        dmem_write_lane(lane, BASE_C + lane, 64'd0);
      end
    end
  endtask

  task load_imem_program;
    integer pc;
    begin
      pc = 0;
      imem_write_hier(pc, enc(OP_LOADI, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_LOAD, 3'd1, 3'd0, 3'd0, BSEL_A, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_LOAD, 3'd2, 3'd0, 3'd0, BSEL_B, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_TENSOR_MAC, 3'd0, 3'd1, 3'd2, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_LOAD, 3'd1, 3'd0, 3'd0, BSEL_A, 1'b0, 16'd4)); pc=pc+1;
      imem_write_hier(pc, enc(OP_LOAD, 3'd2, 3'd0, 3'd0, BSEL_B, 1'b0, 16'd4)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_TENSOR_MAC, 3'd0, 3'd1, 3'd2, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_LOAD, 3'd1, 3'd0, 3'd0, BSEL_A, 1'b0, 16'd8)); pc=pc+1;
      imem_write_hier(pc, enc(OP_LOAD, 3'd2, 3'd0, 3'd0, BSEL_B, 1'b0, 16'd8)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_TENSOR_MAC, 3'd0, 3'd1, 3'd2, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_LOAD, 3'd1, 3'd0, 3'd0, BSEL_A, 1'b0, 16'd12)); pc=pc+1;
      imem_write_hier(pc, enc(OP_LOAD, 3'd2, 3'd0, 3'd0, BSEL_B, 1'b0, 16'd12)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_TENSOR_MAC, 3'd0, 3'd1, 3'd2, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_STORE, 3'd0, 3'd0, 3'd0, BSEL_C, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
      imem_write_hier(pc, enc(OP_NOP,  3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;

      imem_write_hier(pc, enc(OP_HALT, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0)); pc=pc+1;
    end
  endtask

  task wait_done_mmio;
    integer t;
    begin
      for (t=0; t<4000; t=t+1) begin
        mmio_read(REG_STATUS, st);
        if (st[1]) begin
          $display("INFO [done_seen] cycle=%0d status=%h", cycle, st);
          t = 4000;
        end else begin
          tick();
        end
      end
      mmio_read(REG_STATUS, st);
      if (!st[1]) begin
        $display("FAIL [wait_done] timeout cycle=%0d status=%h", cycle, st);
        $finish;
      end
    end
  endtask

  task test_gpu_top_matmul_4x4;
    begin
      $display("=== test_gpu_top_matmul_4x4 ===");

      build_mats();
      init_dmem_for_matmul();
      load_imem_program();

      mmio_write(REG_ENTRY_PC, 32'd0);
      mmio_write(REG_TID_INIT, 32'd0);
      mmio_write(REG_WORK_SIZE, 32'd4);

      mmio_write(REG_BASE_A_LO, BASE_A);
      mmio_write(REG_BASE_A_HI, 32'd0);

      mmio_write(REG_BASE_B_LO, BASE_B);
      mmio_write(REG_BASE_B_HI, 32'd0);

      mmio_write(REG_BASE_C_LO, BASE_C);
      mmio_write(REG_BASE_C_HI, 32'd0);

      mmio_write(REG_BASE_D_LO, 32'd0);
      mmio_write(REG_BASE_D_HI, 32'd0);

      mmio_write(REG_M, 32'd4);
      mmio_write(REG_N, 32'd4);
      mmio_write(REG_K, 32'd4);

      mmio_write(REG_CONTROL, 32'h1);

      wait_done_mmio();

      mmio_read(REG_STATUS, st);
      `CHECK_FALSE("status_busy_cleared", st[0]);
      `CHECK_TRUE("status_done_set", st[1]);
      `CHECK_FALSE("status_error_clear", st[2]);

      got_row = dmem_read_lane(0, BASE_C + 0);
      `CHECK_EQ_HEX("C_row0", got_row, exp_row[0]);

      got_row = dmem_read_lane(1, BASE_C + 1);
      `CHECK_EQ_HEX("C_row1", got_row, exp_row[1]);

      got_row = dmem_read_lane(2, BASE_C + 2);
      `CHECK_EQ_HEX("C_row2", got_row, exp_row[2]);

      got_row = dmem_read_lane(3, BASE_C + 3);
      `CHECK_EQ_HEX("C_row3", got_row, exp_row[3]);

      $display("ALL PASS test_gpu_top_matmul_4x4");
    end
  endtask

  initial begin
    cycle = 0;
    clk = 0;

    rst = 1'b1;
    mmio_wr_en = 0;
    mmio_rd_en = 0;
    mmio_addr  = 0;
    mmio_wdata = 0;

    tick();
    tick();
    rst = 1'b0;
    tick();

    test_gpu_top_matmul_4x4();

    $display("=== E2E MATMUL TEST PASS ===");
    $finish;
  end

endmodule