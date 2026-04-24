# Board Debug UDP Flow

`sw/board_debug/` 提供当前 ANN UDP 板测协议的共享库和低层调试脚本。

它的定位是：

- 协议构造/解析真值源
- `pcap` 离线 compare 真值源
- 本地 raw-socket 调试工具

不是当前 USC 正式板测的编排层。

## Main Files

- `ann_packets.py`
  - 构造和解析 UDP ANN task / result 包
- `pcap_io.py`
  - `pcap` 读写
- `model_batch_eval.py`
  - expected / observed compare
- `send_ann_offload.py`
  - 构造并可选发送 ANN task 包
- `recv_ann_result.py`
  - 接收并解析 ANN result 或 bypass 包
- `run_ann_model_batch.py`
  - batch send / compare 入口

## Formal USC Path

当前 USC 正式真值路径是：

- `nf3`: `annctl`
- `nf4`: `tcpreplay` 和 sender-side `tcpdump`
- `nf1`: `tcpdump`
- 本地：离线 `request_id` 对齐 compare

因此 `board_debug` 当前最重要的作用是：

- 定义帧语义
- 解析 sender/receiver capture
- 生成离线 compare 结果

## Wire Semantics

当前主线协议是：

- `Ethernet + IPv4 + UDP + ANN payload`
- ANN task magic: `0xA11E`
- ANN result magic: `0xA11F`
- 正式 USC sender/receiver 默认 UDP dst port:
  - `0x88B5`

当前正式 RSU 板测结果模式是：

- `compact_class_score`

也就是：

- `result_data_0 = class_id`
- `result_data_1 = score`

## Local Raw-Socket Debug

这些脚本仍然可用于本地或有 raw-socket 权限的环境：

```bash
python sw/board_debug/send_ann_offload.py --dump-json
python sw/board_debug/run_ann_model_batch.py --help
sudo python sw/board_debug/recv_ann_result.py --help
```

但 USC 上的正式板测不再把 raw-socket Python 路径当真值。

## Compare Rule

- ANN offload 结果按 `request_id` 对齐
- bypass 包不做整帧逐字 compare
- 正式判据优先看：
  - `request_id`
  - ANN result fields
  - sender / receiver / engine 三层计数
