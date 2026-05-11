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
from board_debug.ann_packets import inspect_ann_frame
from board_debug.pcap_io import read_pcap_records


DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_demo_verify.json"
DEMO_SUMMARY_JSON = "demo_summary.json"
DEMO_SUMMARY_MD = "demo_summary.md"
VIEW_DEMO = "demo"
VIEW_ENGINE_SINGLE = "engine-single"
DEFAULT_TERM_WIDTH = 100
TERM_WIDTH_CAP = 100
DEFAULT_HEX_CHUNK = 64


def _status_word(passed):
    return "PASS" if passed else "FAIL"


def _coerce_request_id(value):
    if value is None:
        return None
    if isinstance(value, str):
        try:
            return "0x%04x" % int(value, 0)
        except ValueError:
            return value
    if isinstance(value, int):
        return "0x%04x" % value
    return str(value)


def _normalize_packet_summary(row):
    if row is None:
        return None
    summary = {}
    for key in (
        "frame_kind",
        "payload_magic",
        "udp_dst_port",
        "wire_result_data_0_u16",
        "wire_result_data_1_u16",
        "predicted_class",
        "predicted_score_s16",
    ):
        if row.get(key) is not None:
            summary[key] = row.get(key)
    request_id = _coerce_request_id(row.get("request_id"))
    if request_id is not None:
        summary["request_id"] = request_id
    return summary or None


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


def _format_packet_summary(summary):
    if not summary:
        return "packet detail unavailable"
    ordered = []
    for key in (
        "request_id",
        "frame_kind",
        "payload_magic",
        "udp_dst_port",
        "wire_result_data_0_u16",
        "wire_result_data_1_u16",
        "predicted_class",
        "predicted_score_s16",
    ):
        if key in summary:
            ordered.append("%s=%s" % (key, summary[key]))
    return " ".join(ordered) if ordered else "packet detail unavailable"


def _term_width():
    return min(shutil.get_terminal_size((DEFAULT_TERM_WIDTH, 20)).columns, TERM_WIDTH_CAP)


def _print_separator(char="=", width=None):
    width = width or _term_width()
    print(char * width)


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
        "request_id",
        "frame_kind",
        "payload_magic",
        "udp_dst_port",
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


def _print_kv(key, value, indent=0, key_width=11):
    prefix = " " * int(indent)
    print("%s%-*s : %s" % (prefix, int(key_width), str(key), str(value)))


def _print_wrapped_kv(key, value, indent=0, key_width=11, width=None):
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


def _print_packet(title, metadata_dict, hex_string, indent=2, width=None):
    width = width or _term_width()
    prefix = " " * int(indent)
    print("%s%s:" % (prefix, title))
    rows = _metadata_rows(metadata_dict)
    if rows:
        for key, value in rows:
            _print_wrapped_kv(key, value, indent=indent + 2, key_width=20, width=width)
    else:
        print("%spacket detail unavailable" % (" " * (indent + 2)))
    print("%shex:" % (" " * (indent + 2)))
    _print_hex_block(hex_string, indent=indent + 4, chunk=DEFAULT_HEX_CHUNK)


def _print_stage(status, label, detail, indent=2, width=None):
    width = width or _term_width()
    summary = "%s (%s) ... %s" % (label, detail, status)
    _print_wrapped_kv("Stage", summary, indent=indent, key_width=11, width=width)


