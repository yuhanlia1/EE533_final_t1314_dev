import argparse
import math
from pathlib import Path

import numpy as np
import pandas as pd


REQUIRED_5S_COLUMNS = [
    "window_start_ms",
    "window_end_ms",
    "window_id",
    "win_vehicle_count",
    "win_speed_mean",
    "win_speed_std",
    "win_speed_p10",
    "win_speed_p50",
    "win_speed_p90",
    "win_speed_min",
    "win_low_speed_ratio",
    "win_near_stop_ratio",
    "win_stop_vehicle_count",
    "win_acc_mean",
    "win_acc_std",
    "win_acc_min",
    "win_hard_brake_ratio",
    "win_speed_drop_ratio",
    "win_time_headway_mean",
    "win_time_headway_p10",
    "win_short_headway_ratio",
    "win_space_headway_mean",
    "win_space_headway_p10",
]


NUMERIC_5S_COLUMNS = [c for c in REQUIRED_5S_COLUMNS if c not in {"window_start_ms", "window_end_ms"}]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--features-sheet", default="window_5s_features")
    p.add_argument("--meta-sheet", default="meta")
    p.add_argument("--window-seconds", type=int, default=5)
    p.add_argument("--sample-seconds", type=int, default=120)
    p.add_argument("--free-flow-speed", type=float, default=None)
    p.add_argument("--slow-ff-ratio", type=float, default=0.85)
    p.add_argument("--congested-ff-ratio", type=float, default=0.50)
    p.add_argument("--slow-low-speed-ratio", type=float, default=0.15)
    p.add_argument("--congested-low-speed-ratio", type=float, default=0.50)
    p.add_argument("--congested-near-stop-ratio", type=float, default=0.10)
    p.add_argument("--incident-speed-drop-abs", type=float, default=10.0)
    p.add_argument("--incident-speed-drop-rel", type=float, default=0.25)
    p.add_argument("--incident-hard-brake-ratio", type=float, default=0.10)
    p.add_argument("--incident-vehicle-drop-ratio", type=float, default=0.15)
    p.add_argument("--incident-near-stop-ratio", type=float, default=0.15)
    p.add_argument("--min-nonempty-subwindows", type=int, default=1)
    p.add_argument("--keep-all-empty-samples", action="store_true")
    p.add_argument("--export-filled-5s", action="store_true")
    return p.parse_args()


def _safe_float(x):
    try:
        if pd.isna(x):
            return None
        return float(x)
    except Exception:
        return None


def load_free_flow_speed(xls: pd.ExcelFile, args: argparse.Namespace) -> float:
    if args.free_flow_speed is not None:
        return float(args.free_flow_speed)
    if args.meta_sheet in xls.sheet_names:
        meta = pd.read_excel(xls, sheet_name=args.meta_sheet)
        if {"key", "value"}.issubset(set(meta.columns)):
            match = meta.loc[meta["key"].astype(str).str.strip() == "free_flow_speed_ftps", "value"]
            if len(match) > 0:
                val = _safe_float(match.iloc[0])
                if val is not None and val > 0:
                    return float(val)
    df = pd.read_excel(xls, sheet_name=args.features_sheet, usecols=["win_speed_p90"])
    vals = pd.to_numeric(df["win_speed_p90"], errors="coerce").dropna().to_numpy(dtype=float)
    if vals.size == 0:
        raise ValueError("Unable to infer free-flow speed from win_speed_p90.")
    return float(np.percentile(vals, 90))


