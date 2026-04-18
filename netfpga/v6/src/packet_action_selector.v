`timescale 1ns/1ps

module packet_action_selector #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter ACTION_WIDTH = 2,
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

  localparam [ACTION_WIDTH-1:0] ACTION_BYPASS  = 2'b00;
  localparam [ACTION_WIDTH-1:0] ACTION_OFFLOAD = 2'b10;

  localparam [1:0] S_IDLE       = 2'd0;
  localparam [1:0] S_CAPTURE    = 2'd1;
  localparam [1:0] S_DRAIN_HDR  = 2'd2;
  localparam [1:0] S_STREAM     = 2'd3;

  reg [1:0] state;
  reg [DATA_WIDTH-1:0] header_data_0;
  reg [DATA_WIDTH-1:0] header_data_1;
  reg [DATA_WIDTH-1:0] header_data_2;
  reg [DATA_WIDTH-1:0] header_data_3;
  reg [CTRL_WIDTH-1:0] header_ctrl_0;
  reg [CTRL_WIDTH-1:0] header_ctrl_1;
  reg [CTRL_WIDTH-1:0] header_ctrl_2;
  reg [CTRL_WIDTH-1:0] header_ctrl_3;
  reg [2:0]            header_count;
  reg [2:0]            drain_count;
  reg [2:0]            drain_idx;
  reg                  packet_ended_in_header;
  reg [ACTION_WIDTH-1:0] packet_action;

  wire header_accept;
  wire stream_accept;

  assign header_accept     = in_wr && in_rdy && (state == S_IDLE || state == S_CAPTURE);
  assign stream_accept     = in_wr && in_rdy && (state == S_STREAM);

  assign in_rdy = ((state == S_IDLE) || (state == S_CAPTURE)) ? 1'b1   :
                  (state == S_STREAM)                         ? out_rdy :
                                                                1'b0;

  assign out_data = (state == S_DRAIN_HDR) ? ((drain_idx == 3'd0) ? header_data_0 :
                                              (drain_idx == 3'd1) ? header_data_1 :
                                              (drain_idx == 3'd2) ? header_data_2 :
                                                                    header_data_3) :
                                             in_data;
  assign out_ctrl = (state == S_DRAIN_HDR) ? ((drain_idx == 3'd0) ? header_ctrl_0 :
                                              (drain_idx == 3'd1) ? header_ctrl_1 :
                                              (drain_idx == 3'd2) ? header_ctrl_2 :
                                                                    header_ctrl_3) :
                                             in_ctrl;
  assign out_wr   = (state == S_DRAIN_HDR) ? 1'b1                   :
                    (state == S_STREAM)    ? in_wr                   :
                                             1'b0;
  assign out_action = packet_action;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state                <= S_IDLE;
      header_data_0        <= {DATA_WIDTH{1'b0}};
      header_data_1        <= {DATA_WIDTH{1'b0}};
      header_data_2        <= {DATA_WIDTH{1'b0}};
      header_data_3        <= {DATA_WIDTH{1'b0}};
      header_ctrl_0        <= {CTRL_WIDTH{1'b0}};
      header_ctrl_1        <= {CTRL_WIDTH{1'b0}};
      header_ctrl_2        <= {CTRL_WIDTH{1'b0}};
      header_ctrl_3        <= {CTRL_WIDTH{1'b0}};
      header_count         <= 3'd0;
      drain_count          <= 3'd0;
      drain_idx            <= 3'd0;
      packet_ended_in_header <= 1'b0;
      packet_action        <= ACTION_BYPASS;
    end
    else begin
      case (state)
        S_IDLE: begin
          if (header_accept) begin
            header_data_0          <= in_data;
            header_ctrl_0          <= in_ctrl;
            header_count           <= 3'd1;
            drain_idx              <= 3'd0;
            drain_count            <= 3'd1;
            packet_ended_in_header <= 1'b0;
            packet_action          <= ACTION_BYPASS;
            state                  <= S_CAPTURE;
          end
        end

        S_CAPTURE: begin
          if (header_accept) begin
            case (header_count)
              3'd1: begin
                header_data_1 <= in_data;
                header_ctrl_1 <= in_ctrl;
              end
              3'd2: begin
                header_data_2 <= in_data;
                header_ctrl_2 <= in_ctrl;
              end
              default: begin
                header_data_3 <= in_data;
                header_ctrl_3 <= in_ctrl;
              end
            endcase

            if (((in_ctrl != {CTRL_WIDTH{1'b0}}) && (header_count != 3'd0)) ||
                (header_count == 3'd3)) begin
              drain_count            <= header_count + 3'd1;
              packet_ended_in_header <= (in_ctrl != {CTRL_WIDTH{1'b0}});
              drain_idx              <= 3'd0;
              if ((header_count == 3'd3) &&
                  (header_data_2[15:0] == CUSTOM_ETHERTYPE) &&
                  (in_data[63:48] == ANN_TASK_MAGIC)) begin
                packet_action <= ACTION_OFFLOAD;
              end
              else begin
                packet_action <= ACTION_BYPASS;
              end
              state <= S_DRAIN_HDR;
            end
            else begin
              header_count <= header_count + 3'd1;
            end
          end
        end

        S_DRAIN_HDR: begin
          if (out_rdy) begin
            if ((drain_idx + 3'd1) >= drain_count) begin
              if (packet_ended_in_header) begin
                state                  <= S_IDLE;
                header_count           <= 3'd0;
                drain_count            <= 3'd0;
                drain_idx              <= 3'd0;
                packet_ended_in_header <= 1'b0;
                packet_action          <= ACTION_BYPASS;
              end
              else begin
                state <= S_STREAM;
              end
            end
            else begin
              drain_idx <= drain_idx + 3'd1;
            end
          end
        end

        S_STREAM: begin
          if (stream_accept && (in_ctrl != {CTRL_WIDTH{1'b0}})) begin
            state                  <= S_IDLE;
            header_count           <= 3'd0;
            drain_count            <= 3'd0;
            drain_idx              <= 3'd0;
            packet_ended_in_header <= 1'b0;
            packet_action          <= ACTION_BYPASS;
          end
        end

        default: begin
          state                  <= S_IDLE;
          header_count           <= 3'd0;
          drain_count            <= 3'd0;
          drain_idx              <= 3'd0;
          packet_ended_in_header <= 1'b0;
          packet_action          <= ACTION_BYPASS;
        end
      endcase
    end
  end

endmodule
