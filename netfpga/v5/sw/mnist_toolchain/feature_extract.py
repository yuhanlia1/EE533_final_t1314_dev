#!/usr/bin/env python3

from __future__ import annotations

from typing import Iterable


MNIST_SIDE = 28
FEATURE_MAX = 31
FEATURE_NAMES = [
    "total_avg",
    "upper_half_avg",
    "lower_half_avg",
    "left_half_avg",
    "right_half_avg",
    "main_diag_band_avg",
    "anti_diag_band_avg",
    "center_window_avg",
]


def _coerce_flat_pixels(image: object) -> list[int]:
    if hasattr(image, "size") and getattr(image, "size") == (MNIST_SIDE, MNIST_SIDE) and hasattr(image, "getdata"):
        return [int(value) for value in image.getdata()]
    if hasattr(image, "tolist"):
        image = image.tolist()
    if isinstance(image, list) and len(image) == MNIST_SIDE * MNIST_SIDE:
        return [int(value) for value in image]
    if isinstance(image, list) and len(image) == MNIST_SIDE and all(isinstance(row, list) for row in image):
        flat: list[int] = []
        for row in image:
            if len(row) != MNIST_SIDE:
                raise ValueError("MNIST image rows must be length 28")
            flat.extend(int(value) for value in row)
        return flat
    raise ValueError("expected a 28x28 MNIST-compatible image")


def _region_average_quantized(flat_pixels: list[int], coords: Iterable[tuple[int, int]]) -> int:
    values = [flat_pixels[row * MNIST_SIDE + col] for row, col in coords]
    if not values:
        raise ValueError("feature region is empty")
    total = sum(values)
    denom = 255 * len(values)
    return int((total * FEATURE_MAX + (denom // 2)) // denom)


def extract_features(image: object) -> list[int]:
    flat_pixels = _coerce_flat_pixels(image)

    all_coords = [(row, col) for row in range(MNIST_SIDE) for col in range(MNIST_SIDE)]
    upper_half = [(row, col) for row in range(0, 14) for col in range(MNIST_SIDE)]
    lower_half = [(row, col) for row in range(14, 28) for col in range(MNIST_SIDE)]
    left_half = [(row, col) for row in range(MNIST_SIDE) for col in range(0, 14)]
    right_half = [(row, col) for row in range(MNIST_SIDE) for col in range(14, 28)]
    main_diag_band = [(row, col) for row in range(MNIST_SIDE) for col in range(MNIST_SIDE) if abs(row - col) <= 2]
    anti_diag_band = [
        (row, col)
        for row in range(MNIST_SIDE)
        for col in range(MNIST_SIDE)
        if abs((row + col) - (MNIST_SIDE - 1)) <= 2
    ]
    center_window = [(row, col) for row in range(9, 19) for col in range(9, 19)]

    return [
        _region_average_quantized(flat_pixels, all_coords),
        _region_average_quantized(flat_pixels, upper_half),
        _region_average_quantized(flat_pixels, lower_half),
        _region_average_quantized(flat_pixels, left_half),
        _region_average_quantized(flat_pixels, right_half),
        _region_average_quantized(flat_pixels, main_diag_band),
        _region_average_quantized(flat_pixels, anti_diag_band),
        _region_average_quantized(flat_pixels, center_window),
    ]
