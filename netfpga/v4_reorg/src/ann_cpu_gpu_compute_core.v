`timescale 1ns/1ps

module ann_cpu_gpu_compute_core #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter FRAME_LEN_WIDTH = 12,
  parameter FRAME_WORD_ADDR_WIDTH = 8,
  parameter DMEM_DEPTH = 256,
  parameter DMEM_ADDR_WIDTH = 8,
  parameter IN_DIM = 8,
  parameter OUT_DIM = 2
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
  input  [15:0]                   feature_data_0,
  input  [15:0]                   feature_data_1,
  input  [15:0]                   feature_data_2,
  input  [15:0]                   feature_data_3,
  input  [15:0]                   feature_data_4,
  input  [15:0]                   feature_data_5,
  input  [15:0]                   feature_data_6,
  input  [15:0]                   feature_data_7,

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
  output     [31:0]               hw_engine_status
);

  localparam [3:0] ST_IDLE            = 4'd0;
  localparam [3:0] ST_TASK_RESET      = 4'd1;
  localparam [3:0] ST_LOAD_FEATURE    = 4'd2;
  localparam [3:0] ST_SEND_MODULE_HDR = 4'd3;
  localparam [3:0] ST_REPLAY_REQ      = 4'd4;
  localparam [3:0] ST_REPLAY_WAIT     = 4'd5;
  localparam [3:0] ST_REPLAY_SEND     = 4'd6;
  localparam [3:0] ST_WAIT_CPU        = 4'd7;
  localparam [3:0] ST_WAIT_GPU        = 4'd8;
  localparam [3:0] ST_CAPTURE_REQ     = 4'd9;
  localparam [3:0] ST_CAPTURE         = 4'd10;

  localparam [7:0]  RESULT_STATUS_OK        = 8'h00;
  localparam [7:0]  RESULT_STATUS_TRUNC     = 8'h05;
  localparam [7:0]  RESULT_STATUS_NOT_READY = 8'h06;
  localparam [15:0] RESULT_TYPE_NONE        = 16'h0000;
  localparam [15:0] RESULT_TYPE_NN          = 16'h0002;
  localparam [15:0] RESULT_LEN_NONE         = 16'd0;
  localparam [15:0] RESULT_LEN_BYTES        = 16'd4;

  localparam [7:0] GPU_MMIO_CONTROL   = 8'h00;
  localparam [31:0] GPU_CTRL_START    = 32'h0000_0001;
  localparam [31:0] GPU_CTRL_SOFT_RESET = 32'h0000_0004;

  localparam [DMEM_ADDR_WIDTH-1:0] ACT_BASE_ADDR  = 16;
  localparam [DMEM_ADDR_WIDTH-1:0] WGT_BASE_ADDR  = 64;
  localparam [DMEM_ADDR_WIDTH-1:0] BIAS_BASE_ADDR = 96;
  localparam [DMEM_ADDR_WIDTH-1:0] X_OFF          = 0;
  localparam [DMEM_ADDR_WIDTH-1:0] Y_OFF          = 16;
  localparam [DMEM_ADDR_WIDTH-1:0] DMEM_ADDR_ONE  = {{(DMEM_ADDR_WIDTH-1){1'b0}}, 1'b1};

  reg [3:0] state;
  reg [4:0] feature_load_idx;
  reg [FRAME_WORD_ADDR_WIDTH-1:0] replay_word_idx;
  reg [1:0] task_reset_cycles;

  reg [63:0] prev_cpu_prog_bundle;
  reg [63:0] prev_gpu_imem_bundle;
  reg [95:0] prev_sw_w_bundle;
  reg        gpu_done_d;
  reg        gpu_core_reset;
  reg        dmem_debug_pending;

  reg        cpu_programmed;
  reg        gpu_programmed;
  reg        param_programmed;

  wire       engine_enable;
  wire       engine_ready;
  wire       cpu_core_reset;
  wire       task_reset_active;
  wire       dmem_gpu_active;

  wire       cpu_sw_prog_we;
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
  wire                  sw_param_write;
  wire                  feature_in_range;
  wire [DMEM_ADDR_WIDTH-1:0] feature_load_addr;
  wire [63:0]           feature_load_wdata;
  reg  [15:0]           feature_load_data;
  wire [DMEM_ADDR_WIDTH-1:0] capture_addr_0;
  wire [DMEM_ADDR_WIDTH-1:0] capture_addr_1;

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
  wire                  dmem_debug_issue;

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
  assign gpu_imem_prog_addr  = sw_gpu_i_mem_addr[8:0];
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

  assign debug_addr = sw_gpu_ofmap_addr[DMEM_ADDR_WIDTH-1:0];
  assign sw_param_write = sw_gpu_w_mem_addr[31] &&
                          ({sw_gpu_w_mem_addr, sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0} != prev_sw_w_bundle);
  assign feature_in_range = ({11'd0, feature_load_idx} < feature_count);
  assign feature_load_addr = ACT_BASE_ADDR +
                             X_OFF +
                             {{(DMEM_ADDR_WIDTH-5){1'b0}}, feature_load_idx};
  assign feature_load_wdata = feature_in_range ? {48'd0, feature_load_data} : 64'd0;
  assign capture_addr_0 = ACT_BASE_ADDR + Y_OFF;
  assign capture_addr_1 = ACT_BASE_ADDR + Y_OFF + DMEM_ADDR_ONE;
  assign dmem_debug_issue = !dmem_gpu_active &&
                            (state != ST_LOAD_FEATURE) &&
                            (state != ST_CAPTURE_REQ) &&
                            !sw_param_write;
  assign hw_engine_status = {27'd0, gpu_busy, param_programmed, gpu_programmed, cpu_programmed, engine_ready};
  assign gpu_mem0_rdata = dmem_gpu_active ? dmem_a_rdata : 64'd0;
  assign gpu_mem0_rvalid = dmem_gpu_active ? dmem_a_rvalid : 1'b0;
  assign gpu_mem1_rdata = dmem_gpu_active ? dmem_b_rdata : 64'd0;
  assign gpu_mem1_rvalid = dmem_gpu_active ? dmem_b_rvalid : 1'b0;

  always @(*) begin
    case (feature_load_idx)
      5'd0: feature_load_data = feature_data_0;
      5'd1: feature_load_data = feature_data_1;
      5'd2: feature_load_data = feature_data_2;
      5'd3: feature_load_data = feature_data_3;
      5'd4: feature_load_data = feature_data_4;
      5'd5: feature_load_data = feature_data_5;
      5'd6: feature_load_data = feature_data_6;
      5'd7: feature_load_data = feature_data_7;
      default: feature_load_data = 16'd0;
    endcase
  end

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
      dmem_a_addr = capture_addr_0;
      dmem_b_en   = 1'b1;
      dmem_b_addr = capture_addr_1;
    end
    else if (state == ST_LOAD_FEATURE) begin
      if (feature_load_idx < IN_DIM) begin
        dmem_a_en    = 1'b1;
        dmem_a_we    = 1'b1;
        dmem_a_addr  = feature_load_addr;
        dmem_a_wdata = feature_load_wdata;
      end
      else begin
        dmem_a_en    = 1'b1;
        dmem_a_we    = 1'b1;
        dmem_a_addr  = capture_addr_0;
        dmem_b_en    = 1'b1;
        dmem_b_we    = 1'b1;
        dmem_b_addr  = capture_addr_1;
      end
    end
    else if (sw_param_write) begin
      dmem_a_en    = 1'b1;
      dmem_a_we    = 1'b1;
      dmem_a_addr  = sw_gpu_w_mem_addr[DMEM_ADDR_WIDTH-1:0];
      dmem_a_wdata = {sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0};
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
    .reset           (cpu_core_reset)
  );

  gpu_top_fifo_if #(
    .MMIO_ADDR_W(8),
    .IMEM_AW(9),
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
      state               <= ST_IDLE;
      feature_load_idx    <= 5'd0;
      replay_word_idx     <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      task_reset_cycles   <= 2'd0;
      frame_rd_addr       <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
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
      gpu_reset_pulse     <= 1'b0;
      gpu_start_pulse     <= 1'b0;
      gpu_done_d          <= 1'b0;
      gpu_core_reset      <= 1'b1;
      dmem_debug_pending  <= 1'b0;
      prev_cpu_prog_bundle <= 64'd0;
      prev_gpu_imem_bundle <= 64'd0;
      prev_sw_w_bundle     <= 96'd0;
      cpu_programmed       <= 1'b0;
      gpu_programmed       <= 1'b0;
      param_programmed     <= 1'b0;
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
      prev_sw_w_bundle     <= {sw_gpu_w_mem_addr, sw_gpu_w_mem_wdata_1, sw_gpu_w_mem_wdata_0};

      if (dmem_debug_pending) begin
        hw_gpu_ofmap_data_0 <= dmem_a_rdata[31:0];
        hw_gpu_ofmap_data_1 <= dmem_a_rdata[63:32];
      end

      if (cpu_sw_prog_we)
        cpu_programmed <= 1'b1;

      if (gpu_imem_prog_we)
        gpu_programmed <= 1'b1;

      if (sw_param_write) begin
        param_programmed <= 1'b1;
      end

      case (state)
        ST_IDLE: begin
          if (start) begin
            replay_word_idx <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            frame_rd_addr   <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            if (!engine_ready) begin
              result_status <= RESULT_STATUS_NOT_READY;
              result_type   <= RESULT_TYPE_NONE;
              result_len    <= RESULT_LEN_NONE;
              result_data_0 <= 16'd0;
              result_data_1 <= 16'd0;
              done          <= 1'b1;
            end
            else begin
              gpu_done_d      <= 1'b0;
              task_reset_cycles <= 2'd2;
              feature_load_idx <= 5'd0;
              result_status    <= (feature_count == IN_DIM) ? RESULT_STATUS_OK : RESULT_STATUS_TRUNC;
              result_type      <= RESULT_TYPE_NN;
              result_len       <= RESULT_LEN_BYTES;
              state            <= ST_TASK_RESET;
            end
          end
        end

        ST_TASK_RESET: begin
          if (task_reset_cycles != 2'd0) begin
            task_reset_cycles <= task_reset_cycles - 2'd1;
          end
          else begin
            gpu_reset_pulse <= 1'b1;
            state <= ST_LOAD_FEATURE;
          end
        end

        ST_LOAD_FEATURE: begin
          if (feature_load_idx < IN_DIM) begin
            feature_load_idx <= feature_load_idx + 5'd1;
          end
          else begin
            state <= ST_SEND_MODULE_HDR;
          end
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
          if (gpu_done_pulse)
            state <= ST_CAPTURE_REQ;
        end

        ST_CAPTURE_REQ: begin
          state <= ST_CAPTURE;
        end

        ST_CAPTURE: begin
          if (dmem_a_rvalid && dmem_b_rvalid) begin
            result_data_0    <= dmem_a_rdata[15:0];
            result_data_1    <= dmem_b_rdata[15:0];
            cpu_ext_continue <= 1'b1;
            done             <= 1'b1;
            state            <= ST_IDLE;
          end
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
