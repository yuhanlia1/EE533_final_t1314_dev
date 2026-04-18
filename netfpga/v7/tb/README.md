# RTL Testbench Layout

`tb/` 现在按“集成 vs 单元”两层来理解：

- `tb/integration/`
  系统级数据面仿真。这里的 testbench 会拉起 `user_top` 及其相关 ANN 路径，验证协议分类、feature unpack、compute core、结果输出和寄存器控制的协同行为。
- `tb/unit/`
  计算/通信单元级仿真。这里的 testbench 关注 CPU/GPU 通信、矩阵/NN 计算流、GPU IMEM 防护等局部行为。

当前 checked-in 集成 testbench：

- `tb/integration/tb_user_top_offload.v`
  验证 `IPv4/UDP` ANN 请求进入 `user_top` 后的端到端行为，包括：
  - L4 分类与 bypass/offload 分流
  - `ann_feature_unpack` 取特征
  - `ann_cpu_gpu_compute_core` 计算
  - `OFFLOAD` 原包重放并改写结果 payload
  - engine control 更新和 compact-result 开关

当前 checked-in unit testbench：

- `tb/unit/tb_packet.v`
- `tb/unit/tb_communication_nn.v`
- `tb/unit/tb_communication_matrix.v`
- `tb/unit/tb_gpu_imem_guard.v`

## Coverage Notes

- `tb_user_top_offload` 目前仍是一个固定的 ANN smoke 配置，使用 8-feature、2-output 的受控向量来验证顶层路径是否自洽。
- `annmodelctl/model_toolchain` 已经可以构建更通用的量化 MLP bundle，但这些更大维度的模型并没有在当前顶层 RTL 集成 testbench 中全部覆盖。
- 因此，`tb` 通过表示“当前顶层 smoke 配置正确”，不等于“所有 bundle 维度都已经被 RTL 集成仿真覆盖”。

## Entry Points

推荐入口：

```bash
bash scripts/check/rtl_integration.sh
bash scripts/check/rtl_unit.sh
```

兼容入口仍保留：

```bash
bash scripts/verify_tb.sh
```
