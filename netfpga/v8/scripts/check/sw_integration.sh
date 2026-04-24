#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/netfpga_sw_verify.XXXXXX")"
KEEP_ARTIFACTS="${KEEP_VERIFY_ARTIFACTS:-0}"
VERIFY_FAILED=0

cleanup() {
  if [[ "$VERIFY_FAILED" -eq 0 && "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$WORK_DIR"
  else
    printf '[sw] artifacts kept at %s\n' "$WORK_DIR"
  fi
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[sw] missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

fail_verify() {
  printf '[sw] %s\n' "$1" >&2
  VERIFY_FAILED=1
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if ! grep -Fq "$needle" <<<"$haystack"; then
    fail_verify "$label"
  fi
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf '[sw] expected:\n%s\n' "$expected" >&2
    printf '[sw] actual:\n%s\n' "$actual" >&2
    fail_verify "$label"
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    fail_verify "$label"
  fi
}

require_cmd python3
require_cmd perl

printf '[sw] verifying annctl/cpuctl/gpuctl/annmodelctl with mocked regread/regwrite\n'
MOCK_BIN_DIR="$WORK_DIR/mock_bin"
MOCK_STATE_DIR="$WORK_DIR/mock_state"
ANNCTL_STATE_DIR="$WORK_DIR/annctl_state"
MOCK_STATE="$MOCK_STATE_DIR/state.json"
MOCK_LOG="$MOCK_STATE_DIR/regwrite.log"
REG_DEFINES_PATH="$ROOT_DIR/sw/reg_defines_v8.h"
mkdir -p "$MOCK_BIN_DIR" "$MOCK_STATE_DIR" "$ANNCTL_STATE_DIR"
: > "$MOCK_LOG"

assert_file_exists "$REG_DEFINES_PATH" "missing sw/reg_defines_v8.h"

python3 - "$REG_DEFINES_PATH" "$MOCK_STATE" <<'PY'
import json
import os
import re
import sys

defines_path = sys.argv[1]
state_path = sys.argv[2]

required = [
    "USER_TOP_SW_D_MEM_ADDR_REG",
    "USER_TOP_SW_I_MEM_WDATA_REG",
    "USER_TOP_SW_I_MEM_ADDR_REG",
    "USER_TOP_SW_ENGINE_CTRL_REG",
    "USER_TOP_SW_GPU_I_MEM_WDATA_REG",
    "USER_TOP_SW_GPU_I_MEM_ADDR_REG",
    "USER_TOP_SW_GPU_W_MEM_WDATA_1_REG",
    "USER_TOP_SW_GPU_W_MEM_WDATA_0_REG",
    "USER_TOP_SW_GPU_W_MEM_ADDR_REG",
    "USER_TOP_SW_GPU_OFMAP_ADDR_REG",
    "USER_TOP_HW_ENGINE_STATUS_REG",
    "USER_TOP_HW_RESERVED_0_REG",
    "USER_TOP_HW_RESERVED_1_REG",
    "USER_TOP_HW_GPU_OFMAP_DATA_0_REG",
    "USER_TOP_HW_GPU_OFMAP_DATA_1_REG",
]

defines = {}
with open(defines_path, "r", encoding="utf-8") as fh:
    for line in fh:
        match = re.match(r"^\s*#define\s+(USER_TOP_[A-Z0-9_]+_REG)\s+(0x[0-9a-fA-F]+)", line)
        if match:
            defines[match.group(1)] = int(match.group(2), 16)

missing = [name for name in required if name not in defines]
if missing:
    raise SystemExit(f"missing USER_TOP defines: {missing}")

registers = {f"0x{addr:08x}": 0 for addr in defines.values()}
registers[f"0x{defines['USER_TOP_HW_ENGINE_STATUS_REG']:08x}"] = 0x0000001F
registers[f"0x{defines['USER_TOP_HW_RESERVED_0_REG']:08x}"] = 0x00000000
registers[f"0x{defines['USER_TOP_HW_RESERVED_1_REG']:08x}"] = 0x00000000
registers[f"0x{defines['USER_TOP_HW_GPU_OFMAP_DATA_0_REG']:08x}"] = 0x55667788
registers[f"0x{defines['USER_TOP_HW_GPU_OFMAP_DATA_1_REG']:08x}"] = 0x11223344

state = {
    "registers": registers,
    "meta": {
        "sw_d_mem_addr": defines["USER_TOP_SW_D_MEM_ADDR_REG"],
        "sw_i_mem_wdata": defines["USER_TOP_SW_I_MEM_WDATA_REG"],
        "sw_i_mem_addr": defines["USER_TOP_SW_I_MEM_ADDR_REG"],
        "sw_gpu_ofmap_addr": defines["USER_TOP_SW_GPU_OFMAP_ADDR_REG"],
        "hw_reserved_0": defines["USER_TOP_HW_RESERVED_0_REG"],
        "hw_reserved_1": defines["USER_TOP_HW_RESERVED_1_REG"],
        "hw_gpu_ofmap_data_0": defines["USER_TOP_HW_GPU_OFMAP_DATA_0_REG"],
        "hw_gpu_ofmap_data_1": defines["USER_TOP_HW_GPU_OFMAP_DATA_1_REG"],
    },
    "cpu_imem": {},
    "cpu_dmem": {
        "0": "0x000000a5",
        "1": "0x0000005a",
        "2": "0x0000003c",
    },
    "ofmap": {
        "0": "0x1122334455667788",
        "1": "0xdeadbeefcafef00d",
    },
}

with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2, sort_keys=True)
PY

cat > "$MOCK_BIN_DIR/regwrite" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

state_path = os.environ["ANNCTL_MOCK_STATE"]
log_path = os.environ["ANNCTL_MOCK_LOG"]

if len(sys.argv) != 3:
    raise SystemExit("usage: regwrite <addr> <value>")

addr = int(sys.argv[1], 16)
value = int(sys.argv[2], 16)

with open(state_path, "r", encoding="utf-8") as fh:
    state = json.load(fh)

registers = state["registers"]
registers[f"0x{addr:08x}"] = value

meta = state["meta"]
if addr == meta["sw_i_mem_addr"]:
    cpu_addr = value & 0x1FF
    if value & 0x80000000:
        wdata = registers[f"0x{meta['sw_i_mem_wdata']:08x}"]
        state["cpu_imem"][str(cpu_addr)] = f"0x{wdata:08x}"
    elif value & 0x40000000:
        word_hex = state["cpu_imem"].get(str(cpu_addr), "0x00000000")
        registers[f"0x{meta['hw_reserved_0']:08x}"] = int(word_hex, 16)

if addr == meta["sw_d_mem_addr"] and (value & 0x40000000):
    cpu_addr = value & 0x0FF
    word_hex = state["cpu_dmem"].get(str(cpu_addr), "0x00000000")
    registers[f"0x{meta['hw_reserved_1']:08x}"] = int(word_hex, 16)

if addr == meta["sw_gpu_ofmap_addr"]:
    word_hex = state["ofmap"].get(str(value), "0x0000000000000000")
    word = int(word_hex, 16)
    registers[f"0x{meta['hw_gpu_ofmap_data_0']:08x}"] = word & 0xFFFFFFFF
    registers[f"0x{meta['hw_gpu_ofmap_data_1']:08x}"] = (word >> 32) & 0xFFFFFFFF

with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2, sort_keys=True)

with open(log_path, "a", encoding="utf-8") as fh:
    fh.write(f"WRITE 0x{addr:08x} 0x{value:08x}\n")
PY

cat > "$MOCK_BIN_DIR/regread" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

state_path = os.environ["ANNCTL_MOCK_STATE"]

if len(sys.argv) != 2:
    raise SystemExit("usage: regread <addr>")

addr = int(sys.argv[1], 16)

with open(state_path, "r", encoding="utf-8") as fh:
    state = json.load(fh)

value = state["registers"].get(f"0x{addr:08x}", 0)
print(f"Reg 0x{addr:08x} ({addr}): 0x{value:08x}")
PY

chmod +x "$MOCK_BIN_DIR/regwrite" "$MOCK_BIN_DIR/regread"

run_annctl() {
  PATH="$MOCK_BIN_DIR:$PATH" \
  ANNCTL_STATE_DIR="$ANNCTL_STATE_DIR" \
  ANNCTL_MOCK_STATE="$MOCK_STATE" \
  ANNCTL_MOCK_LOG="$MOCK_LOG" \
  perl "$ROOT_DIR/sw/annctl" "$@"
}

run_cpuctl() {
  PATH="$MOCK_BIN_DIR:$PATH" \
  ANNCTL_STATE_DIR="$ANNCTL_STATE_DIR" \
  ANNCTL_MOCK_STATE="$MOCK_STATE" \
  ANNCTL_MOCK_LOG="$MOCK_LOG" \
  python3 "$ROOT_DIR/sw/cpuctl" "$@"
}

run_gpuctl() {
  PATH="$MOCK_BIN_DIR:$PATH" \
  ANNCTL_STATE_DIR="$ANNCTL_STATE_DIR" \
  ANNCTL_MOCK_STATE="$MOCK_STATE" \
  ANNCTL_MOCK_LOG="$MOCK_LOG" \
  python3 "$ROOT_DIR/sw/gpuctl" "$@"
}

run_annmodelctl() {
  PATH="$MOCK_BIN_DIR:$PATH" \
  ANNCTL_STATE_DIR="$ANNCTL_STATE_DIR" \
  ANNCTL_MOCK_STATE="$MOCK_STATE" \
  ANNCTL_MOCK_LOG="$MOCK_LOG" \
  python3 "$ROOT_DIR/sw/annmodelctl" "$@"
}

clear_mock_log() {
  : > "$MOCK_LOG"
}

REGS_LIST_OUTPUT="$(run_annctl regs list)"
assert_contains "$REGS_LIST_OUTPUT" "sw_engine_ctrl" "annctl regs list missing sw_engine_ctrl"
assert_contains "$REGS_LIST_OUTPUT" "addr=0x0200010c" "annctl regs list missing sw_engine_ctrl address"
printf '[sw] PASS annctl register map loads current USER_TOP addresses\n'

STATUS_OUTPUT="$(run_annctl engine status)"
assert_contains "$STATUS_OUTPUT" "raw              = 0x0000001f" "engine status raw decode mismatch"
assert_contains "$STATUS_OUTPUT" "gpu_busy         = 1" "engine status gpu_busy decode mismatch"
printf '[sw] PASS annctl decodes hw_engine_status bits\n'

clear_mock_log
run_annctl cpu load "$ROOT_DIR/sw/testdata/cpu_program_sample.txt" >/dev/null
CPU_LOG_EXPECTED="$(cat <<'EOF'
WRITE 0x02000104 0xe3a01001
WRITE 0x02000108 0x80000000
WRITE 0x02000108 0x00000000
WRITE 0x02000104 0xe3a02002
WRITE 0x02000108 0x80000001
WRITE 0x02000108 0x00000000
WRITE 0x02000104 0xeafffffe
WRITE 0x02000108 0x80000004
WRITE 0x02000108 0x00000000
EOF
)"
assert_equals "$(cat "$MOCK_LOG")" "$CPU_LOG_EXPECTED" "CPU IMEM load sequence mismatch"
CPU_SHADOW="$(run_annctl cpu shadow-dump 0 2)"
assert_contains "$CPU_SHADOW" "cpu_imem_shadow[0x00000000] = 0xe3a01001" "CPU shadow missing first word"
assert_contains "$CPU_SHADOW" "cpu_imem_shadow[0x00000001] = 0xe3a02002" "CPU shadow missing second word"
printf '[sw] PASS annctl CPU IMEM loader preserves write ordering and shadow state\n'

