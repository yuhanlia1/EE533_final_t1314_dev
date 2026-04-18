`timescale 1ns/1ps

module ann_task_ingress #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8,
  parameter MAX_FRAME_BYTES = 2048,
  parameter FRAME_LEN_WIDTH = 12,
  parameter FRAME_WORD_ADDR_WIDTH = 8
) (
  input  [DATA_WIDTH-1:0]                    in_data,
  input  [CTRL_WIDTH-1:0]                    in_ctrl,
  input                                      in_wr,
  output                                     in_rdy,

  output                                     frame_valid,
  input                                      frame_taken,
  output reg [DATA_WIDTH-1:0]                module_header_word,
  output reg [FRAME_LEN_WIDTH-1:0]           frame_len,
  output reg [FRAME_WORD_ADDR_WIDTH:0]       frame_word_count,
  output reg                                 frame_overflow,

  input  [FRAME_WORD_ADDR_WIDTH-1:0]         parser_rd_addr,
  output [DATA_WIDTH+CTRL_WIDTH-1:0]         parser_rd_word,
  input                                      drain_rd_en,
  input  [FRAME_WORD_ADDR_WIDTH-1:0]         drain_rd_addr,
  output [DATA_WIDTH+CTRL_WIDTH-1:0]         drain_rd_word,
  input  [FRAME_WORD_ADDR_WIDTH-1:0]         compute_rd_addr,
  output [DATA_WIDTH+CTRL_WIDTH-1:0]         compute_rd_word,

  input                                      clk,
  input                                      reset
);

  localparam integer MAX_FRAME_WORDS = (MAX_FRAME_BYTES + CTRL_WIDTH - 1) / CTRL_WIDTH;
  localparam [FRAME_LEN_WIDTH-1:0] MAX_FRAME_LEN = MAX_FRAME_BYTES[FRAME_LEN_WIDTH-1:0];
  localparam [1:0] S_IDLE     = 2'd0;
  localparam [1:0] S_CAPTURE  = 2'd1;
  localparam [1:0] S_FINALIZE = 2'd2;
  localparam [1:0] S_HOLD     = 2'd3;

  reg [1:0] state;
  reg [15:0] packet_word_idx;
  reg [CTRL_WIDTH-1:0] last_frame_ctrl;

  reg                               bram_wea;
  reg [FRAME_WORD_ADDR_WIDTH-1:0]   bram_addra;
  reg [DATA_WIDTH+CTRL_WIDTH-1:0]   bram_dina;
  wire [DATA_WIDTH+CTRL_WIDTH-1:0]  bram_douta;
  wire [DATA_WIDTH+CTRL_WIDTH-1:0]  bram_doutb;

  wire accept_word;
  wire store_frame_word;
  wire [FRAME_WORD_ADDR_WIDTH:0] next_frame_word_count;
  wire [CTRL_WIDTH-1:0] last_valid_bytes;
  wire [FRAME_LEN_WIDTH:0] final_frame_len_full;

  function [CTRL_WIDTH-1:0] ctrl_valid_bytes;
    input [CTRL_WIDTH-1:0] ctrl_word;
    begin
      case (ctrl_word)
        8'h80: ctrl_valid_bytes = 1;
        8'h40: ctrl_valid_bytes = 2;
        8'h20: ctrl_valid_bytes = 3;
        8'h10: ctrl_valid_bytes = 4;
        8'h08: ctrl_valid_bytes = 5;
        8'h04: ctrl_valid_bytes = 6;
        8'h02: ctrl_valid_bytes = 7;
        8'h01: ctrl_valid_bytes = 8;
        default: ctrl_valid_bytes = 8;
      endcase
    end
  endfunction

  assign in_rdy                = (state == S_IDLE) || (state == S_CAPTURE);
  assign frame_valid           = (state == S_HOLD);
  assign accept_word           = in_wr && in_rdy;
  assign store_frame_word      = accept_word && (packet_word_idx != 16'd0) &&
                                 (frame_word_count < MAX_FRAME_WORDS);
  assign next_frame_word_count = frame_word_count + {{FRAME_WORD_ADDR_WIDTH{1'b0}}, 1'b1};
  assign last_valid_bytes      = ctrl_valid_bytes(last_frame_ctrl);
  assign final_frame_len_full  = ((frame_word_count - {{FRAME_WORD_ADDR_WIDTH{1'b0}}, 1'b1}) << 3) + last_valid_bytes;

  assign parser_rd_word  = bram_douta;
  assign drain_rd_word   = bram_douta;
  assign compute_rd_word = bram_doutb;

  fifo_bram #(
    .DATA_WIDTH(DATA_WIDTH + CTRL_WIDTH),
    .ADDR_WIDTH(FRAME_WORD_ADDR_WIDTH)
  ) packet_buf (
    .clka  (clk),
    .wea   (bram_wea),
    .addra (bram_addra),
    .dina  (bram_dina),
    .douta (bram_douta),
    .clkb  (clk),
    .web   (1'b0),
    .addrb (compute_rd_addr),
    .dinb  ({(DATA_WIDTH + CTRL_WIDTH){1'b0}}),
    .doutb (bram_doutb)
  );

  always @(*) begin
    bram_wea   = 1'b0;
    bram_addra = parser_rd_addr;
    bram_dina  = {(DATA_WIDTH + CTRL_WIDTH){1'b0}};

    if (store_frame_word) begin
      bram_wea   = 1'b1;
      bram_addra = frame_word_count[FRAME_WORD_ADDR_WIDTH-1:0];
      bram_dina  = {in_ctrl, in_data};
    end
    else if (drain_rd_en) begin
      bram_addra = drain_rd_addr;
    end
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state              <= S_IDLE;
      packet_word_idx    <= 16'd0;
      module_header_word <= {DATA_WIDTH{1'b0}};
      frame_len          <= {FRAME_LEN_WIDTH{1'b0}};
      frame_word_count   <= {(FRAME_WORD_ADDR_WIDTH+1){1'b0}};
      frame_overflow     <= 1'b0;
      last_frame_ctrl    <= {CTRL_WIDTH{1'b0}};
    end
    else begin
      case (state)
        S_IDLE,
        S_CAPTURE: begin
          if (accept_word) begin
            if (packet_word_idx == 16'd0) begin
              module_header_word <= in_data;
              frame_len          <= {FRAME_LEN_WIDTH{1'b0}};
              frame_word_count   <= {(FRAME_WORD_ADDR_WIDTH+1){1'b0}};
              frame_overflow     <= 1'b0;
              last_frame_ctrl    <= {CTRL_WIDTH{1'b0}};
              packet_word_idx    <= 16'd1;
              state              <= S_CAPTURE;
            end
            else begin
              last_frame_ctrl <= in_ctrl;

              if (store_frame_word) begin
                frame_word_count <= next_frame_word_count;
              end
              else begin
                frame_overflow <= 1'b1;
              end

              if (in_ctrl != {CTRL_WIDTH{1'b0}}) begin
                packet_word_idx <= 16'd0;
                state           <= S_FINALIZE;
              end
              else begin
                packet_word_idx <= packet_word_idx + 16'd1;
              end
            end
          end
        end

        S_FINALIZE: begin
          if (frame_overflow) begin
            frame_len <= MAX_FRAME_LEN;
          end
          else if (frame_word_count == {(FRAME_WORD_ADDR_WIDTH+1){1'b0}}) begin
            frame_len <= {FRAME_LEN_WIDTH{1'b0}};
          end
          else if (final_frame_len_full > MAX_FRAME_BYTES) begin
            frame_len      <= MAX_FRAME_LEN;
            frame_overflow <= 1'b1;
          end
          else begin
            frame_len <= final_frame_len_full;
          end
          state <= S_HOLD;
        end

        S_HOLD: begin
          if (frame_taken) begin
            state            <= S_IDLE;
            packet_word_idx  <= 16'd0;
            frame_len        <= {FRAME_LEN_WIDTH{1'b0}};
            frame_word_count <= {(FRAME_WORD_ADDR_WIDTH+1){1'b0}};
            frame_overflow   <= 1'b0;
            last_frame_ctrl  <= {CTRL_WIDTH{1'b0}};
          end
        end

        default: begin
          state           <= S_IDLE;
          packet_word_idx <= 16'd0;
        end
      endcase
    end
  end

endmodule
