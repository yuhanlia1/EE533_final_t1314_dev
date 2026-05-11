from __future__ import annotations

import argparse
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from rsu_mlp_common import (  # noqa: E402
    DEFAULT_INPUT_SHEET,
    DEFAULT_INPUT_XLSX,
    DEFAULT_LABEL_COL,
    DEFAULT_MANIFEST_PATH,
    DEFAULT_MANIFEST_REPORT_PATH,
    DEFAULT_MODEL_DIR,
    FEATURE_COLS,
    SmallMLP,
    ensure_parent_dir,
    labels_from_mapping,
)


INPUT_CONTRACT = "software_standardized_features_quantized_to_int16"
SCALE_FACTOR_CANDIDATES = (1.0, 0.75, 0.5, 0.25)


def _lazy_import_joblib():
    try:
        import joblib
    except ModuleNotFoundError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("joblib is required for RSU model export") from exc
    return joblib


def _lazy_import_torch():
    try:
        import torch
    except ModuleNotFoundError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("torch is required for RSU model export") from exc
    return torch


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, payload: object) -> None:
    ensure_parent_dir(path)
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def _to_s16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def _wrap_s16_numpy(values: np.ndarray) -> np.ndarray:
    wrapped = np.remainder(values.astype(np.int64) + 32768, 65536) - 32768
    return wrapped.astype(np.int64)


def _relu_s16(value: int) -> int:
    return value if value > 0 else 0


def _safe_scale(max_abs: float, target: float) -> float:
    if max_abs <= 1e-12:
        return 1.0
    return max(target / max_abs, 1.0)


def _json_ready_float_list(values: np.ndarray) -> list[float]:
    return [float(value) for value in values.tolist()]


def _json_ready_int_matrix(values: np.ndarray) -> list[list[int]]:
    return [[int(item) for item in row.tolist()] for row in values.astype(np.int64)]


def _json_ready_int_list(values: np.ndarray) -> list[int]:
    return [int(item) for item in values.astype(np.int64).tolist()]


def _scale_vector(scale, size: int) -> np.ndarray:
    if np.isscalar(scale):
        return np.full((size,), float(scale), dtype=np.float64)
    arr = np.asarray(scale, dtype=np.float64).reshape(-1)
    if arr.size != size:
        raise ValueError(f"scale length {arr.size} does not match expected size {size}")
    return arr


def _representative_scale(scale) -> float:
    if np.isscalar(scale):
        return float(scale)
    arr = np.asarray(scale, dtype=np.float64).reshape(-1)
    if arr.size == 0:
        return 1.0
    return float(np.median(arr))


def _scale_json(scale):
    if np.isscalar(scale):
        return float(scale)
    return _json_ready_float_list(np.asarray(scale, dtype=np.float64))


def _per_channel_safe_scale(values: np.ndarray, target: float, conservative_factor: float) -> np.ndarray:
    max_abs = np.max(np.abs(values), axis=0)
    per_channel = np.array([_safe_scale(float(item), target) for item in max_abs], dtype=np.float64)
    per_channel = np.maximum(per_channel * float(conservative_factor), 1.0)
    return per_channel


def _feature_matrix_from_frame(df: pd.DataFrame) -> np.ndarray:
    missing = [name for name in FEATURE_COLS if name not in df.columns]
    if missing:
        raise ValueError(f"dataset is missing required feature columns: {missing}")
    work = df[FEATURE_COLS].copy()
    for name in FEATURE_COLS:
        work[name] = pd.to_numeric(work[name], errors="coerce")
    work = work.replace([np.inf, -np.inf], np.nan).fillna(0.0)
    return work.values.astype(np.float32)


def _label_ids_from_frame(df: pd.DataFrame, labels: list[str], label_col: str) -> np.ndarray | None:
    if "label_id" in df.columns:
        series = pd.to_numeric(df["label_id"], errors="coerce")
        if not series.isna().all():
            return series.fillna(-1).astype(np.int64).values

    if label_col not in df.columns:
        return None

    label_to_id = {label: index for index, label in enumerate(labels)}
    series = df[label_col].map(label_to_id)
    if series.isna().all():
        return None
    return series.fillna(-1).astype(np.int64).values


def _test_names_from_frame(df: pd.DataFrame) -> list[str]:
    for candidate in ("sample_id", "window_id", "name"):
        if candidate in df.columns:
            return [f"{candidate}_{value}" for value in df[candidate].tolist()]
    return [f"row_{index}" for index in range(len(df))]


def _read_dataset_frame(path: str | Path, sheet_name: str = DEFAULT_INPUT_SHEET) -> pd.DataFrame:
    dataset_path = Path(path)
    suffix = dataset_path.suffix.lower()
    if suffix == ".csv":
        return pd.read_csv(dataset_path)
    if suffix == ".json":
        payload = _load_json(dataset_path)
        if not isinstance(payload, list):
            raise ValueError("JSON dataset input must contain a list of row objects")
        return pd.DataFrame(payload)
    return pd.read_excel(dataset_path, sheet_name=sheet_name)


