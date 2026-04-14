`timescale 1ns/1ps

module ann_feature_unpack #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter FRAME_LEN_WIDTH = 12,
  parameter FRAME_WORD_ADDR_WIDTH = 8,
  parameter MAX_FEATURES = 8,
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC   = 16'hA11E
) (
  input                                clk,
  input                                reset,
  input                                start,
  input                                frame_overflow,
  input  [63:0]                        module_header_word,
  input  [FRAME_LEN_WIDTH-1:0]         frame_len,
  input  [FRAME_WORD_ADDR_WIDTH:0]     frame_word_count,
  output reg [FRAME_WORD_ADDR_WIDTH-1:0] rd_addr,
  input  [DATA_WIDTH+CTRL_WIDTH-1:0]   rd_word,

  output reg                           done,
  output reg [7:0]                     parse_status,
  output reg [15:0]                    request_id,
  output reg [15:0]                    task_type,
  output reg [15:0]                    requested_feature_count,
  output reg [15:0]                    parsed_feature_count,
  output reg [15:0]                    dst_port_mask,
  output reg [15:0]                    src_port,
  output reg [47:0]                    eth_dst,
  output reg [47:0]                    eth_src,
  output reg [15:0]                    ethertype,
  output [MAX_FEATURES*16-1:0]         features_flat,
  output [15:0]                        feature_data_0,
  output [15:0]                        feature_data_1,
  output [15:0]                        feature_data_2,
  output [15:0]                        feature_data_3,
  output [15:0]                        feature_data_4,
  output [15:0]                        feature_data_5,
  output [15:0]                        feature_data_6,
  output [15:0]                        feature_data_7
);

  localparam [7:0] STATUS_OK               = 8'h00;
  localparam [7:0] STATUS_SHORT_FRAME      = 8'h01;
  localparam [7:0] STATUS_BAD_ETHERTYPE    = 8'h02;
  localparam [7:0] STATUS_BAD_MAGIC        = 8'h03;
  localparam [7:0] STATUS_CAPTURE_OVERFLOW = 8'h04;
  localparam [7:0] STATUS_FEATURE_TRUNC    = 8'h05;

  localparam [15:0] FEATURE_BASE_BYTES = 16'd24;
  localparam [15:0] MAX_FEATURES_16    = 16'd8;

  localparam [3:0] S_IDLE        = 4'd0;
  localparam [3:0] S_HDR0_WAIT   = 4'd1;
  localparam [3:0] S_HDR0_CAP    = 4'd2;
  localparam [3:0] S_HDR1_WAIT   = 4'd3;
  localparam [3:0] S_HDR1_CAP    = 4'd4;
  localparam [3:0] S_HDR2_WAIT   = 4'd5;
  localparam [3:0] S_HDR2_CAP    = 4'd6;
  localparam [3:0] S_COUNT_CALC  = 4'd7;
  localparam [3:0] S_COUNT_LATCH = 4'd8;
  localparam [3:0] S_FEAT_WAIT   = 4'd9;
  localparam [3:0] S_FEAT_CAP    = 4'd10;

  reg [3:0] state;
  reg [15:0] features_remaining;
  reg [15:0] feature_index;
  reg [FRAME_WORD_ADDR_WIDTH-1:0] feature_word_addr;
  reg [15:0] available_feature_count;
  reg [15:0] features_to_parse_clamped;
  reg        truncation_detected;

  reg [15:0] feature_reg_0;
  reg [15:0] feature_reg_1;
  reg [15:0] feature_reg_2;
  reg [15:0] feature_reg_3;
  reg [15:0] feature_reg_4;
  reg [15:0] feature_reg_5;
  reg [15:0] feature_reg_6;
  reg [15:0] feature_reg_7;

  assign features_flat   = {feature_reg_7, feature_reg_6, feature_reg_5, feature_reg_4,
                            feature_reg_3, feature_reg_2, feature_reg_1, feature_reg_0};
  assign feature_data_0  = feature_reg_0;
  assign feature_data_1  = feature_reg_1;
  assign feature_data_2  = feature_reg_2;
  assign feature_data_3  = feature_reg_3;
  assign feature_data_4  = feature_reg_4;
  assign feature_data_5  = feature_reg_5;
  assign feature_data_6  = feature_reg_6;
  assign feature_data_7  = feature_reg_7;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state                   <= S_IDLE;
      rd_addr                 <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      done                    <= 1'b0;
      parse_status            <= STATUS_OK;
      request_id              <= 16'd0;
      task_type               <= 16'd0;
      requested_feature_count <= 16'd0;
      parsed_feature_count    <= 16'd0;
      dst_port_mask           <= 16'd0;
      src_port                <= 16'd0;
      eth_dst                 <= 48'd0;
      eth_src                 <= 48'd0;
      ethertype               <= 16'd0;
      features_remaining      <= 16'd0;
      feature_index           <= 16'd0;
      feature_word_addr       <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      available_feature_count <= 16'd0;
      features_to_parse_clamped <= 16'd0;
      truncation_detected     <= 1'b0;
      feature_reg_0           <= 16'd0;
      feature_reg_1           <= 16'd0;
      feature_reg_2           <= 16'd0;
      feature_reg_3           <= 16'd0;
      feature_reg_4           <= 16'd0;
      feature_reg_5           <= 16'd0;
      feature_reg_6           <= 16'd0;
      feature_reg_7           <= 16'd0;
    end
    else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            parse_status            <= STATUS_OK;
            request_id              <= 16'd0;
            task_type               <= 16'd0;
            requested_feature_count <= 16'd0;
            parsed_feature_count    <= 16'd0;
            dst_port_mask           <= module_header_word[63:48];
            src_port                <= module_header_word[31:16];
            eth_dst                 <= 48'd0;
            eth_src                 <= 48'd0;
            ethertype               <= 16'd0;
            features_remaining      <= 16'd0;
            feature_index           <= 16'd0;
            feature_word_addr       <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
            available_feature_count <= 16'd0;
            features_to_parse_clamped <= 16'd0;
            truncation_detected     <= 1'b0;
            feature_reg_0           <= 16'd0;
            feature_reg_1           <= 16'd0;
            feature_reg_2           <= 16'd0;
            feature_reg_3           <= 16'd0;
            feature_reg_4           <= 16'd0;
            feature_reg_5           <= 16'd0;
            feature_reg_6           <= 16'd0;
            feature_reg_7           <= 16'd0;

            if (frame_overflow) begin
              parse_status <= STATUS_CAPTURE_OVERFLOW;
              done         <= 1'b1;
            end
            else if ({4'd0, frame_len} < FEATURE_BASE_BYTES) begin
              parse_status <= STATUS_SHORT_FRAME;
              done         <= 1'b1;
            end
            else begin
              rd_addr <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
              state   <= S_HDR0_WAIT;
            end
          end
        end

        S_HDR0_WAIT: begin
          state <= S_HDR0_CAP;
        end

        S_HDR0_CAP: begin
          eth_dst <= rd_word[47:0];
          rd_addr <= {{(FRAME_WORD_ADDR_WIDTH-1){1'b0}}, 1'b1};
          state   <= S_HDR1_WAIT;
        end

        S_HDR1_WAIT: begin
          state <= S_HDR1_CAP;
        end

        S_HDR1_CAP: begin
          eth_src   <= rd_word[63:16];
          ethertype <= rd_word[15:0];
          rd_addr   <= {{(FRAME_WORD_ADDR_WIDTH-2){1'b0}}, 2'b10};
          state     <= S_HDR2_WAIT;
        end

        S_HDR2_WAIT: begin
          state <= S_HDR2_CAP;
        end

        S_HDR2_CAP: begin
          requested_feature_count <= rd_word[31:16];
          request_id              <= rd_word[47:32];
          task_type               <= rd_word[15:0];

          if (ethertype != CUSTOM_ETHERTYPE) begin
            parse_status <= STATUS_BAD_ETHERTYPE;
            done         <= 1'b1;
            state        <= S_IDLE;
          end
          else if (rd_word[63:48] != ANN_TASK_MAGIC) begin
            parse_status <= STATUS_BAD_MAGIC;
            done         <= 1'b1;
            state        <= S_IDLE;
          end
          else begin
            state <= S_COUNT_CALC;
          end
        end

        S_COUNT_CALC: begin
          available_feature_count <= ({4'd0, frame_len} - FEATURE_BASE_BYTES) >> 1;

          if ((requested_feature_count > (({4'd0, frame_len} - FEATURE_BASE_BYTES) >> 1)) ||
              (requested_feature_count > MAX_FEATURES_16))
            truncation_detected <= 1'b1;
          else
            truncation_detected <= 1'b0;

          if (requested_feature_count > (({4'd0, frame_len} - FEATURE_BASE_BYTES) >> 1)) begin
            if ((({4'd0, frame_len} - FEATURE_BASE_BYTES) >> 1) > MAX_FEATURES_16)
              features_to_parse_clamped <= MAX_FEATURES_16;
            else
              features_to_parse_clamped <= ({4'd0, frame_len} - FEATURE_BASE_BYTES) >> 1;
          end
          else if (requested_feature_count > MAX_FEATURES_16) begin
            features_to_parse_clamped <= MAX_FEATURES_16;
          end
          else begin
            features_to_parse_clamped <= requested_feature_count;
          end

          state <= S_COUNT_LATCH;
        end

        S_COUNT_LATCH: begin
          parsed_feature_count <= features_to_parse_clamped;
          if (truncation_detected)
            parse_status <= STATUS_FEATURE_TRUNC;
          else
            parse_status <= STATUS_OK;

          if (features_to_parse_clamped == 16'd0) begin
            done  <= 1'b1;
            state <= S_IDLE;
          end
          else begin
            features_remaining <= features_to_parse_clamped;
            feature_index      <= 16'd0;
            feature_word_addr  <= {{(FRAME_WORD_ADDR_WIDTH-2){1'b0}}, 2'b11};
            rd_addr            <= {{(FRAME_WORD_ADDR_WIDTH-2){1'b0}}, 2'b11};
            state              <= S_FEAT_WAIT;
          end
        end

        S_FEAT_WAIT: begin
          state <= S_FEAT_CAP;
        end

        S_FEAT_CAP: begin
          if (!feature_index[2]) begin
            if (features_remaining > 0)
              feature_reg_0 <= rd_word[63:48];
            if (features_remaining > 1)
              feature_reg_1 <= rd_word[47:32];
            if (features_remaining > 2)
              feature_reg_2 <= rd_word[31:16];
            if (features_remaining > 3)
              feature_reg_3 <= rd_word[15:0];
          end
          else begin
            if (features_remaining > 0)
              feature_reg_4 <= rd_word[63:48];
            if (features_remaining > 1)
              feature_reg_5 <= rd_word[47:32];
            if (features_remaining > 2)
              feature_reg_6 <= rd_word[31:16];
            if (features_remaining > 3)
              feature_reg_7 <= rd_word[15:0];
          end

          if (features_remaining <= 16'd4) begin
            done  <= 1'b1;
            state <= S_IDLE;
          end
          else begin
            features_remaining <= features_remaining - 16'd4;
            feature_index      <= feature_index + 16'd4;
            feature_word_addr  <= feature_word_addr + {{(FRAME_WORD_ADDR_WIDTH-1){1'b0}}, 1'b1};
            rd_addr            <= feature_word_addr + {{(FRAME_WORD_ADDR_WIDTH-1){1'b0}}, 1'b1};
            state              <= S_FEAT_WAIT;
          end
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
