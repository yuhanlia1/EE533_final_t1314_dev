#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_PATH="$ROOT_DIR/dataset/export/rsu_ann_model_int16.json"
REPORT_PATH="$ROOT_DIR/dataset/export/rsu_ann_model_int16.report.json"
SUMMARY_PATH="$ROOT_DIR/dataset/models/mlp_5s_output/summary.json"
BASELINE_PATH="$ROOT_DIR/dataset/export/rsu_demo_baseline.json"
CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_sweep.json"
NIC_METRICS_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_nic_metrics.json"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/board/rsu_demo.sh prepare [boardctl prepare args...]
  bash scripts/board/rsu_demo.sh sweep [board_sweep args...]
  bash scripts/board/rsu_demo.sh nic-metrics [board_metrics args...]
  bash scripts/board/rsu_demo.sh metrics
  bash scripts/board/rsu_demo.sh paths

Subcommands:
  prepare  Run scripts/board/boardctl.py prepare using the current RSU PTQ demo model.
  sweep    Run scripts/board/board_sweep.py using the current RSU demo sweep config and password file.
  nic-metrics Run scripts/board/board_metrics.py using the current RSU NIC metrics config.
  metrics  Print the frozen demo baseline and the current export metrics.
  paths    Print key artifact paths for the current RSU demo candidate.
EOF
}

print_paths() {
  printf 'model=%s\n' "$MODEL_PATH"
  printf 'report=%s\n' "$REPORT_PATH"
  printf 'training_summary=%s\n' "$SUMMARY_PATH"
  printf 'demo_baseline=%s\n' "$BASELINE_PATH"
  printf 'sweep_config=%s\n' "$CONFIG_PATH"
  printf 'nic_metrics_config=%s\n' "$NIC_METRICS_CONFIG_PATH"
}

print_metrics() {
  python3 - "$BASELINE_PATH" "$REPORT_PATH" "$SUMMARY_PATH" <<'PY'
import json
import sys
from pathlib import Path

baseline = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
summary = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

print("RSU demo baseline")
print(f"  baseline_name: {baseline['baseline_name']}")
print(f"  intended_use: {baseline['intended_use']}")
print(f"  float_val_accuracy: {baseline['float_model']['val_accuracy']:.4f}")
print(f"  float_val_macro_f1: {baseline['float_model']['val_macro_f1']:.4f}")
print(f"  ptq_full_agreement: {baseline['ptq_export']['float_vs_quantized_full_dataset_class_agreement']:.4f}")
print(f"  ptq_accuracy: {baseline['ptq_export']['quantized_vs_true_accuracy']:.4f}")
print(f"  ptq_macro_f1: {baseline['ptq_export']['quantized_vs_true_macro_f1']:.4f}")
print(f"  qat_selected: {summary.get('qat_selected')}")
print(f"  qat_rejected_reason: {summary.get('qat_rejected_reason', 'n/a')}")
print("Current export snapshot")
print(f"  channel_scale_mode: {report.get('channel_scale_mode', 'n/a')}")
print(f"  selected_scale_factors: {report.get('selected_scale_factors')}")
print(f"  quantized_prediction_histogram: {report.get('quantized_prediction_histogram')}")
PY
}

prepare_demo() {
  exec python3 "$ROOT_DIR/scripts/board/boardctl.py" prepare --model "$MODEL_PATH" "$@"
}

sweep_demo() {
  exec python3 "$ROOT_DIR/scripts/board/board_sweep.py" --config "$CONFIG_PATH" "$@"
}

nic_metrics_demo() {
  exec python3 "$ROOT_DIR/scripts/board/board_metrics.py" --config "$NIC_METRICS_CONFIG_PATH" "$@"
}

subcommand="${1:-}"
if [[ -z "$subcommand" ]]; then
  usage
  exit 1
fi
shift

case "$subcommand" in
  prepare)
    prepare_demo "$@"
    ;;
  sweep)
    sweep_demo "$@"
    ;;
  nic-metrics)
    nic_metrics_demo "$@"
    ;;
  metrics)
    print_metrics
    ;;
  paths)
    print_paths
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    printf 'unknown subcommand: %s\n' "$subcommand" >&2
    usage >&2
    exit 1
    ;;
esac