def _extract_float_layers(model) -> list[tuple[np.ndarray, np.ndarray, str]]:
    linear_modules = [module for module in model.net if module.__class__.__name__ == "Linear"]
    if len(linear_modules) != 3:
        raise ValueError("expected SmallMLP to contain exactly three Linear layers")

    layers: list[tuple[np.ndarray, np.ndarray, str]] = []
    for index, module in enumerate(linear_modules):
        weight = module.weight.detach().cpu().numpy().astype(np.float64)
        bias = module.bias.detach().cpu().numpy().astype(np.float64)
        activation = "relu" if index < len(linear_modules) - 1 else "none"
        layers.append((weight, bias, activation))
    return layers


def _forward_float_activations(
    inputs: np.ndarray,
    layers: list[tuple[np.ndarray, np.ndarray, str]],
) -> list[np.ndarray]:
    acts: list[np.ndarray] = [inputs.astype(np.float64)]
    cur = acts[0]
    for weight, bias, activation in layers:
        cur = cur @ weight.T + bias[np.newaxis, :]
        if activation == "relu":
            cur = np.maximum(cur, 0.0)
        acts.append(cur)
    return acts


def _quantize_to_s16_numpy(values: np.ndarray, scale: float) -> np.ndarray:
    quantized = np.rint(values.astype(np.float64) * scale)
    quantized = np.clip(quantized, -32768, 32767).astype(np.int64)
    return _wrap_s16_numpy(quantized)


def _quantize_layer_arrays(
    weight: np.ndarray,
    bias: np.ndarray,
    input_scale: float,
    output_scale: float,
) -> tuple[np.ndarray, np.ndarray]:
    input_scale_vec = _scale_vector(input_scale, weight.shape[1])
    output_scale_vec = _scale_vector(output_scale, weight.shape[0])
    weight_scale = output_scale_vec[:, np.newaxis] / input_scale_vec[np.newaxis, :]
    weight_q = _quantize_to_s16_numpy(weight, weight_scale)
    bias_q = _quantize_to_s16_numpy(bias, output_scale_vec)
    return weight_q, bias_q


def _layer_scale_limits(
    layer_inputs: np.ndarray,
    weight: np.ndarray,
    bias: np.ndarray,
    post_activation: np.ndarray,
    target: float,
) -> tuple[float, float, float, float]:
    output_abs = float(np.max(np.abs(post_activation)))
    activation_limited = _safe_scale(output_abs, target)

    max_bias = float(np.max(np.abs(bias)))
    bias_limit = (32767.0 / max_bias) if max_bias > 1e-12 else math.inf

    products = layer_inputs[:, np.newaxis, :] * weight[np.newaxis, :, :]
    max_product_abs = float(np.max(np.abs(products)))
    product_limit = (32767.0 / max_product_abs) if max_product_abs > 1e-12 else math.inf

    partial_sums = np.cumsum(products, axis=2)
    max_partial_abs = float(np.max(np.abs(partial_sums)))
    partial_limit = (32767.0 / max_partial_abs) if max_partial_abs > 1e-12 else math.inf
    return activation_limited, bias_limit, product_limit, partial_limit


def _prepare_quantized_layers(
    raw_layers: list[tuple[np.ndarray, np.ndarray, str]],
    scales: list[float],
) -> list[dict]:
    quantized_layers: list[dict] = []
    for index, (weight, bias, activation) in enumerate(raw_layers):
        weight_q, bias_q = _quantize_layer_arrays(weight, bias, scales[index], scales[index + 1])
        quantized_layers.append(
            {
                "layer_index": index,
                "in_dim": int(weight.shape[1]),
                "out_dim": int(weight.shape[0]),
                "activation": activation,
                "input_scale": scales[index],
                "output_scale": scales[index + 1],
                "weight_q": weight_q,
                "bias_q": bias_q,
                "weights": _json_ready_int_matrix(weight_q),
                "bias": _json_ready_int_list(bias_q),
            }
        )
    return quantized_layers


def _run_quantized_layers_numpy(
    quantized_inputs: np.ndarray,
    quantized_layers: list[dict],
    collect_stats: bool = False,
) -> tuple[np.ndarray, list[dict] | None]:
    acts = quantized_inputs.astype(np.int64, copy=True)
    layer_stats: list[dict] = []
    for layer in quantized_layers:
        weight_q = layer["weight_q"]
        bias_q = layer["bias_q"]
        acc = np.zeros((acts.shape[0], weight_q.shape[0]), dtype=np.int64)
        product_wrap_count = 0
        accumulate_wrap_count = 0
        for in_index in range(weight_q.shape[1]):
            raw_product = acts[:, [in_index]] * weight_q[np.newaxis, :, in_index]
            wrapped_product = _wrap_s16_numpy(raw_product)
            product_wrap_count += int(np.count_nonzero(raw_product != wrapped_product))
            raw_acc = acc + wrapped_product
            acc = _wrap_s16_numpy(raw_acc)
            accumulate_wrap_count += int(np.count_nonzero(raw_acc != acc))
        raw_bias = acc + bias_q[np.newaxis, :]
        acc = _wrap_s16_numpy(raw_bias)
        bias_wrap_count = int(np.count_nonzero(raw_bias != acc))
        if layer["activation"] == "relu":
            acc = np.maximum(acc, 0)
        if collect_stats:
            layer_stats.append(
                {
                    "layer_index": int(layer["layer_index"]),
                    "quantized_output_min": int(acc.min()) if acc.size else 0,
                    "quantized_output_max": int(acc.max()) if acc.size else 0,
                    "quantized_output_nonzero_ratio": float(np.count_nonzero(acc) / acc.size) if acc.size else 0.0,
                    "product_wrap_count": product_wrap_count,
                    "accumulate_wrap_count": accumulate_wrap_count,
                    "bias_wrap_count": bias_wrap_count,
                }
            )
        acts = acc
    return acts, (layer_stats if collect_stats else None)


