#!/usr/bin/env python3

import argparse
import json
import math
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import board_sweep
from board_debug.model_batch_eval import compare_expected_observed, observed_rows_from_frames
from board_debug.pcap_io import read_pcap_records, write_pcap


DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_nic_metrics.json"
DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS = 2.0
DEFAULT_COMPLETION_TIMEOUT_SECONDS = 5.0
DEFAULT_DRAIN_TIMEOUT_SECONDS = 2.0
DEFAULT_LATENCY_WARMUP_COUNT = 10
DEFAULT_LATENCY_SAMPLE_COUNT = 50
DEFAULT_INTER_SAMPLE_PAUSE_SECONDS = 0.0
DEFAULT_BATCH_REPEATS = 5
DEFAULT_SEND_DURATION_SECONDS = 10.0
DEFAULT_RATE_REPEATS = 3
DEFAULT_RATE_POINTS = [10, 25, 50, 100]
DEFAULT_RATE_ACCURACY_TOLERANCE_RATIO = 0.20
DEFAULT_RATE_CHUNK_TARGET_SECONDS = 0.25
RATE_RECEIVER_CAPTURE_NAME = "offload_rate_receiver.cap"
RATE_SENDER_CAPTURE_NAME = "offload_rate_sender.cap"
SINGLE_SENDER_CAPTURE_NAME = "offload_smoke_sender.cap"
RATE_PACKET_DIR_NAME = "rate_packets"
RATE_CHUNK_DIR_NAME = "rate_chunks"
RATE_PACED_PCAP_NAME = "offload_rate_paced.pcap"
LATENCY_STATUS_UNSUPPORTED = "unsupported_without_clock_sync"
TIMING_MODE_NONE = "none"
RATE_GENERATION_MODE_AUTO = "auto"
RATE_GENERATION_MODE_PACED = "paced_pcap_single_replay"
RATE_GENERATION_MODE_CHUNKED = "chunked_replay_fallback"
RATE_ACCURACY_STATUS_WITHIN_TOLERANCE = "within_tolerance"
RATE_ACCURACY_STATUS_OUTSIDE_TOLERANCE = "outside_tolerance"
RATE_ACCURACY_STATUS_MISSING_SEND_RATE = "missing_send_rate"
RATE_ACCURACY_STATUS_SENDER_COUNT_MISMATCH = "sender_count_mismatch"
RATE_ACCURACY_STATUS_PIPELINE_FAILED = "pipeline_failed"


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


def _percentile(sorted_values, percentile):
    if not sorted_values:
        return None
    if len(sorted_values) == 1:
        return sorted_values[0]
    rank = (len(sorted_values) - 1) * (float(percentile) / 100.0)
    lower = int(math.floor(rank))
    upper = int(math.ceil(rank))
    if lower == upper:
        return sorted_values[lower]
    weight = rank - lower
    return sorted_values[lower] + ((sorted_values[upper] - sorted_values[lower]) * weight)


def _latency_summary(latency_us_values):
    if not latency_us_values:
        return {
            "latency_p50_us": None,
            "latency_p95_us": None,
            "latency_p99_us": None,
            "latency_max_us": None,
        }
    values = sorted(float(item) for item in latency_us_values)
    return {
        "latency_p50_us": _percentile(values, 50),
        "latency_p95_us": _percentile(values, 95),
        "latency_p99_us": _percentile(values, 99),
        "latency_max_us": values[-1],
    }


