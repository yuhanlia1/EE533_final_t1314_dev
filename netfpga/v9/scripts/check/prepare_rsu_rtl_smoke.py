#!/usr/bin/env python3

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = ROOT_DIR / "dataset" / "export" / "rsu_ann_model_int16.json"
DEFAULT_REQUEST_ID_BASE = 0x7000
ANN_INPUT_DIM = 20
SAMPLE_WORDS_PER_ENTRY = 3 + ANN_INPUT_DIM
HARDWARE_GPU_IMEM_LIMIT = 4096
HARDWARE_DMEM_LIMIT = 16384


def _parse_args():
    parser = argparse.ArgumentParser(
        description="Build RSU bundle artifacts and convert them into RTL-friendly memh files."
    )
    parser.add_argument("--model", default=str(DEFAULT_MODEL))
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--limit", type=int, default=4)
    parser.add_argument("--request-id-base", type=lambda value: int(value, 0), default=DEFAULT_REQUEST_ID_BASE)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--skip-rtl-limit-check", action="store_true")
    return parser.parse_args()


def _ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _run_annmodelctl_build(model_path: Path, bundle_dir: Path, python_bin: str) -> None:
    subprocess.run(
        [python_bin, str(ROOT_DIR / "sw" / "annmodelctl"), "build", str(model_path), "--out-dir", str(bundle_dir)],
        check=True,
    )


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_memh(path: Path, values, width_bits: int) -> None:
    width_nibbles = width_bits // 4
    text = "\n".join(f"{int(value) & ((1 << width_bits) - 1):0{width_nibbles}x}" for value in values)
    path.write_text(text + "\n", encoding="utf-8")


def _parse_cpu_image(path: Path):
    rows = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        addr_text, data_text = line.split()
        rows.append((int(addr_text, 0), int(data_text, 0)))
    if not rows:
        raise SystemExit(f"empty CPU image: {path}")
    max_addr = max(addr for addr, _ in rows)
    dense = [0] * (max_addr + 1)
    for addr, data in rows:
        dense[addr] = data & 0xFFFFFFFF
    return dense


def _parse_gpu_imem(path: Path):
    values = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        values.append(int(line, 16) & 0xFFFFFFFF)
    if not values:
        raise SystemExit(f"empty GPU IMEM image: {path}")
    return values


def _parse_gpu_params(path: Path):
    rows = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        addr_text, hi_text, lo_text = line.split()
        addr = int(addr_text, 0)
        hi = int(hi_text, 0)
        lo = int(lo_text, 0)
        rows.append((addr, ((hi & 0xFFFFFFFF) << 32) | (lo & 0xFFFFFFFF)))
    if not rows:
        raise SystemExit(f"empty GPU params image: {path}")
    rows.sort()
    base = rows[0][0]
    max_addr = rows[-1][0]
    dense = [0] * (max_addr - base + 1)
    for addr, value in rows:
        dense[addr - base] = value & 0xFFFFFFFFFFFFFFFF
    return base, dense


def _select_samples(test_vectors, expected_rows, limit: int, request_id_base: int):
    expected_by_name = {str(row["name"]): row for row in expected_rows}
    selected = []
    for index, vector in enumerate(test_vectors):
        expected = expected_by_name.get(str(vector["name"]))
        if expected is None:
            continue
        if len(vector["input_s16"]) != ANN_INPUT_DIM:
            raise SystemExit(
                f"vector {vector['name']} has input_dim={len(vector['input_s16'])}, expected {ANN_INPUT_DIM}"
            )
        request_id = (request_id_base + len(selected)) & 0xFFFF
        selected.append(
            {
                "index": len(selected),
                "name": vector["name"],
                "request_id": request_id,
                "expected_class": int(expected["predicted_class"]) & 0xFFFF,
                "expected_score_s16": int(expected["predicted_score_s16"]),
                "expected_score_u16": int(expected["predicted_score_s16"]) & 0xFFFF,
                "wire_result_data_0_u16": int(str(expected["wire_result_data_0_u16"]), 0),
                "wire_result_data_1_u16": int(str(expected["wire_result_data_1_u16"]), 0),
                "predicted_label": expected["predicted_label"],
                "input_s16": [int(value) for value in vector["input_s16"]],
            }
        )
        if len(selected) >= limit:
            break
    if not selected:
        raise SystemExit("no RSU samples selected for RTL smoke")
    return selected