def _safe_accuracy(y_true: np.ndarray | None, y_pred: list[int]) -> float | None:
    if y_true is None:
        return None
    valid = y_true >= 0
    if not np.any(valid):
        return None
    return float(accuracy_score(y_true[valid], np.asarray(y_pred, dtype=np.int64)[valid]))


def _safe_macro_f1(y_true: np.ndarray | None, y_pred: list[int]) -> float | None:
    if y_true is None:
        return None
    valid = y_true >= 0
    if not np.any(valid):
        return None
    return float(f1_score(y_true[valid], np.asarray(y_pred, dtype=np.int64)[valid], average="macro"))


def _safe_confusion_matrix(y_true: np.ndarray | None, y_pred: list[int], class_count: int) -> list[list[int]] | None:
    if y_true is None:
        return None
    valid = y_true >= 0
    if not np.any(valid):
        return None
    matrix = confusion_matrix(
        y_true[valid],
        np.asarray(y_pred, dtype=np.int64)[valid],
        labels=list(range(class_count)),
    )
    return [[int(value) for value in row.tolist()] for row in matrix]


def _prediction_histogram(predicted: list[int], labels: list[str]) -> dict[str, int]:
    counts = {label: 0 for label in labels}
    for value in predicted:
        if 0 <= value < len(labels):
            counts[labels[value]] += 1
    return counts


def _select_test_indices(labels: np.ndarray | None, num_tests: int, total_rows: int) -> list[int]:
    if num_tests <= 0 or total_rows <= 0:
        return []

    if labels is None:
        return list(range(min(num_tests, total_rows)))

    ordered: list[int] = []
    seen: set[int] = set()
    valid_labels = [label for label in sorted(set(labels.tolist())) if label >= 0]
    for label in valid_labels:
        label_indices = [index for index, value in enumerate(labels.tolist()) if value == label]
        if label_indices:
            ordered.append(label_indices[0])
            seen.add(label_indices[0])
            if len(ordered) >= num_tests:
                return ordered

    for index in range(total_rows):
        if index in seen:
            continue
        ordered.append(index)
        if len(ordered) >= num_tests:
            break
    return ordered


def _build_manifest(
    model_path: Path,
    feature_cols: list[str],
    labels: list[str],
    scaler,
    sklearn_version: str,
    quantized_layers: list[dict],
    quantized_tests: np.ndarray,
    selected_names: list[str],
    scales: list[float],
    base_scales: list[float],
    selected_factors: list[float],
    search_combo_count: int,
    channel_scale_mode: str,
) -> dict:
    return {
        "model_type": "mlp",
        "quant_type": "int16",
        "input_dim": len(feature_cols),
        "labels": labels,
        "layers": [
            {
                "in_dim": int(layer["in_dim"]),
                "out_dim": int(layer["out_dim"]),
                "activation": layer["activation"],
                "weights": layer["weights"],
                "bias": layer["bias"],
            }
            for layer in quantized_layers
        ],
        "tests": [
            {
                "name": selected_names[index],
                "input": _json_ready_int_list(quantized_tests[index]),
            }
            for index in range(len(quantized_tests))
        ],
        "export_meta": {
            "source_model_dir": str(model_path.resolve()),
            "feature_columns": feature_cols,
            "input_contract": INPUT_CONTRACT,
            "scaler_class": scaler.__class__.__name__,
            "scaler_sklearn_version": str(sklearn_version),
            "scaler_mean": _json_ready_float_list(np.asarray(scaler.mean_, dtype=np.float64)),
            "scaler_scale": _json_ready_float_list(np.asarray(scaler.scale_, dtype=np.float64)),
            "input_scale": float(scales[0]),
            "activation_scales": [_representative_scale(value) for value in scales[1:]],
            "per_channel_activation_scales": {
                f"layer_{index}_output": _scale_json(scale)
                for index, scale in enumerate(scales[1:])
                if not np.isscalar(scale)
            },
            "base_scales": [float(value) for value in base_scales],
            "selected_scale_factors": [float(value) for value in selected_factors],
            "scale_factor_candidates": [float(value) for value in SCALE_FACTOR_CANDIDATES],
            "scale_search_combination_count": int(search_combo_count),
            "channel_scale_mode": channel_scale_mode,
        },
    }


