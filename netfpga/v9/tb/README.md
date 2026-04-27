# RTL Testbench Layout

`tb/` 按两层理解：

- `tb/integration/`
  - 顶层 `user_top` 级别的系统仿真
- `tb/unit/`
  - 局部计算/通信单元仿真

## Current Integration Testbenches

- `tb/integration/tb_user_top_offload.v`
  - 旧的受控 smoke
  - 验证 ANN UDP 路径和结果改写的基本闭环
- `tb/integration/tb_user_top_offload_rsu.v`
  - 当前 RSU 主线 smoke
  - 从 bundle 工件加载 CPU/GPU/params
  - 验证 wrong-magic / wrong-port bypass
  - 验证 RSU batch 结果与 expected outputs 一致
  - 覆盖 debug counters

## Current Unit Testbenches

- `tb/unit/tb_packet.v`
- `tb/unit/tb_communication_nn.v`
- `tb/unit/tb_communication_matrix.v`
- `tb/unit/tb_gpu_imem_guard.v`

## Recommended Entry Points

```bash
bash scripts/check/rtl_unit.sh
bash scripts/check/rtl_integration.sh
bash scripts/check/rtl_rsu_smoke.sh
```

## Current Position

- RSU smoke 已经是当前 `v8` 主线最重要的集成 testbench
- 当前已验证 bundle 能装入并执行
- 后续若继续做冷启动定位，应优先围绕 `tb_user_top_offload_rsu.v` 扩展，而不是继续依赖旧 smoke
