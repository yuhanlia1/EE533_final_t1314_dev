
import argparse
import json
import math
import random
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import torch
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from torch import nn
from torch.utils.data import DataLoader, Dataset

FEATURE_COLS = [
    "win_vehicle_count",
    "win_speed_mean",
    "win_speed_std",
    "win_speed_p10",
    "win_speed_p50",
    "win_speed_p90",
    "win_speed_min",
    "win_low_speed_ratio",
    "win_near_stop_ratio",
    "win_stop_vehicle_count",
    "win_acc_mean",
    "win_acc_std",
    "win_acc_min",
    "win_hard_brake_ratio",
    "win_speed_drop_ratio",
    "win_time_headway_mean",
    "win_time_headway_p10",
    "win_short_headway_ratio",
    "win_space_headway_mean",
    "win_space_headway_p10",
]

LABEL_ORDER = ["Free-flow", "Slow", "Congested", "Incident-risk"]


def set_seed(seed: int):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


class WindowDataset(Dataset):
    def __init__(self, x, y):
        self.x = torch.tensor(x, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.long)

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return self.x[idx], self.y[idx]


class SmallMLP(nn.Module):
    def __init__(self, in_dim: int, num_classes: int):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, 32),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(32, 16),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(16, num_classes),
        )

    def forward(self, x):
        return self.net(x)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--sheet-name", default="labeled_5s_samples")
    p.add_argument("--label-col", default="label")
    p.add_argument("--output-dir", default="mlp_5s_output")
    p.add_argument("--test-size", type=float, default=0.2)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--epochs", type=int, default=100)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--patience", type=int, default=15)
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


def load_dataframe(path: str, sheet_name: str):
    return pd.read_excel(path, sheet_name=sheet_name)


def prepare_features(df: pd.DataFrame, label_col: str):
    missing = [c for c in FEATURE_COLS if c not in df.columns]
    if missing:
        raise ValueError(f"缺少这些特征列: {missing}")
    if label_col not in df.columns:
        raise ValueError(f"找不到标签列: {label_col}")

    work = df[FEATURE_COLS + [label_col]].copy()
    work = work.dropna(subset=[label_col])

    valid_labels = set(LABEL_ORDER)
    work = work[work[label_col].isin(valid_labels)].copy()
    if work.empty:
        raise ValueError("过滤后没有可用样本，请检查标签列内容。")

    for c in FEATURE_COLS:
        work[c] = pd.to_numeric(work[c], errors="coerce")

    work[FEATURE_COLS] = work[FEATURE_COLS].replace([np.inf, -np.inf], np.nan)
    work[FEATURE_COLS] = work[FEATURE_COLS].fillna(0.0)

    label_to_id = {name: i for i, name in enumerate(LABEL_ORDER)}
    work["label_id"] = work[label_col].map(label_to_id).astype(int)

    x = work[FEATURE_COLS].values.astype(np.float32)
    y = work["label_id"].values.astype(np.int64)
    return work, x, y, label_to_id


def compute_class_weights(y_train: np.ndarray, num_classes: int):
    counts = np.bincount(y_train, minlength=num_classes).astype(np.float32)
    weights = counts.sum() / np.maximum(counts, 1.0)
    weights = weights / weights.mean()
    return torch.tensor(weights, dtype=torch.float32)


def evaluate(model, loader, device, criterion=None):
    model.eval()
    all_probs = []
    all_preds = []
    all_true = []
    losses = []

    with torch.no_grad():
        for xb, yb in loader:
            xb = xb.to(device)
            yb = yb.to(device)
            logits = model(xb)
            if criterion is not None:
                losses.append(criterion(logits, yb).item())
            probs = torch.softmax(logits, dim=1)
            preds = torch.argmax(probs, dim=1)
            all_probs.append(probs.cpu().numpy())
            all_preds.append(preds.cpu().numpy())
            all_true.append(yb.cpu().numpy())

    y_true = np.concatenate(all_true)
    y_pred = np.concatenate(all_preds)
    y_prob = np.concatenate(all_probs)
    return {
        "loss": float(np.mean(losses)) if losses else math.nan,
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "macro_f1": float(f1_score(y_true, y_pred, average="macro")),
        "y_true": y_true,
        "y_pred": y_pred,
        "y_prob": y_prob,
    }


