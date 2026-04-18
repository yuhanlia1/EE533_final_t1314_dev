from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from cpu_toolchain.assembler import parse_source
from cpu_toolchain.scheduler import schedule_instructions


class CpuSchedulerTests(unittest.TestCase):
    def test_adjacent_raw_dependency_inserts_one_nop(self) -> None:
        instructions = parse_source("  mov r0, #1\n  add r1, r0, #2\n")
        result = schedule_instructions(instructions)
        self.assertEqual(result.inserted_nops, 1)
        self.assertEqual(result.hazards[0].registers, ["r0"])
        self.assertEqual(result.instructions[1].mnemonic, "mov")
        self.assertEqual(result.instructions[1].operands, ["r5", "r5"])

    def test_independent_instructions_need_no_nop(self) -> None:
        instructions = parse_source("  mov r0, #1\n  mov r2, #2\n")
        result = schedule_instructions(instructions)
        self.assertEqual(result.inserted_nops, 0)
        self.assertEqual(len(result.instructions), 2)


if __name__ == "__main__":
    unittest.main()

