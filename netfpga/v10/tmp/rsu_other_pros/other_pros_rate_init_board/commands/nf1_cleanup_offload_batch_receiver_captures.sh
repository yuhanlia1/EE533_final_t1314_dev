#!/usr/bin/env bash
set -euo pipefail
for capture_path in "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_time_window.cap" "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_receiver_primary.cap" "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_receiver_fallback.cap"; do
  rm -f "$capture_path"
  pids="$(ps -ef | grep '[t]cpdump' | grep -F -- "$capture_path" | awk '{print $2}' || true)"
  for pid in $pids; do
    kill -INT "$pid" || true
  done
done
sleep 1
for capture_path in "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_time_window.cap" "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_receiver_primary.cap" "$HOME/v8/other_pros_rate_init_board_receiver/captures/offload_batch_receiver_fallback.cap"; do
  pids="$(ps -ef | grep '[t]cpdump' | grep -F -- "$capture_path" | awk '{print $2}' || true)"
  for pid in $pids; do
    kill -TERM "$pid" || true
  done
done
