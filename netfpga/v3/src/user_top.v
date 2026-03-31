`timescale 1ns/1ps

module user_top #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter UDP_REG_SRC_WIDTH = 2,
  parameter FIFO_ADDR_WIDTH = 8
) (
  input  [DATA_WIDTH-1:0]           in_data,
  input  [CTRL_WIDTH-1:0]           in_ctrl,
  input                             in_wr,
  output                            in_rdy,
  output [DATA_WIDTH-1:0]           out_data,
  output [CTRL_WIDTH-1:0]           out_ctrl,
  output                            out_wr,
  input                             out_rdy,

  input                             reg_req_in,
  input                             reg_ack_in,
  input                             reg_rd_wr_L_in,
  input  [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_in,
  input  [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
  input  [UDP_REG_SRC_WIDTH-1:0]    reg_src_in,
  output                            reg_req_out,
  output                            reg_ack_out,
  output                            reg_rd_wr_L_out,
  output [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_out,
  output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
  output [UDP_REG_SRC_WIDTH-1:0]    reg_src_out,

  input  wire                       clk,
  input  wire                       reset
);

  localparam STATUS_PAD_WIDTH = 23 - FIFO_ADDR_WIDTH;

  wire [31:0] sw_ctrl;
  wire [31:0] sw_icache_addr;
  wire [31:0] sw_icache_wdata;
  wire [31:0] sw_bram_addr;
  wire [31:0] sw_gpu_mmio_addr;
  wire [31:0] sw_gpu_mmio_wdata;
  wire [31:0] sw_gpu_imem_addr;
  wire [31:0] sw_gpu_imem_wdata;

  wire [31:0] hw_status;
  wire [31:0] hw_gpu_mmio_rdata;
  wire [31:0] hw_gpu_status;
  reg  [31:0] hw_pc;
  reg  [31:0] hw_bram_lo;
  reg  [31:0] hw_bram_hi;
  reg  [31:0] hw_bram_ctrl;

  wire [7:0]  cpu_proc_mem_addr;
  wire        cpu_proc_mem_en;
  wire        cpu_proc_mem_we;
  wire [63:0] cpu_proc_mem_wdata;
  wire [63:0] cpu_proc_mem_rdata;
  wire        cpu_proc_mem_rvalid;
  wire        cpu_proc_active;
  wire        cpu_proc_done;
  wire [10:0] cpu_dbg_pc;

  wire                       gpu_proc_active;
  wire                       gpu_proc_done;
  wire                       gpu_busy;
  wire [15:0]                gpu_dbg_pc;
  wire [31:0]                gpu_mmio_rdata;

  wire                       gpu_mem0_en;
  wire                       gpu_mem0_we;
  wire [FIFO_ADDR_WIDTH-1:0] gpu_mem0_addr;
  wire [63:0]                gpu_mem0_wdata;
  wire [63:0]                gpu_mem0_rdata;
  wire                       gpu_mem0_rvalid;

  wire                       gpu_mem1_en;
  wire                       gpu_mem1_we;
  wire [FIFO_ADDR_WIDTH-1:0] gpu_mem1_addr;
  wire [63:0]                gpu_mem1_wdata;
  wire [63:0]                gpu_mem1_rdata;
  wire                       gpu_mem1_rvalid;

  wire        fifo_full;
  wire        pkt_ready;
  wire [63:0] fifo_dbg_mem_rdata;
  wire [CTRL_WIDTH-1:0] fifo_dbg_mem_rctrl;
  wire        fifo_dbg_mem_rvalid;
  wire [1:0]  fifo_dbg_state;
  wire [FIFO_ADDR_WIDTH:0] fifo_dbg_pkt_len;

  wire        bypass_enable;
  wire        icache_wr_req;
  wire        dbg_bram_en;
  wire        soft_reset;
  wire        process_en;
  wire        icache_prog_pulse;
  wire        module_reset;

  wire        proc_owner_gpu_cfg;
  wire        gpu_mmio_wr_req;
  wire        gpu_mmio_rd_req;
  wire        gpu_imem_wr_req;
  wire        gpu_mmio_wr_pulse;
  wire        gpu_mmio_rd_pulse;
  wire        gpu_imem_prog_pulse;

  reg         icache_wr_req_d;
  reg         gpu_mmio_wr_req_d;
  reg         gpu_mmio_rd_req_d;
  reg         gpu_imem_wr_req_d;
  reg         cpu_done_sticky;
  reg         gpu_done_sticky;

  wire        fifo_proc_active;
  wire        proc_owner_gpu_live;

  assign bypass_enable      = sw_ctrl[0];
  assign icache_wr_req      = sw_ctrl[1];
  assign dbg_bram_en        = sw_ctrl[2];
  assign soft_reset         = sw_ctrl[3];
  assign proc_owner_gpu_cfg = sw_ctrl[4];
  assign gpu_mmio_wr_req    = sw_ctrl[5];
  assign gpu_mmio_rd_req    = sw_ctrl[6];
  assign gpu_imem_wr_req    = sw_ctrl[7];

  assign process_en   = ~bypass_enable;
  assign module_reset = reset | soft_reset;

  assign icache_prog_pulse   = icache_wr_req   & ~icache_wr_req_d;
  assign gpu_mmio_wr_pulse   = gpu_mmio_wr_req & ~gpu_mmio_wr_req_d;
  assign gpu_mmio_rd_pulse   = gpu_mmio_rd_req & ~gpu_mmio_rd_req_d;
  assign gpu_imem_prog_pulse = gpu_imem_wr_req & ~gpu_imem_wr_req_d;

  assign fifo_proc_active    = cpu_proc_active | gpu_proc_active;
  assign proc_owner_gpu_live = gpu_proc_active ? 1'b1 :
                               cpu_proc_active ? 1'b0 :
                               proc_owner_gpu_cfg;

  assign hw_status = {
    {STATUS_PAD_WIDTH{1'b0}},
    fifo_dbg_pkt_len,
    fifo_dbg_state,
    fifo_dbg_mem_rvalid,
    (cpu_done_sticky | gpu_done_sticky),
    fifo_proc_active,
    pkt_ready,
    proc_owner_gpu_live,
    fifo_full
  };

  assign hw_gpu_mmio_rdata = gpu_mmio_rdata;

  assign hw_gpu_status = {
    6'd0,
    gpu_dbg_pc,
    5'd0,
    gpu_done_sticky,
    gpu_proc_done,
    gpu_proc_active,
    proc_owner_gpu_live,
    gpu_busy
  };

  generic_regs #(
    .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
    .TAG               (`USER_TOP_BLOCK_ADDR),
    .REG_ADDR_WIDTH    (`USER_TOP_REG_ADDR_WIDTH),
    .NUM_COUNTERS      (0),
    .NUM_SOFTWARE_REGS (8),
    .NUM_HARDWARE_REGS (7)
  ) module_regs (
    .reg_req_in       (reg_req_in),
    .reg_ack_in       (reg_ack_in),
    .reg_rd_wr_L_in   (reg_rd_wr_L_in),
    .reg_addr_in      (reg_addr_in),
    .reg_data_in      (reg_data_in),
    .reg_src_in       (reg_src_in),
    .reg_req_out      (reg_req_out),
    .reg_ack_out      (reg_ack_out),
    .reg_rd_wr_L_out  (reg_rd_wr_L_out),
    .reg_addr_out     (reg_addr_out),
    .reg_data_out     (reg_data_out),
    .reg_src_out      (reg_src_out),
    .counter_updates  (),
    .counter_decrement(),
    .software_regs    ({
      sw_gpu_imem_wdata,
      sw_gpu_imem_addr,
      sw_gpu_mmio_wdata,
      sw_gpu_mmio_addr,
      sw_bram_addr,
      sw_icache_wdata,
      sw_icache_addr,
      sw_ctrl
    }),
    .hardware_regs    ({
      hw_gpu_status,
      hw_gpu_mmio_rdata,
      hw_bram_ctrl,
      hw_bram_hi,
      hw_bram_lo,
      hw_pc,
      hw_status
    }),
    .clk              (clk),
    .reset            (module_reset)
  );

  always @(posedge clk) begin
    if (module_reset) begin
      icache_wr_req_d   <= 1'b0;
      gpu_mmio_wr_req_d <= 1'b0;
      gpu_mmio_rd_req_d <= 1'b0;
      gpu_imem_wr_req_d <= 1'b0;
      cpu_done_sticky   <= 1'b0;
      gpu_done_sticky   <= 1'b0;
      hw_pc             <= 32'd0;
      hw_bram_lo        <= 32'd0;
      hw_bram_hi        <= 32'd0;
      hw_bram_ctrl      <= 32'd0;
    end else begin
      icache_wr_req_d   <= icache_wr_req;
      gpu_mmio_wr_req_d <= gpu_mmio_wr_req;
      gpu_mmio_rd_req_d <= gpu_mmio_rd_req;
      gpu_imem_wr_req_d <= gpu_imem_wr_req;

      hw_pc <= proc_owner_gpu_live ? {16'd0, gpu_dbg_pc} : {21'd0, cpu_dbg_pc};

      if (cpu_proc_done)
        cpu_done_sticky <= 1'b1;

      if (gpu_proc_done)
        gpu_done_sticky <= 1'b1;

      if (fifo_dbg_mem_rvalid) begin
        hw_bram_lo   <= fifo_dbg_mem_rdata[31:0];
        hw_bram_hi   <= fifo_dbg_mem_rdata[63:32];
        hw_bram_ctrl <= {{(32-CTRL_WIDTH){1'b0}}, fifo_dbg_mem_rctrl};
      end
    end
  end

  pipeline_datapath u_cpu (
    .clk(clk),
    .rst(module_reset),
    .icache_prog_we(icache_prog_pulse),
    .icache_prog_addr(sw_icache_addr[8:0]),
    .icache_prog_wdata(sw_icache_wdata),
    .dbg_pc(cpu_dbg_pc),
    .proc_mem_addr(cpu_proc_mem_addr),
    .proc_mem_en(cpu_proc_mem_en),
    .proc_mem_we(cpu_proc_mem_we),
    .proc_mem_wdata(cpu_proc_mem_wdata),
    .proc_mem_rdata(cpu_proc_mem_rdata),
    .proc_mem_rvalid(cpu_proc_mem_rvalid),
    .proc_active(cpu_proc_active),
    .proc_done(cpu_proc_done)
  );

  gpu_top_fifo_if #(
    .MMIO_ADDR_W(8),
    .IMEM_AW(9),
    .MEM_AW(FIFO_ADDR_WIDTH)
  ) u_gpu (
    .clk(clk),
    .rst(module_reset),
    .mmio_wr_en(gpu_mmio_wr_pulse),
    .mmio_rd_en(gpu_mmio_rd_pulse),
    .mmio_addr(sw_gpu_mmio_addr[7:0]),
    .mmio_wdata(sw_gpu_mmio_wdata),
    .mmio_rdata(gpu_mmio_rdata),
    .imem_prog_we(gpu_imem_prog_pulse),
    .imem_prog_addr(sw_gpu_imem_addr[8:0]),
    .imem_prog_wdata(sw_gpu_imem_wdata),
    .proc_active(gpu_proc_active),
    .proc_done(gpu_proc_done),
    .mem0_en(gpu_mem0_en),
    .mem0_we(gpu_mem0_we),
    .mem0_addr(gpu_mem0_addr),
    .mem0_wdata(gpu_mem0_wdata),
    .mem0_rdata(gpu_mem0_rdata),
    .mem0_rvalid(gpu_mem0_rvalid),
    .mem1_en(gpu_mem1_en),
    .mem1_we(gpu_mem1_we),
    .mem1_addr(gpu_mem1_addr),
    .mem1_wdata(gpu_mem1_wdata),
    .mem1_rdata(gpu_mem1_rdata),
    .mem1_rvalid(gpu_mem1_rvalid),
    .dbg_pc(gpu_dbg_pc),
    .busy(gpu_busy)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH),
    .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_fifo (
    .in_data(in_data),
    .in_ctrl(in_ctrl),
    .in_wr(in_wr),
    .in_rdy(in_rdy),
    .out_data(out_data),
    .out_ctrl(out_ctrl),
    .out_wr(out_wr),
    .out_rdy(out_rdy),
    .fifo_full(fifo_full),
    .pkt_ready(pkt_ready),
    .process_en(process_en),
    .proc_owner_gpu_cfg(proc_owner_gpu_cfg),
    .proc_done(cpu_proc_done),
    .proc_mem_en(cpu_proc_mem_en),
    .proc_mem_we(cpu_proc_mem_we),
    .proc_mem_addr(cpu_proc_mem_addr[FIFO_ADDR_WIDTH-1:0]),
    .proc_mem_wdata(cpu_proc_mem_wdata),
    .proc_mem_rdata(cpu_proc_mem_rdata),
    .proc_mem_rvalid(cpu_proc_mem_rvalid),
    .proc_active(cpu_proc_active),
    .gpu_proc_done(gpu_proc_done),
    .gpu_mem0_en(gpu_mem0_en),
    .gpu_mem0_we(gpu_mem0_we),
    .gpu_mem0_addr(gpu_mem0_addr),
    .gpu_mem0_wdata(gpu_mem0_wdata),
    .gpu_mem0_rdata(gpu_mem0_rdata),
    .gpu_mem0_rvalid(gpu_mem0_rvalid),
    .gpu_mem1_en(gpu_mem1_en),
    .gpu_mem1_we(gpu_mem1_we),
    .gpu_mem1_addr(gpu_mem1_addr),
    .gpu_mem1_wdata(gpu_mem1_wdata),
    .gpu_mem1_rdata(gpu_mem1_rdata),
    .gpu_mem1_rvalid(gpu_mem1_rvalid),
    .gpu_proc_active(gpu_proc_active),
    .dbg_mem_en(dbg_bram_en),
    .dbg_mem_addr(sw_bram_addr[FIFO_ADDR_WIDTH-1:0]),
    .dbg_mem_rdata(fifo_dbg_mem_rdata),
    .dbg_mem_rctrl(fifo_dbg_mem_rctrl),
    .dbg_mem_rvalid(fifo_dbg_mem_rvalid),
    .dbg_state(fifo_dbg_state),
    .dbg_pkt_len(fifo_dbg_pkt_len),
    .reset(module_reset),
    .clk(clk)
  );

endmodule