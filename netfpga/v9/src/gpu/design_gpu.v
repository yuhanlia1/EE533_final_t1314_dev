`timescale 1ns/1ps

module gpu_top_fifo_if #(
  parameter MMIO_ADDR_W = 8,
  parameter PC_W             = 16,
  parameter IMEM_PROG_ADDR_W = 16,
  parameter IMEM_ADDR_W      = 12,
  parameter IMEM_DEPTH       = 4096,
  parameter MEM_AW      = 8
)(
  input  wire                   clk,
  input  wire                   rst,

  input  wire                   mmio_wr_en,
  input  wire                   mmio_rd_en,
  input  wire [MMIO_ADDR_W-1:0] mmio_addr,
  input  wire [31:0]            mmio_wdata,
  output wire [31:0]            mmio_rdata,

  input  wire                   imem_prog_we,
  input  wire [IMEM_PROG_ADDR_W-1:0] imem_prog_addr,
  input  wire [31:0]            imem_prog_wdata,

  input  wire                   proc_active,
  output wire                   proc_done,

  output wire                   mem0_en,
  output wire                   mem0_we,
  output wire [MEM_AW-1:0]      mem0_addr,
  output wire [63:0]            mem0_wdata,
  input  wire [63:0]            mem0_rdata,
  input  wire                   mem0_rvalid,

  output wire                   mem1_en,
  output wire                   mem1_we,
  output wire [MEM_AW-1:0]      mem1_addr,
  output wire [63:0]            mem1_wdata,
  input  wire [63:0]            mem1_rdata,
  input  wire                   mem1_rvalid,

  output wire [15:0]            dbg_pc,
  output wire                   busy
);

  wire        run_en;
  wire        pipe_run_en;
  wire        start_pulse;
  wire        clear_done_pulse;
  wire        soft_reset_pulse;

  wire [PC_W-1:0]  entry_pc;
  wire [31:0] tid_init;
  wire [31:0] work_size;
  wire [31:0] work_size_eff;
  wire [31:0] m, n, k;

  wire [63:0] base_a, base_b, base_c, base_d;

  wire        done, error;
  wire [7:0]  error_code;

  wire        hw_error_pulse;
  wire [7:0]  hw_error_code;

  assign hw_error_pulse = 1'b0;
  assign hw_error_code  = 8'h00;

  wire [PC_W-1:0]  pc_if;
  wire [31:0] instr_if;

  wire [PC_W-1:0]  pc_id;
  wire [31:0] instr_id;
  wire        flush_id;

  wire        jump_valid;
  wire [PC_W-1:0]  jump_addr;
  wire        flush_pipe;
  wire        ex_halt_pulse;

  wire        id_valid;
  wire [PC_W-1:0]  id_pc;
  wire [15:0] id_ctrl;
  wire [2:0]  id_rd;
  wire        id_dtype;
  wire [1:0]  id_bsel;
  wire [15:0] id_imm;
  wire [63:0] id_base_sel;
  wire [31:0] id_tid_base;
  wire [1:0]  id_lane_mask;

  wire [63:0] id_op1_0, id_op1_1;
  wire [63:0] id_op2_0, id_op2_1;
  wire [63:0] id_acc_0, id_acc_1;

  wire         ex_in_valid;
  wire [PC_W-1:0]   ex_in_pc;
  wire [15:0]  ex_in_ctrl;
  wire [2:0]   ex_in_rd;
  wire         ex_in_dtype;
  wire [15:0]  ex_in_imm;
  wire [63:0]  ex_in_base_sel;
  wire [31:0]  ex_in_tid_base;
  wire [1:0]   ex_in_lane_mask;
  wire [63:0]  ex_in_op1_0, ex_in_op1_1;
  wire [63:0]  ex_in_op2_0, ex_in_op2_1;
  wire [63:0]  ex_in_acc_0, ex_in_acc_1;

  wire        ex_out_valid;
  wire [15:0] ex_out_ctrl;
  wire [2:0]  ex_out_rd;
  wire [1:0]  ex_out_lane_mask;

  wire [MEM_AW-1:0] ex_addr0, ex_addr1;
  wire [63:0]       ex_store0, ex_store1;
  wire [63:0]       ex_res0, ex_res1;

  wire        mm_in_valid;
  wire [15:0] mm_in_ctrl;
  wire [2:0]  mm_in_rd;
  wire [1:0]  mm_in_lane_mask;
  wire [MEM_AW-1:0] mm_addr0, mm_addr1;
  wire [63:0]       mm_store0, mm_store1;
  wire [63:0]       mm_res0, mm_res1;

  wire        mm_out_valid;
  wire [15:0] mm_out_ctrl;
  wire [2:0]  mm_out_rd;
  wire [1:0]  mm_out_lane_mask;
  wire [63:0] dmem_rdata0, dmem_rdata1;
  wire [63:0] mm_out_res0, mm_out_res1;

  wire        wb_in_valid;
  wire [15:0] wb_in_ctrl;
  wire [2:0]  wb_in_rd;
  wire [1:0]  wb_in_lane_mask;
  wire [63:0] wb_in_res0, wb_in_res1;
  wire [63:0] wb_in_load0, wb_in_load1;

  wire        wb_we0, wb_we1;
  wire [2:0]  wb_rd;
  wire [63:0] wb_wdata0, wb_wdata1;

  wire        stall_ex;
  wire        stall_mm;
  wire        busy_stall;
  wire        hazard_stall;
  wire        front_stall;
  wire        hazard_bubble;
  wire        ex_consume_pulse;
  wire        mm_consume_pulse;

  wire        hw_done_pulse;

  wire [3:0]  cur_opcode = instr_id[31:28];
  wire [2:0]  cur_rd_idx = instr_id[27:25];
  wire [2:0]  cur_rs1    = instr_id[24:22];
  wire [2:0]  cur_rs2    = instr_id[21:19];

  wire cur_is_loadi      = (cur_opcode == 4'h1);
  wire cur_is_load       = (cur_opcode == 4'h2);
  wire cur_is_store      = (cur_opcode == 4'h3);
  wire cur_is_add        = (cur_opcode == 4'h4);
  wire cur_is_sub        = (cur_opcode == 4'h5);
  wire cur_is_mul        = (cur_opcode == 4'h6);
  wire cur_is_relu       = (cur_opcode == 4'h7);
  wire cur_is_tensor_mul = (cur_opcode == 4'hB);
  wire cur_is_tensor_mac = (cur_opcode == 4'hC);
  wire cur_is_mov        = (cur_opcode == 4'hD);
  wire cur_is_pseudo_nop = cur_is_mov &
                           (cur_rd_idx == 3'd7) &
                           (cur_rs1    == 3'd7) &
                           (cur_rs2    == 3'd7);

  wire cur_uses_rs1 = ~cur_is_pseudo_nop &
                      (cur_is_mov | cur_is_add | cur_is_sub | cur_is_mul |
                       cur_is_relu | cur_is_tensor_mul | cur_is_tensor_mac);
  wire cur_uses_rs2 = ~cur_is_pseudo_nop &
                      (cur_is_store | cur_is_add | cur_is_sub | cur_is_mul |
                       cur_is_tensor_mul | cur_is_tensor_mac);
  wire cur_uses_acc = cur_is_tensor_mac;

  wire ex_writes = ex_in_valid &
                   (ex_in_ctrl[0] | ex_in_ctrl[2] | ex_in_ctrl[3] | ex_in_ctrl[4] |
                    ex_in_ctrl[5] | ex_in_ctrl[6] | ex_in_ctrl[7] | ex_in_ctrl[8] |
                    ex_in_ctrl[9]) &
                   ~(ex_in_ctrl[3] & (ex_in_rd == 3'd7));

  wire mm_writes = mm_in_valid &
                   (mm_in_ctrl[0] | mm_in_ctrl[2] | mm_in_ctrl[3] | mm_in_ctrl[4] |
                    mm_in_ctrl[5] | mm_in_ctrl[6] | mm_in_ctrl[7] | mm_in_ctrl[8] |
                    mm_in_ctrl[9]) &
                   ~(mm_in_ctrl[3] & (mm_in_rd == 3'd7));

  wire mm_out_writes = mm_out_valid &
                       (mm_out_ctrl[0] | mm_out_ctrl[2] | mm_out_ctrl[3] | mm_out_ctrl[4] |
                        mm_out_ctrl[5] | mm_out_ctrl[6] | mm_out_ctrl[7] | mm_out_ctrl[8] |
                        mm_out_ctrl[9]) &
                       ~(mm_out_ctrl[3] & (mm_out_rd == 3'd7));

  wire hazard_ex = ex_writes &
                   ((cur_uses_rs1 & (ex_in_rd == cur_rs1)) |
                    (cur_uses_rs2 & (ex_in_rd == cur_rs2)) |
                    (cur_uses_acc & (ex_in_rd == cur_rd_idx)));

  wire hazard_mm = mm_writes &
                   ((cur_uses_rs1 & (mm_in_rd == cur_rs1)) |
                    (cur_uses_rs2 & (mm_in_rd == cur_rs2)) |
                    (cur_uses_acc & (mm_in_rd == cur_rd_idx)));

  wire hazard_mm_out = mm_out_writes &
                       ((cur_uses_rs1 & (mm_out_rd == cur_rs1)) |
                        (cur_uses_rs2 & (mm_out_rd == cur_rs2)) |
                        (cur_uses_acc & (mm_out_rd == cur_rd_idx)));

  assign pipe_run_en = run_en & proc_active;
  assign busy_stall   = stall_ex | stall_mm;
  assign hazard_stall = pipe_run_en & ~flush_id & ~busy_stall & (hazard_ex | hazard_mm | hazard_mm_out);
  assign front_stall  = busy_stall | hazard_stall;
  assign hazard_bubble = hazard_stall;
  assign hw_done_pulse = ex_halt_pulse;
  assign proc_done = done;
  assign dbg_pc = {{(16-PC_W){1'b0}}, pc_if};

  gpu_control #(.ADDR_W(MMIO_ADDR_W), .PC_W(PC_W)) u_ctrl (
    .clk(clk),
    .rst(rst),
    .mmio_wr_en(mmio_wr_en),
    .mmio_rd_en(mmio_rd_en),
    .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata),
    .mmio_rdata(mmio_rdata),
    .hw_done_pulse(hw_done_pulse),
    .hw_error_pulse(hw_error_pulse),
    .hw_error_code(hw_error_code),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .clear_done_pulse(clear_done_pulse),
    .soft_reset_pulse(soft_reset_pulse),
    .entry_pc(entry_pc),
    .tid_init(tid_init),
    .work_size(work_size),
    .work_size_eff(work_size_eff),
    .m(m),
    .n(n),
    .k(k),
    .base_a(base_a),
    .base_b(base_b),
    .base_c(base_c),
    .base_d(base_d),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code)
  );

  gpu_if_stage #(
    .PC_W(PC_W),
    .IMEM_PROG_ADDR_W(IMEM_PROG_ADDR_W),
    .IMEM_ADDR_W(IMEM_ADDR_W),
    .IMEM_DEPTH(IMEM_DEPTH)
  ) u_if (
    .clk(clk),
    .rst(rst),
    .run_en(pipe_run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(front_stall),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .imem_we(imem_prog_we),
    .imem_waddr(imem_prog_addr),
    .imem_wdata(imem_prog_wdata),
    .pc_if(pc_if),
    .instr_if(instr_if)
  );

  gpu_if_id_reg #(.PC_W(PC_W)) u_ifid (
    .clk(clk),
    .rst(rst),
    .stall(front_stall),
    .pc_in(pc_if),
    .instr_in(instr_if),
    .flush_in(flush_pipe),
    .pc_id(pc_id),
    .instr_id(instr_id),
    .flush_out(flush_id)
  );

  gpu_id_stage #(.PC_W(PC_W)) u_id (
    .clk(clk),
    .rst(rst),
    .run_en(pipe_run_en),
    .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(front_stall),
    .busy_stall(busy_stall),
    .ex_flush(flush_pipe),
    .tid_init(tid_init),
    .work_size_eff(work_size_eff),
    .base_a(base_a),
    .base_b(base_b),
    .base_c(base_c),
    .base_d(base_d),
    .pc_id(pc_id),
    .instr_id(instr_id),
    .flush_id(flush_id),
    .wb_we0(wb_we0),
    .wb_we1(wb_we1),
    .wb_rd(wb_rd),
    .wb_wdata0(wb_wdata0),
    .wb_wdata1(wb_wdata1),
    .id_valid(id_valid),
    .id_pc(id_pc),
    .id_ctrl(id_ctrl),
    .id_rd(id_rd),
    .id_dtype(id_dtype),
    .id_bsel(id_bsel),
    .id_imm(id_imm),
    .id_base_sel(id_base_sel),
    .id_tid_base(id_tid_base),
    .id_lane_mask(id_lane_mask),
    .id_op1_0(id_op1_0),
    .id_op1_1(id_op1_1),
    .id_op2_0(id_op2_0),
    .id_op2_1(id_op2_1),
    .id_acc_0(id_acc_0),
    .id_acc_1(id_acc_1)
  );

  gpu_id_ex_reg #(.PC_W(PC_W)) u_idex (
    .clk(clk),
    .rst(rst),
    .stall(busy_stall),
    .flush_in(flush_pipe | hazard_bubble),
    .consume_pulse(ex_consume_pulse),
    .in_valid(id_valid),
    .in_pc(id_pc),
    .in_ctrl(id_ctrl),
    .in_rd(id_rd),
    .in_dtype(id_dtype),
    .in_imm(id_imm),
    .in_base_sel(id_base_sel),
    .in_tid_base(id_tid_base),
    .in_lane_mask(id_lane_mask),
    .in_op1_0(id_op1_0),
    .in_op1_1(id_op1_1),
    .in_op2_0(id_op2_0),
    .in_op2_1(id_op2_1),
    .in_acc_0(id_acc_0),
    .in_acc_1(id_acc_1),
    .out_valid(ex_in_valid),
    .out_pc(ex_in_pc),
    .out_ctrl(ex_in_ctrl),
    .out_rd(ex_in_rd),
    .out_dtype(ex_in_dtype),
    .out_imm(ex_in_imm),
    .out_base_sel(ex_in_base_sel),
    .out_tid_base(ex_in_tid_base),
    .out_lane_mask(ex_in_lane_mask),
    .out_op1_0(ex_in_op1_0),
    .out_op1_1(ex_in_op1_1),
    .out_op2_0(ex_in_op2_0),
    .out_op2_1(ex_in_op2_1),
    .out_acc_0(ex_in_acc_0),
    .out_acc_1(ex_in_acc_1)
  );

  gpu_ex_stage #(.DMEM_AW(MEM_AW), .PC_W(PC_W)) u_ex (
    .clk(clk),
    .rst(rst),
    .in_valid(ex_in_valid),
    .in_ctrl(ex_in_ctrl),
    .in_rd(ex_in_rd),
    .in_dtype(ex_in_dtype),
    .in_imm(ex_in_imm),
    .in_base_sel(ex_in_base_sel),
    .in_tid_base(ex_in_tid_base),
    .in_lane_mask(ex_in_lane_mask),
    .in_op1_0(ex_in_op1_0),
    .in_op1_1(ex_in_op1_1),
    .in_op2_0(ex_in_op2_0),
    .in_op2_1(ex_in_op2_1),
    .in_acc_0(ex_in_acc_0),
    .in_acc_1(ex_in_acc_1),
    .stall(stall_ex),
    .consume_pulse(ex_consume_pulse),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .flush_pipe(flush_pipe),
    .halt_pulse(ex_halt_pulse),
    .out_valid(ex_out_valid),
    .out_ctrl(ex_out_ctrl),
    .out_rd(ex_out_rd),
    .out_lane_mask(ex_out_lane_mask),
    .out_addr0(ex_addr0),
    .out_addr1(ex_addr1),
    .out_store0(ex_store0),
    .out_store1(ex_store1),
    .out_res0(ex_res0),
    .out_res1(ex_res1)
  );

  gpu_ex_mm_reg #(.DMEM_AW(MEM_AW)) u_exmm (
    .clk(clk),
    .rst(rst),
    .stall(stall_mm),
    .consume_pulse(mm_consume_pulse),
    .in_valid(ex_out_valid),
    .in_ctrl(ex_out_ctrl),
    .in_rd(ex_out_rd),
    .in_lane_mask(ex_out_lane_mask),
    .in_addr0(ex_addr0),
    .in_addr1(ex_addr1),
    .in_store0(ex_store0),
    .in_store1(ex_store1),
    .in_res0(ex_res0),
    .in_res1(ex_res1),
    .out_valid(mm_in_valid),
    .out_ctrl(mm_in_ctrl),
    .out_rd(mm_in_rd),
    .out_lane_mask(mm_in_lane_mask),
    .out_addr0(mm_addr0),
    .out_addr1(mm_addr1),
    .out_store0(mm_store0),
    .out_store1(mm_store1),
    .out_res0(mm_res0),
    .out_res1(mm_res1)
  );

  gpu_mm_stage #(.DMEM_AW(MEM_AW)) u_mm (
    .clk(clk),
    .rst(rst),
    .proc_active(proc_active),
    .in_valid(mm_in_valid),
    .in_ctrl(mm_in_ctrl),
    .in_rd(mm_in_rd),
    .in_lane_mask(mm_in_lane_mask),
    .in_addr0(mm_addr0),
    .in_addr1(mm_addr1),
    .in_store0(mm_store0),
    .in_store1(mm_store1),
    .in_res0(mm_res0),
    .in_res1(mm_res1),
    .consume_pulse(mm_consume_pulse),
    .stall_mm(stall_mm),
    .mem0_en(mem0_en),
    .mem0_we(mem0_we),
    .mem0_addr(mem0_addr),
    .mem0_wdata(mem0_wdata),
    .mem0_rdata(mem0_rdata),
    .mem0_rvalid(mem0_rvalid),
    .mem1_en(mem1_en),
    .mem1_we(mem1_we),
    .mem1_addr(mem1_addr),
    .mem1_wdata(mem1_wdata),
    .mem1_rdata(mem1_rdata),
    .mem1_rvalid(mem1_rvalid),
    .out_valid(mm_out_valid),
    .out_ctrl(mm_out_ctrl),
    .out_rd(mm_out_rd),
    .out_lane_mask(mm_out_lane_mask),
    .dmem_rdata0(dmem_rdata0),
    .dmem_rdata1(dmem_rdata1),
    .out_res0(mm_out_res0),
    .out_res1(mm_out_res1)
  );

  gpu_mm_wb_reg u_mmwbr (
    .clk(clk),
    .rst(rst),
    .in_valid(mm_out_valid),
    .in_ctrl(mm_out_ctrl),
    .in_rd(mm_out_rd),
    .in_lane_mask(mm_out_lane_mask),
    .in_res0(mm_out_res0),
    .in_res1(mm_out_res1),
    .in_load0(dmem_rdata0),
    .in_load1(dmem_rdata1),
    .out_valid(wb_in_valid),
    .out_ctrl(wb_in_ctrl),
    .out_rd(wb_in_rd),
    .out_lane_mask(wb_in_lane_mask),
    .out_res0(wb_in_res0),
    .out_res1(wb_in_res1),
    .out_load0(wb_in_load0),
    .out_load1(wb_in_load1)
  );

  gpu_wb_stage u_wb (
    .clk(clk),
    .rst(rst),
    .in_valid(wb_in_valid),
    .in_ctrl(wb_in_ctrl),
    .in_rd(wb_in_rd),
    .in_lane_mask(wb_in_lane_mask),
    .in_res0(wb_in_res0),
    .in_res1(wb_in_res1),
    .in_load0(wb_in_load0),
    .in_load1(wb_in_load1),
    .wb_we0(wb_we0),
    .wb_we1(wb_we1),
    .wb_rd(wb_rd),
    .wb_wdata0(wb_wdata0),
    .wb_wdata1(wb_wdata1)
  );

endmodule

module gpu_control #(
  parameter ADDR_W = 8,
  parameter PC_W = 16
)(
  input  wire              clk,
  input  wire              rst,

  input  wire              mmio_wr_en,
  input  wire              mmio_rd_en,
  input  wire [ADDR_W-1:0] mmio_addr,
  input  wire [31:0]       mmio_wdata,
  output reg  [31:0]       mmio_rdata,

  input  wire              hw_done_pulse,
  input  wire              hw_error_pulse,
  input  wire [7:0]        hw_error_code,

  output wire              run_en,
  output reg               start_pulse,
  output reg               clear_done_pulse,
  output reg               soft_reset_pulse,

  output reg  [PC_W-1:0]   entry_pc,
  output reg  [31:0]       tid_init,
  output reg  [31:0]       work_size,
  output reg  [31:0]       work_size_eff,
  output reg  [31:0]       m,
  output reg  [31:0]       n,
  output reg  [31:0]       k,

  output reg  [63:0]       base_a,
  output reg  [63:0]       base_b,
  output reg  [63:0]       base_c,
  output reg  [63:0]       base_d,

  output reg               busy,
  output reg               done,
  output reg               error,
  output reg  [7:0]        error_code
  );

  localparam [ADDR_W-1:0] REG_CONTROL      = 8'h00;
  localparam [ADDR_W-1:0] REG_STATUS       = 8'h04;
  localparam [ADDR_W-1:0] REG_ENTRY_PC     = 8'h08;
  localparam [ADDR_W-1:0] REG_TID_INIT     = 8'h0C;
  localparam [ADDR_W-1:0] REG_WORK_SIZE    = 8'h10;

  localparam [ADDR_W-1:0] REG_BASE_A_LO    = 8'h20;
  localparam [ADDR_W-1:0] REG_BASE_A_HI    = 8'h24;
  localparam [ADDR_W-1:0] REG_BASE_B_LO    = 8'h28;
  localparam [ADDR_W-1:0] REG_BASE_B_HI    = 8'h2C;
  localparam [ADDR_W-1:0] REG_BASE_C_LO    = 8'h30;
  localparam [ADDR_W-1:0] REG_BASE_C_HI    = 8'h34;
  localparam [ADDR_W-1:0] REG_BASE_D_LO    = 8'h38;
  localparam [ADDR_W-1:0] REG_BASE_D_HI    = 8'h3C;

  localparam [ADDR_W-1:0] REG_M            = 8'h40;
  localparam [ADDR_W-1:0] REG_N            = 8'h44;
  localparam [ADDR_W-1:0] REG_K            = 8'h48;

  localparam [ADDR_W-1:0] REG_ERROR_CODE   = 8'h4C;

  localparam integer CTRL_START_BIT        = 0;
  localparam integer CTRL_CLEAR_DONE_BIT   = 1;
  localparam integer CTRL_SOFT_RESET_BIT   = 2;

  localparam integer STAT_BUSY_BIT         = 0;
  localparam integer STAT_DONE_BIT         = 1;
  localparam integer STAT_ERROR_BIT        = 2;

  localparam [7:0] ERR_NONE                = 8'h00;
  localparam [7:0] ERR_START_WHILE_BUSY    = 8'h01;
  localparam [7:0] ERR_PARAM_WRITE_BUSY    = 8'h02;

  reg [31:0] mn_p00_r;
  reg [31:0] mn_p01_r;
  reg [31:0] mn_p10_r;
  reg        mn_mul_v1;
  reg [31:0] mmio_rdata_next;

  assign run_en = busy;

  wire is_param_addr;
  assign is_param_addr =
      (mmio_addr == REG_ENTRY_PC)   |
      (mmio_addr == REG_TID_INIT)   |
      (mmio_addr == REG_WORK_SIZE)  |
      (mmio_addr == REG_BASE_A_LO)  |
      (mmio_addr == REG_BASE_A_HI)  |
      (mmio_addr == REG_BASE_B_LO)  |
      (mmio_addr == REG_BASE_B_HI)  |
      (mmio_addr == REG_BASE_C_LO)  |
      (mmio_addr == REG_BASE_C_HI)  |
      (mmio_addr == REG_BASE_D_LO)  |
      (mmio_addr == REG_BASE_D_HI)  |
      (mmio_addr == REG_M)          |
      (mmio_addr == REG_N)          |
      (mmio_addr == REG_K);

  always @(*) begin
    mmio_rdata_next = 32'h00000000;
    if (mmio_rd_en) begin
      case (mmio_addr)
        REG_STATUS: begin
          mmio_rdata_next = 32'h0;
          mmio_rdata_next[STAT_BUSY_BIT]  = busy;
          mmio_rdata_next[STAT_DONE_BIT]  = done;
          mmio_rdata_next[STAT_ERROR_BIT] = error;
        end
        REG_ENTRY_PC:   mmio_rdata_next = {{(32-PC_W){1'b0}}, entry_pc};
        REG_TID_INIT:   mmio_rdata_next = tid_init;
        REG_WORK_SIZE:  mmio_rdata_next = work_size;
        REG_BASE_A_LO:  mmio_rdata_next = base_a[31:0];
        REG_BASE_A_HI:  mmio_rdata_next = base_a[63:32];
        REG_BASE_B_LO:  mmio_rdata_next = base_b[31:0];
        REG_BASE_B_HI:  mmio_rdata_next = base_b[63:32];
        REG_BASE_C_LO:  mmio_rdata_next = base_c[31:0];
        REG_BASE_C_HI:  mmio_rdata_next = base_c[63:32];
        REG_BASE_D_LO:  mmio_rdata_next = base_d[31:0];
        REG_BASE_D_HI:  mmio_rdata_next = base_d[63:32];
        REG_M:          mmio_rdata_next = m;
        REG_N:          mmio_rdata_next = n;
        REG_K:          mmio_rdata_next = k;
        REG_ERROR_CODE: mmio_rdata_next = {24'd0, error_code};
        default:        mmio_rdata_next = 32'h00000000;
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      mmio_rdata       <= 32'd0;
      busy             <= 1'b0;
      done             <= 1'b0;
      error            <= 1'b0;
      error_code       <= ERR_NONE;
      start_pulse      <= 1'b0;
      clear_done_pulse <= 1'b0;
      soft_reset_pulse <= 1'b0;
      entry_pc         <= {PC_W{1'b0}};
      tid_init         <= 32'd0;
      work_size        <= 32'd0;
      work_size_eff    <= 32'd0;
      m                <= 32'd0;
      n                <= 32'd0;
      k                <= 32'd0;
      base_a           <= 64'd0;
      base_b           <= 64'd0;
      base_c           <= 64'd0;
      base_d           <= 64'd0;
      mn_p00_r         <= 32'd0;
      mn_p01_r         <= 32'd0;
      mn_p10_r         <= 32'd0;
      mn_mul_v1        <= 1'b0;
    end else begin
      mmio_rdata       <= mmio_rdata_next;
      start_pulse      <= 1'b0;
      clear_done_pulse <= 1'b0;
      soft_reset_pulse <= 1'b0;

      if (mn_mul_v1) begin
        work_size_eff <= mn_p00_r + ((mn_p01_r + mn_p10_r) << 16);
        mn_mul_v1     <= 1'b0;
      end

      if (hw_done_pulse) begin
        busy <= 1'b0;
        done <= 1'b1;
      end

      if (hw_error_pulse) begin
        busy       <= 1'b0;
        error      <= 1'b1;
        error_code <= hw_error_code;
      end

      if (mmio_wr_en) begin
        if (mmio_addr == REG_CONTROL) begin
          if (mmio_wdata[CTRL_SOFT_RESET_BIT]) begin
            soft_reset_pulse <= 1'b1;
            busy             <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;
            error_code       <= ERR_NONE;
            entry_pc         <= {PC_W{1'b0}};
            tid_init         <= 32'd0;
            work_size        <= 32'd0;
            work_size_eff    <= 32'd0;
            m                <= 32'd0;
            n                <= 32'd0;
            k                <= 32'd0;
            base_a           <= 64'd0;
            base_b           <= 64'd0;
            base_c           <= 64'd0;
            base_d           <= 64'd0;
            mn_p00_r         <= 32'd0;
            mn_p01_r         <= 32'd0;
            mn_p10_r         <= 32'd0;
            mn_mul_v1        <= 1'b0;
          end

          if (mmio_wdata[CTRL_CLEAR_DONE_BIT]) begin
            clear_done_pulse <= 1'b1;
            done             <= 1'b0;
          end

          if (mmio_wdata[CTRL_START_BIT]) begin
            if (busy) begin
              error      <= 1'b1;
              error_code <= ERR_START_WHILE_BUSY;
            end else begin
              start_pulse <= 1'b1;
              busy        <= 1'b1;
              done        <= 1'b0;
              error       <= 1'b0;
              error_code  <= ERR_NONE;
              if (work_size != 32'd0) begin
                work_size_eff <= work_size;
                mn_mul_v1     <= 1'b0;
              end else begin
                mn_p00_r      <= m[15:0]  * n[15:0];
                mn_p01_r      <= m[15:0]  * n[31:16];
                mn_p10_r      <= m[31:16] * n[15:0];
                mn_mul_v1     <= 1'b1;
              end
            end
          end
        end else begin
          if (busy && is_param_addr) begin
            error      <= 1'b1;
            error_code <= ERR_PARAM_WRITE_BUSY;
          end else begin
            case (mmio_addr)
              REG_ENTRY_PC:   entry_pc      <= mmio_wdata[PC_W-1:0];
              REG_TID_INIT:   tid_init      <= mmio_wdata;
              REG_WORK_SIZE:  work_size     <= mmio_wdata;
              REG_BASE_A_LO:  base_a[31:0]  <= mmio_wdata;
              REG_BASE_A_HI:  base_a[63:32] <= mmio_wdata;
              REG_BASE_B_LO:  base_b[31:0]  <= mmio_wdata;
              REG_BASE_B_HI:  base_b[63:32] <= mmio_wdata;
              REG_BASE_C_LO:  base_c[31:0]  <= mmio_wdata;
              REG_BASE_C_HI:  base_c[63:32] <= mmio_wdata;
              REG_BASE_D_LO:  base_d[31:0]  <= mmio_wdata;
              REG_BASE_D_HI:  base_d[63:32] <= mmio_wdata;
              REG_M:          m             <= mmio_wdata;
              REG_N:          n             <= mmio_wdata;
              REG_K:          k             <= mmio_wdata;
              default: begin end
            endcase
          end
        end
      end
    end
  end

endmodule

module gpu_if_stage #(
  parameter PC_W = 16,
  parameter IMEM_PROG_ADDR_W = 16,
  parameter IMEM_ADDR_W      = 12,
  parameter IMEM_DEPTH       = 4096
) (
  input  wire        clk,
  input  wire        rst,

  input  wire        run_en,
  input  wire        start_pulse,
  input  wire [PC_W-1:0]  entry_pc,
  input  wire        soft_reset_pulse,

  input  wire        stall,

  input  wire        jump_valid,
  input  wire [PC_W-1:0]  jump_addr,

  input  wire        imem_we,
  input  wire [IMEM_PROG_ADDR_W-1:0] imem_waddr,
  input  wire [31:0] imem_wdata,

  output wire [PC_W-1:0]  pc_if,
  output wire [31:0] instr_if
);

  wire [PC_W-1:0]        pc_w;
  wire [IMEM_ADDR_W-1:0] imem_addr_w;
  wire [IMEM_ADDR_W-1:0] imem_fetch_addr_w;
  wire [IMEM_ADDR_W-1:0] imem_waddr_phys;
  wire [31:0]            imem_rdata_w;
  wire                   imem_we_int;

  reg         stall_d;
  reg         skid_valid;
  reg  [31:0] skid_instr;
  wire        use_skid;

  assign use_skid = skid_valid & (stall | stall_d);
  assign pc_if = pc_w;
  assign imem_fetch_addr_w = pc_w[IMEM_ADDR_W-1:0];
  assign imem_waddr_phys = imem_waddr[IMEM_ADDR_W-1:0];
  assign imem_we_int = imem_we && (imem_waddr < IMEM_DEPTH);
  assign imem_addr_w = imem_we_int ? imem_waddr_phys : imem_fetch_addr_w;

  gpu_pc #(.PC_W(PC_W)) u_pc (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .gpu_pc(pc_w)
  );

  gpu_imem #(
    .AW(IMEM_ADDR_W),
    .DEPTH(IMEM_DEPTH)
  ) u_imem (
    .clk(clk),
    .we(imem_we_int),
    .addr(imem_addr_w),
    .wdata(imem_wdata),
    .rdata(imem_rdata_w)
  );

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      stall_d     <= 1'b0;
      skid_valid  <= 1'b0;
      skid_instr  <= 32'd0;
    end else begin
      stall_d     <= stall;

      if (start_pulse || jump_valid) begin
        skid_valid <= 1'b0;
      end else if (stall && !stall_d && run_en && !imem_we_int) begin
        skid_valid <= 1'b1;
        skid_instr <= imem_rdata_w;
      end else if (!stall && stall_d) begin
        skid_valid <= 1'b0;
      end
    end
  end

  assign instr_if = use_skid ? skid_instr : imem_rdata_w;

endmodule


module gpu_pc #(
  parameter PC_W = 16
) (
  input  wire       clk,
  input  wire       rst,
  input  wire       run_en,
  input  wire       start_pulse,
  input  wire [PC_W-1:0] entry_pc,
  input  wire       soft_reset_pulse,
  input  wire       stall,
  input  wire       jump_valid,
  input  wire [PC_W-1:0] jump_addr,
  output reg  [PC_W-1:0] gpu_pc
);

  always @(posedge clk) begin
    if (rst) gpu_pc <= {PC_W{1'b0}};
    else if (soft_reset_pulse) gpu_pc <= {PC_W{1'b0}};
    else if (stall) gpu_pc <= gpu_pc;
    else if (start_pulse) gpu_pc <= entry_pc;
    else if (!run_en) gpu_pc <= gpu_pc;
    else if (jump_valid) gpu_pc <= jump_addr;
    else gpu_pc <= gpu_pc + {{(PC_W-1){1'b0}}, 1'b1};
  end

endmodule

module gpu_if_id_reg #(
  parameter PC_W = 16
) (
  input  wire        clk,
  input  wire        rst,
  input  wire        stall,
  input  wire [PC_W-1:0]  pc_in,
  input  wire [31:0] instr_in,
  input  wire        flush_in,
  output reg  [PC_W-1:0]  pc_id,
  output reg  [31:0] instr_id,
  output reg         flush_out
);

  always @(posedge clk) begin
    if (rst) begin
      pc_id     <= {PC_W{1'b0}};
      instr_id  <= 32'd0;
      flush_out <= 1'b0;
    end else if (!stall) begin
      pc_id     <= pc_in;
      instr_id  <= instr_in;
      flush_out <= flush_in;
    end
  end
endmodule


module gpu_id_stage #(
  parameter PC_W = 16
) (
  input  wire        clk,
  input  wire        rst,

  input  wire        run_en,
  input  wire        start_pulse,
  input  wire        soft_reset_pulse,

  input  wire        stall,
  input  wire        busy_stall,
  input  wire        ex_flush,

  input  wire [31:0] tid_init,
  input  wire [31:0] work_size_eff,

  input  wire [63:0] base_a,
  input  wire [63:0] base_b,
  input  wire [63:0] base_c,
  input  wire [63:0] base_d,

  input  wire [PC_W-1:0]  pc_id,
  input  wire [31:0] instr_id,
  input  wire        flush_id,

  input  wire        wb_we0,
  input  wire        wb_we1,
  input  wire [2:0]  wb_rd,
  input  wire [63:0] wb_wdata0,
  input  wire [63:0] wb_wdata1,

  output wire        id_valid,
  output wire [PC_W-1:0]  id_pc,
  output wire [15:0] id_ctrl,
  output wire [2:0]  id_rd,
  output wire        id_dtype,
  output wire [1:0]  id_bsel,
  output wire [15:0] id_imm,
  output wire [63:0] id_base_sel,
  output wire [31:0] id_tid_base,
  output wire [1:0]  id_lane_mask,

  output wire [63:0] id_op1_0,
  output wire [63:0] id_op1_1,
  output wire [63:0] id_op2_0,
  output wire [63:0] id_op2_1,

  output wire [63:0] id_acc_0,
  output wire [63:0] id_acc_1
);

  reg [31:0] tid_base;

  reg run_d1;
  reg run_d2;

  reg [63:0] rf0 [0:7];
  reg [63:0] rf1 [0:7];
  integer i;

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      run_d1 <= 1'b0;
      run_d2 <= 1'b0;
    end else begin
      run_d1 <= run_en;
      run_d2 <= run_d1;
    end
  end

  wire [3:0]  opcode = instr_id[31:28];
  wire [2:0]  rd     = instr_id[27:25];
  wire [2:0]  rs1    = instr_id[24:22];
  wire [2:0]  rs2    = instr_id[21:19];
  wire [1:0]  bsel   = instr_id[18:17];
  wire        dtype  = instr_id[16];
  wire [15:0] imm    = instr_id[15:0];

  wire instr_valid0 = run_en & run_d2 & ~flush_id & ~stall;
  wire instr_valid  = instr_valid0;

  wire is_load       = (opcode == 4'h2);
  wire is_store      = (opcode == 4'h3);
  wire is_loadi      = (opcode == 4'h1);
  wire is_mov        = (opcode == 4'hD);
  wire is_add        = (opcode == 4'h4);
  wire is_sub        = (opcode == 4'h5);
  wire is_mul        = (opcode == 4'h6);
  wire is_relu       = (opcode == 4'h7);
  wire is_tensor_mul = (opcode == 4'hB);
  wire is_tensor_mac = (opcode == 4'hC);
  wire is_set_tid    = (opcode == 4'h8);
  wire is_inc_tid    = (opcode == 4'h9);
  wire is_blt        = (opcode == 4'hA);
  wire is_jump       = (opcode == 4'hE);
  wire is_halt_i     = (opcode == 4'hF);

  wire [63:0] base_sel =
      (bsel == 2'b00) ? base_a :
      (bsel == 2'b01) ? base_b :
      (bsel == 2'b10) ? base_c :
                        base_d;

  wire [31:0] pack0 = tid_base + 32'd0;
  wire [31:0] pack1 = tid_base + 32'd1;

  wire lm0 = (pack0 < work_size_eff);
  wire lm1 = (pack1 < work_size_eff);

  wire [1:0] lane_mask = {lm1, lm0};

  wire [15:0] ctrl_raw = {
    3'd0,
    is_halt_i,
    is_jump,
    is_blt,
    is_tensor_mac,
    is_tensor_mul,
    is_relu,
    is_mul,
    is_sub,
    is_add,
    is_mov,
    is_loadi,
    is_store,
    is_load
  };

  wire pipe_op   = is_load | is_store | is_loadi | is_mov | is_add | is_sub | is_mul | is_relu | is_tensor_mul | is_tensor_mac;
  wire ex_ctrl_op = is_blt | is_jump | is_halt_i;
  wire send_to_ex = pipe_op | ex_ctrl_op;

  assign id_valid     = instr_valid & send_to_ex;
  assign id_pc        = pc_id;
  assign id_ctrl      = instr_valid ? ctrl_raw : 16'd0;
  assign id_rd        = rd;
  assign id_dtype     = dtype;
  assign id_bsel      = bsel;
  assign id_imm       = imm;
  assign id_base_sel  = base_sel;
  assign id_tid_base  = tid_base;
  assign id_lane_mask = lane_mask;

  wire [63:0] rf0_rs1 = rf0[rs1];
  wire [63:0] rf1_rs1 = rf1[rs1];

  wire [63:0] rf0_rs2 = rf0[rs2];
  wire [63:0] rf1_rs2 = rf1[rs2];

  wire [63:0] rf0_rd0 = rf0[rd];
  wire [63:0] rf1_rd0 = rf1[rd];

  assign id_op1_0 = (wb_we0 && (wb_rd == rs1)) ? wb_wdata0 : rf0_rs1;
  assign id_op1_1 = (wb_we1 && (wb_rd == rs1)) ? wb_wdata1 : rf1_rs1;

  assign id_op2_0 = (wb_we0 && (wb_rd == rs2)) ? wb_wdata0 : rf0_rs2;
  assign id_op2_1 = (wb_we1 && (wb_rd == rs2)) ? wb_wdata1 : rf1_rs2;

  assign id_acc_0 = (wb_we0 && (wb_rd == rd)) ? wb_wdata0 : rf0_rd0;
  assign id_acc_1 = (wb_we1 && (wb_rd == rd)) ? wb_wdata1 : rf1_rd0;

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      tid_base <= 32'd0;
    end else if (start_pulse) begin
      tid_base <= tid_init;
    end else if (instr_valid && !ex_flush && is_set_tid) begin
      tid_base <= {16'd0, imm};
    end else if (instr_valid && !ex_flush && is_inc_tid) begin
      tid_base <= tid_base + 32'd2;
    end else begin
      tid_base <= tid_base;
    end
  end

  always @(posedge clk) begin
    if (rst || soft_reset_pulse || start_pulse) begin
      for (i = 0; i < 8; i = i + 1) begin
        rf0[i] <= 64'd0;
        rf1[i] <= 64'd0;
      end
    end else begin
      if (wb_we0) rf0[wb_rd] <= wb_wdata0;
      if (wb_we1) rf1[wb_rd] <= wb_wdata1;
    end
  end

endmodule


module gpu_id_ex_reg #(
  parameter PC_W = 16
) (
  input  wire        clk,
  input  wire        rst,

  input  wire        stall,
  input  wire        flush_in,
  input  wire        consume_pulse,

  input  wire        in_valid,
  input  wire [PC_W-1:0]  in_pc,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire        in_dtype,
  input  wire [15:0] in_imm,
  input  wire [63:0] in_base_sel,
  input  wire [31:0] in_tid_base,
  input  wire [1:0]  in_lane_mask,

  input  wire [63:0] in_op1_0,
  input  wire [63:0] in_op1_1,
  input  wire [63:0] in_op2_0,
  input  wire [63:0] in_op2_1,

  input  wire [63:0] in_acc_0,
  input  wire [63:0] in_acc_1,

  output reg         out_valid,
  output reg  [PC_W-1:0]  out_pc,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg         out_dtype,
  output reg  [15:0] out_imm,
  output reg  [63:0] out_base_sel,
  output reg  [31:0] out_tid_base,
  output reg  [1:0]  out_lane_mask,

  output reg  [63:0] out_op1_0,
  output reg  [63:0] out_op1_1,
  output reg  [63:0] out_op2_0,
  output reg  [63:0] out_op2_1,

  output reg  [63:0] out_acc_0,
  output reg  [63:0] out_acc_1
);

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_pc        <= {PC_W{1'b0}};
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_dtype     <= 1'b0;
      out_imm       <= 16'd0;
      out_base_sel  <= 64'd0;
      out_tid_base  <= 32'd0;
      out_lane_mask <= 2'd0;
      out_op1_0     <= 64'd0;
      out_op1_1     <= 64'd0;
      out_op2_0     <= 64'd0;
      out_op2_1     <= 64'd0;
      out_acc_0     <= 64'd0;
      out_acc_1     <= 64'd0;
    end else if (flush_in) begin
      out_valid     <= 1'b0;
    end else begin
      if (consume_pulse) begin
        out_valid <= 1'b0;
      end else if (!stall) begin
        out_valid     <= in_valid;
        out_pc        <= in_pc;
        out_ctrl      <= in_ctrl;
        out_rd        <= in_rd;
        out_dtype     <= in_dtype;
        out_imm       <= in_imm;
        out_base_sel  <= in_base_sel;
        out_tid_base  <= in_tid_base;
        out_lane_mask <= in_lane_mask;
        out_op1_0     <= in_op1_0;
        out_op1_1     <= in_op1_1;
        out_op2_0     <= in_op2_0;
        out_op2_1     <= in_op2_1;
        out_acc_0     <= in_acc_0;
        out_acc_1     <= in_acc_1;
      end
    end
  end

endmodule

module gpu_ex_stage #(
  parameter DMEM_AW = 10,
  parameter PC_W = 16,
  parameter integer BFMUL_OBS_LAT = 8,
  parameter integer BFADD_OBS_LAT = 14
)(
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire        in_dtype,
  input  wire [15:0] in_imm,
  input  wire [63:0] in_base_sel,
  input  wire [31:0] in_tid_base,
  input  wire [1:0]  in_lane_mask,

  input  wire [63:0] in_op1_0,
  input  wire [63:0] in_op1_1,
  input  wire [63:0] in_op2_0,
  input  wire [63:0] in_op2_1,

  input  wire [63:0] in_acc_0,
  input  wire [63:0] in_acc_1,

  output wire        stall,
  output wire        consume_pulse,

  output wire        jump_valid,
  output wire [PC_W-1:0]  jump_addr,
  output wire        flush_pipe,
  output wire        halt_pulse,

  output wire        out_valid,
  output wire [15:0] out_ctrl,
  output wire [2:0]  out_rd,
  output wire [1:0]  out_lane_mask,

  output wire [DMEM_AW-1:0] out_addr0,
  output wire [DMEM_AW-1:0] out_addr1,

  output wire [63:0] out_store0,
  output wire [63:0] out_store1,

  output wire [63:0] out_res0,
  output wire [63:0] out_res1
);

  function [63:0] add16x4;
    input [63:0] a;
    input [63:0] b;
    reg signed [15:0] a0,a1,a2,a3;
    reg signed [15:0] b0,b1,b2,b3;
    reg signed [15:0] y0,y1,y2,y3;
    begin
      a0 = a[15:0];   a1 = a[31:16];  a2 = a[47:32];  a3 = a[63:48];
      b0 = b[15:0];   b1 = b[31:16];  b2 = b[47:32];  b3 = b[63:48];
      y0 = a0 + b0;   y1 = a1 + b1;   y2 = a2 + b2;   y3 = a3 + b3;
      add16x4 = {y3,y2,y1,y0};
    end
  endfunction

  function [63:0] sub16x4;
    input [63:0] a;
    input [63:0] b;
    reg signed [15:0] a0,a1,a2,a3;
    reg signed [15:0] b0,b1,b2,b3;
    reg signed [15:0] y0,y1,y2,y3;
    begin
      a0 = a[15:0];   a1 = a[31:16];  a2 = a[47:32];  a3 = a[63:48];
      b0 = b[15:0];   b1 = b[31:16];  b2 = b[47:32];  b3 = b[63:48];
      y0 = a0 - b0;   y1 = a1 - b1;   y2 = a2 - b2;   y3 = a3 - b3;
      sub16x4 = {y3,y2,y1,y0};
    end
  endfunction

  function [63:0] mul16x4;
    input [63:0] a;
    input [63:0] b;
    reg signed [15:0] a0,a1,a2,a3;
    reg signed [15:0] b0,b1,b2,b3;
    reg signed [31:0] p0,p1,p2,p3;
    begin
      a0 = a[15:0];   a1 = a[31:16];  a2 = a[47:32];  a3 = a[63:48];
      b0 = b[15:0];   b1 = b[31:16];  b2 = b[47:32];  b3 = b[63:48];
      p0 = a0 * b0;   p1 = a1 * b1;   p2 = a2 * b2;   p3 = a3 * b3;
      mul16x4 = {p3[15:0],p2[15:0],p1[15:0],p0[15:0]};
    end
  endfunction

  function [63:0] relu16x4;
    input [63:0] a;
    reg signed [15:0] a0,a1,a2,a3;
    reg signed [15:0] y0,y1,y2,y3;
    begin
      a0 = a[15:0];   a1 = a[31:16];  a2 = a[47:32];  a3 = a[63:48];
      y0 = (a0 < 0) ? 16'd0 : a0;
      y1 = (a1 < 0) ? 16'd0 : a1;
      y2 = (a2 < 0) ? 16'd0 : a2;
      y3 = (a3 < 0) ? 16'd0 : a3;
      relu16x4 = {y3,y2,y1,y0};
    end
  endfunction

  function [63:0] loadi4;
    input [15:0] imm;
    begin
      loadi4 = {imm,imm,imm,imm};
    end
  endfunction

  function [15:0] get16;
    input [63:0] v;
    input [1:0]  idx;
    begin
      case (idx)
        2'd0: get16 = v[15:0];
        2'd1: get16 = v[31:16];
        2'd2: get16 = v[47:32];
        default: get16 = v[63:48];
      endcase
    end
  endfunction

  function [63:0] set16;
    input [63:0] v;
    input [1:0]  idx;
    input [15:0] w;
    reg [63:0] t;
    begin
      t = v;
      case (idx)
        2'd0: t[15:0]     = w;
        2'd1: t[31:16]    = w;
        2'd2: t[47:32]    = w;
        default: t[63:48] = w;
      endcase
      set16 = t;
    end
  endfunction

  wire is_load       = in_ctrl[0];
  wire is_store      = in_ctrl[1];
  wire is_loadi      = in_ctrl[2];
  wire is_mov        = in_ctrl[3];
  wire is_add        = in_ctrl[4];
  wire is_sub        = in_ctrl[5];
  wire is_mul        = in_ctrl[6];
  wire is_relu       = in_ctrl[7];
  wire is_tensor_mul = in_ctrl[8];
  wire is_tensor_mac = in_ctrl[9];
  wire is_blt        = in_ctrl[10];
  wire is_jump       = in_ctrl[11];
  wire is_halt       = in_ctrl[12];

  wire pipe_op_now = is_load | is_store | is_loadi | is_mov | is_add | is_sub | is_mul | is_relu | is_tensor_mul | is_tensor_mac;
  wire any_active  = |in_lane_mask;

  assign jump_valid = is_jump | (is_blt & any_active);
  assign jump_addr  = in_imm[PC_W-1:0];
  assign halt_pulse = in_valid & is_halt;
  assign flush_pipe = jump_valid;  // Don't flush on halt to avoid combinational loop

  reg        bf_busy;
  reg        bf_commit;
  reg [2:0]  bf_state;
  reg [2:0]  bf_idx;
  reg [15:0] bf_ctrl;
  reg [2:0]  bf_rd;
  reg [1:0]  bf_lane_mask;
  reg [63:0] bf_op1_0, bf_op1_1;
  reg [63:0] bf_op2_0, bf_op2_1;
  reg [63:0] bf_acc_0, bf_acc_1;
  reg [63:0] bf_res_0, bf_res_1;

  reg [15:0] mul_a_r, mul_b_r;
  reg [15:0] add_a_r, add_b_r;
  wire [15:0] mul_r;
  wire [15:0] add_r;

  reg [7:0]  mul_wait;
  reg [7:0]  add_wait;
  reg [15:0] p16_r;
  reg [15:0] y16_r;

  localparam [2:0] BF_IDLE     = 3'd0;
  localparam [2:0] BF_LOAD_MUL = 3'd1;
  localparam [2:0] BF_WAIT_MUL = 3'd2;
  localparam [2:0] BF_LOAD_ADD = 3'd3;
  localparam [2:0] BF_WAIT_ADD = 3'd4;
  localparam [2:0] BF_WRITE    = 3'd5;
  localparam [2:0] BF_COMMIT   = 3'd6;
  
  wire bf_op  = in_valid & in_dtype & (is_mul | is_tensor_mul | is_tensor_mac);
  wire bf_req = bf_op & ~bf_busy & ~bf_commit;

  wire do_mul16 = (~in_dtype) & (is_mul | is_tensor_mul | is_tensor_mac);
  wire do_mac16 = (~in_dtype) & is_tensor_mac;

  wire       bf_lane = bf_idx[2];
  wire [1:0] bf_elem = bf_idx[1:0];

  wire [15:0] cur_a16 = bf_lane ? get16(bf_op1_1, bf_elem) : get16(bf_op1_0, bf_elem);
  wire [15:0] cur_b16 = bf_lane ? get16(bf_op2_1, bf_elem) : get16(bf_op2_0, bf_elem);
  wire [15:0] cur_c16 = bf_lane ? get16(bf_acc_1, bf_elem) : get16(bf_acc_0, bf_elem);

  bf16_mult u_bf16_mult (
    .clk(clk),
    .a(mul_a_r),
    .b(mul_b_r),
    .result(mul_r)
  );

  bf16_add_sub u_bf16_add_sub (
    .clk(clk),
    .operation(6'b000000),
    .a(add_a_r),
    .b(add_b_r),
    .result(add_r)
  );

  always @(posedge clk) begin
    if (rst) begin
      bf_busy      <= 1'b0;
      bf_commit    <= 1'b0;
      bf_state     <= BF_IDLE;
      bf_idx       <= 3'd0;
      bf_ctrl      <= 16'd0;
      bf_rd        <= 3'd0;
      bf_lane_mask <= 2'd0;
      bf_op1_0     <= 64'd0;
      bf_op1_1     <= 64'd0;
      bf_op2_0     <= 64'd0;
      bf_op2_1     <= 64'd0;
      bf_acc_0     <= 64'd0;
      bf_acc_1     <= 64'd0;
      bf_res_0     <= 64'd0;
      bf_res_1     <= 64'd0;
      mul_a_r      <= 16'd0;
      mul_b_r      <= 16'd0;
      add_a_r      <= 16'd0;
      add_b_r      <= 16'd0;
      mul_wait     <= 8'd0;
      add_wait     <= 8'd0;
      p16_r        <= 16'd0;
      y16_r        <= 16'd0;
    end else begin
      if (bf_commit) bf_commit <= 1'b0;

      case (bf_state)
        BF_IDLE: begin
          if (bf_req) begin
            bf_busy      <= 1'b1;
            bf_state     <= BF_LOAD_MUL;
            bf_idx       <= 3'd0;
            bf_ctrl      <= in_ctrl;
            bf_rd        <= in_rd;
            bf_lane_mask <= in_lane_mask;
            bf_op1_0     <= in_op1_0;
            bf_op1_1     <= in_op1_1;
            bf_op2_0     <= in_op2_0;
            bf_op2_1     <= in_op2_1;
            bf_acc_0     <= in_acc_0;
            bf_acc_1     <= in_acc_1;
            bf_res_0     <= 64'd0;
            bf_res_1     <= 64'd0;
          end
        end

        BF_LOAD_MUL: begin
          mul_a_r  <= cur_a16;
          mul_b_r  <= cur_b16;
          mul_wait <= BFMUL_OBS_LAT - 1;
          bf_state <= BF_WAIT_MUL;
        end

        BF_WAIT_MUL: begin
          if (mul_wait != 0) begin
            mul_wait <= mul_wait - 1'b1;
          end else begin
            p16_r <= mul_r;
            if (bf_ctrl[9]) begin
              bf_state <= BF_LOAD_ADD;
            end else begin
              y16_r   <= mul_r;
              bf_state <= BF_WRITE;
            end
          end
        end

        BF_LOAD_ADD: begin
          add_a_r  <= cur_c16;
          add_b_r  <= p16_r;
          add_wait <= BFADD_OBS_LAT - 1;
          bf_state <= BF_WAIT_ADD;
        end

        BF_WAIT_ADD: begin
          if (add_wait != 0) begin
            add_wait <= add_wait - 1'b1;
          end else begin
            y16_r   <= add_r;
            bf_state <= BF_WRITE;
          end
        end

        BF_WRITE: begin
          if (!bf_lane) begin
            bf_res_0 <= set16(bf_res_0, bf_elem, y16_r);
          end else begin
            bf_res_1 <= set16(bf_res_1, bf_elem, y16_r);
          end

          if (bf_idx == 3'd7) begin
            bf_state <= BF_COMMIT;
          end else begin
            bf_idx   <= bf_idx + 3'd1;
            bf_state <= BF_LOAD_MUL;
          end
        end

        BF_COMMIT: begin
          bf_busy   <= 1'b0;
          bf_commit <= 1'b1;
          bf_state  <= BF_IDLE;
        end

        default: begin
          bf_state <= BF_IDLE;
          bf_busy  <= 1'b0;
        end
      endcase
    end
  end

  assign stall = bf_busy | bf_commit | bf_req;
  assign consume_pulse = (bf_state == BF_WRITE) && (bf_idx == 3'd7);

  wire [31:0] imm_sext = {{16{in_imm[15]}}, in_imm};

  wire [DMEM_AW-1:0] base_w = in_base_sel[DMEM_AW-1:0];
  wire [DMEM_AW-1:0] tid_w  = in_tid_base[DMEM_AW-1:0];
  wire [DMEM_AW-1:0] imm_w  = imm_sext[DMEM_AW-1:0];

  assign out_addr0 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd0} + imm_w;
  assign out_addr1 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd1} + imm_w;

  assign out_store0 = in_op2_0;
  assign out_store1 = in_op2_1;

  wire [63:0] mul0 = mul16x4(in_op1_0, in_op2_0);
  wire [63:0] mul1 = mul16x4(in_op1_1, in_op2_1);

  wire [63:0] mac0 = add16x4(in_acc_0, mul0);
  wire [63:0] mac1 = add16x4(in_acc_1, mul1);

  wire [63:0] comb0 =
      is_loadi ? loadi4(in_imm) :
      is_mov   ? in_op1_0 :
      is_add   ? add16x4(in_op1_0, in_op2_0) :
      is_sub   ? sub16x4(in_op1_0, in_op2_0) :
      do_mac16 ? mac0 :
      do_mul16 ? mul0 :
      is_relu  ? relu16x4(in_op1_0) :
      64'd0;

  wire [63:0] comb1 =
      is_loadi ? loadi4(in_imm) :
      is_mov   ? in_op1_1 :
      is_add   ? add16x4(in_op1_1, in_op2_1) :
      is_sub   ? sub16x4(in_op1_1, in_op2_1) :
      do_mac16 ? mac1 :
      do_mul16 ? mul1 :
      is_relu  ? relu16x4(in_op1_1) :
      64'd0;

  assign out_valid = bf_commit ? 1'b1 :
                     ((bf_busy | bf_op) ? 1'b0 : (in_valid & pipe_op_now));

  assign out_ctrl      = bf_commit ? bf_ctrl      : in_ctrl;
  assign out_rd        = bf_commit ? bf_rd        : in_rd;
  assign out_lane_mask = bf_commit ? bf_lane_mask : in_lane_mask;

  assign out_res0 = bf_commit ? bf_res_0 : comb0;
  assign out_res1 = bf_commit ? bf_res_1 : comb1;

endmodule

module gpu_ex_mm_reg #(
  parameter DMEM_AW = 10
)(
  input  wire               clk,
  input  wire               rst,
  input  wire               stall,
  input  wire               consume_pulse,

  input  wire               in_valid,
  input  wire [15:0]        in_ctrl,
  input  wire [2:0]         in_rd,
  input  wire [1:0]         in_lane_mask,

  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,

  input  wire [63:0]        in_store0,
  input  wire [63:0]        in_store1,

  input  wire [63:0]        in_res0,
  input  wire [63:0]        in_res1,

  output reg                out_valid,
  output reg  [15:0]        out_ctrl,
  output reg  [2:0]         out_rd,
  output reg  [1:0]         out_lane_mask,

  output reg  [DMEM_AW-1:0] out_addr0,
  output reg  [DMEM_AW-1:0] out_addr1,

  output reg  [63:0]        out_store0,
  output reg  [63:0]        out_store1,

  output reg  [63:0]        out_res0,
  output reg  [63:0]        out_res1
);

  always @(posedge clk) begin
    if (rst) begin
      out_valid      <= 1'b0;
      out_ctrl       <= 16'd0;
      out_rd         <= 3'd0;
      out_lane_mask  <= 2'd0;
      out_addr0      <= {DMEM_AW{1'b0}};
      out_addr1      <= {DMEM_AW{1'b0}};
      out_store0     <= 64'd0;
      out_store1     <= 64'd0;
      out_res0       <= 64'd0;
      out_res1       <= 64'd0;
    end else begin
      /*
      if (consume_pulse) begin
        out_valid <= 1'b0;
      end else if (!stall) begin
        out_valid      <= in_valid;
        out_ctrl       <= in_ctrl;
        out_rd         <= in_rd;
        out_lane_mask  <= in_lane_mask;
        out_addr0      <= in_addr0;
        out_addr1      <= in_addr1;
        out_store0     <= in_store0;
        out_store1     <= in_store1;
        out_res0       <= in_res0;
        out_res1       <= in_res1;
      end
      */
      if (!stall) begin
        out_valid      <= in_valid;
        out_ctrl       <= in_ctrl;
        out_rd         <= in_rd;
        out_lane_mask  <= in_lane_mask;
        out_addr0      <= in_addr0;
        out_addr1      <= in_addr1;
        out_store0     <= in_store0;
        out_store1     <= in_store1;
        out_res0       <= in_res0;
        out_res1       <= in_res1;
      end else if (consume_pulse) begin
        out_valid <= 1'b0;
      end
    end
  end

endmodule

module gpu_mm_stage #(
  parameter DMEM_AW = 10
)(
  input  wire               clk,
  input  wire               rst,
  input  wire               proc_active,

  input  wire               in_valid,
  input  wire [15:0]        in_ctrl,
  input  wire [2:0]         in_rd,
  input  wire [1:0]         in_lane_mask,
  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,
  input  wire [63:0]        in_store0,
  input  wire [63:0]        in_store1,
  input  wire [63:0]        in_res0,
  input  wire [63:0]        in_res1,

  output wire               consume_pulse,
  output wire               stall_mm,

  output wire               mem0_en,
  output wire               mem0_we,
  output wire [DMEM_AW-1:0] mem0_addr,
  output wire [63:0]        mem0_wdata,
  input  wire [63:0]        mem0_rdata,
  input  wire               mem0_rvalid,

  output wire               mem1_en,
  output wire               mem1_we,
  output wire [DMEM_AW-1:0] mem1_addr,
  output wire [63:0]        mem1_wdata,
  input  wire [63:0]        mem1_rdata,
  input  wire               mem1_rvalid,

  output wire               out_valid,
  output wire [15:0]        out_ctrl,
  output wire [2:0]         out_rd,
  output wire [1:0]         out_lane_mask,
  output wire [63:0]        dmem_rdata0,
  output wire [63:0]        dmem_rdata1,
  output wire [63:0]        out_res0,
  output wire [63:0]        out_res1
);

  reg         load_pending;

  wire is_load  = in_ctrl[0];
  wire is_store = in_ctrl[1];

  wire issue_load  = in_valid & is_load  & ~load_pending;
  wire issue_store = in_valid & is_store;

  wire load_rsp_done = load_pending &&
                       ((!in_lane_mask[0] || mem0_rvalid) &&
                        (!in_lane_mask[1] || mem1_rvalid));

  assign consume_pulse = in_valid & (((~is_load) & (~is_store)) | issue_store | load_rsp_done);

  assign mem0_en    = (issue_load | issue_store) & in_lane_mask[0];
  assign mem0_we    = issue_store & in_lane_mask[0];
  assign mem0_addr  = in_addr0;
  assign mem0_wdata = in_store0;

  assign mem1_en    = (issue_load | issue_store) & in_lane_mask[1];
  assign mem1_we    = issue_store & in_lane_mask[1];
  assign mem1_addr  = in_addr1;
  assign mem1_wdata = in_store1;

  assign stall_mm = issue_load | (load_pending & ~load_rsp_done);

  assign out_valid = load_rsp_done ? 1'b1 : ((in_valid && !is_load) ? 1'b1 : 1'b0);

  assign out_ctrl      = in_ctrl;
  assign out_rd        = in_rd;
  assign out_lane_mask = in_lane_mask;
  assign out_res0      = in_res0;
  assign out_res1      = in_res1;

  assign dmem_rdata0 = mem0_rdata;
  assign dmem_rdata1 = mem1_rdata;

  always @(posedge clk) begin
    if (rst) begin
      load_pending <= 1'b0;
    end else begin
      if (issue_load) begin
        load_pending <= 1'b1;
      end else if (load_rsp_done) begin
        load_pending <= 1'b0;
      end
    end
  end

endmodule

module gpu_mm_wb_reg (
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [1:0]  in_lane_mask,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,

  input  wire [63:0] in_load0,
  input  wire [63:0] in_load1,

  output reg         out_valid,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg  [1:0]  out_lane_mask,

  output reg  [63:0] out_res0,
  output reg  [63:0] out_res1,

  output wire [63:0] out_load0,
  output wire [63:0] out_load1
);

  assign out_load0 = in_load0;
  assign out_load1 = in_load1;

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_lane_mask <= 2'd0;
      out_res0      <= 64'd0;
      out_res1      <= 64'd0;
    end else begin
      out_valid     <= in_valid;
      out_ctrl      <= in_ctrl;
      out_rd        <= in_rd;
      out_lane_mask <= in_lane_mask;
      out_res0      <= in_res0;
      out_res1      <= in_res1;
    end
  end

endmodule


module gpu_wb_stage (
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [1:0]  in_lane_mask,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,

  input  wire [63:0] in_load0,
  input  wire [63:0] in_load1,

  output wire        wb_we0,
  output wire        wb_we1,
  output wire [2:0]  wb_rd,
  output wire [63:0] wb_wdata0,
  output wire [63:0] wb_wdata1
);

  wire is_load       = in_ctrl[0];
  wire is_loadi      = in_ctrl[2];
  wire is_mov        = in_ctrl[3];
  wire is_add        = in_ctrl[4];
  wire is_sub        = in_ctrl[5];
  wire is_mul        = in_ctrl[6];
  wire is_relu       = in_ctrl[7];
  wire is_tensor_mul = in_ctrl[8];
  wire is_tensor_mac = in_ctrl[9];

  wire wants_wb = is_load | is_loadi | is_mov | is_add | is_sub | is_mul | is_relu | is_tensor_mul | is_tensor_mac;
  wire wb_fire = in_valid & wants_wb;

  assign wb_rd = in_rd;
  assign wb_wdata0 = is_load ? in_load0 : in_res0;
  assign wb_wdata1 = is_load ? in_load1 : in_res1;
  assign wb_we0 = wb_fire & in_lane_mask[0];
  assign wb_we1 = wb_fire & in_lane_mask[1];

endmodule
