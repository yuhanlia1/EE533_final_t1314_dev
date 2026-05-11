from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from gpu_toolchain.parser import Parser


class GpuParserTests(unittest.TestCase):
    def test_parser_tracks_labels_and_comments(self) -> None:
        source = "\n".join(
            [
                "# comment",
                ".start:",
                "  loadi r0, 1",
                "done: halt",
                "",
            ]
        )
        parser = Parser(source)
        instructions = parser.parse()
        self.assertEqual(len(instructions), 2)
        self.assertEqual(parser.labels[".start"], 0)
        self.assertEqual(parser.labels["done"], 1)

    def test_duplicate_label_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate label"):
            Parser("loop:\nloop:\n  halt\n").parse()

    def test_dangling_label_raises(self) -> None:
        with self.assertRaisesRegex(ValueError, "dangling label"):
            Parser("done:\n").parse()


if __name__ == "__main__":
    unittest.main()

