#!/usr/bin/env python3

import argparse
import json
import shutil
import sys
import textwrap
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import board_metrics
import board_sweep
from board_debug.ann_packets import build_udp_frame_defaults, inspect_ann_frame
from board_debug.pcap_io import read_pcap_records, write_pcap


DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_demo_protocol.json"
DEFAULT_REQUEST_ID_BASE = "0x1100"
DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS = 2.0
DEFAULT_BYPASS_UDP_DST_PORT = 0x7777
DEFAULT_BYPASS_PAYLOAD_HEX = "44454d4f5f425950415353"
DEFAULT_TERM_WIDTH = 100
TERM_WIDTH_CAP = 100
DEFAULT_HEX_CHUNK = 64
PROTOCOL_SUMMARY_JSON = "protocol_demo_summary.json"
PROTOCOL_SUMMARY_MD = "protocol_demo_summary.md"
STEP_ORDER = ["bypass", "wrong_magic", "offload"]
STEP_VARIANTS = {
    "bypass": "bypass",
    "wrong_magic": "wrong_magic",
    "offload": "offload",
}
STEP_LABELS = {
    "bypass": "Bypass Gate",
    "wrong_magic": "Payload Gate",
    "offload": "Accepted Compute",
}


def _load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def _write_text(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _write_shell(path, text):
    _write_text(path, text)
    path = Path(path)
    path.chmod(0o755)


def _parse_int(value):
    return int(str(value), 0)


def _normalize_hex_string(value, field_name):
    text = str(value).strip().lower()
    if text.startswith("0x"):
        text = text[2:]
    if not text or (len(text) % 2) != 0:
        raise SystemExit("%s must contain an even number of hex digits" % field_name)
    try:
        int(text, 16)
    except ValueError as exc:
        raise SystemExit("invalid %s hex string: %s" % (field_name, value)) from exc
    return text


def _status_word(passed):
    return "PASS" if passed else "FAIL"


def _term_width():
    return min(shutil.get_terminal_size((DEFAULT_TERM_WIDTH, 20)).columns, TERM_WIDTH_CAP)


def _print_separator(char="=", width=None):
    width = width or _term_width()
    print(char * width)


def _print_kv(key, value, indent=0, key_width=17):
    prefix = " " * int(indent)
    print("%s%-*s : %s" % (prefix, int(key_width), str(key), str(value)))


def _print_wrapped_kv(key, value, indent=0, key_width=17, width=None):
    width = width or _term_width()
    prefix = " " * int(indent)
    label = "%s%-*s : " % (prefix, int(key_width), str(key))
    available_width = max(width - len(label), 20)
    text = str(value) if value is not None else ""
    wrapped = textwrap.wrap(text, width=available_width) or [""]
    print(label + wrapped[0])
    continuation_prefix = " " * len(label)
    for line in wrapped[1:]:
        print(continuation_prefix + line)


def _print_hex_block(hex_string, indent=6, chunk=DEFAULT_HEX_CHUNK):
    prefix = " " * int(indent)
    if not hex_string:
        print(prefix + "unavailable")
        return
    text = "".join(str(hex_string).split())
    for start in range(0, len(text), int(chunk)):
        print(prefix + text[start : start + int(chunk)])


def _display_packet_key(key):
    mapping = {
        "wire_result_data_0_u16": "wire_result_data_0",
        "wire_result_data_1_u16": "wire_result_data_1",
    }
    return mapping.get(key, key)


def _metadata_rows(summary):
    if not summary:
        return []
    ordered_keys = (
        "frame_kind",
        "request_id",
        "payload_magic",
        "udp_dst_port",
        "payload_len",
        "wire_result_data_0_u16",
        "wire_result_data_1_u16",
        "predicted_class",
        "predicted_score_s16",
    )
    rows = []
    for key in ordered_keys:
        if key in summary and summary[key] is not None:
            rows.append((_display_packet_key(key), str(summary[key])))
    return rows


def _print_packet(title, metadata_dict, hex_string, indent=2, width=None):
    width = width or _term_width()
    print("%s%s:" % (" " * int(indent), title))
    rows = _metadata_rows(metadata_dict)
    if rows:
        for key, value in rows:
            _print_wrapped_kv(key, value, indent=indent + 2, key_width=20, width=width)
    else:
        print("%spacket detail unavailable" % (" " * (indent + 2)))
    print("%shex:" % (" " * (indent + 2)))
    _print_hex_block(hex_string, indent=indent + 4, chunk=DEFAULT_HEX_CHUNK)


def _format_request_id(value):
    if value is None:
        return None
    if isinstance(value, str):
        try:
            return "0x%04x" % int(value, 0)
        except ValueError:
            return value
    if isinstance(value, int):
        return "0x%04x" % (value & 0xFFFF)
    return str(value)


def _normalize_packet_summary(row):
    if row is None:
        return None
    summary = {}
    for key in (
        "frame_kind",
        "payload_magic",
        "udp_dst_port",
        "payload_len",
        "wire_result_data_0_u16",
        "wire_result_data_1_u16",
        "predicted_class",
        "predicted_score_s16",
    ):
        if row.get(key) is not None:
            summary[key] = row.get(key)
    request_id = _format_request_id(row.get("request_id"))
    if request_id is not None:
        summary["request_id"] = request_id
    return summary or None


def _read_first_capture_packet(path, result_mode):
    packet_path = Path(path)
    if not packet_path.exists():
        return None
    records = read_pcap_records(packet_path)
    if not records:
        return None
    row = inspect_ann_frame(records[0]["frame"], result_mode)
    return {
        "summary": _normalize_packet_summary(row),
        "wire_frame_hex": row.get("wire_frame_hex"),
        "payload_hex": row.get("payload_hex"),
    }


def _protocol_capture_filter(manifest):
    return "udp and src host {src_ip} and dst host {dst_ip}".format(
        src_ip=manifest["network"]["src_ip"],
        dst_ip=manifest["network"]["dst_ip"],
    )


def _load_protocol_defaults(config_path):
    config = _load_json(config_path)
    if not isinstance(config, dict):
        raise SystemExit("protocol demo config must be a JSON object")
    defaults = board_sweep._normalize_defaults(config, config_path.parent)
    bypass_payload_hex = _normalize_hex_string(
        config.get("bypass_payload_hex", DEFAULT_BYPASS_PAYLOAD_HEX),
        "bypass_payload_hex",
    )
    return {
        "config_path": str(config_path),
        "runner_defaults": defaults,
        "request_id_base": str(config.get("request_id_base", DEFAULT_REQUEST_ID_BASE)),
        "single_result_timeout_seconds": float(
            config.get("single_result_timeout_seconds", DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS)
        ),
        "bypass_udp_dst_port": int(
            str(config.get("bypass_udp_dst_port", "0x%04x" % DEFAULT_BYPASS_UDP_DST_PORT)),
            0,
        ),
        "bypass_payload_hex": bypass_payload_hex,
    }


def _runner_defaults_from_manifest(manifest):
    defaults = board_sweep._normalize_defaults({}, ROOT_DIR)
    protocol = manifest.get("protocol_demo", {})
    usc = manifest["usc"]
    network = manifest["network"]
    defaults.update(
        {
            "model": manifest["model"]["source"],
            "bitfile": manifest["bitfile"],
            "ssh_mode": str(protocol.get("ssh_mode", defaults["ssh_mode"])),
            "netfpga_host": usc["netfpga_host"],
            "sender_host": usc["sender_host"],
            "receiver_host": usc["receiver_host"],
            "sender_iface": usc["sender_iface"],
            "receiver_iface": usc["receiver_iface"],
            "pre_capture_delay_seconds": float(
                protocol.get("pre_capture_delay_seconds", defaults["pre_capture_delay_seconds"])
            ),
            "capture_ready_delay_seconds": float(
                protocol.get("capture_ready_delay_seconds", defaults["capture_ready_delay_seconds"])
            ),
            "dst_mac": network["dst_mac"],
            "src_mac": network["src_mac"],
            "src_ip": network["src_ip"],
            "dst_ip": network["dst_ip"],
            "src_udp_port": network["src_udp_port"],
            "dst_udp_port": network["dst_udp_port"],
            "task_type": network["task_type"],
        }
    )
    defaults["password_file"] = None
    return defaults


def _resolve_password(defaults, password_file):
    defaults = dict(defaults)
    defaults["password_file"] = password_file if password_file is not None else defaults.get("password_file")
    board_sweep._ensure_local_dependency("ssh")
    board_sweep._ensure_local_dependency("scp")
    if defaults["ssh_mode"] == "sshpass":
        board_sweep._ensure_local_dependency("sshpass")
    return board_sweep._resolve_password(defaults["ssh_mode"], defaults.get("password_file"))


def _init_experiment(run_name, protocol_defaults):
    return {
        "run_name": run_name,
        "prepare_limit": 1,
        "sample_pool_mode": "truncate",
        "prepare_request_id_base": str(protocol_defaults["request_id_base"]),
        "prepare_batch_time_window_seconds": float(protocol_defaults["single_result_timeout_seconds"]),
        "mode": "latency_single",
    }


def _render_protocol_bypass_scripts(manifest):
    usc = manifest["usc"]
    protocol = manifest["protocol_demo"]
    bypass_pcap = protocol["artifacts"]["bypass_pcap"]
    bypass_capture = protocol["artifacts"]["bypass_capture"]
    sender_pcap_root = board_sweep._shell_remote_path("%s/pcaps" % usc["remote_sender_root"])
    capture_path = board_sweep._shell_remote_path("%s/%s" % (usc["remote_receiver_root"], bypass_capture))
    capture_filter = _protocol_capture_filter(manifest)
    return {
        "nf1_capture_protocol_bypass.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c 1 '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=board_sweep._shell_remote_path("%s/captures" % usc["remote_receiver_root"]),
            capture_path=capture_path,
            iface=usc["receiver_iface"],
            capture_filter=capture_filter,
        ),
        "nf4_replay_protocol_bypass.sh": """#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"
""".format(
            iface=usc["sender_iface"],
            pcap_path="%s/%s" % (sender_pcap_root, Path(bypass_pcap).name),
        ),
    }


