#!/usr/bin/env python

from optparse import OptionParser

from packetlib import json_compat
from packetlib.reg_access import RegisterAccessor
from packetlib.regmap import (
    debug_snapshot_registers,
    load_only_fifo_regmap,
    pre_debug_snapshot_registers,
    resolve_register,
)


ACTION_NAMES = {
    0: "bypass",
    2: "offload",
}


def _format_hex32(value):
    return "0x%08x" % (value & 0xffffffff)


def _format_hex64(value):
    return "0x%016x" % (value & 0xffffffffffffffff)


def _write_line(text):
    import sys

    sys.stdout.write(text + "\n")


def _build_common_parser(usage, description):
    parser = OptionParser(usage=usage, description=description)
    parser.add_option("--reg-defines", dest="reg_defines")
    parser.add_option("--regread-bin", dest="regread_bin")
    parser.add_option("--regwrite-bin", dest="regwrite_bin")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    return parser


def _load_context(options):
    regmap = load_only_fifo_regmap(options.reg_defines)
    accessor = RegisterAccessor(
        regread_bin=options.regread_bin,
        regwrite_bin=options.regwrite_bin,
    )
    return regmap, accessor


def _render_reg_entry(entry):
    label = entry.get("qualified_short") or entry.get("short")
    return "%s %s %s %s" % (
        entry["addr_text"],
        entry["access"],
        label,
        entry["symbol"],
    )


def _read_entry(accessor, entry):
    value = accessor.read_reg(entry["addr"])
    result = {
        "addr": entry["addr_text"],
        "access": entry["access"],
        "group": entry.get("group"),
        "short": entry.get("short"),
        "qualified_short": entry.get("qualified_short"),
        "symbol": entry["symbol"],
        "value": _format_hex32(value),
        "value_int": value,
    }
    return result


def _combine_words(hi_value, lo_value):
    return ((hi_value & 0xffffffff) << 32) | (lo_value & 0xffffffff)


def _snapshot_post_payload(regmap, accessor):
    read_values = {}
    for entry in debug_snapshot_registers(regmap):
        read_values[entry["short"]] = _read_entry(accessor, entry)

    last_action_value = read_values["hw_last_action"]["value_int"]
    snapshot = {
        "group": "post",
        "reg_defines_path": regmap["reg_defines_path"],
        "base_addr": regmap["base_addr_text"],
        "last_action": {
            "value": read_values["hw_last_action"]["value"],
            "value_int": last_action_value,
            "name": ACTION_NAMES.get(last_action_value, "unknown"),
        },
        "offload_match_count": read_values["hw_offload_match_count"]["value_int"],
        "rewrite_fire_count": read_values["hw_rewrite_fire_count"]["value_int"],
        "last_udp_dst_port": {
            "value": read_values["hw_last_udp_dst_port"]["value"],
            "value_int": read_values["hw_last_udp_dst_port"]["value_int"] & 0xffff,
        },
        "last_payload_magic": {
            "value": read_values["hw_last_payload_magic"]["value"],
            "value_int": read_values["hw_last_payload_magic"]["value_int"] & 0xffff,
        },
        "last_header_word5": _format_hex64(
            _combine_words(
                read_values["hw_last_header_word5_hi"]["value_int"],
                read_values["hw_last_header_word5_lo"]["value_int"],
            )
        ),
        "last_header_word6": _format_hex64(
            _combine_words(
                read_values["hw_last_header_word6_hi"]["value_int"],
                read_values["hw_last_header_word6_lo"]["value_int"],
            )
        ),
        "last_rewrite_word": _format_hex64(
            _combine_words(
                read_values["hw_last_rewrite_word_hi"]["value_int"],
                read_values["hw_last_rewrite_word_lo"]["value_int"],
            )
        ),
        "raw_registers": read_values,
    }
    return snapshot