def main():
    args = parse_args()
    set_seed(args.seed)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    df = load_dataframe(args.input, args.sheet_name)
    work, x, y, label_to_id = prepare_features(df, args.label_col)
    id_to_label = {v: k for k, v in label_to_id.items()}

    if len(np.unique(y)) < 2:
        raise ValueError("至少需要两个类别才能训练。")

    x_train, x_val, y_train, y_val = train_test_split(
        x,
        y,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y,
    )

    scaler = StandardScaler()
    x_train = scaler.fit_transform(x_train)
    x_val = scaler.transform(x_val)

    train_ds = WindowDataset(x_train, y_train)
    val_ds = WindowDataset(x_val, y_val)

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, drop_last=False)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, drop_last=False)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = SmallMLP(in_dim=len(FEATURE_COLS), num_classes=len(LABEL_ORDER)).to(device)
    class_weights = compute_class_weights(y_train, len(LABEL_ORDER)).to(device)
    criterion = nn.CrossEntropyLoss(weight=class_weights)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)

    best_metric = -1.0
    best_epoch = -1
    bad_epochs = 0
    history = []

    for epoch in range(1, args.epochs + 1):
        model.train()
        train_losses = []

        for xb, yb in train_loader:
            xb = xb.to(device)
            yb = yb.to(device)
            optimizer.zero_grad()
            logits = model(xb)
            loss = criterion(logits, yb)
            loss.backward()
            optimizer.step()
            train_losses.append(loss.item())

        train_loss = float(np.mean(train_losses)) if train_losses else math.nan
        val_result = evaluate(model, val_loader, device, criterion)
        val_loss = val_result["loss"]
        val_acc = val_result["accuracy"]
        val_macro_f1 = val_result["macro_f1"]

        history.append({
            "epoch": epoch,
            "train_loss": train_loss,
            "val_loss": val_loss,
            "val_accuracy": val_acc,
            "val_macro_f1": val_macro_f1,
        })

        improved = val_macro_f1 > best_metric
        if improved:
            best_metric = val_macro_f1
            best_epoch = epoch
            bad_epochs = 0
            torch.save(model.state_dict(), out_dir / "best_model.pt")
        else:
            bad_epochs += 1

        print(
            f"epoch={epoch:03d} "
            f"train_loss={train_loss:.4f} "
            f"val_loss={val_loss:.4f} "
            f"val_acc={val_acc:.4f} "
            f"val_macro_f1={val_macro_f1:.4f}"
        )

        if bad_epochs >= args.patience:
            print(f"提前停止，best_epoch={best_epoch}, best_val_macro_f1={best_metric:.4f}")
            break

    model.load_state_dict(torch.load(out_dir / "best_model.pt", map_location=device))
    final_val = evaluate(model, val_loader, device, criterion)
    y_true = final_val["y_true"]
    y_pred = final_val["y_pred"]

    report = classification_report(
        y_true,
        y_pred,
        labels=list(range(len(LABEL_ORDER))),
        target_names=LABEL_ORDER,
        digits=4,
        output_dict=True,
        zero_division=0,
    )
    cm = confusion_matrix(y_true, y_pred, labels=list(range(len(LABEL_ORDER))))

    pd.DataFrame(history).to_excel(out_dir / "training_history.xlsx", index=False)

    report_rows = []
    for k, v in report.items():
        if isinstance(v, dict):
            row = {"label": k}
            row.update(v)
            report_rows.append(row)
        else:
            report_rows.append({"label": k, "value": v})
    pd.DataFrame(report_rows).to_excel(out_dir / "classification_report.xlsx", index=False)

    pd.DataFrame(cm, index=LABEL_ORDER, columns=LABEL_ORDER).to_excel(out_dir / "confusion_matrix.xlsx")

    val_pred_df = pd.DataFrame({
        "y_true_id": y_true,
        "y_true_label": [id_to_label[int(i)] for i in y_true],
        "y_pred_id": y_pred,
        "y_pred_label": [id_to_label[int(i)] for i in y_pred],
    })
    for i, label in enumerate(LABEL_ORDER):
        val_pred_df[f"prob_{label}"] = final_val["y_prob"][:, i]
    val_pred_df.to_excel(out_dir / "val_predictions.xlsx", index=False)

    joblib.dump(scaler, out_dir / "scaler.pkl")
    with open(out_dir / "feature_columns.json", "w", encoding="utf-8") as f:
        json.dump(FEATURE_COLS, f, ensure_ascii=False, indent=2)
    with open(out_dir / "label_mapping.json", "w", encoding="utf-8") as f:
        json.dump(label_to_id, f, ensure_ascii=False, indent=2)

    summary = {
        "num_samples_total": int(len(work)),
        "num_train": int(len(x_train)),
        "num_val": int(len(x_val)),
        "best_epoch": int(best_epoch),
        "best_val_macro_f1": float(best_metric),
        "final_val_accuracy": float(final_val["accuracy"]),
        "final_val_macro_f1": float(final_val["macro_f1"]),
        "device": str(device),
        "class_counts_total": {LABEL_ORDER[i]: int((y == i).sum()) for i in range(len(LABEL_ORDER))},
        "class_counts_train": {LABEL_ORDER[i]: int((y_train == i).sum()) for i in range(len(LABEL_ORDER))},
        "class_counts_val": {LABEL_ORDER[i]: int((y_val == i).sum()) for i in range(len(LABEL_ORDER))},
    }
    with open(out_dir / "summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("\\n训练完成")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
