module ex_stage1 #(
  parameter REG_ADDR_WIDTH  = 4,
  parameter DATA_WIDTH      = 64,
  parameter INST_ADDR_WIDTH = 9
) (
  input  wire                       clk,
  input  wire                       reset,
  input  wire                       pipeline_enable,
  input  wire                       ex_flush,

  // Signals from ID stage
  input  wire                       w_mem_en,
  input  wire                       w_reg_en,
  input  wire [DATA_WIDTH-1:0]      R1_in,
  input  wire [DATA_WIDTH-1:0]      R2_in,
  input  wire [REG_ADDR_WIDTH-1:0]  WReg1,
  input  wire                       immediate_en,
  input  wire [DATA_WIDTH-1:0]      immediate,
  input  wire [INST_ADDR_WIDTH-1:0] pc_next,
  input  wire                       branch_en,
  input  wire                       mov_lsl_flag,
  input  wire                       mov_lsl_flag_imm_en,
  input  wire [3:0]                 alu_ctrl,
  input  wire                       lw_en,
  input  wire [3:0]                 cond,
  input  wire signed [23:0]         imm_24,
  input  wire [1:0]                 thread_id,
  input  wire [1:0]                 ld_ptrs,

  // Pipeline outputs to EX2
  output wire                       ex1_w_mem_en,
  output wire                       ex1_w_reg_en,
  output wire [DATA_WIDTH-1:0]      ex1_alu_a_in,
  output wire [DATA_WIDTH-1:0]      ex1_alu_b_in,
  output wire [DATA_WIDTH-1:0]      ex1_R2_out,
  output wire [REG_ADDR_WIDTH-1:0]  ex1_WReg1,
  output wire [INST_ADDR_WIDTH-1:0] ex1_pc_next,
  output wire                       ex1_branch_en,
  output wire [3:0]                 ex1_alu_ctrl,
  output wire                       ex1_lw_en,
  output wire [3:0]                 ex1_cond,
  output wire signed [23:0]         ex1_imm_24,
  output wire [1:0]                 ex1_thread_id,
  output wire [1:0]                 ex1_ld_ptrs,
  output wire                       ex1_comp_two_cycle,
  output wire                       ex1_carry_out,
  output wire [31:0]                ex1_lower_result,
  output wire [63:0]                ex1_full_result,
  output wire [ 1:0]                ex1_partial_cmp_result,
  output wire                       ex1_cmp_done_stage1
);

  reg                        w_mem_en_reg;
  reg                        w_reg_en_reg;
  reg [DATA_WIDTH-1:0]       R1_in_reg;
  reg [DATA_WIDTH-1:0]       R2_in_reg;
  reg [REG_ADDR_WIDTH-1:0]   WReg1_reg;
  reg                        immediate_en_reg;
  reg [DATA_WIDTH-1:0]       immediate_reg;
  reg [INST_ADDR_WIDTH-1:0]  pc_next_reg;
  reg                        branch_en_reg;
  reg                        mov_lsl_flag_reg;
  reg                        mov_lsl_flag_imm_en_reg;
  reg [3:0]                  alu_ctrl_reg;
  reg                        lw_en_reg;
  reg [3:0]                  cond_reg;
  reg signed [23:0]          imm_24_reg;
  reg [1:0]                  thread_id_reg;
  reg [1:0]                  ld_ptrs_reg;

  assign ex1_w_mem_en            = w_mem_en_reg;
  assign ex1_w_reg_en            = w_reg_en_reg;
  assign ex1_R2_out              = R2_in_reg;
  assign ex1_WReg1               = WReg1_reg;
  assign ex1_pc_next             = pc_next_reg;
  assign ex1_branch_en           = branch_en_reg;
  assign ex1_alu_ctrl            = alu_ctrl_reg;
  assign ex1_lw_en               = lw_en_reg;
  assign ex1_cond                = cond_reg;
  assign ex1_imm_24              = imm_24_reg;
  assign ex1_thread_id           = thread_id_reg;
  assign ex1_ld_ptrs             = ld_ptrs_reg;

  wire [DATA_WIDTH-1:0] alu_a_in;
  assign alu_a_in = mov_lsl_flag_imm_en_reg ? immediate_reg : R1_in_reg;

  wire [DATA_WIDTH-1:0] alu_b_in;
  assign alu_b_in = (mov_lsl_flag_imm_en_reg) ? 0 : immediate_en_reg ? immediate_reg : R2_in_reg;

  assign ex1_alu_a_in = alu_a_in;
  assign ex1_alu_b_in = alu_b_in;



  alu_64_stage1 alu (
    .a                  (alu_a_in),
    .b                  (alu_b_in),
    .alu_ctrl           (alu_ctrl_reg),
    .lower_result       (ex1_lower_result),
    .carry_out          (ex1_carry_out),
    .do_two_cycle       (ex1_comp_two_cycle),
    .partial_cmp_result (ex1_partial_cmp_result),
    .cmp_done_stage1    (ex1_cmp_done_stage1),
    .full_result        (ex1_full_result)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      w_mem_en_reg            <= 0;
      w_reg_en_reg            <= 0;
      R1_in_reg               <= 0;
      R2_in_reg               <= 0;
      WReg1_reg               <= 0;
      immediate_en_reg        <= 0;
      immediate_reg           <= 0;
      pc_next_reg             <= 0;
      branch_en_reg           <= 0;
      mov_lsl_flag_reg        <= 0;
      mov_lsl_flag_imm_en_reg <= 0;
      alu_ctrl_reg            <= 0;
      lw_en_reg               <= 0;
      cond_reg                <= 0;
      imm_24_reg              <= 0;
      thread_id_reg           <= 0;
      ld_ptrs_reg             <= 0;
    end
    else if (ex_flush) begin
      w_mem_en_reg            <= 0;
      w_reg_en_reg            <= 0;
      R1_in_reg               <= 0;
      R2_in_reg               <= 0;
      WReg1_reg               <= 0;
      immediate_en_reg        <= 0;
      immediate_reg           <= 0;
      pc_next_reg             <= 0;
      branch_en_reg           <= 0;
      mov_lsl_flag_reg        <= 0;
      mov_lsl_flag_imm_en_reg <= 0;
      alu_ctrl_reg            <= 0;
      lw_en_reg               <= 0;
      cond_reg                <= 0;
      imm_24_reg              <= 0;
      thread_id_reg           <= 0;
      ld_ptrs_reg             <= 0;
    end
    else if (pipeline_enable) begin
      w_mem_en_reg            <= w_mem_en;
      w_reg_en_reg            <= w_reg_en;
      R1_in_reg               <= R1_in;
      R2_in_reg               <= R2_in;
      WReg1_reg               <= WReg1;
      immediate_en_reg        <= immediate_en;
      immediate_reg           <= immediate;
      pc_next_reg             <= pc_next;
      branch_en_reg           <= branch_en;
      mov_lsl_flag_reg        <= mov_lsl_flag;
      mov_lsl_flag_imm_en_reg <= mov_lsl_flag_imm_en;
      alu_ctrl_reg            <= alu_ctrl;
      lw_en_reg               <= lw_en;
      cond_reg                <= cond;
      imm_24_reg              <= imm_24;
      thread_id_reg           <= thread_id;
      ld_ptrs_reg             <= ld_ptrs;
    end
  end

endmodule