def _snapshot_pre_payload(regmap, accessor):
    read_values = {}
    for entry in pre_debug_snapshot_registers(regmap):
        read_values[entry["short"]] = _read_entry(accessor, entry)

    status_value = read_values["hw_status"]["value_int"]
    ctrl_pack_0_value = read_values["hw_last_ctrl_pack_0"]["value_int"]
    ctrl_pack_1_value = read_values["hw_last_ctrl_pack_1"]["value_int"]
    last_ctrl = [
        ctrl_pack_0_value & 0xff,
        (ctrl_pack_0_value >> 8) & 0xff,
        (ctrl_pack_0_value >> 16) & 0xff,
        (ctrl_pack_0_value >> 24) & 0xff,
        ctrl_pack_1_value & 0xff,
        (ctrl_pack_1_value >> 8) & 0xff,
    ]
    last_words = []
    word_index = 0
    while word_index < 6:
        hi_key = "hw_last_word%d_hi" % word_index
        lo_key = "hw_last_word%d_lo" % word_index
        last_words.append(
            _format_hex64(
                _combine_words(
                    read_values[hi_key]["value_int"],
                    read_values[lo_key]["value_int"],
                )
            )
        )
        word_index += 1

    snapshot_valid = 0
    capture_active = 0
    capture_done = 0
    if status_value & 0x1:
        snapshot_valid = 1
    if status_value & 0x2:
        capture_active = 1
    if status_value & 0x4:
        capture_done = 1

    snapshot = {
        "group": "pre",
        "reg_defines_path": regmap["reg_defines_path"],
        "base_addr": regmap["base_addr_text"],
        "snapshot_valid": snapshot_valid,
        "capture_active": capture_active,
        "capture_done": capture_done,
        "last_word_count": (status_value >> 8) & 0xff,
        "pkt_seen_count": (status_value >> 16) & 0xffff,
        "last_ctrl": last_ctrl,
        "last_words": last_words,
        "raw_registers": read_values,
    }
    return snapshot


def _render_post_snapshot(snapshot):
    _write_line("last_action=%s (%s)" % (snapshot["last_action"]["name"], snapshot["last_action"]["value"]))
    _write_line("offload_match_count=%d" % snapshot["offload_match_count"])
    _write_line("rewrite_fire_count=%d" % snapshot["rewrite_fire_count"])
    _write_line("last_udp_dst_port=%s" % snapshot["last_udp_dst_port"]["value"])
    _write_line("last_payload_magic=%s" % snapshot["last_payload_magic"]["value"])
    _write_line("last_header_word5=%s" % snapshot["last_header_word5"])
    _write_line("last_header_word6=%s" % snapshot["last_header_word6"])
    _write_line("last_rewrite_word=%s" % snapshot["last_rewrite_word"])


def _render_pre_snapshot(snapshot):
    _write_line(
        "snapshot_valid=%d capture_active=%d capture_done=%d pkt_seen_count=%d last_word_count=%d" % (
            snapshot["snapshot_valid"],
            snapshot["capture_active"],
            snapshot["capture_done"],
            snapshot["pkt_seen_count"],
            snapshot["last_word_count"],
        )
    )
    ctrl_index = 0
    while ctrl_index < len(snapshot["last_ctrl"]):
        _write_line("last_ctrl%d=0x%02x" % (ctrl_index, snapshot["last_ctrl"][ctrl_index]))
        ctrl_index += 1
    word_index = 0
    while word_index < len(snapshot["last_words"]):
        _write_line("last_word%d=%s" % (word_index, snapshot["last_words"][word_index]))
        word_index += 1


def _clear_debug_state(regmap, accessor):
    cleared = []
    group_name = None
    for group_name in ("post", "pre"):
        ctrl_entry = resolve_register("debug_ctrl", regmap["groups"][group_name])
        accessor.write_reg(ctrl_entry["addr"], 1)
        accessor.write_reg(ctrl_entry["addr"], 0)
        cleared.append(
            {
                "group": group_name,
                "register": ctrl_entry["symbol"],
                "addr": ctrl_entry["addr_text"],
            }
        )
    return cleared


def main_pktctl(argv=None):
    import sys

    if argv is None:
        argv = sys.argv[1:]

    if not argv:
        _write_line("usage: pktctl <regs|stats|pre|post|snapshot|diagnose> ...")
        return 1

    category = argv[0]
    sub_argv = argv[1:]

    if category == "regs":
        return _main_regs(sub_argv)
    if category == "stats":
        return _main_stats(sub_argv)
    if category == "pre":
        return _main_pre(sub_argv)
    if category == "post":
        return _main_post(sub_argv)
    if category == "snapshot":
        return _main_snapshot(sub_argv)
    if category == "diagnose":
        return _main_diagnose(sub_argv)

    _write_line("unknown pktctl category: %s" % category)
    return 1