def _normalize_metric_experiments(config, config_dir):
    defaults = board_sweep._normalize_defaults(config, config_dir)
    expanded = []
    for raw_index, item in enumerate(config["experiments"], start=1):
        if not isinstance(item, dict):
            raise SystemExit("metric experiment entries must be JSON objects")
        name = str(item.get("name") or ("metric_%02d" % raw_index))
        mode = str(item.get("mode") or "").strip()
        if mode == "latency_single":
            run_name = "%s_r01" % board_sweep._slugify(name)
            expanded.append(
                {
                    "name": name,
                    "mode": mode,
                    "run_name": run_name,
                    "prepare_limit": 1,
                    "prepare_request_id_base": item.get("request_id_base", "0x1234"),
                    "prepare_batch_time_window_seconds": float(item.get("single_result_timeout_seconds", DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS)),
                    "warmup_count": int(item.get("warmup_count", DEFAULT_LATENCY_WARMUP_COUNT)),
                    "sample_count": int(item.get("sample_count", DEFAULT_LATENCY_SAMPLE_COUNT)),
                    "single_result_timeout_seconds": float(item.get("single_result_timeout_seconds", DEFAULT_SINGLE_RESULT_TIMEOUT_SECONDS)),
                    "inter_sample_pause_seconds": float(item.get("inter_sample_pause_seconds", DEFAULT_INTER_SAMPLE_PAUSE_SECONDS)),
                    "request_id_base": item.get("request_id_base", "0x1234"),
                }
            )
            continue
        if mode == "batch_completion":
            repeats = int(item.get("repeats", DEFAULT_BATCH_REPEATS))
            batch_size = int(item["batch_size"])
            for repeat_index in range(1, repeats + 1):
                run_name = "%s_r%02d" % (board_sweep._slugify(name), repeat_index)
                expanded.append(
                    {
                        "name": name,
                        "mode": mode,
                        "run_name": run_name,
                        "repeat_index": repeat_index,
                        "prepare_limit": batch_size,
                        "prepare_request_id_base": item.get("request_id_base", "0x1234"),
                        "prepare_batch_time_window_seconds": float(item.get("completion_timeout_seconds", DEFAULT_COMPLETION_TIMEOUT_SECONDS)),
                        "batch_size": batch_size,
                        "batch_time_window_seconds": float(item.get("completion_timeout_seconds", DEFAULT_COMPLETION_TIMEOUT_SECONDS)),
                        "batch_pre_replay_delay_seconds": float(
                            item.get("batch_pre_replay_delay_seconds", defaults["pre_capture_delay_seconds"])
                        ),
                        "completion_timeout_seconds": float(item.get("completion_timeout_seconds", DEFAULT_COMPLETION_TIMEOUT_SECONDS)),
                        "request_id_base": item.get("request_id_base", "0x1234"),
                    }
                )
            continue
        if mode == "rate_scan":
            repeats = int(item.get("repeats", DEFAULT_RATE_REPEATS))
            send_duration_seconds = float(item.get("send_duration_seconds", DEFAULT_SEND_DURATION_SECONDS))
            drain_timeout_seconds = float(item.get("drain_timeout_seconds", DEFAULT_DRAIN_TIMEOUT_SECONDS))
            rate_generation_mode = str(item.get("rate_generation_mode", RATE_GENERATION_MODE_AUTO))
            rate_accuracy_tolerance_ratio = float(
                item.get("rate_accuracy_tolerance_ratio", DEFAULT_RATE_ACCURACY_TOLERANCE_RATIO)
            )
            rate_chunk_target_seconds = float(
                item.get("rate_chunk_target_seconds", DEFAULT_RATE_CHUNK_TARGET_SECONDS)
            )
            rate_points = item.get("rate_points_req_per_sec", DEFAULT_RATE_POINTS)
            if not isinstance(rate_points, list) or not rate_points:
                raise SystemExit("rate_scan experiment %s must provide rate_points_req_per_sec list" % name)
            request_id_base_start = int(str(item.get("request_id_base_start", "0x2000")), 0)
            for rate_index, rate_value in enumerate(rate_points):
                rate = float(rate_value)
                expected_count = max(1, int(math.ceil(rate * send_duration_seconds)))
                request_id_base = "0x%04x" % ((request_id_base_start + (rate_index * 0x0100)) & 0xFFFF)
                for repeat_index in range(1, repeats + 1):
                    run_name = "%s_%spps_r%02d" % (board_sweep._slugify(name), int(rate), repeat_index)
                    expanded.append(
                        {
                            "name": name,
                            "mode": mode,
                            "run_name": run_name,
                            "repeat_index": repeat_index,
                            "offered_rate_req_per_sec": rate,
                            "send_duration_seconds": send_duration_seconds,
                            "drain_timeout_seconds": drain_timeout_seconds,
                            "expected_count": expected_count,
                            "prepare_limit": expected_count,
                            "prepare_request_id_base": request_id_base,
                            "prepare_batch_time_window_seconds": drain_timeout_seconds,
                            "request_id_base": request_id_base,
                            "rate_generation_mode": rate_generation_mode,
                            "rate_accuracy_tolerance_ratio": rate_accuracy_tolerance_ratio,
                            "rate_chunk_target_seconds": rate_chunk_target_seconds,
                        }
                    )
            continue
        raise SystemExit("unsupported metric mode %s for experiment %s" % (mode or "<missing>", name))
    return defaults, expanded


def _single_capture_filter(manifest):
    return "udp and src host {src_ip} and dst host {dst_ip}".format(
        src_ip=manifest["network"]["src_ip"],
        dst_ip=manifest["network"]["dst_ip"],
    )


def _rate_packet_relpath(index):
    return "pcaps/%s/offload_rate_%04d.pcap" % (RATE_PACKET_DIR_NAME, int(index))


def _rate_paced_pcap_relpath():
    return "pcaps/%s" % RATE_PACED_PCAP_NAME


def _rate_chunk_relpath(index):
    return "pcaps/%s/offload_rate_chunk_%04d.pcap" % (RATE_CHUNK_DIR_NAME, int(index))


class MetricsRunner(board_sweep.SweepRunner):
    def _metrics_log_path(self, run_name):
        return self.log_dir / (run_name + ".log")

    def _write_runtime_script(self, run_dir, script_name, script_text):
        path = Path(run_dir) / "commands" / script_name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(script_text, encoding="utf-8")
        path.chmod(0o755)
        return path

    def _timestamp_bounds(self, path):
        records = read_pcap_records(path)
        if not records:
            return None, None, 0
        return records[0]["timestamp_seconds"], records[-1]["timestamp_seconds"], len(records)

    def _single_sender_capture_script(self, manifest):
        usc = manifest["usc"]
        capture_filter = _single_capture_filter(manifest)
        capture_path = board_sweep._shell_remote_path("%s/captures/%s" % (usc["remote_sender_root"], SINGLE_SENDER_CAPTURE_NAME))
        return """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c 1 '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=board_sweep._shell_remote_path("%s/captures" % usc["remote_sender_root"]),
            capture_path=capture_path,
            iface=usc["sender_iface"],
            capture_filter=capture_filter,
        )

    def _rate_receiver_capture_script(self, manifest):
        usc = manifest["usc"]
        capture_filter = _single_capture_filter(manifest)
        capture_path = board_sweep._shell_remote_path("%s/captures/%s" % (usc["remote_receiver_root"], RATE_RECEIVER_CAPTURE_NAME))
        return """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=board_sweep._shell_remote_path("%s/captures" % usc["remote_receiver_root"]),
            capture_path=capture_path,
            iface=usc["receiver_iface"],
            capture_filter=capture_filter,
        )

    def _rate_sender_capture_script(self, manifest, expected_count):
        usc = manifest["usc"]
        capture_filter = _single_capture_filter(manifest)
        capture_path = board_sweep._shell_remote_path("%s/captures/%s" % (usc["remote_sender_root"], RATE_SENDER_CAPTURE_NAME))
        return """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c {count} '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=board_sweep._shell_remote_path("%s/captures" % usc["remote_sender_root"]),
            capture_path=capture_path,
            iface=usc["sender_iface"],
            count=int(expected_count),
            capture_filter=capture_filter,
        )

    def _rate_paced_replay_script(self, manifest):
        usc = manifest["usc"]
        paced_relpath = manifest.get("metrics", {}).get("rate_paced_pcap")
        if not paced_relpath:
            raise SystemExit("rate_scan manifest missing metrics.rate_paced_pcap")
        remote_path = "%s/%s" % (
            board_sweep._shell_remote_path("%s/pcaps" % usc["remote_sender_root"]),
            Path(paced_relpath).relative_to("pcaps").as_posix(),
        )
        return """#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"
