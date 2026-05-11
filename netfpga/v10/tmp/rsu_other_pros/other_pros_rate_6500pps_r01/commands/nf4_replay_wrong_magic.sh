#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/other_pros_rate_6500pps_r01_sender/pcaps/wrong_magic_bypass.pcap"
