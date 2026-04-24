from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import sys
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

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from export_rsu_mlp_manifest import (  # noqa: E402
    build_manifest_from_arrays,
    export_manifest_from_dataset,
    hardware_aligned_mlp_torch,
)
from rsu_mlp_common import (  # noqa: E402
    DEFAULT_INPUT_SHEET,
    DEFAULT_INPUT_XLSX,
    DEFAULT_LABEL_COL,
    DEFAULT_MANIFEST_PATH,
    DEFAULT_MANIFEST_REPORT_PATH,
    DEFAULT_MODEL_DIR,
    FEATURE_COLS,
    LABEL_ORDER,
    SmallMLP,
)


INPUT_CONTRACT = "software_standardized_features_quantized_to_int16"


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


class QuantAwareSmallMLP(SmallMLP):
    def __init__(
        self,
        in_dim: int,
        num_classes: int,
        input_scale: float,
        activation_scales: list[float],
        dropout: float = 0.0,
    ):
        super().__init__(in_dim=in_dim, num_classes=num_classes, dropout=dropout)
        if len(activation_scales) != 3:
            raise ValueError("activation_scales must contain three values for the RSU MLP")
        self.register_buffer(
            "_input_scale",
            torch.tensor(float(input_scale), dtype=torch.float32),
            persistent=False,
        )
        self.register_buffer(
            "_activation_scales",
            torch.tensor([float(value) for value in activation_scales], dtype=torch.float32),
            persistent=False,
        )

    def _linear_layers(self) -> list[nn.Linear]:
        return [self.net[0], self.net[3], self.net[6]]

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return hardware_aligned_mlp_torch(
            standardized_inputs=x,
            linear_layers=self._linear_layers(),
            input_scale=float(self._input_scale.item()),
            activation_scales=[float(value) for value in self._activation_scales.tolist()],
        )

    def quant_scales(self) -> tuple[float, list[float]]:
        return float(self._input_scale.item()), [float(value) for value in self._activation_scales.tolist()]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", default=str(DEFAULT_INPUT_XLSX))
    p.add_argument("--sheet-name", default=DEFAULT_INPUT_SHEET)
    p.add_argument("--label-col", default=DEFAULT_LABEL_COL)
    p.add_argument("--output-dir", default=str(DEFAULT_MODEL_DIR))
    p.add_argument("--test-size", type=float, default=0.2)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--epochs", type=int, default=100)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--patience", type=int, default=15)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--quantization-mode", choices=["ptq_prestandardized", "qat"], default="ptq_prestandardized")
    p.add_argument("--qat-epochs", type=int, default=40)
    p.add_argument("--qat-lr", type=float, default=1e-4)
    p.add_argument("--qat-patience", type=int, default=10)
    p.add_argument("--export-ann-manifest", action="store_true")
    p.add_argument("--ann-manifest-output", default=str(DEFAULT_MANIFEST_PATH))
    p.add_argument("--ann-report-output", default=str(DEFAULT_MANIFEST_REPORT_PATH))
    p.add_argument("--ann-test-count", type=int, default=8)
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


def write_training_artifacts(out_dir: Path, scaler: StandardScaler, label_to_id: dict[str, int]) -> None:
    joblib.dump(scaler, out_dir / "scaler.pkl")
    with open(out_dir / "feature_columns.json", "w", encoding="utf-8") as f:
        json.dump(FEATURE_COLS, f, ensure_ascii=False, indent=2)
    with open(out_dir / "label_mapping.json", "w", encoding="utf-8") as f:
        json.dump(label_to_id, f, ensure_ascii=False, indent=2)


