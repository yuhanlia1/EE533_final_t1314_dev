`timescale 1ns/1ps

module packet_action_selector #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter ACTION_WIDTH = 2,
  parameter [15:0] IPV4_ETHERTYPE = 16'h0800,
  parameter [7:0]  IP_PROTOCOL_UDP = 8'h11,
  parameter [15:0] ANN_UDP_DST_PORT = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC = 16'hA11E
) (
  input  [DATA_WIDTH-1:0] in_data,
  input  [CTRL_WIDTH-1:0] in_ctrl,
  input                   in_wr,
  output                  in_rdy,

  output [DATA_WIDTH-1:0] out_data,
  output [CTRL_WIDTH-1:0] out_ctrl,
  output                  out_wr,
  input                   out_rdy,

  output [ACTION_WIDTH-1:0] out_action,

  input                   clk,
  input                   reset
);

  localparam [ACTION_WIDTH-1:0] ACTION_BYPASS  = 2'b00;
  localparam [ACTION_WIDTH-1:0] ACTION_OFFLOAD = 2'b10;

  localparam [2:0] S_IDLE      = 3'd0;
  localparam [2:0] S_CAPTURE   = 3'd1;
  localparam [2:0] S_DRAIN_HDR = 3'd2;
  localparam [2:0] S_STREAM    = 3'd3;

  localparam [2:0] LAST_HEADER_INDEX = 3'd6;
  localparam [15:0] MIN_CLASSIFY_BYTES = 16'd46;

  reg [2:0] state;
  reg [DATA_WIDTH-1:0] header_data_0;
  reg [DATA_WIDTH-1:0] header_data_1;
  reg [DATA_WIDTH-1:0] header_data_2;
  reg [DATA_WIDTH-1:0] header_data_3;
  reg [DATA_WIDTH-1:0] header_data_4;
  reg [DATA_WIDTH-1:0] header_data_5;
  reg [DATA_WIDTH-1:0] header_data_6;
  reg [CTRL_WIDTH-1:0] header_ctrl_0;
  reg [CTRL_WIDTH-1:0] header_ctrl_1;
  reg [CTRL_WIDTH-1:0] header_ctrl_2;
  reg [CTRL_WIDTH-1:0] header_ctrl_3;
  reg [CTRL_WIDTH-1:0] header_ctrl_4;
  reg [CTRL_WIDTH-1:0] header_ctrl_5;
  reg [CTRL_WIDTH-1:0] header_ctrl_6;
  reg [2:0] header_count;
  reg [2:0] drain_count;
  reg [2:0] drain_idx;
  reg       packet_ended_in_header;
  reg [ACTION_WIDTH-1:0] packet_action;

  wire header_accept;
  wire stream_accept;
  reg  [DATA_WIDTH-1:0] drain_data_word;
  reg  [CTRL_WIDTH-1:0] drain_ctrl_word;

  assign header_accept = in_wr && in_rdy && ((state == S_IDLE) || (state == S_CAPTURE));
  assign stream_accept = in_wr && in_rdy && (state == S_STREAM);

  assign in_rdy = ((state == S_IDLE) || (state == S_CAPTURE)) ? 1'b1   :
                  (state == S_STREAM)                         ? out_rdy :
                                                                1'b0;
  assign out_data = (state == S_DRAIN_HDR) ? drain_data_word : in_data;
  assign out_ctrl = (state == S_DRAIN_HDR) ? drain_ctrl_word : in_ctrl;
  assign out_wr   = (state == S_DRAIN_HDR) ? 1'b1 :
                    (state == S_STREAM)    ? in_wr :
                                             1'b0;
  assign out_action = packet_action;

  always @(*) begin
    case (drain_idx)
      3'd0: begin
        drain_data_word = header_data_0;
        drain_ctrl_word = header_ctrl_0;
      end
      3'd1: begin
        drain_data_word = header_data_1;
        drain_ctrl_word = header_ctrl_1;
      end
      3'd2: begin
        drain_data_word = header_data_2;
        drain_ctrl_word = header_ctrl_2;
      end
      3'd3: begin
        drain_data_word = header_data_3;
        drain_ctrl_word = header_ctrl_3;
      end
      3'd4: begin
        drain_data_word = header_data_4;
        drain_ctrl_word = header_ctrl_4;
      end
      3'd5: begin
        drain_data_word = header_data_5;
        drain_ctrl_word = header_ctrl_5;
      end
      default: begin
        drain_data_word = header_data_6;
        drain_ctrl_word = header_ctrl_6;
      end
    endcase
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state                      <= S_IDLE;
      header_data_0              <= {DATA_WIDTH{1'b0}};
      header_data_1              <= {DATA_WIDTH{1'b0}};
      header_data_2              <= {DATA_WIDTH{1'b0}};
      header_data_3              <= {DATA_WIDTH{1'b0}};
      header_data_4              <= {DATA_WIDTH{1'b0}};
      header_data_5              <= {DATA_WIDTH{1'b0}};
      header_data_6              <= {DATA_WIDTH{1'b0}};
      header_ctrl_0              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_1              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_2              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_3              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_4              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_5              <= {CTRL_WIDTH{1'b0}};
      header_ctrl_6              <= {CTRL_WIDTH{1'b0}};
      header_count               <= 3'd0;
      drain_count                <= 3'd0;
      drain_idx                  <= 3'd0;
      packet_ended_in_header     <= 1'b0;
      packet_action              <= ACTION_BYPASS;
    end
    else begin
      case (state)
        S_IDLE: begin
          if (header_accept) begin
            header_data_0          <= in_data;
            header_ctrl_0          <= in_ctrl;
            header_count           <= 3'd1;
            drain_count            <= 3'd1;
            drain_idx              <= 3'd0;
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
              3'd3: begin
                header_data_3 <= in_data;
                header_ctrl_3 <= in_ctrl;
              end
              3'd4: begin
                header_data_4 <= in_data;
                header_ctrl_4 <= in_ctrl;
              end
              3'd5: begin
                header_data_5 <= in_data;
                header_ctrl_5 <= in_ctrl;
              end
              default: begin
                header_data_6 <= in_data;
                header_ctrl_6 <= in_ctrl;
              end
            endcase

            if (((in_ctrl != {CTRL_WIDTH{1'b0}}) && (header_count != 3'd0)) ||
                (header_count == LAST_HEADER_INDEX)) begin
              drain_count            <= header_count + 3'd1;
              drain_idx              <= 3'd0;
              packet_ended_in_header <= (in_ctrl != {CTRL_WIDTH{1'b0}});

              if (header_count == LAST_HEADER_INDEX) begin
                if ((header_data_0[15:0] >= MIN_CLASSIFY_BYTES) &&
                    (header_data_2[31:16] == IPV4_ETHERTYPE) &&
                    (header_data_2[15:12] == 4'h4) &&
                    (header_data_2[11:8]  == 4'h5) &&
                    (header_data_3[7:0]   == IP_PROTOCOL_UDP) &&
                    (header_data_5[31:16] == ANN_UDP_DST_PORT) &&
                    (in_data[47:32]       == ANN_TASK_MAGIC)) begin
                  packet_action <= ACTION_OFFLOAD;
                end
                else begin
                  packet_action <= ACTION_BYPASS;
                end
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
