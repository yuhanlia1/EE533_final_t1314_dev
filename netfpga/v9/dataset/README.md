# Dataset Layout

`dataset/` 现在只保留当前 RSU 主线需要的数据、训练和导出内容。

## Directory Map

- `raw/`
  - 外部原始数据真值源
- `intermediate/`
  - 可再生中间 Excel 产物
- `scripts/`
  - 当前正式入口
- `models/`
  - 训练输出
- `export/`
  - 面向硬件的最终导出物

## Current Recommended Scripts

只把 `dataset/scripts/*` 当成正式入口：

- `aggregate_rsu_features.py`
- `aggregate_2min_and_label.py`
- `label_5s_windows.py`
- `train_5s_mlp.py`
- `export_rsu_mlp_manifest.py`
- `rsu_mlp_common.py`

`scripts/legacy/*` 只保留作历史参考，不作为推荐入口。

## Recommended Flow

1. 聚合 5 秒窗口特征
2. 打标
3. 训练 RSU MLP
4. 导出 `int16` manifest 到 `dataset/export/`

## Dependencies

当前数据链路依赖文件：

- `dataset/requirements-rsu.txt`

至少需要：

- `numpy`
- `pandas`
- `openpyxl`
- `joblib`
- `scikit-learn`

PyTorch 仍用于当前 RSU 训练脚本，但建议按 CPU wheel 单独安装，而不是直接写进通用 requirements 文件。

## Setup

```bash
bash dataset/setup_rsu_env.sh
source .venv-rsu/bin/activate
```

或手动：

```bash
python3 -m venv .venv-rsu
source .venv-rsu/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r dataset/requirements-rsu.txt
python -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.4.1+cpu
```
