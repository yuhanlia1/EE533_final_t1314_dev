`timescale 1ns/1ps
`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 23
`endif
`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif
`ifndef USER_TOP_BLOCK_ADDR
`define USER_TOP_BLOCK_ADDR 10'h155
`endif
`ifndef USER_TOP_REG_ADDR_WIDTH
`define USER_TOP_REG_ADDR_WIDTH 6
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
  localparam integer TOTAL_REGS = NUM_SOFTWARE_REGS + NUM_HARDWARE_REGS;
  localparam integer BLOCK_TAG_WIDTH = `UDP_REG_ADDR_WIDTH - REG_ADDR_WIDTH;
  localparam integer WORD_INDEX_WIDTH = REG_ADDR_WIDTH - 2;

  wire [WORD_INDEX_WIDTH-1:0] reg_word_index;
  wire                        block_hit;
  wire                        local_hit;
  reg  [31:0]                 local_read_data;
  reg  [NUM_SOFTWARE_REGS*32-1:0] software_regs_r;

  assign reg_word_index = reg_addr_in[REG_ADDR_WIDTH-1:2];
  assign block_hit      = reg_addr_in[`UDP_REG_ADDR_WIDTH-1:REG_ADDR_WIDTH] == TAG[BLOCK_TAG_WIDTH-1:0];
  assign local_hit      = reg_req_in && block_hit && (reg_word_index < TOTAL_REGS);

  assign reg_req_out     = reg_req_in;
  assign reg_ack_out     = reg_ack_in || local_hit;
  assign reg_rd_wr_L_out = reg_rd_wr_L_in;
  assign reg_addr_out    = reg_addr_in;
  assign reg_data_out    = reg_ack_in ? reg_data_in : (local_hit ? local_read_data : reg_data_in);
  assign reg_src_out     = reg_src_in;
  assign software_regs   = software_regs_r;

  always @(*) begin
    local_read_data = 32'd0;
    if (reg_word_index < NUM_SOFTWARE_REGS)
      local_read_data = software_regs_r[(reg_word_index * 32) +: 32];
    else if (reg_word_index < TOTAL_REGS)
      local_read_data = hardware_regs[((reg_word_index - NUM_SOFTWARE_REGS) * 32) +: 32];
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      software_regs_r <= {(NUM_SOFTWARE_REGS*32){1'b0}};
    end
    else if (local_hit && !reg_rd_wr_L_in && (reg_word_index < NUM_SOFTWARE_REGS)) begin
      software_regs_r[(reg_word_index * 32) +: 32] <= reg_data_in;
    end
  end
endmodule
