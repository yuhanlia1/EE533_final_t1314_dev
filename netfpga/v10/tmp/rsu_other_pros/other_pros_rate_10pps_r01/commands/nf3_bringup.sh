#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT="/home/netfpga/scripts/v8/other_pros_rate_10pps_r01_netfpga"
RESULT_ROOT="/home/netfpga/scripts/v8/other_pros_rate_10pps_r01_results"
export ANNCTL_STATE_DIR="$RESULT_ROOT/annctl_state"

mkdir -p "$RUN_ROOT" "$RESULT_ROOT" "$ANNCTL_STATE_DIR"
cd "$RUN_ROOT"

/home/netfpga/bin/nf_download ~/bitfiles/nw_proc4_2_moreobserve.bit
if ! ps -ef | grep [r]kd >/dev/null 2>&1; then
  /home/netfpga/bin/rkd
fi

regwrite 0x02000028 0x0000004e
regwrite 0x0200002c 0x46324300
regwrite 0x02000030 0x0000004e
regwrite 0x02000034 0x46324301
regwrite 0x02000038 0x0000004e
regwrite 0x0200003c 0x46324302
regwrite 0x02000040 0x0000004e
regwrite 0x02000044 0x46324303

perl bin/annctl regs read sw_engine_ctrl
perl bin/annctl regs read hw_engine_status
perl bin/annctl cpu load "/home/netfpga/scripts/v8/other_pros_rate_10pps_r01_netfpga/bundle/cpu_build/image.txt"
perl bin/annctl gpu imem-load "/home/netfpga/scripts/v8/other_pros_rate_10pps_r01_netfpga/bundle/gpu_build/compiled_gpu_imem.txt"
perl bin/annctl gpu param-load "/home/netfpga/scripts/v8/other_pros_rate_10pps_r01_netfpga/bundle/gpu_build/compiled_gpu_params.txt"
perl bin/annctl engine result-config 0x00000b6c 4 compact
perl bin/annctl engine enable
perl bin/annctl engine status
perl bin/annctl engine debug-clear
perl bin/annctl engine debug-status
