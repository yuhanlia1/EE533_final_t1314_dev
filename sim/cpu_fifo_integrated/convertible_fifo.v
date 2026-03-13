module convertible_fifo #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH/8,
  parameter UDP_REG_SRC_WIDTH = 2,
  parameter FIFO_ADDR_WIDTH = 8
)(
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
  output                            fifo_full,
  output                            pkt_ready,
  input                             proc_done,
  input                             proc_mem_en,
  input                             proc_mem_we,
  input  [FIFO_ADDR_WIDTH-1:0]      proc_mem_addr,
  input  [DATA_WIDTH-1:0]           proc_mem_wdata,
  output [DATA_WIDTH-1:0]           proc_mem_rdata,
  output                            proc_mem_rvalid,
  output                            proc_active,
  input                             reset,
  input                             clk
);
  localparam FIFO_WORD_WIDTH = DATA_WIDTH + CTRL_WIDTH;

  reg hold_valid;
  reg [DATA_WIDTH-1:0] hold_data;
  reg [CTRL_WIDTH-1:0] hold_ctrl;
  reg hold_first;

  wire [FIFO_WORD_WIDTH-1:0] dropfifo_out_fifo;
  wire dropfifo_write_ready;
  wire can_flush_hold;
  wire accept_in;
  wire incoming_first;

  reg fifowrite;
  reg firstword;
  reg lastword;
  reg [FIFO_WORD_WIDTH-1:0] write_word;

  assign out_ctrl = dropfifo_out_fifo[FIFO_WORD_WIDTH-1:DATA_WIDTH];
  assign out_data = dropfifo_out_fifo[DATA_WIDTH-1:0];

  assign reg_req_out      = reg_req_in;
  assign reg_ack_out      = reg_ack_in;
  assign reg_rd_wr_L_out  = reg_rd_wr_L_in;
  assign reg_addr_out     = reg_addr_in;
  assign reg_data_out     = reg_data_in;
  assign reg_src_out      = reg_src_in;

  assign incoming_first = (in_ctrl != {CTRL_WIDTH{1'b0}});
  assign can_flush_hold = hold_valid && dropfifo_write_ready;
  assign in_rdy = !fifo_full && (!hold_valid || can_flush_hold);
  assign accept_in = in_wr && in_rdy;

  dropfifo #(
    .FIFO_WORD_WIDTH(FIFO_WORD_WIDTH), 
    .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH), 
    .PROC_DATA_WIDTH(DATA_WIDTH)) 
  drop_fifo (
    .clk(clk), 
    .rst(reset), 
    .drop_pkt(1'b0), 
    .fiforead(out_rdy), 
    .fifowrite(fifowrite), 
    .firstword(firstword), 
    .in_fifo(write_word), 
    .lastword(lastword),
    .proc_done(proc_done), 
    .proc_mem_en(proc_mem_en), 
    .proc_mem_we(proc_mem_we), 
    .proc_mem_addr(proc_mem_addr), 
    .proc_mem_wdata(proc_mem_wdata), 
    .proc_mem_rdata(proc_mem_rdata), 
    .proc_mem_rvalid(proc_mem_rvalid), 
    .proc_active(proc_active),
    .out_fifo(dropfifo_out_fifo), 
    .valid_data(out_wr), 
    .fifo_full(fifo_full), 
    .pkt_ready(pkt_ready), 
    .write_ready(dropfifo_write_ready)
  );

  always @(*) begin
    fifowrite = 1'b0;
    firstword = 1'b0;
    lastword  = 1'b0;
    write_word = {hold_ctrl, hold_data};
    if (can_flush_hold) begin
      fifowrite = 1'b1;
      firstword = hold_first;
      if (accept_in) lastword = incoming_first;
      else lastword = 1'b1;
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      hold_valid <= 1'b0;
      hold_data  <= {DATA_WIDTH{1'b0}};
      hold_ctrl  <= {CTRL_WIDTH{1'b0}};
      hold_first <= 1'b0;
    end else begin
      if (can_flush_hold) begin
        if (accept_in) begin
          hold_valid <= 1'b1;
          hold_data  <= in_data;
          hold_ctrl  <= in_ctrl;
          hold_first <= incoming_first;
        end else begin
          hold_valid <= 1'b0;
          hold_data  <= hold_data;
          hold_ctrl  <= hold_ctrl;
          hold_first <= 1'b0;
        end
      end else if (!hold_valid && accept_in) begin
        hold_valid <= 1'b1;
        hold_data  <= in_data;
        hold_ctrl  <= in_ctrl;
        hold_first <= incoming_first;
      end
    end
  end
endmodule