from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parents[1]
SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from helpers import ROOT_DIR, write_fake_annctl
from model_toolchain.bundle import build_model, build_model_and_load


MODEL_PATH = ROOT_DIR / "sw" / "testdata" / "ann_model_mlp_int16.json"


class AnnModelBundleTests(unittest.TestCase):
    def test_build_model_emits_expected_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = build_model(str(MODEL_PATH), tmpdir)

            self.assertEqual(result.input_dim, 8)
            self.assertEqual(result.output_dim, 2)
            self.assertEqual(result.layer_count, 2)
            self.assertEqual(result.test_count, 2)

            self.assertTrue(result.manifest_path.exists())
            self.assertTrue(result.cpu_source_path.exists())
            self.assertTrue(result.cpu_image_path.exists())
            self.assertTrue(result.gpu_program_path.exists())
            self.assertTrue(result.gpu_imem_path.exists())
            self.assertTrue(result.gpu_params_path.exists())
            self.assertTrue(result.expected_output_path.exists())

            cpu_source = result.cpu_source_path.read_text(encoding="utf-8")
            self.assertIn("mov r10, #128", cpu_source)
            self.assertIn("str r6, [r10, #56]", cpu_source)

            gpu_source = result.gpu_program_path.read_text(encoding="utf-8")
            self.assertIn("load r0, A, 0", gpu_source)
            self.assertIn("store D, r6, 0", gpu_source)
            self.assertIn("store A, r6, 800", gpu_source)

            expected_rows = json.loads(result.expected_output_path.read_text(encoding="utf-8"))
            self.assertEqual(expected_rows[0]["predicted_class"], 0)
            self.assertEqual(expected_rows[1]["predicted_class"], 1)
            self.assertEqual(expected_rows[0]["wire_result_data_0_u16"], "0x0007")
            self.assertEqual(expected_rows[1]["wire_result_data_1_u16"], "0x0005")
            self.assertEqual(result.result_mode, "legacy_logits")

    def test_build_model_accepts_compact_multiclass_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            model_path = Path(tmpdir) / "compact.json"
            model = json.loads(MODEL_PATH.read_text(encoding="utf-8"))
            model["layers"][-1]["out_dim"] = 3
            model["layers"][-1]["weights"] = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
            model["layers"][-1]["bias"] = [0, 0, 0]
            model_path.write_text(json.dumps(model, indent=2), encoding="utf-8")

            result = build_model(str(model_path), str(Path(tmpdir) / "out"))
            expected_rows = json.loads(result.expected_output_path.read_text(encoding="utf-8"))

            self.assertEqual(result.output_dim, 3)
            self.assertEqual(result.result_mode, "compact_class_score")
            self.assertEqual(expected_rows[0]["result_mode"], "compact_class_score")

    def test_build_load_invokes_annctl_cpu_and_gpu_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "out"
            annctl_path = Path(tmpdir) / "fake_annctl.pl"
            log_path = Path(tmpdir) / "annctl.log"
            write_fake_annctl(annctl_path)
            annctl_path.chmod(0o755)
            os.environ["ANNCTL_LOG"] = str(log_path)
            try:
                result = build_model_and_load(str(MODEL_PATH), str(out_dir), annctl_path=str(annctl_path))
            finally:
                del os.environ["ANNCTL_LOG"]

            self.assertTrue(result.cpu_image_path.exists())
            self.assertTrue(result.gpu_imem_path.exists())
            log_lines = log_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(log_lines[0].split()[:2], ["cpu", "load"])
            self.assertEqual(log_lines[1].split()[:2], ["gpu", "imem-load"])
            self.assertEqual(log_lines[2].split()[:2], ["gpu", "param-load"])
            self.assertEqual(log_lines[3].split()[:2], ["engine", "result-clear"])


if __name__ == "__main__":
    unittest.main()
