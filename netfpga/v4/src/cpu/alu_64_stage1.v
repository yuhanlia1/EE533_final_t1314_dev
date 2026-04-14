module alu_64_stage1 (
  // 64-bit inputs
  input  wire [63:0] a,
  input  wire [63:0] b,
  // 4-bit control (assume [3:1] = operation code, [0] = shift direction, etc.)
  input  wire [ 3:0] alu_ctrl,

  //--------------- Outputs to Stage 2 ---------------//
  // For ADD/SUB partial result:
  output reg  [31:0] lower_result,   
  output reg         carry_out,       // carry or borrow from lower 32-bit add/sub
  output reg         do_two_cycle,    // signals Stage 2 to finish the op

  // For COMPARE partial result:
  output reg  [ 1:0] partial_cmp_result, // 2-bit code: 0=equal,1=a<b,2=a>b
  output reg         cmp_done_stage1,    // 1 if upper bits already decide < or >

  // Single-cycle 64-bit result (bitwise, shift, etc.)
  output reg  [63:0] full_result
);

  // Operation codes
  localparam ALU_ADD       = 3'b000;
  localparam ALU_SUB       = 3'b001;
  localparam ALU_AND       = 3'b010;
  localparam ALU_OR        = 3'b011;
  localparam ALU_XNOR      = 3'b100;
  localparam ALU_CMP       = 3'b101;
  localparam ALU_SHIFT     = 3'b110;
  localparam ALU_SHIFT_CMP = 3'b111;

  // Extract op and shift direction
  wire [2:0] op        = alu_ctrl[3:1];
  wire       shift_dir = alu_ctrl[0];  // 0 => left, 1 => right

  // Default assignments in a combinational block
  always @(*) begin
    // Defaults
    lower_result       = 32'd0;
    carry_out          = 1'b0;
    do_two_cycle       = 1'b0;
    full_result        = 64'd0;

    // Compare-related signals
    partial_cmp_result = 2'd0;   // 0 => eq so far
    cmp_done_stage1    = 1'b0;   // not decided yet by default

    case (op)
      //-----------------------------------------
      // 1) Split 64-bit ADD
      //-----------------------------------------
      ALU_ADD: begin
        // Only handle lower 32 bits. We'll add upper 32 bits + carry in Stage 2.
        {carry_out, lower_result} = a[31:0] + b[31:0];
        // Indicate we need Stage 2
        do_two_cycle = 1'b1;
      end

      //-----------------------------------------
      // 2) Split 64-bit SUB
      //-----------------------------------------
      ALU_SUB: begin
        // Only handle lower 32 bits. We'll do upper 32 bits in Stage 2.
        {carry_out, lower_result} = a[31:0] - b[31:0];
        // Indicate we need Stage 2
        do_two_cycle = 1'b1;
      end

      //-----------------------------------------
      // 3) Split 64-bit CMP (2-stage)
      //-----------------------------------------
      ALU_CMP: begin
        // Compare the upper 32 bits first
        do_two_cycle = 1'b1; // we may need Stage 2 if they're equal
        if (a[63:32] < b[63:32]) begin
          partial_cmp_result = 2'd1; // a < b
          cmp_done_stage1    = 1'b1; // done, no need to compare lower bits
        end
        else if (a[63:32] > b[63:32]) begin
          partial_cmp_result = 2'd2; // a > b
          cmp_done_stage1    = 1'b1; // done
        end
        else begin
          partial_cmp_result = 2'd0; // equal so far
          cmp_done_stage1    = 1'b0; // must compare lower bits in Stage 2
        end
      end

      //-----------------------------------------
      // 4) Single-Cycle Bitwise Ops
      //-----------------------------------------
      ALU_AND:   full_result = a & b;
      ALU_OR:    full_result = a | b;
      ALU_XNOR:  full_result = ~(a ^ b);

      //-----------------------------------------
      // 5) Single-Cycle Shift
      //-----------------------------------------
      ALU_SHIFT: begin
        if (shift_dir == 1'b0)
          full_result = a << b[2:0];
        else
          full_result = a >> b[2:0];
      end

      //-----------------------------------------
      // 6) Single-Cycle SHIFT_CMP
      //-----------------------------------------
      ALU_SHIFT_CMP: begin
        full_result = ((shift_dir == 1'b0) ? (a << b[2:0]) : (a >> b[2:0])) == b ? 64'd1 : 64'd0;
      end

      default: full_result = 64'd0;
    endcase
  end

endmodule
