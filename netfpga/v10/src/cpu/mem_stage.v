module mem_stage #(
  parameter NETWORK_DATA_WIDTH = 64,
  parameter NETWORK_CTRL_WIDTH = NETWORK_DATA_WIDTH / 8,  // e.g., 8
  parameter INST_ADDR_WIDTH    = 9,
  parameter REG_ADDR_WIDTH     = 4,
  parameter MEM_ADDR_WIDTH     = 8,                       // up to 256 entries
  parameter DATA_WIDTH         = 64,
  // Generic MMIO peripheral window (replaces hard-coded GPU address range)
  parameter [7:0] MMIO_BASE    = 8'h80,
  parameter [7:0] MMIO_LAST    = 8'hCF
) (
  input wire clk,
  input wire reset,
  input wire pipeline_enable,

  // Network inputs
  input  wire [NETWORK_DATA_WIDTH-1:0] nw_in_data,
  input  wire [NETWORK_CTRL_WIDTH-1:0] nw_in_ctrl,
  input  wire                          nw_in_wr,
  output reg                           nw_in_rdy,

  // Network outputs
  output reg  [NETWORK_DATA_WIDTH-1:0] nw_out_data,
  output reg  [NETWORK_CTRL_WIDTH-1:0] nw_out_ctrl,
  output reg                           nw_out_wr,
  input  wire                          nw_out_rdy,

  // From software (debug or external CPU-driven?)
  input wire                           sw_d_mem_we,
  input wire                           sw_d_mem_re,
  input wire [MEM_ADDR_WIDTH-1:0]      sw_d_mem_addr,
  input wire [    DATA_WIDTH-1:0]      sw_d_mem_data,

  // Generic MMIO peripheral bus (replaces GPU-specific signals)
  output reg                           ext_mmio_wr_en,
  output reg                           ext_mmio_rd_en,
  output reg  [7:0]                    ext_mmio_addr,
  output reg  [31:0]                   ext_mmio_wdata,
  input  wire [31:0]                   ext_mmio_rdata,

  // CPU processing handshake
  output reg                           cpu_done,      // one-cycle pulse when CPU_MODE ends
  input  wire                          ext_continue,  // controller: proceed to NET_DRAIN
  input  wire                          ext_drop,      // controller: drop packet, go IDLE

  // From EX stage
  input wire                        w_mem_en,
  input wire                        w_reg_en,
  input wire                        lw_en,
  input wire [     DATA_WIDTH-1:0]  alu_in,
  input wire [     DATA_WIDTH-1:0]  R2_in,
  input wire [ REG_ADDR_WIDTH-1:0]  WReg1,
  input wire [INST_ADDR_WIDTH-1:0]  pc_next,
  input wire                        jmp_ctrl,
  input wire [                1:0]  thread_id,
  input wire [1:0]                  ld_ptrs,

  // To WB stage
  output wire                       mem_w_reg_en,
  output wire [     DATA_WIDTH-1:0] mem_d_out,
  output wire [     DATA_WIDTH-1:0] mem_alu_out,
  output wire [ REG_ADDR_WIDTH-1:0] mem_WReg1,
  output wire                       mem_lw_en,
  output wire [INST_ADDR_WIDTH-1:0] mem_pc_next,
  output wire                       mem_jmp_ctrl,
  output wire [               1:0]  mem_thread_id_out,

  output wire [               1:0]  mem_ld_ptrs,
  output wire [MEM_ADDR_WIDTH-1:0]  mem_head_ptr,
  output wire [MEM_ADDR_WIDTH-1:0]  mem_tail_ptr,

  output wire mem_fetch_reset,
  output wire mem_decode_flush,
  output wire mem_ex_flush,
  output wire mem_wb_flush
);

  //-------------------------------------------------------------------------
  // 1) Pipeline registers from EX to MEM
  //-------------------------------------------------------------------------
  reg                       w_mem_en_reg;
  reg                       w_reg_en_reg;
  reg                       lw_en_reg;
  reg [     DATA_WIDTH-1:0] alu_in_reg;
  reg [     DATA_WIDTH-1:0] R2_in_reg;
  reg [ REG_ADDR_WIDTH-1:0] WReg1_reg;
  reg [INST_ADDR_WIDTH-1:0] pc_next_reg;
  reg                       jmp_ctrl_reg;
  reg [                1:0] thread_id_reg;
  reg [                1:0] ld_ptrs_reg;
  reg                       ext_mmio_sel_reg;  // delayed MMIO select (for read mux)

  // Network Registers
  reg [2:0] net_state, net_state_next;
  reg [2:0] header_counter, header_counter_next;
  reg [MEM_ADDR_WIDTH-1:0] wr_ptr, wr_ptr_next;
  reg [MEM_ADDR_WIDTH-1:0] rd_ptr, rd_ptr_next;
  reg [9:0] cpu_cycle_count, cpu_cycle_count_next;
  reg nw_fetch_reset;
  reg nw_decode_flush;
  reg nw_ex_flush;
  reg nw_wb_flush;

  // NETWORK FSM — 7 states (GPU_MODE_START/WAIT removed)
  localparam NET_IDLE       = 3'd0;
  localparam NET_HEADER     = 3'd1;
  localparam NET_PAYLOAD    = 3'd2;
  localparam CPU_MODE       = 3'd3;
  localparam CPU_WAIT       = 3'd4;  // wait for controller (replaces GPU_MODE_*)
  localparam NET_DRAIN      = 3'd5;
  localparam NET_DRAIN_WAIT = 3'd6;

  // Flush Logics
  assign mem_fetch_reset   = nw_fetch_reset;
  assign mem_decode_flush  = (nw_decode_flush) ? 1 : 0;
  assign mem_ex_flush      = (nw_ex_flush) ? 1 : 0;
  assign mem_wb_flush      = nw_wb_flush;

  // Pass-through Values
  assign mem_w_reg_en      = w_reg_en_reg;
  assign mem_WReg1         = WReg1_reg;
  assign mem_alu_out       = alu_in_reg;
  assign mem_lw_en         = lw_en_reg;
  assign mem_pc_next       = pc_next_reg;
  assign mem_jmp_ctrl      = jmp_ctrl_reg;
  assign mem_thread_id_out = thread_id_reg;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      alu_in_reg        <= 0;
      w_reg_en_reg      <= 0;
      lw_en_reg         <= 0;
      WReg1_reg         <= 0;
      pc_next_reg       <= 0;
      jmp_ctrl_reg      <= 0;
      thread_id_reg     <= 0;
      ld_ptrs_reg       <= 0;
      w_mem_en_reg      <= 0;
      R2_in_reg         <= 0;
      ext_mmio_sel_reg  <= 1'b0;
    end else if (pipeline_enable) begin
      if (net_state != CPU_MODE) begin
        alu_in_reg        <= 0;
        w_reg_en_reg      <= 0;
        lw_en_reg         <= 0;
        WReg1_reg         <= 0;
        pc_next_reg       <= 0;
        jmp_ctrl_reg      <= 0;
        thread_id_reg     <= 0;
        ld_ptrs_reg       <= 0;
        w_mem_en_reg      <= 0;
        R2_in_reg         <= 0;
        ext_mmio_sel_reg  <= 1'b0;
      end else begin
        alu_in_reg        <= alu_in;
        w_reg_en_reg      <= w_reg_en;
        lw_en_reg         <= lw_en;
        WReg1_reg         <= WReg1;
        pc_next_reg       <= pc_next;
        jmp_ctrl_reg      <= jmp_ctrl;
        thread_id_reg     <= thread_id;
        ld_ptrs_reg       <= ld_ptrs;
        w_mem_en_reg      <= w_mem_en;
        R2_in_reg         <= R2_in;
        // Capture MMIO select one cycle early for read-data mux
        ext_mmio_sel_reg  <= lw_en &&
                             (alu_in[MEM_ADDR_WIDTH-1:0] >= MMIO_BASE) &&
                             (alu_in[MEM_ADDR_WIDTH-1:0] <= MMIO_LAST);
      end
    end
  end

  //-------------------------------------------------------------------------
  // 2) Network FSM — sequential
  //-------------------------------------------------------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      net_state       <= NET_IDLE;
      header_counter  <= 0;
      wr_ptr          <= 0;
      rd_ptr          <= 0;
      cpu_cycle_count <= 0;
    end else begin
      net_state       <= net_state_next;
      header_counter  <= header_counter_next;
      wr_ptr          <= wr_ptr_next;
      rd_ptr          <= rd_ptr_next;
      cpu_cycle_count <= cpu_cycle_count_next;
    end
  end

  // cpu_done: one-cycle pulse on the last cycle of CPU_MODE
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      cpu_done <= 1'b0;
    end else begin
      cpu_done <= (net_state == CPU_MODE) && (cpu_cycle_count >= 500);
    end
  end

  // Next-state logic
  always @* begin
    // Comb default values (pipeline flush by default)
    nw_fetch_reset       = 1;
    nw_decode_flush      = 1;
    nw_ex_flush          = 1;
    nw_wb_flush          = 1;

    net_state_next       = net_state;
    header_counter_next  = header_counter;
    wr_ptr_next          = wr_ptr;
    rd_ptr_next          = rd_ptr;
    cpu_cycle_count_next = cpu_cycle_count;

    case (net_state)
      NET_IDLE: begin
        wr_ptr_next    = 0;
        rd_ptr_next    = 0;
        if (nw_in_wr && (nw_in_ctrl != 0)) begin
          net_state_next = NET_HEADER;
        end
      end

      NET_HEADER: begin
        if (nw_in_wr) begin
          if (nw_in_ctrl == 0) begin
            header_counter_next = header_counter + 1'b1;
            wr_ptr_next         = wr_ptr + 1'b1;
            if (header_counter_next == 3) begin
              net_state_next = NET_PAYLOAD;
            end
          end else begin
            // End of pkt
            net_state_next      = CPU_MODE;
            header_counter_next = 0;
            wr_ptr_next         = wr_ptr + 1'b1;
          end
        end
      end

      NET_PAYLOAD: begin
        if (nw_in_wr) begin
          if (nw_in_ctrl != 0) begin
            // End of Payload
            net_state_next      = CPU_MODE;
            header_counter_next = 0;
            wr_ptr_next         = wr_ptr + 1'b1;
          end else begin
            wr_ptr_next         = wr_ptr + 1'b1;
          end
        end
      end

      CPU_MODE: begin
        if (cpu_cycle_count < 500) begin
          nw_fetch_reset       = 0;
          nw_decode_flush      = 0;
          nw_ex_flush          = 0;
          nw_wb_flush          = 0;
          cpu_cycle_count_next = cpu_cycle_count + 1;
        end else begin
          // CPU processing done — go wait for controller decision
          net_state_next       = CPU_WAIT;
          cpu_cycle_count_next = 0;
          rd_ptr_next          = 0;
        end
      end

      CPU_WAIT: begin
        // Hold here until the orchestrator signals what to do next.
        // ext_continue: CPU result is valid, drain to network
        // ext_drop:     drop the packet, return to idle
        if (ext_continue) begin
          net_state_next = NET_DRAIN;
        end else if (ext_drop) begin
          net_state_next = NET_IDLE;
          wr_ptr_next    = 0;
          rd_ptr_next    = 0;
        end
      end

      NET_DRAIN: begin
        // If there's data to read, go to WAIT state so memory can output valid data
        if (rd_ptr <= wr_ptr) begin
          net_state_next = NET_DRAIN_WAIT;
        end else begin
          // No data to drain, go IDLE
          net_state_next = NET_IDLE;
          wr_ptr_next    = 0;
          rd_ptr_next    = 0;
        end
      end

      NET_DRAIN_WAIT: begin
        if (nw_out_rdy) begin
          // Once downstream is ready, we can consume the memory data
          rd_ptr_next = rd_ptr + 1'b1;

          // If we just drained the last word, go IDLE
          if (rd_ptr == wr_ptr) begin
            net_state_next = NET_IDLE;
            wr_ptr_next    = 0;
            rd_ptr_next    = 0;
          end else begin
            // Otherwise, go back to NET_DRAIN to set up the next read
            net_state_next = NET_DRAIN;
          end
        end
      end

      default: net_state_next = NET_IDLE;
    endcase
  end

  // NW_IN Ready (Handshake Protocol)
  always @* begin
    case (net_state)
      NET_IDLE, NET_HEADER, NET_PAYLOAD: nw_in_rdy = 1;
      default:                           nw_in_rdy = 0;
    endcase
  end

  //-------------------------------------------------------------------------
  // 3) Load Pointers
  //-------------------------------------------------------------------------
  assign mem_ld_ptrs  = ld_ptrs_reg;
  assign mem_head_ptr = rd_ptr;
  assign mem_tail_ptr = wr_ptr;

  //-------------------------------------------------------------------------
  // 4) Data Memory (d_mem)
  //-------------------------------------------------------------------------
  reg d_mem_we;
  reg [MEM_ADDR_WIDTH-1:0] d_mem_addr;
  reg [DATA_WIDTH-1:0]     d_mem_wdata;
  wire [DATA_WIDTH-1:0]    d_mem_rdata;
  reg  ext_mmio_sel;   // combinational: MMIO address window hit (module-level)

  // Read-data mux: MMIO register read vs data-memory read
  assign mem_d_out = ext_mmio_sel_reg ? {32'd0, ext_mmio_rdata} : d_mem_rdata;

  always @(*) begin
    ext_mmio_sel = (net_state == CPU_MODE) &&
                   (alu_in_reg[MEM_ADDR_WIDTH-1:0] >= MMIO_BASE) &&
                   (alu_in_reg[MEM_ADDR_WIDTH-1:0] <= MMIO_LAST);

    // External MMIO peripheral bus
    ext_mmio_wr_en = ext_mmio_sel && w_mem_en_reg;
    ext_mmio_rd_en = ext_mmio_sel && lw_en_reg;
    ext_mmio_addr  = alu_in_reg[7:0] - MMIO_BASE;
    ext_mmio_wdata = R2_in_reg[31:0];

    // Write enable logic (MMIO-addressed writes go to ext bus, not d_mem)
    d_mem_we = ((sw_d_mem_we) ||
               ((net_state == CPU_MODE) && w_mem_en_reg && !ext_mmio_sel) ||
               (nw_in_wr && (net_state == NET_HEADER ||
                             net_state == NET_PAYLOAD ||
                             net_state == NET_IDLE)));

    // Address selection
    d_mem_addr = (sw_d_mem_we || sw_d_mem_re) ? sw_d_mem_addr :
                 (net_state == CPU_MODE && (w_mem_en_reg || lw_en_reg) && !ext_mmio_sel) ? alu_in_reg[MEM_ADDR_WIDTH-1:0] :
                 ((net_state == NET_HEADER)  ||
                  (net_state == NET_PAYLOAD) ||
                  (net_state == NET_IDLE)) ? wr_ptr_next :
                 (net_state == NET_DRAIN || net_state == NET_DRAIN_WAIT) ? rd_ptr : 0;

    // Write data selection
    d_mem_wdata = sw_d_mem_we ? sw_d_mem_data :
                  ((net_state == NET_HEADER)  ||
                   (net_state == NET_PAYLOAD) ||
                   (net_state == NET_IDLE)) ? nw_in_data :
                  ((net_state == CPU_MODE) && w_mem_en_reg && !ext_mmio_sel) ? R2_in_reg : 0;
  end

  // Instantiate the data memory
  mem_data #(
    .ADDR_WIDTH(MEM_ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) D_MEM (
    .clk  (clk),
    .we   (d_mem_we),
    .addr (d_mem_addr),
    .wdata(d_mem_wdata),
    .rdata(d_mem_rdata)
  );

  //-------------------------------------------------------------------------
  // 5) CTRL Memory for CTRL Data
  //-------------------------------------------------------------------------
  reg ctrl_mem_we;
  reg [NETWORK_CTRL_WIDTH-1:0] ctrl_mem_wdata;
  reg [MEM_ADDR_WIDTH-1:0] ctrl_mem_addr;
  wire [NETWORK_CTRL_WIDTH-1:0] ctrl_mem_rdata;

  always @(*) begin
    // Default Values
    ctrl_mem_we    = 0;
    ctrl_mem_wdata = 0;
    ctrl_mem_addr  = (net_state == NET_DRAIN || net_state == NET_DRAIN_WAIT) ? rd_ptr : wr_ptr_next;

    // If we are receiving a packet in IDLE/HEADER/PAYLOAD states, store CTRL
    if (nw_in_wr && (net_state == NET_IDLE || net_state == NET_HEADER || net_state == NET_PAYLOAD)) begin
      ctrl_mem_we    = 1;
      ctrl_mem_wdata = nw_in_ctrl;
    end
  end

  mem_data #(
    .ADDR_WIDTH(MEM_ADDR_WIDTH),
    .DATA_WIDTH(NETWORK_CTRL_WIDTH)
  ) CTRL_MEM (
    .clk  (clk),
    .we   (ctrl_mem_we),
    .addr (ctrl_mem_addr),
    .wdata(ctrl_mem_wdata),
    .rdata(ctrl_mem_rdata)
  );

  //-------------------------------------------------------------------------
  // 6) Network Output (draining)
  //-------------------------------------------------------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      nw_out_data <= 0;
      nw_out_ctrl <= 0;
      nw_out_wr   <= 0;
    end else begin
      if (net_state == NET_DRAIN_WAIT) begin
        nw_out_data <= d_mem_rdata;
        nw_out_ctrl <= ctrl_mem_rdata;
        nw_out_wr   <= nw_out_rdy;
      end else begin
        nw_out_wr   <= 0;
        nw_out_data <= 0;
        nw_out_ctrl <= 0;
      end
    end
  end

endmodule
