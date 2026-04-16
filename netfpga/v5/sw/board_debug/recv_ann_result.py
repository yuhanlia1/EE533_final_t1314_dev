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
from board_debug.ann_packets import parse_result_frame  # noqa: E402


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
    parser = OptionParser(usage="%prog [options]", description="Capture ANN result frames from a raw Ethernet interface.")
    parser.add_option("--iface", dest="iface")
    parser.add_option("--count", dest="count", default="1")
    parser.add_option("--timeout-ms", dest="timeout_ms", default="1000")
    parser.add_option("--request-id", dest="request_id")
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
                parsed = parse_result_frame(frame, "legacy_logits")
            except ValueError:
                continue
            if request_id is not None and parsed.request_id != request_id:
                continue
            row = parsed.to_json_dict()
            row["request_id"] = parsed.request_id
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
