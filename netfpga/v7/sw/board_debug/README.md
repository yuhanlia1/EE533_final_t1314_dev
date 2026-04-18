# Board Debug UDP Flow

`sw/board_debug/` 现在以**正式 `src` 系统的 UDP 板测语义**为真值源，不再默认使用旧的
L2 `EtherType 0x88B5` 结果帧。

当前目录的定位是：

- 协议构造/解析与 compare 的**共享库层**
- 低层 CLI：
  - `send_ann_offload.py`
  - `recv_ann_result.py`
  - `run_ann_model_batch.py`

正式 USC 板测编排层已经上移到：

- `scripts/board/prepare.sh`
- `scripts/board/bringup.sh`
- `scripts/board/capture.sh`
- `scripts/board/report.sh`

当前 wire format 以 RTL/testbench 为准：

- `Ethernet + IPv4 + UDP + ANN task payload`
- `UDP dst port = 0x88B5`
- `UDP checksum = 0x0000`
- `task magic = 0xA11E`
- `OFFLOAD` 输出不是独立 reply，而是**保留原始 UDP 包外壳并原地改写 payload**
- 结果 payload 头：
  - `result magic = 0xA11F`
  - `version = 0x01`
  - `status`
  - `request_id`
  - `result_type`
  - `result_len`
  - `result_data_0`
  - `result_data_1`

## Files

- `send_ann_offload.py`
  - 构造并可选发送 UDP ANN task 包
  - 兼容 USC 节点的 Python 2.4 / 3.x
- `recv_ann_result.py`
  - 抓取并解析 UDP in-place result 包
  - 可选接受 bypass 包并导出 raw metadata
- `run_ann_model_batch.py`
  - 批量发包/比对入口
  - 支持：
    - 单机 live `send+recv`
    - `--send-only`
    - `--observed-json` 离线 compare

## Recommended USC Flow

固定角色：

- 本地 buildhost：`python3 sw/annmodelctl`
- `netfpga@nf3.usc.edu`：`perl annctl`、`nf_download`、`rkd`
- `node3@nf4.usc.edu`：sender
- `node3@nf1.usc.edu`：receiver

需要先明确一个 USC 现实约束：

- `node3@nf1/nf4` 当前不能 `sudo python ...`
- 但可以 `sudo /usr/bin/tcpreplay ...`
- 也可以 `sudo /usr/sbin/tcpdump ...`

因此，**当前正式、已验证的 USC 路径不是 raw-socket Python live send/recv，而是：**

- 主节点：`annctl`
- sender：`tcpreplay`
- receiver：`tcpdump`
- 本地：离线解析与 compare

`send_ann_offload.py` / `recv_ann_result.py` / `run_ann_model_batch.py` 仍然有价值，但更适合：

- 本地或有 `CAP_NET_RAW` 的环境
- 构造/解析 frame JSON
- 离线 compare
- 非 USC 的 live raw-socket 调试
- `scripts/board/*` 编排层的底层复用

### 1. 本地生成 bundle

```bash
python3 sw/annmodelctl build sw/testdata/ann_model_mlp_int16.json --out-dir /tmp/ann_bundle
```

关键工件：

- `/tmp/ann_bundle/cpu_build/image.txt`
- `/tmp/ann_bundle/gpu_build/compiled_gpu_imem.txt`
- `/tmp/ann_bundle/gpu_build/compiled_gpu_params.txt`
- `/tmp/ann_bundle/test_vectors.json`
- `/tmp/ann_bundle/expected_outputs.json`

### 2. 主节点加载 bitfile 和工件

主节点建议只写 `~/scripts/v7/...`。

同时建议显式设置：

```bash
export ANNCTL_STATE_DIR=~/scripts/v7/nw_proc3_udp1_results_2026-04-18/annctl_state
```

原因是 USC 主机 `/tmp` 可能没有可用空间，`annctl` 默认的 `/tmp/netfpga_annctl` 不可靠。

```bash
perl sw/annctl cpu load /path/to/image.txt
perl sw/annctl gpu imem-load /path/to/compiled_gpu_imem.txt
perl sw/annctl gpu param-load /path/to/compiled_gpu_params.txt
perl sw/annctl engine enable
perl sw/annctl engine status
```

如 manifest 指示 `compact_class_score`，先执行：

```bash
perl sw/annctl engine result-config <base> <count> compact
```

否则执行：

```bash
perl sw/annctl engine result-clear
```

当前正式 `src` 在 USC 上板测通过的 bitfile 是：