def load_5s_features(xls: pd.ExcelFile, sheet_name: str) -> pd.DataFrame:
    df = pd.read_excel(xls, sheet_name=sheet_name)
    missing = [c for c in REQUIRED_5S_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required 5s feature columns: {missing}")
    out = df[REQUIRED_5S_COLUMNS].copy()
    for c in REQUIRED_5S_COLUMNS:
        if c not in {"window_start_ms", "window_end_ms"}:
            out[c] = pd.to_numeric(out[c], errors="coerce")
    out["window_start_ms"] = pd.to_numeric(out["window_start_ms"], errors="coerce").astype("Int64")
    out["window_end_ms"] = pd.to_numeric(out["window_end_ms"], errors="coerce").astype("Int64")
    out = out.dropna(subset=["window_start_ms", "window_end_ms"]).copy()
    out["window_start_ms"] = out["window_start_ms"].astype(np.int64)
    out["window_end_ms"] = out["window_end_ms"].astype(np.int64)
    out = out.sort_values("window_start_ms").drop_duplicates(subset=["window_start_ms"], keep="last").reset_index(drop=True)
    return out


def build_filled_5s_grid(df: pd.DataFrame, window_ms: int) -> pd.DataFrame:
    start0 = int(df["window_start_ms"].min())
    end0 = int(df["window_start_ms"].max())
    full_starts = np.arange(start0, end0 + window_ms, window_ms, dtype=np.int64)
    full = pd.DataFrame({"window_start_ms": full_starts})
    full["window_end_ms"] = full["window_start_ms"] + window_ms
    full["window_id"] = ((full["window_start_ms"] - start0) // window_ms).astype(np.int64)
    merged = full.merge(df, on="window_start_ms", how="left", suffixes=("", "_src"))
    if "window_end_ms_src" in merged.columns:
        merged["window_end_ms"] = merged["window_end_ms_src"].fillna(merged["window_end_ms"])
        merged = merged.drop(columns=["window_end_ms_src"])
    if "window_id_src" in merged.columns:
        merged = merged.drop(columns=["window_id_src"])
    merged["empty_window_flag"] = merged["win_vehicle_count"].isna().astype(int)
    fill_zero_cols = [
        "win_vehicle_count",
        "win_speed_mean",
        "win_speed_std",
        "win_speed_p10",
        "win_speed_p50",
        "win_speed_p90",
        "win_speed_min",
        "win_low_speed_ratio",
        "win_near_stop_ratio",
        "win_stop_vehicle_count",
        "win_acc_mean",
        "win_acc_std",
        "win_acc_min",
        "win_hard_brake_ratio",
        "win_speed_drop_ratio",
        "win_time_headway_mean",
        "win_time_headway_p10",
        "win_short_headway_ratio",
        "win_space_headway_mean",
        "win_space_headway_p10",
    ]
    merged[fill_zero_cols] = merged[fill_zero_cols].fillna(0.0)
    return merged


def _stat_or_zero(series: pd.Series, fn, default=0.0):
    vals = pd.to_numeric(series, errors="coerce").dropna().to_numpy(dtype=float)
    if vals.size == 0:
        return default
    return float(fn(vals))


def _series_min_diff(vals: np.ndarray) -> float:
    if vals.size < 2:
        return 0.0
    return float(np.min(np.diff(vals)))


def _series_min_rel_diff(vals: np.ndarray) -> float:
    if vals.size < 2:
        return 0.0
    prev = vals[:-1]
    curr = vals[1:]
    denom = np.where(np.abs(prev) < 1e-9, np.nan, prev)
    rel = (curr - prev) / denom
    rel = rel[~np.isnan(rel)]
    if rel.size == 0:
        return 0.0
    return float(np.min(rel))


def _series_slope(vals: np.ndarray) -> float:
    if vals.size < 2:
        return 0.0
    x = np.arange(vals.size, dtype=float)
    slope, _ = np.polyfit(x, vals.astype(float), 1)
    return float(slope)


def aggregate_sample(group: pd.DataFrame, sample_start_ms: int, sample_ms: int, free_flow_speed: float, args: argparse.Namespace):
    group = group.sort_values("window_start_ms").reset_index(drop=True)
    nonempty = group[group["empty_window_flag"] == 0].copy()
    subwindow_count = int(len(group))
    nonempty_count = int(len(nonempty))
    empty_ratio = 1.0 - (nonempty_count / subwindow_count if subwindow_count > 0 else 0.0)
    if nonempty_count == 0 and not args.keep_all_empty_samples:
        return None
    if nonempty_count < args.min_nonempty_subwindows and not args.keep_all_empty_samples:
        return None

    speed_series = nonempty["win_speed_mean"].to_numpy(dtype=float) if nonempty_count > 0 else np.array([], dtype=float)
    sudden_speed_drop_abs = _series_min_diff(speed_series)
    sudden_speed_drop_rel = _series_min_rel_diff(speed_series)
    speed_slope_per_5s = _series_slope(speed_series)

    row = {
        "sample_id": int(sample_start_ms // sample_ms),
        "sample_start_ms": int(sample_start_ms),
        "sample_end_ms": int(sample_start_ms + sample_ms),
        "sample_start_utc": pd.to_datetime(sample_start_ms, unit="ms"),
        "sample_end_utc": pd.to_datetime(sample_start_ms + sample_ms, unit="ms"),
        "sample_subwindow_count": subwindow_count,
        "sample_nonempty_subwindow_count": nonempty_count,
        "sample_empty_subwindow_ratio": float(empty_ratio),
        "sample_vehicle_count_mean": _stat_or_zero(nonempty["win_vehicle_count"], np.mean),
        "sample_vehicle_count_max": _stat_or_zero(nonempty["win_vehicle_count"], np.max),
        "sample_speed_mean_mean": _stat_or_zero(nonempty["win_speed_mean"], np.mean),
        "sample_speed_mean_std": _stat_or_zero(nonempty["win_speed_mean"], np.std),
        "sample_speed_mean_min": _stat_or_zero(nonempty["win_speed_mean"], np.min),
        "sample_speed_p10_mean": _stat_or_zero(nonempty["win_speed_p10"], np.mean),
        "sample_speed_p50_mean": _stat_or_zero(nonempty["win_speed_p50"], np.mean),
        "sample_speed_p90_mean": _stat_or_zero(nonempty["win_speed_p90"], np.mean),
        "sample_speed_min_min": _stat_or_zero(nonempty["win_speed_min"], np.min),
        "sample_low_speed_ratio_mean": _stat_or_zero(nonempty["win_low_speed_ratio"], np.mean),
        "sample_low_speed_ratio_max": _stat_or_zero(nonempty["win_low_speed_ratio"], np.max),
        "sample_near_stop_ratio_mean": _stat_or_zero(nonempty["win_near_stop_ratio"], np.mean),
        "sample_near_stop_ratio_max": _stat_or_zero(nonempty["win_near_stop_ratio"], np.max),
        "sample_stop_vehicle_count_sum": _stat_or_zero(nonempty["win_stop_vehicle_count"], np.sum),
        "sample_stop_vehicle_count_max": _stat_or_zero(nonempty["win_stop_vehicle_count"], np.max),
        "sample_acc_mean_mean": _stat_or_zero(nonempty["win_acc_mean"], np.mean),
        "sample_acc_std_mean": _stat_or_zero(nonempty["win_acc_std"], np.mean),
        "sample_acc_min_min": _stat_or_zero(nonempty["win_acc_min"], np.min),
        "sample_hard_brake_ratio_mean": _stat_or_zero(nonempty["win_hard_brake_ratio"], np.mean),
        "sample_hard_brake_ratio_max": _stat_or_zero(nonempty["win_hard_brake_ratio"], np.max),
        "sample_speed_drop_ratio_mean": _stat_or_zero(nonempty["win_speed_drop_ratio"], np.mean),
        "sample_speed_drop_ratio_max": _stat_or_zero(nonempty["win_speed_drop_ratio"], np.max),
        "sample_time_headway_mean_mean": _stat_or_zero(nonempty["win_time_headway_mean"], np.mean),
        "sample_time_headway_p10_min": _stat_or_zero(nonempty["win_time_headway_p10"], np.min),
        "sample_short_headway_ratio_mean": _stat_or_zero(nonempty["win_short_headway_ratio"], np.mean),
        "sample_short_headway_ratio_max": _stat_or_zero(nonempty["win_short_headway_ratio"], np.max),
        "sample_space_headway_mean_mean": _stat_or_zero(nonempty["win_space_headway_mean"], np.mean),
        "sample_space_headway_p10_min": _stat_or_zero(nonempty["win_space_headway_p10"], np.min),
        "sample_sudden_speed_drop_abs_min": sudden_speed_drop_abs,
        "sample_sudden_speed_drop_rel_min": sudden_speed_drop_rel,
        "sample_speed_trend_slope_per_5s": speed_slope_per_5s,
        "free_flow_speed_ftps": float(free_flow_speed),
    }
    ff_ratio = row["sample_speed_mean_mean"] / free_flow_speed if free_flow_speed > 0 else 0.0
    row["sample_free_flow_ratio"] = float(ff_ratio)
    label, reason = assign_label(row, args)
    row["label"] = label
    row["label_rule"] = reason
    return row


def assign_label(row: dict, args: argparse.Namespace):
    ff_ratio = row["sample_free_flow_ratio"]
    incident = (
        row["sample_nonempty_subwindow_count"] >= 2
        and (
            row["sample_sudden_speed_drop_abs_min"] <= -abs(args.incident_speed_drop_abs)
            or row["sample_sudden_speed_drop_rel_min"] <= -abs(args.incident_speed_drop_rel)
        )
        and (
            row["sample_hard_brake_ratio_max"] >= args.incident_hard_brake_ratio
            or row["sample_speed_drop_ratio_max"] >= args.incident_vehicle_drop_ratio
            or row["sample_near_stop_ratio_max"] >= args.incident_near_stop_ratio
        )
    )
    if incident:
        return "Incident-risk", (
            f"incident: sudden_drop_abs={row['sample_sudden_speed_drop_abs_min']:.3f}, "
            f"sudden_drop_rel={row['sample_sudden_speed_drop_rel_min']:.3f}, "
            f"hard_brake_max={row['sample_hard_brake_ratio_max']:.3f}, "
            f"speed_drop_ratio_max={row['sample_speed_drop_ratio_max']:.3f}, "
            f"near_stop_ratio_max={row['sample_near_stop_ratio_max']:.3f}"
        )
    congested = (
        ff_ratio < args.congested_ff_ratio
        or row["sample_near_stop_ratio_mean"] >= args.congested_near_stop_ratio
        or row["sample_low_speed_ratio_mean"] >= args.congested_low_speed_ratio
    )
    if congested:
        return "Congested", (
            f"congested: ff_ratio={ff_ratio:.3f}, "
            f"near_stop_mean={row['sample_near_stop_ratio_mean']:.3f}, "
            f"low_speed_mean={row['sample_low_speed_ratio_mean']:.3f}"
        )
    slow = (
        ff_ratio < args.slow_ff_ratio
        or row["sample_low_speed_ratio_mean"] >= args.slow_low_speed_ratio
    )
    if slow:
        return "Slow", (
            f"slow: ff_ratio={ff_ratio:.3f}, "
            f"low_speed_mean={row['sample_low_speed_ratio_mean']:.3f}"
        )
    return "Free-flow", f"free_flow: ff_ratio={ff_ratio:.3f}"


def build_samples(filled_5s: pd.DataFrame, args: argparse.Namespace, free_flow_speed: float) -> tuple[pd.DataFrame, pd.DataFrame]:
    window_ms = args.window_seconds * 1000
    sample_ms = args.sample_seconds * 1000
    origin_start_ms = int(filled_5s["window_start_ms"].min())
    filled_5s = filled_5s.copy()
    filled_5s["sample_start_ms"] = origin_start_ms + (((filled_5s["window_start_ms"] - origin_start_ms) // sample_ms) * sample_ms)
    rows = []
    dropped = []
    for sample_start_ms, grp in filled_5s.groupby("sample_start_ms", sort=True):
        row = aggregate_sample(grp, int(sample_start_ms), sample_ms, free_flow_speed, args)
        if row is None:
            dropped.append({
                "sample_start_ms": int(sample_start_ms),
                "sample_end_ms": int(sample_start_ms + sample_ms),
                "reason": "all_empty_or_too_sparse",
                "sample_subwindow_count": int(len(grp)),
                "sample_nonempty_subwindow_count": int((grp["empty_window_flag"] == 0).sum()),
            })
        else:
            rows.append(row)
    samples = pd.DataFrame(rows)
    dropped_df = pd.DataFrame(dropped)
    if not samples.empty:
        samples = samples.sort_values("sample_start_ms").reset_index(drop=True)
        samples["sample_start_utc"] = pd.to_datetime(samples["sample_start_ms"], unit="ms")
        samples["sample_end_utc"] = pd.to_datetime(samples["sample_end_ms"], unit="ms")
    return samples, dropped_df


def build_meta(args: argparse.Namespace, free_flow_speed: float, raw_5s_count: int, filled_5s_count: int, samples_count: int, dropped_count: int) -> pd.DataFrame:
    rows = [
        ("input_file", str(args.input)),
        ("features_sheet", args.features_sheet),
        ("window_seconds", args.window_seconds),
        ("sample_seconds", args.sample_seconds),
        ("free_flow_speed_ftps", free_flow_speed),
        ("slow_ff_ratio", args.slow_ff_ratio),
        ("congested_ff_ratio", args.congested_ff_ratio),
        ("slow_low_speed_ratio", args.slow_low_speed_ratio),
        ("congested_low_speed_ratio", args.congested_low_speed_ratio),
        ("congested_near_stop_ratio", args.congested_near_stop_ratio),
        ("incident_speed_drop_abs", args.incident_speed_drop_abs),
        ("incident_speed_drop_rel", args.incident_speed_drop_rel),
        ("incident_hard_brake_ratio", args.incident_hard_brake_ratio),
        ("incident_vehicle_drop_ratio", args.incident_vehicle_drop_ratio),
        ("incident_near_stop_ratio", args.incident_near_stop_ratio),
        ("min_nonempty_subwindows", args.min_nonempty_subwindows),
        ("keep_all_empty_samples", int(args.keep_all_empty_samples)),
        ("raw_5s_rows", raw_5s_count),
        ("filled_5s_rows", filled_5s_count),
        ("two_min_samples_rows", samples_count),
        ("dropped_samples_rows", dropped_count),
    ]
    return pd.DataFrame(rows, columns=["key", "value"])


def main():
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    xls = pd.ExcelFile(input_path)
    free_flow_speed = load_free_flow_speed(xls, args)
    raw_5s = load_5s_features(xls, args.features_sheet)
    filled_5s = build_filled_5s_grid(raw_5s, args.window_seconds * 1000)
    samples, dropped = build_samples(filled_5s, args, free_flow_speed)
    meta = build_meta(args, free_flow_speed, len(raw_5s), len(filled_5s), len(samples), len(dropped))
    with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
        samples.to_excel(writer, sheet_name="two_min_samples", index=False)
        meta.to_excel(writer, sheet_name="meta", index=False)
        if not dropped.empty:
            dropped.to_excel(writer, sheet_name="dropped_samples", index=False)
        if args.export_filled_5s:
            filled_5s.to_excel(writer, sheet_name="filled_5s_windows", index=False)
    print(f"Saved 2-minute samples to: {output_path}")
    print(f"Rows in two_min_samples: {len(samples)}")
    if not dropped.empty:
        print(f"Dropped sparse/all-empty samples: {len(dropped)}")


if __name__ == "__main__":
    main()
