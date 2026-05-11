#!/usr/bin/env bash
set -euo pipefail
RUN_ROOT="/home/netfpga/scripts/v8/rsu_zero_copy_demo_netfpga"
RESULT_ROOT="/home/netfpga/scripts/v8/rsu_zero_copy_demo_results"
mkdir -p "$RESULT_ROOT"
cd "$RUN_ROOT"
perl bin/annctl engine debug-status > "$RESULT_ROOT/debug_status_post.txt"
cat "$RESULT_ROOT/debug_status_post.txt"
