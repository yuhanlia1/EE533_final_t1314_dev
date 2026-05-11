#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/batch5_single_r01_sender/pcaps/offload_smoke_0.pcap"
