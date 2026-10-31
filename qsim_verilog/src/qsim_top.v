//======================================================================
// qsim_top.v  -  2-qubit quantum circuit simulator on the Basys 3
//======================================================================
// Runs the circuit:   |00>  --H on qubit 0-->  --CNOT(0 -> 1)-->  Bell
//
// Expected final state (Q1.14 integers, matching the Python model):
//
//     re = [11585, 0, 0, 11585]      im = [0, 0, 0, 0]
//
// which is  (|00> + |11>) / sqrt(2)  -  a maximally entangled Bell pair.
//
//----------------------------------------------------------------------
// STATE REPRESENTATION
//   2 qubits -> 2^2 = 4 complex amplitudes.
//   Index i is a 2-bit number; bit k of i is qubit k, bit 0 is qubit 0.
//       index 0 = |00>   1 = |01>   2 = |10>   3 = |11>
//
//   At 2 qubits the whole state is 8 x 16-bit values, so it lives in
//   REGISTERS. No block RAM, no address generator, no read latency.
//   (Scaling past ~6 qubits is where you would move to BRAM.)
//
//----------------------------------------------------------------------
// GATE SCHEDULE
//   H on qubit 0 touches index pairs that differ in bit 0: (0,1) and (2,3)
//   CNOT control=0 target=1 swaps the amplitudes where control bit is 1
//   and target bit is 0  ->  that is index 1 with index 3.
//
//----------------------------------------------------------------------
// USER INTERFACE
//   btnC         : run the circuit (press once)
//   btnU         : reset back to |00>
//   sw[1:0]      : which amplitude to display (0..3)
//   sw[2]        : 0 = show real part, 1 = show imaginary part
//   7-seg        : selected value as 4 hex digits (two's complement)
//   led[15:0]    : same value in binary
//======================================================================

