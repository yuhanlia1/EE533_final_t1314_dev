#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/rsu_zero_copy_demo_sender/pcaps/offload_smoke_0.pcap"