def _write_rtl_env(path: Path, values) -> None:
    lines = ["#!/usr/bin/env bash", "set -euo pipefail"]
    for key, value in values.items():
        if isinstance(value, Path):
            rendered = shlex.quote(str(value))
        else:
            rendered = shlex.quote(str(value))
        lines.append(f"export {key}={rendered}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    args = _parse_args()
    model_path = Path(args.model).resolve()
    out_dir = Path(args.out_dir).resolve()
    bundle_dir = out_dir / "bundle"

    _ensure_clean_dir(out_dir)
    _run_annmodelctl_build(model_path, bundle_dir, args.python)

    built_manifest = _load_json(bundle_dir / "model_manifest.json")
    test_vectors = _load_json(bundle_dir / "test_vectors.json")
    expected_rows = _load_json(bundle_dir / "expected_outputs.json")

    cpu_image_words = _parse_cpu_image(bundle_dir / "cpu_build" / "image.txt")
    gpu_imem_words = _parse_gpu_imem(bundle_dir / "gpu_build" / "compiled_gpu_imem.txt")
    gpu_param_base, gpu_param_words = _parse_gpu_params(bundle_dir / "gpu_build" / "compiled_gpu_params.txt")
    selected_samples = _select_samples(test_vectors, expected_rows, args.limit, args.request_id_base)

    compatibility = {
        "gpu_imem_limit": HARDWARE_GPU_IMEM_LIMIT,
        "gpu_imem_count": len(gpu_imem_words),
        "gpu_imem_fits_rtl": len(gpu_imem_words) <= HARDWARE_GPU_IMEM_LIMIT,
        "gpu_dmem_limit": HARDWARE_DMEM_LIMIT,
        "gpu_param_top_addr": gpu_param_base + len(gpu_param_words) - 1,
        "gpu_params_fit_dmem": (gpu_param_base + len(gpu_param_words)) <= HARDWARE_DMEM_LIMIT,
    }

    limit_error = None
    if not args.skip_rtl_limit_check and not compatibility["gpu_imem_fits_rtl"]:
        limit_error = (
            "bundle GPU IMEM footprint exceeds current RTL limit: "
            f"{len(gpu_imem_words)} words required, limit is {HARDWARE_GPU_IMEM_LIMIT}"
        )

    cpu_memh = out_dir / "cpu_image.memh"
    gpu_imem_memh = out_dir / "gpu_imem.memh"
    gpu_params_memh = out_dir / "gpu_params.memh"
    sample_words_memh = out_dir / "sample_words.memh"

    _write_memh(cpu_memh, cpu_image_words, 32)
    _write_memh(gpu_imem_memh, gpu_imem_words, 32)
    _write_memh(gpu_params_memh, gpu_param_words, 64)

    sample_words = []
    for sample in selected_samples:
        sample_words.append(sample["request_id"])
        sample_words.append(sample["expected_class"])
        sample_words.append(sample["expected_score_u16"])
        sample_words.extend(value & 0xFFFF for value in sample["input_s16"])
    _write_memh(sample_words_memh, sample_words, 16)

    summary = {
        "model": str(model_path),
        "bundle_dir": str(bundle_dir),
        "cpu_image_count": len(cpu_image_words),
        "gpu_imem_count": len(gpu_imem_words),
        "gpu_param_base": gpu_param_base,
        "gpu_param_count": len(gpu_param_words),
        "result_base": int(built_manifest["runtime"]["result_output_base"]),
        "output_count": int(built_manifest["runtime"]["result_output_count"]),
        "sample_words_per_entry": SAMPLE_WORDS_PER_ENTRY,
        "rtl_compatibility": compatibility,
        "selected_samples": selected_samples,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (out_dir / "selected_expected_outputs.json").write_text(
        json.dumps(
            [
                {
                    "name": sample["name"],
                    "request_id": f"0x{sample['request_id']:04x}",
                    "expected_class": f"0x{sample['expected_class']:04x}",
                    "expected_score_u16": f"0x{sample['expected_score_u16']:04x}",
                    "predicted_label": sample["predicted_label"],
                }
                for sample in selected_samples
            ],
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    _write_rtl_env(
        out_dir / "rtl_env.sh",
        {
            "RTL_RSU_ARTIFACT_DIR": out_dir,
            "CPU_IMAGE_FILE": cpu_memh,
            "CPU_IMAGE_COUNT": len(cpu_image_words),
            "GPU_IMEM_FILE": gpu_imem_memh,
            "GPU_IMEM_COUNT": len(gpu_imem_words),
            "GPU_PARAMS_FILE": gpu_params_memh,
            "GPU_PARAMS_BASE": gpu_param_base,
            "GPU_PARAMS_COUNT": len(gpu_param_words),
            "SAMPLE_WORDS_FILE": sample_words_memh,
            "SAMPLE_COUNT": len(selected_samples),
            "RESULT_BASE": int(built_manifest["runtime"]["result_output_base"]),
            "OUTPUT_COUNT": int(built_manifest["runtime"]["result_output_count"]),
        },
    )

    print(f"artifact_dir={out_dir}")
    print(f"bundle_dir={bundle_dir}")
    print(f"cpu_image_count={len(cpu_image_words)}")
    print(f"gpu_imem_count={len(gpu_imem_words)}")
    print(f"gpu_params_base=0x{gpu_param_base:08x}")
    print(f"gpu_params_count={len(gpu_param_words)}")
    print(f"result_base=0x{int(built_manifest['runtime']['result_output_base']):04x}")
    print(f"output_count={int(built_manifest['runtime']['result_output_count'])}")
    print(f"sample_count={len(selected_samples)}")

    if limit_error is not None:
        raise SystemExit(limit_error)


if __name__ == "__main__":
    main()