def run_training_phase(
    model: nn.Module,
    train_loader: DataLoader,
    val_loader: DataLoader,
    device: torch.device,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    checkpoint_path: Path,
    epochs: int,
    patience: int,
    phase_name: str,
) -> tuple[list[dict[str, float | int | str]], int, float]:
    best_metric = -1.0
    best_epoch = -1
    bad_epochs = 0
    history: list[dict[str, float | int | str]] = []

    for epoch in range(1, epochs + 1):
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

        history.append(
            {
                "phase": phase_name,
                "phase_epoch": epoch,
                "train_loss": train_loss,
                "val_loss": val_loss,
                "val_accuracy": val_acc,
                "val_macro_f1": val_macro_f1,
            }
        )

        improved = val_macro_f1 > best_metric
        if improved:
            best_metric = val_macro_f1
            best_epoch = epoch
            bad_epochs = 0
            torch.save(model.state_dict(), checkpoint_path)
        else:
            bad_epochs += 1

        print(
            f"phase={phase_name} "
            f"epoch={epoch:03d} "
            f"train_loss={train_loss:.4f} "
            f"val_loss={val_loss:.4f} "
            f"val_acc={val_acc:.4f} "
            f"val_macro_f1={val_macro_f1:.4f}"
        )

        if bad_epochs >= patience:
            print(f"{phase_name} 提前停止，best_epoch={best_epoch}, best_val_macro_f1={best_metric:.4f}")
            break

    return history, best_epoch, best_metric


