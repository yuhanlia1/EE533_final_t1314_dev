# only_fifo Artifacts

`only_fifo/artifacts` 用于保存需要长期保留的样例和板测参考资产，不存放一次性运行结果。

目录约定：

- `usc_vectors/`
  USC 板测输入样例真值源。包含 `pcap/json/wire.hex` 和 `manifest.json`。
- `usc_captures/`
  板测 bring-up 过程中保留的参考抓包，用于对照真实物理口行为。
- `local_vectors/`
  本地协议和回归样例。包含 `json/wire.hex/opl.txt/udp_payload.hex` 等由 `pktbatch` 生成的固定资产。

这里不保存临时运行结果。新的本地抓包、远端节点 `only_fifo_results*`、`tb/build/` 和 `__pycache__` 都应视为可清理内容。

