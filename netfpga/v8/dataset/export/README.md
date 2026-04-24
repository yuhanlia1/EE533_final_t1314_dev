# Export Outputs

`dataset/export/` 保存当前 RSU 主线面向硬件的最终导出物。

## Current Files

- `rsu_ann_model_int16.json`
  - `annmodelctl` 可直接读取的量化 MLP manifest
- `rsu_ann_model_int16.report.json`
  - 导出过程的缩放、量化和一致性摘要
- `rsu_demo_baseline.json`
  - 当前课程 demo 冻结说明

## Rules

- 这里只放最终导出物
- 不放训练 checkpoint
- 不放一次性中间 Excel
- 当前板测和 RTL smoke 都默认从这里读取 RSU 主线模型