def _augment_manifest_for_protocol_demo(run_dir, manifest, protocol_defaults):
    bypass_pcap = run_dir / "pcaps" / "protocol_bypass.pcap"
    bypass_payload = bytes.fromhex(protocol_defaults["bypass_payload_hex"])
    bypass_frame, bypass_meta = build_udp_frame_defaults(
        payload=bypass_payload,
        dst_mac=manifest["network"]["dst_mac"],
        src_mac=manifest["network"]["src_mac"],
        src_ip=manifest["network"]["src_ip"],
        dst_ip=manifest["network"]["dst_ip"],
        udp_src_port=_parse_int(manifest["network"]["src_udp_port"]),
        udp_dst_port=int(protocol_defaults["bypass_udp_dst_port"]),
    )
    write_pcap(bypass_pcap, [bypass_frame])

    protocol_section = {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "config_path": str(protocol_defaults["config_path"]),
        "ssh_mode": protocol_defaults["runner_defaults"]["ssh_mode"],
        "pre_capture_delay_seconds": float(protocol_defaults["runner_defaults"]["pre_capture_delay_seconds"]),
        "capture_ready_delay_seconds": float(protocol_defaults["runner_defaults"]["capture_ready_delay_seconds"]),
        "single_result_timeout_seconds": float(protocol_defaults["single_result_timeout_seconds"]),
        "request_id_base": str(protocol_defaults["request_id_base"]),
        "bypass_udp_dst_port": "0x%04x" % int(protocol_defaults["bypass_udp_dst_port"]),
        "bypass_payload_hex": str(protocol_defaults["bypass_payload_hex"]),
        "artifacts": {
            "bypass_pcap": board_sweep._relpath(bypass_pcap, run_dir),
            "bypass_capture": "captures/protocol_bypass.cap",
            "summary_json": PROTOCOL_SUMMARY_JSON,
            "summary_md": PROTOCOL_SUMMARY_MD,
        },
        "bypass_packet_metadata": bypass_meta,
        "steps": list(STEP_ORDER),
    }
    manifest["protocol_demo"] = protocol_section
    manifest["artifacts"]["protocol_bypass_pcap"] = protocol_section["artifacts"]["bypass_pcap"]

    scripts = _render_protocol_bypass_scripts(manifest)
    for name, content in scripts.items():
        _write_shell(run_dir / "commands" / name, content)


