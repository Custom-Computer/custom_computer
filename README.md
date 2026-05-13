## BLG 222E Spring 2026 — Computer Organization Project

### Authors Ravan Seyfullayev and Raimbek Erik

### Description This project illustrates a simple computer architecture model, including:

- Basic Registers $${\color{green}finished}$$
- ALU Logic $${\color{green}finished}$$
- Memory Units $${\color{green}finished}$$
- Control Unit and Instruction Logic $${\color{green}finished}$$
- Simple program in using our computer and additional ISA elements $${\color{green}finished}$$

You find our reports in the $\textbf{report}$ directory.

## ALU System whole picture

![Alt Text](images/system.png)

## Assembly Syntax Reference

The custom 16-bit architecture uses a simple, intuitive assembly language syntax.

## How to Run the Assembler

1. Navigate to the `assembler` directory and write your assembly code in a `.asm` file (e.g., `simple.asm`).

2. Execute the assembler by passing your file as an argument:
   ```bash
   ./assembler simple.asm
   ```

Upon success, it will generate a `ROM.mem` file containing the assembled hex codes, ready to be loaded into the Verilog CPU simulation.
### Instruction Formats

The assembler supports two primary instruction formats:

**Type 1: Control Flow & Immediates**

- **Branches:** `OPCODE ADDRESS` or `OPCODE LABEL` (e.g., `BNE LOOP`, `BRA 0x0C`)
- **Immediates:** `IMM REG, ADDRESS` (e.g., `IMM R1, 0x0A`)

**Type 2: Data Processing & Arithmetic**

- **3-Operand (ALU):** `OPCODE DSTREG, SREG1, SREG2` (e.g., `ADD R1, R2, R3`)
- **2-Operand (Unary/Move):** `OPCODE DSTREG, SREG1` (e.g., `INC R1, R1`, `MOV R2, R1`)

### Registers

The architecture defines the following accessible registers:

- **General Purpose:** `R1`, `R2`, `R3`, `R4`
- **Special Purpose:** `PC` (Program Counter), `AR` (Address Register), `SP` (Stack Pointer)

### Labels and Comments

- **Labels:** Define a label by appending a colon `:` to an identifier. Labels can be placed on their own line or preceding an instruction. (e.g., `LOOP: DEC R1, R1`)
- **Comments:** Use the `#` symbol for line comments. (e.g., `# Initialize counter`)

### Example

```assembly
IMM R1, 0x05          # Initialize R1 to 5
IMM R2, 0x00          # Initialize accumulator R2 to 0

LOOP: ADD R2, R2, R1  # R2 = R2 + R1
DEC R1, R1            # Decrement R1
BNE LOOP              # If R1 != 0, branch to LOOP

HALT: BRA HALT        # Infinite loop to halt execution
```

© 2026 Ravan Seyfullayev and Raimbek Erik. All rights reserved.
