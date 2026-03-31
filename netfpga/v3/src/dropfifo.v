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
  input                             proc_owner_gpu_cfg,

  input                             proc_done,
  input                             proc_mem_en,
  input                             proc_mem_we,
  input      [FIFO_ADDR_WIDTH-1:0]  proc_mem_addr,
  input      [PROC_DATA_WIDTH-1:0]  proc_mem_wdata,
  output     [PROC_DATA_WIDTH-1:0]  proc_mem_rdata,
  output                            proc_mem_rvalid,
  output                            proc_active,

  input                             gpu_proc_done,
  input                             gpu_mem0_en,
  input                             gpu_mem0_we,
  input      [FIFO_ADDR_WIDTH-1:0]  gpu_mem0_addr,
  input      [PROC_DATA_WIDTH-1:0]  gpu_mem0_wdata,
  output     [PROC_DATA_WIDTH-1:0]  gpu_mem0_rdata,
  output                            gpu_mem0_rvalid,
  input                             gpu_mem1_en,
  input                             gpu_mem1_we,
  input      [FIFO_ADDR_WIDTH-1:0]  gpu_mem1_addr,
  input      [PROC_DATA_WIDTH-1:0]  gpu_mem1_wdata,
  output     [PROC_DATA_WIDTH-1:0]  gpu_mem1_rdata,
  output                            gpu_mem1_rvalid,
  output                            gpu_proc_active,

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
  reg gpu0_rd_valid_d;
  reg gpu1_rd_valid_d;
  reg dbg_rd_valid_d;
  reg proc_done_seen;
  reg proc_owner_gpu_lat;

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
  wire cpu_proc_read_req;
  wire gpu0_read_req;
  wire gpu1_read_req;
  wire dbg_read_req;
  wire proc_done_safe;
  wire active_proc_done;
  wire write_cycle;
  wire enter_process_from_idle;
  wire enter_process_from_fill;

  wire cpu_proc_active_int;
  wire gpu_proc_active_int;

  wire data_wea;
  wire [FIFO_ADDR_WIDTH-1:0] data_addra;
  wire [PROC_DATA_WIDTH-1:0] data_dina;

  wire data_web;
  wire [FIFO_ADDR_WIDTH-1:0] data_addrb;
  wire [PROC_DATA_WIDTH-1:0] data_dinb;

  wire [FIFO_ADDR_WIDTH-1:0] ctrl_addra;
  wire [FIFO_ADDR_WIDTH-1:0] ctrl_addrb;

  assign start_write = (state == S_IDLE) && fifowrite && firstword;
  assign fill_write  = (state == S_FILL) && fifowrite;
  assign write_cycle = start_write || fill_write;

  assign cpu_proc_active_int = (state == S_PROCESS) && !proc_owner_gpu_lat;
  assign gpu_proc_active_int = (state == S_PROCESS) &&  proc_owner_gpu_lat;

  assign proc_active     = cpu_proc_active_int;
  assign gpu_proc_active = gpu_proc_active_int;

  assign cpu_proc_read_req = cpu_proc_active_int && proc_mem_en && !proc_mem_we;
  assign gpu0_read_req     = gpu_proc_active_int && gpu_mem0_en && !gpu_mem0_we;
  assign gpu1_read_req     = gpu_proc_active_int && gpu_mem1_en && !gpu_mem1_we;

  assign proc_mem_rdata    = data_doutb;
  assign proc_mem_rvalid   = proc_rd_valid_d;
  assign gpu_mem0_rdata    = data_douta;
  assign gpu_mem0_rvalid   = gpu0_rd_valid_d;
  assign gpu_mem1_rdata    = data_doutb;
  assign gpu_mem1_rvalid   = gpu1_rd_valid_d;

  assign dbg_read_req      = dbg_mem_en && (state != S_PROCESS) && (state != S_DRAIN);
  assign dbg_mem_rdata     = data_doutb;
  assign dbg_mem_rctrl     = ctrl_doutb;
  assign dbg_mem_rvalid    = dbg_rd_valid_d;
  assign dbg_state         = state;
  assign dbg_pkt_len       = pkt_len;

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

  assign active_proc_done = cpu_proc_active_int ? proc_done :
                            gpu_proc_active_int ? gpu_proc_done :
                            1'b0;

  assign proc_done_safe = proc_done_seen &&
                          !proc_rd_valid_d &&
                          !gpu0_rd_valid_d &&
                          !gpu1_rd_valid_d &&
                          !cpu_proc_read_req &&
                          !gpu0_read_req &&
                          !gpu1_read_req;

  assign resp_din   = {ctrl_doutb, data_doutb};
  assign out_fifo   = resp_dout;
  assign valid_data = !resp_empty;

  assign enter_process_from_idle = start_write && lastword && !drop_pkt && process_en;
  assign enter_process_from_fill = fill_write  && lastword && !drop_pkt && process_en;

  assign data_wea = write_cycle ? 1'b1 :
                    (gpu_proc_active_int && gpu_mem0_en && gpu_mem0_we);

  assign data_addra = write_cycle ? ((state == S_IDLE) ? {FIFO_ADDR_WIDTH{1'b0}} : write_count[FIFO_ADDR_WIDTH-1:0]) :
                      gpu_proc_active_int ? gpu_mem0_addr :
                      {FIFO_ADDR_WIDTH{1'b0}};

  assign data_dina = write_cycle ? in_fifo[PROC_DATA_WIDTH-1:0] :
                     gpu_mem0_wdata;

  assign data_web = (cpu_proc_active_int && proc_mem_en && proc_mem_we) ||
                    (gpu_proc_active_int && gpu_mem1_en && gpu_mem1_we);

  assign data_addrb = cpu_proc_active_int ? proc_mem_addr :
                      gpu_proc_active_int ? gpu_mem1_addr :
                      dbg_read_req ? dbg_mem_addr :
                      read_issue_count[FIFO_ADDR_WIDTH-1:0];

  assign data_dinb = cpu_proc_active_int ? proc_mem_wdata :
                     gpu_proc_active_int ? gpu_mem1_wdata :
                     {PROC_DATA_WIDTH{1'b0}};

  assign ctrl_addra = write_cycle ? ((state == S_IDLE) ? {FIFO_ADDR_WIDTH{1'b0}} : write_count[FIFO_ADDR_WIDTH-1:0]) :
                      gpu_proc_active_int ? gpu_mem0_addr :
                      {FIFO_ADDR_WIDTH{1'b0}};

  assign ctrl_addrb = cpu_proc_active_int ? proc_mem_addr :
                      gpu_proc_active_int ? gpu_mem1_addr :
                      dbg_read_req ? dbg_mem_addr :
                      read_issue_count[FIFO_ADDR_WIDTH-1:0];

  fifo_bram #(
    .DATA_WIDTH(PROC_DATA_WIDTH),
    .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_data_bram (
    .clka  (clk),
    .wea   (data_wea),
    .addra (data_addra),
    .dina  (data_dina),
    .douta (data_douta),
    .clkb  (clk),
    .web   (data_web),
    .addrb (data_addrb),
    .dinb  (data_dinb),
    .doutb (data_doutb)
  );

  fifo_bram #(
    .DATA_WIDTH(CTRL_WIDTH),
    .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) u_ctrl_bram (
    .clka  (clk),
    .wea   (write_cycle),
    .addra (ctrl_addra),
    .dina  (in_fifo[FIFO_WORD_WIDTH-1:PROC_DATA_WIDTH]),
    .douta (ctrl_douta),
    .clkb  (clk),
    .web   (1'b0),
    .addrb (ctrl_addrb),
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
      gpu0_rd_valid_d  <= 1'b0;
      gpu1_rd_valid_d  <= 1'b0;
      dbg_rd_valid_d   <= 1'b0;
      proc_done_seen   <= 1'b0;
      proc_owner_gpu_lat <= 1'b0;
    end else begin
      if (enter_process_from_idle || enter_process_from_fill)
        proc_owner_gpu_lat <= proc_owner_gpu_cfg;

      case (state)
        S_IDLE: begin
          write_count      <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          read_issue_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          words_sent       <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          flight_count     <= {(FIFO_ADDR_WIDTH+1){1'b0}};
          rd_valid_d       <= 1'b0;
          proc_rd_valid_d  <= 1'b0;
          gpu0_rd_valid_d  <= 1'b0;
          gpu1_rd_valid_d  <= 1'b0;
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
          gpu0_rd_valid_d <= 1'b0;
          gpu1_rd_valid_d <= 1'b0;
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
          proc_rd_valid_d  <= cpu_proc_read_req;
          gpu0_rd_valid_d  <= gpu0_read_req;
          gpu1_rd_valid_d  <= gpu1_read_req;
          dbg_rd_valid_d   <= 1'b0;
          if (active_proc_done)
            proc_done_seen <= 1'b1;
        end

        S_DRAIN: begin
          rd_valid_d      <= issue_read;
          proc_rd_valid_d <= 1'b0;
          gpu0_rd_valid_d <= 1'b0;
          gpu1_rd_valid_d <= 1'b0;
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
          gpu0_rd_valid_d  <= 1'b0;
          gpu1_rd_valid_d  <= 1'b0;
          dbg_rd_valid_d   <= 1'b0;
          proc_done_seen   <= 1'b0;
        end
      endcase
    end
  end
endmodule
