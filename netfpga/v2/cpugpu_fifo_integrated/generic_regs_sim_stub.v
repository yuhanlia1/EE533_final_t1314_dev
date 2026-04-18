`timescale 1ns/1ps
`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 23
`endif
`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif
`ifndef USER_TOP_BLOCK_ADDR
`define USER_TOP_BLOCK_ADDR 0
`endif
`ifndef USER_TOP_REG_ADDR_WIDTH
`define USER_TOP_REG_ADDR_WIDTH 4
`endif

module generic_regs #(
  parameter UDP_REG_SRC_WIDTH = 2,
  parameter TAG = 0,
  parameter REG_ADDR_WIDTH = 4,
  parameter NUM_COUNTERS = 0,
  parameter NUM_SOFTWARE_REGS = 4,
  parameter NUM_HARDWARE_REGS = 5
) (
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
  input  [NUM_COUNTERS-1:0]         counter_updates,
  input  [NUM_COUNTERS-1:0]         counter_decrement,
  output [NUM_SOFTWARE_REGS*32-1:0] software_regs,
  input  [NUM_HARDWARE_REGS*32-1:0] hardware_regs,
  input                             clk,
  input                             reset
);
  assign reg_req_out     = reg_req_in;
  assign reg_ack_out     = reg_ack_in;
  assign reg_rd_wr_L_out = reg_rd_wr_L_in;
  assign reg_addr_out    = reg_addr_in;
  assign reg_data_out    = reg_data_in;
  assign reg_src_out     = reg_src_in;
  assign software_regs   = {NUM_SOFTWARE_REGS*32{1'b0}};
endmodule
