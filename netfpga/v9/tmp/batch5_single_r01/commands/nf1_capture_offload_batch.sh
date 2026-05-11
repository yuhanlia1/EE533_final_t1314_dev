#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/v8/batch5_single_r01_receiver/captures"
sudo /usr/sbin/tcpdump -i port2 -nn -U -c 5 'udp and src host 10.0.12.3 and dst host 10.0.14.3' -w "$HOME/v8/batch5_single_r01_receiver/captures/offload_batch.cap"
