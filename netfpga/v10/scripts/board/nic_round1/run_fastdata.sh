#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_ROOT="$ROOT_DIR/bt/round1_fastdata"
PASSWORD_FILE=""
SSH_MODE=""
FORCE=0

SINGLE_PACKET_REF="$ROOT_DIR/bt/round1_fixcheck/single_packet/summary.json"
RATE_SCAN_BASELINE_REF="$ROOT_DIR/bt/round1_rerun/rate_scan/summary.json"
RATE_SCAN_CONFIG="$ROOT_DIR/scripts/board/nic_round1/rate_scan_extend.json"
BURST_SAFE_CONFIG="$ROOT_DIR/scripts/board/nic_round1/burst_safe_subset.json"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/board/nic_round1/run_fastdata.sh [options]

Options:
  --password-file <path>
  --ssh-mode <sshpass|system>
  --out-root <dir>
  --force
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --password-file)
      PASSWORD_FILE="$2"
      shift 2
      ;;
    --ssh-mode)
      SSH_MODE="$2"
      shift 2
      ;;
    --out-root)
      OUT_ROOT="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "required file missing: $path" >&2
    exit 1
  fi
}

build_temp_rate_config() {
  local rate="$1"
  local request_id_base="$2"
  local path="$3"
  cat >"$path" <<EOF
{
  "model": "dataset/export/rsu_ann_model_int16.json",
  "bitfile": "nw_proc4_2_moreobserve.bit",
  "ssh_mode": "sshpass",
  "netfpga_host": "netfpga@nf3.usc.edu",
  "sender_host": "node3@nf4.usc.edu",
  "receiver_host": "node3@nf1.usc.edu",
  "sender_iface": "port0",
  "receiver_iface": "port2",
  "pre_capture_delay_seconds": 0.5,
  "capture_ready_delay_seconds": 1.0,
  "continue_on_error": true,
  "experiments": [
    {
      "name": "rate_scan_round1_extend",
      "mode": "rate_scan",
      "sample_pool_mode": "repeat",
      "request_id_base_start": "${request_id_base}",
      "rate_points_req_per_sec": [
        ${rate}
      ],
      "send_duration_seconds": 2.0,
      "drain_timeout_seconds": 1.0,
      "rate_generation_mode": "auto",
      "rate_accuracy_tolerance_ratio": 0.20,
      "rate_chunk_target_seconds": 0.25,
      "repeats": 1
    }
  ]
}
EOF
}

run_metrics() {
  local config_path="$1"
  local out_dir="$2"
  local -a cmd=(python3 "$ROOT_DIR/scripts/board/board_metrics.py" --config "$config_path" --out-dir "$out_dir")
  if [[ -n "$PASSWORD_FILE" ]]; then
    cmd+=(--password-file "$PASSWORD_FILE")
  fi
  if [[ -n "$SSH_MODE" ]]; then
    cmd+=(--ssh-mode "$SSH_MODE")
  fi
  if [[ "$FORCE" -eq 1 ]]; then
    cmd+=(--force)
  fi
  "${cmd[@]}"
}

rate_point_valid() {
  local summary_path="$1"
  python3 - "$summary_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    summary = json.load(handle)
result = summary["results"][0]
measurement_valid = bool(result.get("measurement_valid"))
drop_count = int(result.get("drop_count", 0) or 0)
mismatch_count = int(result.get("mismatch_count", 0) or 0)
print("1" if (measurement_valid and drop_count == 0 and mismatch_count == 0) else "0")
PY
}

mkdir -p "$OUT_ROOT"
require_file "$SINGLE_PACKET_REF"
require_file "$RATE_SCAN_BASELINE_REF"
require_file "$RATE_SCAN_CONFIG"
require_file "$BURST_SAFE_CONFIG"

if [[ "$FORCE" -eq 1 ]]; then
  rm -rf "$OUT_ROOT/rate_scan_extend" "$OUT_ROOT/burst_safe_subset"
fi
mkdir -p "$OUT_ROOT/rate_scan_extend"

mapfile -t RATE_POINTS < <(python3 - "$RATE_SCAN_CONFIG" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    config = json.load(handle)
for value in config["experiments"][0]["rate_points_req_per_sec"]:
    print(int(value))
PY
)

executed_rates=()
stop_reason="completed"
stop_rate=""
for index in "${!RATE_POINTS[@]}"; do
  rate="${RATE_POINTS[$index]}"
  request_id_base=$(printf "0x%04x" $((0x4000 + index * 0x0100)))
  temp_config="$(mktemp "/tmp/rsu_rate_scan_extend_${rate}_XXXX.json")"
  build_temp_rate_config "$rate" "$request_id_base" "$temp_config"
  out_dir="$OUT_ROOT/rate_scan_extend/${rate}pps"
  if ! run_metrics "$temp_config" "$out_dir"; then
    executed_rates+=("$rate")
    stop_reason="board_metrics_failed"
    stop_rate="$rate"
    rm -f "$temp_config"
    break
  fi
  executed_rates+=("$rate")
  summary_path="$out_dir/summary.json"
  if [[ "$(rate_point_valid "$summary_path")" != "1" ]]; then
    stop_reason="invalid_rate_point"
    stop_rate="$rate"
    rm -f "$temp_config"
    break
  fi
  rm -f "$temp_config"
done

burst_safe_exit=0
if ! run_metrics "$BURST_SAFE_CONFIG" "$OUT_ROOT/burst_safe_subset"; then
  burst_safe_exit=$?
fi

python3 - "$ROOT_DIR" "$OUT_ROOT" "$SINGLE_PACKET_REF" "$RATE_SCAN_BASELINE_REF" "$stop_reason" "$stop_rate" "$burst_safe_exit" "${executed_rates[@]}" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

