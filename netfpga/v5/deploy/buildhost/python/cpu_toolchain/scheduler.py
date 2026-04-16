#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List

from .assembler import Instruction


NOP_MNEMONIC = "mov"
NOP_OPERANDS = ["r5", "r5"]


@dataclass
class HazardEvent:
    producer_pc: int
    consumer_pc: int
    registers: List[str]


@dataclass
class ScheduleResult:
    instructions: List[Instruction]
    inserted_nops: int
    hazards: List[HazardEvent]
    original_words: int


def make_nop() -> Instruction:
    return Instruction(labels=[], mnemonic=NOP_MNEMONIC, operands=NOP_OPERANDS[:])


def _required_nops(prev_inst: Instruction, next_inst: Instruction) -> tuple[int, List[str]]:
    overlap = sorted(prev_inst.write_registers() & next_inst.read_registers())
    if not overlap:
        return 0, []
    return 1, overlap


def schedule_instructions(instructions: Iterable[Instruction]) -> ScheduleResult:
    original = list(instructions)
    if not original:
        return ScheduleResult(instructions=[], inserted_nops=0, hazards=[], original_words=0)

    scheduled: List[Instruction] = []
    hazards: List[HazardEvent] = []
    inserted_nops = 0

    for index, inst in enumerate(original):
        scheduled.append(inst)
        if index + 1 >= len(original):
            continue
        next_inst = original[index + 1]
        nop_count, overlap = _required_nops(inst, next_inst)
        if nop_count == 0:
            continue
        hazards.append(
            HazardEvent(
                producer_pc=inst.pc if inst.pc is not None else index,
                consumer_pc=next_inst.pc if next_inst.pc is not None else index + 1,
                registers=overlap,
            )
        )
        for _ in range(nop_count):
            scheduled.append(make_nop())
            inserted_nops += 1

    return ScheduleResult(
        instructions=scheduled,
        inserted_nops=inserted_nops,
        hazards=hazards,
        original_words=len(original),
    )
