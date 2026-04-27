#!/usr/bin/env python3
"""Generate an ASIC evaluation parameter pack for the RSU user module layer."""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
from collections import OrderedDict, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional


REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_ROOT = REPO_ROOT / "src"
PD_ROOT = REPO_ROOT / "pd"
FPGA_REPORT_DIR = PD_ROOT / "fpga_report"
ASIC_REPORT_ROOT = PD_ROOT / "asic_report"
DEFAULT_OUT_DIR = ASIC_REPORT_ROOT / "eval" / "user_top_eval"
DEFAULT_PLATFORM = "nangate45"

RESERVED_WORDS = {
    "if",
    "else",
    "for",
    "while",
    "case",
    "casex",
    "casez",
    "always",
    "assign",
    "wire",
    "reg",
    "logic",
    "input",
    "output",
    "inout",
    "function",
    "task",
    "begin",
    "end",
    "generate",
    "endgenerate",
    "module",
    "endcase",
    "endmodule",
    "default",
}

GROUP_NAMES = {
    "control_plane": "Control Plane",
    "protocol_flow": "Protocol / Flow",
    "ann_wrapper": "ANN Wrapper",
    "compute_core": "Compute Core",
    "other": "Other",
}

MEMORY_DESCRIPTORS = {
    "fifo_bram": {
        "kind": "fifo",
        "depth_expr": "1 << ADDR_WIDTH",
        "width_key": "DATA_WIDTH",
        "ports": "dual_port_rw",
    },
    "gpu_shared_dmem": {
        "kind": "shared_dmem",
        "depth_key": "DEPTH",
        "width_key": "DATA_WIDTH",
        "ports": "dual_port_rw",
    },
    "gpu_imem": {
        "kind": "instruction_memory",
        "depth_key": "DEPTH",
        "width_key": "DW",
        "ports": "single_port_rw",
    },
    "mem_inst": {
        "kind": "instruction_memory",
        "depth_expr": "1 << ADDR_WIDTH",
        "width_key": "DATA_WIDTH",
        "ports": "single_port_rw",
    },
    "mem_data": {
        "kind": "data_memory",
        "depth_expr": "1 << ADDR_WIDTH",
        "width_key": "DATA_WIDTH",
        "ports": "single_port_rw",
    },
    "mem_RF": {
        "kind": "register_file",
        "depth_expr": "1 << ADDR_WIDTH",
        "width_key": "DATA_WIDTH",
        "ports": "1w_2r",
    },
    "bram_wrapper": {
        "kind": "scratchpad",
        "depth_expr": "1 << ADDR_WIDTH",
        "width_key": "DATA_WIDTH",
        "ports": "single_port_rw",
    },
}

MEMORY_BLACKBOX_MODULES = tuple(sorted(MEMORY_DESCRIPTORS))

PLATFORM_SUPPORT = {
    "nangate45": {
        "label": "Nangate45 teaching library",
        "platform_root": PD_ROOT / "asic_flow" / "nangate45",
        "required_env": {
            "ASIC_LIBERTY": "Path to the Nangate45 liberty file used by Yosys/OpenROAD.",
            "ASIC_TECH_LEF": "Path to the Nangate45 technology LEF.",
            "ASIC_STD_CELL_LEF": "Path to the Nangate45 standard-cell LEF.",
        },
        "optional_env": {
            "ASIC_PLATFORM_ROOT": "Optional Nangate45 platform root used to auto-derive liberty/LEF and fakeram collateral.",
            "ASIC_SITE": "OpenROAD site name. Defaults to the common Nangate45 site.",
            "ASIC_DIE_AREA": "Explicit die area rectangle. Default: 0 0 3000 2500.",
            "ASIC_CORE_AREA": "Explicit core area rectangle. Default: 50 50 2950 2450.",
            "ASIC_PLACE_DENSITY": "Target placement density. Default: 0.55.",
            "ASIC_PLATFORM_CONFIG": "Optional shell fragment sourced by run wrappers before validation.",
            "YOSYS_BIN": "Optional Yosys binary override.",
            "OPENROAD_BIN": "Optional OpenROAD binary override.",
        },
        "default_site": "FreePDK45_38x28_10R_NP_162NW_34O",
        "default_die_area": "{0 0 3000 2500}",
        "default_core_area": "{50 50 2950 2450}",
        "default_place_density": 0.55,
    }
}

FAKERAM_CELLS = {
    "fakeram45_1024x32": {"depth": 1024, "width": 32},
    "fakeram45_256x32": {"depth": 256, "width": 32},
    "fakeram45_256x16": {"depth": 256, "width": 16},
}

NANGATE45_TRACKS = {
    "metal1": {"x_offset": 0.095, "x_pitch": 0.19, "y_offset": 0.07, "y_pitch": 0.14},
    "metal2": {"x_offset": 0.095, "x_pitch": 0.19, "y_offset": 0.07, "y_pitch": 0.14},
    "metal3": {"x_offset": 0.095, "x_pitch": 0.19, "y_offset": 0.07, "y_pitch": 0.14},
    "metal4": {"x_offset": 0.095, "x_pitch": 0.28, "y_offset": 0.07, "y_pitch": 0.28},
    "metal5": {"x_offset": 0.095, "x_pitch": 0.28, "y_offset": 0.07, "y_pitch": 0.28},
    "metal6": {"x_offset": 0.095, "x_pitch": 0.28, "y_offset": 0.07, "y_pitch": 0.28},
    "metal7": {"x_offset": 0.095, "x_pitch": 0.8, "y_offset": 0.07, "y_pitch": 0.8},
}

PLACEHOLDER_MACROS = {
    "placeholder_fifo_bram_256x72_dp": {
        "size": (120.0, 140.0),
        "area": 16800.0,
        "clock_pins": ["clka", "clkb"],
        "inputs": [
            ("clka", 1),
            ("wea", 1),
            ("addra", 8),
            ("dina", 72),
            ("clkb", 1),
            ("web", 1),
            ("addrb", 8),
            ("dinb", 72),
        ],
        "outputs": [
            ("douta", 72, "clka"),
            ("doutb", 72, "clkb"),
        ],
    },
    "placeholder_gpu_shared_dmem_16384x64_dp": {
        "size": (1400.0, 520.0),
        "area": 728000.0,
        "clock_pins": ["clk"],
        "inputs": [
            ("clk", 1),
            ("a_en", 1),
            ("a_we", 1),
            ("a_addr", 14),
            ("a_wdata", 64),
            ("b_en", 1),
            ("b_we", 1),
            ("b_addr", 14),
            ("b_wdata", 64),
        ],
        "outputs": [
            ("a_rdata", 64, "clk"),
            ("a_rvalid", 1, "clk"),
            ("b_rdata", 64, "clk"),
            ("b_rvalid", 1, "clk"),
        ],
    },
    "placeholder_mem_rf_64x64_1w2r": {
        "size": (100.0, 120.0),
        "area": 12000.0,
        "clock_pins": ["clk"],
        "inputs": [
            ("clk", 1),
            ("we", 1),
            ("waddr", 6),
            ("wdata", 64),
            ("r0addr", 6),
            ("r1addr", 6),
        ],
        "outputs": [
            ("r0data", 64, "clk"),
            ("r1data", 64, "clk"),
        ],
    },
}

MAPPED_MEMORY_TARGETS = {
    ("mem_inst", 512, 32): {
        "implementation": "fakeram_wrapper",
        "wrapper_strategy": "single_macro_zero_extended_addr",
        "target_cells": [{"cell_name": "fakeram45_1024x32", "count": 1}],
        "notes": "Map 512x32 instruction memory into a single 1024x32 fakeram with zero-extended address bits.",
    },
    ("gpu_imem", 4096, 32): {
        "implementation": "fakeram_wrapper",
        "wrapper_strategy": "banked_4x1024x32",
        "target_cells": [{"cell_name": "fakeram45_1024x32", "count": 4}],
        "notes": "Split 4096x32 GPU IMEM across four 1024x32 fakerams, banked by addr[11:10].",
    },
    ("mem_data", 256, 64): {
        "implementation": "fakeram_wrapper",
        "wrapper_strategy": "width_split_2x256x32",
        "target_cells": [{"cell_name": "fakeram45_256x32", "count": 2}],
        "notes": "Map 256x64 data memory into two parallel 256x32 fakerams.",
    },
    ("mem_data", 256, 8): {
        "implementation": "fakeram_wrapper",
        "wrapper_strategy": "single_macro_padded_256x16",
        "target_cells": [{"cell_name": "fakeram45_256x16", "count": 1}],
        "notes": "Map 256x8 control memory into a 256x16 fakeram and use only the low byte.",
    },
    ("fifo_bram", 256, 72): {
        "implementation": "placeholder_macro",
        "wrapper_strategy": "direct_placeholder_wrapper",
        "target_cells": [{"cell_name": "placeholder_fifo_bram_256x72_dp", "count": 1}],
        "notes": "Keep dual-port FIFO storage as a macro placeholder in the first routed baseline.",
    },
    ("gpu_shared_dmem", 16384, 64): {
        "implementation": "placeholder_macro",
        "wrapper_strategy": "direct_placeholder_wrapper",
        "target_cells": [{"cell_name": "placeholder_gpu_shared_dmem_16384x64_dp", "count": 1}],
        "notes": "Keep the large dual-port shared DMEM as a macro placeholder in the first routed baseline.",
    },
    ("mem_RF", 64, 64): {
        "implementation": "placeholder_macro",
        "wrapper_strategy": "direct_placeholder_wrapper",
        "target_cells": [{"cell_name": "placeholder_mem_rf_64x64_1w2r", "count": 1}],
        "notes": "Keep the 1w2r register file as a macro placeholder in the first routed baseline.",
    },
}

MEMORY_BLACKBOX_STUBS = {
    "fifo_bram": """\
(* blackbox *)
module fifo_bram #(
  parameter DATA_WIDTH = 72,
  parameter ADDR_WIDTH = 8
) (
  input                        clka,
  input                        wea,
  input  [ADDR_WIDTH-1:0]      addra,
  input  [DATA_WIDTH-1:0]      dina,
  output [DATA_WIDTH-1:0]      douta,
  input                        clkb,
  input                        web,
  input  [ADDR_WIDTH-1:0]      addrb,
  input  [DATA_WIDTH-1:0]      dinb,
  output [DATA_WIDTH-1:0]      doutb
);
endmodule
""",
    "gpu_imem": """\
(* blackbox *)
module gpu_imem #(
  parameter AW = 9,
  parameter DW = 32,
  parameter DEPTH = 512
) (
  input               clk,
  input               we,
  input  [AW-1:0]     addr,
  input  [DW-1:0]     wdata,
  output [DW-1:0]     rdata
);
endmodule
""",
    "gpu_shared_dmem": """\
(* blackbox *)
module gpu_shared_dmem #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input                       clk,
  input                       a_en,
  input                       a_we,
  input  [ADDR_WIDTH-1:0]     a_addr,
  input  [DATA_WIDTH-1:0]     a_wdata,
  output [DATA_WIDTH-1:0]     a_rdata,
  output                      a_rvalid,
  input                       b_en,
  input                       b_we,
  input  [ADDR_WIDTH-1:0]     b_addr,
  input  [DATA_WIDTH-1:0]     b_wdata,
  output [DATA_WIDTH-1:0]     b_rdata,
  output                      b_rvalid
);
endmodule
""",
    "mem_RF": """\
(* blackbox *)
module mem_RF #(
  parameter ADDR_WIDTH = 6,
  parameter DATA_WIDTH = 64
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     waddr,
  input  [DATA_WIDTH-1:0]     wdata,
  input  [ADDR_WIDTH-1:0]     r0addr,
  output [DATA_WIDTH-1:0]     r0data,
  input  [ADDR_WIDTH-1:0]     r1addr,
  output [DATA_WIDTH-1:0]     r1data
);
endmodule
""",
    "mem_data": """\
(* blackbox *)
module mem_data #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     addr,
  input  [DATA_WIDTH-1:0]     wdata,
  output [DATA_WIDTH-1:0]     rdata
);
endmodule
""",
    "mem_inst": """\
(* blackbox *)
module mem_inst #(
  parameter ADDR_WIDTH = 9,
  parameter DATA_WIDTH = 32
) (
  input                       clk,
  input                       we,
  input  [ADDR_WIDTH-1:0]     addr,
  input  [DATA_WIDTH-1:0]     wdata,
  output [DATA_WIDTH-1:0]     rdata
);
endmodule
""",
}

GROUP_MODULES = {
    "control_plane": {"generic_regs"},
    "protocol_flow": {
        "convertible_fifo",
        "fifo_bram",
        "packet_action_selector",
        "action_dispatcher",
        "network_stream_slice",
    },
    "ann_wrapper": {
        "ann_engine_wrapper",
        "ann_task_ingress",
        "ann_feature_unpack",
        "ann_result_packet_builder",
    },
}


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


@dataclass
class InstanceTemplate:
    module_name: str
    instance_name: str
    overrides: Dict[str, str] = field(default_factory=dict)


@dataclass
class ModuleDef:
    name: str
    file_path: Path
    param_order: List[str]
    param_defaults: Dict[str, str]
    localparam_order: List[str]
    localparam_defaults: Dict[str, str]
    body: str
    instances: List[InstanceTemplate] = field(default_factory=list)


@dataclass
class HierarchyNode:
    path: str
    module_name: str
    file_path: Optional[str]
    params: Dict[str, Optional[int]]
    group: str
    children: List["HierarchyNode"] = field(default_factory=list)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text


