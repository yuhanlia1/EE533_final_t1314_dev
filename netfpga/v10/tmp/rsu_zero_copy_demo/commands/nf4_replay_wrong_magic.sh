#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/rsu_zero_copy_demo_sender/pcaps/wrong_magic_bypass.pcap"
