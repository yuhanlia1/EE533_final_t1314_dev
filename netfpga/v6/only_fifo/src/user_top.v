`timescale 1ns/1ps

`ifndef USER_TOP_BLOCK_ADDR
`define USER_TOP_BLOCK_ADDR 10'h155
`endif

`ifndef USER_TOP_REG_ADDR_WIDTH
`define USER_TOP_REG_ADDR_WIDTH 6
`endif

module user_top #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter UDP_REG_SRC_WIDTH = 2,
  parameter ACTION_WIDTH = 2
) (
  input  [DATA_WIDTH-1:0]           in_data,
  input  [CTRL_WIDTH-1:0]           in_ctrl,
  input                             in_wr,
  output                            in_rdy,

  output [DATA_WIDTH-1:0]           out_data,
  output [CTRL_WIDTH-1:0]           out_ctrl,
  output                            out_wr,
  input                             out_rdy,

  input                             reg_req_in,
  input                             reg_ack_in,
  input                             reg_rd_wr_L_in,
  input  [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_in,
  input  [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
  input  [UDP_REG_SRC_WIDTH-1:0]    reg_src_in,

  output                            reg_req_out,
  output                            reg_ack_out,
  output                            reg_rd_wr_L_out,
  output [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_out,
  output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
  output [UDP_REG_SRC_WIDTH-1:0]    reg_src_out,

  input wire                        clk,
  input wire                        reset
);

  localparam integer NUM_DEBUG_SW_REGS = 1;
  localparam integer NUM_DEBUG_HW_REGS = 11;
  localparam [ACTION_WIDTH-1:0] ACTION_BYPASS = 2'b00;
  localparam [ACTION_WIDTH-1:0] ACTION_OFFLOAD = 2'b10;

  wire [31:0] debug_ctrl;
  reg  [31:0] debug_ctrl_prev;
  reg  [31:0] debug_last_action_reg;
  reg  [31:0] debug_offload_match_count_reg;
  reg  [31:0] debug_rewrite_fire_count_reg;
  reg  [31:0] debug_last_udp_dst_port_reg;
  reg  [31:0] debug_last_payload_magic_reg;
  reg  [63:0] debug_last_header_word5_reg;
  reg  [63:0] debug_last_header_word6_reg;
  reg  [63:0] debug_last_rewrite_word_reg;
  reg         debug_snapshot_locked_reg;
  reg         debug_wait_for_rewrite_reg;

  wire [NUM_DEBUG_SW_REGS*32-1:0] debug_software_regs;
  wire [NUM_DEBUG_HW_REGS*32-1:0] debug_hardware_regs;

  wire [DATA_WIDTH-1:0] front_buf_out_data;
  wire [CTRL_WIDTH-1:0] front_buf_out_ctrl;
  wire                  front_buf_out_wr;
  wire                  front_buf_out_rdy;

  wire [DATA_WIDTH-1:0] action_out_data;
  wire [CTRL_WIDTH-1:0] action_out_ctrl;
  wire                  action_out_wr;
  wire                  action_out_rdy;
  wire [ACTION_WIDTH-1:0] selector_action;
  wire                    selector_debug_classify_pulse;
  wire                    selector_debug_offload_match_pulse;
  wire                    selector_debug_rewrite_pulse;
  wire [ACTION_WIDTH-1:0] selector_debug_last_action;
  wire [15:0]             selector_debug_last_udp_dst_port;
  wire [15:0]             selector_debug_last_payload_magic;
  wire [63:0]             selector_debug_last_header_word5;
  wire [63:0]             selector_debug_last_header_word6;
  wire [63:0]             selector_debug_last_rewrite_word;

  wire                    debug_clear_pulse;

  assign debug_ctrl = debug_software_regs[31:0];
  assign debug_clear_pulse = debug_ctrl[0] && !debug_ctrl_prev[0];

  assign debug_hardware_regs = {
    debug_last_rewrite_word_reg[31:0],
    debug_last_rewrite_word_reg[63:32],
    debug_last_header_word6_reg[31:0],
    debug_last_header_word6_reg[63:32],
    debug_last_header_word5_reg[31:0],
    debug_last_header_word5_reg[63:32],
    debug_last_payload_magic_reg,
    debug_last_udp_dst_port_reg,
    debug_rewrite_fire_count_reg,
    debug_offload_match_count_reg,
    debug_last_action_reg
  };

  generic_regs #(
    .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
    .TAG               (`USER_TOP_BLOCK_ADDR),
    .REG_ADDR_WIDTH    (`USER_TOP_REG_ADDR_WIDTH),
    .NUM_COUNTERS      (0),
    .NUM_SOFTWARE_REGS (NUM_DEBUG_SW_REGS),
    .NUM_HARDWARE_REGS (NUM_DEBUG_HW_REGS)
  ) u_debug_regs (
    .reg_req_in        (reg_req_in),
    .reg_ack_in        (reg_ack_in),
    .reg_rd_wr_L_in    (reg_rd_wr_L_in),
    .reg_addr_in       (reg_addr_in),
    .reg_data_in       (reg_data_in),
    .reg_src_in        (reg_src_in),
    .reg_req_out       (reg_req_out),
    .reg_ack_out       (reg_ack_out),
    .reg_rd_wr_L_out   (reg_rd_wr_L_out),
    .reg_addr_out      (reg_addr_out),
    .reg_data_out      (reg_data_out),
    .reg_src_out       (reg_src_out),
    .counter_updates   (),
    .counter_decrement (),
    .software_regs     (debug_software_regs),
    .hardware_regs     (debug_hardware_regs),
    .clk               (clk),
    .reset             (reset)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) u_front_buffer (
    .in_data        (in_data),
    .in_ctrl        (in_ctrl),
    .in_wr          (in_wr),
    .in_rdy         (in_rdy),

    .out_data       (front_buf_out_data),
    .out_ctrl       (front_buf_out_ctrl),
    .out_wr         (front_buf_out_wr),
    .out_rdy        (front_buf_out_rdy),

    .reset          (reset),
    .clk            (clk)
  );

  packet_action_selector #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ACTION_WIDTH(ACTION_WIDTH)
  ) u_action_selector (
    .in_data                  (front_buf_out_data),
    .in_ctrl                  (front_buf_out_ctrl),
    .in_wr                    (front_buf_out_wr),
    .in_rdy                   (front_buf_out_rdy),

    .out_data                 (action_out_data),
    .out_ctrl                 (action_out_ctrl),
    .out_wr                   (action_out_wr),
    .out_rdy                  (action_out_rdy),
    .out_action               (selector_action),
    .debug_classify_pulse     (selector_debug_classify_pulse),
    .debug_offload_match_pulse(selector_debug_offload_match_pulse),
    .debug_rewrite_pulse      (selector_debug_rewrite_pulse),
    .debug_last_action        (selector_debug_last_action),
    .debug_last_udp_dst_port  (selector_debug_last_udp_dst_port),
    .debug_last_payload_magic (selector_debug_last_payload_magic),
    .debug_last_header_word5  (selector_debug_last_header_word5),
    .debug_last_header_word6  (selector_debug_last_header_word6),
    .debug_last_rewrite_word  (selector_debug_last_rewrite_word),

    .reset                    (reset),
    .clk                      (clk)
  );

  convertible_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH)
  ) u_backend_buffer (
    .in_data        (action_out_data),
    .in_ctrl        (action_out_ctrl),
    .in_wr          (action_out_wr),
    .in_rdy         (action_out_rdy),

    .out_data       (out_data),
    .out_ctrl       (out_ctrl),
    .out_wr         (out_wr),
    .out_rdy        (out_rdy),

    .reset          (reset),
    .clk            (clk)
  );

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      debug_ctrl_prev <= 32'h0000_0000;
      debug_last_action_reg <= 32'h0000_0000;
      debug_offload_match_count_reg <= 32'h0000_0000;
      debug_rewrite_fire_count_reg <= 32'h0000_0000;
      debug_last_udp_dst_port_reg <= 32'h0000_0000;
      debug_last_payload_magic_reg <= 32'h0000_0000;
      debug_last_header_word5_reg <= 64'h0000_0000_0000_0000;
      debug_last_header_word6_reg <= 64'h0000_0000_0000_0000;
      debug_last_rewrite_word_reg <= 64'h0000_0000_0000_0000;
      debug_snapshot_locked_reg <= 1'b0;
      debug_wait_for_rewrite_reg <= 1'b0;
    end
    else begin
      debug_ctrl_prev <= debug_ctrl;

      if (debug_clear_pulse) begin
        debug_last_action_reg <= 32'h0000_0000;
        debug_offload_match_count_reg <= 32'h0000_0000;
        debug_rewrite_fire_count_reg <= 32'h0000_0000;
        debug_last_udp_dst_port_reg <= 32'h0000_0000;
        debug_last_payload_magic_reg <= 32'h0000_0000;
        debug_last_header_word5_reg <= 64'h0000_0000_0000_0000;
        debug_last_header_word6_reg <= 64'h0000_0000_0000_0000;
        debug_last_rewrite_word_reg <= 64'h0000_0000_0000_0000;
        debug_snapshot_locked_reg <= 1'b0;
        debug_wait_for_rewrite_reg <= 1'b0;
      end
      else begin
        if (selector_debug_classify_pulse && !debug_snapshot_locked_reg && !debug_wait_for_rewrite_reg) begin
          debug_last_action_reg <= {{(32-ACTION_WIDTH){1'b0}}, selector_debug_last_action};
          debug_last_udp_dst_port_reg <= {16'h0000, selector_debug_last_udp_dst_port};
          debug_last_payload_magic_reg <= {16'h0000, selector_debug_last_payload_magic};
          debug_last_header_word5_reg <= selector_debug_last_header_word5;
          debug_last_header_word6_reg <= selector_debug_last_header_word6;

          if (selector_debug_last_action == ACTION_OFFLOAD) begin
            if (selector_debug_offload_match_pulse)
              debug_offload_match_count_reg <= debug_offload_match_count_reg + 32'd1;
            debug_wait_for_rewrite_reg <= 1'b1;
          end
          else begin
            debug_snapshot_locked_reg <= 1'b1;
          end
        end

        if (selector_debug_rewrite_pulse && debug_wait_for_rewrite_reg) begin
          debug_rewrite_fire_count_reg <= debug_rewrite_fire_count_reg + 32'd1;
          debug_last_rewrite_word_reg <= selector_debug_last_rewrite_word;
          debug_wait_for_rewrite_reg <= 1'b0;
          debug_snapshot_locked_reg <= 1'b1;
        end
      end
    end
  end

endmodule
