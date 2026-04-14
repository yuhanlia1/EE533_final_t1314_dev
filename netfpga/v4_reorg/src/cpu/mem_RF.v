module mem_RF #(
  parameter ADDR_WIDTH = 6, // 16 * 4 entries
  parameter DATA_WIDTH = 64
) (
  input wire clk,
  input wire we, // Write enable
  input wire [ADDR_WIDTH-1:0] waddr, // Write address
  input wire [DATA_WIDTH-1:0] wdata, // Write data

  input wire [ADDR_WIDTH-1:0] r0addr, // Read port 0 address (dedicated read)
  output reg [DATA_WIDTH-1:0] r0data, // Read port 0 data

  input wire [ADDR_WIDTH-1:0] r1addr, // Read port 1 address (shared with write)
  output reg [DATA_WIDTH-1:0] r1data  // Read port 1 data
);

  reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

  always @(posedge clk) begin
      if (we) begin
          mem[waddr] <= wdata;
      end
      r0data <= mem[r0addr];
      r1data <= mem[r1addr];
  end

endmodule
