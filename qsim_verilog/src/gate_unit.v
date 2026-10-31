//======================================================================
// gate_unit.v  -  applies a 2x2 complex gate to ONE amplitude pair
//======================================================================
// This is the hardware version of apply_1q()'s inner body in the Python
// reference model:
//
//     out[i] = U00*a + U01*b
//     out[j] = U10*a + U11*b
//
// where a and b are complex amplitudes. Complex multiply:
//
//     (ur + j*ui)(xr + j*xi) = (ur*xr - ui*xi) + j(ur*xi + ui*xr)
//
// Four complex multiplies = 16 real multiplies. All 16 run in PARALLEL
// here, one fx_mul each. Vivado will map these onto DSP48 slices - the
// Artix-7 on the Basys 3 has about 90, so 16 is comfortable.
//
// TIMING / HANDSHAKE
//   cycle 0 : `start` high  -> inputs latched
//   cycle 1 : fx_mul registers the 16 products
//   cycle 2 : products summed, saturated, outputs registered, `done` set
//   cycle 3 : `done` visible to the FSM
//
// Inputs are latched internally on `start`, so the caller is free to
// change them immediately afterwards.
//======================================================================

`timescale 1ns / 1ps

module gate_unit (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,

    // amplitude pair in  (a = state[i], b = state[j])
    input  wire signed [15:0] ar_in, ai_in,
    input  wire signed [15:0] br_in, bi_in,

    // 2x2 complex gate matrix, Q1.14
    input  wire signed [15:0] u00r, u00i, u01r, u01i,
    input  wire signed [15:0] u10r, u10i, u11r, u11i,

    // amplitude pair out
    output reg  signed [15:0] ar_out, ai_out,
    output reg  signed [15:0] br_out, bi_out,
    output reg                done
);

    //------------------------------------------------------------------
    // Latched operands
    //------------------------------------------------------------------
    reg signed [15:0] ar, ai, br, bi;
    reg signed [15:0] g00r, g00i, g01r, g01i;
    reg signed [15:0] g10r, g10i, g11r, g11i;
    reg        [1:0]  stage;

    //------------------------------------------------------------------
    // 16 parallel multipliers
    //------------------------------------------------------------------
    wire signed [19:0] m00r_ar, m00i_ai, m01r_br, m01i_bi;   // row0 real
    wire signed [19:0] m00r_ai, m00i_ar, m01r_bi, m01i_br;   // row0 imag
    wire signed [19:0] m10r_ar, m10i_ai, m11r_br, m11i_bi;   // row1 real
    wire signed [19:0] m10r_ai, m10i_ar, m11r_bi, m11i_br;   // row1 imag

    fx_mul u_m0  (.clk(clk), .a(g00r), .b(ar), .p(m00r_ar));
    fx_mul u_m1  (.clk(clk), .a(g00i), .b(ai), .p(m00i_ai));
    fx_mul u_m2  (.clk(clk), .a(g01r), .b(br), .p(m01r_br));
    fx_mul u_m3  (.clk(clk), .a(g01i), .b(bi), .p(m01i_bi));

    fx_mul u_m4  (.clk(clk), .a(g00r), .b(ai), .p(m00r_ai));
    fx_mul u_m5  (.clk(clk), .a(g00i), .b(ar), .p(m00i_ar));
    fx_mul u_m6  (.clk(clk), .a(g01r), .b(bi), .p(m01r_bi));
    fx_mul u_m7  (.clk(clk), .a(g01i), .b(br), .p(m01i_br));

    fx_mul u_m8  (.clk(clk), .a(g10r), .b(ar), .p(m10r_ar));
    fx_mul u_m9  (.clk(clk), .a(g10i), .b(ai), .p(m10i_ai));
    fx_mul u_m10 (.clk(clk), .a(g11r), .b(br), .p(m11r_br));
    fx_mul u_m11 (.clk(clk), .a(g11i), .b(bi), .p(m11i_bi));

    fx_mul u_m12 (.clk(clk), .a(g10r), .b(ai), .p(m10r_ai));
    fx_mul u_m13 (.clk(clk), .a(g10i), .b(ar), .p(m10i_ar));
    fx_mul u_m14 (.clk(clk), .a(g11r), .b(bi), .p(m11r_bi));
    fx_mul u_m15 (.clk(clk), .a(g11i), .b(br), .p(m11i_br));

    //------------------------------------------------------------------
    // Wide accumulators (24 bits) - sum FIRST, saturate LAST.
    // Saturating each partial sum instead would give silently wrong
    // answers. The Python model accumulates wide too.
    //------------------------------------------------------------------
    wire signed [23:0] row0_re = {{4{m00r_ar[19]}}, m00r_ar}
                               - {{4{m00i_ai[19]}}, m00i_ai}
                               + {{4{m01r_br[19]}}, m01r_br}
                               - {{4{m01i_bi[19]}}, m01i_bi};

    wire signed [23:0] row0_im = {{4{m00r_ai[19]}}, m00r_ai}
                               + {{4{m00i_ar[19]}}, m00i_ar}
                               + {{4{m01r_bi[19]}}, m01r_bi}
                               + {{4{m01i_br[19]}}, m01i_br};

    wire signed [23:0] row1_re = {{4{m10r_ar[19]}}, m10r_ar}
                               - {{4{m10i_ai[19]}}, m10i_ai}
                               + {{4{m11r_br[19]}}, m11r_br}
                               - {{4{m11i_bi[19]}}, m11i_bi};

    wire signed [23:0] row1_im = {{4{m10r_ai[19]}}, m10r_ai}
                               + {{4{m10i_ar[19]}}, m10i_ar}
                               + {{4{m11r_bi[19]}}, m11r_bi}
                               + {{4{m11i_br[19]}}, m11i_br};

    //------------------------------------------------------------------
    // Saturation to 16-bit signed - same as saturate() in Python
    //------------------------------------------------------------------
    function signed [15:0] sat;
        input signed [23:0] v;
        begin
            if      (v >  24'sd32767)  sat =  16'sd32767;
            else if (v < -24'sd32768)  sat = -16'sd32768;
            else                       sat =  v[15:0];
        end
    endfunction

    //------------------------------------------------------------------
    // Control
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            stage  <= 2'd0;
            done   <= 1'b0;
            ar_out <= 16'sd0; ai_out <= 16'sd0;
            br_out <= 16'sd0; bi_out <= 16'sd0;
        end else begin
            done <= 1'b0;

            if (start) begin
                ar   <= ar_in;  ai   <= ai_in;
                br   <= br_in;  bi   <= bi_in;
                g00r <= u00r;   g00i <= u00i;
                g01r <= u01r;   g01i <= u01i;
                g10r <= u10r;   g10i <= u10i;
                g11r <= u11r;   g11i <= u11i;
                stage <= 2'd1;
            end else begin
                case (stage)
                    2'd1: stage <= 2'd2;        // multipliers working
                    2'd2: begin                 // products ready
                        ar_out <= sat(row0_re);
                        ai_out <= sat(row0_im);
                        br_out <= sat(row1_re);
                        bi_out <= sat(row1_im);
                        done   <= 1'b1;
                        stage  <= 2'd0;
                    end
                    default: stage <= 2'd0;
                endcase
            end
        end
    end

endmodule
