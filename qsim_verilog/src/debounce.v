//======================================================================
// debounce.v  -  button debouncer + rising-edge pulse generator
//======================================================================
// Mechanical buttons bounce: one physical press produces dozens of
// electrical transitions over a few milliseconds. Without this, one
// press would run the circuit many times.
//
// Two jobs:
//   1. Synchronise the asynchronous button into the clock domain
//      (the two flip-flops sync0/sync1 - skipping this causes
//      metastability, which shows up as rare random misbehaviour).
//   2. Require the level to hold steady for 2^N clocks before believing
//      it, then emit a SINGLE-CYCLE pulse on the rising edge.
//
// N = 20 at 100 MHz is about 10 ms. The testbench overrides N to a
// small value so simulation does not take forever.
//======================================================================

`timescale 1ns / 1ps

module debounce #(
    parameter N = 20
)(
    input  wire clk,
    input  wire noisy,
    output reg  pulse
);

    reg         sync0 = 1'b0, sync1 = 1'b0;
    reg         stable = 1'b0;
    reg [N-1:0] cnt = {N{1'b0}};

    always @(posedge clk) begin
        sync0 <= noisy;
        sync1 <= sync0;
    end

    always @(posedge clk) begin
        pulse <= 1'b0;

        if (sync1 != stable) begin
            cnt <= cnt + 1'b1;
            if (&cnt) begin                 // held long enough
                stable <= sync1;
                cnt    <= {N{1'b0}};
                if (sync1) pulse <= 1'b1;   // rising edge only
            end
        end else begin
            cnt <= {N{1'b0}};               // bounced back, restart
        end
    end

endmodule
