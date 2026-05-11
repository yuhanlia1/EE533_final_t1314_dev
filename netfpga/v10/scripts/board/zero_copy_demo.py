#!/usr/bin/env python3

import argparse
import json
import math
import shutil
import subprocess
import sys
import textwrap
import time
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import board_metrics
import board_sweep
from board_debug.ann_packets import inspect_ann_frame
from board_debug.pcap_io import read_pcap_records


DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_demo_zero_copy.json"
DEFAULT_REQUEST_ID_BASE = "0x1100"
DEFAULT_LIMIT_WINDOW_MS = 50
DEFAULT_THRESHOLD_WINDOWS_MS = [1600, 800, 400, 200, 100, 50, 10, 1]
DEFAULT_PATH_TIMEOUT_SECONDS = 2.0
DEFAULT_CAPTURE_GUARD_TIMEOUT_SECONDS = 1.0
DEFAULT_WINDOW_POLL_INTERVAL_SECONDS = 0.005
DEFAULT_MEASUREMENT_RESOLUTION_MS = int(math.ceil(DEFAULT_WINDOW_POLL_INTERVAL_SECONDS * 1000.0))
DEFAULT_TERM_WIDTH = 100
TERM_WIDTH_CAP = 100
DEFAULT_HEX_CHUNK = 64
ZERO_COPY_SUMMARY_JSON = "zero_copy_demo_summary.json"
ZERO_COPY_SUMMARY_MD = "zero_copy_demo_summary.md"
THRESHOLD_SUMMARY_JSON = "zero_copy_threshold_summary.json"
THRESHOLD_SUMMARY_MD = "zero_copy_threshold_summary.md"
LIMIT_SUMMARY_JSON = "zero_copy_limit_summary.json"
LIMIT_SUMMARY_MD = "zero_copy_limit_summary.md"
PATH_SUMMARY_JSON = "zero_copy_path_summary.json"
PATH_SUMMARY_MD = "zero_copy_path_summary.md"
PATH_DEBUG_STATUS_NAME = "zero_copy_path_debug_status.txt"
STEP_ORDER = ["threshold", "limit", "path"]
STEP_LABELS = {
    "threshold": "Threshold Sweep",
    "limit": "Limit Point Demo",
    "path": "Path Visualization",
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


def _term_width():
    return min(shutil.get_terminal_size((DEFAULT_TERM_WIDTH, 20)).columns, TERM_WIDTH_CAP)


def _print_separator(char="=", width=None):
    width = width or _term_width()
    print(char * width)


def _print_kv(key, value, indent=0, key_width=18):
    prefix = " " * int(indent)
    print("%s%-*s : %s" % (prefix, int(key_width), str(key), str(value)))


def _print_wrapped_kv(key, value, indent=0, key_width=18, width=None):
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


def _status_word(verdict):
    if isinstance(verdict, str):
        text = verdict.strip().lower()
        if text == "pass":
            return "PASS"
        if text == "unstable":
            return "UNSTABLE"
        return "FAIL"
    return "PASS" if verdict else "FAIL"


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
        "payload_hex",
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


def _load_model_labels(model_path):
    try:
        model = json.loads(Path(model_path).read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return []
    labels = model.get("labels")
    if not isinstance(labels, list):
        return []
    return [str(label) for label in labels]


def _predicted_label(summary, labels):
    if not summary or not labels:
        return None
    raw_value = summary.get("predicted_class")
    if raw_value is None:
        return None
    try:
        index = int(str(raw_value), 0)
    except ValueError:
        return None
    if 0 <= index < len(labels):
        return labels[index]
    return None


def _normalize_window_list(raw_windows, field_name):
    if not isinstance(raw_windows, list) or not raw_windows:
        raise SystemExit("%s must be a non-empty JSON list" % field_name)
    normalized = []
    for item in raw_windows:
        value = int(item)
        if value <= 0:
            raise SystemExit("%s values must be > 0 ms" % field_name)
        normalized.append(value)
    return sorted(set(normalized), reverse=True)


def _parse_windows_arg(text):
    parts = [item.strip() for item in str(text).split(",") if item.strip()]
    if not parts:
        raise SystemExit("--windows-ms must contain at least one integer value")
    normalized = []
    for item in parts:
        try:
            value = int(item)
        except ValueError as exc:
            raise SystemExit("invalid --windows-ms value: %s" % item) from exc
        if value <= 0:
            raise SystemExit("--windows-ms values must be > 0")
        normalized.append(value)
    return sorted(set(normalized), reverse=True)


def _measurement_resolution_ms(poll_interval_seconds):
    return max(1, int(math.ceil(float(poll_interval_seconds) * 1000.0)))


def _load_zero_copy_defaults(config_path):
    config = _load_json(config_path)
    if not isinstance(config, dict):
        raise SystemExit("zero-copy config must be a JSON object")
    defaults = board_sweep._normalize_defaults(config, config_path.parent)
    window_poll_interval_seconds = float(
        config.get("window_poll_interval_seconds", DEFAULT_WINDOW_POLL_INTERVAL_SECONDS)
    )
    return {
        "config_path": str(config_path),
        "runner_defaults": defaults,
        "request_id_base": str(config.get("request_id_base", DEFAULT_REQUEST_ID_BASE)),
        "default_limit_window_ms": int(config.get("default_limit_window_ms", DEFAULT_LIMIT_WINDOW_MS)),
        "default_threshold_windows_ms": _normalize_window_list(
            config.get("default_threshold_windows_ms", DEFAULT_THRESHOLD_WINDOWS_MS),
            "default_threshold_windows_ms",
        ),
        "path_timeout_seconds": float(config.get("path_timeout_seconds", DEFAULT_PATH_TIMEOUT_SECONDS)),
        "capture_guard_timeout_seconds": float(
            config.get("capture_guard_timeout_seconds", DEFAULT_CAPTURE_GUARD_TIMEOUT_SECONDS)
        ),
        "window_poll_interval_seconds": window_poll_interval_seconds,
        "measurement_resolution_ms": int(
            config.get(
                "measurement_resolution_ms",
                _measurement_resolution_ms(window_poll_interval_seconds),
            )
        ),
        "clear_debug_before_path": bool(config.get("clear_debug_before_path", True)),
    }


def _runner_defaults_from_manifest(manifest):
    defaults = board_sweep._normalize_defaults({}, ROOT_DIR)
    zero_copy = manifest.get("zero_copy_demo", {})
    usc = manifest["usc"]
    network = manifest["network"]
    defaults.update(
        {
            "model": manifest["model"]["source"],
            "bitfile": manifest["bitfile"],
            "ssh_mode": str(zero_copy.get("ssh_mode", defaults["ssh_mode"])),
            "netfpga_host": usc["netfpga_host"],
            "sender_host": usc["sender_host"],
            "receiver_host": usc["receiver_host"],
            "sender_iface": usc["sender_iface"],
            "receiver_iface": usc["receiver_iface"],
            "pre_capture_delay_seconds": float(
                zero_copy.get("pre_capture_delay_seconds", defaults["pre_capture_delay_seconds"])
            ),
            "capture_ready_delay_seconds": float(
                zero_copy.get("capture_ready_delay_seconds", defaults["capture_ready_delay_seconds"])
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


def _init_experiment(run_name, zero_copy_defaults):
    prepare_window_seconds = max(
        max(zero_copy_defaults["default_threshold_windows_ms"]) / 1000.0,
        float(zero_copy_defaults["path_timeout_seconds"]),
        float(zero_copy_defaults["default_limit_window_ms"]) / 1000.0,
    )
    return {
        "run_name": run_name,
        "prepare_limit": 1,
        "sample_pool_mode": "truncate",
        "prepare_request_id_base": str(zero_copy_defaults["request_id_base"]),
        "prepare_batch_time_window_seconds": prepare_window_seconds,
        "mode": "latency_single",
    }


def _render_zero_copy_support_scripts(manifest):
    usc = manifest["usc"]
    return {
        "nf3_zero_copy_debug_clear.sh": """#!/usr/bin/env bash
set -euo pipefail
RUN_ROOT="{run_root}"
RESULT_ROOT="{result_root}"
export ANNCTL_STATE_DIR="$RESULT_ROOT/annctl_state"
mkdir -p "$RUN_ROOT" "$RESULT_ROOT" "$ANNCTL_STATE_DIR"
cd "$RUN_ROOT"
perl bin/annctl engine debug-clear
perl bin/annctl engine debug-status
""".format(
            run_root=board_sweep._shell_remote_path(usc["remote_netfpga_root"]),
            result_root=board_sweep._shell_remote_path(usc["remote_netfpga_results"]),
        ),
    }


def _augment_manifest_for_zero_copy(run_dir, manifest, zero_copy_defaults):
    zero_copy = {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "config_path": str(zero_copy_defaults["config_path"]),
        "ssh_mode": zero_copy_defaults["runner_defaults"]["ssh_mode"],
        "pre_capture_delay_seconds": float(
            zero_copy_defaults["runner_defaults"]["pre_capture_delay_seconds"]
        ),
        "capture_ready_delay_seconds": float(
            zero_copy_defaults["runner_defaults"]["capture_ready_delay_seconds"]
        ),
        "request_id_base": str(zero_copy_defaults["request_id_base"]),
        "default_limit_window_ms": int(zero_copy_defaults["default_limit_window_ms"]),
        "default_threshold_windows_ms": list(zero_copy_defaults["default_threshold_windows_ms"]),
        "path_timeout_seconds": float(zero_copy_defaults["path_timeout_seconds"]),
        "capture_guard_timeout_seconds": float(zero_copy_defaults["capture_guard_timeout_seconds"]),
        "window_poll_interval_seconds": float(zero_copy_defaults["window_poll_interval_seconds"]),
        "measurement_resolution_ms": int(zero_copy_defaults["measurement_resolution_ms"]),
        "clear_debug_before_path": bool(zero_copy_defaults["clear_debug_before_path"]),
        "steps": list(STEP_ORDER),
        "artifacts": {
            "summary_json": ZERO_COPY_SUMMARY_JSON,
            "summary_md": ZERO_COPY_SUMMARY_MD,
            "threshold_summary_json": THRESHOLD_SUMMARY_JSON,
            "threshold_summary_md": THRESHOLD_SUMMARY_MD,
            "limit_summary_json": LIMIT_SUMMARY_JSON,
            "limit_summary_md": LIMIT_SUMMARY_MD,
            "path_summary_json": PATH_SUMMARY_JSON,
            "path_summary_md": PATH_SUMMARY_MD,
            "path_debug_status_txt": PATH_DEBUG_STATUS_NAME,
        },
    }
    manifest["zero_copy_demo"] = zero_copy
    manifest["artifacts"]["zero_copy_path_debug_status_txt"] = PATH_DEBUG_STATUS_NAME
    for name, content in _render_zero_copy_support_scripts(manifest).items():
        _write_shell(run_dir / "commands" / name, content)


def _zero_copy_state(run_dir):
    return Path(run_dir) / ZERO_COPY_SUMMARY_JSON


def _step_summary_paths(run_dir, step_name):
    mapping = {
        "threshold": (
            Path(run_dir) / THRESHOLD_SUMMARY_JSON,
            Path(run_dir) / THRESHOLD_SUMMARY_MD,
        ),
        "limit": (
            Path(run_dir) / LIMIT_SUMMARY_JSON,
            Path(run_dir) / LIMIT_SUMMARY_MD,
        ),
        "path": (
            Path(run_dir) / PATH_SUMMARY_JSON,
            Path(run_dir) / PATH_SUMMARY_MD,
        ),
    }
    return mapping[step_name]


def _base_zero_copy_summary(run_dir, manifest):
    zero_copy = manifest.get("zero_copy_demo", {})
    return {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "run_dir": str(run_dir),
        "run_name": manifest["run_name"],
        "config_path": zero_copy.get("config_path"),
        "steps_expected": list(zero_copy.get("steps", STEP_ORDER)),
        "steps_completed": [],
        "steps_passed": 0,
        "steps_failed": 0,
        "overall_verdict": "incomplete",
        "steps": {},
    }


def _load_or_init_zero_copy_summary(run_dir, manifest):
    summary_path = _zero_copy_state(run_dir)
    if summary_path.exists():
        return _load_json(summary_path)
    return _base_zero_copy_summary(run_dir, manifest)


def _render_zero_copy_summary_markdown(summary):
    lines = [
        "# Zero-Copy Demo Summary",
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
            "| %s | %s | `%s` |"
            % (
                step_name,
                str(item.get("zero_copy_verdict", "fail")).upper(),
                item.get("summary_md", "-"),
            )
        )
    return "\n".join(lines) + "\n"


def _update_zero_copy_summary(run_dir, manifest, step_name, label, status, zero_copy_verdict):
    summary = _load_or_init_zero_copy_summary(run_dir, manifest)
    summary["updated_at"] = datetime.now().isoformat(timespec="seconds")
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, step_name)
    summary["steps"][step_name] = {
        "label": label,
        "status": status,
        "zero_copy_verdict": zero_copy_verdict,
        "summary_json": board_sweep._relpath(summary_json_path, run_dir),
        "summary_md": board_sweep._relpath(summary_md_path, run_dir),
    }
    completed = [step for step in summary.get("steps_expected", STEP_ORDER) if step in summary["steps"]]
    passed = len([step for step in completed if summary["steps"][step]["zero_copy_verdict"] == "pass"])
    failed = len([step for step in completed if summary["steps"][step]["zero_copy_verdict"] != "pass"])
    summary["steps_completed"] = completed
    summary["steps_passed"] = passed
    summary["steps_failed"] = failed
    if len(completed) == len(summary.get("steps_expected", STEP_ORDER)) and failed == 0:
        summary["overall_verdict"] = "pass"
    elif failed > 0:
        summary["overall_verdict"] = "fail"
    else:
        summary["overall_verdict"] = "incomplete"
    _write_json(_zero_copy_state(run_dir), summary)
    _write_text(run_dir / ZERO_COPY_SUMMARY_MD, _render_zero_copy_summary_markdown(summary))
    return summary


def _window_status_note(measurement):
    status = measurement.get("status")
    if status == "passed":
        return "Observed matching ann_result within the configured window."
    return "This window is not treated as a demo-grade pass result."


def _build_window_measurement(run_dir, manifest, labels, sample, window_ms):
    sender_packet = _read_first_capture_packet(
        run_dir / sample["sender_capture_path"],
        manifest["model"]["result_mode"],
    )
    observed_packet = _read_first_capture_packet(
        run_dir / sample["receiver_capture_path"],
        manifest["model"]["result_mode"],
    )
    observed_summary = observed_packet["summary"] if observed_packet else None
    predicted_label = _predicted_label(observed_summary, labels)
    measurement_resolution_ms = int(
        manifest.get("zero_copy_demo", {}).get(
            "measurement_resolution_ms",
            _measurement_resolution_ms(
                manifest.get("zero_copy_demo", {}).get(
                    "window_poll_interval_seconds",
                    DEFAULT_WINDOW_POLL_INTERVAL_SECONDS,
                )
            ),
        )
    )
    if int(window_ms) < measurement_resolution_ms:
        inference_check = "WINDOW BELOW MEASUREMENT RESOLUTION"
        window_verdict = "unstable"
        display_status = "unstable"
    elif sample.get("status") == "passed":
        inference_check = "MATCHED EXPECTED OFFLOAD RESULT"
        window_verdict = "pass"
        display_status = "passed"
    elif sample.get("status") == "window_miss":
        inference_check = "RESULT NOT OBSERVED WITHIN WINDOW"
        window_verdict = "fail"
        display_status = "window_miss"
    elif sample.get("status") == "capture_missing":
        inference_check = "CAPTURE MISSING AFTER WINDOW CLOSED"
        window_verdict = "fail"
        display_status = "capture_missing"
    else:
        inference_check = "RESULT MISMATCH"
        window_verdict = "fail"
        display_status = sample.get("status")
    measurement = {
        "window_ms": int(window_ms),
        "window_verdict": window_verdict,
        "status": display_status,
        "raw_status": sample.get("status"),
        "measurement_resolution_ms": measurement_resolution_ms,
        "sender_capture_exists": bool(sample.get("sender_capture_exists")),
        "receiver_capture_exists": bool(sample.get("receiver_capture_exists")),
        "receiver_completed_within_window": bool(sample.get("receiver_completed_within_window")),
        "sender_completed_within_window": bool(sample.get("sender_completed_within_window")),
        "sender_capture_path": sample.get("sender_capture_path"),
        "receiver_capture_path": sample.get("receiver_capture_path"),
        "receiver_window_wait_us": sample.get("receiver_window_wait_us"),
        "request_id": observed_summary.get("request_id") if observed_summary else None,
        "predicted_class": observed_summary.get("predicted_class") if observed_summary else None,
        "predicted_label": predicted_label,
        "predicted_score_s16": observed_summary.get("predicted_score_s16") if observed_summary else None,
        "inference_check": inference_check,
        "window_note": None,
        "sent_packet_summary": sender_packet["summary"] if sender_packet else None,
        "sent_packet_hex": sender_packet["wire_frame_hex"] if sender_packet else None,
        "observed_packet_summary": observed_summary,
        "observed_packet_hex": observed_packet["wire_frame_hex"] if observed_packet else None,
    }
    measurement["window_note"] = _window_status_note(measurement)
    return measurement


def _threshold_window_analysis(window_results):
    passing_windows = [item["window_ms"] for item in window_results if item.get("window_verdict") == "pass"]
    failing_windows = [item["window_ms"] for item in window_results if item.get("window_verdict") == "fail"]
    smallest_passing = min(passing_windows) if passing_windows else None
    largest_failing = max(failing_windows) if failing_windows else None
    ordering_consistent = True
    seen_fail = False
    for item in window_results:
        verdict = item.get("window_verdict")
        if verdict == "unstable":
            continue
        if verdict != "pass":
            seen_fail = True
            continue
        if seen_fail:
            ordering_consistent = False
            break
    threshold_transition_found = (
        smallest_passing is not None
        and largest_failing is not None
        and ordering_consistent
        and largest_failing < smallest_passing
    )
    return {
        "smallest_passing_window_ms": smallest_passing,
        "largest_failing_window_ms": largest_failing,
        "threshold_transition_found": threshold_transition_found,
        "limit_exhausted": largest_failing is not None,
        "ordering_consistent": ordering_consistent,
        "zero_copy_verdict": "pass" if smallest_passing is not None else "fail",
    }


def _build_threshold_summary(run_dir, manifest, log_path, windows_ms, window_results):
    analysis = _threshold_window_analysis(window_results)
    return {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "step": "threshold",
        "label": STEP_LABELS["threshold"],
        "run_dir": str(run_dir),
        "runner_log": board_sweep._relpath(log_path, run_dir),
        "windows_tested_ms": list(windows_ms),
        "window_results": window_results,
        **analysis,
        "status": "passed" if analysis["zero_copy_verdict"] == "pass" else "failed",
        "artifacts": {
            "step_summary_json": THRESHOLD_SUMMARY_JSON,
            "step_summary_md": THRESHOLD_SUMMARY_MD,
        },
    }


def _render_threshold_markdown(summary):
    lines = [
        "# Zero-Copy Threshold Sweep",
        "",
        "- run_dir: `%s`" % summary.get("run_dir"),
        "- runner_log: `%s`" % summary.get("runner_log"),
        "- zero_copy_verdict: `%s`" % str(summary.get("zero_copy_verdict", "fail")).upper(),
        "- smallest_passing_window_ms: `%s`" % summary.get("smallest_passing_window_ms"),
        "- largest_failing_window_ms: `%s`" % summary.get("largest_failing_window_ms"),
        "- threshold_transition_found: `%s`" % summary.get("threshold_transition_found"),
        "- limit_exhausted: `%s`" % summary.get("limit_exhausted"),
        "- ordering_consistent: `%s`" % summary.get("ordering_consistent"),
        "",
        "| Window (ms) | Verdict | Request ID | Label | Note |",
        "| --- | --- | --- | --- | --- |",
    ]
    for item in summary.get("window_results", []):
        lines.append(
            "| {window_ms} | {verdict} | {request_id} | {predicted_label} | {note} |".format(
                window_ms=item["window_ms"],
                verdict=str(item.get("window_verdict", "fail")).upper(),
                request_id=item.get("request_id") or "-",
                predicted_label=item.get("predicted_label") or "-",
                note=item.get("window_note") or "-",
            )
        )
    return "\n".join(lines) + "\n"


def _build_limit_summary(run_dir, log_path, window_ms, measurement):
    return {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "step": "limit",
        "label": STEP_LABELS["limit"],
        "run_dir": str(run_dir),
        "runner_log": board_sweep._relpath(log_path, run_dir),
        "window_ms": int(window_ms),
        "zero_copy_verdict": measurement["window_verdict"],
        "status": measurement["status"],
        "measurement_resolution_ms": measurement.get("measurement_resolution_ms"),
        "request_id": measurement.get("request_id"),
        "predicted_class": measurement.get("predicted_class"),
        "predicted_label": measurement.get("predicted_label"),
        "predicted_score_s16": measurement.get("predicted_score_s16"),
        "receiver_completed_within_window": measurement.get("receiver_completed_within_window"),
        "receiver_window_wait_us": measurement.get("receiver_window_wait_us"),
        "sender_capture_exists": measurement.get("sender_capture_exists"),
        "receiver_capture_exists": measurement.get("receiver_capture_exists"),
        "inference_check": measurement.get("inference_check"),
        "window_note": measurement.get("window_note"),
        "sent_packet_summary": measurement.get("sent_packet_summary"),
        "sent_packet_hex": measurement.get("sent_packet_hex"),
        "observed_packet_summary": measurement.get("observed_packet_summary"),
        "observed_packet_hex": measurement.get("observed_packet_hex"),
        "artifacts": {
            "step_summary_json": LIMIT_SUMMARY_JSON,
            "step_summary_md": LIMIT_SUMMARY_MD,
        },
    }


def _render_limit_markdown(summary):
    lines = [
        "# Zero-Copy Limit Point Demo",
        "",
        "- run_dir: `%s`" % summary.get("run_dir"),
        "- runner_log: `%s`" % summary.get("runner_log"),
        "- zero_copy_verdict: `%s`" % str(summary.get("zero_copy_verdict", "fail")).upper(),
        "- window_ms: `%s`" % summary.get("window_ms"),
        "- measurement_resolution_ms: `%s`" % summary.get("measurement_resolution_ms"),
        "- request_id: `%s`" % (summary.get("request_id") or "unavailable"),
        "- predicted_label: `%s`" % (summary.get("predicted_label") or "unavailable"),
        "- receiver_completed_within_window: `%s`" % summary.get("receiver_completed_within_window"),
        "- inference_check: `%s`" % summary.get("inference_check"),
        "- note: %s" % summary.get("window_note"),
        "",
        "## Request Packet",
        "",
    ]
    sent_packet = summary.get("sent_packet_summary")
    if sent_packet:
        for key, value in _metadata_rows(sent_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "request_wire_hex=%s" % (summary.get("sent_packet_hex") or "unavailable"),
            "```",
            "",
            "## Observed Result",
            "",
        ]
    )
    observed_packet = summary.get("observed_packet_summary")
    if observed_packet:
        for key, value in _metadata_rows(observed_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "observed_wire_hex=%s" % (summary.get("observed_packet_hex") or "unavailable"),
            "```",
            "",
        ]
    )
    return "\n".join(lines) + "\n"


def _format_debug_summary(debug_status):
    if not debug_status:
        return None
    summary = {}
    ordered_keys = (
        "offload_accept_count",
        "frame_hold_count",
        "compute_start_count",
        "compute_done_count",
        "result_emit_count",
        "last_parse_request_id",
        "last_compute_request_id",
        "last_emit_request_id",
        "ingress_overflow_seen",
        "parse_nonfatal_seen",
        "parse_fatal_seen",
        "emit_stall_seen",
    )
    for key in ordered_keys:
        if key not in debug_status:
            continue
        value = debug_status[key]
        if key.endswith("_request_id"):
            summary[key] = _format_request_id(value)
        else:
            summary[key] = value
    return summary or None


def _request_id_consistent(sender_summary, receiver_summary, debug_status):
    sender_request_id = sender_summary.get("request_id") if sender_summary else None
    receiver_request_id = receiver_summary.get("request_id") if receiver_summary else None
    if sender_request_id is None or receiver_request_id is None or sender_request_id != receiver_request_id:
        return False
    for key in ("last_parse_request_id", "last_compute_request_id", "last_emit_request_id"):
        raw_value = debug_status.get(key) if debug_status else None
        if raw_value in (None, 0, "0x0000"):
            continue
        if _format_request_id(raw_value) != sender_request_id:
            return False
    return True


def _build_path_summary(run_dir, manifest, labels, log_path, sample, debug_status_path, debug_status):
    sender_packet = _read_first_capture_packet(
        run_dir / sample["sender_capture_path"],
        manifest["model"]["result_mode"],
    )
    receiver_packet = _read_first_capture_packet(
        run_dir / sample["receiver_capture_path"],
        manifest["model"]["result_mode"],
    )
    sender_summary = sender_packet["summary"] if sender_packet else None
    receiver_summary = receiver_packet["summary"] if receiver_packet else None
    predicted_label = _predicted_label(receiver_summary, labels)
    request_id_consistent = _request_id_consistent(sender_summary, receiver_summary, debug_status or {})
    debug_summary = _format_debug_summary(debug_status or {})
    checks = {
        "sender_ann_task": bool(sender_summary and sender_summary.get("frame_kind") == "ann_task"),
        "receiver_ann_result": bool(receiver_summary and receiver_summary.get("frame_kind") == "ann_result"),
        "offload_accept_seen": bool((debug_status or {}).get("offload_accept_count", 0) >= 1),
        "compute_done_seen": bool((debug_status or {}).get("compute_done_count", 0) >= 1),
        "result_emit_seen": bool((debug_status or {}).get("result_emit_count", 0) >= 1),
        "request_id_consistent": bool(request_id_consistent),
    }
    passed = all(checks.values())
    statement = (
        "Host handled replay/capture only; board accepted, computed, and emitted the result in datapath."
        if passed
        else "Zero-copy evidence was incomplete; at least one host-edge or board-internal proof point is missing."
    )
    return {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "step": "path",
        "label": STEP_LABELS["path"],
        "status": sample.get("status"),
        "zero_copy_verdict": "pass" if passed else "fail",
        "run_dir": str(run_dir),
        "runner_log": board_sweep._relpath(log_path, run_dir),
        "request_id": receiver_summary.get("request_id") if receiver_summary else None,
        "request_id_consistent": request_id_consistent,
        "predicted_class": receiver_summary.get("predicted_class") if receiver_summary else None,
        "predicted_label": predicted_label,
        "predicted_score_s16": receiver_summary.get("predicted_score_s16") if receiver_summary else None,
        "zero_copy_statement": statement,
        "checks": checks,
        "sender_packet_summary": sender_summary,
        "sender_packet_hex": sender_packet["wire_frame_hex"] if sender_packet else None,
        "receiver_packet_summary": receiver_summary,
        "receiver_packet_hex": receiver_packet["wire_frame_hex"] if receiver_packet else None,
        "postrun_debug_status_path": board_sweep._relpath(debug_status_path, run_dir),
        "postrun_debug_status": debug_summary,
        "artifacts": {
            "step_summary_json": PATH_SUMMARY_JSON,
            "step_summary_md": PATH_SUMMARY_MD,
        },
    }


def _render_path_markdown(summary):
    lines = [
        "# Zero-Copy Path Visualization",
        "",
        "- run_dir: `%s`" % summary.get("run_dir"),
        "- runner_log: `%s`" % summary.get("runner_log"),
        "- zero_copy_verdict: `%s`" % str(summary.get("zero_copy_verdict", "fail")).upper(),
        "- request_id: `%s`" % (summary.get("request_id") or "unavailable"),
        "- request_id_consistent: `%s`" % summary.get("request_id_consistent"),
        "- predicted_label: `%s`" % (summary.get("predicted_label") or "unavailable"),
        "- zero_copy_statement: %s" % summary.get("zero_copy_statement"),
        "",
        "## Board Internal",
        "",
    ]
    debug_status = summary.get("postrun_debug_status") or {}
    if debug_status:
        for key, value in debug_status.items():
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- debug status unavailable")
    lines.extend(
        [
            "",
            "## Host Edge",
            "",
        ]
    )
    sender_packet = summary.get("sender_packet_summary")
    if sender_packet:
        for key, value in _metadata_rows(sender_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "sender_wire_hex=%s" % (summary.get("sender_packet_hex") or "unavailable"),
            "```",
            "",
            "## Result Edge",
            "",
        ]
    )
    receiver_packet = summary.get("receiver_packet_summary")
    if receiver_packet:
        for key, value in _metadata_rows(receiver_packet):
            lines.append("- %s: `%s`" % (key, value))
    else:
        lines.append("- packet detail unavailable")
    lines.extend(
        [
            "",
            "```text",
            "receiver_wire_hex=%s" % (summary.get("receiver_packet_hex") or "unavailable"),
            "```",
            "",
        ]
    )
    return "\n".join(lines) + "\n"


def _print_threshold_block(summary):
    width = _term_width()
    _print_separator("=", width=width)
    _print_kv("Zero-Copy Step", STEP_LABELS["threshold"], key_width=18)
    _print_wrapped_kv(
        "Method",
        "Run one legal ANN offload per window and record PASS/FAIL/UNSTABLE points for the threshold plot.",
        key_width=18,
        width=width,
    )
    _print_separator("-", width=width)
    for item in summary.get("window_results", []):
        value = "%s | %s" % (
            _status_word(item.get("window_verdict")),
            item.get("window_note"),
        )
        if item.get("predicted_label"):
            value += " | label=%s" % item.get("predicted_label")
        _print_wrapped_kv("Window %sms" % item["window_ms"], value, key_width=18, width=width)
    _print_separator("-", width=width)
    _print_kv("Result", _status_word(summary.get("zero_copy_verdict")), key_width=18)
    _print_kv("Smallest Pass", summary.get("smallest_passing_window_ms"), key_width=18)
    _print_kv("Largest Fail", summary.get("largest_failing_window_ms"), key_width=18)
    _print_kv("Transition Found", summary.get("threshold_transition_found"), key_width=18)
    _print_kv("Step Summary", summary["artifacts"]["step_summary_md"], key_width=18)
    _print_separator("=", width=width)


def _print_limit_block(summary):
    width = _term_width()
    _print_separator("=", width=width)
    _print_kv("Zero-Copy Demo", STEP_LABELS["limit"], key_width=18)
    _print_kv("Window", "%s ms" % summary["window_ms"], key_width=18)
    _print_kv("Result", _status_word(summary.get("zero_copy_verdict")), key_width=18)
    _print_wrapped_kv("Inference Check", summary.get("inference_check"), key_width=18, width=width)
    _print_wrapped_kv("Note", summary.get("window_note"), key_width=18, width=width)
    _print_kv("Resolution Floor", "%s ms" % summary.get("measurement_resolution_ms"), key_width=18)
    _print_kv("Predicted Label", summary.get("predicted_label", "n/a") or "n/a", key_width=18)
    _print_separator("-", width=width)
    _print_packet(
        "Request Packet",
        summary.get("sent_packet_summary"),
        summary.get("sent_packet_hex"),
        indent=2,
        width=width,
    )
    _print_separator("-", width=width)
    _print_packet(
        "Observed Result (Debug)" if summary.get("zero_copy_verdict") == "unstable" else "Observed Result",
        summary.get("observed_packet_summary"),
        summary.get("observed_packet_hex"),
        indent=2,
        width=width,
    )
    _print_separator("-", width=width)
    _print_kv("Step Summary", summary["artifacts"]["step_summary_md"], key_width=18)
    _print_separator("=", width=width)


def _print_debug_status_block(debug_status, width):
    if not debug_status:
        print("    debug status unavailable")
        return
    for key, value in debug_status.items():
        _print_wrapped_kv(key, value, indent=4, key_width=23, width=width)


def _print_path_block(summary):
    width = _term_width()
    _print_separator("=", width=width)
    _print_kv("Zero-Copy Step", STEP_LABELS["path"], key_width=18)
    _print_wrapped_kv("Zero-Copy Check", summary["zero_copy_statement"], key_width=18, width=width)
    _print_kv("Result", _status_word(summary.get("zero_copy_verdict") == "pass"), key_width=18)
    _print_separator("-", width=width)
    print("  Host Edge:")
    print()
    _print_packet("Sent Packet", summary.get("sender_packet_summary"), summary.get("sender_packet_hex"), indent=4, width=width)
    print()
    _print_separator("-", width=width)
    print("  Board Internal:")
    print()
    _print_debug_status_block(summary.get("postrun_debug_status"), width=width)
    print()
    _print_separator("-", width=width)
    print("  Result Edge:")
    print()
    _print_packet(
        "Observed Result",
        summary.get("receiver_packet_summary"),
        summary.get("receiver_packet_hex"),
        indent=4,
        width=width,
    )
    print()
    _print_separator("-", width=width)
    _print_kv("Request ID Match", summary.get("request_id_consistent"), key_width=18)
    _print_kv("Predicted Label", summary.get("predicted_label", "n/a") or "n/a", key_width=18)
    _print_kv("Step Summary", summary["artifacts"]["step_summary_md"], key_width=18)
    _print_separator("=", width=width)


class ZeroCopyRunner(board_metrics.MetricsRunner):
    def _single_window_sample(self, run_dir, manifest, handle, sample_index, window_ms):
        usc = manifest["usc"]
        commands_dir = run_dir / "commands"
        sender_capture_local = run_dir / "captures" / ("offload_sender_%03d.cap" % sample_index)
        receiver_capture_local = run_dir / "captures" / ("offload_receiver_%03d.cap" % sample_index)
        sender_capture_remote = "%s/captures/%s" % (
            usc["remote_sender_root"],
            board_metrics.SINGLE_SENDER_CAPTURE_NAME,
        )
        paths = self._single_packet_paths(run_dir, manifest, "offload")
        receiver_capture_remote = paths["receiver_remote"]

        if sender_capture_local.exists():
            sender_capture_local.unlink()
        if receiver_capture_local.exists():
            receiver_capture_local.unlink()
        self._run_remote_command(
            handle,
            usc["sender_host"],
            "rm -f %s" % board_sweep._shell_remote_path(sender_capture_remote),
            tty=False,
        )
        self._run_remote_command(
            handle,
            usc["receiver_host"],
            "rm -f %s" % board_sweep._shell_remote_path(receiver_capture_remote),
            tty=False,
        )

        sender_script = self._write_runtime_script(
            run_dir,
            "nf4_capture_single_sender.sh",
            self._single_sender_capture_script(manifest),
        )
        sender_capture = self._start_remote_script(handle, usc["sender_host"], sender_script, tty=True)
        receiver_capture = self._start_remote_script(
            handle,
            usc["receiver_host"],
            commands_dir / paths["receiver_script"],
            tty=True,
        )
        time.sleep(float(self.defaults["pre_capture_delay_seconds"]))
        self._run_remote_script(handle, usc["sender_host"], commands_dir / paths["replay_script"], tty=True)

        wait_start = time.perf_counter()
        deadline = wait_start + (float(window_ms) / 1000.0)
        poll_interval = float(
            manifest["zero_copy_demo"].get(
                "window_poll_interval_seconds",
                DEFAULT_WINDOW_POLL_INTERVAL_SECONDS,
            )
        )
        receiver_exit_time = None
        sender_exit_time = None
        while True:
            now = time.perf_counter()
            if sender_exit_time is None and sender_capture.process.poll() is not None:
                sender_exit_time = now
            if receiver_exit_time is None and receiver_capture.process.poll() is not None:
                receiver_exit_time = now
            if receiver_exit_time is not None:
                break
            if now >= deadline:
                break
            time.sleep(min(poll_interval, max(deadline - now, 0.0)))

        receiver_completed_within_window = receiver_capture.process.poll() is not None
        sender_completed_within_window = sender_capture.process.poll() is not None
        if receiver_completed_within_window and receiver_exit_time is None:
            receiver_exit_time = time.perf_counter()
        if sender_completed_within_window and sender_exit_time is None:
            sender_exit_time = time.perf_counter()

        guard_timeout_seconds = float(
            manifest["zero_copy_demo"].get(
                "capture_guard_timeout_seconds",
                DEFAULT_CAPTURE_GUARD_TIMEOUT_SECONDS,
            )
        )
        if receiver_capture.process.poll() is None:
            self._stop_async_remote_run(handle, receiver_capture, guard_timeout_seconds)
        else:
            receiver_capture.wait(check=False)
        if sender_capture.process.poll() is None:
            try:
                sender_capture.wait(timeout=guard_timeout_seconds, check=False)
            except subprocess.TimeoutExpired:
                self._stop_async_remote_run(handle, sender_capture, guard_timeout_seconds)
        else:
            sender_capture.wait(check=False)

        sender_remote_state, sender_local_state = self._fetch_remote_capture(
            handle,
            usc["sender_host"],
            sender_capture_remote,
            sender_capture_local,
        )
        receiver_remote_state, receiver_local_state = self._fetch_remote_capture(
            handle,
            usc["receiver_host"],
            receiver_capture_remote,
            receiver_capture_local,
        )

        sample = {
            "sample_index": sample_index,
            "sender_capture_path": board_sweep._relpath(sender_capture_local, self.output_dir),
            "receiver_capture_path": board_sweep._relpath(receiver_capture_local, self.output_dir),
            "sender_capture_exists": sender_local_state["exists"],
            "receiver_capture_exists": receiver_local_state["exists"],
            "sender_capture_remote_exists": sender_remote_state["exists"],
            "receiver_capture_remote_exists": receiver_remote_state["exists"],
            "sender_completed_within_window": sender_completed_within_window,
            "receiver_completed_within_window": receiver_completed_within_window,
            "receiver_window_wait_us": (
                max((receiver_exit_time - wait_start) * 1000000.0, 0.0)
                if receiver_exit_time is not None
                else None
            ),
            "window_ms": int(window_ms),
        }
        if not receiver_completed_within_window:
            sample["status"] = "window_miss"
            return sample
        if not receiver_local_state["exists"]:
            sample["status"] = "capture_missing"
            return sample

        verdict = self._single_packet_offload_verdict(run_dir, manifest, receiver_local_state)
        sample.update(verdict)
        sample["status"] = "passed" if verdict["verdict"] == "healthy" else "failed"
        return sample


def init_command(args):
    config_path = Path(args.config).resolve()
    zero_copy_defaults = _load_zero_copy_defaults(config_path)
    defaults = dict(zero_copy_defaults["runner_defaults"])
    password = _resolve_password(defaults, args.password_file)
    run_dir = Path(args.out_dir).resolve()
    if run_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % run_dir)
        shutil.rmtree(run_dir)
    experiment = _init_experiment(run_dir.name, zero_copy_defaults)
    runner = ZeroCopyRunner(output_dir=run_dir.parent, config_path=config_path, defaults=defaults, password=password)
    log_path = runner.log_dir / (run_dir.name + "_zero_copy_init.log")

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
        _augment_manifest_for_zero_copy(run_dir, manifest, zero_copy_defaults)
        _write_json(run_dir / "manifest.json", manifest)
        runner._stage_artifacts(run_dir, manifest, handle)
        runner._run_remote_script(
            handle,
            manifest["usc"]["netfpga_host"],
            run_dir / "commands" / "nf3_bringup.sh",
            tty=False,
        )

    manifest = _load_json(run_dir / "manifest.json")
    summary = _base_zero_copy_summary(run_dir, manifest)
    _write_json(run_dir / ZERO_COPY_SUMMARY_JSON, summary)
    _write_text(run_dir / ZERO_COPY_SUMMARY_MD, _render_zero_copy_summary_markdown(summary))

    print("run_dir=%s" % run_dir)
    print("manifest=%s" % (run_dir / "manifest.json"))
    print("zero_copy_summary_json=%s" % (run_dir / ZERO_COPY_SUMMARY_JSON))
    print("zero_copy_summary_md=%s" % (run_dir / ZERO_COPY_SUMMARY_MD))
    print("next_steps=threshold,limit,path")
    return 0


