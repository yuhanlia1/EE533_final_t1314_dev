#!/usr/bin/env python3

from __future__ import annotations

import re
from typing import List


_LABEL_PREFIX_RE = re.compile(
    r"^(\s*(?:(?:\.[A-Za-z_]|[A-Za-z_])[A-Za-z0-9_\.]*)\s*:\s*)(.*)$"
)


def _split_label_prefix(line: str) -> tuple[str, str]:
    match = _LABEL_PREFIX_RE.match(line)
    if not match:
        return "", line
    return match.group(1), match.group(2)


def _indent_of(text: str) -> str:
    match = re.match(r"^(\s*)", text)
    return match.group(1) if match else ""


def _apply_prefix(prefix: str, expanded: List[str]) -> List[str]:
    if not prefix or not expanded:
        return expanded
    return [prefix + expanded[0].lstrip()] + expanded[1:]


def expand_line(line: str) -> List[str]:
    prefix, body = _split_label_prefix(line.rstrip("\n"))
    if body.strip() == "":
        return [line.rstrip("\n")]

    indent = _indent_of(body)
    stripped = body.strip()

    if re.match(r"^ldmia\s+lr!,\s*\{r0,\s*r1,\s*r2,\s*r3\}\s*$", stripped, re.IGNORECASE):
        return _apply_prefix(
            prefix,
            [
                f"{indent}ldr r0, [lr]",
                f"{indent}add lr, lr, #4",
                f"{indent}ldr r1, [lr]",
                f"{indent}add lr, lr, #4",
                f"{indent}ldr r2, [lr]",
                f"{indent}add lr, lr, #4",
                f"{indent}ldr r3, [lr]",
                f"{indent}add lr, lr, #4",
            ],
        )

    if re.match(r"^stmia\s+ip!,\s*\{r0,\s*r1,\s*r2,\s*r3\}\s*$", stripped, re.IGNORECASE):
        return _apply_prefix(
            prefix,
            [
                f"{indent}str r0, [ip]",
                f"{indent}add ip, ip, #4",
                f"{indent}str r1, [ip]",
                f"{indent}add ip, ip, #4",
                f"{indent}str r2, [ip]",
                f"{indent}add ip, ip, #4",
                f"{indent}str r3, [ip]",
                f"{indent}add ip, ip, #4",
            ],
        )

    if re.match(r"^ldm\s+lr,\s*\{r0,\s*r1\}\s*$", stripped, re.IGNORECASE):
        return _apply_prefix(
            prefix,
            [
                f"{indent}ldr r0, [lr]",
                f"{indent}ldr r1, [lr, #4]",
            ],
        )

    if re.match(r"^stm\s+ip,\s*\{r0,\s*r1\}\s*$", stripped, re.IGNORECASE):
        return _apply_prefix(
            prefix,
            [
                f"{indent}str r0, [ip]",
                f"{indent}str r1, [ip, #4]",
            ],
        )

    literal_match = re.match(r"^ldr\s+([A-Za-z0-9_]+),\s+([^[]\S*)\s*$", stripped, re.IGNORECASE)
    if literal_match:
        reg = literal_match.group(1)
        return _apply_prefix(prefix, [f"{indent}mov {reg}, #128"])

    return [line.rstrip("\n")]


def preprocess_source(text: str) -> str:
    lines: List[str] = []
    for line in text.splitlines():
        lines.extend(expand_line(line))
    if not lines:
        return ""
    return "\n".join(lines) + "\n"
