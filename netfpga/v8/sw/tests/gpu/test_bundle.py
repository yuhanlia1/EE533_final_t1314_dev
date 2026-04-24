from __future__ import annotations

import os
import sys
import tempfile
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
from gpu_toolchain.bundle import build_program, inspect_target, load_bundle, package_bundle, template_mlp


class GpuBundleTests(unittest.TestCase):
    def test_build_program_emits_expected_imem_hex(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / "program.gpus"
            out_dir = tmp_path / "out"
            source_path.write_text(".start:\n  loadi r0, 1\n  halt\n", encoding="utf-8")

            result = build_program(str(source_path), str(out_dir))

            self.assertEqual(result.instruction_words, 2)
            self.assertEqual((out_dir / "compiled_gpu_imem.txt").read_text(encoding="utf-8"), "10000001\nF0000000\n")
            self.assertIn("instruction_words=2", (out_dir / "gpu_program_report.txt").read_text(encoding="utf-8"))

    def test_package_bundle_normalizes_meta_and_params(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bundle_dir = tmp_path / "bundle"
            out_dir = tmp_path / "out"
            bundle_dir.mkdir()
            (bundle_dir / "program.gpus").write_text(".entry:\n  jump .done\n.done:\n  halt\n", encoding="utf-8")
            (bundle_dir / "params.txt").write_text("0x40 0x0000000000000001\n0x41 0x00000000 0x00000002\n", encoding="utf-8")
            (bundle_dir / "meta.json").write_text(
                '{\n  "entry_pc": 0,\n  "work_size": 2,\n  "base_a": 16,\n  "base_b": 64,\n  "base_c": 224,\n  "base_d": 248,\n  "tid_init": 0,\n  "m": 0,\n  "n": 0,\n  "k": 0\n}\n',
                encoding="utf-8",
            )

            result = package_bundle(str(bundle_dir), str(out_dir))

            self.assertEqual(result.instruction_words, 2)
            self.assertEqual(result.param_words, 2)
            self.assertTrue((out_dir / "compiled_gpu_params.txt").is_file())
            self.assertIn("0x00000040 0x00000000 0x00000001", (out_dir / "compiled_gpu_params.txt").read_text(encoding="utf-8"))
            self.assertIn('"base_c": 224', (out_dir / "meta.json").read_text(encoding="utf-8"))

    def test_load_bundle_invokes_annctl_for_program_and_params(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bundle_dir = tmp_path / "bundle"
            out_dir = tmp_path / "out"
            annctl_path = tmp_path / "annctl_mock.pl"
            log_path = tmp_path / "annctl.log"
            bundle_dir.mkdir()
            (bundle_dir / "program.gpus").write_text(".entry:\n  halt\n", encoding="utf-8")
            (bundle_dir / "params.txt").write_text("0x40 0x00000000 0x00000001\n", encoding="utf-8")
            write_fake_annctl(annctl_path)

            with mock.patch.dict(os.environ, {"ANNCTL_LOG": str(log_path)}):
                load_bundle(str(bundle_dir), annctl_path=str(annctl_path), out_dir=str(out_dir))

            log_lines = [line.strip() for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(len(log_lines), 2)
            self.assertTrue(log_lines[0].startswith(f"gpu imem-load {out_dir / 'compiled_gpu_imem.txt'}"))
            self.assertEqual(log_lines[1], f"gpu param-load {out_dir / 'compiled_gpu_params.txt'}")

    def test_template_mlp_generates_packageable_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            result = template_mlp(str(tmp_path), in_dim=3, out_dim=2, work_size=2)

            self.assertTrue(result.program_path.is_file())
            self.assertTrue(result.params_path.is_file())
            self.assertTrue(result.meta_path.is_file())
            self.assertIn("tensor_mac r6, r0, r1", result.program_path.read_text(encoding="utf-8"))
            self.assertIn("param_words=16", result.report_path.read_text(encoding="utf-8"))

            inspected = inspect_target(str(tmp_path))
            self.assertEqual(inspected.mode, "bundle")
            self.assertEqual(inspected.param_words, 16)

    def test_build_program_rejects_imem_overflow(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / "too_long.gpus"
            out_dir = tmp_path / "out"
            source_path.write_text("".join("  halt\n" for _ in range(65537)), encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "65536-word IMEM limit"):
                build_program(str(source_path), str(out_dir))


if __name__ == "__main__":
    unittest.main()
