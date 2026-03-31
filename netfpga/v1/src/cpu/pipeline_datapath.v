module pipeline_datapath(
    input  wire        clk,
    input  wire        rst,
    input  wire        icache_prog_we,
    input  wire [8:0]  icache_prog_addr,
    input  wire [31:0] icache_prog_wdata,
    output wire [10:0] dbg_pc,
    output wire [7:0]  proc_mem_addr,
    output wire        proc_mem_en,
    output wire        proc_mem_we,
    output wire [63:0] proc_mem_wdata,
    input  wire [63:0] proc_mem_rdata,
    input  wire        proc_mem_rvalid,
    input  wire        proc_active,
    output wire        proc_done
);
wire mem_stall;
wire cpu_rst_local;
wire cpu_boot_wait;
wire en_reg;
reg  boot_wait_r;
wire [8:0] icache_addr_mux;
wire [31:0] icache_din_mux;
wire [10:0] pc_if;
wire [10:0] pc_new;
wire flush_in;
wire [31:0] instr_in;
wire [10:0] pc_id;
wire [31:0] instr_id;
wire flush_out;
wire [63:0] imm_id;
wire is_b_id;
wire is_jal_id;
wire is_jalr_id;
wire wreg_id;
wire [63:0] rd1_id;
wire [63:0] rd2_id;
wire [4:0]  rd_id;
wire [2:0]  funct3_id;
wire [6:0]  funct7_id;
wire ALUsrc_id;
wire WMM_id;
wire RMM_id;
wire MOA_id;
wire jal_jalr_id;
wire AUIPC_id;
wire [10:0] pc_ex;
wire [63:0] IMM_ex;
wire wreg_ex;
wire [63:0] rd2_ex;
wire [63:0] rd1_ex;
wire [4:0]  rd_ex;
wire [2:0]  func3_ex;
wire [6:0]  func7_ex;
wire ALUsrc_ex;
wire WMM_ex;
wire RMM_ex;
wire MOA_ex;
wire jal_jalr_ex;
wire AUIPC_ex;
wire wist_ex;
wire is_b_ex;
wire is_jal_ex;
wire is_jalr_ex;
wire [63:0] alu_ex;
wire [63:0] rd2_ex_o;
wire wreg_ex_o;
wire [4:0]  rd_ex_o;
wire WMM_ex_o;
wire RMM_ex_o;
wire MOA_ex_o;
wire jal_jalr_ex_o;
wire jump_valid_ex_final;
wire [10:0] jump_addr_ex_final;
wire [63:0] alu_mem_in;
wire [63:0] rd2_mem_in;
wire wreg_mem_in;
wire [4:0]  rd_mem_in;
wire WMM_mem_in;
wire RMM_mem_in;
wire MOA_mem_in;
wire jal_jalr_mem_in;
wire [63:0] alu_mm;
wire [63:0] mem_mm;
wire wreg_mm;
wire [4:0]  rd_mm;
wire MOA_mm;
wire [63:0] alu_mm_wb;
wire [63:0] mem_mm_wb;
wire wreg_mm_wb;
wire [4:0]  rd_mm_wb;
wire MOA_mm_wb;
wire [63:0] wb_data_out;
wire wb_wreg_out;
wire [4:0] wb_rd_out;

assign cpu_rst_local = rst | ~proc_active;
assign cpu_boot_wait = boot_wait_r;
assign en_reg = proc_active & ~mem_stall & ~cpu_boot_wait;
assign icache_addr_mux = icache_prog_we ? icache_prog_addr : pc_if[10:2];
assign icache_din_mux  = icache_prog_wdata;
assign flush_in = jump_valid_ex_final;
assign pc_new   = jump_addr_ex_final;
assign dbg_pc   = pc_if;

always @(posedge clk) begin
  if (cpu_rst_local)
    boot_wait_r <= 1'b1;
  else if (boot_wait_r)
    boot_wait_r <= 1'b0;
end

pc pc_inst(
  .clk(clk),
  .rst(cpu_rst_local),
  .enable(en_reg),
  .jump_valid(flush_in),
  .jump_addr(pc_new),
  .pc(pc_if),
  .pc_next()
);

Icache Imm(
  .clk(clk),
  .addr(icache_addr_mux),
  .din(icache_din_mux),
  .dout(instr_in),
  .we(icache_prog_we)
);

if_id_reg if_id_reg_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .enable(en_reg),
  .wist(flush_in),
  .pc_in(pc_if),
  .inst_in(instr_in),
  .pc_out(pc_id),
  .inst_out(instr_id),
  .wist_out(flush_out)
);

id_stage id_stage_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .pc_in(pc_id),
  .inst_in(instr_id),
  .wb_rd_addr(wb_rd_out),
  .wb_data(wb_data_out),
  .wb_wea(wb_wreg_out),
  .imm(imm_id),
  .is_b_out(is_b_id),
  .is_jal_out(is_jal_id),
  .is_jalr_out(is_jalr_id),
  .wreg(wreg_id),
  .rd1_out(rd1_id),
  .rd2_out(rd2_id),
  .rd_out(rd_id),
  .funct3_out(funct3_id),
  .funct7_out(funct7_id),
  .ALUsrc(ALUsrc_id),
  .WMM(WMM_id),
  .RMM(RMM_id),
  .MOA(MOA_id),
  .jal_jalr(jal_jalr_id),
  .AUIPC(AUIPC_id)
);

