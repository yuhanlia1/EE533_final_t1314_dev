#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_PATH="$ROOT_DIR/dataset/export/rsu_ann_model_int16.json"
REPORT_PATH="$ROOT_DIR/dataset/export/rsu_ann_model_int16.report.json"
SUMMARY_PATH="$ROOT_DIR/dataset/models/mlp_5s_output/summary.json"
BASELINE_PATH="$ROOT_DIR/dataset/export/rsu_demo_baseline.json"
CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_sweep.json"
NIC_METRICS_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_nic_metrics.json"
DEMO_VERIFY_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_verify.json"
PROTOCOL_DEMO_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_protocol.json"
ENGINE_SINGLE_INFER_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_single_infer.json"
ZERO_COPY_DEMO_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_zero_copy.json"
OTHER_PROS_RATE_CONFIG_PATH="$ROOT_DIR/scripts/board/rsu_demo_other_pros_rate.json"
SYSTEM_REPORT_SUMMARY_PATH="$ROOT_DIR/bt/system_report/summary.json"
ASIC_POWER_REPORT_PATH="$ROOT_DIR/pd/asic_report/pnr/user_top/reports/4_postroute_power.rpt"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/board/rsu_demo.sh prepare [boardctl prepare args...]
  bash scripts/board/rsu_demo.sh sweep [board_sweep args...]
  bash scripts/board/rsu_demo.sh nic-metrics [board_metrics args...]
  bash scripts/board/rsu_demo.sh demo-verify [demo_verify args...]
  bash scripts/board/rsu_demo.sh engine-metrics
  bash scripts/board/rsu_demo.sh engine-toolchain [annmodelctl build args...]
  bash scripts/board/rsu_demo.sh engine-single-infer [demo_verify args...]
  bash scripts/board/rsu_demo.sh zero-copy-init [zero_copy_demo init args...]
  bash scripts/board/rsu_demo.sh zero-copy-threshold [zero_copy_demo threshold args...]
  bash scripts/board/rsu_demo.sh zero-copy-limit [zero_copy_demo limit args...]
  bash scripts/board/rsu_demo.sh zero-copy-path [zero_copy_demo path args...]
  bash scripts/board/rsu_demo.sh protocol-init [protocol_demo init args...]
  bash scripts/board/rsu_demo.sh protocol-bypass [protocol_demo bypass args...]
  bash scripts/board/rsu_demo.sh protocol-wrong-magic [protocol_demo wrong-magic args...]
  bash scripts/board/rsu_demo.sh protocol-offload [protocol_demo offload args...]
  bash scripts/board/rsu_demo.sh other-pros-rate-init [other_pros_rate_demo init args...]
  bash scripts/board/rsu_demo.sh other-pros-rate-scan [other_pros_rate_demo scan args...]
  bash scripts/board/rsu_demo.sh other-pros-rate-export [export_other_pros_rate_xlsx args...]
  bash scripts/board/rsu_demo.sh other-pros-throughput [other_pros_demo throughput args...]
  bash scripts/board/rsu_demo.sh other-pros-power [other_pros_demo power args...]
  bash scripts/board/rsu_demo.sh metrics
  bash scripts/board/rsu_demo.sh paths

Subcommands:
  prepare  Run scripts/board/boardctl.py prepare using the current RSU PTQ demo model.
  sweep    Run scripts/board/board_sweep.py using the current RSU demo sweep config and password file.
  nic-metrics Run scripts/board/board_metrics.py using the current RSU NIC metrics config.
  demo-verify Run scripts/board/demo_verify.py using the current RSU demo verification config.
  engine-metrics Print only the float baseline metrics used by the Cuda-like Engine demo.
  engine-toolchain Build the current RSU model bundle and print CPU/GPU artifact paths.
  engine-single-infer Run scripts/board/demo_verify.py in engine-single view using a single offload experiment.
  zero-copy-init Run scripts/board/zero_copy_demo.py init for the Zero Host/OS Copy showcase.
  zero-copy-threshold Run the offline threshold sweep used to find the extreme passing window.
  zero-copy-limit Run the on-stage single-point extreme latency demo using an existing zero-copy run_dir.
  zero-copy-path Run the sender/board/receiver evidence path using an existing zero-copy run_dir.
  protocol-init Run scripts/board/protocol_demo.py init for the thin protocol showcase wrapper.
  protocol-bypass Replay a normal IPv4/UDP bypass packet using an existing protocol demo run_dir.
  protocol-wrong-magic Replay the wrong-magic bypass packet using an existing protocol demo run_dir.
  protocol-offload Replay the accepted ANN offload packet using an existing protocol demo run_dir.
  other-pros-rate-init Prepare one board bring-up and freeze the default live rate-scan ladder.
  other-pros-rate-scan Run the live rate-scan ladder and print max zero-loss vs first overload.
  other-pros-rate-export Merge baseline + live high-rate scan results into a presentation-ready Excel workbook.
  other-pros-throughput Print the existing high-flow zero-loss vs overload threshold summary.
  other-pros-power Print the existing ASIC post-route power summary used by the demo deck.
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
  printf 'demo_verify_config=%s\n' "$DEMO_VERIFY_CONFIG_PATH"
  printf 'engine_single_infer_config=%s\n' "$ENGINE_SINGLE_INFER_CONFIG_PATH"
  printf 'zero_copy_demo_config=%s\n' "$ZERO_COPY_DEMO_CONFIG_PATH"
  printf 'protocol_demo_config=%s\n' "$PROTOCOL_DEMO_CONFIG_PATH"
  printf 'other_pros_rate_config=%s\n' "$OTHER_PROS_RATE_CONFIG_PATH"
  printf 'system_report_summary=%s\n' "$SYSTEM_REPORT_SUMMARY_PATH"
  printf 'asic_power_report=%s\n' "$ASIC_POWER_REPORT_PATH"
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

