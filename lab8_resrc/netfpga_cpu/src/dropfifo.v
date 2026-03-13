module dropfifo #(
  parameter FIFO_WORD_WIDTH = 72,
  parameter FIFO_ADDR_WIDTH = 8,
  parameter RESP_FIFO_DEPTH_BITS = 2,
  parameter PROC_DATA_WIDTH = 64
)(
  input                             clk,
  input                             drop_pkt,
  input                             fiforead,
  input                             fifowrite,
  input                             firstword,
  input      [FIFO_WORD_WIDTH-1:0]  in_fifo,
  input                             lastword,
  input                             rst,
  input                             process_en,
  input                             proc_done,
  input                             proc_mem_en,
  input                             proc_mem_we,
  input      [FIFO_ADDR_WIDTH-1:0]  proc_mem_addr,
  input      [PROC_DATA_WIDTH-1:0]  proc_mem_wdata,
  output     [PROC_DATA_WIDTH-1:0]  proc_mem_rdata,
  output                            proc_mem_rvalid,
  output                            proc_active,
  input                             dbg_mem_en,
  input      [FIFO_ADDR_WIDTH-1:0]  dbg_mem_addr,
  output     [PROC_DATA_WIDTH-1:0]  dbg_mem_rdata,
  output     [FIFO_WORD_WIDTH-PROC_DATA_WIDTH-1:0] dbg_mem_rctrl,
  output                            dbg_mem_rvalid,
  output     [1:0]                  dbg_state,
  output     [FIFO_ADDR_WIDTH:0]    dbg_pkt_len,
  output     [FIFO_WORD_WIDTH-1:0]  out_fifo,
  output                            valid_data,
  output                            fifo_full,
  output                            pkt_ready,
  output                            write_ready
);
  localparam S_IDLE    = 2'b00;
  localparam S_FILL    = 2'b01;
  localparam S_PROCESS = 2'b10;
  localparam S_DRAIN   = 2'b11;
  localparam CTRL_WIDTH = FIFO_WORD_WIDTH - PROC_DATA_WIDTH;

  reg [1:0] state, state_next;
  reg [FIFO_ADDR_WIDTH:0] write_count;
  reg [FIFO_ADDR_WIDTH:0] pkt_len;
  reg [FIFO_ADDR_WIDTH:0] read_issue_count;
  reg [FIFO_ADDR_WIDTH:0] words_sent;
  reg [FIFO_ADDR_WIDTH:0] flight_count;
  reg rd_valid_d;
  reg proc_rd_valid_d;
  reg dbg_rd_valid_d;
  reg proc_done_seen;

  wire [PROC_DATA_WIDTH-1:0] data_douta;
  wire [PROC_DATA_WIDTH-1:0] data_doutb;
  wire [CTRL_WIDTH-1:0]      ctrl_douta;
  wire [CTRL_WIDTH-1:0]      ctrl_doutb;

  wire [FIFO_WORD_WIDTH-1:0] resp_din;
  wire [FIFO_WORD_WIDTH-1:0] resp_dout;
  wire                       resp_full;
  wire                       resp_nearly_full;
  wire                       resp_prog_full;
  wire                       resp_empty;

  wire start_write;
  wire fill_write;
  wire issue_read;
  wire read_return;
  wire resp_pop;
  wire drain_done;
  wire proc_read_req;
  wire dbg_read_req;
  wire proc_done_safe;

  assign start_write = (state == S_IDLE) && fifowrite && firstword;
  assign fill_write  = (state == S_FILL) && fifowrite;

  assign proc_active     = (state == S_PROCESS);
  assign proc_read_req   = proc_active && proc_mem_en && !proc_mem_we;
  assign dbg_read_req    = dbg_mem_en && !proc_active && (state != S_DRAIN);
  assign proc_mem_rdata  = data_doutb;
  assign proc_mem_rvalid = proc_rd_valid_d;
  assign dbg_mem_rdata   = data_doutb;
  assign dbg_mem_rctrl   = ctrl_doutb;
  assign dbg_mem_rvalid  = dbg_rd_valid_d;
  assign dbg_state       = state;
  assign dbg_pkt_len     = pkt_len;

  assign read_return = rd_valid_d;
  assign resp_pop    = fiforead && !resp_empty;

  assign fifo_full   = (state == S_PROCESS) || (state == S_DRAIN);
  assign pkt_ready   = (state == S_PROCESS);
  assign write_ready = (state == S_IDLE) || (state == S_FILL);

  assign issue_read = (state == S_DRAIN) &&
                      (read_issue_count < pkt_len) &&
                      !resp_nearly_full;

  assign drain_done = (state == S_DRAIN) &&
                      (read_issue_count == pkt_len) &&
                      (flight_count == 0) &&
                      resp_empty;

  assign proc_done_safe = proc_done_seen && !proc_rd_valid_d && !proc_read_req;

  assign resp_din   = {ctrl_doutb, data_doutb};
  assign out_fifo   = resp_dout;
  assign valid_data = !resp_empty;

  fifo_bram #(
    .DATA_WIDTH(PROC_DATA_WIDTH),
    .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_data_bram (
    .clka  (clk),
    .wea   (start_write || fill_write),
    .addra ((state == S_IDLE) ? {FIFO_ADDR_WIDTH{1'b0}} : write_count[FIFO_ADDR_WIDTH-1:0]),
    .dina  (in_fifo[PROC_DATA_WIDTH-1:0]),
    .douta (data_douta),
    .clkb  (clk),
    .web   (proc_active && proc_mem_en && proc_mem_we),
    .addrb (proc_active ? proc_mem_addr : (dbg_read_req ? dbg_mem_addr : read_issue_count[FIFO_ADDR_WIDTH-1:0])),
    .dinb  (proc_mem_wdata),
    .doutb (data_doutb)
  );

  fifo_bram #(
    .DATA_WIDTH(CTRL_WIDTH),
    .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_ctrl_bram (
    .clka  (clk),
    .wea   (start_write || fill_write),
    .addra ((state == S_IDLE) ? {FIFO_ADDR_WIDTH{1'b0}} : write_count[FIFO_ADDR_WIDTH-1:0]),
    .dina  (in_fifo[FIFO_WORD_WIDTH-1:PROC_DATA_WIDTH]),
    .douta (ctrl_douta),
    .clkb  (clk),
    .web   (1'b0),
    .addrb (proc_active ? proc_mem_addr : (dbg_read_req ? dbg_mem_addr : read_issue_count[FIFO_ADDR_WIDTH-1:0])),
    .dinb  ({CTRL_WIDTH{1'b0}}),
    .doutb (ctrl_doutb)
  );

  ft_small_fifo #(
    .WIDTH(FIFO_WORD_WIDTH),
    .MAX_DEPTH_BITS(RESP_FIFO_DEPTH_BITS)
  ) resp_fifo (
    .din         (resp_din),
    .wr_en       (read_return),
    .rd_en       (resp_pop),
    .dout        (resp_dout),
    .full        (resp_full),
    .nearly_full (resp_nearly_full),
    .prog_full   (resp_prog_full),
    .empty       (resp_empty),
    .reset       (rst),
    .clk         (clk)
  );

  always @(posedge clk) begin
    if (rst)
      state <= S_IDLE;
    else
      state <= state_next;
  end

  always @(*) begin
    state_next = state;
    case (state)
      S_IDLE: begin
        if (start_write) begin
          if (lastword) begin
            if (drop_pkt)
              state_next = S_IDLE;
            else if (process_en)
              state_next = S_PROCESS;
            else
              state_next = S_DRAIN;
          end else begin
            state_next = S_FILL;
          end
        end
      end

      S_FILL: begin
        if (fill_write && lastword) begin
          if (drop_pkt)
            state_next = S_IDLE;
          else if (process_en)
            state_next = S_PROCESS;
          else
            state_next = S_DRAIN;
        end
      end

      S_PROCESS: begin
        if (proc_done_safe)
          state_next = S_DRAIN;
      end

      S_DRAIN: begin
        if (drain_done)
          state_next = S_IDLE;
      end

      default: begin
        state_next = S_IDLE;
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      write_count      <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      pkt_len          <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      read_issue_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      words_sent       <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      flight_count     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
      rd_valid_d       <= 1'b0;
      proc_rd_valid_d  <= 1'b0;
      dbg_rd_valid_d   <= 1'b0;
      proc_done_seen   <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          write_count      <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          read_issue_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          words_sent       <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          flight_count     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_valid_d       <= 1'b0;
          proc_rd_valid_d  <= 1'b0;
          dbg_rd_valid_d   <= dbg_read_req;
          proc_done_seen   <= 1'b0;
          if (start_write) begin
            if (lastword) begin
              if (!drop_pkt)
                pkt_len <= {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
              else
                pkt_len <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            end else begin
              write_count <= {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
              pkt_len <= {(FIFO_ADDR_WIDTH+1){1'b0}};
            end
          end else begin
            pkt_len <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          end
        end

        S_FILL: begin
          rd_valid_d      <= 1'b0;
          proc_rd_valid_d <= 1'b0;
          dbg_rd_valid_d  <= dbg_read_req;
          proc_done_seen  <= 1'b0;
          if (fill_write) begin
            if (lastword)
              pkt_len <= write_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
            else
              write_count <= write_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
          end
        end

        S_PROCESS: begin
          read_issue_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          words_sent       <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          flight_count     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_valid_d       <= 1'b0;
          proc_rd_valid_d  <= proc_read_req;
          dbg_rd_valid_d   <= 1'b0;
          if (proc_done)
            proc_done_seen <= 1'b1;
        end

        S_DRAIN: begin
          rd_valid_d      <= issue_read;
          proc_rd_valid_d <= 1'b0;
          dbg_rd_valid_d  <= 1'b0;
          proc_done_seen  <= 1'b0;

          if (issue_read)
            read_issue_count <= read_issue_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};

          if (resp_pop)
            words_sent <= words_sent + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};

          case ({issue_read, read_return})
            2'b10: flight_count <= flight_count + {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
            2'b01: flight_count <= flight_count - {{FIFO_ADDR_WIDTH{1'b0}}, 1'b1};
            default: flight_count <= flight_count;
          endcase
        end

        default: begin
          write_count      <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          pkt_len          <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          read_issue_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          words_sent       <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          flight_count     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_valid_d       <= 1'b0;
          proc_rd_valid_d  <= 1'b0;
          dbg_rd_valid_d   <= 1'b0;
          proc_done_seen   <= 1'b0;
        end
      endcase
    end
  end
endmodule