def run_threshold_command(args):
    run_dir = Path(args.run_dir).resolve()
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit("zero-copy manifest not found: %s" % manifest_path)
    manifest = _load_json(manifest_path)
    if "zero_copy_demo" not in manifest:
        raise SystemExit("manifest is missing zero_copy_demo section; rerun zero-copy-init")

    defaults = _runner_defaults_from_manifest(manifest)
    password = _resolve_password(defaults, args.password_file)
    runner = ZeroCopyRunner(output_dir=run_dir, config_path=manifest_path, defaults=defaults, password=password)
    labels = _load_model_labels(defaults["model"])
    zero_copy = manifest["zero_copy_demo"]
    windows_ms = (
        _parse_windows_arg(args.windows_ms)
        if args.windows_ms is not None
        else list(zero_copy["default_threshold_windows_ms"])
    )
    log_path = runner.log_dir / "zero_copy_threshold.log"
    window_results = []

    with open(log_path, "w", encoding="utf-8") as handle:
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._log(handle, "step=threshold")
        runner._log(handle, "windows_ms=%s" % ",".join(str(item) for item in windows_ms))
        for sample_index, window_ms in enumerate(windows_ms, start=1):
            sample = runner._single_window_sample(run_dir, manifest, handle, sample_index, window_ms)
            window_results.append(_build_window_measurement(run_dir, manifest, labels, sample, window_ms))

    summary = _build_threshold_summary(run_dir, manifest, log_path, windows_ms, window_results)
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, "threshold")
    _write_json(summary_json_path, summary)
    _write_text(summary_md_path, _render_threshold_markdown(summary))
    _update_zero_copy_summary(
        run_dir,
        manifest,
        "threshold",
        STEP_LABELS["threshold"],
        summary["status"],
        summary["zero_copy_verdict"],
    )
    _print_threshold_block(summary)
    return 0 if summary["zero_copy_verdict"] == "pass" else 1


