`timescale 1ns/1ps

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

  input                             reset,
  input                             clk
);

  localparam FIFO_WORD_WIDTH = DATA_WIDTH + CTRL_WIDTH;

  localparam START   = 2'b00;
  localparam HEADER  = 2'b01;
  localparam PAYLOAD = 2'b10;

  reg [1:0] state, state_next;
  reg [2:0] header_counter, header_counter_next;

  wire [DATA_WIDTH-1:0] in_fifo_data;
  wire [CTRL_WIDTH-1:0] in_fifo_ctrl;
  wire                  in_fifo_full;
  wire                  in_fifo_nearly_full;
  wire                  in_fifo_prog_full;
  wire                  in_fifo_empty;

  reg                   in_fifo_rd_en;
  reg                   fifowrite;
  reg                   firstword;
  reg                   lastword;

  wire                  dropfifo_write_ready;
  wire [FIFO_WORD_WIDTH-1:0] dropfifo_out_fifo;

  assign out_ctrl = dropfifo_out_fifo[FIFO_WORD_WIDTH-1:DATA_WIDTH];
  assign out_data = dropfifo_out_fifo[DATA_WIDTH-1:0];

  assign in_rdy = !in_fifo_nearly_full && !fifo_full;

  assign reg_req_out      = reg_req_in;
  assign reg_ack_out      = reg_ack_in;
  assign reg_rd_wr_L_out  = reg_rd_wr_L_in;
  assign reg_addr_out     = reg_addr_in;
  assign reg_data_out     = reg_data_in;
  assign reg_src_out      = reg_src_in;

  fallthrough_small_fifo #(
    .WIDTH(FIFO_WORD_WIDTH),
    .MAX_DEPTH_BITS(2)
  ) input_fifo (
    .din         ({in_ctrl, in_data}),
    .wr_en       (in_wr),
    .rd_en       (in_fifo_rd_en),
    .dout        ({in_fifo_ctrl, in_fifo_data}),
    .full        (in_fifo_full),
    .nearly_full (in_fifo_nearly_full),
    .prog_full   (in_fifo_prog_full),
    .empty       (in_fifo_empty),
    .reset       (reset),
    .clk         (clk)
  );

  dropfifo #(
    .FIFO_WORD_WIDTH(FIFO_WORD_WIDTH),
    .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) drop_fifo (
    .clk         (clk),
    .rst         (reset),
    .drop_pkt    (1'b0),            // No dropping in this design
    .fiforead    (out_rdy),
    .fifowrite   (fifowrite),
    .firstword   (firstword),
    .in_fifo     ({in_fifo_ctrl, in_fifo_data}),
    .lastword    (lastword),
    .out_fifo    (dropfifo_out_fifo),
    .valid_data  (out_wr),
    .fifo_full   (fifo_full),
    .pkt_ready   (pkt_ready),
    .write_ready (dropfifo_write_ready)
  );

  always @(posedge clk) begin
    if (reset) begin
      state <= START;
      header_counter <= 3'b000;
    end
    else begin
      state <= state_next;
      header_counter <= header_counter_next;
    end
  end

  always @(*) begin
    state_next = state;
    case (state)
      START: begin
        if (!in_fifo_empty && dropfifo_write_ready && (in_fifo_ctrl != 0))
          state_next = HEADER;
      end

      HEADER: begin
        if (!in_fifo_empty && dropfifo_write_ready) begin
          if ((in_fifo_ctrl == 0) && (header_counter == 3'd2))
            state_next = PAYLOAD;
        end
      end

      PAYLOAD: begin
        if (!in_fifo_empty && dropfifo_write_ready && (in_fifo_ctrl != 0))
          state_next = START;
      end

      default: begin
        state_next = START;
      end
    endcase
  end

  always @(*) begin
    header_counter_next = header_counter;
    case (state)
      START: begin
        header_counter_next = 3'b000;
      end

      HEADER: begin
        if (!in_fifo_empty && dropfifo_write_ready) begin
          if (in_fifo_ctrl == 0) begin
            if (header_counter == 3'd2)
              header_counter_next = 3'b000;
            else
              header_counter_next = header_counter + 3'd1;
          end
        end
      end

      PAYLOAD: begin
        if (!in_fifo_empty && dropfifo_write_ready && (in_fifo_ctrl != 0))
          header_counter_next = 3'b000;
      end

      default: begin
        header_counter_next = 3'b000;
      end
    endcase
  end

  always @(*) begin
    in_fifo_rd_en = 1'b0;
    fifowrite     = 1'b0;
    firstword     = 1'b0;
    lastword      = 1'b0;

    case (state)
      START: begin
        if (!in_fifo_empty && dropfifo_write_ready && (in_fifo_ctrl != 0)) begin
          in_fifo_rd_en = 1'b1;
          fifowrite     = 1'b1;
          firstword     = 1'b1;
        end
      end

      HEADER: begin
        if (!in_fifo_empty && dropfifo_write_ready) begin
          in_fifo_rd_en = 1'b1;
          fifowrite     = 1'b1;
        end
      end

      PAYLOAD: begin
        if (!in_fifo_empty && dropfifo_write_ready) begin
          in_fifo_rd_en = 1'b1;
          fifowrite     = 1'b1;
          if (in_fifo_ctrl != 0)
            lastword = 1'b1;
        end
      end

      default: begin
        in_fifo_rd_en = 1'b0;
        fifowrite     = 1'b0;
        firstword     = 1'b0;
        lastword      = 1'b0;
      end
    endcase
  end

endmodule