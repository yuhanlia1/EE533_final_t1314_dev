#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from cpu_toolchain.toolchain import build_single, load_image
from gpu_toolchain.bundle import load_params, load_program, package_bundle


MODEL_TYPE = "mlp"
QUANT_TYPE = "int16"

PROGRAM_SOURCE_NAME = "program.gpus"
PARAM_SOURCE_NAME = "params.txt"
META_SOURCE_NAME = "meta.json"
MANIFEST_OUTPUT_NAME = "model_manifest.json"
CPU_SOURCE_NAME = "cpu_runtime.s"
TEST_VECTOR_OUTPUT_NAME = "test_vectors.json"
EXPECTED_OUTPUT_NAME = "expected_outputs.json"
REPORT_OUTPUT_NAME = "ann_model_report.txt"

CPU_BUILD_DIR_NAME = "cpu_build"
GPU_SOURCE_DIR_NAME = "gpu_bundle"
GPU_BUILD_DIR_NAME = "gpu_build"

HARDWARE_INPUT_DIM = 784
HARDWARE_OUTPUT_DIM_MAX = 96
A_SCRATCH_CAPACITY = 96
D_SCRATCH_CAPACITY = 2048
A_RESULT_CAPACITY = 96
D_RESULT_CAPACITY = 96
DMEM_DEPTH_WORDS = 16384

BASE_C = 32
BASE_A = 128
BASE_D = 1024
BASE_B = 3072
BASE_D_AUX = BASE_D

A_INPUT_OFFSET = 0
A_SCRATCH_OFFSET = 800
A_RESULT_OFFSET = 800
D_SCRATCH_OFFSET = 0
D_RESULT_OFFSET = 1900

CPU_MMIO_BASE = 0x80
GPU_REG_ENTRY_PC = 0x08
GPU_REG_TID_INIT = 0x0C
GPU_REG_WORK_SIZE = 0x10
GPU_REG_BASE_A = 0x20
GPU_REG_BASE_B = 0x28
GPU_REG_BASE_C = 0x30
GPU_REG_BASE_D = 0x38


def ensure_out_dir(out_dir: str | None, prefix: str) -> Path:
    if out_dir:
        path = Path(out_dir)
        path.mkdir(parents=True, exist_ok=True)
        return path
    return Path(tempfile.mkdtemp(prefix=prefix))


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _parse_int(value: object, label: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{label} must be an integer")
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 0)
    raise ValueError(f"{label} must be an integer-compatible value")


def _wrap_u16(value: int) -> int:
    return value & 0xFFFF


def _to_s16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def _relu_s16(value: int) -> int:
    return 0 if value < 0 else value


def _pack_param_word(value: int) -> tuple[int, int]:
    return 0, _wrap_u16(value)


@dataclass
class LayerPlan:
    index: int
    in_dim: int
    out_dim: int
    activation: str
    src_bank: str
    src_offset: int
    dst_bank: str
    dst_offset: int
    weight_offset: int
    bias_offset: int
    weights: list[list[int]] = field(default_factory=list)
    bias: list[int] = field(default_factory=list)


@dataclass
class TestVector:
    name: str
    values: list[int]


@dataclass
class ExpectedVector:
    name: str
    logits_s16: list[int]
    logits_u16: list[int]
    predicted_class: int
    predicted_score_s16: int
    result_data_0_u16: int
    result_data_1_u16: int


@dataclass
class AnnModelBuildResult:
    mode: str
    out_dir: Path
    source_path: str
    manifest_path: Path
    cpu_source_path: Path
    cpu_image_path: Path
    gpu_program_path: Path
    gpu_param_source_path: Path
    gpu_meta_path: Path
    gpu_imem_path: Path
    gpu_params_path: Path
    report_path: Path
    test_vector_path: Path
    expected_output_path: Path
    input_dim: int
    output_dim: int
    result_mode: str
    result_base: int
    layer_count: int
    test_count: int
    layers: list[LayerPlan] = field(default_factory=list)


