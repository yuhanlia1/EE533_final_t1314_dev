from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_ZERO_COPY_SPEC = importlib.util.spec_from_file_location(
    "zero_copy_demo_module",
    ROOT_DIR / "scripts" / "board" / "zero_copy_demo.py",
)
zero_copy_demo = importlib.util.module_from_spec(_ZERO_COPY_SPEC)
assert _ZERO_COPY_SPEC.loader is not None
_ZERO_COPY_SPEC.loader.exec_module(zero_copy_demo)

from board_debug.ann_packets import build_result_frame, build_task_frame_defaults
from board_debug.pcap_io import write_pcap


class ZeroCopyDemoTests(unittest.TestCase):
    def test_threshold_window_analysis_finds_transition(self) -> None:
        analysis = zero_copy_demo._threshold_window_analysis(
            [
                {"window_ms": 1600, "window_verdict": "pass"},
                {"window_ms": 800, "window_verdict": "pass"},
                {"window_ms": 400, "window_verdict": "unstable"},
                {"window_ms": 200, "window_verdict": "pass"},
                {"window_ms": 100, "window_verdict": "fail"},
                {"window_ms": 10, "window_verdict": "fail"},
            ]
        )

        self.assertEqual(analysis["zero_copy_verdict"], "pass")
        self.assertEqual(analysis["smallest_passing_window_ms"], 200)
        self.assertEqual(analysis["largest_failing_window_ms"], 100)
        self.assertTrue(analysis["threshold_transition_found"])

    def test_build_limit_summary_keeps_single_window_shape(self) -> None:
        summary = zero_copy_demo._build_limit_summary(
            Path("/tmp/out"),
            Path("/tmp/out/logs/zero_copy_limit.log"),
            50,
            {
                "window_verdict": "pass",
                "status": "passed",
                "measurement_resolution_ms": 5,
                "request_id": "0x1100",
                "predicted_class": 1,
                "predicted_label": "Slow",
                "predicted_score_s16": 331,
                "receiver_completed_within_window": True,
                "receiver_window_wait_us": 42000.0,
                "sender_capture_exists": True,
                "receiver_capture_exists": True,
                "inference_check": "MATCHED EXPECTED OFFLOAD RESULT",
                "window_note": "Observed matching ann_result within the configured window.",
                "sent_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_task"},
                "sent_packet_hex": "001122",
                "observed_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_result"},
                "observed_packet_hex": "aabbcc",
            },
        )

        self.assertEqual(summary["window_ms"], 50)
        self.assertEqual(summary["zero_copy_verdict"], "pass")
        self.assertEqual(summary["predicted_label"], "Slow")
        self.assertEqual(summary["measurement_resolution_ms"], 5)
        self.assertNotIn("window_results", summary)

    def test_build_window_measurement_marks_sub_resolution_window_unstable(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            capture_dir = run_dir / "captures"
            capture_dir.mkdir(parents=True, exist_ok=True)

            sender_frame, _sender_meta = build_task_frame_defaults(request_id=0x1100)
            receiver_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(capture_dir / "offload_sender_001.cap", [sender_frame])
            write_pcap(capture_dir / "offload_receiver_001.cap", [receiver_frame])

            measurement = zero_copy_demo._build_window_measurement(
                run_dir,
                {
                    "model": {"result_mode": "compact_class_score"},
                    "zero_copy_demo": {
                        "measurement_resolution_ms": 5,
                        "window_poll_interval_seconds": 0.005,
                    },
                },
                ["Free-flow", "Slow", "Congested", "Incident-risk"],
                {
                    "status": "passed",
                    "sender_capture_path": "captures/offload_sender_001.cap",
                    "receiver_capture_path": "captures/offload_receiver_001.cap",
                    "sender_capture_exists": True,
                    "receiver_capture_exists": True,
                    "sender_completed_within_window": True,
                    "receiver_completed_within_window": True,
                    "receiver_window_wait_us": 900.0,
                },
                1,
            )

        self.assertEqual(measurement["window_verdict"], "unstable")
        self.assertEqual(measurement["status"], "unstable")
        self.assertEqual(measurement["measurement_resolution_ms"], 5)
        self.assertEqual(measurement["inference_check"], "WINDOW BELOW MEASUREMENT RESOLUTION")
        self.assertEqual(measurement["predicted_label"], "Slow")
        self.assertEqual(measurement["window_note"], "This window is not treated as a demo-grade pass result.")

    def test_build_path_summary_passes_with_sender_board_receiver_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            capture_dir = run_dir / "captures"
            capture_dir.mkdir(parents=True, exist_ok=True)

            sender_frame, _sender_meta = build_task_frame_defaults(request_id=0x1100)
            receiver_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(capture_dir / "offload_sender_1001.cap", [sender_frame])
            write_pcap(capture_dir / "offload_receiver_1001.cap", [receiver_frame])

            debug_path = run_dir / "zero_copy_path_debug_status.txt"
            debug_path.write_text(
                "\n".join(
                    [
                        "offload_accept_count=1",
                        "compute_start_count=1",
                        "compute_done_count=1",
                        "result_emit_count=1",
                        "last_parse_request_id=0x1100",
                        "last_compute_request_id=0x1100",
                        "last_emit_request_id=0x1100",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            summary = zero_copy_demo._build_path_summary(
                run_dir,
                {
                    "model": {
                        "result_mode": "compact_class_score",
                    },
                },
                ["Free-flow", "Slow", "Congested", "Incident-risk"],
                run_dir / "logs" / "zero_copy_path.log",
                {
                    "status": "passed",
                    "sender_capture_path": "captures/offload_sender_1001.cap",
                    "receiver_capture_path": "captures/offload_receiver_1001.cap",
                },
                debug_path,
                zero_copy_demo.board_sweep._parse_debug_status_text(debug_path.read_text(encoding="utf-8")),
            )

        self.assertEqual(summary["zero_copy_verdict"], "pass")
        self.assertTrue(summary["request_id_consistent"])
        self.assertEqual(summary["predicted_label"], "Slow")
        self.assertEqual(summary["postrun_debug_status"]["result_emit_count"], 1)
        self.assertEqual(summary["postrun_debug_status"]["last_emit_request_id"], "0x1100")

    def test_update_zero_copy_summary_tracks_new_steps(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            manifest = {
                "run_name": "zero_copy_demo_run",
                "zero_copy_demo": {
                    "config_path": "/tmp/zero_copy.json",
                    "steps": ["threshold", "limit", "path"],
                },
            }

            summary = zero_copy_demo._update_zero_copy_summary(
                run_dir,
                manifest,
                "threshold",
                "Threshold Sweep",
                "passed",
                "pass",
            )

        self.assertEqual(summary["steps_completed"], ["threshold"])
        self.assertEqual(summary["steps_passed"], 1)
        self.assertEqual(summary["steps_failed"], 0)
        self.assertEqual(summary["overall_verdict"], "incomplete")

    def test_print_path_block_has_blank_lines_between_sections(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            zero_copy_demo._print_path_block(
                {
                    "zero_copy_verdict": "pass",
                    "zero_copy_statement": "Host handled replay/capture only.",
                    "sender_packet_summary": {
                        "request_id": "0x1100",
                        "frame_kind": "ann_task",
                    },
                    "sender_packet_hex": "001122",
                    "postrun_debug_status": {
                        "offload_accept_count": 1,
                        "last_emit_request_id": "0x1100",
                    },
                    "receiver_packet_summary": {
                        "request_id": "0x1100",
                        "frame_kind": "ann_result",
                        "predicted_class": 1,
                    },
                    "receiver_packet_hex": "aabbcc",
                    "request_id_consistent": True,
                    "predicted_label": "Slow",
                    "artifacts": {
                        "step_summary_md": "zero_copy_path_summary.md",
                    },
                }
            )
        rendered = buffer.getvalue()
        self.assertIn("  Host Edge:\n\n    Sent Packet:\n", rendered)
        self.assertIn("  Board Internal:\n\n    offload_accept_count", rendered)
        self.assertIn("  Result Edge:\n\n    Observed Result:\n", rendered)

    def test_print_limit_block_shows_unstable_resolution_floor(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            zero_copy_demo._print_limit_block(
                {
                    "window_ms": 1,
                    "zero_copy_verdict": "unstable",
                    "inference_check": "WINDOW BELOW MEASUREMENT RESOLUTION",
                    "window_note": "This window is not treated as a demo-grade pass result.",
                    "measurement_resolution_ms": 5,
                    "predicted_label": "Slow",
                    "sent_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_task"},
                    "sent_packet_hex": "001122",
                    "observed_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_result"},
                    "observed_packet_hex": "aabbcc",
                    "artifacts": {"step_summary_md": "zero_copy_limit_summary.md"},
                }
            )
        rendered = buffer.getvalue()
        self.assertIn("Result             : UNSTABLE", rendered)
        self.assertIn("Resolution Floor   : 5 ms", rendered)
        self.assertIn("Observed Result (Debug):", rendered)


if __name__ == "__main__":
    unittest.main()
