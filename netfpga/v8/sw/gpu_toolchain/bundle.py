#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .assembler import Assembler, render_source


PROGRAM_SOURCE_NAME = "program.gpus"
PARAM_SOURCE_NAME = "params.txt"
META_SOURCE_NAME = "meta.json"
PROCESSED_PROGRAM_NAME = "processed.gpus"
IMEM_OUTPUT_NAME = "compiled_gpu_imem.txt"
PARAM_OUTPUT_NAME = "compiled_gpu_params.txt"
PROGRAM_REPORT_NAME = "gpu_program_report.txt"
BUNDLE_REPORT_NAME = "gpu_bundle_report.txt"
TEMPLATE_REPORT_NAME = "gpu_template_report.txt"
GPU_IMEM_MAX_WORDS = 65536

DEFAULT_ENTRY_PC = 0
DEFAULT_TID_INIT = 0
DEFAULT_WORK_SIZE = 2
DEFAULT_BASE_A = 16
DEFAULT_BASE_B = 64
DEFAULT_BASE_C = 224
DEFAULT_BASE_D = 248
DEFAULT_M = 0
DEFAULT_N = 0
DEFAULT_K = 0
DEFAULT_OUT_OFFSET = 16

_META_FIELD_ORDER = [
    "entry_pc",
    "tid_init",
    "work_size",
    "base_a",
    "base_b",
    "base_c",
    "base_d",
    "m",
    "n",
    "k",
]

_META_64_FIELDS = {"base_a", "base_b", "base_c", "base_d"}


@dataclass
class ParamEntry:
    addr: int
    hi32: int
    lo32: int


@dataclass
class GpuBuildResult:
    mode: str
    out_dir: Path
    source_path: str
    processed_path: Path
    imem_path: Path
    report_path: Path
    instruction_words: int
    labels: dict[str, int] = field(default_factory=dict)
    params_path: Path | None = None
    param_words: int = 0
    meta_path: Path | None = None
    meta: dict[str, int] = field(default_factory=dict)


@dataclass
class GpuTemplateResult:
    mode: str
    out_dir: Path
    program_path: Path
    params_path: Path
    meta_path: Path
    report_path: Path
    in_dim: int
    out_dim: int
    work_size: int
    relu: bool


def ensure_out_dir(out_dir: str | None, prefix: str) -> Path:
    if out_dir:
        path = Path(out_dir)
        path.mkdir(parents=True, exist_ok=True)
        return path
    return Path(tempfile.mkdtemp(prefix=prefix))


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _parse_numeric(value: str | int) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 0)
    raise ValueError(f"expected integer-compatible value, got {value!r}")


def _parse_u32(value: str | int, label: str) -> int:
    parsed = _parse_numeric(value)
    if not 0 <= parsed <= 0xFFFF_FFFF:
        raise ValueError(f"{label} out of 32-bit range: {parsed}")
    return parsed


def _parse_u64(value: str | int, label: str) -> int:
    parsed = _parse_numeric(value)
    if not 0 <= parsed <= 0xFFFF_FFFF_FFFF_FFFF:
        raise ValueError(f"{label} out of 64-bit range: {parsed}")
    return parsed


def _format_hex_words(words: list[int]) -> str:
    return "".join(f"{word:08X}\n" for word in words)


def _parse_param_entries(path: Path) -> list[ParamEntry]:
    entries: list[ParamEntry] = []
    with path.open("r", encoding="utf-8") as fh:
        for line_number, raw_line in enumerate(fh, start=1):
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            tokens = line.split()
            if len(tokens) == 2:
                addr = _parse_u32(tokens[0], f"{path}:{line_number} addr")
                value64 = _parse_u64(tokens[1], f"{path}:{line_number} value64")
                entries.append(
                    ParamEntry(addr=addr, hi32=(value64 >> 32) & 0xFFFF_FFFF, lo32=value64 & 0xFFFF_FFFF)
                )
            elif len(tokens) == 3:
                addr = _parse_u32(tokens[0], f"{path}:{line_number} addr")
                hi32 = _parse_u32(tokens[1], f"{path}:{line_number} hi32")
                lo32 = _parse_u32(tokens[2], f"{path}:{line_number} lo32")
                entries.append(ParamEntry(addr=addr, hi32=hi32, lo32=lo32))
            else:
                raise ValueError(f"{path}:{line_number} invalid params.txt line")

    for entry in entries:
        if not 0 <= entry.addr <= 0x3FFF:
            raise ValueError(f"GPU parameter address out of range: 0x{entry.addr:08x}")
    return entries


