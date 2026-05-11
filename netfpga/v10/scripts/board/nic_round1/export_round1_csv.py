#!/usr/bin/env python3

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[3]
DEFAULT_SOURCE_SUMMARY = ROOT_DIR / "bt" / "round1_final" / "summary.json"
DEFAULT_REPORT_DIR = ROOT_DIR / "bt" / "report"
DATASET_VERSION = "round1_final_v1"


def _load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _normalize_value(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return value


def _write_csv(path, fieldnames, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: _normalize_value(row.get(key)) for key in fieldnames})


def _overview_rows(summary, source_summary_path):
    return [
        {
            "dataset_version": DATASET_VERSION,
            "source_summary_json": str(source_summary_path.resolve()),
            "created_at": summary.get("created_at"),
            "max_zero_loss_pps": summary.get("max_zero_loss_pps"),
            "max_zero_loss_wire_gbps": summary.get("max_zero_loss_wire_gbps"),
            "max_zero_loss_payload_gbps": summary.get("max_zero_loss_payload_gbps"),
            "first_overload_pps": summary.get("first_overload_pps"),
            "single_packet_passed_runs": len(
                [item for item in summary.get("single_packet_results", []) if item.get("board_passed")]
            ),
            "rate_scan_passed_runs": len(
                [item for item in summary.get("rate_scan_results", []) if item.get("board_passed")]
            ),
            "burst_curve_passed_runs": len(
                [item for item in summary.get("burst_curve_results", []) if item.get("board_passed")]
            ),
        }
    ]


def _single_packet_rows(summary):
    rows = []
    for item in summary.get("single_packet_results", []):
        rows.append(
            {
                "run_name": item.get("run_name"),
                "variant": item.get("single_packet_variant"),
                "status": item.get("status"),
                "sample_pass_rate": item.get("sample_pass_rate"),
                "mean_completion_us": item.get("mean_completion_us"),
                "p50_completion_us": item.get("p50_completion_us"),
                "p95_completion_us": item.get("p95_completion_us"),
                "max_completion_us": item.get("max_completion_us"),
                "timing_mode": item.get("timing_mode"),
                "latency_status": item.get("latency_status"),
            }
        )
    return rows


def _rate_scan_rows(summary):
    rows = []
    for item in sorted(
        summary.get("rate_scan_results", []),
        key=lambda row: float(row.get("offered_rate_req_per_sec") or 0.0),
    ):
        rows.append(
            {
                "run_name": item.get("run_name"),
                "offered_rate_req_per_sec": item.get("offered_rate_req_per_sec"),
                "actual_send_rate_req_per_sec": item.get("actual_send_rate_req_per_sec"),
                "goodput_result_per_sec": item.get("goodput_result_per_sec"),
                "wire_goodput_gbps": item.get("wire_goodput_gbps"),
                "payload_goodput_gbps": item.get("payload_goodput_gbps"),
                "measurement_valid": item.get("measurement_valid"),
                "drop_count": item.get("drop_count"),
                "drop_ratio": item.get("drop_ratio"),
                "mismatch_count": item.get("mismatch_count"),
                "rate_error_ratio": item.get("rate_error_ratio"),
                "sender_capture_count": item.get("sender_capture_count"),
                "receiver_capture_count": item.get("receiver_capture_count"),
                "engine_emit_count": item.get("engine_emit_count"),
                "receiver_span_seconds": item.get("receiver_span_seconds"),
                "send_span_seconds": item.get("send_span_seconds"),
                "pipeline_verdict": item.get("pipeline_verdict"),
                "correctness_verdict": item.get("correctness_verdict"),
            }
        )
    return rows


def _burst_curve_rows(summary):
    rows = []
    for item in sorted(
        summary.get("burst_curve_results", []),
        key=lambda row: int(row.get("batch_size") or 0),
    ):
        rows.append(
            {
                "run_name": item.get("run_name"),
                "batch_size": item.get("batch_size"),
                "status": item.get("status"),
                "correctness_verdict": item.get("correctness_verdict"),
                "batch_completion_time_us": item.get("batch_completion_time_us"),
                "throughput_req_per_sec": item.get("throughput_req_per_sec"),
                "throughput_result_per_sec": item.get("throughput_result_per_sec"),
                "sender_capture_count": item.get("sender_capture_count"),
                "receiver_capture_count": item.get("receiver_capture_count"),
                "engine_emit_count": item.get("engine_emit_count"),
                "offload_accept_count": item.get("offload_accept_count"),
                "compute_done_count": item.get("compute_done_count"),
                "request_id_base": item.get("request_id_base"),
                "sample_pool_mode": item.get("sample_pool_mode"),
                "sample_pool_repeated": item.get("sample_pool_repeated"),
            }
        )
    return rows


