`timescale 1ns/1ps

module ann_cpu_gpu_compute_core #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter MAX_FRAME_BYTES = 2048,
  parameter FRAME_LEN_WIDTH = $clog2(MAX_FRAME_BYTES + 1),
  parameter MAX_FEATURES = 1012,
  parameter DMEM_DEPTH = 256,
  parameter DMEM_ADDR_WIDTH = $clog2(DMEM_DEPTH),
  parameter IN_DIM = 8,
  parameter OUT_DIM = 2
) (
  input                           clk,
  input                           reset,
  input                           start,
  input  [DATA_WIDTH-1:0]         module_header_word,
  input  [FRAME_LEN_WIDTH-1:0]    frame_len,
  input  [MAX_FRAME_BYTES*8-1:0]  frame_bytes_flat,
  input  [15:0]                   task_type,
  input  [15:0]                   feature_count,
  input  [MAX_FEATURES*16-1:0]    features_flat,

  input  [31:0]                   sw_i_mem_addr,
  input  [31:0]                   sw_i_mem_wdata,
  input  [31:0]                   sw_d_mem_addr,
  input  [31:0]                   sw_gpu_w_mem_addr,
  input  [31:0]                   sw_gpu_w_mem_wdata_0,
  input  [31:0]                   sw_gpu_w_mem_wdata_1,
  input  [31:0]                   sw_gpu_ifmap_addr,
  input  [31:0]                   sw_gpu_ifmap_wdata,
  input  [31:0]                   sw_gpu_ofmap_addr,

  output reg                      done,
  output reg [7:0]                result_status,
  output reg [15:0]               result_type,
  output reg [15:0]               result_len,
  output reg [15:0]               result_data_0,
  output reg [15:0]               result_data_1,
  output reg [31:0]               hw_gpu_ofmap_data_0,
  output reg [31:0]               hw_gpu_ofmap_data_1
);

  localparam integer CPU_PROG_DEPTH = 64;
  localparam integer GPU_PROG_DEPTH = 128;
  localparam integer CPU_PROG_LEN   = 13;
  localparam integer GPU_PROG_LEN   = 59;
  localparam integer MAX_FRAME_WORDS = ((MAX_FRAME_BYTES + CTRL_WIDTH - 1) / CTRL_WIDTH);
  localparam integer FRAME_WORD_IDX_WIDTH = (MAX_FRAME_WORDS > 1) ? $clog2(MAX_FRAME_WORDS) : 1;

  localparam [1:0] BOOT_CPU  = 2'd0;
  localparam [1:0] BOOT_GPU  = 2'd1;
  localparam [1:0] BOOT_DONE = 2'd2;

  localparam [2:0] ST_IDLE         = 3'd0;
  localparam [2:0] ST_LOAD_FEATURE = 3'd1;
  localparam [2:0] ST_SEND_MODULE_HDR = 3'd2;
  localparam [2:0] ST_SEND_FRAME_WORDS = 3'd3;
  localparam [2:0] ST_WAIT_CPU     = 3'd4;
  localparam [2:0] ST_WAIT_GPU     = 3'd5;
  localparam [2:0] ST_CAPTURE      = 3'd6;

  localparam [7:0]  RESULT_STATUS_OK    = 8'h00;
  localparam [7:0]  RESULT_STATUS_TRUNC = 8'h05;
  localparam [15:0] RESULT_TYPE_NN      = 16'h0002;
  localparam [15:0] RESULT_LEN_BYTES    = 16'd4;

  localparam [7:0] GPU_MMIO_CONTROL   = 8'h00;
  localparam [31:0] GPU_CTRL_START    = 32'h0000_0001;

  localparam integer ACT_BASE_ADDR = 16;
  localparam integer WGT_BASE_ADDR = 64;
  localparam integer BIAS_BASE_ADDR = 96;
  localparam integer X_OFF = 0;
  localparam integer Y_OFF = 16;

  reg [31:0] cpu_program_rom [0:CPU_PROG_DEPTH-1];
  reg [31:0] gpu_program_rom [0:GPU_PROG_DEPTH-1];
  reg signed [15:0] weight_rom [0:(OUT_DIM*IN_DIM)-1];
  reg signed [15:0] bias_rom [0:OUT_DIM-1];
  reg [63:0] shared_dmem [0:DMEM_DEPTH-1];

  reg [1:0] boot_state;
  reg [8:0] boot_idx;

  reg [2:0] state;
  reg [4:0] feature_load_idx;
  reg [FRAME_WORD_IDX_WIDTH-1:0] replay_word_idx;

  reg [95:0] prev_sw_w_bundle;
  reg [63:0] prev_sw_ifmap_bundle;
  reg        gpu_done_d;

  wire       core_reset;
  wire       cpu_sw_boot_we;
  wire [31:0] cpu_sw_addr_mux;
  wire [31:0] cpu_sw_wdata_mux;
  wire       gpu_imem_prog_we;
  wire [8:0] gpu_imem_prog_addr;
  wire [31:0] gpu_imem_prog_wdata;

  reg  [DATA_WIDTH-1:0] cpu_nw_in_data;
  reg  [CTRL_WIDTH-1:0] cpu_nw_in_ctrl;
  reg                   cpu_nw_in_wr;
  wire                  cpu_nw_in_rdy;

  wire [DATA_WIDTH-1:0] cpu_nw_out_data;
  wire [CTRL_WIDTH-1:0] cpu_nw_out_ctrl;
  wire                  cpu_nw_out_wr;
  wire                  cpu_done_pulse;
  reg                   cpu_ext_continue;

  wire                  cpu_mmio_wr_en;
  wire                  cpu_mmio_rd_en;
  wire [7:0]            cpu_mmio_addr;
  wire [31:0]           cpu_mmio_wdata;
  wire [31:0]           cpu_mmio_rdata;

  reg                   gpu_start_pulse;
  wire                  gpu_mmio_wr_en;
  wire                  gpu_mmio_rd_en;
  wire [7:0]            gpu_mmio_addr;
  wire [31:0]           gpu_mmio_wdata;
  wire [31:0]           gpu_mmio_rdata;

  wire                  gpu_done_level;
  wire                  gpu_done_pulse;
  wire                  gpu_busy;
  wire [15:0]           gpu_dbg_pc;
  wire                  gpu_mem0_en;
  wire                  gpu_mem0_we;
  wire [DMEM_ADDR_WIDTH-1:0] gpu_mem0_addr;
  wire [63:0]           gpu_mem0_wdata;
  reg  [63:0]           gpu_mem0_rdata;
  reg                   gpu_mem0_rvalid;
  wire                  gpu_mem1_en;
  wire                  gpu_mem1_we;
  wire [DMEM_ADDR_WIDTH-1:0] gpu_mem1_addr;
  wire [63:0]           gpu_mem1_wdata;
  reg  [63:0]           gpu_mem1_rdata;
  reg                   gpu_mem1_rvalid;
  reg  [DATA_WIDTH-1:0] replay_frame_word_data;
  reg  [CTRL_WIDTH-1:0] replay_frame_word_ctrl;

  wire [DMEM_ADDR_WIDTH-1:0] debug_addr;
  wire [FRAME_LEN_WIDTH-1:0] frame_word_count;
  integer i;
  integer pc;
  integer replay_byte_offset;
  integer replay_valid_bytes;
  integer replay_lane;

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

  function signed [15:0] default_weight;
    input integer out_idx;
    input integer in_idx;
    begin
      if (out_idx == 0)
        default_weight = ((in_idx % 4) - 1);
      else
        default_weight = (((in_idx + 1) % 5) - 2);
    end
  endfunction

  function signed [15:0] default_bias;
    input integer out_idx;
    begin
      if (out_idx == 0)
        default_bias = 16'sd1;
      else
        default_bias = -16'sd2;
    end
  endfunction

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

  assign core_reset       = reset || (boot_state != BOOT_DONE);
  assign cpu_sw_boot_we   = (boot_state == BOOT_CPU);
  assign cpu_sw_addr_mux  = cpu_sw_boot_we ? (32'h8000_0000 | boot_idx) : sw_i_mem_addr;
  assign cpu_sw_wdata_mux = cpu_sw_boot_we ? cpu_program_rom[boot_idx]   : sw_i_mem_wdata;
  assign gpu_imem_prog_we = (boot_state == BOOT_GPU);
  assign gpu_imem_prog_addr = boot_idx;
  assign gpu_imem_prog_wdata = gpu_program_rom[boot_idx];
  assign gpu_done_pulse   = gpu_done_level && !gpu_done_d;

  assign gpu_mmio_wr_en = gpu_start_pulse ? 1'b1            : cpu_mmio_wr_en;
  assign gpu_mmio_rd_en = gpu_start_pulse ? 1'b0            : cpu_mmio_rd_en;
  assign gpu_mmio_addr  = gpu_start_pulse ? GPU_MMIO_CONTROL: cpu_mmio_addr;
  assign gpu_mmio_wdata = gpu_start_pulse ? GPU_CTRL_START  : cpu_mmio_wdata;

  assign debug_addr = sw_gpu_ofmap_addr[DMEM_ADDR_WIDTH-1:0];
  assign frame_word_count = (frame_len + CTRL_WIDTH - 1) / CTRL_WIDTH;

  always @* begin
    replay_frame_word_data = {DATA_WIDTH{1'b0}};
    replay_frame_word_ctrl = {CTRL_WIDTH{1'b0}};

    replay_byte_offset = replay_word_idx * CTRL_WIDTH;
    replay_valid_bytes = frame_len - replay_byte_offset;
    if (replay_valid_bytes > CTRL_WIDTH)
      replay_valid_bytes = CTRL_WIDTH;
    if (replay_valid_bytes < 0)
      replay_valid_bytes = 0;

    for (replay_lane = 0; replay_lane < CTRL_WIDTH; replay_lane = replay_lane + 1) begin
      if (replay_lane < replay_valid_bytes) begin
        replay_frame_word_data[(DATA_WIDTH - 1) - (replay_lane * 8) -: 8] =
          frame_bytes_flat[((replay_byte_offset + replay_lane) * 8) +: 8];
      end
    end

    if ((replay_word_idx + 1'b1) >= frame_word_count)
      replay_frame_word_ctrl = eop_ctrl(replay_valid_bytes);
  end

  arm_64_top arm_cpu (
    .nw_in_data      (cpu_nw_in_data),
    .nw_in_ctrl      (cpu_nw_in_ctrl),
    .nw_in_wr        (cpu_nw_in_wr),
    .nw_in_rdy       (cpu_nw_in_rdy),
    .nw_out_data     (cpu_nw_out_data),
    .nw_out_ctrl     (cpu_nw_out_ctrl),
    .nw_out_wr       (cpu_nw_out_wr),
    .nw_out_rdy      (1'b1),
    .sw_i_mem_addr   (cpu_sw_addr_mux),
    .sw_i_mem_wdata  (cpu_sw_wdata_mux),
    .sw_d_mem_addr   (sw_d_mem_addr),
    .hw_i_mem_word_out(),
    .hw_d_mem_word_out_0(),
    .hw_d_mem_word_out_1(),
    .ext_mmio_wr_en  (cpu_mmio_wr_en),
    .ext_mmio_rd_en  (cpu_mmio_rd_en),
    .ext_mmio_addr   (cpu_mmio_addr),
    .ext_mmio_wdata  (cpu_mmio_wdata),
    .ext_mmio_rdata  (cpu_mmio_rdata),
    .cpu_done        (cpu_done_pulse),
    .ext_continue    (cpu_ext_continue),
    .ext_drop        (1'b0),
    .clk             (clk),
    .reset           (core_reset)
  );

  gpu_top_fifo_if_copy #(
    .MMIO_ADDR_W(8),
    .IMEM_AW(9),
    .MEM_AW(DMEM_ADDR_WIDTH)
  ) gpu_core (
    .clk            (clk),
    .rst            (core_reset),
    .mmio_wr_en     (gpu_mmio_wr_en),
    .mmio_rd_en     (gpu_mmio_rd_en),
    .mmio_addr      (gpu_mmio_addr),
    .mmio_wdata     (gpu_mmio_wdata),
    .mmio_rdata     (gpu_mmio_rdata),
    .imem_prog_we   (gpu_imem_prog_we),
    .imem_prog_addr (gpu_imem_prog_addr),
    .imem_prog_wdata(gpu_imem_prog_wdata),
    .proc_active    (1'b1),
    .proc_done      (gpu_done_level),
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
    .mem1_rvalid    (gpu_mem1_rvalid),
    .dbg_pc         (gpu_dbg_pc),
    .busy           (gpu_busy)
  );

  initial begin
    for (i = 0; i < CPU_PROG_DEPTH; i = i + 1)
      cpu_program_rom[i] = 32'hE1A00000;
    for (i = 0; i < GPU_PROG_DEPTH; i = i + 1)
      gpu_program_rom[i] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
    for (i = 0; i < OUT_DIM * IN_DIM; i = i + 1)
      weight_rom[i] = default_weight(i / IN_DIM, i % IN_DIM);
    for (i = 0; i < OUT_DIM; i = i + 1)
      bias_rom[i] = default_bias(i);

    cpu_program_rom[0]  = arm_mov_imm(4'd10, 8'h80);
    cpu_program_rom[1]  = arm_mov_imm(4'd0,  8'd0);
    cpu_program_rom[2]  = arm_mov_imm(4'd1,  8'd1);
    cpu_program_rom[3]  = arm_mov_imm(4'd2,  ACT_BASE_ADDR[7:0]);
    cpu_program_rom[4]  = arm_mov_imm(4'd3,  WGT_BASE_ADDR[7:0]);
    cpu_program_rom[5]  = arm_mov_imm(4'd4,  BIAS_BASE_ADDR[7:0]);
    cpu_program_rom[6]  = arm_mov_imm(4'd5,  8'd0);
    cpu_program_rom[7]  = arm_str_imm(4'd0,  4'd10, 12'd8);
    cpu_program_rom[8]  = arm_str_imm(4'd1,  4'd10, 12'd16);
    cpu_program_rom[9]  = arm_str_imm(4'd2,  4'd10, 12'd32);
    cpu_program_rom[10] = arm_str_imm(4'd3,  4'd10, 12'd40);
    cpu_program_rom[11] = arm_str_imm(4'd4,  4'd10, 12'd48);
    cpu_program_rom[12] = arm_str_imm(4'd5,  4'd10, 12'd56);

    pc = 0;
    for (i = 0; i < OUT_DIM; i = i + 1) begin
      integer in_idx;
      gpu_program_rom[pc] = gpu_instr(4'h1, 3'd6, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
      pc = pc + 1;

      for (in_idx = 0; in_idx < IN_DIM; in_idx = in_idx + 1) begin
        gpu_program_rom[pc] = gpu_instr(4'h2, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, X_OFF + in_idx);
        pc = pc + 1;
        gpu_program_rom[pc] = gpu_instr(4'h2, 3'd1, 3'd0, 3'd0, 2'b01, 1'b0, (i * IN_DIM) + in_idx);
        pc = pc + 1;
        gpu_program_rom[pc] = gpu_instr(4'hC, 3'd6, 3'd0, 3'd1, 2'b00, 1'b0, 16'h0000);
        pc = pc + 1;
      end

      gpu_program_rom[pc] = gpu_instr(4'h2, 3'd2, 3'd0, 3'd0, 2'b10, 1'b0, i);
      pc = pc + 1;
      gpu_program_rom[pc] = gpu_instr(4'h4, 3'd6, 3'd6, 3'd2, 2'b00, 1'b0, 16'h0000);
      pc = pc + 1;
      gpu_program_rom[pc] = gpu_instr(4'h3, 3'd0, 3'd0, 3'd6, 2'b00, 1'b0, Y_OFF + i);
      pc = pc + 1;
    end
    gpu_program_rom[pc] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'h0000);
  end

  always @(posedge clk or posedge reset) begin
    integer mem_idx;
    if (reset) begin
      boot_state          <= BOOT_CPU;
      boot_idx            <= 9'd0;
      state               <= ST_IDLE;
      feature_load_idx    <= 5'd0;
      replay_word_idx     <= {FRAME_WORD_IDX_WIDTH{1'b0}};
      done                <= 1'b0;
      result_status       <= RESULT_STATUS_OK;
      result_type         <= RESULT_TYPE_NN;
      result_len          <= RESULT_LEN_BYTES;
      result_data_0       <= 16'd0;
      result_data_1       <= 16'd0;
      hw_gpu_ofmap_data_0 <= 32'd0;
      hw_gpu_ofmap_data_1 <= 32'd0;
      cpu_nw_in_data      <= {DATA_WIDTH{1'b0}};
      cpu_nw_in_ctrl      <= {CTRL_WIDTH{1'b0}};
      cpu_nw_in_wr        <= 1'b0;
      cpu_ext_continue    <= 1'b0;
      gpu_start_pulse     <= 1'b0;
      gpu_done_d          <= 1'b0;
      gpu_mem0_rdata      <= 64'd0;
      gpu_mem1_rdata      <= 64'd0;
      gpu_mem0_rvalid     <= 1'b0;
      gpu_mem1_rvalid     <= 1'b0;
      prev_sw_w_bundle    <= 96'd0;
      prev_sw_ifmap_bundle <= 64'd0;
      for (mem_idx = 0; mem_idx < DMEM_DEPTH; mem_idx = mem_idx + 1)
        shared_dmem[mem_idx] <= 64'd0;
      for (mem_idx = 0; mem_idx < OUT_DIM * IN_DIM; mem_idx = mem_idx + 1)
        shared_dmem[WGT_BASE_ADDR + mem_idx] <= {48'd0, weight_rom[mem_idx]};
      for (mem_idx = 0; mem_idx < OUT_DIM; mem_idx = mem_idx + 1)
        shared_dmem[BIAS_BASE_ADDR + mem_idx] <= {48'd0, bias_rom[mem_idx]};
    end
    else begin
      done             <= 1'b0;
      cpu_nw_in_wr     <= 1'b0;
      cpu_ext_continue <= 1'b0;
      gpu_start_pulse  <= 1'b0;
      gpu_mem0_rvalid  <= 1'b0;
      gpu_mem1_rvalid  <= 1'b0;
      gpu_done_d       <= gpu_done_level;

      hw_gpu_ofmap_data_0 <= shared_dmem[debug_addr][31:0];
      hw_gpu_ofmap_data_1 <= shared_dmem[debug_addr][63:32];

      prev_sw_w_bundle     <= {sw_gpu_w_mem_addr, sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0};
      prev_sw_ifmap_bundle <= {sw_gpu_ifmap_addr, sw_gpu_ifmap_wdata};

      if ((boot_state == BOOT_DONE) &&
          sw_gpu_w_mem_addr[31] &&
          ({sw_gpu_w_mem_addr, sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0} != prev_sw_w_bundle)) begin
        shared_dmem[sw_gpu_w_mem_addr[DMEM_ADDR_WIDTH-1:0]] <=
          {sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0};
      end

      if ((boot_state == BOOT_DONE) &&
          sw_gpu_ifmap_addr[31] &&
          ({sw_gpu_ifmap_addr, sw_gpu_ifmap_wdata} != prev_sw_ifmap_bundle)) begin
        shared_dmem[sw_gpu_ifmap_addr[DMEM_ADDR_WIDTH-1:0]] <=
          {32'd0, sw_gpu_ifmap_wdata};
      end

      if (gpu_mem0_en) begin
        if (gpu_mem0_we) begin
          shared_dmem[gpu_mem0_addr] <= gpu_mem0_wdata;
        end
        else begin
          gpu_mem0_rdata  <= shared_dmem[gpu_mem0_addr];
          gpu_mem0_rvalid <= 1'b1;
        end
      end

      if (gpu_mem1_en) begin
        if (gpu_mem1_we) begin
          shared_dmem[gpu_mem1_addr] <= gpu_mem1_wdata;
        end
        else begin
          gpu_mem1_rdata  <= shared_dmem[gpu_mem1_addr];
          gpu_mem1_rvalid <= 1'b1;
        end
      end

      case (boot_state)
        BOOT_CPU: begin
          if (boot_idx + 9'd1 >= CPU_PROG_LEN) begin
            boot_state <= BOOT_GPU;
            boot_idx   <= 9'd0;
          end
          else begin
            boot_idx <= boot_idx + 9'd1;
          end
        end

        BOOT_GPU: begin
          if (boot_idx + 9'd1 >= GPU_PROG_LEN) begin
            boot_state <= BOOT_DONE;
            boot_idx   <= 9'd0;
          end
          else begin
            boot_idx <= boot_idx + 9'd1;
          end
        end

        default: begin
        end
      endcase

      if (boot_state == BOOT_DONE) begin
        case (state)
          ST_IDLE: begin
            if (start) begin
              feature_load_idx <= 5'd0;
              replay_word_idx  <= {FRAME_WORD_IDX_WIDTH{1'b0}};
              result_type      <= RESULT_TYPE_NN;
              result_len       <= RESULT_LEN_BYTES;
              result_status    <= (feature_count == IN_DIM) ? RESULT_STATUS_OK : RESULT_STATUS_TRUNC;
              state            <= ST_LOAD_FEATURE;
            end
          end

          ST_LOAD_FEATURE: begin
            if (feature_load_idx < IN_DIM) begin
              if (feature_load_idx < feature_count)
                shared_dmem[ACT_BASE_ADDR + X_OFF + feature_load_idx] <=
                  {48'd0, features_flat[(feature_load_idx * 16) +: 16]};
              else
                shared_dmem[ACT_BASE_ADDR + X_OFF + feature_load_idx] <= 64'd0;
              feature_load_idx <= feature_load_idx + 5'd1;
            end
            else begin
              shared_dmem[ACT_BASE_ADDR + Y_OFF + 0] <= 64'd0;
              shared_dmem[ACT_BASE_ADDR + Y_OFF + 1] <= 64'd0;
              state <= ST_SEND_MODULE_HDR;
            end
          end

          ST_SEND_MODULE_HDR: begin
            cpu_nw_in_data <= module_header_word;
            cpu_nw_in_ctrl <= 8'hff;
            cpu_nw_in_wr   <= 1'b1;
            if (cpu_nw_in_rdy) begin
              replay_word_idx <= {FRAME_WORD_IDX_WIDTH{1'b0}};
              state <= ST_SEND_FRAME_WORDS;
            end
          end

          ST_SEND_FRAME_WORDS: begin
            cpu_nw_in_data <= replay_frame_word_data;
            cpu_nw_in_ctrl <= replay_frame_word_ctrl;
            cpu_nw_in_wr   <= 1'b1;
            if (cpu_nw_in_rdy) begin
              if ((replay_word_idx + 1'b1) >= frame_word_count)
                state <= ST_WAIT_CPU;
              else
                replay_word_idx <= replay_word_idx + 1'b1;
            end
          end

          ST_WAIT_CPU: begin
            if (cpu_done_pulse) begin
              gpu_start_pulse <= 1'b1;
              state <= ST_WAIT_GPU;
            end
          end

          ST_WAIT_GPU: begin
            if (gpu_done_pulse)
              state <= ST_CAPTURE;
          end

          ST_CAPTURE: begin
            result_data_0    <= shared_dmem[ACT_BASE_ADDR + Y_OFF + 0][15:0];
            result_data_1    <= shared_dmem[ACT_BASE_ADDR + Y_OFF + 1][15:0];
            cpu_ext_continue <= 1'b1;
            done             <= 1'b1;
            state            <= ST_IDLE;
          end

          default: begin
            state <= ST_IDLE;
          end
        endcase
      end
    end
  end

endmodule