def run_limit_command(args):
    run_dir = Path(args.run_dir).resolve()
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit("zero-copy manifest not found: %s" % manifest_path)
    manifest = _load_json(manifest_path)
    if "zero_copy_demo" not in manifest:
        raise SystemExit("manifest is missing zero_copy_demo section; rerun zero-copy-init")

    defaults = _runner_defaults_from_manifest(manifest)
    password = _resolve_password(defaults, args.password_file)
    runner = ZeroCopyRunner(output_dir=run_dir, config_path=manifest_path, defaults=defaults, password=password)
    labels = _load_model_labels(defaults["model"])
    zero_copy = manifest["zero_copy_demo"]
    window_ms = int(args.window_ms) if args.window_ms is not None else int(zero_copy["default_limit_window_ms"])
    if window_ms <= 0:
        raise SystemExit("--window-ms must be > 0")
    log_path = runner.log_dir / "zero_copy_limit.log"

    with open(log_path, "w", encoding="utf-8") as handle:
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._log(handle, "step=limit")
        runner._log(handle, "window_ms=%s" % window_ms)
        sample = runner._single_window_sample(run_dir, manifest, handle, sample_index=1, window_ms=window_ms)

    measurement = _build_window_measurement(run_dir, manifest, labels, sample, window_ms)
    summary = _build_limit_summary(run_dir, log_path, window_ms, measurement)
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, "limit")
    _write_json(summary_json_path, summary)
    _write_text(summary_md_path, _render_limit_markdown(summary))
    _update_zero_copy_summary(
        run_dir,
        manifest,
        "limit",
        STEP_LABELS["limit"],
        summary["status"],
        summary["zero_copy_verdict"],
    )
    _print_limit_block(summary)
    return 0 if summary["zero_copy_verdict"] == "pass" else 1


