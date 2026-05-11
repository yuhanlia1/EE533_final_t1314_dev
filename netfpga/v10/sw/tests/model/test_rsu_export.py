from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


TESTS_DIR = Path(__file__).resolve().parents[1]
SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent
DATASET_SCRIPTS_DIR = ROOT_DIR / "dataset" / "scripts"

if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))
if str(DATASET_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(DATASET_SCRIPTS_DIR))

from model_toolchain.bundle import build_model

try:
    import joblib
    import torch
    from sklearn.preprocessing import StandardScaler
except ModuleNotFoundError:
    joblib = None
    torch = None
    StandardScaler = None

if torch is not None and joblib is not None and StandardScaler is not None:
    from export_rsu_mlp_manifest import build_manifest_from_arrays
    from rsu_mlp_common import FEATURE_COLS, SmallMLP


@unittest.skipUnless(torch is not None and joblib is not None and StandardScaler is not None, "RSU export deps unavailable")
class RsuExportTests(unittest.TestCase):
    def _write_model_dir(self, root: Path) -> Path:
        model_dir = root / "model_dir"
        model_dir.mkdir(parents=True, exist_ok=True)

        model = SmallMLP(in_dim=len(FEATURE_COLS), num_classes=4, dropout=0.0)
        with torch.no_grad():
            for param in model.parameters():
                param.zero_()
            first = model.net[0]
            second = model.net[3]
            third = model.net[6]
            first.weight[0, 0] = 0.5
            first.weight[1, 1] = 0.75
            first.weight[2, 2] = -0.25
            first.weight[3, 3] = 0.40
            first.bias[0] = 0.1
            first.bias[1] = -0.05
            second.weight[0, 0] = 0.8
            second.weight[1, 1] = 0.7
            second.weight[2, 3] = 0.6
            second.weight[3, 2] = -0.4
            second.bias[0] = 0.05
            third.weight[0, 0] = 1.0
            third.weight[1, 1] = 1.0
            third.weight[2, 2] = 1.0
            third.weight[3, 3] = 1.0

        torch.save(model.state_dict(), model_dir / "best_model.pt")

        calibration = np.zeros((4, len(FEATURE_COLS)), dtype=np.float32)
        calibration[:, 0] = [1.0, 2.0, 0.5, 1.5]
        calibration[:, 1] = [0.5, 1.0, 1.5, 0.0]
        calibration[:, 2] = [0.0, 0.5, 1.0, 0.5]
        calibration[:, 3] = [2.0, 1.5, 0.5, 1.0]
        scaler = StandardScaler().fit(calibration)
        joblib.dump(scaler, model_dir / "scaler.pkl")
        (model_dir / "feature_columns.json").write_text(
            json.dumps(FEATURE_COLS, indent=2) + "\n",
            encoding="utf-8",
        )
        (model_dir / "label_mapping.json").write_text(
            json.dumps({"Free-flow": 0, "Slow": 1, "Congested": 2, "Incident-risk": 3}, indent=2) + "\n",
            encoding="utf-8",
        )
        return model_dir

    def test_exported_manifest_builds_with_toolchain(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            model_dir = self._write_model_dir(tmp_path)
            calibration = np.zeros((4, len(FEATURE_COLS)), dtype=np.float32)
            calibration[:, 0] = [1.0, 2.0, 0.5, 1.5]
            calibration[:, 1] = [0.5, 1.0, 1.5, 0.0]
            calibration[:, 2] = [0.0, 0.5, 1.0, 0.5]
            calibration[:, 3] = [2.0, 1.5, 0.5, 1.0]
            label_ids = np.array([0, 1, 2, 3], dtype=np.int64)

            manifest, report = build_manifest_from_arrays(
                model_dir=model_dir,
                calibration_features=calibration,
                calibration_label_ids=label_ids,
                test_features=calibration,
                test_names=["row0", "row1", "row2", "row3"],
                num_tests=4,
            )

            manifest_path = tmp_path / "rsu_manifest.json"
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            result = build_model(str(manifest_path), str(tmp_path / "build"))
            expected_rows = json.loads(result.expected_output_path.read_text(encoding="utf-8"))

            self.assertEqual(result.input_dim, len(FEATURE_COLS))
            self.assertEqual(result.output_dim, 4)
            self.assertEqual(result.result_mode, "compact_class_score")
            self.assertEqual(len(manifest["tests"]), 4)
            self.assertEqual(len(expected_rows), 4)
            self.assertIn("float_vs_quantized_test_class_agreement", report)
            self.assertIn("float_vs_quantized_full_dataset_class_agreement", report)
            self.assertIn("layer_diagnostics", report)
            self.assertIn("quantized_prefix_ablation", report)
            self.assertIn("selected_scale_factors", report)
            self.assertIn("per_channel_activation_scales", report)
            self.assertIn("quantized_logit_margin_stats", report)
            self.assertIn("per_class_logit_stats", report)
            self.assertEqual(manifest["export_meta"]["input_contract"], "software_standardized_features_quantized_to_int16")
            self.assertEqual(report["input_contract"], "software_standardized_features_quantized_to_int16")
            self.assertEqual(len(report["full_dataset_rows"]), 4)
            self.assertEqual(len(report["layer_diagnostics"]), 3)
            self.assertEqual(len(report["quantized_prefix_ablation"]), 4)
            self.assertEqual(len(report["per_class_logit_stats"]), 4)


if __name__ == "__main__":
    unittest.main()
