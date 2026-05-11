#!/usr/bin/env python3

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


ROOT_DIR = Path(__file__).resolve().parents[3]
DEFAULT_REPORT_DIR = ROOT_DIR / "bt" / "report"
DEFAULT_OUT_DIR = DEFAULT_REPORT_DIR / "figures"

SINGLE_PACKET_FILE = "round1_single_packet.csv"
RATE_SCAN_FILE = "round1_rate_scan.csv"
BURST_CURVE_FILE = "round1_burst_curve.csv"


def _load_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path)


def _ensure_numeric(df: pd.DataFrame, columns):
    for column in columns:
        df[column] = pd.to_numeric(df[column], errors="coerce")
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


def plot_single_packet(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / SINGLE_PACKET_FILE)
    df = _ensure_numeric(
        df,
        [
            "mean_completion_us",
            "p50_completion_us",
            "p95_completion_us",
            "max_completion_us",
        ],
    )
    order = ["offload", "wrong_magic", "wrong_port"]
    df["variant"] = pd.Categorical(df["variant"], categories=order, ordered=True)
    df = df.sort_values("variant")

    fig, ax = _new_axes(
        title="Single-Packet Relative Completion Time",
        xlabel="Path Variant",
        ylabel="Completion Time (us)",
    )
    x = df["variant"].astype(str)
    ax.plot(x, df["mean_completion_us"], marker="o", linewidth=2, label="Mean")
    ax.plot(x, df["p50_completion_us"], marker="o", linewidth=2, label="P50")
    ax.plot(x, df["p95_completion_us"], marker="o", linewidth=2, label="P95")
    ax.plot(x, df["max_completion_us"], marker="o", linewidth=2, label="Max")
    ax.legend()
    _save(fig, out_dir / "single_packet_completion_us.png")


def plot_rate_scan(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / RATE_SCAN_FILE)
    df = _ensure_numeric(
        df,
        [
            "offered_rate_req_per_sec",
            "actual_send_rate_req_per_sec",
            "goodput_result_per_sec",
            "wire_goodput_gbps",
            "payload_goodput_gbps",
            "drop_ratio",
        ],
    ).sort_values("offered_rate_req_per_sec")

    x = df["offered_rate_req_per_sec"]

    fig, ax = _new_axes(
        title="Rate Scan: Actual Send Rate vs Result Goodput",
        xlabel="Offered Rate (req/s)",
        ylabel="Rate (req/s)",
    )
    ax.plot(x, x, marker="o", linewidth=2, label="Offered Rate")
    ax.plot(x, df["actual_send_rate_req_per_sec"], marker="o", linewidth=2, label="Actual Send Rate")
    ax.plot(x, df["goodput_result_per_sec"], marker="o", linewidth=2, label="Result Goodput")
    ax.legend()
    _save(fig, out_dir / "rate_scan_pps.png")

    fig, ax = _new_axes(
        title="Rate Scan: Goodput in Gbps",
        xlabel="Offered Rate (req/s)",
        ylabel="Goodput (Gbps)",
    )
    ax.plot(x, df["wire_goodput_gbps"], marker="o", linewidth=2, label="Wire Goodput")
    ax.plot(x, df["payload_goodput_gbps"], marker="o", linewidth=2, label="Payload Goodput")
    ax.legend()
    _save(fig, out_dir / "rate_scan_gbps.png")

    fig, ax = _new_axes(
        title="Rate Scan: Drop Ratio",
        xlabel="Offered Rate (req/s)",
        ylabel="Drop Ratio",
    )
    ax.plot(x, df["drop_ratio"], marker="o", linewidth=2, label="Drop Ratio", color="#c44e52")
    ax.legend()
    _save(fig, out_dir / "rate_scan_drop_ratio.png")


def plot_burst_curve(report_dir: Path, out_dir: Path):
    df = _load_csv(report_dir / BURST_CURVE_FILE)
    df = _ensure_numeric(
        df,
        [
            "batch_size",
            "batch_completion_time_us",
            "throughput_req_per_sec",
            "throughput_result_per_sec",
        ],
    ).sort_values("batch_size")

    x = df["batch_size"]

    fig, ax = _new_axes(
        title="Burst Curve: Batch Completion Time",
        xlabel="Batch Size",
        ylabel="Completion Time (us)",
    )
    ax.plot(x, df["batch_completion_time_us"], marker="o", linewidth=2, label="Completion Time")
    ax.legend()
    _save(fig, out_dir / "burst_completion_us.png")

    fig, ax = _new_axes(
        title="Burst Curve: Throughput",
        xlabel="Batch Size",
        ylabel="Throughput (req/s)",
    )
    ax.plot(x, df["throughput_req_per_sec"], marker="o", linewidth=2, label="Request Throughput")
    ax.plot(x, df["throughput_result_per_sec"], marker="o", linewidth=2, label="Result Throughput")
    ax.legend()
    _save(fig, out_dir / "burst_throughput_pps.png")


def build_parser():
    parser = argparse.ArgumentParser(description="Generate English-only line charts from bt/report CSV files.")
    parser.add_argument("--report-dir", default=str(DEFAULT_REPORT_DIR))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    return parser


def main():
    args = build_parser().parse_args()
    report_dir = Path(args.report_dir).resolve()
    out_dir = Path(args.out_dir).resolve()

    _base_style()
    plot_single_packet(report_dir, out_dir)
    plot_rate_scan(report_dir, out_dir)
    plot_burst_curve(report_dir, out_dir)

    print(f"Generated figures in {out_dir}")


if __name__ == "__main__":
    main()
