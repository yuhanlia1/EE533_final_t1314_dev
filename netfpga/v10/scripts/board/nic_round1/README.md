# NIC Round 1

这一目录承载第一轮 RSU SmartNIC 网络侧 baseline 测试配置。

目标分成三类：

- `single_packet_relative.json`
  - 比较 `offload / wrong_magic / wrong_port` 的相对处理时间
- `rate_scan_ladder.json`
  - 评估 sustained throughput、最大无丢包吞吐率、overload 拐点
- `burst_fifo.json`
  - 评估 `batch16 / 32 / 64` 的 burst stability，与 FIFO 对突发的吸收能力

## 命令

单独运行：

```bash
python3 scripts/board/board_metrics.py \
  --config scripts/board/nic_round1/single_packet_relative.json \
  --password-file ssh_passkey.txt \
  --out-dir bt/round1/single_packet \
  --force
```

```bash
python3 scripts/board/board_metrics.py \
  --config scripts/board/nic_round1/rate_scan_ladder.json \
  --password-file ssh_passkey.txt \
  --out-dir bt/round1/rate_scan \
  --force
```

```bash
python3 scripts/board/board_metrics.py \
  --config scripts/board/nic_round1/burst_fifo.json \
  --password-file ssh_passkey.txt \
  --out-dir bt/round1/burst_fifo \
  --force
```

串行运行：

```bash
bash scripts/board/nic_round1/run_round1.sh \
  --password-file ssh_passkey.txt \
  --out-root bt/round1 \
  --force
```

快速出数流程：

```bash
bash scripts/board/nic_round1/run_fastdata.sh \
  --password-file ssh_passkey.txt \
  --out-root bt/round1_fastdata \
  --force
```

## 结果重点

`single_packet_relative` 重点看：

- `mean_completion_us`
- `p50_completion_us`
- `p95_completion_us`
- `max_completion_us`
- `sample_pass_rate`

`rate_scan_ladder` 重点看：

- `actual_send_rate_req_per_sec`
- `goodput_result_per_sec`
- `wire_goodput_gbps`
- `payload_goodput_gbps`
- `drop_count`
- `drop_ratio`
- `measurement_valid`

`burst_fifo` 重点看：

- `batch_completion_time_us`
- `throughput_req_per_sec`
- `sender_capture_count`
- `receiver_capture_count`
- `engine_emit_count`
- `pipeline_verdict`

`run_fastdata.sh` 的重点是：

- 直接复用已通过的 `single_packet` 与 `rate_scan` baseline
- 只新增更高速率的 `rate_scan_extend`
- 只新增避开已知 bug 的 `burst_safe_subset`