id_ex_reg id_ex_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .enable(en_reg),
  .pc_in(pc_id),
  .IMM(imm_id),
  .wreg(wreg_id),
  .rd2(rd2_id),
  .rd1(rd1_id),
  .rd(rd_id),
  .func3(funct3_id),
  .func7(funct7_id),
  .ALUsrc(ALUsrc_id),
  .WMM(WMM_id),
  .RMM(RMM_id),
  .MOA(MOA_id),
  .jal_jalr(jal_jalr_id),
  .AUIPC(AUIPC_id),
  .flush_in(flush_in),
  .flush_out(flush_out),
  .is_b_in(is_b_id),
  .is_jal_in(is_jal_id),
  .is_jalr_in(is_jalr_id),
  .pc_out(pc_ex),
  .IMM_out(IMM_ex),
  .wreg_out(wreg_ex),
  .rd2_out(rd2_ex),
  .rd1_out(rd1_ex),
  .rd_out(rd_ex),
  .func3_out(func3_ex),
  .func7_out(func7_ex),
  .ALUsrc_out(ALUsrc_ex),
  .WMM_out(WMM_ex),
  .RMM_out(RMM_ex),
  .MOA_out(MOA_ex),
  .jal_jalr_out(jal_jalr_ex),
  .AUIPC_out(AUIPC_ex),
  .wist_out(wist_ex),
  .is_b_out(is_b_ex),
  .is_jal_out(is_jal_ex),
  .is_jalr_out(is_jalr_ex)
);

ex_stage ex_stage_inst (
  .pc_in(pc_ex),
  .IMM_in(IMM_ex),
  .wreg_in(wreg_ex),
  .rd2_in(rd2_ex),
  .rd1_in(rd1_ex),
  .rd_in(rd_ex),
  .func3_in(func3_ex),
  .func7_in(func7_ex),
  .ALUsrc_in(ALUsrc_ex),
  .WMM_in(WMM_ex),
  .RMM_in(RMM_ex),
  .MOA_in(MOA_ex),
  .jal_jalr_in(jal_jalr_ex),
  .AUIPC_in(AUIPC_ex),
  .wist_in(wist_ex),
  .is_b_in(is_b_ex),
  .is_jal_in(is_jal_ex),
  .is_jalr_in(is_jalr_ex),
  .alu_out(alu_ex),
  .rd2_out(rd2_ex_o),
  .wreg_out(wreg_ex_o),
  .rd_out(rd_ex_o),
  .WMM_out(WMM_ex_o),
  .RMM_out(RMM_ex_o),
  .MOA_out(MOA_ex_o),
  .jal_jalr_out(jal_jalr_ex_o),
  .jump_valid_out(jump_valid_ex_final),
  .jump_addr_out(jump_addr_ex_final)
);

ex_mm_reg ex_mm_reg_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .enable(en_reg),
  .alu_in(alu_ex),
  .rd2_in(rd2_ex_o),
  .wreg_in(wreg_ex_o),
  .rd_in(rd_ex_o),
  .WMM_in(WMM_ex_o),
  .RMM_in(RMM_ex_o),
  .MOA_in(MOA_ex_o),
  .jal_jalr_in(jal_jalr_ex_o),
  .alu_out(alu_mem_in),
  .rd2_out(rd2_mem_in),
  .wreg_out(wreg_mem_in),
  .rd_out(rd_mem_in),
  .WMM_out(WMM_mem_in),
  .RMM_out(RMM_mem_in),
  .MOA_out(MOA_mem_in),
  .jal_jalr_out(jal_jalr_mem_in)
);

mm_stage mm_stage_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .alu_in(alu_mem_in),
  .rd2_in(rd2_mem_in),
  .wreg_in(wreg_mem_in),
  .rd_in(rd_mem_in),
  .WMM_in(WMM_mem_in),
  .RMM_in(RMM_mem_in),
  .MOA_in(MOA_mem_in),
  .jal_jalr_in(jal_jalr_mem_in),
  .proc_mem_addr(proc_mem_addr),
  .proc_mem_en(proc_mem_en),
  .proc_mem_we(proc_mem_we),
  .proc_mem_wdata(proc_mem_wdata),
  .proc_mem_rdata(proc_mem_rdata),
  .proc_mem_rvalid(proc_mem_rvalid),
  .proc_active(proc_active),
  .proc_done(proc_done),
  .mem_stall(mem_stall),
  .alu_out(alu_mm),
  .mem_out(mem_mm),
  .wreg_out(wreg_mm),
  .rd_out(rd_mm),
  .MOA_out(MOA_mm)
);

mm_wb_reg mm_wb_reg_inst (
  .clk(clk),
  .rst(cpu_rst_local),
  .enable(en_reg),
  .alu_in(alu_mm),
  .mem_in(mem_mm),
  .wreg_in(wreg_mm),
  .rd_in(rd_mm),
  .MOA_in(MOA_mm),
  .alu_out(alu_mm_wb),
  .mem_out(mem_mm_wb),
  .wreg_out(wreg_mm_wb),
  .rd_out(rd_mm_wb),
  .MOA_out(MOA_mm_wb)
);

wb_stage wb_stage_inst (
  .alu_in(alu_mm_wb),
  .mem_in(mem_mm_wb),
  .wreg_in(wreg_mm_wb),
  .rd_in(rd_mm_wb),
  .MOA_in(MOA_mm_wb),
  .wb_data_out(wb_data_out),
  .wreg_out(wb_wreg_out),
  .rd_out(wb_rd_out)
);
endmodule
