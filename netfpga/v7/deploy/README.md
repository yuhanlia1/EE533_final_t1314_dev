# Deploy Layout

`deploy/` 现在对应正式 `src` 系统的 USC 上板角色分工。

如果目标是执行**正式 USC 板测**，优先入口现在是：

```bash
bash scripts/board/prepare.sh ...
bash scripts/board/bringup.sh ...
bash scripts/board/capture.sh ...
bash scripts/board/report.sh ...
```

`deploy/` 继续承担远端镜像角色，但流程编排已收敛到 `scripts/board/`。

## Roles

- `buildhost/`
  - 本地现代 Python 环境
  - 运行 `cpuctl` / `gpuctl` / `annmodelctl`
  - 生成 CPU/GPU/param/test-vector 工件
- `netfpga/`
  - USC 主节点控制包
  - 运行 `annctl`
  - 配合 `nf_download` / `rkd` 完成 bring-up
- `node0/`
  - Python 2.4 兼容 sender 包
  - 可发送 `Ethernet + IPv4 + UDP + ANN payload` task 包
- `node2/`
  - Python 2.4 兼容 receiver 包
  - 可抓取并解析当前 RTL 的 UDP in-place result 包

需要注意：`node0/` / `node2/` 的 Python 工具是正式软件资产的一部分，但**当前 USC 已验证的真值路径**并不是它们的 raw-socket live 模式，而是：

- `nf3 annctl`
- `nf4 tcpreplay`
- `nf1 tcpdump`
- 本地离线 compare

## Remote Compatibility

- `buildhost/` 需要 `python3 >= 3.9`
- `netfpga/annctl` 兼容 USC 旧 Perl
- `node0/` / `node2/` 运行脚本按 Python 2.4 / 3.x 兼容子集维护

## Suggested USC Layout

- 本地：
  - 保留并运行 `deploy/buildhost/`
- 主节点：
  - 上传到 `~/scripts/v7/<run_name>_netfpga/`
- sender：
  - 上传到 `~/v7/<run_name>_node0/`
- receiver：
  - 上传到 `~/v7/<run_name>_node2/`

主节点默认只假设 `~/scripts/v7` 可写，不依赖其他路径写权限。

当前已正式验证过的命名实例是：

- `~/scripts/v7/nw_proc3_udp1_netfpga/`
- `~/v7/nw_proc3_udp1_node0/`
- `~/v7/nw_proc3_udp1_node2/`

## Typical Flow

1. 本地 `deploy/buildhost/bin/annmodelctl build ...`
2. 将生成工件拷到远端 `~/scripts/v7/...` 或 `~/v7/...`
3. 主节点设置：
   - `ANNCTL_STATE_DIR=~/scripts/v7/<run_name>_results_<date>/annctl_state`
4. 主节点 `nf_download` 下载目标 bitfile
5. 主节点 `rkd`
6. 主节点检查并恢复 `router_op_lut` 实验室 MAC
7. 主节点 `perl bin/annctl ...` 加载 CPU/GPU/param 并 `engine enable`
8. USC 正式板测时：
   - sender 节点运行 `tcpreplay`
   - receiver 节点运行 `tcpdump`
9. 本地离线执行：
   - 结果包解析
   - `expected/observed` compare

如果环境具备 raw-socket 权限，`node0/` / `node2/` 里的 Python 工具仍可以直接 live send/recv；但这不是当前 USC 的正式验证路径。

更推荐的做法是：

1. `scripts/board/prepare.sh` 生成 bundle / pcap / manifest
2. `scripts/board/bringup.sh` 生成 `nf3` bring-up 脚本
3. `scripts/board/capture.sh` 生成 `nf1/nf4` capture/replay 脚本
4. `scripts/board/report.sh` 解析 capture 并输出最终报告

## Notes

- 当前正式 `src` 的结果包不是独立 reply，而是**原 UDP 请求包的 payload 原地改写**。
- `node0` / `node2` 的脚本默认协议是：
  - EtherType `0x0800`
  - IPv4
  - UDP dst port `0x88B5`
  - task magic `0xA11E`
  - result magic `0xA11F`
- `only_fifo` 的 `tcpreplay + tcpdump + pktctl` 仍然是前端调试基线，但不是正式 `src` 的推理主线。
- 当前已正式板测通过的 bitfile 是：
  - `nw_proc3_udp1.bit`
- 当前已正式板测通过的模型范围是：
  - `input_dim = 8`
  - `output_dim = 2`
  - `legacy_logits`

## Local Smoke Checks

从仓库根目录：

```bash
perl deploy/netfpga/bin/annctl regs list
python3 deploy/buildhost/bin/cpuctl --help
python3 deploy/buildhost/bin/gpuctl --help
python3 deploy/buildhost/bin/annmodelctl --help
python deploy/node0/bin/send_ann_offload.py --dump-json
python deploy/node0/bin/run_ann_model_batch.py --help
python deploy/node2/bin/recv_ann_result.py --help
```
