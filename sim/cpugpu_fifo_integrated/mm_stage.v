module mm_stage(
  input  wire        clk,
  input  wire        rst,
  input  wire [63:0] alu_in,
  input  wire [63:0] rd2_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,
  output wire [7:0]  proc_mem_addr,
  output wire        proc_mem_en,
  output wire        proc_mem_we,
  output wire [63:0] proc_mem_wdata,
  input  wire [63:0] proc_mem_rdata,
  input  wire        proc_mem_rvalid,
  input  wire        proc_active,
  output wire        proc_done,
  output wire        mem_stall,
  output wire [63:0] alu_out,
  output wire [63:0] mem_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        MOA_out
);
  localparam [63:0] DONE_BYTE_ADDR = 64'h0000_0000_0000_0800;
  reg read_pending;
  wire [7:0] addr_bus;
  wire mem_req;
  wire is_done_store;
  wire start_read;
  wire start_write;
  assign addr_bus      = alu_in[10:3];
  assign mem_req       = WMM_in | RMM_in;
  assign is_done_store = WMM_in && (alu_in == DONE_BYTE_ADDR);
  assign start_read  = RMM_in && proc_active && !read_pending;
  assign start_write = WMM_in && proc_active && !is_done_store;
  assign proc_mem_addr  = addr_bus;
  assign proc_mem_en    = start_read | start_write;
  assign proc_mem_we    = start_write;
  assign proc_mem_wdata = rd2_in;
  assign proc_done      = proc_active && is_done_store;
  assign mem_stall = (mem_req && !proc_active) || start_read || (read_pending && !proc_mem_rvalid);
  assign mem_out  = proc_mem_rdata;
  assign alu_out  = jal_jalr_in ? rd2_in : alu_in;
  assign wreg_out = wreg_in;
  assign rd_out   = rd_in;
  assign MOA_out  = MOA_in;
  always @(posedge clk) begin
    if (rst) read_pending <= 1'b0;
    else begin
      if (start_read) read_pending <= 1'b1;
      else if (proc_mem_rvalid) read_pending <= 1'b0;
    end
  end
endmodule