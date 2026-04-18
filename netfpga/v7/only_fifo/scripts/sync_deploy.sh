#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SW_DIR="$ROOT_DIR/sw"
DEPLOY_DIR="$ROOT_DIR/deploy"
REG_DEFINES="$ROOT_DIR/reg_defines_onlyfifo.h"

copy_exec() {
  local src="$1"
  local dst="$2"
  install -m 0755 "$src" "$dst"
}

copy_data() {
  local src="$1"
  local dst="$2"
  install -m 0644 "$src" "$dst"
}

reset_dir() {
  local dir="$1"
  mkdir -p "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

sync_buildhost() {
  local role_dir="$DEPLOY_DIR/buildhost"
  mkdir -p "$role_dir/bin" "$role_dir/python/packetlib" "$role_dir/testdata"
  reset_dir "$role_dir/bin"
  reset_dir "$role_dir/python/packetlib"
  reset_dir "$role_dir/testdata"

  copy_exec "$SW_DIR/bin/pktgen" "$role_dir/bin/pktgen"
  copy_exec "$SW_DIR/bin/pktbatch" "$role_dir/bin/pktbatch"

  copy_data "$SW_DIR/packetlib/__init__.py" "$role_dir/python/packetlib/__init__.py"
  copy_data "$SW_DIR/packetlib/cli.py" "$role_dir/python/packetlib/cli.py"
  copy_data "$SW_DIR/packetlib/json_compat.py" "$role_dir/python/packetlib/json_compat.py"
  copy_data "$SW_DIR/packetlib/udp_ann_packets.py" "$role_dir/python/packetlib/udp_ann_packets.py"

  copy_data "$SW_DIR/testdata/smoke_batch.json" "$role_dir/testdata/smoke_batch.json"
}

sync_node() {
  local role_dir="$DEPLOY_DIR/node"
  mkdir -p "$role_dir/bin" "$role_dir/python/packetlib"
  reset_dir "$role_dir/bin"
  reset_dir "$role_dir/python/packetlib"

  copy_exec "$SW_DIR/bin/pktsend" "$role_dir/bin/pktsend"
  copy_exec "$SW_DIR/bin/pktrecv" "$role_dir/bin/pktrecv"
  copy_exec "$SW_DIR/bin/pktdecode" "$role_dir/bin/pktdecode"

  copy_data "$SW_DIR/packetlib/__init__.py" "$role_dir/python/packetlib/__init__.py"
  copy_data "$SW_DIR/packetlib/cli.py" "$role_dir/python/packetlib/cli.py"
  copy_data "$SW_DIR/packetlib/json_compat.py" "$role_dir/python/packetlib/json_compat.py"
  copy_data "$SW_DIR/packetlib/udp_ann_packets.py" "$role_dir/python/packetlib/udp_ann_packets.py"
}

sync_netfpga() {
  local role_dir="$DEPLOY_DIR/netfpga"
  mkdir -p "$role_dir/bin" "$role_dir/python/packetlib" "$role_dir/config"
  reset_dir "$role_dir/bin"
  reset_dir "$role_dir/python/packetlib"
  reset_dir "$role_dir/config"

  copy_exec "$SW_DIR/bin/pktctl" "$role_dir/bin/pktctl"

  cat > "$role_dir/python/packetlib/__init__.py" <<'EOF'
#!/usr/bin/env python
EOF
  copy_data "$SW_DIR/packetlib/json_compat.py" "$role_dir/python/packetlib/json_compat.py"
  copy_data "$SW_DIR/packetlib/reg_access.py" "$role_dir/python/packetlib/reg_access.py"
  copy_data "$SW_DIR/packetlib/reg_cli.py" "$role_dir/python/packetlib/reg_cli.py"
  copy_data "$SW_DIR/packetlib/regmap.py" "$role_dir/python/packetlib/regmap.py"
  copy_data "$SW_DIR/packetlib/udp_ann_packets.py" "$role_dir/python/packetlib/udp_ann_packets.py"

  copy_data "$REG_DEFINES" "$role_dir/config/reg_defines_onlyfifo.h"
}

clean_caches() {
  find "$DEPLOY_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +
  find "$DEPLOY_DIR" -name '*.pyc' -type f -delete
}

sync_buildhost
sync_node
sync_netfpga
clean_caches

echo "synced only_fifo/deploy from only_fifo/sw and only_fifo/reg_defines_onlyfifo.h"