def _evaluate_scale_candidate(
    standardized_rows: np.ndarray,
    test_label_ids: np.ndarray | None,
    raw_layers: list[tuple[np.ndarray, np.ndarray, str]],
    float_predicted: list[int],
    base_scales: list[float],
    scale_factors: tuple[float, ...],
) -> dict:
    scales = [max(1.0, float(base_scales[index] * scale_factors[index])) for index in range(len(base_scales))]
    quantized_layers = _prepare_quantized_layers(raw_layers, scales)
    quantized_inputs = _quantize_to_s16_numpy(standardized_rows, scales[0])
    logits_int, layer_stats = _run_quantized_layers_numpy(quantized_inputs, quantized_layers, collect_stats=True)
    quantized_predicted = np.argmax(logits_int, axis=1).astype(np.int64).tolist()
    agreement = (
        float(sum(int(a == b) for a, b in zip(float_predicted, quantized_predicted))) / len(float_predicted)
        if float_predicted
        else 1.0
    )
    quantized_accuracy = _safe_accuracy(test_label_ids, quantized_predicted)
    total_product_wraps = int(sum(item["product_wrap_count"] for item in layer_stats or []))
    total_acc_wraps = int(sum(item["accumulate_wrap_count"] for item in layer_stats or []))
    total_bias_wraps = int(sum(item["bias_wrap_count"] for item in layer_stats or []))
    return {
        "scales": scales,
        "factors": [float(item) for item in scale_factors],
        "quantized_layers": quantized_layers,
        "quantized_inputs": quantized_inputs,
        "logits_int": logits_int,
        "quantized_predicted": quantized_predicted,
        "agreement": float(agreement),
        "quantized_accuracy": quantized_accuracy,
        "layer_stats": layer_stats or [],
        "score": (
            float(agreement),
            -1.0 if quantized_accuracy is None else float(quantized_accuracy),
            -float(total_product_wraps + total_acc_wraps + total_bias_wraps),
            -float(sum(scales)),
        ),
    }


def _logit_margin_stats(logits: np.ndarray) -> dict[str, float]:
    if logits.size == 0:
        return {
            "mean": 0.0,
            "min": 0.0,
            "p10": 0.0,
            "p50": 0.0,
            "p90": 0.0,
        }
    sorted_logits = np.sort(logits, axis=1)
    if sorted_logits.shape[1] >= 2:
        margins = sorted_logits[:, -1] - sorted_logits[:, -2]
    else:
        margins = sorted_logits[:, -1]
    return {
        "mean": float(np.mean(margins)),
        "min": float(np.min(margins)),
        "p10": float(np.percentile(margins, 10)),
        "p50": float(np.percentile(margins, 50)),
        "p90": float(np.percentile(margins, 90)),
    }


def _per_class_logit_stats(float_logits: np.ndarray, quantized_logits: np.ndarray, labels: list[str]) -> list[dict]:
    rows: list[dict] = []
    for index, label in enumerate(labels):
        rows.append(
            {
                "class_index": int(index),
                "label": label,
                "float_mean": float(np.mean(float_logits[:, index])),
                "float_min": float(np.min(float_logits[:, index])),
                "float_max": float(np.max(float_logits[:, index])),
                "quantized_mean": float(np.mean(quantized_logits[:, index])),
                "quantized_min": float(np.min(quantized_logits[:, index])),
                "quantized_max": float(np.max(quantized_logits[:, index])),
            }
        )
    return rows


def _refine_hidden2_channel_scales(
    standardized_calibration: np.ndarray,
    standardized_rows: np.ndarray,
    raw_layers: list[tuple[np.ndarray, np.ndarray, str]],
    float_predicted: list[int],
    test_label_ids: np.ndarray | None,
    scalar_result: dict,
    hidden_target: float,
) -> dict:
    calibration_activations = _forward_float_activations(standardized_calibration, raw_layers)
    selected_factors = list(scalar_result["factors"])
    hidden2_output_scale = _per_channel_safe_scale(
        calibration_activations[2],
        hidden_target,
        conservative_factor=float(selected_factors[2]),
    )

    best = None
    for hidden2_factor, logit_factor in itertools.product(SCALE_FACTOR_CANDIDATES, repeat=2):
        stage_scales = [
            float(scalar_result["base_scales"][0] * selected_factors[0]),
            float(scalar_result["base_scales"][1] * selected_factors[1]),
            np.maximum(hidden2_output_scale * float(hidden2_factor), 1.0),
            float(scalar_result["base_scales"][3] * float(logit_factor)),
        ]
        quantized_layers = _prepare_quantized_layers(raw_layers, stage_scales)
        quantized_inputs = _quantize_to_s16_numpy(standardized_rows, stage_scales[0])
        logits_int, layer_stats = _run_quantized_layers_numpy(quantized_inputs, quantized_layers, collect_stats=True)
        quantized_predicted = np.argmax(logits_int, axis=1).astype(np.int64).tolist()
        agreement = (
            float(sum(int(a == b) for a, b in zip(float_predicted, quantized_predicted))) / len(float_predicted)
            if float_predicted
            else 1.0
        )
        quantized_accuracy = _safe_accuracy(test_label_ids, quantized_predicted)
        quantized_macro_f1 = _safe_macro_f1(test_label_ids, quantized_predicted)
        total_product_wraps = int(sum(item["product_wrap_count"] for item in layer_stats or []))
        total_acc_wraps = int(sum(item["accumulate_wrap_count"] for item in layer_stats or []))
        total_bias_wraps = int(sum(item["bias_wrap_count"] for item in layer_stats or []))
        candidate = {
            "scales": stage_scales,
            "factors": [
                float(selected_factors[0]),
                float(selected_factors[1]),
                float(hidden2_factor),
                float(logit_factor),
            ],
            "quantized_layers": quantized_layers,
            "quantized_inputs": quantized_inputs,
            "logits_int": logits_int,
            "quantized_predicted": quantized_predicted,
            "agreement": float(agreement),
            "quantized_accuracy": quantized_accuracy,
            "quantized_macro_f1": quantized_macro_f1,
            "layer_stats": layer_stats or [],
            "score": (
                float(agreement),
                -1.0 if quantized_macro_f1 is None else float(quantized_macro_f1),
                -1.0 if quantized_accuracy is None else float(quantized_accuracy),
                -float(total_product_wraps + total_acc_wraps + total_bias_wraps),
            ),
        }
        if best is None or candidate["score"] > best["score"]:
            best = candidate

    assert best is not None
    best["base_scales"] = list(scalar_result["base_scales"])
    best["search_combo_count"] = int(scalar_result["search_combo_count"] + len(SCALE_FACTOR_CANDIDATES) ** 2)
    best["channel_scale_mode"] = "layer_1_output_per_channel"
    best["scalar_reference_scales"] = list(scalar_result["scales"])
    return best


