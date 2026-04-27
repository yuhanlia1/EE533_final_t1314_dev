from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_BOARD_METRICS_SPEC = importlib.util.spec_from_file_location(
    "board_metrics_module",
    ROOT_DIR / "scripts" / "board" / "board_metrics.py",
)
board_metrics = importlib.util.module_from_spec(_BOARD_METRICS_SPEC)
assert _BOARD_METRICS_SPEC.loader is not None
_BOARD_METRICS_SPEC.loader.exec_module(board_metrics)

from board_debug.pcap_io import read_pcap_records, write_pcap


class BoardMetricsTests(unittest.TestCase):
    def _runner_defaults(self):
        return board_metrics.board_sweep._normalize_defaults({}, ROOT_DIR)

    def test_read_pcap_records_preserves_timestamp_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "demo.cap"
            write_pcap(path, [b"\x00" * 60, b"\x01" * 60, b"\x02" * 60])

            records = read_pcap_records(path)

            self.assertEqual(len(records), 3)
            self.assertEqual(records[0]["frame"], b"\x00" * 60)
            self.assertLess(records[0]["timestamp_seconds"], records[1]["timestamp_seconds"])
            self.assertLess(records[1]["timestamp_seconds"], records[2]["timestamp_seconds"])

    def test_write_pcap_preserves_explicit_timestamps(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "timed.cap"
            write_pcap(
                path,
                [
                    {"frame": b"\x00" * 60, "timestamp_seconds": 10.0},
                    {"frame": b"\x01" * 60, "timestamp_seconds": 10.25},
                ],
            )

            records = read_pcap_records(path)

            self.assertEqual(len(records), 2)
            self.assertAlmostEqual(records[0]["timestamp_seconds"], 10.0, places=6)
            self.assertAlmostEqual(records[1]["timestamp_seconds"], 10.25, places=6)

    def test_normalize_metric_experiments_supports_latency_and_batch_and_rate(self) -> None:
        defaults, experiments = board_metrics._normalize_metric_experiments(
            {
                "experiments": [
                    {"name": "lat", "mode": "latency_single", "sample_count": 4},
                    {"name": "batch", "mode": "batch_completion", "batch_size": 6, "repeats": 2},
                    {
                        "name": "rate",
                        "mode": "rate_scan",
                        "rate_points_req_per_sec": [10, 25],
                        "send_duration_seconds": 2.0,
                        "repeats": 1,
                    },
                ]
            },
            ROOT_DIR,
        )

        self.assertEqual(defaults["pre_capture_delay_seconds"], board_metrics.board_sweep.DEFAULT_PRE_CAPTURE_DELAY_SECONDS)
        self.assertEqual(experiments[0]["mode"], "latency_single")
        self.assertEqual(experiments[0]["prepare_limit"], 1)
        self.assertEqual(experiments[0]["sample_count"], 4)
        self.assertEqual(experiments[1]["run_name"], "batch_r01")
        self.assertEqual(experiments[2]["run_name"], "batch_r02")
        self.assertEqual(experiments[3]["mode"], "rate_scan")
        self.assertEqual(experiments[3]["expected_count"], 20)
        self.assertEqual(experiments[3]["rate_generation_mode"], board_metrics.RATE_GENERATION_MODE_AUTO)
        self.assertEqual(experiments[4]["expected_count"], 50)

    def test_latency_summary_reports_expected_percentiles(self) -> None:
        summary = board_metrics._latency_summary([10.0, 20.0, 30.0, 40.0, 50.0])

        self.assertEqual(summary["latency_p50_us"], 30.0)
        self.assertEqual(summary["latency_p95_us"], 48.0)
        self.assertEqual(summary["latency_p99_us"], 49.6)
        self.assertEqual(summary["latency_max_us"], 50.0)

    def test_render_markdown_summary_marks_cross_host_latency_as_unsupported(self) -> None:
        markdown = board_metrics._render_markdown_summary(
            "/tmp/out",
            "/tmp/config.json",
            [
                {
                    "run_name": "latency_single_demo_r01",
                    "mode": "latency_single",
                    "status": "passed",
                    "latency_status": board_metrics.LATENCY_STATUS_UNSUPPORTED,
                    "sender_capture_count": 1,
                    "receiver_capture_count": 1,
                }
            ],
        )

        self.assertIn("unsupported", markdown)
        self.assertNotIn("255438", markdown)

    def test_prepare_rate_replay_pcaps_builds_paced_and_chunk_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            batch_pcap = run_dir / "pcaps" / "offload_batch.pcap"
            batch_pcap.parent.mkdir(parents=True, exist_ok=True)
            write_pcap(batch_pcap, [b"\x00" * 60, b"\x01" * 60, b"\x02" * 60])

            runner = board_metrics.MetricsRunner(
                output_dir=run_dir,
                config_path=run_dir / "config.json",
                defaults=self._runner_defaults(),
            )
            replay_paths = runner._prepare_rate_replay_pcaps(
                run_dir,
                {"artifacts": {"offload_batch_pcap": "pcaps/offload_batch.pcap"}},
                10.0,
                0.2,
            )

            self.assertEqual(replay_paths["rate_paced_pcap"], "pcaps/offload_rate_paced.pcap")
            paced_records = read_pcap_records(run_dir / replay_paths["rate_paced_pcap"])
            self.assertEqual(len(paced_records), 3)
            self.assertAlmostEqual(paced_records[1]["timestamp_seconds"] - paced_records[0]["timestamp_seconds"], 0.1, places=6)
            self.assertEqual(len(replay_paths["rate_chunk_plan"]), 2)
            self.assertEqual(replay_paths["rate_chunk_plan"][0]["packet_count"], 2)
            self.assertEqual(replay_paths["rate_chunk_plan"][1]["packet_count"], 1)

    def test_rate_paced_replay_script_uses_whitelisted_tcpreplay_shape(self) -> None:
        runner = board_metrics.MetricsRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        script = runner._rate_paced_replay_script(
            {
                "usc": {
                    "remote_sender_root": "~/v8/demo_sender",
                    "sender_iface": "port0",
                },
                "metrics": {
                    "rate_paced_pcap": "pcaps/offload_rate_paced.pcap",
                },
            },
        )

        self.assertNotIn("--pps", script)
        self.assertIn('sudo /usr/bin/tcpreplay -i port0', script)
        self.assertIn("offload_rate_paced.pcap", script)

    def test_rate_chunked_replay_script_uses_chunk_sleeps(self) -> None:
        runner = board_metrics.MetricsRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        script = runner._rate_chunked_replay_script(
            {
                "usc": {
                    "remote_sender_root": "~/v8/demo_sender",
                    "sender_iface": "port0",
                },
                "metrics": {
                    "rate_chunk_plan": [
                        {"pcap": "pcaps/rate_chunks/offload_rate_chunk_0000.pcap", "sleep_after_seconds": 0.2},
                        {"pcap": "pcaps/rate_chunks/offload_rate_chunk_0001.pcap", "sleep_after_seconds": 0.0},
                    ]
                },
            }
        )

        self.assertNotIn("--pps", script)
        self.assertIn("offload_rate_chunk_0000.pcap", script)
        self.assertIn("offload_rate_chunk_0001.pcap", script)
        self.assertIn("sleep 0.200000", script)

    def test_select_rate_attempt_prefers_valid_fallback(self) -> None:
        runner = board_metrics.MetricsRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        chosen = runner._select_rate_attempt(
            {"rate_generation_mode": board_metrics.RATE_GENERATION_MODE_PACED, "measurement_valid": False},
            {"rate_generation_mode": board_metrics.RATE_GENERATION_MODE_CHUNKED, "measurement_valid": True},
        )

        self.assertEqual(chosen["rate_generation_mode"], board_metrics.RATE_GENERATION_MODE_CHUNKED)


if __name__ == "__main__":
    unittest.main()
