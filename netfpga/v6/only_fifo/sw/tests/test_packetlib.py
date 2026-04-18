import os
import sys
import unittest


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
SW_DIR = os.path.dirname(THIS_DIR)
if SW_DIR not in sys.path:
    sys.path.insert(0, SW_DIR)


from packetlib.udp_ann_packets import (  # noqa: E402
    ACTION_BYPASS,
    ACTION_OFFLOAD,
    ANN_TASK_MAGIC,
    ANN_UDP_DST_PORT,
    DEFAULT_DST_PORT_MASK,
    DEFAULT_REQUEST_ID,
    DEFAULT_SRC_PORT,
    OFFLOAD_RESULT_MAGIC,
    build_opl_packet,
    build_packet_artifacts,
    build_udp_ann_frame,
    decode_packet_blob,
    render_opl_words_text,
    rewrite_udp_payload_for_offload,
    selector_expected_action_for_wire_frame,
)


class PacketLibTest(unittest.TestCase):
    def test_udp_ann_frame_offload_metadata(self):
        frame, payload, metadata = build_udp_ann_frame(
            dst_mac="0b:ad:c0:de:00:01",
            src_mac="f0:0d:ca:fe:00:02",
            src_ip="192.168.1.1",
            dst_ip="192.168.1.2",
            udp_src_port=0x4001,
            udp_dst_port=ANN_UDP_DST_PORT,
            task_magic=ANN_TASK_MAGIC,
            request_id=DEFAULT_REQUEST_ID,
            feature_count=8,
            task_type=0x0000,
            emitted_feature_count=8,
            feature_seed=3,
            explicit_features=None,
        )
        self.assertEqual(len(payload), 24)
        self.assertEqual(len(frame), 66)
        self.assertEqual(metadata["request_id"], "0x1234")
        self.assertEqual(selector_expected_action_for_wire_frame(frame), ACTION_OFFLOAD)

    def test_opl_encoding_matches_tb_shape(self):
        artifacts = build_packet_artifacts(
            {
                "packet_kind": "udp_ann",
                "src_port": DEFAULT_SRC_PORT,
                "dst_port_mask": DEFAULT_DST_PORT_MASK,
            }
        )
        self.assertEqual(artifacts["expected_module_header"], "0x0008000900010044")
        self.assertEqual(artifacts["internal_frame_len"], 68)
        self.assertEqual(artifacts["opl_words"][-1]["ctrl"], "0x10")
        self.assertTrue(render_opl_words_text(artifacts["opl_words"]).startswith("000 0x0008000900010044 0xff"))

    def test_wrong_udp_port_bypasses(self):
        artifacts = build_packet_artifacts(
            {
                "packet_kind": "udp_ann",
                "udp_dst_port": 0x9999,
            }
        )
        self.assertEqual(artifacts["selector_expected_action"], ACTION_BYPASS)

    def test_decode_wire_frame(self):
        artifacts = build_packet_artifacts({"packet_kind": "udp_ann"})
        decoded = decode_packet_blob(bytes.fromhex(artifacts["wire_frame_hex"]), "wire")
        self.assertEqual(decoded["selector_expected_action"], ACTION_OFFLOAD)
        self.assertEqual(decoded["udp_payload"]["task_magic"], "0x%04x" % ANN_TASK_MAGIC)
        self.assertEqual(decoded["udp_payload"]["request_id"], "0x%04x" % DEFAULT_REQUEST_ID)

    def test_offload_expected_receive_magic_uses_result_marker(self):
        artifacts = build_packet_artifacts({"packet_kind": "udp_ann"})
        self.assertEqual(artifacts["expected_rx_kind"], ACTION_OFFLOAD)
        self.assertEqual(artifacts["expected_rx_magic"], "0x%04x" % OFFLOAD_RESULT_MAGIC)

    def test_rewritten_payload_decodes_as_offload_result(self):
        artifacts = build_packet_artifacts({"packet_kind": "udp_ann"})
        rewritten = rewrite_udp_payload_for_offload(bytes.fromhex(artifacts["udp_payload_hex"]))
        decoded = decode_packet_blob(rewritten, "udp_payload")
        self.assertEqual(decoded["task_magic"], "0x%04x" % OFFLOAD_RESULT_MAGIC)
        self.assertEqual(decoded["task_magic_kind"], "offload_result")


if __name__ == "__main__":
    unittest.main()
