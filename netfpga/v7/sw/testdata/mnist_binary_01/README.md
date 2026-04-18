# Binary MNIST 0-vs-1 Flow

This directory contains the current-hardware MNIST validation flow for the
NetFPGA v5 ANN stack.

The flow is intentionally split in two:

- a **deterministic fixture** that works without PyTorch and keeps repo
  regression stable
- a **real PyTorch training/export path** that you can run locally when
  `torch` and `torchvision` are installed

## Current example scope

这个目录描述的是当前仓库里的 **binary-MNIST example/fixture flow**，不是全部模型能力声明。

当前边界应理解为：

- `sw/annmodelctl` / `sw/model_toolchain` 是通用 bundle 构建真值源
- 本目录只提供一个稳定、轻量、可回归的 binary 例子
- 当前顶层 RTL integration smoke 也主要围绕这个 8-feature / 2-output 例子在验证

因此，这个 flow 继续使用 **binary MNIST task (`0` vs `1`)** 和一个 8-feature
extractor，而不是直接把 28x28 图像的 784 像素送进硬件集成回归。

## Feature definition

`sw/mnist_toolchain/feature_extract.py` emits 8 integer features:

1. `total_avg`
2. `upper_half_avg`
3. `lower_half_avg`
4. `left_half_avg`
5. `right_half_avg`
6. `main_diag_band_avg`
7. `anti_diag_band_avg`
8. `center_window_avg`

Each feature is quantized into `0..31` and fits the current 16-bit payload
format comfortably.

## Deterministic fixture

`fixture_model.json` is a small hand-authored `digit0`/`digit1` model that
matches the current bundle format. It is used for repo regression and offline
board-eval tooling tests without pulling MNIST or importing PyTorch.

Build it with:

```bash
python3 sw/annmodelctl build sw/testdata/mnist_binary_01/fixture_model.json --out-dir /tmp/mnist_fixture_bundle
```

Then run offline comparison with:

```bash
python3 sw/board_debug/run_ann_model_batch.py \
  --test-vectors /tmp/mnist_fixture_bundle/test_vectors.json \
  --expected /tmp/mnist_fixture_bundle/expected_outputs.json \
  --observed-json /tmp/mnist_fixture_bundle/observed.json
```

## Real PyTorch flow

### 1. Train a binary 0-vs-1 MLP

```bash
python3 sw/mnist_toolchain/train_binary.py \
  --out-dir /tmp/mnist_train \
  --epochs 20 \
  --hidden-dim 8
```

Outputs:

- `/tmp/mnist_train/checkpoint.pt`
- `/tmp/mnist_train/training_metrics.json`
- `/tmp/mnist_train/training_report.txt`

### 2. Export the trained checkpoint into `annmodelctl` JSON

```bash
python3 sw/mnist_toolchain/export_binary.py \
  /tmp/mnist_train/checkpoint.pt \
  --out-dir /tmp/mnist_export \
  --export-count 32
```

Outputs:

- `/tmp/mnist_export/mnist_binary_01_model.json`
- `/tmp/mnist_export/export_report.json`

### 3. Build and load the hardware bundle

```bash
python3 sw/annmodelctl build-load \
  /tmp/mnist_export/mnist_binary_01_model.json \
  --out-dir /tmp/mnist_bundle
```

### 4. Run live board evaluation

```bash
sudo python3 sw/board_debug/run_ann_model_batch.py \
  --send-only \
  --iface <tx_ifname> \
  --test-vectors /tmp/mnist_bundle/test_vectors.json \
  --expected /tmp/mnist_bundle/expected_outputs.json \
  --sent-out /tmp/mnist_bundle/sent_rows.json

sudo python3 sw/board_debug/recv_ann_result.py \
  --iface <rx_ifname> \
  --count 32 \
  --expected /tmp/mnist_bundle/expected_outputs.json \
  --json-out /tmp/mnist_bundle/observed_results.json

python3 sw/board_debug/run_ann_model_batch.py \
  --test-vectors /tmp/mnist_bundle/test_vectors.json \
  --expected /tmp/mnist_bundle/expected_outputs.json \
  --observed-json /tmp/mnist_bundle/observed_results.json \
  --report-out /tmp/mnist_bundle/board_eval_report.json
```

This will:

- send each exported feature vector as one ANN task frame
- capture the ANN result frame on the receiver side
- compare returned logits and predicted class to the expected bundle outputs

## Standard 10-class MNIST

标准 10-class MNIST 不再由这个 README 充当能力真值源。

当前更准确的说法是：

- `annmodelctl/model_toolchain` 已经承担更通用的量化 MLP bundle 构建职责
- 这个目录仍然只维护 binary fixture/example
- `scripts/check/examples_binary_mnist.sh` 只验证这个 binary 示例链路

如果要讨论多类模型 bundle、compact class/score 结果语义或更大输入维度，请以：

- `sw/model_toolchain/bundle.py`
- `sw/annmodelctl`
- `docs/verification_matrix.md`

为准，而不是以这个 example README 为准。
