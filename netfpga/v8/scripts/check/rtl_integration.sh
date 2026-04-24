#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_TESTS=(tb_user_top_offload)

if [[ "$#" -gt 0 ]]; then
  SELECTED=("$@")
else
  SELECTED=("${DEFAULT_TESTS[@]}")
fi

for tb_name in "${SELECTED[@]}"; do
  case "$tb_name" in
    tb_user_top_offload)
      ;;
    *)
      printf '[rtl-integration] unknown integration testbench: %s\n' "$tb_name" >&2
      printf '[rtl-integration] supported: %s\n' "${DEFAULT_TESTS[*]}" >&2
      exit 1
      ;;
  esac
done

exec bash "$ROOT_DIR/scripts/check/rtl_runner.sh" "${SELECTED[@]}"
