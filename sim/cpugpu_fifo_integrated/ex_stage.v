// -------------------- EX stage --------------------
module ex_stage(
  input  wire [10:0] pc_in,
  input  wire [63:0] IMM_in,
  input  wire        wreg_in,
  input  wire [63:0] rd2_in,
  input  wire [63:0] rd1_in,
  input  wire [4:0]  rd_in,
  input  wire [2:0]  func3_in,
  input  wire [6:0]  func7_in,
  input  wire        ALUsrc_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,
  input  wire        AUIPC_in,
  input  wire        wist_in,
  input  wire        is_b_in,
  input  wire        is_jal_in,
  input  wire        is_jalr_in,
  output wire [63:0] alu_out,
  output wire [63:0] rd2_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        WMM_out,
  output wire        RMM_out,
  output wire        MOA_out,
  output wire        jal_jalr_out,
  output wire        jump_valid_out,
  output wire [10:0] jump_addr_out
);

wire [63:0] b_sel;
wire add_force;
wire zero_unused;
wire lt_unused;
wire ltu_unused;
wire eq;
wire lt_s;
wire ge_s;
wire lt_u;
wire ge_u;
reg b_take;
wire jump_valid_raw;
wire [63:0] pc_u64;
wire [63:0] base64;
wire [63:0] target_raw;
wire [63:0] target_aligned;

assign b_sel = ALUsrc_in ? IMM_in : rd2_in;
assign add_force = WMM_in | RMM_in | AUIPC_in;

alu u_alu (
  .a(rd1_in), 
  .b(b_sel), 
  .func3(func3_in), 
  .func7(func7_in), 
  .add_force(add_force), 
  .is_imm(ALUsrc_in), 
  .y(alu_out), 
  .zero(zero_unused), 
  .lt(lt_unused), 
  .ltu(ltu_unused)
);

assign eq   = (rd1_in == rd2_in);
assign lt_s = ($signed(rd1_in) <  $signed(rd2_in));
assign ge_s = ($signed(rd1_in) >= $signed(rd2_in));
assign lt_u = (rd1_in <  rd2_in);
assign ge_u = (rd1_in >= rd2_in);

always @(*) begin
  if (is_b_in) begin
    case (func3_in)
      3'b000: b_take = eq;
      3'b001: b_take = ~eq;
      3'b100: b_take = lt_s;
      3'b101: b_take = ge_s;
      3'b110: b_take = lt_u;
      3'b111: b_take = ge_u;
      default: b_take = 1'b0;
    endcase
  end else b_take = 1'b0;
end

assign jump_valid_raw = b_take | is_jal_in | is_jalr_in;
assign jump_valid_out = (wist_in) ? 1'b0 : jump_valid_raw;
assign pc_u64   = {53'd0, pc_in};
assign base64   = is_jalr_in ? rd1_in : pc_u64;
assign target_raw = base64 + IMM_in;
assign target_aligned = target_raw & ~64'd3;
assign jump_addr_out = target_aligned[10:0];
assign rd2_out      = rd2_in;
assign wreg_out     = (wist_in) ? 1'b0 : wreg_in;
assign rd_out       = rd_in;
assign WMM_out      = (wist_in) ? 1'b0 : WMM_in;
assign RMM_out      = (wist_in) ? 1'b0 : RMM_in;
assign MOA_out      = MOA_in;
assign jal_jalr_out = (wist_in) ? 1'b0 : jal_jalr_in;

endmodule
