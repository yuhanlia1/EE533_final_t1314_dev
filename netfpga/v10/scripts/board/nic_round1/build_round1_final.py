#!/usr/bin/env python3

import argparse
import json
from datetime import datetime
from pathlib import Path
import sys


ROOT_DIR = Path(__file__).resolve().parents[3]
if str(ROOT_DIR / "scripts" / "board") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "scripts" / "board"))

import board_metrics


DEFAULT_SINGLE_PACKET_SUMMARY = ROOT_DIR / "bt" / "round1_fixcheck" / "single_packet" / "summary.json"
DEFAULT_RATE_BASELINE_SUMMARY = ROOT_DIR / "bt" / "round1_rerun" / "rate_scan" / "summary.json"
DEFAULT_RATE_EXTEND_ROOT = ROOT_DIR / "bt" / "round1_fastdata" / "rate_scan_extend"
DEFAULT_BURST_SUMMARY = ROOT_DIR / "bt" / "round1_final" / "burst_curve" / "summary.json"
DEFAULT_OUTPUT_ROOT = ROOT_DIR / "bt" / "round1_final"


def _load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def _write_text(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _collect_recomputed_rate_results(summary_path):
    summary = _load_json(summary_path)
    results = []
    for prior_result in summary.get("results", []):
        results.append(
            board_metrics.recompute_rate_scan_result_from_run_dir(
                prior_result["run_dir"],
                prior_result=prior_result,
            )
        )
    return results


def _collect_extend_recomputed_results(extend_root):
    results = []
    for summary_path in sorted(Path(extend_root).glob("*/summary.json")):
        summary = _load_json(summary_path)
        if not summary.get("results"):
            continue
        prior_result = summary["results"][0]
        results.append(
            board_metrics.recompute_rate_scan_result_from_run_dir(
                prior_result["run_dir"],
                prior_result=prior_result,
            )
        )
    return results


def _max_zero_loss(rate_results):
    valid = [
        item for item in rate_results
        if item.get("measurement_valid")
        and int(item.get("drop_count", 0) or 0) == 0
        and int(item.get("mismatch_count", 0) or 0) == 0
    ]
    valid.sort(key=lambda item: float(item.get("offered_rate_req_per_sec", 0.0)))
    return valid[-1] if valid else None


def _first_overload(rate_results):
    for item in sorted(rate_results, key=lambda entry: float(entry.get("offered_rate_req_per_sec", 0.0))):
        if not item.get("measurement_valid") or int(item.get("drop_count", 0) or 0) > 0:
            return item
    return None


def _render_markdown(summary):
    lines = [
        "# Round 1 Final Summary",
        "",
        f"- single_packet_ref: `{summary['single_packet_ref']}`",
        f"- rate_scan_baseline_ref: `{summary['rate_scan_baseline_ref']}`",
        f"- rate_scan_extend_root: `{summary['rate_scan_extend_root']}`",
        f"- burst_curve_ref: `{summary['burst_curve_ref']}`",
        f"- max_zero_loss_pps: `{summary['max_zero_loss_pps'] if summary['max_zero_loss_pps'] is not None else '-'}`",
        f"- max_zero_loss_wire_gbps: `{summary['max_zero_loss_wire_gbps'] if summary['max_zero_loss_wire_gbps'] is not None else '-'}`",
        f"- max_zero_loss_payload_gbps: `{summary['max_zero_loss_payload_gbps'] if summary['max_zero_loss_payload_gbps'] is not None else '-'}`",
        f"- first_overload_pps: `{summary['first_overload_pps'] if summary['first_overload_pps'] is not None else '-'}`",
        "",
        "## Single Packet",
        "",
        "| Run | Status | Mean us | P50 us | P95 us | Max us | Pass Rate |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in summary["single_packet_results"]:
        lines.append(
            "| {run_name} | {status} | {mean:.2f} | {p50:.2f} | {p95:.2f} | {maxv:.2f} | {pass_rate:.2f} |".format(
                run_name=item["run_name"],
                status=item.get("status", "-"),
                mean=float(item.get("mean_completion_us") or 0.0),
                p50=float(item.get("p50_completion_us") or 0.0),
                p95=float(item.get("p95_completion_us") or 0.0),
                maxv=float(item.get("max_completion_us") or 0.0),
                pass_rate=float(item.get("sample_pass_rate") or 0.0),
            )
        )

    lines.extend(
        [
            "",
            "## Rate Scan",
            "",
            "| Run | Offered PPS | Actual PPS | Valid | Drop | Mismatch | Goodput PPS | Wire Gbps | Payload Gbps |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for item in summary["rate_scan_results"]:
        lines.append(
            "| {run_name} | {offered:.0f} | {actual:.2f} | {valid} | {drop} | {mismatch} | {goodput:.2f} | {wire:.6f} | {payload:.6f} |".format(
                run_name=item["run_name"],
                offered=float(item.get("offered_rate_req_per_sec") or 0.0),
                actual=float(item.get("actual_send_rate_req_per_sec") or 0.0),
                valid=("yes" if item.get("measurement_valid") else "no"),
                drop=int(item.get("drop_count", 0) or 0),
                mismatch=int(item.get("mismatch_count", 0) or 0),
                goodput=float(item.get("goodput_result_per_sec") or 0.0),
                wire=float(item.get("wire_goodput_gbps") or 0.0),
                payload=float(item.get("payload_goodput_gbps") or 0.0),
            )
        )

    lines.extend(
        [
            "",
            "## Burst Curve",
            "",
            "| Run | Status | Correctness | Batch Size | Sender | Receiver | Engine | Time us | Req/s | Result/s |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for item in summary["burst_curve_results"]:
        lines.append(
            "| {run_name} | {status} | {correctness} | {batch_size} | {sender} | {receiver} | {engine} | {time_us:.2f} | {reqs:.2f} | {results:.2f} |".format(
                run_name=item["run_name"],
                status=item.get("status", "-"),
                correctness=item.get("correctness_verdict", "-"),
                batch_size=item.get("batch_size", "-"),
                sender=item.get("sender_capture_count", "-"),
                receiver=item.get("receiver_capture_count", "-"),
                engine=item.get("engine_emit_count", "-"),
                time_us=float(item.get("batch_completion_time_us") or 0.0),
                reqs=float(item.get("throughput_req_per_sec") or 0.0),
                results=float(item.get("throughput_result_per_sec") or 0.0),
            )
        )
    return "\n".join(lines) + "\n"


def build_parser():
    parser = argparse.ArgumentParser(description="Assemble round1 final summary from existing metrics outputs.")
    parser.add_argument("--out-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--single-packet-summary", default=str(DEFAULT_SINGLE_PACKET_SUMMARY))
    parser.add_argument("--rate-baseline-summary", default=str(DEFAULT_RATE_BASELINE_SUMMARY))
    parser.add_argument("--rate-extend-root", default=str(DEFAULT_RATE_EXTEND_ROOT))
    parser.add_argument("--burst-summary", default=str(DEFAULT_BURST_SUMMARY))
    return parser


def main():
    args = build_parser().parse_args()
    out_root = Path(args.out_root).resolve()
    single_packet_summary = _load_json(args.single_packet_summary)
    burst_summary = _load_json(args.burst_summary)
    baseline_rate_results = _collect_recomputed_rate_results(args.rate_baseline_summary)
    extend_rate_results = _collect_extend_recomputed_results(args.rate_extend_root)
    all_rate_results = baseline_rate_results + extend_rate_results
    max_zero_loss = _max_zero_loss(all_rate_results)
    first_overload = _first_overload(all_rate_results)

    summary = {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "single_packet_ref": str(Path(args.single_packet_summary).resolve()),
        "rate_scan_baseline_ref": str(Path(args.rate_baseline_summary).resolve()),
        "rate_scan_extend_root": str(Path(args.rate_extend_root).resolve()),
        "burst_curve_ref": str(Path(args.burst_summary).resolve()),
        "single_packet_results": single_packet_summary.get("results", []),
        "rate_scan_results": all_rate_results,
        "burst_curve_results": burst_summary.get("results", []),
        "max_zero_loss_pps": max_zero_loss.get("offered_rate_req_per_sec") if max_zero_loss is not None else None,
        "max_zero_loss_wire_gbps": max_zero_loss.get("wire_goodput_gbps") if max_zero_loss is not None else None,
        "max_zero_loss_payload_gbps": max_zero_loss.get("payload_goodput_gbps") if max_zero_loss is not None else None,
        "first_overload_pps": first_overload.get("offered_rate_req_per_sec") if first_overload is not None else None,
    }
    _write_json(out_root / "summary.json", summary)
    _write_text(out_root / "summary.md", _render_markdown(summary))
    print("summary_json=%s" % (out_root / "summary.json"))
    print("summary_md=%s" % (out_root / "summary.md"))


if __name__ == "__main__":
    raise SystemExit(main())