def verilog_number_to_int(token: str) -> str:
    match = re.fullmatch(r"(?:(\d+))?'([sS]?)([bBoOdDhH])([0-9a-fA-F_xXzZ]+)", token)
    if not match:
        return token
    _, _, base_char, digits = match.groups()
    digits = digits.replace("_", "").replace("x", "0").replace("X", "0").replace("z", "0").replace("Z", "0")
    base = {"b": 2, "o": 8, "d": 10, "h": 16}[base_char.lower()]
    return str(int(digits, base))


def normalize_expr(expr: str) -> str:
    expr = strip_comments(expr).strip()
    expr = re.sub(
        r"(?:(?:\d+)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ]+)",
        lambda m: verilog_number_to_int(m.group(0)),
        expr,
    )
    expr = expr.replace("/", "//")
    return expr


class SafeExprEvaluator(ast.NodeVisitor):
    def __init__(self, env: Dict[str, int]) -> None:
        self.env = env

    def visit_Expression(self, node: ast.Expression) -> int:
        return self.visit(node.body)

    def visit_Constant(self, node: ast.Constant) -> int:
        if isinstance(node.value, (int, float)):
            return int(node.value)
        raise ValueError("unsupported constant")

    def visit_Name(self, node: ast.Name) -> int:
        if node.id in self.env and self.env[node.id] is not None:
            return int(self.env[node.id])
        raise ValueError(f"unknown name {node.id}")

    def visit_UnaryOp(self, node: ast.UnaryOp) -> int:
        value = self.visit(node.operand)
        if isinstance(node.op, ast.USub):
            return -value
        if isinstance(node.op, ast.UAdd):
            return value
        if isinstance(node.op, ast.Invert):
            return ~value
        raise ValueError("unsupported unary op")

    def visit_BinOp(self, node: ast.BinOp) -> int:
        left = self.visit(node.left)
        right = self.visit(node.right)
        op = node.op
        if isinstance(op, ast.Add):
            return left + right
        if isinstance(op, ast.Sub):
            return left - right
        if isinstance(op, ast.Mult):
            return left * right
        if isinstance(op, ast.FloorDiv):
            return left // right
        if isinstance(op, ast.Div):
            return left // right
        if isinstance(op, ast.Pow):
            return left ** right
        if isinstance(op, ast.LShift):
            return left << right
        if isinstance(op, ast.RShift):
            return left >> right
        if isinstance(op, ast.BitAnd):
            return left & right
        if isinstance(op, ast.BitOr):
            return left | right
        if isinstance(op, ast.BitXor):
            return left ^ right
        if isinstance(op, ast.Mod):
            return left % right
        raise ValueError("unsupported binary op")

    def generic_visit(self, node: ast.AST) -> int:
        raise ValueError(f"unsupported syntax: {type(node).__name__}")


def safe_eval(expr: str, env: Dict[str, Optional[int]]) -> Optional[int]:
    normalized = normalize_expr(expr)
    try:
        tree = ast.parse(normalized, mode="eval")
        evaluator = SafeExprEvaluator({k: int(v) for k, v in env.items() if v is not None})
        return evaluator.visit(tree)
    except Exception:
        return None


def parse_parameter_block(block: str) -> OrderedDict[str, str]:
    params: OrderedDict[str, str] = OrderedDict()
    cleaned = strip_comments(block)
    pattern = re.compile(
        r"\b(?:parameter|localparam)\b"
        r"(?:\s+(?:(?:signed|integer|real|time|genvar)\s+)?(?:\[[^\]]+\]\s+)?)?"
        r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<expr>[^,\n)]+)",
        re.M,
    )
    for match in pattern.finditer(cleaned):
        expr = match.group("expr").strip().rstrip(";").strip()
        params[match.group("name")] = expr
    return params


def parse_named_map(block: str) -> Dict[str, str]:
    items: Dict[str, str] = {}
    idx = 0
    while idx < len(block):
        dot = block.find(".", idx)
        if dot == -1:
            break
        name_match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", block[dot:])
        if not name_match:
            idx = dot + 1
            continue
        name = name_match.group(1)
        pos = dot + name_match.end()
        depth = 1
        start = pos
        while pos < len(block) and depth > 0:
            ch = block[pos]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            pos += 1
        items[name] = block[start : pos - 1].strip()
        idx = pos
    return items


def parse_instances(body: str) -> List[InstanceTemplate]:
    instances: List[InstanceTemplate] = []
    instance_re = re.compile(
        r"(?ms)^[ \t]*(?P<module>[A-Za-z_][A-Za-z0-9_]*)\s*"
        r"(?P<params>#\s*\(.*?\))?\s+"
        r"(?P<instance>[A-Za-z_][A-Za-z0-9_]*)\s*\(",
    )
    for match in instance_re.finditer(body):
        module_name = match.group("module")
        if module_name in RESERVED_WORDS:
            continue
        overrides = {}
        params_block = match.group("params")
        if params_block:
            inner = params_block[params_block.find("(") + 1 : params_block.rfind(")")]
            overrides = parse_named_map(inner)
        instances.append(
            InstanceTemplate(
                module_name=module_name,
                instance_name=match.group("instance"),
                overrides=overrides,
            )
        )
    return instances


def load_modules(source_files: Iterable[Path]) -> Dict[str, ModuleDef]:
    modules: Dict[str, ModuleDef] = {}
    module_re = re.compile(
        r"(?ms)^\s*module\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*"
        r"(?:#\s*\((?P<params>.*?)\))?\s*\(.*?^\s*endmodule\b"
    )
    header_re = re.compile(
        r"(?ms)^\s*module\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*"
        r"(?:#\s*\((?P<params>.*?)\))?\s*\(.*?\)\s*;"
    )
    for file_path in source_files:
        text = file_path.read_text(encoding="utf-8")
        for match in module_re.finditer(text):
            module_text = match.group(0)
            header_match = header_re.match(module_text)
            if not header_match:
                continue
            params = parse_parameter_block(header_match.group("params") or "")
            body = module_text[header_match.end() : module_text.rfind("endmodule")]
            localparams = parse_parameter_block(body)
            module = ModuleDef(
                name=match.group("name"),
                file_path=file_path,
                param_order=list(params.keys()),
                param_defaults=dict(params),
                localparam_order=list(localparams.keys()),
                localparam_defaults=dict(localparams),
                body=body,
            )
            module.instances = parse_instances(body)
            modules[module.name] = module
    return modules


def default_param_env(module: ModuleDef, parent_env: Optional[Dict[str, Optional[int]]] = None) -> Dict[str, Optional[int]]:
    env: Dict[str, Optional[int]] = {}
    parent_env = parent_env or {}
    for name in module.param_order:
        expr = module.param_defaults[name]
        eval_env = dict(parent_env)
        eval_env.update(env)
        env[name] = safe_eval(expr, eval_env)
    for name in module.localparam_order:
        expr = module.localparam_defaults[name]
        eval_env = dict(parent_env)
        eval_env.update(env)
        env[name] = safe_eval(expr, eval_env)
    return env


def instantiate_env(
    child: ModuleDef,
    parent_env: Dict[str, Optional[int]],
    overrides: Dict[str, str],
) -> Dict[str, Optional[int]]:
    env = default_param_env(child, parent_env)
    for name, expr in overrides.items():
        value = safe_eval(expr, parent_env)
        if value is not None:
            env[name] = value
    return env


def classify_group(path: str, module_name: str) -> str:
    if module_name in GROUP_MODULES["control_plane"]:
        return "control_plane"
    if "/ann_engine/compute_core" in path or module_name in {
        "ann_cpu_gpu_compute_core",
        "arm_64_top",
        "gpu_top_fifo_if",
        "gpu_shared_dmem",
        "gpu_imem",
        "mem_inst",
        "mem_data",
        "mem_RF",
        "fetch_stage1",
        "fetch_stage2",
        "decode_stage1",
        "ex_stage1",
        "ex_stage2",
        "mem_stage",
        "mem_register_slice",
        "wb_stage1",
        "gpu_control",
        "gpu_if_stage",
        "gpu_if_id_reg",
        "gpu_id_stage",
        "gpu_id_ex_reg",
        "gpu_ex_stage",
        "gpu_ex_mm_reg",
        "gpu_mm_stage",
        "gpu_pc",
        "bf16_add_sub",
        "bf16_mult",
    }:
        return "compute_core"
    if module_name in GROUP_MODULES["ann_wrapper"] or "/ann_engine/" in path:
        return "ann_wrapper"
    if module_name in GROUP_MODULES["protocol_flow"]:
        return "protocol_flow"
    return "other"


def build_hierarchy(
    modules: Dict[str, ModuleDef],
    module_name: str,
    path: str,
    env: Dict[str, Optional[int]],
    missing: Dict[str, int],
) -> HierarchyNode:
    module = modules[module_name]
    node = HierarchyNode(
        path=path,
        module_name=module_name,
        file_path=str(module.file_path.relative_to(REPO_ROOT)),
        params=env,
        group=classify_group(path, module_name),
    )
    for instance in module.instances:
        if instance.module_name not in modules:
            missing[instance.module_name] += 1
            continue
        child = modules[instance.module_name]
        child_env = instantiate_env(child, env, instance.overrides)
        child_path = f"{path}/{instance.instance_name}"
        node.children.append(build_hierarchy(modules, child.name, child_path, child_env, missing))
    return node


def walk_nodes(node: HierarchyNode) -> Iterable[HierarchyNode]:
    yield node
    for child in node.children:
        yield from walk_nodes(child)


def flatten_paths(node: HierarchyNode) -> List[str]:
    return [child.path for child in walk_nodes(node)]


def build_memory_summary(node: HierarchyNode) -> List[Dict[str, object]]:
    memories: List[Dict[str, object]] = []
    for current in walk_nodes(node):
        descriptor = MEMORY_DESCRIPTORS.get(current.module_name)
        if not descriptor:
            continue
        params = current.params
        depth = None
        width = None
        if "depth_key" in descriptor:
            depth = params.get(descriptor["depth_key"])
        elif "depth_expr" in descriptor:
            depth = safe_eval(descriptor["depth_expr"], params)
        if "width_key" in descriptor:
            width = params.get(descriptor["width_key"])
        bits = depth * width if depth is not None and width is not None else None
        memories.append(
            {
                "instance_path": current.path,
                "module_name": current.module_name,
                "group": current.group,
                "kind": descriptor["kind"],
                "depth": depth,
                "width": width,
                "ports": descriptor["ports"],
                "bits_total": bits,
            }
        )
    return memories


def aggregate_groups(root: HierarchyNode, memories: List[Dict[str, object]]) -> List[Dict[str, object]]:
    group_nodes: Dict[str, List[HierarchyNode]] = defaultdict(list)
    for node in walk_nodes(root):
        group_nodes[node.group].append(node)

    memory_bits_by_group: Dict[str, int] = defaultdict(int)
    memory_count_by_group: Dict[str, int] = defaultdict(int)
    for memory in memories:
        group = str(memory["group"])
        bits = memory["bits_total"]
        memory_count_by_group[group] += 1
        if isinstance(bits, int):
            memory_bits_by_group[group] += bits

    aggregated = []
    for group in GROUP_NAMES:
        nodes = group_nodes.get(group, [])
        if not nodes:
            continue
        unique_modules = sorted({node.module_name for node in nodes})
        aggregated.append(
            {
                "group": group,
                "label": GROUP_NAMES[group],
                "instance_count": len(nodes),
                "unique_modules": unique_modules,
                "memory_instance_count": memory_count_by_group.get(group, 0),
                "memory_bits_total": memory_bits_by_group.get(group, 0),
                "logic_area_est": None,
                "seq_area_est": None,
            }
        )
    return aggregated


def detect_tools() -> Dict[str, Optional[str]]:
    return {
        "yosys": shutil.which("yosys"),
        "openroad": shutil.which("openroad"),
        "sta": shutil.which("sta"),
    }