root_dir = Path(sys.argv[1])
out_root = Path(sys.argv[2])
single_ref = Path(sys.argv[3])
rate_baseline_ref = Path(sys.argv[4])
stop_reason = sys.argv[5]
stop_rate = sys.argv[6] or None
burst_safe_exit = int(sys.argv[7])
executed_rates = [int(item) for item in sys.argv[8:]]

def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

single_summary = load_json(single_ref)
rate_baseline_summary = load_json(rate_baseline_ref)
burst_safe_summary = load_json(out_root / "burst_safe_subset" / "summary.json")

rate_extend_results = []
for rate in executed_rates:
    summary_path = out_root / "rate_scan_extend" / f"{rate}pps" / "summary.json"
    if summary_path.exists():
        summary = load_json(summary_path)
        rate_extend_results.append(summary["results"][0])

all_rate_results = list(rate_baseline_summary.get("results", [])) + rate_extend_results
valid_zero_loss = [
    item for item in all_rate_results
    if item.get("measurement_valid")
    and int(item.get("drop_count", 0) or 0) == 0
    and int(item.get("mismatch_count", 0) or 0) == 0
]
valid_zero_loss.sort(key=lambda item: float(item.get("offered_rate_req_per_sec", 0.0)))
max_zero_loss = valid_zero_loss[-1] if valid_zero_loss else None

first_overload = None
for item in sorted(all_rate_results, key=lambda entry: float(entry.get("offered_rate_req_per_sec", 0.0))):
    if not item.get("measurement_valid") or int(item.get("drop_count", 0) or 0) > 0:
        first_overload = item
        break

summary = {
    "schema_version": 1,
    "created_at": datetime.now().isoformat(timespec="seconds"),
    "single_packet_ref": str(single_ref),
    "rate_scan_baseline_ref": str(rate_baseline_ref),
    "rate_scan_extend_dir": str(out_root / "rate_scan_extend"),
    "burst_safe_subset_ref": str(out_root / "burst_safe_subset" / "summary.json"),
    "rate_scan_extend_executed": executed_rates,
    "rate_scan_extend_stop_reason": stop_reason,
    "rate_scan_extend_stop_rate_pps": stop_rate,
    "burst_safe_subset_exit_code": burst_safe_exit,
    "single_packet_results": single_summary.get("results", []),
    "rate_scan_baseline_results": rate_baseline_summary.get("results", []),
    "rate_scan_extend_results": rate_extend_results,
    "burst_safe_subset_results": burst_safe_summary.get("results", []),
    "max_zero_loss_pps": (
        max_zero_loss.get("offered_rate_req_per_sec") if max_zero_loss is not None else None
    ),
    "max_zero_loss_wire_gbps": (
        max_zero_loss.get("wire_goodput_gbps") if max_zero_loss is not None else None
    ),
    "max_zero_loss_payload_gbps": (
        max_zero_loss.get("payload_goodput_gbps") if max_zero_loss is not None else None
    ),
    "first_overload_pps": (
        first_overload.get("offered_rate_req_per_sec") if first_overload is not None else None
    ),
}

(out_root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Round 1 Fast Data Summary",
    "",
    f"- single_packet_ref: `{single_ref}`",
    f"- rate_scan_baseline_ref: `{rate_baseline_ref}`",
    f"- rate_scan_extend_dir: `{out_root / 'rate_scan_extend'}`",
    f"- burst_safe_subset_ref: `{out_root / 'burst_safe_subset' / 'summary.json'}`",
    f"- rate_scan_extend_executed: `{executed_rates}`",
    f"- rate_scan_extend_stop_reason: `{stop_reason}`",
    f"- rate_scan_extend_stop_rate_pps: `{stop_rate if stop_rate is not None else '-'}`",
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

lines.extend([
    "",
    "## Rate Scan",
    "",
    "| Run | Offered PPS | Actual PPS | Valid | Drop | Mismatch | Wire Gbps | Payload Gbps |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
])
for item in summary["rate_scan_baseline_results"] + summary["rate_scan_extend_results"]:
    lines.append(
        "| {run_name} | {offered:.0f} | {actual:.2f} | {valid} | {drop} | {mismatch} | {wire:.6f} | {payload:.6f} |".format(
            run_name=item["run_name"],
            offered=float(item.get("offered_rate_req_per_sec") or 0.0),
            actual=float(item.get("actual_send_rate_req_per_sec") or 0.0),
            valid=("yes" if item.get("measurement_valid") else "no"),
            drop=int(item.get("drop_count", 0) or 0),
            mismatch=int(item.get("mismatch_count", 0) or 0),
            wire=float(item.get("wire_goodput_gbps") or 0.0),
            payload=float(item.get("payload_goodput_gbps") or 0.0),
        )
    )

lines.extend([
    "",
    "## Burst Safe Subset",
    "",
    "| Run | Status | Correctness | Sender | Receiver | Engine | Mismatch |",
    "| --- | --- | --- | --- | --- | --- | --- |",
])
for item in summary["burst_safe_subset_results"]:
    lines.append(
        "| {run_name} | {status} | {correctness} | {sender} | {receiver} | {engine} | {mismatch} |".format(
            run_name=item["run_name"],
            status=item.get("status", "-"),
            correctness=item.get("correctness_verdict", "-"),
            sender=item.get("sender_capture_count", "-"),
            receiver=item.get("receiver_capture_count", "-"),
            engine=item.get("engine_emit_count", "-"),
            mismatch=item.get("mismatch_count", "-"),
        )
    )

(out_root / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "summary_json=$OUT_ROOT/summary.json"
echo "summary_md=$OUT_ROOT/summary.md"