CPU_HW_IMEM_0="$(run_annctl cpu hw-imem-read 0)"
assert_contains "$CPU_HW_IMEM_0" "cpu_hw_imem[0x00000000] = 0xe3a01001" "CPU IMEM hardware readback mismatch at address 0"
CPU_HW_IMEM_4="$(run_annctl cpu hw-imem-read 4)"
assert_contains "$CPU_HW_IMEM_4" "cpu_hw_imem[0x00000004] = 0xeafffffe" "CPU IMEM hardware readback mismatch at sparse address 4"
CPU_HW_DMEM="$(run_annctl cpu hw-dmem-dump 0 3)"
assert_contains "$CPU_HW_DMEM" "cpu_hw_dmem_low32[0x00000000] = 0x000000a5" "CPU DMEM hardware readback mismatch at address 0"
assert_contains "$CPU_HW_DMEM" "cpu_hw_dmem_low32[0x00000001] = 0x0000005a" "CPU DMEM hardware readback mismatch at address 1"
assert_contains "$CPU_HW_DMEM" "cpu_hw_dmem_low32[0x00000002] = 0x0000003c" "CPU DMEM hardware readback mismatch at address 2"
printf '[sw] PASS annctl reads CPU IMEM/DMEM debug data through hw_reserved_0/1\n'

