#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass, field
import re
from typing import Iterable, List


def encode_immediate(immediate: int) -> int:
    if immediate < -2048 or immediate > 2047:
        raise ValueError(
            f"immediate {immediate} is not encodable in the hardware 12-bit signed immediate field"
        )
    return immediate & 0xFFF


_LABEL_RE = re.compile(r"^(?:\.[A-Za-z_]|[A-Za-z_])[A-Za-z0-9_\.]*$")
_TOKEN_RE = re.compile(r"[^\s,]+")

_ALIAS_MAP = {
    "pc": "r15",
    "lr": "r14",
    "sp": "r13",
    "ip": "r12",
    "fp": "r11",
    "sl": "r10",
    "sb": "r9",
    "v8": "r11",
    "v7": "r10",
    "v6": "r9",
    "v5": "r8",
    "v4": "r7",
    "v3": "r6",
    "v2": "r5",
    "v1": "r4",
    "a4": "r3",
    "a3": "r2",
    "a2": "r1",
    "a1": "r0",
}


def _strip_comments(line: str) -> str:
    text = line.rstrip("\n")
    stripped = text.lstrip()
    if not stripped:
        return ""
    if stripped.startswith("#") or stripped.startswith("@") or stripped.startswith(";"):
        return ""
    for marker in (";", "@"):
        if marker in text:
            text = text.split(marker, 1)[0]
    return text.strip()


def _replace_aliases(text: str) -> str:
    result = text
    for alias, real_reg in _ALIAS_MAP.items():
        result = re.sub(rf"\b{re.escape(alias)}\b", real_reg, result)
    return result


def _reg_num(register: str) -> int:
    match = re.fullmatch(r"r(\d+)", register.lower())
    if not match:
        raise ValueError(f"invalid register format: {register}")
    return int(match.group(1))


def _is_immediate(token: str) -> bool:
    return token.startswith("#")


def _parse_memory_operand(tokens: List[str]) -> tuple[str, int]:
    mem_str = " ".join(tokens)
    mem_str = mem_str.replace("[", "").replace("]", "")
    parts = re.split(r"[\s,]+", mem_str.strip())
    if not parts or not parts[0]:
        raise ValueError(f"invalid memory operand: {' '.join(tokens)}")
    base_reg = parts[0]
    offset = 0
    if len(parts) > 1 and parts[1]:
        raw = parts[1]
        offset = int(raw[1:], 0) if raw.startswith("#") else int(raw, 0)
    return base_reg, offset


@dataclass
class Instruction:
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

    def is_branch(self) -> bool:
        return self.mnemonic.lower() in ("b", "bge", "ble")

    def read_registers(self) -> set[str]:
        mnem = self.mnemonic.lower()
        if mnem in ("add", "sub", "and"):
            reads = {self.operands[1].lower()}
            if not _is_immediate(self.operands[2]):
                reads.add(self.operands[2].lower())
            return reads
        if mnem == "cmp":
            reads = {self.operands[0].lower()}
            if not _is_immediate(self.operands[1]):
                reads.add(self.operands[1].lower())
            return reads
        if mnem in ("mov", "lsl"):
            if len(self.operands) == 2:
                return set() if _is_immediate(self.operands[1]) else {self.operands[1].lower()}
            return {self.operands[1].lower()}
        if mnem == "ldr":
            base_reg, _ = _parse_memory_operand(self.operands[1:])
            return {base_reg.lower()}
        if mnem == "str":
            base_reg, _ = _parse_memory_operand(self.operands[1:])
            return {self.operands[0].lower(), base_reg.lower()}
        if mnem in ("b", "bge", "ble"):
            return set()
        raise ValueError(f"unsupported mnemonic in hazard analysis: {self.mnemonic}")

    def write_registers(self) -> set[str]:
        mnem = self.mnemonic.lower()
        if mnem in ("add", "sub", "and", "mov", "lsl", "ldr"):
            return {self.operands[0].lower()}
        if mnem in ("cmp", "str", "b", "bge", "ble"):
            return set()
        raise ValueError(f"unsupported mnemonic in hazard analysis: {self.mnemonic}")


