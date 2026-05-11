from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_OTHER_PROS_RATE_SPEC = importlib.util.spec_from_file_location(
    "other_pros_rate_demo_module",
    ROOT_DIR / "scripts" / "board" / "other_pros_rate_demo.py",
)
other_pros_rate_demo = importlib.util.module_from_spec(_OTHER_PROS_RATE_SPEC)
assert _OTHER_PROS_RATE_SPEC.loader is not None
_OTHER_PROS_RATE_SPEC.loader.exec_module(other_pros_rate_demo)


class OtherProsRateDemoTests(unittest.TestCase):
    def test_parse_rates_arg_normalizes_and_sorts(self) -> None:
        self.assertEqual(
            other_pros_rate_demo._parse_rates_arg("2400,50,2000,50,10"),
            [10, 50, 2000, 2400],
        )

    def test_rate_experiment_uses_rate_and_duration_to_compute_expected_count(self) -> None:
        experiment = other_pros_rate_demo._rate_experiment(
            400,
            {
                "request_id_base_start": "0x3000",
                "send_duration_seconds": 2.0,
                "drain_timeout_seconds": 1.0,
                "rate_accuracy_tolerance_ratio": 0.2,
                "rate_chunk_target_seconds": 0.25,
            },
            2,
        )

        self.assertEqual(experiment["expected_count"], 800)
        self.assertEqual(experiment["prepare_limit"], 800)
        self.assertEqual(experiment["request_id_base"], "0x3200")

    def test_analyze_rate_results_finds_zero_loss_and_first_overload(self) -> None:
        analysis = other_pros_rate_demo._analyze_rate_results(
            [
                {"offered_rate_req_per_sec": 10.0, "measurement_valid": True, "drop_count": 0, "mismatch_count": 0},
                {"offered_rate_req_per_sec": 2000.0, "measurement_valid": True, "drop_count": 0, "mismatch_count": 0},
                {"offered_rate_req_per_sec": 2400.0, "measurement_valid": False, "drop_count": 3, "mismatch_count": 3},
            ]
        )

        self.assertEqual(analysis["max_zero_loss_pps"], 2000.0)
        self.assertEqual(analysis["first_overload_pps"], 2400.0)
        self.assertTrue(analysis["threshold_complete"])
        self.assertEqual(analysis["overall_verdict"], "pass")

    def test_render_summary_markdown_contains_key_threshold_fields(self) -> None:
        rendered = other_pros_rate_demo._render_summary_markdown(
            {
                "run_dir": "/tmp/demo",
                "config_path": "/tmp/config.json",
                "init_run_dir": "other_pros_rate_init_board",
                "rate_points_req_per_sec": [10, 50, 2400],
                "send_duration_seconds": 2.0,
                "drain_timeout_seconds": 1.0,
                "max_zero_loss_pps": 2000.0,
                "first_overload_pps": 2400.0,
                "threshold_complete": True,
                "overall_verdict": "pass",
                "recommended_figure": "/tmp/rate_scan_energy_validity.png",
                "rate_results": [
                    {
                        "offered_rate_req_per_sec": 2400.0,
                        "zero_loss_pass": False,
                        "measurement_valid": False,
                        "drop_count": 3,
                        "mismatch_count": 3,
                        "goodput_result_per_sec": 555.0,
                        "rate_generation_mode_used": "chunked_replay_fallback",
                    }
                ],
            }
        )

        self.assertIn("max_zero_loss_pps", rendered)
        self.assertIn("first_overload_pps", rendered)
        self.assertIn("| 2400.0 | FAIL | no | 3 | 3 | 555.000 | chunked_replay_fallback |", rendered)

    def test_print_scan_footer_has_clean_summary_lines(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            other_pros_rate_demo._print_scan_footer(
                {
                    "run_dir": "/tmp/demo",
                    "max_zero_loss_pps": 2000.0,
                    "first_overload_pps": 2400.0,
                    "threshold_complete": True,
                    "recommended_figure": "/tmp/rate_scan_energy_validity.png",
                    "overall_verdict": "pass",
                }
            )
        rendered = buffer.getvalue()
        self.assertIn("Max Zero-Loss Rate", rendered)
        self.assertIn("First Overload Rate", rendered)
        self.assertIn("Recommended Figure", rendered)
        self.assertIn("Result", rendered)

    def test_load_and_write_summary_state_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            state = {
                "config_path": "/tmp/config.json",
                "init_run_dir": "other_pros_rate_init_board",
                "default_rate_points_req_per_sec": [10, 25, 50],
                "default_send_duration_seconds": 2.0,
                "default_drain_timeout_seconds": 1.0,
                "default_rate_accuracy_tolerance_ratio": 0.2,
                "default_rate_chunk_target_seconds": 0.25,
            }
            summary = other_pros_rate_demo._base_summary(run_dir, state)
            other_pros_rate_demo._write_summary(run_dir, summary)
            loaded = other_pros_rate_demo._load_json(run_dir / other_pros_rate_demo.RATE_SUMMARY_JSON)

        self.assertEqual(loaded["rate_points_req_per_sec"], [10, 25, 50])
        self.assertEqual(loaded["overall_verdict"], "pending")


if __name__ == "__main__":
    unittest.main()
