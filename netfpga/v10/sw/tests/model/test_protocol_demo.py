from __future__ import annotations

import contextlib
import io
import importlib.util
import tempfile
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_PROTOCOL_DEMO_SPEC = importlib.util.spec_from_file_location(
    "protocol_demo_module",
    ROOT_DIR / "scripts" / "board" / "protocol_demo.py",
)
protocol_demo = importlib.util.module_from_spec(_PROTOCOL_DEMO_SPEC)
assert _PROTOCOL_DEMO_SPEC.loader is not None
_PROTOCOL_DEMO_SPEC.loader.exec_module(protocol_demo)

from board_debug.ann_packets import build_result_frame, build_task_frame_defaults, build_udp_frame_defaults
from board_debug.pcap_io import write_pcap


class ProtocolDemoTests(unittest.TestCase):
    def _runner_defaults(self):
        return protocol_demo.board_sweep._normalize_defaults({}, ROOT_DIR)

    def test_protocol_runner_accepts_generic_bypass_packet(self) -> None:
        runner = protocol_demo.ProtocolRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        manifest = {
            "model": {"result_mode": "compact_class_score"},
            "protocol_demo": {
                "bypass_udp_dst_port": "0x7777",
                "bypass_payload_hex": b"DEMO_BYPASS".hex(),
            },
        }
        frame, _meta = build_udp_frame_defaults(payload=b"DEMO_BYPASS", udp_dst_port=0x7777)

        with tempfile.TemporaryDirectory() as tmpdir:
            capture_path = Path(tmpdir) / "protocol_bypass.cap"
            write_pcap(capture_path, [frame])

            verdict = runner._single_packet_bypass_verdict(
                manifest,
                {"path": capture_path},
                "bypass",
            )

        self.assertEqual(verdict["verdict"], "bypass_ok")
        self.assertEqual(verdict["frame_kind"], "udp_unknown")
        self.assertEqual(verdict["udp_dst_port"], "0x7777")
        self.assertEqual(verdict["payload_hex"], b"DEMO_BYPASS".hex())

    def test_build_step_summary_reports_offload_result_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            capture_dir = run_dir / "captures"
            capture_dir.mkdir(parents=True, exist_ok=True)
            sent_frame, _meta = build_task_frame_defaults(request_id=0x1100)
            recv_frame = build_result_frame(request_id=0x1100, result_data_0=1, result_data_1=331)
            write_pcap(capture_dir / "offload_sender_001.cap", [sent_frame])
            write_pcap(capture_dir / "offload_receiver_001.cap", [recv_frame])

            step_summary = protocol_demo._build_step_summary(
                run_dir,
                {
                    "model": {"result_mode": "compact_class_score"},
                    "run_name": "protocol_demo_run",
                    "protocol_demo": {},
                },
                "offload",
                run_dir / "logs" / "protocol_offload.log",
                {
                    "status": "passed",
                    "sender_capture_path": "captures/offload_sender_001.cap",
                    "receiver_capture_path": "captures/offload_receiver_001.cap",
                },
            )

        self.assertEqual(step_summary["protocol_verdict"], "pass")
        self.assertEqual(step_summary["observed_packet_summary"]["frame_kind"], "ann_result")
        self.assertEqual(step_summary["observed_packet_summary"]["request_id"], "0x1100")
        self.assertIn("predicted_class=1", step_summary["protocol_check"])

    def test_update_protocol_summary_tracks_completed_steps(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            manifest = {
                "run_name": "protocol_demo_run",
                "protocol_demo": {
                    "config_path": "/tmp/protocol.json",
                    "steps": ["bypass", "wrong_magic", "offload"],
                },
            }
            step_summary = {
                "step": "bypass",
                "label": "Bypass Gate",
                "status": "passed",
                "protocol_verdict": "pass",
            }

            summary = protocol_demo._update_protocol_summary(run_dir, manifest, step_summary)

        self.assertEqual(summary["steps_completed"], ["bypass"])
        self.assertEqual(summary["steps_passed"], 1)
        self.assertEqual(summary["steps_failed"], 0)
        self.assertEqual(summary["overall_verdict"], "incomplete")

    def test_augment_manifest_for_protocol_demo_writes_bypass_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir)
            (run_dir / "pcaps").mkdir(parents=True, exist_ok=True)
            (run_dir / "commands").mkdir(parents=True, exist_ok=True)
            manifest = {
                "run_name": "protocol_demo_run",
                "model": {"result_mode": "compact_class_score", "source": "/tmp/model.json"},
                "bitfile": "demo.bit",
                "network": {
                    "dst_mac": "00:4e:46:32:43:00",
                    "src_mac": "a0:36:9f:0a:5d:5b",
                    "src_ip": "10.0.16.3",
                    "dst_ip": "10.0.18.3",
                    "src_udp_port": "0x4001",
                    "dst_udp_port": "0x88b5",
                    "task_type": "0x0000",
                },
                "usc": {
                    "sender_iface": "port0",
                    "receiver_iface": "port2",
                    "remote_sender_root": "~/v8/protocol_sender",
                    "remote_receiver_root": "~/v8/protocol_receiver",
                },
                "artifacts": {},
            }

            protocol_demo._augment_manifest_for_protocol_demo(
                run_dir,
                manifest,
                {
                    "config_path": "/tmp/protocol.json",
                    "runner_defaults": self._runner_defaults(),
                    "request_id_base": "0x1100",
                    "single_result_timeout_seconds": 2.0,
                    "bypass_udp_dst_port": 0x7777,
                    "bypass_payload_hex": b"DEMO_BYPASS".hex(),
                },
            )

            self.assertIn("protocol_demo", manifest)
            self.assertTrue((run_dir / "pcaps" / "protocol_bypass.pcap").exists())
            self.assertTrue((run_dir / "commands" / "nf1_capture_protocol_bypass.sh").exists())
            self.assertTrue((run_dir / "commands" / "nf4_replay_protocol_bypass.sh").exists())

    def test_print_step_block_adds_blank_lines_between_sections(self) -> None:
        step_summary = {
            "step": "bypass",
            "label": "Bypass Gate",
            "expected_behavior": "Packet should stay on bypass path.",
            "protocol_check": "receiver observed udp_unknown without ann_result",
            "protocol_verdict": "pass",
            "sent_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "udp_unknown",
                "udp_dst_port": "0x7777",
            },
            "sent_packet_hex": "00112233",
            "observed_packet_summary": {
                "request_id": "0x1100",
                "frame_kind": "udp_unknown",
                "udp_dst_port": "0x7777",
            },
            "observed_packet_hex": "aabbccdd",
            "artifacts": {"step_summary_md": "protocol_bypass_summary.md"},
        }

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            protocol_demo._print_step_block(step_summary)

        rendered = stdout.getvalue()
        self.assertTrue(rendered.startswith("\n"))
        self.assertIn("Expected          : Non-ANN UDP should stay on bypass path.\n", rendered)
        self.assertIn("Protocol Check    : udp_unknown captured on 0x7777\n", rendered)
        self.assertIn("Result            : PASS\n\n", rendered)
        self.assertIn("  Request Edge:\n\n", rendered)
        self.assertIn("    Sent Packet:\n\n", rendered)
        self.assertIn("hex:\n", rendered)
        self.assertIn("\n\n----------------------------------------------------------------------------------------------------\n  Result Edge:\n\n", rendered)
        self.assertIn("    Observed Packet:\n\n", rendered)
        self.assertIn("\n\n----------------------------------------------------------------------------------------------------\n  Step Summary:\n\n", rendered)
        self.assertTrue(rendered.endswith("====================================================================================================\n\n"))


if __name__ == "__main__":
    unittest.main()
