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

from mnist_toolchain.binary_model import build_binary_mlp, require_torch  # noqa: E402
from mnist_toolchain.feature_extract import FEATURE_NAMES, extract_features  # noqa: E402


def _prepare_split(dataset: object, positive_digits: tuple[int, int], limit: int | None) -> tuple[list[list[int]], list[int]]:
    digit_to_class = {positive_digits[0]: 0, positive_digits[1]: 1}
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


def _accuracy(logits: object, labels: object, torch: object) -> float:
    predictions = logits.argmax(dim=1)
    return float((predictions == labels).float().mean().item())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a binary MNIST 0-vs-1 int16-aligned MLP in PyTorch.")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--data-dir", default=str(Path.home() / ".cache" / "mnist"))
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=0.01)
    parser.add_argument("--hidden-dim", type=int, default=8)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--train-limit", type=int)
    parser.add_argument("--test-limit", type=int)
    parser.add_argument("--digit-a", type=int, default=0)
    parser.add_argument("--digit-b", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    torch, nn = require_torch()
    from torch.utils.data import DataLoader, TensorDataset
    from torchvision.datasets import MNIST

    torch.manual_seed(args.seed)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    digit_pair = (args.digit_a, args.digit_b)
    train_dataset = MNIST(args.data_dir, train=True, download=True)
    test_dataset = MNIST(args.data_dir, train=False, download=True)

    train_features, train_labels = _prepare_split(train_dataset, digit_pair, args.train_limit)
    test_features, test_labels = _prepare_split(test_dataset, digit_pair, args.test_limit)

    train_x = torch.tensor(train_features, dtype=torch.float32)
    train_y = torch.tensor(train_labels, dtype=torch.long)
    test_x = torch.tensor(test_features, dtype=torch.float32)
    test_y = torch.tensor(test_labels, dtype=torch.long)

    train_loader = DataLoader(TensorDataset(train_x, train_y), batch_size=args.batch_size, shuffle=True)
    model = build_binary_mlp(hidden_dim=args.hidden_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    loss_fn = nn.CrossEntropyLoss()

    epoch_rows: list[dict[str, object]] = []
    for epoch in range(args.epochs):
        model.train()
        total_loss = 0.0
        for batch_x, batch_y in train_loader:
            optimizer.zero_grad()
            logits = model(batch_x)
            loss = loss_fn(logits, batch_y)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * int(batch_x.shape[0])

        model.eval()
        with torch.no_grad():
            train_logits = model(train_x)
            test_logits = model(test_x)
        epoch_rows.append(
            {
                "epoch": epoch + 1,
                "avg_loss": total_loss / len(train_x),
                "train_accuracy": _accuracy(train_logits, train_y, torch),
                "test_accuracy": _accuracy(test_logits, test_y, torch),
            }
        )

    checkpoint_path = out_dir / "checkpoint.pt"
    torch.save(
        {
            "digit_pair": list(digit_pair),
            "hidden_dim": args.hidden_dim,
            "feature_names": FEATURE_NAMES,
            "state_dict": model.state_dict(),
            "epochs": args.epochs,
            "batch_size": args.batch_size,
            "learning_rate": args.lr,
            "seed": args.seed,
            "train_count": len(train_features),
            "test_count": len(test_features),
            "final_train_accuracy": epoch_rows[-1]["train_accuracy"],
            "final_test_accuracy": epoch_rows[-1]["test_accuracy"],
        },
        checkpoint_path,
    )

    (out_dir / "training_metrics.json").write_text(json.dumps(epoch_rows, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    (out_dir / "training_report.txt").write_text(
        "\n".join(
            [
                f"digit_pair={digit_pair[0]},{digit_pair[1]}",
                f"hidden_dim={args.hidden_dim}",
                f"train_count={len(train_features)}",
                f"test_count={len(test_features)}",
                f"final_train_accuracy={epoch_rows[-1]['train_accuracy']:.6f}",
                f"final_test_accuracy={epoch_rows[-1]['test_accuracy']:.6f}",
                f"checkpoint={checkpoint_path}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"checkpoint={checkpoint_path}")
    print(f"final_train_accuracy={epoch_rows[-1]['train_accuracy']:.6f}")
    print(f"final_test_accuracy={epoch_rows[-1]['test_accuracy']:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
