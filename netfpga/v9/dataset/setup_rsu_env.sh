#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv-rsu"
REQ_FILE="${ROOT_DIR}/dataset/requirements-rsu.txt"
TORCH_INDEX_URL="https://download.pytorch.org/whl/cpu"
TORCH_SPEC="torch==2.4.1+cpu"

if [[ ! -f "${REQ_FILE}" ]]; then
  echo "missing requirements file: ${REQ_FILE}" >&2
  exit 1
fi

if python3 -c "import ensurepip" >/dev/null 2>&1; then
  python3 -m venv "${VENV_DIR}"
else
  python3 -m virtualenv "${VENV_DIR}"
fi
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "${REQ_FILE}"
python -m pip install --index-url "${TORCH_INDEX_URL}" "${TORCH_SPEC}"

python - <<'PY'
mods = ["torch", "joblib", "openpyxl", "sklearn", "pandas", "numpy"]
for name in mods:
    __import__(name)
    print(name, "OK")
PY

cat <<EOF
RSU environment ready.
activate with:
  source "${VENV_DIR}/bin/activate"
EOF
