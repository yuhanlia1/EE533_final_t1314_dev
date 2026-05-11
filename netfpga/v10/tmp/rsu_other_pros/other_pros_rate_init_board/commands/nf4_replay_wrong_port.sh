#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i port0 "$HOME/v8/other_pros_rate_init_board_sender/pcaps/wrong_port_bypass.pcap"
