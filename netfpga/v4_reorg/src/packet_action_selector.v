`timescale 1ns/1ps

module packet_action_selector #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter ACTION_WIDTH = 2,
  parameter MAX_PKT_WORDS = 512,
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC   = 16'hA11E
) (
  input  [DATA_WIDTH-1:0]     in_data,
  input  [CTRL_WIDTH-1:0]     in_ctrl,
  input                       in_wr,
  output                      in_rdy,

  output [DATA_WIDTH-1:0]     out_data,
  output [CTRL_WIDTH-1:0]     out_ctrl,
  output                      out_wr,
  input                       out_rdy,
  output [ACTION_WIDTH-1:0]   out_action,

  input                       clk,
  input                       reset
);

  localparam [ACTION_WIDTH-1:0] ACTION_BYPASS = 2'b00;
  localparam [ACTION_WIDTH-1:0] ACTION_DROP   = 2'b01;
  localparam [ACTION_WIDTH-1:0] ACTION_OFFLOAD = 2'b10;

  localparam S_IDLE    = 2'd0;
  localparam S_CAPTURE = 2'd1;
  localparam S_DRAIN   = 2'd2;

  reg [1:0] state;
  reg [DATA_WIDTH-1:0] pkt_data [0:MAX_PKT_WORDS-1];
  reg [CTRL_WIDTH-1:0] pkt_ctrl [0:MAX_PKT_WORDS-1];
  reg [9:0]            write_idx;
  reg [9:0]            pkt_len;
  reg [9:0]            read_idx;
  reg [ACTION_WIDTH-1:0] packet_action;
  reg                    ethertype_match_seen;

  wire accept_word;
  wire packet_end_word;

  assign accept_word = in_wr && in_rdy;
  assign packet_end_word = accept_word && (write_idx != 0) && (in_ctrl != 0);

  assign in_rdy = (state != S_DRAIN) && (write_idx < MAX_PKT_WORDS);
  assign out_data = pkt_data[read_idx];
  assign out_ctrl = pkt_ctrl[read_idx];
  assign out_wr = (state == S_DRAIN);
  assign out_action = packet_action;

  integer i;
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state         <= S_IDLE;
      write_idx     <= 10'd0;
      pkt_len       <= 10'd0;
      read_idx      <= 10'd0;
      packet_action <= ACTION_BYPASS;
      ethertype_match_seen <= 1'b0;
      for (i = 0; i < MAX_PKT_WORDS; i = i + 1) begin
        pkt_data[i] <= {DATA_WIDTH{1'b0}};
        pkt_ctrl[i] <= {CTRL_WIDTH{1'b0}};
      end
    end
    else begin
      case (state)
        S_IDLE,
        S_CAPTURE: begin
          if (accept_word) begin
            pkt_data[write_idx] <= in_data;
            pkt_ctrl[write_idx] <= in_ctrl;

            if (state == S_IDLE) begin
              state         <= S_CAPTURE;
              packet_action <= ACTION_BYPASS;
              ethertype_match_seen <= 1'b0;
            end

            if (write_idx == 2) begin
              ethertype_match_seen <= (in_data[15:0] == CUSTOM_ETHERTYPE);
            end

            if (write_idx == 3) begin
              if (ethertype_match_seen && (in_data[63:48] == ANN_TASK_MAGIC))
                packet_action <= ACTION_OFFLOAD;
              else
                packet_action <= ACTION_BYPASS;
            end

            if (packet_end_word) begin
              pkt_len   <= write_idx + 10'd1;
              read_idx  <= 10'd0;
              write_idx <= 10'd0;
              state     <= S_DRAIN;
            end
            else begin
              write_idx <= write_idx + 10'd1;
            end
          end
        end

        S_DRAIN: begin
          if (out_rdy) begin
            if (read_idx + 10'd1 >= pkt_len) begin
              state         <= S_IDLE;
              pkt_len       <= 10'd0;
              read_idx      <= 10'd0;
              packet_action <= ACTION_BYPASS;
              ethertype_match_seen <= 1'b0;
            end
            else begin
              read_idx <= read_idx + 10'd1;
            end
          end
        end

        default: begin
          state         <= S_IDLE;
          write_idx     <= 10'd0;
          pkt_len       <= 10'd0;
          read_idx      <= 10'd0;
          packet_action <= ACTION_BYPASS;
          ethertype_match_seen <= 1'b0;
        end
      endcase
    end
  end

endmodule