def _run_quantized_prefix_ablation(
    standardized_rows: np.ndarray,
    raw_layers: list[tuple[np.ndarray, np.ndarray, str]],
    quantized_layers: list[dict],
    scales: list[float],
    float_predicted: list[int],
    test_label_ids: np.ndarray | None,
    labels: list[str],
) -> list[dict]:
    rows: list[dict] = []

    input_only = _quantize_to_s16_numpy(standardized_rows, scales[0]).astype(np.float64) / scales[0]
    input_only_logits = _forward_float_activations(input_only, raw_layers)[-1]
    input_only_pred = np.argmax(input_only_logits, axis=1).astype(np.int64).tolist()
    rows.append(
        {
            "name": "input_only",
            "quantized_prefix_layers": 0,
            "float_vs_quantized_agreement": float(
                sum(int(a == b) for a, b in zip(float_predicted, input_only_pred)) / len(float_predicted)
            ),
            "quantized_vs_true_accuracy": _safe_accuracy(test_label_ids, input_only_pred),
            "quantized_vs_true_macro_f1": _safe_macro_f1(test_label_ids, input_only_pred),
            "prediction_histogram": _prediction_histogram(input_only_pred, labels),
        }
    )

    quantized_inputs = _quantize_to_s16_numpy(standardized_rows, scales[0])
    current_int = quantized_inputs
    for prefix_layers in range(1, len(quantized_layers) + 1):
        current_int, _ = _run_quantized_layers_numpy(current_int, [quantized_layers[prefix_layers - 1]], collect_stats=False)
        if prefix_layers == len(quantized_layers):
            logits = current_int.astype(np.float64) / _scale_vector(scales[prefix_layers], current_int.shape[1])[np.newaxis, :]
        else:
            cur = current_int.astype(np.float64) / _scale_vector(scales[prefix_layers], current_int.shape[1])[np.newaxis, :]
            for weight, bias, activation in raw_layers[prefix_layers:]:
                cur = cur @ weight.T + bias[np.newaxis, :]
                if activation == "relu":
                    cur = np.maximum(cur, 0.0)
            logits = cur
        predicted = np.argmax(logits, axis=1).astype(np.int64).tolist()
        rows.append(
            {
                "name": f"first_{prefix_layers}_layers",
                "quantized_prefix_layers": prefix_layers,
                "float_vs_quantized_agreement": float(
                    sum(int(a == b) for a, b in zip(float_predicted, predicted)) / len(float_predicted)
                ),
                "quantized_vs_true_accuracy": _safe_accuracy(test_label_ids, predicted),
                "quantized_vs_true_macro_f1": _safe_macro_f1(test_label_ids, predicted),
                "prediction_histogram": _prediction_histogram(predicted, labels),
            }
        )
    return rows


def _build_layer_diagnostics(
    float_activations: list[np.ndarray],
    quantized_layers: list[dict],
    quantized_layer_stats: list[dict],
) -> list[dict]:
    rows: list[dict] = []
    for index, layer in enumerate(quantized_layers):
        stats = quantized_layer_stats[index]
        rows.append(
            {
                "layer_index": int(index),
                "in_dim": int(layer["in_dim"]),
                "out_dim": int(layer["out_dim"]),
                "activation": layer["activation"],
                "input_scale": _representative_scale(layer["input_scale"]),
                "input_scale_mode": "scalar" if np.isscalar(layer["input_scale"]) else "per_channel",
                "output_scale": _representative_scale(layer["output_scale"]),
                "output_scale_mode": "scalar" if np.isscalar(layer["output_scale"]) else "per_channel",
                "input_scale_detail": _scale_json(layer["input_scale"]),
                "output_scale_detail": _scale_json(layer["output_scale"]),
                "float_input_min": float(np.min(float_activations[index])),
                "float_input_max": float(np.max(float_activations[index])),
                "float_output_min": float(np.min(float_activations[index + 1])),
                "float_output_max": float(np.max(float_activations[index + 1])),
                "quantized_output_min": int(stats["quantized_output_min"]),
                "quantized_output_max": int(stats["quantized_output_max"]),
                "quantized_output_nonzero_ratio": float(stats["quantized_output_nonzero_ratio"]),
                "product_wrap_count": int(stats["product_wrap_count"]),
                "accumulate_wrap_count": int(stats["accumulate_wrap_count"]),
                "bias_wrap_count": int(stats["bias_wrap_count"]),
            }
        )
    return rows


