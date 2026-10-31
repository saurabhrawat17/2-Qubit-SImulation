# 2-Qubit Quantum Circuit Simulator on the Basys 3

Builds a **Bell state** — `(|00⟩ + |11⟩)/√2`, a maximally entangled pair —
in hardware, and displays the resulting state vector on the board.

Verified in simulation against the Python reference model: both produce
`re = [11585, 0, 0, 11585]`, `im = [0, 0, 0, 0]`.

---

## Files

```
src/fx_mul.v         Q1.14 fixed-point multiplier
src/gate_unit.v      applies a 2x2 complex gate to one amplitude pair
src/seg7_display.v   4-digit hex readout with refresh multiplexing
src/debounce.v       button debouncer + edge detect
src/qsim_top.v       state registers, controller FSM, display mux
sim/tb_qsim.v        testbench - checks against the Python model
constrs/Basys3_qsim.xdc   pin constraints
```

---

## Build steps in Vivado

1. **Create a new RTL project.** Choose the Basys 3 board, or the part
   `xc7a35tcpg236-1` directly if the board files aren't installed.

2. **Add design sources:** all five `.v` files from `src/`.

3. **Add a simulation source:** `sim/tb_qsim.v`.

4. **Add the constraints file:** `constrs/Basys3_qsim.xdc`.

5. **Set `qsim_top` as the top module** — right-click it in the Sources
   pane → *Set as Top*. It should appear in bold.

6. **Run Simulation → Run Behavioral Simulation** *first*. Check the Tcl
   console prints `ALL CHECKS PASSED`. Don't skip this — if simulation
   fails, hardware will too, and simulation tells you why.

7. **Run Synthesis**, then **Run Implementation**, then
   **Generate Bitstream**. (Generate Bitstream will run the earlier
   steps automatically if needed.)

8. **Open Hardware Manager → Open Target → Auto Connect →
   Program Device.**

### If bitstream generation fails with DRC NSTD-1 or UCIO-1

That means a port in `qsim_top.v` has no matching constraint in the XDC.
The error names the problem port. Check that the port name in the XDC
matches the Verilog **exactly**, including whether it's a vector:
`led[0]` in the XDC only matches a port declared as a vector, not a
scalar named `led`.

---

## Using it on the board

| Control | Effect |
|---|---|
| **btnC** (centre) | Run the circuit |
| **btnU** (up) | Reset back to \|00⟩ |
| **sw[1:0]** | Select which amplitude to display (0–3) |
| **sw[2]** | 0 = real part, 1 = imaginary part |
| **7-segment** | Selected value as 4 hex digits |
| **LEDs** | Same value in binary |

### What you should see

**At power-on**, with all switches down, the display reads `4000`.
That's hex for 16384 — amplitude 1.0 in Q1.14. The state is |00⟩ with
certainty.

**Press btnC.** The display changes to `2D41` — hex for 11585, which is
1/√2 ≈ 0.7071.

Now sweep `sw[1:0]` through all four amplitudes:

| sw[1:0] | Index | Basis state | Display | Value |
|---|---|---|---|---|
| 00 | 0 | \|00⟩ | `2D41` | +0.7071 |
| 01 | 1 | \|01⟩ | `0000` | 0 |
| 10 | 2 | \|10⟩ | `0000` | 0 |
| 11 | 3 | \|11⟩ | `2D41` | +0.7071 |

**That table is the result.** Equal amplitude on |00⟩ and |11⟩, exactly
zero on |01⟩ and |10⟩ — the two qubits are perfectly correlated and
never disagree. That's entanglement, computed by hardware you built.

Flip `sw[2]` to confirm all imaginary parts read `0000`.

---

## How it works, step by step

### The state lives in registers

Two qubits means 2² = 4 complex amplitudes. Each is two 16-bit
fixed-point numbers (real and imaginary), so the entire quantum state is
8 × 16 = 128 bits — small enough to hold in flip-flops. No block RAM, no
address generator, no memory latency to manage.

This is why 2 qubits is the right starting point. At 6+ qubits you'd
need BRAM and all the complexity that brings.

### Q1.14 fixed point