clear_mock_log
run_annctl gpu imem-load "$ROOT_DIR/sw/testdata/gpu_imem_sample.txt" >/dev/null
GPU_IMEM_LOG_EXPECTED="$(cat <<'EOF'
WRITE 0x02000110 0x10000001
WRITE 0x02000114 0x80000000
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0x20000002
WRITE 0x02000114 0x80000001
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0x30000003
WRITE 0x02000114 0x80000005
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0x40000004
WRITE 0x02000114 0x80000006
WRITE 0x02000114 0x00000000
EOF
)"
assert_equals "$(cat "$MOCK_LOG")" "$GPU_IMEM_LOG_EXPECTED" "GPU IMEM load sequence mismatch"
GPU_IMEM_SHADOW="$(run_annctl gpu imem-shadow-dump 5 2)"
assert_contains "$GPU_IMEM_SHADOW" "gpu_imem_shadow[0x00000005] = 0x30000003" "GPU IMEM shadow missing explicit address word"
assert_contains "$GPU_IMEM_SHADOW" "gpu_imem_shadow[0x00000006] = 0x40000004" "GPU IMEM shadow missing sequential continuation"
printf '[sw] PASS annctl GPU IMEM loader preserves write ordering and sparse addresses\n'

clear_mock_log
run_annctl gpu param-load "$ROOT_DIR/sw/testdata/gpu_params_sample.txt" >/dev/null
GPU_PARAM_LOG_EXPECTED="$(cat <<'EOF'
WRITE 0x02000118 0x00000001
WRITE 0x0200011c 0x00000002
WRITE 0x02000120 0x80000000
WRITE 0x02000120 0x00000000
WRITE 0x02000118 0x0000000a
WRITE 0x0200011c 0x0000000b
WRITE 0x02000120 0x80000003
WRITE 0x02000120 0x00000000
EOF
)"
assert_equals "$(cat "$MOCK_LOG")" "$GPU_PARAM_LOG_EXPECTED" "GPU parameter load sequence mismatch"
GPU_PARAM_SHADOW="$(run_annctl gpu param-shadow-dump 0 1)"
assert_contains "$GPU_PARAM_SHADOW" "gpu_param_shadow[0x00000000] = 0x0000000100000002" "GPU parameter shadow missing HI/LO load"
GPU_PARAM_SHADOW_EXPLICIT="$(run_annctl gpu param-shadow-read 3)"
assert_contains "$GPU_PARAM_SHADOW_EXPLICIT" "0x0000000a0000000b" "GPU parameter 64-bit parsing mismatch"
printf '[sw] PASS annctl GPU parameter loader preserves HI/LO ordering and 64-bit parsing\n'

OFMAP_OUTPUT="$(run_annctl gpu ofmap-dump 0 2)"
assert_contains "$OFMAP_OUTPUT" "gpu_ofmap[0x00000000] = 0x1122334455667788" "GPU OFMAP readback mismatch at address 0"
assert_contains "$OFMAP_OUTPUT" "gpu_ofmap[0x00000001] = 0xdeadbeefcafef00d" "GPU OFMAP readback mismatch at address 1"
printf '[sw] PASS annctl reads GPU OFMAP/debug data through the user_top window\n'

run_annctl reset-state >/dev/null
if run_annctl cpu shadow-read 0 >/dev/null 2>&1; then
  fail_verify 'reset-state did not clear CPU shadow state'
fi
RESET_ENGINE="$(run_annctl regs read sw_engine_ctrl)"
assert_contains "$RESET_ENGINE" "sw_engine_ctrl = 0x00000000" "reset-state did not clear sw_engine_ctrl"
printf '[sw] PASS annctl reset-state clears latched software registers and local shadows\n'

