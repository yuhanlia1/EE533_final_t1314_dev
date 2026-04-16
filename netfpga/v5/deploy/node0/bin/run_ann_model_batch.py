#!/usr/bin/env python

import os
import sys
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
    DEFAULT_DST_MAC,
    DEFAULT_DST_PORT_MASK,
    DEFAULT_REQUEST_ID,
    DEFAULT_SRC_MAC,
    DEFAULT_SRC_PORT,
    DEFAULT_TASK_TYPE,
)
from board_debug.model_batch_eval import (  # noqa: E402
    compare_expected_observed,
    load_expected_outputs,
    load_observed_outputs,
    load_test_vectors,
    run_live_batch,
)


def _write_json(path, value, sort_keys):
    handle = open(path, "w")
    try:
        handle.write(json_compat.dumps(value, indent=2, sort_keys=sort_keys))
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
    parser = OptionParser(usage="%prog [options]", description="Run or compare batch ANN model evaluation vectors.")
    parser.add_option("--test-vectors", dest="test_vectors")
    parser.add_option("--expected", dest="expected")
    parser.add_option("--observed-json", dest="observed_json")
    parser.add_option("--iface", dest="iface")
    parser.add_option("--limit", dest="limit")
    parser.add_option("--request-id-base", dest="request_id_base", default="0x%04x" % DEFAULT_REQUEST_ID)
    parser.add_option("--timeout-ms", dest="timeout_ms", default="1000")
    parser.add_option("--interval-ms", dest="interval_ms", default="50")
    parser.add_option("--dst-mac", dest="dst_mac", default=DEFAULT_DST_MAC)
    parser.add_option("--src-mac", dest="src_mac", default=DEFAULT_SRC_MAC)
    parser.add_option("--src-port", dest="src_port", default="0x%04x" % DEFAULT_SRC_PORT)
    parser.add_option("--dst-port-mask", dest="dst_port_mask", default="0x%04x" % DEFAULT_DST_PORT_MASK)
    parser.add_option("--task-type", dest="task_type", default="0x%04x" % DEFAULT_TASK_TYPE)
    parser.add_option("--report-out", dest="report_out")
    parser.add_option("--observed-out", dest="observed_out")
    options, args = parser.parse_args()
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    if not options.test_vectors:
        parser.error("--test-vectors is required")
    if not options.expected:
        parser.error("--expected is required")
    return parser, options


def main():
    parser, args = parse_args()
    test_vectors = load_test_vectors(args.test_vectors)
    expected_rows = load_expected_outputs(args.expected)

    if args.limit is not None:
        limit = int(args.limit)
        test_vectors = test_vectors[:limit]
        expected_rows = expected_rows[:limit]

    if args.iface:
        summary, observed_rows = run_live_batch(
            args.iface,
            test_vectors,
            expected_rows,
            request_id_base=_parse_int(args.request_id_base),
            timeout_ms=int(args.timeout_ms),
            interval_ms=int(args.interval_ms),
            dst_mac=args.dst_mac,
            src_mac=args.src_mac,
            src_port=_parse_int(args.src_port),
            dst_port_mask=_parse_int(args.dst_port_mask),
            task_type=_parse_int(args.task_type),
        )
    elif args.observed_json:
        observed_rows = load_observed_outputs(args.observed_json)
        summary = compare_expected_observed(expected_rows, observed_rows)
    else:
        parser.error("either --iface or --observed-json is required")

    if args.observed_out:
        _write_json(args.observed_out, observed_rows, False)
    if args.report_out:
        _write_json(args.report_out, summary, True)

    _write_line(json_compat.dumps(summary, indent=2, sort_keys=True))
    if summary["mismatches"] or summary["missing_samples"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
