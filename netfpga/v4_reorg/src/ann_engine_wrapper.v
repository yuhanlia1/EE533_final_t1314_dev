`timescale 1ns/1ps

module ann_engine_wrapper #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter MAX_FRAME_BYTES = 2048,
  parameter [15:0] CUSTOM_ETHERTYPE = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC   = 16'hA11E,
  parameter [15:0] ANN_RESULT_MAGIC = 16'hA11F
) (
  input  [DATA_WIDTH-1:0]  in_data,
  input  [CTRL_WIDTH-1:0]  in_ctrl,
  input                    in_wr,
  output                   in_rdy,

  output [DATA_WIDTH-1:0]  out_data,
  output [CTRL_WIDTH-1:0]  out_ctrl,
  output                   out_wr,
  input                    out_rdy,

  input  [31:0]            sw_i_mem_addr,
  input  [31:0]            sw_i_mem_wdata,
  input  [31:0]            sw_d_mem_addr,
  input  [31:0]            sw_gpu_w_mem_addr,
  input  [31:0]            sw_gpu_w_mem_wdata_0,
  input  [31:0]            sw_gpu_w_mem_wdata_1,
  input  [31:0]            sw_gpu_ifmap_addr,
  input  [31:0]            sw_gpu_ifmap_wdata,
  input  [31:0]            sw_gpu_ofmap_addr,

  output [31:0]            hw_gpu_ofmap_data_1,
  output [31:0]            hw_gpu_ofmap_data_0,
  output     [31:0]        hw_gpu_drop,

  input                    clk,
  input                    reset
);

  localparam integer FRAME_LEN_WIDTH = $clog2(MAX_FRAME_BYTES + 1);
  localparam integer MAX_FEATURES = ((MAX_FRAME_BYTES > 24) ? ((MAX_FRAME_BYTES - 24) / 2) : 1);
  localparam integer RESULT_FRAME_BYTES = 30;
  localparam integer RESULT_DATA_WORDS  = ((RESULT_FRAME_BYTES + 7) / 8);
  localparam integer RESULT_PKT_WORDS   = RESULT_DATA_WORDS + 1;
  localparam [7:0] STATUS_OK            = 8'h00;
  localparam [7:0] STATUS_FEATURE_TRUNC = 8'h05;

  localparam [2:0] ST_WAIT_FRAME   = 3'd0;
  localparam [2:0] ST_PARSE_START  = 3'd1;
  localparam [2:0] ST_PARSE_WAIT   = 3'd2;
  localparam [2:0] ST_COMPUTE_START = 3'd3;
  localparam [2:0] ST_COMPUTE_WAIT = 3'd4;
  localparam [2:0] ST_BUILD_START  = 3'd5;
  localparam [2:0] ST_BUILD_WAIT   = 3'd6;
  localparam [2:0] ST_DRAIN        = 3'd7;

  reg  [2:0] state;
  reg  [$clog2(RESULT_PKT_WORDS)-1:0] out_pkt_idx;

  wire                                  ingress_frame_valid;
  wire                                  ingress_in_rdy;
  wire [DATA_WIDTH-1:0]                 ingress_module_header_word;
  wire [FRAME_LEN_WIDTH-1:0]            ingress_frame_len;
  wire [MAX_FRAME_BYTES*8-1:0]          ingress_frame_bytes_flat;
  wire                                  ingress_frame_overflow;
  wire                                  ingress_frame_taken;

  wire                                  parse_start;
  wire                                  parse_done;
  wire [7:0]                            parse_status;
  wire [15:0]                           parse_request_id;
  wire [15:0]                           parse_task_type;
  wire [15:0]                           parse_requested_feature_count;
  wire [15:0]                           parse_parsed_feature_count;
  wire [15:0]                           parse_dst_port_mask;
  wire [15:0]                           parse_src_port;
  wire [47:0]                           parse_eth_dst;
  wire [47:0]                           parse_eth_src;
  wire [15:0]                           parse_ethertype;
  wire [MAX_FEATURES*16-1:0]            parse_features_flat;

  wire                                  compute_start;
  wire                                  compute_done;
  wire [7:0]                            compute_result_status;
  wire [15:0]                           compute_result_type;
  wire [15:0]                           compute_result_len;
  wire [15:0]                           compute_result_data_0;
  wire [15:0]                           compute_result_data_1;

  wire                                  build_start;
  wire                                  build_done;
  wire [RESULT_PKT_WORDS*DATA_WIDTH-1:0] built_pkt_data_flat;
  wire [RESULT_PKT_WORDS*CTRL_WIDTH-1:0] built_pkt_ctrl_flat;

  wire parse_nonfatal;
  wire [7:0] build_status;
  wire [15:0] build_result_type;
  wire [15:0] build_result_len;
  wire [15:0] build_result_data_0;
  wire [15:0] build_result_data_1;

  assign in_rdy            = ingress_in_rdy;
  assign out_data          = built_pkt_data_flat[(out_pkt_idx * DATA_WIDTH) +: DATA_WIDTH];
  assign out_ctrl          = built_pkt_ctrl_flat[(out_pkt_idx * CTRL_WIDTH) +: CTRL_WIDTH];
  assign out_wr            = (state == ST_DRAIN);
  assign hw_gpu_drop = 32'd0;

  assign parse_start        = (state == ST_PARSE_START);
  assign compute_start      = (state == ST_COMPUTE_START);
  assign build_start        = (state == ST_BUILD_START);
  assign ingress_frame_taken = (state == ST_DRAIN) && out_rdy &&
                               (out_pkt_idx == RESULT_PKT_WORDS - 1);
  assign parse_nonfatal     = (parse_status == STATUS_OK) ||
                              (parse_status == STATUS_FEATURE_TRUNC);
  assign build_status       = (parse_status == STATUS_OK) ? compute_result_status : parse_status;
  assign build_result_type  = parse_nonfatal ? compute_result_type   : 16'd0;
  assign build_result_len   = parse_nonfatal ? compute_result_len    : 16'd0;
  assign build_result_data_0 = parse_nonfatal ? compute_result_data_0 : 16'd0;
  assign build_result_data_1 = parse_nonfatal ? compute_result_data_1 : 16'd0;

  ann_task_ingress #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH)
  ) ingress (
    .in_data            (in_data),
    .in_ctrl            (in_ctrl),
    .in_wr              (in_wr),
    .in_rdy             (ingress_in_rdy),
    .frame_valid        (ingress_frame_valid),
    .frame_taken        (ingress_frame_taken),
    .module_header_word (ingress_module_header_word),
    .frame_len          (ingress_frame_len),
    .frame_bytes_flat   (ingress_frame_bytes_flat),
    .frame_overflow     (ingress_frame_overflow),
    .clk                (clk),
    .reset              (reset)
  );

  ann_feature_unpack #(
    .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH),
    .MAX_FEATURES(MAX_FEATURES),
    .CUSTOM_ETHERTYPE(CUSTOM_ETHERTYPE),
    .ANN_TASK_MAGIC(ANN_TASK_MAGIC)
  ) unpack (
    .clk                     (clk),
    .reset                   (reset),
    .start                   (parse_start),
    .frame_overflow          (ingress_frame_overflow),
    .module_header_word      (ingress_module_header_word),
    .frame_len               (ingress_frame_len),
    .frame_bytes_flat        (ingress_frame_bytes_flat),
    .done                    (parse_done),
    .parse_status            (parse_status),
    .request_id              (parse_request_id),
    .task_type               (parse_task_type),
    .requested_feature_count (parse_requested_feature_count),
    .parsed_feature_count    (parse_parsed_feature_count),
    .dst_port_mask           (parse_dst_port_mask),
    .src_port                (parse_src_port),
    .eth_dst                 (parse_eth_dst),
    .eth_src                 (parse_eth_src),
    .ethertype               (parse_ethertype),
    .features_flat           (parse_features_flat)
  );

  ann_cpu_gpu_compute_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH),
    .MAX_FEATURES(MAX_FEATURES)
  ) compute_core (
    .clk                (clk),
    .reset              (reset),
    .start              (compute_start),
    .module_header_word (ingress_module_header_word),
    .frame_len          (ingress_frame_len),
    .frame_bytes_flat   (ingress_frame_bytes_flat),
    .task_type          (parse_task_type),
    .feature_count      (parse_parsed_feature_count),
    .features_flat      (parse_features_flat),
    .sw_i_mem_addr      (sw_i_mem_addr),
    .sw_i_mem_wdata     (sw_i_mem_wdata),
    .sw_d_mem_addr      (sw_d_mem_addr),
    .sw_gpu_w_mem_addr  (sw_gpu_w_mem_addr),
    .sw_gpu_w_mem_wdata_0(sw_gpu_w_mem_wdata_0),
    .sw_gpu_w_mem_wdata_1(sw_gpu_w_mem_wdata_1),
    .sw_gpu_ifmap_addr  (sw_gpu_ifmap_addr),
    .sw_gpu_ifmap_wdata (sw_gpu_ifmap_wdata),
    .sw_gpu_ofmap_addr  (sw_gpu_ofmap_addr),
    .done               (compute_done),
    .result_status      (compute_result_status),
    .result_type        (compute_result_type),
    .result_len         (compute_result_len),
    .result_data_0      (compute_result_data_0),
    .result_data_1      (compute_result_data_1),
    .hw_gpu_ofmap_data_0(hw_gpu_ofmap_data_0),
    .hw_gpu_ofmap_data_1(hw_gpu_ofmap_data_1)
  );

  ann_result_packet_builder #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .RESULT_FRAME_BYTES(RESULT_FRAME_BYTES),
    .RESULT_DATA_WORDS(RESULT_DATA_WORDS),
    .RESULT_PKT_WORDS(RESULT_PKT_WORDS),
    .CUSTOM_ETHERTYPE(CUSTOM_ETHERTYPE),
    .ANN_RESULT_MAGIC(ANN_RESULT_MAGIC)
  ) builder (
    .clk           (clk),
    .reset         (reset),
    .start         (build_start),
    .dst_port_mask (parse_dst_port_mask),
    .src_port      (parse_src_port),
    .eth_dst       (parse_eth_dst),
    .eth_src       (parse_eth_src),
    .request_id    (parse_request_id),
    .result_status (build_status),
    .result_type   (build_result_type),
    .result_len    (build_result_len),
    .result_data_0 (build_result_data_0),
    .result_data_1 (build_result_data_1),
    .done          (build_done),
    .pkt_data_flat (built_pkt_data_flat),
    .pkt_ctrl_flat (built_pkt_ctrl_flat)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state               <= ST_WAIT_FRAME;
      out_pkt_idx         <= {($clog2(RESULT_PKT_WORDS)){1'b0}};
    end
    else begin
      case (state)
        ST_WAIT_FRAME: begin
          out_pkt_idx <= {($clog2(RESULT_PKT_WORDS)){1'b0}};
          if (ingress_frame_valid)
            state <= ST_PARSE_START;
        end

        ST_PARSE_START: begin
          state <= ST_PARSE_WAIT;
        end

        ST_PARSE_WAIT: begin
          if (parse_done) begin
            if (parse_nonfatal) begin
              state <= ST_COMPUTE_START;
            end
            else begin
              state <= ST_BUILD_START;
            end
          end
        end

        ST_COMPUTE_START: begin
          state <= ST_COMPUTE_WAIT;
        end

        ST_COMPUTE_WAIT: begin
          if (compute_done) begin
            state <= ST_BUILD_START;
          end
        end

        ST_BUILD_START: begin
          state <= ST_BUILD_WAIT;
        end

        ST_BUILD_WAIT: begin
          if (build_done) begin
            out_pkt_idx <= {($clog2(RESULT_PKT_WORDS)){1'b0}};
            state <= ST_DRAIN;
          end
        end

        ST_DRAIN: begin
          if (out_rdy) begin
            if (out_pkt_idx == RESULT_PKT_WORDS - 1) begin
              out_pkt_idx <= {($clog2(RESULT_PKT_WORDS)){1'b0}};
              state <= ST_WAIT_FRAME;
            end
            else begin
              out_pkt_idx <= out_pkt_idx + 1'b1;
            end
          end
        end

        default: begin
          state <= ST_WAIT_FRAME;
        end
      endcase
    end
  end

endmodule
