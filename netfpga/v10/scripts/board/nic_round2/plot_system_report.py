#!/usr/bin/env python3

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


ROOT_DIR = Path(__file__).resolve().parents[3]
DEFAULT_REPORT_DIR = ROOT_DIR / "bt" / "system_report"
DEFAULT_OUT_DIR = DEFAULT_REPORT_DIR / "figures"

OVERVIEW_FILE = "system_metrics_overview.csv"
SINGLE_PACKET_FILE = "system_single_packet.csv"
FPGA_ENERGY_FILE = "system_fpga_energy.csv"
ASIC_ENERGY_FILE = "system_asic_energy.csv"
BURST_ENERGY_FILE = "system_burst_energy.csv"


def _load_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path)


def _ensure_numeric(df: pd.DataFrame, columns):
    for column in columns:
        df[column] = pd.to_numeric(df[column], errors="coerce")
    return df


def _ensure_boolean(df: pd.DataFrame, columns):
    truthy = {"true", "1", "yes", "y", "t"}
    falsy = {"false", "0", "no", "n", "f", ""}
    for column in columns:
        df[column] = df[column].map(
            lambda value: None
            if pd.isna(value)
            else (
                True
                if str(value).strip().lower() in truthy
                else False
                if str(value).strip().lower() in falsy
                else None
            )
        )
    return df


def _base_style():
    plt.style.use("seaborn-v0_8-whitegrid")


def _new_axes(title: str, xlabel: str, ylabel: str):
    fig, ax = plt.subplots(figsize=(9, 5.5))
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.grid(True, linestyle="--", linewidth=0.6, alpha=0.6)
    return fig, ax


