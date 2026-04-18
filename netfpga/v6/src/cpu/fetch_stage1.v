module fetch_stage1 #(
  parameter INST_ADDR_WIDTH = 9,
  parameter INST_DATA_WIDTH = 32
) (
  // Global Logic
  input  wire                       clk,
  input  wire                       reset,
  input  wire                       pipeline_enable,
  input  wire                       fetch_reset,

  // Logic from SW
  input  wire                       sw_i_mem_we,
  input  wire                       sw_i_mem_re,
  input  wire [INST_ADDR_WIDTH-1:0] sw_i_mem_addr,
  input  wire [INST_DATA_WIDTH-1:0] sw_i_mem_data,

  // Jump/Branch logic
  input  wire                       jmp_ctrl,
  input  wire [INST_ADDR_WIDTH-1:0] jmp_pc,
  input  wire [1:0]                 jmp_thread_id,

  output wire [INST_DATA_WIDTH-1:0] if1_inst_out,
  output wire [INST_ADDR_WIDTH-1:0] if1_pc_next_out,
  output wire [1:0]                 if1_thread_id_out,
  output wire                       if1_is_noop
);

  // ----------------------------------------------------------------------------
  // Local parameters for the FSM
  // ----------------------------------------------------------------------------
  localparam ST_NORMAL = 1'b0;
  localparam ST_NOOP    = 1'b1;

  // FSM state registers
  reg fsm_state, fsm_state_next;

  // Count how many NOP cycles have been injected
  reg [2:0] nop_count, nop_count_next;       // counts up to 4

  // ----------------------------------------------------------------------------
  // Program Counter registers (kept separate for older synthesis tools)
  // ----------------------------------------------------------------------------
  reg [INST_ADDR_WIDTH-1:0] pc0, pc1, pc2, pc3;
  reg [INST_ADDR_WIDTH-1:0] pc0_next, pc1_next, pc2_next, pc3_next;
  reg [1:0] thread_id, thread_id_next;

  // These regs hold the selected PC outputs
  reg [INST_ADDR_WIDTH-1:0] pc_out;
  reg [INST_ADDR_WIDTH-1:0] pc_next_out;

  // ----------------------------------------------------------------------------
  // Combinational logic for next-state of PCs and thread scheduling
  // ----------------------------------------------------------------------------
  always @(*) begin
    fsm_state_next    = fsm_state;
    nop_count_next    = nop_count;
    pc0_next = pc0;
    pc1_next = pc1;
    pc2_next = pc2;
    pc3_next = pc3;
    thread_id_next = thread_id;
    pc_out = {INST_ADDR_WIDTH{1'b0}};
    pc_next_out = {INST_ADDR_WIDTH{1'b0}};

    if (fetch_reset) begin
      fsm_state_next  = ST_NORMAL;
      nop_count_next  = 0;
      pc0_next        = 0;
      pc1_next        = 0;
      pc2_next        = 0;
      pc3_next        = 0;
      thread_id_next  = 0;
    end else begin
      if (fsm_state == ST_NORMAL) begin
        // Round-robin thread scheduling: 0->1->2->3->0
        thread_id_next = (thread_id == 2'd3) ? 2'd0 : (thread_id + 2'd1);

        // Increment the PC for whichever thread is active
        case (thread_id)
          2'd0: if (pc0 != 126) pc0_next = pc0 + 1;
          2'd1: if (pc1 != 126) pc1_next = pc1 + 1;
          2'd2: if (pc2 != 126) pc2_next = pc2 + 1;
          2'd3: if (pc3 != 126) pc3_next = pc3 + 1;
          default: begin
          end
        endcase

        if (thread_id == 2'd3) begin
          fsm_state_next    = ST_NOOP;
        end
      end else begin
        nop_count_next = nop_count + 1;
        if (nop_count == 2'd2) begin
          fsm_state_next = ST_NORMAL;
          nop_count_next = 0;
        end
      end

      // Jump logic overrides for the indicated thread if jmp_ctrl is high
      if (jmp_ctrl) begin
        case (jmp_thread_id)
          2'd0: pc0_next = jmp_pc;
          2'd1: pc1_next = jmp_pc;
          2'd2: pc2_next = jmp_pc;
          2'd3: pc3_next = jmp_pc;
        endcase
      end
      // Prepare outputs based on the current thread ID
      case (thread_id)
        2'd0: begin
          pc_out      = {thread_id, pc0[INST_ADDR_WIDTH-3:0]};
          pc_next_out = pc0_next;
        end
        2'd1: begin
          pc_out      = {thread_id, pc1[INST_ADDR_WIDTH-3:0]};
          pc_next_out = pc1_next;
        end
        2'd2: begin
          pc_out      = {thread_id, pc2[INST_ADDR_WIDTH-3:0]};
          pc_next_out = pc2_next;
        end
        default: begin
          pc_out      = {thread_id, pc3[INST_ADDR_WIDTH-3:0]};
          pc_next_out = pc3_next;
        end
      endcase
    end
  end

  // ----------------------------------------------------------------------------
  // Sequential logic: update PCs and thread ID on clock
  // ----------------------------------------------------------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      fsm_state <= ST_NORMAL;
      nop_count <= 0;
      thread_id <= 0;
      pc0       <= 0;
      pc1       <= 0;
      pc2       <= 0;
      pc3       <= 0;
    end else if (pipeline_enable) begin
      fsm_state <= fsm_state_next;
      nop_count <= nop_count_next;
      thread_id <= thread_id_next;
      pc0       <= pc0_next;
      pc1       <= pc1_next;
      pc2       <= pc2_next;
      pc3       <= pc3_next;
    end
  end

  // Drive the PC output signals
  assign if1_pc_next_out   = pc_next_out;
  assign if1_thread_id_out = thread_id;
  assign if1_is_noop       = fsm_state == ST_NOOP;

  // ----------------------------------------------------------------------------
  // Instruction Memory
  // ----------------------------------------------------------------------------
  wire [INST_ADDR_WIDTH-1:0] imem_addr;
  assign imem_addr = (sw_i_mem_we || sw_i_mem_re) ? sw_i_mem_addr : pc_out;

  mem_inst #(
    .ADDR_WIDTH (INST_ADDR_WIDTH),
    .DATA_WIDTH (INST_DATA_WIDTH)
  ) I_MEM (
    .clk        (clk),
    .we         (sw_i_mem_we),
    .addr       (imem_addr),
    .wdata      (sw_i_mem_data),
    .rdata      (if1_inst_out)
  );

endmodule
