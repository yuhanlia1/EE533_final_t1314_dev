`timescale 1ns / 1ps

module final_nn_gpu_bridge #(
  parameter MMIO_ADDR_W = 8,
  parameter IMEM_AW     = 9,
  parameter MEM_AW      = 8
) (
  input  wire                   clk,
  input  wire                   reset,
  input  wire                   gpu_start_pulse,
  input  wire                   gpu_mmio_wr_en,
  input  wire                   gpu_mmio_rd_en,
  input  wire [MMIO_ADDR_W-1:0] gpu_mmio_addr,
  input  wire [31:0]            gpu_mmio_wdata,
  output wire [31:0]            gpu_mmio_rdata,
  input  wire                   imem_prog_we,
  input  wire [IMEM_AW-1:0]     imem_prog_addr,
  input  wire [31:0]            imem_prog_wdata,
  output wire                   gpu_done,
  output wire                   gpu_busy,
  output wire [15:0]            dbg_gpu_pc,
  output wire                   mem0_en,
  output wire                   mem0_we,
  output wire [MEM_AW-1:0]      mem0_addr,
  output wire [63:0]            mem0_wdata,
  input  wire [63:0]            mem0_rdata,
  input  wire                   mem0_rvalid,
  output wire                   mem1_en,
  output wire                   mem1_we,
  output wire [MEM_AW-1:0]      mem1_addr,
  output wire [63:0]            mem1_wdata,
  input  wire [63:0]            mem1_rdata,
  input  wire                   mem1_rvalid
);

  localparam [MMIO_ADDR_W-1:0] REG_CONTROL = 8'h00;
  localparam [31:0] CTRL_START = 32'h0000_0001;

  wire                   mmio_wr_en_mux;
  wire                   mmio_rd_en_mux;
  wire [MMIO_ADDR_W-1:0] mmio_addr_mux;
  wire [31:0]            mmio_wdata_mux;

  assign mmio_wr_en_mux = gpu_start_pulse ? 1'b1        : gpu_mmio_wr_en;
  assign mmio_rd_en_mux = gpu_start_pulse ? 1'b0        : gpu_mmio_rd_en;
  assign mmio_addr_mux  = gpu_start_pulse ? REG_CONTROL : gpu_mmio_addr;
  assign mmio_wdata_mux = gpu_start_pulse ? CTRL_START  : gpu_mmio_wdata;

  gpu_top_fifo_if #(
    .MMIO_ADDR_W(MMIO_ADDR_W),
    .PC_W       (IMEM_AW),
    .IMEM_PROG_ADDR_W(IMEM_AW),
    .IMEM_ADDR_W(IMEM_AW),
    .IMEM_DEPTH (1 << IMEM_AW),
    .MEM_AW     (MEM_AW)
  ) u_gpu (
    .clk            (clk),
    .rst            (reset),
    .mmio_wr_en     (mmio_wr_en_mux),
    .mmio_rd_en     (mmio_rd_en_mux),
    .mmio_addr      (mmio_addr_mux),
    .mmio_wdata     (mmio_wdata_mux),
    .mmio_rdata     (gpu_mmio_rdata),
    .imem_prog_we   (imem_prog_we),
    .imem_prog_addr (imem_prog_addr),
    .imem_prog_wdata(imem_prog_wdata),
    .proc_active    (1'b1),
    .proc_done      (gpu_done),
    .mem0_en        (mem0_en),
    .mem0_we        (mem0_we),
    .mem0_addr      (mem0_addr),
    .mem0_wdata     (mem0_wdata),
    .mem0_rdata     (mem0_rdata),
    .mem0_rvalid    (mem0_rvalid),
    .mem1_en        (mem1_en),
    .mem1_we        (mem1_we),
    .mem1_addr      (mem1_addr),
    .mem1_wdata     (mem1_wdata),
    .mem1_rdata     (mem1_rdata),
    .mem1_rvalid    (mem1_rvalid),
    .dbg_pc         (dbg_gpu_pc),
    .busy           (gpu_busy)
  );
endmodule

module tb_communication_nn;

  localparam integer CPU_PROG_DEPTH = 512;
  localparam integer GPU_PROG_DEPTH = 512;
  localparam integer DMEM_DEPTH     = 256;

  localparam integer SAMPLE_COUNT = 2;
  localparam integer IN_DIM  = 8;
  localparam integer H1_DIM  = 6;
  localparam integer H2_DIM  = 4;
  localparam integer OUT_DIM = 2;

  localparam integer ACT_BASE_ADDR  = 16;
  localparam integer WGT_BASE_ADDR  = 64;
  localparam integer BIAS_BASE_ADDR = 224;
  localparam integer AUX_BASE_ADDR  = 248;

  localparam integer X_OFF   = 0;
  localparam integer H1_OFF  = 16;
  localparam integer H2_OFF  = 28;
  localparam integer Y_OFF   = 36;

  localparam integer W1_OFF  = 0;
  localparam integer W2_OFF  = 96;
  localparam integer W3_OFF  = 144;

  localparam integer B1_OFF  = 0;
  localparam integer B2_OFF  = 12;
  localparam integer B3_OFF  = 20;

  integer i;
  integer j;
  integer k;
  integer s;
  integer pc;
  integer acc;
  integer errors;
  integer timeout_cycles;
  integer gpu_start_count;
  reg     done_seen;

  reg         clk;
  reg         reset;
  reg  [63:0] nw_in_data;
  reg  [7:0]  nw_in_ctrl;
  reg         nw_in_wr;
  wire        nw_in_rdy;
  wire [63:0] nw_out_data;
  wire [7:0]  nw_out_ctrl;
  wire        nw_out_wr;
  reg         nw_out_rdy;

  reg  [31:0] sw_i_mem_addr;
  reg  [31:0] sw_i_mem_wdata;
  reg  [31:0] sw_d_mem_addr;

  // Decoupled CPU-GPU interface
  wire        cpu_done;
  wire        ext_continue;
  wire        ext_drop;
  wire        cpu_mmio_wr_en;
  wire        cpu_mmio_rd_en;
  wire [7:0]  cpu_mmio_addr;
  wire [31:0] cpu_mmio_wdata;
  wire [31:0] cpu_mmio_rdata;

  wire        gpu_done;
  wire        gpu_start;
  wire        gpu_mmio_wr_en;
  wire        gpu_mmio_rd_en;
  wire [7:0]  gpu_mmio_addr;
  wire [31:0] gpu_mmio_wdata;
  wire [31:0] gpu_mmio_rdata;

  reg         gpu_imem_prog_we;
  reg  [8:0]  gpu_imem_prog_addr;
  reg  [31:0] gpu_imem_prog_wdata;

  wire        gpu_mem0_en;
  wire        gpu_mem0_we;
  wire [7:0]  gpu_mem0_addr;
  wire [63:0] gpu_mem0_wdata;
  reg  [63:0] gpu_mem0_rdata;
  reg         gpu_mem0_rvalid;

  wire        gpu_mem1_en;
  wire        gpu_mem1_we;
  wire [7:0]  gpu_mem1_addr;
  wire [63:0] gpu_mem1_wdata;
  reg  [63:0] gpu_mem1_rdata;
  reg         gpu_mem1_rvalid;

  wire [15:0] dbg_gpu_pc;
  wire        dbg_gpu_busy;

  reg [31:0] cpu_program [0:CPU_PROG_DEPTH-1];
  reg [31:0] gpu_program [0:GPU_PROG_DEPTH-1];
  reg [63:0] dmem [0:DMEM_DEPTH-1];

  reg signed [15:0] input_data [0:(SAMPLE_COUNT*IN_DIM)-1];
  reg signed [15:0] w1_data    [0:(IN_DIM*H1_DIM)-1];
  reg signed [15:0] w2_data    [0:(H1_DIM*H2_DIM)-1];
  reg signed [15:0] w3_data    [0:(H2_DIM*OUT_DIM)-1];
  reg signed [15:0] b1_data    [0:H1_DIM-1];
  reg signed [15:0] b2_data    [0:H2_DIM-1];
  reg signed [15:0] b3_data    [0:OUT_DIM-1];

  reg [15:0] h1_expected [0:(SAMPLE_COUNT*H1_DIM)-1];
  reg [15:0] h2_expected [0:(SAMPLE_COUNT*H2_DIM)-1];
  reg [15:0] y_expected  [0:(SAMPLE_COUNT*OUT_DIM)-1];

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

  function [31:0] arm_nop;
    input dummy;
    begin
      arm_nop = 32'hE1A00000;
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

  task emit_fc_relu_layer(
    input integer in_off,
    input integer out_off,
    input integer weight_off,
    input integer bias_off,
    input integer in_dim,
    input integer out_dim,
    input integer do_relu
  );
    integer in_idx;
    integer out_idx;
    begin
      for (out_idx = 0; out_idx < out_dim; out_idx = out_idx + 1) begin
        gpu_program[pc] = gpu_instr(4'h1, 3'd6, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
        pc = pc + 1;

        for (in_idx = 0; in_idx < in_dim; in_idx = in_idx + 1) begin
          gpu_program[pc] = gpu_instr(4'h2, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, in_off + in_idx * SAMPLE_COUNT);
          pc = pc + 1;
          gpu_program[pc] = gpu_instr(4'h2, 3'd1, 3'd0, 3'd0, 2'b01, 1'b0,
                                      weight_off + (out_idx * in_dim + in_idx) * SAMPLE_COUNT);
          pc = pc + 1;
          gpu_program[pc] = gpu_instr(4'hC, 3'd6, 3'd0, 3'd1, 2'b00, 1'b0, 16'h0000);
          pc = pc + 1;
        end

        gpu_program[pc] = gpu_instr(4'h2, 3'd2, 3'd0, 3'd0, 2'b10, 1'b0, bias_off + out_idx * SAMPLE_COUNT);
        pc = pc + 1;
        gpu_program[pc] = gpu_instr(4'h4, 3'd6, 3'd6, 3'd2, 2'b00, 1'b0, 16'h0000);
        pc = pc + 1;

        if (do_relu != 0) begin
          gpu_program[pc] = gpu_instr(4'h7, 3'd6, 3'd6, 3'd0, 2'b00, 1'b0, 16'h0000);
          pc = pc + 1;
        end

        gpu_program[pc] = gpu_instr(4'h3, 3'd0, 3'd0, 3'd6, 2'b00, 1'b0, out_off + out_idx * SAMPLE_COUNT);
        pc = pc + 1;
      end
    end
  endtask

  task send_dummy_packet;
    begin
      nw_in_wr   = 1'b1;
      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'hff;
      @(posedge clk); @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk); @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk); @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk); @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk); @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h10;
      @(posedge clk); @(posedge clk);

      nw_in_wr   = 1'b0;
      nw_in_data = 64'd0;
      nw_in_ctrl = 8'd0;
    end
  endtask

  task check_results;
    begin
      errors = 0;

      $display("\n[TB] Final NN check:");

      for (s = 0; s < SAMPLE_COUNT; s = s + 1) begin
        for (i = 0; i < H1_DIM; i = i + 1) begin
          if (dmem[ACT_BASE_ADDR + H1_OFF + i * SAMPLE_COUNT + s][15:0] !== h1_expected[s * H1_DIM + i]) begin
            $display("[FAIL] sample%0d H1[%0d] DMEM[%0d] = 0x%04h expected 0x%04h",
                     s, i, ACT_BASE_ADDR + H1_OFF + i * SAMPLE_COUNT + s,
                     dmem[ACT_BASE_ADDR + H1_OFF + i * SAMPLE_COUNT + s][15:0],
                     h1_expected[s * H1_DIM + i]);
            errors = errors + 1;
          end
        end
      end

      for (s = 0; s < SAMPLE_COUNT; s = s + 1) begin
        for (i = 0; i < H2_DIM; i = i + 1) begin
          if (dmem[ACT_BASE_ADDR + H2_OFF + i * SAMPLE_COUNT + s][15:0] !== h2_expected[s * H2_DIM + i]) begin
            $display("[FAIL] sample%0d H2[%0d] DMEM[%0d] = 0x%04h expected 0x%04h",
                     s, i, ACT_BASE_ADDR + H2_OFF + i * SAMPLE_COUNT + s,
                     dmem[ACT_BASE_ADDR + H2_OFF + i * SAMPLE_COUNT + s][15:0],
                     h2_expected[s * H2_DIM + i]);
            errors = errors + 1;
          end
        end
      end

      for (s = 0; s < SAMPLE_COUNT; s = s + 1) begin
        for (i = 0; i < OUT_DIM; i = i + 1) begin
          if (dmem[ACT_BASE_ADDR + Y_OFF + i * SAMPLE_COUNT + s][15:0] !== y_expected[s * OUT_DIM + i]) begin
            $display("[FAIL] sample%0d Y[%0d] DMEM[%0d] = 0x%04h expected 0x%04h",
                     s, i, ACT_BASE_ADDR + Y_OFF + i * SAMPLE_COUNT + s,
                     dmem[ACT_BASE_ADDR + Y_OFF + i * SAMPLE_COUNT + s][15:0],
                     y_expected[s * OUT_DIM + i]);
            errors = errors + 1;
          end else begin
            $display("[PASS] sample%0d Y[%0d] DMEM[%0d] = 0x%04h",
                     s, i, ACT_BASE_ADDR + Y_OFF + i * SAMPLE_COUNT + s,
                     dmem[ACT_BASE_ADDR + Y_OFF + i * SAMPLE_COUNT + s][15:0]);
          end
        end
      end

      if (gpu_start_count < 1) begin
        $display("[FAIL] GPU start pulse was not observed");
        errors = errors + 1;
      end else begin
        $display("[PASS] GPU start pulse count = %0d", gpu_start_count);
      end

      if (errors == 0)
        $display("[TB] === PASS: final-copy ARM -> GPU NN flow completed correctly ===");
      else
        $display("[TB] === FAIL: %0d mismatches detected ===", errors);
    end
  endtask

  arm_64_top arm_cpu (
    .clk               (clk),
    .reset             (reset),
    .nw_in_data        (nw_in_data),
    .nw_in_ctrl        (nw_in_ctrl),
    .nw_in_wr          (nw_in_wr),
    .nw_in_rdy         (nw_in_rdy),
    .nw_out_data       (nw_out_data),
    .nw_out_ctrl       (nw_out_ctrl),
    .nw_out_wr         (nw_out_wr),
    .nw_out_rdy        (nw_out_rdy),
    .sw_i_mem_addr     (sw_i_mem_addr),
    .sw_i_mem_wdata    (sw_i_mem_wdata),
    .sw_d_mem_addr     (sw_d_mem_addr),
    .hw_i_mem_word_out (),
    .hw_d_mem_word_out_0(),
    .hw_d_mem_word_out_1(),
    .cpu_done          (cpu_done),
    .ext_continue      (ext_continue),
    .ext_drop          (ext_drop),
    .ext_mmio_wr_en    (cpu_mmio_wr_en),
    .ext_mmio_rd_en    (cpu_mmio_rd_en),
    .ext_mmio_addr     (cpu_mmio_addr),
    .ext_mmio_wdata    (cpu_mmio_wdata),
    .ext_mmio_rdata    (cpu_mmio_rdata)
  );

  cpu_gpu_controller ctrl (
    .clk            (clk),
    .reset          (reset),
    .cpu_done       (cpu_done),
    .ext_continue   (ext_continue),
    .ext_drop       (ext_drop),
    .cpu_mmio_wr_en (cpu_mmio_wr_en),
    .cpu_mmio_rd_en (cpu_mmio_rd_en),
    .cpu_mmio_addr  (cpu_mmio_addr),
    .cpu_mmio_wdata (cpu_mmio_wdata),
    .cpu_mmio_rdata (cpu_mmio_rdata),
    .gpu_start      (gpu_start),
    .gpu_core_done  (gpu_done),
    .gpu_result_a   (32'd0),
    .gpu_result_b   (32'd0),
    .gpu_mmio_wr_en (gpu_mmio_wr_en),
    .gpu_mmio_rd_en (gpu_mmio_rd_en),
    .gpu_mmio_addr  (gpu_mmio_addr),
    .gpu_mmio_wdata (gpu_mmio_wdata),
    .gpu_mmio_rdata (gpu_mmio_rdata)
  );

  final_nn_gpu_bridge u_gpu_bridge (
    .clk            (clk),
    .reset          (reset),
    .gpu_start_pulse(gpu_start),
    .gpu_mmio_wr_en (gpu_mmio_wr_en),
    .gpu_mmio_rd_en (gpu_mmio_rd_en),
    .gpu_mmio_addr  (gpu_mmio_addr),
    .gpu_mmio_wdata (gpu_mmio_wdata),
    .gpu_mmio_rdata (gpu_mmio_rdata),
    .imem_prog_we   (gpu_imem_prog_we),
    .imem_prog_addr (gpu_imem_prog_addr),
    .imem_prog_wdata(gpu_imem_prog_wdata),
    .gpu_done       (gpu_done),
    .gpu_busy       (dbg_gpu_busy),
    .dbg_gpu_pc     (dbg_gpu_pc),
    .mem0_en        (gpu_mem0_en),
    .mem0_we        (gpu_mem0_we),
    .mem0_addr      (gpu_mem0_addr),
    .mem0_wdata     (gpu_mem0_wdata),
    .mem0_rdata     (gpu_mem0_rdata),
    .mem0_rvalid    (gpu_mem0_rvalid),
    .mem1_en        (gpu_mem1_en),
    .mem1_we        (gpu_mem1_we),
    .mem1_addr      (gpu_mem1_addr),
    .mem1_wdata     (gpu_mem1_wdata),
    .mem1_rdata     (gpu_mem1_rdata),
    .mem1_rvalid    (gpu_mem1_rvalid)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (reset) begin
      gpu_mem0_rvalid <= 1'b0;
      gpu_mem1_rvalid <= 1'b0;
      gpu_start_count <= 0;
    end else begin
      gpu_mem0_rvalid <= 1'b0;
      gpu_mem1_rvalid <= 1'b0;

      if (gpu_start)
        gpu_start_count <= gpu_start_count + 1;

      if (gpu_mem0_en) begin
        if (gpu_mem0_we) begin
          dmem[gpu_mem0_addr] <= gpu_mem0_wdata;
          $display("[TB] GPU write DMEM[%0d] <- 0x%016h (lane0)", gpu_mem0_addr, gpu_mem0_wdata);
        end else begin
          gpu_mem0_rdata  <= dmem[gpu_mem0_addr];
          gpu_mem0_rvalid <= 1'b1;
          $display("[TB] GPU read  DMEM[%0d] -> 0x%016h (lane0)", gpu_mem0_addr, dmem[gpu_mem0_addr]);
        end
      end

      if (gpu_mem1_en) begin
        if (gpu_mem1_we) begin
          dmem[gpu_mem1_addr] <= gpu_mem1_wdata;
          $display("[TB] GPU write DMEM[%0d] <- 0x%016h (lane1)", gpu_mem1_addr, gpu_mem1_wdata);
        end else begin
          gpu_mem1_rdata  <= dmem[gpu_mem1_addr];
          gpu_mem1_rvalid <= 1'b1;
          $display("[TB] GPU read  DMEM[%0d] -> 0x%016h (lane1)", gpu_mem1_addr, dmem[gpu_mem1_addr]);
        end
      end

      if (gpu_mmio_wr_en) begin
        $display("[TB] CPU write GPU_MMIO[0x%02h] <- 0x%08h", gpu_mmio_addr, gpu_mmio_wdata);
      end
    end
  end

  initial begin
    for (i = 0; i < CPU_PROG_DEPTH; i = i + 1)
      cpu_program[i] = arm_nop(1'b0);

    for (i = 0; i < GPU_PROG_DEPTH; i = i + 1)
      gpu_program[i] = 32'h00000000;

    for (i = 0; i < DMEM_DEPTH; i = i + 1)
      dmem[i] = 64'd0;

    input_data[0]  = 16'sd3;
    input_data[1]  = -16'sd2;
    input_data[2]  = -16'sd1;
    input_data[3]  = 16'sd1;
    input_data[4]  = 16'sd2;
    input_data[5]  = 16'sd0;
    input_data[6]  = 16'sd0;
    input_data[7]  = 16'sd4;
    input_data[8]  = 16'sd1;
    input_data[9]  = -16'sd1;
    input_data[10] = -16'sd2;
    input_data[11] = 16'sd3;
    input_data[12] = 16'sd4;
    input_data[13] = -16'sd3;
    input_data[14] = 16'sd1;
    input_data[15] = 16'sd2;

    for (i = 0; i < IN_DIM * H1_DIM; i = i + 1) begin
      acc = ((i * 3 + 2) % 5) - 2;
      w1_data[i] = acc[15:0];
    end
    for (i = 0; i < H1_DIM * H2_DIM; i = i + 1) begin
      acc = ((i * 2 + 1) % 5) - 2;
      w2_data[i] = acc[15:0];
    end
    for (i = 0; i < H2_DIM * OUT_DIM; i = i + 1) begin
      acc = ((i + 3) % 5) - 2;
      w3_data[i] = acc[15:0];
    end

    for (i = 0; i < H1_DIM; i = i + 1)
      b1_data[i] = i - 2;
    for (i = 0; i < H2_DIM; i = i + 1)
      b2_data[i] = 2 - i;
    b3_data[0] = 16'sd1;
    b3_data[1] = -16'sd1;

    for (s = 0; s < SAMPLE_COUNT; s = s + 1) begin
      for (j = 0; j < H1_DIM; j = j + 1) begin
        acc = $signed(b1_data[j]);
        for (k = 0; k < IN_DIM; k = k + 1)
          acc = acc + $signed(input_data[s * IN_DIM + k]) * $signed(w1_data[j * IN_DIM + k]);
        if (acc < 0)
          h1_expected[s * H1_DIM + j] = 16'h0000;
        else
          h1_expected[s * H1_DIM + j] = acc[15:0];
      end

      for (j = 0; j < H2_DIM; j = j + 1) begin
        acc = $signed(b2_data[j]);
        for (k = 0; k < H1_DIM; k = k + 1)
          acc = acc + $signed(h1_expected[s * H1_DIM + k]) * $signed(w2_data[j * H1_DIM + k]);
        if (acc < 0)
          h2_expected[s * H2_DIM + j] = 16'h0000;
        else
          h2_expected[s * H2_DIM + j] = acc[15:0];
      end

      for (j = 0; j < OUT_DIM; j = j + 1) begin
        acc = $signed(b3_data[j]);
        for (k = 0; k < H2_DIM; k = k + 1)
          acc = acc + $signed(h2_expected[s * H2_DIM + k]) * $signed(w3_data[j * H2_DIM + k]);
        y_expected[s * OUT_DIM + j] = acc[15:0];
      end
    end

    for (i = 0; i < IN_DIM; i = i + 1) begin
      dmem[ACT_BASE_ADDR + X_OFF + i * SAMPLE_COUNT + 0] = {48'd0, input_data[i]};
      dmem[ACT_BASE_ADDR + X_OFF + i * SAMPLE_COUNT + 1] = {48'd0, input_data[IN_DIM + i]};
    end
    for (i = 0; i < IN_DIM * H1_DIM; i = i + 1) begin
      dmem[WGT_BASE_ADDR + W1_OFF + i * SAMPLE_COUNT + 0] = {48'd0, w1_data[i]};
      dmem[WGT_BASE_ADDR + W1_OFF + i * SAMPLE_COUNT + 1] = {48'd0, w1_data[i]};
    end
    for (i = 0; i < H1_DIM * H2_DIM; i = i + 1) begin
      dmem[WGT_BASE_ADDR + W2_OFF + i * SAMPLE_COUNT + 0] = {48'd0, w2_data[i]};
      dmem[WGT_BASE_ADDR + W2_OFF + i * SAMPLE_COUNT + 1] = {48'd0, w2_data[i]};
    end
    for (i = 0; i < H2_DIM * OUT_DIM; i = i + 1) begin
      dmem[WGT_BASE_ADDR + W3_OFF + i * SAMPLE_COUNT + 0] = {48'd0, w3_data[i]};
      dmem[WGT_BASE_ADDR + W3_OFF + i * SAMPLE_COUNT + 1] = {48'd0, w3_data[i]};
    end
    for (i = 0; i < H1_DIM; i = i + 1) begin
      dmem[BIAS_BASE_ADDR + B1_OFF + i * SAMPLE_COUNT + 0] = {48'd0, b1_data[i]};
      dmem[BIAS_BASE_ADDR + B1_OFF + i * SAMPLE_COUNT + 1] = {48'd0, b1_data[i]};
    end
    for (i = 0; i < H2_DIM; i = i + 1) begin
      dmem[BIAS_BASE_ADDR + B2_OFF + i * SAMPLE_COUNT + 0] = {48'd0, b2_data[i]};
      dmem[BIAS_BASE_ADDR + B2_OFF + i * SAMPLE_COUNT + 1] = {48'd0, b2_data[i]};
    end
    for (i = 0; i < OUT_DIM; i = i + 1) begin
      dmem[BIAS_BASE_ADDR + B3_OFF + i * SAMPLE_COUNT + 0] = {48'd0, b3_data[i]};
      dmem[BIAS_BASE_ADDR + B3_OFF + i * SAMPLE_COUNT + 1] = {48'd0, b3_data[i]};
    end

    cpu_program[0] = arm_mov_imm(4'd10, 8'h80);
    cpu_program[1] = arm_mov_imm(4'd0,  8'd0);
    cpu_program[2] = arm_mov_imm(4'd1,  SAMPLE_COUNT[7:0]);
    cpu_program[3] = arm_mov_imm(4'd2,  ACT_BASE_ADDR[7:0]);
    cpu_program[4] = arm_mov_imm(4'd3,  WGT_BASE_ADDR[7:0]);
    cpu_program[5] = arm_mov_imm(4'd4,  BIAS_BASE_ADDR[7:0]);
    cpu_program[6] = arm_mov_imm(4'd5,  AUX_BASE_ADDR[7:0]);
    cpu_program[7] = arm_str_imm(4'd0,  4'd10, 12'd8);
    cpu_program[8] = arm_str_imm(4'd1,  4'd10, 12'd16);
    cpu_program[9] = arm_str_imm(4'd2,  4'd10, 12'd32);
    cpu_program[10]= arm_str_imm(4'd3,  4'd10, 12'd40);
    cpu_program[11]= arm_str_imm(4'd4,  4'd10, 12'd48);
    cpu_program[12]= arm_str_imm(4'd5,  4'd10, 12'd56);

    pc = 0;
    emit_fc_relu_layer(X_OFF,  H1_OFF, W1_OFF, B1_OFF, IN_DIM, H1_DIM, 1);
    emit_fc_relu_layer(H1_OFF, H2_OFF, W2_OFF, B2_OFF, H1_DIM, H2_DIM, 1);
    emit_fc_relu_layer(H2_OFF, Y_OFF,  W3_OFF, B3_OFF, H2_DIM, OUT_DIM, 0);
    gpu_program[pc] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
    pc = pc + 1;
    for (i = pc; i < GPU_PROG_DEPTH; i = i + 1)
      gpu_program[i] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
  end

  initial begin
    $dumpfile("tb_communication_nn.vcd");
    $dumpvars(0, tb_communication_nn);
  end

  initial begin
    $display("[TB] === STARTING FINAL-COPY COMMUNICATION NN TEST ===");

    clk                = 1'b0;
    reset              = 1'b1;
    nw_in_data         = 64'd0;
    nw_in_ctrl         = 8'd0;
    nw_in_wr           = 1'b0;
    nw_out_rdy         = 1'b1;
    sw_i_mem_addr      = 32'd0;
    sw_i_mem_wdata     = 32'd0;
    sw_d_mem_addr      = 32'd0;
    gpu_imem_prog_we   = 1'b0;
    gpu_imem_prog_addr = 9'd0;
    gpu_imem_prog_wdata= 32'd0;
    gpu_mem0_rdata     = 64'd0;
    gpu_mem1_rdata     = 64'd0;
    gpu_mem0_rvalid    = 1'b0;
    gpu_mem1_rvalid    = 1'b0;
    errors             = 0;
    timeout_cycles     = 0;
    gpu_start_count    = 0;
    done_seen          = 1'b0;

    #20;

    $display("[TB] Preloading ARM IMEM...");
    for (i = 0; i < CPU_PROG_DEPTH; i = i + 1) begin
      sw_i_mem_addr  = 32'h8000_0000 + i;
      sw_i_mem_wdata = cpu_program[i];
      #10;
    end
    sw_i_mem_addr  = 32'd0;
    sw_i_mem_wdata = 32'd0;

    $display("[TB] Preloading GPU IMEM...");
    for (i = 0; i < GPU_PROG_DEPTH; i = i + 1) begin
      gpu_imem_prog_we    = 1'b1;
      gpu_imem_prog_addr  = i[8:0];
      gpu_imem_prog_wdata = gpu_program[i];
      #10;
    end
    gpu_imem_prog_we    = 1'b0;
    gpu_imem_prog_addr  = 9'd0;
    gpu_imem_prog_wdata = 32'd0;

    reset = 1'b0;
    #20;

    $display("[TB] Sending dummy packet to enter CPU_MODE...");
    send_dummy_packet();
  end

  always @(posedge clk) begin
    if (!reset) begin
      timeout_cycles <= timeout_cycles + 1;

      if ((timeout_cycles < 40) || (timeout_cycles[6:0] == 7'd0)) begin
        $display("[TB] trace timeout=%0d state=%0d cpu_cycles=%0d in_rdy=%b in_wr=%b gpu_start=%b gpu_done=%b gpu_busy=%b gpu_pc=0x%04h",
                 timeout_cycles,
                 arm_cpu.MEM.net_state,
                 arm_cpu.MEM.cpu_cycle_count,
                 nw_in_rdy,
                 nw_in_wr,
                 gpu_start,
                 gpu_done,
                 dbg_gpu_busy,
                 dbg_gpu_pc);
      end

      if (!done_seen && gpu_done) begin
        done_seen <= 1'b1;
        $display("[TB] GPU completed at time %0t", $time);
        #20;
        check_results();
        #20;
        $finish;
      end

      if (timeout_cycles > 12000) begin
        $display("[TB] TIMEOUT: state=%0d cpu_cycles=%0d gpu_start_count=%0d gpu_busy=%b gpu_done=%b gpu_pc=0x%04h",
                 arm_cpu.MEM.net_state,
                 arm_cpu.MEM.cpu_cycle_count,
                 gpu_start_count,
                 dbg_gpu_busy,
                 gpu_done,
                 dbg_gpu_pc);
        check_results();
        $finish;
      end
    end
  end

endmodule
