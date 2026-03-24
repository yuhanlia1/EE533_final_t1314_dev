`timescale 1ns/1ps
`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH 23
`endif
`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH 32
`endif
`ifndef USER_TOP_BLOCK_ADDR
`define USER_TOP_BLOCK_ADDR 0
`endif
`ifndef USER_TOP_REG_ADDR_WIDTH
`define USER_TOP_REG_ADDR_WIDTH 4
`endif
module gpu_fifo_adapter #(
  parameter ADDR_W = 8
) (
  input  wire               clk,
  input  wire               rst,
  input  wire               proc_active,

  input  wire               req_valid,
  output wire               req_ready,
  input  wire               req_we,
  input  wire [1:0]         req_lane_mask,
  input  wire [ADDR_W-1:0]  req_addr0,
  input  wire [ADDR_W-1:0]  req_addr1,
  input  wire [63:0]        req_wdata0,
  input  wire [63:0]        req_wdata1,

  output reg                rsp_valid,
  output reg  [63:0]        rsp_rdata0,
  output reg  [63:0]        rsp_rdata1,
  output wire               busy,

  output reg                proc_mem_en,
  output reg                proc_mem_we,
  output reg  [ADDR_W-1:0]  proc_mem_addr,
  output reg  [63:0]        proc_mem_wdata,
  input  wire [63:0]        proc_mem_rdata,
  input  wire               proc_mem_rvalid
);

  localparam ST_IDLE  = 2'd0;
  localparam ST_ISSUE = 2'd1;
  localparam ST_WAIT  = 2'd2;
  localparam ST_RESP  = 2'd3;

  reg [1:0]        state;
  reg              req_we_r;
  reg [1:0]        req_lane_mask_r;
  reg              lane_idx_r;
  reg [ADDR_W-1:0] req_addr0_r;
  reg [ADDR_W-1:0] req_addr1_r;
  reg [63:0]       req_wdata0_r;
  reg [63:0]       req_wdata1_r;

  assign req_ready = proc_active & (state == ST_IDLE);
  assign busy = (state != ST_IDLE);

  function first_lane;
    input [1:0] mask;
    begin
      if (mask[0]) first_lane = 1'b0;
      else first_lane = 1'b1;
    end
  endfunction

  function next_lane;
    input       curr;
    input [1:0] mask;
    begin
      if ((curr == 1'b0) && mask[1]) next_lane = 1'b1;
      else next_lane = 1'b0;
    end
  endfunction

  function is_last_lane;
    input       curr;
    input [1:0] mask;
    begin
      if (curr == 1'b0) is_last_lane = ~mask[1];
      else is_last_lane = 1'b1;
    end
  endfunction

  always @(*) begin
    proc_mem_en = 1'b0;
    proc_mem_we = 1'b0;
    proc_mem_addr = {ADDR_W{1'b0}};
    proc_mem_wdata = 64'd0;

    if (state == ST_ISSUE && proc_active) begin
      proc_mem_en = 1'b1;
      proc_mem_we = req_we_r;
      case (lane_idx_r)
        1'b0: begin
          proc_mem_addr = req_addr0_r;
          proc_mem_wdata = req_wdata0_r;
        end
        default: begin
          proc_mem_addr = req_addr1_r;
          proc_mem_wdata = req_wdata1_r;
        end
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= ST_IDLE;
      req_we_r <= 1'b0;
      req_lane_mask_r <= 2'd0;
      lane_idx_r <= 1'b0;
      req_addr0_r <= {ADDR_W{1'b0}};
      req_addr1_r <= {ADDR_W{1'b0}};
      req_wdata0_r <= 64'd0;
      req_wdata1_r <= 64'd0;
      rsp_valid <= 1'b0;
      rsp_rdata0 <= 64'd0;
      rsp_rdata1 <= 64'd0;
    end else begin
      rsp_valid <= 1'b0;

      if (!proc_active) begin
        state <= ST_IDLE;
      end else begin
        case (state)
          ST_IDLE: begin
            if (req_valid) begin
              req_we_r <= req_we;
              req_lane_mask_r <= req_lane_mask;
              lane_idx_r <= first_lane(req_lane_mask);
              req_addr0_r <= req_addr0;
              req_addr1_r <= req_addr1;
              req_wdata0_r <= req_wdata0;
              req_wdata1_r <= req_wdata1;
              rsp_rdata0 <= 64'd0;
              rsp_rdata1 <= 64'd0;
              if (req_lane_mask == 2'd0)
                state <= ST_RESP;
              else
                state <= ST_ISSUE;
            end
          end

          ST_ISSUE: begin
            if (req_we_r) begin
              if (is_last_lane(lane_idx_r, req_lane_mask_r))
                state <= ST_RESP;
              else begin
                lane_idx_r <= next_lane(lane_idx_r, req_lane_mask_r);
                state <= ST_ISSUE;
              end
            end else begin
              state <= ST_WAIT;
            end
          end

          ST_WAIT: begin
            if (proc_mem_rvalid) begin
              case (lane_idx_r)
                1'b0: rsp_rdata0 <= proc_mem_rdata;
                default: rsp_rdata1 <= proc_mem_rdata;
              endcase
              if (is_last_lane(lane_idx_r, req_lane_mask_r))
                state <= ST_RESP;
              else begin
                lane_idx_r <= next_lane(lane_idx_r, req_lane_mask_r);
                state <= ST_ISSUE;
              end
            end
          end

          ST_RESP: begin
            rsp_valid <= 1'b1;
            state <= ST_IDLE;
          end

          default: begin
            state <= ST_IDLE;
          end
        endcase
      end
    end
  end

endmodule

module gpu_top_fifo_if #(
  parameter MMIO_ADDR_W = 8,
  parameter IMEM_AW     = 9,
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
  input  wire [IMEM_AW-1:0]     imem_prog_addr,
  input  wire [31:0]            imem_prog_wdata,

  input  wire                   proc_active,
  output wire                   proc_done,

  output wire                   mem_req_valid,
  input  wire                   mem_req_ready,
  output wire                   mem_req_we,
  output wire [1:0]             mem_lane_mask,
  output wire [MEM_AW-1:0]      mem_addr0,
  output wire [MEM_AW-1:0]      mem_addr1,
  output wire [63:0]            mem_wdata0,
  output wire [63:0]            mem_wdata1,

  input  wire                   mem_rsp_valid,
  input  wire [63:0]            mem_rdata0,
  input  wire [63:0]            mem_rdata1,

  output wire [15:0]            dbg_pc,
  output wire                   busy
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

  wire        done, error;
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
  wire [1:0]  id_lane_mask;

  wire [63:0] id_op1_0, id_op1_1;
  wire [63:0] id_op2_0, id_op2_1;
  wire [63:0] id_acc_0, id_acc_1;

  wire         ex_in_valid;
  wire [8:0]   ex_in_pc;
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

  wire        stall_ex_core;
  wire        stall_mm;
  wire        stall_pipe;
  wire        ex_consume_pulse;

  wire        hw_done_pulse;
  assign hw_done_pulse = ex_halt_pulse;
  assign proc_done = proc_active & hw_done_pulse;
  assign dbg_pc = {7'd0, pc_if};
  assign stall_pipe = stall_ex_core | stall_mm;

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

  gpu_if_stage u_if (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall_pipe),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .imem_we(imem_prog_we),
    .imem_waddr(imem_prog_addr),
    .imem_wdata(imem_prog_wdata),
    .pc_if(pc_if),
    .instr_if(instr_if)
  );

  gpu_if_id_reg u_ifid (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipe),
    .pc_in(pc_if),
    .instr_in(instr_if),
    .flush_in(flush_pipe),
    .pc_id(pc_id),
    .instr_id(instr_id),
    .flush_out(flush_id)
  );

  gpu_id_stage u_id (
    .clk(clk),
    .rst(rst),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall_pipe),
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

  gpu_id_ex_reg u_idex (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipe),
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

  gpu_ex_stage #(.DMEM_AW(MEM_AW)) u_ex (
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
    .stall(stall_ex_core),
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
    .stall_mm(stall_mm),
    .mem_req_valid(mem_req_valid),
    .mem_req_ready(mem_req_ready),
    .mem_req_we(mem_req_we),
    .mem_lane_mask(mem_lane_mask),
    .mem_addr0(mem_addr0),
    .mem_addr1(mem_addr1),
    .mem_wdata0(mem_wdata0),
    .mem_wdata1(mem_wdata1),
    .mem_rsp_valid(mem_rsp_valid),
    .mem_rdata0(mem_rdata0),
    .mem_rdata1(mem_rdata1),
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

module gpu_if_stage (
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

  gpu_pc u_pc (
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

  gpu_imem u_imem (
    .clk(clk),
    .we(imem_we),
    .addr(imem_addr_w),
    .wdata(imem_wdata),
    .rdata(imem_rdata_w)
  );

  assign instr_if = imem_rdata_w;

endmodule

module gpu_pc (
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

module gpu_if_id_reg (
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

module gpu_id_stage (
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
  input  wire [2:0]  wb_rd,
  input  wire [63:0] wb_wdata0,
  input  wire [63:0] wb_wdata1,

  output wire        id_valid,
  output wire [8:0]  id_pc,
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

  reg stall_prev;
  reg stall_release;

  reg [63:0] rf0 [0:7];
  reg [63:0] rf1 [0:7];

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
    if (wb_we0) rf0[wb_rd] <= wb_wdata0;
    if (wb_we1) rf1[wb_rd] <= wb_wdata1;
  end

endmodule

module gpu_id_ex_reg (
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
  input  wire [1:0]  in_lane_mask,

  input  wire [63:0] in_op1_0,
  input  wire [63:0] in_op1_1,
  input  wire [63:0] in_op2_0,
  input  wire [63:0] in_op2_1,

  input  wire [63:0] in_acc_0,
  input  wire [63:0] in_acc_1,

  output reg         out_valid,
  output reg  [8:0]  out_pc,
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
      out_pc        <= 9'd0;
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
      out_pc        <= 9'd0;
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
  output wire [8:0]  jump_addr,
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

  reg bf_busy;
  reg bf_commit;

  wire bf_op  = in_valid & in_dtype & (is_mul | is_tensor_mul | is_tensor_mac);
  wire bf_req = bf_op & ~bf_busy & ~bf_commit;

  wire do_mul16 = (~in_dtype) & (is_mul | is_tensor_mul | is_tensor_mac);
  wire do_mac16 = (~in_dtype) & is_tensor_mac;

  reg [2:0] bf_idx;

  reg [15:0] bf_ctrl;
  reg [2:0]  bf_rd;
  reg [1:0]  bf_lane_mask;

  reg [63:0] bf_op1_0, bf_op1_1;
  reg [63:0] bf_op2_0, bf_op2_1;
  reg [63:0] bf_acc_0, bf_acc_1;

  reg [63:0] bf_res_0, bf_res_1;

  wire done_now = bf_busy && (bf_idx == 3'd7);
  assign consume_pulse = done_now;

  wire bf_lane = bf_idx[2];
  wire [1:0] bf_elem = bf_idx[1:0];

  reg [15:0] a16, b16, c16;
  reg [31:0] a32, b32, c32;
  reg [31:0] p32, s32;
  reg [15:0] y16;

  always @(posedge clk) begin
    if (rst) begin
      bf_busy      <= 1'b0;
      bf_commit    <= 1'b0;
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
    end else begin
      if (bf_commit) bf_commit <= 1'b0;

      if (!bf_busy) begin
        if (bf_req) begin
          bf_busy      <= 1'b1;
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
      end else begin
        case (bf_lane)
          1'b0: begin
            a16 = get16(bf_op1_0, bf_elem);
            b16 = get16(bf_op2_0, bf_elem);
            c16 = get16(bf_acc_0, bf_elem);
          end
          default: begin
            a16 = get16(bf_op1_1, bf_elem);
            b16 = get16(bf_op2_1, bf_elem);
            c16 = get16(bf_acc_1, bf_elem);
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
          1'b0: bf_res_0 <= set16(bf_res_0, bf_elem, y16);
          default: bf_res_1 <= set16(bf_res_1, bf_elem, y16);
        endcase

        if (bf_idx == 3'd7) begin
          bf_busy   <= 1'b0;
          bf_commit <= 1'b1;
          bf_idx    <= 3'd0;
        end else begin
          bf_idx <= bf_idx + 3'd1;
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
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [1:0]  in_lane_mask,

  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,

  input  wire [63:0] in_store0,
  input  wire [63:0] in_store1,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,

  output reg         out_valid,
  output reg  [15:0] out_ctrl,
  output reg  [2:0]  out_rd,
  output reg  [1:0]  out_lane_mask,

  output reg  [DMEM_AW-1:0] out_addr0,
  output reg  [DMEM_AW-1:0] out_addr1,

  output reg  [63:0] out_store0,
  output reg  [63:0] out_store1,

  output reg  [63:0] out_res0,
  output reg  [63:0] out_res1
);

  always @(posedge clk) begin
    if (rst) begin
      out_valid     <= 1'b0;
      out_ctrl      <= 16'd0;
      out_rd        <= 3'd0;
      out_lane_mask <= 2'd0;
      out_addr0     <= {DMEM_AW{1'b0}};
      out_addr1     <= {DMEM_AW{1'b0}};
      out_store0    <= 64'd0;
      out_store1    <= 64'd0;
      out_res0      <= 64'd0;
      out_res1      <= 64'd0;
    end else begin
      out_valid     <= in_valid;
      out_ctrl      <= in_ctrl;
      out_rd        <= in_rd;
      out_lane_mask <= in_lane_mask;
      out_addr0     <= in_addr0;
      out_addr1     <= in_addr1;
      out_store0    <= in_store0;
      out_store1    <= in_store1;
      out_res0      <= in_res0;
      out_res1      <= in_res1;
    end
  end

endmodule

module gpu_mm_stage #(
  parameter DMEM_AW = 10
)(
  input  wire        clk,
  input  wire        rst,

  input  wire        in_valid,
  input  wire [15:0] in_ctrl,
  input  wire [2:0]  in_rd,
  input  wire [1:0]  in_lane_mask,

  input  wire [DMEM_AW-1:0] in_addr0,
  input  wire [DMEM_AW-1:0] in_addr1,

  input  wire [63:0] in_store0,
  input  wire [63:0] in_store1,

  input  wire [63:0] in_res0,
  input  wire [63:0] in_res1,

  output wire        stall_mm,

  output wire        mem_req_valid,
  input  wire        mem_req_ready,
  output wire        mem_req_we,
  output wire [1:0]  mem_lane_mask,
  output wire [DMEM_AW-1:0] mem_addr0,
  output wire [DMEM_AW-1:0] mem_addr1,
  output wire [63:0] mem_wdata0,
  output wire [63:0] mem_wdata1,

  input  wire        mem_rsp_valid,
  input  wire [63:0] mem_rdata0,
  input  wire [63:0] mem_rdata1,

  output wire        out_valid,
  output wire [15:0] out_ctrl,
  output wire [2:0]  out_rd,
  output wire [1:0]  out_lane_mask,

  output reg  [63:0] dmem_rdata0,
  output reg  [63:0] dmem_rdata1,

  output wire [63:0] out_res0,
  output wire [63:0] out_res1
);

  localparam ST_IDLE     = 2'd0;
  localparam ST_WAIT_REQ = 2'd1;
  localparam ST_WAIT_RSP = 2'd2;
  localparam ST_RESP     = 2'd3;

  reg [1:0]  state;

  reg [15:0] ctrl_r;
  reg [2:0]  rd_r;
  reg [1:0]  lane_mask_r;

  reg [DMEM_AW-1:0] addr0_r, addr1_r;
  reg [63:0] wdata0_r, wdata1_r;
  reg [63:0] res0_r, res1_r;
  reg        req_we_r;

  wire is_load  = in_ctrl[0];
  wire is_store = in_ctrl[1];
  wire mem_op_now = in_valid & (is_load | is_store);

  assign stall_mm =
      (state == ST_WAIT_REQ) |
      (state == ST_WAIT_RSP) |
      ((state == ST_IDLE) & mem_op_now);

  assign mem_req_valid =
      ((state == ST_IDLE) & mem_op_now) |
      (state == ST_WAIT_REQ);

  assign mem_req_we =
      (state == ST_IDLE) ? is_store : req_we_r;

  assign mem_lane_mask =
      (state == ST_IDLE) ? in_lane_mask : lane_mask_r;

  assign mem_addr0 =
      (state == ST_IDLE) ? in_addr0 : addr0_r;
  assign mem_addr1 =
      (state == ST_IDLE) ? in_addr1 : addr1_r;

  assign mem_wdata0 =
      (state == ST_IDLE) ? in_store0 : wdata0_r;
  assign mem_wdata1 =
      (state == ST_IDLE) ? in_store1 : wdata1_r;

  assign out_valid =
      (state == ST_RESP) ? 1'b1 :
      ((state == ST_IDLE) ? (in_valid & ~(is_load | is_store)) : 1'b0);

  assign out_ctrl =
      (state == ST_RESP) ? ctrl_r : in_ctrl;
  assign out_rd =
      (state == ST_RESP) ? rd_r : in_rd;
  assign out_lane_mask =
      (state == ST_RESP) ? lane_mask_r : in_lane_mask;

  assign out_res0 =
      (state == ST_RESP) ? res0_r : in_res0;
  assign out_res1 =
      (state == ST_RESP) ? res1_r : in_res1;

  always @(posedge clk) begin
    if (rst) begin
      state <= ST_IDLE;
      ctrl_r <= 16'd0;
      rd_r <= 3'd0;
      lane_mask_r <= 2'd0;
      addr0_r <= {DMEM_AW{1'b0}};
      addr1_r <= {DMEM_AW{1'b0}};
      wdata0_r <= 64'd0;
      wdata1_r <= 64'd0;
      res0_r <= 64'd0;
      res1_r <= 64'd0;
      req_we_r <= 1'b0;
      dmem_rdata0 <= 64'd0;
      dmem_rdata1 <= 64'd0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (mem_op_now) begin
            ctrl_r      <= in_ctrl;
            rd_r        <= in_rd;
            lane_mask_r <= in_lane_mask;
            addr0_r     <= in_addr0;
            addr1_r     <= in_addr1;
            wdata0_r    <= in_store0;
            wdata1_r    <= in_store1;
            res0_r      <= in_res0;
            res1_r      <= in_res1;
            req_we_r    <= is_store;
            dmem_rdata0 <= 64'd0;
            dmem_rdata1 <= 64'd0;

            if (mem_req_ready) begin
              if (is_store)
                state <= ST_RESP;
              else
                state <= ST_WAIT_RSP;
            end else begin
              state <= ST_WAIT_REQ;
            end
          end
        end

        ST_WAIT_REQ: begin
          if (mem_req_ready) begin
            if (req_we_r)
              state <= ST_RESP;
            else
              state <= ST_WAIT_RSP;
          end
        end

        ST_WAIT_RSP: begin
          if (mem_rsp_valid) begin
            dmem_rdata0 <= mem_rdata0;
            dmem_rdata1 <= mem_rdata1;
            state <= ST_RESP;
          end
        end

        ST_RESP: begin
          state <= ST_IDLE;
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
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
