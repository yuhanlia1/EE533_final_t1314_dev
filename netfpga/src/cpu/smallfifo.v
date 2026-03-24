///////////////////////////////////////////////////////////////////////////////
// $Id: small_fifo.v 5205 2009-03-08 18:54:46Z grg $
//
// Module: small_fifo.v
// Project: UNET
// Description: small fifo with no fallthrough i.e. data valid after rd is high
//
// Change history: 
//   7/20/07 -- Set nearly full to 2^MAX_DEPTH_BITS - 1 by default so that it 
//              goes high a clock cycle early.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module smallfifo #(parameter WIDTH = 72, parameter MAX_DEPTH_BITS = 3, parameter NEARLY_FULL = 2**MAX_DEPTH_BITS - 1)(
     input  [WIDTH-1:0] din,
     input              wr_en,
     input              rd_en,
     output reg [WIDTH-1:0] dout,
     output             full,
     output             nearly_full,
     output             empty,
     input              reset,
     input              clk
);
parameter MAX_DEPTH = 2 ** MAX_DEPTH_BITS;
reg [WIDTH-1:0] queue [MAX_DEPTH - 1 : 0];
reg [MAX_DEPTH_BITS - 1 : 0] rd_ptr;
reg [MAX_DEPTH_BITS - 1 : 0] wr_ptr;
reg [MAX_DEPTH_BITS : 0] depth;
always @(posedge clk) begin
   if (wr_en) queue[wr_ptr] <= din;
   if (rd_en) dout <= queue[rd_ptr];
end
always @(posedge clk) begin
   if (reset) begin
      rd_ptr <= 'h0;
      wr_ptr <= 'h0;
      depth  <= 'h0;
   end else begin
      if (wr_en) wr_ptr <= wr_ptr + 'h1;
      if (rd_en) rd_ptr <= rd_ptr + 'h1;
      if (wr_en & ~rd_en) depth <= depth + 'h1;
      else if (~wr_en & rd_en) depth <= depth - 'h1;
   end
end
assign full = depth == MAX_DEPTH;
assign nearly_full = depth >= NEARLY_FULL;
assign empty = depth == 'h0;
endmodule // small_fifo


/* vim:set shiftwidth=3 softtabstop=3 expandtab: */
