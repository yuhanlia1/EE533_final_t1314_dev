#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/netfpga_mnist_verify.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[mnist] missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf '[mnist] %s\n' "$label" >&2
    exit 1
  fi
}

require_cmd python3

printf '[mnist] verifying deterministic binary-MNIST fixture flow\n'
FIXTURE_MODEL="$ROOT_DIR/sw/testdata/mnist_binary_01/fixture_model.json"
FIXTURE_BUILD="$WORK_DIR/fixture_build"
python3 "$ROOT_DIR/sw/annmodelctl" build "$FIXTURE_MODEL" --out-dir "$FIXTURE_BUILD" >/dev/null

python3 - "$FIXTURE_BUILD/expected_outputs.json" "$WORK_DIR/observed.json" <<'PY'
import json
import sys

expected_path = sys.argv[1]
observed_path = sys.argv[2]
expected = json.load(open(expected_path, "r", encoding="utf-8"))
observed = []
for index, row in enumerate(expected):
    observed.append(
        {
            "name": row["name"],
            "predicted_class": row["predicted_class"],
            "wire_result_data_0_u16": row["wire_result_data_0_u16"],
            "wire_result_data_1_u16": row["wire_result_data_1_u16"],
            "request_id": index,
        }
    )
json.dump(observed, open(observed_path, "w", encoding="utf-8"), indent=2)
PY

MNIST_REPORT="$WORK_DIR/mnist_report.json"
MNIST_OUTPUT="$(python3 "$ROOT_DIR/sw/board_debug/run_ann_model_batch.py" \
  --test-vectors "$FIXTURE_BUILD/test_vectors.json" \
  --expected "$FIXTURE_BUILD/expected_outputs.json" \
  --observed-json "$WORK_DIR/observed.json" \
  --report-out "$MNIST_REPORT")"
assert_contains "$MNIST_OUTPUT" '"class_accuracy": 1.0' "offline MNIST batch evaluator lost class accuracy"
assert_contains "$MNIST_OUTPUT" '"wire_accuracy": 1.0' "offline MNIST batch evaluator lost wire accuracy"
printf '[mnist] PASS fixture bundle builds and compares cleanly through the batch evaluator\n'

python3 "$ROOT_DIR/sw/mnist_toolchain/train_binary.py" --help >/dev/null
python3 "$ROOT_DIR/sw/mnist_toolchain/export_binary.py" --help >/dev/null
python3 "$ROOT_DIR/sw/mnist_toolchain/eval_binary.py" \
  --expected "$FIXTURE_BUILD/expected_outputs.json" \
  --observed "$WORK_DIR/observed.json" \
  --report-out "$WORK_DIR/eval_report.json" >/dev/null
printf '[mnist] PASS training/export/eval CLI entrypoints are wired\n'

TORCH_PRESENT="$(python3 - <<'PY'
import importlib.util
print(1 if importlib.util.find_spec("torch") and importlib.util.find_spec("torchvision") else 0)
PY
)"
if [[ "$TORCH_PRESENT" == "1" ]]; then
  printf '[mnist] torch/torchvision detected; real training flow can be executed locally\n'
else
  printf '[mnist] torch/torchvision not installed; skipped live MNIST training smoke\n'
fi

printf '[mnist] all binary-MNIST flow checks passed\n'
