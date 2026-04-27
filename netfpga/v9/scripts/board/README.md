# Board Workflow

`scripts/board/` 是当前正式 USC 板测编排入口。

它把这些步骤收敛到一份共享 `manifest.json`：

- bundle 生成
- `pcap` 生成
- `nf3` bring-up
- `nf4` 回放
- `nf1` 抓包
- 本地离线 compare

## Entry Points

```bash
bash scripts/board/prepare.sh ...
bash scripts/board/bringup.sh <run_dir>/manifest.json
bash scripts/board/capture.sh <run_dir>/manifest.json
bash scripts/board/report.sh <run_dir>/manifest.json
bash scripts/board/run_sweep.sh --config scripts/board/rsu_demo_sweep.json
bash scripts/board/run_sweep.sh --config scripts/board/rsu_demo_batch5_single.json
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics.json
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics_rate_only.json
```

密码输入规则：

- 默认不带 `--password-file` 时，命令启动后会提示手动输入一次 USC 密码
- 若要走文件模式，可显式传 `--password-file ssh_passkey.txt`
- `ssh_passkey.txt` 的内容必须只有一行纯密码，例如 `r006+vYeW0Or`

当前 RSU demo 的固定入口是：

```bash
bash scripts/board/rsu_demo.sh metrics
bash scripts/board/rsu_demo.sh prepare \
  --bitfile nw_proc4_2_moreobserve.bit \
  --limit 4 \
  --out-dir /tmp/rsu_demo_run \
  --force

bash scripts/board/rsu_demo.sh sweep \
  --out-dir /tmp/rsu_demo_sweep \
  --force

bash scripts/board/run_sweep.sh \
  --config scripts/board/rsu_demo_batch5_single.json \
  --out-dir /tmp/rsu_demo_batch5 \
  --force

bash scripts/board/rsu_demo.sh nic-metrics \
  --out-dir /tmp/rsu_nic_metrics \
  --force

python3 scripts/board/board_metrics.py \
  --config scripts/board/rsu_nic_metrics_rate_only.json \
  --out-dir /tmp/rsu_nic_metrics_rate_only \
  --force
```

## What Each Step Produces

- `prepare`
  - `bundle/`
  - `board_test_vectors.json`
  - `board_expected_outputs.json`
  - `pcaps/*.pcap`
  - `manifest.json`
- `bringup`
  - `commands/nf3_bringup.sh`
- `capture`
  - `commands/nf1_capture_*.sh`
  - `commands/nf4_replay_*.sh`
  - `commands/nf4_capture_offload_batch_sender.sh`
- `report`
  - `observed_results.json`
  - `board_eval_report.json`
  - `board_test_summary.md`
- `run_sweep`
  - `<out_dir>/<run_name>/...`
  - `<out_dir>/summary.json`
  - `<out_dir>/summary.md`
- `board_metrics.py`
  - `<out_dir>/<run_name>/...`
  - `<out_dir>/summary.json`
  - `<out_dir>/summary.md`

## Current Board-Test Truth

- 当前正式 bitfile 应显式传入；最近一次正式验证使用：
  - `nw_proc4_2_moreobserve.bit`
- 当前寄存器真值：
  - 根目录 `reg_defines_v8.h`
- 当前正式 USC 路径：
  - `annctl + tcpreplay + tcpdump + 本地离线 compare`
- 当前正式自动化真值：
  - `batch5_single` 已在真板 PASS
  - `batch4 / batch5 / batch6` 正式 sweep 已在真板 PASS
  - `rsu_nic_metrics_rate_only.json` 已在真板 PASS（`10 / 25 / 50 pps`）

## Current Usage

当前推荐的板测使用方式是：

- `rsu_demo_sweep.json` 作为正式展示和主流程入口
- `rsu_demo_batch5_single.json` 作为最小 smoke run
- `rsu_nic_metrics.json` 作为 NIC 性能测量入口
- `rsu_nic_metrics_rate_only.json` 作为 rate-scan 定向调试入口
- `rate_scan` 当前以 `measurement_valid` 作为正式通过判据，不再只看 `pipeline_verdict`
- 当前 `rate_only` 真板已确认 `10 / 25 / 50 pps` 都 `measurement_valid = true`
- 代码中保留 receiver capture fallback，但它不是日常入口
- 当前不再围绕 receiver capture 机制做排障性开发

后续若继续使用这套流程，主要目标应转为 NIC 常规指标测量，例如：

- throughput
- batch completion time
- rate scan / goodput
- repeated-run stability

当前 `board_metrics.py` 里的 `latency_single` 只保留为 single-packet correctness/completion check。
在 USC 现网环境下，`nf4` 与 `nf1` 主机时钟没有同步，因此跨主机 `pcap` 时间戳直减不再作为正式 latency 指标。
当前 `rate_scan` 会先尝试 `paced_pcap_single_replay`，必要时自动降到 `chunked_replay_fallback`；summary 里要重点看：

- `rate_generation_mode_used`
- `actual_send_rate_req_per_sec`
- `rate_error_ratio`
- `measurement_valid`

当前建议的顺序是：

1. `rsu_nic_metrics_rate_only.json`
2. `rsu_nic_metrics.json`
