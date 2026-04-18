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

  wire fifo_full;
  wire pkt_ready;

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) u_convertible_fifo (
    .in_data        (in_data),
    .in_ctrl        (in_ctrl),
    .in_wr          (in_wr),
    .in_rdy         (in_rdy),

    .out_data       (out_data),
    .out_ctrl       (out_ctrl),
    .out_wr         (out_wr),
    .out_rdy        (out_rdy),

    .reg_req_in     (reg_req_in),
    .reg_ack_in     (reg_ack_in),
    .reg_rd_wr_L_in (reg_rd_wr_L_in),
    .reg_addr_in    (reg_addr_in),
    .reg_data_in    (reg_data_in),
    .reg_src_in     (reg_src_in),

    .reg_req_out    (reg_req_out),
    .reg_ack_out    (reg_ack_out),
    .reg_rd_wr_L_out(reg_rd_wr_L_out),
    .reg_addr_out   (reg_addr_out),
    .reg_data_out   (reg_data_out),
    .reg_src_out    (reg_src_out),

    .fifo_full      (fifo_full),
    .pkt_ready      (pkt_ready),

    .reset          (reset),
    .clk            (clk)
  );

endmodule