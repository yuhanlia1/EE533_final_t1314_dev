#!/usr/bin/env bash
set -euo pipefail

REG_SCRIPT="${REG_SCRIPT:-./user_top_regs_v2.pl}"
START_ADDR=0
FINAL_MODE="gpu"

usage() {
  cat <<'USAGE'
Usage:
  ./load_gpu_imem_v2.sh [options] <gpu_imem.hex>

Options:
  --reg-script <path>   Path to user_top_regs_v2.pl
  --start-addr <n>      Initial word address if file has no @addr lines (default: 0)
  --mode-gpu            Switch to gpu mode after loading (default)
  --mode-cpu            Switch to cpu mode after loading
  --keep-bypass         Stay in bypass mode after loading
  -h, --help            Show this help
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
      --reg-script) REG_SCRIPT="$2"; shift 2 ;;
      --start-addr) START_ADDR="$2"; shift 2 ;;
      --mode-gpu) FINAL_MODE="gpu"; shift ;;
      --mode-cpu) FINAL_MODE="cpu"; shift ;;
      --keep-bypass) FINAL_MODE="bypass"; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
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
  "$REG_SCRIPT" gpu_imem_write "$addr" "0x$word" >/dev/null
  printf 'GPU_IMEM[%d] <= 0x%s\n' "$addr" "$word"
}

main() {
  parse_args "$@"
  [[ -f "$HEX_FILE" ]] || { echo "Hex file not found: $HEX_FILE" >&2; exit 1; }
  [[ -f "$REG_SCRIPT" ]] || { echo "Register script not found: $REG_SCRIPT" >&2; exit 1; }

  local current_addr="$START_ADDR"
  local loaded=0

  echo "[1/4] soft reset"
  "$REG_SCRIPT" reset >/dev/null

  echo "[2/4] switch to bypass while programming gpu imem"
  "$REG_SCRIPT" mode_bypass >/dev/null

  echo "[3/4] programming gpu imem from $HEX_FILE"
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
    [[ "$token" =~ ^[0-9a-fA-F]+$ ]] || { echo "Bad hex word in line: $raw" >&2; exit 1; }

    token="$(printf '%08x' $((16#$token & 0xFFFFFFFF)))"
    write_one "$current_addr" "$token"
    current_addr=$((current_addr + 1))
    loaded=$((loaded + 1))
  done < "$HEX_FILE"

  echo "[4/4] load complete: $loaded words"

  case "$FINAL_MODE" in
    gpu)
      echo "Switching to gpu mode"
      "$REG_SCRIPT" mode_gpu >/dev/null
      ;;
    cpu)
      echo "Switching to cpu mode"
      "$REG_SCRIPT" mode_cpu >/dev/null
      ;;
    *)
      echo "Keeping bypass mode"
      "$REG_SCRIPT" mode_bypass >/dev/null
      ;;
  esac

  echo
  "$REG_SCRIPT" status
  "$REG_SCRIPT" gpu_status || true
}

main "$@"
