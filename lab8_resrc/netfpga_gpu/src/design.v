// Code your design here
`timescale 1ns/1ps

module gpu_top #(
  parameter MMIO_ADDR_W = 8,
  parameter DMEM_AW     = 10,
  parameter DMEM_DEPTH  = 1024
)(
  input  wire                   clk,
  input  wire                   rst,

  input  wire                   mmio_wr_en,
  input  wire                   mmio_rd_en,
  input  wire [MMIO_ADDR_W-1:0] mmio_addr,
  input  wire [31:0]            mmio_wdata,
  output wire [31:0]            mmio_rdata
);

  wire        run_en;
  wire        start_pulse;
  wire        clear_done_pulse;
  wire        soft_reset_pulse;

  wire [8:0]  entry_pc;
  wire [31:0] tid_init;
  wire [31:0] work_size;
  wire [31:0] work_size_eff;
  wire [31:0] m, n, k;

  wire [63:0] base_a, base_b, base_c, base_d;

  wire        busy, done, error;
  wire [7:0]  error_code;

  wire        hw_error_pulse;
  wire [7:0]  hw_error_code;

  assign hw_error_pulse = 1'b0;
  assign hw_error_code  = 8'h00;

  wire [8:0]  pc_if;
  wire [31:0] instr_if;

  wire [8:0]  pc_id;
  wire [31:0] instr_id;
  wire        flush_id;

  wire        jump_valid;
  wire [8:0]  jump_addr;
  wire        flush_pipe;
  wire        ex_halt_pulse;

  wire        id_valid;
  wire [8:0]  id_pc;
  wire [15:0] id_ctrl;
  wire [2:0]  id_rd;
  wire        id_dtype;
  wire [1:0]  id_bsel;
  wire [15:0] id_imm;
  wire [63:0] id_base_sel;
  wire [31:0] id_tid_base;
  wire [3:0]  id_lane_mask;

  wire [63:0] id_op1_0, id_op1_1, id_op1_2, id_op1_3;
  wire [63:0] id_op2_0, id_op2_1, id_op2_2, id_op2_3;
  wire [63:0] id_acc_0, id_acc_1, id_acc_2, id_acc_3;

  wire         ex_in_valid;
  wire [8:0]   ex_in_pc;
  wire [15:0]  ex_in_ctrl;
  wire [2:0]   ex_in_rd;
  wire         ex_in_dtype;
  wire [15:0]  ex_in_imm;
  wire [63:0]  ex_in_base_sel;
  wire [31:0]  ex_in_tid_base;
  wire [3:0]   ex_in_lane_mask;
  wire [63:0]  ex_in_op1_0, ex_in_op1_1, ex_in_op1_2, ex_in_op1_3;
  wire [63:0]  ex_in_op2_0, ex_in_op2_1, ex_in_op2_2, ex_in_op2_3;
  wire [63:0]  ex_in_acc_0, ex_in_acc_1, ex_in_acc_2, ex_in_acc_3;

  wire        ex_out_valid;
  wire [15:0] ex_out_ctrl;
  wire [2:0]  ex_out_rd;
  wire [3:0]  ex_out_lane_mask;

  wire [DMEM_AW-1:0] ex_addr0, ex_addr1, ex_addr2, ex_addr3;
  wire [63:0]        ex_store0, ex_store1, ex_store2, ex_store3;
  wire [63:0]        ex_res0, ex_res1, ex_res2, ex_res3;

  wire        mm_in_valid;
  wire [15:0] mm_in_ctrl;
  wire [2:0]  mm_in_rd;
  wire [3:0]  mm_in_lane_mask;
  wire [DMEM_AW-1:0] mm_addr0, mm_addr1, mm_addr2, mm_addr3;
  wire [63:0]        mm_store0, mm_store1, mm_store2, mm_store3;
  wire [63:0]        mm_res0, mm_res1, mm_res2, mm_res3;

  wire        mm_out_valid;
  wire [15:0] mm_out_ctrl;
  wire [2:0]  mm_out_rd;
  wire [3:0]  mm_out_lane_mask;
  wire [63:0] dmem_rdata0, dmem_rdata1, dmem_rdata2, dmem_rdata3;
  wire [63:0] mm_out_res0, mm_out_res1, mm_out_res2, mm_out_res3;

  wire        wb_in_valid;
  wire [15:0] wb_in_ctrl;
  wire [2:0]  wb_in_rd;
  wire [3:0]  wb_in_lane_mask;
  wire [63:0] wb_in_res0, wb_in_res1, wb_in_res2, wb_in_res3;
  wire [63:0] wb_in_load0, wb_in_load1, wb_in_load2, wb_in_load3;

  wire        wb_we0, wb_we1, wb_we2, wb_we3;
  wire [2:0]  wb_rd;
  wire [63:0] wb_wdata0, wb_wdata1, wb_wdata2, wb_wdata3;

  wire        stall_ex;
  wire        ex_consume_pulse;

  wire        hw_done_pulse;
  assign hw_done_pulse = ex_halt_pulse;

  gpu_control #(.ADDR_W(MMIO_ADDR_W)) u_ctrl (
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

  if_stage u_if (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall_ex),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .imem_we(1'b0),
    .imem_waddr(9'd0),
    .imem_wdata(32'd0),
    .pc_if(pc_if),
    .instr_if(instr_if)
  );

  if_id_reg u_ifid (
    .clk(clk),
    .rst(rst),
    .stall(stall_ex),
    .pc_in(pc_if),
    .instr_in(instr_if),
    .flush_in(flush_pipe),
    .pc_id(pc_id),
    .instr_id(instr_id),
    .flush_out(flush_id)
  );

  id_stage u_id (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall_ex),
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
    .wb_we2(wb_we2),
    .wb_we3(wb_we3),
    .wb_rd(wb_rd),
    .wb_wdata0(wb_wdata0),
    .wb_wdata1(wb_wdata1),
    .wb_wdata2(wb_wdata2),
    .wb_wdata3(wb_wdata3),
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
    .id_op1_2(id_op1_2),
    .id_op1_3(id_op1_3),
    .id_op2_0(id_op2_0),
    .id_op2_1(id_op2_1),
    .id_op2_2(id_op2_2),
    .id_op2_3(id_op2_3),
    .id_acc_0(id_acc_0),
    .id_acc_1(id_acc_1),
    .id_acc_2(id_acc_2),
    .id_acc_3(id_acc_3)
  );

  id_ex_reg u_idex (
    .clk(clk),
    .rst(rst),
    .stall(stall_ex),
    .flush_in(flush_pipe),
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
    .in_op1_2(id_op1_2),
    .in_op1_3(id_op1_3),
    .in_op2_0(id_op2_0),
    .in_op2_1(id_op2_1),
    .in_op2_2(id_op2_2),
    .in_op2_3(id_op2_3),
    .in_acc_0(id_acc_0),
    .in_acc_1(id_acc_1),
    .in_acc_2(id_acc_2),
    .in_acc_3(id_acc_3),
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
    .out_op1_2(ex_in_op1_2),
    .out_op1_3(ex_in_op1_3),
    .out_op2_0(ex_in_op2_0),
    .out_op2_1(ex_in_op2_1),
    .out_op2_2(ex_in_op2_2),
    .out_op2_3(ex_in_op2_3),
    .out_acc_0(ex_in_acc_0),
    .out_acc_1(ex_in_acc_1),
    .out_acc_2(ex_in_acc_2),
    .out_acc_3(ex_in_acc_3)
  );

  ex_stage #(.DMEM_AW(DMEM_AW)) u_ex (
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
    .in_op1_2(ex_in_op1_2),
    .in_op1_3(ex_in_op1_3),
    .in_op2_0(ex_in_op2_0),
    .in_op2_1(ex_in_op2_1),
    .in_op2_2(ex_in_op2_2),
    .in_op2_3(ex_in_op2_3),
    .in_acc_0(ex_in_acc_0),
    .in_acc_1(ex_in_acc_1),
    .in_acc_2(ex_in_acc_2),
    .in_acc_3(ex_in_acc_3),
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
    .out_addr2(ex_addr2),
    .out_addr3(ex_addr3),
    .out_store0(ex_store0),
    .out_store1(ex_store1),
    .out_store2(ex_store2),
    .out_store3(ex_store3),
    .out_res0(ex_res0),
    .out_res1(ex_res1),
    .out_res2(ex_res2),
    .out_res3(ex_res3)
  );

  ex_mm_reg #(.DMEM_AW(DMEM_AW)) u_exmm (
    .clk(clk),
    .rst(rst),
    .in_valid(ex_out_valid),
    .in_ctrl(ex_out_ctrl),
    .in_rd(ex_out_rd),
    .in_lane_mask(ex_out_lane_mask),
    .in_addr0(ex_addr0),
    .in_addr1(ex_addr1),
    .in_addr2(ex_addr2),
    .in_addr3(ex_addr3),
    .in_store0(ex_store0),
    .in_store1(ex_store1),
    .in_store2(ex_store2),
    .in_store3(ex_store3),
    .in_res0(ex_res0),
    .in_res1(ex_res1),
    .in_res2(ex_res2),
    .in_res3(ex_res3),
    .out_valid(mm_in_valid),
    .out_ctrl(mm_in_ctrl),
    .out_rd(mm_in_rd),
    .out_lane_mask(mm_in_lane_mask),
    .out_addr0(mm_addr0),
    .out_addr1(mm_addr1),
    .out_addr2(mm_addr2),
    .out_addr3(mm_addr3),
    .out_store0(mm_store0),
    .out_store1(mm_store1),
    .out_store2(mm_store2),
    .out_store3(mm_store3),
    .out_res0(mm_res0),
    .out_res1(mm_res1),
    .out_res2(mm_res2),
    .out_res3(mm_res3)
  );

  mm_stage #(.DMEM_AW(DMEM_AW), .DMEM_DEPTH(DMEM_DEPTH)) u_mm (
    .clk(clk),
    .rst(rst),
    .in_valid(mm_in_valid),
    .in_ctrl(mm_in_ctrl),
    .in_rd(mm_in_rd),
    .in_lane_mask(mm_in_lane_mask),
    .in_addr0(mm_addr0),
    .in_addr1(mm_addr1),
    .in_addr2(mm_addr2),
    .in_addr3(mm_addr3),
    .in_store0(mm_store0),
    .in_store1(mm_store1),
    .in_store2(mm_store2),
    .in_store3(mm_store3),
    .in_res0(mm_res0),
    .in_res1(mm_res1),
    .in_res2(mm_res2),
    .in_res3(mm_res3),
    .out_valid(mm_out_valid),
    .out_ctrl(mm_out_ctrl),
    .out_rd(mm_out_rd),
    .out_lane_mask(mm_out_lane_mask),
    .dmem_rdata0(dmem_rdata0),
    .dmem_rdata1(dmem_rdata1),
    .dmem_rdata2(dmem_rdata2),
    .dmem_rdata3(dmem_rdata3),
    .out_res0(mm_out_res0),
    .out_res1(mm_out_res1),
    .out_res2(mm_out_res2),
    .out_res3(mm_out_res3)
  );

  mm_wb_reg u_mmwbr (
    .clk(clk),
    .rst(rst),
    .in_valid(mm_out_valid),
    .in_ctrl(mm_out_ctrl),
    .in_rd(mm_out_rd),
    .in_lane_mask(mm_out_lane_mask),
    .in_res0(mm_out_res0),
    .in_res1(mm_out_res1),
    .in_res2(mm_out_res2),
    .in_res3(mm_out_res3),
    .in_load0(dmem_rdata0),
    .in_load1(dmem_rdata1),
    .in_load2(dmem_rdata2),
    .in_load3(dmem_rdata3),
    .out_valid(wb_in_valid),
    .out_ctrl(wb_in_ctrl),
    .out_rd(wb_in_rd),
    .out_lane_mask(wb_in_lane_mask),
    .out_res0(wb_in_res0),
    .out_res1(wb_in_res1),
    .out_res2(wb_in_res2),
    .out_res3(wb_in_res3),
    .out_load0(wb_in_load0),
    .out_load1(wb_in_load1),
    .out_load2(wb_in_load2),
    .out_load3(wb_in_load3)
  );

  wb_stage u_wb (
    .clk(clk),
    .rst(rst),
    .in_valid(wb_in_valid),
    .in_ctrl(wb_in_ctrl),
    .in_rd(wb_in_rd),
    .in_lane_mask(wb_in_lane_mask),
    .in_res0(wb_in_res0),
    .in_res1(wb_in_res1),
    .in_res2(wb_in_res2),
    .in_res3(wb_in_res3),
    .in_load0(wb_in_load0),
    .in_load1(wb_in_load1),
    .in_load2(wb_in_load2),
    .in_load3(wb_in_load3),
    .wb_we0(wb_we0),
    .wb_we1(wb_we1),
    .wb_we2(wb_we2),
    .wb_we3(wb_we3),
    .wb_rd(wb_rd),
    .wb_wdata0(wb_wdata0),
    .wb_wdata1(wb_wdata1),
    .wb_wdata2(wb_wdata2),
    .wb_wdata3(wb_wdata3)
  );

endmodule


module gpu_control #(
  parameter ADDR_W = 8
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

  output reg  [8:0]        entry_pc,
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
        REG_ENTRY_PC:   mmio_rdata_next = {23'd0, entry_pc};
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
      entry_pc         <= 9'd0;
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
            entry_pc         <= 9'd0;
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
              REG_ENTRY_PC:   entry_pc      <= mmio_wdata[8:0];
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

module if_stage (
  input  wire        clk,
  input  wire        rst,

  input  wire        run_en,
  input  wire        start_pulse,
  input  wire [8:0]  entry_pc,
  input  wire        soft_reset_pulse,

  input  wire        stall,

  input  wire        jump_valid,
  input  wire [8:0]  jump_addr,

  input  wire        imem_we,
  input  wire [8:0]  imem_waddr,
  input  wire [31:0] imem_wdata,

  output wire [8:0]  pc_if,
  output wire [31:0] instr_if
);

  wire [8:0]  pc_w;
  wire [8:0]  imem_addr_w;
  wire [31:0] imem_rdata_w;

  assign pc_if = pc_w;
  assign imem_addr_w = imem_we ? imem_waddr : pc_w;

  pc u_pc (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .pc(pc_w)
  );

  imem u_imem (
    .clk(clk),
    .we(imem_we),
    .addr(imem_addr_w),
    .wdata(imem_wdata),
    .rdata(imem_rdata_w)
  );

  assign instr_if = imem_rdata_w;

endmodule


module pc (
  input  wire       clk,
  input  wire       rst,
  input  wire       run_en,
  input  wire       start_pulse,
  input  wire [8:0] entry_pc,
  input  wire       soft_reset_pulse,
  input  wire       stall,
  input  wire       jump_valid,
  input  wire [8:0] jump_addr,
  output reg  [8:0] pc
);

  always @(posedge clk) begin
    if (rst) pc <= 9'd0;
    else if (soft_reset_pulse) pc <= 9'd0;
    else if (stall) pc <= pc;
    else if (start_pulse) pc <= entry_pc;
    else if (!run_en) pc <= pc;
    else if (jump_valid) pc <= jump_addr;
    else pc <= pc + 9'd1;
  end

endmodule


module imem #(
  parameter AW = 9,
  parameter DW = 32,
  parameter DEPTH = 512
)(
  input  wire           clk,
  input  wire           we,
  input  wire [AW-1:0]  addr,
  input  wire [DW-1:0]  wdata,
  output reg  [DW-1:0]  rdata
);

  reg [DW-1:0] mem [0:DEPTH-1];
  integer i;
  localparam [DW-1:0] NOP = 32'h00000013;

  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = NOP;
    rdata = NOP;
  end

  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    rdata <= we ? wdata : mem[addr];
  end

endmodule


module if_id_reg (
  input  wire        clk,
  input  wire        rst,

  input  wire        stall,

  input  wire [8:0]  pc_in,
  input  wire [31:0] instr_in,
  input  wire        flush_in,

  output reg  [8:0]  pc_id,
  output wire [31:0] instr_id,
  output reg         flush_out
);

  assign instr_id = instr_in;

  always @(posedge clk) begin
    if (rst) begin
      pc_id     <= 9'd0;
      flush_out <= 1'b0;
    end else if (!stall) begin
      pc_id     <= pc_in;
      flush_out <= flush_in;
    end
  end

endmodule


module id_stage (
  input  wire        clk,
  input  wire        rst,

  input  wire        run_en,
  input  wire        start_pulse,
  input  wire        soft_reset_pulse,

  input  wire        stall,
  input  wire        ex_flush,

  input  wire [31:0] tid_init,
  input  wire [31:0] work_size_eff,

  input  wire [63:0] base_a,
  input  wire [63:0] base_b,
  input  wire [63:0] base_c,
  input  wire [63:0] base_d,

  input  wire [8:0]  pc_id,
  input  wire [31:0] instr_id,
  input  wire        flush_id,

  input  wire        wb_we0,
  input  wire        wb_we1,
  input  wire        wb_we2,
  input  wire        wb_we3,
  input  wire [2:0]  wb_rd,
  input  wire [63:0] wb_wdata0,
  input  wire [63:0] wb_wdata1,
  input  wire [63:0] wb_wdata2,
  input  wire [63:0] wb_wdata3,

  output wire        id_valid,
  output wire [8:0]  id_pc,
  output wire [15:0] id_ctrl,
  output wire [2:0]  id_rd,
  output wire        id_dtype,
  output wire [1:0]  id_bsel,
  output wire [15:0] id_imm,
  output wire [63:0] id_base_sel,
  output wire [31:0] id_tid_base,
  output wire [3:0]  id_lane_mask,

  output wire [63:0] id_op1_0,
  output wire [63:0] id_op1_1,
  output wire [63:0] id_op1_2,
  output wire [63:0] id_op1_3,
  output wire [63:0] id_op2_0,
  output wire [63:0] id_op2_1,
  output wire [63:0] id_op2_2,
  output wire [63:0] id_op2_3,

  output wire [63:0] id_acc_0,
  output wire [63:0] id_acc_1,
  output wire [63:0] id_acc_2,
  output wire [63:0] id_acc_3
);

  reg [31:0] tid_base;

  reg run_d1;
  reg run_d2;

  reg stall_prev;
  reg stall_release;

  reg [63:0] rf0 [0:7];
  reg [63:0] rf1 [0:7];
  reg [63:0] rf2 [0:7];
  reg [63:0] rf3 [0:7];

  integer i;
  initial begin
    for (i = 0; i < 8; i = i + 1) begin
      rf0[i] = 64'd0;
      rf1[i] = 64'd0;
      rf2[i] = 64'd0;
      rf3[i] = 64'd0;
    end
  end

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      run_d1 <= 1'b0;
      run_d2 <= 1'b0;
    end else begin
      run_d1 <= run_en;
      run_d2 <= run_d1;
    end
  end

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      stall_prev    <= 1'b0;
      stall_release <= 1'b0;
    end else begin
      stall_release <= (stall_prev & ~stall);
      stall_prev    <= stall;
    end
  end

  wire [3:0]  opcode = instr_id[31:28];
  wire [2:0]  rd     = instr_id[27:25];
  wire [2:0]  rs1    = instr_id[24:22];
  wire [2:0]  rs2    = instr_id[21:19];
  wire [1:0]  bsel   = instr_id[18:17];
  wire        dtype  = instr_id[16];
  wire [15:0] imm    = instr_id[15:0];

  wire instr_valid0 = run_en & run_d2 & ~flush_id & ~stall & ~stall_release;
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
  wire [31:0] pack2 = tid_base + 32'd2;
  wire [31:0] pack3 = tid_base + 32'd3;

  wire lm0 = (pack0 < work_size_eff);
  wire lm1 = (pack1 < work_size_eff);
  wire lm2 = (pack2 < work_size_eff);
  wire lm3 = (pack3 < work_size_eff);

  wire [3:0] lane_mask = {lm3, lm2, lm1, lm0};

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

  wire pipe_op = is_load | is_store | is_loadi | is_mov | is_add | is_sub | is_mul | is_relu | is_tensor_mul | is_tensor_mac;
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
  wire [63:0] rf2_rs1 = rf2[rs1];
  wire [63:0] rf3_rs1 = rf3[rs1];

  wire [63:0] rf0_rs2 = rf0[rs2];
  wire [63:0] rf1_rs2 = rf1[rs2];
  wire [63:0] rf2_rs2 = rf2[rs2];
  wire [63:0] rf3_rs2 = rf3[rs2];

  wire [63:0] rf0_rd0 = rf0[rd];
  wire [63:0] rf1_rd0 = rf1[rd];
  wire [63:0] rf2_rd0 = rf2[rd];
  wire [63:0] rf3_rd0 = rf3[rd];

  assign id_op1_0 = (wb_we0 && (wb_rd == rs1)) ? wb_wdata0 : rf0_rs1;
  assign id_op1_1 = (wb_we1 && (wb_rd == rs1)) ? wb_wdata1 : rf1_rs1;
  assign id_op1_2 = (wb_we2 && (wb_rd == rs1)) ? wb_wdata2 : rf2_rs1;
  assign id_op1_3 = (wb_we3 && (wb_rd == rs1)) ? wb_wdata3 : rf3_rs1;

  assign id_op2_0 = (wb_we0 && (wb_rd == rs2)) ? wb_wdata0 : rf0_rs2;
  assign id_op2_1 = (wb_we1 && (wb_rd == rs2)) ? wb_wdata1 : rf1_rs2;
  assign id_op2_2 = (wb_we2 && (wb_rd == rs2)) ? wb_wdata2 : rf2_rs2;
  assign id_op2_3 = (wb_we3 && (wb_rd == rs2)) ? wb_wdata3 : rf3_rs2;

  assign id_acc_0 = (wb_we0 && (wb_rd == rd)) ? wb_wdata0 : rf0_rd0;
  assign id_acc_1 = (wb_we1 && (wb_rd == rd)) ? wb_wdata1 : rf1_rd0;
  assign id_acc_2 = (wb_we2 && (wb_rd == rd)) ? wb_wdata2 : rf2_rd0;
  assign id_acc_3 = (wb_we3 && (wb_rd == rd)) ? wb_wdata3 : rf3_rd0;

  always @(posedge clk) begin
    if (rst || soft_reset_pulse) begin
      tid_base <= 32'd0;
    end else if (start_pulse) begin
      tid_base <= tid_init;
    end else if (instr_valid && !ex_flush && is_set_tid) begin
      tid_base <= {16'd0, imm};
    end else if (instr_valid && !ex_flush && is_inc_tid) begin
      tid_base <= tid_base + 32'd4;
    end else begin
      tid_base <= tid_base;
    end
  end

  always @(posedge clk) begin
    if (wb_we0) rf0[wb_rd] <= wb_wdata0;
    if (wb_we1) rf1[wb_rd] <= wb_wdata1;
    if (wb_we2) rf2[wb_rd] <= wb_wdata2;
    if (wb_we3) rf3[wb_rd] <= wb_wdata3;
  end

endmodule


module id_ex_reg (
  input  wire        clk,
  input  wire        rst,

  input  wire        stall,
  input  wire        flush_in,
  input  wire        consume_pulse,

  input  wire        in_valid,
  input  wire [8:0]  in_pc,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire        in_dtype,
  input  wire [15:0] in_imm,
  input  wire [63:0] in_base_sel,
  input  wire [31:0] in_tid_base,
  input  wire [3:0]  in_lane_mask,

  input  wire [63:0] in_op1_0,
  input  wire [63:0] in_op1_1,
  input  wire [63:0] in_op1_2,
  input  wire [63:0] in_op1_3,
  input  wire [63:0] in_op2_0,
  input  wire [63:0] in_op2_1,
  input  wire [63:0] in_op2_2,
  input  wire [63:0] in_op2_3,

  input  wire [63:0] in_acc_0,
  input  wire [63:0] in_acc_1,
  input  wire [63:0] in_acc_2,
  input  wire [63:0] in_acc_3,

  output reg         out_valid,
  output reg  [8:0]  out_pc,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg         out_dtype,
  output reg  [15:0] out_imm,
  output reg  [63:0] out_base_sel,
  output reg  [31:0] out_tid_base,
  output reg  [3:0]  out_lane_mask,

  output reg  [63:0] out_op1_0,
  output reg  [63:0] out_op1_1,
  output reg  [63:0] out_op1_2,
  output reg  [63:0] out_op1_3,
  output reg  [63:0] out_op2_0,
  output reg  [63:0] out_op2_1,
  output reg  [63:0] out_op2_2,
  output reg  [63:0] out_op2_3,

  output reg  [63:0] out_acc_0,
  output reg  [63:0] out_acc_1,
  output reg  [63:0] out_acc_2,
  output reg  [63:0] out_acc_3
);

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_pc        <= 9'd0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_dtype     <= 1'b0;
      out_imm       <= 16'd0;
      out_base_sel  <= 64'd0;
      out_tid_base  <= 32'd0;
      out_lane_mask <= 4'd0;
      out_op1_0     <= 64'd0;
      out_op1_1     <= 64'd0;
      out_op1_2     <= 64'd0;
      out_op1_3     <= 64'd0;
      out_op2_0     <= 64'd0;
      out_op2_1     <= 64'd0;
      out_op2_2     <= 64'd0;
      out_op2_3     <= 64'd0;
      out_acc_0     <= 64'd0;
      out_acc_1     <= 64'd0;
      out_acc_2     <= 64'd0;
      out_acc_3     <= 64'd0;
    end else if (flush_in) begin
      out_valid     <= 1'b0;
      out_pc        <= 9'd0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_dtype     <= 1'b0;
      out_imm       <= 16'd0;
      out_base_sel  <= 64'd0;
      out_tid_base  <= 32'd0;
      out_lane_mask <= 4'd0;
      out_op1_0     <= 64'd0;
      out_op1_1     <= 64'd0;
      out_op1_2     <= 64'd0;
      out_op1_3     <= 64'd0;
      out_op2_0     <= 64'd0;
      out_op2_1     <= 64'd0;
      out_op2_2     <= 64'd0;
      out_op2_3     <= 64'd0;
      out_acc_0     <= 64'd0;
      out_acc_1     <= 64'd0;
      out_acc_2     <= 64'd0;
      out_acc_3     <= 64'd0;
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
        out_op1_2     <= in_op1_2;
        out_op1_3     <= in_op1_3;
        out_op2_0     <= in_op2_0;
        out_op2_1     <= in_op2_1;
        out_op2_2     <= in_op2_2;
        out_op2_3     <= in_op2_3;
        out_acc_0     <= in_acc_0;
        out_acc_1     <= in_acc_1;
        out_acc_2     <= in_acc_2;
        out_acc_3     <= in_acc_3;
      end
    end
  end

endmodule


module ex_stage #(
  parameter DMEM_AW = 10
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
  input  wire [3:0]  in_lane_mask,

  input  wire [63:0] in_op1_0,
  input  wire [63:0] in_op1_1,
  input  wire [63:0] in_op1_2,
  input  wire [63:0] in_op1_3,
  input  wire [63:0] in_op2_0,
  input  wire [63:0] in_op2_1,
  input  wire [63:0] in_op2_2,
  input  wire [63:0] in_op2_3,

  input  wire [63:0] in_acc_0,
  input  wire [63:0] in_acc_1,
  input  wire [63:0] in_acc_2,
  input  wire [63:0] in_acc_3,

  output wire        stall,
  output wire        consume_pulse,

  output wire        jump_valid,
  output wire [8:0]  jump_addr,
  output wire        flush_pipe,
  output wire        halt_pulse,

  output wire        out_valid,
  output wire [15:0] out_ctrl,
  output wire [2:0]  out_rd,
  output wire [3:0]  out_lane_mask,

  output wire [DMEM_AW-1:0] out_addr0,
  output wire [DMEM_AW-1:0] out_addr1,
  output wire [DMEM_AW-1:0] out_addr2,
  output wire [DMEM_AW-1:0] out_addr3,

  output wire [63:0] out_store0,
  output wire [63:0] out_store1,
  output wire [63:0] out_store2,
  output wire [63:0] out_store3,

  output wire [63:0] out_res0,
  output wire [63:0] out_res1,
  output wire [63:0] out_res2,
  output wire [63:0] out_res3
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

  function [31:0] bf16_to_fp32;
    input [15:0] h;
    begin
      bf16_to_fp32 = {h, 16'h0000};
    end
  endfunction

  function [15:0] fp32_to_bf16_rne;
    input [31:0] f;
    reg [15:0] top;
    reg [15:0] low;
    reg inc;
    reg [15:0] top_inc;
    begin
      top = f[31:16];
      low = f[15:0];
      inc = (low > 16'h8000) || ((low == 16'h8000) && (top[0] == 1'b1));
      top_inc = top + (inc ? 16'd1 : 16'd0);
      if ((f[30:23] == 8'hFF) && (f[22:0] != 23'd0)) begin
        fp32_to_bf16_rne = {top[15:7], 7'b0000001};
      end else begin
        fp32_to_bf16_rne = top_inc;
      end
    end
  endfunction

  function [31:0] fp32_mul_simple;
    input [31:0] a;
    input [31:0] b;
    reg sa, sb, so;
    reg [7:0] ea, eb;
    reg [22:0] fa, fb;
    reg a_zero, b_zero, a_inf, b_inf, a_nan, b_nan;
    reg [23:0] ma, mb;
    reg [47:0] prod;
    reg [8:0] e_sum;
    reg [7:0] e_out;
    reg [23:0] mant24;
    reg guard, roundb, sticky;
    reg inc;
    reg [24:0] mant25;
    begin
      sa = a[31];
      sb = b[31];
      ea = a[30:23];
      eb = b[30:23];
      fa = a[22:0];
      fb = b[22:0];

      a_zero = (ea == 8'd0)  && (fa == 23'd0);
      b_zero = (eb == 8'd0)  && (fb == 23'd0);
      a_inf  = (ea == 8'hFF) && (fa == 23'd0);
      b_inf  = (eb == 8'hFF) && (fb == 23'd0);
      a_nan  = (ea == 8'hFF) && (fa != 23'd0);
      b_nan  = (eb == 8'hFF) && (fb != 23'd0);

      if (a_nan || b_nan) begin
        fp32_mul_simple = 32'h7FC00000;
      end else if ((a_inf && b_zero) || (b_inf && a_zero)) begin
        fp32_mul_simple = 32'h7FC00000;
      end else if (a_inf || b_inf) begin
        so = sa ^ sb;
        fp32_mul_simple = {so, 8'hFF, 23'd0};
      end else if (a_zero || b_zero) begin
        so = sa ^ sb;
        fp32_mul_simple = {so, 8'd0, 23'd0};
      end else begin
        ma = {1'b1, fa};
        mb = {1'b1, fb};

        e_sum = {1'b0, ea} + {1'b0, eb} - 9'd127;
        prod  = ma * mb;
        so    = sa ^ sb;

        if (prod[47]) begin
          mant24 = prod[47:24];
          guard  = prod[23];
          roundb = prod[22];
          sticky = |prod[21:0];
          e_sum  = e_sum + 9'd1;
        end else begin
          mant24 = prod[46:23];
          guard  = prod[22];
          roundb = prod[21];
          sticky = |prod[20:0];
        end

        inc    = guard && (roundb || sticky || mant24[0]);
        mant25 = {1'b0, mant24} + (inc ? 25'd1 : 25'd0);

        if (mant25[24]) begin
          mant24 = mant25[24:1];
          e_sum  = e_sum + 9'd1;
        end else begin
          mant24 = mant25[23:0];
        end

        if (e_sum >= 9'd255) begin
          fp32_mul_simple = {so, 8'hFF, 23'd0};
        end else if (e_sum <= 9'd0) begin
          fp32_mul_simple = {so, 8'd0, 23'd0};
        end else begin
          e_out = e_sum[7:0];
          fp32_mul_simple = {so, e_out, mant24[22:0]};
        end
      end
    end
  endfunction

  function [31:0] fp32_add_simple;
    input [31:0] a;
    input [31:0] b;
    reg sa, sb, so;
    reg [7:0] ea, eb;
    reg [22:0] fa, fb;
    reg a_zero, b_zero, a_inf, b_inf, a_nan, b_nan;

    reg [7:0] e_big, e_sml;
    reg s_big, s_sml;
    reg [23:0] m_big, m_sml;

    reg [7:0] diff;
    reg [26:0] big_ext, sml_ext;
    reg sticky;
    integer j;

    reg [27:0] sum_ext;
    reg [7:0] e_norm;
    reg [26:0] m_norm;

    reg guard, roundb;
    reg inc;
    reg [23:0] mant24;
    integer shift_cnt;
    reg found;
    begin
      sa = a[31]; sb = b[31];
      ea = a[30:23]; eb = b[30:23];
      fa = a[22:0];  fb = b[22:0];

      a_zero = (ea == 8'd0) && (fa == 23'd0);
      b_zero = (eb == 8'd0) && (fb == 23'd0);
      a_inf  = (ea == 8'hFF) && (fa == 23'd0);
      b_inf  = (eb == 8'hFF) && (fb == 23'd0);
      a_nan  = (ea == 8'hFF) && (fa != 23'd0);
      b_nan  = (eb == 8'hFF) && (fb != 23'd0);

      if (a_nan || b_nan) begin
        fp32_add_simple = 32'h7FC00000;
      end else if (a_inf && b_inf && (sa != sb)) begin
        fp32_add_simple = 32'h7FC00000;
      end else if (a_inf) begin
        fp32_add_simple = a;
      end else if (b_inf) begin
        fp32_add_simple = b;
      end else if (a_zero) begin
        fp32_add_simple = b;
      end else if (b_zero) begin
        fp32_add_simple = a;
      end else begin
        if (ea > eb) begin
          e_big = ea; e_sml = eb;
          s_big = sa; s_sml = sb;
          m_big = {1'b1, fa};
          m_sml = {1'b1, fb};
        end else if (eb > ea) begin
          e_big = eb; e_sml = ea;
          s_big = sb; s_sml = sa;
          m_big = {1'b1, fb};
          m_sml = {1'b1, fa};
        end else begin
          if ({1'b1, fa} >= {1'b1, fb}) begin
            e_big = ea; e_sml = eb;
            s_big = sa; s_sml = sb;
            m_big = {1'b1, fa};
            m_sml = {1'b1, fb};
          end else begin
            e_big = eb; e_sml = ea;
            s_big = sb; s_sml = sa;
            m_big = {1'b1, fb};
            m_sml = {1'b1, fa};
          end
        end

        diff = e_big - e_sml;

        big_ext = {m_big, 3'b000};
        sml_ext = {m_sml, 3'b000};
        sticky = 1'b0;

        if (diff != 8'd0) begin
          if (diff >= 8'd27) begin
            sticky = |sml_ext;
            sml_ext = 27'd0;
          end else begin
            for (j = 0; j < 27; j = j + 1) begin
              if (j < diff) sticky = sticky | sml_ext[j];
            end
            sml_ext = sml_ext >> diff;
            if (sticky) sml_ext[0] = 1'b1;
          end
        end

        if (s_big == s_sml) begin
          sum_ext = {1'b0, big_ext} + {1'b0, sml_ext};
          so = s_big;
        end else begin
          sum_ext = {1'b0, big_ext} - {1'b0, sml_ext};
          so = s_big;
        end

        e_norm = e_big;
        m_norm = sum_ext[26:0];

        if (sum_ext[27]) begin
          m_norm = sum_ext[27:1];
          m_norm[0] = sum_ext[0] | sum_ext[1];
          e_norm = e_norm + 8'd1;
        end else begin
          found = 1'b0;
          shift_cnt = 0;
          for (j = 26; j >= 0; j = j - 1) begin
            if (!found && m_norm[j]) begin
              shift_cnt = 26 - j;
              found = 1'b1;
            end
          end
          if (!found) begin
            m_norm = 27'd0;
            e_norm = 8'd0;
          end else if (shift_cnt > 0) begin
            if (e_norm > shift_cnt[7:0]) begin
              m_norm = m_norm << shift_cnt;
              e_norm = e_norm - shift_cnt[7:0];
            end else begin
              m_norm = 27'd0;
              e_norm = 8'd0;
            end
          end
        end

        guard  = m_norm[2];
        roundb = m_norm[1];
        sticky = m_norm[0];
        mant24 = m_norm[26:3];

        inc = guard && (roundb || sticky || mant24[0]);
        mant24 = mant24 + (inc ? 24'd1 : 24'd0);

        if (mant24[23] == 1'b0) begin
          fp32_add_simple = {so, 8'd0, 23'd0};
        end else if (e_norm >= 8'hFF) begin
          fp32_add_simple = {so, 8'hFF, 23'd0};
        end else begin
          fp32_add_simple = {so, e_norm, mant24[22:0]};
        end
      end
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
        2'd0: t[15:0]    = w;
        2'd1: t[31:16]   = w;
        2'd2: t[47:32]   = w;
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

  assign jump_valid = in_valid & (is_jump | (is_blt & any_active));
  assign jump_addr  = in_imm[8:0];
  assign halt_pulse = in_valid & is_halt;
  assign flush_pipe = jump_valid | halt_pulse;

  wire bf_op  = in_valid & in_dtype & (is_mul | is_tensor_mul | is_tensor_mac);
  wire bf_req = bf_op & ~bf_busy & ~bf_commit;

  wire do_mul16 = (~in_dtype) & (is_mul | is_tensor_mul | is_tensor_mac);
  wire do_mac16 = (~in_dtype) & is_tensor_mac;

  reg bf_busy;
  reg bf_commit;
  reg [4:0] bf_idx;

  reg [15:0] bf_ctrl;
  reg [2:0]  bf_rd;
  reg [3:0]  bf_lane_mask;

  reg [63:0] bf_op1_0, bf_op1_1, bf_op1_2, bf_op1_3;
  reg [63:0] bf_op2_0, bf_op2_1, bf_op2_2, bf_op2_3;
  reg [63:0] bf_acc_0, bf_acc_1, bf_acc_2, bf_acc_3;

  reg [63:0] bf_res_0, bf_res_1, bf_res_2, bf_res_3;

  wire done_now = bf_busy && (bf_idx == 5'd15);
  assign consume_pulse = done_now;

  wire [1:0] bf_lane = bf_idx[3:2];
  wire [1:0] bf_elem = bf_idx[1:0];

  reg [15:0] a16, b16, c16;
  reg [31:0] a32, b32, c32;
  reg [31:0] p32, s32;
  reg [15:0] y16;

  always @(posedge clk) begin
    if (rst) begin
      bf_busy      <= 1'b0;
      bf_commit    <= 1'b0;
      bf_idx       <= 5'd0;
      bf_ctrl      <= 16'd0;
      bf_rd        <= 3'd0;
      bf_lane_mask <= 4'd0;
      bf_op1_0     <= 64'd0;
      bf_op1_1     <= 64'd0;
      bf_op1_2     <= 64'd0;
      bf_op1_3     <= 64'd0;
      bf_op2_0     <= 64'd0;
      bf_op2_1     <= 64'd0;
      bf_op2_2     <= 64'd0;
      bf_op2_3     <= 64'd0;
      bf_acc_0     <= 64'd0;
      bf_acc_1     <= 64'd0;
      bf_acc_2     <= 64'd0;
      bf_acc_3     <= 64'd0;
      bf_res_0     <= 64'd0;
      bf_res_1     <= 64'd0;
      bf_res_2     <= 64'd0;
      bf_res_3     <= 64'd0;
    end else begin
      if (bf_commit) bf_commit <= 1'b0;

      if (!bf_busy) begin
        if (bf_req) begin
          bf_busy      <= 1'b1;
          bf_idx       <= 5'd0;
          bf_ctrl      <= in_ctrl;
          bf_rd        <= in_rd;
          bf_lane_mask <= in_lane_mask;
          bf_op1_0     <= in_op1_0; bf_op1_1 <= in_op1_1; bf_op1_2 <= in_op1_2; bf_op1_3 <= in_op1_3;
          bf_op2_0     <= in_op2_0; bf_op2_1 <= in_op2_1; bf_op2_2 <= in_op2_2; bf_op2_3 <= in_op2_3;
          bf_acc_0     <= in_acc_0; bf_acc_1 <= in_acc_1; bf_acc_2 <= in_acc_2; bf_acc_3 <= in_acc_3;
          bf_res_0     <= 64'd0;
          bf_res_1     <= 64'd0;
          bf_res_2     <= 64'd0;
          bf_res_3     <= 64'd0;
        end
      end else begin
        case (bf_lane)
          2'd0: begin
            a16 = get16(bf_op1_0, bf_elem);
            b16 = get16(bf_op2_0, bf_elem);
            c16 = get16(bf_acc_0, bf_elem);
          end
          2'd1: begin
            a16 = get16(bf_op1_1, bf_elem);
            b16 = get16(bf_op2_1, bf_elem);
            c16 = get16(bf_acc_1, bf_elem);
          end
          2'd2: begin
            a16 = get16(bf_op1_2, bf_elem);
            b16 = get16(bf_op2_2, bf_elem);
            c16 = get16(bf_acc_2, bf_elem);
          end
          default: begin
            a16 = get16(bf_op1_3, bf_elem);
            b16 = get16(bf_op2_3, bf_elem);
            c16 = get16(bf_acc_3, bf_elem);
          end
        endcase

        a32 = bf16_to_fp32(a16);
        b32 = bf16_to_fp32(b16);
        c32 = bf16_to_fp32(c16);

        p32 = fp32_mul_simple(a32, b32);

        if (bf_ctrl[9]) begin
          s32 = fp32_add_simple(c32, p32);
          y16 = fp32_to_bf16_rne(s32);
        end else begin
          y16 = fp32_to_bf16_rne(p32);
        end

        case (bf_lane)
          2'd0: bf_res_0 <= set16(bf_res_0, bf_elem, y16);
          2'd1: bf_res_1 <= set16(bf_res_1, bf_elem, y16);
          2'd2: bf_res_2 <= set16(bf_res_2, bf_elem, y16);
          default: bf_res_3 <= set16(bf_res_3, bf_elem, y16);
        endcase

        if (bf_idx == 5'd15) begin
          bf_busy   <= 1'b0;
          bf_commit <= 1'b1;
          bf_idx    <= 5'd0;
        end else begin
          bf_idx <= bf_idx + 5'd1;
        end
      end
    end
  end

  assign stall = bf_busy | bf_commit;

  wire [31:0] imm_sext = {{16{in_imm[15]}}, in_imm};

  wire [DMEM_AW-1:0] base_w = in_base_sel[DMEM_AW-1:0];
  wire [DMEM_AW-1:0] tid_w  = in_tid_base[DMEM_AW-1:0];
  wire [DMEM_AW-1:0] imm_w  = imm_sext[DMEM_AW-1:0];

  assign out_addr0 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd0} + imm_w;
  assign out_addr1 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd1} + imm_w;
  assign out_addr2 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd2} + imm_w;
  assign out_addr3 = base_w + tid_w + {{(DMEM_AW-2){1'b0}},2'd3} + imm_w;

  assign out_store0 = in_op2_0;
  assign out_store1 = in_op2_1;
  assign out_store2 = in_op2_2;
  assign out_store3 = in_op2_3;

  wire [63:0] mul0 = mul16x4(in_op1_0, in_op2_0);
  wire [63:0] mul1 = mul16x4(in_op1_1, in_op2_1);
  wire [63:0] mul2 = mul16x4(in_op1_2, in_op2_2);
  wire [63:0] mul3 = mul16x4(in_op1_3, in_op2_3);

  wire [63:0] mac0 = add16x4(in_acc_0, mul0);
  wire [63:0] mac1 = add16x4(in_acc_1, mul1);
  wire [63:0] mac2 = add16x4(in_acc_2, mul2);
  wire [63:0] mac3 = add16x4(in_acc_3, mul3);

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

  wire [63:0] comb2 =
      is_loadi ? loadi4(in_imm) :
      is_mov   ? in_op1_2 :
      is_add   ? add16x4(in_op1_2, in_op2_2) :
      is_sub   ? sub16x4(in_op1_2, in_op2_2) :
      do_mac16 ? mac2 :
      do_mul16 ? mul2 :
      is_relu  ? relu16x4(in_op1_2) :
      64'd0;

  wire [63:0] comb3 =
      is_loadi ? loadi4(in_imm) :
      is_mov   ? in_op1_3 :
      is_add   ? add16x4(in_op1_3, in_op2_3) :
      is_sub   ? sub16x4(in_op1_3, in_op2_3) :
      do_mac16 ? mac3 :
      do_mul16 ? mul3 :
      is_relu  ? relu16x4(in_op1_3) :
      64'd0;

  assign out_valid = bf_commit ? 1'b1 :
                     ((bf_busy | bf_op) ? 1'b0 : (in_valid & pipe_op_now));

  assign out_ctrl      = bf_commit ? bf_ctrl      : in_ctrl;
  assign out_rd        = bf_commit ? bf_rd        : in_rd;
  assign out_lane_mask = bf_commit ? bf_lane_mask : in_lane_mask;

  assign out_res0 = bf_commit ? bf_res_0 : comb0;
  assign out_res1 = bf_commit ? bf_res_1 : comb1;
  assign out_res2 = bf_commit ? bf_res_2 : comb2;
  assign out_res3 = bf_commit ? bf_res_3 : comb3;

endmodule


module ex_mm_reg #(
  parameter DMEM_AW = 10
)(
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [3:0]  in_lane_mask,

  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,
  input  wire [DMEM_AW-1:0] in_addr2,
  input  wire [DMEM_AW-1:0] in_addr3,

  input  wire [63:0] in_store0,
  input  wire [63:0] in_store1,
  input  wire [63:0] in_store2,
  input  wire [63:0] in_store3,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,
  input  wire [63:0] in_res2,
  input  wire [63:0] in_res3,

  output reg         out_valid,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg  [3:0]  out_lane_mask,

  output reg  [DMEM_AW-1:0] out_addr0,
  output reg  [DMEM_AW-1:0] out_addr1,
  output reg  [DMEM_AW-1:0] out_addr2,
  output reg  [DMEM_AW-1:0] out_addr3,

  output reg  [63:0] out_store0,
  output reg  [63:0] out_store1,
  output reg  [63:0] out_store2,
  output reg  [63:0] out_store3,

  output reg  [63:0] out_res0,
  output reg  [63:0] out_res1,
  output reg  [63:0] out_res2,
  output reg  [63:0] out_res3
);

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_lane_mask <= 4'd0;
      out_addr0     <= {DMEM_AW{1'b0}};
      out_addr1     <= {DMEM_AW{1'b0}};
      out_addr2     <= {DMEM_AW{1'b0}};
      out_addr3     <= {DMEM_AW{1'b0}};
      out_store0    <= 64'd0;
      out_store1    <= 64'd0;
      out_store2    <= 64'd0;
      out_store3    <= 64'd0;
      out_res0      <= 64'd0;
      out_res1      <= 64'd0;
      out_res2      <= 64'd0;
      out_res3      <= 64'd0;
    end else begin
      out_valid     <= in_valid;
      out_ctrl      <= in_ctrl;
      out_rd        <= in_rd;
      out_lane_mask <= in_lane_mask;
      out_addr0     <= in_addr0;
      out_addr1     <= in_addr1;
      out_addr2     <= in_addr2;
      out_addr3     <= in_addr3;
      out_store0    <= in_store0;
      out_store1    <= in_store1;
      out_store2    <= in_store2;
      out_store3    <= in_store3;
      out_res0      <= in_res0;
      out_res1      <= in_res1;
      out_res2      <= in_res2;
      out_res3      <= in_res3;
    end
  end

endmodule


module dmem #(
  parameter AW = 10,
  parameter DEPTH = 1024
)(
  input  wire          clk,
  input  wire          re,
  input  wire          we,
  input  wire [AW-1:0] addr,
  input  wire [63:0]   wdata,
  output reg  [63:0]   rdata
);

  reg [63:0] mem [0:DEPTH-1];
  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = 64'd0;
    rdata = 64'd0;
  end

  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    if (re) rdata <= mem[addr];
  end

endmodule


module mm_stage #(
  parameter DMEM_AW = 10,
  parameter DMEM_DEPTH = 1024
)(
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [3:0]  in_lane_mask,

  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,
  input  wire [DMEM_AW-1:0] in_addr2,
  input  wire [DMEM_AW-1:0] in_addr3,

  input  wire [63:0] in_store0,
  input  wire [63:0] in_store1,
  input  wire [63:0] in_store2,
  input  wire [63:0] in_store3,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,
  input  wire [63:0] in_res2,
  input  wire [63:0] in_res3,

  output wire        out_valid,
  output wire [15:0] out_ctrl,
  output wire [2:0]  out_rd,
  output wire [3:0]  out_lane_mask,

  output wire [63:0] dmem_rdata0,
  output wire [63:0] dmem_rdata1,
  output wire [63:0] dmem_rdata2,
  output wire [63:0] dmem_rdata3,

  output wire [63:0] out_res0,
  output wire [63:0] out_res1,
  output wire [63:0] out_res2,
  output wire [63:0] out_res3
);

  wire is_load  = in_ctrl[0];
  wire is_store = in_ctrl[1];

  wire re0 = in_valid & is_load  & in_lane_mask[0];
  wire re1 = in_valid & is_load  & in_lane_mask[1];
  wire re2 = in_valid & is_load  & in_lane_mask[2];
  wire re3 = in_valid & is_load  & in_lane_mask[3];

  wire we0 = in_valid & is_store & in_lane_mask[0];
  wire we1 = in_valid & is_store & in_lane_mask[1];
  wire we2 = in_valid & is_store & in_lane_mask[2];
  wire we3 = in_valid & is_store & in_lane_mask[3];

  dmem #(.AW(DMEM_AW), .DEPTH(DMEM_DEPTH)) u_dmem0 (
    .clk(clk), .re(re0), .we(we0), .addr(in_addr0), .wdata(in_store0), .rdata(dmem_rdata0)
  );

  dmem #(.AW(DMEM_AW), .DEPTH(DMEM_DEPTH)) u_dmem1 (
    .clk(clk), .re(re1), .we(we1), .addr(in_addr1), .wdata(in_store1), .rdata(dmem_rdata1)
  );

  dmem #(.AW(DMEM_AW), .DEPTH(DMEM_DEPTH)) u_dmem2 (
    .clk(clk), .re(re2), .we(we2), .addr(in_addr2), .wdata(in_store2), .rdata(dmem_rdata2)
  );

  dmem #(.AW(DMEM_AW), .DEPTH(DMEM_DEPTH)) u_dmem3 (
    .clk(clk), .re(re3), .we(we3), .addr(in_addr3), .wdata(in_store3), .rdata(dmem_rdata3)
  );

  assign out_valid     = in_valid;
  assign out_ctrl      = in_ctrl;
  assign out_rd        = in_rd;
  assign out_lane_mask = in_lane_mask;

  assign out_res0 = in_res0;
  assign out_res1 = in_res1;
  assign out_res2 = in_res2;
  assign out_res3 = in_res3;

endmodule


module mm_wb_reg (
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [3:0]  in_lane_mask,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,
  input  wire [63:0] in_res2,
  input  wire [63:0] in_res3,

  input  wire [63:0] in_load0,
  input  wire [63:0] in_load1,
  input  wire [63:0] in_load2,
  input  wire [63:0] in_load3,

  output reg         out_valid,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg  [3:0]  out_lane_mask,

  output reg  [63:0] out_res0,
  output reg  [63:0] out_res1,
  output reg  [63:0] out_res2,
  output reg  [63:0] out_res3,

  output wire [63:0] out_load0,
  output wire [63:0] out_load1,
  output wire [63:0] out_load2,
  output wire [63:0] out_load3
);

  assign out_load0 = in_load0;
  assign out_load1 = in_load1;
  assign out_load2 = in_load2;
  assign out_load3 = in_load3;

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_lane_mask <= 4'd0;
      out_res0      <= 64'd0;
      out_res1      <= 64'd0;
      out_res2      <= 64'd0;
      out_res3      <= 64'd0;
    end else begin
      out_valid     <= in_valid;
      out_ctrl      <= in_ctrl;
      out_rd        <= in_rd;
      out_lane_mask <= in_lane_mask;
      out_res0      <= in_res0;
      out_res1      <= in_res1;
      out_res2      <= in_res2;
      out_res3      <= in_res3;
    end
  end

endmodule


module wb_stage (
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [3:0]  in_lane_mask,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,
  input  wire [63:0] in_res2,
  input  wire [63:0] in_res3,

  input  wire [63:0] in_load0,
  input  wire [63:0] in_load1,
  input  wire [63:0] in_load2,
  input  wire [63:0] in_load3,

  output wire        wb_we0,
  output wire        wb_we1,
  output wire        wb_we2,
  output wire        wb_we3,
  output wire [2:0]  wb_rd,
  output wire [63:0] wb_wdata0,
  output wire [63:0] wb_wdata1,
  output wire [63:0] wb_wdata2,
  output wire [63:0] wb_wdata3
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
  assign wb_wdata2 = is_load ? in_load2 : in_res2;
  assign wb_wdata3 = is_load ? in_load3 : in_res3;

  assign wb_we0 = wb_fire & in_lane_mask[0];
  assign wb_we1 = wb_fire & in_lane_mask[1];
  assign wb_we2 = wb_fire & in_lane_mask[2];
  assign wb_we3 = wb_fire & in_lane_mask[3];

endmodule