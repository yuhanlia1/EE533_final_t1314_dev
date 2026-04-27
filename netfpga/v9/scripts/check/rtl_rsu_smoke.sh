#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${1:-$(mktemp -d "${TMPDIR:-/tmp}/rsu_rtl_smoke.XXXXXX")}"
USER_PROVIDED_WORKDIR=0
if [[ "$#" -gt 0 ]]; then
  USER_PROVIDED_WORKDIR=1
fi
KEEP_ARTIFACTS="${KEEP_RSU_RTL_ARTIFACTS:-0}"
RSU_LIMIT="${RSU_RTL_LIMIT:-4}"
FAILED=0

cleanup() {
  if [[ "$FAILED" -eq 0 && "$KEEP_ARTIFACTS" != "1" && "$USER_PROVIDED_WORKDIR" -eq 0 ]]; then
    rm -rf "$WORK_DIR"
  else
    printf '[rsu-rtl] artifacts kept at %s\n' "$WORK_DIR"
  fi
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[rsu-rtl] missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd iverilog
require_cmd vvp

printf '[rsu-rtl] work_dir=%s\n' "$WORK_DIR"
printf '[rsu-rtl] sample_limit=%s\n' "$RSU_LIMIT"

mkdir -p "$WORK_DIR"

python3 "$ROOT_DIR/scripts/check/prepare_rsu_rtl_smoke.py" \
  --out-dir "$WORK_DIR/artifacts" \
  --limit "$RSU_LIMIT"

source "$WORK_DIR/artifacts/rtl_env.sh"

export RTL_VVP_ARGS="+cpu_image_file=$CPU_IMAGE_FILE +cpu_image_count=$CPU_IMAGE_COUNT +gpu_imem_file=$GPU_IMEM_FILE +gpu_imem_count=$GPU_IMEM_COUNT +gpu_params_file=$GPU_PARAMS_FILE +gpu_params_base=$GPU_PARAMS_BASE +gpu_params_count=$GPU_PARAMS_COUNT +sample_words_file=$SAMPLE_WORDS_FILE +sample_count=$SAMPLE_COUNT +result_base=$RESULT_BASE +output_count=$OUTPUT_COUNT"

if ! bash "$ROOT_DIR/scripts/check/rtl_runner.sh" tb_user_top_offload_rsu; then
  FAILED=1
  exit 1
fi

printf '[rsu-rtl] summary=%s\n' "$WORK_DIR/artifacts/summary.json"
