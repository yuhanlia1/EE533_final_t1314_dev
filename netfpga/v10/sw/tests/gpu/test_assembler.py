from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from gpu_toolchain.assembler import Assembler


class GpuAssemblerTests(unittest.TestCase):
    def test_compile_minimal_program(self) -> None:
        source = Path(SW_DIR / "testdata" / "gpu_program_minimal.gpus").read_text(encoding="utf-8")
        assembler = Assembler(source)
        assembler.parse()
        self.assertEqual(
            assembler.compile_all(),
            [0x10000001, 0xD2000000, 0xE0000003, 0xF0000000],
        )

    def test_tensor_mac_bf16_sets_dtype_bit(self) -> None:
        assembler = Assembler("  tensor_mac r6, r0, r1, bf16\n")
        assembler.parse()
        self.assertEqual(assembler.compile_all(), [0xCC090000])

    def test_invalid_base_selector_raises(self) -> None:
        assembler = Assembler("  load r0, Z, 0\n")
        assembler.parse()
        with self.assertRaisesRegex(ValueError, "invalid GPU base selector"):
            assembler.compile_all()


if __name__ == "__main__":
    unittest.main()

