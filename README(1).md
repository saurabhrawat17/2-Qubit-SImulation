# Simulating Quantum Entanglement on a Programmable Chip

**A small hardware circuit, designed in a hardware description language and built on a student FPGA board, that computes what two entangled quantum bits would do and shows the result on the board's display.**

> 📹 **[Add a short video or photo here of the board running: pressing the button and the display changing from `4000` to `2D41`.]**

---

## The idea, in plain English

Ordinary computers store information in **bits**, and each bit is either 0 or 1. Quantum computers use **qubits**, which can be in a blend of 0 and 1 at the same time until they're measured. Qubits can also be **entangled**, which means linked so that measuring one tells you about the other.

A simple way to picture entanglement is two coins that always land the same way. Each flip on its own is a 50/50 chance, but the two coins never disagree. If one shows heads, so does the other.

Real quantum computers are rare, expensive, and kept near absolute zero. The **math** that describes how they behave is well understood, though. This project builds a circuit that does that math, so it can show what a pair of entangled qubits would look like.

**To be clear, this is not a quantum computer.** It's an ordinary chip that simulates one. The simulation follows the same mathematics that real quantum hardware follows.

## Why build it on a chip instead of writing a program?

Writing a quantum simulator in Python is a common project. I wanted to go one level deeper, so I designed the **hardware itself**.

The board is a **Basys 3**, which carries an **FPGA**. An FPGA is a chip whose internal wiring can be reconfigured. I didn't write instructions for a processor to follow. I described a circuit made of multipliers, memory, and control logic, and the chip physically rearranged itself to become that circuit.

## What it does

1. When the board is powered on, the two qubits start in the state "both 0."
2. Pressing the center button runs a two-step quantum circuit. The first step puts one qubit into an even blend of 0 and 1. The second step entangles it with the other qubit.
3. The board's display then shows the result, and the switches let you look at each of the four possible outcomes:

| Outcome | Display | Meaning |
|---|---|---|
| both 0 | `2D41` | 50% chance |
| first 0, second 1 | `0000` | never happens |
| first 1, second 0 | `0000` | never happens |
| both 1 | `2D41` | 50% chance |

That table shows the entanglement. The qubits always agree and never disagree, which is the same pattern as the two coins.

The whole calculation finishes in about **100 nanoseconds**, which is one ten-millionth of a second.

## The challenges along the way

- **Computers don't natively do the math quantum mechanics needs.** Quantum states use fractions and complex numbers, and the chip only handles whole numbers. I used a technique called *fixed-point arithmetic*, which represents fractions as scaled-up whole numbers. For example, the number 0.7071 is stored as 11,585.
- **Avoiding wasted work.** The textbook method multiplies huge tables of numbers, and most of the entries are zeros. This design only computes the pairs of values that actually matter. With 10 qubits, the textbook approach would spend more than 99% of its effort multiplying by zero.
- **Getting hardware to work at all.** Before any quantum math ran, I had to learn the professional design software (Xilinx Vivado), fix errors about how the circuit connects to the board's physical pins, and track down why my computer couldn't detect the board. The cause turned out to be a USB cable that carried power but no data.
- **Proving it's correct.** I built the same simulator in Python first, as a trusted reference. The hardware's output matches it exactly, down to the last digit.

## How this was built

> ✏️ **[Edit this section so it accurately describes your own contribution. Admissions readers value honesty here far more than they value a claim of doing everything alone.]**

I used an AI assistant (Claude) as a tutor and collaborator throughout this project. It explained the underlying concepts, helped design the architecture, and wrote much of the initial Python and Verilog code. My part was:

- setting up the toolchain and getting the board running end to end
- debugging the constraint and hardware-connection problems
- running the simulations and verifying the results against the reference model
- programming the physical board and testing it
- studying the design until I could explain how every part works
- [add anything else you did, such as changes you made, extensions you built, or data you collected]

## What I learned

> ✏️ **[Write this part yourself, in your own words. A few honest sentences about what surprised you, what was hard, or what changed in how you think will be worth more than anything written for you.]**

## What's next

- Support more types of quantum operations
- Scale from 2 qubits to 3 or more, and measure exactly where this chip runs out of resources
- Send results to a computer and check them automatically against professional quantum software (Qiskit)

## For technical readers

The full design is in this repository: Verilog source, a testbench, pin constraints, and a Python reference model. See [`TECHNICAL.md`](TECHNICAL.md) for the architecture, the fixed-point format (Q1.14), and the controller design.

---

**About me:** [Your name] · [School], [Grade] · Nairobi, Kenya · [email or other contact, optional]