def _select_scales(
    standardized_calibration: np.ndarray,
    standardized_rows: np.ndarray,
    raw_layers: list[tuple[np.ndarray, np.ndarray, str]],
    float_predicted: list[int],
    test_label_ids: np.ndarray | None,
    input_target: float,
    hidden_target: float,
    logit_target: float,
) -> dict:
    activations = _forward_float_activations(standardized_calibration, raw_layers)
    base_scales = [_safe_scale(float(np.max(np.abs(activations[0]))), input_target)]
    for index, (weight, bias, _) in enumerate(raw_layers):
        target = logit_target if index == len(raw_layers) - 1 else hidden_target
        activation_limited, bias_limit, product_limit, partial_limit = _layer_scale_limits(
            activations[index],
            weight,
            bias,
            activations[index + 1],
            target,
        )
        base_scales.append(max(1.0, min(activation_limited, bias_limit, product_limit, partial_limit)))

    best = None
    search_combo_count = 0
    for scale_factors in itertools.product(SCALE_FACTOR_CANDIDATES, repeat=len(base_scales)):
        candidate = _evaluate_scale_candidate(
            standardized_rows=standardized_rows,
            test_label_ids=test_label_ids,
            raw_layers=raw_layers,
            float_predicted=float_predicted,
            base_scales=base_scales,
            scale_factors=scale_factors,
        )
        search_combo_count += 1
        if best is None or candidate["score"] > best["score"]:
            best = candidate

    assert best is not None
    best["base_scales"] = [float(value) for value in base_scales]
    best["search_combo_count"] = int(search_combo_count)
    return _refine_hidden2_channel_scales(
        standardized_calibration=standardized_calibration,
        standardized_rows=standardized_rows,
        raw_layers=raw_layers,
        float_predicted=float_predicted,
        test_label_ids=test_label_ids,
        scalar_result=best,
        hidden_target=hidden_target,
    )


