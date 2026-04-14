`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
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

  reg  [31:0] sw_network_la_addr_latch;
  reg  [31:0] sw_i_mem_addr_latch;
  reg  [31:0] sw_i_mem_wdata_latch;
  reg  [31:0] sw_d_mem_addr_latch;
  reg  [31:0] sw_gpu_w_mem_addr_latch;
  reg  [31:0] sw_gpu_w_mem_wdata_0_latch;
  reg  [31:0] sw_gpu_w_mem_wdata_1_latch;
  reg  [31:0] sw_gpu_ifmap_addr_latch;
  reg  [31:0] sw_gpu_ifmap_wdata_latch;
  reg  [31:0] sw_gpu_ofmap_addr_latch;

  wire [31:0] sw_network_la_addr;
  wire [31:0] sw_i_mem_addr;
  wire [31:0] sw_i_mem_wdata;
  wire [31:0] sw_d_mem_addr;
  wire [31:0] sw_gpu_w_mem_addr;
  wire [31:0] sw_gpu_w_mem_wdata_0;
  wire [31:0] sw_gpu_w_mem_wdata_1;
  wire [31:0] sw_gpu_ifmap_addr;
  wire [31:0] sw_gpu_ifmap_wdata;
  wire [31:0] sw_gpu_ofmap_addr;

  wire [31:0] hw_gpu_drop;
  reg  [31:0] hw_network_la_word_out_1;
  reg  [31:0] hw_network_la_word_out_0;
  wire [31:0] hw_gpu_ofmap_data_1;
  wire [31:0] hw_gpu_ofmap_data_0;

  wire [DATA_WIDTH-1:0] ingress_out_data;
  wire [CTRL_WIDTH-1:0] ingress_out_ctrl;
  wire                  ingress_out_wr;
  wire                  ingress_out_rdy;

  wire [DATA_WIDTH-1:0] selector_out_data;
  wire [CTRL_WIDTH-1:0] selector_out_ctrl;
  wire                  selector_out_wr;
  wire                  selector_out_rdy;
  wire [ACTION_WIDTH-1:0] selector_out_action;

  wire [DATA_WIDTH-1:0] bypass_data;
  wire [CTRL_WIDTH-1:0] bypass_ctrl;
  wire                  bypass_wr;
  wire                  bypass_rdy;

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

  pipeline_control_regs #(
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) control_regs (
    .reg_req_in              (reg_req_in),
    .reg_ack_in              (reg_ack_in),
    .reg_rd_wr_L_in          (reg_rd_wr_L_in),
    .reg_addr_in             (reg_addr_in),
    .reg_data_in             (reg_data_in),
    .reg_src_in              (reg_src_in),
    .reg_req_out             (reg_req_out),
    .reg_ack_out             (reg_ack_out),
    .reg_rd_wr_L_out         (reg_rd_wr_L_out),
    .reg_addr_out            (reg_addr_out),
    .reg_data_out            (reg_data_out),
    .reg_src_out             (reg_src_out),
    .sw_d_mem_addr           (sw_d_mem_addr),
    .sw_i_mem_wdata          (sw_i_mem_wdata),
    .sw_i_mem_addr           (sw_i_mem_addr),
    .sw_network_la_addr      (sw_network_la_addr),
    .sw_gpu_ifmap_wdata      (sw_gpu_ifmap_wdata),
    .sw_gpu_ifmap_addr       (sw_gpu_ifmap_addr),
    .sw_gpu_w_mem_wdata_1    (sw_gpu_w_mem_wdata_1),
    .sw_gpu_w_mem_wdata_0    (sw_gpu_w_mem_wdata_0),
    .sw_gpu_w_mem_addr       (sw_gpu_w_mem_addr),
    .sw_gpu_ofmap_addr       (sw_gpu_ofmap_addr),
    .hw_network_la_word_out_0(hw_network_la_word_out_0),
    .hw_network_la_word_out_1(hw_network_la_word_out_1),
    .hw_gpu_drop             (hw_gpu_drop),
    .hw_gpu_ofmap_data_0     (hw_gpu_ofmap_data_0),
    .hw_gpu_ofmap_data_1     (hw_gpu_ofmap_data_1),
    .clk                     (clk),
    .reset                   (reset)
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
    .in_data    (ingress_out_data),
    .in_ctrl    (ingress_out_ctrl),
    .in_wr      (ingress_out_wr),
    .in_rdy     (ingress_out_rdy),
    .out_data   (selector_out_data),
    .out_ctrl   (selector_out_ctrl),
    .out_wr     (selector_out_wr),
    .out_rdy    (selector_out_rdy),
    .out_action (selector_out_action),
    .clk        (clk),
    .reset      (reset)
  );

  action_dispatcher #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ACTION_WIDTH(ACTION_WIDTH)
  ) dispatcher (
    .clk         (clk),
    .reset       (reset),
    .in_data     (selector_out_data),
    .in_ctrl     (selector_out_ctrl),
    .in_wr       (selector_out_wr),
    .in_rdy      (selector_out_rdy),
    .in_action   (selector_out_action),
    .out_data    (dispatcher_out_data),
    .out_ctrl    (dispatcher_out_ctrl),
    .out_wr      (dispatcher_out_wr),
    .out_rdy     (dispatcher_out_rdy),
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
    .sw_i_mem_addr         (sw_i_mem_addr_latch),
    .sw_i_mem_wdata        (sw_i_mem_wdata_latch),
    .sw_d_mem_addr         (sw_d_mem_addr_latch),
    .sw_gpu_w_mem_addr     (sw_gpu_w_mem_addr_latch),
    .sw_gpu_w_mem_wdata_0  (sw_gpu_w_mem_wdata_0_latch),
    .sw_gpu_w_mem_wdata_1  (sw_gpu_w_mem_wdata_1_latch),
    .sw_gpu_ifmap_addr     (sw_gpu_ifmap_addr_latch),
    .sw_gpu_ifmap_wdata    (sw_gpu_ifmap_wdata_latch),
    .sw_gpu_ofmap_addr     (sw_gpu_ofmap_addr_latch),
    .hw_gpu_ofmap_data_1   (hw_gpu_ofmap_data_1),
    .hw_gpu_ofmap_data_0   (hw_gpu_ofmap_data_0),
    .hw_gpu_drop           (hw_gpu_drop),
    .clk                   (clk),
    .reset                 (reset)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      sw_network_la_addr_latch   <= 32'd0;
      sw_i_mem_addr_latch        <= 32'd0;
      sw_i_mem_wdata_latch       <= 32'd0;
      sw_d_mem_addr_latch        <= 32'd0;
      sw_gpu_w_mem_addr_latch    <= 32'd0;
      sw_gpu_w_mem_wdata_0_latch <= 32'd0;
      sw_gpu_w_mem_wdata_1_latch <= 32'd0;
      sw_gpu_ifmap_addr_latch    <= 32'd0;
      sw_gpu_ifmap_wdata_latch   <= 32'd0;
      sw_gpu_ofmap_addr_latch    <= 32'd0;
    end
    else begin
      sw_network_la_addr_latch   <= sw_network_la_addr;
      sw_i_mem_addr_latch        <= sw_i_mem_addr;
      sw_i_mem_wdata_latch       <= sw_i_mem_wdata;
      sw_d_mem_addr_latch        <= sw_d_mem_addr;
      sw_gpu_w_mem_addr_latch    <= sw_gpu_w_mem_addr;
      sw_gpu_w_mem_wdata_0_latch <= sw_gpu_w_mem_wdata_0;
      sw_gpu_w_mem_wdata_1_latch <= sw_gpu_w_mem_wdata_1;
      sw_gpu_ifmap_addr_latch    <= sw_gpu_ifmap_addr;
      sw_gpu_ifmap_wdata_latch   <= sw_gpu_ifmap_wdata;
      sw_gpu_ofmap_addr_latch    <= sw_gpu_ofmap_addr;
    end
  end

  reg [DATA_WIDTH-1:0] nw_la_mem [0:127];
  reg [6:0] nw_la_wr_ptr;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      nw_la_wr_ptr <= 7'd0;
    end
    else if (in_wr && in_rdy && nw_la_wr_ptr < 7'd127) begin
      nw_la_mem[nw_la_wr_ptr] <= in_data;
      nw_la_wr_ptr            <= nw_la_wr_ptr + 1'b1;
    end
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      hw_network_la_word_out_0 <= 32'd0;
      hw_network_la_word_out_1 <= 32'd0;
    end
    else begin
      hw_network_la_word_out_0 <= nw_la_mem[sw_network_la_addr_latch[6:0]][31:0];
      hw_network_la_word_out_1 <= nw_la_mem[sw_network_la_addr_latch[6:0]][63:32];
    end
  end

endmodule
