`timescale 1ns/1ps

module ann_task_ingress #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter MAX_FRAME_BYTES = 2048,
  parameter FRAME_LEN_WIDTH = $clog2(MAX_FRAME_BYTES + 1)
) (
  input  [DATA_WIDTH-1:0]              in_data,
  input  [CTRL_WIDTH-1:0]              in_ctrl,
  input                                in_wr,
  output                               in_rdy,

  output                               frame_valid,
  input                                frame_taken,
  output reg [DATA_WIDTH-1:0]          module_header_word,
  output reg [FRAME_LEN_WIDTH-1:0]     frame_len,
  output reg [MAX_FRAME_BYTES*8-1:0]   frame_bytes_flat,
  output reg                           frame_overflow,

  input                                clk,
  input                                reset
);

  localparam [1:0] S_IDLE    = 2'd0;
  localparam [1:0] S_CAPTURE = 2'd1;
  localparam [1:0] S_HOLD    = 2'd2;

  reg [1:0] state;
  reg [15:0] packet_word_idx;

  wire accept_word;

  function [CTRL_WIDTH-1:0] ctrl_valid_bytes;
    input [CTRL_WIDTH-1:0] ctrl_word;
    begin
      case (ctrl_word)
        8'h80: ctrl_valid_bytes = 1;
        8'h40: ctrl_valid_bytes = 2;
        8'h20: ctrl_valid_bytes = 3;
        8'h10: ctrl_valid_bytes = 4;
        8'h08: ctrl_valid_bytes = 5;
        8'h04: ctrl_valid_bytes = 6;
        8'h02: ctrl_valid_bytes = 7;
        8'h01: ctrl_valid_bytes = 8;
        default: ctrl_valid_bytes = 8;
      endcase
    end
  endfunction

  function [7:0] lane_byte;
    input [DATA_WIDTH-1:0] word;
    input integer lane;
    begin
      case (lane)
        0: lane_byte = word[63:56];
        1: lane_byte = word[55:48];
        2: lane_byte = word[47:40];
        3: lane_byte = word[39:32];
        4: lane_byte = word[31:24];
        5: lane_byte = word[23:16];
        6: lane_byte = word[15:8];
        default: lane_byte = word[7:0];
      endcase
    end
  endfunction

  assign in_rdy = (state != S_HOLD);
  assign frame_valid = (state == S_HOLD);
  assign accept_word = in_wr && in_rdy;

  integer i;
  integer lane;
  integer valid_bytes;
  integer bytes_to_store;
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state              <= S_IDLE;
      packet_word_idx    <= 16'd0;
      module_header_word <= {DATA_WIDTH{1'b0}};
      frame_len          <= {FRAME_LEN_WIDTH{1'b0}};
      frame_bytes_flat   <= {(MAX_FRAME_BYTES*8){1'b0}};
      frame_overflow     <= 1'b0;
    end
    else begin
      case (state)
        S_IDLE,
        S_CAPTURE: begin
          if (accept_word) begin
            if (packet_word_idx == 16'd0) begin
              module_header_word <= in_data;
              frame_len          <= {FRAME_LEN_WIDTH{1'b0}};
              frame_overflow     <= 1'b0;
              packet_word_idx    <= 16'd1;
              state              <= S_CAPTURE;
            end
            else begin
              valid_bytes = (in_ctrl == {CTRL_WIDTH{1'b0}}) ? CTRL_WIDTH : ctrl_valid_bytes(in_ctrl);
              bytes_to_store = valid_bytes;

              if ((frame_len + valid_bytes) > MAX_FRAME_BYTES) begin
                bytes_to_store = MAX_FRAME_BYTES - frame_len;
                frame_overflow <= 1'b1;
              end

              for (lane = 0; lane < bytes_to_store; lane = lane + 1)
                frame_bytes_flat[((frame_len + lane) * 8) +: 8] <= lane_byte(in_data, lane);

              if ((frame_len + bytes_to_store) > MAX_FRAME_BYTES)
                frame_len <= MAX_FRAME_BYTES[FRAME_LEN_WIDTH-1:0];
              else
                frame_len <= frame_len + bytes_to_store[FRAME_LEN_WIDTH-1:0];

              if (in_ctrl != {CTRL_WIDTH{1'b0}}) begin
                packet_word_idx <= 16'd0;
                state           <= S_HOLD;
              end
              else begin
                packet_word_idx <= packet_word_idx + 16'd1;
              end
            end
          end
        end

        S_HOLD: begin
          if (frame_taken) begin
            state          <= S_IDLE;
            frame_len      <= {FRAME_LEN_WIDTH{1'b0}};
            frame_overflow <= 1'b0;
          end
        end

        default: begin
          state           <= S_IDLE;
          packet_word_idx <= 16'd0;
        end
      endcase
    end
  end

endmodule
