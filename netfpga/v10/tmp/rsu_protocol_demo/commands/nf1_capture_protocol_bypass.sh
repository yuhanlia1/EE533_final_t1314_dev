#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/rsu_protocol_demo_receiver/captures"
rm -f "$HOME/v8/rsu_protocol_demo_receiver/captures/protocol_bypass.cap"
sudo /usr/sbin/tcpdump -i port2 -nn -U -c 1 'udp and src host 10.0.16.3 and dst host 10.0.18.3' -w "$HOME/v8/rsu_protocol_demo_receiver/captures/protocol_bypass.cap"
