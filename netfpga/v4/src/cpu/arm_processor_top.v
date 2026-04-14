module arm_64_top #(
  parameter NETWORK_DATA_WIDTH = 64,
  parameter NETWORK_CTRL_WIDTH = NETWORK_DATA_WIDTH / 8,
  parameter DATA_WIDTH = 64,
  parameter INST_DATA_WIDTH = 32,  // 32-bit instructions
  parameter INST_ADDR_WIDTH = 9,   // 512-deep instruction memory (2^9 = 512)
  parameter MEM_ADDR_WIDTH = 8,    // 256-deep data memory (2^8 = 256)
  parameter REG_ADDR_WIDTH = 6     // 8-deep Register Files (2^4 = 16), we have 4 copies of Register Files, hence 2^(2+4) = 2^6 = 64
) (

  // Network Data Interfaces
  input  wire [NETWORK_DATA_WIDTH-1:0] nw_in_data,
  input  wire [NETWORK_CTRL_WIDTH-1:0] nw_in_ctrl,
  input  wire                          nw_in_wr,
  output wire                          nw_in_rdy,

  output wire [NETWORK_DATA_WIDTH-1:0] nw_out_data,
  output wire [NETWORK_CTRL_WIDTH-1:0] nw_out_ctrl,
  output wire                          nw_out_wr,
  input  wire                          nw_out_rdy,

  // SW Interfaces
  input wire [31:0] sw_i_mem_addr,
  input wire [31:0] sw_i_mem_wdata,
  input wire [31:0] sw_d_mem_addr,

  // HW Interfaces
  output reg [31:0] hw_i_mem_word_out,     //  bits [31:0]
  output reg [31:0] hw_d_mem_word_out_0,   //  bits [31:0]
  output reg [31:0] hw_d_mem_word_out_1,   //  bits [63:32]

  // Generic MMIO peripheral bus (decoupled from GPU)
  output wire        ext_mmio_wr_en,
  output wire        ext_mmio_rd_en,
  output wire [7:0]  ext_mmio_addr,
  output wire [31:0] ext_mmio_wdata,
  input  wire [31:0] ext_mmio_rdata,

  // CPU processing handshake (decoupled from GPU)
  output wire        cpu_done,      // one-cycle pulse: CPU finished 500-cycle window
  input  wire        ext_continue,  // controller: proceed to NET_DRAIN
  input  wire        ext_drop,      // controller: drop packet, return to IDLE

  input wire clk,
  input wire reset
);
  // ------------------------------------------------------------------------------------
  // Global Signal
  wire pipeline_enable;
  assign pipeline_enable = 1;

  wire mem_fetch_reset;
  wire mem_decode_flush;
  wire mem_ex_flush;
  wire mem_wb_flush;

  // ------------------------------------------------------------------------------------
  // NETWORK HANDSHAKE REGISTER SLICE Signals
  // ------------------------------------------------------------------------------------ 
  wire [NETWORK_DATA_WIDTH-1:0] rs_nw_in_data;
  wire [NETWORK_CTRL_WIDTH-1:0] rs_nw_in_ctrl;
  wire                          rs_nw_in_wr;
  wire                          mem_nw_in_rdy;

  wire [NETWORK_DATA_WIDTH-1:0] mem_nw_out_data;
  wire [NETWORK_CTRL_WIDTH-1:0] mem_nw_out_ctrl;
  wire                          mem_nw_out_wr;
  wire                          rs_nw_out_rdy;

  // ------------------------------------------------------------------------------------
  // IF1
  // ------------------------------------------------------------------------------------
  // Outputs
  wire [INST_DATA_WIDTH-1:0] if1_inst_out;
  wire [INST_ADDR_WIDTH-1:0] if1_pc_next_out;
  wire [1:0]                 if1_thread_id_out;
  wire                       if1_is_noop;

  // ------------------------------------------------------------------------------------
  // IF2
  // ------------------------------------------------------------------------------------
  // Outputs
  wire [INST_DATA_WIDTH-1:0] if2_inst_out;
  wire [INST_ADDR_WIDTH-1:0] if2_pc_next_out;
  wire [1:0]                 if2_thread_id_out;

  // ------------------------------------------------------------------------------------
  // ID1
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                       id1_w_mem_en;
  wire                       id1_w_reg_en;
  wire [DATA_WIDTH-1:0]      id1_R1_out;
  wire [DATA_WIDTH-1:0]      id1_R2_out;
  wire [REG_ADDR_WIDTH-1:0]  id1_WReg1;
  wire [INST_ADDR_WIDTH-1:0] id1_pc_next_out;
  wire [DATA_WIDTH-1:0]      id1_ext;
  wire [3:0]                 id1_alu_ctrl;
  wire                       id1_alu_src;
  wire                       id1_lw_en;
  wire                       id1_branch_en;
  wire                       id1_mov_lsl_flag;
  wire                       id1_mov_lsl_flag_imm_en;
  wire [3:0]                 id1_cond;
  wire signed [23:0]         id1_imm_24;
  wire [1:0]                 id1_thread_id_out;
  wire [1:0]                 id1_ld_ptrs;

  // ------------------------------------------------------------------------------------
  // ID2
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                       id2_w_mem_en;
  wire                       id2_w_reg_en;
  wire [DATA_WIDTH-1:0]      id2_R1_out;
  wire [DATA_WIDTH-1:0]      id2_R2_out;
  wire [REG_ADDR_WIDTH-1:0]  id2_WReg1;
  wire [INST_ADDR_WIDTH-1:0] id2_pc_next_out;
  wire [DATA_WIDTH-1:0]      id2_ext;
  wire [3:0]                 id2_alu_ctrl;
  wire                       id2_alu_src;
  wire                       id2_lw_en;
  wire                       id2_branch_en;
  wire                       id2_mov_lsl_flag;
  wire                       id2_mov_lsl_flag_imm_en;
  wire [3:0]                 id2_cond;
  wire signed [23:0]         id2_imm_24;
  wire [1:0]                 id2_thread_id_out;
  wire [1:0]                 id2_ld_ptrs;

  // ------------------------------------------------------------------------------------
  // EX1
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                       ex1_w_mem_en;
  wire                       ex1_w_reg_en;
  wire [DATA_WIDTH-1:0]      ex1_alu_a_in;
  wire [DATA_WIDTH-1:0]      ex1_alu_b_in;
  wire [DATA_WIDTH-1:0]      ex1_R2_out;
  wire [DATA_WIDTH-1:0]      ex1_WReg1;
  wire [INST_ADDR_WIDTH-1:0] ex1_pc_next;
  wire                       ex1_branch_en;
  wire [3:0]                 ex1_alu_ctrl;
  wire                       ex1_lw_en;
  wire [3:0]                 ex1_cond;
  wire signed [23:0]         ex1_imm_24;
  wire [1:0]                 ex1_thread_id;
  wire [1:0]                 ex1_ld_ptrs;
  wire                       ex1_comp_two_cycle;
  wire                       ex1_carry_out;
  wire [31:0]                ex1_lower_result;
  wire [63:0]                ex1_full_result;
  wire [ 1:0]                ex1_partial_cmp_result;
  wire                       ex1_cmp_done_stage1;

  // ------------------------------------------------------------------------------------
  // EX2
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                       ex2_w_mem_en;
  wire                       ex2_w_reg_en;
  wire [REG_ADDR_WIDTH-1:0]  ex2_WReg1;
  wire [DATA_WIDTH-1:0]      ex2_R2_out;
  wire [DATA_WIDTH-1:0]      ex2_alu_out;
  wire                       ex2_lw_en;
  wire [INST_ADDR_WIDTH-1:0] ex2_pc_next;
  wire                       ex2_jmp_ctrl;
  wire [1:0]                 ex2_thread_id_out;
  wire [1:0]                 ex2_ld_ptrs;

  // ------------------------------------------------------------------------------------
  // MEM
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                       mem_w_reg_en;
  wire [DATA_WIDTH-1:0]      mem_d_out;
  wire [DATA_WIDTH-1:0]      mem_alu_out;
  wire [REG_ADDR_WIDTH-1:0]  mem_WReg1;
  wire                       mem_lw_en;
  wire [INST_ADDR_WIDTH-1:0] mem_pc_next;
  wire                       mem_jmp_ctrl;
  wire [1:0]                 mem_thread_id_out;
  wire [               1:0]  mem_ld_ptrs;
  wire [MEM_ADDR_WIDTH-1:0]  mem_head_ptr;
  wire [MEM_ADDR_WIDTH-1:0]  mem_tail_ptr;

  // ------------------------------------------------------------------------------------
  // WB1
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                      wb1_w_reg_en;
  wire [DATA_WIDTH-1:0]     wb1_d_out;
  wire [REG_ADDR_WIDTH-1:0] wb1_WReg1;
  wire [1:0]                wb1_thread_id_out;

  // ------------------------------------------------------------------------------------
  // WB2
  // ------------------------------------------------------------------------------------
  // Outputs
  wire                      wb2_w_reg_en;
  wire [DATA_WIDTH-1:0]     wb2_d_out;
  wire [REG_ADDR_WIDTH-1:0] wb2_WReg1;
  wire [1:0]                wb2_thread_id_out;

  // ------------------------------------------------------------------------------------
  // FETCH STAGE1
  // ------------------------------------------------------------------------------------
  fetch_stage1 #(
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH),
    .INST_DATA_WIDTH (INST_DATA_WIDTH)
  ) IF1 (
    .clk               (clk),
    .reset             (reset),
    .pipeline_enable   (pipeline_enable),
    .fetch_reset       (mem_fetch_reset),

    // Logic from SW
    .sw_i_mem_we       (sw_i_mem_addr[31]),
    .sw_i_mem_re       (sw_i_mem_addr[30]),
    .sw_i_mem_addr     (sw_i_mem_addr[INST_ADDR_WIDTH-1:0]),
    .sw_i_mem_data     (sw_i_mem_wdata[INST_DATA_WIDTH-1:0]),

    // Logic from mem
    .jmp_ctrl          (mem_jmp_ctrl),
    .jmp_pc            (mem_pc_next),
    .jmp_thread_id     (mem_thread_id_out),

    // Logic to ID2 Stage
    .if1_inst_out      (if1_inst_out),
    .if1_pc_next_out   (if1_pc_next_out),
    .if1_thread_id_out (if1_thread_id_out),
    .if1_is_noop       (if1_is_noop)
  );

  // ------------------------------------------------------------------------------------
  // FETCH STAGE2
  // ------------------------------------------------------------------------------------
  fetch_stage2 #(
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH),
    .INST_DATA_WIDTH (INST_DATA_WIDTH)
  ) IF2 (
    .clk               (clk),
    .reset             (reset),
    .pipeline_enable   (pipeline_enable),
    .fetch_reset       (mem_fetch_reset),

    // Logic from mem
    .if1_inst          (if1_inst_out),
    .if1_pc_next       (if1_pc_next_out),
    .if1_thread_id     (if1_thread_id_out),
    .if1_is_noop       (if1_is_noop),

    // Logic to ID1 Stage
    .if2_inst_out      (if2_inst_out),
    .if2_pc_next_out   (if2_pc_next_out),
    .if2_thread_id_out (if2_thread_id_out)
  );

  // ------------------------------------------------------------------------------------
  // DECODE STAGE1
  // ------------------------------------------------------------------------------------
  decode_stage1 #(
    .INST_DATA_WIDTH (INST_DATA_WIDTH),
    .REG_ADDR_WIDTH  (REG_ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH)
  ) ID1 (
    .clk                     (clk),
    .reset                   (reset),
    .pipeline_enable         (pipeline_enable),
    .decode_flush            (mem_decode_flush),

    // Logic from SW
    .sw_rf_we                (0),
    .sw_rf_re                (0),
    .sw_rf_addr              (0),
    .sw_rf_data              (0),

    // Logic from IF2
    .inst                    (if2_inst_out),
    .pc_next                 (if2_pc_next_out),
    .thread_id               (if2_thread_id_out),

    // Logic from WB
    .wb_we                   (wb2_w_reg_en),
    .wb_waddr                (wb2_WReg1),
    .wb_wdata                (wb2_d_out),
    .wb_thread_id            (wb2_thread_id_out),

    // Logic to ID2
    .id1_w_mem_en            (id1_w_mem_en),
    .id1_w_reg_en            (id1_w_reg_en),
    .id1_R1_out              (id1_R1_out),
    .id1_R2_out              (id1_R2_out),
    .id1_WReg1               (id1_WReg1),
    .id1_ext                 (id1_ext),
    .id1_alu_src             (id1_alu_src),
    .id1_alu_ctrl            (id1_alu_ctrl),
    .id1_lw_en               (id1_lw_en),
    .id1_branch_en           (id1_branch_en),
    .id1_mov_lsl_flag        (id1_mov_lsl_flag),
    .id1_mov_lsl_flag_imm_en (id1_mov_lsl_flag_imm_en),
    .id1_pc_next_out         (id1_pc_next_out),
    .id1_cond                (id1_cond),
    .id1_imm_24              (id1_imm_24),
    .id1_thread_id_out       (id1_thread_id_out),
    .id1_ld_ptrs             (id1_ld_ptrs)
  );

  // ------------------------------------------------------------------------------------
  // DECODE STAGE2
  // ------------------------------------------------------------------------------------
  decode_stage2 #(
    .INST_DATA_WIDTH (INST_DATA_WIDTH),
    .REG_ADDR_WIDTH  (REG_ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH)
  ) ID2 (
    .clk                    (clk),
    .reset                  (reset),
    .pipeline_enable        (pipeline_enable),
    .decode_flush           (mem_decode_flush),

    // Logic from ID1
    .id1_w_mem_en            (id1_w_mem_en),
    .id1_w_reg_en            (id1_w_reg_en),
    .id1_R1_out              (id1_R1_out),
    .id1_R2_out              (id1_R2_out),
    .id1_WReg1               (id1_WReg1),
    .id1_ext                 (id1_ext),
    .id1_alu_src             (id1_alu_src),
    .id1_alu_ctrl            (id1_alu_ctrl),
    .id1_lw_en               (id1_lw_en),
    .id1_branch_en           (id1_branch_en),
    .id1_mov_lsl_flag        (id1_mov_lsl_flag),
    .id1_mov_lsl_flag_imm_en (id1_mov_lsl_flag_imm_en),
    .id1_pc_next_out         (id1_pc_next_out),
    .id1_cond                (id1_cond),
    .id1_imm_24              (id1_imm_24),
    .id1_thread_id_out       (id1_thread_id_out),
    .id1_ld_ptrs             (id1_ld_ptrs),

    // Logic to EX Stage
    .id2_w_mem_en            (id2_w_mem_en),
    .id2_w_reg_en            (id2_w_reg_en),
    .id2_R1_out              (id2_R1_out),
    .id2_R2_out              (id2_R2_out),
    .id2_WReg1               (id2_WReg1),
    .id2_ext                 (id2_ext),
    .id2_alu_src             (id2_alu_src),
    .id2_alu_ctrl            (id2_alu_ctrl),
    .id2_lw_en               (id2_lw_en),
    .id2_branch_en           (id2_branch_en),
    .id2_mov_lsl_flag        (id2_mov_lsl_flag),
    .id2_mov_lsl_flag_imm_en (id2_mov_lsl_flag_imm_en),
    .id2_pc_next_out         (id2_pc_next_out),
    .id2_cond                (id2_cond),
    .id2_imm_24              (id2_imm_24),
    .id2_thread_id_out       (id2_thread_id_out),
    .id2_ld_ptrs             (id2_ld_ptrs)
  );

  // ------------------------------------------------------------------------------------
  // EXECUTE STAGE1
  // ------------------------------------------------------------------------------------
  ex_stage1 #(
    .REG_ADDR_WIDTH  (REG_ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH)
  ) EX1 (
    .clk                 (clk),
    .reset               (reset),
    .pipeline_enable     (pipeline_enable),
    .ex_flush            (mem_ex_flush),

    // Logic from Decode Stage
    .w_mem_en                (id2_w_mem_en),
    .w_reg_en                (id2_w_reg_en),
    .R1_in                   (id2_R1_out),
    .R2_in                   (id2_R2_out),
    .WReg1                   (id2_WReg1),
    .thread_id               (id2_thread_id_out),
    .immediate_en            (id2_alu_src),
    .immediate               (id2_ext),
    .branch_en               (id2_branch_en),
    .mov_lsl_flag            (id2_mov_lsl_flag),
    .mov_lsl_flag_imm_en     (id2_mov_lsl_flag_imm_en),
    .pc_next                 (id2_pc_next_out),
    .alu_ctrl                (id2_alu_ctrl),
    .lw_en                   (id2_lw_en),
    .cond                    (id2_cond),
    .imm_24                  (id2_imm_24),
    .ld_ptrs                 (id2_ld_ptrs),

    // Logic to EX2 Stage
    .ex1_w_mem_en            (ex1_w_mem_en),
    .ex1_w_reg_en            (ex1_w_reg_en),
    .ex1_alu_a_in            (ex1_alu_a_in),
    .ex1_alu_b_in            (ex1_alu_b_in),
    .ex1_R2_out              (ex1_R2_out),
    .ex1_WReg1               (ex1_WReg1),
    .ex1_pc_next             (ex1_pc_next),
    .ex1_branch_en           (ex1_branch_en),
    .ex1_alu_ctrl            (ex1_alu_ctrl),
    .ex1_lw_en               (ex1_lw_en),
    .ex1_cond                (ex1_cond),
    .ex1_imm_24              (ex1_imm_24),
    .ex1_thread_id           (ex1_thread_id),
    .ex1_ld_ptrs             (ex1_ld_ptrs),
    .ex1_comp_two_cycle      (ex1_comp_two_cycle),
    .ex1_carry_out           (ex1_carry_out),
    .ex1_lower_result        (ex1_lower_result),
    .ex1_full_result         (ex1_full_result),
    .ex1_partial_cmp_result  (ex1_partial_cmp_result),
    .ex1_cmp_done_stage1     (ex1_cmp_done_stage1)
  );

  // ------------------------------------------------------------------------------------
  // EXECUTE STAGE2
  // ------------------------------------------------------------------------------------
  ex_stage2 #(
    .REG_ADDR_WIDTH  (REG_ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .INST_ADDR_WIDTH (INST_ADDR_WIDTH)
  ) EX2 (
    .clk                    (clk),
    .reset                  (reset),
    .pipeline_enable        (pipeline_enable),
    .ex_flush               (mem_ex_flush),

    // Logic from Decode Stage
    .w_mem_en               (ex1_w_mem_en),
    .w_reg_en               (ex1_w_reg_en),
    .alu_a_in               (ex1_alu_a_in),
    .alu_b_in               (ex1_alu_b_in),
    .R2_in                  (ex1_R2_out),
    .WReg1                  (ex1_WReg1),
    .pc_next                (ex1_pc_next),
    .branch_en              (ex1_branch_en),
    .alu_ctrl               (ex1_alu_ctrl),
    .lw_en                  (ex1_lw_en),
    .cond                   (ex1_cond),
    .imm_24                 (ex1_imm_24),
    .thread_id              (ex1_thread_id),
    .ld_ptrs                (ex1_ld_ptrs),
    .comp_two_cycle         (ex1_comp_two_cycle),
    .carry_in               (ex1_carry_out),
    .lower_result           (ex1_lower_result),
    .ex1_full_result        (ex1_full_result),
    .ex1_partial_cmp_result (ex1_partial_cmp_result),
    .ex1_cmp_done_stage1    (ex1_cmp_done_stage1),

    // Logic to MEM Stage
    .ex2_w_mem_en           (ex2_w_mem_en),
    .ex2_w_reg_en           (ex2_w_reg_en),
    .ex2_alu_out            (ex2_alu_out),
    .ex2_R2_out             (ex2_R2_out),
    .ex2_WReg1              (ex2_WReg1),
    .ex2_lw_en              (ex2_lw_en),
    .ex2_pc_next            (ex2_pc_next),
    .ex2_jmp_ctrl           (ex2_jmp_ctrl),
    .ex2_thread_id_out      (ex2_thread_id_out),
    .ex2_ld_ptrs            (ex2_ld_ptrs)
  );

  // ------------------------------------------------------------------------------------
  // MEMORY STAGE
  // ------------------------------------------------------------------------------------
  mem_stage #(
    .NETWORK_DATA_WIDTH (NETWORK_DATA_WIDTH),
    .NETWORK_CTRL_WIDTH (NETWORK_CTRL_WIDTH),
    .INST_ADDR_WIDTH    (INST_ADDR_WIDTH),
    .REG_ADDR_WIDTH     (REG_ADDR_WIDTH),
    .MEM_ADDR_WIDTH     (MEM_ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH)
  ) MEM (
    .clk               (clk),
    .reset             (reset),
    .pipeline_enable   (pipeline_enable),

    // Network Interfaces
    .nw_in_data        (rs_nw_in_data),
    .nw_in_ctrl        (rs_nw_in_ctrl),
    .nw_in_wr          (rs_nw_in_wr),
    .nw_in_rdy         (mem_nw_in_rdy),
    .nw_out_data       (mem_nw_out_data),
    .nw_out_ctrl       (mem_nw_out_ctrl),
    .nw_out_wr         (mem_nw_out_wr),
    .nw_out_rdy        (rs_nw_out_rdy),

    // Logic from SW
    .sw_d_mem_we       (0),
    .sw_d_mem_re       (sw_d_mem_addr[30]),
    .sw_d_mem_addr     ({56'b0, sw_d_mem_addr[MEM_ADDR_WIDTH-1:0]}),
    .sw_d_mem_data     (0),

    .ext_mmio_wr_en    (ext_mmio_wr_en),
    .ext_mmio_rd_en    (ext_mmio_rd_en),
    .ext_mmio_addr     (ext_mmio_addr),
    .ext_mmio_wdata    (ext_mmio_wdata),
    .ext_mmio_rdata    (ext_mmio_rdata),
    .cpu_done          (cpu_done),
    .ext_continue      (ext_continue),
    .ext_drop          (ext_drop),

    // Logic from EX
    .lw_en             (ex2_lw_en),
    .w_mem_en          (ex2_w_mem_en),
    .w_reg_en          (ex2_w_reg_en),
    .alu_in            (ex2_alu_out),
    .R2_in             (ex2_R2_out),
    .WReg1             (ex2_WReg1),
    .pc_next           (ex2_pc_next),
    .jmp_ctrl          (ex2_jmp_ctrl),
    .thread_id         (ex2_thread_id_out),
    .ld_ptrs           (ex2_ld_ptrs),

    // Logic to WB
    .mem_w_reg_en      (mem_w_reg_en),
    .mem_d_out         (mem_d_out),
    .mem_alu_out       (mem_alu_out),
    .mem_WReg1         (mem_WReg1),
    .mem_lw_en         (mem_lw_en),
    .mem_ld_ptrs       (mem_ld_ptrs),
    .mem_head_ptr      (mem_head_ptr),
    .mem_tail_ptr      (mem_tail_ptr),

    // Logic to IF
    .mem_pc_next       (mem_pc_next),
    .mem_jmp_ctrl      (mem_jmp_ctrl),
    .mem_thread_id_out (mem_thread_id_out),
    
    // Output Global Flush/Reset Logics
    .mem_fetch_reset   (mem_fetch_reset),
    .mem_decode_flush  (mem_decode_flush),
    .mem_ex_flush      (mem_ex_flush),
    .mem_wb_flush      (mem_wb_flush)
  );

  // ------------------------------------------------------------------------------------
  // WRITEBACK STAGE1
  // ------------------------------------------------------------------------------------
  wb_stage1 #(
    .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH)
  ) WB1 (
    .clk               (clk),
    .reset             (reset),
    .pipeline_enable   (pipeline_enable),
    .wb_flush          (mem_wb_flush),
    
    // Logic from MEM
    .w_reg_en          (mem_w_reg_en),
    .lw_en             (mem_lw_en),
    .d_in_alu          (mem_alu_out),
    .d_in_mem          (mem_d_out),
    .WReg1             (mem_WReg1),
    .thread_id         (mem_thread_id_out),
    .ld_ptrs           (mem_ld_ptrs),
    .head_ptr          (mem_head_ptr),
    .tail_ptr          (mem_tail_ptr),

    // Logic to WB2
    .wb1_w_reg_en      (wb1_w_reg_en),
    .wb1_d_out         (wb1_d_out),
    .wb1_WReg1         (wb1_WReg1),
    .wb1_thread_id_out (wb1_thread_id_out)
  );

  // ------------------------------------------------------------------------------------
  // WRITEBACK STAGE2
  // ------------------------------------------------------------------------------------
  wb_stage2 #(
    .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH)
  ) WB2 (
    .clk               (clk),
    .reset             (reset),
    .pipeline_enable   (pipeline_enable),
    .wb_flush          (mem_wb_flush),
    
    // Logic from WB1
    .wb1_w_reg_en      (wb1_w_reg_en),
    .wb1_d_out         (wb1_d_out),
    .wb1_WReg1         (wb1_WReg1),
    .wb1_thread_id_out (wb1_thread_id_out),

    // Logic to ID
    .wb2_w_reg_en      (wb2_w_reg_en),
    .wb2_d_out         (wb2_d_out),
    .wb2_WReg1         (wb2_WReg1),
    .wb2_thread_id_out (wb2_thread_id_out)
  );

  // ------------------------------------------------------------------------------------
  // NETWORK HANDSHAKE REGISTER SLICE
  // ------------------------------------------------------------------------------------ 
  mem_register_slice #(
    .NETWORK_DATA_WIDTH (NETWORK_DATA_WIDTH),
    .NETWORK_CTRL_WIDTH (NETWORK_CTRL_WIDTH)
  ) rs_in (
    .clk     (clk),
    .reset   (reset),

    // From top to RS
    .s_data  (nw_in_data),
    .s_ctrl  (nw_in_ctrl),
    .s_valid (nw_in_wr),
    
    // FROM RS TO TOP
    .s_ready (nw_in_rdy),

    // From RS to MEM
    .m_data  (rs_nw_in_data),
    .m_ctrl  (rs_nw_in_ctrl),
    .m_valid (rs_nw_in_wr),

    // FROM MEM TO RS
    .m_ready (mem_nw_in_rdy)
  );

  mem_register_slice #(
    .NETWORK_DATA_WIDTH(NETWORK_DATA_WIDTH),
    .NETWORK_CTRL_WIDTH(NETWORK_CTRL_WIDTH)
  ) rs_out (
    .clk     (clk),
    .reset   (reset),

    // From MEM to RS
    .s_data  (mem_nw_out_data),
    .s_ctrl  (mem_nw_out_ctrl),
    .s_valid (mem_nw_out_wr),
    
    // FROM RS TO MEM
    .s_ready (rs_nw_out_rdy),

    // From RS to TOP
    .m_data  (nw_out_data),
    .m_ctrl  (nw_out_ctrl),
    .m_valid (nw_out_wr),

    // FROM TOP TO RS
    .m_ready (nw_out_rdy)
  );

  // ------------------------------------------------------------------------------------
  // Hardware Registers Values forwarding
  // ------------------------------------------------------------------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      hw_i_mem_word_out    <= 0;
      hw_d_mem_word_out_1  <= 0;
      hw_d_mem_word_out_0  <= 0;
    end else begin
      hw_i_mem_word_out    <= if1_inst_out[31:0];
      hw_d_mem_word_out_1  <= mem_d_out[63:32];
      hw_d_mem_word_out_0  <= mem_d_out[31:0];
    end
  end

endmodule
