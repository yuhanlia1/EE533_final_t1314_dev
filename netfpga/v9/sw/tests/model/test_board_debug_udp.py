from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))
ROOT_DIR = SW_DIR.parent

_BOARDCTL_SPEC = importlib.util.spec_from_file_location(
    "boardctl_module",
    ROOT_DIR / "scripts" / "board" / "boardctl.py",
)
boardctl = importlib.util.module_from_spec(_BOARDCTL_SPEC)
assert _BOARDCTL_SPEC.loader is not None
_BOARDCTL_SPEC.loader.exec_module(boardctl)

from board_debug.ann_packets import (
    ANN_RESULT_MAGIC,
    ANN_UDP_DST_PORT,
    build_result_frame,
    build_task_frame_defaults,
    inspect_ann_frame,
    parse_result_frame,
    rewrite_result_frame,
)
from board_debug.model_batch_eval import compare_expected_observed, observed_rows_from_frames


class BoardDebugUdpPacketTests(unittest.TestCase):
    def test_task_frame_defaults_emit_udp_ann_packet(self) -> None:
        frame, metadata = build_task_frame_defaults(request_id=0x2222)
        parsed = inspect_ann_frame(frame)

        self.assertEqual(metadata["ethertype"], "0x0800")
        self.assertEqual(metadata["ip_protocol"], "0x11")
        self.assertEqual(metadata["udp_dst_port"], "0x88b5")
        self.assertEqual(metadata["udp_checksum"], "0x0000")
        self.assertEqual(parsed["frame_kind"], "ann_task")
        self.assertEqual(parsed["request_id"], 0x2222)
        self.assertEqual(parsed["payload_magic"], "0xa11e")

    def test_result_frame_roundtrip_preserves_udp_headers(self) -> None:
        frame = build_result_frame(request_id=0x1234, result_data_0=7, result_data_1=-5)
        parsed = parse_result_frame(frame)
        inspected = inspect_ann_frame(frame)

        self.assertEqual(parsed.request_id, 0x1234)
        self.assertEqual(parsed.result_data_0_s16, 7)
        self.assertEqual(parsed.result_data_1_s16, -5)
        self.assertEqual(parsed.predicted_class, 0)
        self.assertEqual(parsed.udp_dst_port, ANN_UDP_DST_PORT)
        self.assertEqual(parsed.udp_checksum, 0)
        self.assertEqual(inspected["frame_kind"], "ann_result")
        self.assertEqual(inspected["wire_result_data_0_u16"], "0x0007")

    def test_rewrite_result_frame_preserves_outer_headers(self) -> None:
        task_frame, _metadata = build_task_frame_defaults(request_id=0x3456)
        result_frame = rewrite_result_frame(task_frame, request_id=0x3456, result_data_0=3, result_data_1=-2)

        self.assertEqual(task_frame[:42], result_frame[:42])
        self.assertEqual(task_frame[40:42], result_frame[40:42])

        parsed = parse_result_frame(result_frame, "compact_class_score")
        self.assertEqual(parsed.result_data_0_u16, 3)
        self.assertEqual(parsed.result_data_1_s16, -2)
        self.assertEqual(parsed.predicted_class, 3)
        self.assertEqual(parsed.predicted_score_s16, -2)
        self.assertIn("%04x" % ANN_RESULT_MAGIC, parsed.wire_frame_hex)

    def test_offline_batch_alignment_uses_request_id_when_first_result_is_missing(self) -> None:
        expected_rows = [
            {
                "name": "window_id_20",
                "predicted_class": 1,
                "wire_result_data_0_u16": 1,
                "wire_result_data_1_u16": 331,
                "result_mode": "compact_class_score",
            },
            {
                "name": "window_id_0",
                "predicted_class": 1,
                "wire_result_data_0_u16": 1,
                "wire_result_data_1_u16": 319,
                "result_mode": "compact_class_score",
            },
            {
                "name": "window_id_172",
                "predicted_class": 1,
                "wire_result_data_0_u16": 1,
                "wire_result_data_1_u16": 172,
                "result_mode": "compact_class_score",
            },
            {
                "name": "window_id_175",
                "predicted_class": 1,
                "wire_result_data_0_u16": 1,
                "wire_result_data_1_u16": 172,
                "result_mode": "compact_class_score",
            },
        ]
        frames = [
            build_result_frame(request_id=0x1235, result_data_0=1, result_data_1=319),
            build_result_frame(request_id=0x1236, result_data_0=1, result_data_1=172),
            build_result_frame(request_id=0x1237, result_data_0=1, result_data_1=172),
        ]

        observed_rows = observed_rows_from_frames(
            frames,
            expected_rows=expected_rows,
            result_mode="compact_class_score",
            request_id_base=0x1234,
        )
        summary = compare_expected_observed(expected_rows, observed_rows)

        self.assertEqual([row["name"] for row in observed_rows], ["window_id_0", "window_id_172", "window_id_175"])
        self.assertEqual(summary["class_matches"], 3)
        self.assertEqual(summary["wire_matches"], 3)
        self.assertEqual(summary["missing_samples"], ["window_id_20"])
        self.assertEqual(len(summary["mismatches"]), 1)
        self.assertEqual(summary["mismatches"][0]["reason"], "missing_observation")

    def test_boardctl_capture_workflow_includes_time_window_script(self) -> None:
        manifest = {
            "usc": {
                "receiver_host": "node3@nf1.usc.edu",
                "receiver_iface": "port2",
                "sender_host": "node3@nf4.usc.edu",
                "sender_iface": "port0",
                "netfpga_host": "netfpga@nf3.usc.edu",
                "remote_receiver_root": "~/v8/demo_receiver",
                "remote_sender_root": "~/v8/demo_sender",
                "remote_netfpga_root": "~/scripts/v8/demo_netfpga",
                "remote_netfpga_results": "~/scripts/v8/demo_results",
            },
            "network": {
                "src_ip": "10.0.12.3",
                "dst_ip": "10.0.14.3",
            },
            "artifacts": {
                "offload_batch_pcap": "pcaps/offload_batch.pcap",
                "offload_smoke_pcap": "pcaps/offload_smoke_0.pcap",
                "wrong_magic_pcap": "pcaps/wrong_magic_bypass.pcap",
                "wrong_port_pcap": "pcaps/wrong_port_bypass.pcap",
                "offload_smoke_capture": "captures/offload_smoke.cap",
                "offload_batch_time_window_capture": "captures/offload_batch_time_window.cap",
                "debug_status_txt": "debug_status_post.txt",
            },
            "counts": {
                "batch_packet_count": 4,
            },
            "capture": {
                "batch_time_window_seconds": 2.5,
            },
        }

        scripts = boardctl._render_capture_workflow(Path("/tmp/demo_run"), manifest)

        self.assertIn("nf1_capture_offload_batch.sh", scripts)
        self.assertIn("nf1_capture_offload_batch_count.sh", scripts)
        self.assertIn("nf1_capture_offload_batch_time_window.sh", scripts)
        self.assertIn("nf1_capture_offload_smoke.sh", scripts)
        self.assertIn("nf4_capture_offload_batch_sender.sh", scripts)
        self.assertIn("nf4_capture_offload_batch_sender_primary.sh", scripts)
        self.assertIn("nf4_capture_offload_batch_sender_fallback.sh", scripts)
        self.assertIn("nf4_replay_offload_smoke.sh", scripts)
        self.assertIn("nf1_cleanup_offload_batch_receiver_captures.sh", scripts)
        self.assertIn("nf4_cleanup_offload_batch_sender_captures.sh", scripts)
        self.assertIn("-c 4", scripts["nf1_capture_offload_batch.sh"])
        self.assertIn("sudo /usr/sbin/tcpdump -i port2", scripts["nf1_capture_offload_batch.sh"])
        self.assertIn("offload_smoke.cap", scripts["nf1_capture_offload_smoke.sh"])
        self.assertIn("offload_smoke_0.pcap", scripts["nf4_replay_offload_smoke.sh"])
        self.assertIn("sudo /usr/sbin/tcpdump -i port0", scripts["nf4_capture_offload_batch_sender.sh"])
        self.assertIn("sudo /usr/sbin/tcpdump -i port2 -nn -U -c 4", scripts["nf1_capture_offload_batch_count.sh"])
        self.assertIn("offload_batch_receiver_primary.cap", scripts["nf1_capture_offload_batch_count.sh"])
        self.assertIn("offload_batch_sender_primary.cap", scripts["nf4_capture_offload_batch_sender_primary.sh"])
        self.assertIn("offload_batch_sender_fallback.cap", scripts["nf4_capture_offload_batch_sender_fallback.sh"])
        self.assertNotIn("timeout --signal=INT", scripts["nf1_capture_offload_batch_time_window.sh"])
        self.assertNotIn("-G 3 -W 1", scripts["nf1_capture_offload_batch_time_window.sh"])
        self.assertNotIn("-c 4", scripts["nf1_capture_offload_batch_time_window.sh"])
        self.assertIn("offload_batch_receiver_fallback.cap", scripts["nf1_capture_offload_batch_time_window.sh"])
        self.assertIn("offload_batch_sender.cap", scripts["nf4_capture_offload_batch_sender.sh"])
        self.assertIn("local_fetch_sender_captures.sh", scripts)

    def test_boardctl_augments_report_with_debug_emit_gap(self) -> None:
        expected_rows = [
            {"name": "window_id_20", "request_id": 0x1234},
            {"name": "window_id_0", "request_id": 0x1235},
            {"name": "window_id_172", "request_id": 0x1236},
            {"name": "window_id_175", "request_id": 0x1237},
        ]
        summary = {
            "sample_count": 4,
            "observed_count": 3,
            "missing_samples": ["window_id_20"],
            "mismatches": [{"name": "window_id_20", "reason": "missing_observation"}],
        }
        manifest = {
            "counts": {"batch_packet_count": 4},
        }
        debug_text = "\n".join(
            [
                "offload_accept_count   = 4",
                "frame_hold_count       = 4",
                "compute_done_count     = 4",
                "result_emit_count      = 4",
            ]
        )

        augmented = boardctl._augment_batch_summary(
            summary,
            manifest,
            expected_rows,
            observed_rows=[{"request_id": 0x1235}, {"request_id": 0x1236}, {"request_id": 0x1237}],
            batch_capture_path=Path("/tmp/offload_batch_time_window.cap"),
            debug_status_text=debug_text,
        )

        self.assertEqual(augmented["sent_count"], 4)
        self.assertEqual(augmented["capture_count"], 3)
        self.assertEqual(augmented["debug_emit_count"], 4)
        self.assertEqual(augmented["capture_vs_emit_gap"], 1)
        self.assertEqual(augmented["pipeline_verdict"], "capture_side_miss")
        self.assertEqual(augmented["missing_request_ids"], ["0x1234"])
        self.assertEqual(augmented["batch_capture_mode"], "time_window")

    def test_boardctl_augments_report_with_sender_receiver_request_ids(self) -> None:
        manifest = {
            "counts": {"batch_packet_count": 4},
            "network": {"request_id_base": "0x1234"},
        }
        summary = {}
        sender_rows = [{"request_id": 0x1234}, {"request_id": 0x1235}, {"request_id": 0x1236}, {"request_id": 0x1237}]
        receiver_rows = [{"request_id": 0x1235}, {"request_id": 0x1236}, {"request_id": 0x1237}]
        debug_text = "result_emit_count = 4\nlast_emit_request_id = 0x1237\n"

        augmented = boardctl._augment_sender_receiver_summary(
            summary,
            manifest,
            sender_rows,
            receiver_rows,
            debug_status_text=debug_text,
        )

        self.assertEqual(augmented["expected_request_ids"], ["0x1234", "0x1235", "0x1236", "0x1237"])
        self.assertEqual(augmented["sender_capture_count"], 4)
        self.assertEqual(augmented["receiver_capture_count"], 3)
        self.assertEqual(augmented["sender_request_ids"], ["0x1234", "0x1235", "0x1236", "0x1237"])
        self.assertEqual(augmented["receiver_request_ids"], ["0x1235", "0x1236", "0x1237"])
        self.assertEqual(augmented["engine_emit_count"], 4)
        self.assertEqual(augmented["engine_last_emit_request_id"], "0x1237")


if __name__ == "__main__":
    unittest.main()
