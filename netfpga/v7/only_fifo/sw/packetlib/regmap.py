#!/usr/bin/env python

import os
import re

try:
    integer_types = (int, long)
except NameError:
    integer_types = (int,)

DEFINE_RE = re.compile(r"^\s*#define\s+([A-Z0-9_]+)\s+(0x[0-9a-fA-F]+)\s*$")


def _packetlib_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def default_reg_defines_path():
    env_path = os.environ.get("ONLY_FIFO_REG_DEFINES")
    if env_path:
        return env_path

    root = _packetlib_root()
    candidates = [
        os.path.join(root, "reg_defines_onlyfifo.h"),
        os.path.join(root, "config", "reg_defines_onlyfifo.h"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return candidates[0]


def _group_specs():
    return [
        ("USER_TOP", "post"),
        ("USER_PRE_DEBUG", "pre"),
    ]


def _infer_access(symbol):
    if symbol in ("USER_TOP_DEBUG_CTRL_REG", "USER_PRE_DEBUG_DEBUG_CTRL_REG"):
        return "rw"
    if symbol.startswith("USER_TOP_HW_") or symbol.startswith("USER_PRE_DEBUG_HW_"):
        return "ro"
    return "rw"


def _short_name(symbol, prefix):
    short_name = symbol
    prefix_with_sep = prefix + "_"
    if short_name.startswith(prefix_with_sep):
        short_name = short_name[len(prefix_with_sep):]
    if short_name.endswith("_REG"):
        short_name = short_name[:-len("_REG")]
    return short_name.lower()


def _format_hex32(value):
    return "0x%08x" % (value & 0xffffffff)


def _read_define_lines(reg_defines_path):
    handle = open(reg_defines_path, "r")
    try:
        return handle.readlines()
    finally:
        handle.close()


def _load_group_regmap(lines, reg_defines_path, prefix, group_name):
    base_addr = None
    entries = []
    base_symbol = prefix + "_BASE_ADDR"
    prefix_with_sep = prefix + "_"

    for line in lines:
        match = DEFINE_RE.match(line)
        if not match:
            continue

        symbol = match.group(1)
        value = int(match.group(2), 16)

        if symbol == base_symbol:
            base_addr = value
            continue

        if not symbol.startswith(prefix_with_sep) or not symbol.endswith("_REG"):
            continue

        entry = {
            "group": group_name,
            "symbol": symbol,
            "short": _short_name(symbol, prefix),
            "access": _infer_access(symbol),
            "addr": value,
            "addr_text": _format_hex32(value),
        }
        entry["qualified_short"] = group_name + "." + entry["short"]
        entries.append(entry)

    entries.sort(key=lambda item: item["addr"])
    by_symbol = {}
    by_short = {}
    by_addr = {}
    for entry in entries:
        by_symbol[entry["symbol"]] = entry
        by_short[entry["short"]] = entry
        by_short[entry["qualified_short"]] = entry
        by_addr[entry["addr"]] = entry

    if base_addr is None:
        base_addr_text = None
    else:
        base_addr_text = _format_hex32(base_addr)

    result = {
        "group": group_name,
        "prefix": prefix,
        "reg_defines_path": reg_defines_path,
        "base_addr": base_addr,
        "base_addr_text": base_addr_text,
        "entries": entries,
        "by_symbol": by_symbol,
        "by_short": by_short,
        "by_addr": by_addr,
    }
    return result


def load_only_fifo_regmap(reg_defines_path=None):
    if reg_defines_path is None:
        reg_defines_path = default_reg_defines_path()

    lines = _read_define_lines(reg_defines_path)
    groups = {}
    all_entries = []
    short_counts = {}

    for prefix, group_name in _group_specs():
        group = _load_group_regmap(lines, reg_defines_path, prefix, group_name)
        groups[group_name] = group
        all_entries.extend(group["entries"])
        for entry in group["entries"]:
            count = short_counts.get(entry["short"], 0)
            short_counts[entry["short"]] = count + 1

    all_entries.sort(key=lambda item: item["addr"])
    by_symbol = {}
    by_short = {}
    by_addr = {}
    for entry in all_entries:
        by_symbol[entry["symbol"]] = entry
        by_short[entry["qualified_short"]] = entry
        if short_counts.get(entry["short"], 0) == 1:
            by_short[entry["short"]] = entry
        by_addr[entry["addr"]] = entry

    return {
        "reg_defines_path": reg_defines_path,
        "groups": groups,
        "entries": all_entries,
        "by_symbol": by_symbol,
        "by_short": by_short,
        "by_addr": by_addr,
    }


def load_user_top_regmap(reg_defines_path=None):
    return load_only_fifo_regmap(reg_defines_path)["groups"]["post"]


def load_user_pre_debug_regmap(reg_defines_path=None):
    return load_only_fifo_regmap(reg_defines_path)["groups"]["pre"]


def resolve_register(token, regmap):
    if token is None:
        raise ValueError("missing register token")

    if isinstance(token, integer_types):
        addr = int(token)
    else:
        text = str(token).strip()
        if text in regmap["by_symbol"]:
            return regmap["by_symbol"][text]
        if text in regmap["by_short"]:
            return regmap["by_short"][text]
        try:
            addr = int(text, 0)
        except ValueError:
            raise ValueError("unknown register token: %s" % token)

    if addr in regmap["by_addr"]:
        return regmap["by_addr"][addr]

    return {
        "group": None,
        "symbol": None,
        "short": None,
        "qualified_short": None,
        "access": "unknown",
        "addr": addr,
        "addr_text": _format_hex32(addr),
    }


def resolve_user_top_register(token, regmap):
    return resolve_register(token, regmap)


def debug_snapshot_registers(regmap):
    wanted = [
        "debug_ctrl",
        "hw_last_action",
        "hw_offload_match_count",
        "hw_rewrite_fire_count",
        "hw_last_udp_dst_port",
        "hw_last_payload_magic",
        "hw_last_header_word5_hi",
        "hw_last_header_word5_lo",
        "hw_last_header_word6_hi",
        "hw_last_header_word6_lo",
        "hw_last_rewrite_word_hi",
        "hw_last_rewrite_word_lo",
    ]
    result = []
    for short_name in wanted:
        result.append(resolve_register(short_name, regmap))
    return result


def pre_debug_snapshot_registers(regmap):
    wanted = [
        "debug_ctrl",
        "hw_status",
        "hw_last_ctrl_pack_0",
        "hw_last_ctrl_pack_1",
        "hw_last_word0_hi",
        "hw_last_word0_lo",
        "hw_last_word1_hi",
        "hw_last_word1_lo",
        "hw_last_word2_hi",
        "hw_last_word2_lo",
        "hw_last_word3_hi",
        "hw_last_word3_lo",
        "hw_last_word4_hi",
        "hw_last_word4_lo",
        "hw_last_word5_hi",
        "hw_last_word5_lo",
    ]
    result = []
    for short_name in wanted:
        result.append(resolve_register(short_name, regmap))
    return result
