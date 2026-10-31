//======================================================================
// seg7_display.v  -  4-digit hex readout on the Basys 3 7-segment
//======================================================================
// The Basys 3's four 7-segment digits share ONE set of segment wires.
// You cannot light them independently at the same time. Instead you
// show digit 0, then digit 1, then 2, then 3, cycling fast enough that
// persistence of vision makes all four look lit at once.
//
// refresh[17:16] steps at 100MHz / 2^16 = ~1.5 kHz, so the full 4-digit
// scan runs at ~380 Hz. Fast enough that there is no visible flicker.
//
// Both `seg` and `an` are ACTIVE LOW on this board: 0 lights a segment,
// 0 enables a digit.
//
// A 16-bit value is displayed as 4 hex digits, in two's complement.
// So  11585 -> 0x2D41,  and -11585 -> 0xD2BF.
//======================================================================

`timescale 1ns / 1ps

module seg7_display (
    input  wire        clk,
    input  wire [15:0] value,
    output reg  [6:0]  seg,     // active low, seg[0]=a ... seg[6]=g
    output reg  [3:0]  an,      // active low digit enables
    output wire        dp
);

    assign dp = 1'b1;           // decimal point off

    reg [17:0] refresh = 18'd0;
    always @(posedge clk)
        refresh <= refresh + 1'b1;

    wire [1:0] digit_sel = refresh[17:16];

    reg [3:0] nibble;

    // pick which digit is active and which 4 bits it shows
    always @(*) begin
        case (digit_sel)
            2'd0: begin an = 4'b1110; nibble = value[3:0];   end  // rightmost
            2'd1: begin an = 4'b1101; nibble = value[7:4];   end
            2'd2: begin an = 4'b1011; nibble = value[11:8];  end
            2'd3: begin an = 4'b0111; nibble = value[15:12]; end  // leftmost
        endcase
    end

    // hex nibble -> segment pattern (active low)
    always @(*) begin
        case (nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
        endcase
    end

endmodule
