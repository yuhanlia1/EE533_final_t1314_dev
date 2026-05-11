from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_DEMO_VERIFY_SPEC = importlib.util.spec_from_file_location(
    "demo_verify_module",
    ROOT_DIR / "scripts" / "board" / "demo_verify.py",
)
demo_verify = importlib.util.module_from_spec(_DEMO_VERIFY_SPEC)
assert _DEMO_VERIFY_SPEC.loader is not None
_DEMO_VERIFY_SPEC.loader.exec_module(demo_verify)

from board_debug.ann_packets import build_result_frame, build_task_frame_defaults
from board_debug.pcap_io import write_pcap


class DemoVerifyTests(unittest.TestCase):
    def test_print_hex_block_wraps_long_hex(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            demo_verify._print_hex_block("a" * 80, indent=4, chunk=16)
        rendered = buffer.getvalue().splitlines()
        self.assertEqual(rendered[0], "    " + ("a" * 16))
        self.assertEqual(rendered[-1], "    " + ("a" * 16))
        self.assertEqual(len(rendered), 5)

    def test_latency_result_separates_toolchain_and_inference(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            sender = out_dir / "sender.cap"
            receiver = out_dir / "receiver.cap"
            sent_frame, _meta = build_task_frame_defaults(request_id=0x1100)
            recv_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(sender, [sent_frame])
            write_pcap(receiver, [recv_frame])

            result = {
                "mode": "latency_single",
                "run_name": "demo_single_offload_r01",
                "single_packet_variant": "offload",
                "sample_results": [
                    {
                        "phase": "measure",
                        "status": "passed",
                        "timed_out": False,
                        "sender_capture_exists": True,
                        "receiver_capture_exists": True,
                        "sender_capture_path": "sender.cap",
                        "receiver_capture_path": "receiver.cap",
                        }
                    ],
                }

            view = demo_verify._demo_result_view(result, out_dir, labels=["Free-flow", "Slow"])

            self.assertEqual(view["toolchain_verdict"], "pass")
            self.assertEqual(view["inference_verdict"], "pass")
            self.assertIn("1/1 offload sample", view["evidence"])
            self.assertEqual(view["sent_packet_summary"]["request_id"], "0x1100")
            self.assertEqual(view["received_packet_summary"]["wire_result_data_1_u16"], "0x014b")
            self.assertEqual(view["predicted_label"], "Slow")
            self.assertEqual(view["inference_check"], "MATCHED EXPECTED OFFLOAD RESULT")

    def test_batch_result_can_pass_toolchain_and_fail_inference(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            (run_dir / "pcaps").mkdir(parents=True, exist_ok=True)
            sent_frame, sent_meta = build_task_frame_defaults(request_id=0x3100)
            (run_dir / "pcaps" / "offload_meta.json").write_text(
                json.dumps({"batch_frames": [{"request_id": "0x3100", "wire_frame_hex": sent_meta["wire_frame_hex"]}]}),
                encoding="utf-8",
            )
            observed = [
                {
                    "request_id": 0x3100,
                    "frame_kind": "ann_result",
                    "wire_result_data_0_u16": "0x0001",
                    "wire_result_data_1_u16": "0x014b",
                    "wire_frame_hex": build_result_frame(request_id=0x3100, result_data_0=1, result_data_1=331).hex(),
                }
            ]
            (run_dir / "observed_results.json").write_text(json.dumps(observed), encoding="utf-8")

            result = {
                "mode": "batch_completion",
                "run_name": "demo_batch8_r01",
                "run_dir": str(run_dir),
                "batch_size": 8,
                "sender_capture_local_exists": True,
                "receiver_capture_local_exists": True,
                "report_exit_code": 1,
                "correctness_verdict": "mismatch",
                "mismatch_count": 2,
                "missing_sample_count": 0,
                "receiver_capture_count": 6,
            }

            view = demo_verify._demo_result_view(result, run_dir)

            self.assertEqual(view["toolchain_verdict"], "pass")
            self.assertEqual(view["inference_verdict"], "fail")
            self.assertEqual(view["failure_stage"], "inference")
            self.assertEqual(view["sent_packet_summary"]["request_id"], "0x3100")
            self.assertEqual(view["received_packet_summary"]["request_id"], "0x3100")
            self.assertEqual(view["inference_check"], "MISMATCH (mismatch_count=2)")

    def test_build_demo_summary_aggregates_overall_verdicts(self) -> None:
        detailed_summary = {
            "runs_total": 2,
            "runs_passed": 2,
            "runs_failed": 0,
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            sender = out_dir / "sender.cap"
            receiver = out_dir / "receiver.cap"
            sent_frame, sent_meta = build_task_frame_defaults(request_id=0x1100)
            recv_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(sender, [sent_frame])
            write_pcap(receiver, [recv_frame])
            batch_run = out_dir / "batch8"
            (batch_run / "pcaps").mkdir(parents=True, exist_ok=True)
            (batch_run / "pcaps" / "offload_meta.json").write_text(
                json.dumps({"batch_frames": [{"request_id": "0x3100", "wire_frame_hex": sent_meta["wire_frame_hex"]}]}),
                encoding="utf-8",
            )
            observed = [
                {
                    "request_id": 0x3100,
                    "frame_kind": "ann_result",
                    "wire_result_data_0_u16": "0x0001",
                    "wire_result_data_1_u16": "0x014b",
                    "wire_frame_hex": build_result_frame(request_id=0x3100, result_data_0=1, result_data_1=331).hex(),
                }
            ]
            (batch_run / "observed_results.json").write_text(json.dumps(observed), encoding="utf-8")

            results = [
                {
                    "mode": "latency_single",
                    "run_name": "demo_single_offload_r01",
                    "single_packet_variant": "offload",
                    "sample_results": [
                        {
                            "phase": "measure",
                            "status": "passed",
                            "timed_out": False,
                            "sender_capture_exists": True,
                            "receiver_capture_exists": True,
                            "sender_capture_path": "sender.cap",
                            "receiver_capture_path": "receiver.cap",
                        }
                    ],
                },
                {
                    "mode": "batch_completion",
                    "run_name": "demo_batch8_r01",
                    "run_dir": str(batch_run),
                    "batch_size": 8,
                    "sender_capture_local_exists": True,
                    "receiver_capture_local_exists": True,
                    "report_exit_code": 0,
                    "correctness_verdict": "healthy",
                    "mismatch_count": 0,
                    "missing_sample_count": 0,
                    "receiver_capture_count": 8,
                },
            ]

            summary = demo_verify._build_demo_summary(
                ROOT_DIR / "scripts" / "board" / "rsu_demo_verify.json",
                out_dir,
                detailed_summary,
                results,
            )

        self.assertEqual(summary["toolchain_verdict"], "pass")
        self.assertEqual(summary["inference_verdict"], "pass")
        self.assertEqual(summary["overall_verdict"], "pass")
        self.assertEqual(len(summary["proof_runs"]), 2)
        self.assertIn("sent_packet_summary", summary["proof_runs"][0])
        self.assertIn("received_packet_hex", summary["proof_runs"][1])

    def test_print_result_block_separates_packet_metadata_and_hex(self) -> None:
        view = {
            "toolchain_verdict": "pass",
            "inference_verdict": "pass",
            "overall_verdict": "pass",
            "evidence": "1/1 offload sample matched expected result",
            "sent_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "ann_task",
                "payload_magic": "0xa11e",
                "udp_dst_port": "0x88b5",
            },
            "sent_packet_hex": "a" * 80,
            "received_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "ann_result",
                "udp_dst_port": "0x88b5",
                "wire_result_data_0_u16": "0x0001",
                "wire_result_data_1_u16": "0x014b",
            },
            "received_packet_hex": "b" * 80,
            "inference_check": "MATCHED EXPECTED OFFLOAD RESULT",
            "failure_stage": None,
            "runner_log": None,
            "summary_md": None,
            "report_json": None,
        }
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            demo_verify._print_result_block(view, verbose=False)
        rendered = buffer.getvalue()
        self.assertIn("Sent Packet:", rendered)
        self.assertIn("Received Packet:", rendered)
        self.assertIn("request_id", rendered)
        self.assertIn("hex:", rendered)
        self.assertNotIn("hex=aaaaaaaa", rendered)
        self.assertNotIn("request_id=0x1100 frame_kind=ann_task", rendered)

    def test_render_demo_markdown_contains_demo_verdicts(self) -> None:
        markdown = demo_verify._render_demo_markdown(
            {
                "overall_verdict": "pass",
                "toolchain_verdict": "pass",
                "inference_verdict": "pass",
                "config_path": "/tmp/config.json",
                "output_dir": "/tmp/out",
                "proof_runs": [
                    {
                        "label": "Single-Packet Offload",
                        "toolchain_verdict": "pass",
                        "inference_verdict": "pass",
                        "overall_verdict": "pass",
                        "evidence": "1/1 offload sample matched expected result",
                        "predicted_label": "Slow",
                        "inference_check": "MATCHED EXPECTED OFFLOAD RESULT",
                        "sent_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_task"},
                        "received_packet_summary": {
                            "request_id": "0x1100",
                            "frame_kind": "ann_result",
                            "wire_result_data_0_u16": "0x0001",
                            "wire_result_data_1_u16": "0x014b",
                        },
                        "sent_packet_hex": "001122",
                        "received_packet_hex": "aabbcc",
                    }
                ],
                "artifacts": {
                    "demo_summary_json": "demo_summary.json",
                    "demo_summary_md": "demo_summary.md",
                    "detailed_summary_json": "summary.json",
                    "detailed_summary_md": "summary.md",
                },
            }
        )

        self.assertIn("overall_verdict: `PASS`", markdown)
        self.assertIn("| Single-Packet Offload | PASS | PASS | PASS |", markdown)
        self.assertIn("predicted_label: `Slow`", markdown)
        self.assertIn("sent_packet", markdown)
        self.assertIn("received_wire_hex=aabbcc", markdown)

    def test_print_engine_result_block_shows_predicted_label(self) -> None:
        view = {
            "label": "Single-Packet Offload",
            "overall_verdict": "pass",
            "received_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "ann_result",
                "predicted_class": 1,
                "predicted_score_s16": 331,
            },
            "received_packet_hex": "b" * 32,
            "sent_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "ann_task",
                "payload_magic": "0xa11e",
            },
            "sent_packet_hex": "a" * 32,
            "predicted_label": "Slow",
            "inference_check": "MATCHED EXPECTED OFFLOAD RESULT",
            "failure_stage": None,
            "runner_log": None,
            "summary_md": None,
            "report_json": None,
        }
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            demo_verify._print_engine_result_block(view, verbose=False)
        rendered = buffer.getvalue()
        self.assertIn("Engine Step", rendered)
        self.assertIn("Observed Result:", rendered)
        self.assertIn("Predicted Label", rendered)
        self.assertIn("Slow", rendered)

    def test_build_engine_single_summary_is_compact(self) -> None:
        detailed_summary = {
            "runs_total": 1,
            "runs_passed": 1,
            "runs_failed": 0,
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            sender = out_dir / "sender.cap"
            receiver = out_dir / "receiver.cap"
            sent_frame, _meta = build_task_frame_defaults(request_id=0x1100)
            recv_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(sender, [sent_frame])
            write_pcap(receiver, [recv_frame])
            results = [
                {
                    "mode": "latency_single",
                    "run_name": "engine_single_infer_r01",
                    "single_packet_variant": "offload",
                    "sample_results": [
                        {
                            "phase": "measure",
                            "status": "passed",
                            "timed_out": False,
                            "sender_capture_exists": True,
                            "receiver_capture_exists": True,
                            "sender_capture_path": "sender.cap",
                            "receiver_capture_path": "receiver.cap",
                        }
                    ],
                }
            ]

            summary = demo_verify._build_engine_single_summary(
                ROOT_DIR / "scripts" / "board" / "rsu_demo_single_infer.json",
                out_dir,
                detailed_summary,
                results,
                labels=["Free-flow", "Slow"],
            )

        self.assertEqual(summary["view"], "engine-single")
        self.assertEqual(summary["overall_verdict"], "pass")
        self.assertEqual(summary["request_id"], "0x1100")
        self.assertEqual(summary["predicted_class"], 1)
        self.assertEqual(summary["predicted_label"], "Slow")
        self.assertEqual(summary["predicted_score_s16"], 331)
        self.assertNotIn("toolchain_verdict", summary)
        self.assertNotIn("inference_verdict", summary)
        self.assertNotIn("proof_runs", summary)

    def test_render_engine_single_markdown_uses_compact_summary(self) -> None:
        markdown = demo_verify._render_engine_single_markdown(
            {
                "overall_verdict": "pass",
                "request_id": "0x1100",
                "predicted_class": 1,
                "predicted_label": "Slow",
                "predicted_score_s16": 331,
                "inference_check": "MATCHED EXPECTED OFFLOAD RESULT",
                "config_path": "/tmp/config.json",
                "output_dir": "/tmp/out",
                "sent_packet_summary": {"request_id": "0x1100", "frame_kind": "ann_task"},
                "received_packet_summary": {
                    "request_id": "0x1100",
                    "frame_kind": "ann_result",
                    "predicted_class": 1,
                    "predicted_score_s16": 331,
                },
                "sent_packet_hex": "001122",
                "received_packet_hex": "aabbcc",
                "artifacts": {
                    "demo_summary_json": "demo_summary.json",
                    "demo_summary_md": "demo_summary.md",
                    "detailed_summary_json": "summary.json",
                    "detailed_summary_md": "summary.md",
                },
            }
        )
        self.assertIn("predicted_class: `1`", markdown)
        self.assertIn("predicted_label: `Slow`", markdown)
        self.assertNotIn("toolchain_verdict", markdown)
        self.assertNotIn("Proof Runs", markdown)
