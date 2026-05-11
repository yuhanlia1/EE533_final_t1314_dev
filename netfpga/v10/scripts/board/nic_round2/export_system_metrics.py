#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[3]
DEFAULT_SOURCE_SUMMARY = ROOT_DIR / "bt" / "round1_final" / "summary.json"
DEFAULT_REPORT_DIR = ROOT_DIR / "bt" / "system_report"
DEFAULT_FPGA_UTILIZATION = ROOT_DIR / "pd" / "fpga_report" / "nf2_top.srp"
DEFAULT_FPGA_MODEL = ROOT_DIR / "bt" / "power_models" / "fpga_resource_model.json"
DEFAULT_ASIC_POWER = ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "reports" / "4_postroute_power.rpt"
DATASET_VERSION = "system_metrics_v2"


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def _write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _normalize_value(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return value


def _write_csv(path: Path, fieldnames, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: _normalize_value(row.get(key)) for key in fieldnames})


def _safe_div(numerator, denominator):
    if numerator is None or denominator is None:
        return None
    if float(denominator) == 0.0:
        return None
    return float(numerator) / float(denominator)


def _energy_from_power_and_rate(power_w, rate_per_second):
    if power_w is None or rate_per_second is None:
        return None
    if float(rate_per_second) <= 0.0:
        return None
    return float(power_w) / float(rate_per_second)


def _energy_from_power_and_time(power_w, duration_seconds):
    if power_w is None or duration_seconds is None:
        return None
    if float(duration_seconds) < 0.0:
        return None
    return float(power_w) * float(duration_seconds)


def _float_or_none(value):
    if value is None or value == "":
        return None
    return float(value)


