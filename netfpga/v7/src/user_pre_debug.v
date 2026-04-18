`timescale 1ns/1ps

`ifndef USER_PRE_DEBUG_BLOCK_ADDR
`define USER_PRE_DEBUG_BLOCK_ADDR 10'h156
`endif

`ifndef USER_PRE_DEBUG_REG_ADDR_WIDTH
`define USER_PRE_DEBUG_REG_ADDR_WIDTH 6
`endif

module user_pre_debug #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter UDP_REG_SRC_WIDTH = 2
) (
  input  [DATA_WIDTH-1:0]           mon_data,
  input  [CTRL_WIDTH-1:0]           mon_ctrl,
  input                             mon_wr,
  input                             mon_rdy,

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

  input                             clk,
  input                             reset
);

  localparam integer NUM_DEBUG_SW_REGS = 1;
  localparam integer NUM_DEBUG_HW_REGS = 6;
  localparam integer SNAPSHOT_WORDS = 2;

  wire [31:0] debug_ctrl;
  reg  [31:0] debug_ctrl_prev;
  wire        debug_clear_pulse;
  wire        mon_accept;

  reg         snapshot_valid_reg;
  reg         capture_active_reg;
  reg         capture_done_reg;
  reg  [15:0] pkt_seen_count_reg;
  reg  [7:0]  word_count_reg;
  reg         capture_index_reg;
  reg  [7:0]  ctrl_word0_reg;
  reg  [7:0]  ctrl_word1_reg;
  reg  [63:0] data_word0_reg;
  reg  [63:0] data_word1_reg;

  wire [NUM_DEBUG_SW_REGS*32-1:0] debug_software_regs;
  wire [NUM_DEBUG_HW_REGS*32-1:0] debug_hardware_regs;

  assign debug_ctrl = debug_software_regs[31:0];
  assign debug_clear_pulse = debug_ctrl[0] && !debug_ctrl_prev[0];
  assign mon_accept = mon_wr && mon_rdy;

  assign debug_hardware_regs = {
    data_word1_reg[31:0],
    data_word1_reg[63:32],
    data_word0_reg[31:0],
    data_word0_reg[63:32],
    {16'h0000, ctrl_word1_reg, ctrl_word0_reg},
    {pkt_seen_count_reg, word_count_reg, 5'b0, capture_done_reg, capture_active_reg, snapshot_valid_reg}
  };

  generic_regs #(
    .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
    .TAG               (`USER_PRE_DEBUG_BLOCK_ADDR),
    .REG_ADDR_WIDTH    (`USER_PRE_DEBUG_REG_ADDR_WIDTH),
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

  task store_snapshot_word;
    input                   word_index;
    input [DATA_WIDTH-1:0]  word_data;
    input [CTRL_WIDTH-1:0]  word_ctrl;
    begin
      case (word_index)
        1'b0: begin
          data_word0_reg <= word_data;
          ctrl_word0_reg <= word_ctrl;
        end
        default: begin
          data_word1_reg <= word_data;
          ctrl_word1_reg <= word_ctrl;
        end
      endcase
    end
  endtask

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      debug_ctrl_prev    <= 32'h0000_0000;
      snapshot_valid_reg <= 1'b0;
      capture_active_reg <= 1'b0;
      capture_done_reg   <= 1'b0;
      pkt_seen_count_reg <= 16'h0000;
      word_count_reg     <= 8'h00;
      capture_index_reg  <= 1'b0;
      ctrl_word0_reg     <= 8'h00;
      ctrl_word1_reg     <= 8'h00;
      data_word0_reg     <= 64'h0000_0000_0000_0000;
      data_word1_reg     <= 64'h0000_0000_0000_0000;
    end
    else begin
      debug_ctrl_prev <= debug_ctrl;

      if (debug_clear_pulse) begin
        snapshot_valid_reg <= 1'b0;
        capture_active_reg <= 1'b0;
        capture_done_reg   <= 1'b0;
        pkt_seen_count_reg <= 16'h0000;
        word_count_reg     <= 8'h00;
        capture_index_reg  <= 1'b0;
        ctrl_word0_reg     <= 8'h00;
        ctrl_word1_reg     <= 8'h00;
        data_word0_reg     <= 64'h0000_0000_0000_0000;
        data_word1_reg     <= 64'h0000_0000_0000_0000;
      end
      else if (mon_accept && !snapshot_valid_reg) begin
        if (!capture_active_reg) begin
          if (mon_ctrl != {CTRL_WIDTH{1'b0}}) begin
            pkt_seen_count_reg <= pkt_seen_count_reg + 16'd1;
            capture_active_reg <= 1'b1;
            capture_done_reg   <= 1'b0;
            capture_index_reg  <= 1'b1;
            word_count_reg     <= 8'd1;
            store_snapshot_word(1'b0, mon_data, mon_ctrl);

            if (mon_ctrl != {CTRL_WIDTH{1'b1}}) begin
              snapshot_valid_reg <= 1'b1;
              capture_active_reg <= 1'b0;
              capture_done_reg   <= 1'b1;
              capture_index_reg  <= 1'b0;
            end
          end
        end
        else begin
          store_snapshot_word(capture_index_reg, mon_data, mon_ctrl);
          word_count_reg <= {7'b0, capture_index_reg} + 8'd1;

          if ((capture_index_reg == (SNAPSHOT_WORDS - 1)) ||
              (mon_ctrl != {CTRL_WIDTH{1'b0}})) begin
            snapshot_valid_reg <= 1'b1;
            capture_active_reg <= 1'b0;
            capture_done_reg   <= 1'b1;
            capture_index_reg  <= 1'b0;
          end
          else begin
            capture_index_reg <= capture_index_reg + 1'b1;
          end
        end
      end
    end
  end

endmodule
