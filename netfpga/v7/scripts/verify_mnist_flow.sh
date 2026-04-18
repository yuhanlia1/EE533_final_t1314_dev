#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf '[example-binary-mnist] compat wrapper: prefer bash scripts/check/examples_binary_mnist.sh\n'
exec bash "$ROOT_DIR/scripts/check/examples_binary_mnist.sh" "$@"
