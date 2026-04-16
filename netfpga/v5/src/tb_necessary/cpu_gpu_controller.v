`timescale 1ns / 1ps

// cpu_gpu_controller
//
// Orchestrates the CPU → GPU → network pipeline.
// Receives cpu_done from the CPU when its 500-cycle processing window ends,
// triggers GPU execution, and signals the CPU to either drain the packet to
// the network (ext_continue) or discard it (ext_drop).
//
// Also routes the CPU's generic MMIO bus to the GPU's MMIO interface so that
// the CPU can configure GPU registers via LDR/STR instructions without
// knowing it is talking to a GPU specifically.

module cpu_gpu_controller (
  input  wire clk,
  input  wire reset,

  // -----------------------------------------------------------------------
  // CPU side
  // -----------------------------------------------------------------------
  input  wire        cpu_done,      // one-cycle pulse: CPU processing window ended
  output reg         ext_continue,  // assert to let CPU proceed to NET_DRAIN
  output reg         ext_drop,      // assert to let CPU discard packet

  // Generic MMIO bus from CPU (during CPU_MODE only)
  input  wire        cpu_mmio_wr_en,
  input  wire        cpu_mmio_rd_en,
  input  wire [7:0]  cpu_mmio_addr,
  input  wire [31:0] cpu_mmio_wdata,
  output wire [31:0] cpu_mmio_rdata,

  // -----------------------------------------------------------------------
  // GPU side
  // -----------------------------------------------------------------------
  output reg         gpu_start,       // one-cycle pulse to GPU bridge

  // GPU result interface (from gpu_platform_bridge, replaces done/drop ports)
  input  wire        gpu_core_done,   // GPU computation finished (core_done_out)
  input  wire [31:0] gpu_result_a,    // result_node_a: class-A score
  input  wire [31:0] gpu_result_b,    // result_node_b: class-B score

  // GPU MMIO bus (forwarded to gpu_platform_bridge)
  output wire        gpu_mmio_wr_en,
  output wire        gpu_mmio_rd_en,
  output wire [7:0]  gpu_mmio_addr,
  output wire [31:0] gpu_mmio_wdata,
  input  wire [31:0] gpu_mmio_rdata
);

  // -----------------------------------------------------------------------
  // Controller FSM
  // -----------------------------------------------------------------------
  localparam CTRL_IDLE      = 2'd0;  // waiting for cpu_done
  localparam CTRL_GPU_START = 2'd1;  // pulse gpu_start for one cycle
  localparam CTRL_GPU_WAIT  = 2'd2;  // wait for gpu_done

  reg [1:0] ctrl_state, ctrl_state_next;

  // Sequential
  always @(posedge clk or posedge reset) begin
    if (reset)
      ctrl_state <= CTRL_IDLE;
    else
      ctrl_state <= ctrl_state_next;
  end

  // Next-state / output logic (Mealy)
  always @(*) begin
    ctrl_state_next = ctrl_state;
    gpu_start       = 1'b0;
    ext_continue    = 1'b0;
    ext_drop        = 1'b0;

    case (ctrl_state)
      CTRL_IDLE: begin
        if (cpu_done)
          ctrl_state_next = CTRL_GPU_START;
      end

      CTRL_GPU_START: begin
        // One-cycle pulse to GPU bridge, then wait
        gpu_start       = 1'b1;
        ctrl_state_next = CTRL_GPU_WAIT;
      end

      CTRL_GPU_WAIT: begin
        if (gpu_core_done) begin
          ctrl_state_next = CTRL_IDLE;
          // Drop decision: if class-B score > class-A score, drop the packet
          if ($signed(gpu_result_b[15:0]) > $signed(gpu_result_a[15:0]))
            ext_drop     = 1'b1;
          else
            ext_continue = 1'b1;
        end
      end

      default: ctrl_state_next = CTRL_IDLE;
    endcase
  end

  // -----------------------------------------------------------------------
  // MMIO bus pass-through: CPU generic bus → GPU MMIO bus
  // The CPU accesses GPU registers via LDR/STR to the MMIO address window.
  // This block simply connects the two buses; address filtering is done in
  // mem_stage (MMIO_BASE/LAST parameters).
  // -----------------------------------------------------------------------
  assign gpu_mmio_wr_en = cpu_mmio_wr_en;
  assign gpu_mmio_rd_en = cpu_mmio_rd_en;
  assign gpu_mmio_addr  = cpu_mmio_addr;
  assign gpu_mmio_wdata = cpu_mmio_wdata;
  assign cpu_mmio_rdata = gpu_mmio_rdata;

endmodule
