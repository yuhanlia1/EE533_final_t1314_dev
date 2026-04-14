# ARM Compiler for Bubble Assembly

This project implements a simple ARM assembler and compiler that supports all the instructions found in the uploaded version of `bubble.s`. The toolchain consists of two scripts:

1. **preprocess.py** – Converts pseudo instructions into actual instructions supported by our processor.
2. **armCompiler.py** – Compiles the processed assembly file into machine code.

Features
--------

* **Pseudo-Instructions Conversion:**  
  `preprocess.py` replaces all pseudo instructions with actual instructions, producing a fully functional assembly file.

* **Compilation:**  
  `armCompiler.py` compiles the assembly file into two output files:
  
  * **Debug Output:** A file containing all marks (labels), PC values, and the reprinted instructions for debugging purposes.
  * **Hex Output:** A file with the compiled instructions in hexadecimal format (one per line).

* **Supported Instructions:**  
  The compiler supports all instructions included in the uploaded version of `bubble.s` (e.g., data processing instructions like `add`, `sub`, `mov`, `lsl`, as well as branch and memory load/store instructions).

How to Use
----------

1. **Preprocessing the Assembly File**
   Run the `preprocess.py` script to convert pseudo instructions into supported instructions:
      python preprocess.py original.s processed.s
* **Input:** `original.s` – your original assembly source file.

* **Output:** `processed.s` – the fully processed assembly file with only supported instructions.
  
  2. **Compiling the Processed Assembly**
  
  Use `armCompiler.py` to compile the processed assembly file:
    python armCompiler.py processed.s
  This script will generate two output files:

* `output.txt` – Contains the reprinted assembly with PC marks and label mappings for debugging.

* `compiled_binary.txt` – Contains the compiled machine code in hexadecimal format (one instruction per line).

Example
-------

Assuming you have an assembly file named `bubble.s`, the process is as simple as:




    python preprocess.py bubble.s processed.s
    python armCompiler.py processed.s

After running these commands, check the output files:

* **`output.txt`** – For a detailed view with PC addresses and label mappings.
* **`compiled_binary.txt`** – For the final compiled binary code in hex.

Requirements
------------

* Python 3.x

No additional libraries are needed.
