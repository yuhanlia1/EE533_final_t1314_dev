////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2008 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor: Xilinx
// \   \   \/     Version: K.31
//  \   \         Application: netgen
//  /   /         Filename: bf16_mult.v
// /___/   /\     Timestamp: Mon Mar 30 20:33:00 2026
// \   \  /  \ 
//  \___\/\___\
//             
// Command	: -intstyle ise -w -sim -ofmt verilog "C:\Documents and Settings\student\Desktop\integrated\tmp\_cg\bf16_mult.ngc" "C:\Documents and Settings\student\Desktop\integrated\tmp\_cg\bf16_mult.v" 
// Device	: 2vp2fg256-6
// Input file	: C:/Documents and Settings/student/Desktop/integrated/tmp/_cg/bf16_mult.ngc
// Output file	: C:/Documents and Settings/student/Desktop/integrated/tmp/_cg/bf16_mult.v
// # of Modules	: 1
// Design Name	: bf16_mult
// Xilinx        : C:\Xilinx\10.1\ISE
//             
// Purpose:    
//     This verilog netlist is a verification model and uses simulation 
//     primitives which may not represent the true implementation of the 
//     device, however the netlist is functionally correct and should not 
//     be modified. This file cannot be synthesized and should only be used 
//     with supported simulation tools.
//             
// Reference:  
//     Development System Reference Guide, Chapter 23 and Synthesis and Simulation Design Guide, Chapter 6
//             
////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns/1 ps

