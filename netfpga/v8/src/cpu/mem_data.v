module mem_data #(
  parameter ADDR_WIDTH = 8, // e.g., 256 entries
  parameter DATA_WIDTH = 64
) (
  input wire clk,
  input wire we, // Write enable
  input wire [ADDR_WIDTH-1:0] addr,  // Write address
  input wire [DATA_WIDTH-1:0] wdata, // Write data
  output reg [DATA_WIDTH-1:0] rdata  // Read data
);

  reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

  always @(posedge clk) begin
      if (we) begin
          mem[addr] <= wdata;
      end

      rdata <= mem[addr];
  end

endmodule