printf '[sw] verifying cpuctl single-thread flow\n'
CPUCTL_INSPECT_OUTPUT="$(run_cpuctl inspect "$ROOT_DIR/sw/testdata/cpu_single_thread.s")"
assert_contains "$CPUCTL_INSPECT_OUTPUT" "mode=single" "cpuctl inspect did not report single-thread mode"
assert_contains "$CPUCTL_INSPECT_OUTPUT" "inserted_nops=4" "cpuctl inspect did not report expected nop count"
printf '[sw] PASS cpuctl inspect reports current hazard scheduling\n'

CPUCTL_SINGLE_DIR="$WORK_DIR/cpuctl_single"
run_cpuctl build "$ROOT_DIR/sw/testdata/cpu_single_thread.s" --out-dir "$CPUCTL_SINGLE_DIR" >/dev/null
assert_file_exists "$CPUCTL_SINGLE_DIR/processed.s" "cpuctl build missing processed.s"
assert_file_exists "$CPUCTL_SINGLE_DIR/scheduled.s" "cpuctl build missing scheduled.s"
assert_file_exists "$CPUCTL_SINGLE_DIR/compiled_binary.txt" "cpuctl build missing compiled_binary.txt"
assert_file_exists "$CPUCTL_SINGLE_DIR/image.txt" "cpuctl build missing image.txt"
assert_file_exists "$CPUCTL_SINGLE_DIR/build_report.txt" "cpuctl build missing build_report.txt"
SINGLE_REPORT="$(cat "$CPUCTL_SINGLE_DIR/build_report.txt")"
assert_contains "$SINGLE_REPORT" "thread0.inserted_nops=4" "cpuctl build report missing expected nop count"
assert_contains "$SINGLE_REPORT" "thread0.final_words=12" "cpuctl build report missing final word count"
assert_equals "$(grep -c '^  mov r5, r5$' "$CPUCTL_SINGLE_DIR/scheduled.s")" "4" "cpuctl scheduled.s nop count mismatch"
printf '[sw] PASS cpuctl build emits processed/scheduled/hex/image artifacts\n'

BOARD_SIG_DIR="$WORK_DIR/board_cpu_signature"
run_cpuctl build "$ROOT_DIR/sw/testdata/board_cpu_signature.s" --out-dir "$BOARD_SIG_DIR" >/dev/null
assert_file_exists "$BOARD_SIG_DIR/compiled_binary.txt" "board CPU signature build missing compiled_binary.txt"
assert_file_exists "$BOARD_SIG_DIR/image.txt" "board CPU signature build missing image.txt"
if [[ "$(wc -l < "$BOARD_SIG_DIR/compiled_binary.txt" | tr -d ' ')" -lt 7 ]]; then
  fail_verify 'board CPU signature build produced too few instruction words'
fi
printf '[sw] PASS cpuctl builds the on-board CPU signature program\n'

BOARD_PACKET_JSON="$(python3 "$ROOT_DIR/sw/board_debug/send_ann_offload.py" --dump-json --src-ip 10.1.1.1 --dst-ip 10.1.1.2 --src-udp-port 0x1234)"
assert_contains "$BOARD_PACKET_JSON" "\"ethertype\": \"0x0800\"" "board ANN frame builder ethertype mismatch"
assert_contains "$BOARD_PACKET_JSON" "\"ip_protocol\": \"0x11\"" "board ANN frame builder IP protocol mismatch"
assert_contains "$BOARD_PACKET_JSON" "\"udp_src_port\": \"0x1234\"" "board ANN frame builder source UDP port mismatch"
assert_contains "$BOARD_PACKET_JSON" "\"udp_dst_port\": \"0x88b5\"" "board ANN frame builder destination UDP port mismatch"
assert_contains "$BOARD_PACKET_JSON" "\"udp_checksum\": \"0x0000\"" "board ANN frame builder UDP checksum mismatch"
assert_contains "$BOARD_PACKET_JSON" "\"task_magic\": \"0xa11e\"" "board ANN frame builder task magic mismatch"
printf '[sw] PASS board-side ANN frame generator matches the current RTL/TB protocol\n'

run_annctl cpu load "$CPUCTL_SINGLE_DIR/compiled_binary.txt" 16 >/dev/null
CPU_COMPAT="$(run_annctl cpu shadow-read 16)"
FIRST_SINGLE_WORD="0x$(sed -n '1p' "$CPUCTL_SINGLE_DIR/compiled_binary.txt" | tr 'A-Z' 'a-z')"
assert_contains "$CPU_COMPAT" "$FIRST_SINGLE_WORD" "cpuctl compiled_binary.txt is not accepted by annctl cpu load"
printf '[sw] PASS cpuctl compiled_binary.txt remains annctl-compatible\n'

TOO_LONG_SRC="$WORK_DIR/cpu_too_long.s"
{
  printf '.main:\n'
  for _ in $(seq 1 128); do
    printf '  mov r0, #0\n'
  done
} > "$TOO_LONG_SRC"
if run_cpuctl build "$TOO_LONG_SRC" --out-dir "$WORK_DIR/cpuctl_too_long" >/dev/null 2>&1; then
  fail_verify 'cpuctl accepted a thread longer than 127 words'
fi
printf '[sw] PASS cpuctl enforces the per-thread IMEM length limit\n'