def _format_param_entries(entries: list[ParamEntry]) -> str:
    return "".join(
        f"0x{entry.addr:08x} 0x{entry.hi32:08x} 0x{entry.lo32:08x}\n"
        for entry in entries
    )


def _parse_meta(path: Path | None) -> dict[str, int]:
    if path is None or not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"{path} must contain a JSON object")

    meta: dict[str, int] = {}
    for key, value in raw.items():
        if key not in _META_FIELD_ORDER:
            raise ValueError(f"{path} contains unsupported meta field '{key}'")
        if key in _META_64_FIELDS:
            meta[key] = _parse_u64(value, f"{path}:{key}")
        elif key == "entry_pc":
            parsed = _parse_u32(value, f"{path}:{key}")
            if not 0 <= parsed <= 0xFFFF:
                raise ValueError(f"{path}:{key} out of GPU PC range: {parsed}")
            meta[key] = parsed
        else:
            meta[key] = _parse_u32(value, f"{path}:{key}")
    return meta


def _format_meta(meta: dict[str, int]) -> str:
    ordered = {key: meta[key] for key in _META_FIELD_ORDER if key in meta}
    return json.dumps(ordered, indent=2, sort_keys=False) + "\n"


def _format_report(result: GpuBuildResult) -> str:
    lines = [
        f"mode={result.mode}",
        f"source={result.source_path}",
        f"processed={result.processed_path.name}",
        f"imem={result.imem_path.name}",
        f"instruction_words={result.instruction_words}",
        f"param_words={result.param_words}",
        f"meta_present={1 if result.meta else 0}",
    ]
    for label, pc in sorted(result.labels.items()):
        lines.append(f"label.{label}=0x{pc:04x}")
    for key in _META_FIELD_ORDER:
        if key in result.meta:
            width = 16 if key in _META_64_FIELDS else 8
            lines.append(f"meta.{key}=0x{result.meta[key]:0{width}x}")
    return "\n".join(lines) + "\n"


def _signed16_word(value: int) -> int:
    if not -0x8000 <= value <= 0x7FFF:
        raise ValueError(f"template value out of signed 16-bit range: {value}")
    return value & 0xFFFF


def _pattern_value(index: int, stride: int, bias: int) -> int:
    return ((index * stride + bias) % 5) - 2


def _build_program_from_text(source_text: str, source_path: str, out_dir: Path, report_name: str, mode: str) -> GpuBuildResult:
    assembler = Assembler(source_text)
    instructions = assembler.parse()
    compiled_words = assembler.compile_all()
    processed_source = render_source(instructions)

    if len(compiled_words) > GPU_IMEM_MAX_WORDS:
        raise ValueError(f"GPU program exceeds the {GPU_IMEM_MAX_WORDS}-word IMEM limit: {len(compiled_words)}")

    processed_path = out_dir / PROCESSED_PROGRAM_NAME
    imem_path = out_dir / IMEM_OUTPUT_NAME
    report_path = out_dir / report_name

    _write_text(processed_path, processed_source)
    _write_text(imem_path, _format_hex_words(compiled_words))

    result = GpuBuildResult(
        mode=mode,
        out_dir=out_dir,
        source_path=source_path,
        processed_path=processed_path,
        imem_path=imem_path,
        report_path=report_path,
        instruction_words=len(compiled_words),
        labels=assembler.labels.copy(),
    )
    _write_text(report_path, _format_report(result))
    return result


