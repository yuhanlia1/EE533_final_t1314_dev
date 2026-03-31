module gpu_imem #(
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
 
 /*
  integer i;
  localparam [DW-1:0] NOP = 32'h00000013;

  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = NOP;
    rdata = NOP;
  end
  */

  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    rdata <= we ? wdata : mem[addr];
  end

endmodule