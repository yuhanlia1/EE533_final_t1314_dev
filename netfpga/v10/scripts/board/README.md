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
python3 scripts/board/demo_verify.py --config scripts/board/rsu_demo_verify.json
python3 scripts/board/demo_verify.py --config scripts/board/rsu_demo_single_infer.json --view engine-single
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics.json
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics_rate_only.json
bash scripts/board/rsu_demo.sh engine-metrics
bash scripts/board/rsu_demo.sh engine-toolchain --out-dir /tmp/rsu_engine_build
bash scripts/board/rsu_demo.sh engine-single-infer --out-dir /tmp/rsu_engine_single_infer --force
bash scripts/board/rsu_demo.sh zero-copy-init --out-dir /tmp/rsu_zero_copy_demo --force
bash scripts/board/rsu_demo.sh zero-copy-threshold --run-dir /tmp/rsu_zero_copy_demo --windows-ms 1600,800,400,200,100,50,10,1
bash scripts/board/rsu_demo.sh zero-copy-limit --run-dir /tmp/rsu_zero_copy_demo --window-ms 50
bash scripts/board/rsu_demo.sh zero-copy-path --run-dir /tmp/rsu_zero_copy_demo
bash scripts/board/rsu_demo.sh protocol-init --out-dir /tmp/rsu_protocol_demo --force
bash scripts/board/rsu_demo.sh protocol-bypass --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-wrong-magic --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-offload --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh other-pros-rate-init --out-dir /tmp/rsu_other_pros_rate_demo --force
bash scripts/board/rsu_demo.sh other-pros-rate-scan --run-dir /tmp/rsu_other_pros_rate_demo --rates 10,25,50,100,200,400,800,1200,1600,2000,2400
bash scripts/board/rsu_demo.sh other-pros-throughput
bash scripts/board/rsu_demo.sh other-pros-power
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

bash scripts/board/rsu_demo.sh demo-verify \
  --out-dir /tmp/rsu_demo_verify \
  --force

bash scripts/board/rsu_demo.sh engine-metrics

bash scripts/board/rsu_demo.sh engine-toolchain \
  --out-dir /tmp/rsu_engine_build

bash scripts/board/rsu_demo.sh engine-single-infer \
  --out-dir /tmp/rsu_engine_single_infer \
  --force

bash scripts/board/rsu_demo.sh zero-copy-init \
  --out-dir /tmp/rsu_zero_copy_demo \
  --force

bash scripts/board/rsu_demo.sh zero-copy-threshold \
  --run-dir /tmp/rsu_zero_copy_demo \
  --windows-ms 1600,800,400,200,100,50,10,1

bash scripts/board/rsu_demo.sh zero-copy-limit \
  --run-dir /tmp/rsu_zero_copy_demo \
  --window-ms 50

bash scripts/board/rsu_demo.sh zero-copy-path \
  --run-dir /tmp/rsu_zero_copy_demo

bash scripts/board/rsu_demo.sh other-pros-rate-init \
  --out-dir /tmp/rsu_other_pros_rate_demo \
  --force

bash scripts/board/rsu_demo.sh other-pros-rate-scan \
  --run-dir /tmp/rsu_other_pros_rate_demo \
  --rates 10,25,50,100,200,400,800,1200,1600,2000,2400

bash scripts/board/rsu_demo.sh other-pros-throughput

bash scripts/board/rsu_demo.sh other-pros-power

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

当前若只验证 demo 第一节 `Customized NetworkProtocol`，推荐直接跑：

```bash
bash scripts/board/rsu_demo.sh protocol-init \
  --password-file ssh_passkey.txt \
  --out-dir /tmp/rsu_protocol_demo_round1 \
  --force
```

```bash
bash scripts/board/rsu_demo.sh protocol-bypass \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_protocol_demo_round1
```

```bash
bash scripts/board/rsu_demo.sh protocol-wrong-magic \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_protocol_demo_round1
```

```bash
bash scripts/board/rsu_demo.sh protocol-offload \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_protocol_demo_round1
```

当前若只验证 demo 第三节 `Zero Host/OS Copy`，推荐直接跑：

```bash
bash scripts/board/rsu_demo.sh zero-copy-init \
  --password-file ssh_passkey.txt \
  --out-dir /tmp/rsu_zero_copy_demo_round1 \
  --force
```

```bash
bash scripts/board/rsu_demo.sh zero-copy-threshold \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_zero_copy_demo_round1 \
  --windows-ms 1600,800,400,200,100,50,10,1
```

```bash
bash scripts/board/rsu_demo.sh zero-copy-limit \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_zero_copy_demo_round1 \
  --window-ms 50
```

```bash
bash scripts/board/rsu_demo.sh zero-copy-path \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_zero_copy_demo_round1
```

当前若只展示 demo 第四节 `Other Pros`，推荐直接跑：

```bash
bash scripts/board/rsu_demo.sh other-pros-rate-init \
  --password-file ssh_passkey.txt \
  --out-dir /tmp/rsu_other_pros_rate_demo_round1 \
  --force
```

```bash
bash scripts/board/rsu_demo.sh other-pros-rate-scan \
  --password-file ssh_passkey.txt \
  --run-dir /tmp/rsu_other_pros_rate_demo_round1 \
  --rates 10,25,50,100,200,400,800,1200,1600,2000,2400
```

静态 fallback：

```bash
bash scripts/board/rsu_demo.sh other-pros-throughput
```

```bash
bash scripts/board/rsu_demo.sh other-pros-power
```

当前这两条命令的默认数据源分别是：

- `other-pros-rate-init / other-pros-rate-scan`
  - `scripts/board/rsu_demo_other_pros_rate.json`
  - live `rate_scan` via `board_metrics.py`
- `other-pros-throughput`
  - `bt/system_report/summary.json`
  - `bt/report/round1_rate_scan.csv`
  - `bt/system_report/figures/rate_scan_energy_validity.png`
- `other-pros-power`
  - `pd/asic_report/pnr/user_top/reports/4_postroute_power.rpt`

其中：

- `other-pros-rate-scan` 是第四节高流量展示的正式主入口
- 高流量稳定性当前固定展示 `max_zero_loss_pps = 2000.0`
- 第一个 overload 点当前固定展示 `first_overload_pps = 2400.0`
- `other-pros-throughput` 继续保留为静态 fallback
- 功耗当前固定展示 `ASIC post-route total power = 2.03e-02 W`
- `pd/asic_report/pnr/user_top/` 下面没有现成版图 PNG，因此本轮 power demo 走静态 report，不走 layout screenshot

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
- `demo_verify.py`
  - `<out_dir>/<run_name>/...`
  - `<out_dir>/summary.json`
  - `<out_dir>/summary.md`
  - `<out_dir>/demo_summary.json`
  - `<out_dir>/demo_summary.md`
- `zero_copy_demo.py`
  - `<run_dir>/zero_copy_demo_summary.json`
  - `<run_dir>/zero_copy_demo_summary.md`
  - `<run_dir>/zero_copy_threshold_summary.json`
  - `<run_dir>/zero_copy_threshold_summary.md`
  - `<run_dir>/zero_copy_limit_summary.json`
  - `<run_dir>/zero_copy_limit_summary.md`
  - `<run_dir>/zero_copy_path_summary.json`
  - `<run_dir>/zero_copy_path_summary.md`

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
- `rsu_demo_verify.json` 作为 demo 风格的 correctness smoke 入口
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
