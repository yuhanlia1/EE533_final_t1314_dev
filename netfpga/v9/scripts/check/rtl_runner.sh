#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
  [tb_gpu_imem_guard]='[TB] === PASS: GPU IMEM out-of-range program writes are ignored ==='
  [tb_user_top_offload]='[TB] === PASS: user_top offload end-to-end scenarios completed ==='
  [tb_user_top_offload_rsu]='[TB] === PASS: user_top RSU smoke completed ==='
)

SUPPORTED_TESTBENCHES=(
  tb_user_top_offload_rsu
  tb_user_top_offload
  tb_packet
  tb_communication_nn
  tb_communication_matrix
  tb_gpu_imem_guard
)

DEFAULT_TESTBENCHES=(
  tb_user_top_offload
  tb_packet
  tb_communication_nn
  tb_communication_matrix
  tb_gpu_imem_guard
)

if [[ "$#" -gt 0 ]]; then
  SELECTED_TESTBENCHES=("$@")
else
  SELECTED_TESTBENCHES=("${DEFAULT_TESTBENCHES[@]}")
fi

for tb_name in "${SELECTED_TESTBENCHES[@]}"; do
  if [[ -z "${PASS_MARKERS[$tb_name]:-}" ]]; then
    printf '[tb] unknown testbench: %s\n' "$tb_name" >&2
    printf '[tb] supported testbenches: %s\n' "${SUPPORTED_TESTBENCHES[*]}" >&2
    exit 1
  fi
done

COMMON_SOURCES=(
  "$ROOT_DIR/src/bram_wrapper.v"
  "$ROOT_DIR/src/tb_necessary/cpu_gpu_controller.v"
  "$ROOT_DIR/src/tb_necessary/gpu_platform_bridge.v"
)
CPU_SOURCES=(
  "$ROOT_DIR/src/cpu/alu_64_stage1.v"
  "$ROOT_DIR/src/cpu/alu_64_stage2.v"
  "$ROOT_DIR/src/cpu/arm_processor_top.v"
  "$ROOT_DIR/src/cpu/decode_stage1.v"
  "$ROOT_DIR/src/cpu/ex_stage1.v"
  "$ROOT_DIR/src/cpu/ex_stage2.v"
  "$ROOT_DIR/src/cpu/fetch_stage1.v"
  "$ROOT_DIR/src/cpu/fetch_stage2.v"
  "$ROOT_DIR/src/cpu/mem_RF.v"
  "$ROOT_DIR/src/cpu/mem_data.v"
  "$ROOT_DIR/src/cpu/mem_inst.v"
  "$ROOT_DIR/src/cpu/mem_register_slice.v"
  "$ROOT_DIR/src/cpu/mem_stage.v"
  "$ROOT_DIR/src/cpu/wb_stage1.v"
)
GPU_SOURCES=("$ROOT_DIR"/src/gpu/*.v)
USER_TOP_SOURCES=(
  "$ROOT_DIR/src/fifo_bram.v"
  "$ROOT_DIR/src/convertible_fifo.v"
  "$ROOT_DIR/src/packet_action_selector.v"
  "$ROOT_DIR/src/action_dispatcher.v"
  "$ROOT_DIR/src/network_stream_slice.v"
  "$ROOT_DIR/src/tb_necessary/generic_regs_sim_stub.v"
  "$ROOT_DIR/src/ann_task_ingress.v"
  "$ROOT_DIR/src/ann_feature_unpack.v"
  "$ROOT_DIR/src/ann_cpu_gpu_compute_core.v"
  "$ROOT_DIR/src/ann_result_packet_builder.v"
  "$ROOT_DIR/src/ann_engine_wrapper.v"
  "$ROOT_DIR/src/bram_wrapper.v"
  "$ROOT_DIR/src/tb_necessary/cpu_gpu_controller.v"
  "$ROOT_DIR/src/tb_necessary/gpu_platform_bridge.v"
  "${CPU_SOURCES[@]}"
  "${GPU_SOURCES[@]}"
  "$ROOT_DIR/src/user_top.v"
)

run_testbench() {
  local tb_name="$1"
  local tb_dir="$WORK_DIR/$tb_name"
  local compile_log="$tb_dir/compile.log"
  local run_log="$tb_dir/run.log"
  local sim_bin="$tb_dir/$tb_name.out"
  local tb_file
  local -a tb_sources
  local -a tb_defines

  mkdir -p "$tb_dir"

  case "$tb_name" in
    tb_user_top_offload|tb_user_top_offload_rsu)
      tb_file="$ROOT_DIR/tb/integration/$tb_name.v"
      tb_sources=("${USER_TOP_SOURCES[@]}")
      tb_defines=(-DUDP_REG_ADDR_WIDTH=16 -DCPCI_NF2_DATA_WIDTH=32 -DNO_VCD)
      ;;
    *)
      tb_file="$ROOT_DIR/tb/unit/$tb_name.v"
      tb_sources=(
        "${COMMON_SOURCES[@]}"
        "${CPU_SOURCES[@]}"
        "${GPU_SOURCES[@]}"
      )
      tb_defines=()
      ;;
  esac

  printf '[tb] compiling %s\n' "$tb_name"
  if ! iverilog -g2012 \
      -I "$ROOT_DIR/include" \
      "${tb_defines[@]}" \
      -o "$sim_bin" \
      "$tb_file" \
      "${tb_sources[@]}" \
      >"$compile_log" 2>&1; then
    VERIFY_FAILED=1
    cat "$compile_log" >&2
    return 1
  fi

  if [[ -s "$compile_log" ]]; then
    printf '[tb] %s compiled with warnings; see %s\n' "$tb_name" "$compile_log"
  fi

  printf '[tb] running %s\n' "$tb_name"
  local -a vvp_args
  if [[ -n "${RTL_VVP_ARGS:-}" ]]; then
    read -r -a vvp_args <<< "${RTL_VVP_ARGS}"
  else
    vvp_args=()
  fi
  if ! (
      cd "$tb_dir"
      vvp "$sim_bin" "${vvp_args[@]}"
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