def parse_fpga_baseline() -> Dict[str, object]:
    baseline: Dict[str, object] = {
        "sources": [
            repo_rel(FPGA_REPORT_DIR / "nf2_top.srp"),
            repo_rel(FPGA_REPORT_DIR / "nf2_top_par.twr"),
        ],
        "device": None,
        "slices_used": None,
        "slices_total": None,
        "slice_ff_used": None,
        "lut_used": None,
        "brams_used": None,
        "mult18x18_used": None,
        "core_clk_period_ns": None,
        "core_clk_fmax_mhz": None,
        "implemented_min_period_ns": None,
        "implemented_fmax_mhz": None,
        "notes": [
            "These are legacy NetFPGA Virtex-2 Pro FPGA baselines, not ASIC results.",
            "The ASIC parameter pack uses them only as comparison anchors.",
        ],
    }

    srp_path = FPGA_REPORT_DIR / "nf2_top.srp"
    twr_path = FPGA_REPORT_DIR / "nf2_top_par.twr"
    if srp_path.exists():
        srp_text = srp_path.read_text(encoding="utf-8", errors="ignore")
        patterns = {
            "device": r"Selected Device\s*:\s*(\S+)",
            "slices_used": r"Number of Slices:\s+(\d+)\s+out of\s+(\d+)",
            "slice_ff_used": r"Number of Slice Flip Flops:\s+(\d+)",
            "lut_used": r"Number of 4 input LUTs:\s+(\d+)",
            "brams_used": r"Number of BRAMs:\s+(\d+)",
            "mult18x18_used": r"Number of MULT18X18s:\s+(\d+)",
        }
        device_match = re.search(patterns["device"], srp_text)
        if device_match:
            baseline["device"] = device_match.group(1)
        slices_match = re.search(patterns["slices_used"], srp_text)
        if slices_match:
            baseline["slices_used"] = int(slices_match.group(1))
            baseline["slices_total"] = int(slices_match.group(2))
        for key in ("slice_ff_used", "lut_used", "brams_used", "mult18x18_used"):
            match = re.search(patterns[key], srp_text)
            if match:
                baseline[key] = int(match.group(1))
        timing_match = re.search(
            r"Timing constraint: Default period analysis for Clock 'core_clk'.*?Clock period:\s*([0-9.]+)ns \(frequency:\s*([0-9.]+)MHz\)",
            srp_text,
            flags=re.S,
        )
        if timing_match:
            baseline["core_clk_period_ns"] = float(timing_match.group(1))
            baseline["core_clk_fmax_mhz"] = float(timing_match.group(2))
    else:
        baseline["notes"].append(f"Missing FPGA synthesis report: {repo_rel(srp_path)}")
    if twr_path.exists():
        twr_text = twr_path.read_text(encoding="utf-8", errors="ignore")
        match = re.search(r"Minimum period:\s*([0-9.]+)ns\s+\(Maximum frequency:\s*([0-9.]+)MHz\)", twr_text)
        if match:
            baseline["implemented_min_period_ns"] = float(match.group(1))
            baseline["implemented_fmax_mhz"] = float(match.group(2))
    else:
        baseline["notes"].append(f"Missing FPGA PAR timing report: {repo_rel(twr_path)}")
    return baseline


def write_filelist(path: Path, source_files: List[Path]) -> Path:
    path.write_text("".join(f"{repo_rel(source)}\n" for source in source_files), encoding="utf-8")
    return path


def make_yosys_read_lines(source_files: List[Path]) -> str:
    return "\n".join(f"read_verilog -defer {repo_rel(source)}" for source in source_files)


def classify_memory_targets(memories: List[Dict[str, object]]) -> List[Dict[str, object]]:
    classified: List[Dict[str, object]] = []
    for memory in memories:
        key = (str(memory["module_name"]), memory["depth"], memory["width"])
        strategy = MAPPED_MEMORY_TARGETS.get(key)
        if strategy is None:
            strategy = {
                "implementation": "unclassified",
                "wrapper_strategy": "unknown",
                "target_cells": [],
                "notes": "No ASIC memory strategy defined for this memory shape.",
            }
        classified.append(
            {
                "instance_path": memory["instance_path"],
                "module_name": memory["module_name"],
                "depth": memory["depth"],
                "width": memory["width"],
                "ports": memory["ports"],
                "implementation": strategy["implementation"],
                "wrapper_strategy": strategy["wrapper_strategy"],
                "target_cells": strategy["target_cells"],
                "notes": strategy["notes"],
            }
        )
    return classified


def aggregate_memory_targets(memory_impls: List[Dict[str, object]], implementation: str) -> List[Dict[str, object]]:
    by_cell: Dict[str, Dict[str, object]] = {}
    for item in memory_impls:
        if item["implementation"] != implementation:
            continue
        for target in item["target_cells"]:
            cell_name = str(target["cell_name"])
            entry = by_cell.setdefault(
                cell_name,
                {
                    "cell_name": cell_name,
                    "total_instances": 0,
                    "instance_paths": [],
                },
            )
            entry["total_instances"] += int(target["count"])
            entry["instance_paths"].append(item["instance_path"])
    return list(by_cell.values())


def write_placeholder_macro_lib(out_path: Path, cell_name: str, spec: Dict[str, object]) -> Path:
    def bus_type_name(pin_name: str) -> str:
        return f"{cell_name}_{pin_name}_TYPE"

    lines = [
        f"library({cell_name}) {{",
        "  technology (cmos);",
        '  delay_model : table_lookup;',
        '  time_unit : "1ns";',
        '  voltage_unit : "1V";',
        '  current_unit : "1uA";',
        '  leakage_power_unit : "1nw";',
        "  capacitive_load_unit (1,ff);",
        "  nom_process : 1;",
        "  nom_temperature : 25.0;",
        "  nom_voltage : 1.1;",
        "  operating_conditions(tt_1p1_25) {",
        "    process : 1;",
        "    temperature : 25.0;",
        "    voltage : 1.1;",
        "    tree_type : balanced_tree;",
        "  }",
        "  default_operating_conditions : tt_1p1_25;",
    ]

    for name, width in list(spec["inputs"]) + [(name, width) for name, width, _ in spec["outputs"]]:
        if width == 1:
            continue
        lines.extend(
            [
                f"  type ({bus_type_name(name)}) {{",
                "    base_type : array;",
                "    data_type : bit;",
                f"    bit_width : {width};",
                f"    bit_from : {width - 1};",
                "    bit_to : 0;",
                "    downto : true;",
                "  }",
            ]
        )

    lines.extend(
        [
            f"  cell({cell_name}) {{",
            f"    area : {float(spec['area']):.3f};",
            "    interface_timing : true;",
            "    pg_pin(VDD) {",
            '      voltage_name : "VDD";',
            "      pg_type : primary_power;",
            "    }",
            "    pg_pin(VSS) {",
            '      voltage_name : "VSS";',
            "      pg_type : primary_ground;",
            "    }",
        ]
    )

    for name, width in spec["inputs"]:
        if width == 1:
            lines.extend(
                [
                    f"    pin({name}) {{",
                    "      direction : input;",
                    f"      capacitance : {25.0 if name in spec['clock_pins'] else 5.0:.3f};",
                    f"      clock : {'true' if name in spec['clock_pins'] else 'false'};",
                    "    }",
                ]
            )
        else:
            lines.extend(
                [
                    f"    bus({name}) {{",
                    f"      bus_type : {bus_type_name(name)};",
                    "      direction : input;",
                    "      capacitance : 5.000;",
                    "    }",
                ]
            )

    for name, width, related_clock in spec["outputs"]:
        if width == 1:
            lines.extend(
                [
                    f"    pin({name}) {{",
                    "      direction : output;",
                    "      max_capacitance : 500.000;",
                    "      timing() {",
                    f'        related_pin : "{related_clock}";',
                    "        timing_type : rising_edge;",
                    "        timing_sense : non_unate;",
                    '        cell_rise(scalar) { values ("0.500"); }',
                    '        cell_fall(scalar) { values ("0.500"); }',
                    '        rise_transition(scalar) { values ("0.050"); }',
                    '        fall_transition(scalar) { values ("0.050"); }',
                    "      }",
                    "    }",
                ]
            )
        else:
            lines.extend(
                [
                    f"    bus({name}) {{",
                    f"      bus_type : {bus_type_name(name)};",
                    "      direction : output;",
                    "      max_capacitance : 500.000;",
                    "      timing() {",
                    f'        related_pin : "{related_clock}";',
                    "        timing_type : rising_edge;",
                    "        timing_sense : non_unate;",
                    '        cell_rise(scalar) { values ("0.500"); }',
                    '        cell_fall(scalar) { values ("0.500"); }',
                    '        rise_transition(scalar) { values ("0.050"); }',
                    '        fall_transition(scalar) { values ("0.050"); }',
                    "      }",
                    "    }",
                ]
            )

    lines.extend(["  }", "}"])
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_path


