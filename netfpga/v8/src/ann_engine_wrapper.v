`timescale 1ns/1ps

module ann_engine_wrapper #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter MAX_FRAME_BYTES = 2048,
  parameter [15:0] IPV4_ETHERTYPE = 16'h0800,
  parameter [7:0]  IP_PROTOCOL_UDP = 8'h11,
  parameter [15:0] ANN_UDP_DST_PORT = 16'h88B5,
  parameter [15:0] ANN_TASK_MAGIC   = 16'hA11E,
  parameter [15:0] ANN_RESULT_MAGIC = 16'hA11F,
  parameter [7:0]  ANN_RESULT_VERSION = 8'h01
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
  input  [31:0]            sw_engine_ctrl,
  input  [31:0]            sw_gpu_i_mem_addr,
  input  [31:0]            sw_gpu_i_mem_wdata,
  input  [31:0]            sw_gpu_w_mem_addr,
  input  [31:0]            sw_gpu_w_mem_wdata_0,
  input  [31:0]            sw_gpu_w_mem_wdata_1,
  input  [31:0]            sw_gpu_ofmap_addr,

  output [31:0]            hw_gpu_ofmap_data_1,
  output [31:0]            hw_gpu_ofmap_data_0,
  output [31:0]            hw_cpu_i_mem_word_out,
  output [31:0]            hw_cpu_d_mem_word_out_0,
  output [31:0]            hw_cpu_d_mem_word_out_1,
  output [31:0]            hw_engine_status,
  output                   debug_frame_ready_pulse,
  output                   debug_parse_done_pulse,
  output                   debug_compute_start_pulse,
  output                   debug_compute_done_pulse,
  output                   debug_result_emit_pulse,
  output                   debug_ingress_overflow_pulse,
  output                   debug_parse_nonfatal_pulse,
  output                   debug_parse_fatal_pulse,
  output                   debug_emit_stall,
  output [15:0]            debug_parse_request_id,
  output [15:0]            debug_active_request_id,

  input                    clk,
  input                    reset
);

  function integer clog2;
    input integer value;
    integer tmp;
    begin
      tmp = value - 1;
      clog2 = 0;
      while (tmp > 0) begin
        tmp = tmp >> 1;
        clog2 = clog2 + 1;
      end
    end
  endfunction

  localparam integer FRAME_LEN_WIDTH = clog2(MAX_FRAME_BYTES + 1);
  localparam integer FRAME_WORD_ADDR_WIDTH = clog2((MAX_FRAME_BYTES + CTRL_WIDTH - 1) / CTRL_WIDTH);
  localparam integer MAX_FEATURES = 1024;
  localparam [7:0] STATUS_OK            = 8'h00;
  localparam [7:0] STATUS_FEATURE_TRUNC = 8'h05;
  localparam [FRAME_WORD_ADDR_WIDTH-1:0] RESULT_WORD0_FRAME_IDX = 5;
  localparam [FRAME_WORD_ADDR_WIDTH-1:0] RESULT_WORD1_FRAME_IDX = 6;

  localparam [2:0] ST_WAIT_FRAME   = 3'd0;
  localparam [2:0] ST_PARSE_START  = 3'd1;
  localparam [2:0] ST_PARSE_WAIT   = 3'd2;
  localparam [2:0] ST_COMPUTE_START = 3'd3;
  localparam [2:0] ST_COMPUTE_WAIT = 3'd4;
  localparam [2:0] ST_DRAIN_HDR    = 3'd5;
  localparam [2:0] ST_DRAIN_PRIME  = 3'd6;
  localparam [2:0] ST_DRAIN_WORD   = 3'd7;

  reg  [2:0] state;
  reg  [FRAME_WORD_ADDR_WIDTH-1:0] drain_word_idx;
  reg  [FRAME_WORD_ADDR_WIDTH-1:0] drain_rd_addr;

  wire                                  ingress_frame_valid;
  wire                                  ingress_frame_ready_pulse;
  wire                                  ingress_in_rdy;
  wire [DATA_WIDTH-1:0]                 ingress_module_header_word;
  wire [FRAME_LEN_WIDTH-1:0]            ingress_frame_len;
  wire [FRAME_WORD_ADDR_WIDTH:0]        ingress_frame_word_count;
  wire                                  ingress_frame_overflow;
  wire                                  ingress_frame_taken;
  wire [FRAME_WORD_ADDR_WIDTH-1:0]      parse_rd_addr;
  wire [DATA_WIDTH+CTRL_WIDTH-1:0]      parse_rd_word;
  wire                                  drain_rd_en;
  wire [DATA_WIDTH+CTRL_WIDTH-1:0]      drain_rd_word;
  wire [FRAME_WORD_ADDR_WIDTH-1:0]      compute_rd_addr;
  wire [DATA_WIDTH+CTRL_WIDTH-1:0]      compute_rd_word;

  wire                                  parse_start;
  wire                                  parse_done;
  wire [7:0]                            parse_status;
  wire [15:0]                           parse_request_id;
  wire [15:0]                           parse_task_type;
  wire [15:0]                           parse_requested_feature_count;
  wire [15:0]                           parse_parsed_feature_count;
  wire [15:0]                           parse_dst_port_mask;
  wire [15:0]                           parse_src_port;
  wire                                  parse_feature_wr_en;
  wire [15:0]                           parse_feature_wr_addr;
  wire [15:0]                           parse_feature_wr_data;
  wire                                  parse_feature_wr_last;

  wire                                  compute_start;
  wire                                  compute_done;
  wire [7:0]                            compute_result_status;
  wire [15:0]                           compute_result_type;
  wire [15:0]                           compute_result_len;
  wire [15:0]                           compute_result_data_0;
  wire [15:0]                           compute_result_data_1;

  wire parse_nonfatal;
  wire [7:0] build_status;
  wire [15:0] build_result_type;
  wire [15:0] build_result_len;
  wire [15:0] build_result_data_0;
  wire [15:0] build_result_data_1;
  reg  [DATA_WIDTH-1:0]                 built_word_data;
  reg  [CTRL_WIDTH-1:0]                 built_word_ctrl;
  wire [DATA_WIDTH-1:0]                 drain_frame_data;
  wire [CTRL_WIDTH-1:0]                 drain_frame_ctrl;
  reg  [DATA_WIDTH-1:0]                 rewritten_frame_data;
  reg  [15:0]                           active_request_id;

  assign in_rdy            = ingress_in_rdy;
  assign out_data          = built_word_data;
  assign out_ctrl          = built_word_ctrl;
  assign out_wr            = (state == ST_DRAIN_HDR) || (state == ST_DRAIN_WORD);

  assign parse_start        = (state == ST_PARSE_START);
  assign compute_start      = (state == ST_COMPUTE_START);
  assign drain_rd_en        = (state == ST_DRAIN_PRIME);
  assign ingress_frame_taken = ((state == ST_DRAIN_HDR) && out_rdy &&
                                (ingress_frame_word_count == {(FRAME_WORD_ADDR_WIDTH+1){1'b0}})) ||
                               ((state == ST_DRAIN_WORD) && out_rdy &&
                                (drain_word_idx == ingress_frame_word_count[FRAME_WORD_ADDR_WIDTH-1:0] - 1'b1));
  assign parse_nonfatal     = (parse_status == STATUS_OK) ||
                              (parse_status == STATUS_FEATURE_TRUNC);
  assign build_status       = (parse_status == STATUS_OK) ? compute_result_status : parse_status;
  assign build_result_type  = parse_nonfatal ? compute_result_type   : 16'd0;
  assign build_result_len   = parse_nonfatal ? compute_result_len    : 16'd0;
  assign build_result_data_0 = parse_nonfatal ? compute_result_data_0 : 16'd0;
  assign build_result_data_1 = parse_nonfatal ? compute_result_data_1 : 16'd0;
  assign drain_frame_data   = drain_rd_word[DATA_WIDTH-1:0];
  assign drain_frame_ctrl   = drain_rd_word[DATA_WIDTH+CTRL_WIDTH-1:DATA_WIDTH];
  assign debug_frame_ready_pulse = ingress_frame_ready_pulse;
  assign debug_parse_done_pulse = parse_done;
  assign debug_compute_start_pulse = compute_start;
  assign debug_compute_done_pulse = compute_done;
  assign debug_result_emit_pulse = ((state == ST_DRAIN_HDR) && out_rdy &&
                                    (ingress_frame_word_count == {(FRAME_WORD_ADDR_WIDTH+1){1'b0}})) ||
                                   ((state == ST_DRAIN_WORD) && out_rdy &&
                                    (drain_word_idx == ingress_frame_word_count[FRAME_WORD_ADDR_WIDTH-1:0] - 1'b1));
  assign debug_ingress_overflow_pulse = ingress_frame_ready_pulse && ingress_frame_overflow;
  assign debug_parse_nonfatal_pulse = parse_done && parse_nonfatal && (parse_status != STATUS_OK);
  assign debug_parse_fatal_pulse = parse_done && !parse_nonfatal;
  assign debug_emit_stall = (((state == ST_DRAIN_HDR) || (state == ST_DRAIN_WORD)) && !out_rdy);
  assign debug_parse_request_id = parse_request_id;
  assign debug_active_request_id = active_request_id;

  always @(*) begin
    rewritten_frame_data = drain_frame_data;
    if (parse_nonfatal) begin
      if (drain_word_idx == RESULT_WORD0_FRAME_IDX) begin
        rewritten_frame_data = {
          drain_frame_data[63:48],
          ANN_RESULT_MAGIC,
          ANN_RESULT_VERSION,
          build_status,
          parse_request_id
        };
      end
      else if (drain_word_idx == RESULT_WORD1_FRAME_IDX) begin
        rewritten_frame_data = {
          build_result_type,
          build_result_len,
          build_result_data_0,
          build_result_data_1
        };
      end
    end

    case (state)
      ST_DRAIN_HDR: begin
        built_word_data = ingress_module_header_word;
        built_word_ctrl = {CTRL_WIDTH{1'b1}};
      end
      ST_DRAIN_WORD: begin
        built_word_data = rewritten_frame_data;
        built_word_ctrl = drain_frame_ctrl;
      end
      default: begin
        built_word_data = {DATA_WIDTH{1'b0}};
        built_word_ctrl = {CTRL_WIDTH{1'b0}};
      end
    endcase
  end

  ann_task_ingress #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH),
    .FRAME_WORD_ADDR_WIDTH(FRAME_WORD_ADDR_WIDTH)
  ) ingress (
    .in_data            (in_data),
    .in_ctrl            (in_ctrl),
    .in_wr              (in_wr),
    .in_rdy             (ingress_in_rdy),
    .frame_valid        (ingress_frame_valid),
    .frame_taken        (ingress_frame_taken),
    .frame_ready_pulse  (ingress_frame_ready_pulse),
    .module_header_word (ingress_module_header_word),
    .frame_len          (ingress_frame_len),
    .frame_word_count   (ingress_frame_word_count),
    .frame_overflow     (ingress_frame_overflow),
    .parser_rd_addr     (parse_rd_addr),
    .parser_rd_word     (parse_rd_word),
    .drain_rd_en        (drain_rd_en),
    .drain_rd_addr      (drain_rd_addr),
    .drain_rd_word      (drain_rd_word),
    .compute_rd_addr    (compute_rd_addr),
    .compute_rd_word    (compute_rd_word),
    .clk                (clk),
    .reset              (reset)
  );

  ann_feature_unpack #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH),
    .FRAME_WORD_ADDR_WIDTH(FRAME_WORD_ADDR_WIDTH),
    .MAX_FEATURES(MAX_FEATURES),
    .IPV4_ETHERTYPE(IPV4_ETHERTYPE),
    .IP_PROTOCOL_UDP(IP_PROTOCOL_UDP),
    .ANN_UDP_DST_PORT(ANN_UDP_DST_PORT),
    .ANN_TASK_MAGIC(ANN_TASK_MAGIC)
  ) unpack (
    .clk                     (clk),
    .reset                   (reset),
    .start                   (parse_start),
    .frame_overflow          (ingress_frame_overflow),
    .module_header_word      (ingress_module_header_word),
    .frame_len               (ingress_frame_len),
    .frame_word_count        (ingress_frame_word_count),
    .rd_addr                 (parse_rd_addr),
    .rd_word                 (parse_rd_word),
    .done                    (parse_done),
    .parse_status            (parse_status),
    .request_id              (parse_request_id),
    .task_type               (parse_task_type),
    .requested_feature_count (parse_requested_feature_count),
    .parsed_feature_count    (parse_parsed_feature_count),
    .dst_port_mask           (parse_dst_port_mask),
    .src_port                (parse_src_port),
    .feature_wr_en           (parse_feature_wr_en),
    .feature_wr_addr         (parse_feature_wr_addr),
    .feature_wr_data         (parse_feature_wr_data),
    .feature_wr_last         (parse_feature_wr_last)
  );

  ann_cpu_gpu_compute_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .FRAME_LEN_WIDTH(FRAME_LEN_WIDTH),
    .FRAME_WORD_ADDR_WIDTH(FRAME_WORD_ADDR_WIDTH),
    .FEATURE_WINDOW_WORDS(MAX_FEATURES)
  ) compute_core (
    .clk                (clk),
    .reset              (reset),
    .start              (compute_start),
    .module_header_word (ingress_module_header_word),
    .frame_len          (ingress_frame_len),
    .frame_word_count   (ingress_frame_word_count),
    .frame_rd_addr      (compute_rd_addr),
    .frame_rd_word      (compute_rd_word),
    .task_type          (parse_task_type),
    .feature_count      (parse_parsed_feature_count),
    .feature_wr_en      (parse_feature_wr_en),
    .feature_wr_addr    (parse_feature_wr_addr),
    .feature_wr_data    (parse_feature_wr_data),
    .sw_i_mem_addr      (sw_i_mem_addr),
    .sw_i_mem_wdata     (sw_i_mem_wdata),
    .sw_d_mem_addr      (sw_d_mem_addr),
    .sw_engine_ctrl     (sw_engine_ctrl),
    .sw_gpu_i_mem_addr  (sw_gpu_i_mem_addr),
    .sw_gpu_i_mem_wdata (sw_gpu_i_mem_wdata),
    .sw_gpu_w_mem_addr  (sw_gpu_w_mem_addr),
    .sw_gpu_w_mem_wdata_0(sw_gpu_w_mem_wdata_0),
    .sw_gpu_w_mem_wdata_1(sw_gpu_w_mem_wdata_1),
    .sw_gpu_ofmap_addr  (sw_gpu_ofmap_addr),
    .done               (compute_done),
    .result_status      (compute_result_status),
    .result_type        (compute_result_type),
    .result_len         (compute_result_len),
    .result_data_0      (compute_result_data_0),
    .result_data_1      (compute_result_data_1),
    .hw_gpu_ofmap_data_0(hw_gpu_ofmap_data_0),
    .hw_gpu_ofmap_data_1(hw_gpu_ofmap_data_1),
    .hw_cpu_i_mem_word_out(hw_cpu_i_mem_word_out),
    .hw_cpu_d_mem_word_out_0(hw_cpu_d_mem_word_out_0),
    .hw_cpu_d_mem_word_out_1(hw_cpu_d_mem_word_out_1),
    .hw_engine_status   (hw_engine_status)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state               <= ST_WAIT_FRAME;
      drain_word_idx      <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      drain_rd_addr       <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
      active_request_id   <= 16'd0;
    end
    else begin
      case (state)
        ST_WAIT_FRAME: begin
          drain_word_idx <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
          drain_rd_addr  <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
          if (ingress_frame_valid)
            state <= ST_PARSE_START;
        end

        ST_PARSE_START: begin
          state <= ST_PARSE_WAIT;
        end

        ST_PARSE_WAIT: begin
          if (parse_done) begin
            active_request_id <= parse_request_id;
            if (parse_nonfatal) begin
              state <= ST_COMPUTE_START;
            end
            else begin
              state <= ST_DRAIN_HDR;
            end
          end
        end

        ST_COMPUTE_START: begin
          state <= ST_COMPUTE_WAIT;
        end

        ST_COMPUTE_WAIT: begin
          if (compute_done) begin
            state <= ST_DRAIN_HDR;
          end
        end

        ST_DRAIN_HDR: begin
          if (out_rdy) begin
            if (ingress_frame_word_count == {(FRAME_WORD_ADDR_WIDTH+1){1'b0}}) begin
              state <= ST_WAIT_FRAME;
            end
            else begin
              drain_word_idx <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
              drain_rd_addr  <= {FRAME_WORD_ADDR_WIDTH{1'b0}};
              state          <= ST_DRAIN_PRIME;
            end
          end
        end

        ST_DRAIN_PRIME: begin
          state <= ST_DRAIN_WORD;
        end

        ST_DRAIN_WORD: begin
          if (out_rdy) begin
            if (drain_word_idx == ingress_frame_word_count[FRAME_WORD_ADDR_WIDTH-1:0] - 1'b1) begin
              state <= ST_WAIT_FRAME;
            end
            else begin
              drain_word_idx <= drain_word_idx + 1'b1;
              drain_rd_addr  <= drain_rd_addr + 1'b1;
              state          <= ST_DRAIN_PRIME;
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
