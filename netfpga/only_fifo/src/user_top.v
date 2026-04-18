`timescale 1ns/1ps

module user_top #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter UDP_REG_SRC_WIDTH = 2
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

  assign reg_req_out      = reg_req_in;
  assign reg_ack_out      = reg_ack_in;
  assign reg_rd_wr_L_out  = reg_rd_wr_L_in;
  assign reg_addr_out     = reg_addr_in;
  assign reg_data_out     = reg_data_in;
  assign reg_src_out      = reg_src_in;

  wire [DATA_WIDTH-1:0] front_buf_out_data;
  wire [CTRL_WIDTH-1:0] front_buf_out_ctrl;
  wire                  front_buf_out_wr;
  wire                  front_buf_out_rdy;

  wire [DATA_WIDTH-1:0] action_out_data;
  wire [CTRL_WIDTH-1:0] action_out_ctrl;
  wire                  action_out_wr;
  wire                  action_out_rdy;

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) u_front_buffer (
    .in_data        (in_data),
    .in_ctrl        (in_ctrl),
    .in_wr          (in_wr),
    .in_rdy         (in_rdy),

    .out_data       (front_buf_out_data),
    .out_ctrl       (front_buf_out_ctrl),
    .out_wr         (front_buf_out_wr),
    .out_rdy        (front_buf_out_rdy),

    .reset          (reset),
    .clk            (clk)
  );

  packet_action_selector #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) u_action_selector (
    .in_data        (front_buf_out_data),
    .in_ctrl        (front_buf_out_ctrl),
    .in_wr          (front_buf_out_wr),
    .in_rdy         (front_buf_out_rdy),

    .out_data       (action_out_data),
    .out_ctrl       (action_out_ctrl),
    .out_wr         (action_out_wr),
    .out_rdy        (action_out_rdy),

    .reset          (reset),
    .clk            (clk)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) u_backend_buffer (
    .in_data        (action_out_data),
    .in_ctrl        (action_out_ctrl),
    .in_wr          (action_out_wr),
    .in_rdy         (action_out_rdy),

    .out_data       (out_data),
    .out_ctrl       (out_ctrl),
    .out_wr         (out_wr),
    .out_rdy        (out_rdy),

    .reset          (reset),
    .clk            (clk)
  );

endmodule