printf '[sw] verifying cpuctl package flow\n'
CPUCTL_PACKAGE_DIR="$WORK_DIR/cpuctl_package"
run_cpuctl package "$ROOT_DIR/sw/testdata/cpu_package" --out-dir "$CPUCTL_PACKAGE_DIR" >/dev/null
assert_file_exists "$CPUCTL_PACKAGE_DIR/cpu_image.txt" "cpuctl package missing cpu_image.txt"
assert_file_exists "$CPUCTL_PACKAGE_DIR/image_map.txt" "cpuctl package missing image_map.txt"
PACKAGE_REPORT="$(cat "$CPUCTL_PACKAGE_DIR/build_report.txt")"
assert_contains "$PACKAGE_REPORT" "thread0.auto_stub=0" "cpuctl package lost explicit thread0 source"
assert_contains "$PACKAGE_REPORT" "thread1.auto_stub=0" "cpuctl package lost explicit thread1 source"
assert_contains "$PACKAGE_REPORT" "thread2.auto_stub=1" "cpuctl package did not auto-stub thread2"
assert_contains "$PACKAGE_REPORT" "thread3.auto_stub=1" "cpuctl package did not auto-stub thread3"
IMAGE_MAP="$(cat "$CPUCTL_PACKAGE_DIR/image_map.txt")"
assert_contains "$IMAGE_MAP" "thread0 base=0x00000000" "cpuctl package thread0 base address mismatch"
assert_contains "$IMAGE_MAP" "thread1 base=0x00000080" "cpuctl package thread1 base address mismatch"
assert_contains "$IMAGE_MAP" "thread2 base=0x00000100" "cpuctl package thread2 base address mismatch"
assert_contains "$IMAGE_MAP" "thread3 base=0x00000180" "cpuctl package thread3 base address mismatch"
printf '[sw] PASS cpuctl package lays out per-thread IMEM slots and auto-stubs missing threads\n'

clear_mock_log
CPUCTL_BUILD_LOAD_DIR="$WORK_DIR/cpuctl_build_load"
run_cpuctl build-load "$ROOT_DIR/sw/testdata/cpu_single_thread.s" --out-dir "$CPUCTL_BUILD_LOAD_DIR" >/dev/null
BUILD_LOAD_FIRST_WORD="0x$(sed -n '1p' "$CPUCTL_BUILD_LOAD_DIR/compiled_binary.txt" | tr 'A-Z' 'a-z')"
BUILD_LOAD_SHADOW="$(run_annctl cpu shadow-read 0)"
assert_contains "$BUILD_LOAD_SHADOW" "$BUILD_LOAD_FIRST_WORD" "cpuctl build-load did not program thread0 address 0"
assert_contains "$(cat "$MOCK_LOG")" "WRITE 0x02000108 0x80000000" "cpuctl build-load missing sw_i_mem_addr write pulse"
printf '[sw] PASS cpuctl build-load compiles and programs CPU IMEM through annctl\n'

clear_mock_log
CPUCTL_PACKAGE_LOAD_DIR="$WORK_DIR/cpuctl_package_load"
run_cpuctl package-load "$ROOT_DIR/sw/testdata/cpu_package" --out-dir "$CPUCTL_PACKAGE_LOAD_DIR" >/dev/null
THREAD1_FIRST_WORD="0x$(sed -n '1p' "$CPUCTL_PACKAGE_LOAD_DIR/thread1.hex" | tr 'A-Z' 'a-z')"
PACKAGE_SHADOW="$(run_annctl cpu shadow-read 128)"
assert_contains "$PACKAGE_SHADOW" "$THREAD1_FIRST_WORD" "cpuctl package-load did not program thread1 base address"
assert_contains "$(cat "$MOCK_LOG")" "WRITE 0x02000108 0x80000080" "cpuctl package-load missing thread1 IMEM address pulse"
printf '[sw] PASS cpuctl package-load emits an absolute image and loads multi-thread slots correctly\n'

printf '[sw] verifying gpuctl GPU assembler and bundle flow\n'
GPUCTL_INSPECT_OUTPUT="$(run_gpuctl inspect "$ROOT_DIR/sw/testdata/gpu_program_minimal.gpus")"
assert_contains "$GPUCTL_INSPECT_OUTPUT" "mode=program" "gpuctl inspect did not report program mode"
assert_contains "$GPUCTL_INSPECT_OUTPUT" "instruction_words=4" "gpuctl inspect instruction count mismatch"
printf '[sw] PASS gpuctl inspect parses a minimal GPU source\n'

GPUCTL_BUILD_DIR="$WORK_DIR/gpuctl_build"
run_gpuctl build "$ROOT_DIR/sw/testdata/gpu_program_minimal.gpus" --out-dir "$GPUCTL_BUILD_DIR" >/dev/null
assert_file_exists "$GPUCTL_BUILD_DIR/processed.gpus" "gpuctl build missing processed.gpus"
assert_file_exists "$GPUCTL_BUILD_DIR/compiled_gpu_imem.txt" "gpuctl build missing compiled_gpu_imem.txt"
assert_file_exists "$GPUCTL_BUILD_DIR/gpu_program_report.txt" "gpuctl build missing gpu_program_report.txt"
GPU_IMEM_EXPECTED="$(cat <<'EOF'
10000001
D2000000
E0000003
F0000000
EOF
)"
assert_equals "$(cat "$GPUCTL_BUILD_DIR/compiled_gpu_imem.txt")" "$GPU_IMEM_EXPECTED" "gpuctl minimal GPU program encoding mismatch"
GPU_PROGRAM_REPORT="$(cat "$GPUCTL_BUILD_DIR/gpu_program_report.txt")"
assert_contains "$GPU_PROGRAM_REPORT" "instruction_words=4" "gpuctl program report instruction count mismatch"
assert_contains "$GPU_PROGRAM_REPORT" "label..done=0x0003" "gpuctl program report label resolution mismatch"
printf '[sw] PASS gpuctl build emits deterministic GPU IMEM encoding\n'

