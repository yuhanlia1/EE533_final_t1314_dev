`timescale 1ns/1ps

`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 16
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif

`ifndef PIPELINE_REG_ADDR_WIDTH
`define PIPELINE_REG_ADDR_WIDTH 6
`endif

`ifndef PIPELINE_BLOCK_ADDR
`define PIPELINE_BLOCK_ADDR 10'h155
`endif

module pipeline_control_regs #(
  parameter UDP_REG_SRC_WIDTH = 2
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

  output reg [31:0] sw_d_mem_addr,
  output reg [31:0] sw_i_mem_wdata,
  output reg [31:0] sw_i_mem_addr,
  output reg [31:0] sw_engine_ctrl,
  output reg [31:0] sw_gpu_i_mem_wdata,
  output reg [31:0] sw_gpu_i_mem_addr,
  output reg [31:0] sw_gpu_w_mem_wdata_1,
  output reg [31:0] sw_gpu_w_mem_wdata_0,
  output reg [31:0] sw_gpu_w_mem_addr,
  output reg [31:0] sw_gpu_ofmap_addr,

  input      [31:0] hw_engine_status,
  input      [31:0] hw_gpu_ofmap_data_0,
  input      [31:0] hw_gpu_ofmap_data_1,

  input             clk,
  input             reset
);

  localparam integer REG_ADDR_WIDTH = `PIPELINE_REG_ADDR_WIDTH;
  localparam integer BLOCK_TAG_WIDTH = `UDP_REG_ADDR_WIDTH - REG_ADDR_WIDTH;
  localparam integer WORD_INDEX_WIDTH = REG_ADDR_WIDTH - 2;
  localparam integer NUM_REGS = 15;

  localparam [BLOCK_TAG_WIDTH-1:0] BLOCK_TAG = `PIPELINE_BLOCK_ADDR;

  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_D_MEM_ADDR          = 0;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_I_MEM_WDATA         = 1;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_I_MEM_ADDR          = 2;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_ENGINE_CTRL         = 3;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_I_MEM_WDATA     = 4;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_I_MEM_ADDR      = 5;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_W_MEM_WDATA_1   = 6;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_W_MEM_WDATA_0   = 7;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_W_MEM_ADDR      = 8;
  localparam [WORD_INDEX_WIDTH-1:0] REG_SW_GPU_OFMAP_ADDR      = 9;
  localparam [WORD_INDEX_WIDTH-1:0] REG_HW_ENGINE_STATUS       = 10;
  localparam [WORD_INDEX_WIDTH-1:0] REG_HW_RESERVED_0          = 11;
  localparam [WORD_INDEX_WIDTH-1:0] REG_HW_RESERVED_1          = 12;
  localparam [WORD_INDEX_WIDTH-1:0] REG_HW_GPU_OFMAP_DATA_0    = 13;
  localparam [WORD_INDEX_WIDTH-1:0] REG_HW_GPU_OFMAP_DATA_1    = 14;

  wire [WORD_INDEX_WIDTH-1:0] reg_word_index;
  wire                        block_hit;
  wire                        local_hit;
  reg  [31:0]                local_read_data;

  assign reg_word_index = reg_addr_in[REG_ADDR_WIDTH-1:2];
  assign block_hit = reg_addr_in[`UDP_REG_ADDR_WIDTH-1:REG_ADDR_WIDTH] == BLOCK_TAG;
  assign local_hit = reg_req_in && block_hit && (reg_word_index < NUM_REGS);

  assign reg_req_out = reg_req_in;
  assign reg_ack_out = reg_ack_in || local_hit;
  assign reg_rd_wr_L_out = reg_rd_wr_L_in;
  assign reg_addr_out = reg_addr_in;
  assign reg_data_out = reg_ack_in ? reg_data_in : (local_hit ? local_read_data : reg_data_in);
  assign reg_src_out = reg_src_in;

  always @(*) begin
    case (reg_word_index)
      REG_SW_D_MEM_ADDR:            local_read_data = sw_d_mem_addr;
      REG_SW_I_MEM_WDATA:           local_read_data = sw_i_mem_wdata;
      REG_SW_I_MEM_ADDR:            local_read_data = sw_i_mem_addr;
      REG_SW_ENGINE_CTRL:           local_read_data = sw_engine_ctrl;
      REG_SW_GPU_I_MEM_WDATA:       local_read_data = sw_gpu_i_mem_wdata;
      REG_SW_GPU_I_MEM_ADDR:        local_read_data = sw_gpu_i_mem_addr;
      REG_SW_GPU_W_MEM_WDATA_1:     local_read_data = sw_gpu_w_mem_wdata_1;
      REG_SW_GPU_W_MEM_WDATA_0:     local_read_data = sw_gpu_w_mem_wdata_0;
      REG_SW_GPU_W_MEM_ADDR:        local_read_data = sw_gpu_w_mem_addr;
      REG_SW_GPU_OFMAP_ADDR:        local_read_data = sw_gpu_ofmap_addr;
      REG_HW_ENGINE_STATUS:         local_read_data = hw_engine_status;
      REG_HW_RESERVED_0:            local_read_data = 32'd0;
      REG_HW_RESERVED_1:            local_read_data = 32'd0;
      REG_HW_GPU_OFMAP_DATA_0:      local_read_data = hw_gpu_ofmap_data_0;
      REG_HW_GPU_OFMAP_DATA_1:      local_read_data = hw_gpu_ofmap_data_1;
      default:                      local_read_data = 32'd0;
    endcase
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      sw_d_mem_addr        <= 32'd0;
      sw_i_mem_wdata       <= 32'd0;
      sw_i_mem_addr        <= 32'd0;
      sw_engine_ctrl       <= 32'd0;
      sw_gpu_i_mem_wdata   <= 32'd0;
      sw_gpu_i_mem_addr    <= 32'd0;
      sw_gpu_w_mem_wdata_1 <= 32'd0;
      sw_gpu_w_mem_wdata_0 <= 32'd0;
      sw_gpu_w_mem_addr    <= 32'd0;
      sw_gpu_ofmap_addr    <= 32'd0;
    end
    else if (local_hit && !reg_rd_wr_L_in) begin
      case (reg_word_index)
        REG_SW_D_MEM_ADDR:          sw_d_mem_addr        <= reg_data_in;
        REG_SW_I_MEM_WDATA:         sw_i_mem_wdata       <= reg_data_in;
        REG_SW_I_MEM_ADDR:          sw_i_mem_addr        <= reg_data_in;
        REG_SW_ENGINE_CTRL:         sw_engine_ctrl       <= reg_data_in;
        REG_SW_GPU_I_MEM_WDATA:     sw_gpu_i_mem_wdata   <= reg_data_in;
        REG_SW_GPU_I_MEM_ADDR:      sw_gpu_i_mem_addr    <= reg_data_in;
        REG_SW_GPU_W_MEM_WDATA_1:   sw_gpu_w_mem_wdata_1 <= reg_data_in;
        REG_SW_GPU_W_MEM_WDATA_0:   sw_gpu_w_mem_wdata_0 <= reg_data_in;
        REG_SW_GPU_W_MEM_ADDR:      sw_gpu_w_mem_addr    <= reg_data_in;
        REG_SW_GPU_OFMAP_ADDR:      sw_gpu_ofmap_addr    <= reg_data_in;
        default: begin
        end
      endcase
    end
  end

endmodule
