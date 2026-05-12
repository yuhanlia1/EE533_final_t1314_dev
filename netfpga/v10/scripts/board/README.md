# Board Workflow

`scripts/board/` 是当前正式 USC 板测编排入口。

当前默认 USC 映射已经切回 team-3：

- `netfpga_host = netfpga@nf3.usc.edu`
- `sender_host = node3@nf4.usc.edu`
- `receiver_host = node3@nf1.usc.edu`

此前曾临时借用过 team-9（`nf9/nf5/nf7`）；当前 `v10` 也已切回 team-3 默认值。

它把这些步骤收敛到一份共享 `manifest.json`：

- bundle 生成
- `pcap` 生成
- `nf3` bring-up
- `nf4` 回放
- `nf1` 抓包
- 本地离线 compare

## Entry Points

```bash
bash scripts/board/prepare.sh ...
bash scripts/board/bringup.sh <run_dir>/manifest.json
bash scripts/board/capture.sh <run_dir>/manifest.json
bash scripts/board/report.sh <run_dir>/manifest.json
bash scripts/board/run_sweep.sh --config scripts/board/rsu_demo_sweep.json
bash scripts/board/run_sweep.sh --config scripts/board/rsu_demo_batch5_single.json
python3 scripts/board/demo_verify.py --config scripts/board/rsu_demo_verify.json
python3 scripts/board/demo_verify.py --config scripts/board/rsu_demo_single_infer.json --view engine-single
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics.json
python3 scripts/board/board_metrics.py --config scripts/board/rsu_nic_metrics_rate_only.json
bash scripts/board/rsu_demo.sh engine-metrics
bash scripts/board/rsu_demo.sh engine-toolchain --out-dir /tmp/rsu_engine_build
bash scripts/board/rsu_demo.sh engine-single-infer --out-dir /tmp/rsu_engine_single_infer --force
bash scripts/board/rsu_demo.sh zero-copy-init --out-dir /tmp/rsu_zero_copy_demo --force
bash scripts/board/rsu_demo.sh zero-copy-threshold --run-dir /tmp/rsu_zero_copy_demo --windows-ms 1600,800,400,200,100,50,10,1
bash scripts/board/rsu_demo.sh zero-copy-limit --run-dir /tmp/rsu_zero_copy_demo --window-ms 50
bash scripts/board/rsu_demo.sh zero-copy-path --run-dir /tmp/rsu_zero_copy_demo
bash scripts/board/rsu_demo.sh protocol-init --out-dir /tmp/rsu_protocol_demo --force
bash scripts/board/rsu_demo.sh protocol-bypass --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-wrong-magic --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-offload --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh other-pros-rate-init --out-dir /tmp/rsu_other_pros_rate_demo --force
bash scripts/board/rsu_demo.sh other-pros-rate-scan --run-dir /tmp/rsu_other_pros_rate_demo --rates 10,25,50,100,200,400,800,1200,1600,2000,2400
bash scripts/board/rsu_demo.sh other-pros-throughput
bash scripts/board/rsu_demo.sh other-pros-power
```

密码输入规则：

- 默认不带 `--password-file` 时，命令启动后会提示手动输入一次 USC 密码
- 若要走文件模式，可显式传 `--password-file ssh_passkey.txt`
- `ssh_passkey.txt` 的内容必须只有一行纯密码，例如 `r006+vYeW0Or`

当前 RSU demo 的固定入口是：

```bash
bash scripts/board/rsu_demo.sh protocol-init --password-file ssh_passkey.txt --out-dir /tmp/rsu_protocol_demo --force
bash scripts/board/rsu_demo.sh protocol-bypass --password-file ssh_passkey.txt --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-wrong-magic --password-file ssh_passkey.txt --run-dir /tmp/rsu_protocol_demo
bash scripts/board/rsu_demo.sh protocol-offload --password-file ssh_passkey.txt --run-dir /tmp/rsu_protocol_demo
```
