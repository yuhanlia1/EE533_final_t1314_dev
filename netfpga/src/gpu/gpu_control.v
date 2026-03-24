module gpu_control #(
  parameter ADDR_W = 8
)(
  input  wire              clk,
  input  wire              rst,

  input  wire              mmio_wr_en,
  input  wire              mmio_rd_en,
  input  wire [ADDR_W-1:0] mmio_addr,
  input  wire [31:0]       mmio_wdata,
  output reg  [31:0]       mmio_rdata,

  input  wire              hw_done_pulse,
  input  wire              hw_error_pulse,
  input  wire [7:0]        hw_error_code,

  output wire              run_en,
  output reg               start_pulse,
  output reg               clear_done_pulse,
  output reg               soft_reset_pulse,

  output reg  [8:0]        entry_pc,
  output reg  [31:0]       tid_init,
  output reg  [31:0]       work_size,
  output reg  [31:0]       work_size_eff,
  output reg  [31:0]       m,
  output reg  [31:0]       n,
  output reg  [31:0]       k,

  output reg  [63:0]       base_a,
  output reg  [63:0]       base_b,
  output reg  [63:0]       base_c,
  output reg  [63:0]       base_d,

  output reg               busy,
  output reg               done,
  output reg               error,
  output reg  [7:0]        error_code
);

  localparam [ADDR_W-1:0] REG_CONTROL      = 8'h00;
  localparam [ADDR_W-1:0] REG_STATUS       = 8'h04;
  localparam [ADDR_W-1:0] REG_ENTRY_PC     = 8'h08;
  localparam [ADDR_W-1:0] REG_TID_INIT     = 8'h0C;
  localparam [ADDR_W-1:0] REG_WORK_SIZE    = 8'h10;

  localparam [ADDR_W-1:0] REG_BASE_A_LO    = 8'h20;
  localparam [ADDR_W-1:0] REG_BASE_A_HI    = 8'h24;
  localparam [ADDR_W-1:0] REG_BASE_B_LO    = 8'h28;
  localparam [ADDR_W-1:0] REG_BASE_B_HI    = 8'h2C;
  localparam [ADDR_W-1:0] REG_BASE_C_LO    = 8'h30;
  localparam [ADDR_W-1:0] REG_BASE_C_HI    = 8'h34;
  localparam [ADDR_W-1:0] REG_BASE_D_LO    = 8'h38;
  localparam [ADDR_W-1:0] REG_BASE_D_HI    = 8'h3C;

  localparam [ADDR_W-1:0] REG_M            = 8'h40;
  localparam [ADDR_W-1:0] REG_N            = 8'h44;
  localparam [ADDR_W-1:0] REG_K            = 8'h48;

  localparam [ADDR_W-1:0] REG_ERROR_CODE   = 8'h4C;

  localparam integer CTRL_START_BIT        = 0;
  localparam integer CTRL_CLEAR_DONE_BIT   = 1;
  localparam integer CTRL_SOFT_RESET_BIT   = 2;

  localparam integer STAT_BUSY_BIT         = 0;
  localparam integer STAT_DONE_BIT         = 1;
  localparam integer STAT_ERROR_BIT        = 2;

  localparam [7:0] ERR_NONE                = 8'h00;
  localparam [7:0] ERR_START_WHILE_BUSY    = 8'h01;
  localparam [7:0] ERR_PARAM_WRITE_BUSY    = 8'h02;

  reg [31:0] mn_p00_r;
  reg [31:0] mn_p01_r;
  reg [31:0] mn_p10_r;
  reg        mn_mul_v1;
  reg [31:0] mmio_rdata_next;

  assign run_en = busy;

  wire is_param_addr;
  assign is_param_addr =
      (mmio_addr == REG_ENTRY_PC)   |
      (mmio_addr == REG_TID_INIT)   |
      (mmio_addr == REG_WORK_SIZE)  |
      (mmio_addr == REG_BASE_A_LO)  |
      (mmio_addr == REG_BASE_A_HI)  |
      (mmio_addr == REG_BASE_B_LO)  |
      (mmio_addr == REG_BASE_B_HI)  |
      (mmio_addr == REG_BASE_C_LO)  |
      (mmio_addr == REG_BASE_C_HI)  |
      (mmio_addr == REG_BASE_D_LO)  |
      (mmio_addr == REG_BASE_D_HI)  |
      (mmio_addr == REG_M)          |
      (mmio_addr == REG_N)          |
      (mmio_addr == REG_K);

  always @(*) begin
    mmio_rdata_next = 32'h00000000;
    if (mmio_rd_en) begin
      case (mmio_addr)
        REG_STATUS: begin
          mmio_rdata_next = 32'h0;
          mmio_rdata_next[STAT_BUSY_BIT]  = busy;
          mmio_rdata_next[STAT_DONE_BIT]  = done;
          mmio_rdata_next[STAT_ERROR_BIT] = error;
        end
        REG_ENTRY_PC:   mmio_rdata_next = {23'd0, entry_pc};
        REG_TID_INIT:   mmio_rdata_next = tid_init;
        REG_WORK_SIZE:  mmio_rdata_next = work_size;
        REG_BASE_A_LO:  mmio_rdata_next = base_a[31:0];
        REG_BASE_A_HI:  mmio_rdata_next = base_a[63:32];
        REG_BASE_B_LO:  mmio_rdata_next = base_b[31:0];
        REG_BASE_B_HI:  mmio_rdata_next = base_b[63:32];
        REG_BASE_C_LO:  mmio_rdata_next = base_c[31:0];
        REG_BASE_C_HI:  mmio_rdata_next = base_c[63:32];
        REG_BASE_D_LO:  mmio_rdata_next = base_d[31:0];
        REG_BASE_D_HI:  mmio_rdata_next = base_d[63:32];
        REG_M:          mmio_rdata_next = m;
        REG_N:          mmio_rdata_next = n;
        REG_K:          mmio_rdata_next = k;
        REG_ERROR_CODE: mmio_rdata_next = {24'd0, error_code};
        default:        mmio_rdata_next = 32'h00000000;
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      mmio_rdata       <= 32'd0;
      busy             <= 1'b0;
      done             <= 1'b0;
      error            <= 1'b0;
      error_code       <= ERR_NONE;
      start_pulse      <= 1'b0;
      clear_done_pulse <= 1'b0;
      soft_reset_pulse <= 1'b0;
      entry_pc         <= 9'd0;
      tid_init         <= 32'd0;
      work_size        <= 32'd0;
      work_size_eff    <= 32'd0;
      m                <= 32'd0;
      n                <= 32'd0;
      k                <= 32'd0;
      base_a           <= 64'd0;
      base_b           <= 64'd0;
      base_c           <= 64'd0;
      base_d           <= 64'd0;
      mn_p00_r         <= 32'd0;
      mn_p01_r         <= 32'd0;
      mn_p10_r         <= 32'd0;
      mn_mul_v1        <= 1'b0;
    end else begin
      mmio_rdata       <= mmio_rdata_next;
      start_pulse      <= 1'b0;
      clear_done_pulse <= 1'b0;
      soft_reset_pulse <= 1'b0;

      if (mn_mul_v1) begin
        work_size_eff <= mn_p00_r + ((mn_p01_r + mn_p10_r) << 16);
        mn_mul_v1     <= 1'b0;
      end

      if (hw_done_pulse) begin
        busy <= 1'b0;
        done <= 1'b1;
      end

      if (hw_error_pulse) begin
        busy       <= 1'b0;
        error      <= 1'b1;
        error_code <= hw_error_code;
      end

      if (mmio_wr_en) begin
        if (mmio_addr == REG_CONTROL) begin
          if (mmio_wdata[CTRL_SOFT_RESET_BIT]) begin
            soft_reset_pulse <= 1'b1;
            busy             <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;
            error_code       <= ERR_NONE;
            entry_pc         <= 9'd0;
            tid_init         <= 32'd0;
            work_size        <= 32'd0;
            work_size_eff    <= 32'd0;
            m                <= 32'd0;
            n                <= 32'd0;
            k                <= 32'd0;
            base_a           <= 64'd0;
            base_b           <= 64'd0;
            base_c           <= 64'd0;
            base_d           <= 64'd0;
            mn_p00_r         <= 32'd0;
            mn_p01_r         <= 32'd0;
            mn_p10_r         <= 32'd0;
            mn_mul_v1        <= 1'b0;
          end

          if (mmio_wdata[CTRL_CLEAR_DONE_BIT]) begin
            clear_done_pulse <= 1'b1;
            done             <= 1'b0;
          end

          if (mmio_wdata[CTRL_START_BIT]) begin
            if (busy) begin
              error      <= 1'b1;
              error_code <= ERR_START_WHILE_BUSY;
            end else begin
              start_pulse <= 1'b1;
              busy        <= 1'b1;
              done        <= 1'b0;
              error       <= 1'b0;
              error_code  <= ERR_NONE;
              if (work_size != 32'd0) begin
                work_size_eff <= work_size;
                mn_mul_v1     <= 1'b0;
              end else begin
                mn_p00_r      <= m[15:0]  * n[15:0];
                mn_p01_r      <= m[15:0]  * n[31:16];
                mn_p10_r      <= m[31:16] * n[15:0];
                mn_mul_v1     <= 1'b1;
              end
            end
          end
        end else begin
          if (busy && is_param_addr) begin
            error      <= 1'b1;
            error_code <= ERR_PARAM_WRITE_BUSY;
          end else begin
            case (mmio_addr)
              REG_ENTRY_PC:   entry_pc      <= mmio_wdata[8:0];
              REG_TID_INIT:   tid_init      <= mmio_wdata;
              REG_WORK_SIZE:  work_size     <= mmio_wdata;
              REG_BASE_A_LO:  base_a[31:0]  <= mmio_wdata;
              REG_BASE_A_HI:  base_a[63:32] <= mmio_wdata;
              REG_BASE_B_LO:  base_b[31:0]  <= mmio_wdata;
              REG_BASE_B_HI:  base_b[63:32] <= mmio_wdata;
              REG_BASE_C_LO:  base_c[31:0]  <= mmio_wdata;
              REG_BASE_C_HI:  base_c[63:32] <= mmio_wdata;
              REG_BASE_D_LO:  base_d[31:0]  <= mmio_wdata;
              REG_BASE_D_HI:  base_d[63:32] <= mmio_wdata;
              REG_M:          m             <= mmio_wdata;
              REG_N:          n             <= mmio_wdata;
              REG_K:          k             <= mmio_wdata;
              default: begin end
            endcase
          end
        end
      end
    end
  end

endmodule