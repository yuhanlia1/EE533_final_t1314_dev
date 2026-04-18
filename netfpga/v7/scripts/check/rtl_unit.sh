#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_TESTS=(
  tb_packet
  tb_communication_nn
  tb_communication_matrix
  tb_gpu_imem_guard
)

if [[ "$#" -gt 0 ]]; then
  SELECTED=("$@")
else
  SELECTED=("${DEFAULT_TESTS[@]}")
fi

for tb_name in "${SELECTED[@]}"; do
  case "$tb_name" in
    tb_packet|tb_communication_nn|tb_communication_matrix|tb_gpu_imem_guard)
      ;;
    *)
      printf '[rtl-unit] unknown unit testbench: %s\n' "$tb_name" >&2
      printf '[rtl-unit] supported: %s\n' "${DEFAULT_TESTS[*]}" >&2
      exit 1
      ;;
  esac
done

exec bash "$ROOT_DIR/scripts/check/rtl_runner.sh" "${SELECTED[@]}"
