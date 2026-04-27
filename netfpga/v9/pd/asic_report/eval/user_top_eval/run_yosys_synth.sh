#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [[ -n "${ASIC_PLATFORM_CONFIG:-}" ]]; then
  # shellcheck disable=SC1090
  source "${ASIC_PLATFORM_CONFIG}"
fi

YOSYS_BIN="${YOSYS_BIN:-yosys}"
if ! command -v "$YOSYS_BIN" >/dev/null 2>&1; then
  ORFS_YOSYS="$HOME/codex/third_party/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys"
  if [[ -x "$ORFS_YOSYS" ]]; then
    YOSYS_BIN="$ORFS_YOSYS"
  fi
fi
if ! command -v "$YOSYS_BIN" >/dev/null 2>&1 && [[ ! -x "$YOSYS_BIN" ]]; then
  echo "error: yosys not found; set YOSYS_BIN or add yosys to PATH" >&2
  exit 127
fi

if [[ -n "${ASIC_PLATFORM_ROOT:-}" ]]; then
  : "${ASIC_LIBERTY:=${ASIC_PLATFORM_ROOT}/lib/NangateOpenCellLibrary_typical.lib}"
fi

: "${ASIC_LIBERTY:?Set ASIC_LIBERTY or ASIC_PLATFORM_ROOT before running synthesis.}"

MEMORY_IMPL="pd/asic_report/eval/user_top_eval/user_top_memory_impl.v"
SYNTH_NETLIST="pd/asic_report/eval/user_top_eval/user_top_synth.v"
SYNTH_JSON="pd/asic_report/eval/user_top_eval/user_top_synth.json"
SYNTH_STAT="pd/asic_report/eval/user_top_eval/user_top_synth_stat.rpt"
SYNTH_CHECK="pd/asic_report/eval/user_top_eval/user_top_synth_check.rpt"
TMP_SCRIPT="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<EOF
read_verilog -defer $MEMORY_IMPL
read_verilog -defer src/action_dispatcher.v
read_verilog -defer src/ann_cpu_gpu_compute_core.v
read_verilog -defer src/ann_engine_wrapper.v
read_verilog -defer src/ann_feature_unpack.v
read_verilog -defer src/ann_task_ingress.v
read_verilog -defer src/convertible_fifo.v
read_verilog -defer src/cpu/alu_64_stage1.v
read_verilog -defer src/cpu/alu_64_stage2.v
read_verilog -defer src/cpu/arm_processor_top.v
read_verilog -defer src/cpu/decode_stage1.v
read_verilog -defer src/cpu/ex_stage1.v
read_verilog -defer src/cpu/ex_stage2.v
read_verilog -defer src/cpu/fetch_stage1.v
read_verilog -defer src/cpu/fetch_stage2.v
read_verilog -defer src/cpu/mem_register_slice.v
read_verilog -defer src/cpu/mem_stage.v
read_verilog -defer src/cpu/wb_stage1.v
read_verilog -defer src/gpu/bf16_add_sub.v
read_verilog -defer src/gpu/bf16_mult.v
read_verilog -defer src/gpu/design_gpu.v
read_verilog -defer src/packet_action_selector.v
read_verilog -defer src/tb_necessary/generic_regs_sim_stub.v
read_verilog -defer src/user_top.v
hierarchy -check -top user_top
check
proc
memory
opt
fsm
opt
techmap
opt
dfflibmap -liberty $ASIC_LIBERTY
abc -liberty $ASIC_LIBERTY
clean
read_liberty -lib $ASIC_LIBERTY
hilomap -singleton -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
check -assert
tee -o $SYNTH_STAT stat -top user_top -liberty $ASIC_LIBERTY
tee -o $SYNTH_CHECK check -mapped -assert
write_json $SYNTH_JSON
write_verilog -noattr $SYNTH_NETLIST
EOF

(
  cd "$REPO_ROOT"
  "$YOSYS_BIN" -s "$TMP_SCRIPT"
)

echo "wrote $SYNTH_NETLIST"
echo "wrote $SYNTH_JSON"
echo "wrote $SYNTH_STAT"
echo "wrote $SYNTH_CHECK"
