module wb_stage2 #(
  parameter MEM_ADDR_WIDTH = 8,
  parameter REG_ADDR_WIDTH = 4,
  parameter DATA_WIDTH = 64
) (
  // Global Signals
  input wire clk,
  input wire reset,
  input wire pipeline_enable,
  input wire wb_flush,

  input wire                      wb1_w_reg_en,
  input wire [DATA_WIDTH-1:0]     wb1_d_out,
  input wire [REG_ADDR_WIDTH-1:0] wb1_WReg1,
  input wire [1:0]                wb1_thread_id_out,

  output wire                      wb2_w_reg_en,
  output wire [DATA_WIDTH-1:0]     wb2_d_out,
  output wire [REG_ADDR_WIDTH-1:0] wb2_WReg1,
  output wire [1:0]                wb2_thread_id_out
);

  reg                      wb1_w_reg_en_reg;
  reg [DATA_WIDTH-1:0]     wb1_d_out_reg;
  reg [REG_ADDR_WIDTH-1:0] wb1_WReg1_reg;
  reg [1:0]                wb1_thread_id_out_reg;

  assign wb2_w_reg_en      = wb1_w_reg_en_reg;
  assign wb2_d_out         = wb1_d_out_reg;
  assign wb2_WReg1         = wb1_WReg1_reg;
  assign wb2_thread_id_out = wb1_thread_id_out_reg;

  always @(posedge clk or posedge reset) begin
      if (reset) begin
        wb1_w_reg_en_reg <= 0;
        wb1_d_out_reg <= 0;
        wb1_WReg1_reg <= 0;
        wb1_thread_id_out_reg <= 0;
      end else if (wb_flush) begin
        wb1_w_reg_en_reg <= 0;
        wb1_d_out_reg <= 0;
        wb1_WReg1_reg <= 0;
        wb1_thread_id_out_reg <= 0;
      end else if (pipeline_enable) begin
        wb1_w_reg_en_reg <= wb1_w_reg_en;
        wb1_d_out_reg <= wb1_d_out;
        wb1_WReg1_reg <= wb1_WReg1;
        wb1_thread_id_out_reg <= wb1_thread_id_out;
      end
  end

endmodule