def _main_regs(argv):
    if not argv:
        _write_line("usage: pktctl regs <list|read|dump> ...")
        return 1

    command = argv[0]
    sub_argv = argv[1:]

    if command == "list":
        parser = _build_common_parser("%prog regs list [options]", "List only_fifo pre/post debug registers.")
        options, args = parser.parse_args(sub_argv)
        if args:
            parser.error("unexpected positional arguments: %s" % " ".join(args))
        regmap, accessor = _load_context(options)
        del accessor
        if options.dump_json:
            _write_line(json_compat.dumps(regmap["entries"], indent=2, sort_keys=True))
            return 0
        for entry in regmap["entries"]:
            _write_line(_render_reg_entry(entry))
        return 0

    if command == "read":
        parser = _build_common_parser("%prog regs read <symbol|addr> [options]", "Read one only_fifo debug register.")
        options, args = parser.parse_args(sub_argv)
        if len(args) != 1:
            parser.error("expected one register token")
        regmap, accessor = _load_context(options)
        entry = resolve_register(args[0], regmap)
        result = _read_entry(accessor, entry)
        if options.dump_json:
            _write_line(json_compat.dumps(result, indent=2, sort_keys=True))
            return 0
        label = entry["symbol"] or entry["addr_text"]
        _write_line("%s %s" % (label, result["value"]))
        return 0

    if command == "dump":
        parser = _build_common_parser("%prog regs dump [options]", "Read all only_fifo debug registers.")
        options, args = parser.parse_args(sub_argv)
        if args:
            parser.error("unexpected positional arguments: %s" % " ".join(args))
        regmap, accessor = _load_context(options)
        results = []
        for entry in regmap["entries"]:
            results.append(_read_entry(accessor, entry))
        if options.dump_json:
            _write_line(json_compat.dumps(results, indent=2, sort_keys=True))
            return 0
        for result in results:
            _write_line("%s %s" % (result["symbol"], result["value"]))
        return 0

    _write_line("unknown pktctl regs command: %s" % command)
    return 1


def _main_stats(argv):
    if not argv:
        _write_line("usage: pktctl stats <clear|snapshot> ...")
        return 1

    command = argv[0]
    sub_argv = argv[1:]

    if command == "clear":
        parser = _build_common_parser("%prog stats clear [options]", "Clear only_fifo pre/post debug counters and snapshots.")
        options, args = parser.parse_args(sub_argv)
        if args:
            parser.error("unexpected positional arguments: %s" % " ".join(args))
        regmap, accessor = _load_context(options)
        cleared = _clear_debug_state(regmap, accessor)
        result = {
            "cleared": True,
            "registers": cleared,
        }
        if options.dump_json:
            _write_line(json_compat.dumps(result, indent=2, sort_keys=True))
            return 0
        _write_line("cleared only_fifo debug stats via %s, %s" % (cleared[0]["register"], cleared[1]["register"]))
        return 0

    if command == "snapshot":
        parser = _build_common_parser("%prog stats snapshot [options]", "Read only_fifo post-user_top debug snapshot registers.")
        options, args = parser.parse_args(sub_argv)
        if args:
            parser.error("unexpected positional arguments: %s" % " ".join(args))
        regmap, accessor = _load_context(options)
        snapshot = _snapshot_post_payload(regmap["groups"]["post"], accessor)
        if options.dump_json:
            _write_line(json_compat.dumps(snapshot, indent=2, sort_keys=True))
            return 0
        _render_post_snapshot(snapshot)
        return 0

    _write_line("unknown pktctl stats command: %s" % command)
    return 1


def _main_pre(argv):
    if not argv or argv[0] != "snapshot":
        _write_line("usage: pktctl pre snapshot [options]")
        return 1
    parser = _build_common_parser("%prog pre snapshot [options]", "Read only_fifo pre-user_top debug snapshot registers.")
    options, args = parser.parse_args(argv[1:])
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    regmap, accessor = _load_context(options)
    snapshot = _snapshot_pre_payload(regmap["groups"]["pre"], accessor)
    if options.dump_json:
        _write_line(json_compat.dumps(snapshot, indent=2, sort_keys=True))
        return 0
    _render_pre_snapshot(snapshot)
    return 0


def _main_post(argv):
    if not argv or argv[0] != "snapshot":
        _write_line("usage: pktctl post snapshot [options]")
        return 1
    parser = _build_common_parser("%prog post snapshot [options]", "Read only_fifo post-user_top debug snapshot registers.")
    options, args = parser.parse_args(argv[1:])
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    regmap, accessor = _load_context(options)
    snapshot = _snapshot_post_payload(regmap["groups"]["post"], accessor)
    if options.dump_json:
        _write_line(json_compat.dumps(snapshot, indent=2, sort_keys=True))
        return 0
    _render_post_snapshot(snapshot)
    return 0