module bf16_mult (
  clk, a, b, result
);
  input clk;
  input [15 : 0] a;
  input [15 : 0] b;
  output [15 : 0] result;
  
  // synthesis translate_off
  
  wire sig00000001;
  wire sig00000002;
  wire sig00000003;
  wire sig00000004;
  wire sig00000005;
  wire sig00000006;
  wire sig00000007;
  wire sig00000008;
  wire sig00000009;
  wire sig0000000a;
  wire sig0000000b;
  wire sig0000000c;
  wire sig0000000d;
  wire sig0000000e;
  wire sig0000000f;
  wire sig00000010;
  wire sig00000011;
  wire sig00000012;
  wire sig00000013;
  wire sig00000014;
  wire sig00000015;
  wire sig00000016;
  wire sig00000017;
  wire sig00000018;
  wire sig00000019;
  wire sig0000001a;
  wire sig0000001b;
  wire sig0000001c;
  wire sig0000001d;
  wire sig0000001e;
  wire sig0000001f;
  wire sig00000020;
  wire sig00000021;
  wire sig00000022;
  wire sig00000023;
  wire sig00000024;
  wire sig00000025;
  wire sig00000026;
  wire sig00000027;
  wire sig00000028;
  wire sig00000029;
  wire sig0000002a;
  wire sig0000002b;
  wire sig0000002c;
  wire sig0000002d;
  wire sig0000002e;
  wire sig0000002f;
  wire sig00000030;
  wire sig00000031;
  wire \blk00000003/sig0000024c ;
  wire \blk00000003/sig0000024b ;
  wire \blk00000003/sig0000024a ;
  wire \blk00000003/sig00000249 ;
  wire \blk00000003/sig00000248 ;
  wire \blk00000003/sig00000247 ;
  wire \blk00000003/sig00000246 ;
  wire \blk00000003/sig00000245 ;
  wire \blk00000003/sig00000244 ;
  wire \blk00000003/sig00000243 ;
  wire \blk00000003/sig00000242 ;
  wire \blk00000003/sig00000241 ;
  wire \blk00000003/sig00000240 ;
  wire \blk00000003/sig0000023f ;
  wire \blk00000003/sig0000023e ;
  wire \blk00000003/sig0000023d ;
  wire \blk00000003/sig0000023c ;
  wire \blk00000003/sig0000023b ;
  wire \blk00000003/sig0000023a ;
  wire \blk00000003/sig00000239 ;
  wire \blk00000003/sig00000238 ;
  wire \blk00000003/sig00000237 ;
  wire \blk00000003/sig00000236 ;
  wire \blk00000003/sig00000235 ;
  wire \blk00000003/sig00000234 ;
  wire \blk00000003/sig00000233 ;
  wire \blk00000003/sig00000232 ;
  wire \blk00000003/sig00000231 ;
  wire \blk00000003/sig00000230 ;
  wire \blk00000003/sig0000022f ;
  wire \blk00000003/sig0000022e ;
  wire \blk00000003/sig0000022d ;
  wire \blk00000003/sig0000022c ;
  wire \blk00000003/sig0000022b ;
  wire \blk00000003/sig0000022a ;
  wire \blk00000003/sig00000229 ;
  wire \blk00000003/sig00000228 ;
  wire \blk00000003/sig00000227 ;
  wire \blk00000003/sig00000226 ;
  wire \blk00000003/sig00000225 ;
  wire \blk00000003/sig00000224 ;
  wire \blk00000003/sig00000223 ;
  wire \blk00000003/sig00000222 ;
  wire \blk00000003/sig00000221 ;
  wire \blk00000003/sig00000220 ;
  wire \blk00000003/sig0000021f ;
  wire \blk00000003/sig0000021e ;
  wire \blk00000003/sig0000021d ;
  wire \blk00000003/sig0000021c ;
  wire \blk00000003/sig0000021b ;
  wire \blk00000003/sig0000021a ;
  wire \blk00000003/sig00000219 ;
  wire \blk00000003/sig00000218 ;
  wire \blk00000003/sig00000217 ;
  wire \blk00000003/sig00000216 ;
  wire \blk00000003/sig00000215 ;
  wire \blk00000003/sig00000214 ;
  wire \blk00000003/sig00000213 ;
  wire \blk00000003/sig00000212 ;
  wire \blk00000003/sig00000211 ;
  wire \blk00000003/sig00000210 ;
  wire \blk00000003/sig0000020f ;
  wire \blk00000003/sig0000020e ;
  wire \blk00000003/sig0000020d ;
  wire \blk00000003/sig0000020c ;
  wire \blk00000003/sig0000020b ;
  wire \blk00000003/sig0000020a ;
  wire \blk00000003/sig00000209 ;
  wire \blk00000003/sig00000208 ;
  wire \blk00000003/sig00000207 ;
  wire \blk00000003/sig00000206 ;
  wire \blk00000003/sig00000205 ;
  wire \blk00000003/sig00000204 ;
  wire \blk00000003/sig00000203 ;
  wire \blk00000003/sig00000202 ;
  wire \blk00000003/sig00000201 ;
  wire \blk00000003/sig00000200 ;
  wire \blk00000003/sig000001ff ;
  wire \blk00000003/sig000001fe ;
  wire \blk00000003/sig000001fd ;
  wire \blk00000003/sig000001fc ;
  wire \blk00000003/sig000001fb ;
  wire \blk00000003/sig000001fa ;
  wire \blk00000003/sig000001f9 ;
  wire \blk00000003/sig000001f8 ;
  wire \blk00000003/sig000001f7 ;
  wire \blk00000003/sig000001f6 ;
  wire \blk00000003/sig000001f5 ;
  wire \blk00000003/sig000001f4 ;
  wire \blk00000003/sig000001f3 ;
  wire \blk00000003/sig000001f2 ;
  wire \blk00000003/sig000001f1 ;
  wire \blk00000003/sig000001f0 ;
  wire \blk00000003/sig000001ef ;
  wire \blk00000003/sig000001ee ;
  wire \blk00000003/sig000001ed ;
  wire \blk00000003/sig000001ec ;
  wire \blk00000003/sig000001eb ;
  wire \blk00000003/sig000001ea ;
  wire \blk00000003/sig000001e9 ;
  wire \blk00000003/sig000001e8 ;
  wire \blk00000003/sig000001e7 ;
  wire \blk00000003/sig000001e6 ;
  wire \blk00000003/sig000001e5 ;
  wire \blk00000003/sig000001e4 ;
  wire \blk00000003/sig000001e3 ;
  wire \blk00000003/sig000001e2 ;
  wire \blk00000003/sig000001e1 ;
  wire \blk00000003/sig000001e0 ;
  wire \blk00000003/sig000001df ;
  wire \blk00000003/sig000001de ;
  wire \blk00000003/sig000001dd ;
  wire \blk00000003/sig000001dc ;
  wire \blk00000003/sig000001db ;
  wire \blk00000003/sig000001da ;
  wire \blk00000003/sig000001d9 ;
  wire \blk00000003/sig000001d8 ;
  wire \blk00000003/sig000001d7 ;
  wire \blk00000003/sig000001d6 ;
  wire \blk00000003/sig000001d5 ;
  wire \blk00000003/sig000001d4 ;
  wire \blk00000003/sig000001d3 ;
  wire \blk00000003/sig000001d2 ;
  wire \blk00000003/sig000001d1 ;
  wire \blk00000003/sig000001d0 ;
  wire \blk00000003/sig000001cf ;
  wire \blk00000003/sig000001ce ;
  wire \blk00000003/sig000001cd ;
  wire \blk00000003/sig000001cc ;
  wire \blk00000003/sig000001cb ;
  wire \blk00000003/sig000001ca ;
  wire \blk00000003/sig000001c9 ;
  wire \blk00000003/sig000001c8 ;
  wire \blk00000003/sig000001c7 ;
  wire \blk00000003/sig000001c6 ;
  wire \blk00000003/sig000001c5 ;
  wire \blk00000003/sig000001c4 ;
  wire \blk00000003/sig000001c3 ;
  wire \blk00000003/sig000001c2 ;
  wire \blk00000003/sig000001c1 ;
  wire \blk00000003/sig000001c0 ;
  wire \blk00000003/sig000001bf ;
  wire \blk00000003/sig000001be ;
  wire \blk00000003/sig000001bd ;
  wire \blk00000003/sig000001bc ;
  wire \blk00000003/sig000001bb ;
  wire \blk00000003/sig000001ba ;
  wire \blk00000003/sig000001b9 ;
  wire \blk00000003/sig000001b8 ;
  wire \blk00000003/sig000001b7 ;
  wire \blk00000003/sig000001b6 ;
  wire \blk00000003/sig000001b5 ;
  wire \blk00000003/sig000001b4 ;
  wire \blk00000003/sig000001b3 ;
  wire \blk00000003/sig000001b2 ;
  wire \blk00000003/sig000001b1 ;
  wire \blk00000003/sig000001b0 ;
  wire \blk00000003/sig000001af ;
  wire \blk00000003/sig000001ae ;
  wire \blk00000003/sig000001ad ;
  wire \blk00000003/sig000001ac ;
  wire \blk00000003/sig000001ab ;
  wire \blk00000003/sig000001aa ;
  wire \blk00000003/sig000001a9 ;
  wire \blk00000003/sig000001a8 ;
  wire \blk00000003/sig000001a7 ;
  wire \blk00000003/sig000001a6 ;
  wire \blk00000003/sig000001a5 ;
  wire \blk00000003/sig000001a4 ;
  wire \blk00000003/sig000001a3 ;
  wire \blk00000003/sig000001a2 ;
  wire \blk00000003/sig000001a1 ;
  wire \blk00000003/sig000001a0 ;
  wire \blk00000003/sig0000019f ;
  wire \blk00000003/sig0000019e ;
  wire \blk00000003/sig0000019d ;
  wire \blk00000003/sig0000019c ;
  wire \blk00000003/sig0000019b ;
  wire \blk00000003/sig0000019a ;
  wire \blk00000003/sig00000199 ;
  wire \blk00000003/sig00000198 ;
  wire \blk00000003/sig00000197 ;
  wire \blk00000003/sig00000196 ;
  wire \blk00000003/sig00000195 ;
  wire \blk00000003/sig00000194 ;
  wire \blk00000003/sig00000193 ;
  wire \blk00000003/sig00000192 ;
  wire \blk00000003/sig00000191 ;
  wire \blk00000003/sig00000190 ;
  wire \blk00000003/sig0000018f ;
  wire \blk00000003/sig0000018e ;
  wire \blk00000003/sig0000018d ;
  wire \blk00000003/sig0000018c ;
  wire \blk00000003/sig0000018b ;
  wire \blk00000003/sig0000018a ;
  wire \blk00000003/sig00000189 ;
  wire \blk00000003/sig00000188 ;
  wire \blk00000003/sig00000187 ;
  wire \blk00000003/sig00000186 ;
  wire \blk00000003/sig00000185 ;
  wire \blk00000003/sig00000184 ;
  wire \blk00000003/sig00000183 ;
  wire \blk00000003/sig00000182 ;
  wire \blk00000003/sig00000181 ;
  wire \blk00000003/sig00000180 ;
  wire \blk00000003/sig0000017f ;
  wire \blk00000003/sig0000017e ;
  wire \blk00000003/sig0000017d ;
  wire \blk00000003/sig0000017c ;
  wire \blk00000003/sig0000017b ;
  wire \blk00000003/sig0000017a ;
  wire \blk00000003/sig00000179 ;
  wire \blk00000003/sig00000178 ;
  wire \blk00000003/sig00000177 ;
  wire \blk00000003/sig00000176 ;
  wire \blk00000003/sig00000175 ;
  wire \blk00000003/sig00000174 ;
  wire \blk00000003/sig00000173 ;
  wire \blk00000003/sig00000172 ;
  wire \blk00000003/sig00000171 ;
  wire \blk00000003/sig00000170 ;
  wire \blk00000003/sig0000016f ;
  wire \blk00000003/sig0000016e ;
  wire \blk00000003/sig0000016d ;
  wire \blk00000003/sig0000016c ;
  wire \blk00000003/sig0000016b ;
  wire \blk00000003/sig0000016a ;
  wire \blk00000003/sig00000169 ;
  wire \blk00000003/sig00000168 ;
  wire \blk00000003/sig00000167 ;
  wire \blk00000003/sig00000166 ;
  wire \blk00000003/sig00000165 ;
  wire \blk00000003/sig00000164 ;
  wire \blk00000003/sig00000163 ;
  wire \blk00000003/sig00000162 ;
  wire \blk00000003/sig00000161 ;
  wire \blk00000003/sig00000160 ;
  wire \blk00000003/sig0000015f ;
  wire \blk00000003/sig0000015e ;
  wire \blk00000003/sig0000015d ;
  wire \blk00000003/sig0000015c ;
  wire \blk00000003/sig0000015b ;
  wire \blk00000003/sig0000015a ;
  wire \blk00000003/sig00000159 ;
  wire \blk00000003/sig00000158 ;
  wire \blk00000003/sig00000157 ;
  wire \blk00000003/sig00000156 ;
  wire \blk00000003/sig00000155 ;
  wire \blk00000003/sig00000154 ;
  wire \blk00000003/sig00000153 ;
  wire \blk00000003/sig00000152 ;
  wire \blk00000003/sig00000151 ;
  wire \blk00000003/sig00000150 ;
  wire \blk00000003/sig0000014f ;
  wire \blk00000003/sig0000014e ;
  wire \blk00000003/sig0000014d ;
  wire \blk00000003/sig0000014c ;
  wire \blk00000003/sig0000014b ;
  wire \blk00000003/sig0000014a ;
  wire \blk00000003/sig00000149 ;
  wire \blk00000003/sig00000148 ;
  wire \blk00000003/sig00000147 ;
  wire \blk00000003/sig00000146 ;
  wire \blk00000003/sig00000145 ;
  wire \blk00000003/sig00000144 ;
  wire \blk00000003/sig00000143 ;
  wire \blk00000003/sig00000142 ;
  wire \blk00000003/sig00000141 ;
  wire \blk00000003/sig00000140 ;
  wire \blk00000003/sig0000013f ;
  wire \blk00000003/sig0000013e ;
  wire \blk00000003/sig0000013d ;
  wire \blk00000003/sig0000013c ;
  wire \blk00000003/sig0000013b ;
  wire \blk00000003/sig0000013a ;
  wire \blk00000003/sig00000139 ;
  wire \blk00000003/sig00000138 ;
  wire \blk00000003/sig00000137 ;
  wire \blk00000003/sig00000136 ;
  wire \blk00000003/sig00000135 ;
  wire \blk00000003/sig00000134 ;
  wire \blk00000003/sig00000133 ;
  wire \blk00000003/sig00000132 ;
  wire \blk00000003/sig00000131 ;
  wire \blk00000003/sig00000130 ;
  wire \blk00000003/sig0000012f ;
  wire \blk00000003/sig0000012e ;
  wire \blk00000003/sig0000012d ;
  wire \blk00000003/sig0000012c ;
  wire \blk00000003/sig0000012b ;
  wire \blk00000003/sig0000012a ;
  wire \blk00000003/sig00000129 ;
  wire \blk00000003/sig00000128 ;
  wire \blk00000003/sig00000127 ;
  wire \blk00000003/sig00000126 ;
  wire \blk00000003/sig00000125 ;
  wire \blk00000003/sig00000124 ;
  wire \blk00000003/sig00000123 ;
  wire \blk00000003/sig00000122 ;
  wire \blk00000003/sig00000121 ;
  wire \blk00000003/sig00000120 ;
  wire \blk00000003/sig0000011f ;
  wire \blk00000003/sig0000011e ;
  wire \blk00000003/sig0000011d ;
  wire \blk00000003/sig0000011c ;
  wire \blk00000003/sig0000011b ;
  wire \blk00000003/sig0000011a ;
  wire \blk00000003/sig00000119 ;
  wire \blk00000003/sig00000118 ;
  wire \blk00000003/sig00000117 ;
  wire \blk00000003/sig00000116 ;
  wire \blk00000003/sig00000115 ;
  wire \blk00000003/sig00000114 ;
  wire \blk00000003/sig00000113 ;
  wire \blk00000003/sig00000112 ;
  wire \blk00000003/sig00000111 ;
  wire \blk00000003/sig00000110 ;
  wire \blk00000003/sig0000010f ;
  wire \blk00000003/sig0000010e ;
  wire \blk00000003/sig0000010d ;
  wire \blk00000003/sig0000010c ;
  wire \blk00000003/sig0000010b ;
  wire \blk00000003/sig0000010a ;
  wire \blk00000003/sig00000109 ;
  wire \blk00000003/sig00000108 ;
  wire \blk00000003/sig00000107 ;
  wire \blk00000003/sig00000106 ;
  wire \blk00000003/sig00000105 ;
  wire \blk00000003/sig00000104 ;
  wire \blk00000003/sig00000103 ;
  wire \blk00000003/sig00000102 ;
  wire \blk00000003/sig00000101 ;
  wire \blk00000003/sig00000100 ;
  wire \blk00000003/sig000000ff ;
  wire \blk00000003/sig000000fe ;
  wire \blk00000003/sig000000fd ;
  wire \blk00000003/sig000000fc ;
  wire \blk00000003/sig000000fb ;
  wire \blk00000003/sig000000fa ;
  wire \blk00000003/sig000000f9 ;
  wire \blk00000003/sig000000f8 ;
  wire \blk00000003/sig000000f7 ;
  wire \blk00000003/sig000000f6 ;
  wire \blk00000003/sig000000f5 ;
  wire \blk00000003/sig000000f4 ;
  wire \blk00000003/sig000000f3 ;
  wire \blk00000003/sig000000f2 ;
  wire \blk00000003/sig000000f1 ;
  wire \blk00000003/sig000000f0 ;
  wire \blk00000003/sig000000ef ;
  wire \blk00000003/sig000000ee ;
  wire \blk00000003/sig000000ed ;
  wire \blk00000003/sig000000ec ;
  wire \blk00000003/sig000000eb ;
  wire \blk00000003/sig000000ea ;
  wire \blk00000003/sig000000e9 ;
  wire \blk00000003/sig000000e8 ;
  wire \blk00000003/sig000000e7 ;
  wire \blk00000003/sig000000e6 ;
  wire \blk00000003/sig000000e5 ;
  wire \blk00000003/sig000000e4 ;
  wire \blk00000003/sig000000e3 ;
  wire \blk00000003/sig000000e2 ;
  wire \blk00000003/sig000000e1 ;
  wire \blk00000003/sig000000e0 ;
  wire \blk00000003/sig000000df ;
  wire \blk00000003/sig000000de ;
  wire \blk00000003/sig000000dd ;
  wire \blk00000003/sig000000dc ;
  wire \blk00000003/sig000000db ;
  wire \blk00000003/sig000000da ;
  wire \blk00000003/sig000000d9 ;
  wire \blk00000003/sig000000d8 ;
  wire \blk00000003/sig000000d7 ;
  wire \blk00000003/sig000000d6 ;
  wire \blk00000003/sig000000d5 ;
  wire \blk00000003/sig000000d4 ;
  wire \blk00000003/sig000000d3 ;
  wire \blk00000003/sig000000d2 ;
  wire \blk00000003/sig000000d1 ;
  wire \blk00000003/sig000000d0 ;
  wire \blk00000003/sig000000cf ;
  wire \blk00000003/sig000000ce ;
  wire \blk00000003/sig000000cd ;
  wire \blk00000003/sig000000cc ;
  wire \blk00000003/sig000000cb ;
  wire \blk00000003/sig000000ca ;
  wire \blk00000003/sig000000c9 ;
  wire \blk00000003/sig000000c8 ;
  wire \blk00000003/sig000000c7 ;
  wire \blk00000003/sig000000c6 ;
  wire \blk00000003/sig000000c5 ;
  wire \blk00000003/sig000000c4 ;
  wire \blk00000003/sig000000c3 ;
  wire \blk00000003/sig000000c2 ;
  wire \blk00000003/sig000000c1 ;
  wire \blk00000003/sig000000c0 ;
  wire \blk00000003/sig000000bf ;
  wire \blk00000003/sig000000be ;
  wire \blk00000003/sig000000bd ;
  wire \blk00000003/sig000000bc ;
  wire \blk00000003/sig000000bb ;
  wire \blk00000003/sig000000ba ;
  wire \blk00000003/sig000000b9 ;
  wire \blk00000003/sig000000b8 ;
  wire \blk00000003/sig000000b7 ;
  wire \blk00000003/sig000000b6 ;
  wire \blk00000003/sig000000b5 ;
  wire \blk00000003/sig000000b4 ;
  wire \blk00000003/sig000000b3 ;
  wire \blk00000003/sig000000b2 ;
  wire \blk00000003/sig000000b1 ;
  wire \blk00000003/sig000000b0 ;
  wire \blk00000003/sig000000af ;
  wire \blk00000003/sig000000ae ;
  wire \blk00000003/sig000000ad ;
  wire \blk00000003/sig000000ac ;
  wire \blk00000003/sig000000ab ;
  wire \blk00000003/sig000000aa ;
  wire \blk00000003/sig000000a9 ;
  wire \blk00000003/sig000000a8 ;
  wire \blk00000003/sig000000a7 ;
  wire \blk00000003/sig000000a6 ;
  wire \blk00000003/sig000000a5 ;
  wire \blk00000003/sig000000a4 ;
  wire \blk00000003/sig000000a3 ;
  wire \blk00000003/sig000000a2 ;
  wire \blk00000003/sig000000a1 ;
  wire \blk00000003/sig000000a0 ;
  wire \blk00000003/sig0000009f ;
  wire \blk00000003/sig0000009e ;
  wire \blk00000003/sig0000009d ;
  wire \blk00000003/sig0000009c ;
  wire \blk00000003/sig0000009b ;
  wire \blk00000003/sig0000009a ;
  wire \blk00000003/sig00000099 ;
  wire \blk00000003/sig00000098 ;
  wire \blk00000003/sig00000097 ;
  wire \blk00000003/sig00000096 ;
  wire \blk00000003/sig00000095 ;
  wire \blk00000003/sig00000094 ;
  wire \blk00000003/sig00000093 ;
  wire \blk00000003/sig00000092 ;
  wire \blk00000003/sig00000091 ;
  wire \blk00000003/sig00000090 ;
  wire \blk00000003/sig0000008f ;
  wire \blk00000003/sig0000008e ;
  wire \blk00000003/sig0000008d ;
  wire \blk00000003/sig0000008c ;
  wire \blk00000003/sig0000008b ;
  wire \blk00000003/sig0000008a ;
  wire \blk00000003/sig00000089 ;
  wire \blk00000003/sig00000088 ;
  wire \blk00000003/sig00000087 ;
  wire \blk00000003/sig00000086 ;
  wire \blk00000003/sig00000085 ;
  wire \blk00000003/sig00000084 ;
  wire \blk00000003/sig00000083 ;
  wire \blk00000003/sig00000082 ;
  wire \blk00000003/sig00000081 ;
  wire \blk00000003/sig00000080 ;
  wire \blk00000003/sig0000007f ;
  wire \blk00000003/sig0000007e ;
  wire \blk00000003/sig0000007d ;
  wire \blk00000003/sig0000007c ;
  wire \blk00000003/sig0000007b ;
  wire \blk00000003/sig0000007a ;
  wire \blk00000003/sig00000079 ;
  wire \blk00000003/sig00000078 ;
  wire \blk00000003/sig00000077 ;
  wire \blk00000003/sig00000076 ;
  wire \blk00000003/sig00000075 ;
  wire \blk00000003/sig00000074 ;
  wire \blk00000003/sig00000073 ;
  wire \blk00000003/sig00000072 ;
  wire \blk00000003/sig00000071 ;
  wire \blk00000003/sig00000070 ;
  wire \blk00000003/sig0000006f ;
  wire \blk00000003/sig0000006e ;
  wire \blk00000003/sig0000006d ;
  wire \blk00000003/sig0000006c ;
  wire \blk00000003/sig0000006b ;
  wire \blk00000003/sig0000006a ;
  wire \blk00000003/sig00000069 ;
  wire \blk00000003/sig00000068 ;
  wire \blk00000003/sig00000067 ;
  wire \blk00000003/sig00000066 ;
  wire \blk00000003/sig00000065 ;
  wire \blk00000003/sig00000034 ;
  wire \blk00000003/sig00000033 ;
  wire NLW_blk00000001_P_UNCONNECTED;
  wire NLW_blk00000002_G_UNCONNECTED;
  wire \NLW_blk00000003/blk000001ab_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk000001a1_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk000001a0_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk0000019f_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk0000019e_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk00000151_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk0000014e_O_UNCONNECTED ;
  wire \NLW_blk00000003/blk0000012b_Q_UNCONNECTED ;
  wire \NLW_blk00000003/blk00000101_O_UNCONNECTED ;
  wire \NLW_blk00000003/blk000000d5_O_UNCONNECTED ;
  wire \NLW_blk00000003/blk000000a7_O_UNCONNECTED ;
  wire \NLW_blk00000003/blk00000079_O_UNCONNECTED ;
  wire \NLW_blk00000003/blk0000004b_O_UNCONNECTED ;
  assign
    sig00000001 = a[15],
    sig00000002 = a[14],
    sig00000003 = a[13],
    sig00000004 = a[12],
    sig00000005 = a[11],
    sig00000006 = a[10],
    sig00000007 = a[9],
    sig00000008 = a[8],
    sig00000009 = a[7],
    sig0000000a = a[6],
    sig0000000b = a[5],
    sig0000000c = a[4],
    sig0000000d = a[3],
    sig0000000e = a[2],
    sig0000000f = a[1],
    sig00000010 = a[0],
    sig00000011 = b[15],
    sig00000012 = b[14],
    sig00000013 = b[13],
    sig00000014 = b[12],
    sig00000015 = b[11],
    sig00000016 = b[10],
    sig00000017 = b[9],
    sig00000018 = b[8],
    sig00000019 = b[7],
    sig0000001a = b[6],
    sig0000001b = b[5],
    sig0000001c = b[4],
    sig0000001d = b[3],
    sig0000001e = b[2],
    sig0000001f = b[1],
    sig00000020 = b[0],
    result[15] = sig00000022,
    result[14] = sig00000023,
    result[13] = sig00000024,
    result[12] = sig00000025,
    result[11] = sig00000026,
    result[10] = sig00000027,
    result[9] = sig00000028,
    result[8] = sig00000029,
    result[7] = sig0000002a,
    result[6] = sig0000002b,
    result[5] = sig0000002c,
    result[4] = sig0000002d,
    result[3] = sig0000002e,
    result[2] = sig0000002f,
    result[1] = sig00000030,
    result[0] = sig00000031,
    sig00000021 = clk;
  VCC   blk00000001 (
    .P(NLW_blk00000001_P_UNCONNECTED)
  );
  GND   blk00000002 (
    .G(NLW_blk00000002_G_UNCONNECTED)
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000209  (
    .C(sig00000021),
    .D(\blk00000003/sig0000024c ),
    .Q(\blk00000003/sig000001c8 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk00000208  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001d9 ),
    .Q(\blk00000003/sig0000024c )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000207  (
    .C(sig00000021),
    .D(\blk00000003/sig0000024b ),
    .Q(\blk00000003/sig000001c6 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk00000206  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001d7 ),
    .Q(\blk00000003/sig0000024b )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000205  (
    .C(sig00000021),
    .D(\blk00000003/sig0000024a ),
    .Q(\blk00000003/sig000001c2 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk00000204  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001d3 ),
    .Q(\blk00000003/sig0000024a )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000203  (
    .C(sig00000021),
    .D(\blk00000003/sig00000249 ),
    .Q(\blk00000003/sig000001c0 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk00000202  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001d1 ),
    .Q(\blk00000003/sig00000249 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000201  (
    .C(sig00000021),
    .D(\blk00000003/sig00000248 ),
    .Q(\blk00000003/sig000001c4 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk00000200  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001d5 ),
    .Q(\blk00000003/sig00000248 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001ff  (
    .C(sig00000021),
    .D(\blk00000003/sig00000247 ),
    .Q(\blk00000003/sig000001bc )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001fe  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001cd ),
    .Q(\blk00000003/sig00000247 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001fd  (
    .C(sig00000021),
    .D(\blk00000003/sig00000246 ),
    .Q(\blk00000003/sig000001ba )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001fc  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001cb ),
    .Q(\blk00000003/sig00000246 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001fb  (
    .C(sig00000021),
    .D(\blk00000003/sig00000245 ),
    .Q(\blk00000003/sig000001be )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001fa  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig000001cf ),
    .Q(\blk00000003/sig00000245 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001f9  (
    .C(sig00000021),
    .D(\blk00000003/sig00000244 ),
    .Q(\blk00000003/sig0000022d )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001f8  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig00000227 ),
    .Q(\blk00000003/sig00000244 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001f7  (
    .C(sig00000021),
    .D(\blk00000003/sig00000243 ),
    .Q(\blk00000003/sig00000216 )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001f6  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig00000225 ),
    .Q(\blk00000003/sig00000243 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001f5  (
    .C(sig00000021),
    .D(\blk00000003/sig00000242 ),
    .Q(\blk00000003/sig0000022e )
  );
  SRL16 #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk000001f4  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig00000229 ),
    .Q(\blk00000003/sig00000242 )
  );
  LUT4_L #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001f3  (
    .I0(\blk00000003/sig000001d1 ),
    .I1(\blk00000003/sig000001cf ),
    .I2(\blk00000003/sig000001cd ),
    .I3(\blk00000003/sig000001d5 ),
    .LO(\blk00000003/sig0000023d )
  );
  LUT3_L #(
    .INIT ( 8'hFE ))
  \blk00000003/blk000001f2  (
    .I0(\blk00000003/sig00000218 ),
    .I1(\blk00000003/sig0000021a ),
    .I2(\blk00000003/sig0000022e ),
    .LO(\blk00000003/sig0000023a )
  );
  LUT2_L #(
    .INIT ( 4'h1 ))
  \blk00000003/blk000001f1  (
    .I0(\blk00000003/sig000001d1 ),
    .I1(\blk00000003/sig000001d3 ),
    .LO(\blk00000003/sig00000235 )
  );
  LUT4_L #(
    .INIT ( 16'hDD5D ))
  \blk00000003/blk000001f0  (
    .I0(\blk00000003/sig0000022c ),
    .I1(\blk00000003/sig0000020d ),
    .I2(\blk00000003/sig0000020e ),
    .I3(\blk00000003/sig0000020f ),
    .LO(\blk00000003/sig00000234 )
  );
  LUT3_L #(
    .INIT ( 8'h7F ))
  \blk00000003/blk000001ef  (
    .I0(\blk00000003/sig0000020f ),
    .I1(\blk00000003/sig0000020e ),
    .I2(\blk00000003/sig0000020d ),
    .LO(\blk00000003/sig00000233 )
  );
  LUT3_L #(
    .INIT ( 8'hF7 ))
  \blk00000003/blk000001ee  (
    .I0(\blk00000003/sig00000189 ),
    .I1(\blk00000003/sig0000021c ),
    .I2(\blk00000003/sig0000021a ),
    .LO(\blk00000003/sig00000231 )
  );
  LUT3_D #(
    .INIT ( 8'hEF ))
  \blk00000003/blk000001ed  (
    .I0(\blk00000003/sig00000218 ),
    .I1(\blk00000003/sig0000021a ),
    .I2(\blk00000003/sig00000189 ),
    .LO(\blk00000003/sig00000230 ),
    .O(\blk00000003/sig0000022f )
  );
  MUXF5   \blk00000003/blk000001ec  (
    .I0(\blk00000003/sig00000241 ),
    .I1(\blk00000003/sig00000240 ),
    .S(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig0000023e )
  );
  LUT3 #(
    .INIT ( 8'h10 ))
  \blk00000003/blk000001eb  (
    .I0(\blk00000003/sig0000021a ),
    .I1(\blk00000003/sig0000022e ),
    .I2(\blk00000003/sig00000218 ),
    .O(\blk00000003/sig00000241 )
  );
  LUT4 #(
    .INIT ( 16'h1110 ))
  \blk00000003/blk000001ea  (
    .I0(\blk00000003/sig0000021a ),
    .I1(\blk00000003/sig0000022e ),
    .I2(\blk00000003/sig0000021c ),
    .I3(\blk00000003/sig00000218 ),
    .O(\blk00000003/sig00000240 )
  );
  INV   \blk00000003/blk000001e9  (
    .I(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig00000194 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e8  (
    .I0(\blk00000003/sig000001c7 ),
    .O(\blk00000003/sig000001b6 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e7  (
    .I0(\blk00000003/sig000001c5 ),
    .O(\blk00000003/sig000001b4 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e6  (
    .I0(\blk00000003/sig000001c3 ),
    .O(\blk00000003/sig000001b2 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e5  (
    .I0(\blk00000003/sig000001c1 ),
    .O(\blk00000003/sig000001b0 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e4  (
    .I0(\blk00000003/sig000001bf ),
    .O(\blk00000003/sig000001ae )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e3  (
    .I0(\blk00000003/sig000001bd ),
    .O(\blk00000003/sig000001ac )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk000001e2  (
    .I0(\blk00000003/sig000001bb ),
    .O(\blk00000003/sig000001aa )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001e1  (
    .I0(\blk00000003/sig00000182 ),
    .I1(\blk00000003/sig00000181 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig00000199 )
  );
  LUT2 #(
    .INIT ( 4'h4 ))
  \blk00000003/blk000001e0  (
    .I0(\blk00000003/sig0000021e ),
    .I1(\blk00000003/sig0000021a ),
    .O(\blk00000003/sig0000023f )
  );
  FDRS #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001df  (
    .C(sig00000021),
    .D(\blk00000003/sig0000023f ),
    .R(\blk00000003/sig0000022d ),
    .S(\blk00000003/sig0000022e ),
    .Q(\blk00000003/sig000000b5 )
  );
  FDS #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001de  (
    .C(sig00000021),
    .D(\blk00000003/sig00000239 ),
    .S(\blk00000003/sig0000022d ),
    .Q(\blk00000003/sig000000ad )
  );
  FDR #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001dd  (
    .C(sig00000021),
    .D(\blk00000003/sig0000022d ),
    .R(\blk00000003/sig0000022e ),
    .Q(\blk00000003/sig000000ab )
  );
  FDS #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001dc  (
    .C(sig00000021),
    .D(\blk00000003/sig0000023e ),
    .S(\blk00000003/sig0000022d ),
    .Q(\blk00000003/sig000000b6 )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001db  (
    .I0(\blk00000003/sig00000182 ),
    .I1(\blk00000003/sig00000181 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig000001a8 )
  );
  LUT3 #(
    .INIT ( 8'h2A ))
  \blk00000003/blk000001da  (
    .I0(\blk00000003/sig00000066 ),
    .I1(\blk00000003/sig00000180 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig000001a7 )
  );
  LUT3 #(
    .INIT ( 8'hCA ))
  \blk00000003/blk000001d9  (
    .I0(\blk00000003/sig00000180 ),
    .I1(\blk00000003/sig00000181 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig000001a5 )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d8  (
    .I0(\blk00000003/sig00000183 ),
    .I1(\blk00000003/sig00000182 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig0000019c )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d7  (
    .I0(\blk00000003/sig00000184 ),
    .I1(\blk00000003/sig00000183 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig0000019f )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d6  (
    .I0(\blk00000003/sig00000185 ),
    .I1(\blk00000003/sig00000184 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig000001a2 )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d5  (
    .I0(\blk00000003/sig00000186 ),
    .I1(\blk00000003/sig00000185 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig0000018b )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d4  (
    .I0(\blk00000003/sig00000187 ),
    .I1(\blk00000003/sig00000186 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig0000018e )
  );
  LUT3 #(
    .INIT ( 8'hAC ))
  \blk00000003/blk000001d3  (
    .I0(\blk00000003/sig00000188 ),
    .I1(\blk00000003/sig00000187 ),
    .I2(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig00000191 )
  );
  LUT4 #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001d2  (
    .I0(\blk00000003/sig000001d3 ),
    .I1(\blk00000003/sig000001d7 ),
    .I2(\blk00000003/sig0000023d ),
    .I3(\blk00000003/sig000001db ),
    .O(\blk00000003/sig00000238 )
  );
  LUT4 #(
    .INIT ( 16'h083B ))
  \blk00000003/blk000001d1  (
    .I0(\blk00000003/sig00000211 ),
    .I1(\blk00000003/sig00000210 ),
    .I2(\blk00000003/sig0000023c ),
    .I3(\blk00000003/sig0000023b ),
    .O(\blk00000003/sig00000228 )
  );
  LUT4 #(
    .INIT ( 16'hFF8C ))
  \blk00000003/blk000001d0  (
    .I0(\blk00000003/sig0000020f ),
    .I1(\blk00000003/sig0000020d ),
    .I2(\blk00000003/sig0000020e ),
    .I3(\blk00000003/sig0000020c ),
    .O(\blk00000003/sig0000023c )
  );
  LUT4 #(
    .INIT ( 16'hA2A7 ))
  \blk00000003/blk000001cf  (
    .I0(\blk00000003/sig0000020d ),
    .I1(\blk00000003/sig0000020e ),
    .I2(\blk00000003/sig0000020f ),
    .I3(\blk00000003/sig0000020c ),
    .O(\blk00000003/sig0000023b )
  );
  LUT4 #(
    .INIT ( 16'hFCFA ))
  \blk00000003/blk000001ce  (
    .I0(\blk00000003/sig0000021e ),
    .I1(\blk00000003/sig0000021c ),
    .I2(\blk00000003/sig0000023a ),
    .I3(\blk00000003/sig00000189 ),
    .O(\blk00000003/sig00000239 )
  );
  LUT4 #(
    .INIT ( 16'hECA0 ))
  \blk00000003/blk000001cd  (
    .I0(\blk00000003/sig000001cb ),
    .I1(\blk00000003/sig000001db ),
    .I2(\blk00000003/sig00000238 ),
    .I3(\blk00000003/sig000001d9 ),
    .O(\blk00000003/sig0000021f )
  );
  LUT3 #(
    .INIT ( 8'hB8 ))
  \blk00000003/blk000001cc  (
    .I0(\blk00000003/sig0000022e ),
    .I1(\blk00000003/sig0000022d ),
    .I2(\blk00000003/sig00000239 ),
    .O(\blk00000003/sig0000022a )
  );
  LUT3 #(
    .INIT ( 8'h10 ))
  \blk00000003/blk000001cb  (
    .I0(\blk00000003/sig000001cb ),
    .I1(\blk00000003/sig000001d9 ),
    .I2(\blk00000003/sig00000238 ),
    .O(\blk00000003/sig00000221 )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk000001ca  (
    .I0(\blk00000003/sig000001b8 ),
    .I1(\blk00000003/sig000001c9 ),
    .O(\blk00000003/sig000001b9 )
  );
  LUT2 #(
    .INIT ( 4'h8 ))
  \blk00000003/blk000001c9  (
    .I0(\blk00000003/sig00000237 ),
    .I1(\blk00000003/sig00000236 ),
    .O(\blk00000003/sig00000222 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001c8  (
    .I0(\blk00000003/sig000001d5 ),
    .I1(\blk00000003/sig000001cb ),
    .I2(\blk00000003/sig000001cd ),
    .I3(\blk00000003/sig000001db ),
    .O(\blk00000003/sig00000237 )
  );
  LUT4 #(
    .INIT ( 16'h1000 ))
  \blk00000003/blk000001c7  (
    .I0(\blk00000003/sig000001cf ),
    .I1(\blk00000003/sig000001d7 ),
    .I2(\blk00000003/sig00000235 ),
    .I3(\blk00000003/sig000001d9 ),
    .O(\blk00000003/sig00000236 )
  );
  LUT4 #(
    .INIT ( 16'h020F ))
  \blk00000003/blk000001c6  (
    .I0(\blk00000003/sig00000211 ),
    .I1(\blk00000003/sig0000020c ),
    .I2(\blk00000003/sig00000234 ),
    .I3(\blk00000003/sig00000210 ),
    .O(\blk00000003/sig00000224 )
  );
  LUT4 #(
    .INIT ( 16'hB111 ))
  \blk00000003/blk000001c5  (
    .I0(\blk00000003/sig00000210 ),
    .I1(\blk00000003/sig00000233 ),
    .I2(\blk00000003/sig00000232 ),
    .I3(\blk00000003/sig00000211 ),
    .O(\blk00000003/sig00000223 )
  );
  LUT4 #(
    .INIT ( 16'hEA22 ))
  \blk00000003/blk000001c4  (
    .I0(\blk00000003/sig0000020c ),
    .I1(\blk00000003/sig0000020d ),
    .I2(\blk00000003/sig0000020f ),
    .I3(\blk00000003/sig0000020e ),
    .O(\blk00000003/sig00000232 )
  );
  LUT4 #(
    .INIT ( 16'h0405 ))
  \blk00000003/blk000001c3  (
    .I0(\blk00000003/sig0000022e ),
    .I1(\blk00000003/sig00000218 ),
    .I2(\blk00000003/sig0000022d ),
    .I3(\blk00000003/sig00000231 ),
    .O(\blk00000003/sig00000212 )
  );
  LUT4 #(
    .INIT ( 16'h0020 ))
  \blk00000003/blk000001c2  (
    .I0(\blk00000003/sig0000021c ),
    .I1(\blk00000003/sig0000022e ),
    .I2(\blk00000003/sig00000230 ),
    .I3(\blk00000003/sig0000022d ),
    .O(\blk00000003/sig00000214 )
  );
  LUT4 #(
    .INIT ( 16'h0020 ))
  \blk00000003/blk000001c1  (
    .I0(\blk00000003/sig0000021e ),
    .I1(\blk00000003/sig0000022e ),
    .I2(\blk00000003/sig0000022f ),
    .I3(\blk00000003/sig0000022d ),
    .O(\blk00000003/sig00000215 )
  );
  LUT3 #(
    .INIT ( 8'h10 ))
  \blk00000003/blk000001c0  (
    .I0(\blk00000003/sig0000022d ),
    .I1(\blk00000003/sig0000022e ),
    .I2(\blk00000003/sig0000021a ),
    .O(\blk00000003/sig00000213 )
  );
  LUT2 #(
    .INIT ( 4'h1 ))
  \blk00000003/blk000001bf  (
    .I0(\blk00000003/sig000001db ),
    .I1(\blk00000003/sig000001d9 ),
    .O(\blk00000003/sig00000220 )
  );
  LUT2 #(
    .INIT ( 4'hE ))
  \blk00000003/blk000001be  (
    .I0(\blk00000003/sig00000210 ),
    .I1(\blk00000003/sig0000020d ),
    .O(\blk00000003/sig00000226 )
  );
  LUT4 #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001bd  (
    .I0(sig00000008),
    .I1(sig00000009),
    .I2(sig00000006),
    .I3(sig00000007),
    .O(\blk00000003/sig000001e9 )
  );
  LUT4 #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001bc  (
    .I0(sig00000004),
    .I1(sig00000005),
    .I2(sig00000002),
    .I3(sig00000003),
    .O(\blk00000003/sig000001eb )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001bb  (
    .I0(sig00000008),
    .I1(sig00000009),
    .I2(sig00000006),
    .I3(sig00000007),
    .O(\blk00000003/sig000001e5 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001ba  (
    .I0(sig00000004),
    .I1(sig00000005),
    .I2(sig00000002),
    .I3(sig00000003),
    .O(\blk00000003/sig000001e7 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001b9  (
    .I0(sig0000000f),
    .I1(sig00000010),
    .I2(sig0000000d),
    .I3(sig0000000e),
    .O(\blk00000003/sig000001ed )
  );
  LUT4 #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001b8  (
    .I0(sig00000018),
    .I1(sig00000019),
    .I2(sig00000016),
    .I3(sig00000017),
    .O(\blk00000003/sig000001f5 )
  );
  LUT4 #(
    .INIT ( 16'h8000 ))
  \blk00000003/blk000001b7  (
    .I0(sig00000014),
    .I1(sig00000015),
    .I2(sig00000012),
    .I3(sig00000013),
    .O(\blk00000003/sig000001f7 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001b6  (
    .I0(sig00000018),
    .I1(sig00000019),
    .I2(sig00000016),
    .I3(sig00000017),
    .O(\blk00000003/sig000001f1 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001b5  (
    .I0(sig00000014),
    .I1(sig00000015),
    .I2(sig00000012),
    .I3(sig00000013),
    .O(\blk00000003/sig000001f3 )
  );
  LUT4 #(
    .INIT ( 16'h0001 ))
  \blk00000003/blk000001b4  (
    .I0(sig0000001f),
    .I1(sig00000020),
    .I2(sig0000001d),
    .I3(sig0000001e),
    .O(\blk00000003/sig000001f9 )
  );
  LUT3 #(
    .INIT ( 8'h01 ))
  \blk00000003/blk000001b3  (
    .I0(sig0000000a),
    .I1(sig0000000b),
    .I2(sig0000000c),
    .O(\blk00000003/sig000001ef )
  );
  LUT3 #(
    .INIT ( 8'h01 ))
  \blk00000003/blk000001b2  (
    .I0(sig0000001a),
    .I1(sig0000001b),
    .I2(sig0000001c),
    .O(\blk00000003/sig000001fb )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk000001b1  (
    .I0(sig00000011),
    .I1(sig00000001),
    .O(\blk00000003/sig0000022b )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001b0  (
    .C(sig00000021),
    .D(\blk00000003/sig0000022b ),
    .Q(\blk00000003/sig0000022c )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001af  (
    .C(sig00000021),
    .D(\blk00000003/sig0000022a ),
    .Q(\blk00000003/sig000000aa )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001ae  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000228 ),
    .Q(\blk00000003/sig00000229 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001ad  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000226 ),
    .Q(\blk00000003/sig00000227 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001ac  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000224 ),
    .Q(\blk00000003/sig00000225 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001ab  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000223 ),
    .Q(\NLW_blk00000003/blk000001ab_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001aa  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000222 ),
    .Q(\blk00000003/sig0000021d )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a9  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000221 ),
    .Q(\blk00000003/sig0000021b )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a8  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000220 ),
    .Q(\blk00000003/sig00000219 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a7  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000021f ),
    .Q(\blk00000003/sig00000217 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a6  (
    .C(sig00000021),
    .D(\blk00000003/sig0000021d ),
    .Q(\blk00000003/sig0000021e )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a5  (
    .C(sig00000021),
    .D(\blk00000003/sig0000021b ),
    .Q(\blk00000003/sig0000021c )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a4  (
    .C(sig00000021),
    .D(\blk00000003/sig00000219 ),
    .Q(\blk00000003/sig0000021a )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a3  (
    .C(sig00000021),
    .D(\blk00000003/sig00000217 ),
    .Q(\blk00000003/sig00000218 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a2  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000216 ),
    .Q(\blk00000003/sig000000ae )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a1  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000215 ),
    .Q(\NLW_blk00000003/blk000001a1_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000001a0  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000214 ),
    .Q(\NLW_blk00000003/blk000001a0_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000213 ),
    .Q(\NLW_blk00000003/blk0000019f_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000212 ),
    .Q(\NLW_blk00000003/blk0000019e_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001fc ),
    .Q(\blk00000003/sig00000211 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001f8 ),
    .Q(\blk00000003/sig00000210 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001f4 ),
    .Q(\blk00000003/sig0000020f )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000019a  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001f0 ),
    .Q(\blk00000003/sig0000020e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000199  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001ec ),
    .Q(\blk00000003/sig0000020d )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000198  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e8 ),
    .Q(\blk00000003/sig0000020c )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000197  (
    .I0(sig00000009),
    .I1(sig00000019),
    .O(\blk00000003/sig0000020b )
  );
  MUXCY   \blk00000003/blk00000196  (
    .CI(\blk00000003/sig00000034 ),
    .DI(sig00000009),
    .S(\blk00000003/sig0000020b ),
    .O(\blk00000003/sig00000209 )
  );
  XORCY   \blk00000003/blk00000195  (
    .CI(\blk00000003/sig00000034 ),
    .LI(\blk00000003/sig0000020b ),
    .O(\blk00000003/sig000001dc )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000194  (
    .I0(sig00000008),
    .I1(sig00000018),
    .O(\blk00000003/sig0000020a )
  );
  MUXCY   \blk00000003/blk00000193  (
    .CI(\blk00000003/sig00000209 ),
    .DI(sig00000008),
    .S(\blk00000003/sig0000020a ),
    .O(\blk00000003/sig00000207 )
  );
  XORCY   \blk00000003/blk00000192  (
    .CI(\blk00000003/sig00000209 ),
    .LI(\blk00000003/sig0000020a ),
    .O(\blk00000003/sig000001dd )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000191  (
    .I0(sig00000007),
    .I1(sig00000017),
    .O(\blk00000003/sig00000208 )
  );
  MUXCY   \blk00000003/blk00000190  (
    .CI(\blk00000003/sig00000207 ),
    .DI(sig00000007),
    .S(\blk00000003/sig00000208 ),
    .O(\blk00000003/sig00000205 )
  );
  XORCY   \blk00000003/blk0000018f  (
    .CI(\blk00000003/sig00000207 ),
    .LI(\blk00000003/sig00000208 ),
    .O(\blk00000003/sig000001de )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk0000018e  (
    .I0(sig00000006),
    .I1(sig00000016),
    .O(\blk00000003/sig00000206 )
  );
  MUXCY   \blk00000003/blk0000018d  (
    .CI(\blk00000003/sig00000205 ),
    .DI(sig00000006),
    .S(\blk00000003/sig00000206 ),
    .O(\blk00000003/sig00000203 )
  );
  XORCY   \blk00000003/blk0000018c  (
    .CI(\blk00000003/sig00000205 ),
    .LI(\blk00000003/sig00000206 ),
    .O(\blk00000003/sig000001df )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk0000018b  (
    .I0(sig00000005),
    .I1(sig00000015),
    .O(\blk00000003/sig00000204 )
  );
  MUXCY   \blk00000003/blk0000018a  (
    .CI(\blk00000003/sig00000203 ),
    .DI(sig00000005),
    .S(\blk00000003/sig00000204 ),
    .O(\blk00000003/sig00000201 )
  );
  XORCY   \blk00000003/blk00000189  (
    .CI(\blk00000003/sig00000203 ),
    .LI(\blk00000003/sig00000204 ),
    .O(\blk00000003/sig000001e0 )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000188  (
    .I0(sig00000004),
    .I1(sig00000014),
    .O(\blk00000003/sig00000202 )
  );
  MUXCY   \blk00000003/blk00000187  (
    .CI(\blk00000003/sig00000201 ),
    .DI(sig00000004),
    .S(\blk00000003/sig00000202 ),
    .O(\blk00000003/sig000001ff )
  );
  XORCY   \blk00000003/blk00000186  (
    .CI(\blk00000003/sig00000201 ),
    .LI(\blk00000003/sig00000202 ),
    .O(\blk00000003/sig000001e1 )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000185  (
    .I0(sig00000003),
    .I1(sig00000013),
    .O(\blk00000003/sig00000200 )
  );
  MUXCY   \blk00000003/blk00000184  (
    .CI(\blk00000003/sig000001ff ),
    .DI(sig00000003),
    .S(\blk00000003/sig00000200 ),
    .O(\blk00000003/sig000001fd )
  );
  XORCY   \blk00000003/blk00000183  (
    .CI(\blk00000003/sig000001ff ),
    .LI(\blk00000003/sig00000200 ),
    .O(\blk00000003/sig000001e2 )
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000182  (
    .I0(sig00000002),
    .I1(sig00000012),
    .O(\blk00000003/sig000001fe )
  );
  MUXCY   \blk00000003/blk00000181  (
    .CI(\blk00000003/sig000001fd ),
    .DI(sig00000002),
    .S(\blk00000003/sig000001fe ),
    .O(\blk00000003/sig000001e4 )
  );
  XORCY   \blk00000003/blk00000180  (
    .CI(\blk00000003/sig000001fd ),
    .LI(\blk00000003/sig000001fe ),
    .O(\blk00000003/sig000001e3 )
  );
  MUXCY   \blk00000003/blk0000017f  (
    .CI(\blk00000003/sig000001fa ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001fb ),
    .O(\blk00000003/sig000001fc )
  );
  MUXCY   \blk00000003/blk0000017e  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001f9 ),
    .O(\blk00000003/sig000001fa )
  );
  MUXCY   \blk00000003/blk0000017d  (
    .CI(\blk00000003/sig000001f6 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001f7 ),
    .O(\blk00000003/sig000001f8 )
  );
  MUXCY   \blk00000003/blk0000017c  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001f5 ),
    .O(\blk00000003/sig000001f6 )
  );
  MUXCY   \blk00000003/blk0000017b  (
    .CI(\blk00000003/sig000001f2 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001f3 ),
    .O(\blk00000003/sig000001f4 )
  );
  MUXCY   \blk00000003/blk0000017a  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001f1 ),
    .O(\blk00000003/sig000001f2 )
  );
  MUXCY   \blk00000003/blk00000179  (
    .CI(\blk00000003/sig000001ee ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001ef ),
    .O(\blk00000003/sig000001f0 )
  );
  MUXCY   \blk00000003/blk00000178  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001ed ),
    .O(\blk00000003/sig000001ee )
  );
  MUXCY   \blk00000003/blk00000177  (
    .CI(\blk00000003/sig000001ea ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001eb ),
    .O(\blk00000003/sig000001ec )
  );
  MUXCY   \blk00000003/blk00000176  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001e9 ),
    .O(\blk00000003/sig000001ea )
  );
  MUXCY   \blk00000003/blk00000175  (
    .CI(\blk00000003/sig000001e6 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001e7 ),
    .O(\blk00000003/sig000001e8 )
  );
  MUXCY   \blk00000003/blk00000174  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001e5 ),
    .O(\blk00000003/sig000001e6 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000173  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e4 ),
    .Q(\blk00000003/sig000001da )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000172  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e3 ),
    .Q(\blk00000003/sig000001d8 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000171  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e2 ),
    .Q(\blk00000003/sig000001d6 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000170  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e1 ),
    .Q(\blk00000003/sig000001d4 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001e0 ),
    .Q(\blk00000003/sig000001d2 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001df ),
    .Q(\blk00000003/sig000001d0 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001de ),
    .Q(\blk00000003/sig000001ce )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001dd ),
    .Q(\blk00000003/sig000001cc )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001dc ),
    .Q(\blk00000003/sig000001ca )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000016a  (
    .C(sig00000021),
    .D(\blk00000003/sig000001da ),
    .Q(\blk00000003/sig000001db )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000169  (
    .C(sig00000021),
    .D(\blk00000003/sig000001d8 ),
    .Q(\blk00000003/sig000001d9 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000168  (
    .C(sig00000021),
    .D(\blk00000003/sig000001d6 ),
    .Q(\blk00000003/sig000001d7 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000167  (
    .C(sig00000021),
    .D(\blk00000003/sig000001d4 ),
    .Q(\blk00000003/sig000001d5 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000166  (
    .C(sig00000021),
    .D(\blk00000003/sig000001d2 ),
    .Q(\blk00000003/sig000001d3 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000165  (
    .C(sig00000021),
    .D(\blk00000003/sig000001d0 ),
    .Q(\blk00000003/sig000001d1 )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000164  (
    .C(sig00000021),
    .D(\blk00000003/sig000001ce ),
    .Q(\blk00000003/sig000001cf )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000163  (
    .C(sig00000021),
    .D(\blk00000003/sig000001cc ),
    .Q(\blk00000003/sig000001cd )
  );
  FD #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000162  (
    .C(sig00000021),
    .D(\blk00000003/sig000001ca ),
    .Q(\blk00000003/sig000001cb )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000161  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000034 ),
    .Q(\blk00000003/sig000001b8 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000160  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001c8 ),
    .Q(\blk00000003/sig000001c9 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001c6 ),
    .Q(\blk00000003/sig000001c7 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001c4 ),
    .Q(\blk00000003/sig000001c5 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001c2 ),
    .Q(\blk00000003/sig000001c3 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001c0 ),
    .Q(\blk00000003/sig000001c1 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001be ),
    .Q(\blk00000003/sig000001bf )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000015a  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001bc ),
    .Q(\blk00000003/sig000001bd )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000159  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001ba ),
    .Q(\blk00000003/sig000001bb )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000158  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000019b ),
    .Q(\blk00000003/sig000000b2 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000157  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000019e ),
    .Q(\blk00000003/sig000000b3 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000156  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001a1 ),
    .Q(\blk00000003/sig000000b0 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000155  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000001a3 ),
    .Q(\blk00000003/sig000000af )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000154  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000018d ),
    .Q(\blk00000003/sig000000b1 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000153  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000190 ),
    .Q(\blk00000003/sig000000ac )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000152  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000193 ),
    .Q(\blk00000003/sig000000a9 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000151  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000196 ),
    .Q(\NLW_blk00000003/blk00000151_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000150  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000197 ),
    .Q(\blk00000003/sig000001a9 )
  );
  XORCY   \blk00000003/blk0000014f  (
    .CI(\blk00000003/sig000001b7 ),
    .LI(\blk00000003/sig000001b9 ),
    .O(\blk00000003/sig000000b4 )
  );
  MUXCY   \blk00000003/blk0000014e  (
    .CI(\blk00000003/sig000001b7 ),
    .DI(\blk00000003/sig000001b8 ),
    .S(\blk00000003/sig000001b9 ),
    .O(\NLW_blk00000003/blk0000014e_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk0000014d  (
    .CI(\blk00000003/sig000001b5 ),
    .LI(\blk00000003/sig000001b6 ),
    .O(\blk00000003/sig000000b7 )
  );
  MUXCY   \blk00000003/blk0000014c  (
    .CI(\blk00000003/sig000001b5 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001b6 ),
    .O(\blk00000003/sig000001b7 )
  );
  XORCY   \blk00000003/blk0000014b  (
    .CI(\blk00000003/sig000001b3 ),
    .LI(\blk00000003/sig000001b4 ),
    .O(\blk00000003/sig000000b8 )
  );
  MUXCY   \blk00000003/blk0000014a  (
    .CI(\blk00000003/sig000001b3 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001b4 ),
    .O(\blk00000003/sig000001b5 )
  );
  XORCY   \blk00000003/blk00000149  (
    .CI(\blk00000003/sig000001b1 ),
    .LI(\blk00000003/sig000001b2 ),
    .O(\blk00000003/sig000000b9 )
  );
  MUXCY   \blk00000003/blk00000148  (
    .CI(\blk00000003/sig000001b1 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001b2 ),
    .O(\blk00000003/sig000001b3 )
  );
  XORCY   \blk00000003/blk00000147  (
    .CI(\blk00000003/sig000001af ),
    .LI(\blk00000003/sig000001b0 ),
    .O(\blk00000003/sig000000ba )
  );
  MUXCY   \blk00000003/blk00000146  (
    .CI(\blk00000003/sig000001af ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001b0 ),
    .O(\blk00000003/sig000001b1 )
  );
  XORCY   \blk00000003/blk00000145  (
    .CI(\blk00000003/sig000001ad ),
    .LI(\blk00000003/sig000001ae ),
    .O(\blk00000003/sig000000bb )
  );
  MUXCY   \blk00000003/blk00000144  (
    .CI(\blk00000003/sig000001ad ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001ae ),
    .O(\blk00000003/sig000001af )
  );
  XORCY   \blk00000003/blk00000143  (
    .CI(\blk00000003/sig000001ab ),
    .LI(\blk00000003/sig000001ac ),
    .O(\blk00000003/sig000000bc )
  );
  MUXCY   \blk00000003/blk00000142  (
    .CI(\blk00000003/sig000001ab ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001ac ),
    .O(\blk00000003/sig000001ad )
  );
  XORCY   \blk00000003/blk00000141  (
    .CI(\blk00000003/sig000001a9 ),
    .LI(\blk00000003/sig000001aa ),
    .O(\blk00000003/sig000000bd )
  );
  MUXCY   \blk00000003/blk00000140  (
    .CI(\blk00000003/sig000001a9 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001aa ),
    .O(\blk00000003/sig000001ab )
  );
  MUXCY   \blk00000003/blk0000013f  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001a8 ),
    .O(\blk00000003/sig000001a6 )
  );
  MUXCY   \blk00000003/blk0000013e  (
    .CI(\blk00000003/sig000001a6 ),
    .DI(\blk00000003/sig00000034 ),
    .S(\blk00000003/sig000001a7 ),
    .O(\blk00000003/sig000001a4 )
  );
  MUXCY   \blk00000003/blk0000013d  (
    .CI(\blk00000003/sig000001a4 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001a5 ),
    .O(\blk00000003/sig00000198 )
  );
  XORCY   \blk00000003/blk0000013c  (
    .CI(\blk00000003/sig000001a0 ),
    .LI(\blk00000003/sig000001a2 ),
    .O(\blk00000003/sig000001a3 )
  );
  MUXCY   \blk00000003/blk0000013b  (
    .CI(\blk00000003/sig000001a0 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000001a2 ),
    .O(\blk00000003/sig0000018a )
  );
  XORCY   \blk00000003/blk0000013a  (
    .CI(\blk00000003/sig0000019d ),
    .LI(\blk00000003/sig0000019f ),
    .O(\blk00000003/sig000001a1 )
  );
  MUXCY   \blk00000003/blk00000139  (
    .CI(\blk00000003/sig0000019d ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig0000019f ),
    .O(\blk00000003/sig000001a0 )
  );
  XORCY   \blk00000003/blk00000138  (
    .CI(\blk00000003/sig0000019a ),
    .LI(\blk00000003/sig0000019c ),
    .O(\blk00000003/sig0000019e )
  );
  MUXCY   \blk00000003/blk00000137  (
    .CI(\blk00000003/sig0000019a ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig0000019c ),
    .O(\blk00000003/sig0000019d )
  );
  XORCY   \blk00000003/blk00000136  (
    .CI(\blk00000003/sig00000198 ),
    .LI(\blk00000003/sig00000199 ),
    .O(\blk00000003/sig0000019b )
  );
  MUXCY   \blk00000003/blk00000135  (
    .CI(\blk00000003/sig00000198 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig00000199 ),
    .O(\blk00000003/sig0000019a )
  );
  XORCY   \blk00000003/blk00000134  (
    .CI(\blk00000003/sig00000195 ),
    .LI(\blk00000003/sig00000033 ),
    .O(\blk00000003/sig00000197 )
  );
  XORCY   \blk00000003/blk00000133  (
    .CI(\blk00000003/sig00000192 ),
    .LI(\blk00000003/sig00000194 ),
    .O(\blk00000003/sig00000196 )
  );
  MUXCY   \blk00000003/blk00000132  (
    .CI(\blk00000003/sig00000192 ),
    .DI(\blk00000003/sig00000034 ),
    .S(\blk00000003/sig00000194 ),
    .O(\blk00000003/sig00000195 )
  );
  XORCY   \blk00000003/blk00000131  (
    .CI(\blk00000003/sig0000018f ),
    .LI(\blk00000003/sig00000191 ),
    .O(\blk00000003/sig00000193 )
  );
  MUXCY   \blk00000003/blk00000130  (
    .CI(\blk00000003/sig0000018f ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig00000191 ),
    .O(\blk00000003/sig00000192 )
  );
  XORCY   \blk00000003/blk0000012f  (
    .CI(\blk00000003/sig0000018c ),
    .LI(\blk00000003/sig0000018e ),
    .O(\blk00000003/sig00000190 )
  );
  MUXCY   \blk00000003/blk0000012e  (
    .CI(\blk00000003/sig0000018c ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig0000018e ),
    .O(\blk00000003/sig0000018f )
  );
  XORCY   \blk00000003/blk0000012d  (
    .CI(\blk00000003/sig0000018a ),
    .LI(\blk00000003/sig0000018b ),
    .O(\blk00000003/sig0000018d )
  );
  MUXCY   \blk00000003/blk0000012c  (
    .CI(\blk00000003/sig0000018a ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig0000018b ),
    .O(\blk00000003/sig0000018c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000012b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000162 ),
    .Q(\NLW_blk00000003/blk0000012b_Q_UNCONNECTED )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000012a  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000165 ),
    .Q(\blk00000003/sig00000189 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000129  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000168 ),
    .Q(\blk00000003/sig00000188 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000128  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000016b ),
    .Q(\blk00000003/sig00000187 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000127  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000016e ),
    .Q(\blk00000003/sig00000186 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000126  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000171 ),
    .Q(\blk00000003/sig00000185 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000125  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000174 ),
    .Q(\blk00000003/sig00000184 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000124  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000177 ),
    .Q(\blk00000003/sig00000183 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000123  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000017a ),
    .Q(\blk00000003/sig00000182 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000122  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000017d ),
    .Q(\blk00000003/sig00000181 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000121  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000017f ),
    .Q(\blk00000003/sig00000180 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000120  (
    .I0(\blk00000003/sig00000092 ),
    .I1(\blk00000003/sig00000158 ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig0000017e )
  );
  MUXCY   \blk00000003/blk0000011f  (
    .CI(\blk00000003/sig000000a4 ),
    .DI(\blk00000003/sig00000092 ),
    .S(\blk00000003/sig0000017e ),
    .O(\blk00000003/sig0000017b )
  );
  XORCY   \blk00000003/blk0000011e  (
    .CI(\blk00000003/sig000000a4 ),
    .LI(\blk00000003/sig0000017e ),
    .O(\blk00000003/sig0000017f )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk0000011d  (
    .I0(\blk00000003/sig00000090 ),
    .I1(\blk00000003/sig00000159 ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig0000017c )
  );
  MUXCY   \blk00000003/blk0000011c  (
    .CI(\blk00000003/sig0000017b ),
    .DI(\blk00000003/sig00000090 ),
    .S(\blk00000003/sig0000017c ),
    .O(\blk00000003/sig00000178 )
  );
  XORCY   \blk00000003/blk0000011b  (
    .CI(\blk00000003/sig0000017b ),
    .LI(\blk00000003/sig0000017c ),
    .O(\blk00000003/sig0000017d )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk0000011a  (
    .I0(\blk00000003/sig0000008e ),
    .I1(\blk00000003/sig0000015a ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000179 )
  );
  MUXCY   \blk00000003/blk00000119  (
    .CI(\blk00000003/sig00000178 ),
    .DI(\blk00000003/sig0000008e ),
    .S(\blk00000003/sig00000179 ),
    .O(\blk00000003/sig00000175 )
  );
  XORCY   \blk00000003/blk00000118  (
    .CI(\blk00000003/sig00000178 ),
    .LI(\blk00000003/sig00000179 ),
    .O(\blk00000003/sig0000017a )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000117  (
    .I0(\blk00000003/sig0000008c ),
    .I1(\blk00000003/sig0000015b ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000176 )
  );
  MUXCY   \blk00000003/blk00000116  (
    .CI(\blk00000003/sig00000175 ),
    .DI(\blk00000003/sig0000008c ),
    .S(\blk00000003/sig00000176 ),
    .O(\blk00000003/sig00000172 )
  );
  XORCY   \blk00000003/blk00000115  (
    .CI(\blk00000003/sig00000175 ),
    .LI(\blk00000003/sig00000176 ),
    .O(\blk00000003/sig00000177 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000114  (
    .I0(\blk00000003/sig0000008a ),
    .I1(\blk00000003/sig0000015c ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000173 )
  );
  MUXCY   \blk00000003/blk00000113  (
    .CI(\blk00000003/sig00000172 ),
    .DI(\blk00000003/sig0000008a ),
    .S(\blk00000003/sig00000173 ),
    .O(\blk00000003/sig0000016f )
  );
  XORCY   \blk00000003/blk00000112  (
    .CI(\blk00000003/sig00000172 ),
    .LI(\blk00000003/sig00000173 ),
    .O(\blk00000003/sig00000174 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000111  (
    .I0(\blk00000003/sig00000088 ),
    .I1(\blk00000003/sig0000015d ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000170 )
  );
  MUXCY   \blk00000003/blk00000110  (
    .CI(\blk00000003/sig0000016f ),
    .DI(\blk00000003/sig00000088 ),
    .S(\blk00000003/sig00000170 ),
    .O(\blk00000003/sig0000016c )
  );
  XORCY   \blk00000003/blk0000010f  (
    .CI(\blk00000003/sig0000016f ),
    .LI(\blk00000003/sig00000170 ),
    .O(\blk00000003/sig00000171 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk0000010e  (
    .I0(\blk00000003/sig00000086 ),
    .I1(\blk00000003/sig0000015e ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig0000016d )
  );
  MUXCY   \blk00000003/blk0000010d  (
    .CI(\blk00000003/sig0000016c ),
    .DI(\blk00000003/sig00000086 ),
    .S(\blk00000003/sig0000016d ),
    .O(\blk00000003/sig00000169 )
  );
  XORCY   \blk00000003/blk0000010c  (
    .CI(\blk00000003/sig0000016c ),
    .LI(\blk00000003/sig0000016d ),
    .O(\blk00000003/sig0000016e )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk0000010b  (
    .I0(\blk00000003/sig00000084 ),
    .I1(\blk00000003/sig0000015f ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig0000016a )
  );
  MUXCY   \blk00000003/blk0000010a  (
    .CI(\blk00000003/sig00000169 ),
    .DI(\blk00000003/sig00000084 ),
    .S(\blk00000003/sig0000016a ),
    .O(\blk00000003/sig00000166 )
  );
  XORCY   \blk00000003/blk00000109  (
    .CI(\blk00000003/sig00000169 ),
    .LI(\blk00000003/sig0000016a ),
    .O(\blk00000003/sig0000016b )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000108  (
    .I0(\blk00000003/sig00000082 ),
    .I1(\blk00000003/sig0000015f ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000167 )
  );
  MUXCY   \blk00000003/blk00000107  (
    .CI(\blk00000003/sig00000166 ),
    .DI(\blk00000003/sig00000082 ),
    .S(\blk00000003/sig00000167 ),
    .O(\blk00000003/sig00000163 )
  );
  XORCY   \blk00000003/blk00000106  (
    .CI(\blk00000003/sig00000166 ),
    .LI(\blk00000003/sig00000167 ),
    .O(\blk00000003/sig00000168 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000105  (
    .I0(\blk00000003/sig00000080 ),
    .I1(\blk00000003/sig0000015f ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000164 )
  );
  MUXCY   \blk00000003/blk00000104  (
    .CI(\blk00000003/sig00000163 ),
    .DI(\blk00000003/sig00000080 ),
    .S(\blk00000003/sig00000164 ),
    .O(\blk00000003/sig00000160 )
  );
  XORCY   \blk00000003/blk00000103  (
    .CI(\blk00000003/sig00000163 ),
    .LI(\blk00000003/sig00000164 ),
    .O(\blk00000003/sig00000165 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk00000102  (
    .I0(\blk00000003/sig0000007e ),
    .I1(\blk00000003/sig0000015f ),
    .I2(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig00000161 )
  );
  MUXCY   \blk00000003/blk00000101  (
    .CI(\blk00000003/sig00000160 ),
    .DI(\blk00000003/sig0000007e ),
    .S(\blk00000003/sig00000161 ),
    .O(\NLW_blk00000003/blk00000101_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk00000100  (
    .CI(\blk00000003/sig00000160 ),
    .LI(\blk00000003/sig00000161 ),
    .O(\blk00000003/sig00000162 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000ff  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000013a ),
    .Q(\blk00000003/sig0000015f )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000fe  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000013d ),
    .Q(\blk00000003/sig0000015e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000fd  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000140 ),
    .Q(\blk00000003/sig0000015d )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000fc  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000143 ),
    .Q(\blk00000003/sig0000015c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000fb  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000146 ),
    .Q(\blk00000003/sig0000015b )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000fa  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000149 ),
    .Q(\blk00000003/sig0000015a )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000f9  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000014c ),
    .Q(\blk00000003/sig00000159 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000f8  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000014f ),
    .Q(\blk00000003/sig00000158 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000f7  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000152 ),
    .Q(\blk00000003/sig000000a1 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000f6  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000155 ),
    .Q(\blk00000003/sig000000a0 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000f5  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000157 ),
    .Q(\blk00000003/sig0000009f )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000f4  (
    .I0(\blk00000003/sig000000e1 ),
    .I1(\blk00000003/sig0000010b ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000156 )
  );
  MUXCY   \blk00000003/blk000000f3  (
    .CI(\blk00000003/sig00000094 ),
    .DI(\blk00000003/sig000000e1 ),
    .S(\blk00000003/sig00000156 ),
    .O(\blk00000003/sig00000153 )
  );
  XORCY   \blk00000003/blk000000f2  (
    .CI(\blk00000003/sig00000094 ),
    .LI(\blk00000003/sig00000156 ),
    .O(\blk00000003/sig00000157 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000f1  (
    .I0(\blk00000003/sig000000e2 ),
    .I1(\blk00000003/sig0000010c ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000154 )
  );
  MUXCY   \blk00000003/blk000000f0  (
    .CI(\blk00000003/sig00000153 ),
    .DI(\blk00000003/sig000000e2 ),
    .S(\blk00000003/sig00000154 ),
    .O(\blk00000003/sig00000150 )
  );
  XORCY   \blk00000003/blk000000ef  (
    .CI(\blk00000003/sig00000153 ),
    .LI(\blk00000003/sig00000154 ),
    .O(\blk00000003/sig00000155 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000ee  (
    .I0(\blk00000003/sig000000e3 ),
    .I1(\blk00000003/sig0000010d ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000151 )
  );
  MUXCY   \blk00000003/blk000000ed  (
    .CI(\blk00000003/sig00000150 ),
    .DI(\blk00000003/sig000000e3 ),
    .S(\blk00000003/sig00000151 ),
    .O(\blk00000003/sig0000014d )
  );
  XORCY   \blk00000003/blk000000ec  (
    .CI(\blk00000003/sig00000150 ),
    .LI(\blk00000003/sig00000151 ),
    .O(\blk00000003/sig00000152 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000eb  (
    .I0(\blk00000003/sig000000e4 ),
    .I1(\blk00000003/sig0000010e ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig0000014e )
  );
  MUXCY   \blk00000003/blk000000ea  (
    .CI(\blk00000003/sig0000014d ),
    .DI(\blk00000003/sig000000e4 ),
    .S(\blk00000003/sig0000014e ),
    .O(\blk00000003/sig0000014a )
  );
  XORCY   \blk00000003/blk000000e9  (
    .CI(\blk00000003/sig0000014d ),
    .LI(\blk00000003/sig0000014e ),
    .O(\blk00000003/sig0000014f )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000e8  (
    .I0(\blk00000003/sig000000e5 ),
    .I1(\blk00000003/sig0000010f ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig0000014b )
  );
  MUXCY   \blk00000003/blk000000e7  (
    .CI(\blk00000003/sig0000014a ),
    .DI(\blk00000003/sig000000e5 ),
    .S(\blk00000003/sig0000014b ),
    .O(\blk00000003/sig00000147 )
  );
  XORCY   \blk00000003/blk000000e6  (
    .CI(\blk00000003/sig0000014a ),
    .LI(\blk00000003/sig0000014b ),
    .O(\blk00000003/sig0000014c )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000e5  (
    .I0(\blk00000003/sig000000e6 ),
    .I1(\blk00000003/sig00000110 ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000148 )
  );
  MUXCY   \blk00000003/blk000000e4  (
    .CI(\blk00000003/sig00000147 ),
    .DI(\blk00000003/sig000000e6 ),
    .S(\blk00000003/sig00000148 ),
    .O(\blk00000003/sig00000144 )
  );
  XORCY   \blk00000003/blk000000e3  (
    .CI(\blk00000003/sig00000147 ),
    .LI(\blk00000003/sig00000148 ),
    .O(\blk00000003/sig00000149 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000e2  (
    .I0(\blk00000003/sig000000e7 ),
    .I1(\blk00000003/sig00000111 ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000145 )
  );
  MUXCY   \blk00000003/blk000000e1  (
    .CI(\blk00000003/sig00000144 ),
    .DI(\blk00000003/sig000000e7 ),
    .S(\blk00000003/sig00000145 ),
    .O(\blk00000003/sig00000141 )
  );
  XORCY   \blk00000003/blk000000e0  (
    .CI(\blk00000003/sig00000144 ),
    .LI(\blk00000003/sig00000145 ),
    .O(\blk00000003/sig00000146 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000df  (
    .I0(\blk00000003/sig0000007d ),
    .I1(\blk00000003/sig00000112 ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000142 )
  );
  MUXCY   \blk00000003/blk000000de  (
    .CI(\blk00000003/sig00000141 ),
    .DI(\blk00000003/sig0000007d ),
    .S(\blk00000003/sig00000142 ),
    .O(\blk00000003/sig0000013e )
  );
  XORCY   \blk00000003/blk000000dd  (
    .CI(\blk00000003/sig00000141 ),
    .LI(\blk00000003/sig00000142 ),
    .O(\blk00000003/sig00000143 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000dc  (
    .I0(\blk00000003/sig0000007d ),
    .I1(\blk00000003/sig00000113 ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig0000013f )
  );
  MUXCY   \blk00000003/blk000000db  (
    .CI(\blk00000003/sig0000013e ),
    .DI(\blk00000003/sig0000007d ),
    .S(\blk00000003/sig0000013f ),
    .O(\blk00000003/sig0000013b )
  );
  XORCY   \blk00000003/blk000000da  (
    .CI(\blk00000003/sig0000013e ),
    .LI(\blk00000003/sig0000013f ),
    .O(\blk00000003/sig00000140 )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000d9  (
    .I0(\blk00000003/sig0000007d ),
    .I1(\blk00000003/sig00000114 ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig0000013c )
  );
  MUXCY   \blk00000003/blk000000d8  (
    .CI(\blk00000003/sig0000013b ),
    .DI(\blk00000003/sig0000007d ),
    .S(\blk00000003/sig0000013c ),
    .O(\blk00000003/sig00000138 )
  );
  XORCY   \blk00000003/blk000000d7  (
    .CI(\blk00000003/sig0000013b ),
    .LI(\blk00000003/sig0000013c ),
    .O(\blk00000003/sig0000013d )
  );
  LUT3 #(
    .INIT ( 8'h96 ))
  \blk00000003/blk000000d6  (
    .I0(\blk00000003/sig0000007d ),
    .I1(\blk00000003/sig0000007d ),
    .I2(\blk00000003/sig00000094 ),
    .O(\blk00000003/sig00000139 )
  );
  MUXCY   \blk00000003/blk000000d5  (
    .CI(\blk00000003/sig00000138 ),
    .DI(\blk00000003/sig0000007d ),
    .S(\blk00000003/sig00000139 ),
    .O(\NLW_blk00000003/blk000000d5_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk000000d4  (
    .CI(\blk00000003/sig00000138 ),
    .LI(\blk00000003/sig00000139 ),
    .O(\blk00000003/sig0000013a )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000d3  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000117 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig0000007f )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000d2  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000011b ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000081 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000d1  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000011f ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000083 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000d0  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000123 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000085 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000cf  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000127 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000087 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000ce  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000012b ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000089 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000cd  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000012f ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig0000008b )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000cc  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000133 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig0000008d )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000cb  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000136 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig0000008f )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000ca  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000137 ),
    .R(\blk00000003/sig0000007c ),
    .Q(\blk00000003/sig00000091 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000c9  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig0000009d ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000137 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000c8  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009d ),
    .I2(\blk00000003/sig0000009c ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000136 )
  );
  MULT_AND   \blk00000003/blk000000c7  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009d ),
    .LO(\blk00000003/sig00000135 )
  );
  MUXCY   \blk00000003/blk000000c6  (
    .CI(\blk00000003/sig00000033 ),
    .DI(\blk00000003/sig00000135 ),
    .S(\blk00000003/sig00000136 ),
    .O(\blk00000003/sig00000131 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000c5  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009c ),
    .I2(\blk00000003/sig0000009b ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000132 )
  );
  MULT_AND   \blk00000003/blk000000c4  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009c ),
    .LO(\blk00000003/sig00000134 )
  );
  MUXCY   \blk00000003/blk000000c3  (
    .CI(\blk00000003/sig00000131 ),
    .DI(\blk00000003/sig00000134 ),
    .S(\blk00000003/sig00000132 ),
    .O(\blk00000003/sig0000012d )
  );
  XORCY   \blk00000003/blk000000c2  (
    .CI(\blk00000003/sig00000131 ),
    .LI(\blk00000003/sig00000132 ),
    .O(\blk00000003/sig00000133 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000c1  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009b ),
    .I2(\blk00000003/sig0000009a ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig0000012e )
  );
  MULT_AND   \blk00000003/blk000000c0  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009b ),
    .LO(\blk00000003/sig00000130 )
  );
  MUXCY   \blk00000003/blk000000bf  (
    .CI(\blk00000003/sig0000012d ),
    .DI(\blk00000003/sig00000130 ),
    .S(\blk00000003/sig0000012e ),
    .O(\blk00000003/sig00000129 )
  );
  XORCY   \blk00000003/blk000000be  (
    .CI(\blk00000003/sig0000012d ),
    .LI(\blk00000003/sig0000012e ),
    .O(\blk00000003/sig0000012f )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000bd  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009a ),
    .I2(\blk00000003/sig00000099 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig0000012a )
  );
  MULT_AND   \blk00000003/blk000000bc  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig0000009a ),
    .LO(\blk00000003/sig0000012c )
  );
  MUXCY   \blk00000003/blk000000bb  (
    .CI(\blk00000003/sig00000129 ),
    .DI(\blk00000003/sig0000012c ),
    .S(\blk00000003/sig0000012a ),
    .O(\blk00000003/sig00000125 )
  );
  XORCY   \blk00000003/blk000000ba  (
    .CI(\blk00000003/sig00000129 ),
    .LI(\blk00000003/sig0000012a ),
    .O(\blk00000003/sig0000012b )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000b9  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000099 ),
    .I2(\blk00000003/sig00000098 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000126 )
  );
  MULT_AND   \blk00000003/blk000000b8  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000099 ),
    .LO(\blk00000003/sig00000128 )
  );
  MUXCY   \blk00000003/blk000000b7  (
    .CI(\blk00000003/sig00000125 ),
    .DI(\blk00000003/sig00000128 ),
    .S(\blk00000003/sig00000126 ),
    .O(\blk00000003/sig00000121 )
  );
  XORCY   \blk00000003/blk000000b6  (
    .CI(\blk00000003/sig00000125 ),
    .LI(\blk00000003/sig00000126 ),
    .O(\blk00000003/sig00000127 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000b5  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000098 ),
    .I2(\blk00000003/sig00000097 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000122 )
  );
  MULT_AND   \blk00000003/blk000000b4  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000098 ),
    .LO(\blk00000003/sig00000124 )
  );
  MUXCY   \blk00000003/blk000000b3  (
    .CI(\blk00000003/sig00000121 ),
    .DI(\blk00000003/sig00000124 ),
    .S(\blk00000003/sig00000122 ),
    .O(\blk00000003/sig0000011d )
  );
  XORCY   \blk00000003/blk000000b2  (
    .CI(\blk00000003/sig00000121 ),
    .LI(\blk00000003/sig00000122 ),
    .O(\blk00000003/sig00000123 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000b1  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000097 ),
    .I2(\blk00000003/sig00000096 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig0000011e )
  );
  MULT_AND   \blk00000003/blk000000b0  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000097 ),
    .LO(\blk00000003/sig00000120 )
  );
  MUXCY   \blk00000003/blk000000af  (
    .CI(\blk00000003/sig0000011d ),
    .DI(\blk00000003/sig00000120 ),
    .S(\blk00000003/sig0000011e ),
    .O(\blk00000003/sig00000119 )
  );
  XORCY   \blk00000003/blk000000ae  (
    .CI(\blk00000003/sig0000011d ),
    .LI(\blk00000003/sig0000011e ),
    .O(\blk00000003/sig0000011f )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000ad  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000096 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig0000011a )
  );
  MULT_AND   \blk00000003/blk000000ac  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000096 ),
    .LO(\blk00000003/sig0000011c )
  );
  MUXCY   \blk00000003/blk000000ab  (
    .CI(\blk00000003/sig00000119 ),
    .DI(\blk00000003/sig0000011c ),
    .S(\blk00000003/sig0000011a ),
    .O(\blk00000003/sig00000115 )
  );
  XORCY   \blk00000003/blk000000aa  (
    .CI(\blk00000003/sig00000119 ),
    .LI(\blk00000003/sig0000011a ),
    .O(\blk00000003/sig0000011b )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk000000a9  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig0000007a ),
    .O(\blk00000003/sig00000116 )
  );
  MULT_AND   \blk00000003/blk000000a8  (
    .I0(\blk00000003/sig00000078 ),
    .I1(\blk00000003/sig00000033 ),
    .LO(\blk00000003/sig00000118 )
  );
  MUXCY   \blk00000003/blk000000a7  (
    .CI(\blk00000003/sig00000115 ),
    .DI(\blk00000003/sig00000118 ),
    .S(\blk00000003/sig00000116 ),
    .O(\NLW_blk00000003/blk000000a7_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk000000a6  (
    .CI(\blk00000003/sig00000115 ),
    .LI(\blk00000003/sig00000116 ),
    .O(\blk00000003/sig00000117 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a5  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000ea ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig00000114 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a4  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000ee ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig00000113 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a3  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000f2 ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig00000112 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a2  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000f6 ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig00000111 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a1  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000fa ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig00000110 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk000000a0  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000fe ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig0000010f )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000009f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000102 ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig0000010e )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000009e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000106 ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig0000010d )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000009d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000109 ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig0000010c )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000009c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000010a ),
    .R(\blk00000003/sig00000076 ),
    .Q(\blk00000003/sig0000010b )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000009b  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig0000009d ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig0000010a )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000009a  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009d ),
    .I2(\blk00000003/sig0000009c ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig00000109 )
  );
  MULT_AND   \blk00000003/blk00000099  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009d ),
    .LO(\blk00000003/sig00000108 )
  );
  MUXCY   \blk00000003/blk00000098  (
    .CI(\blk00000003/sig00000033 ),
    .DI(\blk00000003/sig00000108 ),
    .S(\blk00000003/sig00000109 ),
    .O(\blk00000003/sig00000104 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000097  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009c ),
    .I2(\blk00000003/sig0000009b ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig00000105 )
  );
  MULT_AND   \blk00000003/blk00000096  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009c ),
    .LO(\blk00000003/sig00000107 )
  );
  MUXCY   \blk00000003/blk00000095  (
    .CI(\blk00000003/sig00000104 ),
    .DI(\blk00000003/sig00000107 ),
    .S(\blk00000003/sig00000105 ),
    .O(\blk00000003/sig00000100 )
  );
  XORCY   \blk00000003/blk00000094  (
    .CI(\blk00000003/sig00000104 ),
    .LI(\blk00000003/sig00000105 ),
    .O(\blk00000003/sig00000106 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000093  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009b ),
    .I2(\blk00000003/sig0000009a ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig00000101 )
  );
  MULT_AND   \blk00000003/blk00000092  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009b ),
    .LO(\blk00000003/sig00000103 )
  );
  MUXCY   \blk00000003/blk00000091  (
    .CI(\blk00000003/sig00000100 ),
    .DI(\blk00000003/sig00000103 ),
    .S(\blk00000003/sig00000101 ),
    .O(\blk00000003/sig000000fc )
  );
  XORCY   \blk00000003/blk00000090  (
    .CI(\blk00000003/sig00000100 ),
    .LI(\blk00000003/sig00000101 ),
    .O(\blk00000003/sig00000102 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000008f  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009a ),
    .I2(\blk00000003/sig00000099 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000fd )
  );
  MULT_AND   \blk00000003/blk0000008e  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig0000009a ),
    .LO(\blk00000003/sig000000ff )
  );
  MUXCY   \blk00000003/blk0000008d  (
    .CI(\blk00000003/sig000000fc ),
    .DI(\blk00000003/sig000000ff ),
    .S(\blk00000003/sig000000fd ),
    .O(\blk00000003/sig000000f8 )
  );
  XORCY   \blk00000003/blk0000008c  (
    .CI(\blk00000003/sig000000fc ),
    .LI(\blk00000003/sig000000fd ),
    .O(\blk00000003/sig000000fe )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000008b  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000099 ),
    .I2(\blk00000003/sig00000098 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000f9 )
  );
  MULT_AND   \blk00000003/blk0000008a  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000099 ),
    .LO(\blk00000003/sig000000fb )
  );
  MUXCY   \blk00000003/blk00000089  (
    .CI(\blk00000003/sig000000f8 ),
    .DI(\blk00000003/sig000000fb ),
    .S(\blk00000003/sig000000f9 ),
    .O(\blk00000003/sig000000f4 )
  );
  XORCY   \blk00000003/blk00000088  (
    .CI(\blk00000003/sig000000f8 ),
    .LI(\blk00000003/sig000000f9 ),
    .O(\blk00000003/sig000000fa )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000087  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000098 ),
    .I2(\blk00000003/sig00000097 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000f5 )
  );
  MULT_AND   \blk00000003/blk00000086  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000098 ),
    .LO(\blk00000003/sig000000f7 )
  );
  MUXCY   \blk00000003/blk00000085  (
    .CI(\blk00000003/sig000000f4 ),
    .DI(\blk00000003/sig000000f7 ),
    .S(\blk00000003/sig000000f5 ),
    .O(\blk00000003/sig000000f0 )
  );
  XORCY   \blk00000003/blk00000084  (
    .CI(\blk00000003/sig000000f4 ),
    .LI(\blk00000003/sig000000f5 ),
    .O(\blk00000003/sig000000f6 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000083  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000097 ),
    .I2(\blk00000003/sig00000096 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000f1 )
  );
  MULT_AND   \blk00000003/blk00000082  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000097 ),
    .LO(\blk00000003/sig000000f3 )
  );
  MUXCY   \blk00000003/blk00000081  (
    .CI(\blk00000003/sig000000f0 ),
    .DI(\blk00000003/sig000000f3 ),
    .S(\blk00000003/sig000000f1 ),
    .O(\blk00000003/sig000000ec )
  );
  XORCY   \blk00000003/blk00000080  (
    .CI(\blk00000003/sig000000f0 ),
    .LI(\blk00000003/sig000000f1 ),
    .O(\blk00000003/sig000000f2 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000007f  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000096 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000ed )
  );
  MULT_AND   \blk00000003/blk0000007e  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000096 ),
    .LO(\blk00000003/sig000000ef )
  );
  MUXCY   \blk00000003/blk0000007d  (
    .CI(\blk00000003/sig000000ec ),
    .DI(\blk00000003/sig000000ef ),
    .S(\blk00000003/sig000000ed ),
    .O(\blk00000003/sig000000e8 )
  );
  XORCY   \blk00000003/blk0000007c  (
    .CI(\blk00000003/sig000000ec ),
    .LI(\blk00000003/sig000000ed ),
    .O(\blk00000003/sig000000ee )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000007b  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig00000074 ),
    .O(\blk00000003/sig000000e9 )
  );
  MULT_AND   \blk00000003/blk0000007a  (
    .I0(\blk00000003/sig00000072 ),
    .I1(\blk00000003/sig00000033 ),
    .LO(\blk00000003/sig000000eb )
  );
  MUXCY   \blk00000003/blk00000079  (
    .CI(\blk00000003/sig000000e8 ),
    .DI(\blk00000003/sig000000eb ),
    .S(\blk00000003/sig000000e9 ),
    .O(\NLW_blk00000003/blk00000079_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk00000078  (
    .CI(\blk00000003/sig000000e8 ),
    .LI(\blk00000003/sig000000e9 ),
    .O(\blk00000003/sig000000ea )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000077  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000c0 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e7 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000076  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000c4 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e6 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000075  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000c8 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e5 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000074  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000cc ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e4 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000073  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000d0 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e3 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000072  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000d4 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e2 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000071  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000d8 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000e1 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000070  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000dc ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000a7 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000006f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000df ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000a6 )
  );
  FDRE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000006e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig000000e0 ),
    .R(\blk00000003/sig00000070 ),
    .Q(\blk00000003/sig000000a5 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000006d  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig0000009d ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000e0 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000006c  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009d ),
    .I2(\blk00000003/sig0000009c ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000df )
  );
  MULT_AND   \blk00000003/blk0000006b  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009d ),
    .LO(\blk00000003/sig000000de )
  );
  MUXCY   \blk00000003/blk0000006a  (
    .CI(\blk00000003/sig00000033 ),
    .DI(\blk00000003/sig000000de ),
    .S(\blk00000003/sig000000df ),
    .O(\blk00000003/sig000000da )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000069  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009c ),
    .I2(\blk00000003/sig0000009b ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000db )
  );
  MULT_AND   \blk00000003/blk00000068  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009c ),
    .LO(\blk00000003/sig000000dd )
  );
  MUXCY   \blk00000003/blk00000067  (
    .CI(\blk00000003/sig000000da ),
    .DI(\blk00000003/sig000000dd ),
    .S(\blk00000003/sig000000db ),
    .O(\blk00000003/sig000000d6 )
  );
  XORCY   \blk00000003/blk00000066  (
    .CI(\blk00000003/sig000000da ),
    .LI(\blk00000003/sig000000db ),
    .O(\blk00000003/sig000000dc )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000065  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009b ),
    .I2(\blk00000003/sig0000009a ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000d7 )
  );
  MULT_AND   \blk00000003/blk00000064  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009b ),
    .LO(\blk00000003/sig000000d9 )
  );
  MUXCY   \blk00000003/blk00000063  (
    .CI(\blk00000003/sig000000d6 ),
    .DI(\blk00000003/sig000000d9 ),
    .S(\blk00000003/sig000000d7 ),
    .O(\blk00000003/sig000000d2 )
  );
  XORCY   \blk00000003/blk00000062  (
    .CI(\blk00000003/sig000000d6 ),
    .LI(\blk00000003/sig000000d7 ),
    .O(\blk00000003/sig000000d8 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000061  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009a ),
    .I2(\blk00000003/sig00000099 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000d3 )
  );
  MULT_AND   \blk00000003/blk00000060  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig0000009a ),
    .LO(\blk00000003/sig000000d5 )
  );
  MUXCY   \blk00000003/blk0000005f  (
    .CI(\blk00000003/sig000000d2 ),
    .DI(\blk00000003/sig000000d5 ),
    .S(\blk00000003/sig000000d3 ),
    .O(\blk00000003/sig000000ce )
  );
  XORCY   \blk00000003/blk0000005e  (
    .CI(\blk00000003/sig000000d2 ),
    .LI(\blk00000003/sig000000d3 ),
    .O(\blk00000003/sig000000d4 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000005d  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000099 ),
    .I2(\blk00000003/sig00000098 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000cf )
  );
  MULT_AND   \blk00000003/blk0000005c  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000099 ),
    .LO(\blk00000003/sig000000d1 )
  );
  MUXCY   \blk00000003/blk0000005b  (
    .CI(\blk00000003/sig000000ce ),
    .DI(\blk00000003/sig000000d1 ),
    .S(\blk00000003/sig000000cf ),
    .O(\blk00000003/sig000000ca )
  );
  XORCY   \blk00000003/blk0000005a  (
    .CI(\blk00000003/sig000000ce ),
    .LI(\blk00000003/sig000000cf ),
    .O(\blk00000003/sig000000d0 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000059  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000098 ),
    .I2(\blk00000003/sig00000097 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000cb )
  );
  MULT_AND   \blk00000003/blk00000058  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000098 ),
    .LO(\blk00000003/sig000000cd )
  );
  MUXCY   \blk00000003/blk00000057  (
    .CI(\blk00000003/sig000000ca ),
    .DI(\blk00000003/sig000000cd ),
    .S(\blk00000003/sig000000cb ),
    .O(\blk00000003/sig000000c6 )
  );
  XORCY   \blk00000003/blk00000056  (
    .CI(\blk00000003/sig000000ca ),
    .LI(\blk00000003/sig000000cb ),
    .O(\blk00000003/sig000000cc )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000055  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000097 ),
    .I2(\blk00000003/sig00000096 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000c7 )
  );
  MULT_AND   \blk00000003/blk00000054  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000097 ),
    .LO(\blk00000003/sig000000c9 )
  );
  MUXCY   \blk00000003/blk00000053  (
    .CI(\blk00000003/sig000000c6 ),
    .DI(\blk00000003/sig000000c9 ),
    .S(\blk00000003/sig000000c7 ),
    .O(\blk00000003/sig000000c2 )
  );
  XORCY   \blk00000003/blk00000052  (
    .CI(\blk00000003/sig000000c6 ),
    .LI(\blk00000003/sig000000c7 ),
    .O(\blk00000003/sig000000c8 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk00000051  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000096 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000c3 )
  );
  MULT_AND   \blk00000003/blk00000050  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000096 ),
    .LO(\blk00000003/sig000000c5 )
  );
  MUXCY   \blk00000003/blk0000004f  (
    .CI(\blk00000003/sig000000c2 ),
    .DI(\blk00000003/sig000000c5 ),
    .S(\blk00000003/sig000000c3 ),
    .O(\blk00000003/sig000000be )
  );
  XORCY   \blk00000003/blk0000004e  (
    .CI(\blk00000003/sig000000c2 ),
    .LI(\blk00000003/sig000000c3 ),
    .O(\blk00000003/sig000000c4 )
  );
  LUT4 #(
    .INIT ( 16'h4478 ))
  \blk00000003/blk0000004d  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000033 ),
    .I2(\blk00000003/sig00000033 ),
    .I3(\blk00000003/sig0000006e ),
    .O(\blk00000003/sig000000bf )
  );
  MULT_AND   \blk00000003/blk0000004c  (
    .I0(\blk00000003/sig0000006c ),
    .I1(\blk00000003/sig00000033 ),
    .LO(\blk00000003/sig000000c1 )
  );
  MUXCY   \blk00000003/blk0000004b  (
    .CI(\blk00000003/sig000000be ),
    .DI(\blk00000003/sig000000c1 ),
    .S(\blk00000003/sig000000bf ),
    .O(\NLW_blk00000003/blk0000004b_O_UNCONNECTED )
  );
  XORCY   \blk00000003/blk0000004a  (
    .CI(\blk00000003/sig000000be ),
    .LI(\blk00000003/sig000000bf ),
    .O(\blk00000003/sig000000c0 )
  );
  FDRS   \blk00000003/blk00000049  (
    .C(sig00000021),
    .D(\blk00000003/sig000000bd ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig0000002a)
  );
  FDRS   \blk00000003/blk00000048  (
    .C(sig00000021),
    .D(\blk00000003/sig000000bc ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000029)
  );
  FDRS   \blk00000003/blk00000047  (
    .C(sig00000021),
    .D(\blk00000003/sig000000bb ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000028)
  );
  FDRS   \blk00000003/blk00000046  (
    .C(sig00000021),
    .D(\blk00000003/sig000000ba ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000027)
  );
  FDRS   \blk00000003/blk00000045  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b9 ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000026)
  );
  FDRS   \blk00000003/blk00000044  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b8 ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000025)
  );
  FDRS   \blk00000003/blk00000043  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b7 ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000024)
  );
  FDRS   \blk00000003/blk00000042  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b4 ),
    .R(\blk00000003/sig000000b5 ),
    .S(\blk00000003/sig000000b6 ),
    .Q(sig00000023)
  );
  FDRS   \blk00000003/blk00000041  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b3 ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig00000030)
  );
  FDRS   \blk00000003/blk00000040  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b2 ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig00000031)
  );
  FDRS   \blk00000003/blk0000003f  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b1 ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig0000002d)
  );
  FDRS   \blk00000003/blk0000003e  (
    .C(sig00000021),
    .D(\blk00000003/sig000000b0 ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig0000002f)
  );
  FDRS   \blk00000003/blk0000003d  (
    .C(sig00000021),
    .D(\blk00000003/sig000000af ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig0000002e)
  );
  FDRS   \blk00000003/blk0000003c  (
    .C(sig00000021),
    .D(\blk00000003/sig000000ae ),
    .R(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig00000022)
  );
  FDRS   \blk00000003/blk0000003b  (
    .C(sig00000021),
    .D(\blk00000003/sig000000ac ),
    .R(\blk00000003/sig000000ad ),
    .S(\blk00000003/sig00000033 ),
    .Q(sig0000002c)
  );
  FDRS   \blk00000003/blk0000003a  (
    .C(sig00000021),
    .D(\blk00000003/sig000000a9 ),
    .R(\blk00000003/sig000000aa ),
    .S(\blk00000003/sig000000ab ),
    .Q(sig0000002b)
  );
  LUT2 #(
    .INIT ( 4'h6 ))
  \blk00000003/blk00000039  (
    .I0(sig0000001e),
    .I1(sig0000001b),
    .O(\blk00000003/sig00000095 )
  );
  LUT4 #(
    .INIT ( 16'h8001 ))
  \blk00000003/blk00000038  (
    .I0(sig0000001b),
    .I1(sig0000001a),
    .I2(\blk00000003/sig00000034 ),
    .I3(\blk00000003/sig00000033 ),
    .O(\blk00000003/sig0000007b )
  );
  LUT4 #(
    .INIT ( 16'h1998 ))
  \blk00000003/blk00000037  (
    .I0(sig0000001b),
    .I1(sig0000001a),
    .I2(\blk00000003/sig00000034 ),
    .I3(\blk00000003/sig00000033 ),
    .O(\blk00000003/sig00000079 )
  );
  LUT4 #(
    .INIT ( 16'h07E0 ))
  \blk00000003/blk00000036  (
    .I0(sig0000001b),
    .I1(sig0000001a),
    .I2(\blk00000003/sig00000034 ),
    .I3(\blk00000003/sig00000033 ),
    .O(\blk00000003/sig00000077 )
  );
  LUT4 #(
    .INIT ( 16'h8001 ))
  \blk00000003/blk00000035  (
    .I0(sig0000001e),
    .I1(sig0000001d),
    .I2(sig0000001c),
    .I3(sig0000001b),
    .O(\blk00000003/sig00000075 )
  );
  LUT4 #(
    .INIT ( 16'h1998 ))
  \blk00000003/blk00000034  (
    .I0(sig0000001e),
    .I1(sig0000001d),
    .I2(sig0000001c),
    .I3(sig0000001b),
    .O(\blk00000003/sig00000073 )
  );
  LUT4 #(
    .INIT ( 16'h07E0 ))
  \blk00000003/blk00000033  (
    .I0(sig0000001e),
    .I1(sig0000001d),
    .I2(sig0000001c),
    .I3(sig0000001b),
    .O(\blk00000003/sig00000071 )
  );
  LUT4 #(
    .INIT ( 16'h8001 ))
  \blk00000003/blk00000032  (
    .I0(\blk00000003/sig00000033 ),
    .I1(sig00000020),
    .I2(sig0000001f),
    .I3(sig0000001e),
    .O(\blk00000003/sig0000006f )
  );
  LUT4 #(
    .INIT ( 16'h1998 ))
  \blk00000003/blk00000031  (
    .I0(\blk00000003/sig00000033 ),
    .I1(sig00000020),
    .I2(sig0000001f),
    .I3(sig0000001e),
    .O(\blk00000003/sig0000006d )
  );
  LUT4 #(
    .INIT ( 16'h07E0 ))
  \blk00000003/blk00000030  (
    .I0(\blk00000003/sig00000033 ),
    .I1(sig00000020),
    .I2(sig0000001f),
    .I3(sig0000001e),
    .O(\blk00000003/sig0000006b )
  );
  MUXCY   \blk00000003/blk0000002f  (
    .CI(\blk00000003/sig00000034 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000000a8 ),
    .O(\blk00000003/sig00000069 )
  );
  LUT3 #(
    .INIT ( 8'h01 ))
  \blk00000003/blk0000002e  (
    .I0(\blk00000003/sig000000a5 ),
    .I1(\blk00000003/sig000000a6 ),
    .I2(\blk00000003/sig000000a7 ),
    .O(\blk00000003/sig000000a8 )
  );
  SRL16E #(
    .INIT ( 16'h0000 ))
  \blk00000003/blk0000002d  (
    .A0(\blk00000003/sig00000033 ),
    .A1(\blk00000003/sig00000033 ),
    .A2(\blk00000003/sig00000033 ),
    .A3(\blk00000003/sig00000033 ),
    .CE(\blk00000003/sig00000034 ),
    .CLK(sig00000021),
    .D(\blk00000003/sig0000009e ),
    .Q(\blk00000003/sig00000067 )
  );
  MUXCY   \blk00000003/blk0000002c  (
    .CI(\blk00000003/sig00000065 ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000000a3 ),
    .O(\blk00000003/sig000000a4 )
  );
  LUT1 #(
    .INIT ( 2'h2 ))
  \blk00000003/blk0000002b  (
    .I0(\blk00000003/sig00000068 ),
    .O(\blk00000003/sig000000a3 )
  );
  MUXCY   \blk00000003/blk0000002a  (
    .CI(\blk00000003/sig0000006a ),
    .DI(\blk00000003/sig00000033 ),
    .S(\blk00000003/sig000000a2 ),
    .O(\blk00000003/sig00000065 )
  );
  LUT3 #(
    .INIT ( 8'h01 ))
  \blk00000003/blk00000029  (
    .I0(\blk00000003/sig0000009f ),
    .I1(\blk00000003/sig000000a0 ),
    .I2(\blk00000003/sig000000a1 ),
    .O(\blk00000003/sig000000a2 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000028  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000033 ),
    .Q(\blk00000003/sig0000007d )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000027  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000001e),
    .Q(\blk00000003/sig0000009e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000026  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig00000010),
    .Q(\blk00000003/sig0000009d )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000025  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000f),
    .Q(\blk00000003/sig0000009c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000024  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000e),
    .Q(\blk00000003/sig0000009b )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000023  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000d),
    .Q(\blk00000003/sig0000009a )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000022  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000c),
    .Q(\blk00000003/sig00000099 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000021  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000b),
    .Q(\blk00000003/sig00000098 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000020  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(sig0000000a),
    .Q(\blk00000003/sig00000097 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000034 ),
    .Q(\blk00000003/sig00000096 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000095 ),
    .Q(\blk00000003/sig00000093 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000093 ),
    .Q(\blk00000003/sig00000094 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000091 ),
    .Q(\blk00000003/sig00000092 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000008f ),
    .Q(\blk00000003/sig00000090 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000001a  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000008d ),
    .Q(\blk00000003/sig0000008e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000019  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000008b ),
    .Q(\blk00000003/sig0000008c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000018  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000089 ),
    .Q(\blk00000003/sig0000008a )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000017  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000087 ),
    .Q(\blk00000003/sig00000088 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000016  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000085 ),
    .Q(\blk00000003/sig00000086 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000015  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000083 ),
    .Q(\blk00000003/sig00000084 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000014  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000081 ),
    .Q(\blk00000003/sig00000082 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000013  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000007f ),
    .Q(\blk00000003/sig00000080 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000012  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000007d ),
    .Q(\blk00000003/sig0000007e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000011  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000007b ),
    .Q(\blk00000003/sig0000007c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000010  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000079 ),
    .Q(\blk00000003/sig0000007a )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000f  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000077 ),
    .Q(\blk00000003/sig00000078 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000e  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000075 ),
    .Q(\blk00000003/sig00000076 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000d  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000073 ),
    .Q(\blk00000003/sig00000074 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000c  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000071 ),
    .Q(\blk00000003/sig00000072 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000b  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000006f ),
    .Q(\blk00000003/sig00000070 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk0000000a  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000006d ),
    .Q(\blk00000003/sig0000006e )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000009  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig0000006b ),
    .Q(\blk00000003/sig0000006c )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000008  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000069 ),
    .Q(\blk00000003/sig0000006a )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000007  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000067 ),
    .Q(\blk00000003/sig00000068 )
  );
  FDE #(
    .INIT ( 1'b0 ))
  \blk00000003/blk00000006  (
    .C(sig00000021),
    .CE(\blk00000003/sig00000034 ),
    .D(\blk00000003/sig00000065 ),
    .Q(\blk00000003/sig00000066 )
  );
  VCC   \blk00000003/blk00000005  (
    .P(\blk00000003/sig00000034 )
  );
  GND   \blk00000003/blk00000004  (
    .G(\blk00000003/sig00000033 )
  );

// synthesis translate_on

endmodule

// synthesis translate_off

`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;

    wire GSR;
    wire GTS;
    wire PRLD;

    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (weak1, weak0) GSR = GSR_int;
    assign (weak1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

endmodule

// synthesis translate_on
