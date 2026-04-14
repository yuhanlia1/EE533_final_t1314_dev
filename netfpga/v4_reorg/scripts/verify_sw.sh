#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_cmd python3
require_cmd sha256sum

run_armcompiler_case() {
  local case_name="$1"
  local input_src="$2"
  local processed_name="$3"
  local case_dir="$WORK_DIR/$case_name"
  local input_name

  input_name="$(basename "$input_src")"
  mkdir -p "$case_dir"
  cp "$ROOT_DIR"/sw/armcompiler/programs/*.py "$case_dir"/
  cp "$input_src" "$case_dir/$input_name"

  (
    cd "$case_dir"
    python3 preprocess.py "$input_name" "$processed_name" >/dev/null
    python3 armCompiler.py "$processed_name" > armCompiler.log
  )

  if [[ ! -s "$case_dir/compiled_binary.txt" || ! -s "$case_dir/output.txt" ]]; then
    printf '[sw] armcompiler case %s did not produce expected outputs\n' "$case_name" >&2
    VERIFY_FAILED=1
    return 1
  fi

  printf '[sw] PASS armcompiler smoke: %s\n' "$case_name"
}

printf '[sw] verifying armcompiler baseline\n'
run_armcompiler_case arm_test "$ROOT_DIR/sw/armcompiler/assembly/test.s" processed.s

if [[ "$(hash_file "$WORK_DIR/arm_test/compiled_binary.txt")" != "$(hash_file "$ROOT_DIR/sw/armcompiler/compiled_binary.txt")" ]]; then
  printf '[sw] compiled_binary.txt hash mismatch for armcompiler baseline\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

if [[ "$(hash_file "$WORK_DIR/arm_test/output.txt")" != "$(hash_file "$ROOT_DIR/sw/armcompiler/output.txt")" ]]; then
  printf '[sw] output.txt hash mismatch for armcompiler baseline\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

printf '[sw] PASS armcompiler baseline matches repository outputs\n'

printf '[sw] verifying armcompiler on sort.s and bubble.s\n'
SORT_READY_SRC="$WORK_DIR/sort_compiler_ready.s"
awk '
  /^main:/ {keep = 1}
  !keep {next}
  /^[[:space:]]*@/ {next}
  /^[[:space:]]*push[[:space:]]/ {next}
  /^[[:space:]]*pop[[:space:]]/ {next}
  /^[[:space:]]*bx[[:space:]]/ {next}
  {print}
  /^[[:space:]]*sub[[:space:]]+sp,[[:space:]]*fp,[[:space:]]*#4[[:space:]]*$/ {exit}
' "$ROOT_DIR/sw/c_program/sort.s" > "$SORT_READY_SRC"

if [[ "$(cat "$ROOT_DIR/sw/armcompiler/assembly/bubble.s")" != "$(cat "$SORT_READY_SRC")" ]]; then
  printf '[sw] compiler-ready sort.s body does not match sw/armcompiler/assembly/bubble.s\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

printf '[sw] PASS sort.s normalizes to the compiler-ready bubble.s form\n'

run_armcompiler_case arm_sort "$SORT_READY_SRC" sort_processed.s
run_armcompiler_case arm_bubble "$ROOT_DIR/sw/armcompiler/assembly/bubble.s" bubble_processed.s

if grep -Eq '^[[:space:]]*(ldmia|stmia|ldm|stm)\b' "$WORK_DIR/arm_sort/sort_processed.s"; then
  printf '[sw] sort_processed.s still contains multi-register instructions\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

if grep -Eq '^[[:space:]]*(ldmia|stmia|ldm|stm)\b' "$WORK_DIR/arm_bubble/bubble_processed.s"; then
  printf '[sw] bubble_processed.s still contains multi-register instructions\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

printf '[sw] PASS preprocess removed multi-register instructions from compiler-ready sort.s and bubble.s\n'

printf '[sw] verifying netcat binary generation\n'
NETCAT_DIR="$WORK_DIR/netcat"
mkdir -p "$NETCAT_DIR"
cp "$ROOT_DIR"/sw/netcat/*.py "$NETCAT_DIR"/

(
  cd "$NETCAT_DIR"
  python3 generate_netcat_.py > generate_netcat.log
  python3 netcat_convert.py > netcat_convert.log
  python3 arm_vivado_convert.py > arm_vivado_convert.log
)

if [[ "$(hash_file "$NETCAT_DIR/sample1.bin")" != "$(hash_file "$ROOT_DIR/sw/netcat/sample1.bin")" ]]; then
  printf '[sw] sample1.bin hash mismatch for netcat generation\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

if [[ "$(hash_file "$NETCAT_DIR/sample2.bin")" != "$(hash_file "$ROOT_DIR/sw/netcat/sample2.bin")" ]]; then
  printf '[sw] sample2.bin hash mismatch for netcat generation\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

if [[ "$(grep -c "nw_in_data = 64'h" "$NETCAT_DIR/arm_vivado_convert.log")" -ne 16 ]]; then
  printf '[sw] arm_vivado_convert.py did not emit 16 stimulus words\n' >&2
  VERIFY_FAILED=1
  exit 1
fi

printf '[sw] PASS netcat binary generation matches repository samples\n'
printf '[sw] PASS netcat helper scripts executed successfully\n'
printf '[sw] skipped cpureg runtime validation because it requires board-side regread/regwrite\n'
printf '[sw] all software translation checks passed\n'
