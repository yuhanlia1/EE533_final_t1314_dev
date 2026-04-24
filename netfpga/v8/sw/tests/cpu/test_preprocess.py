from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from cpu_toolchain.preprocess import preprocess_source


class CpuPreprocessTests(unittest.TestCase):
    def test_ldmia_expands_and_preserves_label(self) -> None:
        source = "loop: ldmia lr!, {r0, r1, r2, r3}\n"
        result = preprocess_source(source)
        self.assertEqual(
            result,
            "\n".join(
                [
                    "loop: ldr r0, [lr]",
                    "add lr, lr, #4",
                    "ldr r1, [lr]",
                    "add lr, lr, #4",
                    "ldr r2, [lr]",
                    "add lr, lr, #4",
                    "ldr r3, [lr]",
                    "add lr, lr, #4",
                    "",
                ]
            ),
        )

    def test_literal_ldr_is_rewritten_to_mov(self) -> None:
        result = preprocess_source("  ldr r3, CONST_WORD\n")
        self.assertEqual(result, "  mov r3, #128\n")


if __name__ == "__main__":
    unittest.main()
