`timescale 1ns / 1ps

module gpu_platform_bridge #(
  parameter MMIO_ADDR_W = 8,
  parameter IMEM_AW     = 9,
  parameter MEM_AW      = 8
) (
  input  wire        clk,
  input  wire        reset,

  input  wire        start,
  input  wire        il_mem_wen,
  input  wire [31:0] il_mem_addr,
  input  wire [31:0] il_mem_wdata,

  input  wire        sw_w_mem_wen,
  input  wire [31:0] sw_w_mem_addr,
  input  wire [31:0] sw_w_mem_wdata_0,
  input  wire [31:0] sw_w_mem_wdata_1,

  input  wire        sw_ofmap_mem_ren,
  input  wire [31:0] sw_ofmap_mem_addr,
  output reg  [31:0] hw_ofmap_mem_data_1,
  output reg  [31:0] hw_ofmap_mem_data_0,

  input  wire                   gpu_mmio_wr_en,
  input  wire                   gpu_mmio_rd_en,
  input  wire [MMIO_ADDR_W-1:0] gpu_mmio_addr,
  input  wire [31:0]            gpu_mmio_wdata,
  output wire [31:0]            gpu_mmio_rdata,

  // Decoupled result interface: let the caller decide what to do with output
  output wire [31:0]            result_node_a,  // mem0[NODE1_ADDR][31:0]
  output wire [31:0]            result_node_b,  // mem0[NODE2_ADDR][31:0]
  output wire                   core_done_out   // GPU computation complete
);

  localparam [MMIO_ADDR_W-1:0] REG_CONTROL   = 8'h00;
  localparam [MMIO_ADDR_W-1:0] REG_ENTRY_PC  = 8'h08;
  localparam [MMIO_ADDR_W-1:0] REG_WORK_SIZE = 8'h10;
  localparam [MMIO_ADDR_W-1:0] REG_BASE_A_LO = 8'h20;
  localparam [MMIO_ADDR_W-1:0] REG_BASE_C_LO = 8'h30;

  localparam [31:0] CTRL_START = 32'h0000_0001;

  localparam integer PROGRAM_LEN = 9;
  localparam [MEM_AW-1:0] NODE1_ADDR = 8'd32;
  localparam [MEM_AW-1:0] NODE2_ADDR = 8'd33;

  reg [31:0] result_node_a_reg;
  reg [31:0] result_node_b_reg;

  reg [31:0] program_rom [0:PROGRAM_LEN-1];
  reg [IMEM_AW-1:0] program_idx;
  reg               program_loading;
  reg               program_loaded;

  reg               auto_cfg_active;
  reg [2:0]         auto_cfg_state;
  reg               auto_start_only;
  reg               cfg_seen;

  reg                    auto_mmio_wr_en;
  reg [MMIO_ADDR_W-1:0]  auto_mmio_addr;
  reg [31:0]             auto_mmio_wdata;

  reg  [63:0] mem0 [0:(1<<MEM_AW)-1];
  reg  [63:0] mem1 [0:(1<<MEM_AW)-1];
  reg  [63:0] mem0_rdata_reg;
  reg  [63:0] mem1_rdata_reg;
  reg         mem0_rvalid_reg;
  reg         mem1_rvalid_reg;
  reg         core_done_d;
  integer      i;
  integer      j;

  wire                   mmio_wr_sel;
  wire                   mmio_rd_sel;
  wire [MMIO_ADDR_W-1:0] mmio_addr_sel;
  wire [31:0]            mmio_wdata_sel;

  wire                   core_done;
  wire                   core_mem0_en;
  wire                   core_mem0_we;
  wire [MEM_AW-1:0]      core_mem0_addr;
  wire [63:0]            core_mem0_wdata;
  wire                   core_mem1_en;
  wire                   core_mem1_we;
  wire [MEM_AW-1:0]      core_mem1_addr;
  wire [63:0]            core_mem1_wdata;
  wire [15:0]            dbg_pc;
  wire                   gpu_busy;
  wire [31:0]            core_mmio_rdata;

  function automatic [31:0] gpu_instr(
    input [3:0]  opcode,
    input [2:0]  rd,
    input [2:0]  rs1,
    input [2:0]  rs2,
    input [1:0]  bsel,
    input        dtype,
    input [15:0] imm
  );
    begin
      gpu_instr = {opcode, rd, rs1, rs2, bsel, dtype, imm};
    end
  endfunction

  assign mmio_wr_sel    = auto_cfg_active ? auto_mmio_wr_en : gpu_mmio_wr_en;
  assign mmio_rd_sel    = auto_cfg_active ? 1'b0            : gpu_mmio_rd_en;
  assign mmio_addr_sel  = auto_cfg_active ? auto_mmio_addr  : gpu_mmio_addr;
  assign mmio_wdata_sel = auto_cfg_active ? auto_mmio_wdata : gpu_mmio_wdata;
  assign gpu_mmio_rdata  = core_mmio_rdata;
  assign result_node_a   = result_node_a_reg;
  assign result_node_b   = result_node_b_reg;
  assign core_done_out   = core_done;

  initial begin
    for (i = 0; i < (1 << MEM_AW); i = i + 1) begin
      mem0[i] = 64'd0;
      mem1[i] = 64'd0;
    end

    program_rom[0] = gpu_instr(4'h2, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd1);
    program_rom[1] = 32'h00000000;
    program_rom[2] = gpu_instr(4'h3, 3'd0, 3'd0, 3'd0, 2'b10, 1'b0, 16'd0);
    program_rom[3] = gpu_instr(4'h2, 3'd1, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0);
    program_rom[4] = 32'h00000000;
    program_rom[5] = gpu_instr(4'h3, 3'd1, 3'd0, 3'd0, 2'b10, 1'b0, 16'd1);
    program_rom[6] = 32'h00000000;
    program_rom[7] = 32'h00000000;
    program_rom[8] = gpu_instr(4'hF, 3'd0, 3'd0, 3'd0, 2'b00, 1'b0, 16'd0);
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      for (j = 0; j < (1 << MEM_AW); j = j + 1) begin
        mem0[j] <= 64'd0;
        mem1[j] <= 64'd0;
      end

      mem0_rdata_reg      <= 64'd0;
      mem1_rdata_reg      <= 64'd0;
      mem0_rvalid_reg     <= 1'b0;
      mem1_rvalid_reg     <= 1'b0;
      hw_ofmap_mem_data_0 <= 32'd0;
      hw_ofmap_mem_data_1 <= 32'd0;
      result_node_a_reg   <= 32'd0;
      result_node_b_reg   <= 32'd0;
      core_done_d         <= 1'b0;
      program_idx         <= {IMEM_AW{1'b0}};
      program_loading     <= 1'b1;
      program_loaded      <= 1'b0;
      auto_cfg_active     <= 1'b0;
      auto_cfg_state      <= 3'd0;
      auto_start_only     <= 1'b0;
      cfg_seen            <= 1'b0;
      auto_mmio_wr_en     <= 1'b0;
      auto_mmio_addr      <= {MMIO_ADDR_W{1'b0}};
      auto_mmio_wdata     <= 32'd0;
    end else begin
      core_done_d     <= core_done;
      auto_mmio_wr_en <= 1'b0;
      mem0_rvalid_reg <= 1'b0;
      mem1_rvalid_reg <= 1'b0;

      if (gpu_mmio_wr_en &&
          ((gpu_mmio_addr == REG_ENTRY_PC) ||
           (gpu_mmio_addr == REG_WORK_SIZE) ||
           (gpu_mmio_addr == REG_BASE_A_LO) ||
           (gpu_mmio_addr == REG_BASE_C_LO))) begin
        cfg_seen <= 1'b1;
      end

      if (il_mem_wen) begin
        mem0[il_mem_addr[MEM_AW-1:0]] <= {32'd0, il_mem_wdata};
      end

      if (sw_w_mem_wen) begin
        mem1[sw_w_mem_addr[MEM_AW-1:0]] <= {sw_w_mem_wdata_1, sw_w_mem_wdata_0};
      end

      if (core_mem0_en) begin
        if (core_mem0_we) begin
          mem0[core_mem0_addr] <= core_mem0_wdata;
        end else begin
          mem0_rdata_reg  <= mem0[core_mem0_addr];
          mem0_rvalid_reg <= 1'b1;
        end
      end

      if (core_mem1_en) begin
        if (core_mem1_we) begin
          mem1[core_mem1_addr] <= core_mem1_wdata;
        end else begin
          mem1_rdata_reg  <= mem1[core_mem1_addr];
          mem1_rvalid_reg <= 1'b1;
        end
      end

      if (sw_ofmap_mem_ren) begin
        hw_ofmap_mem_data_0 <= mem0[sw_ofmap_mem_addr[MEM_AW-1:0]][31:0];
        hw_ofmap_mem_data_1 <= mem0[sw_ofmap_mem_addr[MEM_AW-1:0]][63:32];
      end

      if (program_loading) begin
        if (program_idx == PROGRAM_LEN-1) begin
          program_loading <= 1'b0;
          program_loaded  <= 1'b1;
        end
        program_idx <= program_idx + 1'b1;
      end

      if (!auto_cfg_active && program_loaded && start) begin
        auto_cfg_active <= 1'b1;
        auto_cfg_state  <= 3'd0;
        auto_start_only <= cfg_seen;
      end

      if (auto_cfg_active) begin
        auto_mmio_wr_en <= 1'b1;
        if (auto_start_only) begin
          auto_mmio_addr  <= REG_CONTROL;
          auto_mmio_wdata <= CTRL_START;
          auto_cfg_active <= 1'b0;
          auto_cfg_state  <= 3'd0;
        end else begin
          case (auto_cfg_state)
            3'd0: begin
              auto_mmio_addr  <= REG_ENTRY_PC;
              auto_mmio_wdata <= 32'd0;
              auto_cfg_state  <= 3'd1;
            end
            3'd1: begin
              auto_mmio_addr  <= REG_WORK_SIZE;
              auto_mmio_wdata <= 32'd1;
              auto_cfg_state  <= 3'd2;
            end
            3'd2: begin
              auto_mmio_addr  <= REG_BASE_A_LO;
              auto_mmio_wdata <= 32'd0;
              auto_cfg_state  <= 3'd3;
            end
            3'd3: begin
              auto_mmio_addr  <= REG_BASE_C_LO;
              auto_mmio_wdata <= NODE1_ADDR;
              auto_cfg_state  <= 3'd4;
            end
            default: begin
              auto_mmio_addr  <= REG_CONTROL;
              auto_mmio_wdata <= CTRL_START;
              auto_cfg_active <= 1'b0;
              auto_cfg_state  <= 3'd0;
            end
          endcase
        end
      end

      // Capture result values on GPU completion rising edge.
      // Drop decision is delegated to cpu_gpu_controller.
      if (core_done && !core_done_d) begin
        result_node_a_reg <= mem0[NODE1_ADDR][31:0];
        result_node_b_reg <= mem0[NODE2_ADDR][31:0];
      end
    end
  end

  gpu_top_fifo_if #(
    .MMIO_ADDR_W(MMIO_ADDR_W),
    .IMEM_AW    (IMEM_AW),
    .MEM_AW     (MEM_AW)
  ) u_gpu (
    .clk           (clk),
    .rst           (reset),
    .mmio_wr_en    (mmio_wr_sel),
    .mmio_rd_en    (mmio_rd_sel),
    .mmio_addr     (mmio_addr_sel),
    .mmio_wdata    (mmio_wdata_sel),
    .mmio_rdata    (core_mmio_rdata),
    .imem_prog_we  (program_loading),
    .imem_prog_addr(program_idx),
    .imem_prog_wdata(program_rom[program_idx]),
    .proc_active   (1'b1),
    .proc_done     (core_done),
    .mem0_en       (core_mem0_en),
    .mem0_we       (core_mem0_we),
    .mem0_addr     (core_mem0_addr),
    .mem0_wdata    (core_mem0_wdata),
    .mem0_rdata    (mem0_rdata_reg),
    .mem0_rvalid   (mem0_rvalid_reg),
    .mem1_en       (core_mem1_en),
    .mem1_we       (core_mem1_we),
    .mem1_addr     (core_mem1_addr),
    .mem1_wdata    (core_mem1_wdata),
    .mem1_rdata    (mem1_rdata_reg),
    .mem1_rvalid   (mem1_rvalid_reg),
    .dbg_pc        (dbg_pc),
    .busy          (gpu_busy)
  );

endmodule