def _step_summary_paths(run_dir, step_name):
    return (
        run_dir / ("protocol_%s_summary.json" % step_name),
        run_dir / ("protocol_%s_summary.md" % step_name),
    )


def _protocol_state(run_dir):
    return run_dir / PROTOCOL_SUMMARY_JSON


def _base_protocol_summary(run_dir, manifest):
    protocol = manifest.get("protocol_demo", {})
    return {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "run_dir": str(run_dir),
        "run_name": manifest["run_name"],
        "config_path": protocol.get("config_path"),
        "steps_expected": list(protocol.get("steps", STEP_ORDER)),
        "steps_completed": [],
        "steps_passed": 0,
        "steps_failed": 0,
        "overall_verdict": "incomplete",
        "steps": {},
    }


def _load_or_init_protocol_summary(run_dir, manifest):
    summary_path = _protocol_state(run_dir)
    if summary_path.exists():
        return _load_json(summary_path)
    return _base_protocol_summary(run_dir, manifest)


def _render_protocol_summary_markdown(summary):
    lines = [
        "# Protocol Demo Summary",
        "",
        "- run_name: `%s`" % summary.get("run_name"),
        "- run_dir: `%s`" % summary.get("run_dir"),
        "- config_path: `%s`" % summary.get("config_path"),
        "- steps_completed: `%s`" % len(summary.get("steps_completed", [])),
        "- steps_passed: `%s`" % summary.get("steps_passed", 0),
        "- steps_failed: `%s`" % summary.get("steps_failed", 0),
        "- overall_verdict: `%s`" % str(summary.get("overall_verdict", "incomplete")).upper(),
        "",
        "| Step | Status | Summary |",
        "| --- | --- | --- |",
    ]
    for step_name in summary.get("steps_expected", STEP_ORDER):
        item = summary.get("steps", {}).get(step_name)
        if item is None:
            lines.append("| %s | pending | - |" % step_name)
            continue
        lines.append(
            "| %s | %s | `%s` |" % (
                step_name,
                str(item.get("protocol_verdict", "fail")).upper(),
                item.get("summary_md", "-"),
            )
        )
    return "\n".join(lines) + "\n"


