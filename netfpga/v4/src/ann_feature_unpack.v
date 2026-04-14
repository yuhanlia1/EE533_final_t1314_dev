`timescale 1ns/1ps

module ann_feature_unpack #(
  parameter MAX_FRAME_BYTES = 2048,
  parameter FRAME_LEN_WIDTH = $clog2(MAX_FRAME_BYTES + 1),
  parameter MAX_FEATURES = ((MAX_FRAME_BYTES > 22) ? ((MAX_FRAME_BYTES - 22) / 2) : 1),
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC   = 16'hA11E
) (
  input                                clk,
  input                                reset,
  input                                start,
  input                                frame_overflow,
  input  [63:0]                        module_header_word,
  input  [FRAME_LEN_WIDTH-1:0]         frame_len,
  input  [MAX_FRAME_BYTES*8-1:0]       frame_bytes_flat,

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
  output reg [MAX_FEATURES*16-1:0]     features_flat
);

  localparam [7:0] STATUS_OK               = 8'h00;
  localparam [7:0] STATUS_SHORT_FRAME      = 8'h01;
  localparam [7:0] STATUS_BAD_ETHERTYPE    = 8'h02;
  localparam [7:0] STATUS_BAD_MAGIC        = 8'h03;
  localparam [7:0] STATUS_CAPTURE_OVERFLOW = 8'h04;
  localparam [7:0] STATUS_FEATURE_TRUNC    = 8'h05;
  localparam integer PAD_BYTES             = 2;
  localparam integer ETH_DST_OFF           = 2;
  localparam integer ETH_SRC_OFF           = 8;
  localparam integer ETHERTYPE_OFF         = 14;
  localparam integer MAGIC_OFF             = 16;
  localparam integer REQUEST_ID_OFF        = 18;
  localparam integer FEATURE_COUNT_OFF     = 20;
  localparam integer TASK_TYPE_OFF         = 22;
  localparam integer FEATURE_BASE_OFF      = 24;

  function automatic [7:0] get_byte;
    input [MAX_FRAME_BYTES*8-1:0] flat;
    input integer idx;
    begin
      get_byte = flat[(idx * 8) +: 8];
    end
  endfunction

  integer i;
  integer available_features;
  integer features_to_parse;
  reg [7:0]                 parse_status_next;
  reg [15:0]                request_id_next;
  reg [15:0]                task_type_next;
  reg [15:0]                requested_feature_count_next;
  reg [15:0]                parsed_feature_count_next;
  reg [15:0]                dst_port_mask_next;
  reg [15:0]                src_port_next;
  reg [47:0]                eth_dst_next;
  reg [47:0]                eth_src_next;
  reg [15:0]                ethertype_next;
  reg [MAX_FEATURES*16-1:0] features_flat_next;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
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
      features_flat           <= {(MAX_FEATURES*16){1'b0}};
    end
    else begin
      done <= 1'b0;
      if (start) begin
        parse_status_next            = STATUS_OK;
        request_id_next              = 16'd0;
        task_type_next               = 16'd0;
        requested_feature_count_next = 16'd0;
        parsed_feature_count_next    = 16'd0;
        dst_port_mask_next           = module_header_word[63:48];
        src_port_next                = module_header_word[31:16];
        eth_dst_next                 = 48'd0;
        eth_src_next                 = 48'd0;
        ethertype_next               = 16'd0;
        features_flat_next           = {(MAX_FEATURES*16){1'b0}};
        available_features           = 0;
        features_to_parse            = 0;

        if (frame_overflow) begin
          parse_status_next = STATUS_CAPTURE_OVERFLOW;
        end
        else if (frame_len < FEATURE_BASE_OFF) begin
          parse_status_next = STATUS_SHORT_FRAME;
        end
        else begin
          eth_dst_next = {
            get_byte(frame_bytes_flat, ETH_DST_OFF + 0), get_byte(frame_bytes_flat, ETH_DST_OFF + 1),
            get_byte(frame_bytes_flat, ETH_DST_OFF + 2), get_byte(frame_bytes_flat, ETH_DST_OFF + 3),
            get_byte(frame_bytes_flat, ETH_DST_OFF + 4), get_byte(frame_bytes_flat, ETH_DST_OFF + 5)
          };
          eth_src_next = {
            get_byte(frame_bytes_flat, ETH_SRC_OFF + 0), get_byte(frame_bytes_flat, ETH_SRC_OFF + 1),
            get_byte(frame_bytes_flat, ETH_SRC_OFF + 2), get_byte(frame_bytes_flat, ETH_SRC_OFF + 3),
            get_byte(frame_bytes_flat, ETH_SRC_OFF + 4), get_byte(frame_bytes_flat, ETH_SRC_OFF + 5)
          };
          ethertype_next               = {
            get_byte(frame_bytes_flat, ETHERTYPE_OFF + 0),
            get_byte(frame_bytes_flat, ETHERTYPE_OFF + 1)
          };
          request_id_next              = {
            get_byte(frame_bytes_flat, REQUEST_ID_OFF + 0),
            get_byte(frame_bytes_flat, REQUEST_ID_OFF + 1)
          };
          requested_feature_count_next = {
            get_byte(frame_bytes_flat, FEATURE_COUNT_OFF + 0),
            get_byte(frame_bytes_flat, FEATURE_COUNT_OFF + 1)
          };
          task_type_next               = {
            get_byte(frame_bytes_flat, TASK_TYPE_OFF + 0),
            get_byte(frame_bytes_flat, TASK_TYPE_OFF + 1)
          };

          if (ethertype_next != CUSTOM_ETHERTYPE) begin
            parse_status_next = STATUS_BAD_ETHERTYPE;
          end
          else if ({
            get_byte(frame_bytes_flat, MAGIC_OFF + 0),
            get_byte(frame_bytes_flat, MAGIC_OFF + 1)
          } != ANN_TASK_MAGIC) begin
            parse_status_next = STATUS_BAD_MAGIC;
          end
          else begin
            available_features = (frame_len - FEATURE_BASE_OFF) / 2;
            features_to_parse = requested_feature_count_next;
            if (features_to_parse > available_features)
              features_to_parse = available_features;
            if (features_to_parse > MAX_FEATURES)
              features_to_parse = MAX_FEATURES;

            parsed_feature_count_next = features_to_parse[15:0];
            if ((requested_feature_count_next > available_features) ||
                (requested_feature_count_next > MAX_FEATURES))
              parse_status_next = STATUS_FEATURE_TRUNC;

            for (i = 0; i < features_to_parse; i = i + 1)
              features_flat_next[(i * 16) +: 16] = {
                get_byte(frame_bytes_flat, FEATURE_BASE_OFF + (i * 2)),
                get_byte(frame_bytes_flat, FEATURE_BASE_OFF + (i * 2) + 1)
              };
          end
        end

        parse_status            <= parse_status_next;
        request_id              <= request_id_next;
        task_type               <= task_type_next;
        requested_feature_count <= requested_feature_count_next;
        parsed_feature_count    <= parsed_feature_count_next;
        dst_port_mask           <= dst_port_mask_next;
        src_port                <= src_port_next;
        eth_dst                 <= eth_dst_next;
        eth_src                 <= eth_src_next;
        ethertype               <= ethertype_next;
        features_flat           <= features_flat_next;
        done                    <= 1'b1;
      end
    end
  end

endmodule
