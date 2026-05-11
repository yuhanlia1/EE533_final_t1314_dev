#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_ROOT="$ROOT_DIR/bt/round1"
PASSWORD_FILE=""
SSH_MODE=""
FORCE=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/board/nic_round1/run_round1.sh [options]

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

run_metrics() {
  local name="$1"
  local config_rel="$2"
  local out_dir="$OUT_ROOT/$name"
  local cmd=(python3 "$ROOT_DIR/scripts/board/board_metrics.py" --config "$ROOT_DIR/$config_rel" --out-dir "$out_dir")
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

mkdir -p "$OUT_ROOT"

run_metrics "single_packet" "scripts/board/nic_round1/single_packet_relative.json"
run_metrics "rate_scan" "scripts/board/nic_round1/rate_scan_ladder.json"
run_metrics "burst_fifo" "scripts/board/nic_round1/burst_fifo.json"
