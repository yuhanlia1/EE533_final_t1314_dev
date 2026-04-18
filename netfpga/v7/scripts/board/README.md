# Board Workflow

`scripts/board/` 提供正式 USC 板测的编排入口，目标是把当前分散的：

- bundle 生成
- pcap 生成
- `nf3` bring-up
- `nf4` 回放
- `nf1` 抓包
- 本地离线 compare

收敛成一套共享 `manifest.json` 的工作流。

## Entry Points

```bash
bash scripts/board/prepare.sh --limit 2
bash scripts/board/bringup.sh runs/<run_name>/manifest.json
bash scripts/board/capture.sh runs/<run_name>/manifest.json
bash scripts/board/report.sh runs/<run_name>/manifest.json
```

也可以直接使用：

```bash
python3 scripts/board/boardctl.py <subcommand> ...
```

## What Each Step Produces

- `prepare`
  - `bundle/`
  - `board_test_vectors.json`
  - `board_expected_outputs.json`
  - `pcaps/*.pcap`
  - `manifest.json`
- `bringup`
  - `commands/local_stage_netfpga.sh`
  - `commands/nf3_bringup.sh`
- `capture`
  - `commands/nf1_capture_*.sh`
  - `commands/nf4_replay_*.sh`
  - `commands/local_fetch_captures.sh`
- `report`
  - `observed_results.json`
  - `board_eval_report.json`
  - `board_test_summary.md`

## Current Assumptions

- 正式 bitfile 默认是 `nw_proc3_udp1.bit`
- 正式寄存器头默认是顶层 `reg_defines_v7.h`
- USC 默认主机是：
  - `netfpga@nf3.usc.edu`
  - `node3@nf4.usc.edu`
  - `node3@nf1.usc.edu`
- 正式 sender/receiver 接口默认是：
  - `nf4:port0`
  - `nf1:port2`
- 当前正式、已验证的板测模式仍是：
  - `annctl + tcpreplay + tcpdump + 离线 compare`