def parse_fpga_utilization_srp(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")

    def _extract(pattern: str, label: str) -> int:
        match = re.search(pattern, text)
        if not match:
            raise ValueError("missing FPGA utilization field: %s" % label)
        return int(match.group(1))

    device_match = re.search(r"Selected Device\s*:\s*([^\n]+)", text)
    if not device_match:
        raise ValueError("missing FPGA selected device in %s" % path)

    return {
        "device": device_match.group(1).strip(),
        "slices": _extract(r"Number of Slices:\s+(\d+)\s+out of", "slices"),
        "slice_flip_flops": _extract(r"Number of Slice Flip Flops:\s+(\d+)\s+out of", "slice_flip_flops"),
        "lut4": _extract(r"Number of 4 input LUTs:\s+(\d+)\s+out of", "lut4"),
        "lut_logic": _extract(r"Number used as logic:\s+(\d+)", "lut_logic"),
        "lut_shift_registers": _extract(r"Number used as Shift registers:\s+(\d+)", "lut_shift_registers"),
        "lut_rams": _extract(r"Number used as RAMs:\s+(\d+)", "lut_rams"),
        "bonded_iobs": _extract(r"Number of bonded IOBs:\s+(\d+)\s+out of", "bonded_iobs"),
        "brams": _extract(r"Number of BRAMs:\s+(\d+)\s+out of", "brams"),
        "mult18x18": _extract(r"Number of MULT18X18s:\s+(\d+)\s+out of", "mult18x18"),
        "gclks": _extract(r"Number of GCLKs:\s+(\d+)\s+out of", "gclks"),
        "dcms": _extract(r"Number of DCMs:\s+(\d+)\s+out of", "dcms"),
    }


def parse_asic_power_report(path: Path):
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
        raise ValueError("missing Total row in ASIC power report %s" % path)
    return {
        "groups": groups,
        "total_power_w": groups["Total"]["total_w"],
        "internal_power_w": groups["Total"]["internal_w"],
        "switching_power_w": groups["Total"]["switching_w"],
        "leakage_power_w": groups["Total"]["leakage_w"],
    }


def build_fpga_theoretical_power(utilization, model):
    coefficients = dict(model.get("coefficients", {}))
    component_inputs = {
        "lut4": utilization["lut4"],
        "slice_flip_flops": utilization["slice_flip_flops"],
        "brams": utilization["brams"],
        "mult18x18": utilization["mult18x18"],
        "bonded_iobs": utilization["bonded_iobs"],
        "gclks": utilization["gclks"],
        "dcms": utilization["dcms"],
    }
    component_names = {
        "lut4": "lut4_w",
        "slice_flip_flops": "slice_flip_flops_w",
        "brams": "brams_w",
        "mult18x18": "mult18x18_w",
        "bonded_iobs": "bonded_iobs_w",
        "gclks": "gclks_w",
        "dcms": "dcms_w",
    }
    power_components = {}
    total_power_w = 0.0
    for resource_name, count in component_inputs.items():
        coefficient_name = component_names[resource_name]
        coeff = float(coefficients[coefficient_name])
        component_power = float(count) * coeff
        power_components[resource_name] = {
            "count": int(count),
            "coefficient_w_per_resource": coeff,
            "power_w": component_power,
        }
        total_power_w += component_power
    return {
        "model_name": model.get("model_name"),
        "model_status": model.get("model_status"),
        "coefficient_source": model.get("coefficient_source"),
        "power_units": model.get("power_units"),
        "device_family": model.get("device_family"),
        "utilization": utilization,
        "components": power_components,
        "total_power_w": total_power_w,
    }


def _single_packet_rows(summary, fpga_power_w, asic_power_w):
    rows = []
    for item in summary.get("single_packet_results", []):
        mean_us = _float_or_none(item.get("mean_completion_us"))
        p50_us = _float_or_none(item.get("p50_completion_us"))
        p95_us = _float_or_none(item.get("p95_completion_us"))
        max_us = _float_or_none(item.get("max_completion_us"))
        rows.append(
            {
                "run_name": item.get("run_name"),
                "variant": item.get("single_packet_variant"),
                "status": item.get("status"),
                "sample_pass_rate": item.get("sample_pass_rate"),
                "timing_mode": item.get("timing_mode"),
                "latency_status": item.get("latency_status"),
                "mean_system_e2e_completion_us": mean_us,
                "p50_system_e2e_completion_us": p50_us,
                "p95_system_e2e_completion_us": p95_us,
                "max_system_e2e_completion_us": max_us,
                "fpga_theoretical_power_w": fpga_power_w,
                "asic_postroute_total_power_w": asic_power_w,
                "fpga_mean_energy_per_inference_j": _energy_from_power_and_time(fpga_power_w, _safe_div(mean_us, 1e6)),
                "asic_mean_energy_per_inference_j": _energy_from_power_and_time(asic_power_w, _safe_div(mean_us, 1e6)),
            }
        )
    return rows


def _rate_scan_rows(summary, fpga_power_w, asic_power_w):
    rows = []
    for item in sorted(summary.get("rate_scan_results", []), key=lambda row: float(row.get("offered_rate_req_per_sec") or 0.0)):
        measurement_valid = bool(item.get("measurement_valid"))
        goodput = _float_or_none(item.get("goodput_result_per_sec"))
        payload_gbps = _float_or_none(item.get("payload_goodput_gbps"))
        wire_gbps = _float_or_none(item.get("wire_goodput_gbps"))
        fpga_energy = _energy_from_power_and_rate(fpga_power_w, goodput) if measurement_valid else None
        asic_energy = _energy_from_power_and_rate(asic_power_w, goodput) if measurement_valid else None
        rows.append(
            {
                "run_name": item.get("run_name"),
                "offered_rate_req_per_sec": item.get("offered_rate_req_per_sec"),
                "actual_send_rate_req_per_sec": item.get("actual_send_rate_req_per_sec"),
                "goodput_result_per_sec": goodput,
                "wire_goodput_gbps": wire_gbps,
                "payload_goodput_gbps": payload_gbps,
                "measurement_valid": measurement_valid,
                "drop_count": item.get("drop_count"),
                "drop_ratio": item.get("drop_ratio"),
                "mismatch_count": item.get("mismatch_count"),
                "rate_error_ratio": item.get("rate_error_ratio"),
                "pipeline_verdict": item.get("pipeline_verdict"),
                "correctness_verdict": item.get("correctness_verdict"),
                "fpga_theoretical_power_w": fpga_power_w,
                "asic_postroute_total_power_w": asic_power_w,
                "fpga_energy_per_inference_j": fpga_energy,
                "asic_energy_per_inference_j": asic_energy,
                "fpga_energy_per_packet_j": fpga_energy,
                "asic_energy_per_packet_j": asic_energy,
                "fpga_inferences_per_joule": _safe_div(goodput, fpga_power_w) if measurement_valid else None,
                "asic_inferences_per_joule": _safe_div(goodput, asic_power_w) if measurement_valid else None,
                "fpga_payload_gbps_per_watt": _safe_div(payload_gbps, fpga_power_w) if measurement_valid else None,
                "asic_payload_gbps_per_watt": _safe_div(payload_gbps, asic_power_w) if measurement_valid else None,
                "receiver_span_seconds": item.get("receiver_span_seconds"),
                "send_span_seconds": item.get("send_span_seconds"),
            }
        )
    return rows


def _burst_rows(summary, fpga_power_w, asic_power_w):
    rows = []
    for item in sorted(summary.get("burst_curve_results", []), key=lambda row: int(row.get("batch_size") or 0)):
        completion_us = _float_or_none(item.get("batch_completion_time_us"))
        completion_s = _safe_div(completion_us, 1e6)
        batch_size = int(item.get("batch_size") or 0)
        fpga_batch_energy = _energy_from_power_and_time(fpga_power_w, completion_s)
        asic_batch_energy = _energy_from_power_and_time(asic_power_w, completion_s)
        rows.append(
            {
                "run_name": item.get("run_name"),
                "batch_size": batch_size,
                "status": item.get("status"),
                "pipeline_verdict": item.get("pipeline_verdict"),
                "correctness_verdict": item.get("correctness_verdict"),
                "batch_completion_time_us": completion_us,
                "throughput_req_per_sec": item.get("throughput_req_per_sec"),
                "throughput_result_per_sec": item.get("throughput_result_per_sec"),
                "sender_capture_count": item.get("sender_capture_count"),
                "receiver_capture_count": item.get("receiver_capture_count"),
                "engine_emit_count": item.get("engine_emit_count"),
                "offload_accept_count": item.get("offload_accept_count"),
                "compute_done_count": item.get("compute_done_count"),
                "fpga_theoretical_power_w": fpga_power_w,
                "asic_postroute_total_power_w": asic_power_w,
                "fpga_batch_energy_j": fpga_batch_energy,
                "asic_batch_energy_j": asic_batch_energy,
                "fpga_batch_energy_per_inference_j": _safe_div(fpga_batch_energy, batch_size),
                "asic_batch_energy_per_inference_j": _safe_div(asic_batch_energy, batch_size),
            }
        )
    return rows


def _find_rate_row(rows, offered_pps):
    for row in rows:
        if float(row.get("offered_rate_req_per_sec") or 0.0) == float(offered_pps):
            return row
    return None


def _overview_rows(summary, source_summary_path, fpga_model_path, asic_power_path, fpga_power, asic_power, rate_rows):
    max_zero_loss_pps = summary.get("max_zero_loss_pps")
    max_zero_loss_row = _find_rate_row(rate_rows, max_zero_loss_pps)
    return [
        {
            "dataset_version": DATASET_VERSION,
            "source_summary_json": str(source_summary_path.resolve()),
            "fpga_model_json": str(fpga_model_path.resolve()),
            "asic_power_report": str(asic_power_path.resolve()),
            "created_at": summary.get("created_at"),
            "fpga_model_status": fpga_power.get("model_status"),
            "fpga_theoretical_power_w": fpga_power.get("total_power_w"),
            "asic_postroute_total_power_w": asic_power.get("total_power_w"),
            "max_zero_loss_pps": max_zero_loss_pps,
            "max_zero_loss_wire_gbps": summary.get("max_zero_loss_wire_gbps"),
            "max_zero_loss_payload_gbps": summary.get("max_zero_loss_payload_gbps"),
            "first_overload_pps": summary.get("first_overload_pps"),
            "fpga_energy_per_inference_at_max_zero_loss_j": max_zero_loss_row.get("fpga_energy_per_inference_j") if max_zero_loss_row else None,
            "asic_energy_per_inference_at_max_zero_loss_j": max_zero_loss_row.get("asic_energy_per_inference_j") if max_zero_loss_row else None,
            "fpga_inferences_per_joule_at_max_zero_loss": max_zero_loss_row.get("fpga_inferences_per_joule") if max_zero_loss_row else None,
            "asic_inferences_per_joule_at_max_zero_loss": max_zero_loss_row.get("asic_inferences_per_joule") if max_zero_loss_row else None,
        }
    ]


def _summary_json(summary, source_summary_path, fpga_model_path, asic_power_path, fpga_power, asic_power, overview_rows, single_rows, rate_rows, burst_rows):
    return {
        "schema_version": "system_metrics_v2",
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "source_summary_json": str(source_summary_path.resolve()),
        "fpga_model_json": str(fpga_model_path.resolve()),
        "asic_power_report": str(asic_power_path.resolve()),
        "overview": overview_rows[0],
        "fpga_power_model": fpga_power,
        "asic_power_model": asic_power,
        "single_packet_system_results": single_rows,
        "rate_scan_energy_results": rate_rows,
        "burst_energy_results": burst_rows,
    }


def _render_summary_markdown(summary_json):
    overview = summary_json["overview"]
    lines = [
        "# V2 System Metrics Summary",
        "",
        "- source_summary_json: `%s`" % summary_json["source_summary_json"],
        "- fpga_model_json: `%s`" % summary_json["fpga_model_json"],
        "- asic_power_report: `%s`" % summary_json["asic_power_report"],
        "- fpga_theoretical_power_w: `%.6f`" % overview["fpga_theoretical_power_w"],
        "- asic_postroute_total_power_w: `%.6f`" % overview["asic_postroute_total_power_w"],
        "- max_zero_loss_pps: `%s`" % overview["max_zero_loss_pps"],
        "- first_overload_pps: `%s`" % overview["first_overload_pps"],
        "",
        "## Single Packet System E2E",
        "",
        "| Variant | Mean us | P50 us | P95 us | Max us | FPGA J/inference | ASIC J/inference |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in summary_json["single_packet_system_results"]:
        lines.append(
            "| {variant} | {mean:.2f} | {p50:.2f} | {p95:.2f} | {maxv:.2f} | {fpga:.9f} | {asic:.9f} |".format(
                variant=row["variant"],
                mean=float(row["mean_system_e2e_completion_us"]),
                p50=float(row["p50_system_e2e_completion_us"]),
                p95=float(row["p95_system_e2e_completion_us"]),
                maxv=float(row["max_system_e2e_completion_us"]),
                fpga=float(row["fpga_mean_energy_per_inference_j"]),
                asic=float(row["asic_mean_energy_per_inference_j"]),
            )
        )
    lines.extend(
        [
            "",
            "## Rate Scan Energy",
            "",
            "| Offered PPS | Valid | Goodput PPS | Payload Gbps | FPGA J/inference | ASIC J/inference | FPGA inf/J | ASIC inf/J |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in summary_json["rate_scan_energy_results"]:
        lines.append(
            "| {pps:g} | {valid} | {goodput} | {gbps} | {fpga} | {asic} | {fpga_ipj} | {asic_ipj} |".format(
                pps=float(row["offered_rate_req_per_sec"]),
                valid="yes" if row["measurement_valid"] else "no",
                goodput=("%.2f" % float(row["goodput_result_per_sec"])) if row["goodput_result_per_sec"] is not None else "-",
                gbps=("%.6f" % float(row["payload_goodput_gbps"])) if row["payload_goodput_gbps"] is not None else "-",
                fpga=("%.9f" % float(row["fpga_energy_per_inference_j"])) if row["fpga_energy_per_inference_j"] is not None else "-",
                asic=("%.9f" % float(row["asic_energy_per_inference_j"])) if row["asic_energy_per_inference_j"] is not None else "-",
                fpga_ipj=("%.2f" % float(row["fpga_inferences_per_joule"])) if row["fpga_inferences_per_joule"] is not None else "-",
                asic_ipj=("%.2f" % float(row["asic_inferences_per_joule"])) if row["asic_inferences_per_joule"] is not None else "-",
            )
        )
    lines.extend(
        [
            "",
            "## Burst Energy",
            "",
            "| Batch | Time us | Correctness | FPGA batch J | ASIC batch J | FPGA J/inference | ASIC J/inference |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in summary_json["burst_energy_results"]:
        lines.append(
            "| {batch} | {time:.2f} | {correctness} | {fpga_batch:.9f} | {asic_batch:.9f} | {fpga_inf:.9f} | {asic_inf:.9f} |".format(
                batch=int(row["batch_size"]),
                time=float(row["batch_completion_time_us"]),
                correctness=row["correctness_verdict"],
                fpga_batch=float(row["fpga_batch_energy_j"]),
                asic_batch=float(row["asic_batch_energy_j"]),
                fpga_inf=float(row["fpga_batch_energy_per_inference_j"]),
                asic_inf=float(row["asic_batch_energy_per_inference_j"]),
            )
        )
    return "\n".join(lines) + "\n"


def _write_readme(report_dir: Path, source_summary_path: Path, fpga_model_path: Path, asic_power_path: Path) -> None:
    text = f"""# V2 System Metrics Export

- source_summary_json: `{source_summary_path.resolve()}`
- fpga_model_json: `{fpga_model_path.resolve()}`
- asic_power_report: `{asic_power_path.resolve()}`
- generated_at: `{datetime.now().isoformat(timespec="seconds")}`

## Files

- `system_metrics_overview.csv`
  - one-row V2 headline summary
- `system_single_packet.csv`
  - coarse system-level end-to-end completion for `offload`, `wrong_magic`, and `wrong_port`
- `system_fpga_energy.csv`
  - FPGA resource-based theoretical energy derived from `v1` operating points
- `system_asic_energy.csv`
  - ASIC post-route estimated energy derived from `v1` operating points
- `system_burst_energy.csv`
  - burst energy estimates for `batch8/16/32/64`
- `summary.json`
  - structured V2 system-metrics export
- `summary.md`
  - human-readable V2 summary

## Notes

- `system_single_packet.csv` uses coarse controller-observed completion, not strict network RTT.
- FPGA power is a `resource_based_theoretical` estimate derived from utilization in `pd/fpga_report/nf2_top.srp`.
- The FPGA model uses explicit configurable coefficients and is currently a provisional estimate, not measured power.
- ASIC power is derived from the post-route power report in `pd/asic_report/pnr/user_top/reports/4_postroute_power.rpt`.
- Energy-per-inference and energy-per-packet are derived from power and measured throughput/completion data from `bt/round1_final/summary.json`.
"""
    _write_text(report_dir / "README.md", text)


def build_parser():
    parser = argparse.ArgumentParser(description="Export V2 system-level metrics from existing round1 final artifacts")
    parser.add_argument("--source-summary", default=str(DEFAULT_SOURCE_SUMMARY))
    parser.add_argument("--out-dir", default=str(DEFAULT_REPORT_DIR))
    parser.add_argument("--fpga-srp", default=str(DEFAULT_FPGA_UTILIZATION))
    parser.add_argument("--fpga-model", default=str(DEFAULT_FPGA_MODEL))
    parser.add_argument("--asic-power-report", default=str(DEFAULT_ASIC_POWER))
    return parser


def main():
    args = build_parser().parse_args()
    source_summary_path = Path(args.source_summary).resolve()
    out_dir = Path(args.out_dir).resolve()
    fpga_srp_path = Path(args.fpga_srp).resolve()
    fpga_model_path = Path(args.fpga_model).resolve()
    asic_power_path = Path(args.asic_power_report).resolve()

    summary = _load_json(source_summary_path)
    fpga_model = _load_json(fpga_model_path)
    fpga_utilization = parse_fpga_utilization_srp(fpga_srp_path)
    asic_power = parse_asic_power_report(asic_power_path)
    fpga_power = build_fpga_theoretical_power(fpga_utilization, fpga_model)

    fpga_power_w = fpga_power["total_power_w"]
    asic_power_w = asic_power["total_power_w"]
    single_rows = _single_packet_rows(summary, fpga_power_w, asic_power_w)
    rate_rows = _rate_scan_rows(summary, fpga_power_w, asic_power_w)
    burst_rows = _burst_rows(summary, fpga_power_w, asic_power_w)
    overview_rows = _overview_rows(
        summary,
        source_summary_path,
        fpga_model_path,
        asic_power_path,
        fpga_power,
        asic_power,
        rate_rows,
    )

    _write_csv(
        out_dir / "system_metrics_overview.csv",
        [
            "dataset_version",
            "source_summary_json",
            "fpga_model_json",
            "asic_power_report",
            "created_at",
            "fpga_model_status",
            "fpga_theoretical_power_w",
            "asic_postroute_total_power_w",
            "max_zero_loss_pps",
            "max_zero_loss_wire_gbps",
            "max_zero_loss_payload_gbps",
            "first_overload_pps",
            "fpga_energy_per_inference_at_max_zero_loss_j",
            "asic_energy_per_inference_at_max_zero_loss_j",
            "fpga_inferences_per_joule_at_max_zero_loss",
            "asic_inferences_per_joule_at_max_zero_loss",
        ],
        overview_rows,
    )
    _write_csv(
        out_dir / "system_single_packet.csv",
        [
            "run_name",
            "variant",
            "status",
            "sample_pass_rate",
            "timing_mode",
            "latency_status",
            "mean_system_e2e_completion_us",
            "p50_system_e2e_completion_us",
            "p95_system_e2e_completion_us",
            "max_system_e2e_completion_us",
            "fpga_theoretical_power_w",
            "asic_postroute_total_power_w",
            "fpga_mean_energy_per_inference_j",
            "asic_mean_energy_per_inference_j",
        ],
        single_rows,
    )
    _write_csv(
        out_dir / "system_fpga_energy.csv",
        [
            "run_name",
            "offered_rate_req_per_sec",
            "actual_send_rate_req_per_sec",
            "goodput_result_per_sec",
            "payload_goodput_gbps",
            "measurement_valid",
            "drop_count",
            "drop_ratio",
            "mismatch_count",
            "rate_error_ratio",
            "fpga_theoretical_power_w",
            "fpga_energy_per_inference_j",
            "fpga_energy_per_packet_j",
            "fpga_inferences_per_joule",
            "fpga_payload_gbps_per_watt",
            "pipeline_verdict",
            "correctness_verdict",
        ],
        rate_rows,
    )
    _write_csv(
        out_dir / "system_asic_energy.csv",
        [
            "run_name",
            "offered_rate_req_per_sec",
            "actual_send_rate_req_per_sec",
            "goodput_result_per_sec",
            "payload_goodput_gbps",
            "measurement_valid",
            "drop_count",
            "drop_ratio",
            "mismatch_count",
            "rate_error_ratio",
            "asic_postroute_total_power_w",
            "asic_energy_per_inference_j",
            "asic_energy_per_packet_j",
            "asic_inferences_per_joule",
            "asic_payload_gbps_per_watt",
            "pipeline_verdict",
            "correctness_verdict",
        ],
        rate_rows,
    )
    _write_csv(
        out_dir / "system_burst_energy.csv",
        [
            "run_name",
            "batch_size",
            "status",
            "pipeline_verdict",
            "correctness_verdict",
            "batch_completion_time_us",
            "throughput_req_per_sec",
            "throughput_result_per_sec",
            "sender_capture_count",
            "receiver_capture_count",
            "engine_emit_count",
            "offload_accept_count",
            "compute_done_count",
            "fpga_theoretical_power_w",
            "asic_postroute_total_power_w",
            "fpga_batch_energy_j",
            "asic_batch_energy_j",
            "fpga_batch_energy_per_inference_j",
            "asic_batch_energy_per_inference_j",
        ],
        burst_rows,
    )

    summary_json = _summary_json(
        summary,
        source_summary_path,
        fpga_model_path,
        asic_power_path,
        fpga_power,
        asic_power,
        overview_rows,
        single_rows,
        rate_rows,
        burst_rows,
    )
    _write_json(out_dir / "summary.json", summary_json)
    _write_text(out_dir / "summary.md", _render_summary_markdown(summary_json))
    _write_readme(out_dir, source_summary_path, fpga_model_path, asic_power_path)


if __name__ == "__main__":
    main()
