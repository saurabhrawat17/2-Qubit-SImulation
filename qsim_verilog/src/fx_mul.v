//======================================================================
// fx_mul.v  -  Q1.14 fixed-point multiplier
//======================================================================
// Multiplies two Q1.14 numbers and returns a Q1.14 result.
//
// Q1.14 means: 1 sign bit, 1 integer bit, 14 fractional bits.
//   stored integer N represents the real value  N / 16384
//   so  1.0 -> 16384,  -1.0 -> -16384,  1/sqrt(2) -> 11585
//
// The maths:
//   (A/16384) * (B/16384) = (A*B)/16384^2
//   to get back to Q1.14 we divide by 16384 once  ->  (A*B) >> 14
//
// We add 2^13 before shifting so we round-to-nearest instead of always
// rounding toward negative infinity. This matches fx_mul() in the Python
// reference model exactly.
//
// NOTE ON WIDTH: the output is 20 bits, not 16. Products can exceed the
// 16-bit range, and if we truncated here the hardware would wrap where
// Python did not. We keep headroom through the datapath and saturate
// once, at the end, inside gate_unit.
//
// NOTE ON SIGNEDNESS: every port is declared `signed` and the shift is
// `>>>` (arithmetic), not `>>` (logical). Verilog treats values as
// unsigned by default. Forgetting this is the single most common bug in
// fixed-point HDL - the symptom is that positive numbers work fine and
// negative ones come out as huge positives.
//======================================================================

`timescale 1ns / 1ps

module fx_mul #(
    parameter W    = 16,    // input word width
    parameter FRAC = 14     // fractional bits
)(
    input  wire                 clk,
    input  wire signed [W-1:0]  a,
    input  wire signed [W-1:0]  b,
    output reg  signed [W+3:0]  p     // 20 bits: headroom, no wrap
);

    localparam signed [2*W-1:0] ROUND = 1 <<< (FRAC - 1);   // 8192

    wire signed [2*W-1:0] prod = a * b;
    wire signed [2*W-1:0] rnd  = prod + ROUND;

    always @(posedge clk)
        p <= rnd >>> FRAC;          // arithmetic shift right by 14

endmodule
