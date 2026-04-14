`timescale 1ns / 1ps

module final_packet_nn_gpu_bridge #(
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
  wire                   core_done_level;
  reg                    core_done_d;

  assign mmio_wr_en_mux = gpu_start_pulse ? 1'b1        : gpu_mmio_wr_en;
  assign mmio_rd_en_mux = gpu_start_pulse ? 1'b0        : gpu_mmio_rd_en;
  assign mmio_addr_mux  = gpu_start_pulse ? REG_CONTROL : gpu_mmio_addr;
  assign mmio_wdata_mux = gpu_start_pulse ? CTRL_START  : gpu_mmio_wdata;
  assign gpu_done       = core_done_level & ~core_done_d;

  always @(posedge clk or posedge reset) begin
    if (reset)
      core_done_d <= 1'b0;
    else
      core_done_d <= core_done_level;
  end

  gpu_top_fifo_if_copy #(
    .MMIO_ADDR_W(MMIO_ADDR_W),
    .IMEM_AW    (IMEM_AW),
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
    .proc_done      (core_done_level),
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

module tb_packet;

  localparam integer CPU_PROG_DEPTH = 512;
  localparam integer GPU_PROG_DEPTH = 512;
  localparam integer DMEM_DEPTH     = 256;

  localparam integer PACKET_COUNT = 3;
  localparam integer PKT_WORDS    = 6;
  localparam integer PKT_TX_WORDS = (PKT_WORDS * 2) - 2;

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
  integer gpu_done_count;
  integer tx_packet_done_count;
  integer tx_capture_packet;
  integer active_packet_idx;
  reg     all_done;
  reg     gpu_done_d;
  reg     tx_active;

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

  reg signed [15:0] packet_input_data [0:PACKET_COUNT-1][0:(SAMPLE_COUNT*IN_DIM)-1];
  reg signed [15:0] w1_data            [0:(IN_DIM*H1_DIM)-1];
  reg signed [15:0] w2_data            [0:(H1_DIM*H2_DIM)-1];
  reg signed [15:0] w3_data            [0:(H2_DIM*OUT_DIM)-1];
  reg signed [15:0] b1_data            [0:H1_DIM-1];
  reg signed [15:0] b2_data            [0:H2_DIM-1];
  reg signed [15:0] b3_data            [0:OUT_DIM-1];
  reg [15:0] packet_h1_expected        [0:PACKET_COUNT-1][0:(SAMPLE_COUNT*H1_DIM)-1];
  reg [15:0] packet_h2_expected        [0:PACKET_COUNT-1][0:(SAMPLE_COUNT*H2_DIM)-1];
  reg [15:0] packet_y_expected         [0:PACKET_COUNT-1][0:(SAMPLE_COUNT*OUT_DIM)-1];

  reg [63:0] pkt_data                  [0:PACKET_COUNT-1][0:PKT_WORDS-1];
  reg [7:0]  pkt_ctrl                  [0:PACKET_COUNT-1][0:PKT_WORDS-1];
  reg [63:0] tx_data_capture           [0:PACKET_COUNT-1][0:PKT_TX_WORDS-1];
  reg [7:0]  tx_ctrl_capture           [0:PACKET_COUNT-1][0:PKT_TX_WORDS-1];
  integer    tx_word_count             [0:PACKET_COUNT-1];

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

  task load_packet_inputs(
    input integer pkt
  );
    integer idx;
    begin
      $display("\n[TB] Loading NN inputs for packet %0d into shared GPU DMEM...", pkt);
      for (idx = 0; idx < IN_DIM; idx = idx + 1) begin
        dmem[ACT_BASE_ADDR + X_OFF + idx * SAMPLE_COUNT + 0] = {48'd0, packet_input_data[pkt][idx]};
        dmem[ACT_BASE_ADDR + X_OFF + idx * SAMPLE_COUNT + 1] = {48'd0, packet_input_data[pkt][IN_DIM + idx]};
        $display("[TB]   pkt%0d X lane0[%0d]=%0d lane1[%0d]=%0d",
                 pkt,
                 idx,
                 $signed(packet_input_data[pkt][idx]),
                 idx,
                 $signed(packet_input_data[pkt][IN_DIM + idx]));
      end
    end
  endtask

  task send_packet(
    input integer pkt
  );
    integer idx;
    begin
      $display("\n[TB] Sending packet %0d into network path...", pkt);
      nw_in_wr = 1'b1;
      for (idx = 0; idx < PKT_WORDS; idx = idx + 1) begin
        nw_in_data = pkt_data[pkt][idx];
        nw_in_ctrl = pkt_ctrl[pkt][idx];
        $display("[TB]   RX pkt%0d word%0d ctrl=0x%02h data=0x%016h",
                 pkt, idx, pkt_ctrl[pkt][idx], pkt_data[pkt][idx]);
        @(posedge clk);
        @(posedge clk);
      end

      nw_in_wr   = 1'b0;
      nw_in_data = 64'd0;
      nw_in_ctrl = 8'd0;
    end
  endtask

  task check_packet_nn(
    input integer pkt
  );
    integer local_errors;
    integer sample_idx;
    integer out_idx;
    begin
      local_errors = 0;
      $display("\n[TB] Packet %0d NN output check:", pkt);
      for (sample_idx = 0; sample_idx < SAMPLE_COUNT; sample_idx = sample_idx + 1) begin
        for (out_idx = 0; out_idx < OUT_DIM; out_idx = out_idx + 1) begin
          if (dmem[ACT_BASE_ADDR + Y_OFF + out_idx * SAMPLE_COUNT + sample_idx][15:0] !==
              packet_y_expected[pkt][sample_idx * OUT_DIM + out_idx]) begin
            $display("[FAIL] pkt%0d sample%0d Y[%0d]: actual=0x%04h expected=0x%04h",
                     pkt,
                     sample_idx,
                     out_idx,
                     dmem[ACT_BASE_ADDR + Y_OFF + out_idx * SAMPLE_COUNT + sample_idx][15:0],
                     packet_y_expected[pkt][sample_idx * OUT_DIM + out_idx]);
            local_errors = local_errors + 1;
          end else begin
            $display("[PASS] pkt%0d sample%0d Y[%0d]: actual=0x%04h expected=0x%04h",
                     pkt,
                     sample_idx,
                     out_idx,
                     dmem[ACT_BASE_ADDR + Y_OFF + out_idx * SAMPLE_COUNT + sample_idx][15:0],
                     packet_y_expected[pkt][sample_idx * OUT_DIM + out_idx]);
          end
        end
      end
      errors = errors + local_errors;
    end
  endtask

  task check_packet_tx(
    input integer pkt
  );
    integer local_errors;
    integer idx;
    reg [63:0] expected_data;
    reg [7:0]  expected_ctrl;
    begin
      local_errors = 0;
      $display("\n[TB] Packet %0d TX check:", pkt);

      if (tx_word_count[pkt] !== PKT_TX_WORDS) begin
        $display("[FAIL] pkt%0d TX word count: actual=%0d expected=%0d",
                 pkt, tx_word_count[pkt], PKT_TX_WORDS);
        local_errors = local_errors + 1;
      end else begin
        $display("[PASS] pkt%0d TX word count: actual=%0d expected=%0d",
                 pkt, tx_word_count[pkt], PKT_TX_WORDS);
      end

      for (idx = 0; idx < PKT_TX_WORDS; idx = idx + 1) begin
        if (idx == 0) begin
          expected_ctrl = pkt_ctrl[pkt][0];
          expected_data = pkt_data[pkt][0];
        end else if (idx == PKT_TX_WORDS - 1) begin
          expected_ctrl = pkt_ctrl[pkt][PKT_WORDS - 1];
          expected_data = pkt_data[pkt][PKT_WORDS - 1];
        end else begin
          expected_ctrl = 8'h00;
          expected_data = pkt_data[pkt][((idx - 1) / 2) + 1];
        end

        if (tx_ctrl_capture[pkt][idx] !== expected_ctrl) begin
          $display("[FAIL] pkt%0d tx_ctrl[%0d]: actual=0x%02h expected=0x%02h",
                   pkt, idx, tx_ctrl_capture[pkt][idx], expected_ctrl);
          local_errors = local_errors + 1;
        end else begin
          $display("[PASS] pkt%0d tx_ctrl[%0d]: actual=0x%02h expected=0x%02h",
                   pkt, idx, tx_ctrl_capture[pkt][idx], expected_ctrl);
        end

        if (tx_data_capture[pkt][idx] !== expected_data) begin
          $display("[FAIL] pkt%0d tx_data[%0d]: actual=0x%016h expected=0x%016h",
                   pkt, idx, tx_data_capture[pkt][idx], expected_data);
          local_errors = local_errors + 1;
        end else begin
          $display("[PASS] pkt%0d tx_data[%0d]: actual=0x%016h expected=0x%016h",
                   pkt, idx, tx_data_capture[pkt][idx], expected_data);
        end
      end

      errors = errors + local_errors;
    end
  endtask

  arm_64_top arm_cpu (
    .clk            (clk),
    .reset          (reset),
    .nw_in_data     (nw_in_data),
    .nw_in_ctrl     (nw_in_ctrl),
    .nw_in_wr       (nw_in_wr),
    .nw_in_rdy      (nw_in_rdy),
    .nw_out_data    (nw_out_data),
    .nw_out_ctrl    (nw_out_ctrl),
    .nw_out_wr      (nw_out_wr),
    .nw_out_rdy     (nw_out_rdy),
    .sw_i_mem_addr  (sw_i_mem_addr),
    .sw_i_mem_wdata (sw_i_mem_wdata),
    .sw_d_mem_addr  (sw_d_mem_addr),
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

  final_packet_nn_gpu_bridge u_bridge (
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
    if (!reset) begin
      gpu_mem0_rvalid <= 1'b0;
      gpu_mem1_rvalid <= 1'b0;

      if (gpu_mem0_en) begin
        if (gpu_mem0_we) begin
          dmem[gpu_mem0_addr] <= gpu_mem0_wdata;
          $display("[TB] GPU write DMEM[%0d] <- 0x%016h (lane0)", gpu_mem0_addr, gpu_mem0_wdata);
        end else begin
          gpu_mem0_rdata  <= dmem[gpu_mem0_addr];
          gpu_mem0_rvalid <= 1'b1;
        end
      end

      if (gpu_mem1_en) begin
        if (gpu_mem1_we) begin
          dmem[gpu_mem1_addr] <= gpu_mem1_wdata;
          $display("[TB] GPU write DMEM[%0d] <- 0x%016h (lane1)", gpu_mem1_addr, gpu_mem1_wdata);
        end else begin
          gpu_mem1_rdata  <= dmem[gpu_mem1_addr];
          gpu_mem1_rvalid <= 1'b1;
        end
      end

      if (gpu_mmio_wr_en) begin
        $display("[TB] CPU write GPU_MMIO[0x%02h] <- 0x%08h", gpu_mmio_addr, gpu_mmio_wdata);
      end

      if (gpu_start) begin
        gpu_start_count <= gpu_start_count + 1;
        $display("[TB] GPU start pulse #%0d at time %0t", gpu_start_count + 1, $time);
      end

      if (gpu_done && !gpu_done_d) begin
        gpu_done_count <= gpu_done_count + 1;
        $display("[TB] GPU done pulse #%0d at time %0t", gpu_done_count + 1, $time);
      end

      if (nw_out_wr) begin
        if (!tx_active) begin
          if ((nw_out_ctrl == 8'hff) && (tx_capture_packet < PACKET_COUNT)) begin
            tx_active <= 1'b1;
            tx_ctrl_capture[tx_capture_packet][0] <= nw_out_ctrl;
            tx_data_capture[tx_capture_packet][0] <= nw_out_data;
            tx_word_count[tx_capture_packet]      <= 1;
            $display("[TB]   TX pkt%0d word0 ctrl=0x%02h data=0x%016h",
                     tx_capture_packet, nw_out_ctrl, nw_out_data);
          end
        end else begin
          if (tx_capture_packet < PACKET_COUNT && tx_word_count[tx_capture_packet] < PKT_TX_WORDS) begin
            tx_ctrl_capture[tx_capture_packet][tx_word_count[tx_capture_packet]] <= nw_out_ctrl;
            tx_data_capture[tx_capture_packet][tx_word_count[tx_capture_packet]] <= nw_out_data;
          end

          $display("[TB]   TX pkt%0d word%0d ctrl=0x%02h data=0x%016h",
                   tx_capture_packet,
                   tx_word_count[tx_capture_packet],
                   nw_out_ctrl,
                   nw_out_data);

          tx_word_count[tx_capture_packet] <= tx_word_count[tx_capture_packet] + 1;

          if (nw_out_ctrl == 8'h10) begin
            tx_packet_done_count <= tx_packet_done_count + 1;
            tx_active            <= 1'b0;
            $display("[TB] Packet %0d TX completed at time %0t", tx_capture_packet, $time);
            tx_capture_packet    <= tx_capture_packet + 1;
          end
        end
      end

      if ((timeout_cycles < 40) || (timeout_cycles[9:0] == 10'd0)) begin
        $display("[TB] trace cycles=%0d state=%0d in_rdy=%b in_wr=%b out_wr=%b gpu_start=%b gpu_done=%b gpu_busy=%b gpu_pc=0x%04h",
                 timeout_cycles,
                 arm_cpu.MEM.net_state,
                 nw_in_rdy,
                 nw_in_wr,
                 nw_out_wr,
                 gpu_start,
                 gpu_done,
                 dbg_gpu_busy,
                 dbg_gpu_pc);
      end
    end
  end

  always @(posedge clk) begin
    if (!reset && !all_done) begin
      gpu_done_d <= gpu_done;
      timeout_cycles <= timeout_cycles + 1;
      if (timeout_cycles > 30000) begin
        $display("[TB] TIMEOUT: gpu_start_count=%0d gpu_done_count=%0d tx_packet_done_count=%0d state=%0d gpu_busy=%b gpu_pc=0x%04h",
                 gpu_start_count,
                 gpu_done_count,
                 tx_packet_done_count,
                 arm_cpu.MEM.net_state,
                 dbg_gpu_busy,
                 dbg_gpu_pc);
        $finish;
      end
    end
  end

  initial begin
    for (i = 0; i < CPU_PROG_DEPTH; i = i + 1)
      cpu_program[i] = arm_nop(1'b0);
    for (i = 0; i < GPU_PROG_DEPTH; i = i + 1)
      gpu_program[i] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
    for (i = 0; i < DMEM_DEPTH; i = i + 1)
      dmem[i] = 64'd0;
    for (i = 0; i < PACKET_COUNT; i = i + 1) begin
      tx_word_count[i] = 0;
      for (j = 0; j < PKT_TX_WORDS; j = j + 1) begin
        tx_data_capture[i][j] = 64'd0;
        tx_ctrl_capture[i][j] = 8'd0;
      end
    end

    packet_input_data[0][0]  = 16'sd3;
    packet_input_data[0][1]  = -16'sd2;
    packet_input_data[0][2]  = -16'sd1;
    packet_input_data[0][3]  = 16'sd1;
    packet_input_data[0][4]  = 16'sd2;
    packet_input_data[0][5]  = 16'sd0;
    packet_input_data[0][6]  = 16'sd0;
    packet_input_data[0][7]  = 16'sd4;
    packet_input_data[0][8]  = 16'sd1;
    packet_input_data[0][9]  = -16'sd1;
    packet_input_data[0][10] = -16'sd2;
    packet_input_data[0][11] = 16'sd3;
    packet_input_data[0][12] = 16'sd4;
    packet_input_data[0][13] = -16'sd3;
    packet_input_data[0][14] = 16'sd1;
    packet_input_data[0][15] = 16'sd2;

    packet_input_data[1][0]  = -16'sd4;
    packet_input_data[1][1]  = 16'sd1;
    packet_input_data[1][2]  = 16'sd2;
    packet_input_data[1][3]  = -16'sd2;
    packet_input_data[1][4]  = 16'sd3;
    packet_input_data[1][5]  = 16'sd1;
    packet_input_data[1][6]  = -16'sd1;
    packet_input_data[1][7]  = 16'sd0;
    packet_input_data[1][8]  = 16'sd2;
    packet_input_data[1][9]  = 16'sd2;
    packet_input_data[1][10] = -16'sd3;
    packet_input_data[1][11] = 16'sd1;
    packet_input_data[1][12] = -16'sd2;
    packet_input_data[1][13] = 16'sd4;
    packet_input_data[1][14] = 16'sd0;
    packet_input_data[1][15] = -16'sd1;

    for (i = 0; i < SAMPLE_COUNT * IN_DIM; i = i + 1)
      packet_input_data[2][i] = packet_input_data[0][i];

    for (i = 0; i < IN_DIM * H1_DIM; i = i + 1) begin
      acc = ((i % 5) - 2) * (((i / 5) % 3) + 1);
      w1_data[i] = acc[15:0];
    end
    for (i = 0; i < H1_DIM * H2_DIM; i = i + 1) begin
      acc = ((i % 4) - 1) * (((i / 4) % 2) + 1);
      w2_data[i] = acc[15:0];
    end
    for (i = 0; i < H2_DIM * OUT_DIM; i = i + 1) begin
      acc = ((i % 3) - 1) * (((i / 3) % 2) + 1);
      w3_data[i] = acc[15:0];
    end
    for (i = 0; i < H1_DIM; i = i + 1)
      b1_data[i] = i - 2;
    for (i = 0; i < H2_DIM; i = i + 1)
      b2_data[i] = 2 - i;
    b3_data[0] = 16'sd1;
    b3_data[1] = -16'sd1;

    for (j = 0; j < PACKET_COUNT; j = j + 1) begin
      for (s = 0; s < SAMPLE_COUNT; s = s + 1) begin
        for (i = 0; i < H1_DIM; i = i + 1) begin
          acc = $signed(b1_data[i]);
          for (k = 0; k < IN_DIM; k = k + 1)
            acc = acc + $signed(packet_input_data[j][s * IN_DIM + k]) * $signed(w1_data[i * IN_DIM + k]);
          if (acc < 0)
            packet_h1_expected[j][s * H1_DIM + i] = 16'h0000;
          else
            packet_h1_expected[j][s * H1_DIM + i] = acc[15:0];
        end

        for (i = 0; i < H2_DIM; i = i + 1) begin
          acc = $signed(b2_data[i]);
          for (k = 0; k < H1_DIM; k = k + 1)
            acc = acc + $signed(packet_h1_expected[j][s * H1_DIM + k]) * $signed(w2_data[i * H1_DIM + k]);
          if (acc < 0)
            packet_h2_expected[j][s * H2_DIM + i] = 16'h0000;
          else
            packet_h2_expected[j][s * H2_DIM + i] = acc[15:0];
        end

        for (i = 0; i < OUT_DIM; i = i + 1) begin
          acc = $signed(b3_data[i]);
          for (k = 0; k < H2_DIM; k = k + 1)
            acc = acc + $signed(packet_h2_expected[j][s * H2_DIM + k]) * $signed(w3_data[i * H2_DIM + k]);
          packet_y_expected[j][s * OUT_DIM + i] = acc[15:0];
        end
      end
    end

    pkt_data[0][0] = 64'h1111_0000_0000_0001;
    pkt_data[0][1] = 64'hAAAA_0000_0000_0001;
    pkt_data[0][2] = 64'hAAAA_0000_0000_0002;
    pkt_data[0][3] = 64'hAAAA_0000_0000_0003;
    pkt_data[0][4] = 64'hAAAA_0000_0000_0004;
    pkt_data[0][5] = 64'hEEEE_0000_0000_0001;

    pkt_data[1][0] = 64'h2222_0000_0000_0002;
    pkt_data[1][1] = 64'hBBBB_0000_0000_0011;
    pkt_data[1][2] = 64'hBBBB_0000_0000_0012;
    pkt_data[1][3] = 64'hBBBB_0000_0000_0013;
    pkt_data[1][4] = 64'hBBBB_0000_0000_0014;
    pkt_data[1][5] = 64'hEEEE_0000_0000_0002;

    for (i = 0; i < PKT_WORDS; i = i + 1)
      pkt_data[2][i] = pkt_data[0][i];

    for (j = 0; j < PACKET_COUNT; j = j + 1) begin
      pkt_ctrl[j][0] = 8'hff;
      pkt_ctrl[j][1] = 8'h00;
      pkt_ctrl[j][2] = 8'h00;
      pkt_ctrl[j][3] = 8'h00;
      pkt_ctrl[j][4] = 8'h00;
      pkt_ctrl[j][5] = 8'h10;
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

    cpu_program[0]  = arm_mov_imm(4'd10, 8'h80);
    cpu_program[1]  = arm_mov_imm(4'd0,  8'd0);
    cpu_program[2]  = arm_mov_imm(4'd1,  SAMPLE_COUNT[7:0]);
    cpu_program[3]  = arm_mov_imm(4'd2,  ACT_BASE_ADDR[7:0]);
    cpu_program[4]  = arm_mov_imm(4'd3,  WGT_BASE_ADDR[7:0]);
    cpu_program[5]  = arm_mov_imm(4'd4,  BIAS_BASE_ADDR[7:0]);
    cpu_program[6]  = arm_mov_imm(4'd5,  AUX_BASE_ADDR[7:0]);
    cpu_program[7]  = arm_str_imm(4'd0,  4'd10, 12'd8);
    cpu_program[8]  = arm_str_imm(4'd1,  4'd10, 12'd16);
    cpu_program[9]  = arm_str_imm(4'd2,  4'd10, 12'd32);
    cpu_program[10] = arm_str_imm(4'd3,  4'd10, 12'd40);
    cpu_program[11] = arm_str_imm(4'd4,  4'd10, 12'd48);
    cpu_program[12] = arm_str_imm(4'd5,  4'd10, 12'd56);

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
    $dumpfile("tb_packet.vcd");
    $dumpvars(0, tb_packet);
  end

  initial begin
    $display("[TB] === STARTING FINAL-COPY PACKET NN TEST ===");

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
    gpu_done_count     = 0;
    tx_packet_done_count = 0;
    tx_capture_packet  = 0;
    active_packet_idx  = -1;
    all_done           = 1'b0;
    gpu_done_d         = 1'b0;
    tx_active          = 1'b0;

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

    for (j = 0; j < PACKET_COUNT; j = j + 1) begin
      if (j > 0) begin
        $display("\n[TB] Resetting ARM/GPU packet path before packet %0d...", j);
        reset          = 1'b1;
        nw_in_wr       = 1'b0;
        nw_in_data     = 64'd0;
        nw_in_ctrl     = 8'd0;
        timeout_cycles = 0;
        #40;
        reset = 1'b0;
        #40;
      end

      active_packet_idx = j;
      load_packet_inputs(j);

      wait (nw_in_rdy == 1'b1);
      #20;
      send_packet(j);

      wait (gpu_done_count == (j + 1));
      #20;
      check_packet_nn(j);

      wait (tx_packet_done_count == (j + 1));
      #20;
      check_packet_tx(j);
      #40;
    end

    $display("\n[TB] Final summary:");
    if (gpu_start_count !== PACKET_COUNT) begin
      $display("[FAIL] GPU start pulse count: actual=%0d expected=%0d", gpu_start_count, PACKET_COUNT);
      errors = errors + 1;
    end else begin
      $display("[PASS] GPU start pulse count: actual=%0d expected=%0d", gpu_start_count, PACKET_COUNT);
    end

    if (gpu_done_count !== PACKET_COUNT) begin
      $display("[FAIL] GPU done pulse count: actual=%0d expected=%0d", gpu_done_count, PACKET_COUNT);
      errors = errors + 1;
    end else begin
      $display("[PASS] GPU done pulse count: actual=%0d expected=%0d", gpu_done_count, PACKET_COUNT);
    end

    if (tx_packet_done_count !== PACKET_COUNT) begin
      $display("[FAIL] TX packet count: actual=%0d expected=%0d", tx_packet_done_count, PACKET_COUNT);
      errors = errors + 1;
    end else begin
      $display("[PASS] TX packet count: actual=%0d expected=%0d", tx_packet_done_count, PACKET_COUNT);
    end

    if (errors == 0)
      $display("[TB] === PASS: 3 full packets completed through ARM -> GPU NN -> TX ===");
    else
      $display("[TB] === FAIL: %0d total mismatches detected ===", errors);

    all_done = 1'b1;
    #20;
    $finish;
  end

endmodule