def build_manifest_from_arrays(
    model_dir: str | Path,
    calibration_features: np.ndarray,
    calibration_label_ids: np.ndarray | None = None,
    test_features: np.ndarray | None = None,
    test_names: list[str] | None = None,
    num_tests: int = 8,
    input_target: float = 2048.0,
    hidden_target: float = 4096.0,
    logit_target: float = 4096.0,
) -> tuple[dict, dict]:
    torch = _lazy_import_torch()
    joblib = _lazy_import_joblib()
    import sklearn

    model_path = Path(model_dir)
    feature_cols = _load_json(model_path / "feature_columns.json")
    if feature_cols != FEATURE_COLS:
        raise ValueError("feature_columns.json does not match the current RSU feature order")

    label_mapping = _load_json(model_path / "label_mapping.json")
    labels = labels_from_mapping(label_mapping)

    scaler = joblib.load(model_path / "scaler.pkl")
    if len(feature_cols) != len(getattr(scaler, "mean_", [])):
        raise ValueError("scaler feature dimension does not match feature_columns.json")

    model = SmallMLP(in_dim=len(feature_cols), num_classes=len(labels), dropout=0.0)
    state_dict = torch.load(model_path / "best_model.pt", map_location="cpu", weights_only=True)
    model.load_state_dict(state_dict)
    model.eval()

    raw_layers = _extract_float_layers(model)

    calibration_raw = np.asarray(calibration_features, dtype=np.float64)
    if calibration_raw.ndim != 2 or calibration_raw.shape[1] != len(feature_cols):
        raise ValueError("calibration_features must have shape [N, input_dim]")

    test_rows_raw = calibration_raw if test_features is None else np.asarray(test_features, dtype=np.float64)
    if test_rows_raw.ndim != 2 or test_rows_raw.shape[1] != len(feature_cols):
        raise ValueError("test_features must have shape [N, input_dim]")

    calibration = scaler.transform(calibration_raw)
    test_rows = scaler.transform(test_rows_raw)
    if test_features is None:
        test_label_ids = calibration_label_ids
    elif calibration_label_ids is not None and len(test_rows_raw) == len(calibration_label_ids):
        test_label_ids = calibration_label_ids
    else:
        test_label_ids = None

    if test_names is None:
        test_names = [f"sample_{index}" for index in range(len(test_rows))]

    float_activations = _forward_float_activations(test_rows, raw_layers)
    full_float_logits = float_activations[-1]
    full_float_predicted = np.argmax(full_float_logits, axis=1).astype(np.int64).tolist()

    search_result = _select_scales(
        standardized_calibration=calibration,
        standardized_rows=test_rows,
        raw_layers=raw_layers,
        float_predicted=full_float_predicted,
        test_label_ids=test_label_ids,
        input_target=input_target,
        hidden_target=hidden_target,
        logit_target=logit_target,
    )

    scales = search_result["scales"]
    quantized_layers = search_result["quantized_layers"]
    full_quantized_inputs = search_result["quantized_inputs"]
    full_quantized_logits = search_result["logits_int"]
    full_quantized_predicted = search_result["quantized_predicted"]
    quantized_layer_stats = search_result["layer_stats"]

    full_agreement = (
        float(sum(int(a == b) for a, b in zip(full_float_predicted, full_quantized_predicted))) / len(full_float_predicted)
        if full_float_predicted
        else 1.0
    )

    selection = _select_test_indices(test_label_ids, num_tests, len(test_rows))
    selected_rows = test_rows[selection]
    selected_names = [test_names[index] for index in selection]
    selected_label_ids = None if test_label_ids is None else test_label_ids[selection]
    quantized_tests = full_quantized_inputs[selection]
    float_predicted = [int(full_float_predicted[index]) for index in selection]
    quantized_predicted = [int(full_quantized_predicted[index]) for index in selection]
    agreement = (
        float(sum(int(a == b) for a, b in zip(float_predicted, quantized_predicted))) / len(float_predicted)
        if float_predicted
        else 1.0
    )

    manifest = _build_manifest(
        model_path=model_path,
        feature_cols=feature_cols,
        labels=labels,
        scaler=scaler,
        sklearn_version=str(sklearn.__version__),
        quantized_layers=quantized_layers,
        quantized_tests=quantized_tests,
        selected_names=selected_names,
        scales=scales,
        base_scales=search_result["base_scales"],
        selected_factors=search_result["factors"],
        search_combo_count=search_result["search_combo_count"],
        channel_scale_mode=search_result.get("channel_scale_mode", "scalar_only"),
    )

    quantized_logits_float = full_quantized_logits.astype(np.float64) / _scale_vector(scales[-1], full_quantized_logits.shape[1])[np.newaxis, :]

    full_rows = []
    for index in range(len(test_rows)):
        label_id = None if test_label_ids is None else int(test_label_ids[index])
        full_rows.append(
            {
                "name": test_names[index],
                "label_id": label_id,
                "float_predicted_class": int(full_float_predicted[index]),
                "quantized_predicted_class": int(full_quantized_predicted[index]),
                "match": bool(full_float_predicted[index] == full_quantized_predicted[index]),
            }
        )

    report = {
        "source_model_dir": str(model_path.resolve()),
        "input_contract": INPUT_CONTRACT,
        "num_calibration_rows": int(len(calibration)),
        "num_full_dataset_rows": int(len(test_rows)),
        "num_selected_tests": int(len(quantized_tests)),
        "feature_columns": feature_cols,
        "labels": labels,
        "scaler_class": scaler.__class__.__name__,
        "scaler_sklearn_version": str(sklearn.__version__),
        "scaler_mean": _json_ready_float_list(np.asarray(scaler.mean_, dtype=np.float64)),
        "scaler_scale": _json_ready_float_list(np.asarray(scaler.scale_, dtype=np.float64)),
        "input_scale": float(scales[0]),
        "activation_scales": [_representative_scale(value) for value in scales[1:]],
        "per_channel_activation_scales": {
            f"layer_{index}_output": _scale_json(scale)
            for index, scale in enumerate(scales[1:])
            if not np.isscalar(scale)
        },
        "base_scales": [float(value) for value in search_result["base_scales"]],
        "selected_scale_factors": [float(value) for value in search_result["factors"]],
        "scale_factor_candidates": [float(value) for value in SCALE_FACTOR_CANDIDATES],
        "scale_search_combination_count": int(search_result["search_combo_count"]),
        "channel_scale_mode": search_result.get("channel_scale_mode", "scalar_only"),
        "scalar_reference_scales": [
            float(value) for value in search_result.get("scalar_reference_scales", search_result["base_scales"])
        ],
        "float_vs_quantized_test_class_agreement": agreement,
        "float_vs_quantized_full_dataset_class_agreement": full_agreement,
        "float_prediction_histogram": _prediction_histogram(full_float_predicted, labels),
        "quantized_prediction_histogram": _prediction_histogram(full_quantized_predicted, labels),
        "float_vs_true_accuracy": _safe_accuracy(test_label_ids, full_float_predicted),
        "quantized_vs_true_accuracy": _safe_accuracy(test_label_ids, full_quantized_predicted),
        "float_vs_true_macro_f1": _safe_macro_f1(test_label_ids, full_float_predicted),
        "quantized_vs_true_macro_f1": _safe_macro_f1(test_label_ids, full_quantized_predicted),
        "float_vs_true_confusion_matrix": _safe_confusion_matrix(test_label_ids, full_float_predicted, len(labels)),
        "quantized_vs_true_confusion_matrix": _safe_confusion_matrix(test_label_ids, full_quantized_predicted, len(labels)),
        "float_vs_quantized_confusion_matrix": _safe_confusion_matrix(
            np.asarray(full_float_predicted, dtype=np.int64),
            full_quantized_predicted,
            len(labels),
        ),
        "float_logit_margin_stats": _logit_margin_stats(full_float_logits),
        "quantized_logit_margin_stats": _logit_margin_stats(quantized_logits_float),
        "per_class_logit_stats": _per_class_logit_stats(full_float_logits, quantized_logits_float, labels),
        "layer_diagnostics": _build_layer_diagnostics(float_activations, quantized_layers, quantized_layer_stats),
        "quantized_prefix_ablation": _run_quantized_prefix_ablation(
            standardized_rows=test_rows,
            raw_layers=raw_layers,
            quantized_layers=quantized_layers,
            scales=scales,
            float_predicted=full_float_predicted,
            test_label_ids=test_label_ids,
            labels=labels,
        ),
        "selected_tests": [
            {
                "name": selected_names[index],
                "label_id": None if selected_label_ids is None else int(selected_label_ids[index]),
                "float_predicted_class": int(float_predicted[index]),
                "quantized_predicted_class": int(quantized_predicted[index]),
                "standardized_input": _json_ready_float_list(selected_rows[index]),
                "quantized_input": _json_ready_int_list(quantized_tests[index]),
            }
            for index in range(len(quantized_tests))
        ],
        "full_dataset_rows": full_rows,
    }
    return manifest, report


