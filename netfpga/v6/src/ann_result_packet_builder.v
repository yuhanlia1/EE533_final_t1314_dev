`timescale 1ns/1ps

module ann_result_packet_builder #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter RESULT_FRAME_BYTES = 30,
  parameter RESULT_DATA_WORDS = ((RESULT_FRAME_BYTES + 7) / 8),
  parameter RESULT_PKT_WORDS  = RESULT_DATA_WORDS + 1,
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_RESULT_MAGIC = 16'hA11F,
  parameter [7:0]  ANN_RESULT_VERSION = 8'h01
) (
  input                                  clk,
  input                                  reset,
  input                                  start,
  input  [15:0]                          dst_port_mask,
  input  [15:0]                          src_port,
  input  [47:0]                          eth_dst,
  input  [47:0]                          eth_src,
  input  [15:0]                          request_id,
  input  [7:0]                           result_status,
  input  [15:0]                          result_type,
  input  [15:0]                          result_len,
  input  [15:0]                          result_data_0,
  input  [15:0]                          result_data_1,

  output reg                             done,
  output reg [RESULT_PKT_WORDS*DATA_WIDTH-1:0] pkt_data_flat,
  output reg [RESULT_PKT_WORDS*CTRL_WIDTH-1:0] pkt_ctrl_flat
);

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      done             <= 1'b0;
      pkt_data_flat    <= {(RESULT_PKT_WORDS*DATA_WIDTH){1'b0}};
      pkt_ctrl_flat    <= {(RESULT_PKT_WORDS*CTRL_WIDTH){1'b0}};
    end
    else begin
      done <= 1'b0;
      if (start) begin
        pkt_data_flat <= {
          {
            result_len[15:8],
            result_len[7:0],
            result_data_0[15:8],
            result_data_0[7:0],
            result_data_1[15:8],
            result_data_1[7:0],
            8'h00,
            8'h00
          },
          {
            ANN_RESULT_MAGIC[15:8],
            ANN_RESULT_MAGIC[7:0],
            ANN_RESULT_VERSION,
            result_status,
            request_id[15:8],
            request_id[7:0],
            result_type[15:8],
            result_type[7:0]
          },
          {
            eth_src[47:40],
            eth_src[39:32],
            eth_src[31:24],
            eth_src[23:16],
            eth_src[15:8],
            eth_src[7:0],
            CUSTOM_ETHERTYPE[15:8],
            CUSTOM_ETHERTYPE[7:0]
          },
          {
            8'h00,
            8'h00,
            eth_dst[47:40],
            eth_dst[39:32],
            eth_dst[31:24],
            eth_dst[23:16],
            eth_dst[15:8],
            eth_dst[7:0]
          },
          {
            dst_port_mask,
            RESULT_DATA_WORDS[15:0],
            src_port,
            RESULT_FRAME_BYTES[15:0]
          }
        };
        pkt_ctrl_flat <= {
          8'h04,
          8'h00,
          8'h00,
          8'h00,
          8'hff
        };

        done <= 1'b1;
      end
    end
  end

endmodule