def write_placeholder_macro_lef(out_path: Path, cell_name: str, spec: Dict[str, object]) -> Path:
    width, height = spec["size"]
    manufacturing_grid = 0.005
    signal_layer = "metal3"
    signal_tracks = NANGATE45_TRACKS[signal_layer]
    x_track = signal_tracks["x_offset"]
    y_track_offset = signal_tracks["y_offset"]
    y_track_pitch = signal_tracks["y_pitch"]
    pin_track_length = signal_tracks["x_pitch"]
    pin_track_height = signal_tracks["y_pitch"]
    edge_margin = 5.0
    left_input_pins = []
    for pin_name, pin_width in spec["inputs"]:
        if pin_width == 1:
            left_input_pins.append(pin_name)
        else:
            for bit in range(pin_width):
                left_input_pins.append(f"{pin_name}[{bit}]")

    right_output_pins = []
    for pin_name, pin_width, _ in spec["outputs"]:
        if pin_width == 1:
            right_output_pins.append(pin_name)
        else:
            for bit in range(pin_width):
                right_output_pins.append(f"{pin_name}[{bit}]")

    def pin_y_positions(count: int) -> List[float]:
        if count == 0:
            return []
        first_track_index = max(0, int(round((edge_margin - y_track_offset) / y_track_pitch)))
        last_track_index = int((height - edge_margin - y_track_offset) // y_track_pitch)
        available_tracks = max(last_track_index - first_track_index + 1, 1)
        if count <= available_tracks:
            spacing = max(available_tracks // count, 1)
            track_ids = [first_track_index + min(idx * spacing, available_tracks - 1) for idx in range(count)]
            if count > 1:
                track_ids[-1] = last_track_index
            return [y_track_offset + (track_id * y_track_pitch) for track_id in track_ids]

        # Fall back to a dense but still track-centered packing if the macro
        # has more pins than available unique tracks.
        return [y_track_offset + ((first_track_index + idx) * y_track_pitch) for idx in range(count)]

    def snap(value: float) -> float:
        return round(value / manufacturing_grid) * manufacturing_grid

    input_positions = pin_y_positions(len(left_input_pins))
    output_positions = pin_y_positions(len(right_output_pins))

    lines = [
        "VERSION 5.7 ;",
        'BUSBITCHARS "[]" ;',
        f"MACRO {cell_name}",
        f"  FOREIGN {cell_name} 0 0 ;",
        "  ORIGIN 0 0 ;",
        "  SYMMETRY X Y R90 ;",
        f"  SIZE {width:.3f} BY {height:.3f} ;",
        "  CLASS BLOCK ;",
    ]

    def add_signal_pin(name: str, direction: str, x0: float, x1: float, y: float) -> None:
        x0 = snap(x0)
        x1 = snap(x1)
        y0 = snap(max(0.0, y - (pin_track_height / 2.0)))
        y1 = snap(min(height, y + (pin_track_height / 2.0)))
        lines.extend(
            [
                f"  PIN {name}",
                f"    DIRECTION {direction} ;",
                "    USE SIGNAL ;",
                "    SHAPE ABUTMENT ;",
                "    PORT",
                f"      LAYER {signal_layer} ;",
                f"      RECT {x0:.3f} {y0:.3f} {x1:.3f} {y1:.3f} ;",
                "    END",
                f"  END {name}",
            ]
        )

    for pin_name, y in zip(left_input_pins, input_positions):
        add_signal_pin(pin_name, "INPUT", 0.0, pin_track_length, y)
    for pin_name, y in zip(right_output_pins, output_positions):
        add_signal_pin(pin_name, "OUTPUT", width - pin_track_length, width, y)

    for name, use, y0, y1 in (("VDD", "POWER", height - 0.200, height), ("VSS", "GROUND", 0.0, 0.200)):
        lines.extend(
            [
                f"  PIN {name}",
                "    DIRECTION INOUT ;",
                f"    USE {use} ;",
                "    SHAPE ABUTMENT ;",
                "    PORT",
                "      LAYER metal7 ;",
                f"      RECT 0.000 {y0:.3f} {width:.3f} {y1:.3f} ;",
                "    END",
                f"  END {name}",
            ]
        )

    lines.extend([f"END {cell_name}", "END LIBRARY"])
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_path


def write_placeholder_macro_artifacts(out_dir: Path) -> Dict[str, List[Path]]:
    macro_root = out_dir / "generated_macros"
    lib_dir = macro_root / "lib"
    lef_dir = macro_root / "lef"
    lib_dir.mkdir(parents=True, exist_ok=True)
    lef_dir.mkdir(parents=True, exist_ok=True)

    lib_paths: List[Path] = []
    lef_paths: List[Path] = []
    for cell_name, spec in PLACEHOLDER_MACROS.items():
        lib_paths.append(write_placeholder_macro_lib(lib_dir / f"{cell_name}.lib", cell_name, spec))
        lef_paths.append(write_placeholder_macro_lef(lef_dir / f"{cell_name}.lef", cell_name, spec))
    return {"lib": lib_paths, "lef": lef_paths}


def parse_scalar_report(report_path: Path, prefix: str) -> Optional[float]:
    if not report_path.exists():
        return None
    text = report_path.read_text(encoding="utf-8", errors="ignore")
    match = re.search(rf"{re.escape(prefix)}\s+(-?[0-9]+(?:\.[0-9]+)?)", text)
    if not match:
        return None
    return float(match.group(1))


def parse_synth_area_summary(stat_path: Path, top_module: str) -> Dict[str, Optional[float]]:
    summary = {
        "logic_area_um2": None,
        "seq_area_um2": None,
    }
    if not stat_path.exists():
        return summary
    text = stat_path.read_text(encoding="utf-8", errors="ignore")
    top_block_match = re.search(
        rf"Chip area for top module '\\{re.escape(top_module)}':\s+([0-9]+(?:\.[0-9]+)?)\s+"
        r"of which used for sequential elements:\s+([0-9]+(?:\.[0-9]+)?)",
        text,
        flags=re.S,
    )
    if top_block_match:
        summary["logic_area_um2"] = float(top_block_match.group(1))
        summary["seq_area_um2"] = float(top_block_match.group(2))
    return summary


def parse_openroad_log_summary(log_path: Path) -> Dict[str, Optional[float]]:
    summary = {
        "core_area_um2": None,
        "stdcell_area_um2": None,
        "macro_area_um2": None,
        "total_area_um2": None,
        "utilization_pct": None,
        "placement_design_area_um2": None,
    }
    if not log_path.exists():
        return summary
    text = log_path.read_text(encoding="utf-8", errors="ignore")
    patterns = {
        "core_area_um2": r"Core area:\s+([0-9]+(?:\.[0-9]+)?) um\^2",
        "stdcell_area_um2": r"Area of std cell instances:\s+([0-9]+(?:\.[0-9]+)?)",
        "macro_area_um2": r"Area of macros:\s+([0-9]+(?:\.[0-9]+)?)",
        "total_area_um2": r"Area of std cell instances \+ Area of macros:\s+([0-9]+(?:\.[0-9]+)?)",
        "placement_design_area_um2": r"Design area\s+([0-9]+(?:\.[0-9]+)?) um\^2",
        "utilization_pct": r"Design area\s+[0-9]+(?:\.[0-9]+)? um\^2\s+([0-9]+(?:\.[0-9]+)?)% utilization",
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, text)
        if match:
            summary[key] = float(match.group(1))
    return summary


def collect_flow_results(eval_dir: Path, pnr_dir: Path, top_module: str, platform_readiness_status: str) -> Dict[str, object]:
    synth_stat_path = eval_dir / "user_top_synth_stat.rpt"
    synth_check_path = eval_dir / "user_top_synth_check.rpt"
    pnr_report_dir = pnr_dir / "reports"
    pnr_result_dir = pnr_dir / "results"
    openroad_log = pnr_dir / "logs" / "openroad_stdout.log"
    route_def = pnr_result_dir / f"{top_module}_postroute.def"
    route_netlist = pnr_result_dir / f"{top_module}_postroute.v"
    route_sdf = pnr_result_dir / f"{top_module}_postroute.sdf"
    route_spef = pnr_result_dir / f"{top_module}_postroute.spef"
    power_report = pnr_report_dir / "4_postroute_power.rpt"

    synth_summary = parse_synth_area_summary(synth_stat_path, top_module)
    pnr_summary = parse_openroad_log_summary(openroad_log)

    synth_ok = synth_check_path.exists() and "Found and reported 0 problems." in synth_check_path.read_text(encoding="utf-8", errors="ignore")
    placement_wns = parse_scalar_report(pnr_report_dir / "1_placement_worst_slack.rpt", "worst slack max")
    placement_tns = parse_scalar_report(pnr_report_dir / "1_placement_tns.rpt", "tns max")
    cts_wns = parse_scalar_report(pnr_report_dir / "2_cts_worst_slack.rpt", "worst slack max")
    cts_tns = parse_scalar_report(pnr_report_dir / "2_cts_tns.rpt", "tns max")
    route_wns = parse_scalar_report(pnr_report_dir / "3_route_worst_slack.rpt", "worst slack max")
    route_tns = parse_scalar_report(pnr_report_dir / "3_route_tns.rpt", "tns max")

    if route_def.exists() and route_netlist.exists() and route_sdf.exists():
        flow_status = "route_complete"
    elif cts_wns is not None:
        flow_status = "cts_complete_route_blocked"
    elif placement_wns is not None:
        flow_status = "placement_complete"
    elif synth_ok:
        flow_status = "synth_complete"
    else:
        flow_status = platform_readiness_status

    power_status = "report_ready" if power_report.exists() else "flow_ready_activity_missing"
    if not route_spef.exists():
        power_status = "waiting_for_route_completion"

    return {
        "flow_status": flow_status,
        "timing_summary": {
            "placement_wns_ns": placement_wns,
            "placement_tns_ns": placement_tns,
            "cts_wns_ns": cts_wns,
            "cts_tns_ns": cts_tns,
            "route_wns_ns": route_wns,
            "route_tns_ns": route_tns,
            "status": "route_complete" if route_wns is not None else ("cts_complete" if cts_wns is not None else ("placement_complete" if placement_wns is not None else "waiting_for_pnr")),
        },
        "area_summary": {
            "logic_area_um2": synth_summary["logic_area_um2"],
            "seq_area_um2": synth_summary["seq_area_um2"],
            "stdcell_area_um2": pnr_summary["stdcell_area_um2"] or synth_summary["logic_area_um2"],
            "macro_area_um2": pnr_summary["macro_area_um2"],
            "total_area_um2": pnr_summary["total_area_um2"],
            "core_area_um2": pnr_summary["core_area_um2"],
            "placement_design_area_um2": pnr_summary["placement_design_area_um2"],
            "utilization_pct": pnr_summary["utilization_pct"],
            "status": "macro_plus_logic_available" if pnr_summary["total_area_um2"] is not None else ("logic_only_available" if synth_summary["logic_area_um2"] is not None else "waiting_for_synthesis"),
        },
        "power_summary": {
            "status": power_status,
            "post_route_spef": repo_rel(route_spef),
            "report_path": repo_rel(power_report),
            "activity_hook_env": "ASIC_POWER_ACTIVITY_TCL",
            "notes": [
                "Post-route power uses OpenROAD/OpenSTA report_power.",
                "Provide switching activity through ASIC_POWER_ACTIVITY_TCL for workload-driven dynamic power.",
            ],
        },
    }


def write_macro_placement_tcl(pnr_dir: Path) -> Path:
    tcl_path = pnr_dir / "macro_placement.tcl"
    text = """# Auto-generated macro placement guidance for user_top.
# This baseline keeps macro placement automatic but exposes the main route
# convergence knobs through environment variables.

if {[info exists ::env(MACRO_PLACE_HALO_WIDTH)] && $::env(MACRO_PLACE_HALO_WIDTH) ne ""} {
  set macro_halo_width $::env(MACRO_PLACE_HALO_WIDTH)
} else {
  set macro_halo_width 20
}

if {[info exists ::env(MACRO_PLACE_HALO_HEIGHT)] && $::env(MACRO_PLACE_HALO_HEIGHT) ne ""} {
  set macro_halo_height $::env(MACRO_PLACE_HALO_HEIGHT)
} else {
  set macro_halo_height 20
}

if {[info exists ::env(MACRO_PLACE_TARGET_UTIL)] && $::env(MACRO_PLACE_TARGET_UTIL) ne ""} {
  set macro_target_util $::env(MACRO_PLACE_TARGET_UTIL)
} else {
  set macro_target_util $place_density
}

rtl_macro_placer -halo_width $macro_halo_width -halo_height $macro_halo_height -target_util $macro_target_util
"""
    tcl_path.write_text(text, encoding="utf-8")
    return tcl_path


def write_memory_impl_verilog(out_dir: Path) -> Path:
    impl_path = out_dir / "user_top_memory_impl.v"
    text = """`timescale 1ns/1ps

(* blackbox *)
module fakeram45_1024x32 (
  output [31:0] rd_out,
  input  [9:0]  addr_in,
  input         we_in,
  input  [31:0] wd_in,
  input         clk,
  input         ce_in,
  input  [31:0] w_mask_in
);
endmodule

(* blackbox *)
module fakeram45_256x32 (
  output [31:0] rd_out,
  input  [7:0]  addr_in,
  input         we_in,
  input  [31:0] wd_in,
  input         clk,
  input         ce_in,
  input  [31:0] w_mask_in
);
endmodule

(* blackbox *)
module fakeram45_256x16 (
  output [15:0] rd_out,
  input  [7:0]  addr_in,
  input         we_in,
  input  [15:0] wd_in,
  input         clk,
  input         ce_in,
  input  [15:0] w_mask_in
);
endmodule

(* blackbox *)
module placeholder_fifo_bram_256x72_dp (
  input         clka,
  input         wea,
  input  [7:0]  addra,
  input  [71:0] dina,
  output [71:0] douta,
  input         clkb,
  input         web,
  input  [7:0]  addrb,
  input  [71:0] dinb,
  output [71:0] doutb
);
endmodule

(* blackbox *)
module placeholder_gpu_shared_dmem_16384x64_dp (
  input          clk,
  input          a_en,
  input          a_we,
  input  [13:0]  a_addr,
  input  [63:0]  a_wdata,
  output [63:0]  a_rdata,
  output         a_rvalid,
  input          b_en,
  input          b_we,
  input  [13:0]  b_addr,
  input  [63:0]  b_wdata,
  output [63:0]  b_rdata,
  output         b_rvalid
);
endmodule

(* blackbox *)
module placeholder_mem_rf_64x64_1w2r (
  input         clk,
  input         we,
  input  [5:0]  waddr,
  input  [63:0] wdata,
  input  [5:0]  r0addr,
  output [63:0] r0data,
  input  [5:0]  r1addr,
  output [63:0] r1data
);
endmodule

module mem_inst #(
  parameter ADDR_WIDTH = 9,
  parameter DATA_WIDTH = 32
) (
  input                  clk,
  input                  we,
  input  [ADDR_WIDTH-1:0] addr,
  input  [DATA_WIDTH-1:0] wdata,
  output [DATA_WIDTH-1:0] rdata
);
  wire [9:0]  phys_addr;
  wire [31:0] phys_rdata;

  assign phys_addr = {{(10-ADDR_WIDTH){1'b0}}, addr};
  assign rdata = phys_rdata[DATA_WIDTH-1:0];

  fakeram45_1024x32 u_mem (
    .rd_out   (phys_rdata),
    .addr_in  (phys_addr),
    .we_in    (we),
    .wd_in    (wdata[31:0]),
    .clk      (clk),
    .ce_in    (1'b1),
    .w_mask_in({32{we}})
  );
endmodule

module mem_data #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64
) (
  input                   clk,
  input                   we,
  input  [ADDR_WIDTH-1:0] addr,
  input  [DATA_WIDTH-1:0] wdata,
  output [DATA_WIDTH-1:0] rdata
);
  generate
    if (DATA_WIDTH == 64) begin : gen_data_64
      wire [31:0] rdata_lo;
      wire [31:0] rdata_hi;
      assign rdata = {rdata_hi, rdata_lo};

      fakeram45_256x32 u_mem_lo (
        .rd_out   (rdata_lo),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata[31:0]),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );

      fakeram45_256x32 u_mem_hi (
        .rd_out   (rdata_hi),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata[63:32]),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else if (DATA_WIDTH == 32) begin : gen_data_32
      wire [31:0] phys_rdata;
      assign rdata = phys_rdata;

      fakeram45_256x32 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else begin : gen_data_16
      wire [15:0] phys_wdata;
      wire [15:0] phys_rdata;
      assign phys_wdata = {{(16-DATA_WIDTH){1'b0}}, wdata};
      assign rdata = phys_rdata[DATA_WIDTH-1:0];

      fakeram45_256x16 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (addr[7:0]),
        .we_in    (we),
        .wd_in    (phys_wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({{(16-DATA_WIDTH){1'b0}}, {DATA_WIDTH{we}}})
      );
    end
  endgenerate
endmodule

module gpu_imem #(
  parameter AW = 9,
  parameter DW = 32,
  parameter DEPTH = 512
) (
  input              clk,
  input              we,
  input  [AW-1:0]    addr,
  input  [DW-1:0]    wdata,
  output reg [DW-1:0] rdata
);
  generate
    if (DEPTH <= 1024) begin : gen_single_bank
      wire [31:0] phys_rdata;
      wire [9:0]  phys_addr;
      assign phys_addr = {{(10-AW){1'b0}}, addr};

      always @(*) begin
        rdata = phys_rdata;
      end

      fakeram45_1024x32 u_mem (
        .rd_out   (phys_rdata),
        .addr_in  (phys_addr),
        .we_in    (we),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (1'b1),
        .w_mask_in({32{we}})
      );
    end else begin : gen_four_bank
      wire [11:0] phys_addr;
      wire [1:0]  bank_sel;
      wire [9:0]  bank_addr;
      wire [31:0] bank_rdata0;
      wire [31:0] bank_rdata1;
      wire [31:0] bank_rdata2;
      wire [31:0] bank_rdata3;
      reg  [1:0]  bank_sel_q;

      assign phys_addr = {{(12-AW){1'b0}}, addr};
      assign bank_sel = phys_addr[11:10];
      assign bank_addr = phys_addr[9:0];

      always @(posedge clk) begin
        bank_sel_q <= bank_sel;
      end

      always @(*) begin
        case (bank_sel_q)
          2'd0: rdata = bank_rdata0;
          2'd1: rdata = bank_rdata1;
          2'd2: rdata = bank_rdata2;
          default: rdata = bank_rdata3;
        endcase
      end

      fakeram45_1024x32 u_mem0 (
        .rd_out   (bank_rdata0),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd0)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd0),
        .w_mask_in({32{we && (bank_sel == 2'd0)}})
      );

      fakeram45_1024x32 u_mem1 (
        .rd_out   (bank_rdata1),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd1)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd1),
        .w_mask_in({32{we && (bank_sel == 2'd1)}})
      );

      fakeram45_1024x32 u_mem2 (
        .rd_out   (bank_rdata2),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd2)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd2),
        .w_mask_in({32{we && (bank_sel == 2'd2)}})
      );

      fakeram45_1024x32 u_mem3 (
        .rd_out   (bank_rdata3),
        .addr_in  (bank_addr),
        .we_in    (we && (bank_sel == 2'd3)),
        .wd_in    (wdata),
        .clk      (clk),
        .ce_in    (bank_sel == 2'd3),
        .w_mask_in({32{we && (bank_sel == 2'd3)}})
      );
    end
  endgenerate
endmodule

module fifo_bram #(
  parameter DATA_WIDTH = 72,
  parameter ADDR_WIDTH = 8
) (
  input                    clka,
  input                    wea,
  input  [ADDR_WIDTH-1:0]  addra,
  input  [DATA_WIDTH-1:0]  dina,
  output [DATA_WIDTH-1:0]  douta,
  input                    clkb,
  input                    web,
  input  [ADDR_WIDTH-1:0]  addrb,
  input  [DATA_WIDTH-1:0]  dinb,
  output [DATA_WIDTH-1:0]  doutb
);
  placeholder_fifo_bram_256x72_dp u_macro (
    .clka  (clka),
    .wea   (wea),
    .addra (addra[7:0]),
    .dina  (dina[71:0]),
    .douta (douta),
    .clkb  (clkb),
    .web   (web),
    .addrb (addrb[7:0]),
    .dinb  (dinb[71:0]),
    .doutb (doutb)
  );
endmodule

module gpu_shared_dmem #(
  parameter ADDR_WIDTH = 8,
  parameter DATA_WIDTH = 64,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input                   clk,
  input                   a_en,
  input                   a_we,
  input  [ADDR_WIDTH-1:0] a_addr,
  input  [DATA_WIDTH-1:0] a_wdata,
  output [DATA_WIDTH-1:0] a_rdata,
  output                  a_rvalid,
  input                   b_en,
  input                   b_we,
  input  [ADDR_WIDTH-1:0] b_addr,
  input  [DATA_WIDTH-1:0] b_wdata,
  output [DATA_WIDTH-1:0] b_rdata,
  output                  b_rvalid
);
  placeholder_gpu_shared_dmem_16384x64_dp u_macro (
    .clk     (clk),
    .a_en    (a_en),
    .a_we    (a_we),
    .a_addr  (a_addr[13:0]),
    .a_wdata (a_wdata[63:0]),
    .a_rdata (a_rdata),
    .a_rvalid(a_rvalid),
    .b_en    (b_en),
    .b_we    (b_we),
    .b_addr  (b_addr[13:0]),
    .b_wdata (b_wdata[63:0]),
    .b_rdata (b_rdata),
    .b_rvalid(b_rvalid)
  );
endmodule

module mem_RF #(
  parameter ADDR_WIDTH = 6,
  parameter DATA_WIDTH = 64
) (
  input                   clk,
  input                   we,
  input  [ADDR_WIDTH-1:0] waddr,
  input  [DATA_WIDTH-1:0] wdata,
  input  [ADDR_WIDTH-1:0] r0addr,
  output [DATA_WIDTH-1:0] r0data,
  input  [ADDR_WIDTH-1:0] r1addr,
  output [DATA_WIDTH-1:0] r1data
);
  placeholder_mem_rf_64x64_1w2r u_macro (
    .clk   (clk),
    .we    (we),
    .waddr (waddr[5:0]),
    .wdata (wdata[63:0]),
    .r0addr(r0addr[5:0]),
    .r0data(r0data),
    .r1addr(r1addr[5:0]),
    .r1data(r1data)
  );
endmodule
"""
    impl_path.write_text(text, encoding="utf-8")
    return impl_path


def write_yosys_script(
    out_dir: Path,
    rtl_filelist: Path,
    memory_impl_path: Path,
    logic_source_files: List[Path],
    top_module: str,
    target_ns: float,
    platform: str,
) -> Path:
    script_path = out_dir / "user_top_eval.ys"
    read_lines = make_yosys_read_lines(logic_source_files)
    script = f"""# Auto-generated hierarchy check for scripts/asic/generate_rsu_eval.py
# Target platform: {platform}
# Logic source filelist: {repo_rel(rtl_filelist)}
# Memory implementation RTL: {repo_rel(memory_impl_path)}
# For mapped synthesis, run: {repo_rel(out_dir / 'run_yosys_synth.sh')}

read_verilog -defer {repo_rel(memory_impl_path)}
{read_lines}

hierarchy -check -top {top_module}
check
proc
opt
tee -o {repo_rel(out_dir / 'user_top_hierarchy_stat.rpt')} stat -top {top_module}

# Default planning target clock: {target_ns:.3f} ns
# Eval output root: {repo_rel(out_dir)}
"""
    script_path.write_text(script, encoding="utf-8")
    return script_path


def write_yosys_wrapper(
    eval_dir: Path,
    top_module: str,
    rtl_filelist: Path,
    memory_impl_path: Path,
    logic_source_files: List[Path],
    synth_netlist: Path,
    synth_json: Path,
    synth_stat_path: Path,
    synth_check_path: Path,
    platform: str,
) -> Path:
    wrapper_path = eval_dir / "run_yosys_synth.sh"
    read_lines = make_yosys_read_lines(logic_source_files)
    script = f"""#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [[ -n "${{ASIC_PLATFORM_CONFIG:-}}" ]]; then
  # shellcheck disable=SC1090
  source "${{ASIC_PLATFORM_CONFIG}}"
fi

YOSYS_BIN="${{YOSYS_BIN:-yosys}}"
if ! command -v "$YOSYS_BIN" >/dev/null 2>&1; then
  ORFS_YOSYS="$HOME/codex/third_party/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys"
  if [[ -x "$ORFS_YOSYS" ]]; then
    YOSYS_BIN="$ORFS_YOSYS"
  fi
fi
if ! command -v "$YOSYS_BIN" >/dev/null 2>&1 && [[ ! -x "$YOSYS_BIN" ]]; then
  echo "error: yosys not found; set YOSYS_BIN or add yosys to PATH" >&2
  exit 127
fi

if [[ -n "${{ASIC_PLATFORM_ROOT:-}}" ]]; then
  : "${{ASIC_LIBERTY:=${{ASIC_PLATFORM_ROOT}}/lib/NangateOpenCellLibrary_typical.lib}}"
fi

: "${{ASIC_LIBERTY:?Set ASIC_LIBERTY or ASIC_PLATFORM_ROOT before running synthesis.}}"

MEMORY_IMPL="{repo_rel(memory_impl_path)}"
SYNTH_NETLIST="{repo_rel(synth_netlist)}"
SYNTH_JSON="{repo_rel(synth_json)}"
SYNTH_STAT="{repo_rel(synth_stat_path)}"
SYNTH_CHECK="{repo_rel(synth_check_path)}"
TMP_SCRIPT="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<EOF
read_verilog -defer $MEMORY_IMPL
{read_lines}
hierarchy -check -top {top_module}
check
proc
memory
opt
fsm
opt
techmap
opt
dfflibmap -liberty $ASIC_LIBERTY
abc -liberty $ASIC_LIBERTY
clean
read_liberty -lib $ASIC_LIBERTY
hilomap -singleton -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
check -assert
tee -o $SYNTH_STAT stat -top {top_module} -liberty $ASIC_LIBERTY
tee -o $SYNTH_CHECK check -mapped -assert
write_json $SYNTH_JSON
write_verilog -noattr $SYNTH_NETLIST
EOF

(
  cd "$REPO_ROOT"
  "$YOSYS_BIN" -s "$TMP_SCRIPT"
)

echo "wrote $SYNTH_NETLIST"
echo "wrote $SYNTH_JSON"
echo "wrote $SYNTH_STAT"
echo "wrote $SYNTH_CHECK"
"""
    wrapper_path.write_text(script, encoding="utf-8")
    wrapper_path.chmod(0o755)
    return wrapper_path


def write_openroad_skeleton(
    pnr_dir: Path,
    top_module: str,
    target_ns: float,
    eval_dir: Path,
    platform: str,
    synthesized_netlist: Path,
    placeholder_macro_artifacts: Dict[str, List[Path]],
    macro_placement_tcl: Path,
) -> Path:
    pnr_dir.mkdir(parents=True, exist_ok=True)
    (pnr_dir / "reports").mkdir(parents=True, exist_ok=True)
    (pnr_dir / "results").mkdir(parents=True, exist_ok=True)
    (pnr_dir / "logs").mkdir(parents=True, exist_ok=True)
    tcl_path = pnr_dir / "openroad_flow.tcl"
    platform_info = PLATFORM_SUPPORT[platform]
    default_die_area = platform_info["default_die_area"].replace("{", "").replace("}", "")
    default_core_area = platform_info["default_core_area"].replace("{", "").replace("}", "")
    placeholder_lefs = " ".join(f"[file join $repo_root {repo_rel(path)}]" for path in placeholder_macro_artifacts["lef"])
    placeholder_libs = " ".join(f"[file join $repo_root {repo_rel(path)}]" for path in placeholder_macro_artifacts["lib"])
    fakeram_cells = " ".join(sorted(FAKERAM_CELLS))
    text = f"""# Auto-generated OpenROAD baseline for {platform}.
# Expected wrapper entrypoint: {repo_rel(pnr_dir / 'run_openroad.sh')}

proc require_env {{name description}} {{
  if {{![info exists ::env($name)] || $::env($name) eq ""}} {{
    puts stderr "error: missing environment variable $name ($description)"
    exit 2
  }}
}}

proc env_or_default {{name default_value}} {{
  if {{[info exists ::env($name)] && $::env($name) ne ""}} {{
    return $::env($name)
  }}
  return $default_value
}}

proc source_if_exists {{path}} {{
  if {{[file exists $path]}} {{
    uplevel #0 [list source $path]
  }}
}}

proc ensure_env_default {{name default_value}} {{
  if {{![info exists ::env($name)] || $::env($name) eq ""}} {{
    set ::env($name) $default_value
  }}
}}

proc source_env_tcl_if_present {{name}} {{
  if {{![info exists ::env($name)] || $::env($name) eq ""}} {{
    return
  }}
  source_if_exists [file normalize $::env($name)]
}}

proc repair_tie_fanout_if_enabled {{}} {{
  if {{$::env(SKIP_REPAIR_TIE_FANOUT)}} {{
    puts "Skipping repair_tie_fanout because SKIP_REPAIR_TIE_FANOUT is set."
    return
  }}
  foreach {{tie_var tie_label}} {{TIELO_CELL_AND_PORT lo TIEHI_CELL_AND_PORT hi}} {{
    set tie_spec $::env($tie_var)
    set tie_cell_name [lindex $tie_spec 0]
    set tie_pin_name [lindex $tie_spec 1]
    set tie_lib_cells [get_lib_cell $tie_cell_name]
    if {{[llength $tie_lib_cells] == 0}} {{
      puts stderr "error: unable to resolve tie cell $tie_cell_name from $tie_var"
      exit 2
    }}
    set tie_lib_name [get_name [get_property [lindex $tie_lib_cells 0] library]]
    set tie_pin "${{tie_lib_name}}/${{tie_cell_name}}/${{tie_pin_name}}"
    puts "Repair tie $tie_label fanout using $tie_pin ..."
    repair_tie_fanout -separation $::env(TIE_SEPARATION) $tie_pin
  }}
}}

proc normalize_tie_constant_nets {{}} {{
  set block [[[ord::get_db] getChip] getBlock]
  set converted_count 0
  foreach dbnet [$block getNets] {{
    set sig_type [$dbnet getSigType]
    if {{$sig_type ni {{GROUND POWER}}}} {{
      continue
    }}
    if {{[$dbnet isSpecial]}} {{
      continue
    }}
    set iterm_count [llength [$dbnet getITerms]]
    set bterm_count [llength [$dbnet getBTerms]]
    if {{$iterm_count != 0 || $bterm_count != 0}} {{
      continue
    }}
    puts "Converting constant net [$dbnet getName] from $sig_type to SIGNAL."
    $dbnet setSigType SIGNAL
    incr converted_count
  }}
  puts "Converted $converted_count constant POWER/GROUND nets to SIGNAL."
}}

set run_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $run_dir ../../../..]]
set design_name {top_module}
set top_module {top_module}
set synthesized_netlist [file normalize [file join $repo_root {repo_rel(synthesized_netlist)}]]
set sdc_file [file normalize [file join $repo_root {repo_rel(eval_dir / 'user_top_eval.sdc')}]]
set macro_placement_tcl [file normalize [file join $repo_root {repo_rel(macro_placement_tcl)}]]
set report_dir [file normalize [file join $run_dir reports]]
set result_dir [file normalize [file join $run_dir results]]
set log_dir [file normalize [file join $run_dir logs]]

file mkdir $report_dir
file mkdir $result_dir
file mkdir $log_dir

require_env ASIC_LIBERTY "standard-cell liberty"
require_env ASIC_TECH_LEF "technology LEF"
require_env ASIC_STD_CELL_LEF "standard-cell LEF"

set liberty_file $::env(ASIC_LIBERTY)
set tech_lef $::env(ASIC_TECH_LEF)
set stdcell_lef $::env(ASIC_STD_CELL_LEF)
if {{[info exists ::env(ASIC_PLATFORM_ROOT)] && $::env(ASIC_PLATFORM_ROOT) ne ""}} {{
  set platform_root [file normalize $::env(ASIC_PLATFORM_ROOT)]
}} else {{
  set platform_root [file normalize [file dirname [file dirname $tech_lef]]]
}}
set site [env_or_default ASIC_SITE "{platform_info['default_site']}"]
set die_area [env_or_default ASIC_DIE_AREA "{default_die_area}"]
set core_area [env_or_default ASIC_CORE_AREA "{default_core_area}"]
set place_density [env_or_default ASIC_PLACE_DENSITY "{platform_info['default_place_density']:.2f}"]

ensure_env_default TAP_CELL_NAME TAPCELL_X1
ensure_env_default MIN_ROUTING_LAYER metal2
ensure_env_default MIN_CLK_ROUTING_LAYER metal4
ensure_env_default MAX_ROUTING_LAYER metal10
ensure_env_default IO_PLACER_H metal5
ensure_env_default IO_PLACER_V metal6
ensure_env_default VIA_IN_PIN_MIN_LAYER metal1
ensure_env_default VIA_IN_PIN_MAX_LAYER metal3
ensure_env_default TIEHI_CELL_AND_PORT {{LOGIC1_X1 Z}}
ensure_env_default TIELO_CELL_AND_PORT {{LOGIC0_X1 Z}}
ensure_env_default TIE_SEPARATION 0
ensure_env_default SKIP_REPAIR_TIE_FANOUT 0
ensure_env_default DONT_USE_CELLS {{TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1}}
ensure_env_default CELL_PAD_IN_SITES_DETAIL_PLACEMENT 0
ensure_env_default RECOVER_POWER 0
ensure_env_default MACRO_PLACE_HALO_WIDTH 20
ensure_env_default MACRO_PLACE_HALO_HEIGHT 20
ensure_env_default DETAILED_ROUTE_END_ITERATION 64
ensure_env_default DETAILED_ROUTE_VERBOSE 1

set additional_lefs [list]
foreach cell_name [list {fakeram_cells}] {{
  lappend additional_lefs [file join $platform_root lef "${{cell_name}}.lef"]
}}
foreach lef [list {placeholder_lefs}] {{
  lappend additional_lefs $lef
}}

set additional_libs [list]
foreach cell_name [list {fakeram_cells}] {{
  lappend additional_libs [file join $platform_root lib "${{cell_name}}.lib"]
}}
foreach liberty [list {placeholder_libs}] {{
  lappend additional_libs $liberty
}}

if {{![file exists $synthesized_netlist]}} {{
  puts stderr "error: synthesized netlist not found at $synthesized_netlist; run {repo_rel(eval_dir / 'run_yosys_synth.sh')} first"
  exit 2
}}

read_lef $tech_lef
read_lef $stdcell_lef
foreach lef $additional_lefs {{
  read_lef $lef
}}
read_liberty $liberty_file
foreach liberty $additional_libs {{
  read_liberty $liberty
}}
read_verilog $synthesized_netlist
link_design $top_module
read_sdc $sdc_file
if {{$::env(DONT_USE_CELLS) ne ""}} {{
  set_dont_use $::env(DONT_USE_CELLS)
}}

initialize_floorplan -die_area $die_area -core_area $core_area -site $site
if {{[file exists [file join $platform_root make_tracks.tcl]]}} {{
  source [file join $platform_root make_tracks.tcl]
}} else {{
  make_tracks
}}
source_if_exists [file join $platform_root setRC.tcl]
source_if_exists [file join $platform_root fastroute.tcl]
repair_tie_fanout_if_enabled
normalize_tie_constant_nets
source_if_exists $macro_placement_tcl
place_pins -hor_layers $::env(IO_PLACER_H) -ver_layers $::env(IO_PLACER_V)
source_if_exists [file join $platform_root tapcell.tcl]
source_if_exists [file join $platform_root grid_strategy-M1-M4-M7.tcl]
pdngen
global_placement -density $place_density
detailed_placement
check_placement -verbose
estimate_parasitics -placement
report_design_area > [file join $report_dir 1_placement_design_area.rpt]
report_worst_slack > [file join $report_dir 1_placement_worst_slack.rpt]
report_tns > [file join $report_dir 1_placement_tns.rpt]

repair_clock_inverters
clock_tree_synthesis -sink_clustering_enable -repair_clock_nets
set_placement_padding -global -left $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT) -right $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT)
detailed_placement
check_placement -verbose
set_propagated_clock [all_clocks]
estimate_parasitics -placement
report_worst_slack > [file join $report_dir 2_cts_worst_slack.rpt]
report_tns > [file join $report_dir 2_cts_tns.rpt]

normalize_tie_constant_nets
pin_access -via_in_pin_bottom_layer $::env(VIA_IN_PIN_MIN_LAYER) -via_in_pin_top_layer $::env(VIA_IN_PIN_MAX_LAYER)
global_route -congestion_report_file [file join $report_dir 3_route_congestion.rpt]
write_def [file join $result_dir {top_module}_preroute.def]
write_verilog [file join $result_dir {top_module}_preroute.v]
detailed_route -output_drc [file join $report_dir 3_route_drc.rpt] -output_maze [file join $result_dir 3_route_maze.log] -via_in_pin_bottom_layer $::env(VIA_IN_PIN_MIN_LAYER) -via_in_pin_top_layer $::env(VIA_IN_PIN_MAX_LAYER) -repair_pdn_vias 1 -droute_end_iter $::env(DETAILED_ROUTE_END_ITERATION) -verbose $::env(DETAILED_ROUTE_VERBOSE)
estimate_parasitics -global_routing
source_env_tcl_if_present ASIC_POWER_ACTIVITY_TCL
report_checks -path_delay min_max -format full_clock_expanded > [file join $report_dir 3_route_checks.rpt]
report_design_area > [file join $report_dir 3_route_design_area.rpt]
report_worst_slack > [file join $report_dir 3_route_worst_slack.rpt]
report_tns > [file join $report_dir 3_route_tns.rpt]
report_power > [file join $report_dir 4_postroute_power.rpt]

write_def [file join $result_dir {top_module}_postroute.def]
write_verilog [file join $result_dir {top_module}_postroute.v]
write_sdf [file join $result_dir {top_module}_postroute.sdf]
write_spef [file join $result_dir {top_module}_postroute.spef]

# Default planning target from the RSU ASIC parameter pack:
#   core_clk period = {target_ns:.3f} ns
# Default PNR root:
#   {repo_rel(pnr_dir)}
"""
    tcl_path.write_text(text, encoding="utf-8")
    return tcl_path


def write_openroad_wrapper(pnr_dir: Path, platform: str) -> Path:
    wrapper_path = pnr_dir / "run_openroad.sh"
    script = f"""#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"

if [[ -n "${{ASIC_PLATFORM_CONFIG:-}}" ]]; then
  # shellcheck disable=SC1090
  source "${{ASIC_PLATFORM_CONFIG}}"
fi

if [[ -n "${{ASIC_PLATFORM_ROOT:-}}" ]]; then
  : "${{ASIC_LIBERTY:=${{ASIC_PLATFORM_ROOT}}/lib/NangateOpenCellLibrary_typical.lib}}"
  : "${{ASIC_TECH_LEF:=${{ASIC_PLATFORM_ROOT}}/lef/NangateOpenCellLibrary.tech.lef}}"
  : "${{ASIC_STD_CELL_LEF:=${{ASIC_PLATFORM_ROOT}}/lef/NangateOpenCellLibrary.macro.mod.lef}}"
fi

export ASIC_LIBERTY ASIC_TECH_LEF ASIC_STD_CELL_LEF

for required_var in ASIC_LIBERTY ASIC_TECH_LEF ASIC_STD_CELL_LEF; do
  if [[ -z "${{!required_var:-}}" ]]; then
    echo "error: missing $required_var; configure the {platform} library paths first" >&2
    exit 2
  fi
done

OPENROAD_BIN="${{OPENROAD_BIN:-openroad}}"
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1; then
  ORFS_OPENROAD="$HOME/codex/third_party/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad"
  if [[ -x "$ORFS_OPENROAD" ]]; then
    OPENROAD_BIN="$ORFS_OPENROAD"
  fi
fi
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1 && [[ ! -x "$OPENROAD_BIN" ]]; then
  echo "error: openroad not found; set OPENROAD_BIN or add openroad to PATH" >&2
  exit 127
fi

mkdir -p "$SCRIPT_DIR/logs"
cd "$SCRIPT_DIR"
"$OPENROAD_BIN" -exit openroad_flow.tcl | tee "logs/openroad_stdout.log"
"""
    wrapper_path.write_text(script, encoding="utf-8")
    wrapper_path.chmod(0o755)
    return wrapper_path


def write_power_estimation_tcl(
    pnr_dir: Path,
    top_module: str,
    eval_dir: Path,
    platform: str,
    placeholder_macro_artifacts: Dict[str, List[Path]],
) -> Path:
    power_tcl = pnr_dir / "power_estimation.tcl"
    placeholder_lefs = " ".join(f"[file join $repo_root {repo_rel(path)}]" for path in placeholder_macro_artifacts["lef"])
    placeholder_libs = " ".join(f"[file join $repo_root {repo_rel(path)}]" for path in placeholder_macro_artifacts["lib"])
    fakeram_cells = " ".join(sorted(FAKERAM_CELLS))
    text = f"""# Auto-generated post-route power estimation helper for {platform}.

proc require_env {{name description}} {{
  if {{![info exists ::env($name)] || $::env($name) eq ""}} {{
    puts stderr "error: missing environment variable $name ($description)"
    exit 2
  }}
}}

proc env_or_default {{name default_value}} {{
  if {{[info exists ::env($name)] && $::env($name) ne ""}} {{
    return $::env($name)
  }}
  return $default_value
}}

proc source_if_exists {{path}} {{
  if {{[file exists $path]}} {{
    uplevel #0 [list source $path]
  }}
}}

proc source_env_tcl_if_present {{name}} {{
  if {{![info exists ::env($name)] || $::env($name) eq ""}} {{
    return
  }}
  source_if_exists [file normalize $::env($name)]
}}

set run_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $run_dir ../../../..]]
set top_module {top_module}
set sdc_file [file normalize [file join $repo_root {repo_rel(eval_dir / 'user_top_eval.sdc')}]]
set postroute_netlist [file normalize [file join $run_dir results {top_module}_postroute.v]]
set postroute_spef [file normalize [file join $run_dir results {top_module}_postroute.spef]]
set report_dir [file normalize [file join $run_dir reports]]
set report_file [file normalize [file join $report_dir 4_postroute_power.rpt]]

require_env ASIC_LIBERTY "standard-cell liberty"
require_env ASIC_TECH_LEF "technology LEF"
require_env ASIC_STD_CELL_LEF "standard-cell LEF"

set liberty_file $::env(ASIC_LIBERTY)
set tech_lef $::env(ASIC_TECH_LEF)
set stdcell_lef $::env(ASIC_STD_CELL_LEF)
if {{[info exists ::env(ASIC_PLATFORM_ROOT)] && $::env(ASIC_PLATFORM_ROOT) ne ""}} {{
  set platform_root [file normalize $::env(ASIC_PLATFORM_ROOT)]
}} else {{
  set platform_root [file normalize [file dirname [file dirname $tech_lef]]]
}}

set additional_lefs [list]
foreach cell_name [list {fakeram_cells}] {{
  lappend additional_lefs [file join $platform_root lef "${{cell_name}}.lef"]
}}
foreach lef [list {placeholder_lefs}] {{
  lappend additional_lefs $lef
}}

set additional_libs [list]
foreach cell_name [list {fakeram_cells}] {{
  lappend additional_libs [file join $platform_root lib "${{cell_name}}.lib"]
}}
foreach liberty [list {placeholder_libs}] {{
  lappend additional_libs $liberty
}}

if {{![file exists $postroute_netlist]}} {{
  puts stderr "error: missing post-route netlist $postroute_netlist"
  exit 2
}}
if {{![file exists $postroute_spef]}} {{
  puts stderr "error: missing post-route SPEF $postroute_spef"
  exit 2
}}

file mkdir $report_dir

read_lef $tech_lef
read_lef $stdcell_lef
foreach lef $additional_lefs {{
  read_lef $lef
}}
read_liberty $liberty_file
foreach liberty $additional_libs {{
  read_liberty $liberty
}}
read_verilog $postroute_netlist
link_design $top_module
read_sdc $sdc_file
read_spef $postroute_spef
set_propagated_clock [all_clocks]
source_env_tcl_if_present ASIC_POWER_ACTIVITY_TCL
report_power > $report_file
puts "wrote $report_file"
"""
    power_tcl.write_text(text, encoding="utf-8")
    return power_tcl


def write_power_wrapper(pnr_dir: Path) -> Path:
    wrapper_path = pnr_dir / "run_power_estimate.sh"
    script = """#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${ASIC_PLATFORM_CONFIG:-}" ]]; then
  # shellcheck disable=SC1090
  source "${ASIC_PLATFORM_CONFIG}"
fi

if [[ -n "${ASIC_PLATFORM_ROOT:-}" ]]; then
  : "${ASIC_LIBERTY:=${ASIC_PLATFORM_ROOT}/lib/NangateOpenCellLibrary_typical.lib}"
  : "${ASIC_TECH_LEF:=${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.tech.lef}"
  : "${ASIC_STD_CELL_LEF:=${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.macro.mod.lef}"
fi

export ASIC_LIBERTY ASIC_TECH_LEF ASIC_STD_CELL_LEF

OPENROAD_BIN="${OPENROAD_BIN:-openroad}"
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1; then
  ORFS_OPENROAD="$HOME/codex/third_party/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad"
  if [[ -x "$ORFS_OPENROAD" ]]; then
    OPENROAD_BIN="$ORFS_OPENROAD"
  fi
fi
if ! command -v "$OPENROAD_BIN" >/dev/null 2>&1 && [[ ! -x "$OPENROAD_BIN" ]]; then
  echo "error: openroad not found; set OPENROAD_BIN or add openroad to PATH" >&2
  exit 127
fi

cd "$SCRIPT_DIR"
"$OPENROAD_BIN" -exit power_estimation.tcl
"""
    wrapper_path.write_text(script, encoding="utf-8")
    wrapper_path.chmod(0o755)
    return wrapper_path


def write_gatelevel_sim_skeleton(sim_dir: Path, top_module: str, pnr_dir: Path) -> Path:
    sim_dir.mkdir(parents=True, exist_ok=True)
    (sim_dir / "logs").mkdir(parents=True, exist_ok=True)
    (sim_dir / "waves").mkdir(parents=True, exist_ok=True)
    script_path = sim_dir / "run_gatelevel_sdf_template.sh"
    script = f"""#!/usr/bin/env bash
set -euo pipefail

# Auto-generated gate-level + SDF simulation template.
# Replace the simulator command and testbench paths for your environment.
# The netlist/SDF paths below match the default OpenROAD output contract.

TOP_MODULE="{top_module}"
POST_ROUTE_NETLIST="{repo_rel(pnr_dir / 'results' / f'{top_module}_postroute.v')}"
POST_ROUTE_SDF="{repo_rel(pnr_dir / 'results' / f'{top_module}_postroute.sdf')}"
TESTBENCH="<replace-with-testbench.v>"
LOG_PATH="logs/{top_module}_gatelevel_sdf.log"
WAVE_PATH="waves/{top_module}_gatelevel_sdf.vcd"

echo "TOP_MODULE=$TOP_MODULE"
echo "POST_ROUTE_NETLIST=$POST_ROUTE_NETLIST"
echo "POST_ROUTE_SDF=$POST_ROUTE_SDF"
echo "TESTBENCH=$TESTBENCH"
echo "LOG_PATH=$LOG_PATH"
echo "WAVE_PATH=$WAVE_PATH"

# Example flow shape only:
# <simulator> \\
#   -top "$TOP_MODULE" \\
#   "$TESTBENCH" "$POST_ROUTE_NETLIST" \\
#   +sdf_annotate="$POST_ROUTE_SDF" \\
#   > "$LOG_PATH" 2>&1
"""
    script_path.write_text(script, encoding="utf-8")
    script_path.chmod(0o755)
    return script_path


def write_pnr_readme(pnr_dir: Path, top_module: str) -> Path:
    readme_path = pnr_dir / "README.md"
    text = f"""# {top_module} PNR Run Root

This directory is reserved for OpenROAD physical design outputs.

- `run_openroad.sh`: validates Nangate45 inputs and launches `openroad_flow.tcl`
- `run_power_estimate.sh`: reruns post-route power using `results/{top_module}_postroute.v/.spef`
- `macro_placement.tcl`: automatic macro packing rules for placeholder and fakeram macros
- `reports/`: timing, area, utilization, DRC summaries
- `results/`: synthesized / placed / routed netlists, DEF/ODB/SDF/SPEF
- `logs/`: tool logs
"""
    readme_path.write_text(text, encoding="utf-8")
    return readme_path


def write_sim_readme(sim_dir: Path, top_module: str) -> Path:
    readme_path = sim_dir / "README.md"
    text = f"""# {top_module} Gate-Level + SDF Simulation

This directory is reserved for post-route gate-level simulation artifacts.

- `logs/`: simulator stdout/stderr summaries
- `waves/`: optional VCD/FST/FSDB outputs
- `run_gatelevel_sdf_template.sh`: template entrypoint for SDF-annotated simulation using `results/{top_module}_postroute.v/.sdf`
"""
    readme_path.write_text(text, encoding="utf-8")
    return readme_path


def write_stub_sdc(out_dir: Path, target_ns: float) -> Path:
    sdc_path = out_dir / "user_top_eval.sdc"
    sdc = f"""# Auto-generated stub SDC for later synthesis / P&R.
create_clock -name core_clk -period {target_ns:.3f} [get_ports clk]
set_input_delay 0.0 -clock core_clk [all_inputs]
set_output_delay 0.0 -clock core_clk [all_outputs]
# Refine IO delays and false/multicycle paths after library + interface timing are known.
"""
    sdc_path.write_text(sdc, encoding="utf-8")
    return sdc_path


def describe_platform_readiness(platform: str, tools: Dict[str, Optional[str]]) -> Dict[str, object]:
    info = PLATFORM_SUPPORT[platform]
    resolved_inputs = {}
    missing_inputs = []
    platform_root = os.environ.get("ASIC_PLATFORM_ROOT")
    for env_name in info["required_env"]:
        value = os.environ.get(env_name)
        if not value and platform_root:
            if env_name == "ASIC_LIBERTY":
                value = str(Path(platform_root) / "lib" / "NangateOpenCellLibrary_typical.lib")
            elif env_name == "ASIC_TECH_LEF":
                value = str(Path(platform_root) / "lef" / "NangateOpenCellLibrary.tech.lef")
            elif env_name == "ASIC_STD_CELL_LEF":
                value = str(Path(platform_root) / "lef" / "NangateOpenCellLibrary.macro.mod.lef")
        resolved_inputs[env_name] = value
        if not value:
            missing_inputs.append(env_name)
    missing_tools = [name for name in ("yosys", "openroad") if not tools.get(name)]
    if missing_inputs and missing_tools:
        status = "waiting_for_tools_and_platform_inputs"
    elif missing_inputs:
        status = "waiting_for_platform_inputs"
    elif missing_tools:
        status = "waiting_for_tools"
    else:
        status = "ready_for_synth_and_pnr"
    return {
        "status": status,
        "platform_root": repo_rel(info["platform_root"]),
        "required_env": info["required_env"],
        "optional_env": info["optional_env"],
        "resolved_inputs": resolved_inputs,
        "missing_inputs": missing_inputs,
        "missing_tools": missing_tools,
    }


def maybe_run_yosys(
    tools: Dict[str, Optional[str]],
    yosys_script: Path,
    out_dir: Path,
    run_yosys: bool,
) -> Optional[Dict[str, object]]:
    if not run_yosys or not tools["yosys"]:
        return None
    env = os.environ.copy()
    cmd = [tools["yosys"], "-s", str(yosys_script)]
    result = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    (out_dir / "yosys_stdout.txt").write_text(result.stdout, encoding="utf-8")
    (out_dir / "yosys_stderr.txt").write_text(result.stderr, encoding="utf-8")
    return {
        "command": cmd,
        "returncode": result.returncode,
        "stdout_path": "yosys_stdout.txt",
        "stderr_path": "yosys_stderr.txt",
    }


def make_markdown(report: Dict[str, object]) -> str:
    platform = report["platform"]
    platform_readiness = report["platform_readiness"]
    tools = report["tool_availability"]
    timing = report["timing_summary"]
    baseline = report["fpga_baseline"]
    area = report["area_summary"]
    power = report["power_summary"]
    memory = report["memory_summary"]
    assumptions = report["assumption_notes"]
    next_stage = report["next_stage_paths"]
    post_route_sim = report["post_route_sim"]
    generated = report["generated_artifacts"]
    memory_implementation = report["memory_implementation"]
    fakeram_instances = report["fakeram_instances"]
    placeholder_macros = report["placeholder_macros"]
    artifact_paths = report["artifact_contract"]
    group_rows = []
    for group in area["by_hierarchy"]:
        group_rows.append(
            f"| {group['label']} | {group['instance_count']} | {len(group['unique_modules'])} | {group['memory_instance_count']} | {group['memory_bits_total']} |"
        )
    memory_rows = []
    for item in memory:
        memory_rows.append(
            f"| `{item['instance_path']}` | `{item['module_name']}` | {item['kind']} | {item['depth']} | {item['width']} | {item['bits_total']} | {item['ports']} |"
        )
    impl_rows = []
    for item in memory_implementation:
        targets = ", ".join(f"{target['cell_name']} x{target['count']}" for target in item["target_cells"]) or "none"
        impl_rows.append(
            f"| `{item['instance_path']}` | `{item['implementation']}` | `{item['wrapper_strategy']}` | `{targets}` |"
        )

    return f"""# RSU ASIC Evaluation Pack

## Summary

- Top module: `{report['top_module']}`
- Evaluation scope: `{report['evaluation_scope']}`
- Platform: `{platform}`
- Flow status: `{report['flow_status']}`
- Artifact root: `{report['artifact_root']}`
- Clock target: `{timing['target_ns']} ns`
- Yosys in `PATH`: `{"yes" if tools['yosys'] else "no"}`
- OpenROAD in `PATH`: `{"yes" if tools['openroad'] else "no"}`
- Total memory bits discovered: `{report['memory_bits_total']}`
- Logic area: `{area['logic_area_um2']}`
- Total macro + logic area: `{area['total_area_um2']}`
- Placement WNS/TNS: `{timing['placement_wns_ns']}` / `{timing['placement_tns_ns']}`
- CTS WNS/TNS: `{timing['cts_wns_ns']}` / `{timing['cts_tns_ns']}`
- Route WNS/TNS: `{timing['route_wns_ns']}` / `{timing['route_tns_ns']}`
- Power status: `{power['status']}`

## Scope

- Included modules: `{", ".join(report['included_modules'])}`
- Excluded modules: `{", ".join(report['excluded_modules'])}`
- Missing external modules during closure walk: `{", ".join(report['missing_modules']) if report['missing_modules'] else "none"}`

## Stage Directories

- Eval dir: `{next_stage['eval_dir']}`
- PNR dir: `{next_stage['pnr_dir']}`
- Sim dir: `{next_stage['sim_dir']}`
- Default post-route sim mode: `{post_route_sim['default_mode']}`
- Synth entrypoint: `{generated['yosys_wrapper']}`
- OpenROAD entrypoint: `{generated['openroad_wrapper']}`
- Sim template: `{generated['sim_template']}`

## Hierarchy Breakdown

| Group | Instances | Unique Modules | Memory Instances | Memory Bits |
| --- | ---: | ---: | ---: | ---: |
{os.linesep.join(group_rows)}

## Memory Summary

| Instance Path | Module | Kind | Depth | Width | Bits | Ports |
| --- | --- | --- | ---: | ---: | ---: | --- |
{os.linesep.join(memory_rows)}

## Memory Implementation

| Instance Path | Implementation | Wrapper Strategy | Target Cells |
| --- | --- | --- | --- |
{os.linesep.join(impl_rows)}

- ASIC memory RTL: `{generated['memory_impl_rtl']}`
- Logic RTL filelist: `{generated['rtl_filelist']}`
- Fakeram cells used: `{", ".join(item['cell_name'] + " x" + str(item['total_instances']) for item in fakeram_instances) if fakeram_instances else "none"}`
- Placeholder macros used: `{", ".join(item['cell_name'] + " x" + str(item['total_instances']) for item in placeholder_macros) if placeholder_macros else "none"}`

## Platform Inputs

- Platform root: `{platform_readiness['platform_root']}`
- Missing required platform inputs: `{", ".join(platform_readiness['missing_inputs']) if platform_readiness['missing_inputs'] else "none"}`
- Missing required tools: `{", ".join(platform_readiness['missing_tools']) if platform_readiness['missing_tools'] else "none"}`
{os.linesep.join(f"- Required env `{name}`: {desc}" for name, desc in platform_readiness['required_env'].items())}

## FPGA Baseline

- `core_clk` synthesis baseline: `{baseline['core_clk_period_ns']} ns / {baseline['core_clk_fmax_mhz']} MHz`
- Implemented whole-design baseline: `{baseline['implemented_min_period_ns']} ns / {baseline['implemented_fmax_mhz']} MHz`
- Device: `{baseline['device']}`
- Slices: `{baseline['slices_used']}` / `{baseline['slices_total']}`
- BRAMs: `{baseline['brams_used']}`
- MULT18X18: `{baseline['mult18x18_used']}`
{os.linesep.join(f"- Note: {note}" for note in baseline['notes'])}

## Generated Files

- Yosys hierarchy script: `{generated['yosys_script']}`
- Yosys synth wrapper: `{generated['yosys_wrapper']}`
- OpenROAD script: `{generated['openroad_skeleton']}`
- OpenROAD wrapper: `{generated['openroad_wrapper']}`
- Power estimation script: `{generated['power_estimation_tcl']}`
- Power estimation wrapper: `{generated['power_wrapper']}`
- SDC stub: `{generated['sdc_stub']}`
- Flow manifest: `{generated['flow_manifest']}`
- Macro placement TCL: `{generated['macro_placement_tcl']}`
- PNR README: `{generated['pnr_readme']}`
- Sim README: `{generated['sim_readme']}`

## Artifact Contract

- Memory implementation RTL: `{artifact_paths['memory_impl_rtl']}`
- Placeholder macro LEFs: `{", ".join(artifact_paths['placeholder_macro_lefs'])}`
- Placeholder macro LIBs: `{", ".join(artifact_paths['placeholder_macro_libs'])}`
- Synthesized netlist: `{artifact_paths['synthesized_netlist']}`
- Synthesized design JSON: `{artifact_paths['synthesized_json']}`
- Post-route netlist: `{artifact_paths['post_route_netlist']}`
- Post-route SDF: `{artifact_paths['post_route_sdf']}`
- Post-route SPEF: `{artifact_paths['post_route_spef']}`
- Post-route power report: `{artifact_paths['post_route_power_report']}`

## Area And Power

- Logic area status: `{area['status']}`
- Standard-cell logic area: `{area['logic_area_um2']}`
- Sequential area: `{area['seq_area_um2']}`
- Macro area: `{area['macro_area_um2']}`
- Total area: `{area['total_area_um2']}`
- Utilization: `{area['utilization_pct']}`
- Power report path: `{power['report_path']}`
- Power activity hook env: `{power['activity_hook_env']}`
{os.linesep.join(f"- Power note: {note}" for note in power['notes'])}

## Notes

{os.linesep.join(f"- {note}" for note in assumptions)}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--top-module", default="user_top")
    parser.add_argument("--target-ns", type=float, default=10.0)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--platform", default=DEFAULT_PLATFORM, choices=sorted(PLATFORM_SUPPORT))
    parser.add_argument("--run-yosys", action="store_true", default=False)
    args = parser.parse_args()

    source_files = sorted(SRC_ROOT.rglob("*.v"))
    modules = load_modules(source_files)
    if args.top_module not in modules:
        raise SystemExit(f"top module {args.top_module!r} not found")

    top_module = modules[args.top_module]
    top_env = default_param_env(top_module)
    missing: Dict[str, int] = defaultdict(int)
    root = build_hierarchy(modules, args.top_module, args.top_module, top_env, missing)
    nodes = list(walk_nodes(root))
    memories = build_memory_summary(root)
    grouped = aggregate_groups(root, memories)
    tools = detect_tools()
    baseline = parse_fpga_baseline()
    platform_readiness = describe_platform_readiness(args.platform, tools)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    eval_dir = out_dir
    pnr_dir = ASIC_REPORT_ROOT / "pnr" / args.top_module
    sim_dir = ASIC_REPORT_ROOT / "sim" / args.top_module

    memory_impls = classify_memory_targets(memories)
    memory_modules = sorted({str(item["module_name"]) for item in memories if str(item["module_name"]) in modules})
    memory_source_files = sorted({modules[module_name].file_path for module_name in memory_modules})
    logic_source_files = [path for path in sorted({Path(node.file_path) for node in nodes if node.file_path}) if REPO_ROOT / path not in memory_source_files]
    rtl_filelist = write_filelist(eval_dir / "user_top_logic_sources.f", [REPO_ROOT / path for path in logic_source_files])
    memory_impl_path = write_memory_impl_verilog(eval_dir)
    placeholder_macro_artifacts = write_placeholder_macro_artifacts(eval_dir)
    synth_netlist = eval_dir / "user_top_synth.v"
    synth_json = eval_dir / "user_top_synth.json"
    synth_stat_path = eval_dir / "user_top_synth_stat.rpt"
    synth_check_path = eval_dir / "user_top_synth_check.rpt"
    logic_source_abs = [REPO_ROOT / path for path in logic_source_files]
    macro_placement_tcl = write_macro_placement_tcl(pnr_dir)
    yosys_script = write_yosys_script(eval_dir, rtl_filelist, memory_impl_path, logic_source_abs, args.top_module, args.target_ns, args.platform)
    yosys_wrapper = write_yosys_wrapper(
        eval_dir,
        args.top_module,
        rtl_filelist,
        memory_impl_path,
        logic_source_abs,
        synth_netlist,
        synth_json,
        synth_stat_path,
        synth_check_path,
        args.platform,
    )
    openroad_script = write_openroad_skeleton(
        pnr_dir,
        args.top_module,
        args.target_ns,
        eval_dir,
        args.platform,
        synth_netlist,
        placeholder_macro_artifacts,
        macro_placement_tcl,
    )
    openroad_wrapper = write_openroad_wrapper(pnr_dir, args.platform)
    power_tcl = write_power_estimation_tcl(pnr_dir, args.top_module, eval_dir, args.platform, placeholder_macro_artifacts)
    power_wrapper = write_power_wrapper(pnr_dir)
    sim_script = write_gatelevel_sim_skeleton(sim_dir, args.top_module, pnr_dir)
    pnr_readme = write_pnr_readme(pnr_dir, args.top_module)
    sim_readme = write_sim_readme(sim_dir, args.top_module)
    sdc_path = write_stub_sdc(eval_dir, args.target_ns)
    yosys_run = maybe_run_yosys(tools, yosys_script, out_dir, args.run_yosys)

    excluded_modules = [
        "NetFPGA board shell",
        "reference_core / DMA / MAC / SRAM controllers / DCM / IOB resources",
        "user_data_path outer fabric",
    ]

    included_modules = sorted({node.module_name for node in nodes})
    source_manifest = sorted({node.file_path for node in nodes if node.file_path})
    memory_bits_total = sum(item["bits_total"] for item in memories if isinstance(item["bits_total"], int))
    fakeram_instances = aggregate_memory_targets(memory_impls, "fakeram_wrapper")
    placeholder_macros = aggregate_memory_targets(memory_impls, "placeholder_macro")
    flow_manifest_path = eval_dir / "flow_manifest.json"
    artifact_contract = {
        "rtl_filelist": repo_rel(rtl_filelist),
        "memory_impl_rtl": repo_rel(memory_impl_path),
        "placeholder_macro_libs": [repo_rel(path) for path in placeholder_macro_artifacts["lib"]],
        "placeholder_macro_lefs": [repo_rel(path) for path in placeholder_macro_artifacts["lef"]],
        "macro_placement_tcl": repo_rel(macro_placement_tcl),
        "synthesized_netlist": repo_rel(synth_netlist),
        "synthesized_json": repo_rel(synth_json),
        "synth_stat_report": repo_rel(synth_stat_path),
        "synth_check_report": repo_rel(synth_check_path),
        "post_route_netlist": repo_rel(pnr_dir / "results" / f"{args.top_module}_postroute.v"),
        "post_route_def": repo_rel(pnr_dir / "results" / f"{args.top_module}_postroute.def"),
        "post_route_sdf": repo_rel(pnr_dir / "results" / f"{args.top_module}_postroute.sdf"),
        "post_route_spef": repo_rel(pnr_dir / "results" / f"{args.top_module}_postroute.spef"),
        "post_route_power_report": repo_rel(pnr_dir / "reports" / "4_postroute_power.rpt"),
    }
    flow_results = collect_flow_results(eval_dir, pnr_dir, args.top_module, platform_readiness["status"])
    flow_status = flow_results["flow_status"]

    report: Dict[str, object] = {
        "design_name": args.top_module,
        "top_module": args.top_module,
        "evaluation_scope": "user_module_layer",
        "platform": args.platform,
        "platform_label": PLATFORM_SUPPORT[args.platform]["label"],
        "flow_status": flow_status,
        "artifact_root": repo_rel(ASIC_REPORT_ROOT),
        "included_modules": included_modules,
        "excluded_modules": excluded_modules,
        "missing_modules": dict(sorted(missing.items())),
        "source_manifest": source_manifest,
        "memory_implementation": memory_impls,
        "fakeram_instances": fakeram_instances,
        "placeholder_macros": placeholder_macros,
        "next_stage_paths": {
            "eval_dir": repo_rel(eval_dir),
            "pnr_dir": repo_rel(pnr_dir),
            "sim_dir": repo_rel(sim_dir),
        },
        "clock_constraints": [
            {
                "name": "core_clk",
                "target_ns": args.target_ns,
                "stub_sdc": repo_rel(sdc_path),
            }
        ],
        "memory_summary": memories,
        "memory_bits_total": memory_bits_total,
        "timing_summary": {
            "target_ns": args.target_ns,
            "placement_wns_ns": flow_results["timing_summary"]["placement_wns_ns"],
            "placement_tns_ns": flow_results["timing_summary"]["placement_tns_ns"],
            "cts_wns_ns": flow_results["timing_summary"]["cts_wns_ns"],
            "cts_tns_ns": flow_results["timing_summary"]["cts_tns_ns"],
            "route_wns_ns": flow_results["timing_summary"]["route_wns_ns"],
            "route_tns_ns": flow_results["timing_summary"]["route_tns_ns"],
            "fmax_est_mhz": None,
            "critical_path_from": None,
            "critical_path_to": None,
            "status": flow_results["timing_summary"]["status"],
        },
        "area_summary": {
            "logic_area_um2": flow_results["area_summary"]["logic_area_um2"],
            "seq_area_um2": flow_results["area_summary"]["seq_area_um2"],
            "stdcell_area_um2": flow_results["area_summary"]["stdcell_area_um2"],
            "macro_area_um2": flow_results["area_summary"]["macro_area_um2"],
            "total_area_um2": flow_results["area_summary"]["total_area_um2"],
            "core_area_um2": flow_results["area_summary"]["core_area_um2"],
            "placement_design_area_um2": flow_results["area_summary"]["placement_design_area_um2"],
            "utilization_pct": flow_results["area_summary"]["utilization_pct"],
            "status": flow_results["area_summary"]["status"],
            "by_hierarchy": grouped,
        },
        "power_summary": flow_results["power_summary"],
        "fpga_baseline": baseline,
        "tool_availability": {
            "yosys": tools["yosys"],
            "openroad": tools["openroad"],
            "sta": tools["sta"],
        },
        "platform_readiness": platform_readiness,
        "artifact_contract": artifact_contract,
        "post_route_sim": {
            "default_mode": "gate_level_sdf",
            "required_inputs": [
                "post_route_netlist",
                "post_route_sdf",
                "testbench_entry",
            ],
            "expected_outputs": [
                "sim_log",
                "pass_fail_summary",
                "optional_waveform",
            ],
            "sim_root": repo_rel(sim_dir),
            "post_route_netlist": artifact_contract["post_route_netlist"],
            "post_route_sdf": artifact_contract["post_route_sdf"],
        },
        "generated_artifacts": {
            "yosys_script": repo_rel(yosys_script),
            "yosys_wrapper": repo_rel(yosys_wrapper),
            "openroad_skeleton": repo_rel(openroad_script),
            "openroad_wrapper": repo_rel(openroad_wrapper),
            "power_estimation_tcl": repo_rel(power_tcl),
            "power_wrapper": repo_rel(power_wrapper),
            "pnr_readme": repo_rel(pnr_readme),
            "sim_template": repo_rel(sim_script),
            "sim_readme": repo_rel(sim_readme),
            "sdc_stub": repo_rel(sdc_path),
            "rtl_filelist": repo_rel(rtl_filelist),
            "memory_impl_rtl": repo_rel(memory_impl_path),
            "macro_placement_tcl": repo_rel(macro_placement_tcl),
            "flow_manifest": repo_rel(flow_manifest_path),
            "yosys_run": yosys_run,
        },
        "assumption_notes": [
            "The RSU ASIC pack treats user_top as the primary evaluation boundary.",
            "This flow is pinned to a Nangate45 teaching library baseline, not a signoff PDK.",
            "Small single-port memories are mapped through ASIC-only fakeram wrappers; complex memories stay as placeholder macros.",
            "user_data_path and NetFPGA board-facing modules remain out of the main RSU ASIC result.",
            "generic_regs is included through the local behavioral stub to keep user_top hierarchy closed.",
            f"FPGA baselines come from {repo_rel(FPGA_REPORT_DIR)}.",
        ],
    }

    report_path = eval_dir / "user_top_eval.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=False), encoding="utf-8")
    (eval_dir / "user_top_eval.md").write_text(make_markdown(report), encoding="utf-8")
    (eval_dir / "dependency_manifest.json").write_text(
        json.dumps(
            {
                "top_module": args.top_module,
                "platform": args.platform,
                "artifact_root": repo_rel(ASIC_REPORT_ROOT),
                "eval_dir": repo_rel(eval_dir),
                "pnr_dir": repo_rel(pnr_dir),
                "sim_dir": repo_rel(sim_dir),
                "instance_paths": flatten_paths(root),
                "included_modules": included_modules,
                "source_manifest": source_manifest,
                "logic_source_manifest": [repo_rel(REPO_ROOT / path) for path in logic_source_files],
                "memory_modules": memory_modules,
                "memory_implementation": memory_impls,
                "missing_modules": dict(sorted(missing.items())),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    flow_manifest_path.write_text(
        json.dumps(
            {
                "top_module": args.top_module,
                "platform": args.platform,
                "platform_label": PLATFORM_SUPPORT[args.platform]["label"],
                "clock_target_ns": args.target_ns,
                "logic_rtl_filelist": repo_rel(rtl_filelist),
                "memory_impl_rtl": repo_rel(memory_impl_path),
                "memory_implementation": memory_impls,
                "fakeram_instances": fakeram_instances,
                "placeholder_macros": placeholder_macros,
                "artifact_contract": artifact_contract,
                "required_env": platform_readiness["required_env"],
                "optional_env": platform_readiness["optional_env"],
                "flow_status": flow_status,
                "timing_summary": report["timing_summary"],
                "area_summary": report["area_summary"],
                "power_summary": report["power_summary"],
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"wrote {report_path}")
    print(f"wrote {eval_dir / 'user_top_eval.md'}")
    print(f"wrote {eval_dir / 'dependency_manifest.json'}")
    print(f"wrote {flow_manifest_path}")
    print(f"wrote {yosys_script}")
    print(f"wrote {yosys_wrapper}")
    print(f"wrote {memory_impl_path}")
    print(f"wrote {openroad_script}")
    print(f"wrote {openroad_wrapper}")
    print(f"wrote {power_tcl}")
    print(f"wrote {power_wrapper}")
    for path in placeholder_macro_artifacts["lib"] + placeholder_macro_artifacts["lef"]:
        print(f"wrote {path}")
    print(f"wrote {pnr_readme}")
    print(f"wrote {sim_script}")
    print(f"wrote {sim_readme}")
    print(f"wrote {sdc_path}")
    if yosys_run:
        print("ran yosys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
