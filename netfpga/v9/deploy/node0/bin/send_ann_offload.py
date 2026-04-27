#!/usr/bin/env python

import errno
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
from board_debug.ann_packets import (  # noqa: E402
    ANN_TASK_MAGIC,
    DEFAULT_DST_MAC,
    DEFAULT_DST_IP,
    DEFAULT_FEATURE_COUNT,
    DEFAULT_FEATURE_SEED,
    DEFAULT_REQUEST_ID,
    DEFAULT_SRC_MAC,
    DEFAULT_SRC_IP,
    DEFAULT_UDP_DST_PORT,
    DEFAULT_UDP_SRC_PORT,
    DEFAULT_TASK_TYPE,
    build_task_frame_defaults,
    parse_feature_values,
)


def _write_line(text):
    sys.stdout.write(text + "\n")


def _raise_system_exit(message):
    raise SystemExit(message)


def send_raw_frame(iface, frame, repeat, interval_ms):
    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
        sock.bind((iface, 0))
    except:
        exc = sys.exc_info()[1]
        err = getattr(exc, "errno", None)
        if err == errno.EPERM or err == errno.EACCES:
            _raise_system_exit("permission denied opening raw socket on %s: %s" % (iface, exc))
        _raise_system_exit("failed to open raw socket on %s: %s" % (iface, exc))

    try:
        index = 0
        while index < repeat:
            sock.send(frame)
            if index + 1 < repeat:
                time.sleep(float(interval_ms) / 1000.0)
            index += 1
    finally:
        sock.close()


def _parse_int(value):
    if value is None:
        return None
    return int(value, 0)


def parse_args():
    parser = OptionParser(usage="%prog [options]", description="Build and optionally send a valid ANN IPv4/UDP offload frame.")
    parser.add_option("--dst-mac", dest="dst_mac", default=DEFAULT_DST_MAC)
    parser.add_option("--src-mac", dest="src_mac", default=DEFAULT_SRC_MAC)
    parser.add_option("--src-ip", dest="src_ip", default=DEFAULT_SRC_IP)
    parser.add_option("--dst-ip", dest="dst_ip", default=DEFAULT_DST_IP)
    parser.add_option("--src-udp-port", dest="src_udp_port", default="0x%04x" % DEFAULT_UDP_SRC_PORT)
    parser.add_option("--dst-udp-port", dest="dst_udp_port", default="0x%04x" % DEFAULT_UDP_DST_PORT)
    parser.add_option("--request-id", dest="request_id", default="0x%04x" % DEFAULT_REQUEST_ID)
    parser.add_option("--feature-count", dest="feature_count", default=str(DEFAULT_FEATURE_COUNT))
    parser.add_option("--emitted-feature-count", dest="emitted_feature_count")
    parser.add_option("--feature-seed", dest="feature_seed", default=str(DEFAULT_FEATURE_SEED))
    parser.add_option("--feature-values", dest="feature_values")
    parser.add_option("--task-type", dest="task_type", default="0x%04x" % DEFAULT_TASK_TYPE)
    parser.add_option("--task-magic", dest="task_magic", default="0x%04x" % ANN_TASK_MAGIC)
    parser.add_option("--send", dest="send", action="store_true", default=False)
    parser.add_option("--iface", dest="iface")
    parser.add_option("--repeat", dest="repeat", default="1")
    parser.add_option("--interval-ms", dest="interval_ms", default="100")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    parser.add_option("--json-out", dest="json_out")
    options, args = parser.parse_args()
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    return parser, options


def main():
    parser, args = parse_args()
    if args.feature_values:
        explicit_features = parse_feature_values(args.feature_values)
    else:
        explicit_features = None

    feature_count = _parse_int(args.feature_count)
    emitted_feature_count = _parse_int(args.emitted_feature_count)
    if explicit_features is not None:
        feature_count = len(explicit_features)
        emitted_feature_count = len(explicit_features)

    frame, metadata = build_task_frame_defaults(
        dst_mac=args.dst_mac,
        src_mac=args.src_mac,
        src_ip=args.src_ip,
        dst_ip=args.dst_ip,
        task_magic=_parse_int(args.task_magic),
        request_id=_parse_int(args.request_id),
        feature_count=feature_count,
        task_type=_parse_int(args.task_type),
        emitted_feature_count=emitted_feature_count,
        feature_seed=_parse_int(args.feature_seed),
        explicit_features=explicit_features,
        udp_src_port=_parse_int(args.src_udp_port),
        udp_dst_port=_parse_int(args.dst_udp_port),
    )

    if args.dump_json:
        output_text = json_compat.dumps(metadata, indent=2, sort_keys=True)
    else:
        output_lines = []
        output_lines.append("wire_frame_hex=%s" % metadata["wire_frame_hex"])
        output_lines.append("wire_len=%s" % metadata["wire_len"])
        output_lines.append("ip_src=%s" % metadata["ip_src"])
        output_lines.append("ip_dst=%s" % metadata["ip_dst"])
        output_lines.append("udp_src_port=%s" % metadata["udp_src_port"])
        output_lines.append("udp_dst_port=%s" % metadata["udp_dst_port"])
        output_text = "\n".join(output_lines)

    _write_line(output_text)

    if args.json_out:
        handle = open(args.json_out, "w")
        try:
            handle.write(json_compat.dumps(metadata, indent=2, sort_keys=True))
            handle.write("\n")
        finally:
            handle.close()

    if args.send:
        if not args.iface:
            parser.error("--iface is required with --send")
        send_raw_frame(args.iface, frame, repeat=int(args.repeat), interval_ms=int(args.interval_ms))
        _write_line("sent %d frame(s) on %s" % (int(args.repeat), args.iface))

    return 0


if __name__ == "__main__":
    sys.exit(main())