""".format(
            iface=usc["sender_iface"],
            pcap_path=remote_path,
        )

    def _rate_chunked_replay_script(self, manifest):
        usc = manifest["usc"]
        rate_chunk_plan = manifest.get("metrics", {}).get("rate_chunk_plan", [])
        if not rate_chunk_plan:
            raise SystemExit("rate_scan manifest missing metrics.rate_chunk_plan")
        lines = [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
        ]
        for index, item in enumerate(rate_chunk_plan):
            remote_path = "%s/%s" % (
                board_sweep._shell_remote_path("%s/pcaps" % usc["remote_sender_root"]),
                Path(item["pcap"]).relative_to("pcaps").as_posix(),
            )
            lines.append(
                'sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"'.format(
                    iface=usc["sender_iface"],
                    pcap_path=remote_path,
                )
            )
            sleep_after_seconds = float(item.get("sleep_after_seconds", 0.0))
            if sleep_after_seconds > 0 and index != (len(rate_chunk_plan) - 1):
                lines.append("sleep %.6f" % sleep_after_seconds)
        return "\n".join(lines) + "\n"

    def _prepare_rate_replay_pcaps(self, run_dir, manifest, offered_rate_req_per_sec, chunk_target_seconds):
        batch_pcap = run_dir / manifest["artifacts"]["offload_batch_pcap"]
        records = read_pcap_records(batch_pcap)
        if not records:
            raise SystemExit("rate_scan batch pcap is empty: %s" % batch_pcap)
        gap_seconds = 1.0 / float(offered_rate_req_per_sec)
        paced_records = []
        for index, record in enumerate(records):
            paced_records.append(
                {
                    "frame": record["frame"],
                    "timestamp_seconds": 1.0 + (float(index) * gap_seconds),
                }
            )

        paced_relpath = _rate_paced_pcap_relpath()
        paced_path = run_dir / paced_relpath
        paced_path.parent.mkdir(parents=True, exist_ok=True)
        write_pcap(paced_path, paced_records)

        chunk_target_seconds = max(float(chunk_target_seconds), gap_seconds)
        chunk_dir = run_dir / "pcaps" / RATE_CHUNK_DIR_NAME
        chunk_dir.mkdir(parents=True, exist_ok=True)
        chunk_plan = []
        record_index = 0
        while record_index < len(paced_records):
            chunk_start = float(paced_records[record_index]["timestamp_seconds"])
            start_index = record_index
            chunk_records = []
            while record_index < len(paced_records):
                record = paced_records[record_index]
                if chunk_records and (float(record["timestamp_seconds"]) - chunk_start) >= (chunk_target_seconds - 1e-9):
                    break
                chunk_records.append(record)
                record_index += 1

            rel_path = _rate_chunk_relpath(len(chunk_plan))
            local_path = run_dir / rel_path
            first_ts = float(chunk_records[0]["timestamp_seconds"])
            normalized_records = []
            for record in chunk_records:
                normalized_records.append(
                    {
                        "frame": record["frame"],
                        "timestamp_seconds": 1.0 + (float(record["timestamp_seconds"]) - first_ts),
                    }
                )
            write_pcap(local_path, normalized_records)
            if record_index < len(paced_records):
                next_chunk_start = float(paced_records[record_index]["timestamp_seconds"])
                sleep_after_seconds = max(next_chunk_start - chunk_start, 0.0)
            else:
                sleep_after_seconds = 0.0
            chunk_plan.append(
                {
                    "pcap": rel_path,
                    "start_index": start_index,
                    "packet_count": len(chunk_records),
                    "sleep_after_seconds": sleep_after_seconds,
                }
            )
        return {
            "rate_paced_pcap": paced_relpath,
            "rate_chunk_plan": chunk_plan,
        }

    def _fetch_remote_capture(self, handle, host, remote_path, local_path):
        remote_state = self._remote_artifact_state(handle, host, remote_path)
        if remote_state["exists"]:
            self._fetch_single_remote_artifact(handle, host, remote_path, local_path)
        return remote_state, board_sweep._local_artifact_state(local_path)

    def _rate_accuracy_status(self, attempt, offered_rate_req_per_sec, prepared_count, tolerance_ratio):
        if attempt.get("pipeline_verdict") != "healthy":
            return RATE_ACCURACY_STATUS_PIPELINE_FAILED
        if int(attempt.get("sender_capture_count") or 0) != int(prepared_count):
            return RATE_ACCURACY_STATUS_SENDER_COUNT_MISMATCH
        actual_send_rate = attempt.get("actual_send_rate_req_per_sec")
        if actual_send_rate is None or float(offered_rate_req_per_sec) <= 0:
            return RATE_ACCURACY_STATUS_MISSING_SEND_RATE
        rate_error_ratio = abs(float(actual_send_rate) - float(offered_rate_req_per_sec)) / float(offered_rate_req_per_sec)
        if rate_error_ratio <= float(tolerance_ratio):
            return RATE_ACCURACY_STATUS_WITHIN_TOLERANCE
        return RATE_ACCURACY_STATUS_OUTSIDE_TOLERANCE

    def _evaluate_rate_attempt(
        self,
        run_dir,
        manifest,
        sender_local,
        receiver_local,
        debug_status,
        offered_rate_req_per_sec,
        prepared_count,
        tolerance_ratio,
    ):
        attempt = {
            "sender_capture_count": sender_local.get("packet_count"),
            "receiver_capture_count": receiver_local.get("packet_count"),
            "engine_emit_count": debug_status.get("result_emit_count") if debug_status else None,
            "debug_status": debug_status,
        }
        expected_rows = _load_json(run_dir / manifest["artifacts"]["selected_expected_outputs"])
        observed_rows = observed_rows_from_frames(
            [record["frame"] for record in read_pcap_records(receiver_local["path"])] if receiver_local["exists"] else [],
            expected_rows=expected_rows,
            result_mode=manifest["model"]["result_mode"],
            request_id_base=int(str(manifest["network"]["request_id_base"]), 0),
        )
        compare_summary = compare_expected_observed(expected_rows, observed_rows)
        attempt["missing_request_ids"] = [
            "0x%04x" % int(item["expected_request_id"], 0)
            for item in compare_summary.get("mismatches", [])
            if item.get("reason") == "missing_observation" and item.get("expected_request_id") is not None
        ]
        attempt["mismatch_count"] = len(compare_summary.get("mismatches", []))
        attempt["observed_count"] = len(observed_rows)
        attempt["drop_count"] = max(int(prepared_count) - len(observed_rows), 0)
        attempt["drop_ratio"] = float(attempt["drop_count"]) / float(prepared_count) if int(prepared_count) > 0 else 0.0

        sender_first, sender_last, sender_count = self._timestamp_bounds(sender_local["path"]) if sender_local["exists"] else (None, None, 0)
        receiver_first, receiver_last, receiver_count = self._timestamp_bounds(receiver_local["path"]) if receiver_local["exists"] else (None, None, 0)
        attempt["sender_capture_count"] = sender_count
        attempt["receiver_capture_count"] = receiver_count
        if sender_first is not None and sender_last is not None:
            send_span_seconds = max(sender_last - sender_first, 0.0)
            attempt["send_span_seconds"] = send_span_seconds
            if send_span_seconds > 0 and sender_count > 1:
                attempt["actual_send_rate_req_per_sec"] = float(sender_count - 1) / send_span_seconds
        if sender_first is not None and receiver_last is not None:
            total_span_seconds = max(receiver_last - sender_first, 0.0)
            attempt["completion_span_seconds"] = total_span_seconds
            if total_span_seconds > 0:
                attempt["goodput_result_per_sec"] = float(receiver_count) / total_span_seconds

        attempt["send_count_matches_prepared"] = int(sender_count) == int(prepared_count)
        if attempt.get("actual_send_rate_req_per_sec") is not None and float(offered_rate_req_per_sec) > 0:
            attempt["rate_error_ratio"] = abs(
                float(attempt["actual_send_rate_req_per_sec"]) - float(offered_rate_req_per_sec)
            ) / float(offered_rate_req_per_sec)
        else:
            attempt["rate_error_ratio"] = None
        attempt["pipeline_verdict"] = "healthy" if attempt["drop_count"] == 0 and attempt["mismatch_count"] == 0 else "overload_or_loss"
        attempt["overload_flag"] = bool(attempt["drop_count"] or attempt["mismatch_count"])
        attempt["rate_accuracy_status"] = self._rate_accuracy_status(
            attempt,
            offered_rate_req_per_sec,
            prepared_count,
            tolerance_ratio,
        )
        attempt["measurement_valid"] = attempt["rate_accuracy_status"] == RATE_ACCURACY_STATUS_WITHIN_TOLERANCE
        return attempt

    def _copy_rate_attempt_capture(self, source_path, dest_name):
        if source_path.exists():
            shutil.copy2(str(source_path), str(source_path.parent / dest_name))

    def _select_rate_attempt(self, primary_attempt, fallback_attempt):
        if primary_attempt.get("measurement_valid"):
            return primary_attempt
        if fallback_attempt is not None and fallback_attempt.get("measurement_valid"):
            return fallback_attempt
        return fallback_attempt if fallback_attempt is not None else primary_attempt

    def _prepare_run(self, handle, experiment):
        run_dir = self.output_dir / experiment["run_name"]
        prepare_command = board_sweep._build_prepare_command(run_dir, self.defaults, experiment)
        self._run_local(handle, prepare_command)
        self._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "bringup", str(run_dir / "manifest.json")])
        self._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "capture", str(run_dir / "manifest.json")])
        manifest = _load_json(run_dir / "manifest.json")
        rate_replay_pcaps = None
        if experiment["mode"] == "rate_scan":
            rate_replay_pcaps = self._prepare_rate_replay_pcaps(
                run_dir,
                manifest,
                float(experiment["offered_rate_req_per_sec"]),
                float(experiment["rate_chunk_target_seconds"]),
            )
        manifest["metrics"] = {
            "completion_timeout_seconds": experiment.get("completion_timeout_seconds"),
            "single_result_timeout_seconds": experiment.get("single_result_timeout_seconds"),
            "drain_timeout_seconds": experiment.get("drain_timeout_seconds"),
            "offered_rate_req_per_sec": experiment.get("offered_rate_req_per_sec"),
            "rate_generation_mode": experiment.get("rate_generation_mode", RATE_GENERATION_MODE_AUTO),
            "rate_accuracy_tolerance_ratio": experiment.get("rate_accuracy_tolerance_ratio"),
            "rate_chunk_target_seconds": experiment.get("rate_chunk_target_seconds"),
        }
        if rate_replay_pcaps is not None:
            manifest["metrics"].update(rate_replay_pcaps)
        manifest["sweep"] = {
            "batch_pre_replay_delay_seconds": experiment.get("batch_pre_replay_delay_seconds", self.defaults["pre_capture_delay_seconds"]),
            "capture_ready_delay_seconds": self.defaults["capture_ready_delay_seconds"],
            "receiver_capture_mode": self.defaults["receiver_capture_mode"],
            "receiver_capture_primary_mode": self.defaults["receiver_capture_primary_mode"],
            "receiver_capture_fallback_mode": self.defaults["receiver_capture_fallback_mode"],
            "receiver_capture_completion_timeout_seconds": experiment.get("completion_timeout_seconds"),
        }
        _write_json(run_dir / "manifest.json", manifest)
        self._stage_artifacts(run_dir, manifest, handle)
        self._run_remote_script(
            handle,
            manifest["usc"]["netfpga_host"],
            run_dir / "commands" / "nf3_bringup.sh",
            tty=False,
        )
        return run_dir, manifest

    def _single_latency_sample(self, run_dir, manifest, handle, sample_index, timeout_seconds):
        usc = manifest["usc"]
        commands_dir = run_dir / "commands"
        sender_capture_local = run_dir / "captures" / ("single_sender_%03d.cap" % sample_index)
        receiver_capture_local = run_dir / "captures" / ("single_receiver_%03d.cap" % sample_index)
        sender_capture_remote = "%s/captures/%s" % (usc["remote_sender_root"], SINGLE_SENDER_CAPTURE_NAME)
        receiver_capture_remote = "%s/captures/%s" % (
            usc["remote_receiver_root"],
            manifest["artifacts"]["offload_smoke_capture"].split("/")[-1],
        )

        sender_script = self._write_runtime_script(run_dir, "nf4_capture_single_sender.sh", self._single_sender_capture_script(manifest))
        sender_capture = self._start_remote_script(handle, usc["sender_host"], sender_script, tty=True)
        receiver_capture = self._start_remote_script(handle, usc["receiver_host"], commands_dir / "nf1_capture_offload_smoke.sh", tty=True)
        time.sleep(float(self.defaults["pre_capture_delay_seconds"]))
        sample_start_monotonic = time.perf_counter()
        self._run_remote_script(handle, usc["sender_host"], commands_dir / "nf4_replay_offload_smoke.sh", tty=True)

        sample = {
            "sample_index": sample_index,
            "sender_capture_path": board_sweep._relpath(sender_capture_local, self.output_dir),
            "receiver_capture_path": board_sweep._relpath(receiver_capture_local, self.output_dir),
            "timed_out": False,
            "timing_mode": TIMING_MODE_NONE,
            "latency_status": LATENCY_STATUS_UNSUPPORTED,
        }
        try:
            sender_capture.wait(timeout=timeout_seconds)
            receiver_capture.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            sample["timed_out"] = True
            self._stop_async_remote_run(handle, sender_capture, 1.0)
            self._stop_async_remote_run(handle, receiver_capture, 1.0)

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
        sample["sender_capture_exists"] = sender_local_state["exists"]
        sample["receiver_capture_exists"] = receiver_local_state["exists"]
        sample["sender_capture_remote_exists"] = sender_remote_state["exists"]
        sample["receiver_capture_remote_exists"] = receiver_remote_state["exists"]
        if not sender_local_state["exists"] or not receiver_local_state["exists"]:
            sample["timed_out"] = True
            sample["status"] = "timeout"
            return sample

        verdict = self._single_packet_offload_verdict(run_dir, manifest, receiver_local_state)
        sample.update(verdict)
        sample["status"] = "passed" if verdict["verdict"] == "healthy" else "failed"
        sample["coarse_completion_us"] = max((time.perf_counter() - sample_start_monotonic) * 1000000.0, 0.0)
        return sample

    def execute_latency_experiment(self, experiment):
        run_dir = self.output_dir / experiment["run_name"]
        log_path = self._metrics_log_path(experiment["run_name"])
        result = {
            "experiment_name": experiment["name"],
            "mode": "latency_single",
            "run_name": experiment["run_name"],
            "run_dir": str(run_dir),
            "warmup_count": experiment["warmup_count"],
            "sample_count": experiment["sample_count"],
            "single_result_timeout_seconds": experiment["single_result_timeout_seconds"],
            "runner_log": board_sweep._relpath(log_path, self.output_dir),
            "status": "pending",
            "board_passed": False,
            "timing_mode": TIMING_MODE_NONE,
            "latency_status": LATENCY_STATUS_UNSUPPORTED,
        }
        with open(log_path, "w", encoding="utf-8") as handle:
            self._log(handle, "run_name=%s" % experiment["run_name"])
            self._log(handle, "mode=latency_single")
            run_dir, manifest = self._prepare_run(handle, experiment)
            sample_results = []
            total_samples = int(experiment["warmup_count"]) + int(experiment["sample_count"])
            for sample_index in range(1, total_samples + 1):
                sample = self._single_latency_sample(
                    run_dir,
                    manifest,
                    handle,
                    sample_index,
                    float(experiment["single_result_timeout_seconds"]),
                )
                sample["phase"] = "warmup" if sample_index <= int(experiment["warmup_count"]) else "measure"
                sample_results.append(sample)
                if sample_index != total_samples and float(experiment["inter_sample_pause_seconds"]) > 0:
                    time.sleep(float(experiment["inter_sample_pause_seconds"]))
            measured = [item for item in sample_results if item["phase"] == "measure"]
            valid = [item for item in measured if item.get("status") == "passed"]
            coarse_timings = [item["coarse_completion_us"] for item in valid if item.get("coarse_completion_us") is not None]
            result["sample_results"] = sample_results
            result["timeout_count"] = len([item for item in measured if item.get("timed_out")])
            result["valid_sample_count"] = len(valid)
            result["sample_pass_count"] = len([item for item in measured if item.get("status") == "passed"])
            result["sample_fail_count"] = len(measured) - result["sample_pass_count"]
            result.update(_latency_summary([]))
            result["coarse_completion_summary_us"] = _latency_summary(coarse_timings)
            result["board_passed"] = len(valid) == len(measured) and len(measured) > 0
            result["status"] = "passed" if result["board_passed"] else "report_failed"
        return result

    def execute_batch_completion_experiment(self, experiment):
        run_dir = self.output_dir / experiment["run_name"]
        log_path = self._metrics_log_path(experiment["run_name"])
        result = {
            "experiment_name": experiment["name"],
            "mode": "batch_completion",
            "run_name": experiment["run_name"],
            "run_dir": str(run_dir),
            "batch_size": experiment["batch_size"],
            "completion_timeout_seconds": experiment["completion_timeout_seconds"],
            "runner_log": board_sweep._relpath(log_path, self.output_dir),
            "status": "pending",
            "board_passed": False,
        }
        with open(log_path, "w", encoding="utf-8") as handle:
            self._log(handle, "run_name=%s" % experiment["run_name"])
            self._log(handle, "mode=batch_completion")
            run_dir, manifest = self._prepare_run(handle, experiment)
            step_result = self._execute_batch_workload(
                run_dir,
                manifest,
                handle,
                {
                    "batch_size": experiment["batch_size"],
                    "batch_time_window_seconds": experiment["completion_timeout_seconds"],
                    "batch_pre_replay_delay_seconds": experiment["batch_pre_replay_delay_seconds"],
                    "request_id_base": experiment["request_id_base"],
                },
            )
            result.update(step_result)
            sender_capture = run_dir / "captures" / board_sweep.CANONICAL_SENDER_BATCH_CAPTURE_NAME
            receiver_capture = run_dir / "captures" / board_sweep.CANONICAL_RECEIVER_BATCH_CAPTURE_NAME
            sender_first, sender_last, sender_count = self._timestamp_bounds(sender_capture)
            receiver_first, receiver_last, receiver_count = self._timestamp_bounds(receiver_capture)
            if sender_first is not None and receiver_last is not None:
                completion_seconds = max(receiver_last - sender_first, 0.0)
                result["batch_completion_time_us"] = completion_seconds * 1000000.0
                if completion_seconds > 0:
                    result["throughput_req_per_sec"] = float(experiment["batch_size"]) / completion_seconds
                    result["throughput_result_per_sec"] = float(receiver_count) / completion_seconds
            result["sender_capture_count"] = sender_count
            result["receiver_capture_count"] = receiver_count
        return result

    def _run_rate_scan_attempt(
        self,
        run_dir,
        manifest,
        handle,
        replay_script,
        capture_suffix,
        send_duration_seconds,
        drain_timeout_seconds,
        offered_rate_req_per_sec,
        prepared_count,
        tolerance_ratio,
    ):
        usc = manifest["usc"]
        receiver_script = self._write_runtime_script(run_dir, "nf1_capture_offload_rate_%s.sh" % capture_suffix, self._rate_receiver_capture_script(manifest))
        sender_script = self._write_runtime_script(
            run_dir,
            "nf4_capture_offload_rate_sender_%s.sh" % capture_suffix,
            self._rate_sender_capture_script(manifest, prepared_count),
        )

        receiver_capture = self._start_remote_script(handle, usc["receiver_host"], receiver_script, tty=True)
        sender_capture = self._start_remote_script(handle, usc["sender_host"], sender_script, tty=True)
        time.sleep(float(self.defaults["capture_ready_delay_seconds"]))
        self._run_remote_script(handle, usc["sender_host"], replay_script, tty=True)
        sender_capture.wait(timeout=max(float(send_duration_seconds) + 5.0, 5.0))
        time.sleep(float(drain_timeout_seconds))
        self._stop_async_remote_run(handle, receiver_capture, 1.0)
        self._run_remote_script(handle, usc["netfpga_host"], run_dir / "commands" / "nf3_debug_snapshot.sh", tty=False)

        sender_local_path = run_dir / "captures" / ("offload_rate_sender_%s.cap" % capture_suffix)
        receiver_local_path = run_dir / "captures" / ("offload_rate_receiver_%s.cap" % capture_suffix)
        debug_local_path = run_dir / ("debug_status_%s.txt" % capture_suffix)
        sender_remote, sender_local = self._fetch_remote_capture(
            handle,
            usc["sender_host"],
            "%s/captures/%s" % (usc["remote_sender_root"], RATE_SENDER_CAPTURE_NAME),
            sender_local_path,
        )
        receiver_remote, receiver_local = self._fetch_remote_capture(
            handle,
            usc["receiver_host"],
            "%s/captures/%s" % (usc["remote_receiver_root"], RATE_RECEIVER_CAPTURE_NAME),
            receiver_local_path,
        )
        debug_name = Path(manifest["artifacts"]["debug_status_txt"]).name
        self._run_scp(
            handle,
            "%s:%s/%s" % (usc["netfpga_host"], usc["remote_netfpga_results"], debug_name),
            str(debug_local_path),
            recursive=False,
        )
        debug_status = None
        if debug_local_path.exists():
            debug_status = board_sweep._parse_debug_status_text(debug_local_path.read_text(encoding="utf-8"))
        attempt = self._evaluate_rate_attempt(
            run_dir,
            manifest,
            sender_local,
            receiver_local,
            debug_status,
            offered_rate_req_per_sec,
            prepared_count,
            tolerance_ratio,
        )
        attempt["sender_capture_remote_exists"] = sender_remote["exists"]
        attempt["receiver_capture_remote_exists"] = receiver_remote["exists"]
        attempt["sender_capture_path"] = board_sweep._relpath(sender_local_path, self.output_dir)
        attempt["receiver_capture_path"] = board_sweep._relpath(receiver_local_path, self.output_dir)
        attempt["debug_status_path"] = board_sweep._relpath(debug_local_path, self.output_dir)
        return attempt

    def execute_rate_scan_experiment(self, experiment):
        run_dir = self.output_dir / experiment["run_name"]
        log_path = self._metrics_log_path(experiment["run_name"])
        result = {
            "experiment_name": experiment["name"],
            "mode": "rate_scan",
            "run_name": experiment["run_name"],
            "run_dir": str(run_dir),
            "offered_rate_req_per_sec": experiment["offered_rate_req_per_sec"],
            "expected_count": experiment["expected_count"],
            "send_duration_seconds": experiment["send_duration_seconds"],
            "drain_timeout_seconds": experiment["drain_timeout_seconds"],
            "runner_log": board_sweep._relpath(log_path, self.output_dir),
            "status": "pending",
            "board_passed": False,
            "rate_generation_mode_attempted": [],
            "rate_generation_mode_used": None,
        }
        with open(log_path, "w", encoding="utf-8") as handle:
            self._log(handle, "run_name=%s" % experiment["run_name"])
            self._log(handle, "mode=rate_scan")
            run_dir, manifest = self._prepare_run(handle, experiment)
            prepared_count = int(manifest["counts"]["batch_packet_count"])
            result["prepared_count"] = prepared_count
            tolerance_ratio = float(experiment["rate_accuracy_tolerance_ratio"])
            primary_replay_script = self._write_runtime_script(
                run_dir,
                "nf4_replay_offload_rate_primary.sh",
                self._rate_paced_replay_script(manifest),
            )
            primary_attempt = self._run_rate_scan_attempt(
                run_dir,
                manifest,
                handle,
                primary_replay_script,
                "primary",
                float(experiment["send_duration_seconds"]),
                float(experiment["drain_timeout_seconds"]),
                float(experiment["offered_rate_req_per_sec"]),
                prepared_count,
                tolerance_ratio,
            )
            primary_attempt["rate_generation_mode"] = RATE_GENERATION_MODE_PACED
            result["rate_generation_mode_attempted"].append(RATE_GENERATION_MODE_PACED)

            fallback_attempt = None
            if (
                str(experiment.get("rate_generation_mode", RATE_GENERATION_MODE_AUTO)) == RATE_GENERATION_MODE_AUTO
                and not primary_attempt.get("measurement_valid")
            ):
                self._log(handle, "rate primary invalid; rerunning bringup for chunked fallback")
                self._run_remote_script(
                    handle,
                    manifest["usc"]["netfpga_host"],
                    run_dir / "commands" / "nf3_bringup.sh",
                    tty=False,
                )
                fallback_replay_script = self._write_runtime_script(
                    run_dir,
                    "nf4_replay_offload_rate_chunked.sh",
                    self._rate_chunked_replay_script(manifest),
                )
                fallback_attempt = self._run_rate_scan_attempt(
                    run_dir,
                    manifest,
                    handle,
                    fallback_replay_script,
                    "chunked",
                    float(experiment["send_duration_seconds"]),
                    float(experiment["drain_timeout_seconds"]),
                    float(experiment["offered_rate_req_per_sec"]),
                    prepared_count,
                    tolerance_ratio,
                )
                fallback_attempt["rate_generation_mode"] = RATE_GENERATION_MODE_CHUNKED
                result["rate_generation_mode_attempted"].append(RATE_GENERATION_MODE_CHUNKED)

            chosen_attempt = self._select_rate_attempt(primary_attempt, fallback_attempt)
            result["rate_generation_mode_used"] = chosen_attempt.get("rate_generation_mode")
            result["rate_generation_primary_status"] = primary_attempt.get("rate_accuracy_status")
            result["rate_generation_fallback_status"] = (
                fallback_attempt.get("rate_accuracy_status") if fallback_attempt is not None else None
            )
            result["rate_attempt_results"] = [primary_attempt] + ([fallback_attempt] if fallback_attempt is not None else [])
            result.update(chosen_attempt)

            chosen_sender = run_dir / "captures" / Path(chosen_attempt["sender_capture_path"]).name
            chosen_receiver = run_dir / "captures" / Path(chosen_attempt["receiver_capture_path"]).name
            chosen_debug = run_dir / Path(chosen_attempt["debug_status_path"]).name
            self._copy_rate_attempt_capture(chosen_sender, RATE_SENDER_CAPTURE_NAME)
            self._copy_rate_attempt_capture(chosen_receiver, RATE_RECEIVER_CAPTURE_NAME)
            if chosen_debug.exists():
                shutil.copy2(str(chosen_debug), str(run_dir / manifest["artifacts"]["debug_status_txt"]))

            result["board_passed"] = bool(chosen_attempt.get("measurement_valid"))
            if result["board_passed"]:
                result["status"] = "passed"
            elif result.get("pipeline_verdict") == "healthy":
                result["status"] = "invalid_rate_control"
            else:
                result["status"] = "report_failed"
        return result


def _render_markdown_summary(output_dir, config_path, results):
    lines = [
        "# Board Metrics Summary",
        "",
        "- config: `%s`" % config_path,
        "- output_dir: `%s`" % output_dir,
        "- runs_total: `%d`" % len(results),
        "- runs_passed: `%d`" % len([item for item in results if item.get("board_passed")]),
        "- runs_failed: `%d`" % len([item for item in results if not item.get("board_passed")]),
        "",
        "| Run | Mode | Status | Verdict | Timing | Goodput | RateCtrl | Valid | Sender | Receiver | Engine |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in results:
        timing_cell = "-"
        if item.get("latency_status") == LATENCY_STATUS_UNSUPPORTED:
            timing_cell = "unsupported"
        elif item.get("latency_p50_us") is not None:
            timing_cell = "%0.2f" % float(item["latency_p50_us"])
        rate_ctrl = item.get("rate_generation_mode_used") or "-"
        if item.get("actual_send_rate_req_per_sec") is not None:
            rate_ctrl = "%s (%0.2f)" % (rate_ctrl, float(item["actual_send_rate_req_per_sec"]))
        lines.append(
            "| {run_name} | {mode} | {status} | {verdict} | {latency_p50} | {goodput} | {rate_ctrl} | {valid} | {sender} | {receiver} | {engine} |".format(
                run_name=item["run_name"],
                mode=item["mode"],
                status=item.get("status", "-"),
                verdict=item.get("pipeline_verdict") or "-",
                latency_p50=timing_cell,
                goodput=(
                    "%0.3f" % float(item["goodput_result_per_sec"])
                    if item.get("goodput_result_per_sec") is not None
                    else (
                        "%0.3f" % float(item["throughput_result_per_sec"])
                        if item.get("throughput_result_per_sec") is not None
                        else "-"
                    )
                ),
                rate_ctrl=rate_ctrl,
                valid=("yes" if item.get("measurement_valid") else "-"),
                sender=item.get("sender_capture_count", "-"),
                receiver=item.get("receiver_capture_count", "-"),
                engine=item.get("engine_emit_count", "-"),
            )
        )
    return "\n".join(lines) + "\n"


def build_parser():
    parser = argparse.ArgumentParser(description="Run formal USC NetFPGA NIC performance measurements.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--password-file")
    parser.add_argument("--ssh-mode", choices=["sshpass", "system"])
    parser.add_argument("--out-dir")
    parser.add_argument("--force", action="store_true", default=False)
    return parser


def main():
    args = build_parser().parse_args()
    config_path = Path(args.config).resolve()
    config = board_sweep._load_config(config_path)
    if args.password_file is not None:
        config["password_file"] = args.password_file
    if args.ssh_mode is not None:
        config["ssh_mode"] = args.ssh_mode
    defaults, experiments = _normalize_metric_experiments(config, config_path.parent)

    board_sweep._ensure_local_dependency("ssh")
    board_sweep._ensure_local_dependency("scp")
    password = None
    if defaults["ssh_mode"] == "sshpass":
        board_sweep._ensure_local_dependency("sshpass")
        password = board_sweep._resolve_password(defaults["ssh_mode"], defaults.get("password_file"))

    output_dir = Path(args.out_dir).resolve() if args.out_dir else (ROOT_DIR / "runs" / ("board_metrics_" + datetime.now().strftime("%Y%m%d_%H%M%S")))
    if output_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % output_dir)
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    runner = MetricsRunner(output_dir=output_dir, config_path=config_path, defaults=defaults, password=password)
    results = []
    for experiment in experiments:
        if experiment["mode"] == "latency_single":
            results.append(runner.execute_latency_experiment(experiment))
        elif experiment["mode"] == "batch_completion":
            results.append(runner.execute_batch_completion_experiment(experiment))
        elif experiment["mode"] == "rate_scan":
            results.append(runner.execute_rate_scan_experiment(experiment))
        else:
            raise SystemExit("unsupported mode: %s" % experiment["mode"])

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
    _write_json(output_dir / "summary.json", summary)
    _write_text(output_dir / "summary.md", _render_markdown_summary(output_dir, config_path, results))
    print("summary_json=%s" % (output_dir / "summary.json"))
    print("summary_md=%s" % (output_dir / "summary.md"))
    print("runs_total=%d" % summary["runs_total"])
    print("runs_passed=%d" % summary["runs_passed"])
    print("runs_failed=%d" % summary["runs_failed"])
    return 0 if summary["runs_failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
