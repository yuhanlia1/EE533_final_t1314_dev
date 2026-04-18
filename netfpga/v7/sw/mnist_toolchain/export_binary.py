#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SW_DIR = SCRIPT_DIR.parent
import sys

if str(SW_DIR) not in sys.path:
    sys.path.insert(0, str(SW_DIR))

from mnist_toolchain.binary_model import (  # noqa: E402
    build_binary_mlp,
    export_quantized_layers,
    infer_quantized,
    require_torch,
)
from mnist_toolchain.feature_extract import FEATURE_NAMES, extract_features  # noqa: E402


def _prepare_split(dataset: object, digit_pair: tuple[int, int], limit: int | None) -> tuple[list[list[int]], list[int]]:
    digit_to_class = {digit_pair[0]: 0, digit_pair[1]: 1}
    features: list[list[int]] = []
    labels: list[int] = []
    for image, label in dataset:
        label_int = int(label)
        if label_int not in digit_to_class:
            continue
        features.append(extract_features(image))
        labels.append(digit_to_class[label_int])
        if limit is not None and len(features) >= limit:
            break
    return features, labels


def _balanced_export_rows(features: list[list[int]], labels: list[int], limit: int) -> list[dict[str, object]]:
    per_class = max(limit // 2, 1)
    chosen: list[dict[str, object]] = []
    counts = {0: 0, 1: 0}
    indices = {0: 0, 1: 0}
    for feature_row, label in zip(features, labels):
        if counts[label] >= per_class:
            continue
        chosen.append(
            {
                "name": f"digit{label}_{indices[label]:03d}",
                "input": feature_row,
                "label": label,
            }
        )
        counts[label] += 1
        indices[label] += 1
        if counts[0] >= per_class and counts[1] >= per_class:
            break
    return chosen


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export a trained binary MNIST checkpoint into annmodelctl JSON.")
    parser.add_argument("checkpoint")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--data-dir", default=str(Path.home() / ".cache" / "mnist"))
    parser.add_argument("--test-limit", type=int)
    parser.add_argument("--export-count", type=int, default=32)
    parser.add_argument("--model-name", default="mnist_binary_01_model.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    torch, _ = require_torch()
    from torchvision.datasets import MNIST

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    digit_pair = tuple(int(value) for value in checkpoint["digit_pair"])
    hidden_dim = int(checkpoint["hidden_dim"])

    model = build_binary_mlp(hidden_dim=hidden_dim)
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    layers = export_quantized_layers(model)

    test_dataset = MNIST(args.data_dir, train=False, download=True)
    test_features, test_labels = _prepare_split(test_dataset, digit_pair, args.test_limit)
    exported_rows = _balanced_export_rows(test_features, test_labels, args.export_count)

    quantized_correct = 0
    for feature_row, label in zip(test_features, test_labels):
        logits = infer_quantized(feature_row, layers)
        prediction = 0 if logits[0] >= logits[1] else 1
        if prediction == label:
            quantized_correct += 1

    model_json = {
        "model_type": "mlp",
        "quant_type": "int16",
        "input_dim": 8,
        "labels": [f"digit{digit_pair[0]}", f"digit{digit_pair[1]}"],
        "feature_names": FEATURE_NAMES,
        "layers": layers,
        "tests": [{"name": row["name"], "input": row["input"]} for row in exported_rows],
    }

    model_path = out_dir / args.model_name
    model_path.write_text(json.dumps(model_json, indent=2, sort_keys=False) + "\n", encoding="utf-8")

    report = {
        "digit_pair": list(digit_pair),
        "feature_names": FEATURE_NAMES,
        "hidden_dim": hidden_dim,
        "checkpoint": str(args.checkpoint),
        "train_accuracy": float(checkpoint.get("final_train_accuracy", 0.0)),
        "test_accuracy": float(checkpoint.get("final_test_accuracy", 0.0)),
        "quantized_test_accuracy": (quantized_correct / len(test_labels)) if test_labels else 0.0,
        "exported_tests": len(exported_rows),
        "model_json": str(model_path),
    }
    (out_dir / "export_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"model_json={model_path}")
    print(f"quantized_test_accuracy={report['quantized_test_accuracy']:.6f}")
    print(f"exported_tests={len(exported_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