def _update_protocol_summary(run_dir, manifest, step_summary):
    summary = _load_or_init_protocol_summary(run_dir, manifest)
    summary["updated_at"] = datetime.now().isoformat(timespec="seconds")
    step_name = step_summary["step"]
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, step_name)
    summary["steps"][step_name] = {
        "label": step_summary["label"],
        "status": step_summary["status"],
        "protocol_verdict": step_summary["protocol_verdict"],
        "summary_json": board_sweep._relpath(summary_json_path, run_dir),
        "summary_md": board_sweep._relpath(summary_md_path, run_dir),
    }
    completed = [step for step in summary.get("steps_expected", STEP_ORDER) if step in summary["steps"]]
    passed = len([step for step in completed if summary["steps"][step]["protocol_verdict"] == "pass"])
    failed = len([step for step in completed if summary["steps"][step]["protocol_verdict"] != "pass"])
    summary["steps_completed"] = completed
    summary["steps_passed"] = passed
    summary["steps_failed"] = failed
    if len(completed) == len(summary.get("steps_expected", STEP_ORDER)) and failed == 0:
        summary["overall_verdict"] = "pass"
    elif failed > 0:
        summary["overall_verdict"] = "fail"
    else:
        summary["overall_verdict"] = "incomplete"
    _write_json(_protocol_state(run_dir), summary)
    _write_text(run_dir / PROTOCOL_SUMMARY_MD, _render_protocol_summary_markdown(summary))
    return summary


