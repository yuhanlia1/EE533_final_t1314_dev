// DATA_WIDTH: 72 x 2**ADDR_WIDTH: 8 = 18KB
`timescale 1ns/1ps

module fifo_bram #(
    parameter DATA_WIDTH = 72,
    parameter ADDR_WIDTH = 8   
) (
    input                           clka    ,   // portal A
    input                           wea     ,
    input       [ADDR_WIDTH-1:0]    addra   ,
    input       [DATA_WIDTH-1:0]    dina    ,
    output reg  [DATA_WIDTH-1:0]    douta   ,

    input                           clkb    ,   // portal B
    input                           web     ,
    input       [ADDR_WIDTH-1:0]    addrb   ,
    input       [DATA_WIDTH-1:0]    dinb    ,
    output reg  [DATA_WIDTH-1:0]    doutb
);

reg [DATA_WIDTH-1:0] mem [0 : (1<<ADDR_WIDTH) - 1];

always @(posedge clka) begin
    if (wea)
        mem[addra] <= dina;
    douta <= mem[addra];
end

always @(posedge clkb) begin
    if (web)
        mem[addrb] <= dinb;
    doutb <= mem[addrb];
end

endmodule

