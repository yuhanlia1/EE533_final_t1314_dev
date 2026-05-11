#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/rsu_protocol_demo_sender/pcaps/offload_batch.pcap"