def _main_snapshot(argv):
    if not argv or argv[0] != "all":
        _write_line("usage: pktctl snapshot all [options]")
        return 1
    parser = _build_common_parser("%prog snapshot all [options]", "Read both pre-user_top and post-user_top debug snapshots.")
    options, args = parser.parse_args(argv[1:])
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    regmap, accessor = _load_context(options)
    payload = {
        "pre": _snapshot_pre_payload(regmap["groups"]["pre"], accessor),
        "post": _snapshot_post_payload(regmap["groups"]["post"], accessor),
    }
    if options.dump_json:
        _write_line(json_compat.dumps(payload, indent=2, sort_keys=True))
        return 0
    _write_line("[pre]")
    _render_pre_snapshot(payload["pre"])
    _write_line("[post]")
    _render_post_snapshot(payload["post"])
    return 0


def _diagnose_payload(pre, post):
    ANN_UDP_DST_PORT = 0x88B5
    ANN_TASK_MAGIC = 0xA11E
    OFFLOAD_RESULT_MAGIC = 0xF11E
    checks = []
    verdict = "PASS"

    def check(name, ok, got, expected):
        status = "FAIL"
        if ok:
            status = "OK"
        checks.append({"name": name, "ok": ok, "got": got, "expected": expected, "status": status})

    if not pre.get("snapshot_valid"):
        check("pkt_seen", False, 0, 1)
        verdict = "FAIL"
        return {"checks": checks, "verdict": verdict, "pre": pre, "post": post}

    words = pre.get("last_words", [])

    def _hi_lo_word(idx):
        if idx < len(words):
            val = int(words[idx], 16)
            return val
        return 0

    w2 = _hi_lo_word(2)
    w3 = _hi_lo_word(3)
    w5 = _hi_lo_word(5)
    ethertype = (w2 >> 16) & 0xFFFF
    ip_proto = w3 & 0xFF
    udp_dst = (w5 >> 16) & 0xFFFF
    magic_in = post["last_payload_magic"]["value_int"] & 0xFFFF

    check("EtherType=0x0800", ethertype == 0x0800, "0x%04x" % ethertype, "0x0800")
    check("IP proto=0x11 (UDP)", ip_proto == 0x11, "0x%02x" % ip_proto, "0x11")
    check("UDP dst=0x88B5", udp_dst == ANN_UDP_DST_PORT, "0x%04x" % udp_dst, "0x%04x" % ANN_UDP_DST_PORT)
    check("magic=0xA11E", magic_in == ANN_TASK_MAGIC, "0x%04x" % magic_in, "0x%04x" % ANN_TASK_MAGIC)

    post_action = post["last_action"]["name"]
    check("last_action=offload", post_action == "offload", post_action, "offload")
    check("offload_match_count>=1", post["offload_match_count"] >= 1, post["offload_match_count"], ">=1")
    check("rewrite_fire_count>=1", post["rewrite_fire_count"] >= 1, post["rewrite_fire_count"], ">=1")

    rewrite_hi = int(post["last_rewrite_word"][2:10], 16)
    rewrite_magic = rewrite_hi & 0xFFFF
    check("rewrite magic=0xF11E", rewrite_magic == OFFLOAD_RESULT_MAGIC, "0x%04x" % rewrite_magic, "0x%04x" % OFFLOAD_RESULT_MAGIC)

    for c in checks:
        if not c["ok"]:
            verdict = "FAIL"
            break

    return {"checks": checks, "verdict": verdict, "pre": pre, "post": post}


def _render_diagnose(result):
    for c in result["checks"]:
        _write_line("%s=%s (got %s, expected %s)" % (c["name"], c["status"], c["got"], c["expected"]))
    _write_line("VERDICT: %s" % result["verdict"])


def _main_diagnose(argv):
    parser = _build_common_parser("%prog diagnose [options]", "Diagnose only_fifo L4 offload classification on board.")
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    regmap, accessor = _load_context(options)
    pre = _snapshot_pre_payload(regmap["groups"]["pre"], accessor)
    post = _snapshot_post_payload(regmap["groups"]["post"], accessor)
    result = _diagnose_payload(pre, post)
    if options.dump_json:
        _write_line(json_compat.dumps(result, indent=2, sort_keys=True))
        return 0
    _render_diagnose(result)
    if result["verdict"] == "PASS":
        return 0
    return 1