class _DemoStageTracker:
    LATENCY_CAPTURE_SCRIPTS = {
        "nf4_capture_single_sender.sh",
        "nf1_capture_offload_smoke.sh",
        "nf1_capture_wrong_magic.sh",
        "nf1_capture_wrong_port.sh",
    }
    BATCH_CAPTURE_SCRIPTS = {
        "nf1_capture_offload_batch_count.sh",
        "nf4_capture_offload_batch_sender_primary.sh",
        "nf1_capture_offload_batch_time_window.sh",
        "nf4_capture_offload_batch_sender_fallback.sh",
    }
    REPLAY_SCRIPTS = {
        "nf4_replay_offload_smoke.sh",
        "nf4_replay_wrong_magic.sh",
        "nf4_replay_wrong_port.sh",
        "nf4_replay_offload_batch.sh",
    }

    def __init__(self, defaults):
        self.defaults = defaults
        self.width = _term_width()
        self.board_host = str(defaults.get("netfpga_host", "netfpga host"))
        self.sender_host = str(defaults.get("sender_host", "sender host"))
        self.receiver_host = str(defaults.get("receiver_host", "receiver host"))
        self._context = None

    def begin_run(self, label, mode):
        self._context = {
            "label": label,
            "mode": mode,
            "prepare_done": False,
            "staging_done": False,
            "bringup_done": False,
            "arming_done": False,
            "replay_done": False,
            "collect_done": False,
            "checking_done": False,
            "capture_starts": 0,
            "latency_fetches": 0,
        }

    def _active(self):
        return self._context is not None

    def _detail(self, stage_key):
        details = {
            "prepare": "local prepare + manifest build",
            "staging": "copy bundle and pcaps to %s, %s, %s" % (self.board_host, self.sender_host, self.receiver_host),
            "bringup": "download bitfile and enable engine on %s" % self.board_host,
            "arming": "capture on %s and %s" % (self.sender_host, self.receiver_host),
            "replay": "replay on %s" % self.sender_host,
            "collect": "fetch captures from %s and %s" % (self.sender_host, self.receiver_host),
            "check_latency": "parse result packet and compare expected output",
            "check_batch": "run batch report and compare expected outputs",
            "write": "write demo_summary and detailed summary files",
        }
        return details[stage_key]

    def _emit_done(self, stage_key, label):
        _print_stage("DONE", label, self._detail(stage_key), indent=2, width=self.width)

    def _emit_fail(self, stage_key, label):
        _print_stage("FAIL", label, self._detail(stage_key), indent=2, width=self.width)

    def _check_stage_key(self):
        if not self._active():
            return "check_batch"
        return "check_batch" if self._context["mode"] == "batch_completion" else "check_latency"

    def mark_prepare_done(self):
        if self._active() and not self._context["prepare_done"]:
            self._context["prepare_done"] = True
            self._emit_done("prepare", "Preparing Demo Run")

    def mark_staging_done(self):
        if self._active() and not self._context["staging_done"]:
            self._context["staging_done"] = True
            self._emit_done("staging", "Staging Remote Artifacts")

    def mark_bringup_done(self):
        if self._active() and not self._context["bringup_done"]:
            self._context["bringup_done"] = True
            self._emit_done("bringup", "Bringing Up Board")

    def record_capture_start(self):
        if not self._active():
            return
        self._context["capture_starts"] += 1
        if not self._context["arming_done"] and self._context["capture_starts"] >= 2:
            self._context["arming_done"] = True
            self._emit_done("arming", "Arming Capture")

    def mark_replay_done(self):
        if self._active() and not self._context["replay_done"]:
            self._context["replay_done"] = True
            self._emit_done("replay", "Sending Request Packet")

    def record_latency_fetch(self):
        if not self._active():
            return
        self._context["latency_fetches"] += 1
        if not self._context["collect_done"] and self._context["latency_fetches"] >= 2:
            self._context["collect_done"] = True
            self._emit_done("collect", "Collecting Result Packet")

    def mark_collect_done(self):
        if self._active() and not self._context["collect_done"]:
            self._context["collect_done"] = True
            self._emit_done("collect", "Collecting Result Packet")

    def mark_check_done(self):
        if self._active() and not self._context["checking_done"]:
            self._context["checking_done"] = True
            self._emit_done(self._check_stage_key(), "Checking Inference Result")

    def mark_write_done(self):
        _print_stage("DONE", "Writing Demo Summary", self._detail("write"), indent=2, width=self.width)

    def fail_current(self, exc):
        if not self._active():
            return
        if not self._context["prepare_done"]:
            self._emit_fail("prepare", "Preparing Demo Run")
        elif not self._context["staging_done"]:
            self._emit_fail("staging", "Staging Remote Artifacts")
        elif not self._context["bringup_done"]:
            self._emit_fail("bringup", "Bringing Up Board")
        elif not self._context["arming_done"]:
            self._emit_fail("arming", "Arming Capture")
        elif not self._context["replay_done"]:
            self._emit_fail("replay", "Sending Request Packet")
        elif not self._context["collect_done"]:
            self._emit_fail("collect", "Collecting Result Packet")
        else:
            self._emit_fail(self._check_stage_key(), "Checking Inference Result")