def build_program(source_path: str, out_dir: str) -> GpuBuildResult:
    out = Path(out_dir)
    source = Path(source_path)
    return _build_program_from_text(_read_text(source), str(source), out, PROGRAM_REPORT_NAME, "program")


def package_bundle(bundle_dir: str, out_dir: str) -> GpuBuildResult:
    out = Path(out_dir)
    bundle = Path(bundle_dir)
    program_path = bundle / PROGRAM_SOURCE_NAME
    if not program_path.exists():
        raise ValueError(f"bundle directory must contain {program_path}")

    params_source_path = bundle / PARAM_SOURCE_NAME
    meta_source_path = bundle / META_SOURCE_NAME

    result = _build_program_from_text(_read_text(program_path), str(program_path), out, BUNDLE_REPORT_NAME, "bundle")

    if params_source_path.exists():
        entries = _parse_param_entries(params_source_path)
        compiled_params_path = out / PARAM_OUTPUT_NAME
        _write_text(compiled_params_path, _format_param_entries(entries))
        result.params_path = compiled_params_path
        result.param_words = len(entries)
    else:
        compiled_params_path = out / PARAM_OUTPUT_NAME
        _write_text(compiled_params_path, "")
        result.params_path = compiled_params_path
        result.param_words = 0

    if meta_source_path.exists():
        meta = _parse_meta(meta_source_path)
        canonical_meta_path = out / META_SOURCE_NAME
        _write_text(canonical_meta_path, _format_meta(meta))
        result.meta_path = canonical_meta_path
        result.meta = meta

    _write_text(result.report_path, _format_report(result))
    return result


def inspect_target(target: str) -> GpuBuildResult:
    temp_dir = tempfile.mkdtemp(prefix="gpuctl_inspect_")
    path = Path(target)
    return package_bundle(str(path), temp_dir) if path.is_dir() else build_program(str(path), temp_dir)


def load_program(image_path: str, annctl_path: str | None = None, base_addr: str | None = None) -> None:
    image = Path(image_path)
    annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parent.parent / "annctl"
    cmd = ["perl", str(annctl), "gpu", "imem-load", str(image)]
    if base_addr is not None:
        cmd.append(str(base_addr))
    subprocess.run(cmd, check=True)


def load_params(params_path: str, annctl_path: str | None = None) -> None:
    params = Path(params_path)
    annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parent.parent / "annctl"
    cmd = ["perl", str(annctl), "gpu", "param-load", str(params)]
    subprocess.run(cmd, check=True)


def _resolve_compiled_bundle(target: Path, out_dir: str | None) -> GpuBuildResult:
    compiled_imem = target / IMEM_OUTPUT_NAME
    compiled_params = target / PARAM_OUTPUT_NAME
    if compiled_imem.exists():
        report_path = target / BUNDLE_REPORT_NAME
        meta_path = target / META_SOURCE_NAME
        meta = _parse_meta(meta_path) if meta_path.exists() else {}
        instruction_words = len([line for line in compiled_imem.read_text(encoding="utf-8").splitlines() if line.strip()])
        param_words = 0
        if compiled_params.exists():
            param_words = len([line for line in compiled_params.read_text(encoding="utf-8").splitlines() if line.strip()])
        return GpuBuildResult(
            mode="bundle",
            out_dir=target,
            source_path=str(target / PROGRAM_SOURCE_NAME) if (target / PROGRAM_SOURCE_NAME).exists() else str(compiled_imem),
            processed_path=target / PROCESSED_PROGRAM_NAME,
            imem_path=compiled_imem,
            params_path=compiled_params if compiled_params.exists() else None,
            report_path=report_path,
            instruction_words=instruction_words,
            param_words=param_words,
            meta_path=meta_path if meta_path.exists() else None,
            meta=meta,
        )
    return package_bundle(str(target), str(ensure_out_dir(out_dir, "gpuctl_bundle_")))


