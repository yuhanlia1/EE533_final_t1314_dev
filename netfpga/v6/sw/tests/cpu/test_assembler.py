from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from cpu_toolchain.assembler import compile_source, parse_source


class CpuAssemblerTests(unittest.TestCase):
    def test_compile_known_sequence(self) -> None:
        source = "\n".join(
            [
                ".start:",
                "  mov r0, #1",
                "  add r1, r0, #2",
                "  b .done",
                ".done:",
                "  mov r2, r1",
                "",
            ]
        )
        self.assertEqual(
            compile_source(source),
            [0xE3A00001, 0xE2801002, 0xEAFFFFFF, 0xE1A02001],
        )

    def test_aliases_are_normalized_during_parse(self) -> None:
        instructions = parse_source("  mov a1, #1\n")
        self.assertEqual(instructions[0].operands[0], "r0")

    def test_missing_branch_label_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "label .* not found"):
            compile_source("  b .missing\n")

    def test_invalid_register_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "invalid register format"):
            compile_source("  mov foo, #1\n")

    def test_immediate_out_of_range_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "12-bit signed immediate field"):
            compile_source("  mov r4, #3072\n")

    def test_shift_out_of_range_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "hardware 3-bit shift field"):
            compile_source("  lsl r4, r4, #8\n")


if __name__ == "__main__":
    unittest.main()
