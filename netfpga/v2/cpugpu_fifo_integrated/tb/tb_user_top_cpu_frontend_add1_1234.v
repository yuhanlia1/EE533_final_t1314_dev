`timescale 1ns/1ps
`define UDP_REG_ADDR_WIDTH 23
`define CPCI_NF2_DATA_WIDTH 32

module tb_user_top_cpu_frontend_add1_1234;
  localparam DATA_WIDTH = 64;
  localparam CTRL_WIDTH = DATA_WIDTH/8;
  localparam UDP_REG_SRC_WIDTH = 2;

  reg [DATA_WIDTH-1:0] in_data;
  reg [CTRL_WIDTH-1:0] in_ctrl;
  reg in_wr;
  wire in_rdy;

  wire [DATA_WIDTH-1:0] out_data;
  wire [CTRL_WIDTH-1:0] out_ctrl;
  wire out_wr;
  reg out_rdy;

  reg reg_req_in;
  reg reg_ack_in;
  reg reg_rd_wr_L_in;
  reg [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in;
  reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in;
  reg [UDP_REG_SRC_WIDTH-1:0] reg_src_in;

  wire reg_req_out;
  wire reg_ack_out;
  wire reg_rd_wr_L_out;
  wire [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out;
  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out;
  wire [UDP_REG_SRC_WIDTH-1:0] reg_src_out;

  reg clk;
  reg reset;

  integer cycle;
  integer out_count;
  integer i;
  reg [71:0] out_cap [0:31];
  reg [1:0] prev_df_state;
  reg prev_proc_active;
  reg prev_pkt_ready;
  reg prev_proc_done;
  reg prev_owner_gpu;
  reg seen_proc_done;

  user_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
  ) dut (
    .in_data(in_data),
    .in_ctrl(in_ctrl),
    .in_wr(in_wr),
    .in_rdy(in_rdy),
    .out_data(out_data),
    .out_ctrl(out_ctrl),
    .out_wr(out_wr),
    .out_rdy(out_rdy),
    .reg_req_in(reg_req_in),
    .reg_ack_in(reg_ack_in),
    .reg_rd_wr_L_in(reg_rd_wr_L_in),
    .reg_addr_in(reg_addr_in),
    .reg_data_in(reg_data_in),
    .reg_src_in(reg_src_in),
    .reg_req_out(reg_req_out),
    .reg_ack_out(reg_ack_out),
    .reg_rd_wr_L_out(reg_rd_wr_L_out),
    .reg_addr_out(reg_addr_out),
    .reg_data_out(reg_data_out),
    .reg_src_out(reg_src_out),
    .clk(clk),
    .reset(reset)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk) begin
    if (reset)
      cycle <= 0;
    else
      cycle <= cycle + 1;
  end

  task init_program;
    integer k;
    begin
      for (k = 0; k < 512; k = k + 1)
        dut.u_cpu.Imm.mem[k] = 32'h00000013;

      dut.u_cpu.Imm.mem[0]  = 32'h00003083;
      dut.u_cpu.Imm.mem[1]  = 32'h00000013;
      dut.u_cpu.Imm.mem[2]  = 32'h00000013;
      dut.u_cpu.Imm.mem[3]  = 32'h00000013;
      dut.u_cpu.Imm.mem[4]  = 32'h00108093;
      dut.u_cpu.Imm.mem[5]  = 32'h00000013;
      dut.u_cpu.Imm.mem[6]  = 32'h00000013;
      dut.u_cpu.Imm.mem[7]  = 32'h00000013;
      dut.u_cpu.Imm.mem[8]  = 32'h00103023;

      dut.u_cpu.Imm.mem[9]  = 32'h00803183;
      dut.u_cpu.Imm.mem[10] = 32'h00000013;
      dut.u_cpu.Imm.mem[11] = 32'h00000013;
      dut.u_cpu.Imm.mem[12] = 32'h00000013;
      dut.u_cpu.Imm.mem[13] = 32'h00118193;
      dut.u_cpu.Imm.mem[14] = 32'h00000013;
      dut.u_cpu.Imm.mem[15] = 32'h00000013;
      dut.u_cpu.Imm.mem[16] = 32'h00000013;
      dut.u_cpu.Imm.mem[17] = 32'h00303423;

      dut.u_cpu.Imm.mem[18] = 32'h01003203;
      dut.u_cpu.Imm.mem[19] = 32'h00000013;
      dut.u_cpu.Imm.mem[20] = 32'h00000013;
      dut.u_cpu.Imm.mem[21] = 32'h00000013;
      dut.u_cpu.Imm.mem[22] = 32'h00120213;
      dut.u_cpu.Imm.mem[23] = 32'h00000013;
      dut.u_cpu.Imm.mem[24] = 32'h00000013;
      dut.u_cpu.Imm.mem[25] = 32'h00000013;
      dut.u_cpu.Imm.mem[26] = 32'h00403823;

      dut.u_cpu.Imm.mem[27] = 32'h01803283;
      dut.u_cpu.Imm.mem[28] = 32'h00000013;
      dut.u_cpu.Imm.mem[29] = 32'h00000013;
      dut.u_cpu.Imm.mem[30] = 32'h00000013;
      dut.u_cpu.Imm.mem[31] = 32'h00128293;
      dut.u_cpu.Imm.mem[32] = 32'h00000013;
      dut.u_cpu.Imm.mem[33] = 32'h00000013;
      dut.u_cpu.Imm.mem[34] = 32'h00000013;
      dut.u_cpu.Imm.mem[35] = 32'h00503c23;

      dut.u_cpu.Imm.mem[36] = 32'h00001137;
      dut.u_cpu.Imm.mem[37] = 32'h00000013;
      dut.u_cpu.Imm.mem[38] = 32'h00000013;
      dut.u_cpu.Imm.mem[39] = 32'h00000013;
      dut.u_cpu.Imm.mem[40] = 32'h80010113;
      dut.u_cpu.Imm.mem[41] = 32'h00000013;
      dut.u_cpu.Imm.mem[42] = 32'h00000013;
      dut.u_cpu.Imm.mem[43] = 32'h00000013;
      dut.u_cpu.Imm.mem[44] = 32'h00013023;
      dut.u_cpu.Imm.mem[45] = 32'h0000006f;
    end
  endtask

  task do_reset;
    begin
      in_data = 64'd0;
      in_ctrl = 8'd0;
      in_wr = 1'b0;
      out_rdy = 1'b1;
      reg_req_in = 1'b0;
      reg_ack_in = 1'b0;
      reg_rd_wr_L_in = 1'b0;
      reg_addr_in = 0;
      reg_data_in = 0;
      reg_src_in = 0;
      out_count = 0;
      seen_proc_done = 1'b0;
      for (i = 0; i < 32; i = i + 1)
        out_cap[i] = 72'd0;
      reset = 1'b1;
      repeat (6) @(posedge clk);
      init_program();
      repeat (2) @(posedge clk);
      reset = 1'b0;
      @(posedge clk);
    end
  endtask

  task lock_cpu_owner;
    begin
      force dut.proc_owner_gpu_cfg = 1'b0;
      force dut.gpu_mmio_wr_pulse = 1'b0;
      force dut.gpu_mmio_rd_pulse = 1'b0;
      force dut.gpu_imem_prog_pulse = 1'b0;
    end
  endtask

  task send_packet_1234;
    begin
      while (in_rdy !== 1'b1) @(posedge clk);
      @(negedge clk);
      in_wr   = 1'b1;
      in_ctrl = 8'hff;
      in_data = 64'd1;
      @(posedge clk);

      @(negedge clk);
      in_ctrl = 8'h00;
      in_data = 64'd2;
      @(posedge clk);

      @(negedge clk);
      in_ctrl = 8'h00;
      in_data = 64'd3;
      @(posedge clk);

      @(negedge clk);
      in_ctrl = 8'h00;
      in_data = 64'd4;
      @(posedge clk);

      @(negedge clk);
      in_wr   = 1'b0;
      in_ctrl = 8'h00;
      in_data = 64'd0;
    end
  endtask

  task wait_for_idle;
    input integer limit;
    integer k;
    reg ok;
    begin
      ok = 1'b0;
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (dut.u_fifo.hold_valid == 1'b0 &&
            dut.u_fifo.drop_fifo.state == 2'b00 &&
            dut.u_fifo.proc_active == 1'b0) begin
          ok = 1'b1;
          k = limit;
        end
      end
      if (!ok) begin
        $display("FAIL: timeout waiting idle at cycle %0d", cycle);
        $finish;
      end
    end
  endtask

  task print_outputs;
    integer k;
    begin
      $display("OUTPUT COUNT=%0d", out_count);
      for (k = 0; k < out_count; k = k + 1)
        $display("  OUT[%0d] ctrl=%h data=%h", k, out_cap[k][71:64], out_cap[k][63:0]);
    end
  endtask

  always @(posedge clk) begin
    if (reset) begin
      prev_df_state <= 2'b11;
      prev_proc_active <= 1'b0;
      prev_pkt_ready <= 1'b0;
      prev_proc_done <= 1'b0;
      prev_owner_gpu <= 1'b0;
    end else begin
      if (prev_df_state != dut.u_fifo.drop_fifo.state)
        $display("[%0t] DFSM %0d -> %0d", $time, prev_df_state, dut.u_fifo.drop_fifo.state);
      if (prev_proc_active != dut.u_fifo.proc_active)
        $display("[%0t] proc_active -> %b", $time, dut.u_fifo.proc_active);
      if (prev_pkt_ready != dut.u_fifo.pkt_ready)
        $display("[%0t] pkt_ready -> %b", $time, dut.u_fifo.pkt_ready);
      if (prev_proc_done != dut.u_cpu.proc_done)
        $display("[%0t] cpu_proc_done -> %b", $time, dut.u_cpu.proc_done);
      if (prev_owner_gpu != dut.proc_owner_gpu)
        $display("[%0t] proc_owner_gpu -> %b", $time, dut.proc_owner_gpu);
      prev_df_state <= dut.u_fifo.drop_fifo.state;
      prev_proc_active <= dut.u_fifo.proc_active;
      prev_pkt_ready <= dut.u_fifo.pkt_ready;
      prev_proc_done <= dut.u_cpu.proc_done;
      prev_owner_gpu <= dut.proc_owner_gpu;
      if (dut.u_cpu.proc_done)
        seen_proc_done <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!reset && dut.u_cpu.proc_mem_en) begin
      $display("[%0t] CPU MEM en=%b we=%b addr=%0d wdata=%h rvalid=%b rdata=%h pc=%h inst=%h done_hit=%b",
        $time,
        dut.u_cpu.proc_mem_en,
        dut.u_cpu.proc_mem_we,
        dut.u_cpu.proc_mem_addr,
        dut.u_cpu.proc_mem_wdata,
        dut.u_cpu.proc_mem_rvalid,
        dut.u_cpu.proc_mem_rdata,
        dut.u_cpu.pc_if,
        dut.u_cpu.instr_in,
        dut.u_cpu.mm_stage_inst.is_done_store
      );
    end
  end

  always @(posedge clk) begin
    if (!reset && dut.gpu_proc_active)
      $display("[%0t] WARNING: gpu_proc_active asserted during CPU-only TB", $time);
  end

  always @(posedge clk) begin
    if (!reset && out_wr && out_rdy) begin
      out_cap[out_count] <= {out_ctrl, out_data};
      out_count <= out_count + 1;
      $display("[%0t] OUT ctrl=%h data=%h", $time, out_ctrl, out_data);
    end
  end

  initial begin
    $dumpfile("tb_user_top_cpu_frontend_add1_1234.vcd");
    $dumpvars(0, tb_user_top_cpu_frontend_add1_1234);

    lock_cpu_owner();
    do_reset();

    $display("TEST cpu_frontend_add1_1234 begin");
    send_packet_1234();
    wait_for_idle(2000);
    print_outputs();

    if (!seen_proc_done) begin
      $display("FAIL: proc_done was never observed");
      $finish;
    end

    if (dut.proc_owner_gpu !== 1'b0) begin
      $display("FAIL: owner switched away from CPU");
      $finish;
    end

    if (out_count != 4) begin
      $display("FAIL: expected 4 output words, got %0d", out_count);
      $finish;
    end

    if (out_cap[0][71:64] !== 8'hff || out_cap[0][63:0] !== 64'd2) begin
      $display("FAIL: OUT[0] mismatch got ctrl=%h data=%h", out_cap[0][71:64], out_cap[0][63:0]);
      $finish;
    end

    if (out_cap[1][71:64] !== 8'h00 || out_cap[1][63:0] !== 64'd3) begin
      $display("FAIL: OUT[1] mismatch got ctrl=%h data=%h", out_cap[1][71:64], out_cap[1][63:0]);
      $finish;
    end

    if (out_cap[2][71:64] !== 8'h00 || out_cap[2][63:0] !== 64'd4) begin
      $display("FAIL: OUT[2] mismatch got ctrl=%h data=%h", out_cap[2][71:64], out_cap[2][63:0]);
      $finish;
    end

    if (out_cap[3][71:64] !== 8'h00 || out_cap[3][63:0] !== 64'd5) begin
      $display("FAIL: OUT[3] mismatch got ctrl=%h data=%h", out_cap[3][71:64], out_cap[3][63:0]);
      $finish;
    end

    $display("PASS");
    #50;
    release dut.proc_owner_gpu_cfg;
    release dut.gpu_mmio_wr_pulse;
    release dut.gpu_mmio_rd_pulse;
    release dut.gpu_imem_prog_pulse;
    $finish;
  end
endmodule
