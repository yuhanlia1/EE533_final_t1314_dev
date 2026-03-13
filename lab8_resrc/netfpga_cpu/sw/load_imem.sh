#!/usr/bin/env bash
set -euo pipefail

REG_SCRIPT="${REG_SCRIPT:-./user_top_regs.pl}"
START_ADDR=0
FINAL_MODE="cpu"

usage() {
  cat <<'USAGE'
Usage:
  ./load_imem.sh [options] <imem.hex>

Options:
  --reg-script <path>   Path to user_top_regs.pl
  --start-addr <n>      Initial word address if file has no @addr lines (default: 0)
  --keep-bypass         Stay in bypass mode after loading
  --mode-cpu            Switch to cpu mode after loading (default)
  -h, --help            Show this help

Supported hex file formats:
  1) One 32-bit instruction per line:
       00500093
       80002023
  2) Optional 0x prefix:
       0x00500093
  3) Optional @address directives (word address):
       @00000010
       00500093
       80002023

Notes:
  - Address is word index, not byte address.
  - Lines may contain blank space and comments starting with # or //.
USAGE
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

parse_args() {
  local hex_seen=0
  HEX_FILE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reg-script)
        REG_SCRIPT="$2"
        shift 2
        ;;
      --start-addr)
        START_ADDR="$2"
        shift 2
        ;;
      --keep-bypass)
        FINAL_MODE="bypass"
        shift
        ;;
      --mode-cpu)
        FINAL_MODE="cpu"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        if [[ $hex_seen -eq 1 ]]; then
          echo "Only one hex file may be specified." >&2
          usage
          exit 1
        fi
        HEX_FILE="$1"
        hex_seen=1
        shift
        ;;
    esac
  done

  if [[ -z "${HEX_FILE:-}" ]]; then
    usage
    exit 1
  fi
}

write_one() {
  local addr="$1"
  local word="$2"
  "$REG_SCRIPT" icache_write "$addr" "0x$word" >/dev/null
  printf 'IMEM[%d] <= 0x%s\n' "$addr" "$word"
}

main() {
  parse_args "$@"

  if [[ ! -f "$HEX_FILE" ]]; then
    echo "Hex file not found: $HEX_FILE" >&2
    exit 1
  fi
  if [[ ! -x "$REG_SCRIPT" && ! -f "$REG_SCRIPT" ]]; then
    echo "Register script not found: $REG_SCRIPT" >&2
    exit 1
  fi

  local current_addr="$START_ADDR"
  local loaded=0

  echo "[1/4] soft reset"
  "$REG_SCRIPT" reset

  echo "[2/4] switch to bypass while programming icache"
  "$REG_SCRIPT" mode_bypass >/dev/null

  echo "[3/4] programming icache from $HEX_FILE"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    local line="$raw"
    line="${line%%#*}"
    line="${line%%//*}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^@([0-9a-fA-F_]+)$ ]]; then
      local addr_hex="${BASH_REMATCH[1]//_/}"
      current_addr=$((16#$addr_hex))
      printf 'Set load address = %d (0x%x)\n' "$current_addr" "$current_addr"
      continue
    fi

    local token="${line%%[[:space:]]*}"
    token="${token//_/}"
    token="${token#0x}"
    token="${token#0X}"

    if [[ ! "$token" =~ ^[0-9a-fA-F]+$ ]]; then
      echo "Bad hex word in line: $raw" >&2
      exit 1
    fi

    token="$(printf '%08x' $((16#$token & 0xFFFFFFFF)))"
    write_one "$current_addr" "$token"
    current_addr=$((current_addr + 1))
    loaded=$((loaded + 1))
  done < "$HEX_FILE"

  echo "[4/4] load complete: $loaded words"

  if [[ "$FINAL_MODE" == "cpu" ]]; then
    echo "Switching to cpu mode"
    "$REG_SCRIPT" mode_cpu >/dev/null
  else
    echo "Keeping bypass mode"
    "$REG_SCRIPT" mode_bypass >/dev/null
  fi

  echo
  "$REG_SCRIPT" status
  "$REG_SCRIPT" pc || true
}

main "$@"
