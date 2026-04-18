#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf '[unit-sw] compat wrapper: prefer bash scripts/check/sw_unit.sh\n'
exec bash "$ROOT_DIR/scripts/check/sw_unit.sh" "$@"
