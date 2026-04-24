#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_PATH="$ROOT_DIR/dataset/export/rsu_ann_model_int16.json"
OUT_DIR="${1:-/tmp/rsu_demo_smoke}"
LIMIT="${RSU_DEMO_LIMIT:-4}"

printf '[rsu-demo] model=%s\n' "$MODEL_PATH"
printf '[rsu-demo] out_dir=%s\n' "$OUT_DIR"
printf '[rsu-demo] limit=%s\n' "$LIMIT"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

printf '[rsu-demo] annmodelctl inspect\n'
python3 "$ROOT_DIR/sw/annmodelctl" inspect "$MODEL_PATH" >/dev/null

printf '[rsu-demo] annmodelctl build\n'
python3 "$ROOT_DIR/sw/annmodelctl" build "$MODEL_PATH" --out-dir "$OUT_DIR/bundle"

printf '[rsu-demo] boardctl prepare\n'
python3 "$ROOT_DIR/scripts/board/boardctl.py" prepare \
  --model "$MODEL_PATH" \
  --limit "$LIMIT" \
  --out-dir "$OUT_DIR/run" \
  --force

printf '[rsu-demo] ready:\n'
printf '  bundle=%s\n' "$OUT_DIR/bundle"
printf '  run_manifest=%s\n' "$OUT_DIR/run/manifest.json"
