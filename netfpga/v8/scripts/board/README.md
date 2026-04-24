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
```

当前 RSU demo 的固定入口是：

```bash
bash scripts/board/rsu_demo.sh metrics
bash scripts/board/rsu_demo.sh prepare \
  --bitfile nw_proc4_2_moreobserve.bit \
  --limit 4 \
  --out-dir /tmp/rsu_demo_run \
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

## Current Board-Test Truth

- 当前正式 bitfile 应显式传入；最近一次正式验证使用：
  - `nw_proc4_2_moreobserve.bit`
- 当前寄存器真值：
  - 根目录 `reg_defines_v8.h`
- 当前正式 USC 路径：
  - `annctl + tcpreplay + tcpdump + 本地离线 compare`

## Known Board-Test Note

当前 ANN 主路径已经板上跑通，但 receiver capture 首轮仍观察到一个边界现象：

- 首轮 `batch4_a` 时 receiver 漏掉首个结果包
- 同一次会话中继续跑 `batch5`、`batch6`、再回 `batch4_b` 时恢复正常

因此，当前正式抓包建议是：

- receiver 提前启动
- 默认使用 time-window capture
- time-window 保守留足余量
