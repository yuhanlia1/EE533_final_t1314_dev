# NetFPGA v8 Software Toolchain

`sw/` 是当前 `v8` 主线的软件真值源。

它覆盖三部分：

- 硬件控制：`annctl`
- 编译/打包：`cpuctl`、`gpuctl`、`annmodelctl`
- 板级协议与离线 compare：`board_debug`

## Main Entry Points

- `perl sw/annctl ...`
- `python3 sw/cpuctl ...`
- `python3 sw/gpuctl ...`
- `python3 sw/annmodelctl ...`

当前推荐日常入口是：

- 模型 bundle：`annmodelctl`
- 板测编排：`scripts/board/*`
- 低层协议调试：`sw/board_debug/*`

## Dependencies

- `python3 >= 3.9`
  - `cpuctl`、`gpuctl`、`annmodelctl`
- `perl >= 5.8`
  - `annctl`
- root 或 `CAP_NET_RAW`
  - 仅当本地使用 `board_debug` raw-socket live send/recv 时需要

当前仓库已经不再维护 MNIST example flow；软件依赖以 RSU 主线为准。

## Register Defines

当前软件侧寄存器真值是：

- `sw/reg_defines_v8.h`

兼容 fallback 仍保留：

- `sw/reg_defines_v7.h`
- `sw/reg_defines_v5.h`

但它们不是当前 bitfile 真值。

## Tool Roles

### `annctl`

硬件控制唯一真值出口，负责：

- 寄存器读写
- CPU image load
- GPU IMEM load
- GPU param load
- engine enable / status / debug-clear / debug-status

### `cpuctl`

CPU 汇编链路：

- 预处理
- 汇编
- 调度
- 产出 `image.txt`

### `gpuctl`

GPU 程序/参数链路：

- 解析 `.gpus`
- 汇编
- 产出 GPU IMEM / params

### `annmodelctl`

当前推荐的高层模型入口：

- 读取模型 manifest
- 自动生成 CPU/GPU 工件
- 输出 bundle

### `board_debug`

协议共享库与低层调试工具：

- 构造/解析 ANN UDP 帧
- `pcap` 读写
- batch compare
- raw-socket live send/recv

## Current Recommended Flow

### 本地构建

```bash
python3 sw/annmodelctl build dataset/export/rsu_ann_model_int16.json --out-dir /tmp/rsu_bundle
```

### USC 正式板测

```bash
bash scripts/board/rsu_demo.sh prepare \
  --bitfile nw_proc4_2_moreobserve.bit \
  --limit 4 \
  --out-dir /tmp/rsu_run \
  --force

bash scripts/board/bringup.sh /tmp/rsu_run/manifest.json
bash scripts/board/capture.sh /tmp/rsu_run/manifest.json
bash scripts/board/report.sh /tmp/rsu_run/manifest.json
```

### 本地软件检查

```bash
perl sw/tests/annctl/test_anncontrol.t
bash scripts/check/sw_unit.sh
bash scripts/check/sw_integration.sh
```

## Current Truth Boundaries

- 当前正式板测结论以 `scripts/board/*` 和根目录板测报告为准
- 当前正式模型主线是 RSU，不再同时维护 MNIST example
- 当前 USC 真板已验证的是 RSU `compact_class_score` 主线
