`timescale 1ns/1ps

module packet_action_selector #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8
) (
  input  [DATA_WIDTH-1:0] in_data,
  input  [CTRL_WIDTH-1:0] in_ctrl,
  input                   in_wr,
  output                  in_rdy,

  output [DATA_WIDTH-1:0] out_data,
  output [CTRL_WIDTH-1:0] out_ctrl,
  output                  out_wr,
  input                   out_rdy,

  input                   clk,
  input                   reset
);

  localparam ACTION_BYPASS = 2'b00;
  localparam ACTION_DROP   = 2'b01;
  localparam ACTION_OFFLOAD = 2'b10;

  reg       in_packet;
  reg [1:0] packet_action;

  wire accept_word;
  wire packet_start;
  wire packet_end;

  assign accept_word = in_wr && in_rdy;
  assign packet_start = accept_word && !in_packet && (in_ctrl != 0);
  assign packet_end   = accept_word && in_packet && (in_ctrl != 0);

  assign in_rdy  = out_rdy;
  assign out_data = in_data;
  assign out_ctrl = in_ctrl;
  assign out_wr   = in_wr;

  always @(posedge clk) begin
    if (reset) begin
      in_packet     <= 1'b0;
      packet_action <= ACTION_BYPASS;
    end
    else begin
      if (packet_start) begin
        // Future parser/classifier logic will choose drop/bypass/offload here.
        in_packet     <= 1'b1;
        packet_action <= ACTION_BYPASS;
      end
      else if (packet_end) begin
        in_packet     <= 1'b0;
        packet_action <= ACTION_BYPASS;
      end
      else begin
        packet_action <= packet_action;
      end
    end
  end

endmodule
