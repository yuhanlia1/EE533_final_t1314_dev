#!/usr/bin/env bash
set -euo pipefail

# Auto-generated gate-level + SDF simulation template.
# Replace the simulator command and testbench paths for your environment.
# The netlist/SDF paths below match the default OpenROAD output contract.

TOP_MODULE="user_top"
POST_ROUTE_NETLIST="pd/asic_report/pnr/user_top/results/user_top_postroute.v"
POST_ROUTE_SDF="pd/asic_report/pnr/user_top/results/user_top_postroute.sdf"
TESTBENCH="<replace-with-testbench.v>"
LOG_PATH="logs/user_top_gatelevel_sdf.log"
WAVE_PATH="waves/user_top_gatelevel_sdf.vcd"

echo "TOP_MODULE=$TOP_MODULE"
echo "POST_ROUTE_NETLIST=$POST_ROUTE_NETLIST"
echo "POST_ROUTE_SDF=$POST_ROUTE_SDF"
echo "TESTBENCH=$TESTBENCH"
echo "LOG_PATH=$LOG_PATH"
echo "WAVE_PATH=$WAVE_PATH"

# Example flow shape only:
# <simulator> \
#   -top "$TOP_MODULE" \
#   "$TESTBENCH" "$POST_ROUTE_NETLIST" \
#   +sdf_annotate="$POST_ROUTE_SDF" \
#   > "$LOG_PATH" 2>&1
