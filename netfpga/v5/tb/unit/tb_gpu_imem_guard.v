`timescale 1ns / 1ps

module tb_gpu_imem_guard;

  localparam integer PC_W = 16;
  localparam integer IMEM_PROG_ADDR_W = 16;
  localparam integer IMEM_ADDR_W = 9;
  localparam integer IMEM_DEPTH = 512;
  localparam [31:0] HALT_INSTR = 32'hF0000000;
  localparam [31:0] BAD_INSTR  = 32'h12345678;

  reg clk;
  reg reset;
  reg run_en;
  reg start_pulse;
  reg [PC_W-1:0] entry_pc;
  reg soft_reset_pulse;
  reg stall;
  reg jump_valid;
  reg [PC_W-1:0] jump_addr;
  reg imem_we;
  reg [IMEM_PROG_ADDR_W-1:0] imem_waddr;
  reg [31:0] imem_wdata;

  wire [PC_W-1:0] pc_if;
  wire [31:0] instr_if;

  gpu_if_stage #(
    .PC_W(PC_W),
    .IMEM_PROG_ADDR_W(IMEM_PROG_ADDR_W),
    .IMEM_ADDR_W(IMEM_ADDR_W),
    .IMEM_DEPTH(IMEM_DEPTH)
  ) dut (
    .clk(clk),
    .rst(reset),
    .run_en(run_en),
    .start_pulse(start_pulse),
    .entry_pc(entry_pc),
    .soft_reset_pulse(soft_reset_pulse),
    .stall(stall),
    .jump_valid(jump_valid),
    .jump_addr(jump_addr),
    .imem_we(imem_we),
    .imem_waddr(imem_waddr),
    .imem_wdata(imem_wdata),
    .pc_if(pc_if),
    .instr_if(instr_if)
  );

  always #5 clk = ~clk;

  task step;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    run_en = 1'b0;
    start_pulse = 1'b0;
    entry_pc = {PC_W{1'b0}};
    soft_reset_pulse = 1'b0;
    stall = 1'b0;
    jump_valid = 1'b0;
    jump_addr = {PC_W{1'b0}};
    imem_we = 1'b0;
    imem_waddr = {IMEM_PROG_ADDR_W{1'b0}};
    imem_wdata = 32'd0;

    step;
    step;
    reset = 1'b0;

    imem_we = 1'b1;
    imem_waddr = {IMEM_PROG_ADDR_W{1'b0}};
    imem_wdata = HALT_INSTR;
    step;

    imem_waddr = IMEM_DEPTH;
    imem_wdata = BAD_INSTR;
    step;

    imem_we = 1'b0;
    run_en = 1'b1;
    start_pulse = 1'b1;
    entry_pc = {PC_W{1'b0}};
    step;

    start_pulse = 1'b0;
    step;

    if (instr_if !== HALT_INSTR) begin
      $display("[FAIL] expected HALT instruction at PC 0, got %h", instr_if);
      $finish;
    end

    $display("[TB] === PASS: GPU IMEM out-of-range program writes are ignored ===");
    $finish;
  end

endmodule
