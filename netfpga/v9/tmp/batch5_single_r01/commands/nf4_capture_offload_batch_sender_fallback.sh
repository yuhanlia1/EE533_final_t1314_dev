#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/batch5_single_r01_sender/captures"
rm -f "$HOME/v8/batch5_single_r01_sender/captures/offload_batch_sender_fallback.cap"
sudo /usr/sbin/tcpdump -i port0 -nn -U -c 5 'udp and src host 10.0.12.3 and dst host 10.0.14.3' -w "$HOME/v8/batch5_single_r01_sender/captures/offload_batch_sender_fallback.cap"