class Assembler:
    def __init__(self, source: str):
        self.source = source
        self.instructions: List[Instruction] = []
        self.labels: dict[str, int] = {}

    def parse(self) -> List[Instruction]:
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

            mnemonic = tokens[0]
            operands = [_replace_aliases(token) for token in tokens[1:]]
            inst = Instruction(labels=pending_labels, mnemonic=mnemonic, operands=operands)
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
                self.labels[label] = index

    def compile_all(self) -> List[int]:
        if not self.instructions:
            self.parse()
        self._assign_pc()
        binaries: List[int] = []
        for inst in self.instructions:
            binaries.append(self._compile_instruction(inst))
        return binaries

    def _compile_instruction(self, inst: Instruction) -> int:
        mnem = inst.mnemonic.lower()
        if mnem in ("add", "sub", "mov", "lsl", "and"):
            return self._compile_dp(inst)
        if mnem == "cmp":
            return self._compile_cmp(inst)
        if mnem in ("b", "bge", "ble"):
            return self._compile_branch(inst)
        if mnem in ("ldr", "str"):
            return self._compile_ldr_str(inst)
        raise ValueError(f"unsupported instruction at PC {inst.pc}: {inst.mnemonic}")

    def _compile_dp(self, inst: Instruction) -> int:
        mnem = inst.mnemonic.lower()
        cond = 0xE
        s_bit = 0
        if mnem in ("add", "sub", "and"):
            if len(inst.operands) != 3:
                raise ValueError(f"invalid operand count for {mnem} at PC {inst.pc}")
            rd = _reg_num(inst.operands[0])
            rn = _reg_num(inst.operands[1])
            op2 = inst.operands[2]
            if _is_immediate(op2):
                i_bit = 1
                operand2 = encode_immediate(int(op2[1:], 0))
            else:
                i_bit = 0
                operand2 = _reg_num(op2)

            opcode = {"and": 0x0, "sub": 0x2, "add": 0x4}[mnem]
            return (
                (cond << 28)
                | (i_bit << 25)
                | (opcode << 21)
                | (s_bit << 20)
                | (rn << 16)
                | (rd << 12)
                | operand2
            )

        opcode = 0xD
        rn = 0
        rd = _reg_num(inst.operands[0])
        if len(inst.operands) == 2:
            src = inst.operands[1]
            if _is_immediate(src):
                i_bit = 1
                operand2 = encode_immediate(int(src[1:], 0))
            else:
                i_bit = 0
                operand2 = _reg_num(src)
        elif len(inst.operands) == 3:
            rm = _reg_num(inst.operands[1])
            shift_token = inst.operands[2]
            if not _is_immediate(shift_token):
                raise ValueError(f"expected immediate shift amount at PC {inst.pc}")
            shift_amount = int(shift_token[1:], 0)
            if shift_amount < 0 or shift_amount > 7:
                raise ValueError(f"shift amount {shift_amount} exceeds the hardware 3-bit shift field")
            i_bit = 0
            operand2 = (shift_amount << 7) | rm
        elif len(inst.operands) == 4:
            rm = _reg_num(inst.operands[1])
            if inst.operands[2].lower() != "lsl":
                raise ValueError(f"only lsl shift is supported at PC {inst.pc}")
            shift_token = inst.operands[3]
            if not _is_immediate(shift_token):
                raise ValueError(f"expected immediate shift amount at PC {inst.pc}")
            shift_amount = int(shift_token[1:], 0)
            if shift_amount < 0 or shift_amount > 7:
                raise ValueError(f"shift amount {shift_amount} exceeds the hardware 3-bit shift field")
            i_bit = 0
            operand2 = (shift_amount << 7) | rm
        else:
            raise ValueError(f"invalid operand count for {mnem} at PC {inst.pc}")

        return (
            (cond << 28)
            | (i_bit << 25)
            | (opcode << 21)
            | (s_bit << 20)
            | (rn << 16)
            | (rd << 12)
            | operand2
        )

    def _compile_cmp(self, inst: Instruction) -> int:
        if len(inst.operands) != 2:
            raise ValueError(f"invalid operand count for cmp at PC {inst.pc}")
        rn = _reg_num(inst.operands[0])
        op2 = inst.operands[1]
        if _is_immediate(op2):
            i_bit = 1
            operand2 = encode_immediate(int(op2[1:], 0))
        else:
            i_bit = 0
            operand2 = _reg_num(op2)
        cond = 0xE
        opcode = 0xA
        s_bit = 1
        rd = 0
        return (
            (cond << 28)
            | (i_bit << 25)
            | (opcode << 21)
            | (s_bit << 20)
            | (rn << 16)
            | (rd << 12)
            | operand2
        )

    def _compile_branch(self, inst: Instruction) -> int:
        if len(inst.operands) != 1:
            raise ValueError(f"invalid operand count for branch at PC {inst.pc}")
        label = inst.operands[0]
        if label not in self.labels:
            raise ValueError(f"label {label} not found for branch at PC {inst.pc}")
        target_pc = self.labels[label]
        offset = target_pc - (inst.pc + 2)
        cond = {"b": 0xE, "bge": 0xA, "ble": 0xD}[inst.mnemonic.lower()]
        return (cond << 28) | (0x5 << 25) | (offset & 0x00FFFFFF)

    def _compile_ldr_str(self, inst: Instruction) -> int:
        if len(inst.operands) < 2:
            raise ValueError(f"invalid operand count for {inst.mnemonic} at PC {inst.pc}")

        rd = _reg_num(inst.operands[0])
        mem_token = inst.operands[1]
        if not mem_token.startswith("["):
            if inst.mnemonic.lower() != "ldr" or not mem_token.startswith(".L"):
                raise ValueError(f"invalid literal operand for {inst.mnemonic} at PC {inst.pc}")
            rn = 8
            offset = 128
        else:
            base_reg, offset = _parse_memory_operand(inst.operands[1:])
            rn = _reg_num(base_reg)

        if offset >= 0:
            u_bit = 1
            offset_field = offset
        else:
            u_bit = 0
            offset_field = -offset

        if offset_field > 0xFFF:
            raise ValueError(f"offset too large at PC {inst.pc}: {offset}")

        cond = 0xE
        p_bit = 1
        b_bit = 0
        w_bit = 0
        l_bit = 1 if inst.mnemonic.lower() == "ldr" else 0
        return (
            (cond << 28)
            | (0x1 << 26)
            | (p_bit << 24)
            | (u_bit << 23)
            | (b_bit << 22)
            | (w_bit << 21)
            | (l_bit << 20)
            | (rn << 16)
            | (rd << 12)
            | offset_field
        )


def parse_source(source: str) -> List[Instruction]:
    assembler = Assembler(source)
    return assembler.parse()


def compile_source(source: str) -> List[int]:
    assembler = Assembler(source)
    assembler.parse()
    return assembler.compile_all()


def render_source(instructions: Iterable[Instruction]) -> str:
    rendered = [inst.render() for inst in instructions]
    return "\n".join(rendered) + ("\n" if rendered else "")
