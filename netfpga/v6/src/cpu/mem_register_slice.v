module mem_register_slice # (
  parameter NETWORK_DATA_WIDTH = 64,
  parameter NETWORK_CTRL_WIDTH = NETWORK_DATA_WIDTH / 8
) (
  input wire clk,
  input wire reset,

  // Producer Logics
  input  wire [NETWORK_DATA_WIDTH-1:0] s_data,
  input  wire [NETWORK_CTRL_WIDTH-1:0] s_ctrl,
  input  wire                          s_valid,
  output wire                          s_ready,

  // Consumer Logics
  output wire [NETWORK_DATA_WIDTH-1:0] m_data,
  output wire [NETWORK_CTRL_WIDTH-1:0] m_ctrl,
  output wire                          m_valid,
  input  wire                          m_ready
);

reg [NETWORK_DATA_WIDTH-1:0] mem_data [0:1];
reg [NETWORK_CTRL_WIDTH-1:0] mem_ctrl [0:1];
reg [1:0] rd_ptr;
reg [1:0] wr_ptr;

wire write_enable = s_valid && s_ready;
wire read_enable = m_valid && m_ready;

assign s_ready = !(wr_ptr[1] != rd_ptr[1] && wr_ptr[0] == rd_ptr[0]);
assign m_valid = wr_ptr != rd_ptr;
assign m_data = mem_data[rd_ptr[0]];
assign m_ctrl = mem_ctrl[rd_ptr[0]];

always @(posedge clk or posedge reset) begin
  if (reset) begin
    wr_ptr <= 2'b00;
    rd_ptr <= 2'b00;
    mem_data[0] <= {NETWORK_DATA_WIDTH{1'b0}};
    mem_data[1] <= {NETWORK_DATA_WIDTH{1'b0}};
    mem_ctrl[0] <= {NETWORK_CTRL_WIDTH{1'b0}};
    mem_ctrl[1] <= {NETWORK_CTRL_WIDTH{1'b0}};
  end else begin
    if (write_enable && !read_enable) begin
      mem_data[wr_ptr[0]] <= s_data;
      mem_ctrl[wr_ptr[0]] <= s_ctrl;
      wr_ptr         <= wr_ptr + 1'b1;
    end

    else if (read_enable && !write_enable) begin
      rd_ptr <= rd_ptr + 1'b1;
    end

    else if (write_enable && read_enable) begin
      rd_ptr <= rd_ptr + 1'b1;

      mem_data[wr_ptr[0]] <= s_data;
      mem_ctrl[wr_ptr[0]] <= s_ctrl;
      wr_ptr           <= wr_ptr + 1'b1;
    end
  end
end

endmodule
