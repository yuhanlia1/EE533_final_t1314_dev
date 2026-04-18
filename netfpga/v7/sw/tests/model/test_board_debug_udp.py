from __future__ import annotations

import sys
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from board_debug.ann_packets import (
    ANN_RESULT_MAGIC,
    ANN_UDP_DST_PORT,
    build_result_frame,
    build_task_frame_defaults,
    inspect_ann_frame,
    parse_result_frame,
    rewrite_result_frame,
)


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


if __name__ == "__main__":
    unittest.main()
