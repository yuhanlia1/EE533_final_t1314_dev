module fetch_stage2 #(
  parameter INST_ADDR_WIDTH = 9,
  parameter INST_DATA_WIDTH = 32
) (
  // Global Logic
  input  wire                       clk,
  input  wire                       reset,
  input  wire                       pipeline_enable,
  input  wire                       fetch_reset,

  input wire [INST_DATA_WIDTH-1:0]  if1_inst,
  input wire [INST_ADDR_WIDTH-1:0]  if1_pc_next,
  input wire [1:0]                  if1_thread_id,
  input wire                        if1_is_noop,

  output wire [INST_DATA_WIDTH-1:0] if2_inst_out,
  output wire [INST_ADDR_WIDTH-1:0] if2_pc_next_out,
  output wire [1:0]                 if2_thread_id_out
);

  localparam [INST_DATA_WIDTH-1:0] NOOP_INSTR = {INST_DATA_WIDTH{1'b0}};

  reg [INST_ADDR_WIDTH-1:0] if1_pc_next_reg;
  reg [1:0]                 if1_thread_id_reg;
  reg                       if1_is_noop_reg;

  assign if2_inst_out      = fetch_reset ? NOOP_INSTR : if1_is_noop_reg ? NOOP_INSTR : if1_inst;
  assign if2_pc_next_out   = if1_pc_next_reg;
  assign if2_thread_id_out = if1_thread_id_reg;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      if1_pc_next_reg <= 0;
      if1_thread_id_reg <= 0;
      if1_is_noop_reg <= 0;
    end else if (fetch_reset) begin
      if1_pc_next_reg <= 0;
      if1_thread_id_reg <= 0;
      if1_is_noop_reg <= 0;
    end else begin
      if1_pc_next_reg <= if1_pc_next;
      if1_thread_id_reg <= if1_thread_id;
      if1_is_noop_reg <= if1_is_noop;
    end
  end

endmodule