clear_mock_log
run_gpuctl load-program "$GPUCTL_BUILD_DIR/compiled_gpu_imem.txt" >/dev/null
GPU_LOAD_LOG_EXPECTED="$(cat <<'EOF'
WRITE 0x02000110 0x10000001
WRITE 0x02000114 0x80000000
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0xd2000000
WRITE 0x02000114 0x80000001
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0xe0000003
WRITE 0x02000114 0x80000002
WRITE 0x02000114 0x00000000
WRITE 0x02000110 0xf0000000
WRITE 0x02000114 0x80000003
WRITE 0x02000114 0x00000000
EOF
)"
assert_equals "$(cat "$MOCK_LOG")" "$GPU_LOAD_LOG_EXPECTED" "gpuctl load-program did not route through annctl gpu imem-load"
GPU_MINIMAL_SHADOW="$(run_annctl gpu imem-shadow-dump 0 4)"
assert_contains "$GPU_MINIMAL_SHADOW" "gpu_imem_shadow[0x00000000] = 0x10000001" "gpuctl load-program missing first GPU instruction word"
assert_contains "$GPU_MINIMAL_SHADOW" "gpu_imem_shadow[0x00000003] = 0xf0000000" "gpuctl load-program missing halt word"
printf '[sw] PASS gpuctl load-program reuses the annctl GPU IMEM path\n'

GPUCTL_PACKAGE_DIR="$WORK_DIR/gpuctl_package"
run_gpuctl package "$ROOT_DIR/sw/testdata/gpu_bundle_mlp" --out-dir "$GPUCTL_PACKAGE_DIR" >/dev/null
assert_file_exists "$GPUCTL_PACKAGE_DIR/processed.gpus" "gpuctl package missing processed.gpus"
assert_file_exists "$GPUCTL_PACKAGE_DIR/compiled_gpu_imem.txt" "gpuctl package missing compiled_gpu_imem.txt"
assert_file_exists "$GPUCTL_PACKAGE_DIR/compiled_gpu_params.txt" "gpuctl package missing compiled_gpu_params.txt"
assert_file_exists "$GPUCTL_PACKAGE_DIR/meta.json" "gpuctl package missing normalized meta.json"
assert_file_exists "$GPUCTL_PACKAGE_DIR/gpu_bundle_report.txt" "gpuctl package missing gpu_bundle_report.txt"
GPU_BUNDLE_REPORT="$(cat "$GPUCTL_PACKAGE_DIR/gpu_bundle_report.txt")"
assert_contains "$GPU_BUNDLE_REPORT" "instruction_words=23" "gpuctl bundle instruction count mismatch"
assert_contains "$GPU_BUNDLE_REPORT" "param_words=12" "gpuctl bundle parameter count mismatch"
assert_contains "$GPU_BUNDLE_REPORT" "meta_present=1" "gpuctl bundle lost meta.json"
assert_contains "$(cat "$GPUCTL_PACKAGE_DIR/compiled_gpu_params.txt")" "0x00000040 0x00000000 0x00000001" "gpuctl bundle params missing first weight word"
assert_contains "$(cat "$GPUCTL_PACKAGE_DIR/compiled_gpu_params.txt")" "0x000000e3 0x00000000 0x0000ffff" "gpuctl bundle params missing final bias word"
printf '[sw] PASS gpuctl package emits compiled GPU program, params, and meta artifacts\n'

clear_mock_log
run_gpuctl load-bundle "$ROOT_DIR/sw/testdata/gpu_bundle_mlp" --out-dir "$WORK_DIR/gpuctl_bundle_load" >/dev/null
assert_contains "$(cat "$MOCK_LOG")" "WRITE 0x02000114 0x80000000" "gpuctl load-bundle missing GPU IMEM address pulse"
assert_contains "$(cat "$MOCK_LOG")" "WRITE 0x02000120 0x80000040" "gpuctl load-bundle missing GPU param address pulse"
GPU_PARAM_AFTER_LOAD="$(run_annctl gpu param-shadow-read 0x40)"
assert_contains "$GPU_PARAM_AFTER_LOAD" "0x0000000000000001" "gpuctl load-bundle missing GPU weight shadow entry"
GPU_BIAS_AFTER_LOAD="$(run_annctl gpu param-shadow-read 0xe2)"
assert_contains "$GPU_BIAS_AFTER_LOAD" "0x000000000000ffff" "gpuctl load-bundle missing GPU bias shadow entry"
printf '[sw] PASS gpuctl load-bundle composes program and parameter loading through annctl\n'

GPUCTL_TEMPLATE_DIR="$WORK_DIR/gpuctl_template"
run_gpuctl template mlp --out-dir "$GPUCTL_TEMPLATE_DIR" --in-dim 3 --out-dim 2 >/dev/null
assert_file_exists "$GPUCTL_TEMPLATE_DIR/program.gpus" "gpuctl template missing program.gpus"
assert_file_exists "$GPUCTL_TEMPLATE_DIR/params.txt" "gpuctl template missing params.txt"
assert_file_exists "$GPUCTL_TEMPLATE_DIR/meta.json" "gpuctl template missing meta.json"
assert_file_exists "$GPUCTL_TEMPLATE_DIR/gpu_template_report.txt" "gpuctl template missing gpu_template_report.txt"
assert_contains "$(cat "$GPUCTL_TEMPLATE_DIR/gpu_template_report.txt")" "in_dim=3" "gpuctl template report in_dim mismatch"
assert_contains "$(cat "$GPUCTL_TEMPLATE_DIR/gpu_template_report.txt")" "param_words=16" "gpuctl template report param count mismatch"
assert_contains "$(cat "$GPUCTL_TEMPLATE_DIR/program.gpus")" "tensor_mac r6, r0, r1" "gpuctl template did not emit tensor_mac operations"
GPU_TEMPLATE_INSPECT="$(run_gpuctl inspect "$GPUCTL_TEMPLATE_DIR")"
assert_contains "$GPU_TEMPLATE_INSPECT" "mode=bundle" "gpuctl inspect on generated template did not report bundle mode"
assert_contains "$GPU_TEMPLATE_INSPECT" "param_words=16" "gpuctl inspect on generated template lost parameter count"
printf '[sw] PASS gpuctl template mlp emits a packageable GPU bundle source tree\n'

