from __future__ import annotations

import json
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

from board_debug.ann_packets import build_result_frame, parse_result_frame
from board_debug.model_batch_eval import compare_expected_observed
from mnist_toolchain.feature_extract import extract_features
from model_toolchain.bundle import build_model


FIXTURE_PATH = SW_DIR / "testdata" / "mnist_binary_01" / "fixture_model.json"


class MnistBinaryFlowTests(unittest.TestCase):
    def test_feature_extractor_quantizes_expected_regions(self) -> None:
        black = [[0 for _ in range(28)] for _ in range(28)]
        white = [[255 for _ in range(28)] for _ in range(28)]
        top_half = [[255 if row < 14 else 0 for _ in range(28)] for row in range(28)]

        self.assertEqual(extract_features(black), [0] * 8)
        self.assertEqual(extract_features(white), [31] * 8)
        self.assertEqual(extract_features(top_half)[0], 16)
        self.assertEqual(extract_features(top_half)[1], 31)
        self.assertEqual(extract_features(top_half)[2], 0)

    def test_result_packet_roundtrip_preserves_binary_logits(self) -> None:
        frame = build_result_frame(request_id=0x1234, result_data_0=7, result_data_1=-5)
        parsed = parse_result_frame(frame)

        self.assertEqual(parsed.request_id, 0x1234)
        self.assertEqual(parsed.result_data_0_s16, 7)
        self.assertEqual(parsed.result_data_1_s16, -5)
        self.assertEqual(parsed.predicted_class, 0)

    def test_fixture_bundle_builds_and_compares_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = build_model(str(FIXTURE_PATH), tmpdir)
            expected_rows = json.loads(result.expected_output_path.read_text(encoding="utf-8"))
            observed_rows = [
                {
                    "name": row["name"],
                    "predicted_class": row["predicted_class"],
                    "wire_result_data_0_u16": row["wire_result_data_0_u16"],
                    "wire_result_data_1_u16": row["wire_result_data_1_u16"],
                    "request_id": index,
                }
                for index, row in enumerate(expected_rows)
            ]

            summary = compare_expected_observed(expected_rows, observed_rows)
            self.assertEqual(result.input_dim, 8)
            self.assertEqual(result.output_dim, 2)
            self.assertEqual(summary["class_accuracy"], 1.0)
            self.assertEqual(summary["wire_accuracy"], 1.0)
            self.assertEqual(summary["mismatches"], [])


if __name__ == "__main__":
    unittest.main()
