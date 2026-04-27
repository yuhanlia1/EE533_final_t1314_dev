(* blackbox *)
module fifo_bram #(
  parameter DATA_WIDTH = 72,
  parameter ADDR_WIDTH = 8
) (
  input                        clka,
  input                        wea,
  input  [ADDR_WIDTH-1:0]      addra,
  input  [DATA_WIDTH-1:0]      dina,
  output [DATA_WIDTH-1:0]      douta,
  input                        clkb,
  input                        web,
  input  [ADDR_WIDTH-1:0]      addrb,
  input  [DATA_WIDTH-1:0]      dinb,
  output [DATA_WIDTH-1:0]      doutb
);
endmodule

(* blackbox *)
module gpu_imem #(
  parameter AW = 9,
  parameter DW = 32,
  parameter DEPTH = 512
) (
  input               clk,
  input               we,
  input  [AW-1:0]     addr,
  input  [DW-1:0]     wdata,
  output [DW-1:0]     rdata
);
endmodule

(* blackbox *)
module gpu_shared_dmem #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input                       clk,
  input                       a_en,
  input                       a_we,
  input  [ADDR_WIDTH-1:0]     a_addr,
  input  [DATA_WIDTH-1:0]     a_wdata,
  output [DATA_WIDTH-1:0]     a_rdata,
  output                      a_rvalid,
  input                       b_en,
  input                       b_we,
  input  [ADDR_WIDTH-1:0]     b_addr,
  input  [DATA_WIDTH-1:0]     b_wdata,
  output [DATA_WIDTH-1:0]     b_rdata,
  output                      b_rvalid
);
endmodule

(* blackbox *)
module mem_RF #(
  parameter ADDR_WIDTH = 6,
  parameter DATA_WIDTH = 64
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     waddr,
  input  [DATA_WIDTH-1:0]     wdata,
  input  [ADDR_WIDTH-1:0]     r0addr,
  output [DATA_WIDTH-1:0]     r0data,
  input  [ADDR_WIDTH-1:0]     r1addr,
  output [DATA_WIDTH-1:0]     r1data
);
endmodule

(* blackbox *)
module mem_data #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     addr,
  input  [DATA_WIDTH-1:0]     wdata,
  output [DATA_WIDTH-1:0]     rdata
);
endmodule

(* blackbox *)
module mem_inst #(
  parameter ADDR_WIDTH = 9,
  parameter DATA_WIDTH = 32
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     addr,
  input  [DATA_WIDTH-1:0]     wdata,
  output [DATA_WIDTH-1:0]     rdata
);
endmodule
