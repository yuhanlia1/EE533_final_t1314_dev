#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '[tb] compat wrapper: prefer bash scripts/check/rtl_integration.sh and bash scripts/check/rtl_unit.sh\n'

UNIT_TESTS=(
  tb_packet
  tb_communication_nn
  tb_communication_matrix
  tb_gpu_imem_guard
)
INTEGRATION_TESTS=(
  tb_user_top_offload
)

if [[ "$#" -eq 0 ]]; then
  bash "$ROOT_DIR/scripts/check/rtl_integration.sh"
  exec bash "$ROOT_DIR/scripts/check/rtl_unit.sh"
fi

UNIT_SELECTED=()
INTEGRATION_SELECTED=()

for tb_name in "$@"; do
  case "$tb_name" in
    tb_user_top_offload)
      INTEGRATION_SELECTED+=("$tb_name")
      ;;
    tb_packet|tb_communication_nn|tb_communication_matrix|tb_gpu_imem_guard)
      UNIT_SELECTED+=("$tb_name")
      ;;
    *)
      printf '[tb] unknown testbench: %s\n' "$tb_name" >&2
      printf '[tb] integration: %s\n' "${INTEGRATION_TESTS[*]}" >&2
      printf '[tb] unit: %s\n' "${UNIT_TESTS[*]}" >&2
      exit 1
      ;;
  esac
done

if [[ "${#INTEGRATION_SELECTED[@]}" -gt 0 ]]; then
  bash "$ROOT_DIR/scripts/check/rtl_integration.sh" "${INTEGRATION_SELECTED[@]}"
fi

if [[ "${#UNIT_SELECTED[@]}" -gt 0 ]]; then
  exec bash "$ROOT_DIR/scripts/check/rtl_unit.sh" "${UNIT_SELECTED[@]}"
fi
