#!/usr/bin/env bash
set -euo pipefail
RUN_ROOT="/home/netfpga/scripts/v8/other_pros_rate_5200pps_r01_netfpga"
RESULT_ROOT="/home/netfpga/scripts/v8/other_pros_rate_5200pps_r01_results"
mkdir -p "$RESULT_ROOT"
cd "$RUN_ROOT"
perl bin/annctl engine debug-status > "$RESULT_ROOT/debug_status_post.txt"
cat "$RESULT_ROOT/debug_status_post.txt"
