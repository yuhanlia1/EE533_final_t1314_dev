import argparse

import numpy as np
import pandas as pd


REQUIRED_COLS = [
    "window_id",
    "window_start_ms",
    "window_end_ms",
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

LABEL_ORDER = ["Free-flow", "Slow", "Congested", "Incident-risk"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--sheet-name", default="window_5s_features")
    p.add_argument("--output-sheet-name", default="labeled_5s_samples")
    p.add_argument("--free-flow-speed", type=float, default=None)
    p.add_argument("--free-flow-quantile", type=float, default=0.90)
    p.add_argument("--slow-ff-ratio", type=float, default=0.85)
    p.add_argument("--congested-ff-ratio", type=float, default=0.50)
    p.add_argument("--incident-speed-drop-ratio", type=float, default=0.20)
    p.add_argument("--incident-hard-brake-ratio", type=float, default=0.12)
    p.add_argument("--incident-near-stop-ratio", type=float, default=0.10)
    p.add_argument("--incident-low-speed-ratio", type=float, default=0.35)
    p.add_argument("--congested-near-stop-ratio", type=float, default=0.20)
    p.add_argument("--congested-low-speed-ratio", type=float, default=0.60)
    p.add_argument("--slow-low-speed-ratio", type=float, default=0.30)
    p.add_argument("--speed-drop-ratio", type=float, default=0.10)
    p.add_argument("--acc-min-incident-threshold", type=float, default=-8.0)
    p.add_argument("--min-vehicles", type=int, default=1)
    p.add_argument("--keep-empty-windows", action="store_true")
    return p.parse_args()


def validate_columns(df: pd.DataFrame) -> None:
    missing = [c for c in REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")


def infer_free_flow_speed(df: pd.DataFrame, q: float) -> float:
    s = df.loc[df["win_vehicle_count"] > 0, "win_speed_p90"].dropna()
    if s.empty:
        s = df.loc[df["win_vehicle_count"] > 0, "win_speed_mean"].dropna()
    if s.empty:
        raise ValueError("Cannot infer free-flow speed from input file.")
    return float(s.quantile(q))


def assign_label(row: pd.Series, ff_speed: float, args: argparse.Namespace) -> str:
    vehicle_count = int(row["win_vehicle_count"]) if pd.notna(row["win_vehicle_count"]) else 0
    if vehicle_count < args.min_vehicles:
        return "Free-flow"

    speed_mean = float(row["win_speed_mean"]) if pd.notna(row["win_speed_mean"]) else 0.0
    low_ratio = float(row["win_low_speed_ratio"]) if pd.notna(row["win_low_speed_ratio"]) else 0.0
    near_stop_ratio = float(row["win_near_stop_ratio"]) if pd.notna(row["win_near_stop_ratio"]) else 0.0
    hard_brake_ratio = float(row["win_hard_brake_ratio"]) if pd.notna(row["win_hard_brake_ratio"]) else 0.0
    speed_drop_ratio = float(row["win_speed_drop_ratio"]) if pd.notna(row["win_speed_drop_ratio"]) else 0.0
    acc_min = float(row["win_acc_min"]) if pd.notna(row["win_acc_min"]) else 0.0
    prev_speed_drop = float(row["speed_drop_from_prev_ratio"]) if pd.notna(row["speed_drop_from_prev_ratio"]) else 0.0

    ff_ratio = speed_mean / ff_speed if ff_speed > 0 else np.nan

    incident = (
        prev_speed_drop >= args.incident_speed_drop_ratio
        and (
            hard_brake_ratio >= args.incident_hard_brake_ratio
            or near_stop_ratio >= args.incident_near_stop_ratio
            or low_ratio >= args.incident_low_speed_ratio
            or speed_drop_ratio >= args.speed_drop_ratio
            or acc_min <= args.acc_min_incident_threshold
        )
    )
    if incident:
        return "Incident-risk"

    if (
        ff_ratio < args.congested_ff_ratio
        or near_stop_ratio >= args.congested_near_stop_ratio
        or low_ratio >= args.congested_low_speed_ratio
    ):
        return "Congested"

    if ff_ratio < args.slow_ff_ratio or low_ratio >= args.slow_low_speed_ratio:
        return "Slow"

    return "Free-flow"


def main() -> None:
    args = parse_args()

    df = pd.read_excel(args.input, sheet_name=args.sheet_name)
    validate_columns(df)
    df = df.copy().sort_values(["window_id", "window_start_ms"], kind="stable").reset_index(drop=True)

    if not args.keep_empty_windows:
        df = df.loc[df["win_vehicle_count"].fillna(0) > 0].copy()

    ff_speed = args.free_flow_speed if args.free_flow_speed is not None else infer_free_flow_speed(df, args.free_flow_quantile)
    ff_source = "user_provided" if args.free_flow_speed is not None else "inferred"

    df["sample_start"] = pd.to_datetime(df["window_start_ms"], unit="ms")
    df["sample_end"] = pd.to_datetime(df["window_end_ms"], unit="ms")
    df["free_flow_speed_used"] = ff_speed
    df["ff_speed_ratio"] = np.where(ff_speed > 0, df["win_speed_mean"] / ff_speed, np.nan)
    df["prev_speed_mean"] = df["win_speed_mean"].shift(1)
    df["prev_window_id"] = df["window_id"].shift(1)
    df["prev_window_gap"] = df["window_id"] - df["prev_window_id"]
    df["speed_drop_from_prev_ratio"] = np.where(
        (df["prev_window_gap"] == 1) & (df["prev_speed_mean"] > 0),
        ((df["prev_speed_mean"] - df["win_speed_mean"]) / df["prev_speed_mean"]).clip(lower=0),
        np.nan,
    )

    df["road_state_label"] = df.apply(lambda r: assign_label(r, ff_speed, args), axis=1)
    df["label_id"] = pd.Categorical(df["road_state_label"], categories=LABEL_ORDER, ordered=True).codes

    front_cols = [
        "window_id",
        "window_start_ms",
        "window_end_ms",
        "sample_start",
        "sample_end",
        "road_state_label",
        "label_id",
        "free_flow_speed_used",
        "ff_speed_ratio",
        "speed_drop_from_prev_ratio",
    ]
    drop_cols = {"prev_speed_mean", "prev_window_id", "prev_window_gap"}
    remaining = [c for c in df.columns if c not in front_cols and c not in drop_cols]
    out_df = df[front_cols + remaining].copy()

    label_counts = out_df["road_state_label"].value_counts().reindex(LABEL_ORDER, fill_value=0).reset_index()
    label_counts.columns = ["label", "count"]

    meta = pd.DataFrame(
        {
            "item": [
                "input_file",
                "input_sheet",
                "output_sheet",
                "free_flow_speed_source",
                "free_flow_speed_used",
                "free_flow_quantile_if_inferred",
                "slow_ff_ratio",
                "congested_ff_ratio",
                "incident_speed_drop_ratio",
                "incident_hard_brake_ratio",
                "incident_near_stop_ratio",
                "incident_low_speed_ratio",
                "congested_near_stop_ratio",
                "congested_low_speed_ratio",
                "slow_low_speed_ratio",
                "speed_drop_ratio",
                "acc_min_incident_threshold",
                "min_vehicles",
                "keep_empty_windows",
                "num_samples",
            ],
            "value": [
                args.input,
                args.sheet_name,
                args.output_sheet_name,
                ff_source,
                ff_speed,
                args.free_flow_quantile,
                args.slow_ff_ratio,
                args.congested_ff_ratio,
                args.incident_speed_drop_ratio,
                args.incident_hard_brake_ratio,
                args.incident_near_stop_ratio,
                args.incident_low_speed_ratio,
                args.congested_near_stop_ratio,
                args.congested_low_speed_ratio,
                args.slow_low_speed_ratio,
                args.speed_drop_ratio,
                args.acc_min_incident_threshold,
                args.min_vehicles,
                bool(args.keep_empty_windows),
                len(out_df),
            ],
        }
    )

    with pd.ExcelWriter(args.output, engine="openpyxl") as writer:
        out_df.to_excel(writer, sheet_name=args.output_sheet_name, index=False)
        meta.to_excel(writer, sheet_name="meta", index=False)
        label_counts.to_excel(writer, sheet_name="label_counts", index=False)


if __name__ == "__main__":
    main()
