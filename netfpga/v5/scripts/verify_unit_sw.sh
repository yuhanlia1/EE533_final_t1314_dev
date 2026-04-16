#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[unit-sw] missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd perl

printf '[unit-sw] running annctl unit tests\n'
perl "$ROOT_DIR/sw/tests/annctl/test_anncontrol.t"

printf '[unit-sw] running CPU Python unit tests\n'
python3 -m unittest discover -s "$ROOT_DIR/sw/tests/cpu" -p 'test_*.py' -v

printf '[unit-sw] running GPU Python unit tests\n'
python3 -m unittest discover -s "$ROOT_DIR/sw/tests/gpu" -p 'test_*.py' -v

printf '[unit-sw] running ANN model Python unit tests\n'
python3 -m unittest discover -s "$ROOT_DIR/sw/tests/model" -p 'test_*.py' -v

printf '[unit-sw] all software unit tests passed\n'
