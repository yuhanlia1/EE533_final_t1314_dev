module wb_stage1 #(
  parameter MEM_ADDR_WIDTH = 8,
  parameter REG_ADDR_WIDTH = 4,
  parameter DATA_WIDTH = 64
) (
  input wire clk,
  input wire reset,
  input wire pipeline_enable,

  // Global Signals
  input wire wb_flush,

  // Logic from MEM
  input wire w_reg_en,
  input wire lw_en,                       // Load Word Enable (If true, then choose d_in_mem)
  input wire [DATA_WIDTH-1:0] d_in_mem,   // Data from Memory Load
  input wire [DATA_WIDTH-1:0] d_in_alu,   // Data Computed from ALU
  input wire [REG_ADDR_WIDTH-1:0] WReg1,  // RF Destination Address
  input wire [1:0] thread_id,

  input wire [               1:0]  ld_ptrs,
  input wire [MEM_ADDR_WIDTH-1:0]  head_ptr,
  input wire [MEM_ADDR_WIDTH-1:0]  tail_ptr,

  output wire wb1_w_reg_en,
  output wire [DATA_WIDTH-1:0] wb1_d_out,
  output wire [REG_ADDR_WIDTH-1:0] wb1_WReg1,
  output wire [1:0] wb1_thread_id_out
);
  
  reg w_reg_en_reg;
  reg lw_en_reg;
  reg [DATA_WIDTH-1:0] d_in_alu_reg;
  reg [REG_ADDR_WIDTH-1:0] WReg1_reg;  // RF Destination Address
  reg [1:0] thread_id_reg;

  reg [               1:0] ld_ptrs_reg;
  reg [MEM_ADDR_WIDTH-1:0] head_ptr_reg;
  reg [MEM_ADDR_WIDTH-1:0] tail_ptr_reg;

  always @(posedge clk or posedge reset) begin
      if (reset) begin
          w_reg_en_reg <= 0;
          lw_en_reg <= 0;
          d_in_alu_reg <= 0;
          WReg1_reg <= 0;
          thread_id_reg <= 0;
          ld_ptrs_reg <= 0;
          head_ptr_reg <= 0;
          tail_ptr_reg <= 0;
      end else if (wb_flush) begin
          w_reg_en_reg <= 0;
          lw_en_reg <= 0;
          d_in_alu_reg <= 0;
          WReg1_reg <= 0;
          thread_id_reg <= 0;
          ld_ptrs_reg <= 0;
          head_ptr_reg <= 0;
          tail_ptr_reg <= 0;
      end else if (pipeline_enable) begin
          w_reg_en_reg <= w_reg_en;
          lw_en_reg <= lw_en;
          d_in_alu_reg <= d_in_alu;
          WReg1_reg <= WReg1;
          thread_id_reg <= thread_id;
          ld_ptrs_reg <= ld_ptrs;
          head_ptr_reg <= head_ptr;
          tail_ptr_reg <= tail_ptr;
      end
  end

  assign wb1_w_reg_en = w_reg_en_reg;
  assign wb1_d_out = (ld_ptrs_reg == 2'b01) ? head_ptr_reg :
                     (ld_ptrs_reg == 2'b10) ? tail_ptr_reg :
                     (lw_en_reg) ? (d_in_mem) : (d_in_alu_reg);

  assign wb1_WReg1 = WReg1_reg;
  assign wb1_thread_id_out = thread_id_reg;

endmodule
