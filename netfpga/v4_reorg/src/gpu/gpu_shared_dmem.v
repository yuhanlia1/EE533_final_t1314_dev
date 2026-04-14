`timescale 1ns/1ps

module gpu_shared_dmem #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input  wire                  clk,

  input  wire                  a_en,
  input  wire                  a_we,
  input  wire [ADDR_WIDTH-1:0] a_addr,
  input  wire [DATA_WIDTH-1:0] a_wdata,
  output reg  [DATA_WIDTH-1:0] a_rdata,
  output reg                   a_rvalid,

  input  wire                  b_en,
  input  wire                  b_we,
  input  wire [ADDR_WIDTH-1:0] b_addr,
  input  wire [DATA_WIDTH-1:0] b_wdata,
  output reg  [DATA_WIDTH-1:0] b_rdata,
  output reg                   b_rvalid
);

  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  // synthesis attribute ram_style of mem is block

  always @(posedge clk) begin
    a_rvalid <= 1'b0;
    if (a_en) begin
      if (a_we) begin
        mem[a_addr] <= a_wdata;
      end
      else begin
        a_rdata  <= mem[a_addr];
        a_rvalid <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    b_rvalid <= 1'b0;
    if (b_en) begin
      if (b_we) begin
        mem[b_addr] <= b_wdata;
      end
      else begin
        b_rdata  <= mem[b_addr];
        b_rvalid <= 1'b1;
      end
    end
  end

endmodule