def load_bundle(target: str, annctl_path: str | None = None, out_dir: str | None = None) -> GpuBuildResult:
    resolved = _resolve_compiled_bundle(Path(target), out_dir)
    load_program(str(resolved.imem_path), annctl_path=annctl_path)
    if resolved.params_path and resolved.params_path.read_text(encoding="utf-8").strip():
        load_params(str(resolved.params_path), annctl_path=annctl_path)
    return resolved


def template_mlp(out_dir: str, in_dim: int, out_dim: int, *, work_size: int = DEFAULT_WORK_SIZE, relu: bool = True) -> GpuTemplateResult:
    if in_dim <= 0:
        raise ValueError("in_dim must be greater than zero")
    if out_dim <= 0:
        raise ValueError("out_dim must be greater than zero")
    if work_size <= 0:
        raise ValueError("work_size must be greater than zero")

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    program_lines = [
        "# Auto-generated one-layer MLP program for the current GPU ISA.",
        "# Inputs are read from base A, weights from base B, biases from base C,",
        "# and outputs are written back into base A at the configured output offset.",
    ]

    for out_idx in range(out_dim):
        program_lines.append(f"out_{out_idx}:")
        program_lines.append("  loadi r6, 0")
        for in_idx in range(in_dim):
            input_off = in_idx * work_size
            weight_off = (out_idx * in_dim + in_idx) * work_size
            program_lines.append(f"  load r0, A, {input_off}")
            program_lines.append(f"  load r1, B, {weight_off}")
            program_lines.append("  tensor_mac r6, r0, r1")
        bias_off = out_idx * work_size
        output_off = DEFAULT_OUT_OFFSET + out_idx * work_size
        program_lines.append(f"  load r2, C, {bias_off}")
        program_lines.append("  add r6, r6, r2")
        if relu:
            program_lines.append("  relu r6, r6")
        program_lines.append(f"  store A, r6, {output_off}")
        program_lines.append("")
    program_lines.append("  halt")
    program_text = "\n".join(line for line in program_lines).rstrip() + "\n"

    param_entries: list[ParamEntry] = []
    for index in range(in_dim * out_dim):
        value = _signed16_word(_pattern_value(index, 3, 2))
        for lane in range(work_size):
            param_entries.append(
                ParamEntry(addr=DEFAULT_BASE_B + index * work_size + lane, hi32=0, lo32=value)
            )

    for index in range(out_dim):
        value = _signed16_word(_pattern_value(index, 1, 0))
        for lane in range(work_size):
            param_entries.append(
                ParamEntry(addr=DEFAULT_BASE_C + index * work_size + lane, hi32=0, lo32=value)
            )

    meta = {
        "entry_pc": DEFAULT_ENTRY_PC,
        "tid_init": DEFAULT_TID_INIT,
        "work_size": work_size,
        "base_a": DEFAULT_BASE_A,
        "base_b": DEFAULT_BASE_B,
        "base_c": DEFAULT_BASE_C,
        "base_d": DEFAULT_BASE_D,
        "m": DEFAULT_M,
        "n": DEFAULT_N,
        "k": DEFAULT_K,
    }

    program_path = out / PROGRAM_SOURCE_NAME
    params_path = out / PARAM_SOURCE_NAME
    meta_path = out / META_SOURCE_NAME
    report_path = out / TEMPLATE_REPORT_NAME

    _write_text(program_path, program_text)
    _write_text(params_path, _format_param_entries(param_entries))
    _write_text(meta_path, _format_meta(meta))
    _write_text(
        report_path,
        "\n".join(
            [
                "mode=template",
                f"in_dim={in_dim}",
                f"out_dim={out_dim}",
                f"work_size={work_size}",
                f"relu={1 if relu else 0}",
                f"param_words={len(param_entries)}",
                f"output_offset={DEFAULT_OUT_OFFSET}",
            ]
        )
        + "\n",
    )

    return GpuTemplateResult(
        mode="template",
        out_dir=out,
        program_path=program_path,
        params_path=params_path,
        meta_path=meta_path,
        report_path=report_path,
        in_dim=in_dim,
        out_dim=out_dim,
        work_size=work_size,
        relu=relu,
    )
