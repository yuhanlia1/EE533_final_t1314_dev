#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/netfpga_tb_verify.XXXXXX")"
KEEP_ARTIFACTS="${KEEP_VERIFY_ARTIFACTS:-0}"
VERIFY_FAILED=0

cleanup() {
  if [[ "$VERIFY_FAILED" -eq 0 && "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$WORK_DIR"
  else
    printf '[tb] artifacts kept at %s\n' "$WORK_DIR"
  fi
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[tb] missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd iverilog
require_cmd vvp

declare -A PASS_MARKERS=(
  [tb_packet]='[TB] === PASS: 3 full packets completed through ARM -> GPU NN -> TX ==='
  [tb_communication_nn]='[TB] === PASS: final-copy ARM -> GPU NN flow completed correctly ==='
  [tb_communication_matrix]='[TB] === PASS: final-copy ARM -> GPU matrix flow completed correctly ==='
)

ALL_TESTBENCHES=(
  tb_packet
  tb_communication_nn
  tb_communication_matrix
)

if [[ "$#" -gt 0 ]]; then
  SELECTED_TESTBENCHES=("$@")
else
  SELECTED_TESTBENCHES=("${ALL_TESTBENCHES[@]}")
fi

for tb_name in "${SELECTED_TESTBENCHES[@]}"; do
  if [[ -z "${PASS_MARKERS[$tb_name]:-}" ]]; then
    printf '[tb] unknown testbench: %s\n' "$tb_name" >&2
    printf '[tb] supported testbenches: %s\n' "${ALL_TESTBENCHES[*]}" >&2
    exit 1
  fi
done

COMMON_SOURCES=(
  "$ROOT_DIR/src/bram_wrapper.v"
  "$ROOT_DIR/src/cpu_gpu_controller.v"
  "$ROOT_DIR/src/gpu_platform_bridge.v"
)
CPU_SOURCES=("$ROOT_DIR"/src/cpu/*.v)
GPU_SOURCES=("$ROOT_DIR"/src/gpu/*.v)

run_testbench() {
  local tb_name="$1"
  local tb_dir="$WORK_DIR/$tb_name"
  local compile_log="$tb_dir/compile.log"
  local run_log="$tb_dir/run.log"
  local sim_bin="$tb_dir/$tb_name.out"

  mkdir -p "$tb_dir"

  printf '[tb] compiling %s\n' "$tb_name"
  if ! iverilog -g2012 \
      -I "$ROOT_DIR/include" \
      -o "$sim_bin" \
      "$ROOT_DIR/tb/$tb_name.v" \
      "${COMMON_SOURCES[@]}" \
      "${CPU_SOURCES[@]}" \
      "${GPU_SOURCES[@]}" \
      >"$compile_log" 2>&1; then
    VERIFY_FAILED=1
    cat "$compile_log" >&2
    return 1
  fi

  if [[ -s "$compile_log" ]]; then
    printf '[tb] %s compiled with warnings; see %s\n' "$tb_name" "$compile_log"
  fi

  printf '[tb] running %s\n' "$tb_name"
  if ! (
      cd "$tb_dir"
      vvp "$sim_bin"
    ) >"$run_log" 2>&1; then
    VERIFY_FAILED=1
    cat "$run_log" >&2
    return 1
  fi

  if grep -Eq '\[FAIL\]|TIMEOUT' "$run_log"; then
    VERIFY_FAILED=1
    cat "$run_log" >&2
    return 1
  fi

  if ! grep -Fq "${PASS_MARKERS[$tb_name]}" "$run_log"; then
    VERIFY_FAILED=1
    cat "$run_log" >&2
    return 1
  fi

  printf '[tb] PASS %s\n' "$tb_name"
}

for tb_name in "${SELECTED_TESTBENCHES[@]}"; do
  run_testbench "$tb_name"
done

printf '[tb] all selected testbenches passed\n'