- `nw_proc3_udp1.bit`

而且 bring-up 前仍需检查 `router_op_lut` 的实验室 MAC 是否被 `nf_download` 重置。

### 3. USC 正式 smoke 路径

当前正式推荐做法：

1. 本地准备 ANN bundle 与输入样例
2. 在 sender 节点用 `tcpreplay` 回放 `pcap`
3. 在 receiver 节点用 `tcpdump` 抓包
4. 把 capture 拉回本地，用本目录工具离线解析与 compare

说明：

- 这条路径已经在 `nw_proc3_udp1.bit` 上完成正式 USC 验证
- 对 bypass 样例，不要整帧逐字比较，因为正常转发会改写：
  - `dst_mac`
  - `src_mac`
  - `IPv4 TTL`
- 正式判据应以：
  - UDP 端口
  - payload magic
  - ANN result fields
  - expected/observed compare
  为准

### 4. Raw-Socket Live Smoke

下面的命令仍然成立，但默认是给本地或有 raw-socket 权限的环境使用，不是当前 USC 正式真值路径。

发送端 dry-run：

```bash
python sw/board_debug/send_ann_offload.py --dump-json
```

如需匹配 USC 线路，可显式指定 MAC/IP/UDP 字段：

```bash
python sw/board_debug/send_ann_offload.py \
  --dump-json \
  --dst-mac 00:4e:46:32:43:00 \
  --src-mac 00:4e:46:32:43:10 \
  --src-ip 10.0.12.3 \
  --dst-ip 10.0.14.3 \
  --src-udp-port 0x4001 \
  --dst-udp-port 0x88b5
```

接收端：

```bash
sudo python sw/board_debug/recv_ann_result.py \
  --iface <rx_if> \
  --count 1 \
  --json-out /tmp/observed.json
```

发送端：

```bash
sudo python sw/board_debug/send_ann_offload.py \
  --iface <tx_if> \
  --send
```

### 5. Bypass Smoke

`wrong_magic`：

```bash
sudo python sw/board_debug/recv_ann_result.py \
  --iface <rx_if> \
  --count 1 \
  --accept-bypass \
  --request-id 0x1234 \
  --json-out /tmp/wrong_magic.json

sudo python sw/board_debug/send_ann_offload.py \
  --iface <tx_if> \
  --send \
  --request-id 0x1234 \
  --task-magic 0xbeef
```

`wrong_port`：

```bash
sudo python sw/board_debug/recv_ann_result.py \
  --iface <rx_if> \
  --count 1 \
  --accept-bypass \
  --request-id 0x1235 \
  --udp-dst-port 0x9999 \
  --json-out /tmp/wrong_port.json

sudo python sw/board_debug/send_ann_offload.py \
  --iface <tx_if> \
  --send \
  --request-id 0x1235 \
  --dst-udp-port 0x9999
```

### 6. Batch

发送端批量发送：

```bash
sudo python sw/board_debug/run_ann_model_batch.py \
  --send-only \
  --iface <tx_if> \
  --test-vectors /tmp/ann_bundle/test_vectors.json \
  --expected /tmp/ann_bundle/expected_outputs.json \
  --sent-out /tmp/sent_rows.json
```

接收端批量抓取：

```bash
sudo python sw/board_debug/recv_ann_result.py \
  --iface <rx_if> \
  --count 2 \
  --expected /tmp/ann_bundle/expected_outputs.json \
  --json-out /tmp/observed_results.json
```

离线比对：

```bash
python sw/board_debug/run_ann_model_batch.py \
  --test-vectors /tmp/ann_bundle/test_vectors.json \
  --expected /tmp/ann_bundle/expected_outputs.json \
  --observed-json /tmp/observed_results.json \
  --report-out /tmp/board_eval_report.json
```

## Notes

- USC 节点默认按 Python 2.4 兼容子集维护，不要引入仅 Python 3 可用的语法。
- 当前正式 `src` 没有 `only_fifo` 的 `pre/post debug`，因此板测主判据是 sender/receiver JSON 和 batch compare。
- `run_ann_model_batch.py --iface ...` 的 live 模式适合同机收发；USC 三机分离板测更适合：
  - `tcpreplay + tcpdump + 本地离线 compare`
- 当前正式 `src` 已完成 USC 板测的范围是：
  - `input_dim = 8`
  - `output_dim = 2`
  - `legacy_logits`
- `output_dim > 2` 与 `784 feature` 仍属于下一阶段工作。
