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
  localparam STATUS_PAD_WIDTH = 24 - FIFO_ADDR_WIDTH;

  wire [31:0] sw_ctrl;
  wire [31:0] sw_icache_addr;
  wire [31:0] sw_icache_wdata;
  wire [31:0] sw_bram_addr;

  wire [31:0] hw_status;
  reg  [31:0] hw_pc;
  reg  [31:0] hw_bram_lo;
  reg  [31:0] hw_bram_hi;
  reg  [31:0] hw_bram_ctrl;

  wire        reg_req_mid;
  wire        reg_ack_mid;
  wire        reg_rd_wr_L_mid;
  wire [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_mid;
  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_mid;
  wire [UDP_REG_SRC_WIDTH-1:0]    reg_src_mid;

  wire [7:0]  cpu_proc_mem_addr;
  wire        cpu_proc_mem_en;
  wire        cpu_proc_mem_we;
  wire [63:0] cpu_proc_mem_wdata;
  wire [63:0] cpu_proc_mem_rdata;
  wire        cpu_proc_mem_rvalid;
  wire        cpu_proc_active;
  wire        cpu_proc_done;
  wire [10:0] cpu_dbg_pc;

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

  reg         icache_wr_req_d;
  reg         cpu_done_sticky;

  assign bypass_enable = sw_ctrl[0];
  assign icache_wr_req = sw_ctrl[1];
  assign dbg_bram_en   = sw_ctrl[2];
  assign soft_reset    = sw_ctrl[3];
  assign process_en    = ~bypass_enable;
  assign module_reset  = reset | soft_reset;
  assign icache_prog_pulse = icache_wr_req & ~icache_wr_req_d;

  assign hw_status = {{STATUS_PAD_WIDTH{1'b0}}, fifo_dbg_pkt_len, fifo_dbg_state, fifo_dbg_mem_rvalid, cpu_done_sticky, cpu_proc_active, pkt_ready, fifo_full};

  generic_regs #(
    .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
    .TAG               (`USER_TOP_BLOCK_ADDR),
    .REG_ADDR_WIDTH    (`USER_TOP_REG_ADDR_WIDTH),
    .NUM_COUNTERS      (0),
    .NUM_SOFTWARE_REGS (4),
    .NUM_HARDWARE_REGS (5)
  ) module_regs (
    .reg_req_in       (reg_req_in),
    .reg_ack_in       (reg_ack_in),
    .reg_rd_wr_L_in   (reg_rd_wr_L_in),
    .reg_addr_in      (reg_addr_in),
    .reg_data_in      (reg_data_in),
    .reg_src_in       (reg_src_in),
    .reg_req_out      (reg_req_mid),
    .reg_ack_out      (reg_ack_mid),
    .reg_rd_wr_L_out  (reg_rd_wr_L_mid),
    .reg_addr_out     (reg_addr_mid),
    .reg_data_out     (reg_data_mid),
    .reg_src_out      (reg_src_mid),
    .counter_updates  (),
    .counter_decrement(),
    .software_regs    ({sw_bram_addr, sw_icache_wdata, sw_icache_addr, sw_ctrl}),
    .hardware_regs    ({hw_bram_ctrl, hw_bram_hi, hw_bram_lo, hw_pc, hw_status}),
    .clk              (clk),
    .reset            (module_reset)
  );

  always @(posedge clk) begin
    if (module_reset) begin
      icache_wr_req_d <= 1'b0;
      cpu_done_sticky <= 1'b0;
      hw_pc <= 32'd0;
      hw_bram_lo <= 32'd0;
      hw_bram_hi <= 32'd0;
      hw_bram_ctrl <= 32'd0;
    end else begin
      icache_wr_req_d <= icache_wr_req;
      hw_pc <= {21'd0, cpu_dbg_pc};
      if (cpu_proc_done)
        cpu_done_sticky <= 1'b1;
      if (fifo_dbg_mem_rvalid) begin
        hw_bram_lo <= fifo_dbg_mem_rdata[31:0];
        hw_bram_hi <= fifo_dbg_mem_rdata[63:32];
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
    .reg_req_in(reg_req_mid),
    .reg_ack_in(reg_ack_mid),
    .reg_rd_wr_L_in(reg_rd_wr_L_mid),
    .reg_addr_in(reg_addr_mid),
    .reg_data_in(reg_data_mid),
    .reg_src_in(reg_src_mid),
    .reg_req_out(reg_req_out),
    .reg_ack_out(reg_ack_out),
    .reg_rd_wr_L_out(reg_rd_wr_L_out),
    .reg_addr_out(reg_addr_out),
    .reg_data_out(reg_data_out),
    .reg_src_out(reg_src_out),
    .fifo_full(fifo_full),
    .pkt_ready(pkt_ready),
    .process_en(process_en),
    .proc_done(cpu_proc_done),
    .proc_mem_en(cpu_proc_mem_en),
    .proc_mem_we(cpu_proc_mem_we),
    .proc_mem_addr(cpu_proc_mem_addr),
    .proc_mem_wdata(cpu_proc_mem_wdata),
    .proc_mem_rdata(cpu_proc_mem_rdata),
    .proc_mem_rvalid(cpu_proc_mem_rvalid),
    .proc_active(cpu_proc_active),
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
