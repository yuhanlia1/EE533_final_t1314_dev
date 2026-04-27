# Deploy Layout

`deploy/` 保存当前 `v8` 主线在 USC 环境中的运行镜像。

当前正式、已验证的上板路径是：

- `nf3`: `annctl`, `nf_download`, `rkd`
- `nf4`: `tcpreplay`, sender-side `tcpdump`
- `nf1`: `tcpdump`
- 本地：`scripts/board/report.sh` 做离线 compare
- 本地：`scripts/board/board_metrics.py` 做 NIC 指标编排

## Roles

- `buildhost/`
  - 本地现代 Python 环境
  - 运行 `cpuctl`、`gpuctl`、`annmodelctl`
- `netfpga/`
  - USC 主节点控制包
  - 运行 `annctl`
- `node0/` / `node2/`
  - 历史兼容镜像
  - 保留供旧环境或非正式 raw-socket 调试参考
  - 不是当前正式 USC 板测主路径

## Current USC Layout

当前推荐目录约定：

- 主节点：
  - `~/scripts/v8/<run_name>_netfpga`
  - `~/scripts/v8/<run_name>_results`
- sender：
  - `~/v8/<run_name>_sender`
- receiver：
  - `~/v8/<run_name>_receiver`

主节点只假设 `~/scripts/v8` 可写；sender/receiver 只假设 `~/v8` 可写。

## Recommended Flow

从仓库根目录：

```bash
bash scripts/board/prepare.sh ...
bash scripts/board/bringup.sh <run_dir>/manifest.json
bash scripts/board/capture.sh <run_dir>/manifest.json
bash scripts/board/report.sh <run_dir>/manifest.json
```

如果目标是当前 RSU demo，优先使用：

```bash
bash scripts/board/rsu_demo.sh prepare --bitfile nw_proc4_2_moreobserve.bit ...
```

## Notes

- 当前结果包语义以 `src/` 和 `scripts/board/` 为准，不再以旧 `v7` 文档为准。
- 当前 USC 真板已验证的是 RSU 主线和 `compact_class_score` 结果模式。
- 当前 `rate_scan` 的正式通过条件以 `measurement_valid = true` 为准。
- `node0/` / `node2/` 可继续保留，但不应再被描述成当前正式板测真值路径。
