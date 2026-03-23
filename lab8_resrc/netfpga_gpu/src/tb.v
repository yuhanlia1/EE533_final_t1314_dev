`timescale 1ns/1ps

module tb_gpu_ptx;

  reg clk;
  reg rst;

  reg        mmio_wr_en;
  reg        mmio_rd_en;
  reg [7:0]  mmio_addr;
  reg [31:0] mmio_wdata;
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

  localparam [7:0] REG_CONTROL    = 8'h00;
  localparam [7:0] REG_STATUS     = 8'h04;
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
  localparam [7:0] REG_ERROR_CODE = 8'h4C;

  localparam [31:0] BASE_A = 32'd0;
  localparam [31:0] BASE_B = 32'd64;
  localparam [31:0] BASE_C = 32'd128;
  localparam [31:0] BASE_D = 32'd192;

  localparam [8:0] ENTRY_ADD  = 9'd0;
  localparam [8:0] ENTRY_SUB  = 9'd16;
  localparam [8:0] ENTRY_RELU = 9'd32;
  localparam [8:0] ENTRY_MUL  = 9'd48;
  localparam [8:0] ENTRY_FMA  = 9'd64;

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
  localparam [15:0] BF16_15  = 16'h4170;
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

  reg [63:0] expected [0:31];
  integer fail_count;
  integer pass_count;
  integer cycle_count;
  integer i;

  function [63:0] pack4;
    input [15:0] x0;
    input [15:0] x1;
    input [15:0] x2;
    input [15:0] x3;
    begin
      pack4 = {x3, x2, x1, x0};
    end
  endfunction

  function [63:0] dmem_read_global;
    input integer base;
    input integer idx;
    begin
      case (idx % 4)
        0: dmem_read_global = dut.u_mm.u_dmem0.mem[base + idx];
        1: dmem_read_global = dut.u_mm.u_dmem1.mem[base + idx];
        2: dmem_read_global = dut.u_mm.u_dmem2.mem[base + idx];
        default: dmem_read_global = dut.u_mm.u_dmem3.mem[base + idx];
      endcase
    end
  endfunction

  task dmem_write_global;
    input integer base;
    input integer idx;
    input [63:0] data;
    begin
      case (idx % 4)
        0: dut.u_mm.u_dmem0.mem[base + idx] = data;
        1: dut.u_mm.u_dmem1.mem[base + idx] = data;
        2: dut.u_mm.u_dmem2.mem[base + idx] = data;
        3: dut.u_mm.u_dmem3.mem[base + idx] = data;
      endcase
    end
  endtask

  task mmio_write;
    input [7:0] addr;
    input [31:0] data;
    begin
      @(negedge clk);
      mmio_addr  <= addr;
      mmio_wdata <= data;
      mmio_wr_en <= 1'b1;
      mmio_rd_en <= 1'b0;
      @(negedge clk);
      mmio_wr_en <= 1'b0;
      mmio_addr  <= 8'h00;
      mmio_wdata <= 32'h0;
    end
  endtask

  task mmio_read;
    input [7:0] addr;
    output [31:0] data;
    begin
      @(negedge clk);
      mmio_addr  <= addr;
      mmio_rd_en <= 1'b1;
      mmio_wr_en <= 1'b0;
      @(negedge clk);
      #1 data = mmio_rdata;
      mmio_rd_en <= 1'b0;
      mmio_addr  <= 8'h00;
    end
  endtask

  task clear_imem;
    integer j;
    begin
      for (j = 0; j < 512; j = j + 1) begin
        dut.u_if.u_imem.mem[j] = 32'h00000013;
      end
    end
  endtask

  task load_programs;
    begin
      dut.u_if.u_imem.mem[0]  = 32'hA0000002;
      dut.u_if.u_imem.mem[1]  = 32'hF0000000;
      dut.u_if.u_imem.mem[2]  = 32'h20000000;
      dut.u_if.u_imem.mem[3]  = 32'h22020000;
      dut.u_if.u_imem.mem[4]  = 32'h00000013;
      dut.u_if.u_imem.mem[5]  = 32'h00000013;
      dut.u_if.u_imem.mem[6]  = 32'h44080000;
      dut.u_if.u_imem.mem[7]  = 32'h00000013;
      dut.u_if.u_imem.mem[8]  = 32'h00000013;
      dut.u_if.u_imem.mem[9]  = 32'h30140000;
      dut.u_if.u_imem.mem[10] = 32'h90000000;
      dut.u_if.u_imem.mem[11] = 32'hE0000000;

      dut.u_if.u_imem.mem[16] = 32'hA0000012;
      dut.u_if.u_imem.mem[17] = 32'hF0000000;
      dut.u_if.u_imem.mem[18] = 32'h20000000;
      dut.u_if.u_imem.mem[19] = 32'h22020000;
      dut.u_if.u_imem.mem[20] = 32'h00000013;
      dut.u_if.u_imem.mem[21] = 32'h00000013;
      dut.u_if.u_imem.mem[22] = 32'h54080000;
      dut.u_if.u_imem.mem[23] = 32'h00000013;
      dut.u_if.u_imem.mem[24] = 32'h00000013;
      dut.u_if.u_imem.mem[25] = 32'h30140000;
      dut.u_if.u_imem.mem[26] = 32'h90000000;
      dut.u_if.u_imem.mem[27] = 32'hE0000010;

      dut.u_if.u_imem.mem[32] = 32'hA0000022;
      dut.u_if.u_imem.mem[33] = 32'hF0000000;
      dut.u_if.u_imem.mem[34] = 32'h20000000;
      dut.u_if.u_imem.mem[35] = 32'h00000013;
      dut.u_if.u_imem.mem[36] = 32'h00000013;
      dut.u_if.u_imem.mem[37] = 32'h72000000;
      dut.u_if.u_imem.mem[38] = 32'h00000013;
      dut.u_if.u_imem.mem[39] = 32'h00000013;
      dut.u_if.u_imem.mem[40] = 32'h300A0000;
      dut.u_if.u_imem.mem[41] = 32'h90000000;
      dut.u_if.u_imem.mem[42] = 32'hE0000020;

      dut.u_if.u_imem.mem[48] = 32'hA0000032;
      dut.u_if.u_imem.mem[49] = 32'hF0000000;
      dut.u_if.u_imem.mem[50] = 32'h20000000;
      dut.u_if.u_imem.mem[51] = 32'h22020000;
      dut.u_if.u_imem.mem[52] = 32'h00000013;
      dut.u_if.u_imem.mem[53] = 32'h00000013;
      dut.u_if.u_imem.mem[54] = 32'h64090000;
      dut.u_if.u_imem.mem[55] = 32'h00000013;
      dut.u_if.u_imem.mem[56] = 32'h00000013;
      dut.u_if.u_imem.mem[57] = 32'h00000013;
      dut.u_if.u_imem.mem[58] = 32'h30140000;
      dut.u_if.u_imem.mem[59] = 32'h90000000;
      dut.u_if.u_imem.mem[60] = 32'hE0000030;

      dut.u_if.u_imem.mem[64] = 32'hA0000042;
      dut.u_if.u_imem.mem[65] = 32'hF0000000;
      dut.u_if.u_imem.mem[66] = 32'h20000000;
      dut.u_if.u_imem.mem[67] = 32'h22020000;
      dut.u_if.u_imem.mem[68] = 32'h24040000;
      dut.u_if.u_imem.mem[69] = 32'h00000013;
      dut.u_if.u_imem.mem[70] = 32'h00000013;
      dut.u_if.u_imem.mem[71] = 32'hC4090000;
      dut.u_if.u_imem.mem[72] = 32'h00000013;
      dut.u_if.u_imem.mem[73] = 32'h00000013;
      dut.u_if.u_imem.mem[74] = 32'h00000013;
      dut.u_if.u_imem.mem[75] = 32'h30160000;
      dut.u_if.u_imem.mem[76] = 32'h90000000;
      dut.u_if.u_imem.mem[77] = 32'hE0000040;
    end
  endtask

  task clear_dmems;
    integer j;
    begin
      for (j = 0; j < 1024; j = j + 1) begin
        dut.u_mm.u_dmem0.mem[j] = 64'd0;
        dut.u_mm.u_dmem1.mem[j] = 64'd0;
        dut.u_mm.u_dmem2.mem[j] = 64'd0;
        dut.u_mm.u_dmem3.mem[j] = 64'd0;
      end
      dut.u_mm.u_dmem0.rdata = 64'd0;
      dut.u_mm.u_dmem1.rdata = 64'd0;
      dut.u_mm.u_dmem2.rdata = 64'd0;
      dut.u_mm.u_dmem3.rdata = 64'd0;
    end
  endtask

  task clear_expected;
    integer j;
    begin
      for (j = 0; j < 32; j = j + 1) begin
        expected[j] = 64'd0;
      end
    end
  endtask

  task fill_output_sentinel;
    input integer base;
    integer j;
    begin
      for (j = 0; j < 8; j = j + 1) begin
        dmem_write_global(base, j, SENTINEL);
      end
    end
  endtask

  task setup_add_case;
    begin
      clear_dmems;
      clear_expected;
      fill_output_sentinel(BASE_C);

      dmem_write_global(BASE_A, 0, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      dmem_write_global(BASE_B, 0, pack4(16'd10,   16'd20,   16'd30,   16'd40));
      expected[0] =                pack4(16'd11,   16'd22,   16'd33,   16'd44);

      dmem_write_global(BASE_A, 1, pack4(16'd100,  16'd200,  16'd300,  16'd400));
      dmem_write_global(BASE_B, 1, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[1] =                pack4(16'd101,  16'd202,  16'd303,  16'd404);

      dmem_write_global(BASE_A, 2, pack4(16'hFFFF, 16'hFFFE, 16'd5,    16'd6));
      dmem_write_global(BASE_B, 2, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[2] =                pack4(16'd0,    16'd0,    16'd8,    16'd10);

      dmem_write_global(BASE_A, 3, pack4(16'd7,    16'd8,    16'd9,    16'd10));
      dmem_write_global(BASE_B, 3, pack4(16'd11,   16'd12,   16'd13,   16'd14));
      expected[3] =                pack4(16'd18,   16'd20,   16'd22,   16'd24);

      dmem_write_global(BASE_A, 4, pack4(16'd1000, 16'd2000, 16'd3000, 16'd4000));
      dmem_write_global(BASE_B, 4, pack4(16'd5,    16'd6,    16'd7,    16'd8));
      expected[4] =                pack4(16'd1005, 16'd2006, 16'd3007, 16'd4008);

      dmem_write_global(BASE_A, 5, pack4(16'h8000, 16'd1,    16'd2,    16'd3));
      dmem_write_global(BASE_B, 5, pack4(16'd1,    16'd1,    16'd1,    16'd1));
      expected[5] =                pack4(16'h8001, 16'd2,    16'd3,    16'd4);

      dmem_write_global(BASE_A, 6, pack4(16'd15,   16'd25,   16'd35,   16'd45));
      dmem_write_global(BASE_B, 6, pack4(16'd5,    16'd5,    16'd5,    16'd5));
      expected[6] =                pack4(16'd20,   16'd30,   16'd40,   16'd50);
    end
  endtask

  task setup_sub_case;
    begin
      clear_dmems;
      clear_expected;
      fill_output_sentinel(BASE_C);

      dmem_write_global(BASE_A, 0, pack4(16'd10,   16'd20,   16'd30,   16'd40));
      dmem_write_global(BASE_B, 0, pack4(16'd1,    16'd2,    16'd3,    16'd4));
      expected[0] =                pack4(16'd9,    16'd18,   16'd27,   16'd36);

      dmem_write_global(BASE_A, 1, pack4(16'd100,  16'd50,   16'd0,    16'hFFFF));
      dmem_write_global(BASE_B, 1, pack4(16'd5,    16'd10,   16'd1,    16'd1));
      expected[1] =                pack4(16'd95,   16'd40,   16'hFFFF, 16'hFFFE);

      dmem_write_global(BASE_A, 2, pack4(16'd0,    16'd1,    16'd2,    16'd3));
      dmem_write_global(BASE_B, 2, pack4(16'd10,   16'd9,    16'd8,    16'd7));
      expected[2] =                pack4(16'hFFF6, 16'hFFF8, 16'hFFFA, 16'hFFFC);

      dmem_write_global(BASE_A, 3, pack4(16'd300,  16'd400,  16'd500,  16'd600));
      dmem_write_global(BASE_B, 3, pack4(16'd100,  16'd50,   16'd25,   16'd10));
      expected[3] =                pack4(16'd200,  16'd350,  16'd475,  16'd590);

      dmem_write_global(BASE_A, 4, pack4(16'h8000, 16'h7FFF, 16'd1,    16'd2));
      dmem_write_global(BASE_B, 4, pack4(16'd1,    16'd1,    16'd1,    16'd1));
      expected[4] =                pack4(16'h7FFF, 16'h7FFE, 16'd0,    16'd1);

      dmem_write_global(BASE_A, 5, pack4(16'd9,    16'd8,    16'd7,    16'd6));
      dmem_write_global(BASE_B, 5, pack4(16'd6,    16'd7,    16'd8,    16'd9));
      expected[5] =                pack4(16'd3,    16'd1,    16'hFFFF, 16'hFFFD);

      dmem_write_global(BASE_A, 6, pack4(16'd123,  16'd234,  16'd345,  16'd456));
      dmem_write_global(BASE_B, 6, pack4(16'd23,   16'd34,   16'd45,   16'd56));
      expected[6] =                pack4(16'd100,  16'd200,  16'd300,  16'd400);
    end
  endtask

  task setup_relu_case;
    begin
      clear_dmems;
      clear_expected;
      fill_output_sentinel(BASE_B);

      dmem_write_global(BASE_A, 0, pack4(16'hFFFF, 16'd1,    16'hFFFE, 16'd2));
      expected[0] =                pack4(16'd0,    16'd1,    16'd0,    16'd2);

      dmem_write_global(BASE_A, 1, pack4(16'h8000, 16'h7FFF, 16'd0,    16'hFFFF));
      expected[1] =                pack4(16'd0,    16'h7FFF, 16'd0,    16'd0);

      dmem_write_global(BASE_A, 2, pack4(16'd5,    16'd6,    16'd7,    16'd8));
      expected[2] =                pack4(16'd5,    16'd6,    16'd7,    16'd8);

      dmem_write_global(BASE_A, 3, pack4(16'hFFF0, 16'hFFF1, 16'hFFF2, 16'hFFF3));
      expected[3] =                pack4(16'd0,    16'd0,    16'd0,    16'd0);

      dmem_write_global(BASE_A, 4, pack4(16'd100,  16'd0,    16'hFF9C, 16'd50));
      expected[4] =                pack4(16'd100,  16'd0,    16'd0,    16'd50);

      dmem_write_global(BASE_A, 5, pack4(16'd1,    16'h8001, 16'd2,    16'h8002));
      expected[5] =                pack4(16'd1,    16'd0,    16'd2,    16'd0);

      dmem_write_global(BASE_A, 6, pack4(16'd300,  16'd400,  16'd500,  16'd600));
      expected[6] =                pack4(16'd300,  16'd400,  16'd500,  16'd600);
    end
  endtask

  task setup_mul_case;
    begin
      clear_dmems;
      clear_expected;
      fill_output_sentinel(BASE_C);

      dmem_write_global(BASE_A, 0, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      dmem_write_global(BASE_B, 0, pack4(BF16_5,   BF16_6,   BF16_7,   BF16_8));
      expected[0] =                pack4(BF16_5,   BF16_12,  BF16_21,  BF16_32);

      dmem_write_global(BASE_A, 1, pack4(BF16_2,   BF16_2,   BF16_2,   BF16_2));
      dmem_write_global(BASE_B, 1, pack4(BF16_2,   BF16_3,   BF16_4,   BF16_5));
      expected[1] =                pack4(BF16_4,   BF16_6,   BF16_8,   BF16_10);

      dmem_write_global(BASE_A, 2, pack4(BF16_0P5, BF16_1,   BF16_2,   BF16_4));
      dmem_write_global(BASE_B, 2, pack4(BF16_8,   BF16_4,   BF16_2,   BF16_1));
      expected[2] =                pack4(BF16_4,   BF16_4,   BF16_4,   BF16_4);

      dmem_write_global(BASE_A, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      dmem_write_global(BASE_B, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      expected[3] =                pack4(BF16_9,   BF16_16,  BF16_25,  BF16_36);

      dmem_write_global(BASE_A, 4, pack4(BF16_1,   BF16_0P5, BF16_7,   BF16_8));
      dmem_write_global(BASE_B, 4, pack4(BF16_0P5, BF16_8,   BF16_1,   BF16_0P5));
      expected[4] =                pack4(BF16_0P5, BF16_4,   BF16_7,   BF16_4);

      dmem_write_global(BASE_A, 5, pack4(BF16_10,  BF16_11,  BF16_12,  BF16_13));
      dmem_write_global(BASE_B, 5, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[5] =                pack4(BF16_10,  BF16_11,  BF16_12,  BF16_13);

      dmem_write_global(BASE_A, 6, pack4(BF16_4,   BF16_3,   BF16_2,   BF16_1));
      dmem_write_global(BASE_B, 6, pack4(BF16_4,   BF16_3,   BF16_2,   BF16_1));
      expected[6] =                pack4(BF16_16,  BF16_9,   BF16_4,   BF16_1);
    end
  endtask

  task setup_fma_case;
    begin
      clear_dmems;
      clear_expected;
      fill_output_sentinel(BASE_D);

      dmem_write_global(BASE_A, 0, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      dmem_write_global(BASE_B, 0, pack4(BF16_5,   BF16_6,   BF16_7,   BF16_8));
      dmem_write_global(BASE_C, 0, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[0] =                pack4(BF16_6,   BF16_13,  BF16_22,  BF16_33);

      dmem_write_global(BASE_A, 1, pack4(BF16_2,   BF16_2,   BF16_2,   BF16_2));
      dmem_write_global(BASE_B, 1, pack4(BF16_2,   BF16_3,   BF16_4,   BF16_5));
      dmem_write_global(BASE_C, 1, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[1] =                pack4(BF16_5,   BF16_8,   BF16_11,  BF16_14);

      dmem_write_global(BASE_A, 2, pack4(BF16_0P5, BF16_1,   BF16_2,   BF16_4));
      dmem_write_global(BASE_B, 2, pack4(BF16_8,   BF16_4,   BF16_2,   BF16_1));
      dmem_write_global(BASE_C, 2, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[2] =                pack4(BF16_5,   BF16_5,   BF16_5,   BF16_5);

      dmem_write_global(BASE_A, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      dmem_write_global(BASE_B, 3, pack4(BF16_3,   BF16_4,   BF16_5,   BF16_6));
      dmem_write_global(BASE_C, 3, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[3] =                pack4(BF16_10,  BF16_18,  BF16_28,  BF16_40);

      dmem_write_global(BASE_A, 4, pack4(BF16_1,   BF16_0P5, BF16_7,   BF16_8));
      dmem_write_global(BASE_B, 4, pack4(BF16_0P5, BF16_8,   BF16_1,   BF16_0P5));
      dmem_write_global(BASE_C, 4, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[4] =                pack4(16'h3FC0, BF16_6,   BF16_10,  BF16_8);

      dmem_write_global(BASE_A, 5, pack4(BF16_10,  BF16_11,  BF16_12,  BF16_13));
      dmem_write_global(BASE_B, 5, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      dmem_write_global(BASE_C, 5, pack4(BF16_1,   BF16_2,   BF16_3,   BF16_4));
      expected[5] =                pack4(BF16_11,  BF16_13,  BF16_15,  BF16_17);

      dmem_write_global(BASE_A, 6, pack4(BF16_4,   BF16_3,   BF16_2,   BF16_1));
      dmem_write_global(BASE_B, 6, pack4(BF16_4,   BF16_3,   BF16_2,   BF16_1));
      dmem_write_global(BASE_C, 6, pack4(BF16_1,   BF16_1,   BF16_1,   BF16_1));
      expected[6] =                pack4(BF16_17,  BF16_10,  BF16_5,   BF16_2);
    end
  endtask

  task run_kernel;
    input [8:0]  entry_pc;
    input [31:0] work_size;
    input [31:0] base_a;
    input [31:0] base_b;
    input [31:0] base_c;
    input [31:0] base_d;
    begin
      mmio_write(REG_CONTROL, 32'h00000004);
      mmio_write(REG_ENTRY_PC, {23'd0, entry_pc});
      mmio_write(REG_TID_INIT, 32'd0);
      mmio_write(REG_WORK_SIZE, work_size);

      mmio_write(REG_BASE_A_LO, base_a);
      mmio_write(REG_BASE_A_HI, 32'd0);
      mmio_write(REG_BASE_B_LO, base_b);
      mmio_write(REG_BASE_B_HI, 32'd0);
      mmio_write(REG_BASE_C_LO, base_c);
      mmio_write(REG_BASE_C_HI, 32'd0);
      mmio_write(REG_BASE_D_LO, base_d);
      mmio_write(REG_BASE_D_HI, 32'd0);

      mmio_write(REG_M, 32'd0);
      mmio_write(REG_N, 32'd0);
      mmio_write(REG_K, 32'd0);

      mmio_write(REG_CONTROL, 32'h00000001);
    end
  endtask

  task wait_done;
    input integer max_poll;
    integer poll;
    reg [31:0] stat;
    reg [31:0] errc;
    reg found;
    begin
      poll = 0;
      found = 0;
      while ((poll < max_poll) && !found) begin
        mmio_read(REG_STATUS, stat);
        $display("[poll %0d] STATUS=%08h busy=%0d done=%0d error=%0d pc_if=%0d pc_id=%0d tid_base=%0d",
                 poll, stat, stat[0], stat[1], stat[2], dut.pc_if, dut.pc_id, dut.u_id.tid_base);
        if (stat[2]) begin
          mmio_read(REG_ERROR_CODE, errc);
          $display("GPU ERROR error_code=%08h", errc);
          fail_count = fail_count + 1;
          $finish;
        end
        if (stat[1]) begin
          found = 1'b1;
        end else begin
          poll = poll + 1;
        end
      end
      if (!found) begin
        $display("TIMEOUT waiting for done");
        fail_count = fail_count + 1;
        $finish;
      end
    end
  endtask

  task verify_output;
    input [127:0] name;
    input integer base;
    input integer n;
    integer j;
    reg [63:0] got;
    reg local_fail;
    begin
      local_fail = 0;
      $display("---- VERIFY %0s ----", name);
      for (j = 0; j < n; j = j + 1) begin
        got = dmem_read_global(base, j);
        $display("%0s idx=%0d got=%h {%h %h %h %h} exp=%h {%h %h %h %h}",
                 name, j,
                 got, got[63:48], got[47:32], got[31:16], got[15:0],
                 expected[j], expected[j][63:48], expected[j][47:32], expected[j][31:16], expected[j][15:0]);
        if (got !== expected[j]) begin
          local_fail = 1;
        end
      end

      got = dmem_read_global(base, n);
      $display("%0s idx=%0d sentinel_check got=%h exp=%h", name, n, got, SENTINEL);
      if (got !== SENTINEL) begin
        local_fail = 1;
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

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (!rst) begin
      if (dut.run_en || dut.start_pulse || dut.jump_valid || dut.stall_ex || dut.id_valid || dut.mm_in_valid || dut.wb_in_valid || dut.done) begin
        $display("[cycle %0d] busy=%0d done=%0d pc_if=%0d instr_if=%08h pc_id=%0d instr_id=%08h tid_base=%0d lane_mask=%b jump=%0d jump_addr=%0d stall=%0d",
                 cycle_count,
                 dut.busy,
                 dut.done,
                 dut.pc_if,
                 dut.instr_if,
                 dut.pc_id,
                 dut.instr_id,
                 dut.u_id.tid_base,
                 dut.id_lane_mask,
                 dut.jump_valid,
                 dut.jump_addr,
                 dut.stall_ex);
      end

      if (dut.mm_in_valid && dut.mm_in_ctrl[0]) begin
        $display("  LOAD  a0=%0d a1=%0d a2=%0d a3=%0d mask=%b",
                 dut.mm_addr0, dut.mm_addr1, dut.mm_addr2, dut.mm_addr3, dut.mm_in_lane_mask);
      end

      if (dut.mm_in_valid && dut.mm_in_ctrl[1]) begin
        $display("  STORE a0=%0d d0=%h | a1=%0d d1=%h | a2=%0d d2=%h | a3=%0d d3=%h mask=%b",
                 dut.mm_addr0, dut.mm_store0,
                 dut.mm_addr1, dut.mm_store1,
                 dut.mm_addr2, dut.mm_store2,
                 dut.mm_addr3, dut.mm_store3,
                 dut.mm_in_lane_mask);
      end

      if (dut.wb_we0) $display("  WB lane0 rd=%0d data=%h", dut.wb_rd, dut.wb_wdata0);
      if (dut.wb_we1) $display("  WB lane1 rd=%0d data=%h", dut.wb_rd, dut.wb_wdata1);
      if (dut.wb_we2) $display("  WB lane2 rd=%0d data=%h", dut.wb_rd, dut.wb_wdata2);
      if (dut.wb_we3) $display("  WB lane3 rd=%0d data=%h", dut.wb_rd, dut.wb_wdata3);
    end
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    mmio_wr_en = 1'b0;
    mmio_rd_en = 1'b0;
    mmio_addr = 8'h00;
    mmio_wdata = 32'h0;
    fail_count = 0;
    pass_count = 0;
    cycle_count = 0;

    $dumpfile("tb_gpu_ptx.vcd");
    $dumpvars(0, tb_gpu_ptx);

    #1;
    clear_imem;
    load_programs;
    clear_dmems;
    clear_expected;

    $display("IMEM sanity: mem[0]=%08h mem[1]=%08h mem[16]=%08h mem[48]=%08h mem[64]=%08h",
             dut.u_if.u_imem.mem[0],
             dut.u_if.u_imem.mem[1],
             dut.u_if.u_imem.mem[16],
             dut.u_if.u_imem.mem[48],
             dut.u_if.u_imem.mem[64]);

    repeat (6) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    $display("");
    $display("========== TEST vec_add_i16x4 ==========");
    setup_add_case;
    run_kernel(ENTRY_ADD, 32'd7, BASE_A, BASE_B, BASE_C, 32'd0);
    wait_done(400);
    verify_output("vec_add_i16x4", BASE_C, 7);

    $display("");
    $display("========== TEST vec_sub_i16x4 ==========");
    setup_sub_case;
    run_kernel(ENTRY_SUB, 32'd7, BASE_A, BASE_B, BASE_C, 32'd0);
    wait_done(400);
    verify_output("vec_sub_i16x4", BASE_C, 7);

    $display("");
    $display("========== TEST relu_i16x4 ==========");
    setup_relu_case;
    run_kernel(ENTRY_RELU, 32'd7, BASE_A, BASE_B, 32'd0, 32'd0);
    wait_done(400);
    verify_output("relu_i16x4", BASE_B, 7);

    $display("");
    $display("========== TEST vec_mul_bf16x4 ==========");
    setup_mul_case;
    run_kernel(ENTRY_MUL, 32'd7, BASE_A, BASE_B, BASE_C, 32'd0);
    wait_done(2000);
    verify_output("vec_mul_bf16x4", BASE_C, 7);

    $display("");
    $display("========== TEST fma_bf16x4 ==========");
    setup_fma_case;
    run_kernel(ENTRY_FMA, 32'd7, BASE_A, BASE_B, BASE_C, BASE_D);
    wait_done(3000);
    verify_output("fma_bf16x4", BASE_D, 7);

    $display("");
    $display("========== SUMMARY ==========");
    $display("PASS = %0d", pass_count);
    $display("FAIL = %0d", fail_count);

    if (fail_count == 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("SOME TESTS FAILED");
    end

    #50;
    $finish;
  end

endmodule