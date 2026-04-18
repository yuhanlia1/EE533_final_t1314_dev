`timescale 1ns/1ps

module network_stream_slice #(
  parameter DATA_WIDTH = 64,
  parameter CTRL_WIDTH = DATA_WIDTH / 8
) (
  input                           clk,
  input                           reset,

  input  [DATA_WIDTH-1:0]         s_data,
  input  [CTRL_WIDTH-1:0]         s_ctrl,
  input                           s_valid,
  output                          s_ready,

  output [DATA_WIDTH-1:0]         m_data,
  output [CTRL_WIDTH-1:0]         m_ctrl,
  output                          m_valid,
  input                           m_ready
);

  reg [DATA_WIDTH-1:0] data_mem_0;
  reg [DATA_WIDTH-1:0] data_mem_1;
  reg [CTRL_WIDTH-1:0] ctrl_mem_0;
  reg [CTRL_WIDTH-1:0] ctrl_mem_1;
  reg [1:0] rd_ptr;
  reg [1:0] wr_ptr;

  wire write_enable;
  wire read_enable;

  assign write_enable = s_valid && s_ready;
  assign read_enable  = m_valid && m_ready;

  assign s_ready = !(wr_ptr[1] != rd_ptr[1] && wr_ptr[0] == rd_ptr[0]);
  assign m_valid = (wr_ptr != rd_ptr);
  assign m_data  = rd_ptr[0] ? data_mem_1 : data_mem_0;
  assign m_ctrl  = rd_ptr[0] ? ctrl_mem_1 : ctrl_mem_0;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      rd_ptr    <= 2'b00;
      wr_ptr    <= 2'b00;
      data_mem_0 <= {DATA_WIDTH{1'b0}};
      data_mem_1 <= {DATA_WIDTH{1'b0}};
      ctrl_mem_0 <= {CTRL_WIDTH{1'b0}};
      ctrl_mem_1 <= {CTRL_WIDTH{1'b0}};
    end
    else begin
      if (write_enable) begin
        if (wr_ptr[0]) begin
          data_mem_1 <= s_data;
          ctrl_mem_1 <= s_ctrl;
        end
        else begin
          data_mem_0 <= s_data;
          ctrl_mem_0 <= s_ctrl;
        end
        wr_ptr <= wr_ptr + 1'b1;
      end

      if (read_enable)
        rd_ptr <= rd_ptr + 1'b1;
    end
  end

endmodule
