# Binary MNIST 0-vs-1 Flow

This directory contains the current-hardware MNIST validation flow for the
NetFPGA v5 ANN stack.

The flow is intentionally split in two:

- a **deterministic fixture** that works without PyTorch and keeps repo
  regression stable
- a **real PyTorch training/export path** that you can run locally when
  `torch` and `torchvision` are installed

## Current hardware limits

The checked-in ANN RTL and `annmodelctl` currently require:

- `input_dim <= 8`
- `output_dim == 2`

So this flow uses a **binary MNIST task (`0` vs `1`)** and an 8-feature
extractor instead of raw 784-pixel input.

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
  --iface <host_ifname> \
  --test-vectors /tmp/mnist_bundle/test_vectors.json \
  --expected /tmp/mnist_bundle/expected_outputs.json \
  --observed-out /tmp/mnist_bundle/observed_results.json \
  --report-out /tmp/mnist_bundle/board_eval_report.json
```

This will:

- send each exported feature vector as one ANN task frame
- capture the ANN result frame
- compare returned logits and predicted class to the expected bundle outputs

## Standard 10-class MNIST

Standard `784 -> ... -> 10` MNIST is still blocked by current hardware:

- `ann_feature_unpack.v` and `ann_cpu_gpu_compute_core.v` are fixed around 8
  incoming features
- the result packet path only carries two 16-bit logits

So the current implemented flow is the binary 8-feature validation path only.
