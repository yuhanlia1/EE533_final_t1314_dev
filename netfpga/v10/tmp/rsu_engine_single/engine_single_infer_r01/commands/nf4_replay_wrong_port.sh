#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/engine_single_infer_r01_sender/pcaps/wrong_port_bypass.pcap"
