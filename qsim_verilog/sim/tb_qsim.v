//======================================================================
// tb_qsim.v  -  testbench
//======================================================================
// Checks the hardware against the Python reference model's answer.
//
// qsim_reference.py printed:   raw integers re = [11585, 0, 0, 11585]
// so that is exactly what the state registers must contain.
//
// Run in Vivado: add this as a SIMULATION source, then Run Simulation.
// Run with Icarus:  iverilog -o sim.out src/*.v sim/tb_qsim.v && vvp sim.out
//======================================================================

`timescale 1ns / 1ps

module tb_qsim;

    reg         clk = 1'b0;
    reg         btnC = 1'b0;
    reg         btnU = 1'b0;
    reg  [2:0]  sw   = 3'b000;
    wire [15:0] led;
    wire [6:0]  seg;
    wire [3:0]  an;
    wire        dp;

    integer errors = 0;

    // 100 MHz
    always #5 clk = ~clk;

    // DEBOUNCE_N = 3 so a button press settles in 8 clocks, not 10 ms
    qsim_top #(.DEBOUNCE_N(3)) dut (
        .clk (clk), .btnC (btnC), .btnU (btnU), .sw (sw),
        .led (led), .seg (seg), .an (an), .dp (dp)
    );

    //------------------------------------------------------------------
    task press_run;
        begin
            btnC = 1'b1;
            repeat (40) @(posedge clk);
            btnC = 1'b0;
            repeat (40) @(posedge clk);
        end
    endtask

    task check;
        input [255:0] label;
        input signed [15:0] got;
        input signed [15:0] want;
        begin
            if (got !== want) begin
                $display("  FAIL  %0s : got %0d, expected %0d",
                         label, got, want);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s = %0d", label, got);
            end
        end
    endtask

    //------------------------------------------------------------------
    initial begin
        $dumpfile("tb_qsim.vcd");
        $dumpvars(0, tb_qsim);

        $display("");
        $display("=============================================");
        $display(" 2-qubit Bell state simulator - testbench");
        $display("=============================================");

        repeat (20) @(posedge clk);

        $display("");
        $display("Power-on state should already be |00> (amplitude 1.0):");
        check("re[0] at power-on", dut.st_re[0], 16'sd16384);
        check("re[3] at power-on", dut.st_re[3], 16'sd0);

        $display("");
        $display("Pressing RUN...");
        press_run;

        // let the FSM finish (a handful of cycles)
        repeat (60) @(posedge clk);

        $display("");
        $display("FSM state = %0d (7 = S_DONE)", dut.state);
        $display("");
        $display("Final state vector (Q1.14 integers):");
        $display("  index 0 |00> :  re=%0d  im=%0d", dut.st_re[0], dut.st_im[0]);
        $display("  index 1 |01> :  re=%0d  im=%0d", dut.st_re[1], dut.st_im[1]);
        $display("  index 2 |10> :  re=%0d  im=%0d", dut.st_re[2], dut.st_im[2]);
        $display("  index 3 |11> :  re=%0d  im=%0d", dut.st_re[3], dut.st_im[3]);

        $display("");
        $display("Checking against Python reference [11585, 0, 0, 11585]:");
        check("re[0]", dut.st_re[0], 16'sd11585);
        check("re[1]", dut.st_re[1], 16'sd0);
        check("re[2]", dut.st_re[2], 16'sd0);
        check("re[3]", dut.st_re[3], 16'sd11585);
        check("im[0]", dut.st_im[0], 16'sd0);
        check("im[1]", dut.st_im[1], 16'sd0);
        check("im[2]", dut.st_im[2], 16'sd0);
        check("im[3]", dut.st_im[3], 16'sd11585 - 16'sd11585);

        //--------------------------------------------------------------
        // Display multiplexer check
        //--------------------------------------------------------------
        $display("");
        $display("Checking the display selector:");
        sw = 3'b000; #1;
        check("sw=000 shows re[0]", led, 16'sd11585);
        sw = 3'b011; #1;
        check("sw=011 shows re[3]", led, 16'sd11585);
        sw = 3'b001; #1;
        check("sw=001 shows re[1]", led, 16'sd0);
        sw = 3'b100; #1;
        check("sw=100 shows im[0]", led, 16'sd0);

        //--------------------------------------------------------------
        $display("");
        $display("=============================================");
        if (errors == 0) begin
            $display(" ALL CHECKS PASSED");
            $display("");
            $display(" 11585 / 16384 = 0.70709  ~=  1/sqrt(2)");
            $display(" State is (|00> + |11>)/sqrt(2) - a Bell pair.");
        end else begin
            $display(" %0d CHECK(S) FAILED", errors);
        end
        $display("=============================================");
        $display("");

        $finish;
    end

endmodule