def _parse_manifest(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return raw


def _normalize_layer(raw: dict, index: int, in_dim: int) -> tuple[int, str, list[list[int]], list[int]]:
    if not isinstance(raw, dict):
        raise ValueError(f"layer {index} must be an object")
    out_dim = _parse_int(raw.get("out_dim"), f"layer {index} out_dim")
    if out_dim <= 0:
        raise ValueError(f"layer {index} out_dim must be greater than zero")

    activation = str(raw.get("activation", "none")).lower()
    if activation not in ("none", "relu"):
        raise ValueError(f"layer {index} activation must be 'none' or 'relu'")

    weights_raw = raw.get("weights")
    if not isinstance(weights_raw, list) or len(weights_raw) != out_dim:
        raise ValueError(f"layer {index} weights must contain {out_dim} rows")
    weights: list[list[int]] = []
    for row_index, row in enumerate(weights_raw):
        if not isinstance(row, list) or len(row) != in_dim:
            raise ValueError(f"layer {index} weight row {row_index} must contain {in_dim} entries")
        weights.append([_to_s16(_parse_int(value, f"layer {index} weight[{row_index}]")) for value in row])

    bias_raw = raw.get("bias")
    if not isinstance(bias_raw, list) or len(bias_raw) != out_dim:
        raise ValueError(f"layer {index} bias must contain {out_dim} entries")
    bias = [_to_s16(_parse_int(value, f"layer {index} bias")) for value in bias_raw]
    return out_dim, activation, weights, bias


def _normalize_tests(raw_tests: object, input_dim: int) -> list[TestVector]:
    if raw_tests is None:
        return []
    if not isinstance(raw_tests, list):
        raise ValueError("tests must be a list")
    result: list[TestVector] = []
    for index, entry in enumerate(raw_tests):
        if not isinstance(entry, dict):
            raise ValueError(f"test {index} must be an object")
        name = str(entry.get("name", f"sample{index}"))
        values_raw = entry.get("input")
        if not isinstance(values_raw, list) or len(values_raw) != input_dim:
            raise ValueError(f"test {index} input must contain {input_dim} entries")
        values = [_to_s16(_parse_int(value, f"test {index} input")) for value in values_raw]
        result.append(TestVector(name=name, values=values))
    return result


def _plan_layers(
    model: dict,
    source_path: Path,
) -> tuple[list[LayerPlan], list[TestVector], list[str], int, int, str, int]:
    model_type = str(model.get("model_type", "")).lower()
    if model_type != MODEL_TYPE:
        raise ValueError(f"{source_path}: model_type must be '{MODEL_TYPE}'")

    quant_type = str(model.get("quant_type", "")).lower()
    if quant_type != QUANT_TYPE:
        raise ValueError(f"{source_path}: quant_type must be '{QUANT_TYPE}'")

    input_dim = _parse_int(model.get("input_dim"), "input_dim")
    if input_dim <= 0 or input_dim > HARDWARE_INPUT_DIM:
        raise ValueError(f"{source_path}: input_dim must be between 1 and {HARDWARE_INPUT_DIM}")

    raw_layers = model.get("layers")
    if not isinstance(raw_layers, list) or not raw_layers:
        raise ValueError(f"{source_path}: layers must be a non-empty list")

    layer_specs: list[tuple[int, str, list[list[int]], list[int]]] = []
    cur_in_dim = input_dim
    for index, raw_layer in enumerate(raw_layers):
        normalized = _normalize_layer(raw_layer, index, cur_in_dim)
        layer_specs.append(normalized)
        cur_in_dim = normalized[0]

    output_dim = cur_in_dim
    if output_dim <= 0 or output_dim > HARDWARE_OUTPUT_DIM_MAX:
        raise ValueError(
            f"{source_path}: output_dim must be between 1 and {HARDWARE_OUTPUT_DIM_MAX}, got {output_dim}"
        )

    labels_raw = model.get("labels", [])
    if labels_raw:
        if not isinstance(labels_raw, list):
            raise ValueError(f"{source_path}: labels must be a list when present")
        if len(labels_raw) != output_dim:
            labels = [str(index) for index in range(output_dim)]
        else:
            labels = [str(label) for label in labels_raw]
    else:
        labels = []

    tests = _normalize_tests(model.get("tests"), input_dim)

    layers: list[LayerPlan] = []
    weight_cursor = 0
    bias_cursor = 0
    src_bank = "A"
    src_offset = A_INPUT_OFFSET

    for index, (out_dim, activation, weights, bias) in enumerate(layer_specs):
        is_final = index == len(layer_specs) - 1
        if is_final:
            if src_bank == "A":
                dst_bank = "D"
                dst_offset = D_RESULT_OFFSET
                capacity = D_RESULT_CAPACITY
            else:
                dst_bank = "A"
                dst_offset = A_RESULT_OFFSET
                capacity = A_RESULT_CAPACITY
        else:
            if src_bank == "A":
                dst_bank = "D"
                dst_offset = D_SCRATCH_OFFSET
                capacity = D_SCRATCH_CAPACITY
            else:
                dst_bank = "A"
                dst_offset = A_SCRATCH_OFFSET
                capacity = A_SCRATCH_CAPACITY

        if out_dim > capacity:
            raise ValueError(
                f"{source_path}: layer {index} out_dim {out_dim} exceeds current {dst_bank}-bank capacity {capacity}"
            )

        layer = LayerPlan(
            index=index,
            in_dim=len(weights[0]),
            out_dim=out_dim,
            activation=activation,
            src_bank=src_bank,
            src_offset=src_offset,
            dst_bank=dst_bank,
            dst_offset=dst_offset,
            weight_offset=weight_cursor,
            bias_offset=bias_cursor,
            weights=weights,
            bias=bias,
        )
        layers.append(layer)
        weight_cursor += layer.in_dim * layer.out_dim
        bias_cursor += layer.out_dim
        src_bank = dst_bank
        src_offset = dst_offset

    if BASE_B + weight_cursor > DMEM_DEPTH_WORDS:
        raise ValueError(f"{source_path}: packed weights exceed the current DMEM weight window")
    if BASE_C + bias_cursor > BASE_A:
        raise ValueError(f"{source_path}: packed bias values exceed the current DMEM bias window")

    my_result_base = BASE_A + A_RESULT_OFFSET if src_bank == "A" else BASE_D + D_RESULT_OFFSET
    my_result_mode = "compact_class_score" if output_dim > 2 else "legacy_logits"

    return layers, tests, labels, input_dim, output_dim, my_result_mode, my_result_base


def _render_gpu_program(layers: list[LayerPlan]) -> str:
    lines = [".entry:"]
    for layer in layers:
        for out_index in range(layer.out_dim):
            lines.append("  loadi r6, 0")
            for in_index in range(layer.in_dim):
                lines.append(f"  load r0, {layer.src_bank}, {layer.src_offset + in_index}")
                weight_addr = layer.weight_offset + (out_index * layer.in_dim) + in_index
                lines.append(f"  load r1, B, {weight_addr}")
                lines.append("  tensor_mac r6, r0, r1")
            lines.append(f"  load r2, C, {layer.bias_offset + out_index}")
            lines.append("  add r6, r6, r2")
            if layer.activation == "relu":
                lines.append("  relu r6, r6")
            lines.append(f"  store {layer.dst_bank}, r6, {layer.dst_offset + out_index}")
            lines.append("")
    lines.append("  halt")
    return "\n".join(line for line in lines if line is not None).rstrip() + "\n"


def _render_params(layers: list[LayerPlan]) -> str:
    lines: list[str] = []
    for layer in layers:
        for out_index, row in enumerate(layer.weights):
            for in_index, value in enumerate(row):
                addr = BASE_B + layer.weight_offset + (out_index * layer.in_dim) + in_index
                hi32, lo32 = _pack_param_word(value)
                lines.append(f"0x{addr:08x} 0x{hi32:08x} 0x{lo32:08x}")
        for out_index, value in enumerate(layer.bias):
            addr = BASE_C + layer.bias_offset + out_index
            hi32, lo32 = _pack_param_word(value)
            lines.append(f"0x{addr:08x} 0x{hi32:08x} 0x{lo32:08x}")
    return "\n".join(lines) + ("\n" if lines else "")


def _render_gpu_meta() -> str:
    meta = {
        "entry_pc": 0,
        "tid_init": 0,
        "work_size": 1,
        "base_a": BASE_A,
        "base_b": BASE_B,
        "base_c": BASE_C,
        "base_d": BASE_D_AUX,
        "m": 0,
        "n": 0,
        "k": 0,
    }
    return json.dumps(meta, indent=2, sort_keys=False) + "\n"


def _render_cpu_runtime() -> str:
    lines = [
        ".main:",
        f"  mov r10, #{CPU_MMIO_BASE}",
        "  mov r0, #0",
        "  mov r1, #0",
        "  mov r2, #1",
        f"  mov r3, #{BASE_A}",
        f"  mov r4, #{BASE_B >> 1}",
        "  lsl r4, r4, #1",
        f"  mov r5, #{BASE_C}",
        f"  mov r6, #{BASE_D_AUX}",
        f"  str r0, [r10, #{GPU_REG_ENTRY_PC}]",
        f"  str r1, [r10, #{GPU_REG_TID_INIT}]",
        f"  str r2, [r10, #{GPU_REG_WORK_SIZE}]",
        f"  str r3, [r10, #{GPU_REG_BASE_A}]",
        f"  str r4, [r10, #{GPU_REG_BASE_B}]",
        f"  str r5, [r10, #{GPU_REG_BASE_C}]",
        f"  str r6, [r10, #{GPU_REG_BASE_D}]",
        ".done:",
        "  b .done",
    ]
    return "\n".join(lines) + "\n"


def _reference_infer(sample: list[int], layers: list[LayerPlan]) -> ExpectedVector:
    activations = sample[:]
    for layer in layers:
        next_values: list[int] = []
        for out_index in range(layer.out_dim):
            acc = 0
            for in_index in range(layer.in_dim):
                product = _to_s16(activations[in_index] * layer.weights[out_index][in_index])
                acc = _to_s16(acc + product)
            acc = _to_s16(acc + layer.bias[out_index])
            if layer.activation == "relu":
                acc = _relu_s16(acc)
            next_values.append(acc)
        activations = next_values

    logits_s16 = activations
    logits_u16 = [_wrap_u16(value) for value in logits_s16]
    predicted_class = max(range(len(logits_s16)), key=lambda index: logits_s16[index])
    predicted_score = logits_s16[predicted_class]
    return ExpectedVector(
        name="",
        logits_s16=logits_s16,
        logits_u16=logits_u16,
        predicted_class=predicted_class,
        predicted_score_s16=predicted_score,
        result_data_0_u16=_wrap_u16(predicted_class if len(logits_s16) > 2 else logits_s16[0]),
        result_data_1_u16=_wrap_u16(predicted_score if len(logits_s16) > 2 else (logits_s16[1] if len(logits_s16) > 1 else 0)),
    )


def _expected_outputs(
    tests: list[TestVector],
    layers: list[LayerPlan],
    labels: list[str],
    result_mode: str,
) -> tuple[str, str]:
    vectors_json: list[dict[str, object]] = []
    expected_json: list[dict[str, object]] = []

    for test in tests:
        expected = _reference_infer(test.values, layers)
        expected.name = test.name
        vectors_json.append(
            {
                "name": test.name,
                "input_s16": test.values,
                "input_u16": [f"0x{_wrap_u16(value):04x}" for value in test.values],
            }
        )
        row: dict[str, object] = {
            "name": test.name,
            "logits_s16": expected.logits_s16,
            "logits_u16": [f"0x{value:04x}" for value in expected.logits_u16],
            "predicted_class": expected.predicted_class,
            "predicted_score_s16": expected.predicted_score_s16,
            "wire_result_data_0_u16": f"0x{expected.result_data_0_u16:04x}",
            "wire_result_data_1_u16": f"0x{expected.result_data_1_u16:04x}",
            "result_mode": result_mode,
        }
        if labels:
            row["predicted_label"] = labels[expected.predicted_class]
        expected_json.append(row)

    return (
        json.dumps(vectors_json, indent=2, sort_keys=False) + "\n",
        json.dumps(expected_json, indent=2, sort_keys=False) + "\n",
    )


def _normalized_manifest(
    source_path: str,
    layers: list[LayerPlan],
    labels: list[str],
    tests: list[TestVector],
    input_dim: int,
    output_dim: int,
    result_mode: str,
    result_base: int,
) -> str:
    manifest = {
        "model_type": MODEL_TYPE,
        "quant_type": QUANT_TYPE,
        "source": source_path,
        "hardware_limits": {
            "input_dim_max": HARDWARE_INPUT_DIM,
            "output_dim_max": HARDWARE_OUTPUT_DIM_MAX,
            "a_scratch_capacity": A_SCRATCH_CAPACITY,
            "d_scratch_capacity": D_SCRATCH_CAPACITY,
            "result_capacity_max": max(A_RESULT_CAPACITY, D_RESULT_CAPACITY),
            "result_semantics": "wire_result_data_0/1 carry logits for binary models or class_id/score for compact multi-class models",
        },
        "runtime": {
            "cpu_mmio_base": CPU_MMIO_BASE,
            "base_a": BASE_A,
            "base_b": BASE_B,
            "base_c": BASE_C,
            "base_d": BASE_D_AUX,
            "work_size": 1,
            "entry_pc": 0,
            "result_mode": result_mode,
            "result_output_base": result_base,
            "result_output_count": output_dim,
        },
        "input_dim": input_dim,
        "output_dim": output_dim,
        "labels": labels,
        "layers": [
            {
                "index": layer.index,
                "in_dim": layer.in_dim,
                "out_dim": layer.out_dim,
                "activation": layer.activation,
                "src": {"bank": layer.src_bank, "offset": layer.src_offset},
                "dst": {"bank": layer.dst_bank, "offset": layer.dst_offset},
                "weight_offset": layer.weight_offset,
                "bias_offset": layer.bias_offset,
            }
            for layer in layers
        ],
        "tests": [{"name": test.name, "input_s16": test.values} for test in tests],
    }
    return json.dumps(manifest, indent=2, sort_keys=False) + "\n"


def _report_text(result: AnnModelBuildResult) -> str:
    lines = [
        f"mode={result.mode}",
        f"source={result.source_path}",
        f"input_dim={result.input_dim}",
        f"output_dim={result.output_dim}",
        f"result_mode={result.result_mode}",
        f"result_base=0x{result.result_base:08x}",
        f"layer_count={result.layer_count}",
        f"test_count={result.test_count}",
        f"manifest={result.manifest_path.name}",
        f"cpu_source={result.cpu_source_path.name}",
        f"cpu_image={result.cpu_image_path}",
        f"gpu_program={result.gpu_program_path}",
        f"gpu_params={result.gpu_params_path}",
        "wire_result_semantics=binary models keep legacy logits; multi-class models use class_id+score",
    ]
    for layer in result.layers:
        lines.append(
            f"layer{layer.index}=in:{layer.in_dim} out:{layer.out_dim} "
            f"src:{layer.src_bank}+0x{layer.src_offset:02x} "
            f"dst:{layer.dst_bank}+0x{layer.dst_offset:02x} "
            f"act={layer.activation} "
            f"weight_off=0x{layer.weight_offset:02x} "
            f"bias_off=0x{layer.bias_offset:02x}"
        )
    return "\n".join(lines) + "\n"


def build_model(source_path: str, out_dir: str) -> AnnModelBuildResult:
    source = Path(source_path)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    model = _parse_manifest(source)
    layers, tests, labels, input_dim, output_dim, result_mode, result_base = _plan_layers(model, source)

    manifest_path = out / MANIFEST_OUTPUT_NAME
    cpu_source_path = out / CPU_SOURCE_NAME
    gpu_source_dir = out / GPU_SOURCE_DIR_NAME
    gpu_program_path = gpu_source_dir / PROGRAM_SOURCE_NAME
    gpu_param_source_path = gpu_source_dir / PARAM_SOURCE_NAME
    gpu_meta_path = gpu_source_dir / META_SOURCE_NAME
    test_vector_path = out / TEST_VECTOR_OUTPUT_NAME
    expected_output_path = out / EXPECTED_OUTPUT_NAME
    report_path = out / REPORT_OUTPUT_NAME

    _write_text(
        manifest_path,
        _normalized_manifest(str(source), layers, labels, tests, input_dim, output_dim, result_mode, result_base),
    )
    _write_text(cpu_source_path, _render_cpu_runtime())
    _write_text(gpu_program_path, _render_gpu_program(layers))
    _write_text(gpu_param_source_path, _render_params(layers))
    _write_text(gpu_meta_path, _render_gpu_meta())

    vectors_json, expected_json = _expected_outputs(tests, layers, labels, result_mode)
    _write_text(test_vector_path, vectors_json)
    _write_text(expected_output_path, expected_json)

    cpu_build_dir = out / CPU_BUILD_DIR_NAME
    cpu_result = build_single(str(cpu_source_path), str(cpu_build_dir))

    gpu_build_dir = out / GPU_BUILD_DIR_NAME
    gpu_result = package_bundle(str(gpu_source_dir), str(gpu_build_dir))

    result = AnnModelBuildResult(
        mode="model",
        out_dir=out,
        source_path=str(source),
        manifest_path=manifest_path,
        cpu_source_path=cpu_source_path,
        cpu_image_path=cpu_result.image_path,
        gpu_program_path=gpu_program_path,
        gpu_param_source_path=gpu_param_source_path,
        gpu_meta_path=gpu_meta_path,
        gpu_imem_path=gpu_result.imem_path,
        gpu_params_path=gpu_result.params_path if gpu_result.params_path else gpu_build_dir / "compiled_gpu_params.txt",
        report_path=report_path,
        test_vector_path=test_vector_path,
        expected_output_path=expected_output_path,
        input_dim=input_dim,
        output_dim=output_dim,
        result_mode=result_mode,
        result_base=result_base,
        layer_count=len(layers),
        test_count=len(tests),
        layers=layers,
    )
    _write_text(report_path, _report_text(result))
    return result


def inspect_model(source_path: str) -> AnnModelBuildResult:
    out_dir = ensure_out_dir(None, "annmodelctl_inspect_")
    return build_model(source_path, str(out_dir))


def _resolve_built_bundle(target: Path) -> AnnModelBuildResult:
    if target.is_file():
        return build_model(str(target), str(ensure_out_dir(None, "annmodelctl_build_")))

    manifest_path = target / MANIFEST_OUTPUT_NAME
    cpu_source_path = target / CPU_SOURCE_NAME
    cpu_image_path = target / CPU_BUILD_DIR_NAME / "image.txt"
    gpu_program_path = target / GPU_SOURCE_DIR_NAME / PROGRAM_SOURCE_NAME
    gpu_param_source_path = target / GPU_SOURCE_DIR_NAME / PARAM_SOURCE_NAME
    gpu_meta_path = target / GPU_SOURCE_DIR_NAME / META_SOURCE_NAME
    gpu_imem_path = target / GPU_BUILD_DIR_NAME / "compiled_gpu_imem.txt"
    gpu_params_path = target / GPU_BUILD_DIR_NAME / "compiled_gpu_params.txt"
    report_path = target / REPORT_OUTPUT_NAME
    test_vector_path = target / TEST_VECTOR_OUTPUT_NAME
    expected_output_path = target / EXPECTED_OUTPUT_NAME
    if not all(path.exists() for path in (manifest_path, cpu_source_path, cpu_image_path, gpu_imem_path, gpu_params_path)):
        raise ValueError(f"{target} is not a compiled ANN model bundle directory")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    layers = [
        LayerPlan(
            index=int(layer["index"]),
            in_dim=int(layer["in_dim"]),
            out_dim=int(layer["out_dim"]),
            activation=str(layer["activation"]),
            src_bank=str(layer["src"]["bank"]),
            src_offset=int(layer["src"]["offset"]),
            dst_bank=str(layer["dst"]["bank"]),
            dst_offset=int(layer["dst"]["offset"]),
            weight_offset=int(layer["weight_offset"]),
            bias_offset=int(layer["bias_offset"]),
        )
        for layer in manifest["layers"]
    ]
    tests = manifest.get("tests", [])
    return AnnModelBuildResult(
        mode="model",
        out_dir=target,
        source_path=str(manifest.get("source", target)),
        manifest_path=manifest_path,
        cpu_source_path=cpu_source_path,
        cpu_image_path=cpu_image_path,
        gpu_program_path=gpu_program_path,
        gpu_param_source_path=gpu_param_source_path,
        gpu_meta_path=gpu_meta_path,
        gpu_imem_path=gpu_imem_path,
        gpu_params_path=gpu_params_path,
        report_path=report_path,
        test_vector_path=test_vector_path,
        expected_output_path=expected_output_path,
        input_dim=int(manifest["input_dim"]),
        output_dim=int(manifest["output_dim"]),
        result_mode=str(manifest["runtime"].get("result_mode", "legacy_logits")),
        result_base=int(manifest["runtime"].get("result_output_base", BASE_A + A_RESULT_OFFSET)),
        layer_count=len(layers),
        test_count=len(tests),
        layers=layers,
    )


def load_bundle(target: str, annctl_path: str | None = None) -> AnnModelBuildResult:
    resolved = _resolve_built_bundle(Path(target))
    load_image(str(resolved.cpu_image_path), annctl_path=annctl_path)
    load_program(str(resolved.gpu_imem_path), annctl_path=annctl_path)
    if resolved.gpu_params_path.exists() and resolved.gpu_params_path.read_text(encoding="utf-8").strip():
        load_params(str(resolved.gpu_params_path), annctl_path=annctl_path)
    if resolved.result_mode == "compact_class_score":
        annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parent.parent / "annctl"
        subprocess.run(
            [
                "perl",
                str(annctl),
                "engine",
                "result-config",
                f"0x{resolved.result_base:08x}",
                str(resolved.output_dim),
                "compact",
            ],
            check=True,
        )
    else:
        annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parent.parent / "annctl"
        subprocess.run(["perl", str(annctl), "engine", "result-clear"], check=True)
    return resolved


def build_model_and_load(source_path: str, out_dir: str, annctl_path: str | None = None) -> AnnModelBuildResult:
    result = build_model(source_path, out_dir)
    load_image(str(result.cpu_image_path), annctl_path=annctl_path)
    load_program(str(result.gpu_imem_path), annctl_path=annctl_path)
    if result.gpu_params_path.exists() and result.gpu_params_path.read_text(encoding="utf-8").strip():
        load_params(str(result.gpu_params_path), annctl_path=annctl_path)
    annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parent.parent / "annctl"
    if result.result_mode == "compact_class_score":
        subprocess.run(
            [
                "perl",
                str(annctl),
                "engine",
                "result-config",
                f"0x{result.result_base:08x}",
                str(result.output_dim),
                "compact",
            ],
            check=True,
        )
    else:
        subprocess.run(["perl", str(annctl), "engine", "result-clear"], check=True)
    return result
