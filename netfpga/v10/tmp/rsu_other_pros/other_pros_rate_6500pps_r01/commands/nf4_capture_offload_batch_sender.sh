#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/other_pros_rate_6500pps_r01_sender/captures"
rm -f "$HOME/v8/other_pros_rate_6500pps_r01_sender/captures/offload_batch_sender.cap"
sudo /usr/sbin/tcpdump -i port0 -nn -U -c 13000 'udp and src host 10.0.16.3 and dst host 10.0.18.3' -w "$HOME/v8/other_pros_rate_6500pps_r01_sender/captures/offload_batch_sender.cap"
