#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_SYSTEM_REPORT_SUMMARY = ROOT_DIR / "bt" / "system_report" / "summary.json"
DEFAULT_RATE_SCAN_CSV = ROOT_DIR / "bt" / "report" / "round1_rate_scan.csv"
DEFAULT_VALIDITY_FIGURE = ROOT_DIR / "bt" / "system_report" / "figures" / "rate_scan_energy_validity.png"
DEFAULT_PAYLOAD_FIGURE = ROOT_DIR / "bt" / "system_report" / "figures" / "rate_scan_payload_gbps_per_watt.png"
DEFAULT_POWER_REPORT = ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "reports" / "4_postroute_power.rpt"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_asic_power_report(path: Path) -> dict:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    groups = {}
    pattern = re.compile(
        r"^\s*([A-Za-z]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)"
    )
    for line in lines:
        match = pattern.match(line)
        if not match:
            continue
        group = match.group(1)
        groups[group] = {
            "internal_w": float(match.group(2)),
            "switching_w": float(match.group(3)),
            "leakage_w": float(match.group(4)),
            "total_w": float(match.group(5)),
        }
    if "Total" not in groups:
        raise SystemExit(f"missing Total row in ASIC power report: {path}")
    return {
        "groups": groups,
        "total_power_w": groups["Total"]["total_w"],
        "internal_power_w": groups["Total"]["internal_w"],
        "switching_power_w": groups["Total"]["switching_w"],
        "leakage_power_w": groups["Total"]["leakage_w"],
    }


def _format_rate(value) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.1f} pps"


def _format_ratio(value) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.6f}"


def _format_power(value) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.4e} W"


def _build_throughput_summary(summary_path: Path) -> dict:
    report = _load_json(summary_path)
    overview = report.get("overview", {})
    return {
        "demo_name": "other_pros_throughput",
        "source_summary_json": str(summary_path.resolve()),
        "max_zero_loss_pps": overview.get("max_zero_loss_pps"),
        "first_overload_pps": overview.get("first_overload_pps"),
        "max_zero_loss_payload_gbps": overview.get("max_zero_loss_payload_gbps"),
        "max_zero_loss_wire_gbps": overview.get("max_zero_loss_wire_gbps"),
        "figure_validity": str(DEFAULT_VALIDITY_FIGURE.resolve()),
        "figure_payload_efficiency": str(DEFAULT_PAYLOAD_FIGURE.resolve()),
        "rate_scan_csv": str(DEFAULT_RATE_SCAN_CSV.resolve()),
        "display_statement": (
            "Zero-loss operation remains stable through the measured safe region and overload first appears "
            "at the first invalid rate-scan point."
        ),
    }


def _build_power_summary(power_report_path: Path) -> dict:
    parsed = _parse_asic_power_report(power_report_path)
    return {
        "demo_name": "other_pros_power",
        "power_report": str(power_report_path.resolve()),
        "total_power_w": parsed["total_power_w"],
        "internal_power_w": parsed["internal_power_w"],
        "switching_power_w": parsed["switching_power_w"],
        "leakage_power_w": parsed["leakage_power_w"],
        "power_source": "OpenROAD post-route power report",
        "caveat": "Smoke/demo-grade post-route power; workload-driven activity was not injected for this demo.",
    }


def _print_throughput_block(summary: dict) -> None:
    print("=" * 100)
    print("RSU Other Pros Demo")
    print("=" * 100)
    print("Focus      : High-Flow Stability")
    print("Goal       : Show when sustained offered load first stops being zero-loss.")
    print()
    print(f"  Max Zero-Loss Rate : {_format_rate(summary['max_zero_loss_pps'])}")
    print(f"  First Overload Rate: {_format_rate(summary['first_overload_pps'])}")
    print()
    print("  Threshold Evidence:")
    print(f"    rate_scan_csv             : {summary['rate_scan_csv']}")
    print(f"    max_zero_loss_payload_gbps: {_format_ratio(summary['max_zero_loss_payload_gbps'])}")
    print(f"    max_zero_loss_wire_gbps   : {_format_ratio(summary['max_zero_loss_wire_gbps'])}")
    print()
    print("  Recommended Figure:")
    print(f"    validity_plot : {summary['figure_validity']}")
    print(f"    payload_plot  : {summary['figure_payload_efficiency']}")
    print()
    print(f"  Statement  : {summary['display_statement']}")


def _print_power_block(summary: dict) -> None:
    print("=" * 100)
    print("RSU Other Pros Demo")
    print("=" * 100)
    print("Focus      : Power")
    print("Goal       : Show the current ASIC post-route power snapshot used by the demo deck.")
    print()
    print(f"  ASIC Post-route Total Power : {_format_power(summary['total_power_w'])}")
    print(f"  Internal Power              : {_format_power(summary['internal_power_w'])}")
    print(f"  Switching Power             : {_format_power(summary['switching_power_w'])}")
    print(f"  Leakage Power               : {_format_power(summary['leakage_power_w'])}")
    print()
    print(f"  Power Source : {summary['power_source']}")
    print(f"  Report Path  : {summary['power_report']}")
    print(f"  Caveat       : {summary['caveat']}")


def throughput_command(args: argparse.Namespace) -> int:
    summary = _build_throughput_summary(Path(args.summary_json).resolve())
    _print_throughput_block(summary)
    return 0


def power_command(args: argparse.Namespace) -> int:
    summary = _build_power_summary(Path(args.power_report).resolve())
    _print_power_block(summary)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Thin wrappers for the Other Pros demo section.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    throughput = subparsers.add_parser("throughput", help="Print the high-flow zero-loss vs overload threshold summary.")
    throughput.add_argument(
        "--summary-json",
        default=str(DEFAULT_SYSTEM_REPORT_SUMMARY),
        help="System report summary JSON with max_zero_loss_pps and first_overload_pps.",
    )
    throughput.set_defaults(func=throughput_command)

    power = subparsers.add_parser("power", help="Print the ASIC post-route power summary.")
    power.add_argument(
        "--power-report",
        default=str(DEFAULT_POWER_REPORT),
        help="ASIC post-route power report path.",
    )
    power.set_defaults(func=power_command)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
