module alu_64_stage2 (
  // Pass-through from Stage 1 (the "fast" single-cycle result)
  input  wire [63:0] ex1_full_result,

  // For ADD/SUB upper bits
  input  wire [31:0] a_high,
  input  wire [31:0] b_high,
  input  wire [31:0] lower_result_in,
  input  wire        carry_in,

  // For Compare
  input  wire [31:0] a_low,  // to compare if needed
  input  wire [31:0] b_low,
  input  wire [ 1:0] partial_cmp_result_in,
  input  wire        cmp_done_stage1_in,

  // Control signals from Stage 1
  input  wire        do_two_cycle_in,
  input  wire [ 3:0] alu_ctrl,

  // Final 64-bit outputs
  output reg  [63:0] final_result,
  output reg         final_overflow
);

  // localparams for op
  localparam ALU_ADD = 3'b000;
  localparam ALU_SUB = 3'b001;
  localparam ALU_CMP = 3'b101;
  // (Others not strictly needed if we only do two-cycle for ADD/SUB/CMP)

  wire [2:0] op = alu_ctrl[3:1];

  // Temporary for ADD/SUB
  reg [32:0] sum_high;
  reg [32:0] sub_high;

  always @(*) begin
    //----------------------------
    // By default, pass Stage 1's single-cycle output
    // If do_two_cycle_in=0, or op not ADD/SUB/CMP, this is final
    //----------------------------
    final_result   = ex1_full_result;
    final_overflow = 1'b0;

    //----------------------------
    // If Stage 1 says we need a second cycle
    // finish the operation
    //----------------------------
    if (do_two_cycle_in) begin
      case (op)
        //----------------------------------------
        // Finish 64-bit ADD (upper 32 bits)
        //----------------------------------------
        ALU_ADD: begin
          sum_high = a_high + b_high + carry_in;
          final_result = { sum_high[31:0], lower_result_in };

          // Signed 64-bit overflow check (simplified).
          // You might refine this further by checking the sign bits
          final_overflow = ((a_high[31] == b_high[31]) &&
                            (sum_high[31] != a_high[31]));
        end

        //----------------------------------------
        // Finish 64-bit SUB (upper 32 bits)
        //----------------------------------------
        ALU_SUB: begin
          // carry_in is effectively the borrow bit
          sub_high = {1'b0, a_high} - {1'b0, b_high} - carry_in;
          final_result = { sub_high[31:0], lower_result_in };

          // Signed 64-bit overflow (simplified).
          final_overflow = ((a_high[31] != b_high[31]) &&
                            (sub_high[31] != a_high[31]));
        end

        //----------------------------------------
        // Finish 64-bit CMP
        //----------------------------------------
        ALU_CMP: begin
          // If Stage 1 is done, we already know the result from partial_cmp_result_in
          if (cmp_done_stage1_in) begin
            // partial_cmp_result_in is final
            case (partial_cmp_result_in)
              2'd0: final_result = 64'd0; // (Should not happen if done?)
              2'd1: final_result = 64'd1; // a < b
              2'd2: final_result = 64'd2; // a > b
              default: final_result = 64'd0;
            endcase
          end
          else begin
            // Upper bits were equal => compare lower bits
            if (a_low < b_low)      final_result = 64'd1; 
            else if (a_low > b_low) final_result = 64'd2; 
            else                    final_result = 64'd0; 
          end
        end

        default: begin
          // If do_two_cycle_in=1 for an op not handled above,
          // we leave final_result as ex1_full_result (or handle if needed).
        end
      endcase
    end
  end

endmodule