The FPGA has no floating-point unit. So an amplitude is stored as a
16-bit integer that represents `value / 16384`:

| Real value | Stored as |
|---|---|
| 1.0 | 16384 |
| 1/√2 = 0.70710678… | 11585 |
| −1/√2 | −11585 |
| 0.0 | 0 |

Multiplying two of these gives a result scaled by 16384², so the
hardware multiplies, adds 8192 (to round to nearest rather than always
downward), and shifts right by 14. That's all `fx_mul.v` does.

### Gates act on amplitude *pairs*, not on big matrices

A single-qubit gate on qubit *k* only ever combines amplitudes whose
indices **differ in bit k**. For H on qubit 0, that's pairs (0,1) and
(2,3).

This matters enormously. The textbook approach builds a 2ⁿ×2ⁿ matrix —
at 10 qubits that's over a million entries of which only 2048 are
non-zero, so 99.8% of the work would be multiplying by zero. The pairing
approach touches only what matters.

`gate_unit.v` handles one pair: it computes

```
out[i] = U00·a + U01·b
out[j] = U10·a + U11·b
```

using 16 parallel multipliers (four complex multiplies, four real
multiplies each). The Artix-7 has roughly 90 DSP slices, so 16 is
comfortable.

### The FSM walks through the circuit

```
S_IDLE    wait for btnC
S_INIT    load |00⟩  →  re[0] = 16384, everything else 0
S_H_P0    feed pair (0,1) to the gate unit with the H matrix
S_H_P0_W  wait ~3 cycles for the pipeline, store results
S_H_P1    feed pair (2,3)
S_H_P1_W  wait, store
S_CNOT    swap amplitude 1 with amplitude 3
S_DONE    hold the result for display
```

The whole circuit executes in about 10 clock cycles at 100 MHz — roughly
100 nanoseconds. The button debouncer takes 10 milliseconds, so you're
waiting 100,000× longer for your finger than for the computation.

### Why CNOT needs no multipliers

CNOT flips the target qubit wherever the control qubit is 1. In index
terms: for every index with the control bit set and the target bit
clear, swap that amplitude with the one at the target-bit-flipped index.
With control=0 and target=1, that's index 1 ↔ index 3. A pure swap, one
clock cycle, zero arithmetic.

### Tracing the Bell state by hand

```
start           re = [16384,     0,     0,     0]      = |00⟩

H on qubit 0:
  pair (0,1):   a = 16384, b = 0
                out[0] = (11585·16384) >> 14 = 11585
                out[1] = (11585·16384) >> 14 = 11585
  pair (2,3):   both zero, stay zero

                re = [11585, 11585,     0,     0]

CNOT(0→1):      swap index 1 and index 3

                re = [11585,     0,     0, 11585]      = Bell state
```

Every number there is checkable by hand, which is exactly why this is a
good first design.

---

## Extending it

In rough order of difficulty:

1. **More gates.** Replace the hardwired H matrix in `qsim_top.v` with a
   small ROM of gate constants selected by an opcode. X, Y, Z, S, T are
   all just different Q1.14 constants.
2. **Step mode.** Use btnR to advance one gate at a time so you can watch
   the state evolve on the display.
3. **Probabilities.** Compute |amplitude|² = re² + im² and show that
   instead — more intuitive for a demo.
4. **3 qubits.** 8 amplitudes, 4 pairs per gate. Still fits in registers.
   This is where the address-generation formula starts earning its keep:
   `i = ((c >> k) << (k+1)) | (c & ((1 << k) - 1))`.
5. **Instruction ROM.** Store a gate sequence and execute it — this turns
   the design from a fixed circuit into an actual programmable machine.
6. **UART output.** Stream the state vector to a PC and diff it against
   Qiskit automatically.
7. **Block RAM.** Needed past ~6 qubits, where registers stop fitting.

## Data worth collecting

After each synthesis run, open the **utilization report** and record LUT,
FF, DSP and BRAM usage against qubit count. Also note the measured
precision loss from the Python model at each word width.

Those two series — resources vs. qubits, and error vs. gate depth — are
the actual engineering results here. The Bell state is the demo; the
scaling characterisation is the finding.