class DemoMetricsRunner(board_metrics.MetricsRunner):
    def __init__(self, *args, stage_tracker=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.stage_tracker = stage_tracker

    def _observe_local_command(self, command):
        if self.stage_tracker is None:
            return
        joined = " ".join(str(part) for part in command)
        if "boardctl.py capture" in joined:
            self.stage_tracker.mark_prepare_done()
        elif "boardctl.py report" in joined:
            self.stage_tracker.mark_collect_done()

    def _run_local(self, handle, command, cwd=None, check=True):
        result = super()._run_local(handle, command, cwd=cwd, check=check)
        self._observe_local_command(command)
        if self.stage_tracker is not None:
            joined = " ".join(str(part) for part in command)
            if "boardctl.py report" in joined:
                self.stage_tracker.mark_check_done()
        return result

    def _run_remote_script(self, handle, host, script_path, tty, check=True):
        script_name = Path(script_path).name
        if self.stage_tracker is not None and script_name == "nf3_bringup.sh":
            self.stage_tracker.mark_staging_done()
        result = super()._run_remote_script(handle, host, script_path, tty, check=check)
        if self.stage_tracker is None:
            return result
        if script_name == "nf3_bringup.sh":
            self.stage_tracker.mark_bringup_done()
        elif script_name in _DemoStageTracker.REPLAY_SCRIPTS:
            self.stage_tracker.mark_replay_done()
        return result

    def _start_remote_script(self, handle, host, script_path, tty):
        async_run = super()._start_remote_script(handle, host, script_path, tty)
        if self.stage_tracker is None:
            return async_run
        script_name = Path(script_path).name
        if script_name in _DemoStageTracker.LATENCY_CAPTURE_SCRIPTS or script_name in _DemoStageTracker.BATCH_CAPTURE_SCRIPTS:
            self.stage_tracker.record_capture_start()
        return async_run

    def _fetch_remote_capture(self, handle, host, remote_path, local_path):
        remote_state, local_state = super()._fetch_remote_capture(handle, host, remote_path, local_path)
        if self.stage_tracker is not None:
            self.stage_tracker.record_latency_fetch()
        return remote_state, local_state


def _read_first_pcap_packet(path):
    packet_path = Path(path)
    if not packet_path.exists():
        return None
    records = read_pcap_records(packet_path)
    if not records:
        return None
    row = inspect_ann_frame(records[0]["frame"])
    return {
        "summary": _normalize_packet_summary(row),
        "wire_frame_hex": row.get("wire_frame_hex"),
    }


def _single_packet_packet_evidence(result, output_dir):
    measured = _measured_latency_samples(result)
    if not measured:
        return {
            "sent_packet_summary": None,
            "sent_packet_hex": None,
            "received_packet_summary": None,
            "received_packet_hex": None,
        }
    sample = measured[0]
    sent = _read_first_pcap_packet(output_dir / sample["sender_capture_path"]) if sample.get("sender_capture_path") else None
    received = _read_first_pcap_packet(output_dir / sample["receiver_capture_path"]) if sample.get("receiver_capture_path") else None
    return {
        "sent_packet_summary": sent["summary"] if sent else None,
        "sent_packet_hex": sent["wire_frame_hex"] if sent else None,
        "received_packet_summary": received["summary"] if received else None,
        "received_packet_hex": received["wire_frame_hex"] if received else None,
    }


def _batch_packet_evidence(result):
    run_dir = Path(result.get("run_dir", ""))
    sent_summary = None
    sent_hex = None
    meta_path = run_dir / "pcaps" / "offload_meta.json"
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            batch_frames = meta.get("batch_frames") or []
            if batch_frames:
                first = batch_frames[0]
                sent_hex = first.get("wire_frame_hex")
                if sent_hex:
                    sent_summary = _normalize_packet_summary(inspect_ann_frame(bytes.fromhex(sent_hex)))
        except (OSError, ValueError, json.JSONDecodeError):
            sent_summary = None
            sent_hex = None

    received_summary = None
    received_hex = None
    observed_path = run_dir / "observed_results.json"
    if observed_path.exists():
        try:
            observed_rows = json.loads(observed_path.read_text(encoding="utf-8"))
            if observed_rows:
                row = observed_rows[0]
                received_summary = _normalize_packet_summary(row)
                received_hex = row.get("wire_frame_hex")
        except (OSError, ValueError, json.JSONDecodeError):
            received_summary = None
            received_hex = None
    return {
        "sent_packet_summary": sent_summary,
        "sent_packet_hex": sent_hex,
        "received_packet_summary": received_summary,
        "received_packet_hex": received_hex,
    }


def _packet_evidence(result, output_dir):
    if result.get("mode") == "latency_single":
        return _single_packet_packet_evidence(result, output_dir)
    if result.get("mode") == "batch_completion":
        return _batch_packet_evidence(result)
    return {
        "sent_packet_summary": None,
        "sent_packet_hex": None,
        "received_packet_summary": None,
        "received_packet_hex": None,
    }


def _result_label(result):
    mode = result.get("mode")
    if mode == "latency_single":
        variant = str(result.get("single_packet_variant", "offload")).replace("_", " ")
        return "Single-Packet %s" % variant.title()
    if mode == "batch_completion":
        return "Batch Correctness (batch=%s)" % result.get("batch_size", "?")
    return str(result.get("experiment_name") or result.get("run_name") or "Experiment")


def _measured_latency_samples(result):
    return [item for item in result.get("sample_results", []) if item.get("phase") == "measure"]


def _latency_toolchain_pass(result):
    measured = _measured_latency_samples(result)
    if not measured:
        return False
    return all(
        (not item.get("timed_out"))
        and item.get("sender_capture_exists")
        and item.get("receiver_capture_exists")
        for item in measured
    )


def _latency_inference_pass(result):
    measured = _measured_latency_samples(result)
    if not measured:
        return False
    return all(item.get("status") == "passed" for item in measured)


def _batch_toolchain_pass(result):
    return bool(
        result.get("sender_capture_local_exists")
        and result.get("receiver_capture_local_exists")
        and result.get("report_exit_code") is not None
    )


def _batch_inference_pass(result):
    return (
        result.get("correctness_verdict") == "healthy"
        and int(result.get("mismatch_count") or 0) == 0
        and int(result.get("missing_sample_count") or 0) == 0
    )


def _result_toolchain_pass(result):
    if result.get("mode") == "latency_single":
        return _latency_toolchain_pass(result)
    if result.get("mode") == "batch_completion":
        return _batch_toolchain_pass(result)
    return False


def _result_inference_pass(result):
    if result.get("mode") == "latency_single":
        return _latency_inference_pass(result)
    if result.get("mode") == "batch_completion":
        return _batch_inference_pass(result)
    return False


def _result_evidence(result):
    if result.get("mode") == "latency_single":
        measured = _measured_latency_samples(result)
        sample_count = len(measured)
        pass_count = len([item for item in measured if item.get("status") == "passed"])
        if sample_count == 0:
            return "no measured single-packet sample completed"
        if pass_count == sample_count:
            return "%d/%d offload sample matched expected result" % (pass_count, sample_count)
        timeout_count = len([item for item in measured if item.get("timed_out")])
        return "%d/%d sample passed, %d timeout" % (pass_count, sample_count, timeout_count)
    if result.get("mode") == "batch_completion":
        matched = int(result.get("receiver_capture_count") or 0)
        expected = int(result.get("batch_size") or 0)
        mismatches = int(result.get("mismatch_count") or 0)
        if mismatches == 0 and matched == expected:
            return "%d/%d batch results matched expected outputs" % (matched, expected)
        return "%d/%d results matched, mismatch_count=%d" % (matched, expected, mismatches)
    return "no demo evidence"


def _inference_check(result):
    if _result_inference_pass(result):
        if result.get("mode") == "latency_single":
            return "MATCHED EXPECTED OFFLOAD RESULT"
        if result.get("mode") == "batch_completion":
            return "MATCHED EXPECTED BATCH RESULTS"
        return "MATCHED EXPECTED"
    if result.get("mode") == "batch_completion":
        return "MISMATCH (mismatch_count=%s)" % (result.get("mismatch_count") or 0)
    return "MISMATCH"


def _result_failure_stage(result):
    if not _result_toolchain_pass(result):
        if result.get("mode") == "latency_single":
            measured = _measured_latency_samples(result)
            if not measured:
                return "single_packet_sample"
            if any(item.get("timed_out") for item in measured):
                return "capture_timeout"
            if any(not item.get("sender_capture_exists") or not item.get("receiver_capture_exists") for item in measured):
                return "capture_fetch"
            return "toolchain"
        if result.get("mode") == "batch_completion":
            if result.get("report_exit_code") is None:
                return str(result.get("failed_step") or "report")
            if not result.get("sender_capture_local_exists") or not result.get("receiver_capture_local_exists"):
                return "capture_fetch"
            return "report"
    if not _result_inference_pass(result):
        return "inference"
    return None


def _demo_result_view(result, output_dir, labels=None):
    toolchain_pass = _result_toolchain_pass(result)
    inference_pass = _result_inference_pass(result)
    packet_evidence = _packet_evidence(result, output_dir)
    received_packet_summary = packet_evidence["received_packet_summary"]
    return {
        "label": _result_label(result),
        "run_name": result.get("run_name"),
        "mode": result.get("mode"),
        "status": result.get("status"),
        "toolchain_verdict": "pass" if toolchain_pass else "fail",
        "inference_verdict": "pass" if inference_pass else "fail",
        "overall_verdict": "pass" if (toolchain_pass and inference_pass) else "fail",
        "evidence": _result_evidence(result),
        "inference_check": _inference_check(result),
        "failure_stage": _result_failure_stage(result),
        "runner_log": result.get("runner_log"),
        "summary_md": result.get("summary_md"),
        "report_json": result.get("report_json"),
        "batch_size": result.get("batch_size"),
        "single_packet_variant": result.get("single_packet_variant"),
        "sent_packet_summary": packet_evidence["sent_packet_summary"],
        "sent_packet_hex": packet_evidence["sent_packet_hex"],
        "received_packet_summary": received_packet_summary,
        "received_packet_hex": packet_evidence["received_packet_hex"],
        "predicted_label": _predicted_label(received_packet_summary, labels or []),
        "raw_result": result,
    }


def _build_demo_summary(config_path, output_dir, detailed_summary, results, labels=None, demo_name="rsu_demo_verify", view=VIEW_DEMO):
    views = [_demo_result_view(item, output_dir, labels=labels) for item in results]
    toolchain_pass = all(item["toolchain_verdict"] == "pass" for item in views) and bool(views)
    inference_pass = all(item["inference_verdict"] == "pass" for item in views) and bool(views)
    overall_pass = toolchain_pass and inference_pass
    return {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "demo_name": demo_name,
        "view": view,
        "config_path": str(config_path),
        "output_dir": str(output_dir),
        "toolchain_verdict": "pass" if toolchain_pass else "fail",
        "inference_verdict": "pass" if inference_pass else "fail",
        "overall_verdict": "pass" if overall_pass else "fail",
        "proof_runs": [
            {
                "label": item["label"],
                "run_name": item["run_name"],
                "mode": item["mode"],
                "status": item["status"],
                "toolchain_verdict": item["toolchain_verdict"],
                "inference_verdict": item["inference_verdict"],
                "overall_verdict": item["overall_verdict"],
                "failure_stage": item["failure_stage"],
                "evidence": item["evidence"],
                "inference_check": item["inference_check"],
                "sent_packet_summary": item["sent_packet_summary"],
                "sent_packet_hex": item["sent_packet_hex"],
                "received_packet_summary": item["received_packet_summary"],
                "received_packet_hex": item["received_packet_hex"],
                "predicted_label": item.get("predicted_label"),
                "runner_log": item["runner_log"],
                "summary_md": item["summary_md"],
                "report_json": item["report_json"],
                "batch_size": item["batch_size"],
                "single_packet_variant": item["single_packet_variant"],
            }
            for item in views
        ],
        "artifacts": {
            "detailed_summary_json": "summary.json",
            "detailed_summary_md": "summary.md",
            "demo_summary_json": DEMO_SUMMARY_JSON,
            "demo_summary_md": DEMO_SUMMARY_MD,
        },
        "detailed_runs_total": detailed_summary["runs_total"],
        "detailed_runs_passed": detailed_summary["runs_passed"],
        "detailed_runs_failed": detailed_summary["runs_failed"],
    }


def _build_engine_single_summary(config_path, output_dir, detailed_summary, results, labels=None, demo_name="rsu_engine_single_infer"):
    views = [_demo_result_view(item, output_dir, labels=labels) for item in results]
    item = views[0] if views else {}
    received = item.get("received_packet_summary") or {}
    sent = item.get("sent_packet_summary") or {}
    request_id = received.get("request_id") or sent.get("request_id")
    return {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "demo_name": demo_name,
        "view": VIEW_ENGINE_SINGLE,
        "config_path": str(config_path),
        "output_dir": str(output_dir),
        "run_name": item.get("run_name"),
        "overall_verdict": item.get("overall_verdict", "fail"),
        "request_id": request_id,
        "predicted_class": received.get("predicted_class"),
        "predicted_label": item.get("predicted_label"),
        "predicted_score_s16": received.get("predicted_score_s16"),
        "inference_check": item.get("inference_check"),
        "failure_stage": item.get("failure_stage"),
        "sent_packet_summary": sent or None,
        "sent_packet_hex": item.get("sent_packet_hex"),
        "received_packet_summary": received or None,
        "received_packet_hex": item.get("received_packet_hex"),
        "runner_log": item.get("runner_log"),
        "artifacts": {
            "detailed_summary_json": "summary.json",
            "detailed_summary_md": "summary.md",
            "demo_summary_json": DEMO_SUMMARY_JSON,
            "demo_summary_md": DEMO_SUMMARY_MD,
        },
    }


def _render_demo_markdown(summary):
    lines = [
        "# RSU Demo Verification",
        "",
        "- overall_verdict: `%s`" % _status_word(summary["overall_verdict"] == "pass"),
        "- toolchain_verdict: `%s`" % _status_word(summary["toolchain_verdict"] == "pass"),
        "- inference_verdict: `%s`" % _status_word(summary["inference_verdict"] == "pass"),
        "- config_path: `%s`" % summary["config_path"],
        "- output_dir: `%s`" % summary["output_dir"],
        "",
        "## Proof Runs",
        "",
        "| Check | Toolchain | Inference | Overall | Evidence |",
        "| --- | --- | --- | --- | --- |",
    ]
    for item in summary["proof_runs"]:
        lines.append(
            "| {label} | {toolchain} | {inference} | {overall} | {evidence} |".format(
                label=item["label"],
                toolchain=_status_word(item["toolchain_verdict"] == "pass"),
                inference=_status_word(item["inference_verdict"] == "pass"),
                overall=_status_word(item["overall_verdict"] == "pass"),
                evidence=item["evidence"],
            )
        )
        lines.extend(
            [
                "",
                "- sent_packet: `%s`" % _format_packet_summary(item.get("sent_packet_summary")),
                "- received_packet: `%s`" % _format_packet_summary(item.get("received_packet_summary")),
                "- predicted_label: `%s`" % (item.get("predicted_label") or "unavailable"),
                "- inference_check: `%s`" % item.get("inference_check", "unavailable"),
                "",
                "```text",
                "sent_wire_hex=%s" % (item.get("sent_packet_hex") or "unavailable"),
                "received_wire_hex=%s" % (item.get("received_packet_hex") or "unavailable"),
                "```",
                "",
            ]
        )
    lines.extend(
        [
            "## Artifacts",
            "",
            "- demo_summary_json: `%s`" % summary["artifacts"]["demo_summary_json"],
            "- demo_summary_md: `%s`" % summary["artifacts"]["demo_summary_md"],
            "- detailed_summary_json: `%s`" % summary["artifacts"]["detailed_summary_json"],
            "- detailed_summary_md: `%s`" % summary["artifacts"]["detailed_summary_md"],
        ]
    )
    return "\n".join(lines) + "\n"


def _render_engine_single_markdown(summary):
    lines = [
        "# RSU Cuda-like Engine Demo",
        "",
        "- overall_verdict: `%s`" % _status_word(summary["overall_verdict"] == "pass"),
        "- request_id: `%s`" % (summary.get("request_id") or "unavailable"),
        "- predicted_class: `%s`" % (
            summary["predicted_class"] if summary.get("predicted_class") is not None else "unavailable"
        ),
        "- predicted_label: `%s`" % (summary.get("predicted_label") or "unavailable"),
        "- predicted_score_s16: `%s`" % (
            summary["predicted_score_s16"] if summary.get("predicted_score_s16") is not None else "unavailable"
        ),
        "- inference_check: `%s`" % (summary.get("inference_check") or "unavailable"),
        "- config_path: `%s`" % summary["config_path"],
        "- output_dir: `%s`" % summary["output_dir"],
        "",
        "## Packets",
        "",
        "- sent_packet: `%s`" % _format_packet_summary(summary.get("sent_packet_summary")),
        "- received_packet: `%s`" % _format_packet_summary(summary.get("received_packet_summary")),
        "",
        "```text",
        "sent_wire_hex=%s" % (summary.get("sent_packet_hex") or "unavailable"),
        "received_wire_hex=%s" % (summary.get("received_packet_hex") or "unavailable"),
        "```",
        "",
        "## Artifacts",
        "",
        "- demo_summary_json: `%s`" % summary["artifacts"]["demo_summary_json"],
        "- demo_summary_md: `%s`" % summary["artifacts"]["demo_summary_md"],
        "- detailed_summary_json: `%s`" % summary["artifacts"]["detailed_summary_json"],
        "- detailed_summary_md: `%s`" % summary["artifacts"]["detailed_summary_md"],
    ]
    return "\n".join(lines) + "\n"


def _write_detailed_summary(output_dir, config_path, results):
    summary = {
        "schema_version": 2,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "config_path": str(config_path),
        "output_dir": str(output_dir),
        "runs_total": len(results),
        "runs_passed": len([item for item in results if item.get("board_passed")]),
        "runs_failed": len([item for item in results if not item.get("board_passed")]),
        "results": results,
    }
    board_metrics._write_json(output_dir / "summary.json", summary)
    board_metrics._write_text(
        output_dir / "summary.md",
        board_metrics._render_markdown_summary(output_dir, config_path, results),
    )
    return summary


def _print_banner(output_dir):
    width = _term_width()
    _print_separator("=", width)
    print("RSU Demo Verification")
    _print_separator("=", width)
    _print_wrapped_kv(
        "Goal",
        "Prove the toolchain runs end-to-end and inference results are correct.",
        key_width=10,
        width=width,
    )
    _print_wrapped_kv("Scope", "single-packet offload + small batch correctness", key_width=10, width=width)
    _print_wrapped_kv("Output Dir", output_dir, key_width=10, width=width)
    print()


def _print_engine_banner(output_dir):
    width = _term_width()
    _print_separator("=", width)
    print("RSU Cuda-like Engine Demo")
    _print_separator("=", width)
    _print_wrapped_kv(
        "Goal",
        "Show the engine accepts one ANN task packet and returns a classification result.",
        key_width=10,
        width=width,
    )
    _print_wrapped_kv("Scope", "single-packet offload only", key_width=10, width=width)
    _print_wrapped_kv("Output Dir", output_dir, key_width=10, width=width)
    print()


def _print_result_header(index, total, label):
    print("[%d/%d] %s" % (index, total, label))


def _print_result_block(view, verbose):
    width = _term_width()
    _print_kv("Toolchain", _status_word(view["toolchain_verdict"] == "pass"), indent=2, key_width=10)
    _print_kv("Inference", _status_word(view["inference_verdict"] == "pass"), indent=2, key_width=10)
    _print_kv("Result", _status_word(view["overall_verdict"] == "pass"), indent=2, key_width=10)
    _print_wrapped_kv("Evidence", view["evidence"], indent=2, key_width=10, width=width)
    print()
    _print_packet("Sent Packet", view.get("sent_packet_summary"), view.get("sent_packet_hex"), indent=2, width=width)
    print()
    _print_packet(
        "Received Packet",
        view.get("received_packet_summary"),
        view.get("received_packet_hex"),
        indent=2,
        width=width,
    )
    print()
    _print_wrapped_kv("Inference Check", view.get("inference_check", "unavailable"), indent=2, key_width=16, width=width)
    if view["failure_stage"] is not None:
        _print_kv("Failed At", view["failure_stage"], indent=2, key_width=10)
    if verbose:
        if view["runner_log"]:
            _print_wrapped_kv("Runner Log", view["runner_log"], indent=2, key_width=10, width=width)
        if view["summary_md"]:
            _print_wrapped_kv("Summary", view["summary_md"], indent=2, key_width=10, width=width)
        if view["report_json"]:
            _print_wrapped_kv("Report", view["report_json"], indent=2, key_width=10, width=width)
    print()


def _print_engine_result_block(view, verbose):
    width = _term_width()
    observed = view.get("received_packet_summary") or {}
    _print_kv("Engine Step", view["label"], indent=2, key_width=16)
    _print_kv("Result", _status_word(view["overall_verdict"] == "pass"), indent=2, key_width=16)
    _print_kv("Predicted Class", observed.get("predicted_class", "n/a"), indent=2, key_width=16)
    _print_kv("Predicted Label", view.get("predicted_label", "n/a") or "n/a", indent=2, key_width=16)
    _print_kv("Predicted Score", observed.get("predicted_score_s16", "n/a"), indent=2, key_width=16)
    _print_wrapped_kv("Inference Check", view.get("inference_check", "unavailable"), indent=2, key_width=16, width=width)
    if view["failure_stage"] is not None:
        _print_kv("Failed At", view["failure_stage"], indent=2, key_width=16)
    print()
    _print_packet("Sent Packet", view.get("sent_packet_summary"), view.get("sent_packet_hex"), indent=2, width=width)
    print()
    _print_packet("Observed Result", view.get("received_packet_summary"), view.get("received_packet_hex"), indent=2, width=width)
    if verbose:
        print()
        if view["runner_log"]:
            _print_wrapped_kv("Runner Log", view["runner_log"], indent=2, key_width=16, width=width)
        if view["summary_md"]:
            _print_wrapped_kv("Summary", view["summary_md"], indent=2, key_width=16, width=width)
        if view["report_json"]:
            _print_wrapped_kv("Report", view["report_json"], indent=2, key_width=16, width=width)
    print()


def _print_final_block(summary):
    width = _term_width()
    output_dir = Path(summary["output_dir"])
    _print_separator("-", width)
    _print_kv("Toolchain Status", _status_word(summary["toolchain_verdict"] == "pass"), key_width=17)
    _print_kv("Inference Status", _status_word(summary["inference_verdict"] == "pass"), key_width=17)
    _print_kv("Overall Demo", _status_word(summary["overall_verdict"] == "pass"), key_width=17)
    _print_separator("-", width)
    print()
    print("Artifacts:")
    artifact_labels = (
        ("demo_summary_json", "demo_summary_json"),
        ("demo_summary_md", "demo_summary_md"),
        ("detailed_summary_json", "detailed_summary_json"),
        ("detailed_summary_md", "detailed_summary_md"),
    )
    for label, key in artifact_labels:
        _print_wrapped_kv(label, output_dir / summary["artifacts"][key], indent=2, key_width=21, width=width)


def _print_engine_final_block(summary):
    width = _term_width()
    output_dir = Path(summary["output_dir"])
    _print_separator("-", width)
    _print_kv("Single Inference", _status_word(summary["overall_verdict"] == "pass"), key_width=17)
    _print_separator("-", width)
    print()
    print("Artifacts:")
    artifact_labels = (
        ("demo_summary_json", "demo_summary_json"),
        ("demo_summary_md", "demo_summary_md"),
        ("detailed_summary_json", "detailed_summary_json"),
        ("detailed_summary_md", "detailed_summary_md"),
    )
    for label, key in artifact_labels:
        _print_wrapped_kv(label, output_dir / summary["artifacts"][key], indent=2, key_width=21, width=width)


def _render_view_markdown(summary):
    if summary.get("view") == VIEW_ENGINE_SINGLE:
        return _render_engine_single_markdown(summary)
    return _render_demo_markdown(summary)


def _validate_view(view_name, experiments):
    if view_name != VIEW_ENGINE_SINGLE:
        return
    if len(experiments) != 1:
        raise SystemExit("engine-single view requires exactly one experiment")
    experiment = experiments[0]
    if experiment.get("mode") != "latency_single" or experiment.get("single_packet_variant") != "offload":
        raise SystemExit("engine-single view requires one latency_single offload experiment")


def _run_experiment(runner, experiment):
    if experiment["mode"] == "latency_single":
        return runner.execute_latency_experiment(experiment)
    if experiment["mode"] == "batch_completion":
        return runner.execute_batch_completion_experiment(experiment)
    raise SystemExit("unsupported demo mode: %s" % experiment["mode"])


def build_parser():
    parser = argparse.ArgumentParser(description="Run a demo-style RSU verification smoke and print presentation-oriented output.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--password-file")
    parser.add_argument("--ssh-mode", choices=["sshpass", "system"])
    parser.add_argument("--out-dir")
    parser.add_argument("--view", choices=[VIEW_DEMO, VIEW_ENGINE_SINGLE], default=VIEW_DEMO)
    parser.add_argument("--force", action="store_true", default=False)
    parser.add_argument("--verbose", action="store_true", default=False)
    return parser


def main():
    args = build_parser().parse_args()
    config_path = Path(args.config).resolve()
    config = board_sweep._load_config(config_path)
    if args.password_file is not None:
        config["password_file"] = args.password_file
    if args.ssh_mode is not None:
        config["ssh_mode"] = args.ssh_mode
    defaults, experiments = board_metrics._normalize_metric_experiments(config, config_path.parent)
    _validate_view(args.view, experiments)
    labels = _load_model_labels(defaults["model"])

    board_sweep._ensure_local_dependency("ssh")
    board_sweep._ensure_local_dependency("scp")
    password = None
    if defaults["ssh_mode"] == "sshpass":
        board_sweep._ensure_local_dependency("sshpass")
        password = board_sweep._resolve_password(defaults["ssh_mode"], defaults.get("password_file"))

    output_dir = (
        Path(args.out_dir).resolve()
        if args.out_dir
        else (ROOT_DIR / "runs" / ("demo_verify_" + datetime.now().strftime("%Y%m%d_%H%M%S")))
    )
    if output_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % output_dir)
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    stage_tracker = _DemoStageTracker(defaults)
    runner = DemoMetricsRunner(
        output_dir=output_dir,
        config_path=config_path,
        defaults=defaults,
        password=password,
        stage_tracker=stage_tracker,
    )
    results = []
    banner_printer = _print_engine_banner if args.view == VIEW_ENGINE_SINGLE else _print_banner
    result_printer = _print_engine_result_block if args.view == VIEW_ENGINE_SINGLE else _print_result_block
    final_printer = _print_engine_final_block if args.view == VIEW_ENGINE_SINGLE else _print_final_block
    demo_name = "rsu_engine_single_infer" if args.view == VIEW_ENGINE_SINGLE else "rsu_demo_verify"
    banner_printer(output_dir)
    for index, experiment in enumerate(experiments, start=1):
        label = _result_label(experiment)
        _print_result_header(index, len(experiments), label)
        stage_tracker.begin_run(label, experiment["mode"])
        try:
            result = _run_experiment(runner, experiment)
            stage_tracker.mark_check_done()
        except Exception as exc:
            stage_tracker.fail_current(exc)
            result = {
                "experiment_name": experiment["name"],
                "mode": experiment["mode"],
                "run_name": experiment["run_name"],
                "status": "runner_exception",
                "board_passed": False,
                "error": str(exc),
                "runner_log": board_sweep._relpath(runner._metrics_log_path(experiment["run_name"]), output_dir),
            }
            results.append(result)
            result_printer(_demo_result_view(result, output_dir, labels=labels), args.verbose)
            break
        results.append(result)
        result_printer(_demo_result_view(result, output_dir, labels=labels), args.verbose)

    detailed_summary = _write_detailed_summary(output_dir, config_path, results)
    if args.view == VIEW_ENGINE_SINGLE:
        demo_summary = _build_engine_single_summary(
            config_path,
            output_dir,
            detailed_summary,
            results,
            labels=labels,
            demo_name=demo_name,
        )
    else:
        demo_summary = _build_demo_summary(
            config_path,
            output_dir,
            detailed_summary,
            results,
            labels=labels,
            demo_name=demo_name,
            view=args.view,
        )
    board_metrics._write_json(output_dir / DEMO_SUMMARY_JSON, demo_summary)
    board_metrics._write_text(output_dir / DEMO_SUMMARY_MD, _render_view_markdown(demo_summary))
    stage_tracker.mark_write_done()
    print()
    final_printer(demo_summary)
    return 0 if demo_summary["overall_verdict"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
