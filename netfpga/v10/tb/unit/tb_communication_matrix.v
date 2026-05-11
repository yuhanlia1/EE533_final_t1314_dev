`timescale 1ns / 1ps

module final_matrix_gpu_bridge #(
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
) ;

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
    .clk          (clk),
    .rst          (reset),
    .mmio_wr_en   (mmio_wr_en_mux),
    .mmio_rd_en   (mmio_rd_en_mux),
    .mmio_addr    (mmio_addr_mux),
    .mmio_wdata   (mmio_wdata_mux),
    .mmio_rdata   (gpu_mmio_rdata),
    .imem_prog_we (imem_prog_we),
    .imem_prog_addr(imem_prog_addr),
    .imem_prog_wdata(imem_prog_wdata),
    .proc_active  (1'b1),
    .proc_done    (gpu_done),
    .mem0_en      (mem0_en),
    .mem0_we      (mem0_we),
    .mem0_addr    (mem0_addr),
    .mem0_wdata   (mem0_wdata),
    .mem0_rdata   (mem0_rdata),
    .mem0_rvalid  (mem0_rvalid),
    .mem1_en      (mem1_en),
    .mem1_we      (mem1_we),
    .mem1_addr    (mem1_addr),
    .mem1_wdata   (mem1_wdata),
    .mem1_rdata   (mem1_rdata),
    .mem1_rvalid  (mem1_rvalid),
    .dbg_pc       (dbg_gpu_pc),
    .busy         (gpu_busy)
  );
endmodule

module tb_communication_matrix;

  localparam integer CPU_PROG_DEPTH = 512;
  localparam integer GPU_PROG_DEPTH = 512;
  localparam integer DMEM_DEPTH     = 256;
  localparam integer MAT_DIM        = 4;
  localparam integer MAT_ELEMS      = MAT_DIM * MAT_DIM;
  localparam integer BASE_A_ADDR    = 0;
  localparam integer BASE_B_ADDR    = 16;
  localparam integer BASE_C_ADDR    = 64;

  integer i;
  integer row;
  integer col;
  integer k;
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

  reg [15:0] matrix_a [0:MAT_ELEMS-1];
  reg [15:0] matrix_b [0:MAT_ELEMS-1];
  reg [15:0] expected [0:MAT_ELEMS-1];

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

  task send_dummy_packet;
    begin
      nw_in_wr   = 1'b1;
      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'hff;
      @(posedge clk);
      @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk);
      @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk);
      @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk);
      @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h00;
      @(posedge clk);
      @(posedge clk);

      nw_in_data = 64'h0000_0000_0000_0000;
      nw_in_ctrl = 8'h10;
      @(posedge clk);
      @(posedge clk);

      nw_in_wr   = 1'b0;
      nw_in_data = 64'd0;
      nw_in_ctrl = 8'd0;
    end
  endtask

  task check_results;
    begin
      errors = 0;
      $display("\n[TB] Final matrix check:");
      for (i = 0; i < MAT_ELEMS; i = i + 1) begin
        if (dmem[BASE_C_ADDR + i][15:0] !== expected[i]) begin
          $display("[FAIL] C[%0d][%0d] DMEM[%0d] = 0x%04h expected 0x%04h",
                   i / MAT_DIM, i % MAT_DIM, BASE_C_ADDR + i,
                   dmem[BASE_C_ADDR + i][15:0], expected[i]);
          errors = errors + 1;
        end else begin
          $display("[PASS] C[%0d][%0d] DMEM[%0d] = 0x%04h",
                   i / MAT_DIM, i % MAT_DIM, BASE_C_ADDR + i,
                   dmem[BASE_C_ADDR + i][15:0]);
        end
      end

      if (gpu_start_count < 1) begin
        $display("[FAIL] GPU start pulse was not observed");
        errors = errors + 1;
      end else begin
        $display("[PASS] GPU start pulse count = %0d", gpu_start_count);
      end

      if (errors == 0)
        $display("[TB] === PASS: final-copy ARM -> GPU matrix flow completed correctly ===");
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

  final_matrix_gpu_bridge u_gpu_bridge (
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

    matrix_a[0]  = 16'h0001; matrix_a[1]  = 16'h0002; matrix_a[2]  = 16'h0003; matrix_a[3]  = 16'h0004;
    matrix_a[4]  = 16'h0005; matrix_a[5]  = 16'h0006; matrix_a[6]  = 16'h0007; matrix_a[7]  = 16'h0008;
    matrix_a[8]  = 16'h0009; matrix_a[9]  = 16'h000A; matrix_a[10] = 16'h000B; matrix_a[11] = 16'h000C;
    matrix_a[12] = 16'h000D; matrix_a[13] = 16'h000E; matrix_a[14] = 16'h000F; matrix_a[15] = 16'h0010;

    matrix_b[0]  = 16'h0001; matrix_b[1]  = 16'h0000; matrix_b[2]  = 16'h0002; matrix_b[3]  = 16'h0001;
    matrix_b[4]  = 16'h0000; matrix_b[5]  = 16'h0001; matrix_b[6]  = 16'h0001; matrix_b[7]  = 16'h0000;
    matrix_b[8]  = 16'h0001; matrix_b[9]  = 16'h0002; matrix_b[10] = 16'h0000; matrix_b[11] = 16'h0001;
    matrix_b[12] = 16'h0002; matrix_b[13] = 16'h0001; matrix_b[14] = 16'h0001; matrix_b[15] = 16'h0002;

    for (row = 0; row < MAT_DIM; row = row + 1) begin
      for (col = 0; col < MAT_DIM; col = col + 1) begin
        acc = 0;
        for (k = 0; k < MAT_DIM; k = k + 1)
          acc = acc + $signed({1'b0, matrix_a[row * MAT_DIM + k]}) * $signed({1'b0, matrix_b[k * MAT_DIM + col]});
        expected[row * MAT_DIM + col] = acc[15:0];
      end
    end

    for (i = 0; i < MAT_ELEMS; i = i + 1) begin
      dmem[BASE_A_ADDR + i] = {48'd0, matrix_a[i]};
      dmem[BASE_B_ADDR + i] = {48'd0, matrix_b[i]};
    end

    cpu_program[0] = arm_mov_imm(4'd10, 8'h80);  // r10 = GPU MMIO base
    cpu_program[1] = arm_mov_imm(4'd0,  8'h00);  // entry_pc/base_a
    cpu_program[2] = arm_mov_imm(4'd1,  8'h01);  // work_size = 1
    cpu_program[3] = arm_mov_imm(4'd2,  8'h10);  // base_b = 16
    cpu_program[4] = arm_mov_imm(4'd3,  8'h40);  // base_c = 64
    cpu_program[5] = arm_str_imm(4'd0,  4'd10, 12'd8);   // entry_pc @ 0x88
    cpu_program[6] = arm_str_imm(4'd1,  4'd10, 12'd16);  // work_size @ 0x90
    cpu_program[7] = arm_str_imm(4'd0,  4'd10, 12'd32);  // base_a @ 0xA0
    cpu_program[8] = arm_str_imm(4'd2,  4'd10, 12'd40);  // base_b @ 0xA8
    cpu_program[9] = arm_str_imm(4'd3,  4'd10, 12'd48);  // base_c @ 0xB0

    i = 0;
    for (row = 0; row < MAT_DIM; row = row + 1) begin
      for (col = 0; col < MAT_DIM; col = col + 1) begin
        gpu_program[i] = gpu_instr(4'h1, 3'd6, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
        i = i + 1;

        for (k = 0; k < MAT_DIM; k = k + 1) begin
          gpu_program[i] = gpu_instr(4'h2, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, (row * MAT_DIM) + k);
          i = i + 1;
          gpu_program[i] = gpu_instr(4'h2, 3'd1, 3'd0, 3'd0, 2'b01, 1'b0, (k * MAT_DIM) + col);
          i = i + 1;
          gpu_program[i] = gpu_instr(4'hC, 3'd6, 3'd0, 3'd1, 2'b00, 1'b0, 16'h0000);
          i = i + 1;
        end

        gpu_program[i] = gpu_instr(4'h3, 3'd0, 3'd0, 3'd6, 2'b10, 1'b0, (row * MAT_DIM) + col);
        i = i + 1;
      end
    end
    gpu_program[i] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
  end

  initial begin
    $dumpfile("tb_communication_matrix.vcd");
    $dumpvars(0, tb_communication_matrix);
  end

  initial begin
    $display("[TB] === STARTING FINAL-COPY COMMUNICATION MATRIX TEST ===");

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

      if (timeout_cycles > 4000) begin
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
