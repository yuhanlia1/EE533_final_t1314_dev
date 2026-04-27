`timescale 1ns/1ps

`ifndef USER_TOP_BLOCK_ADDR
`define USER_TOP_BLOCK_ADDR 10'h155
`endif

`ifndef USER_TOP_REG_ADDR_WIDTH
`define USER_TOP_REG_ADDR_WIDTH 7
`endif

module user_top #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter UDP_REG_SRC_WIDTH  = 2
) (
  input  [DATA_WIDTH-1:0]           in_data,
  input  [CTRL_WIDTH-1:0]           in_ctrl,
  input                             in_wr,
  output                            in_rdy,

  output [DATA_WIDTH-1:0]           out_data,
  output [CTRL_WIDTH-1:0]           out_ctrl,
  output                            out_wr,
  input                             out_rdy,

  input                             reg_req_in,
  input                             reg_ack_in,
  input                             reg_rd_wr_L_in,
  input  [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_in,
  input  [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
  input  [UDP_REG_SRC_WIDTH-1:0]    reg_src_in,

  output                            reg_req_out,
  output                            reg_ack_out,
  output                            reg_rd_wr_L_out,
  output [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_out,
  output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
  output [UDP_REG_SRC_WIDTH-1:0]    reg_src_out,

  input wire                        clk,
  input wire                        reset
);

  localparam ACTION_WIDTH = 2;
  localparam integer NUM_CONTROL_SW_REGS = 10;
  localparam integer NUM_CONTROL_HW_REGS = 14;
  localparam integer NUM_SW_REGS = NUM_CONTROL_SW_REGS;
  localparam integer NUM_HW_REGS = NUM_CONTROL_HW_REGS;
  localparam [31:0] ENGINE_CTRL_DEBUG_CLEAR_MASK = 32'h0000_0004;

  reg  [31:0] sw_engine_ctrl_latch;
  reg  [31:0] sw_i_mem_addr_latch;
  reg  [31:0] sw_i_mem_wdata_latch;
  reg  [31:0] sw_d_mem_addr_latch;
  reg  [31:0] sw_gpu_i_mem_addr_latch;
  reg  [31:0] sw_gpu_i_mem_wdata_latch;
  reg  [31:0] sw_gpu_w_mem_addr_latch;
  reg  [31:0] sw_gpu_w_mem_wdata_0_latch;
  reg  [31:0] sw_gpu_w_mem_wdata_1_latch;
  reg  [31:0] sw_gpu_ofmap_addr_latch;

  wire [31:0] sw_engine_ctrl;
  wire [31:0] sw_i_mem_addr;
  wire [31:0] sw_i_mem_wdata;
  wire [31:0] sw_d_mem_addr;
  wire [31:0] sw_gpu_i_mem_addr;
  wire [31:0] sw_gpu_i_mem_wdata;
  wire [31:0] sw_gpu_w_mem_addr;
  wire [31:0] sw_gpu_w_mem_wdata_0;
  wire [31:0] sw_gpu_w_mem_wdata_1;
  wire [31:0] sw_gpu_ofmap_addr;

  wire [31:0] hw_engine_status;
  wire [31:0] hw_gpu_ofmap_data_1;
  wire [31:0] hw_gpu_ofmap_data_0;
  wire [31:0] hw_cpu_i_mem_word_out;
  wire [31:0] hw_cpu_d_mem_word_out_0;
  wire [31:0] hw_cpu_d_mem_word_out_1;
  wire [31:0] hw_reserved_1;
  wire [31:0] hw_reserved_0;
  reg  [31:0] hw_dbg_offload_accept_count;
  reg  [31:0] hw_dbg_frame_hold_count;
  reg  [31:0] hw_dbg_compute_start_count;
  reg  [31:0] hw_dbg_compute_done_count;
  reg  [31:0] hw_dbg_result_emit_count;
  reg  [31:0] hw_dbg_last_parse_request_id;
  reg  [31:0] hw_dbg_last_compute_request_id;
  reg  [31:0] hw_dbg_last_emit_request_id;
  reg  [31:0] hw_dbg_flags;

  wire [DATA_WIDTH-1:0] ingress_out_data;
  wire [CTRL_WIDTH-1:0] ingress_out_ctrl;
  wire                  ingress_out_wr;
  wire                  ingress_out_rdy;

  wire [DATA_WIDTH-1:0] selector_out_data;
  wire [CTRL_WIDTH-1:0] selector_out_ctrl;
  wire                  selector_out_wr;
  wire                  selector_out_rdy;
  wire [ACTION_WIDTH-1:0] selector_out_action;

  wire [DATA_WIDTH-1:0] dispatcher_out_data;
  wire [CTRL_WIDTH-1:0] dispatcher_out_ctrl;
  wire                  dispatcher_out_wr;
  wire                  dispatcher_out_rdy;

  wire [DATA_WIDTH-1:0] offload_data;
  wire [CTRL_WIDTH-1:0] offload_ctrl;
  wire                  offload_wr;
  wire                  offload_rdy;

  wire [DATA_WIDTH-1:0] ann_out_data;
  wire [CTRL_WIDTH-1:0] ann_out_ctrl;
  wire                  ann_out_wr;
  wire                  ann_out_rdy;
  wire                  debug_frame_ready_pulse;
  wire                  debug_parse_done_pulse;
  wire                  debug_compute_start_pulse;
  wire                  debug_compute_done_pulse;
  wire                  debug_result_emit_pulse;
  wire                  debug_ingress_overflow_pulse;
  wire                  debug_parse_nonfatal_pulse;
  wire                  debug_parse_fatal_pulse;
  wire                  debug_emit_stall;
  wire [15:0]           debug_parse_request_id;
  wire [15:0]           debug_active_request_id;
  reg                   debug_offload_packet_active;
  reg                   debug_emit_packet_active;
  wire                  debug_clear_active;
  wire                  offload_word_accepted;
  wire                  ann_word_accepted;

  assign hw_reserved_0 = hw_cpu_i_mem_word_out;
  assign hw_reserved_1 = hw_cpu_d_mem_word_out_0;
  assign debug_clear_active = (sw_engine_ctrl_latch & ENGINE_CTRL_DEBUG_CLEAR_MASK) != 32'd0;
  assign offload_word_accepted = offload_wr && offload_rdy;
  assign ann_word_accepted = ann_out_wr && ann_out_rdy;

  generic_regs #(
    .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
    .TAG               (`USER_TOP_BLOCK_ADDR),
    .REG_ADDR_WIDTH    (`USER_TOP_REG_ADDR_WIDTH),
    .NUM_COUNTERS      (0),
    .NUM_SOFTWARE_REGS (NUM_SW_REGS),
    .NUM_HARDWARE_REGS (NUM_HW_REGS)
  ) control_regs (
    .reg_req_in       (reg_req_in),
    .reg_ack_in       (reg_ack_in),
    .reg_rd_wr_L_in   (reg_rd_wr_L_in),
    .reg_addr_in      (reg_addr_in),
    .reg_data_in      (reg_data_in),
    .reg_src_in       (reg_src_in),
    .reg_req_out      (reg_req_out),
    .reg_ack_out      (reg_ack_out),
    .reg_rd_wr_L_out  (reg_rd_wr_L_out),
    .reg_addr_out     (reg_addr_out),
    .reg_data_out     (reg_data_out),
    .reg_src_out      (reg_src_out),
    .counter_updates  (),
    .counter_decrement(),
    .software_regs ({
      sw_gpu_ofmap_addr,
      sw_gpu_w_mem_addr,
      sw_gpu_w_mem_wdata_0,
      sw_gpu_w_mem_wdata_1,
      sw_gpu_i_mem_addr,
      sw_gpu_i_mem_wdata,
      sw_engine_ctrl,
      sw_i_mem_addr,
      sw_i_mem_wdata,
      sw_d_mem_addr
    }),
    .hardware_regs ({
      hw_dbg_flags,
      hw_dbg_last_emit_request_id,
      hw_dbg_last_compute_request_id,
      hw_dbg_last_parse_request_id,
      hw_dbg_result_emit_count,
      hw_dbg_compute_done_count,
      hw_dbg_compute_start_count,
      hw_dbg_frame_hold_count,
      hw_dbg_offload_accept_count,
      hw_gpu_ofmap_data_1,
      hw_gpu_ofmap_data_0,
      hw_reserved_1,
      hw_reserved_0,
      hw_engine_status
    }),
    .clk              (clk),
    .reset            (reset)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) ingress_fifo (
    .in_data   (in_data),
    .in_ctrl   (in_ctrl),
    .in_wr     (in_wr),
    .in_rdy    (in_rdy),
    .out_data  (ingress_out_data),
    .out_ctrl  (ingress_out_ctrl),
    .out_wr    (ingress_out_wr),
    .out_rdy   (ingress_out_rdy),
    .reset     (reset),
    .clk       (clk)
  );

  packet_action_selector #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ACTION_WIDTH(ACTION_WIDTH)
  ) selector (
    .in_data                    (ingress_out_data),
    .in_ctrl                    (ingress_out_ctrl),
    .in_wr                      (ingress_out_wr),
    .in_rdy                     (ingress_out_rdy),
    .out_data                   (selector_out_data),
    .out_ctrl                   (selector_out_ctrl),
    .out_wr                     (selector_out_wr),
    .out_rdy                    (selector_out_rdy),
    .out_action                 (selector_out_action),
    .clk                        (clk),
    .reset                      (reset)
  );

  action_dispatcher #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ACTION_WIDTH(ACTION_WIDTH)
  ) dispatcher (
    .clk            (clk),
    .reset          (reset),
    .in_data        (selector_out_data),
    .in_ctrl        (selector_out_ctrl),
    .in_wr          (selector_out_wr),
    .in_rdy         (selector_out_rdy),
    .in_action      (selector_out_action),
    .out_data       (dispatcher_out_data),
    .out_ctrl       (dispatcher_out_ctrl),
    .out_wr         (dispatcher_out_wr),
    .out_rdy        (dispatcher_out_rdy),
    .engine_in_data (offload_data),
    .engine_in_ctrl (offload_ctrl),
    .engine_in_wr   (offload_wr),
    .engine_in_rdy  (offload_rdy),
    .engine_out_data(ann_out_data),
    .engine_out_ctrl(ann_out_ctrl),
    .engine_out_wr  (ann_out_wr),
    .engine_out_rdy (ann_out_rdy)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) egress_fifo (
    .in_data   (dispatcher_out_data),
    .in_ctrl   (dispatcher_out_ctrl),
    .in_wr     (dispatcher_out_wr),
    .in_rdy    (dispatcher_out_rdy),
    .out_data  (out_data),
    .out_ctrl  (out_ctrl),
    .out_wr    (out_wr),
    .out_rdy   (out_rdy),
    .reset     (reset),
    .clk       (clk)
  );

  ann_engine_wrapper #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) ann_engine (
    .in_data               (offload_data),
    .in_ctrl               (offload_ctrl),
    .in_wr                 (offload_wr),
    .in_rdy                (offload_rdy),
    .out_data              (ann_out_data),
    .out_ctrl              (ann_out_ctrl),
    .out_wr                (ann_out_wr),
    .out_rdy               (ann_out_rdy),
    .sw_engine_ctrl        (sw_engine_ctrl_latch),
    .sw_i_mem_addr         (sw_i_mem_addr_latch),
    .sw_i_mem_wdata        (sw_i_mem_wdata_latch),
    .sw_d_mem_addr         (sw_d_mem_addr_latch),
    .sw_gpu_i_mem_addr     (sw_gpu_i_mem_addr_latch),
    .sw_gpu_i_mem_wdata    (sw_gpu_i_mem_wdata_latch),
    .sw_gpu_w_mem_addr     (sw_gpu_w_mem_addr_latch),
    .sw_gpu_w_mem_wdata_0  (sw_gpu_w_mem_wdata_0_latch),
    .sw_gpu_w_mem_wdata_1  (sw_gpu_w_mem_wdata_1_latch),
    .sw_gpu_ofmap_addr     (sw_gpu_ofmap_addr_latch),
    .hw_gpu_ofmap_data_1   (hw_gpu_ofmap_data_1),
    .hw_gpu_ofmap_data_0   (hw_gpu_ofmap_data_0),
    .hw_cpu_i_mem_word_out (hw_cpu_i_mem_word_out),
    .hw_cpu_d_mem_word_out_0(hw_cpu_d_mem_word_out_0),
    .hw_cpu_d_mem_word_out_1(hw_cpu_d_mem_word_out_1),
    .hw_engine_status      (hw_engine_status),
    .debug_frame_ready_pulse(debug_frame_ready_pulse),
    .debug_parse_done_pulse(debug_parse_done_pulse),
    .debug_compute_start_pulse(debug_compute_start_pulse),
    .debug_compute_done_pulse(debug_compute_done_pulse),
    .debug_result_emit_pulse(debug_result_emit_pulse),
    .debug_ingress_overflow_pulse(debug_ingress_overflow_pulse),
    .debug_parse_nonfatal_pulse(debug_parse_nonfatal_pulse),
    .debug_parse_fatal_pulse(debug_parse_fatal_pulse),
    .debug_emit_stall      (debug_emit_stall),
    .debug_parse_request_id(debug_parse_request_id),
    .debug_active_request_id(debug_active_request_id),
    .clk                   (clk),
    .reset                 (reset)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      sw_engine_ctrl_latch       <= 32'd0;
      sw_i_mem_addr_latch        <= 32'd0;
      sw_i_mem_wdata_latch       <= 32'd0;
      sw_d_mem_addr_latch        <= 32'd0;
      sw_gpu_i_mem_addr_latch    <= 32'd0;
      sw_gpu_i_mem_wdata_latch   <= 32'd0;
      sw_gpu_w_mem_addr_latch    <= 32'd0;
      sw_gpu_w_mem_wdata_0_latch <= 32'd0;
      sw_gpu_w_mem_wdata_1_latch <= 32'd0;
      sw_gpu_ofmap_addr_latch    <= 32'd0;
      hw_dbg_offload_accept_count <= 32'd0;
      hw_dbg_frame_hold_count     <= 32'd0;
      hw_dbg_compute_start_count  <= 32'd0;
      hw_dbg_compute_done_count   <= 32'd0;
      hw_dbg_result_emit_count    <= 32'd0;
      hw_dbg_last_parse_request_id <= 32'd0;
      hw_dbg_last_compute_request_id <= 32'd0;
      hw_dbg_last_emit_request_id <= 32'd0;
      hw_dbg_flags                <= 32'd0;
      debug_offload_packet_active <= 1'b0;
      debug_emit_packet_active    <= 1'b0;
    end
    else begin
      sw_engine_ctrl_latch       <= sw_engine_ctrl;
      sw_i_mem_addr_latch        <= sw_i_mem_addr;
      sw_i_mem_wdata_latch       <= sw_i_mem_wdata;
      sw_d_mem_addr_latch        <= sw_d_mem_addr;
      sw_gpu_i_mem_addr_latch    <= sw_gpu_i_mem_addr;
      sw_gpu_i_mem_wdata_latch   <= sw_gpu_i_mem_wdata;
      sw_gpu_w_mem_addr_latch    <= sw_gpu_w_mem_addr;
      sw_gpu_w_mem_wdata_0_latch <= sw_gpu_w_mem_wdata_0;
      sw_gpu_w_mem_wdata_1_latch <= sw_gpu_w_mem_wdata_1;
      sw_gpu_ofmap_addr_latch    <= sw_gpu_ofmap_addr;

      if (debug_clear_active) begin
        hw_dbg_offload_accept_count <= 32'd0;
        hw_dbg_frame_hold_count     <= 32'd0;
        hw_dbg_compute_start_count  <= 32'd0;
        hw_dbg_compute_done_count   <= 32'd0;
        hw_dbg_result_emit_count    <= 32'd0;
        hw_dbg_last_parse_request_id <= 32'd0;
        hw_dbg_last_compute_request_id <= 32'd0;
        hw_dbg_last_emit_request_id <= 32'd0;
        hw_dbg_flags                <= 32'd0;
        debug_offload_packet_active <= 1'b0;
        debug_emit_packet_active    <= 1'b0;
      end
      else begin
        if (offload_word_accepted) begin
          if (!debug_offload_packet_active) begin
            hw_dbg_offload_accept_count <= hw_dbg_offload_accept_count + 32'd1;
            debug_offload_packet_active <= 1'b1;
          end
          else if (offload_ctrl != {CTRL_WIDTH{1'b0}}) begin
            debug_offload_packet_active <= 1'b0;
          end
        end

        if (ann_word_accepted) begin
          if (!debug_emit_packet_active) begin
            debug_emit_packet_active <= 1'b1;
          end
          else if (ann_out_ctrl != {CTRL_WIDTH{1'b0}}) begin
            debug_emit_packet_active <= 1'b0;
          end
        end

        if (debug_frame_ready_pulse) begin
          hw_dbg_frame_hold_count <= hw_dbg_frame_hold_count + 32'd1;
        end
        if (debug_parse_done_pulse) begin
          hw_dbg_last_parse_request_id <= {16'd0, debug_parse_request_id};
        end
        if (debug_compute_start_pulse) begin
          hw_dbg_compute_start_count <= hw_dbg_compute_start_count + 32'd1;
        end
        if (debug_compute_done_pulse) begin
          hw_dbg_compute_done_count <= hw_dbg_compute_done_count + 32'd1;
          hw_dbg_last_compute_request_id <= {16'd0, debug_active_request_id};
        end
        if (debug_result_emit_pulse) begin
          hw_dbg_result_emit_count <= hw_dbg_result_emit_count + 32'd1;
          hw_dbg_last_emit_request_id <= {16'd0, debug_active_request_id};
        end
        if (debug_ingress_overflow_pulse) begin
          hw_dbg_flags[0] <= 1'b1;
        end
        if (debug_parse_nonfatal_pulse) begin
          hw_dbg_flags[1] <= 1'b1;
        end
        if (debug_parse_fatal_pulse) begin
          hw_dbg_flags[2] <= 1'b1;
        end
        if (debug_emit_stall) begin
          hw_dbg_flags[3] <= 1'b1;
        end
      end
    end
  end

endmodule