def export_manifest_from_dataset(
    model_dir: str | Path,
    dataset_path: str | Path,
    output_path: str | Path,
    report_path: str | Path,
    sheet_name: str = DEFAULT_INPUT_SHEET,
    label_col: str = DEFAULT_LABEL_COL,
    num_tests: int = 8,
    input_target: float = 2048.0,
    hidden_target: float = 4096.0,
    logit_target: float = 4096.0,
) -> tuple[dict, dict]:
    frame = _read_dataset_frame(dataset_path, sheet_name=sheet_name)
    features = _feature_matrix_from_frame(frame)
    labels = _label_ids_from_frame(frame, _load_labels(model_dir), label_col)
    names = _test_names_from_frame(frame)
    manifest, report = build_manifest_from_arrays(
        model_dir=model_dir,
        calibration_features=features,
        calibration_label_ids=labels,
        test_names=names,
        num_tests=num_tests,
        input_target=input_target,
        hidden_target=hidden_target,
        logit_target=logit_target,
    )
    _write_json(Path(output_path), manifest)
    _write_json(Path(report_path), report)
    return manifest, report


def _load_labels(model_dir: str | Path) -> list[str]:
    label_mapping = _load_json(Path(model_dir) / "label_mapping.json")
    return labels_from_mapping(label_mapping)


def _ste_clip_round_torch(values):
    torch = _lazy_import_torch()
    quantized = torch.clamp(torch.round(values), -32768.0, 32767.0)
    return values + (quantized - values).detach()


def _ste_wrap_s16_torch(values):
    torch = _lazy_import_torch()
    wrapped = torch.remainder(values + 32768.0, 65536.0) - 32768.0
    return values + (wrapped - values).detach()


def hardware_aligned_mlp_torch(
    standardized_inputs,
    linear_layers,
    input_scale: float,
    activation_scales: list[float],
):
    torch = _lazy_import_torch()
    scales = [float(input_scale)] + [float(value) for value in activation_scales]
    acts = _ste_clip_round_torch(standardized_inputs * scales[0])
    for layer_index, linear in enumerate(linear_layers):
        out_scale = scales[layer_index + 1]
        in_scale = scales[layer_index]
        weight_int = _ste_clip_round_torch(linear.weight * (out_scale / in_scale))
        bias_int = _ste_clip_round_torch(linear.bias * out_scale)
        acc = torch.zeros((acts.shape[0], weight_int.shape[0]), dtype=acts.dtype, device=acts.device)
        for in_index in range(weight_int.shape[1]):
            product = _ste_wrap_s16_torch(acts[:, in_index : in_index + 1] * weight_int[:, in_index].unsqueeze(0))
            acc = _ste_wrap_s16_torch(acc + product)
        acc = _ste_wrap_s16_torch(acc + bias_int.unsqueeze(0))
        if layer_index < len(linear_layers) - 1:
            acc = torch.relu(acc)
        acts = acc
    return acts / scales[-1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export trained RSU MLP artifacts into an annmodelctl-compatible int16 manifest."
    )
    parser.add_argument("--model-dir", default=str(DEFAULT_MODEL_DIR))
    parser.add_argument("--dataset", default=str(DEFAULT_INPUT_XLSX))
    parser.add_argument("--sheet-name", default=DEFAULT_INPUT_SHEET)
    parser.add_argument("--label-col", default=DEFAULT_LABEL_COL)
    parser.add_argument("--output", default=str(DEFAULT_MANIFEST_PATH))
    parser.add_argument("--report-output", default=str(DEFAULT_MANIFEST_REPORT_PATH))
    parser.add_argument("--test-count", type=int, default=8)
    parser.add_argument("--input-target", type=float, default=2048.0)
    parser.add_argument("--hidden-target", type=float, default=4096.0)
    parser.add_argument("--logit-target", type=float, default=4096.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest, report = export_manifest_from_dataset(
        model_dir=args.model_dir,
        dataset_path=args.dataset,
        output_path=args.output,
        report_path=args.report_output,
        sheet_name=args.sheet_name,
        label_col=args.label_col,
        num_tests=args.test_count,
        input_target=args.input_target,
        hidden_target=args.hidden_target,
        logit_target=args.logit_target,
    )
    print(f"exported manifest: {args.output}")
    print(f"exported report: {args.report_output}")
    print(f"input_dim={manifest['input_dim']}")
    print(f"output_dim={len(manifest['labels'])}")
    print(f"full_dataset_agreement={report['float_vs_quantized_full_dataset_class_agreement']:.4f}")


if __name__ == "__main__":
    main()
