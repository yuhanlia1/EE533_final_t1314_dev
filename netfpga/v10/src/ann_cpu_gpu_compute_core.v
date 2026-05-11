`timescale 1ns/1ps

module ann_cpu_gpu_compute_core #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter FRAME_LEN_WIDTH = 12,
  parameter FRAME_WORD_ADDR_WIDTH = 8,
  parameter DMEM_DEPTH = 16384,
  parameter DMEM_ADDR_WIDTH = 14,
  parameter FEATURE_WINDOW_WORDS = 1024,
  parameter OUT_DIM = 2,
  parameter GPU_PC_WIDTH = 16,
  parameter GPU_IMEM_PROG_ADDR_WIDTH = 16,
  parameter GPU_IMEM_ADDR_WIDTH = 12,
  parameter GPU_IMEM_DEPTH = 4096
) (
  input                           clk,
  input                           reset,
  input                           start,
  input  [DATA_WIDTH-1:0]         module_header_word,
  input  [FRAME_LEN_WIDTH-1:0]    frame_len,
  input  [FRAME_WORD_ADDR_WIDTH:0] frame_word_count,
  output reg [FRAME_WORD_ADDR_WIDTH-1:0] frame_rd_addr,
  input  [DATA_WIDTH+CTRL_WIDTH-1:0] frame_rd_word,
  input  [15:0]                   task_type,
  input  [15:0]                   feature_count,
  input                           feature_wr_en,
  input  [15:0]                   feature_wr_addr,
  input  [15:0]                   feature_wr_data,

  input  [31:0]                   sw_i_mem_addr,
  input  [31:0]                   sw_i_mem_wdata,
  input  [31:0]                   sw_d_mem_addr,
  input  [31:0]                   sw_gpu_i_mem_addr,
  input  [31:0]                   sw_gpu_i_mem_wdata,
  input  [31:0]                   sw_gpu_w_mem_addr,
  input  [31:0]                   sw_gpu_w_mem_wdata_0,
  input  [31:0]                   sw_gpu_w_mem_wdata_1,
  input  [31:0]                   sw_gpu_ofmap_addr,
  input  [31:0]                   sw_engine_ctrl,

  output reg                      done,
  output reg [7:0]                result_status,
  output reg [15:0]               result_type,
  output reg [15:0]               result_len,
  output reg [15:0]               result_data_0,
  output reg [15:0]               result_data_1,
  output reg [31:0]               hw_gpu_ofmap_data_0,
  output reg [31:0]               hw_gpu_ofmap_data_1,
  output     [31:0]               hw_cpu_i_mem_word_out,
  output     [31:0]               hw_cpu_d_mem_word_out_0,
  output     [31:0]               hw_cpu_d_mem_word_out_1,
  output     [31:0]               hw_engine_status
);

  localparam [3:0] ST_IDLE            = 4'd0;
  localparam [3:0] ST_TASK_RESET      = 4'd1;
  localparam [3:0] ST_CLEAR_FEATURES  = 4'd2;
  localparam [3:0] ST_SEND_MODULE_HDR = 4'd3;
  localparam [3:0] ST_REPLAY_REQ      = 4'd4;
  localparam [3:0] ST_REPLAY_WAIT     = 4'd5;
  localparam [3:0] ST_REPLAY_SEND     = 4'd6;
  localparam [3:0] ST_WAIT_CPU        = 4'd7;
  localparam [3:0] ST_WAIT_GPU        = 4'd8;
  localparam [3:0] ST_CAPTURE_REQ     = 4'd9;
  localparam [3:0] ST_CAPTURE_RESP    = 4'd10;

  localparam [7:0]  RESULT_STATUS_OK        = 8'h00;
  localparam [7:0]  RESULT_STATUS_NOT_READY = 8'h06;
  localparam [15:0] RESULT_TYPE_NONE        = 16'h0000;
  localparam [15:0] RESULT_TYPE_NN          = 16'h0002;
  localparam [15:0] RESULT_LEN_NONE         = 16'd0;
  localparam [15:0] RESULT_LEN_BYTES        = 16'd4;

  localparam [7:0]  GPU_MMIO_CONTROL      = 8'h00;
  localparam [31:0] GPU_CTRL_START        = 32'h0000_0001;
  localparam [31:0] GPU_CTRL_SOFT_RESET   = 32'h0000_0004;
  localparam [DMEM_ADDR_WIDTH-1:0] ACT_BASE_ADDR = 14'd128;
  localparam [DMEM_ADDR_WIDTH-1:0] LEGACY_RESULT_OFFSET = 14'd800;
  localparam [DMEM_ADDR_WIDTH-1:0] DEFAULT_CAPTURE_BASE_ADDR = ACT_BASE_ADDR + LEGACY_RESULT_OFFSET;
  localparam [DMEM_ADDR_WIDTH-1:0] DMEM_ADDR_ONE  = {{(DMEM_ADDR_WIDTH-1){1'b0}}, 1'b1};
  localparam [15:0] LEGACY_CAPTURE_COUNT = 16'd2;
  localparam [15:0] DEFAULT_COMPACT_CAPTURE_COUNT = OUT_DIM;

  reg [3:0] state;
  reg [FRAME_WORD_ADDR_WIDTH-1:0] replay_word_idx;
  reg [1:0] task_reset_cycles;
  reg [15:0] feature_clear_idx;
  reg [15:0] capture_index;
  reg [15:0] legacy_capture_0;
  reg [15:0] legacy_capture_1;
  reg        capture_best_valid;
  reg [15:0] capture_best_class;
  reg [15:0] capture_best_word;

  reg [63:0] prev_cpu_prog_bundle;
  reg [63:0] prev_gpu_imem_bundle;
  reg        prev_sw_param_addr_we;
  reg        gpu_done_d;
  reg        gpu_core_reset;
  reg        dmem_debug_pending;

  reg        cpu_programmed;
  reg        gpu_programmed;
  reg        param_programmed;
  reg        pending_param_valid;
  reg  [DMEM_ADDR_WIDTH-1:0] pending_param_addr;
  reg  [63:0]                pending_param_wdata;
  reg                        cfg_compact_result_enable;
  reg  [15:0]               cfg_capture_last_index;
  reg  [DMEM_ADDR_WIDTH-1:0] cfg_capture_base_addr;
  reg  [DMEM_ADDR_WIDTH-1:0] capture_req_addr;

  wire       engine_enable;
  wire       engine_ready;
  wire       cpu_core_reset;
  wire       task_reset_active;
  wire       dmem_gpu_active;

  wire       cpu_sw_prog_we;
  wire [31:0] cpu_sw_addr_mux;
  wire [31:0] cpu_sw_wdata_mux;

  wire       gpu_imem_prog_we;
  wire [GPU_IMEM_PROG_ADDR_WIDTH-1:0] gpu_imem_prog_addr;
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
  wire [31:0]           cpu_hw_i_mem_word_out;
  wire [31:0]           cpu_hw_d_mem_word_out_0;
  wire [31:0]           cpu_hw_d_mem_word_out_1;

  reg                   gpu_reset_pulse;
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
  wire [63:0]           gpu_mem0_rdata;
  wire                  gpu_mem0_rvalid;
  wire                  gpu_mem1_en;
  wire                  gpu_mem1_we;
  wire [DMEM_ADDR_WIDTH-1:0] gpu_mem1_addr;
  wire [63:0]           gpu_mem1_wdata;
  wire [63:0]           gpu_mem1_rdata;
  wire                  gpu_mem1_rvalid;

  wire [DMEM_ADDR_WIDTH-1:0] debug_addr;
  wire                  sw_param_commit;
  wire                  pending_param_issue;
  wire                  feature_wr_in_range;
  wire                  feature_clear_active;
  wire [DMEM_ADDR_WIDTH-1:0] feature_wr_dmem_addr;
  wire [DMEM_ADDR_WIDTH-1:0] feature_clear_addr;
  wire [63:0]           feature_wr_dmem_wdata;
  wire                  dmem_debug_issue;
  wire [7:0]            requested_output_count;
  wire [15:0]           requested_output_base;
  wire [15:0]           requested_capture_count;
  wire [15:0]           requested_capture_last_index;
  wire [DMEM_ADDR_WIDTH-1:0] requested_capture_base_addr;

  reg                   dmem_a_en;
  reg                   dmem_a_we;
  reg  [DMEM_ADDR_WIDTH-1:0] dmem_a_addr;
  reg  [63:0]           dmem_a_wdata;
  wire [63:0]           dmem_a_rdata;
  wire                  dmem_a_rvalid;
  reg                   dmem_b_en;
  reg                   dmem_b_we;
  reg  [DMEM_ADDR_WIDTH-1:0] dmem_b_addr;
  reg  [63:0]           dmem_b_wdata;
  wire [63:0]           dmem_b_rdata;
  wire                  dmem_b_rvalid;

  assign engine_enable   = sw_engine_ctrl[0];
  assign engine_ready    = engine_enable && cpu_programmed && gpu_programmed && param_programmed;
  assign task_reset_active = (state == ST_TASK_RESET);
  assign cpu_core_reset  = reset || !engine_ready || task_reset_active;
  assign dmem_gpu_active = (state == ST_WAIT_GPU);

  assign cpu_sw_prog_we   = sw_i_mem_addr[31] &&
                            ({sw_i_mem_addr, sw_i_mem_wdata} != prev_cpu_prog_bundle);
  assign cpu_sw_addr_mux  = cpu_sw_prog_we ? sw_i_mem_addr :
                            (sw_i_mem_addr[30] ? sw_i_mem_addr : 32'd0);
  assign cpu_sw_wdata_mux = sw_i_mem_wdata;

  assign gpu_imem_prog_we    = sw_gpu_i_mem_addr[31] &&
                               ({sw_gpu_i_mem_addr, sw_gpu_i_mem_wdata} != prev_gpu_imem_bundle);
  assign gpu_imem_prog_addr  = sw_gpu_i_mem_addr[GPU_IMEM_PROG_ADDR_WIDTH-1:0];
  assign gpu_imem_prog_wdata = sw_gpu_i_mem_wdata;

  assign gpu_done_pulse = gpu_done_level && !gpu_done_d;
  assign gpu_mmio_wr_en = gpu_start_pulse ? 1'b1              :
                          gpu_reset_pulse ? 1'b1              :
                                            cpu_mmio_wr_en;
  assign gpu_mmio_rd_en = (gpu_start_pulse || gpu_reset_pulse) ? 1'b0 :
                                                              cpu_mmio_rd_en;
  assign gpu_mmio_addr  = (gpu_start_pulse || gpu_reset_pulse) ? GPU_MMIO_CONTROL :
                                                              cpu_mmio_addr;
  assign gpu_mmio_wdata = gpu_start_pulse ? GPU_CTRL_START      :
                          gpu_reset_pulse ? GPU_CTRL_SOFT_RESET :
                                            cpu_mmio_wdata;
  assign cpu_mmio_rdata = gpu_mmio_rdata;

  assign debug_addr = sw_gpu_ofmap_addr[DMEM_ADDR_WIDTH-1:0];
  assign sw_param_commit = sw_gpu_w_mem_addr[31] && !prev_sw_param_addr_we;
  assign feature_wr_in_range = (feature_wr_addr < FEATURE_WINDOW_WORDS);
  assign feature_clear_active = (state == ST_CLEAR_FEATURES) && (feature_clear_idx < FEATURE_WINDOW_WORDS);
  assign feature_wr_dmem_addr = ACT_BASE_ADDR + feature_wr_addr[DMEM_ADDR_WIDTH-1:0];
  assign feature_clear_addr = ACT_BASE_ADDR + feature_clear_idx[DMEM_ADDR_WIDTH-1:0];
  assign feature_wr_dmem_wdata = {48'd0, feature_wr_data};
  assign requested_output_count = sw_engine_ctrl[15:8];
  assign requested_output_base = sw_engine_ctrl[31:16];
  assign requested_capture_count = sw_engine_ctrl[1]
                                 ? ((requested_output_count != 8'd0)
                                     ? {8'd0, requested_output_count}
                                     : DEFAULT_COMPACT_CAPTURE_COUNT)
                                 : LEGACY_CAPTURE_COUNT;
  assign requested_capture_last_index = (requested_capture_count <= 16'd1)
                                      ? 16'd0
                                      : (requested_capture_count - 16'd1);
  assign requested_capture_base_addr = (requested_output_base != 16'd0)
                                     ? requested_output_base[DMEM_ADDR_WIDTH-1:0]
                                     : DEFAULT_CAPTURE_BASE_ADDR;
  assign pending_param_issue = pending_param_valid &&
                               !dmem_gpu_active &&
                               (state != ST_CAPTURE_REQ) &&
                               !feature_clear_active &&
                               !(feature_wr_en && feature_wr_in_range);
  assign dmem_debug_issue = !dmem_gpu_active &&
                            (state != ST_CLEAR_FEATURES) &&
                            (state != ST_CAPTURE_REQ) &&
                            !(feature_wr_en && feature_wr_in_range) &&
                            !pending_param_valid;
  assign hw_engine_status = {27'd0, gpu_busy, param_programmed, gpu_programmed, cpu_programmed, engine_ready};
  assign hw_cpu_i_mem_word_out = cpu_hw_i_mem_word_out;
  assign hw_cpu_d_mem_word_out_0 = cpu_hw_d_mem_word_out_0;
  assign hw_cpu_d_mem_word_out_1 = cpu_hw_d_mem_word_out_1;
  assign gpu_mem0_rdata = dmem_gpu_active ? dmem_a_rdata : 64'd0;
  assign gpu_mem0_rvalid = dmem_gpu_active ? dmem_a_rvalid : 1'b0;
  assign gpu_mem1_rdata = dmem_gpu_active ? dmem_b_rdata : 64'd0;
  assign gpu_mem1_rvalid = dmem_gpu_active ? dmem_b_rvalid : 1'b0;

  always @(*) begin
    dmem_a_en    = 1'b0;
    dmem_a_we    = 1'b0;
    dmem_a_addr  = {DMEM_ADDR_WIDTH{1'b0}};
    dmem_a_wdata = 64'd0;
    dmem_b_en    = 1'b0;
    dmem_b_we    = 1'b0;
    dmem_b_addr  = {DMEM_ADDR_WIDTH{1'b0}};
    dmem_b_wdata = 64'd0;

    if (dmem_gpu_active) begin
      dmem_a_en    = gpu_mem0_en;
      dmem_a_we    = gpu_mem0_we;
      dmem_a_addr  = gpu_mem0_addr;
      dmem_a_wdata = gpu_mem0_wdata;
      dmem_b_en    = gpu_mem1_en;
      dmem_b_we    = gpu_mem1_we;
      dmem_b_addr  = gpu_mem1_addr;
      dmem_b_wdata = gpu_mem1_wdata;
    end
    else if (state == ST_CAPTURE_REQ) begin
      dmem_a_en   = 1'b1;
      dmem_a_addr = capture_req_addr;
    end
    else if (feature_clear_active) begin
      dmem_a_en    = 1'b1;
      dmem_a_we    = 1'b1;
      dmem_a_addr  = feature_clear_addr;
      dmem_a_wdata = 64'd0;
    end
    else if (feature_wr_en && feature_wr_in_range) begin
      dmem_a_en    = 1'b1;
      dmem_a_we    = 1'b1;
      dmem_a_addr  = feature_wr_dmem_addr;
      dmem_a_wdata = feature_wr_dmem_wdata;
    end
    else if (pending_param_valid) begin
      dmem_a_en    = 1'b1;
      dmem_a_we    = 1'b1;
      dmem_a_addr  = pending_param_addr;
      dmem_a_wdata = pending_param_wdata;
    end
    else begin
      dmem_a_en   = 1'b1;
      dmem_a_addr = debug_addr;
    end
  end

  gpu_shared_dmem #(
    .ADDR_WIDTH(DMEM_ADDR_WIDTH),
    .DATA_WIDTH(64),
    .DEPTH(DMEM_DEPTH)
  ) u_shared_dmem (
    .clk    (clk),
    .a_en   (dmem_a_en),
    .a_we   (dmem_a_we),
    .a_addr (dmem_a_addr),
    .a_wdata(dmem_a_wdata),
    .a_rdata(dmem_a_rdata),
    .a_rvalid(dmem_a_rvalid),
    .b_en   (dmem_b_en),
    .b_we   (dmem_b_we),
    .b_addr (dmem_b_addr),
    .b_wdata(dmem_b_wdata),
    .b_rdata(dmem_b_rdata),
    .b_rvalid(dmem_b_rvalid)
  );

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
    .hw_i_mem_word_out(cpu_hw_i_mem_word_out),
    .hw_d_mem_word_out_0(cpu_hw_d_mem_word_out_0),
    .hw_d_mem_word_out_1(cpu_hw_d_mem_word_out_1),
    .ext_mmio_wr_en  (cpu_mmio_wr_en),
    .ext_mmio_rd_en  (cpu_mmio_rd_en),
    .ext_mmio_addr   (cpu_mmio_addr),
    .ext_mmio_wdata  (cpu_mmio_wdata),
    .ext_mmio_rdata  (cpu_mmio_rdata),
    .cpu_done        (cpu_done_pulse),
    .ext_continue    (cpu_ext_continue),
    .ext_drop        (1'b0),
    .clk             (clk),
    .reset           (cpu_core_reset)
  );

  gpu_top_fifo_if #(
    .MMIO_ADDR_W(8),
    .PC_W(GPU_PC_WIDTH),
    .IMEM_PROG_ADDR_W(GPU_IMEM_PROG_ADDR_WIDTH),
    .IMEM_ADDR_W(GPU_IMEM_ADDR_WIDTH),
    .IMEM_DEPTH(GPU_IMEM_DEPTH),
    .MEM_AW(DMEM_ADDR_WIDTH)
  ) gpu_core (
    .clk            (clk),
    .rst            (gpu_core_reset),
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

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state                <= ST_IDLE;
      replay_word_idx      <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      task_reset_cycles    <= 2'd0;
      feature_clear_idx    <= 16'd0;
      capture_index        <= 16'd0;
      legacy_capture_0     <= 16'd0;
      legacy_capture_1     <= 16'd0;
      capture_best_valid   <= 1'b0;
      capture_best_class   <= 16'd0;
      capture_best_word    <= 16'd0;
      frame_rd_addr        <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      done                 <= 1'b0;
      result_status        <= RESULT_STATUS_OK;
      result_type          <= RESULT_TYPE_NN;
      result_len           <= RESULT_LEN_BYTES;
      result_data_0        <= 16'd0;
      result_data_1        <= 16'd0;
      hw_gpu_ofmap_data_0  <= 32'd0;
      hw_gpu_ofmap_data_1  <= 32'd0;
      cpu_nw_in_data       <= {DATA_WIDTH{1'b0}};
      cpu_nw_in_ctrl       <= {CTRL_WIDTH{1'b0}};
      cpu_nw_in_wr         <= 1'b0;
      cpu_ext_continue     <= 1'b0;
      gpu_reset_pulse      <= 1'b0;
      gpu_start_pulse      <= 1'b0;
      gpu_done_d           <= 1'b0;
      gpu_core_reset       <= 1'b1;
      dmem_debug_pending   <= 1'b0;
      prev_cpu_prog_bundle <= 64'd0;
      prev_gpu_imem_bundle <= 64'd0;
      prev_sw_param_addr_we <= 1'b0;
      cpu_programmed       <= 1'b0;
      gpu_programmed       <= 1'b0;
      param_programmed     <= 1'b0;
      pending_param_valid  <= 1'b0;
      pending_param_addr   <= {DMEM_ADDR_WIDTH{1'b0}};
      pending_param_wdata  <= 64'd0;
      cfg_compact_result_enable <= 1'b0;
      cfg_capture_last_index <= LEGACY_CAPTURE_COUNT - 16'd1;
      cfg_capture_base_addr <= DEFAULT_CAPTURE_BASE_ADDR;
      capture_req_addr <= DEFAULT_CAPTURE_BASE_ADDR;
    end
    else begin
      done             <= 1'b0;
      cpu_nw_in_wr     <= 1'b0;
      cpu_ext_continue <= 1'b0;
      gpu_reset_pulse  <= 1'b0;
      gpu_start_pulse  <= 1'b0;
      gpu_done_d       <= gpu_done_level;
      gpu_core_reset   <= !engine_ready || task_reset_active;
      dmem_debug_pending <= dmem_debug_issue;

      prev_cpu_prog_bundle <= {sw_i_mem_addr, sw_i_mem_wdata};
      prev_gpu_imem_bundle <= {sw_gpu_i_mem_addr, sw_gpu_i_mem_wdata};
      prev_sw_param_addr_we <= sw_gpu_w_mem_addr[31];

      if (dmem_debug_pending) begin
        hw_gpu_ofmap_data_0 <= dmem_a_rdata[31:0];
        hw_gpu_ofmap_data_1 <= dmem_a_rdata[63:32];
      end

      if (cpu_sw_prog_we)
        cpu_programmed <= 1'b1;

      if (gpu_imem_prog_we)
        gpu_programmed <= 1'b1;

      if (pending_param_issue) begin
        pending_param_valid <= 1'b0;
        param_programmed <= 1'b1;
      end

      if (sw_param_commit) begin
        pending_param_valid <= 1'b1;
        pending_param_addr  <= sw_gpu_w_mem_addr[DMEM_ADDR_WIDTH-1:0];
        pending_param_wdata <= {sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0};
      end

      case (state)
        ST_IDLE: begin
          if (start) begin
            replay_word_idx    <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            frame_rd_addr      <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            feature_clear_idx  <= feature_count;
            capture_index      <= 16'd0;
            legacy_capture_0   <= 16'd0;
            legacy_capture_1   <= 16'd0;
            capture_best_valid <= 1'b0;
            capture_best_class <= 16'd0;
            capture_best_word  <= 16'd0;
            if (!engine_ready) begin
              result_status <= RESULT_STATUS_NOT_READY;
              result_type   <= RESULT_TYPE_NONE;
              result_len    <= RESULT_LEN_NONE;
              result_data_0 <= 16'd0;
              result_data_1 <= 16'd0;
              done          <= 1'b1;
            end
            else begin
              gpu_done_d        <= 1'b0;
              task_reset_cycles <= 2'd2;
              result_status     <= RESULT_STATUS_OK;
              result_type       <= RESULT_TYPE_NN;
              result_len        <= RESULT_LEN_BYTES;
              cfg_compact_result_enable <= sw_engine_ctrl[1];
              cfg_capture_last_index <= requested_capture_last_index;
              cfg_capture_base_addr <= requested_capture_base_addr;
              capture_req_addr <= requested_capture_base_addr;
              state             <= ST_TASK_RESET;
            end
          end
        end

        ST_TASK_RESET: begin
          if (task_reset_cycles != 2'd0) begin
            task_reset_cycles <= task_reset_cycles - 2'd1;
          end
          else begin
            gpu_reset_pulse <= 1'b1;
            if (feature_count < FEATURE_WINDOW_WORDS)
              state <= ST_CLEAR_FEATURES;
            else
              state <= ST_SEND_MODULE_HDR;
          end
        end

        ST_CLEAR_FEATURES: begin
          if ((feature_clear_idx + 16'd1) >= FEATURE_WINDOW_WORDS) begin
            state <= ST_SEND_MODULE_HDR;
          end
          feature_clear_idx <= feature_clear_idx + 16'd1;
        end

        ST_SEND_MODULE_HDR: begin
          cpu_nw_in_data <= module_header_word;
          cpu_nw_in_ctrl <= 8'hff;
          cpu_nw_in_wr   <= 1'b1;
          if (cpu_nw_in_rdy) begin
            replay_word_idx <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            state           <= ST_REPLAY_REQ;
          end
        end

        ST_REPLAY_REQ: begin
          frame_rd_addr <= replay_word_idx;
          state         <= ST_REPLAY_WAIT;
        end

        ST_REPLAY_WAIT: begin
          state <= ST_REPLAY_SEND;
        end

        ST_REPLAY_SEND: begin
          cpu_nw_in_data <= frame_rd_word[DATA_WIDTH-1:0];
          cpu_nw_in_ctrl <= frame_rd_word[DATA_WIDTH+CTRL_WIDTH-1:DATA_WIDTH];
          cpu_nw_in_wr   <= 1'b1;
          if (cpu_nw_in_rdy) begin
            if ((replay_word_idx + {{(FRAME_WORD_ADDR_WIDTH-1){1'b0}}, 1'b1}) >= frame_word_count)
              state <= ST_WAIT_CPU;
            else begin
              replay_word_idx <= replay_word_idx + {{(FRAME_WORD_ADDR_WIDTH-1){1'b0}}, 1'b1};
              state           <= ST_REPLAY_REQ;
            end
          end
        end

        ST_WAIT_CPU: begin
          if (cpu_done_pulse) begin
            gpu_start_pulse <= 1'b1;
            state           <= ST_WAIT_GPU;
          end
        end

        ST_WAIT_GPU: begin
          if (gpu_done_pulse) begin
            capture_index      <= 16'd0;
            legacy_capture_0   <= 16'd0;
            legacy_capture_1   <= 16'd0;
            capture_best_valid <= 1'b0;
            capture_best_class <= 16'd0;
            capture_best_word  <= 16'd0;
            capture_req_addr   <= cfg_capture_base_addr;
            state              <= ST_CAPTURE_REQ;
          end
        end

        ST_CAPTURE_REQ: begin
          state <= ST_CAPTURE_RESP;
        end

        ST_CAPTURE_RESP: begin
          if (dmem_a_rvalid) begin
            if (cfg_compact_result_enable) begin
              if (!capture_best_valid || ($signed(dmem_a_rdata[15:0]) > $signed(capture_best_word))) begin
                capture_best_valid <= 1'b1;
                capture_best_class <= capture_index;
                capture_best_word  <= dmem_a_rdata[15:0];
              end
            end
            else begin
              if (capture_index == 16'd0)
                legacy_capture_0 <= dmem_a_rdata[15:0];
              else if (capture_index == 16'd1)
                legacy_capture_1 <= dmem_a_rdata[15:0];
            end

            if (capture_index >= cfg_capture_last_index) begin
              if (cfg_compact_result_enable) begin
                if (!capture_best_valid || ($signed(dmem_a_rdata[15:0]) > $signed(capture_best_word))) begin
                  result_data_0 <= capture_index;
                  result_data_1 <= dmem_a_rdata[15:0];
                end
                else begin
                  result_data_0 <= capture_best_class;
                  result_data_1 <= capture_best_word;
                end
              end
              else begin
                result_data_0 <= (capture_index == 16'd0) ? dmem_a_rdata[15:0] : legacy_capture_0;
                result_data_1 <= (capture_index == 16'd0) ? 16'd0            : dmem_a_rdata[15:0];
              end
              cpu_ext_continue <= 1'b1;
              done             <= 1'b1;
              state            <= ST_IDLE;
            end
            else begin
              capture_index <= capture_index + 16'd1;
              capture_req_addr <= capture_req_addr + DMEM_ADDR_ONE;
              state         <= ST_CAPTURE_REQ;
            end
          end
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
