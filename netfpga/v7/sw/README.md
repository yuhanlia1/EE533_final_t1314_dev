# NetFPGA v7 Software Toolchain

`/sw` 目录包含 NetFPGA 1G ANN offload 项目的全套软件链路，从 ARM 汇编编译、
GPU bundle 打包，到板级调试帧收发，每一层都有独立的入口工具。

---

## 目录

1. [总体架构](#1-总体架构)
2. [环境依赖](#2-环境依赖)
3. [寄存器地址文件](#3-寄存器地址文件)
4. [annctl — 硬件控制底层](#4-annctl--硬件控制底层)
5. [cpuctl — CPU 汇编工具链](#5-cpuctl--cpu-汇编工具链)
6. [gpuctl — GPU 汇编工具链](#6-gpuctl--gpu-汇编工具链)
7. [annmodelctl — MLP 模型自动化入口](#7-annmodelctl--mlp-模型自动化入口)
8. [mnist_toolchain — Binary-MNIST 训练导出](#8-mnist_toolchain--binary-mnist-训练导出)
9. [board_debug — 板级调试工具](#9-board_debug--板级调试工具)
10. [回归脚本](#10-回归脚本)
11. [典型工作流程](#11-典型工作流程)
12. [文件格式说明](#12-文件格式说明)
13. [硬件约束与限制](#13-硬件约束与限制)

---

## 1. 总体架构

```
┌──────────────────────────────────────────────────────────────────────┐
│              可选: Binary-MNIST 训练/导出                             │
│   mnist_toolchain/train_binary.py  →  export_binary.py              │
│                           ↓ 产出 model.json                          │
├──────────────────────────────────────────────────────────────────────┤
│                  高层模型入口 (推荐日常使用)                           │
│                       annmodelctl                                     │
│         读 model.json → 自动生成 CPU .s + GPU .gpus                  │
│                   ↓ 内部调用下层工具                                  │
├─────────────────────────┬────────────────────────────────────────────┤
│   CPU 编译链             │   GPU 编译链                               │
│   cpuctl                │   gpuctl                                   │
│   cpu_toolchain/        │   gpu_toolchain/                           │
│     preprocess.py       │     parser.py                              │
│     assembler.py        │     assembler.py                           │
│     scheduler.py        │     bundle.py                              │
│     toolchain.py        │                                            │
│   输入: .s ARM 汇编      │   输入: .gpus GPU 汇编                    │
├─────────────────────────┴────────────────────────────────────────────┤
│                  硬件控制底层 (所有工具的最终出口)                     │
│                       annctl  (Perl)                                  │
│              lib/NetFPGA/ANNControl.pm                               │
│              reg_defines_v7.h  ←── 地址真值源                        │
│                         ↓ reg_req 总线                               │
│                   NetFPGA 1G 硬件寄存器窗口                           │
├──────────────────────────────────────────────────────────────────────┤
│              板级调试工具 (独立运行，不依赖上层编译链)                 │
│   board_debug/send_ann_offload.py    — 发 UDP ANN task 包            │
│   board_debug/recv_ann_result.py     — 收 UDP in-place result 包     │
│   board_debug/run_ann_model_batch.py — 批量发包 / 离线对比           │
│   (底层: board_debug/ann_packets.py  — UDP 协议构造/解析)            │
└──────────────────────────────────────────────────────────────────────┘
```

**调用链规则：**
- `cpuctl` / `gpuctl` / `annmodelctl` 在所有 `*-load` 类命令中以子进程方式
  调用 `annctl`。
- `annctl` 是唯一与 FPGA 寄存器总线直接通信的工具；其他工具不直接操作硬件。
- `board_debug/` 脚本通过 Linux raw socket 直接收发以太帧，不经过 `annctl`。

---

## 2. 环境依赖

| 依赖 | 用途 | 备注 |
|------|------|------|
| `python3 >= 3.9` | cpuctl / gpuctl / annmodelctl / mnist_toolchain | 本地 build host 使用 |
| `python 2.4+` 或 `python3` | board_debug | 远端 node0-3 运行时脚本，已在 USC `python 2.4.3` 下验证 |
| `perl >= 5.8` | annctl | 兼容旧版 `File::Path` 的实验机 Perl |
| `torch` + `torchvision` | mnist_toolchain/train_binary.py | 仅训练时需要，其余路径不需要 |
| root / `CAP_NET_RAW` | board_debug send/recv | raw AF_PACKET socket 收发 |

`sw/` 目录本身不需要 `make install`，直接以相对路径或绝对路径调用各入口即可。

对于 USC NetFPGA 1G 实验环境，默认应采用“两段式”流程：

- 本地现代环境运行 `cpuctl` / `gpuctl` / `annmodelctl` 做 `build`
- 远端 `netfpga` 主节点只运行 `annctl`
- 远端 `node0-3` 只运行 `board_debug` 运行时脚本

不要假定实验机上存在 `python3`。

---

## 3. 寄存器地址文件

```
sw/reg_defines_v7.h
```

这是软件侧寄存器地址的**主真值源**。`annctl` 启动时优先读取此文件来解析
`USER_TOP_*` 符号名；仅为兼容历史目录时才回退到 `reg_defines_v5.h`。

当综合重新生成寄存器映射时，需要同步更新此文件，否则 `annctl` 的符号名访问会
报错。

当前已定义的寄存器（地址以 `0x2000100` 为基址）：

| 符号名 (短名) | 地址 | 权限 | 说明 |
|---|---|---|---|
| `sw_d_mem_addr` | `0x2000100` | rw | CPU DMEM 地址窗口 |
| `sw_i_mem_wdata` | `0x2000104` | rw | CPU IMEM 写数据 |
| `sw_i_mem_addr` | `0x2000108` | rw | CPU IMEM 地址/触发 |
| `sw_engine_ctrl` | `0x200010c` | rw | Engine 控制（见下） |
| `sw_gpu_i_mem_wdata` | `0x2000110` | rw | GPU IMEM 写数据 |
| `sw_gpu_i_mem_addr` | `0x2000114` | rw | GPU IMEM 地址/触发 |
| `sw_gpu_w_mem_wdata_1` | `0x2000118` | rw | GPU 参数写数据 hi32 |
| `sw_gpu_w_mem_wdata_0` | `0x200011c` | rw | GPU 参数写数据 lo32 |
| `sw_gpu_w_mem_addr` | `0x2000120` | rw | GPU 参数地址/触发 |
| `sw_gpu_ofmap_addr` | `0x2000124` | rw | GPU ofmap 读地址 |
| `hw_reserved_0` | （见文件）| ro | CPU IMEM 读回口 |
| `hw_reserved_1` | （见文件）| ro | CPU DMEM 低32位读回口 |

`sw_engine_ctrl` 位域：

```
bit 0      engine enable
bit 1      compact result mode (result_data_0 = class_id, result_data_1 = score)
bits[15:8] output_count
bits[31:16] output_base
```

---

## 4. annctl — 硬件控制底层

**入口：** `perl sw/annctl <group> <command> [args...]`

### 4.1 寄存器访问

```bash
perl sw/annctl regs list                        # 列出所有寄存器（名称/地址/权限）
perl sw/annctl regs read <name|addr>            # 读一个寄存器
perl sw/annctl regs write <name|addr> <value>   # 写一个寄存器
perl sw/annctl regs dump                        # 打印所有寄存器当前值
```

`<name>` 可以是短名（`sw_engine_ctrl`）、符号名（`USER_TOP_SW_ENGINE_CTRL_REG`）
或裸十六进制地址（`0x200010c`）。

### 4.2 CPU 操作

```bash
# 写入
perl sw/annctl cpu load <path> [base_addr]      # 加载 IMEM 镜像文件（格式见 §12）
perl sw/annctl cpu write <addr> <word32>        # 写 CPU IMEM 单条

# 本地 shadow（读 annctl 最后一次写入的缓存，非硬件）
perl sw/annctl cpu shadow-read <addr>
perl sw/annctl cpu shadow-dump <start> <count>

# 硬件真实读回（通过 hw_reserved_0/1）
perl sw/annctl cpu hw-imem-read <addr>
perl sw/annctl cpu hw-imem-dump <start> <count>
perl sw/annctl cpu hw-dmem-read <addr>
perl sw/annctl cpu hw-dmem-dump <start> <count>
```

### 4.3 GPU 操作

```bash
# IMEM
perl sw/annctl gpu imem-write <addr> <word32>
perl sw/annctl gpu imem-load <path> [base_addr]
perl sw/annctl gpu imem-shadow-read <addr>
perl sw/annctl gpu imem-shadow-dump <start> <count>

# 参数（权重/偏置，64-bit 格式）
perl sw/annctl gpu param-write <addr> <data64|hi32 lo32>
perl sw/annctl gpu param-load <path>
perl sw/annctl gpu param-shadow-read <addr>
perl sw/annctl gpu param-shadow-dump <start> <count>

# 输出 DMEM 读回
perl sw/annctl gpu ofmap-read <addr>
perl sw/annctl gpu ofmap-dump <start> <count>
```

### 4.4 Engine 控制

```bash
perl sw/annctl engine status                              # 打印 ready/programmed 位
perl sw/annctl engine enable                              # 使能 ANN offload engine
perl sw/annctl engine disable                             # 关闭 engine
perl sw/annctl engine result-config <base> <count> [compact|legacy]
perl sw/annctl engine result-clear
```

`compact` 模式下结果帧语义：`result_data_0 = class_id`，`result_data_1 = score`。
`legacy` 模式下两字段由 GPU runtime 直接写入，不做重新映射。

```bash
perl sw/annctl reset-state                                # 清除本地 shadow 状态
```

---

## 5. cpuctl — CPU 汇编工具链

**入口：** `python3 sw/cpuctl <command> [args...]`

**输入格式：** ARM `.s` 汇编文件，使用项目定制语法（见 §12.1）。

### 5.1 命令一览

| 命令 | 说明 |
|------|------|
| `build <src.s> --out-dir <dir>` | 编译单线程汇编，产出 IMEM 镜像 |
| `build-load <src.s> --out-dir <dir>` | 编译并通过 `annctl` 载入硬件 |
| `package <pkg_dir> --out-dir <dir>` | 编译 4-thread 包目录 |
| `package-load <pkg_dir> --out-dir <dir>` | 4-thread 编译并载入 |
| `load <image.txt> --base <addr>` | 直接加载已有 IMEM 镜像（不重新编译） |
| `inspect <src.s\|pkg_dir>` | 预览编译结果（不写硬件，不保留产出目录） |

`--out-dir` 可以省略，省略时自动使用 `/tmp/cpuctl_build_<random>/`。

### 5.2 4-thread 包目录规范

```
pkg_dir/
  thread0.s       # 必须存在，其余线程缺失时自动填充 halt stub
  thread1.s       # 可选
  thread2.s       # 可选
  thread3.s       # 可选
```

### 5.3 编译产出文件

`build` 产出（`--out-dir` 下）：

```
processed.s           # 伪指令展开后的源码
scheduled.s           # RAW hazard 插 NOP 后的源码
compiled_binary.txt   # 裸十六进制，每行一条 32-bit 指令
image.txt             # addr+word 格式，供 annctl cpu load 使用
build_report.txt      # 文本报告（thread 数、NOP 数、hazard 列表）
```

`package` 额外产出：

```
thread{0..3}.processed.s
thread{0..3}.scheduled.s
thread{0..3}.hex
cpu_image.txt        # 四线程合并后的 addr+word 镜像
image_map.txt        # 各线程 base 地址映射表
build_report.txt
```

### 5.4 内部编译流程

```
.s 源码
  ↓  preprocess.py — 伪指令展开（ldmia/stmia/ldm/stm/ldr literal）
  ↓  assembler.py  — 第一遍解析（标签解析，操作数检查）
  ↓  scheduler.py  — RAW hazard 扫描，插入 mov r5, r5 NOP
  ↓  assembler.py  — 第二遍编译，输出 32-bit words
```

---

## 6. gpuctl — GPU 汇编工具链

**入口：** `python3 sw/gpuctl <command> [args...]`

**输入格式：** `.gpus` 文本汇编文件（见 §12.2）。

### 6.1 命令一览

| 命令 | 说明 |
|------|------|
| `build <prog.gpus> --out-dir <dir>` | 编译单个 GPU 程序 |
| `package <bundle_dir> --out-dir <dir>` | 打包 bundle 目录 |
| `load-program <imem.txt> [--base <addr>]` | 加载 GPU IMEM 镜像 |
| `load-params <params.txt>` | 加载 GPU 权重参数 |
| `load-bundle <bundle_dir>` | bundle 目录一次性加载（program + params） |
| `inspect <prog.gpus\|bundle_dir>` | 解析预览，不写硬件 |
| `template mlp --in-dim N --out-dim M [--work-size K]` | 生成单层 MLP bundle 模板源文件 |

### 6.2 bundle 目录规范

```
bundle_dir/
  program.gpus    # 必须存在
  params.txt      # 可选，权重/偏置（格式见 §12.3）
  meta.json       # 可选，运行时元数据
```

### 6.3 编译产出文件

```
processed.gpus          # 规范化后的汇编源
compiled_gpu_imem.txt   # 裸十六进制 GPU IMEM 镜像
compiled_gpu_params.txt # 规范化后的参数文件（addr hi32 lo32）
meta.json               # 规范化后的 meta（若原始存在）
gpu_program_report.txt  # 或 gpu_bundle_report.txt
```

### 6.4 meta.json 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `entry_pc` | u16 | GPU 程序入口 PC |
| `tid_init` | u32 | 初始 thread id |
| `work_size` | u32 | 并行 lane 数 |
| `base_a/b/c/d` | u64 | 四个 DMEM bank 基地址 |
| `m`, `n`, `k` | u32 | 矩阵维度（可选，供 CPU runtime 读取） |

---

## 7. annmodelctl — MLP 模型自动化入口

**入口：** `python3 sw/annmodelctl <command> [args...]`

**输入格式：** `model.json` 量化 int16 MLP manifest（见 §12.4）。

`annmodelctl` 及其底层 `sw/model_toolchain/` 是当前仓库里唯一的 ANN model bundle 构建真值源。模型输入/输出维度约束、bundle 布局和 wire result 语义都以这里为准。

### 7.1 命令一览

| 命令 | 说明 |
|------|------|
| `build <model.json> --out-dir <dir>` | 生成完整 bundle（CPU .s、GPU .gpus、参数、测试向量） |
| `inspect <model.json>` | 检查 manifest 硬件约束，预览层结构 |
| `load-bundle <bundle_dir>` | 加载已 build 的 bundle（CPU IMEM + GPU IMEM + params） |
| `build-load <model.json> --out-dir <dir>` | build + load 一步完成 |

### 7.2 build 产出文件

```
manifest.json           # 规范化后的 model.json 副本
cpu_runtime.s           # 自动生成的 ARM runtime（初始化 GPU 并等待结果）
cpu_image.txt           # 编译后的 CPU IMEM 镜像
gpu_program.gpus        # 自动生成的 GPU MLP kernel
gpu_imem.txt            # 编译后的 GPU IMEM 镜像
gpu_params.txt          # 量化权重/偏置参数
bundle_report.txt       # 完整 bundle 报告
test_vectors.json       # 所有 tests 字段的输入特征向量
expected_outputs.json   # 对应的 golden logits / predicted class
```

### 7.3 model.json 格式（精简示例）

```json
{
  "model_type": "mlp",
  "quant_type": "int16",
  "input_dim": 8,
  "labels": ["class0", "class1"],
  "layers": [
    {
      "out_dim": 4,
      "activation": "relu",
      "weights": [[1, 1, -1, 0, 0, 0, 0, 0], ...],
      "bias": [0, 0, 0, 0]
    },
    {
      "out_dim": 2,
      "activation": "none",
      "weights": [[1, 1, -1, 0], [0, 0, 1, 1]],
      "bias": [0, 0]
    }
  ],
  "tests": [
    {"name": "sample_class0", "input": [3, 2, 1, 1, 2, 0, 1, 0]}
  ]
}
```

---

## 8. mnist_toolchain — Binary-MNIST 示例工具

位于 `sw/mnist_toolchain/`，所有脚本独立运行，不是 CLI 子命令。

这组脚本是 binary-MNIST 示例与数据准备工具，不是第二套模型 bundle 主线。通用量化 MLP 的 build/load 仍然以 `annmodelctl` 为主；`mnist_toolchain` 负责把一个稳定的 binary example 导出成 `annmodelctl` 可消费的 `model.json`。

| 脚本 | 用法示例 | 说明 |
|------|----------|------|
| `train_binary.py` | `python3 sw/mnist_toolchain/train_binary.py --out-dir /tmp/mnist --hidden-dim 8` | 训练 binary-MNIST 0-vs-1 MLP（需 PyTorch） |
| `export_binary.py` | `python3 sw/mnist_toolchain/export_binary.py --checkpoint /tmp/mnist/model.pt --out /tmp/model.json` | 将 checkpoint 导出为 `annmodelctl` 可消费的 `model.json` |
| `eval_binary.py` | `python3 sw/mnist_toolchain/eval_binary.py --observed obs.json --expected golden.json` | 板上结果与 golden 对比 |
| `feature_extract.py` | （被其他脚本 import，不直接调用） | 将 28×28 MNIST 图像压缩为 8 个定点特征 |

训练导出后的接续流程：

```
export_binary.py → model.json → annmodelctl build-load → FPGA
```

稳定回归 fixture 位于 `sw/testdata/mnist_binary_01/fixture_model.json`，不需要 PyTorch 即可运行。当前 repo 中与 MNIST 相关的自动化验证入口是 `bash scripts/check/examples_binary_mnist.sh`。

---

## 9. board_debug — 板级调试工具

位于 `sw/board_debug/`，所有脚本需要板卡已编程且网络接口已接好。
这组运行时脚本保持在 Python 2.4 / 3.x 兼容子集内，适合直接放到
USC 的 `node0-3` 主机上运行。

### 9.1 send_ann_offload.py — 发送 UDP ANN offload 帧

```bash
# 仅打印帧结构（dry-run，不需要 root）
python sw/board_debug/send_ann_offload.py --dump-json

# 指定显式特征值
python sw/board_debug/send_ann_offload.py --dump-json --feature-values "3,2,1,1,2,0,1,0"

# 实际发包（需要 root）
sudo python sw/board_debug/send_ann_offload.py --send --iface eth0

# 常用选项
# --dst-mac / --src-mac      目的/源 MAC 地址
# --src-ip / --dst-ip        IPv4 源/目的地址
# --src-udp-port             UDP 源端口 (默认 0x4000)
# --dst-udp-port             UDP 目的端口 (默认 0x88b5)
# --request-id               请求 ID，用于 result 帧匹配 (默认 0x1234)
# --feature-count            特征数量 (默认 8)
# --repeat <N>               重复发包次数
# --interval-ms <N>          重复间隔 ms
```

默认帧参数（与 RTL/TB 一致）：

```
EtherType     : 0x0800
IP protocol   : 0x11 (UDP)
UDP dst port  : 0x88b5
UDP checksum  : 0x0000
task magic    : 0xa11e
```

### 9.2 recv_ann_result.py — 接收 UDP ANN result 帧

```bash
sudo python sw/board_debug/recv_ann_result.py \
  --iface eth0 --count 1 --timeout-ms 1000

# --request-id <id>     只捕获匹配该 request_id 的结果帧
# --accept-bypass       同时接受 bypass/raw UDP 包并导出 metadata
# --expected <path>     按 expected_outputs.json 为捕获结果补 sample 名称
# --json-out <path>     将解析结果写入 JSON 文件
```

### 9.3 run_ann_model_batch.py — 批量板级评估

```bash
sudo python sw/board_debug/run_ann_model_batch.py \
  --send-only \
  --iface eth0 \
  --test-vectors /tmp/ann_bundle/test_vectors.json \
  --expected     /tmp/ann_bundle/expected_outputs.json \
  --sent-out     /tmp/ann_bundle/sent_rows.json
```

离线对比：

```bash
python3 sw/board_debug/run_ann_model_batch.py \
  --test-vectors  /tmp/ann_bundle/test_vectors.json \
  --expected      /tmp/ann_bundle/expected_outputs.json \
  --observed-json /tmp/ann_bundle/observed_results.json \
  --report-out    /tmp/ann_bundle/board_eval_report.json
```

`test_vectors.json` 和 `expected_outputs.json` 由 `annmodelctl build` 自动产出。

---

## 10. 回归脚本

| 脚本 | 覆盖范围 | 依赖 |
|------|----------|------|
| `bash scripts/check/sw_unit.sh` | CPU/GPU/toolchain/model 的软件单元测试 | python3, perl |
| `bash scripts/check/sw_integration.sh` | annctl mocked 寄存器访问 + 软件集成流 | python3, perl |
| `bash scripts/check/rtl_integration.sh` | 顶层 `user_top` / offload RTL 集成回归 | iverilog |
| `bash scripts/check/rtl_unit.sh` | `tb/unit/` 下的 RTL 单元回归 | iverilog |
| `bash scripts/check/examples_binary_mnist.sh` | binary-MNIST fixture/example 接线验证 | python3 |

旧的 `scripts/verify_*.sh` 仍保留，但只作为兼容 wrapper，不再是文档真值源。

**建议每次修改工具链后先跑：**

```bash
bash scripts/check/sw_unit.sh && bash scripts/check/sw_integration.sh
```

**修改 RTL 后额外跑：**

```bash
bash scripts/check/rtl_integration.sh
bash scripts/check/rtl_unit.sh
```

单元测试目录结构：

```
sw/tests/
  helpers.py
  annctl/
    test_anncontrol.t     # Perl TAP 测试（annctl / ANNControl.pm）
  cpu/
    test_preprocess.py    # 伪指令展开
    test_assembler.py     # ARM 编码
    test_scheduler.py     # RAW hazard
    test_toolchain.py     # build_single / package_directory
  gpu/
    test_parser.py        # .gpus 解析
    test_assembler.py     # opcode 编码
    test_bundle.py        # bundle 打包
  model/
    test_bundle.py        # MLP manifest → CPU/GPU/params 生成
```

---

## 11. 典型工作流程

如果目标机器是 USC 的老实验环境，请把所有 `*-load` 的 Python 命令拆成：

1. 本地 `python3 sw/cpuctl|gpuctl|annmodelctl build ...`
2. 将生成的 `cpu_image.txt` / `gpu_imem.txt` / `gpu_params.txt` scp 到远端
3. 在远端用 `perl sw/annctl ...` 完成 `load`

### 流程 A：快速板级验证（CPU 签名测试）

```bash
# 1. 本地编译 CPU 签名程序
python3 sw/cpuctl build sw/testdata/board_cpu_signature.s \
  --out-dir /tmp/cpu_sig

# 2. 将 /tmp/cpu_sig/image.txt 拷到远端后加载
perl sw/annctl cpu load /tmp/cpu_sig/image.txt

# 3. 加载最小 GPU 镜像并使能 engine
perl sw/annctl gpu imem-load sw/testdata/gpu_imem_sample.txt
perl sw/annctl gpu param-load sw/testdata/gpu_params_sample.txt
perl sw/annctl engine enable
perl sw/annctl engine status   # 确认 engine_ready = 1

# 4. 验证 CPU IMEM 写入正确
perl sw/annctl cpu hw-imem-dump 0 4
# 对比: sed -n '1,4p' /tmp/cpu_sig/compiled_binary.txt

# 5. 在远端 node 上发送触发包
sudo python sw/board_debug/send_ann_offload.py --send --iface eth0

# 6. 读回 CPU DMEM 签名
perl sw/annctl cpu hw-dmem-dump 0 3
# 期望: [0]=0x000000a5  [1]=0x0000005a  [2]=0x0000003c
```

### 流程 B：部署 MLP 模型

```bash
# 1. 本地生成 bundle（使用内置样例）
python3 sw/annmodelctl build sw/testdata/ann_model_mlp_int16.json \
  --out-dir /tmp/ann_bundle

# 2. 查看 bundle 报告
cat /tmp/ann_bundle/bundle_report.txt

# 3. 将 cpu_image.txt / gpu_imem.txt / gpu_params.txt 拷到远端后加载
perl sw/annctl cpu load /tmp/ann_bundle/cpu_image.txt
perl sw/annctl gpu imem-load /tmp/ann_bundle/gpu_imem.txt
perl sw/annctl gpu param-load /tmp/ann_bundle/gpu_params.txt
perl sw/annctl engine enable

# 4. 发送单帧测试
sudo python sw/board_debug/send_ann_offload.py \
  --send --iface eth0 --feature-values "3,2,1,1,2,0,1,0"

# 5. sender 侧批量发送
sudo python sw/board_debug/run_ann_model_batch.py \
  --send-only \
  --iface eth0 \
  --test-vectors /tmp/ann_bundle/test_vectors.json \
  --expected     /tmp/ann_bundle/expected_outputs.json \
  --sent-out     /tmp/ann_bundle/sent_rows.json

# 6. 任意一端离线对比
python3 sw/board_debug/run_ann_model_batch.py \
  --test-vectors  /tmp/ann_bundle/test_vectors.json \
  --expected      /tmp/ann_bundle/expected_outputs.json \
  --observed-json /tmp/ann_bundle/observed_results.json \
  --report-out    /tmp/ann_bundle/board_eval_report.json
```

### 流程 C：训练并部署自定义 Binary-MNIST 示例模型

```bash
# 1. 训练（需要 PyTorch）
python3 sw/mnist_toolchain/train_binary.py \
  --out-dir /tmp/mnist --hidden-dim 8 --epochs 20

# 2. 导出
python3 sw/mnist_toolchain/export_binary.py \
  --checkpoint /tmp/mnist/model.pt \
  --out /tmp/mnist_model.json

# 3. 本地 build（同流程 B）
python3 sw/annmodelctl build /tmp/mnist_model.json \
  --out-dir /tmp/mnist_bundle

# 4. 将产物拷到远端后：
perl sw/annctl cpu load /tmp/mnist_bundle/cpu_image.txt
perl sw/annctl gpu imem-load /tmp/mnist_bundle/gpu_imem.txt
perl sw/annctl gpu param-load /tmp/mnist_bundle/gpu_params.txt
perl sw/annctl engine enable
```

### 流程 D：手工编写 GPU 程序

```bash
# 1. 从模板开始
python3 sw/gpuctl template mlp --in-dim 4 --out-dim 2 --out-dir /tmp/gpu_tpl

# 2. 编辑 /tmp/gpu_tpl/program.gpus 和 params.txt

# 3. 预览编译结果
python3 sw/gpuctl inspect /tmp/gpu_tpl

# 4. 本地打包，然后把产物拷到远端后分别加载
python3 sw/gpuctl package /tmp/gpu_tpl --out-dir /tmp/gpu_tpl_build
perl sw/annctl gpu imem-load /tmp/gpu_tpl_build/compiled_gpu_imem.txt
perl sw/annctl gpu param-load /tmp/gpu_tpl_build/compiled_gpu_params.txt
```

---

## 12. 文件格式说明

### 12.1 CPU ARM 汇编（`.s`）

**注意：** 本项目的 CPU 使用项目定制 immediate 编码，**不兼容标准 ARM**。

- 注释：行首 `#` / `@` / `;`，或行内 `;` / `@`
- immediate：**12-bit signed**，范围 `-2048 .. 2047`（超出范围编译器报错）
- `lsl #imm`：shift 量只有 **3-bit**，范围 `0 .. 7`
- 支持的寄存器别名：`a1-a4`（r0-r3）、`v1-v8`（r4-r11）、`sb`、`sl`、
  `fp`、`ip`、`sp`（r13）、`lr`（r14）、`pc`（r15）

支持的伪指令展开：

| 伪指令 | 展开为 |
|--------|--------|
| `ldmia lr!, {r0,r1,r2,r3}` | 4 × `ldr rN, [lr]` + `add lr, lr, #4` |
| `stmia ip!, {r0,r1,r2,r3}` | 4 × `str rN, [ip]` + `add ip, ip, #4` |
| `ldm lr, {r0,r1}` | `ldr r0, [lr]` + `ldr r1, [lr, #4]` |
| `stm ip, {r0,r1}` | `str r0, [ip]` + `str r1, [ip, #4]` |
| `ldr rN, label` | `mov rN, #128`（当前仅处理字面量加载） |

大常量构造（无法用单条 `mov #imm` 表达时）必须用移位序列：

```asm
mov r0, #3       @ r0 = 3
lsl r0, r0, #3   @ r0 = 3 << 3 = 24  （最多 3 次拼接）
add r0, r0, #72  @ r0 = 96
```

### 12.2 GPU 汇编（`.gpus`）

- 注释：行首 `#`
- 标签：`label_name:` 独占一行
- 寄存器：`r0` .. `r7`（3-bit 编码）
- base selector：`A` / `B` / `C` / `D`
- dtype：`i16`（默认）/ `bf16`

指令编码格式（32-bit）：

```
[31:28] opcode
[27:25] rd
[24:22] rs1
[21:19] rs2
[18:17] bsel  (A=0, B=1, C=2, D=3)
[16]    dtype (i16=0, bf16=1)
[15:0]  imm
```

支持的操作码：

| 指令 | opcode | 典型语法 |
|------|--------|----------|
| `loadi` | 0x1 | `loadi r0, 42` |
| `load` | 0x2 | `load r0, A, 16` |
| `store` | 0x3 | `store A, r0, 16` |
| `add` | 0x4 | `add r2, r0, r1` |
| `sub` | 0x5 | `sub r2, r0, r1` |
| `mul` | 0x6 | `mul r2, r0, r1` |
| `relu` | 0x7 | `relu r0, r0` |
| `set_tid` | 0x8 | `set_tid r0` |
| `inc_tid` | 0x9 | `inc_tid` |
| `blt` | 0xA | `blt r0, r1, .loop` |
| `tensor_mul` | 0xB | `tensor_mul r2, r0, r1` |
| `tensor_mac` | 0xC | `tensor_mac r6, r0, r1` |
| `mov` | 0xD | `mov r1, r0` |
| `jump` | 0xE | `jump .label` |
| `halt` | 0xF | `halt` |

### 12.3 GPU 参数文件（`params.txt`）

每行一条，三种格式均支持（空行和 `#` 注释忽略）：

```
# 格式 1: addr data64（64-bit 十六进制）
0x00000010 0x000000010000002a

# 格式 2: addr hi32 lo32（两个 32-bit 十六进制）
0x00000010 0x00000001 0x0000002a

# 地址范围: 0x0000 .. 0x3FFF
```

### 12.4 IMEM 镜像文件（`image.txt` / `cpu_image.txt`）

`annctl cpu load` / `annctl gpu imem-load` 接受两种格式：

```
# 格式 1: 仅数据（按序从 base_addr 写入）
E3A00000
E5910000
...

# 格式 2: addr + word（annctl 使用 addr 而忽略传入的 base_addr）
0x00000000 0xe3a00000
0x00000001 0xe5910000
```

---

## 13. 硬件约束与限制

| 约束 | 当前值 | 说明 |
|------|--------|------|
| CPU IMEM 总深度 | 512 words | 4 threads 共享，每 thread 占 128 word slot |
| CPU 每 thread 最大有效指令 | **127 条** | 第 128 个 slot 被系统保留 |
| CPU thread 基地址 | t0=`0x000`, t1=`0x080`, t2=`0x100`, t3=`0x180` | 固定布局 |
| CPU immediate 范围 | -2048 .. 2047（12-bit signed） | 非标准 ARM |
| CPU lsl shift 量 | 0 .. 7（3-bit） | 非标准 ARM |
| GPU IMEM 最大深度 | 65536 words（16-bit 地址） | `GPU_IMEM_MAX_WORDS` |
| GPU 参数地址范围 | `0x0000` .. `0x3FFF` | DMEM param bank |
| 共享 DMEM 深度 | 16384 words | CPU + GPU 共享 |
| ANN 协议 EtherType | `0x88B5` | 自定义二层协议 |
| ANN task magic | `0xA11E` | 同时命中才走 offload |
| 每次处理语义 | one-packet-in / one-result-out | 不支持多包 batch |

**已知可接受告警（综合/仿真时）：**
- `bf16_mult` / `bf16_add_sub` black-box（实现端由真实 IP 替换，当前仓库为仿真占位）
- `generic_regs` 的 `counter_updates/counter_decrement` 未连接
- Icarus 下 CPU 模块若干端口宽度 pruning/padding warning
- GPU IMEM 当前无顶层硬件读回口（`annctl gpu imem-shadow-*` 读的是本地 shadow，非硬件）