class ProtocolRunner(board_metrics.MetricsRunner):
    def _single_packet_paths(self, run_dir, manifest, variant):
        if variant == "bypass":
            protocol = manifest["protocol_demo"]
            capture_path = protocol["artifacts"]["bypass_capture"]
            return {
                "receiver_remote": "%s/%s" % (
                    manifest["usc"]["remote_receiver_root"],
                    capture_path,
                ),
                "receiver_local": run_dir / capture_path,
                "receiver_script": "nf1_capture_protocol_bypass.sh",
                "replay_script": "nf4_replay_protocol_bypass.sh",
            }
        return super()._single_packet_paths(run_dir, manifest, variant)

    def _single_packet_bypass_verdict(self, manifest, capture_state, variant):
        if variant != "bypass":
            return super()._single_packet_bypass_verdict(manifest, capture_state, variant)
        frames = board_sweep.read_pcap(capture_state["path"])
        inspected = inspect_ann_frame(frames[0], manifest["model"]["result_mode"]) if frames else {}
        passed = (
            len(frames) >= 1
            and inspected.get("frame_kind") == "udp_unknown"
            and inspected.get("udp_dst_port") == manifest["protocol_demo"]["bypass_udp_dst_port"]
            and inspected.get("payload_hex") == manifest["protocol_demo"]["bypass_payload_hex"]
        )
        return {
            "verdict": "bypass_ok" if passed else "bypass_mismatch",
            "packet_count": len(frames),
            "payload_magic": inspected.get("payload_magic"),
            "udp_dst_port": inspected.get("udp_dst_port"),
            "frame_kind": inspected.get("frame_kind"),
            "payload_hex": inspected.get("payload_hex"),
            "request_id": _format_request_id(inspected.get("request_id")),
        }


def _step_expected_behavior(step_name, manifest):
    if step_name == "bypass":
        return (
            "Replay a normal IPv4/UDP packet on a non-ANN destination port. "
            "The receiver should capture it, but the ANN engine should ignore it."
        )
    if step_name == "wrong_magic":
        return (
            "Replay a packet on the ANN UDP port with an invalid payload magic. "
            "The receiver should capture it, but it must stay on the bypass path."
        )
    if step_name == "offload":
        return (
            "Replay a legal ANN task packet. The receiver should observe an ANN result frame "
            "with the expected class/score fields."
        )
    raise ValueError("unsupported protocol step: %s" % step_name)


def _step_protocol_check(step_name, sample, observed_summary):
    if step_name == "bypass":
        return "Captured udp_unknown on udp_dst_port=%s; packet stayed on bypass path" % (
            observed_summary.get("udp_dst_port", "n/a") if observed_summary else "n/a"
        )
    if step_name == "wrong_magic":
        return "Captured udp_unknown on udp_dst_port=%s with payload_magic=%s; packet did not enter compute" % (
            observed_summary.get("udp_dst_port", "n/a") if observed_summary else "n/a",
            observed_summary.get("payload_magic", "n/a") if observed_summary else "n/a",
        )
    if step_name == "offload":
        return (
            "Captured ann_result request_id=%s predicted_class=%s predicted_score_s16=%s"
            % (
                observed_summary.get("request_id", "n/a") if observed_summary else "n/a",
                observed_summary.get("predicted_class", "n/a") if observed_summary else "n/a",
                observed_summary.get("predicted_score_s16", "n/a") if observed_summary else "n/a",
            )
        )
    return "protocol check unavailable"