`timescale 1ns / 1ps

module qsim_top #(
    parameter DEBOUNCE_N = 20      // testbench overrides this to go fast
)(
    input  wire        clk,        // 100 MHz
    input  wire        btnC,       // run
    input  wire        btnU,       // reset
    input  wire [2:0]  sw,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);

    //==================================================================
    // Fixed-point constants (Q1.14)
    //==================================================================
    localparam signed [15:0] FX_ONE      =  16'sd16384;   //  1.0
    localparam signed [15:0] FX_ZERO     =  16'sd0;       //  0.0
    localparam signed [15:0] FX_INVSQRT2 =  16'sd11585;   //  0.70710678...
    localparam signed [15:0] FX_NINVSQRT2= -16'sd11585;   // -0.70710678...

    //==================================================================
    // State vector: 4 complex amplitudes in registers
    //==================================================================
    reg signed [15:0] st_re [0:3];
    reg signed [15:0] st_im [0:3];

    // Power-on values. On Xilinx FPGAs an `initial` block on a register
    // is synthesisable - the bitstream sets the flip-flop's start value.
    // So the board already shows |00> the moment it is programmed, with
    // no reset press needed.
    initial begin
        st_re[0] = FX_ONE;   st_im[0] = FX_ZERO;
        st_re[1] = FX_ZERO;  st_im[1] = FX_ZERO;
        st_re[2] = FX_ZERO;  st_im[2] = FX_ZERO;
        st_re[3] = FX_ZERO;  st_im[3] = FX_ZERO;
    end

    //==================================================================
    // Buttons
    //==================================================================
    wire run_pulse, rst_pulse;

    debounce #(.N(DEBOUNCE_N)) u_db_run (.clk(clk), .noisy(btnC), .pulse(run_pulse));
    debounce #(.N(DEBOUNCE_N)) u_db_rst (.clk(clk), .noisy(btnU), .pulse(rst_pulse));

    //==================================================================
    // Gate unit
    //==================================================================
    reg                gu_start;
    reg  signed [15:0] gu_ar, gu_ai, gu_br, gu_bi;
    wire signed [15:0] gu_ar_o, gu_ai_o, gu_br_o, gu_bi_o;
    wire               gu_done;

    // Only the Hadamard is ever fed to the gate unit in this design, so
    // its matrix is wired straight in. To add more gates later, replace
    // these with registers driven from a gate-constant ROM.
    //
    //   H = 1/sqrt(2) * [ 1   1 ]
    //                   [ 1  -1 ]
    gate_unit u_gate (
        .clk    (clk),
        .rst    (1'b0),
        .start  (gu_start),
        .ar_in  (gu_ar), .ai_in (gu_ai),
        .br_in  (gu_br), .bi_in (gu_bi),
        .u00r   (FX_INVSQRT2),  .u00i (FX_ZERO),
        .u01r   (FX_INVSQRT2),  .u01i (FX_ZERO),
        .u10r   (FX_INVSQRT2),  .u10i (FX_ZERO),
        .u11r   (FX_NINVSQRT2), .u11i (FX_ZERO),
        .ar_out (gu_ar_o), .ai_out (gu_ai_o),
        .br_out (gu_br_o), .bi_out (gu_bi_o),
        .done   (gu_done)
    );

    //==================================================================
    // Controller FSM
    //==================================================================
    localparam S_IDLE   = 3'd0;   // waiting for btnC
    localparam S_INIT   = 3'd1;   // load |00>
    localparam S_H_P0   = 3'd2;   // issue H on pair (0,1)
    localparam S_H_P0_W = 3'd3;   // wait, then store
    localparam S_H_P1   = 3'd4;   // issue H on pair (2,3)
    localparam S_H_P1_W = 3'd5;   // wait, then store
    localparam S_CNOT   = 3'd6;   // swap index 1 and index 3
    localparam S_DONE   = 3'd7;   // result held, displayed

    reg [2:0] state;
    initial state = S_IDLE;

    integer idx;

    always @(posedge clk) begin
        gu_start <= 1'b0;

        if (rst_pulse) begin
            state <= S_IDLE;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                st_re[idx] <= FX_ZERO;
                st_im[idx] <= FX_ZERO;
            end
            st_re[0] <= FX_ONE;                // back to |00>
        end else begin
            case (state)

                //------------------------------------------------------
                S_IDLE: begin
                    if (run_pulse)
                        state <= S_INIT;
                end

                //------------------------------------------------------
                // Load |00> : amplitude 1.0 on index 0, zero elsewhere
                //------------------------------------------------------
                S_INIT: begin
                    st_re[0] <= FX_ONE;  st_im[0] <= FX_ZERO;
                    st_re[1] <= FX_ZERO; st_im[1] <= FX_ZERO;
                    st_re[2] <= FX_ZERO; st_im[2] <= FX_ZERO;
                    st_re[3] <= FX_ZERO; st_im[3] <= FX_ZERO;
                    state <= S_H_P0;
                end

                //------------------------------------------------------
                // H on qubit 0, first pair: indices 0 and 1
                //------------------------------------------------------
                S_H_P0: begin
                    gu_ar    <= st_re[0];  gu_ai <= st_im[0];
                    gu_br    <= st_re[1];  gu_bi <= st_im[1];
                    gu_start <= 1'b1;
                    state    <= S_H_P0_W;
                end

                S_H_P0_W: begin
                    if (gu_done) begin
                        st_re[0] <= gu_ar_o;  st_im[0] <= gu_ai_o;
                        st_re[1] <= gu_br_o;  st_im[1] <= gu_bi_o;
                        state    <= S_H_P1;
                    end
                end

                //------------------------------------------------------
                // H on qubit 0, second pair: indices 2 and 3
                //------------------------------------------------------
                S_H_P1: begin
                    gu_ar    <= st_re[2];  gu_ai <= st_im[2];
                    gu_br    <= st_re[3];  gu_bi <= st_im[3];
                    gu_start <= 1'b1;
                    state    <= S_H_P1_W;
                end

                S_H_P1_W: begin
                    if (gu_done) begin
                        st_re[2] <= gu_ar_o;  st_im[2] <= gu_ai_o;
                        st_re[3] <= gu_br_o;  st_im[3] <= gu_bi_o;
                        state    <= S_CNOT;
                    end
                end

                //------------------------------------------------------
                // CNOT, control = qubit 0, target = qubit 1.
                // Pure swap - no multipliers, one cycle.
                // Indices with control bit set and target bit clear: i=1
                // Partner: j = 1 | (1<<1) = 3
                //
                // This swap needs no temporary variable. Non-blocking
                // assignment (<=) evaluates ALL right-hand sides first,
                // then assigns, so both reads see the old values. In
                // software this would need a temp; in hardware it is
                // literally two registers swapping contents in one edge.
                //------------------------------------------------------
                S_CNOT: begin
                    st_re[1] <= st_re[3];  st_im[1] <= st_im[3];
                    st_re[3] <= st_re[1];  st_im[3] <= st_im[1];
                    state    <= S_DONE;
                end

                //------------------------------------------------------
                S_DONE: begin
                    if (run_pulse)
                        state <= S_INIT;       // run it again
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    //==================================================================
    // Display: pick one amplitude component and show it
    //==================================================================
    reg signed [15:0] shown;

    always @(*) begin
        if (sw[2]) shown = st_im[sw[1:0]];
        else       shown = st_re[sw[1:0]];
    end

    assign led = shown;

    seg7_display u_disp (
        .clk   (clk),
        .value (shown),
        .seg   (seg),
        .an    (an),
        .dp    (dp)
    );

endmodule
