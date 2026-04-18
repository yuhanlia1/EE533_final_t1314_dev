#!/usr/bin/env python3

from __future__ import annotations

from .parser import GpuInstruction, Parser, render_source


_BSEL_MAP = {
    "a": 0,
    "b": 1,
    "c": 2,
    "d": 3,
}

_OPCODES = {
    "loadi": 0x1,
    "load": 0x2,
    "store": 0x3,
    "add": 0x4,
    "sub": 0x5,
    "mul": 0x6,
    "relu": 0x7,
    "set_tid": 0x8,
    "inc_tid": 0x9,
    "blt": 0xA,
    "tensor_mul": 0xB,
    "tensor_mac": 0xC,
    "mov": 0xD,
    "jump": 0xE,
    "halt": 0xF,
}


def _parse_reg(token: str) -> int:
    text = token.lower()
    if not text.startswith("r"):
        raise ValueError(f"invalid GPU register '{token}'")
    try:
        value = int(text[1:], 10)
    except ValueError as exc:
        raise ValueError(f"invalid GPU register '{token}'") from exc
    if not 0 <= value <= 7:
        raise ValueError(f"GPU register out of range '{token}'")
    return value


def _parse_bsel(token: str) -> int:
    key = token.lower()
    if key not in _BSEL_MAP:
        raise ValueError(f"invalid GPU base selector '{token}', expected A/B/C/D")
    return _BSEL_MAP[key]


def _parse_dtype(token: str) -> int:
    key = token.lower()
    if key == "i16":
        return 0
    if key == "bf16":
        return 1
    raise ValueError(f"invalid GPU dtype '{token}', expected i16 or bf16")


def _parse_int(token: str) -> int:
    text = token[1:] if token.startswith("#") else token
    return int(text, 0)


def _encode_imm16(value: int, context: str) -> int:
    if not -0x8000 <= value <= 0xFFFF:
        raise ValueError(f"{context} immediate out of 16-bit range: {value}")
    return value & 0xFFFF


def _encode_branch_target(value: int, context: str) -> int:
    if not 0 <= value <= 0xFFFF:
        raise ValueError(f"{context} target out of 16-bit GPU PC range: {value}")
    return value & 0xFFFF


def _encode_word(
    opcode: int,
    rd: int = 0,
    rs1: int = 0,
    rs2: int = 0,
    bsel: int = 0,
    dtype: int = 0,
    imm: int = 0,
) -> int:
    return (
        ((opcode & 0xF) << 28)
        | ((rd & 0x7) << 25)
        | ((rs1 & 0x7) << 22)
        | ((rs2 & 0x7) << 19)
        | ((bsel & 0x3) << 17)
        | ((dtype & 0x1) << 16)
        | (imm & 0xFFFF)
    )


class Assembler:
    def __init__(self, source: str):
        self.source = source
        self.instructions: list[GpuInstruction] = []
        self.labels: dict[str, int] = {}

    def parse(self) -> list[GpuInstruction]:
        parser = Parser(self.source)
        self.instructions = parser.parse()
        self.labels = parser.labels
        return self.instructions

    def compile_all(self) -> list[int]:
        if not self.instructions:
            self.parse()
        return [self._compile_instruction(inst) for inst in self.instructions]

    def _resolve_imm(self, token: str, *, allow_label: bool = False, branch_target: bool = False) -> int:
        if allow_label and token in self.labels:
            value = self.labels[token]
            return _encode_branch_target(value, "branch") if branch_target else _encode_imm16(value, "label")
        value = _parse_int(token)
        return _encode_branch_target(value, "branch") if branch_target else _encode_imm16(value, "GPU")

    def _compile_instruction(self, inst: GpuInstruction) -> int:
        mnem = inst.mnemonic.lower()
        if mnem not in _OPCODES:
            raise ValueError(f"unsupported GPU instruction at PC {inst.pc}: {inst.mnemonic}")

        opcode = _OPCODES[mnem]

        if mnem == "loadi":
            if len(inst.operands) != 2:
                raise ValueError(f"loadi expects 2 operands at PC {inst.pc}")
            return _encode_word(
                opcode,
                rd=_parse_reg(inst.operands[0]),
                imm=self._resolve_imm(inst.operands[1]),
            )

        if mnem == "load":
            if len(inst.operands) not in (3, 4):
                raise ValueError(f"load expects 3 or 4 operands at PC {inst.pc}")
            dtype = _parse_dtype(inst.operands[3]) if len(inst.operands) == 4 else 0
            return _encode_word(
                opcode,
                rd=_parse_reg(inst.operands[0]),
                bsel=_parse_bsel(inst.operands[1]),
                dtype=dtype,
                imm=self._resolve_imm(inst.operands[2]),
            )

        if mnem == "store":
            if len(inst.operands) not in (3, 4):
                raise ValueError(f"store expects 3 or 4 operands at PC {inst.pc}")
            dtype = _parse_dtype(inst.operands[3]) if len(inst.operands) == 4 else 0
            return _encode_word(
                opcode,
                rs2=_parse_reg(inst.operands[1]),
                bsel=_parse_bsel(inst.operands[0]),
                dtype=dtype,
                imm=self._resolve_imm(inst.operands[2]),
            )

        if mnem in ("add", "sub", "mul", "tensor_mul", "tensor_mac"):
            if len(inst.operands) not in (3, 4):
                raise ValueError(f"{mnem} expects 3 or 4 operands at PC {inst.pc}")
            dtype = _parse_dtype(inst.operands[3]) if len(inst.operands) == 4 else 0
            return _encode_word(
                opcode,
                rd=_parse_reg(inst.operands[0]),
                rs1=_parse_reg(inst.operands[1]),
                rs2=_parse_reg(inst.operands[2]),
                dtype=dtype,
            )

        if mnem in ("mov", "relu"):
            if len(inst.operands) != 2:
                raise ValueError(f"{mnem} expects 2 operands at PC {inst.pc}")
            return _encode_word(
                opcode,
                rd=_parse_reg(inst.operands[0]),
                rs1=_parse_reg(inst.operands[1]),
            )

        if mnem == "set_tid":
            if len(inst.operands) != 1:
                raise ValueError(f"set_tid expects 1 operand at PC {inst.pc}")
            return _encode_word(opcode, imm=self._resolve_imm(inst.operands[0]))

        if mnem in ("blt", "jump"):
            if len(inst.operands) != 1:
                raise ValueError(f"{mnem} expects 1 operand at PC {inst.pc}")
            return _encode_word(
                opcode,
                imm=self._resolve_imm(inst.operands[0], allow_label=True, branch_target=True),
            )

        if mnem in ("inc_tid", "halt"):
            if inst.operands:
                raise ValueError(f"{mnem} takes no operands at PC {inst.pc}")
            return _encode_word(opcode)

        raise ValueError(f"unsupported GPU instruction at PC {inst.pc}: {inst.mnemonic}")
