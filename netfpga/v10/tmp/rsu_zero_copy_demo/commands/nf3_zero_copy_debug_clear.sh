#!/usr/bin/env bash
set -euo pipefail
RUN_ROOT="/home/netfpga/scripts/v8/rsu_zero_copy_demo_netfpga"
RESULT_ROOT="/home/netfpga/scripts/v8/rsu_zero_copy_demo_results"
export ANNCTL_STATE_DIR="$RESULT_ROOT/annctl_state"
mkdir -p "$RUN_ROOT" "$RESULT_ROOT" "$ANNCTL_STATE_DIR"
cd "$RUN_ROOT"
perl bin/annctl engine debug-clear
perl bin/annctl engine debug-status