printf '[sw] verifying annmodelctl multi-layer MLP flow\n'
ANNMODEL_INSPECT_OUTPUT="$(run_annmodelctl inspect "$ROOT_DIR/sw/testdata/ann_model_mlp_int16.json")"
assert_contains "$ANNMODEL_INSPECT_OUTPUT" "input_dim=8" "annmodelctl inspect lost model input_dim"
assert_contains "$ANNMODEL_INSPECT_OUTPUT" "output_dim=2" "annmodelctl inspect lost model output_dim"
assert_contains "$ANNMODEL_INSPECT_OUTPUT" "layers=2" "annmodelctl inspect lost layer count"
printf '[sw] PASS annmodelctl inspect reports the current hardware-aligned model limits\n'

ANNMODEL_BUILD_DIR="$WORK_DIR/annmodel_build"
run_annmodelctl build "$ROOT_DIR/sw/testdata/ann_model_mlp_int16.json" --out-dir "$ANNMODEL_BUILD_DIR" >/dev/null
assert_file_exists "$ANNMODEL_BUILD_DIR/model_manifest.json" "annmodelctl build missing model_manifest.json"
assert_file_exists "$ANNMODEL_BUILD_DIR/cpu_runtime.s" "annmodelctl build missing cpu_runtime.s"
assert_file_exists "$ANNMODEL_BUILD_DIR/cpu_build/image.txt" "annmodelctl build missing CPU image"
assert_file_exists "$ANNMODEL_BUILD_DIR/gpu_bundle/program.gpus" "annmodelctl build missing GPU source"
assert_file_exists "$ANNMODEL_BUILD_DIR/gpu_build/compiled_gpu_imem.txt" "annmodelctl build missing GPU IMEM image"
assert_file_exists "$ANNMODEL_BUILD_DIR/gpu_build/compiled_gpu_params.txt" "annmodelctl build missing GPU params image"
assert_file_exists "$ANNMODEL_BUILD_DIR/test_vectors.json" "annmodelctl build missing test_vectors.json"
assert_file_exists "$ANNMODEL_BUILD_DIR/expected_outputs.json" "annmodelctl build missing expected_outputs.json"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/cpu_runtime.s")" "str r6, [r10, #56]" "annmodelctl CPU runtime missed base_d MMIO write"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/gpu_bundle/program.gpus")" "store D, r6, 0" "annmodelctl GPU source missed hidden-layer scratch writes"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/gpu_bundle/program.gpus")" "store A, r6, 800" "annmodelctl GPU source missed final output writes at capture offset"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/expected_outputs.json")" "\"predicted_class\": 0" "annmodelctl expected outputs missed sample_class0 prediction"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/expected_outputs.json")" "\"predicted_class\": 1" "annmodelctl expected outputs missed sample_class1 prediction"
assert_contains "$(cat "$ANNMODEL_BUILD_DIR/model_manifest.json")" "\"result_mode\": \"legacy_logits\"" "annmodelctl manifest lost binary result mode"
printf '[sw] PASS annmodelctl builds a hardware-aligned multi-layer MLP bundle with golden outputs\n'

ANNMODEL_PACKET_JSON="$(python3 "$ROOT_DIR/sw/board_debug/send_ann_offload.py" --dump-json --feature-values \"3,2,1,1,2,0,1,0\")"
assert_contains "$ANNMODEL_PACKET_JSON" "\"feature_source\": \"explicit\"" "board ANN frame builder did not switch to explicit feature mode"
assert_contains "$ANNMODEL_PACKET_JSON" "\"feature_count_field\": 8" "board ANN frame builder explicit feature count mismatch"
assert_contains "$ANNMODEL_PACKET_JSON" "\"feature_values_be16\": [" "board ANN frame builder explicit feature list missing"
printf '[sw] PASS board-side ANN frame generator accepts explicit model test vectors\n'

clear_mock_log
ANNMODEL_BUILD_LOAD_DIR="$WORK_DIR/annmodel_build_load"
run_annmodelctl build-load "$ROOT_DIR/sw/testdata/ann_model_mlp_int16.json" --out-dir "$ANNMODEL_BUILD_LOAD_DIR" >/dev/null
ANNMODEL_CPU_FIRST="0x$(sed -n '2p' "$ANNMODEL_BUILD_LOAD_DIR/cpu_build/compiled_binary.txt" | tr 'A-Z' 'a-z')"
ANNMODEL_CPU_SHADOW="$(run_annctl cpu shadow-read 1)"
assert_contains "$ANNMODEL_CPU_SHADOW" "$ANNMODEL_CPU_FIRST" "annmodelctl build-load did not program the generated CPU runtime"
ANNMODEL_GPU_FIRST="$(sed -n '1p' "$ANNMODEL_BUILD_LOAD_DIR/gpu_build/compiled_gpu_imem.txt" | tr 'A-Z' 'a-z')"
ANNMODEL_GPU_SHADOW="$(run_annctl gpu imem-shadow-read 0)"
assert_contains "$ANNMODEL_GPU_SHADOW" "0x$ANNMODEL_GPU_FIRST" "annmodelctl build-load did not program the generated GPU program"
ANNMODEL_PARAM_SHADOW="$(run_annctl gpu param-shadow-read 3072)"
assert_contains "$ANNMODEL_PARAM_SHADOW" "0x0000000000000001" "annmodelctl build-load did not program the first generated weight word"
ANNMODEL_ENGINE_STATUS="$(run_annctl engine status)"
assert_contains "$ANNMODEL_ENGINE_STATUS" "output_count     = 0" "binary annmodelctl build-load unexpectedly changed compact result count"
printf '[sw] PASS annmodelctl build-load composes CPU runtime, GPU program, and model params through annctl\n'

