`timescale 1ns/1ps

module ann_compute_core_simple #(
  parameter MAX_FEATURES = 1013
) (
  input                            clk,
  input                            reset,
  input                            start,
  input  [15:0]                    task_type,
  input  [15:0]                    feature_count,
  input  [MAX_FEATURES*16-1:0]     features_flat,

  output reg                       done,
  output reg [7:0]                 result_status,
  output reg [15:0]                result_type,
  output reg [15:0]                result_len,
  output reg [15:0]                result_data_0,
  output reg [15:0]                result_data_1
);

  localparam [7:0]  RESULT_STATUS_OK   = 8'h00;
  localparam [15:0] RESULT_TYPE_STATS  = 16'h0001;
  localparam [15:0] RESULT_LEN_BYTES   = 16'd4;

  integer i;
  integer signed feature_val;
  integer signed sum_acc;
  integer positive_count;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      done          <= 1'b0;
      result_status <= RESULT_STATUS_OK;
      result_type   <= RESULT_TYPE_STATS;
      result_len    <= RESULT_LEN_BYTES;
      result_data_0 <= 16'd0;
      result_data_1 <= 16'd0;
    end
    else begin
      done <= 1'b0;
      if (start) begin
        sum_acc = 0;
        positive_count = 0;

        for (i = 0; i < feature_count; i = i + 1) begin
          feature_val = $signed(features_flat[(i * 16) +: 16]);
          sum_acc = sum_acc + feature_val;
          if (feature_val > 0)
            positive_count = positive_count + 1;
        end

        result_status <= RESULT_STATUS_OK;
        result_type   <= RESULT_TYPE_STATS;
        result_len    <= RESULT_LEN_BYTES;
        result_data_0 <= sum_acc[15:0];
        result_data_1 <= positive_count[15:0];
        done          <= 1'b1;
      end
    end
  end

endmodule
