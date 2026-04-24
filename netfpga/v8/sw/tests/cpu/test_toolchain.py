from __future__ import annotations

import os
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock


TESTS_DIR = Path(__file__).resolve().parents[1]
SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from helpers import write_fake_annctl
from cpu_toolchain.toolchain import build_single, load_image, package_directory


class CpuToolchainTests(unittest.TestCase):
    def test_build_single_emits_expected_artifacts_and_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / "program.s"
            out_dir = tmp_path / "out"
            source_path.write_text(".main:\n  mov r0, #1\n  add r1, r0, #2\n", encoding="utf-8")

            result = build_single(str(source_path), str(out_dir))

            self.assertEqual(result.mode, "single")
            self.assertEqual(result.total_words, 3)
            self.assertTrue((out_dir / "processed.s").is_file())
            self.assertTrue((out_dir / "scheduled.s").is_file())
            self.assertTrue((out_dir / "compiled_binary.txt").is_file())
            self.assertTrue((out_dir / "image.txt").is_file())
            self.assertIn("0x00000000 0xe3a00001", (out_dir / "image.txt").read_text(encoding="utf-8"))
            self.assertIn("thread0.inserted_nops=1", (out_dir / "build_report.txt").read_text(encoding="utf-8"))

    def test_package_directory_auto_stubs_missing_threads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            package_dir = tmp_path / "pkg"
            out_dir = tmp_path / "out"
            package_dir.mkdir()
            (package_dir / "thread0.s").write_text(".main:\n  mov r0, #1\n", encoding="utf-8")
            (package_dir / "thread1.s").write_text(".main:\n  mov r1, #2\n", encoding="utf-8")

            result = package_directory(str(package_dir), str(out_dir))

            self.assertEqual(result.mode, "package")
            self.assertFalse(result.threads[0].auto_stub)
            self.assertFalse(result.threads[1].auto_stub)
            self.assertTrue(result.threads[2].auto_stub)
            self.assertTrue(result.threads[3].auto_stub)
            self.assertIn("thread2 base=0x00000100", (out_dir / "image_map.txt").read_text(encoding="utf-8"))

    def test_load_image_invokes_annctl_cpu_load(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            image_path = tmp_path / "image.txt"
            annctl_path = tmp_path / "annctl_mock.pl"
            log_path = tmp_path / "annctl.log"
            image_path.write_text("0x00000000 0xe3a00001\n", encoding="utf-8")
            write_fake_annctl(annctl_path)

            with mock.patch.dict(os.environ, {"ANNCTL_LOG": str(log_path)}):
                load_image(str(image_path), base_addr="16", annctl_path=str(annctl_path))

            self.assertEqual(log_path.read_text(encoding="utf-8").strip(), f"cpu load {image_path} 16")

    def test_build_single_rejects_overlong_programs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / "too_long.s"
            out_dir = tmp_path / "out"
            body = ".main:\n" + ("  mov r0, #0\n" * 128)
            source_path.write_text(body, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "127-word limit"):
                build_single(str(source_path), str(out_dir))


if __name__ == "__main__":
    unittest.main()

