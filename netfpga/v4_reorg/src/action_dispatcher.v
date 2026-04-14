`timescale 1ns/1ps

module action_dispatcher #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter ACTION_WIDTH = 2
) (
  input                     clk,
  input                     reset,

  input  [DATA_WIDTH-1:0]   in_data,
  input  [CTRL_WIDTH-1:0]   in_ctrl,
  input                     in_wr,
  output reg                in_rdy,
  input  [ACTION_WIDTH-1:0] in_action,

  output reg [DATA_WIDTH-1:0] out_data,
  output reg [CTRL_WIDTH-1:0] out_ctrl,
  output reg                  out_wr,
  input                       out_rdy,

  output reg [DATA_WIDTH-1:0] engine_in_data,
  output reg [CTRL_WIDTH-1:0] engine_in_ctrl,
  output reg                  engine_in_wr,
  input                       engine_in_rdy,

  input  [DATA_WIDTH-1:0]     engine_out_data,
  input  [CTRL_WIDTH-1:0]     engine_out_ctrl,
  input                       engine_out_wr,
  output reg                  engine_out_rdy
);

  localparam [ACTION_WIDTH-1:0] ACTION_OFFLOAD = 2'b10;

  localparam ST_IDLE       = 2'd0;
  localparam ST_BYPASS     = 2'd1;
  localparam ST_OFFLOAD_IN = 2'd2;
  localparam ST_OFFLOAD_OUT = 2'd3;

  reg [1:0] state;
  reg [9:0] in_word_idx;
  reg [9:0] out_word_idx;

  wire bypass_first_word;
  wire offload_first_word;
  wire accept_in;
  wire accept_engine_out;
  wire input_end_word;
  wire output_end_word;

  assign bypass_first_word = (state == ST_IDLE) && in_wr && (in_action != ACTION_OFFLOAD);
  assign offload_first_word = (state == ST_IDLE) && in_wr && (in_action == ACTION_OFFLOAD);
  assign accept_in = in_wr && in_rdy;
  assign accept_engine_out = engine_out_wr && engine_out_rdy;
  assign input_end_word = accept_in && (in_word_idx != 0) && (in_ctrl != 0);
  assign output_end_word = accept_engine_out && (out_word_idx != 0) && (engine_out_ctrl != 0);

  always @(*) begin
    in_rdy         = 1'b0;
    out_data       = {DATA_WIDTH{1'b0}};
    out_ctrl       = {CTRL_WIDTH{1'b0}};
    out_wr         = 1'b0;
    engine_in_data = {DATA_WIDTH{1'b0}};
    engine_in_ctrl = {CTRL_WIDTH{1'b0}};
    engine_in_wr   = 1'b0;
    engine_out_rdy = 1'b0;

    case (state)
      ST_IDLE: begin
        if (offload_first_word) begin
          in_rdy         = engine_in_rdy;
          engine_in_data = in_data;
          engine_in_ctrl = in_ctrl;
          engine_in_wr   = in_wr;
        end
        else begin
          in_rdy   = out_rdy;
          out_data = in_data;
          out_ctrl = in_ctrl;
          out_wr   = in_wr;
        end
      end

      ST_BYPASS: begin
        in_rdy   = out_rdy;
        out_data = in_data;
        out_ctrl = in_ctrl;
        out_wr   = in_wr;
      end

      ST_OFFLOAD_IN: begin
        in_rdy         = engine_in_rdy;
        engine_in_data = in_data;
        engine_in_ctrl = in_ctrl;
        engine_in_wr   = in_wr;
      end

      ST_OFFLOAD_OUT: begin
        out_data       = engine_out_data;
        out_ctrl       = engine_out_ctrl;
        out_wr         = engine_out_wr;
        engine_out_rdy = out_rdy;
      end

      default: begin
      end
    endcase
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state       <= ST_IDLE;
      in_word_idx <= 10'd0;
      out_word_idx <= 10'd0;
    end
    else begin
      case (state)
        ST_IDLE: begin
          if (accept_in) begin
            in_word_idx <= 10'd1;
            if (offload_first_word)
              state <= ST_OFFLOAD_IN;
            else
              state <= ST_BYPASS;
          end
        end

        ST_BYPASS: begin
          if (accept_in) begin
            if (input_end_word) begin
              state       <= ST_IDLE;
              in_word_idx <= 10'd0;
            end
            else begin
              in_word_idx <= in_word_idx + 10'd1;
            end
          end
        end

        ST_OFFLOAD_IN: begin
          if (accept_in) begin
            if (input_end_word) begin
              state        <= ST_OFFLOAD_OUT;
              in_word_idx  <= 10'd0;
              out_word_idx <= 10'd0;
            end
            else begin
              in_word_idx <= in_word_idx + 10'd1;
            end
          end
        end

        ST_OFFLOAD_OUT: begin
          if (accept_engine_out) begin
            if (output_end_word) begin
              state        <= ST_IDLE;
              out_word_idx <= 10'd0;
            end
            else begin
              out_word_idx <= out_word_idx + 10'd1;
            end
          end
        end

        default: begin
          state        <= ST_IDLE;
          in_word_idx  <= 10'd0;
          out_word_idx <= 10'd0;
        end
      endcase
    end
  end

endmodule
