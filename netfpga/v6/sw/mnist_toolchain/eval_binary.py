#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SW_DIR = SCRIPT_DIR.parent
import sys

if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from board_debug.model_batch_eval import compare_expected_observed, load_expected_outputs, load_observed_outputs  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare observed binary MNIST ANN results against expected outputs.")
    parser.add_argument("--expected", required=True)
    parser.add_argument("--observed", required=True)
    parser.add_argument("--report-out")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = compare_expected_observed(load_expected_outputs(args.expected), load_observed_outputs(args.observed))
    if args.report_out:
        Path(args.report_out).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if not summary["mismatches"] and not summary["missing_samples"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