def run_path_command(args):
    run_dir = Path(args.run_dir).resolve()
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit("zero-copy manifest not found: %s" % manifest_path)
    manifest = _load_json(manifest_path)
    if "zero_copy_demo" not in manifest:
        raise SystemExit("manifest is missing zero_copy_demo section; rerun zero-copy-init")

    defaults = _runner_defaults_from_manifest(manifest)
    password = _resolve_password(defaults, args.password_file)
    runner = ZeroCopyRunner(output_dir=run_dir, config_path=manifest_path, defaults=defaults, password=password)
    labels = _load_model_labels(defaults["model"])
    zero_copy = manifest["zero_copy_demo"]
    log_path = runner.log_dir / "zero_copy_path.log"
    debug_status_path = run_dir / zero_copy["artifacts"]["path_debug_status_txt"]

    with open(log_path, "w", encoding="utf-8") as handle:
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._log(handle, "step=path")
        if zero_copy.get("clear_debug_before_path", True):
            runner._run_remote_script(
                handle,
                manifest["usc"]["netfpga_host"],
                run_dir / "commands" / "nf3_zero_copy_debug_clear.sh",
                tty=False,
            )
        sample = runner._single_window_sample(
            run_dir,
            manifest,
            handle,
            sample_index=1001,
            window_ms=max(int(float(zero_copy["path_timeout_seconds"]) * 1000.0), 1),
        )
        runner._run_remote_script(
            handle,
            manifest["usc"]["netfpga_host"],
            run_dir / "commands" / "nf3_debug_snapshot.sh",
            tty=False,
        )
        debug_name = Path(manifest["artifacts"]["debug_status_txt"]).name
        runner._run_scp(
            handle,
            "%s:%s/%s"
            % (
                manifest["usc"]["netfpga_host"],
                manifest["usc"]["remote_netfpga_results"],
                debug_name,
            ),
            str(debug_status_path),
            recursive=False,
        )

    debug_status = None
    if debug_status_path.exists():
        debug_status = board_sweep._parse_debug_status_text(debug_status_path.read_text(encoding="utf-8"))
    summary = _build_path_summary(
        run_dir,
        manifest,
        labels,
        log_path,
        sample,
        debug_status_path,
        debug_status,
    )
    summary_json_path, summary_md_path = _step_summary_paths(run_dir, "path")
    _write_json(summary_json_path, summary)
    _write_text(summary_md_path, _render_path_markdown(summary))
    _update_zero_copy_summary(
        run_dir,
        manifest,
        "path",
        STEP_LABELS["path"],
        summary["status"],
        summary["zero_copy_verdict"],
    )
    _print_path_block(summary)
    return 0 if summary["zero_copy_verdict"] == "pass" else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Run the Zero Host/OS Copy demo workflow for the RSU showcase.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init = subparsers.add_parser("init", help="prepare one zero-copy demo context and initialize the board once")
    init.add_argument("--config", default=str(DEFAULT_CONFIG))
    init.add_argument("--password-file")
    init.add_argument("--out-dir", required=True)
    init.add_argument("--force", action="store_true", default=False)
    init.set_defaults(func=init_command)

    threshold = subparsers.add_parser("threshold", help="run the offline threshold sweep over multiple windows")
    threshold.add_argument("--run-dir", required=True)
    threshold.add_argument("--password-file")
    threshold.add_argument("--windows-ms", help="comma-separated window list, e.g. 1600,800,400,200,100,50,10,1")
    threshold.set_defaults(func=run_threshold_command)

    limit = subparsers.add_parser("limit", help="run one limit-point demo window")
    limit.add_argument("--run-dir", required=True)
    limit.add_argument("--password-file")
    limit.add_argument("--window-ms", type=int, help="single window value in milliseconds")
    limit.set_defaults(func=run_limit_command)

    path = subparsers.add_parser("path", help="run the zero-copy datapath evidence demo")
    path.add_argument("--run-dir", required=True)
    path.add_argument("--password-file")
    path.set_defaults(func=run_path_command)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
