`timescale 1ns/1ps

module ft_small_fifo
  #(parameter WIDTH = 72,
    parameter MAX_DEPTH_BITS = 3,
    parameter PROG_FULL_THRESHOLD = 2**MAX_DEPTH_BITS - 1)
  (
   input [WIDTH-1:0] din,
   input             wr_en,
   input             rd_en,
   output [WIDTH-1:0] dout,
   output            full,
   output            nearly_full,
   output            prog_full,
   output reg        empty,
   input             reset,
   input             clk
   );

  reg  fifo_rd_en, empty_nxt;
  wire fifo_empty;

  smallfifo
    #(.WIDTH (WIDTH),
      .MAX_DEPTH_BITS (MAX_DEPTH_BITS),
      .NEARLY_FULL (PROG_FULL_THRESHOLD))
  fifo
    (.din           (din),
     .wr_en         (wr_en),
     .rd_en         (fifo_rd_en),
     .dout          (dout),
     .full          (full),
     .nearly_full   (nearly_full),
     .empty         (fifo_empty),
     .reset         (reset),
     .clk           (clk)
     );

  assign prog_full = nearly_full;

  always @(*) begin
    empty_nxt  = empty;
    fifo_rd_en = 0;
    case (empty)
      1'b1: begin
        if(!fifo_empty) begin
          fifo_rd_en = 1;
          empty_nxt  = 0;
        end
      end

      1'b0: begin
        if(rd_en) begin
          if(fifo_empty) begin
            empty_nxt = 1;
          end
          else begin
            fifo_rd_en = 1;
          end
        end
      end
    endcase
  end

  always @(posedge clk) begin
    if(reset) begin
      empty <= 1'b1;
    end
    else begin
      empty <= empty_nxt;
    end
  end

endmodule