printf '[sw] verifying boardctl formal USC workflow scaffolding\n'
BOARD_RUN_DIR="$WORK_DIR/board_run"
python3 "$ROOT_DIR/scripts/board/boardctl.py" prepare --out-dir "$BOARD_RUN_DIR" --run-name verify_board --limit 2 --force >/dev/null
python3 "$ROOT_DIR/scripts/board/boardctl.py" bringup "$BOARD_RUN_DIR/manifest.json" >/dev/null
python3 "$ROOT_DIR/scripts/board/boardctl.py" capture "$BOARD_RUN_DIR/manifest.json" >/dev/null
assert_file_exists "$BOARD_RUN_DIR/manifest.json" "boardctl prepare missing manifest.json"
assert_file_exists "$BOARD_RUN_DIR/pcaps/offload_batch.pcap" "boardctl prepare missing offload_batch.pcap"
assert_file_exists "$BOARD_RUN_DIR/commands/nf3_bringup.sh" "boardctl bringup missing nf3_bringup.sh"
assert_file_exists "$BOARD_RUN_DIR/commands/nf1_capture_offload_batch.sh" "boardctl capture missing nf1 capture script"
assert_file_exists "$BOARD_RUN_DIR/commands/nf1_capture_offload_batch_time_window.sh" "boardctl capture missing nf1 time-window capture script"
assert_file_exists "$BOARD_RUN_DIR/commands/nf4_capture_offload_batch_sender.sh" "boardctl capture missing nf4 sender capture script"
python3 - "$BOARD_RUN_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
repo_root = Path.cwd()
sys.path.insert(0, str(repo_root / "sw"))

from board_debug.ann_packets import rewrite_result_frame
from board_debug.pcap_io import read_pcap, write_pcap

expected = json.loads((root / "board_expected_outputs.json").read_text(encoding="utf-8"))
request_frames = read_pcap(root / "pcaps" / "offload_batch.pcap")
result_frames = []

for index, (frame, row) in enumerate(zip(request_frames, expected)):
    result_frames.append(
        rewrite_result_frame(
            frame,
            request_id=0x1234 + index,
            result_data_0=int(str(row["wire_result_data_0_u16"]), 0),
            result_data_1=int(str(row["wire_result_data_1_u16"]), 0),
            result_status=0x00,
            result_len=4,
        )
    )

write_pcap(root / "captures" / "offload_batch.cap", result_frames)
write_pcap(root / "captures" / "offload_batch_sender.cap", request_frames)
write_pcap(root / "captures" / "wrong_magic_bypass.cap", read_pcap(root / "pcaps" / "wrong_magic_bypass.pcap"))
write_pcap(root / "captures" / "wrong_port_bypass.cap", read_pcap(root / "pcaps" / "wrong_port_bypass.pcap"))
(root / "debug_status_post.txt").write_text(
    "\n".join(
        [
            "offload_accept_count   = 2",
            "frame_hold_count       = 2",
            "compute_start_count    = 2",
            "compute_done_count     = 2",
            "result_emit_count      = 2",
            "last_parse_request_id  = 0x1235",
            "last_compute_request_id = 0x1235",
            "last_emit_request_id   = 0x1235",
            "flags_raw              = 0x00000000",
            "ingress_overflow_seen  = 0",
            "parse_nonfatal_seen    = 0",
            "parse_fatal_seen       = 0",
            "emit_stall_seen        = 0",
            "",
        ]
    ),
    encoding="utf-8",
)
PY
python3 "$ROOT_DIR/scripts/board/boardctl.py" report "$BOARD_RUN_DIR/manifest.json" >/dev/null
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"wire_matches\": 2" "boardctl report wire match count mismatch"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"debug_emit_count\": 2" "boardctl report missing debug emit count"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"sender_capture_count\": 2" "boardctl report missing sender capture count"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"receiver_capture_count\": 2" "boardctl report missing receiver capture count"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"engine_emit_count\": 2" "boardctl report missing engine emit count"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"capture_vs_emit_gap\": 0" "boardctl report capture gap mismatch"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"pipeline_verdict\": \"healthy\"" "boardctl report pipeline verdict mismatch"
assert_contains "$(cat "$BOARD_RUN_DIR/board_eval_report.json")" "\"sender_request_ids\": [" "boardctl report missing sender request ids"
assert_contains "$(cat "$BOARD_RUN_DIR/board_test_summary.md")" "wrong_port_bypass" "boardctl report missing wrong_port smoke summary"
assert_contains "$(cat "$BOARD_RUN_DIR/board_test_summary.md")" "payload_magic=\`0xa11e\`" "boardctl report wrong_port payload magic mismatch"
assert_contains "$(cat "$BOARD_RUN_DIR/board_test_summary.md")" "batch_capture_mode: \`count\`" "boardctl summary missing batch capture mode"
assert_contains "$(cat "$BOARD_RUN_DIR/board_test_summary.md")" "sender_capture_count: \`2\`" "boardctl summary missing sender capture count"
printf '[sw] PASS boardctl prepares artifacts, emits USC scripts, and reports offline captures\n'

printf '[sw] all software integration checks passed\n'
