module decode_stage2 #(
  parameter INST_DATA_WIDTH = 32,
  parameter REG_ADDR_WIDTH  = 6,
  parameter DATA_WIDTH      = 64,
  parameter INST_ADDR_WIDTH = 9
) (
  // Global Signals
  input wire clk,
  input wire reset,
  input wire pipeline_enable,
  input wire decode_flush,

  // -------------------------------
  // Logic from ID1
  // -------------------------------
  input wire                              id1_w_mem_en,      // Store enable
  input wire                              id1_w_reg_en,      // Register file write enable
  input wire        [     DATA_WIDTH-1:0] id1_R1_out,        // Source register 1 data
  input wire        [     DATA_WIDTH-1:0] id1_R2_out,        // Source register 2 data
  input wire        [ REG_ADDR_WIDTH-1:0] id1_WReg1,         // Destination register number
  input wire        [     DATA_WIDTH-1:0] id1_ext,           // Sign/Zero extended immediate
  input wire                              id1_alu_src,       // Select immediate vs. register
  input wire        [                3:0] id1_alu_ctrl,      // ALU control bits
  input wire                              id1_lw_en,         // Load (LDR) enable
  input wire        [INST_ADDR_WIDTH-1:0] id1_pc_next_out,   // Next PC (for branch target)
  input wire                              id1_branch_en,
  input wire                              id1_mov_lsl_flag,
  input wire                              id1_mov_lsl_flag_imm_en,
  input wire        [                3:0] id1_cond,
  input wire signed [               23:0] id1_imm_24,        // Dedicated Signed immediate for branch address calculation
  input wire        [                1:0] id1_thread_id_out,
  input wire        [                1:0] id1_ld_ptrs,

  // -------------------------------
  // Logic to EX1
  // -------------------------------
  output wire                              id2_w_mem_en,      // Store enable
  output wire                              id2_w_reg_en,      // Register file write enable
  output wire        [     DATA_WIDTH-1:0] id2_R1_out,        // Source register 1 data
  output wire        [     DATA_WIDTH-1:0] id2_R2_out,        // Source register 2 data
  output wire        [ REG_ADDR_WIDTH-1:0] id2_WReg1,         // Destination register number
  output wire        [     DATA_WIDTH-1:0] id2_ext,           // Sign/Zero extended immediate
  output wire                              id2_alu_src,       // Select immediate vs. register
  output wire        [                3:0] id2_alu_ctrl,      // ALU control bits
  output wire                              id2_lw_en,         // Load (LDR) enable
  output wire        [INST_ADDR_WIDTH-1:0] id2_pc_next_out,   // Next PC (for branch target)
  output wire                              id2_branch_en,
  output wire                              id2_mov_lsl_flag,
  output wire                              id2_mov_lsl_flag_imm_en,
  output wire        [                3:0] id2_cond,
  output wire signed [               23:0] id2_imm_24,        // Dedicated Signed immediate for branch address calculation
  output wire        [                1:0] id2_thread_id_out,
  output wire        [                1:0] id2_ld_ptrs
);

  reg                              id1_w_mem_en_reg;
  reg                              id1_w_reg_en_reg;
  reg        [ REG_ADDR_WIDTH-1:0] id1_WReg1_reg;
  reg        [     DATA_WIDTH-1:0] id1_ext_reg;
  reg                              id1_alu_src_reg;
  reg        [                3:0] id1_alu_ctrl_reg;
  reg                              id1_lw_en_reg;
  reg        [INST_ADDR_WIDTH-1:0] id1_pc_next_out_reg;
  reg                              id1_branch_en_reg;
  reg                              id1_mov_lsl_flag_reg;
  reg                              id1_mov_lsl_flag_imm_en_reg;
  reg        [                3:0] id1_cond_reg;
  reg signed [               23:0] id1_imm_24_reg;
  reg        [                1:0] id1_thread_id_out_reg;
  reg        [                1:0] id1_ld_ptrs_reg;

  assign id2_R1_out              = id1_R1_out;
  assign id2_R2_out              = id1_R2_out;
  assign id2_w_mem_en            = id1_w_mem_en_reg;
  assign id2_w_reg_en            = id1_w_reg_en_reg;
  assign id2_WReg1               = id1_WReg1_reg;
  assign id2_ext                 = id1_ext_reg;
  assign id2_alu_src             = id1_alu_src_reg;
  assign id2_alu_ctrl            = id1_alu_ctrl_reg;
  assign id2_lw_en               = id1_lw_en_reg;
  assign id2_pc_next_out         = id1_pc_next_out_reg;
  assign id2_branch_en           = id1_branch_en_reg;
  assign id2_mov_lsl_flag        = id1_mov_lsl_flag_reg;
  assign id2_mov_lsl_flag_imm_en = id1_mov_lsl_flag_imm_en_reg;
  assign id2_cond                = id1_cond_reg;
  assign id2_imm_24              = id1_imm_24_reg;
  assign id2_thread_id_out       = id1_thread_id_out_reg;
  assign id2_ld_ptrs             = id1_ld_ptrs_reg;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      id1_w_mem_en_reg <= 0;
      id1_w_reg_en_reg <= 0;
      id1_WReg1_reg <= 0;
      id1_ext_reg <= 0;
      id1_alu_src_reg <= 0;
      id1_alu_ctrl_reg <= 0;
      id1_lw_en_reg <= 0;
      id1_pc_next_out_reg <= 0;
      id1_branch_en_reg <= 0;
      id1_mov_lsl_flag_reg <= 0;
      id1_mov_lsl_flag_imm_en_reg <= 0;
      id1_cond_reg <= 0;
      id1_imm_24_reg <= 0;
      id1_thread_id_out_reg <= 0;
      id1_ld_ptrs_reg <= 0;
    end else if (decode_flush) begin
      id1_w_mem_en_reg <= 0;
      id1_w_reg_en_reg <= 0;
      id1_WReg1_reg <= 0;
      id1_ext_reg <= 0;
      id1_alu_src_reg <= 0;
      id1_alu_ctrl_reg <= 0;
      id1_lw_en_reg <= 0;
      id1_pc_next_out_reg <= 0;
      id1_branch_en_reg <= 0;
      id1_mov_lsl_flag_reg <= 0;
      id1_mov_lsl_flag_imm_en_reg <= 0;
      id1_cond_reg <= 0;
      id1_imm_24_reg <= 0;
      id1_thread_id_out_reg <= 0;
      id1_ld_ptrs_reg <= 0;
    end else begin
      id1_w_mem_en_reg <= id1_w_mem_en;
      id1_w_reg_en_reg <= id1_w_reg_en;
      id1_WReg1_reg <= id1_WReg1;
      id1_ext_reg <= id1_ext;
      id1_alu_src_reg <= id1_alu_src;
      id1_alu_ctrl_reg <= id1_alu_ctrl;
      id1_lw_en_reg <= id1_lw_en;
      id1_pc_next_out_reg <= id1_pc_next_out;
      id1_branch_en_reg <= id1_branch_en;
      id1_mov_lsl_flag_reg <= id1_mov_lsl_flag;
      id1_mov_lsl_flag_imm_en_reg <= id1_mov_lsl_flag_imm_en;
      id1_cond_reg <= id1_cond;
      id1_imm_24_reg <= id1_imm_24;
      id1_thread_id_out_reg <= id1_thread_id_out;
      id1_ld_ptrs_reg <= id1_ld_ptrs;
    end
  end

endmodule
