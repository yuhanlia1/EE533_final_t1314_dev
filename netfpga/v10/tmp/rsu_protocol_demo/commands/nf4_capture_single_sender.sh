#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/rsu_protocol_demo_sender/captures"
rm -f "$HOME/v8/rsu_protocol_demo_sender/captures/offload_smoke_sender.cap"
sudo /usr/sbin/tcpdump -i port0 -nn -U -c 1 'udp and src host 10.0.12.3 and dst host 10.0.14.3' -w "$HOME/v8/rsu_protocol_demo_sender/captures/offload_smoke_sender.cap"