print_engine_metrics() {
  python3 - "$BASELINE_PATH" "$MODEL_PATH" <<'PY'
import json
import sys
from pathlib import Path

baseline = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
model = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

print("RSU Cuda-like Engine baseline")
print(f"  baseline_name: {baseline['baseline_name']}")
print(f"  intended_use: {baseline['intended_use']}")
print(f"  float_val_accuracy: {baseline['float_model']['val_accuracy']:.4f}")
print(f"  float_val_macro_f1: {baseline['float_model']['val_macro_f1']:.4f}")
print(f"  labels: {model.get('labels', [])}")
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

demo_verify() {
  exec python3 "$ROOT_DIR/scripts/board/demo_verify.py" --config "$DEMO_VERIFY_CONFIG_PATH" "$@"
}

engine_toolchain() {
  exec python3 "$ROOT_DIR/sw/annmodelctl" build "$MODEL_PATH" "$@"
}

engine_single_infer() {
  exec python3 "$ROOT_DIR/scripts/board/demo_verify.py" \
    --config "$ENGINE_SINGLE_INFER_CONFIG_PATH" \
    --view engine-single \
    "$@"
}

zero_copy_init() {
  exec python3 "$ROOT_DIR/scripts/board/zero_copy_demo.py" init --config "$ZERO_COPY_DEMO_CONFIG_PATH" "$@"
}

zero_copy_threshold() {
  exec python3 "$ROOT_DIR/scripts/board/zero_copy_demo.py" threshold "$@"
}

zero_copy_limit() {
  exec python3 "$ROOT_DIR/scripts/board/zero_copy_demo.py" limit "$@"
}

zero_copy_path() {
  exec python3 "$ROOT_DIR/scripts/board/zero_copy_demo.py" path "$@"
}

protocol_init() {
  exec python3 "$ROOT_DIR/scripts/board/protocol_demo.py" init --config "$PROTOCOL_DEMO_CONFIG_PATH" "$@"
}

protocol_bypass() {
  exec python3 "$ROOT_DIR/scripts/board/protocol_demo.py" bypass "$@"
}

protocol_wrong_magic() {
  exec python3 "$ROOT_DIR/scripts/board/protocol_demo.py" wrong-magic "$@"
}

protocol_offload() {
  exec python3 "$ROOT_DIR/scripts/board/protocol_demo.py" offload "$@"
}

other_pros_rate_init() {
  exec python3 "$ROOT_DIR/scripts/board/other_pros_rate_demo.py" init \
    --config "$OTHER_PROS_RATE_CONFIG_PATH" \
    "$@"
}

other_pros_rate_scan() {
  exec python3 "$ROOT_DIR/scripts/board/other_pros_rate_demo.py" scan "$@"
}

other_pros_rate_export() {
  exec python3 "$ROOT_DIR/scripts/board/export_other_pros_rate_xlsx.py" "$@"
}

other_pros_throughput() {
  exec python3 "$ROOT_DIR/scripts/board/other_pros_demo.py" throughput \
    --summary-json "$SYSTEM_REPORT_SUMMARY_PATH" \
    "$@"
}

other_pros_power() {
  exec python3 "$ROOT_DIR/scripts/board/other_pros_demo.py" power \
    --power-report "$ASIC_POWER_REPORT_PATH" \
    "$@"
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
  demo-verify)
    demo_verify "$@"
    ;;
  engine-metrics)
    print_engine_metrics
    ;;
  engine-toolchain)
    engine_toolchain "$@"
    ;;
  engine-single-infer)
    engine_single_infer "$@"
    ;;
  zero-copy-init)
    zero_copy_init "$@"
    ;;
  zero-copy-threshold)
    zero_copy_threshold "$@"
    ;;
  zero-copy-limit)
    zero_copy_limit "$@"
    ;;
  zero-copy-latency)
    printf 'deprecated: use zero-copy-threshold instead of zero-copy-latency\n' >&2
    zero_copy_threshold "$@"
    ;;
  zero-copy-path)
    zero_copy_path "$@"
    ;;
  protocol-init)
    protocol_init "$@"
    ;;
  protocol-bypass)
    protocol_bypass "$@"
    ;;
  protocol-wrong-magic)
    protocol_wrong_magic "$@"
    ;;
  protocol-offload)
    protocol_offload "$@"
    ;;
  other-pros-rate-init)
    other_pros_rate_init "$@"
    ;;
  other-pros-rate-scan)
    other_pros_rate_scan "$@"
    ;;
  other-pros-rate-export)
    other_pros_rate_export "$@"
    ;;
  other-pros-throughput)
    other_pros_throughput "$@"
    ;;
  other-pros-power)
    other_pros_power "$@"
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
