# only_fifo Software Toolchain

`only_fifo/sw` 是 `only_fifo` 子项目的软件真值源。这里维护本地开发、协议工件生成、自测试和主节点调试访问；`only_fifo/deploy` 只是从这里裁剪同步出来的远端运行包，不应直接开发。

它不包含主工程的：

- `annctl`
- `cpuctl/gpuctl/annmodelctl`
- ANN engine 控制面
- 模型结果比对

当前目标固定为：

- 生成 `IPv4 + UDP + ANN payload` 样例
- 导出 `wire.hex / udp_payload.hex / opl.txt / pcap`
- 离线解码并核对 `offload/bypass`
- 通过 `pktctl` 读取 `only_fifo` 的 `pre-user_top` / `post-user_top` 调试寄存器

## 目录

- `packetlib/`
  协议与寄存器访问真值源
- `bin/`
  本地 CLI 入口：`pktgen/pktbatch/pktpcap/pktsend/pktrecv/pktdecode/pktctl`
- `config/`
  本地软件需要的配置文件
- `testdata/`
  源样例规格，默认 `smoke_batch.json`
- `tests/`
  Python 单元测试
- `../artifacts/`
  需要长期保留的板测样例与参考抓包
- `../scripts/sync_deploy.sh`
  从 `sw` 同步生成 `deploy/buildhost`、`deploy/node`、`deploy/netfpga`

## 协议默认值

- IPv4 EtherType：`0x0800`
- IPv4 protocol：`0x11` (`UDP`)
- ANN UDP 目标端口：`0x88b5`
- ANN task magic：`0xa11e`
- OFFLOAD 改写 magic：`0xf11e`
- payload 布局：`task_magic | request_id | feature_count | task_type | features...`

板上最小验证语义：

- `BYPASS`
  输出包保持原样
- `OFFLOAD`
  只把 UDP payload 起始 16-bit magic 从 `0xa11e` 改成 `0xf11e`

## 调试寄存器

寄存器地址以 `only_fifo/reg_defines_onlyfifo.h` 为唯一真值源。当前关键基地址是：

- `USER_TOP_BASE_ADDR = 0x2000100`
- `USER_PRE_DEBUG_BASE_ADDR = 0x2000140`

`pktctl` 默认只读取这份头文件，不使用主工程 `sw/reg_defines_v5.h`。

常用命令：

```bash
python3 only_fifo/sw/bin/pktctl regs list
python3 only_fifo/sw/bin/pktctl stats clear
python3 only_fifo/sw/bin/pktctl pre snapshot --dump-json
python3 only_fifo/sw/bin/pktctl post snapshot --dump-json
python3 only_fifo/sw/bin/pktctl snapshot all --dump-json
python3 only_fifo/sw/bin/pktctl diagnose
```

## 工件与同步

推荐把长期保留的生成物放到 `only_fifo/artifacts/`：

- `artifacts/usc_vectors/`
  USC 板测输入样例真值源
- `artifacts/local_vectors/`
  本地协议回归样例
- `artifacts/usc_captures/`
  板测参考抓包

部署前执行：

```bash
./only_fifo/scripts/sync_deploy.sh
```

这会从 `only_fifo/sw` 刷新：

- `only_fifo/deploy/buildhost`
- `only_fifo/deploy/node`
- `only_fifo/deploy/netfpga`

## 典型命令

生成一条默认样例：

```bash
python3 only_fifo/sw/bin/pktgen --dump-json
```

批量生成本地回归工件：

```bash
python3 only_fifo/sw/bin/pktbatch \
  --spec only_fifo/sw/testdata/smoke_batch.json \
  --out-dir /tmp/only_fifo_batch
```

生成 `pcap`：

```bash
python3 only_fifo/sw/bin/pktpcap \
  --json-in only_fifo/artifacts/usc_vectors/udp_ann_offload_smoke_usc.json \
  /tmp/udp_ann_offload_smoke_usc.pcap
```

离线解码线包：

```bash
python3 only_fifo/sw/bin/pktdecode \
  --json-in only_fifo/artifacts/usc_vectors/udp_ann_offload_smoke_usc.json \
  --blob-kind wire \
  --dump-json
```

## 自测试

运行 Python 单元测试：

```bash
python3 -m unittest discover -s only_fifo/sw/tests -p 'test_*.py'
```

推荐最小 smoke：

```bash
python3 only_fifo/sw/bin/pktbatch \
  --spec only_fifo/sw/testdata/smoke_batch.json \
  --out-dir /tmp/only_fifo_batch
python3 only_fifo/sw/bin/pktdecode \
  --json-in /tmp/only_fifo_batch/udp_ann_offload_smoke.json \
  --blob-kind wire \
  --dump-json
python3 only_fifo/sw/bin/pktctl stats snapshot --dump-json --regread-bin /path/to/fake/regread
```
