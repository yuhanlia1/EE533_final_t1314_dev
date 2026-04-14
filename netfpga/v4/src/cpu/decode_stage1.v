module decode_stage1 #(
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
  // Logic from SW (software reads/writes to the register file)
  // -------------------------------
  input wire                      sw_rf_we,
  input wire                      sw_rf_re,
  input wire [REG_ADDR_WIDTH-1:0] sw_rf_addr,
  input wire [    DATA_WIDTH-1:0] sw_rf_data,

  // -------------------------------
  // Logic from IF2
  // -------------------------------
  input wire [INST_DATA_WIDTH-1:0] inst,
  input wire [INST_ADDR_WIDTH-1:0] pc_next,
  input wire [1:0] thread_id,

  // -------------------------------
  // Logic from WB (write-back stage)
  // -------------------------------
  input wire                      wb_we,
  input wire [REG_ADDR_WIDTH-1:0] wb_waddr,
  input wire [    DATA_WIDTH-1:0] wb_wdata,
  input wire [               1:0] wb_thread_id,

  // -------------------------------
  // Outputs to ID2
  // -------------------------------
  output wire                              id1_w_mem_en,      // Store enable
  output wire                              id1_w_reg_en,      // Register file write enable
  output wire        [     DATA_WIDTH-1:0] id1_R1_out,        // Source register 1 data
  output wire        [     DATA_WIDTH-1:0] id1_R2_out,        // Source register 2 data
  output wire        [ REG_ADDR_WIDTH-1:0] id1_WReg1,         // Destination register number
  output wire        [     DATA_WIDTH-1:0] id1_ext,           // Sign/Zero extended immediate
  output wire                              id1_alu_src,       // Select immediate vs. register
  output wire        [                3:0] id1_alu_ctrl,      // ALU control bits
  output wire                              id1_lw_en,         // Load (LDR) enable
  output wire        [INST_ADDR_WIDTH-1:0] id1_pc_next_out,   // Next PC (for branch target)
  output wire                              id1_branch_en,
  output wire                              id1_mov_lsl_flag,
  output wire                              id1_mov_lsl_flag_imm_en,
  output wire        [                3:0] id1_cond,
  output wire signed [               23:0] id1_imm_24,        // Dedicated Signed immediate for branch address calculation
  output wire        [                1:0] id1_thread_id_out,
  output wire        [                1:0] id1_ld_ptrs
);

  //----------------------------------------------------------------------
  // Stage registers
  //----------------------------------------------------------------------
  reg [INST_DATA_WIDTH-1:0] inst_reg;
  reg [INST_ADDR_WIDTH-1:0] pc_next_reg;
  reg [                1:0] id_thread_id_reg;

  //----------------------------------------------------------------------
  // Latch inputs to stage registers on clock
  //----------------------------------------------------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      inst_reg         <= 0;
      pc_next_reg      <= {INST_ADDR_WIDTH{1'b0}};
      id_thread_id_reg <= 0;
    end else if (decode_flush) begin
      inst_reg         <= 0;
      pc_next_reg      <= {INST_ADDR_WIDTH{1'b0}};
      id_thread_id_reg <= 0;
    end else if (pipeline_enable) begin
      inst_reg         <= inst;
      pc_next_reg      <= pc_next;
      id_thread_id_reg <= thread_id;
    end
  end

  //----------------------------------------------------------------------
  // Instruction Field Extraction
  //----------------------------------------------------------------------
  wire        [ 3:0] cond            = inst_reg[31:28];  // Condition bits
  wire        [ 3:0] general_opcode  = inst_reg[24:21];  // e.g., ADD=0100, SUB=0010, CMP=1010, MOV=1101
  wire               imm_flag        = inst_reg[25];     // 1 => immediate, 0 => register
  wire        [ 4:0] ld_st_opcode    = inst_reg[24:20];  // For LDR/STR detection
  wire        [ 3:0] br_opcode       = inst_reg[27:24];  // For branch detection
  wire        [ 3:0] Rn              = inst_reg[19:16];  // Source register #1
  wire        [ 3:0] Rd              = inst_reg[15:12];  // Destination register
  wire        [11:0] imm_12          = inst_reg[11:0];   // 12-bit immediate
  wire        [ 4:0] imm_5           = inst_reg[11:7];   // 8-bit immediate
  wire signed [23:0] imm_24          = inst_reg[23:0];   // 24-bit immediate (for branch)
  wire        [ 3:0] Rm              = inst_reg[3:0];    // Source register #2

  //----------------------------------------------------------------------
  // Basic Decoding
  //----------------------------------------------------------------------
  //   ADD/SUB = general_opcode == 4'h4 or 4'h2
  //   CMP     = general_opcode == 4'hA
  //   MOV/LSL = general_opcode == 4'hD (not fully ARM standard, but simplified)
  //   B, BGE, BLE => br_opcode == 4'hA
  //   LDR/STR => ld_st_opcode == 5'h11, 5'h19 (LDR), 5'h10, 5'h18 (STR)

  // For store
  wire add_sub_flag = (general_opcode == 4'h4 || general_opcode == 4'h2 || general_opcode == 4'h1);
  wire cmp_flag     = (general_opcode == 4'hA);
  wire mov_lsl_flag = (general_opcode == 4'hD);
  wire br_flag      = (br_opcode == 4'hA);
  wire ld_flag      = (ld_st_opcode == 5'h11 || ld_st_opcode == 5'h19 || ld_st_opcode == 5'h1D || ld_st_opcode == 5'h1B);
  wire st_flag      = (ld_st_opcode == 5'h10 || ld_st_opcode == 5'h18);

  // Register-file write enable: ADD/SUB, MOV/LSL, or LDR => 1, else 0
  assign id1_w_reg_en = (decode_flush) ? 0 : (add_sub_flag || mov_lsl_flag || ld_flag) ? 1'b1 : 1'b0;

  // Memory write enable: STR => 1, else 0
  assign id1_w_mem_en = (decode_flush) ? 0 : st_flag ? 1'b1 : 1'b0;

  // Load word enable (for controlling WB stage selection)
  assign id1_lw_en = ld_flag;

  // Destination register
  assign id1_WReg1 = {2'b0, Rd};

  wire ld_imm_flag = ld_flag ? !imm_flag : 0;

  // Decide ALU immediate or register source
  assign id1_alu_src = imm_flag || ld_imm_flag || st_flag || mov_lsl_flag;

  // Branch Enable (Is branch Instructions)
  assign id1_branch_en = br_flag;

  // Assign PC Next
  assign id1_pc_next_out = pc_next_reg;

  // Assign cond
  assign id1_cond = cond;

  assign id1_imm_24 = imm_24;

  assign id1_ld_ptrs = (ld_st_opcode == 5'h1D) ? (2'b01) :
                      (ld_st_opcode == 5'h1B) ? (2'b10) : 2'b00;

  assign id1_thread_id_out = id_thread_id_reg;

  assign id1_mov_lsl_flag = mov_lsl_flag;
  assign id1_mov_lsl_flag_imm_en = mov_lsl_flag && imm_flag;

  //----------------------------------------------------------------------
  // ALU Control
  //----------------------------------------------------------------------
  // The top 3 bits of alu_ctrl => ALU operation (ADD=000, SUB=001, CMP=101, SHIFT=110, etc.)
  // The bottom bit can differentiate sub-ops (e.g., shift left vs right), if needed.
  //
  // In your original design, you used:
  //   4'b0000 => ADD
  //   4'b0010 => SUB
  //   4'b1010 => CMP
  //   4'b1100 => SHIFT (LSL)

  assign id1_alu_ctrl =
    // For ADD (4'h4) or LDR (some are 5'h19, 5'h11?), STR (5'h18, 5'h10) => we treat them as ADD or SUB for address calc
    (general_opcode == 4'h1) ? 4'b0100 : 
    ((general_opcode == 4'h4) || // ADD
     (ld_st_opcode == 5'h19 || ld_st_opcode == 5'h18)) ? 4'b0000 :  // top bits=000 => ALU_ADD

    // For SUB (4'h2) or LDR/STR with different bit (5'h11, 5'h10) => top bits=001 => ALU_SUB
    ((general_opcode == 4'h2) || 
     (ld_st_opcode == 5'h11 || ld_st_opcode == 5'h10)) ? 4'b0010 :  // top bits=001 => ALU_SUB

    // For CMP
    (general_opcode == 4'hA) ? 4'b1010 :  // top bits=101 => ALU_CMP

    // For MOV/LSL
    (mov_lsl_flag) ? 4'b1100 :  // top bits=110 => SHIFT (LSL)

    // default
    4'b0000;  // e.g., treat as ADD if not recognized

  //----------------------------------------------------------------------
  // Immediate Extension
  //----------------------------------------------------------------------
  // For ADD/SUB/MOV => use 5-bit imm (imm_8)
  // For CMP, LDR, STR => use 12-bit imm (imm_12)
  // sign-extend!! Not Zero Extend!
  assign id1_ext = // * mov/lsl seems to be conflicting with port selection for Rm and alu, therefore muxing signals to utilize alu correctly.
    ((add_sub_flag || mov_lsl_flag) && !imm_flag) ? {{59{imm_5[4]}},  imm_5} :
    ((add_sub_flag || mov_lsl_flag) && imm_flag) ? {{52{imm_12[11]}},  imm_12} :
    (cmp_flag || ld_flag || st_flag) ? {{52{imm_12[11]}}, imm_12} : 64'h0;

  //----------------------------------------------------------------------
  // Register File Access (mem_RF)
  //----------------------------------------------------------------------
  wire rf_we;
  wire [REG_ADDR_WIDTH-1:0] rf_waddr;
  wire [DATA_WIDTH-1:0] rf_wdata;
  wire [REG_ADDR_WIDTH-1:0] r0addr;
  wire [REG_ADDR_WIDTH-1:0] r1addr;

  // Combine SW writes + pipeline writes with priority
  assign rf_we    = (sw_rf_we || wb_we);
  assign rf_waddr = (sw_rf_we) ? sw_rf_addr : {wb_thread_id, wb_waddr[3:0]};
  assign rf_wdata = (sw_rf_we) ? sw_rf_data : wb_wdata;

  // For read port 0, either software read or instruction's Rn
  assign r0addr = (sw_rf_re) ? sw_rf_addr :
                  (mov_lsl_flag) ? {id_thread_id_reg, Rm}: // mov/lsl
                  {id_thread_id_reg, Rn};                  // * same as above

  // For read port 1, we read Rm
  assign r1addr = st_flag ? {id_thread_id_reg, Rd} : {id_thread_id_reg, Rm};
  wire [DATA_WIDTH-1:0] raw_R1_out, raw_R2_out;

  mem_RF #(
    .ADDR_WIDTH(REG_ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) REG_FILE (
    .clk   (clk),
    .we    (rf_we),
    .waddr (rf_waddr),
    .wdata (rf_wdata),
    .r0addr(r0addr),
    .r0data(id1_R1_out),
    .r1addr(r1addr),
    .r1data(id1_R2_out)
  );

endmodule
