#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import List

from .assembler import Assembler, render_source
from .preprocess import preprocess_source
from .scheduler import ScheduleResult, schedule_instructions


THREAD_COUNT = 4
THREAD_SLOT_WORDS = 128
THREAD_MAX_WORDS = 127
DEFAULT_IMAGE_NAME = "image.txt"
PACKAGE_IMAGE_NAME = "cpu_image.txt"


@dataclass
class ThreadBuild:
    thread_id: int
    source_path: str
    auto_stub: bool
    processed_source: str
    scheduled_source: str
    compiled_words: List[int]
    schedule: ScheduleResult
    base_addr: int


@dataclass
class BuildResult:
    mode: str
    out_dir: Path
    image_path: Path
    threads: List[ThreadBuild]

    @property
    def total_words(self) -> int:
        return sum(len(thread.compiled_words) for thread in self.threads)


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _write_hex_words(path: Path, words: List[int]) -> None:
    _write_text(path, "".join(f"{word:08X}\n" for word in words))


def _image_lines(base_addr: int, words: List[int]) -> str:
    return "".join(
        f"0x{base_addr + offset:08x} 0x{word:08x}\n"
        for offset, word in enumerate(words)
    )


def _format_report(result: BuildResult) -> str:
    lines = [
        f"mode={result.mode}",
        f"image={result.image_path.name}",
        f"total_words={result.total_words}",
    ]
    for thread in result.threads:
        prefix = f"thread{thread.thread_id}"
        lines.extend(
            [
                f"{prefix}.source={thread.source_path}",
                f"{prefix}.auto_stub={1 if thread.auto_stub else 0}",
                f"{prefix}.base_addr=0x{thread.base_addr:08x}",
                f"{prefix}.original_words={thread.schedule.original_words}",
                f"{prefix}.inserted_nops={thread.schedule.inserted_nops}",
                f"{prefix}.final_words={len(thread.compiled_words)}",
            ]
        )
        for index, hazard in enumerate(thread.schedule.hazards):
            lines.append(
                f"{prefix}.hazard{index}=pc{hazard.producer_pc}->pc{hazard.consumer_pc}:{','.join(hazard.registers)}"
            )
    return "\n".join(lines) + "\n"


def _format_image_map(threads: List[ThreadBuild]) -> str:
    lines = []
    for thread in threads:
        lines.append(
            f"thread{thread.thread_id} "
            f"base=0x{thread.base_addr:08x} "
            f"words={len(thread.compiled_words)} "
            f"auto_stub={1 if thread.auto_stub else 0} "
            f"source={thread.source_path}"
        )
    return "\n".join(lines) + ("\n" if lines else "")


def _auto_stub_source() -> str:
    return ".halt:\n  b .halt\n"


def _build_thread(source_text: str, source_path: str, thread_id: int, auto_stub: bool) -> ThreadBuild:
    processed = preprocess_source(source_text)
    assembler = Assembler(processed)
    instructions = assembler.parse()
    schedule = schedule_instructions(instructions)
    scheduled_source = render_source(schedule.instructions)
    scheduled_assembler = Assembler(scheduled_source)
    scheduled_assembler.parse()
    compiled_words = scheduled_assembler.compile_all()

    if len(compiled_words) > THREAD_MAX_WORDS:
        raise ValueError(
            f"thread{thread_id} exceeds the {THREAD_MAX_WORDS}-word limit: {len(compiled_words)}"
        )

    return ThreadBuild(
        thread_id=thread_id,
        source_path=source_path,
        auto_stub=auto_stub,
        processed_source=processed,
        scheduled_source=scheduled_source,
        compiled_words=compiled_words,
        schedule=schedule,
        base_addr=thread_id * THREAD_SLOT_WORDS,
    )


def build_single(source_path: str, out_dir: str) -> BuildResult:
    out = Path(out_dir)
    source = Path(source_path)
    thread = _build_thread(_read_text(source), str(source), thread_id=0, auto_stub=False)

    _write_text(out / "processed.s", thread.processed_source)
    _write_text(out / "scheduled.s", thread.scheduled_source)
    _write_hex_words(out / "compiled_binary.txt", thread.compiled_words)
    image_path = out / DEFAULT_IMAGE_NAME
    _write_text(image_path, _image_lines(thread.base_addr, thread.compiled_words))

    result = BuildResult(mode="single", out_dir=out, image_path=image_path, threads=[thread])
    _write_text(out / "build_report.txt", _format_report(result))
    return result


def package_directory(package_dir: str, out_dir: str) -> BuildResult:
    out = Path(out_dir)
    pkg = Path(package_dir)
    if not (pkg / "thread0.s").exists():
        raise ValueError(f"package directory must contain {pkg / 'thread0.s'}")
    threads: List[ThreadBuild] = []

    for thread_id in range(THREAD_COUNT):
        source_path = pkg / f"thread{thread_id}.s"
        auto_stub = not source_path.exists()
        source_text = _auto_stub_source() if auto_stub else _read_text(source_path)
        display_path = "<auto-stub>" if auto_stub else str(source_path)
        thread = _build_thread(source_text, display_path, thread_id=thread_id, auto_stub=auto_stub)
        threads.append(thread)
        _write_text(out / f"thread{thread_id}.processed.s", thread.processed_source)
        _write_text(out / f"thread{thread_id}.scheduled.s", thread.scheduled_source)
        _write_hex_words(out / f"thread{thread_id}.hex", thread.compiled_words)

    image_path = out / PACKAGE_IMAGE_NAME
    _write_text(
        image_path,
        "".join(_image_lines(thread.base_addr, thread.compiled_words) for thread in threads),
    )

    result = BuildResult(mode="package", out_dir=out, image_path=image_path, threads=threads)
    _write_text(out / "image_map.txt", _format_image_map(threads))
    _write_text(out / "build_report.txt", _format_report(result))
    return result


def inspect_target(target: str) -> BuildResult:
    temp_dir = tempfile.mkdtemp(prefix="cpuctl_inspect_")
    path = Path(target)
    return package_directory(str(path), temp_dir) if path.is_dir() else build_single(str(path), temp_dir)


def load_image(image_path: str, base_addr: str | None = None, annctl_path: str | None = None) -> None:
    image = Path(image_path)
    annctl = Path(annctl_path) if annctl_path else Path(__file__).resolve().parents[2] / "bin" / "annctl"
    cmd = ["perl", str(annctl), "cpu", "load", str(image)]
    if base_addr is not None:
        cmd.append(str(base_addr))
    subprocess.run(cmd, check=True)


def ensure_out_dir(out_dir: str | None, prefix: str) -> Path:
    if out_dir:
        path = Path(out_dir)
        path.mkdir(parents=True, exist_ok=True)
        return path
    return Path(tempfile.mkdtemp(prefix=prefix))
