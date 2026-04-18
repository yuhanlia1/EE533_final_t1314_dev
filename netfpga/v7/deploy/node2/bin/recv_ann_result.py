#!/usr/bin/env python

import os
import socket
import sys
import time
from optparse import OptionParser


def _add_import_root():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    deploy_python = os.path.join(parent_dir, "python", "board_debug")
    if os.path.isdir(deploy_python):
        import_root = os.path.join(parent_dir, "python")
    else:
        import_root = parent_dir
    if import_root not in sys.path:
        sys.path.insert(0, import_root)


_add_import_root()

from board_debug import json_compat  # noqa: E402
from board_debug.ann_packets import DEFAULT_UDP_DST_PORT, inspect_ann_frame, parse_result_frame  # noqa: E402
from board_debug.model_batch_eval import load_expected_outputs  # noqa: E402


def _write_json(path, value):
    handle = open(path, "w")
    try:
        handle.write(json_compat.dumps(value, indent=2, sort_keys=False))
        handle.write("\n")
    finally:
        handle.close()


def _write_line(text):
    sys.stdout.write(text + "\n")


def _parse_int(value):
    if value is None:
        return None
    return int(value, 0)


def parse_args():
    parser = OptionParser(usage="%prog [options]", description="Capture ANN UDP result frames from a raw Ethernet interface.")
    parser.add_option("--iface", dest="iface")
    parser.add_option("--count", dest="count", default="1")
    parser.add_option("--timeout-ms", dest="timeout_ms", default="1000")
    parser.add_option("--request-id", dest="request_id")
    parser.add_option("--result-mode", dest="result_mode")
    parser.add_option("--expected", dest="expected")
    parser.add_option("--accept-bypass", dest="accept_bypass", action="store_true", default=False)
    parser.add_option("--udp-dst-port", dest="udp_dst_port", default="0x%04x" % DEFAULT_UDP_DST_PORT)
    parser.add_option("--json-out", dest="json_out")
    options, args = parser.parse_args()
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    if not options.iface:
        parser.error("--iface is required")
    return options


def main():
    args = parse_args()
    deadline = time.time() + (float(args.timeout_ms) / 1000.0)
    captured = []
    count = int(args.count)
    request_id = _parse_int(args.request_id)
    udp_dst_port = _parse_int(args.udp_dst_port)
    if args.expected:
        expected_rows = load_expected_outputs(args.expected)
    else:
        expected_rows = None
    if args.result_mode:
        result_mode = str(args.result_mode)
    elif expected_rows:
        result_mode = str(expected_rows[0].get("result_mode", "legacy_logits"))
    else:
        result_mode = "legacy_logits"

    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    try:
        sock.bind((args.iface, 0))
        while len(captured) < count and time.time() < deadline:
            remaining = deadline - time.time()
            if remaining < 0.001:
                remaining = 0.001
            sock.settimeout(remaining)
            frame = sock.recv(2048)
            try:
                parsed = parse_result_frame(frame, result_mode)
                row = parsed.to_json_dict()
            except ValueError:
                if not args.accept_bypass:
                    continue
                try:
                    row = inspect_ann_frame(frame, result_mode)
                except ValueError:
                    continue

            row_udp_dst_port = row.get("udp_dst_port")
            if row_udp_dst_port is not None and int(str(row_udp_dst_port), 0) != udp_dst_port:
                continue
            if request_id is not None and row.get("request_id") != request_id:
                continue
            if expected_rows and len(captured) < len(expected_rows):
                row["name"] = str(expected_rows[len(captured)]["name"])
                if "result_mode" not in row:
                    row["result_mode"] = str(expected_rows[len(captured)].get("result_mode", result_mode))
            captured.append(row)
    finally:
        sock.close()

    if args.json_out:
        _write_json(args.json_out, captured)
    _write_line(json_compat.dumps(captured, indent=2, sort_keys=False))
    if len(captured) == count:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