def _render_step_markdown(step_summary):
    lines = [
        "# %s" % step_summary["label"],
        "",
        "- step: `%s`" % step_summary["step"],
        "- status: `%s`" % str(step_summary["protocol_verdict"]).upper(),
        "- run_dir: `%s`" % step_summary["run_dir"],
        "- runner_log: `%s`" % step_summary["runner_log"],
        "- expected_behavior: %s" % step_summary["expected_behavior"],
        "- protocol_check: %s" % step_summary["protocol_check"],
        "",
        "## Sent Packet",
        "",
    ]
    sent_packet = step_summary.get("sent_packet_summary")
    if sent_packet:
        for key, value in _metadata_rows(sent_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "sent_wire_hex=%s" % (step_summary.get("sent_packet_hex") or "unavailable"),
            "```",
            "",
            "## Observed Packet",
            "",
        ]
    )
    observed_packet = step_summary.get("observed_packet_summary")
    if observed_packet:
        for key, value in _metadata_rows(observed_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "observed_wire_hex=%s" % (step_summary.get("observed_packet_hex") or "unavailable"),
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def _build_step_summary(run_dir, manifest, step_name, log_path, sample):
    variant = STEP_VARIANTS[step_name]
    sent_packet = _read_first_capture_packet(
        run_dir / sample["sender_capture_path"],
        manifest["model"]["result_mode"],
    )
    observed_packet = _read_first_capture_packet(
        run_dir / sample["receiver_capture_path"],
        manifest["model"]["result_mode"],
    )
    protocol_verdict = "pass" if sample.get("status") == "passed" else "fail"
    observed_summary = observed_packet["summary"] if observed_packet else None
    return {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "step": step_name,
        "label": STEP_LABELS[step_name],
        "single_packet_variant": variant,
        "status": sample.get("status"),
        "protocol_verdict": protocol_verdict,
        "run_dir": str(run_dir),
        "runner_log": board_sweep._relpath(log_path, run_dir),
        "expected_behavior": _step_expected_behavior(step_name, manifest),
        "protocol_check": _step_protocol_check(step_name, sample, observed_summary),
        "sample": sample,
        "sent_packet_summary": sent_packet["summary"] if sent_packet else None,
        "sent_packet_hex": sent_packet["wire_frame_hex"] if sent_packet else None,
        "observed_packet_summary": observed_summary,
        "observed_packet_hex": observed_packet["wire_frame_hex"] if observed_packet else None,
        "artifacts": {
            "step_summary_json": _step_summary_paths(run_dir, step_name)[0].name,
            "step_summary_md": _step_summary_paths(run_dir, step_name)[1].name,
        },
    }


def _print_step_block(step_summary):
    width = _term_width()
    _print_separator("=", width=width)
    _print_kv("Protocol Step", step_summary["label"], key_width=17)
    _print_wrapped_kv("Expected", step_summary["expected_behavior"], key_width=17, width=width)
    _print_wrapped_kv("Protocol Check", step_summary["protocol_check"], key_width=17, width=width)
    _print_kv("Result", _status_word(step_summary["protocol_verdict"] == "pass"), key_width=17)
    _print_separator("-", width=width)
    _print_packet("Sent Packet", step_summary.get("sent_packet_summary"), step_summary.get("sent_packet_hex"), indent=2, width=width)
    _print_separator("-", width=width)
    _print_packet(
        "Observed Packet",
        step_summary.get("observed_packet_summary"),
        step_summary.get("observed_packet_hex"),
        indent=2,
        width=width,
    )
    _print_separator("-", width=width)
    _print_kv("Step Summary", step_summary["artifacts"]["step_summary_md"], key_width=17)
    _print_separator("=", width=width)


def init_command(args):
    config_path = Path(args.config).resolve()
    protocol_defaults = _load_protocol_defaults(config_path)
    defaults = dict(protocol_defaults["runner_defaults"])
    password = _resolve_password(defaults, args.password_file)
    run_dir = Path(args.out_dir).resolve()
    if run_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % run_dir)
        shutil.rmtree(run_dir)
    experiment = _init_experiment(run_dir.name, protocol_defaults)
    runner = ProtocolRunner(output_dir=run_dir.parent, config_path=config_path, defaults=defaults, password=password)
    log_path = runner.log_dir / (run_dir.name + "_protocol_init.log")

    with open(log_path, "w", encoding="utf-8") as handle:
        prepare_command = board_sweep._build_prepare_command(run_dir, defaults, experiment)
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._run_local(handle, prepare_command)
        runner._run_local(
            handle,
            [sys.executable, str(board_sweep.BOARDCTL_PATH), "bringup", str(run_dir / "manifest.json")],
        )
        runner._run_local(
            handle,
            [sys.executable, str(board_sweep.BOARDCTL_PATH), "capture", str(run_dir / "manifest.json")],
        )
        manifest = _load_json(run_dir / "manifest.json")
        _augment_manifest_for_protocol_demo(run_dir, manifest, protocol_defaults)
        _write_json(run_dir / "manifest.json", manifest)
        runner._stage_artifacts(run_dir, manifest, handle)
        runner._run_remote_script(
            handle,
            manifest["usc"]["netfpga_host"],
            run_dir / "commands" / "nf3_bringup.sh",
            tty=False,
        )

    manifest = _load_json(run_dir / "manifest.json")
    summary = _base_protocol_summary(run_dir, manifest)
    _write_json(run_dir / PROTOCOL_SUMMARY_JSON, summary)
    _write_text(run_dir / PROTOCOL_SUMMARY_MD, _render_protocol_summary_markdown(summary))

    print("run_dir=%s" % run_dir)
    print("manifest=%s" % (run_dir / "manifest.json"))
    print("protocol_summary_json=%s" % (run_dir / PROTOCOL_SUMMARY_JSON))
    print("protocol_summary_md=%s" % (run_dir / PROTOCOL_SUMMARY_MD))
    print("next_steps=bypass,wrong_magic,offload")
    return 0