def main():
    args = parse_args()
    set_seed(args.seed)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_path = out_dir / "best_model.pt"
    float_checkpoint_path = out_dir / "best_model_float.pt"
    qat_checkpoint_path = out_dir / "best_model_qat.pt"

    df = load_dataframe(args.input, args.sheet_name)
    work, x, y, label_to_id = prepare_features(df, args.label_col)
    id_to_label = {v: k for k, v in label_to_id.items()}

    if len(np.unique(y)) < 2:
        raise ValueError("至少需要两个类别才能训练。")

    x_train_raw, x_val_raw, y_train, y_val = train_test_split(
        x,
        y,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y,
    )

    scaler = StandardScaler()
    x_train = scaler.fit_transform(x_train_raw)
    x_val = scaler.transform(x_val_raw)

    train_ds = WindowDataset(x_train, y_train)
    val_ds = WindowDataset(x_val, y_val)

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, drop_last=False)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, drop_last=False)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    class_weights = compute_class_weights(y_train, len(LABEL_ORDER)).to(device)
    criterion = nn.CrossEntropyLoss(weight=class_weights)

    history_rows: list[dict[str, float | int | str]] = []

    float_model = SmallMLP(in_dim=len(FEATURE_COLS), num_classes=len(LABEL_ORDER), dropout=0.2).to(device)
    float_optimizer = torch.optim.Adam(float_model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    float_history, float_best_epoch, float_best_metric = run_training_phase(
        model=float_model,
        train_loader=train_loader,
        val_loader=val_loader,
        device=device,
        criterion=criterion,
        optimizer=float_optimizer,
        checkpoint_path=checkpoint_path,
        epochs=args.epochs,
        patience=args.patience,
        phase_name="float_pretrain",
    )
    history_rows.extend(float_history)

    float_model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
    float_pretrain_val = evaluate(float_model, val_loader, device, criterion)
    shutil.copy2(checkpoint_path, float_checkpoint_path)

    write_training_artifacts(out_dir, scaler, label_to_id)

    final_model: nn.Module = float_model
    final_val = float_pretrain_val
    final_best_epoch = float_best_epoch
    final_best_metric = float_best_metric
    bootstrap_report = None
    qat_best_epoch = None
    qat_best_metric = None
    qat_selected = False

    if args.quantization_mode == "qat":
        _, bootstrap_report = build_manifest_from_arrays(
            model_dir=out_dir,
            calibration_features=x,
            calibration_label_ids=y,
            num_tests=args.ann_test_count,
        )
        qat_model = QuantAwareSmallMLP(
            in_dim=len(FEATURE_COLS),
            num_classes=len(LABEL_ORDER),
            input_scale=float(bootstrap_report["input_scale"]),
            activation_scales=[float(value) for value in bootstrap_report["activation_scales"]],
            dropout=0.0,
        ).to(device)
        qat_model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
        qat_optimizer = torch.optim.Adam(qat_model.parameters(), lr=args.qat_lr, weight_decay=args.weight_decay)
        qat_history, qat_best_epoch, qat_best_metric = run_training_phase(
            model=qat_model,
            train_loader=train_loader,
            val_loader=val_loader,
            device=device,
            criterion=criterion,
            optimizer=qat_optimizer,
            checkpoint_path=qat_checkpoint_path,
            epochs=args.qat_epochs,
            patience=args.qat_patience,
            phase_name="qat_finetune",
        )
        history_rows.extend(qat_history)
        qat_model.load_state_dict(torch.load(qat_checkpoint_path, map_location=device, weights_only=True))
        qat_val = evaluate(qat_model, val_loader, device, criterion)
        if qat_val["macro_f1"] > float_pretrain_val["macro_f1"]:
            qat_selected = True
            shutil.copy2(qat_checkpoint_path, checkpoint_path)
            final_model = qat_model
            final_val = qat_val
            final_best_epoch = int(qat_best_epoch)
            final_best_metric = float(qat_best_metric)
        else:
            shutil.copy2(float_checkpoint_path, checkpoint_path)
            float_model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
            final_model = float_model
            final_val = float_pretrain_val
            final_best_epoch = float_best_epoch
            final_best_metric = float_best_metric

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

    pd.DataFrame(history_rows).to_excel(out_dir / "training_history.xlsx", index=False)

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

    val_pred_df = pd.DataFrame(
        {
            "y_true_id": y_true,
            "y_true_label": [id_to_label[int(i)] for i in y_true],
            "y_pred_id": y_pred,
            "y_pred_label": [id_to_label[int(i)] for i in y_pred],
        }
    )
    for i, label in enumerate(LABEL_ORDER):
        val_pred_df[f"prob_{label}"] = final_val["y_prob"][:, i]
    val_pred_df.to_excel(out_dir / "val_predictions.xlsx", index=False)

    summary = {
        "num_samples_total": int(len(work)),
        "num_train": int(len(x_train)),
        "num_val": int(len(x_val)),
        "best_epoch": int(final_best_epoch),
        "best_val_macro_f1": float(final_best_metric),
        "final_val_accuracy": float(final_val["accuracy"]),
        "final_val_macro_f1": float(final_val["macro_f1"]),
        "float_pretrain_best_epoch": int(float_best_epoch),
        "float_pretrain_best_val_macro_f1": float(float_best_metric),
        "float_pretrain_val_accuracy": float(float_pretrain_val["accuracy"]),
        "float_pretrain_val_macro_f1": float(float_pretrain_val["macro_f1"]),
        "device": str(device),
        "input_contract": INPUT_CONTRACT,
        "quantization_mode": args.quantization_mode,
        "qat_selected": qat_selected,
        "label_col": args.label_col,
        "class_counts_total": {LABEL_ORDER[i]: int((y == i).sum()) for i in range(len(LABEL_ORDER))},
        "class_counts_train": {LABEL_ORDER[i]: int((y_train == i).sum()) for i in range(len(LABEL_ORDER))},
        "class_counts_val": {LABEL_ORDER[i]: int((y_val == i).sum()) for i in range(len(LABEL_ORDER))},
    }

    if bootstrap_report is not None:
        summary["qat_bootstrap_ptq_full_agreement"] = float(
            bootstrap_report["float_vs_quantized_full_dataset_class_agreement"]
        )
        summary["qat_bootstrap_input_scale"] = float(bootstrap_report["input_scale"])
        summary["qat_bootstrap_activation_scales"] = [
            float(value) for value in bootstrap_report["activation_scales"]
        ]
        summary["qat_best_epoch"] = int(qat_best_epoch)
        summary["qat_best_val_macro_f1"] = float(qat_best_metric)
        if qat_selected:
            qat_input_scale, qat_activation_scales = final_model.quant_scales()  # type: ignore[attr-defined]
            summary["qat_input_scale"] = qat_input_scale
            summary["qat_activation_scales"] = qat_activation_scales
        else:
            summary["qat_rejected_reason"] = "qat_val_macro_f1_not_better_than_float_pretrain"

    if args.export_ann_manifest:
        export_manifest_from_dataset(
            model_dir=out_dir,
            dataset_path=args.input,
            output_path=args.ann_manifest_output,
            report_path=args.ann_report_output,
            sheet_name=args.sheet_name,
            label_col=args.label_col,
            num_tests=args.ann_test_count,
        )
        summary["ann_manifest_output"] = str(Path(args.ann_manifest_output).resolve())
        summary["ann_report_output"] = str(Path(args.ann_report_output).resolve())

    with open(out_dir / "summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("\n训练完成")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
