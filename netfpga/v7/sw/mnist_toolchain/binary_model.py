#!/usr/bin/env python3

from __future__ import annotations

from typing import Any


INT16_MIN = -32768
INT16_MAX = 32767


def require_torch() -> tuple[Any, Any]:
    try:
        import torch
        import torch.nn as nn
    except ImportError as exc:
        raise SystemExit(
            "This command requires torch and torchvision. "
            "Install them in the active Python environment before running the MNIST flow."
        ) from exc
    return torch, nn


def ste_round_clamp(param: Any, torch: Any) -> Any:
    rounded = param + (torch.round(param) - param).detach()
    return torch.clamp(rounded, INT16_MIN, INT16_MAX)


def build_binary_mlp(hidden_dim: int = 8) -> Any:
    torch, nn = require_torch()

    class BinaryMnistMlp(nn.Module):
        def __init__(self, hidden_dim: int) -> None:
            super().__init__()
            self.fc1 = nn.Linear(8, hidden_dim)
            self.fc2 = nn.Linear(hidden_dim, 2)

        def forward(self, x: Any) -> Any:
            w1 = ste_round_clamp(self.fc1.weight, torch)
            b1 = ste_round_clamp(self.fc1.bias, torch)
            hidden = torch.relu(x.matmul(w1.t()) + b1)
            w2 = ste_round_clamp(self.fc2.weight, torch)
            b2 = ste_round_clamp(self.fc2.bias, torch)
            return hidden.matmul(w2.t()) + b2

    return BinaryMnistMlp(hidden_dim)


def export_quantized_layers(model: Any) -> list[dict[str, object]]:
    torch, _ = require_torch()

    def quant_tensor(tensor: Any) -> list[list[int]] | list[int]:
        rounded = torch.clamp(torch.round(tensor), INT16_MIN, INT16_MAX).to(torch.int64)
        values = rounded.tolist()
        if isinstance(values, list):
            return values
        raise ValueError("expected tensor to convert to a list")

    fc1_weights = quant_tensor(model.fc1.weight)
    fc1_bias = quant_tensor(model.fc1.bias)
    fc2_weights = quant_tensor(model.fc2.weight)
    fc2_bias = quant_tensor(model.fc2.bias)

    return [
        {
            "out_dim": len(fc1_weights),
            "activation": "relu",
            "weights": fc1_weights,
            "bias": fc1_bias,
        },
        {
            "out_dim": len(fc2_weights),
            "activation": "none",
            "weights": fc2_weights,
            "bias": fc2_bias,
        },
    ]


def wrap_s16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def infer_quantized(sample: list[int], layers: list[dict[str, object]]) -> list[int]:
    activations = sample[:]
    for layer in layers:
        weights = [[int(value) for value in row] for row in layer["weights"]]  # type: ignore[index]
        bias = [int(value) for value in layer["bias"]]  # type: ignore[index]
        activation = str(layer["activation"])

        next_values: list[int] = []
        for out_index, row in enumerate(weights):
            acc = 0
            for in_value, weight in zip(activations, row):
                product = wrap_s16(int(in_value) * int(weight))
                acc = wrap_s16(acc + product)
            acc = wrap_s16(acc + bias[out_index])
            if activation == "relu" and acc < 0:
                acc = 0
            next_values.append(acc)
        activations = next_values
    return activations
