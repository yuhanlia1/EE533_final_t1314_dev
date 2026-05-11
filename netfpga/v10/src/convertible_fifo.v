`timescale 1ns/1ps

module convertible_fifo #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter FIFO_ADDR_WIDTH = 8
) (
  input  [DATA_WIDTH-1:0]           in_data,
  input  [CTRL_WIDTH-1:0]           in_ctrl,
  input                             in_wr,
  output                            in_rdy,

  output [DATA_WIDTH-1:0]           out_data,
  output [CTRL_WIDTH-1:0]           out_ctrl,
  output                            out_wr,
  input                             out_rdy,

  input                             reset,
  input                             clk
);

  localparam FIFO_WORD_WIDTH = DATA_WIDTH + CTRL_WIDTH;
  localparam FIFO_DEPTH = 2 ** FIFO_ADDR_WIDTH;

  localparam S_IDLE  = 2'b00;
  localparam S_WRITE = 2'b01;
  localparam S_DRAIN = 2'b10;

  reg [1:0] state;

  reg [FIFO_ADDR_WIDTH:0] write_count;
  reg [FIFO_ADDR_WIDTH:0] pkt_len;
  reg [FIFO_ADDR_WIDTH:0] read_count;
  reg                     rd_pending;

  reg [FIFO_WORD_WIDTH-1:0] out_word;
  reg                       out_valid;

  wire [FIFO_WORD_WIDTH-1:0] bram_douta;
  wire [FIFO_WORD_WIDTH-1:0] bram_doutb;

  wire accept_word;
  wire write_enable;
  wire [FIFO_ADDR_WIDTH-1:0] write_addr;
  wire [FIFO_WORD_WIDTH-1:0] write_word;
  wire issue_read;
  wire drain_done;

  assign accept_word = in_wr && in_rdy;
  assign write_enable = ((state == S_IDLE) && accept_word && (in_ctrl != 0)) ||
                        ((state == S_WRITE) && accept_word);
  assign write_addr = (state == S_IDLE) ? {FIFO_ADDR_WIDTH{1'b0}} :
                      write_count[FIFO_ADDR_WIDTH-1:0];
  assign write_word = {in_ctrl, in_data};

  assign issue_read = (state == S_DRAIN) &&
                      !rd_pending &&
                      !out_valid &&
                      (read_count < pkt_len);

  assign drain_done = (state == S_DRAIN) &&
                      (read_count == pkt_len) &&
                      !rd_pending &&
                      !out_valid;

  assign in_rdy = (state != S_DRAIN) && (write_count < FIFO_DEPTH);
  assign out_ctrl = out_word[FIFO_WORD_WIDTH-1:DATA_WIDTH];
  assign out_data = out_word[DATA_WIDTH-1:0];
  assign out_wr = out_valid;

  fifo_bram #(
    .DATA_WIDTH(FIFO_WORD_WIDTH),
    .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_bram (
    .clka  (clk),
    .wea   (write_enable),
    .addra (write_addr),
    .dina  (write_word),
    .douta (bram_douta),
    .clkb  (clk),
    .web   (1'b0),
    .addrb (read_count[FIFO_ADDR_WIDTH-1:0]),
    .dinb  ({FIFO_WORD_WIDTH{1'b0}}),
    .doutb (bram_doutb)
  );

  always @(posedge clk) begin
    if (reset) begin
      state       <= S_IDLE;
      write_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      pkt_len     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      read_count  <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      rd_pending  <= 1'b0;
      out_word    <= {FIFO_WORD_WIDTH{1'b0}};
      out_valid   <= 1'b0;
    end
    else begin
      if (out_valid && out_rdy)
        out_valid <= 1'b0;

      if (rd_pending) begin
        out_word   <= bram_doutb;
        out_valid  <= 1'b1;
        rd_pending <= 1'b0;
      end

      case (state)
        S_IDLE: begin
          write_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          pkt_len     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          read_count  <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_pending  <= 1'b0;
          out_valid   <= 1'b0;

          if (accept_word && (in_ctrl != 0)) begin
            state       <= S_WRITE;
            write_count <= {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
          end
        end

        S_WRITE: begin
          if (accept_word) begin
            if (in_ctrl != 0) begin
              state      <= S_DRAIN;
              pkt_len    <= write_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
              read_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
              rd_pending <= 1'b0;
              out_valid  <= 1'b0;
            end
            else begin
              write_count <= write_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
            end
          end
        end

        S_DRAIN: begin
          if (issue_read) begin
            read_count <= read_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
            rd_pending <= 1'b1;
          end

          if (drain_done)
            state <= S_IDLE;
        end

        default: begin
          state       <= S_IDLE;
          write_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          pkt_len     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          read_count  <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_pending  <= 1'b0;
          out_word    <= {FIFO_WORD_WIDTH{1'b0}};
          out_valid   <= 1'b0;
        end
      endcase
    end
  end

endmodule