def _save(fig, out_path: Path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


def _bar_positions(count: int, width: float):
    base = list(range(count))
    return base, width


def plot_single_packet_system_completion(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / SINGLE_PACKET_FILE)
    df = _ensure_numeric(
        df,
        [
            "mean_system_e2e_completion_us",
            "p50_system_e2e_completion_us",
            "p95_system_e2e_completion_us",
            "max_system_e2e_completion_us",
        ],
    )
    order = ["offload", "wrong_magic", "wrong_port"]
    df["variant"] = pd.Categorical(df["variant"], categories=order, ordered=True)
    df = df.sort_values("variant")

    fig, ax = _new_axes(
        title="Single-Packet System E2E Completion",
        xlabel="Path Variant",
        ylabel="Completion Time (us)",
    )
    x, width = _bar_positions(len(df), 0.18)
    ax.bar([item - 1.5 * width for item in x], df["mean_system_e2e_completion_us"], width, label="Mean")
    ax.bar([item - 0.5 * width for item in x], df["p50_system_e2e_completion_us"], width, label="P50")
    ax.bar([item + 0.5 * width for item in x], df["p95_system_e2e_completion_us"], width, label="P95")
    ax.bar([item + 1.5 * width for item in x], df["max_system_e2e_completion_us"], width, label="Max")
    ax.set_xticks(x)
    ax.set_xticklabels(df["variant"].astype(str))
    ax.legend()
    _save(fig, out_dir / "single_packet_system_completion_us.png")


def plot_single_packet_energy(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / SINGLE_PACKET_FILE)
    df = _ensure_numeric(
        df,
        [
            "asic_mean_energy_per_inference_j",
        ],
    )
    order = ["offload", "wrong_magic", "wrong_port"]
    df["variant"] = pd.Categorical(df["variant"], categories=order, ordered=True)
    df = df.sort_values("variant")

    fig, ax = _new_axes(
        title="Single-Packet Energy per Inference",
        xlabel="Path Variant",
        ylabel="Energy per Inference (J)",
    )
    x, width = _bar_positions(len(df), 0.48)
    ax.bar(x, df["asic_mean_energy_per_inference_j"], width, label="ASIC Post-route")
    ax.set_xticks(x)
    ax.set_xticklabels(df["variant"].astype(str))
    ax.legend()
    _save(fig, out_dir / "single_packet_energy_per_inference_j.png")


def _merged_rate_energy(report_dir: Path) -> pd.DataFrame:
    fpga = _load_csv(report_dir / FPGA_ENERGY_FILE)
    asic = _load_csv(report_dir / ASIC_ENERGY_FILE)
    fpga = _ensure_numeric(
        fpga,
        [
            "offered_rate_req_per_sec",
            "fpga_energy_per_inference_j",
            "fpga_inferences_per_joule",
            "fpga_payload_gbps_per_watt",
            "drop_ratio",
        ],
    )
    asic = _ensure_numeric(
        asic,
        [
            "offered_rate_req_per_sec",
            "asic_energy_per_inference_j",
            "asic_inferences_per_joule",
            "asic_payload_gbps_per_watt",
        ],
    )
    fpga = _ensure_boolean(fpga, ["measurement_valid"])
    asic = _ensure_boolean(asic, ["measurement_valid"])
    merged = fpga.merge(
        asic[
            [
                "offered_rate_req_per_sec",
                "asic_energy_per_inference_j",
                "asic_inferences_per_joule",
                "asic_payload_gbps_per_watt",
            ]
        ],
        on="offered_rate_req_per_sec",
        how="inner",
    )
    return merged.sort_values("offered_rate_req_per_sec")


def plot_rate_scan_energy(report_dir: Path, out_dir: Path):
    df = _merged_rate_energy(report_dir)
    valid = df[df["measurement_valid"] == True].copy()
    x = valid["offered_rate_req_per_sec"]

    fig, ax = _new_axes(
        title="Rate Scan Energy per Inference",
        xlabel="Offered Rate (req/s)",
        ylabel="Energy per Inference (J)",
    )
    ax.plot(x, valid["asic_energy_per_inference_j"], marker="o", linewidth=2, label="ASIC Post-route")
    ax.legend()
    _save(fig, out_dir / "rate_scan_energy_per_inference_j.png")

    fig, ax = _new_axes(
        title="Rate Scan Inferences per Joule",
        xlabel="Offered Rate (req/s)",
        ylabel="Inferences per Joule",
    )
    ax.plot(x, valid["asic_inferences_per_joule"], marker="o", linewidth=2, label="ASIC Post-route")
    ax.legend()
    _save(fig, out_dir / "rate_scan_inferences_per_joule.png")

    fig, ax = _new_axes(
        title="Rate Scan Payload Gbps per Watt",
        xlabel="Offered Rate (req/s)",
        ylabel="Payload Gbps per Watt",
    )
    ax.plot(x, valid["asic_payload_gbps_per_watt"], marker="o", linewidth=2, label="ASIC Post-route")
    ax.legend()
    _save(fig, out_dir / "rate_scan_payload_gbps_per_watt.png")


def plot_rate_scan_validity(report_dir: Path, out_dir: Path):
    df = _merged_rate_energy(report_dir)
    overview = _load_csv(report_dir / OVERVIEW_FILE)
    overview = _ensure_numeric(overview, ["max_zero_loss_pps", "first_overload_pps"])
    x = df["offered_rate_req_per_sec"]

    fig, ax = _new_axes(
        title="Rate Scan Validity and Drop Ratio",
        xlabel="Offered Rate (req/s)",
        ylabel="Drop Ratio",
    )
    ax.plot(x, df["drop_ratio"], marker="o", linewidth=2, label="Drop Ratio", color="#c44e52")
    invalid = df[df["measurement_valid"] == False]
    if not invalid.empty:
        ax.scatter(
            invalid["offered_rate_req_per_sec"],
            invalid["drop_ratio"].fillna(0.0),
            color="#222222",
            marker="x",
            s=80,
            label="Invalid Point",
            zorder=5,
        )
    if not overview.empty:
        max_zero_loss = overview.iloc[0]["max_zero_loss_pps"]
        first_overload = overview.iloc[0]["first_overload_pps"]
        if pd.notna(max_zero_loss):
            ax.axvline(max_zero_loss, linestyle="--", linewidth=1.5, color="#4c72b0", label="Max Zero-Loss")
        if pd.notna(first_overload):
            ax.axvline(first_overload, linestyle="--", linewidth=1.5, color="#dd8452", label="First Overload")
    ax.legend()
    _save(fig, out_dir / "rate_scan_energy_validity.png")


def plot_burst_energy(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / BURST_ENERGY_FILE)
    df = _ensure_numeric(
        df,
        [
            "batch_size",
            "asic_batch_energy_per_inference_j",
            "asic_batch_energy_j",
            "batch_completion_time_us",
            "throughput_req_per_sec",
            "throughput_result_per_sec",
        ],
    ).sort_values("batch_size")
    x = df["batch_size"]

    fig, ax = _new_axes(
        title="Burst Energy per Inference",
        xlabel="Batch Size",
        ylabel="Energy per Inference (J)",
    )
    ax.plot(x, df["asic_batch_energy_per_inference_j"], marker="o", linewidth=2, label="ASIC Post-route")
    ax.legend()
    _save(fig, out_dir / "burst_energy_per_inference_j.png")

    fig, ax = _new_axes(
        title="Burst Total Energy",
        xlabel="Batch Size",
        ylabel="Batch Energy (J)",
    )
    ax.plot(x, df["asic_batch_energy_j"], marker="o", linewidth=2, label="ASIC Post-route")
    ax.legend()
    _save(fig, out_dir / "burst_total_energy_j.png")

    fig, axes = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    axes[0].set_title("Burst Completion and Throughput")
    axes[0].plot(x, df["batch_completion_time_us"], marker="o", linewidth=2, label="Completion Time", color="#4c72b0")
    axes[0].set_ylabel("Completion Time (us)")
    axes[0].grid(True, linestyle="--", linewidth=0.6, alpha=0.6)
    axes[0].legend()

    axes[1].plot(x, df["throughput_req_per_sec"], marker="o", linewidth=2, label="Request Throughput", color="#55a868")
    axes[1].plot(x, df["throughput_result_per_sec"], marker="o", linewidth=2, label="Result Throughput", color="#c44e52")
    axes[1].set_xlabel("Batch Size")
    axes[1].set_ylabel("Throughput (req/s)")
    axes[1].grid(True, linestyle="--", linewidth=0.6, alpha=0.6)
    axes[1].legend()
    _save(fig, out_dir / "burst_completion_and_throughput.png")


def build_parser():
    parser = argparse.ArgumentParser(description="Generate English-only charts from bt/system_report CSV files.")
    parser.add_argument("--report-dir", default=str(DEFAULT_REPORT_DIR))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    return parser


def main():
    args = build_parser().parse_args()
    report_dir = Path(args.report_dir).resolve()
    out_dir = Path(args.out_dir).resolve()

    _base_style()
    plot_single_packet_system_completion(report_dir, out_dir)
    plot_single_packet_energy(report_dir, out_dir)
    plot_rate_scan_energy(report_dir, out_dir)
    plot_rate_scan_validity(report_dir, out_dir)
    plot_burst_energy(report_dir, out_dir)

    print(f"Generated figures in {out_dir}")


if __name__ == "__main__":
    main()
