#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${ASIC_PLATFORM_CONFIG:-}" ]]; then
  # shellcheck disable=SC1090
  source "${ASIC_PLATFORM_CONFIG}"
fi

if [[ -n "${ASIC_PLATFORM_ROOT:-}" ]]; then
  : "${ASIC_LIBERTY:=${ASIC_PLATFORM_ROOT}/lib/NangateOpenCellLibrary_typical.lib}"
  : "${ASIC_TECH_LEF:=${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.tech.lef}"
  : "${ASIC_STD_CELL_LEF:=${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.macro.mod.lef}"
  : "${RCX_RULES:=${ASIC_PLATFORM_ROOT}/rcx_patterns.rules}"
fi

export ASIC_LIBERTY ASIC_TECH_LEF ASIC_STD_CELL_LEF RCX_RULES

for required_var in ASIC_LIBERTY ASIC_TECH_LEF ASIC_STD_CELL_LEF; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: missing $required_var; configure the nangate45 library paths first" >&2
    exit 2
  fi
done

OPENROAD_BIN="${OPENROAD_BIN:-openroad}"
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1; then
  ORFS_OPENROAD="$HOME/codex/third_party/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad"
  if [[ -x "$ORFS_OPENROAD" ]]; then
    OPENROAD_BIN="$ORFS_OPENROAD"
  fi
fi
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1 && [[ ! -x "$OPENROAD_BIN" ]]; then
  echo "error: openroad not found; set OPENROAD_BIN or add openroad to PATH" >&2
  exit 127
fi

mkdir -p "$SCRIPT_DIR/logs"
cd "$SCRIPT_DIR"
"$OPENROAD_BIN" -exit openroad_flow.tcl | tee "logs/openroad_stdout.log"
