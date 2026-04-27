`timescale 1ns/1ps

(* blackbox *)
module fakeram45_1024x32 (
  output [31:0] rd_out,
  input  [9:0]  addr_in,
  input         we_in,
  input  [31:0] wd_in,
  input         clk,
  input         ce_in,
  input  [31:0] w_mask_in
);
endmodule

(* blackbox *)
module fakeram45_256x32 (
  output [31:0] rd_out,
  input  [7:0]  addr_in,
  input         we_in,
  input  [31:0] wd_in,
  input         clk,
  input         ce_in,
  input  [31:0] w_mask_in
);
endmodule

(* blackbox *)
module fakeram45_256x16 (
  output [15:0] rd_out,
  input  [7:0]  addr_in,
  input         we_in,
  input  [15:0] wd_in,
  input         clk,
  input         ce_in,
  input  [15:0] w_mask_in
);
endmodule

(* blackbox *)
module placeholder_fifo_bram_256x72_dp (
  input         clka,
  input         wea,
  input  [7:0]  addra,
  input  [71:0] dina,
  output [71:0] douta,
  input         clkb,
  input         web,
  input  [7:0]  addrb,
  input  [71:0] dinb,
  output [71:0] doutb
);
endmodule

(* blackbox *)
module placeholder_gpu_shared_dmem_16384x64_dp (
  input          clk,
  input          a_en,
  input          a_we,
  input  [13:0]  a_addr,
  input  [63:0]  a_wdata,
  output [63:0]  a_rdata,
  output         a_rvalid,
  input          b_en,
  input          b_we,
  input  [13:0]  b_addr,
  input  [63:0]  b_wdata,
  output [63:0]  b_rdata,
  output         b_rvalid
);
endmodule

(* blackbox *)
module placeholder_mem_rf_64x64_1w2r (
  input         clk,
  input         we,
  input  [5:0]  waddr,
  input  [63:0] wdata,
  input  [5:0]  r0addr,
  output [63:0] r0data,
  input  [5:0]  r1addr,
  output [63:0] r1data
);
endmodule

module mem_inst #(
  parameter ADDR_WIDTH = 9,
  parameter DATA_WIDTH = 32
) (
  input                  clk,
  input                  we,
  input  [ADDR_WIDTH-1:0] addr,
  input  [DATA_WIDTH-1:0] wdata,
  output [DATA_WIDTH-1:0] rdata
);
  wire [9:0]  phys_addr;
  wire [31:0] phys_rdata;

  assign phys_addr = {{(10-ADDR_WIDTH){1'b0}}, addr};
  assign rdata = phys_rdata[DATA_WIDTH-1:0];

  fakeram45_1024x32 u_mem (
    .rd_out   (phys_rdata),
    .addr_in  (phys_addr),
    .we_in    (we),
    .wd_in    (wdata[31:0]),
    .clk      (clk),
    .ce_in    (1'b1),
    .w_mask_in({32{we}})
  );
endmodule

module mem_data #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64
) (
  input                   clk,
  input                   we,
  input  [ADDR_WIDTH-1:0] addr,
  input  [DATA_WIDTH-1:0] wdata,
  output [DATA_WIDTH-1:0] rdata
);
  generate
    if (DATA_WIDTH == 64) begin : gen_data_64
      wire [31:0] rdata_lo;
      wire [31:0] rdata_hi;
      assign rdata = {rdata_hi, rdata_lo};

      fakeram45_256x32 u_mem_lo (
        .rd_out   (rdata_lo),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata[31:0]),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );

      fakeram45_256x32 u_mem_hi (
        .rd_out   (rdata_hi),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata[63:32]),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else if (DATA_WIDTH == 32) begin : gen_data_32
      wire [31:0] phys_rdata;
      assign rdata = phys_rdata;

      fakeram45_256x32 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else begin : gen_data_16
      wire [15:0] phys_wdata;
      wire [15:0] phys_rdata;
      assign phys_wdata = {{(16-DATA_WIDTH){1'b0}}, wdata};
      assign rdata = phys_rdata[DATA_WIDTH-1:0];

      fakeram45_256x16 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (phys_wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({{(16-DATA_WIDTH){1'b0}}, {DATA_WIDTH{we}}})
      );
    end
  endgenerate
endmodule

module gpu_imem #(
  parameter AW = 9,
  parameter DW = 32,
  parameter DEPTH = 512
) (
  input              clk,
  input              we,
  input  [AW-1:0]    addr,
  input  [DW-1:0]    wdata,
  output reg [DW-1:0] rdata
);
  generate
    if (DEPTH <= 1024) begin : gen_single_bank
      wire [31:0] phys_rdata;
      wire [9:0]  phys_addr;
      assign phys_addr = {{(10-AW){1'b0}}, addr};

      always @(*) begin
        rdata = phys_rdata;
      end

      fakeram45_1024x32 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (phys_addr),
        .we_in    (we),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else begin : gen_four_bank
      wire [11:0] phys_addr;
      wire [1:0]  bank_sel;
      wire [9:0]  bank_addr;
      wire [31:0] bank_rdata0;
      wire [31:0] bank_rdata1;
      wire [31:0] bank_rdata2;
      wire [31:0] bank_rdata3;
      reg  [1:0]  bank_sel_q;

      assign phys_addr = {{(12-AW){1'b0}}, addr};
      assign bank_sel = phys_addr[11:10];
      assign bank_addr = phys_addr[9:0];

      always @(posedge clk) begin
        bank_sel_q <= bank_sel;
      end

      always @(*) begin
        case (bank_sel_q)
          2'd0: rdata = bank_rdata0;
          2'd1: rdata = bank_rdata1;
          2'd2: rdata = bank_rdata2;
          default: rdata = bank_rdata3;
        endcase
      end

      fakeram45_1024x32 u_mem0 (
        .rd_out   (bank_rdata0),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd0)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd0),
        .w_mask_in({32{we && (bank_sel == 2'd0)}})
      );

      fakeram45_1024x32 u_mem1 (
        .rd_out   (bank_rdata1),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd1)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd1),
        .w_mask_in({32{we && (bank_sel == 2'd1)}})
      );

      fakeram45_1024x32 u_mem2 (
        .rd_out   (bank_rdata2),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd2)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd2),
        .w_mask_in({32{we && (bank_sel == 2'd2)}})
      );

      fakeram45_1024x32 u_mem3 (
        .rd_out   (bank_rdata3),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd3)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd3),
        .w_mask_in({32{we && (bank_sel == 2'd3)}})
      );
    end
  endgenerate
endmodule

module fifo_bram #(
  parameter DATA_WIDTH = 72,
  parameter ADDR_WIDTH = 8
) (
  input                    clka,
  input                    wea,
  input  [ADDR_WIDTH-1:0]  addra,
  input  [DATA_WIDTH-1:0]  dina,
  output [DATA_WIDTH-1:0]  douta,
  input                    clkb,
  input                    web,
  input  [ADDR_WIDTH-1:0]  addrb,
  input  [DATA_WIDTH-1:0]  dinb,
  output [DATA_WIDTH-1:0]  doutb
);
  placeholder_fifo_bram_256x72_dp u_macro (
    .clka  (clka),
    .wea   (wea),
    .addra (addra[7:0]),
    .dina  (dina[71:0]),
    .douta (douta),
    .clkb  (clkb),
    .web   (web),
    .addrb (addrb[7:0]),
    .dinb  (dinb[71:0]),
    .doutb (doutb)
  );
endmodule

module gpu_shared_dmem #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input                   clk,
  input                   a_en,
  input                   a_we,
  input  [ADDR_WIDTH-1:0] a_addr,
  input  [DATA_WIDTH-1:0] a_wdata,
  output [DATA_WIDTH-1:0] a_rdata,
  output                  a_rvalid,
  input                   b_en,
  input                   b_we,
  input  [ADDR_WIDTH-1:0] b_addr,
  input  [DATA_WIDTH-1:0] b_wdata,
  output [DATA_WIDTH-1:0] b_rdata,
  output                  b_rvalid
);
  placeholder_gpu_shared_dmem_16384x64_dp u_macro (
    .clk     (clk),
    .a_en    (a_en),
    .a_we    (a_we),
    .a_addr  (a_addr[13:0]),
    .a_wdata (a_wdata[63:0]),
    .a_rdata (a_rdata),
    .a_rvalid(a_rvalid),
    .b_en    (b_en),
    .b_we    (b_we),
    .b_addr  (b_addr[13:0]),
    .b_wdata (b_wdata[63:0]),
    .b_rdata (b_rdata),
    .b_rvalid(b_rvalid)
  );
endmodule

module mem_RF #(
  parameter ADDR_WIDTH = 6,
  parameter DATA_WIDTH = 64
) (
  input                   clk,
  input                   we,
  input  [ADDR_WIDTH-1:0] waddr,
  input  [DATA_WIDTH-1:0] wdata,
  input  [ADDR_WIDTH-1:0] r0addr,
  output [DATA_WIDTH-1:0] r0data,
  input  [ADDR_WIDTH-1:0] r1addr,
  output [DATA_WIDTH-1:0] r1data
);
  placeholder_mem_rf_64x64_1w2r u_macro (
    .clk   (clk),
    .we    (we),
    .waddr (waddr[5:0]),
    .wdata (wdata[63:0]),
    .r0addr(r0addr[5:0]),
    .r0data(r0data),
    .r1addr(r1addr[5:0]),
    .r1data(r1data)
  );
endmodule
