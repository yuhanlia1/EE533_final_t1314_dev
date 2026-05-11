#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/rsu_zero_copy_demo_sender/captures"
rm -f "$HOME/v8/rsu_zero_copy_demo_sender/captures/offload_batch_sender.cap"
sudo /usr/sbin/tcpdump -i port0 -nn -U -c 1 'udp and src host 10.0.16.3 and dst host 10.0.18.3' -w "$HOME/v8/rsu_zero_copy_demo_sender/captures/offload_batch_sender.cap"
