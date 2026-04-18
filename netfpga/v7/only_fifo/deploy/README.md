# only_fifo Deploy Layout

`only_fifo/deploy` 是从 `only_fifo/sw` 派生出来的远端运行包，不是并行开发目录。  
在复制到实验机之前，先在仓库根目录执行：

```bash
./only_fifo/scripts/sync_deploy.sh
```

这会刷新三类角色：

- `deploy/buildhost`
  本地批量生成工件和样例
- `deploy/node`
  远端发送、接收、离线解码
- `deploy/netfpga`
  主节点 `regread/regwrite` 调试入口

## 目录

- `buildhost/bin/pktgen`
- `buildhost/bin/pktbatch`
- `buildhost/python/packetlib/`
- `buildhost/testdata/smoke_batch.json`
- `node/bin/pktsend`
- `node/bin/pktrecv`
- `node/bin/pktdecode`
- `node/python/packetlib/`
- `netfpga/bin/pktctl`
- `netfpga/python/packetlib/`
- `netfpga/config/reg_defines_onlyfifo.h`

## 样例来源

长期保留的输入样例放在：

- `only_fifo/artifacts/usc_vectors/`
- `only_fifo/artifacts/local_vectors/`

其中：

- `usc_vectors/` 是 USC 板测输入真值源
- `local_vectors/` 是本地协议回归固定样例

板测参考抓包放在：

- `only_fifo/artifacts/usc_captures/`

## 推荐板测路径

当前已经验证通过的 USC 板测主路径是：

1. `netfpga`
   - `nf_download`
   - `rkd`
   - `python bin/pktctl stats clear`
   - `python bin/pktctl snapshot all --dump-json`
2. `node0`
   - `sudo /usr/bin/tcpreplay -i port0 *.pcap`
3. `node2`
   - `sudo /usr/sbin/tcpdump -i port2 ...`

`iperf`、raw socket live send/recv 和旧的 L2 自定义 EtherType 路径都不是当前正式验证路径。

## 常用命令

本地 buildhost：

```bash
python buildhost/bin/pktbatch \
  --spec buildhost/testdata/smoke_batch.json \
  --out-dir /tmp/only_fifo_batch
```

节点侧离线解码：

```bash
python bin/pktdecode --json-in udp_ann_offload_smoke_usc.json --blob-kind wire --dump-json
```

主节点调试：

```bash
python bin/pktctl regs list
python bin/pktctl stats clear
python bin/pktctl pre snapshot --dump-json
python bin/pktctl post snapshot --dump-json
python bin/pktctl snapshot all --dump-json
python bin/pktctl diagnose
```

## 远端拷贝约定

推荐部署路径：

- 主节点：`~/scripts/v5/only_fifo_netfpga`
- 节点：`~/v5/only_fifo_node`

推荐复制内容：

- `deploy/netfpga/*` -> 主节点
- `deploy/node/*` -> 节点
- `artifacts/usc_vectors/*.pcap` 和 `artifacts/usc_vectors/*.json` -> 发送端
- `artifacts/usc_vectors/*.json` -> 接收端

运行时抓包结果不回写到仓库，统一放远端：

- `~/v5/only_fifo_results_udp4/`
