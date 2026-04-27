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
  // synthesis attribute ram_style of mem is block

  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    rdata <= we ? wdata : mem[addr];
  end

endmodule
