`timescale 1ns/1ps
`define UDP_REG_ADDR_WIDTH 23
`define CPCI_NF2_DATA_WIDTH 32

module tb_user_top_cpu_modify;
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
    if (reset) cycle <= 0;
    else cycle <= cycle + 1;
  end

  task clear_outputs;
    begin
      out_count = 0;
      for (i = 0; i < 32; i = i + 1)
        out_cap[i] = 72'd0;
    end
  endtask

  task init_program_nop_safe;
    integer k;
    begin
      for (k = 0; k < 512; k = k + 1)
        dut.u_cpu.Imm.mem[k] = 32'h00000013;

      dut.u_cpu.Imm.mem[0]  = 32'h00001137;
      dut.u_cpu.Imm.mem[1]  = 32'h00000013;
      dut.u_cpu.Imm.mem[2]  = 32'h00000013;
      dut.u_cpu.Imm.mem[3]  = 32'h00000013;
      dut.u_cpu.Imm.mem[4]  = 32'h80010113;
      dut.u_cpu.Imm.mem[5]  = 32'h00000013;
      dut.u_cpu.Imm.mem[6]  = 32'h00000013;
      dut.u_cpu.Imm.mem[7]  = 32'h00000013;
      dut.u_cpu.Imm.mem[8]  = 32'h00012023;
      dut.u_cpu.Imm.mem[9]  = 32'h0000006f;
    end
  endtask

  task init_program_modify_word1_add1;
    integer k;
    begin
      for (k = 0; k < 512; k = k + 1)
        dut.u_cpu.Imm.mem[k] = 32'h00000013;

      dut.u_cpu.Imm.mem[0]  = 32'h00800093;
      dut.u_cpu.Imm.mem[1]  = 32'h00000013;
      dut.u_cpu.Imm.mem[2]  = 32'h00000013;
      dut.u_cpu.Imm.mem[3]  = 32'h00000013;
      dut.u_cpu.Imm.mem[4]  = 32'h0000b103;
      dut.u_cpu.Imm.mem[5]  = 32'h00000013;
      dut.u_cpu.Imm.mem[6]  = 32'h00000013;
      dut.u_cpu.Imm.mem[7]  = 32'h00000013;
      dut.u_cpu.Imm.mem[8]  = 32'h00110113;
      dut.u_cpu.Imm.mem[9]  = 32'h00000013;
      dut.u_cpu.Imm.mem[10] = 32'h00000013;
      dut.u_cpu.Imm.mem[11] = 32'h00000013;
      dut.u_cpu.Imm.mem[12] = 32'h0020b023;
      dut.u_cpu.Imm.mem[13] = 32'h00000013;
      dut.u_cpu.Imm.mem[14] = 32'h00000013;
      dut.u_cpu.Imm.mem[15] = 32'h00000013;
      dut.u_cpu.Imm.mem[16] = 32'h000011b7;
      dut.u_cpu.Imm.mem[17] = 32'h00000013;
      dut.u_cpu.Imm.mem[18] = 32'h00000013;
      dut.u_cpu.Imm.mem[19] = 32'h00000013;
      dut.u_cpu.Imm.mem[20] = 32'h80018193;
      dut.u_cpu.Imm.mem[21] = 32'h00000013;
      dut.u_cpu.Imm.mem[22] = 32'h00000013;
      dut.u_cpu.Imm.mem[23] = 32'h00000013;
      dut.u_cpu.Imm.mem[24] = 32'h0001b023;
      dut.u_cpu.Imm.mem[25] = 32'h0000006f;
    end
  endtask

  task do_reset;
    input integer prog_sel;
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
      clear_outputs();
      reset = 1'b1;
      repeat (6) @(posedge clk);
      if (prog_sel == 0)
        init_program_nop_safe();
      else
        init_program_modify_word1_add1();
      repeat (2) @(posedge clk);
      reset = 1'b0;
      @(posedge clk);
    end
  endtask

  task send_packet_ff00;
    begin
      while (in_rdy !== 1'b1) @(posedge clk);
      @(negedge clk);
      in_wr   = 1'b1;
      in_ctrl = 8'hff; in_data = 64'h1111111111111111; @(posedge clk);
      @(negedge clk);
      in_ctrl = 8'h00; in_data = 64'h2222222222222222; @(posedge clk);
      @(negedge clk);
      in_ctrl = 8'h00; in_data = 64'h3333333333333333; @(posedge clk);
      @(negedge clk);
      in_ctrl = 8'h00; in_data = 64'h4444444444444444; @(posedge clk);
      @(negedge clk);
      in_ctrl = 8'h00; in_data = 64'h5555555555555555; @(posedge clk);
      @(negedge clk);
      in_ctrl = 8'h00; in_data = 64'h6666666666666666; @(posedge clk);
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
        if (dut.u_fifo.hold_valid == 1'b0 && dut.u_fifo.drop_fifo.state == 2'b00) begin
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

  task check_pkt_unchanged;
    begin
      if (out_count != 6) begin
        $display("FAIL: expected 6 output words, got %0d", out_count);
        $finish;
      end
      if (out_cap[0] !== {8'hff,64'h1111111111111111}) begin
        $display("FAIL: word0 mismatch");
        $finish;
      end
      if (out_cap[1] !== {8'h00,64'h2222222222222222}) begin
        $display("FAIL: word1 mismatch");
        $finish;
      end
      if (out_cap[2] !== {8'h00,64'h3333333333333333}) begin
        $display("FAIL: word2 mismatch");
        $finish;
      end
      if (out_cap[3] !== {8'h00,64'h4444444444444444}) begin
        $display("FAIL: word3 mismatch");
        $finish;
      end
      if (out_cap[4] !== {8'h00,64'h5555555555555555}) begin
        $display("FAIL: word4 mismatch");
        $finish;
      end
      if (out_cap[5] !== {8'h00,64'h6666666666666666}) begin
        $display("FAIL: word5 mismatch");
        $finish;
      end
    end
  endtask

  task check_pkt_word1_add1;
    begin
      if (out_count != 6) begin
        $display("FAIL: expected 6 output words, got %0d", out_count);
        $finish;
      end
      if (out_cap[0] !== {8'hff,64'h1111111111111111}) begin
        $display("FAIL: word0 mismatch");
        $finish;
      end
      if (out_cap[1] !== {8'h00,64'h2222222222222223}) begin
        $display("FAIL: modified word1 mismatch, got %h", out_cap[1][63:0]);
        $finish;
      end
      if (out_cap[2] !== {8'h00,64'h3333333333333333}) begin
        $display("FAIL: word2 mismatch");
        $finish;
      end
      if (out_cap[3] !== {8'h00,64'h4444444444444444}) begin
        $display("FAIL: word3 mismatch");
        $finish;
      end
      if (out_cap[4] !== {8'h00,64'h5555555555555555}) begin
        $display("FAIL: word4 mismatch");
        $finish;
      end
      if (out_cap[5] !== {8'h00,64'h6666666666666666}) begin
        $display("FAIL: word5 mismatch");
        $finish;
      end
    end
  endtask

  always @(posedge clk) begin
    if (reset) begin
      prev_df_state <= 2'b11;
      prev_proc_active <= 1'b0;
      prev_pkt_ready <= 1'b0;
      prev_proc_done <= 1'b0;
    end else begin
      if (prev_df_state != dut.u_fifo.drop_fifo.state)
        $display("[%0t] DFSM %0d -> %0d", $time, prev_df_state, dut.u_fifo.drop_fifo.state);
      if (prev_proc_active != dut.u_fifo.proc_active)
        $display("[%0t] proc_active -> %b", $time, dut.u_fifo.proc_active);
      if (prev_pkt_ready != dut.u_fifo.pkt_ready)
        $display("[%0t] pkt_ready -> %b", $time, dut.u_fifo.pkt_ready);
      if (prev_proc_done != dut.u_cpu.proc_done)
        $display("[%0t] proc_done -> %b", $time, dut.u_cpu.proc_done);
      prev_df_state <= dut.u_fifo.drop_fifo.state;
      prev_proc_active <= dut.u_fifo.proc_active;
      prev_pkt_ready <= dut.u_fifo.pkt_ready;
      prev_proc_done <= dut.u_cpu.proc_done;
    end
  end

  always @(posedge clk) begin
    if (!reset && dut.u_cpu.proc_mem_en)
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

  always @(posedge clk) begin
    if (!reset && out_wr && out_rdy) begin
      out_cap[out_count] <= {out_ctrl, out_data};
      out_count <= out_count + 1;
      $display("[%0t] OUT ctrl=%h data=%h", $time, out_ctrl, out_data);
    end
  end

  initial begin
    $dumpfile("tb_user_top_cpu_modify.vcd");
    $dumpvars(0, tb_user_top_cpu_modify);

    do_reset(0);
    $display("TEST1 begin: NOP safe / packet should pass unchanged");
    send_packet_ff00();
    wait_for_idle(400);
    print_outputs();
    check_pkt_unchanged();
    $display("TEST1 PASS");

    do_reset(1);
    $display("TEST2 begin: CPU reads word1, adds 1, writes it back");
    send_packet_ff00();
    wait_for_idle(500);
    print_outputs();
    check_pkt_word1_add1();
    $display("TEST2 PASS");

    $display("ALL PASS");
    #50;
    $finish;
  end
endmodule
