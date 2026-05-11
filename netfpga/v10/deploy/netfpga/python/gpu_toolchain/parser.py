#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import List


_LABEL_RE = re.compile(r"^(?:\.[A-Za-z_]|[A-Za-z_])[A-Za-z0-9_\.]*$")
_TOKEN_RE = re.compile(r"[^\s,]+")


def _strip_comments(line: str) -> str:
    text = line.rstrip("\n")
    stripped = text.lstrip()
    if not stripped:
        return ""
    if stripped.startswith("#") or stripped.startswith("@") or stripped.startswith(";"):
        return ""
    for marker in ("#", ";", "@"):
        if marker in text:
            text = text.split(marker, 1)[0]
    return text.strip()


@dataclass
class GpuInstruction:
    labels: List[str]
    mnemonic: str
    operands: List[str]
    pc: int | None = None

    def render(self) -> str:
        lines = [f"{label}:" for label in self.labels]
        if self.operands:
            lines.append(f"  {self.mnemonic} " + ", ".join(self.operands))
        else:
            lines.append(f"  {self.mnemonic}")
        return "\n".join(lines)


def render_source(instructions: List[GpuInstruction]) -> str:
    if not instructions:
        return ""
    return "\n".join(inst.render() for inst in instructions) + "\n"


class Parser:
    def __init__(self, source: str):
        self.source = source
        self.instructions: List[GpuInstruction] = []
        self.labels: dict[str, int] = {}

    def parse(self) -> List[GpuInstruction]:
        pending_labels: List[str] = []

        for raw_line in self.source.splitlines():
            line = _strip_comments(raw_line)
            if not line:
                continue

            while ":" in line:
                possible_label, rest = line.split(":", 1)
                possible_label = possible_label.strip()
                if not _LABEL_RE.fullmatch(possible_label):
                    break
                if possible_label in self.labels or possible_label in pending_labels:
                    raise ValueError(f"duplicate label '{possible_label}'")
                pending_labels.append(possible_label)
                line = rest.strip()
                if not line:
                    break

            if not line:
                continue

            if line.startswith("."):
                continue

            tokens = _TOKEN_RE.findall(line)
            if not tokens:
                continue

            mnemonic = tokens[0].lower()
            operands = [token.strip() for token in tokens[1:]]
            inst = GpuInstruction(labels=pending_labels, mnemonic=mnemonic, operands=operands)
            self.instructions.append(inst)
            pending_labels = []

        if pending_labels:
            raise ValueError(f"dangling label(s) without following instruction: {', '.join(pending_labels)}")

        self._assign_pc()
        return self.instructions

    def _assign_pc(self) -> None:
        self.labels = {}
        for index, inst in enumerate(self.instructions):
            inst.pc = index
            for label in inst.labels:
                if label in self.labels:
                    raise ValueError(f"duplicate label '{label}'")
                self.labels[label] = index

