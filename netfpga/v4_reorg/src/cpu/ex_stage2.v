module ex_stage2 #(
  parameter REG_ADDR_WIDTH  = 4,
  parameter DATA_WIDTH      = 64,
  parameter INST_ADDR_WIDTH = 9
) (
  // Global Signals
  input wire clk,
  input wire reset,
  input wire pipeline_enable,
  input wire ex_flush,

  // Logic from ID
  input wire                        w_mem_en,
  input wire                        w_reg_en,
  input wire [DATA_WIDTH-1:0]       alu_a_in,
  input wire [DATA_WIDTH-1:0]       alu_b_in,
  input wire [DATA_WIDTH-1:0]       R2_in,
  input wire [REG_ADDR_WIDTH-1:0]   WReg1,
  input wire [INST_ADDR_WIDTH-1:0]  pc_next,
  input wire                        branch_en,
  input wire [3:0]                  alu_ctrl,
  input wire                        lw_en,
  input wire [3:0]                  cond,
  input wire signed [23:0]          imm_24, // Dedicated Signed immediate for branch address calculation
  input wire [1:0]                  thread_id,
  input wire [1:0]                  ld_ptrs,
  input wire                        comp_two_cycle,
  input wire                        carry_in,
  input wire [31:0]                 lower_result,
  input wire [63:0]                 ex1_full_result,
  input wire [ 1:0]                 ex1_partial_cmp_result,
  input wire                        ex1_cmp_done_stage1,

  // Logic to MEM
  output wire                       ex2_w_mem_en,
  output wire                       ex2_w_reg_en,
  output wire [REG_ADDR_WIDTH-1:0]  ex2_WReg1,
  output wire [DATA_WIDTH-1:0]      ex2_R2_out,
  output wire [DATA_WIDTH-1:0]      ex2_alu_out,
  output wire                       ex2_lw_en,

  // Logic to IF
  output wire [INST_ADDR_WIDTH-1:0] ex2_pc_next,
  output wire                       ex2_jmp_ctrl,
  output wire [1:0]                 ex2_thread_id_out,
  output wire [1:0]                 ex2_ld_ptrs
);

  // Contains value
  // 31	N	Negative flag. Set if an arithmetic result is negative (based on the top bit of the result).
  // 30	Z	Zero flag. Set if an arithmetic/logic result is zero.
  // 29	C	Carry flag. Set if an operation produces a carry-out (e.g., unsigned overflow) or, for shift operations, if a bit is shifted out.
  // 28	V	Overflow flag. Set if an arithmetic operation causes a signed overflow.
  // 27–8	— (Reserved / Architecture-specific)	These bits may be used for other features in specific ARM architectures or remain reserved.
  // 7	I	IRQ Disable. 1 = IRQ disabled, 0 = IRQ enabled.
  // 6	F	FIQ Disable. 1 = FIQ disabled, 0 = FIQ enabled.
  // 5	T	Thumb state bit. 1 = CPU executing Thumb instructions (16-bit), 0 = CPU executing ARM instructions (32-bit).
  // 4–0	M[4:0]	Processor Mode Bits. These specify the CPU mode (User, FIQ, IRQ, Supervisor, Abort, Undefined, System, Monitor, etc.). For example, 10000b = User mode, 10011b = Supervisor mode, etc.
  reg [31:0] CPSR [0:3];

  reg                       w_mem_en_reg;
  reg                       w_reg_en_reg;
  reg [REG_ADDR_WIDTH-1:0]  WReg1_reg;
  reg [INST_ADDR_WIDTH-1:0] pc_next_reg;
  reg [3:0]                 alu_ctrl_reg;
  reg                       lw_en_reg;
  reg                       branch_en_reg;
  reg [3:0]                 cond_reg;
  reg signed [23:0]         imm_24_reg;
  reg [1:0]                 thread_id_reg;
  reg [1:0]                 ld_ptrs_reg;
  reg [DATA_WIDTH-1:0]      R2_in_reg;
  reg [DATA_WIDTH-1:0]      alu_a_in_reg;
  reg [DATA_WIDTH-1:0]      alu_b_in_reg;
  reg                       comp_two_cycle_reg;
  reg                       carry_in_reg;
  reg [31:0]                lower_result_reg;
  reg [63:0]                ex1_full_result_reg;
  reg [ 1:0]                ex1_partial_cmp_result_reg;
  reg                       ex1_cmp_done_stage1_reg;
  
  assign ex2_w_mem_en = w_mem_en_reg;
  assign ex2_w_reg_en = w_reg_en_reg;
  assign ex2_WReg1 = WReg1_reg;
  assign ex2_R2_out = R2_in_reg;
  assign ex2_lw_en = lw_en_reg;
  assign ex2_ld_ptrs = ld_ptrs_reg;

  wire [63:0] alu_out;
  assign ex2_alu_out = alu_out;

  alu_64_stage2 alu (
    .ex1_full_result(ex1_full_result_reg),
    .a_high(alu_a_in_reg[63:32]),
    .b_high(alu_b_in_reg[63:32]),
    .lower_result_in(lower_result_reg),
    .carry_in(carry_in_reg),
    .a_low(alu_a_in_reg[31:0]),
    .b_low(alu_b_in_reg[31:0]),
    .partial_cmp_result_in(ex1_partial_cmp_result_reg),
    .cmp_done_stage1_in(ex1_cmp_done_stage1_reg),
    .do_two_cycle_in(comp_two_cycle_reg),
    .alu_ctrl(alu_ctrl_reg),
    .final_result(alu_out),
    .final_overflow()
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      w_mem_en_reg <= 0;
      w_reg_en_reg <= 0;
      WReg1_reg <= 0;
      pc_next_reg <= 0;
      alu_ctrl_reg <= 0;
      lw_en_reg <= 0;
      branch_en_reg <= 0;
      cond_reg <= 0;
      imm_24_reg <= 0;
      thread_id_reg <= 0;
      ld_ptrs_reg <= 0;
      R2_in_reg <= 0;
      alu_a_in_reg <= 0;
      alu_b_in_reg <= 0;
      comp_two_cycle_reg <= 0;
      carry_in_reg <= 0;
      lower_result_reg <= 0;
      ex1_full_result_reg <= 0;
      ex1_partial_cmp_result_reg <= 0;
      ex1_cmp_done_stage1_reg <= 0;
    end else if (ex_flush) begin
      w_mem_en_reg <= 0;
      w_reg_en_reg <= 0;
      WReg1_reg <= 0;
      pc_next_reg <= 0;
      alu_ctrl_reg <= 0;
      lw_en_reg <= 0;
      branch_en_reg <= 0;
      cond_reg <= 0;
      imm_24_reg <= 0;
      thread_id_reg <= 0;
      ld_ptrs_reg <= 0;
      R2_in_reg <= 0;
      alu_a_in_reg <= 0;
      alu_b_in_reg <= 0;
      comp_two_cycle_reg <= 0;
      carry_in_reg <= 0;
      lower_result_reg <= 0;
      ex1_full_result_reg <= 0;
      ex1_partial_cmp_result_reg <= 0;
      ex1_cmp_done_stage1_reg <= 0;
    end else if (pipeline_enable) begin
      w_mem_en_reg <= w_mem_en;
      w_reg_en_reg <= w_reg_en;
      WReg1_reg <= WReg1;
      pc_next_reg <= pc_next;
      alu_ctrl_reg <= alu_ctrl;
      lw_en_reg <= lw_en;
      branch_en_reg <= branch_en;
      cond_reg <= cond;
      imm_24_reg <= imm_24;
      thread_id_reg <= thread_id;
      ld_ptrs_reg <= ld_ptrs;
      R2_in_reg <= R2_in;
      alu_a_in_reg <= alu_a_in;
      alu_b_in_reg <= alu_b_in;
      comp_two_cycle_reg <= comp_two_cycle;
      carry_in_reg <= carry_in;
      lower_result_reg <= lower_result;
      ex1_full_result_reg <= ex1_full_result;
      ex1_partial_cmp_result_reg <= ex1_partial_cmp_result;
      ex1_cmp_done_stage1_reg <= ex1_cmp_done_stage1;
    end
  end

  //----------------------------------------------------------------------
  // Branch Target Calculation
  //----------------------------------------------------------------------
  assign ex2_pc_next = pc_next_reg + (imm_24_reg[INST_ADDR_WIDTH-1:0] + 1);

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      CPSR[0] <= 0;
      CPSR[1] <= 0;
      CPSR[2] <= 0;
      CPSR[3] <= 0;
    end else begin
      // Only update CPSR when CMP instructions for now (Actuall update every insturctions..)
      if (alu_ctrl_reg[3:1] == 3'b101) begin
        if (alu_out == 0) begin  // Zero Case
          // Set Z (Zero)
          CPSR[thread_id_reg][30] <= 1;
        end else begin
          CPSR[thread_id_reg][30] <= 0;
        end

        if (alu_out == 2) begin  // Greater than Case
          // Set C (Carry)
          CPSR[thread_id_reg][29] <= 1;
        end else begin
          CPSR[thread_id_reg][29] <= 0;
        end

        if (alu_out == 1) begin  // Less than Case
          // Set N (Negative)
          CPSR[thread_id_reg][31] <= 1;
        end else begin
          CPSR[thread_id_reg][31] <= 0;
        end
      end
    end
  end

  //----------------------------------------------------------------------
  // Branch Decision
  //----------------------------------------------------------------------
  // ex2_alu_out_reg is the result from a prior CMP:
  //   0 => a == b
  //   1 => a < b
  //   2 => a > b
  //   3 => otherwise
  // We do B, BGE, BLE by checking ex2_alu_out_reg:
  //   B  => cond=1110 (unconditional)
  //   BGE=> cond=1010 => ex2_alu_out_reg==0 (equal) or 2 (greater)
  //   BLE=> cond=1101 => ex2_alu_out_reg==0 (equal) or 1 (less)

  // In your code, you used 0xA, 0xD for cond. That can vary. Example:
  assign ex2_jmp_ctrl = branch_en_reg && ((cond_reg == 4'hE)  // unconditional
      || (cond_reg == 4'hA && (CPSR[thread_id_reg][30] == 1 || CPSR[thread_id_reg][29] == 1))  // BGE
      || (cond_reg == 4'hD && (CPSR[thread_id_reg][30] == 1 || CPSR[thread_id_reg][31] == 1))  // BLE
      ) ? 1'b1 : 1'b0;

  assign ex2_thread_id_out = thread_id_reg;

endmodule