def run_step_command(args, step_name):
    run_dir = Path(args.run_dir).resolve()
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit("protocol demo manifest not found: %s" % manifest_path)
    manifest = _load_json(manifest_path)
    if "protocol_demo" not in manifest:
        raise SystemExit("manifest is missing protocol_demo section; rerun protocol-init")

    defaults = _runner_defaults_from_manifest(manifest)
    password = _resolve_password(defaults, args.password_file)
    runner = ProtocolRunner(output_dir=run_dir, config_path=manifest_path, defaults=defaults, password=password)
    variant = STEP_VARIANTS[step_name]
    timeout_seconds = float(
        manifest["protocol_demo"].get("single_result_timeout_seconds", DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS)
    )
    log_path = runner.log_dir / ("protocol_%s.log" % step_name)

    with open(log_path, "w", encoding="utf-8") as handle:
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._log(handle, "step=%s" % step_name)
        sample = runner._single_latency_sample(
            run_dir,
            manifest,
            handle,
            sample_index=1,
            timeout_seconds=timeout_seconds,
            variant=variant,
        )

    step_summary = _build_step_summary(run_dir, manifest, step_name, log_path, sample)
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, step_name)
    _write_json(summary_json_path, step_summary)
    _write_text(summary_md_path, _render_step_markdown(step_summary))
    _update_protocol_summary(run_dir, manifest, step_summary)
    _print_step_block(step_summary)
    return 0 if step_summary["protocol_verdict"] == "pass" else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Run the thin protocol demo workflow for the RSU board showcase.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init = subparsers.add_parser("init", help="prepare one protocol demo context and initialize the board once")
    init.add_argument("--config", default=str(DEFAULT_CONFIG))
    init.add_argument("--password-file")
    init.add_argument("--out-dir", required=True)
    init.add_argument("--force", action="store_true", default=False)
    init.set_defaults(func=init_command)

    bypass = subparsers.add_parser("bypass", help="run the normal IPv4/UDP bypass step")
    bypass.add_argument("--run-dir", required=True)
    bypass.add_argument("--password-file")
    bypass.set_defaults(func=lambda args: run_step_command(args, "bypass"))

    wrong_magic = subparsers.add_parser("wrong-magic", help="run the wrong-magic bypass step")
    wrong_magic.add_argument("--run-dir", required=True)
    wrong_magic.add_argument("--password-file")
    wrong_magic.set_defaults(func=lambda args: run_step_command(args, "wrong_magic"))

    offload = subparsers.add_parser("offload", help="run the accepted ANN offload step")
    offload.add_argument("--run-dir", required=True)
    offload.add_argument("--password-file")
    offload.set_defaults(func=lambda args: run_step_command(args, "offload"))

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