def _write_readme(report_dir, source_summary_path):
    text = f"""# Round 1 CSV Export

- source_summary_json: `{source_summary_path.resolve()}`
- dataset_version: `{DATASET_VERSION}`
- generated_at: `{datetime.now().isoformat(timespec="seconds")}`

## Files

- `round1_overview.csv`
  - one-row project summary
- `round1_single_packet.csv`
  - single-packet relative completion data for `offload`, `wrong_magic`, `wrong_port`
- `round1_rate_scan.csv`
  - sustained throughput / drop / overload data
- `round1_burst_curve.csv`
  - pure-batch burst envelope data for `batch8/16/32/64`

## Notes

- All CSV files are exported from `bt/round1_final/summary.json`.
- `round1_single_packet.csv` is relative completion data, not absolute RTT.
- `round1_rate_scan.csv` uses the corrected receiver-local time window for `goodput_result_per_sec`, `wire_goodput_gbps`, and `payload_goodput_gbps`.
- `round1_burst_curve.csv` should be interpreted primarily through:
  - `correctness_verdict`
  - `batch_completion_time_us`
  - `throughput_req_per_sec`
- `engine_emit_count`, `offload_accept_count`, and `compute_done_count` are preserved as diagnostic fields only because some burst runs still show debug-counter inflation.
"""
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "README.md").write_text(text, encoding="utf-8")


def build_parser():
    parser = argparse.ArgumentParser(description="Export round1 project CSVs from bt/round1_final/summary.json")
    parser.add_argument("--source-summary", default=str(DEFAULT_SOURCE_SUMMARY))
    parser.add_argument("--out-dir", default=str(DEFAULT_REPORT_DIR))
    return parser


def main():
    args = build_parser().parse_args()
    source_summary_path = Path(args.source_summary).resolve()
    out_dir = Path(args.out_dir).resolve()
    summary = _load_json(source_summary_path)

    _write_csv(
        out_dir / "round1_overview.csv",
        [
            "dataset_version",
            "source_summary_json",
            "created_at",
            "max_zero_loss_pps",
            "max_zero_loss_wire_gbps",
            "max_zero_loss_payload_gbps",
            "first_overload_pps",
            "single_packet_passed_runs",
            "rate_scan_passed_runs",
            "burst_curve_passed_runs",
        ],
        _overview_rows(summary, source_summary_path),
    )
    _write_csv(
        out_dir / "round1_single_packet.csv",
        [
            "run_name",
            "variant",
            "status",
            "sample_pass_rate",
            "mean_completion_us",
            "p50_completion_us",
            "p95_completion_us",
            "max_completion_us",
            "timing_mode",
            "latency_status",
        ],
        _single_packet_rows(summary),
    )
    _write_csv(
        out_dir / "round1_rate_scan.csv",
        [
            "run_name",
            "offered_rate_req_per_sec",
            "actual_send_rate_req_per_sec",
            "goodput_result_per_sec",
            "wire_goodput_gbps",
            "payload_goodput_gbps",
            "measurement_valid",
            "drop_count",
            "drop_ratio",
            "mismatch_count",
            "rate_error_ratio",
            "sender_capture_count",
            "receiver_capture_count",
            "engine_emit_count",
            "receiver_span_seconds",
            "send_span_seconds",
            "pipeline_verdict",
            "correctness_verdict",
        ],
        _rate_scan_rows(summary),
    )
    _write_csv(
        out_dir / "round1_burst_curve.csv",
        [
            "run_name",
            "batch_size",
            "status",
            "correctness_verdict",
            "batch_completion_time_us",
            "throughput_req_per_sec",
            "throughput_result_per_sec",
            "sender_capture_count",
            "receiver_capture_count",
            "engine_emit_count",
            "offload_accept_count",
            "compute_done_count",
            "request_id_base",
            "sample_pool_mode",
            "sample_pool_repeated",
        ],
        _burst_curve_rows(summary),
    )
    _write_readme(out_dir, source_summary_path)
    print("report_dir=%s" % out_dir)
    print("overview_csv=%s" % (out_dir / "round1_overview.csv"))
    print("single_packet_csv=%s" % (out_dir / "round1_single_packet.csv"))
    print("rate_scan_csv=%s" % (out_dir / "round1_rate_scan.csv"))
    print("burst_curve_csv=%s" % (out_dir / "round1_burst_curve.csv"))


if __name__ == "__main__":
    raise SystemExit(main())
