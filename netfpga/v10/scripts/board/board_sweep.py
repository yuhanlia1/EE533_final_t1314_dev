#!/usr/bin/env python3

import argparse
import getpass
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))

from board_debug.ann_packets import ANN_TASK_MAGIC, inspect_ann_frame
from board_debug.model_batch_eval import compare_expected_observed, observed_rows_from_frames
from board_debug.pcap_io import read_pcap

BOARDCTL_PATH = ROOT_DIR / "scripts" / "board" / "boardctl.py"
DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_demo_sweep.json"
DEFAULT_MODEL = ROOT_DIR / "dataset" / "export" / "rsu_ann_model_int16.json"
DEFAULT_BITFILE = "nw_proc4_2_moreobserve.bit"
DEFAULT_REMOTE_VERSION = "v8"
DEFAULT_NETFPGA_HOST = "netfpga@nf9.usc.edu"
DEFAULT_SENDER_HOST = "node4@nf5.usc.edu"
DEFAULT_RECEIVER_HOST = "node4@nf7.usc.edu"
DEFAULT_SENDER_IFACE = "port0"
DEFAULT_RECEIVER_IFACE = "port2"
DEFAULT_PRE_CAPTURE_DELAY_SECONDS = 0.5
DEFAULT_CAPTURE_READY_DELAY_SECONDS = 1.0
DEFAULT_SSH_MODE = "sshpass"
DEFAULT_KEX_ALGORITHMS = "diffie-hellman-group14-sha1"
DEFAULT_RECEIVER_CAPTURE_MODE = "auto"
DEFAULT_RECEIVER_CAPTURE_PRIMARY_MODE = "count"
DEFAULT_RECEIVER_CAPTURE_FALLBACK_MODE = "time_window"
DEFAULT_RECEIVER_CAPTURE_GRACE_SECONDS = 2.0
DEFAULT_RECEIVER_CAPTURE_TIMEOUT_MARGIN_SECONDS = 2.0
DEFAULT_WRONG_MAGIC = 0xBEEF
DEFAULT_WRONG_PORT = 0x9999

PRIMARY_RECEIVER_BATCH_CAPTURE_NAME = "offload_batch_receiver_primary.cap"
FALLBACK_RECEIVER_BATCH_CAPTURE_NAME = "offload_batch_receiver_fallback.cap"
PRIMARY_SENDER_BATCH_CAPTURE_NAME = "offload_batch_sender_primary.cap"
FALLBACK_SENDER_BATCH_CAPTURE_NAME = "offload_batch_sender_fallback.cap"
CANONICAL_RECEIVER_BATCH_CAPTURE_NAME = "offload_batch_time_window.cap"
CANONICAL_SENDER_BATCH_CAPTURE_NAME = "offload_batch_sender.cap"
SINGLE_OFFLOAD_CAPTURE_NAME = "offload_smoke.cap"


def _slugify(value):
    text = str(value).strip().lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text.strip("_") or "run"


def _parse_int(value):
    return int(str(value), 0)


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


def _parse_debug_status_text(text):
    parsed = {}
    for raw_line in str(text).splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        try:
            parsed[key] = int(value, 0)
        except ValueError:
            parsed[key] = value
    return parsed


def _relpath(path, base):
    return os.path.relpath(str(path), str(base))


def _default_output_dir():
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return ROOT_DIR / "runs" / ("board_sweep_" + stamp)


def _remote_script_command(host, tty):
    command = ["ssh"]
    if tty:
        command.append("-tt")
    command.extend([host, "bash", "-s"])
    return command


def _load_config(path):
    config = _load_json(path)
    if not isinstance(config, dict):
        raise SystemExit("config must be a JSON object")
    experiments = config.get("experiments")
    if not isinstance(experiments, list) or not experiments:
        raise SystemExit("config must include a non-empty experiments list")
    return config


def _load_password_file(path):
    text = Path(path).read_text(encoding="utf-8")
    lines = text.splitlines()
    if len(lines) != 1 or not lines[0] or lines[0].strip() != lines[0] or lines[0].startswith("Password:"):
        raise SystemExit("password file %s must contain exactly one non-empty password line" % path)
    return lines[0]


def _prompt_password(prompt_func=None, stdin=None):
    prompt_func = getpass.getpass if prompt_func is None else prompt_func
    stdin = sys.stdin if stdin is None else stdin
    if stdin is None or not hasattr(stdin, "isatty") or not stdin.isatty():
        raise SystemExit("password file not provided and no interactive terminal is available for password prompt")
    password = prompt_func("USC password: ")
    if not password:
        raise SystemExit("empty password is not allowed")
    return password


def _resolve_password(ssh_mode, password_file=None, prompt_func=None, stdin=None):
    if ssh_mode != "sshpass":
        return None
    if password_file:
        password_path = Path(password_file)
        if not password_path.exists():
            raise SystemExit("password file not found: %s" % password_file)
        return _load_password_file(password_path)
    return _prompt_password(prompt_func=prompt_func, stdin=stdin)


def _ensure_local_dependency(name):
    if shutil.which(name) is None:
        raise SystemExit("missing required local command: %s" % name)


def _quote_remote(value):
    return shlex.quote(str(value))


def _shell_remote_path(value):
    text = str(value)
    if text.startswith("~/"):
        return "$HOME/" + text[2:]
    return _quote_remote(text)


def _local_artifact_state(path):
    artifact_path = Path(path)
    state = {
        "path": str(artifact_path),
        "exists": artifact_path.exists(),
        "size_bytes": None,
        "packet_count": None,
    }
    if not artifact_path.exists():
        return state
    state["size_bytes"] = artifact_path.stat().st_size
    if artifact_path.suffix == ".cap":
        try:
            state["packet_count"] = len(read_pcap(artifact_path))
        except Exception as exc:  # pragma: no cover - defensive for corrupted captures
            state["read_error"] = str(exc)
    return state


def _classify_receiver_batch_artifact(remote_state, local_state):
    if local_state.get("exists"):
        return None
    if remote_state.get("exists"):
        return "fetch_side_issue"
    return "receiver_capture_issue"


def _attempt_capture_names(attempt_name):
    if attempt_name == "primary":
        return {
            "receiver_capture": PRIMARY_RECEIVER_BATCH_CAPTURE_NAME,
            "sender_capture": PRIMARY_SENDER_BATCH_CAPTURE_NAME,
            "receiver_script": "nf1_capture_offload_batch_count.sh",
            "sender_script": "nf4_capture_offload_batch_sender_primary.sh",
            "mode": "count",
        }
    if attempt_name == "fallback":
        return {
            "receiver_capture": FALLBACK_RECEIVER_BATCH_CAPTURE_NAME,
            "sender_capture": FALLBACK_SENDER_BATCH_CAPTURE_NAME,
            "receiver_script": "nf1_capture_offload_batch_time_window.sh",
            "sender_script": "nf4_capture_offload_batch_sender_fallback.sh",
            "mode": "time_window",
        }
    raise ValueError("unsupported attempt name: %s" % attempt_name)


def _attempt_packet_count(state):
    count = state.get("packet_count")
    return int(count) if count is not None else 0


def _attempt_artifact_status(attempt, expected_count):
    receiver_local = attempt["local"]["receiver"]
    sender_local = attempt["local"]["sender"]
    receiver_count = _attempt_packet_count(receiver_local)
    sender_count = _attempt_packet_count(sender_local)
    if receiver_count >= expected_count and sender_count >= expected_count:
        return "complete"
    if receiver_local.get("exists") or sender_local.get("exists"):
        return "partial"
    if attempt["remote"]["receiver"].get("exists") or attempt["remote"]["sender"].get("exists"):
        return "remote_only"
    return "missing"


def _display_batch_size(experiment):
    value = experiment.get("batch_size")
    return "-" if value is None else str(value)


def _display_batch_window(experiment):
    value = experiment.get("batch_time_window_seconds")
    return "-" if value is None else ("%g" % float(value))


def _summarize_workloads(workloads):
    labels = []
    for workload in workloads:
        workload_type = workload["type"]
        if workload_type == "single_packet":
            labels.append(str(workload["variant"]))
        elif workload_type == "batch":
            labels.append("batch%s" % workload["batch_size"])
        else:
            labels.append(str(workload_type))
    return ",".join(labels)


def _validate_single_packet_variant(variant, experiment_name):
    if variant not in {"offload", "wrong_magic", "wrong_port"}:
        raise SystemExit("unsupported single_packet variant %s for experiment %s" % (variant, experiment_name))
    return variant


def _normalize_workloads(item, defaults, experiment_name):
    raw_workloads = item.get("workloads")
    if raw_workloads is None:
        if "batch_size" not in item:
            raise SystemExit("experiment %s must define batch_size or workloads" % experiment_name)
        return [
            {"type": "single_packet", "variant": "wrong_magic"},
            {"type": "single_packet", "variant": "wrong_port"},
            {
                "type": "batch",
                "batch_size": int(item["batch_size"]),
                "request_id_base": item.get("request_id_base", "0x1234"),
                "batch_time_window_seconds": float(item.get("batch_time_window_seconds", 2.0)),
                "batch_pre_replay_delay_seconds": float(
                    item.get("batch_pre_replay_delay_seconds", defaults["pre_capture_delay_seconds"])
                ),
                "batch_include_smoke_steps": bool(item.get("batch_include_smoke_steps", True)),
            },
        ]
    if not isinstance(raw_workloads, list) or not raw_workloads:
        raise SystemExit("experiment %s workloads must be a non-empty list" % experiment_name)

    normalized = []
    batch_workloads = []
    for index, workload in enumerate(raw_workloads, start=1):
        if not isinstance(workload, dict):
            raise SystemExit("experiment %s workload %d must be a JSON object" % (experiment_name, index))
        workload_type = str(workload.get("type") or "").strip()
        if workload_type == "single_packet":
            normalized.append(
                {
                    "type": "single_packet",
                    "variant": _validate_single_packet_variant(
                        str(workload.get("variant") or "").strip(),
                        experiment_name,
                    ),
                }
            )
            continue
        if workload_type == "batch":
            normalized_batch = {
                "type": "batch",
                "batch_size": int(workload.get("batch_size", item.get("batch_size", 1))),
                "request_id_base": workload.get("request_id_base", item.get("request_id_base", "0x1234")),
                "batch_time_window_seconds": float(
                    workload.get("batch_time_window_seconds", item.get("batch_time_window_seconds", 2.0))
                ),
                "batch_pre_replay_delay_seconds": float(
                    workload.get(
                        "batch_pre_replay_delay_seconds",
                        item.get("batch_pre_replay_delay_seconds", defaults["pre_capture_delay_seconds"]),
                    )
                ),
                "batch_include_smoke_steps": bool(
                    workload.get(
                        "batch_include_smoke_steps",
                        item.get("batch_include_smoke_steps", True),
                    )
                ),
            }
            normalized.append(normalized_batch)
            batch_workloads.append(normalized_batch)
            continue
        raise SystemExit("unsupported workload type %s for experiment %s" % (workload_type or "<missing>", experiment_name))

    if len(batch_workloads) > 1:
        raise SystemExit("experiment %s may define at most one batch workload" % experiment_name)
    return normalized


def _prepare_parameters_from_workloads(item, workloads, defaults):
    batch_workload = None
    for workload in workloads:
        if workload["type"] == "batch":
            batch_workload = workload
            break
    if batch_workload is not None:
        return {
            "prepare_limit": int(batch_workload["batch_size"]),
            "sample_pool_mode": item.get("sample_pool_mode"),
            "prepare_request_id_base": batch_workload["request_id_base"],
            "prepare_batch_time_window_seconds": float(batch_workload["batch_time_window_seconds"]),
            "batch_size": int(batch_workload["batch_size"]),
            "batch_time_window_seconds": float(batch_workload["batch_time_window_seconds"]),
            "batch_pre_replay_delay_seconds": float(batch_workload["batch_pre_replay_delay_seconds"]),
            "batch_include_smoke_steps": bool(batch_workload.get("batch_include_smoke_steps", True)),
            "request_id_base": batch_workload["request_id_base"],
        }
    return {
        "prepare_limit": 1,
        "sample_pool_mode": item.get("sample_pool_mode"),
        "prepare_request_id_base": item.get("request_id_base", "0x1234"),
        "prepare_batch_time_window_seconds": float(item.get("batch_time_window_seconds", 2.0)),
        "batch_size": None,
        "batch_time_window_seconds": None,
        "batch_pre_replay_delay_seconds": float(item.get("batch_pre_replay_delay_seconds", defaults["pre_capture_delay_seconds"])),
        "batch_include_smoke_steps": bool(item.get("batch_include_smoke_steps", True)),
        "request_id_base": item.get("request_id_base", "0x1234"),
    }


def _build_prepare_command(run_dir, defaults, experiment):
    command = [
        sys.executable,
        str(BOARDCTL_PATH),
        "prepare",
        "--model",
        str(defaults["model"]),
        "--out-dir",
        str(run_dir),
        "--run-name",
        experiment["run_name"],
        "--limit",
        str(experiment["prepare_limit"]),
        "--sample-pool-mode",
        str(experiment.get("sample_pool_mode") or "truncate"),
        "--force",
        "--bitfile",
        str(defaults["bitfile"]),
        "--netfpga-host",
        str(defaults["netfpga_host"]),
        "--sender-host",
        str(defaults["sender_host"]),
        "--receiver-host",
        str(defaults["receiver_host"]),
        "--sender-iface",
        str(defaults["sender_iface"]),
        "--receiver-iface",
        str(defaults["receiver_iface"]),
        "--request-id-base",
        str(experiment["prepare_request_id_base"]),
        "--batch-time-window-seconds",
        str(experiment["prepare_batch_time_window_seconds"]),
    ]

    optional_keys = [
        "reg_defines",
        "dst_mac",
        "src_mac",
        "src_ip",
        "dst_ip",
        "src_udp_port",
        "dst_udp_port",
        "task_type",
    ]
    for key in optional_keys:
        value = defaults.get(key)
        if value is None:
            continue
        command.extend(["--" + key.replace("_", "-"), str(value)])
    return command


def _config_value_path(config_dir, value):
    path = Path(value)
    if path.is_absolute():
        return str(path)
    config_relative = (config_dir / path).resolve()
    if config_relative.exists():
        return str(config_relative)
    cwd_relative = (Path.cwd() / path).resolve()
    if cwd_relative.exists():
        return str(cwd_relative)
    return str(config_relative)


def _normalize_defaults(config, config_dir):
    defaults = {
        "model": _config_value_path(config_dir, config.get("model", str(DEFAULT_MODEL))),
        "bitfile": config.get("bitfile", DEFAULT_BITFILE),
        "remote_version": config.get("remote_version", DEFAULT_REMOTE_VERSION),
        "ssh_mode": str(config.get("ssh_mode", DEFAULT_SSH_MODE)),
        "netfpga_host": config.get("netfpga_host", DEFAULT_NETFPGA_HOST),
        "sender_host": config.get("sender_host", DEFAULT_SENDER_HOST),
        "receiver_host": config.get("receiver_host", DEFAULT_RECEIVER_HOST),
        "sender_iface": config.get("sender_iface", DEFAULT_SENDER_IFACE),
        "receiver_iface": config.get("receiver_iface", DEFAULT_RECEIVER_IFACE),
        "pre_capture_delay_seconds": float(config.get("pre_capture_delay_seconds", DEFAULT_PRE_CAPTURE_DELAY_SECONDS)),
        "capture_ready_delay_seconds": float(
            config.get("capture_ready_delay_seconds", DEFAULT_CAPTURE_READY_DELAY_SECONDS)
        ),
        "receiver_capture_mode": str(config.get("receiver_capture_mode", DEFAULT_RECEIVER_CAPTURE_MODE)),
        "receiver_capture_primary_mode": str(
            config.get("receiver_capture_primary_mode", DEFAULT_RECEIVER_CAPTURE_PRIMARY_MODE)
        ),
        "receiver_capture_fallback_mode": str(
            config.get("receiver_capture_fallback_mode", DEFAULT_RECEIVER_CAPTURE_FALLBACK_MODE)
        ),
        "receiver_capture_grace_seconds": float(
            config.get("receiver_capture_grace_seconds", DEFAULT_RECEIVER_CAPTURE_GRACE_SECONDS)
        ),
        "receiver_capture_timeout_margin_seconds": float(
            config.get("receiver_capture_timeout_margin_seconds", DEFAULT_RECEIVER_CAPTURE_TIMEOUT_MARGIN_SECONDS)
        ),
        "continue_on_error": bool(config.get("continue_on_error", True)),
    }
    if "password_file" in config:
        defaults["password_file"] = _config_value_path(config_dir, config["password_file"])
    else:
        defaults["password_file"] = None
    for key in [
        "reg_defines",
        "dst_mac",
        "src_mac",
        "src_ip",
        "dst_ip",
        "src_udp_port",
        "dst_udp_port",
        "task_type",
    ]:
        if key in config:
            if key == "reg_defines":
                defaults[key] = _config_value_path(config_dir, config[key])
            else:
                defaults[key] = config[key]
    return defaults


def _expand_experiments(config, config_dir):
    defaults = _normalize_defaults(config, config_dir)
    expanded = []
    for raw_index, item in enumerate(config["experiments"], start=1):
        if not isinstance(item, dict):
            raise SystemExit("experiment entries must be JSON objects")
        name = str(item.get("name") or ("experiment_%02d" % raw_index))
        workloads = _normalize_workloads(item, defaults, name)
        prepare_params = _prepare_parameters_from_workloads(item, workloads, defaults)
        replay_repeat = int(item.get("replay_repeat", 1))
        if replay_repeat < 1:
            raise SystemExit("replay_repeat must be >= 1 for experiment %s" % name)
        for repeat_index in range(1, replay_repeat + 1):
            run_name = "%s_r%02d" % (_slugify(name), repeat_index)
            expanded.append(
                {
                    "name": name,
                    "run_name": run_name,
                    "repeat_index": repeat_index,
                    "inter_run_pause_seconds": float(item.get("inter_run_pause_seconds", 0.0)),
                    "workloads": json.loads(json.dumps(workloads)),
                    "workload_summary": _summarize_workloads(workloads),
                    **prepare_params,
                }
            )
    return defaults, expanded


class _AsyncRemoteRun:
    def __init__(self, label, process, resource=None):
        self.label = label
        self.process = process
        self.resource = resource

    def wait(self, timeout=None, check=True):
        try:
            return_code = self.process.wait(timeout=timeout)
        finally:
            if self.resource is not None and self.process.poll() is not None:
                self.resource.close()
        if check and return_code != 0:
            raise subprocess.CalledProcessError(return_code, self.process.args)
        return return_code

    def send_signal(self, sig):
        if self.process.poll() is None:
            self.process.send_signal(sig)


class RemoteTransport:
    def __init__(self, mode, password):
        self.mode = str(mode)
        self.password = password
        if self.mode not in {"sshpass", "system"}:
            raise SystemExit("unsupported ssh_mode: %s" % self.mode)

    def _base(self):
        if self.mode == "sshpass":
            return ["sshpass", "-p", self.password]
        return []

    def ssh_command(self, host, tty):
        command = self._base() + [
            "ssh",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "KexAlgorithms=+%s" % DEFAULT_KEX_ALGORITHMS,
        ]
        if tty:
            command.append("-tt")
        command.append(host)
        return command

    def scp_command(self, recursive):
        command = self._base() + [
            "scp",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "KexAlgorithms=+%s" % DEFAULT_KEX_ALGORITHMS,
        ]
        if recursive:
            command.append("-r")
        return command


class SweepRunner:
    def __init__(self, output_dir, config_path, defaults, password=None):
        self.output_dir = Path(output_dir).resolve()
        self.config_path = Path(config_path).resolve()
        self.defaults = defaults
        if self.defaults["receiver_capture_mode"] not in {"auto", "count", "time_window"}:
            raise SystemExit("unsupported receiver_capture_mode: %s" % self.defaults["receiver_capture_mode"])
        if self.defaults["receiver_capture_primary_mode"] != "count":
            raise SystemExit(
                "unsupported receiver_capture_primary_mode: %s" % self.defaults["receiver_capture_primary_mode"]
            )
        if self.defaults["receiver_capture_fallback_mode"] != "time_window":
            raise SystemExit(
                "unsupported receiver_capture_fallback_mode: %s" % self.defaults["receiver_capture_fallback_mode"]
            )
        self.password = password if defaults["ssh_mode"] == "sshpass" else None
        self.transport = RemoteTransport(defaults["ssh_mode"], self.password or "")
        self.log_dir = self.output_dir / "logs"
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def _step_log_path(self, run_dir):
        return self.log_dir / (Path(run_dir).name + ".log")

    def _log(self, handle, message):
        handle.write("[%s] %s\n" % (datetime.now().isoformat(timespec="seconds"), message))
        handle.flush()

    def _run_local(self, handle, command, cwd=None, check=True):
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "LOCAL  %s" % rendered)
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, command)
        return result

    def _run_remote_command(self, handle, host, remote_command, tty, check=True):
        command = self.transport.ssh_command(host, tty) + [remote_command]
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "REMOTE %s" % rendered)
        result = subprocess.run(
            command,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, command)
        return result

    def _run_remote_capture(self, handle, host, remote_command, tty, check=True):
        command = self.transport.ssh_command(host, tty) + [remote_command]
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "REMOTE %s" % rendered)
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if result.stdout:
            handle.write(result.stdout)
            if not result.stdout.endswith("\n"):
                handle.write("\n")
            handle.flush()
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, command)
        return result

    def _run_scp(self, handle, src, dst, recursive, check=True):
        command = self.transport.scp_command(recursive) + [src, dst]
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "COPY   %s" % rendered)
        result = subprocess.run(
            command,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, command)
        return result

    def _remote_command_from_script(self, script_path):
        script_text = Path(script_path).read_text(encoding="utf-8")
        return "bash -lc %s" % shlex.quote(script_text)

    def _run_remote_script(self, handle, host, script_path, tty, check=True):
        command = self.transport.ssh_command(host, tty) + [self._remote_command_from_script(script_path)]
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "REMOTE %s < %s" % (rendered, script_path))
        result = subprocess.run(
            command,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, command)
        return result

    def _start_remote_script(self, handle, host, script_path, tty):
        command = self.transport.ssh_command(host, tty) + [self._remote_command_from_script(script_path)]
        rendered = " ".join(shlex.quote(part) for part in command)
        self._log(handle, "ASYNC  %s < %s" % (rendered, script_path))
        process = subprocess.Popen(
            command,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        return _AsyncRemoteRun(str(script_path), process)

    def _stop_async_remote_run(self, handle, async_run, grace_seconds):
        self._log(handle, "ASYNC  %s timed out; sending SIGINT" % async_run.label)
        async_run.send_signal(signal.SIGINT)
        try:
            return_code = async_run.wait(timeout=grace_seconds, check=False)
            self._log(handle, "ASYNC  %s exited rc=%s after SIGINT" % (async_run.label, return_code))
            return return_code
        except subprocess.TimeoutExpired:
            self._log(handle, "ASYNC  %s still running after SIGINT; sending SIGTERM" % async_run.label)
            async_run.send_signal(signal.SIGTERM)
            try:
                return_code = async_run.wait(timeout=grace_seconds, check=False)
                self._log(handle, "ASYNC  %s exited rc=%s after SIGTERM" % (async_run.label, return_code))
                return return_code
            except subprocess.TimeoutExpired:
                self._log(handle, "ASYNC  %s still running after SIGTERM; killing local ssh process" % async_run.label)
                async_run.process.kill()
                return_code = async_run.wait(check=False)
                self._log(handle, "ASYNC  %s exited rc=%s after SIGKILL" % (async_run.label, return_code))
                return return_code

    def _wait_receiver_batch_capture(self, handle, receiver_batch, manifest):
        completion_timeout = manifest.get("sweep", {}).get("receiver_capture_completion_timeout_seconds")
        if completion_timeout is None:
            completion_timeout = manifest.get("metrics", {}).get("completion_timeout_seconds")
        capture_window_seconds = float(
            completion_timeout
            if completion_timeout is not None
            else manifest.get("capture", {}).get("batch_time_window_seconds", DEFAULT_PRE_CAPTURE_DELAY_SECONDS)
        )
        capture_timeout_seconds = max(
            5.0,
            capture_window_seconds + float(self.defaults["receiver_capture_timeout_margin_seconds"]),
        )
        grace_seconds = max(
            float(self.defaults["receiver_capture_grace_seconds"]),
            min(5.0, capture_window_seconds),
        )
        try:
            receiver_batch.wait(timeout=capture_timeout_seconds)
        except subprocess.TimeoutExpired:
            self._stop_async_remote_run(handle, receiver_batch, grace_seconds)

    def _stage_artifacts(self, run_dir, manifest, handle):
        usc = manifest["usc"]
        netfpga_root = usc["remote_netfpga_root"]
        netfpga_results = usc["remote_netfpga_results"]
        sender_root = usc["remote_sender_root"]
        receiver_root = usc["remote_receiver_root"]

        self._run_remote_command(
            handle,
            usc["netfpga_host"],
            "mkdir -p %s %s" % (_shell_remote_path(netfpga_root), _shell_remote_path(netfpga_results)),
            tty=False,
        )
        self._run_scp(
            handle,
            str(run_dir / "deploy_netfpga") + "/.",
            "%s:%s/" % (usc["netfpga_host"], netfpga_root),
            recursive=True,
        )
        self._run_scp(
            handle,
            str(run_dir / "bundle"),
            "%s:%s/bundle" % (usc["netfpga_host"], netfpga_root),
            recursive=True,
        )

        self._run_remote_command(
            handle,
            usc["sender_host"],
            "mkdir -p %s %s" % (
                _shell_remote_path("%s/pcaps" % sender_root),
                _shell_remote_path("%s/captures" % sender_root),
            ),
            tty=False,
        )
        self._run_scp(
            handle,
            str(run_dir / "pcaps") + "/.",
            "%s:%s/pcaps/" % (usc["sender_host"], sender_root),
            recursive=True,
        )

        self._run_remote_command(
            handle,
            usc["receiver_host"],
            "mkdir -p %s" % _shell_remote_path("%s/captures" % receiver_root),
            tty=False,
        )

    def _fetch_artifacts(self, run_dir, manifest, handle):
        usc = manifest["usc"]
        local_capture_dir = run_dir / "captures"
        local_capture_dir.mkdir(parents=True, exist_ok=True)
        debug_name = Path(manifest["artifacts"]["debug_status_txt"]).name

        self._run_scp(
            handle,
            "%s:%s/captures/*.cap" % (usc["receiver_host"], usc["remote_receiver_root"]),
            str(local_capture_dir) + "/",
            recursive=False,
        )
        self._run_scp(
            handle,
            "%s:%s/captures/*.cap" % (usc["sender_host"], usc["remote_sender_root"]),
            str(local_capture_dir) + "/",
            recursive=False,
        )
        self._run_scp(
            handle,
            "%s:%s/%s" % (usc["netfpga_host"], usc["remote_netfpga_results"], debug_name),
            str(run_dir / manifest["artifacts"]["debug_status_txt"]),
            recursive=False,
        )

    def _batch_attempt_paths(self, run_dir, manifest, attempt_name):
        names = _attempt_capture_names(attempt_name)
        receiver_root = manifest["usc"]["remote_receiver_root"]
        sender_root = manifest["usc"]["remote_sender_root"]
        local_capture_dir = run_dir / "captures"
        return {
            "receiver_remote": "%s/captures/%s" % (receiver_root, names["receiver_capture"]),
            "sender_remote": "%s/captures/%s" % (sender_root, names["sender_capture"]),
            "receiver_local": local_capture_dir / names["receiver_capture"],
            "sender_local": local_capture_dir / names["sender_capture"],
            "receiver_script": names["receiver_script"],
            "sender_script": names["sender_script"],
            "mode": names["mode"],
        }

    def _single_packet_paths(self, run_dir, manifest, variant):
        receiver_root = manifest["usc"]["remote_receiver_root"]
        local_capture_dir = run_dir / "captures"
        mapping = {
            "offload": {
                "capture_name": SINGLE_OFFLOAD_CAPTURE_NAME,
                "receiver_script": "nf1_capture_offload_smoke.sh",
                "replay_script": "nf4_replay_offload_smoke.sh",
            },
            "wrong_magic": {
                "capture_name": "wrong_magic_bypass.cap",
                "receiver_script": "nf1_capture_wrong_magic.sh",
                "replay_script": "nf4_replay_wrong_magic.sh",
            },
            "wrong_port": {
                "capture_name": "wrong_port_bypass.cap",
                "receiver_script": "nf1_capture_wrong_port.sh",
                "replay_script": "nf4_replay_wrong_port.sh",
            },
        }
        selected = mapping[variant]
        return {
            "receiver_remote": "%s/captures/%s" % (receiver_root, selected["capture_name"]),
            "receiver_local": local_capture_dir / selected["capture_name"],
            "receiver_script": selected["receiver_script"],
            "replay_script": selected["replay_script"],
        }

    def _fetch_single_remote_artifact(self, handle, host, remote_path, local_path):
        result = self._run_scp(
            handle,
            "%s:%s" % (host, remote_path),
            str(local_path),
            recursive=False,
            check=False,
        )
        return result.returncode

    def _remote_artifact_state(self, handle, host, path):
        remote_path = _shell_remote_path(path)
        result = self._run_remote_capture(
            handle,
            host,
            "if [ -f {path} ]; then bytes=$(wc -c < {path}); "
            "printf 'exists=1\\nsize_bytes=%s\\n' \"$bytes\"; "
            "else printf 'exists=0\\n'; fi".format(path=remote_path),
            tty=False,
        )
        state = {
            "host": host,
            "path": str(path),
            "exists": False,
            "size_bytes": None,
        }
        for raw_line in result.stdout.splitlines():
            if "=" not in raw_line:
                continue
            key, value = raw_line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if key == "exists":
                state["exists"] = value == "1"
            elif key == "size_bytes":
                state["size_bytes"] = int(value)
        return state

    def _run_batch_capture_attempt(self, run_dir, manifest, handle, attempt_name):
        usc = manifest["usc"]
        commands_dir = run_dir / "commands"
        paths = self._batch_attempt_paths(run_dir, manifest, attempt_name)
        capture_ready_delay_seconds = max(
            float(self.defaults["capture_ready_delay_seconds"]),
            float(manifest.get("sweep", {}).get("batch_pre_replay_delay_seconds", 0.0)),
        )

        self._run_remote_script(
            handle,
            usc["receiver_host"],
            commands_dir / "nf1_cleanup_offload_batch_receiver_captures.sh",
            tty=False,
        )
        self._run_remote_script(
            handle,
            usc["sender_host"],
            commands_dir / "nf4_cleanup_offload_batch_sender_captures.sh",
            tty=False,
        )

        receiver_batch = self._start_remote_script(
            handle,
            usc["receiver_host"],
            commands_dir / paths["receiver_script"],
            tty=True,
        )
        sender_batch = self._start_remote_script(
            handle,
            usc["sender_host"],
            commands_dir / paths["sender_script"],
            tty=True,
        )
        time.sleep(capture_ready_delay_seconds)
        self._run_remote_script(handle, usc["sender_host"], commands_dir / "nf4_replay_offload_batch.sh", tty=True)
        sender_batch.wait()
        self._wait_receiver_batch_capture(handle, receiver_batch, manifest)

        attempt = {
            "name": attempt_name,
            "mode": paths["mode"],
            "remote": {
                "receiver": self._remote_artifact_state(handle, usc["receiver_host"], paths["receiver_remote"]),
                "sender": self._remote_artifact_state(handle, usc["sender_host"], paths["sender_remote"]),
            },
            "local": {
                "receiver": _local_artifact_state(paths["receiver_local"]),
                "sender": _local_artifact_state(paths["sender_local"]),
            },
            "fetch": {
                "receiver_return_code": None,
                "sender_return_code": None,
            },
        }

        if attempt["remote"]["receiver"]["exists"]:
            attempt["fetch"]["receiver_return_code"] = self._fetch_single_remote_artifact(
                handle,
                usc["receiver_host"],
                paths["receiver_remote"],
                paths["receiver_local"],
            )
        if attempt["remote"]["sender"]["exists"]:
            attempt["fetch"]["sender_return_code"] = self._fetch_single_remote_artifact(
                handle,
                usc["sender_host"],
                paths["sender_remote"],
                paths["sender_local"],
            )

        attempt["local"]["receiver"] = _local_artifact_state(paths["receiver_local"])
        attempt["local"]["sender"] = _local_artifact_state(paths["sender_local"])
        attempt["status"] = _attempt_artifact_status(attempt, int(manifest["counts"]["batch_packet_count"]))
        return attempt

    def _run_single_packet_capture(self, run_dir, manifest, handle, variant):
        commands_dir = run_dir / "commands"
        sender_host = manifest["usc"]["sender_host"]
        receiver_host = manifest["usc"]["receiver_host"]
        paths = self._single_packet_paths(run_dir, manifest, variant)

        local_capture = Path(paths["receiver_local"])
        if local_capture.exists():
            local_capture.unlink()
        self._run_remote_command(
            handle,
            receiver_host,
            "rm -f %s" % _shell_remote_path(paths["receiver_remote"]),
            tty=False,
        )

        receiver_capture = self._start_remote_script(
            handle,
            receiver_host,
            commands_dir / paths["receiver_script"],
            tty=True,
        )
        time.sleep(float(self.defaults["pre_capture_delay_seconds"]))
        self._run_remote_script(handle, sender_host, commands_dir / paths["replay_script"], tty=True)
        receiver_capture.wait()

        remote_state = self._remote_artifact_state(handle, receiver_host, paths["receiver_remote"])
        fetch_return_code = None
        if remote_state["exists"]:
            fetch_return_code = self._fetch_single_remote_artifact(
                handle,
                receiver_host,
                paths["receiver_remote"],
                paths["receiver_local"],
            )
        local_state = _local_artifact_state(paths["receiver_local"])
        return {
            "remote": remote_state,
            "local": local_state,
            "fetch_return_code": fetch_return_code,
        }

    def _expected_single_packet_request_id(self, manifest, variant):
        if variant == "wrong_magic":
            return manifest["smoke"]["wrong_magic_request_id"]
        if variant == "wrong_port":
            return manifest["smoke"]["wrong_port_request_id"]
        return manifest["network"]["request_id_base"]

    def _single_packet_offload_verdict(self, run_dir, manifest, capture_state):
        expected_rows = _load_json(run_dir / manifest["artifacts"]["selected_expected_outputs"])
        if expected_rows:
            expected_rows = [expected_rows[0]]
        frames = read_pcap(capture_state["path"])
        observed_rows = observed_rows_from_frames(
            frames,
            expected_rows=expected_rows,
            result_mode=manifest["model"]["result_mode"],
            request_id_base=_parse_int(manifest["network"]["request_id_base"]),
        )
        summary = compare_expected_observed(expected_rows, observed_rows)
        return {
            "verdict": "healthy" if not summary.get("missing_samples") and not summary.get("mismatches") else "mismatch",
            "packet_count": len(frames),
            "observed_count": len(observed_rows),
            "class_matches": summary.get("class_matches"),
            "wire_matches": summary.get("wire_matches"),
            "missing_samples": summary.get("missing_samples", []),
            "mismatch_count": len(summary.get("mismatches", [])),
            "request_id": "0x%04x" % int(observed_rows[0]["request_id"]) if observed_rows else None,
        }

    def _single_packet_bypass_verdict(self, manifest, capture_state, variant):
        frames = read_pcap(capture_state["path"])
        inspected = inspect_ann_frame(frames[0], manifest["model"]["result_mode"]) if frames else {}
        expected_request_id = self._expected_single_packet_request_id(manifest, variant)
        if variant == "wrong_magic":
            expected_magic = "0x%04x" % DEFAULT_WRONG_MAGIC
            expected_udp_dst = manifest["network"]["dst_udp_port"]
            passed = (
                len(frames) >= 1
                and inspected.get("payload_magic") == expected_magic
                and inspected.get("udp_dst_port") == expected_udp_dst
                and (
                    "0x%04x" % int(inspected["request_id"])
                    if inspected.get("request_id") is not None
                    else None
                ) == expected_request_id
            )
        else:
            expected_magic = "0x%04x" % ANN_TASK_MAGIC
            expected_udp_dst = "0x%04x" % DEFAULT_WRONG_PORT
            passed = (
                len(frames) >= 1
                and inspected.get("frame_kind") == "ann_task"
                and inspected.get("payload_magic") == expected_magic
                and inspected.get("udp_dst_port") == expected_udp_dst
                and (
                    "0x%04x" % int(inspected["request_id"])
                    if inspected.get("request_id") is not None
                    else None
                ) == expected_request_id
            )
        return {
            "verdict": "bypass_ok" if passed else "bypass_mismatch",
            "packet_count": len(frames),
            "request_id": "0x%04x" % int(inspected["request_id"]) if inspected.get("request_id") is not None else None,
            "payload_magic": inspected.get("payload_magic"),
            "udp_dst_port": inspected.get("udp_dst_port"),
            "frame_kind": inspected.get("frame_kind"),
        }

    def _execute_single_packet_workload(self, run_dir, manifest, handle, workload):
        variant = workload["variant"]
        capture_result = self._run_single_packet_capture(run_dir, manifest, handle, variant)
        step_result = {
            "type": "single_packet",
            "variant": variant,
            "status": "failed",
            "verdict": None,
            "failed_step": None,
            "error": None,
            "request_id": self._expected_single_packet_request_id(manifest, variant),
            "capture_path": _relpath(capture_result["local"]["path"], self.output_dir),
            "capture_exists": capture_result["local"]["exists"],
            "capture_remote_exists": capture_result["remote"]["exists"],
            "capture_size_bytes": capture_result["local"].get("size_bytes"),
            "packet_count": capture_result["local"].get("packet_count"),
        }
        if not capture_result["remote"]["exists"]:
            step_result["failed_step"] = "capture"
            step_result["error"] = "remote capture missing"
            return step_result
        if not capture_result["local"]["exists"]:
            step_result["failed_step"] = "fetch"
            step_result["error"] = "local capture missing after fetch"
            return step_result

        if variant == "offload":
            verdict = self._single_packet_offload_verdict(run_dir, manifest, capture_result["local"])
            step_result.update(verdict)
            step_result["status"] = "passed" if verdict["verdict"] == "healthy" else "failed"
            if step_result["status"] != "passed":
                step_result["failed_step"] = "compare"
                step_result["error"] = "single packet offload compare failed"
            return step_result

        verdict = self._single_packet_bypass_verdict(manifest, capture_result["local"], variant)
        step_result.update(verdict)
        step_result["status"] = "passed" if verdict["verdict"] == "bypass_ok" else "failed"
        if step_result["status"] != "passed":
            step_result["failed_step"] = "compare"
            step_result["error"] = "single packet bypass capture did not match expected wire fields"
        return step_result

    def _select_best_batch_attempt(self, manifest, attempts):
        expected_count = int(manifest["counts"]["batch_packet_count"])
        ordered_attempts = [attempts[name] for name in ("primary", "fallback") if name in attempts]
        for attempt in ordered_attempts:
            receiver_count = _attempt_packet_count(attempt["local"]["receiver"])
            sender_count = _attempt_packet_count(attempt["local"]["sender"])
            if receiver_count >= expected_count and sender_count >= expected_count:
                return attempt
        best_attempt = None
        best_key = (-1, -1, -1, -1)
        for attempt in ordered_attempts:
            receiver_local = attempt["local"]["receiver"]
            sender_local = attempt["local"]["sender"]
            candidate_key = (
                _attempt_packet_count(receiver_local),
                _attempt_packet_count(sender_local),
                1 if receiver_local.get("exists") else 0,
                1 if sender_local.get("exists") else 0,
            )
            if candidate_key > best_key:
                best_key = candidate_key
                best_attempt = attempt
        if best_attempt is None:
            return None
        if best_key[0] <= 0 and best_key[2] == 0:
            return None
        return best_attempt

    def _promote_selected_batch_artifacts(self, run_dir, selected_attempt):
        local_capture_dir = run_dir / "captures"
        canonical_receiver = local_capture_dir / CANONICAL_RECEIVER_BATCH_CAPTURE_NAME
        canonical_sender = local_capture_dir / CANONICAL_SENDER_BATCH_CAPTURE_NAME
        if canonical_receiver.exists():
            canonical_receiver.unlink()
        if canonical_sender.exists():
            canonical_sender.unlink()
        if selected_attempt is None:
            return {
                "receiver": _local_artifact_state(canonical_receiver),
                "sender": _local_artifact_state(canonical_sender),
            }

        receiver_source = Path(selected_attempt["local"]["receiver"]["path"])
        sender_source = Path(selected_attempt["local"]["sender"]["path"])
        if receiver_source.exists():
            shutil.copy2(receiver_source, canonical_receiver)
        if sender_source.exists():
            shutil.copy2(sender_source, canonical_sender)
        return {
            "receiver": _local_artifact_state(canonical_receiver),
            "sender": _local_artifact_state(canonical_sender),
        }

    def _collect_artifact_diagnostics(self, run_dir, manifest, handle, attempts):
        usc = manifest["usc"]
        artifacts = manifest["artifacts"]
        receiver_root = usc["remote_receiver_root"]
        netfpga_results = usc["remote_netfpga_results"]

        self._fetch_artifacts(run_dir, manifest, handle)
        for attempt_name, attempt in attempts.items():
            paths = self._batch_attempt_paths(run_dir, manifest, attempt_name)
            attempt["local"]["receiver"] = _local_artifact_state(paths["receiver_local"])
            attempt["local"]["sender"] = _local_artifact_state(paths["sender_local"])
            attempt["status"] = _attempt_artifact_status(attempt, int(manifest["counts"]["batch_packet_count"]))

        selected_attempt = self._select_best_batch_attempt(manifest, attempts)
        promoted = self._promote_selected_batch_artifacts(run_dir, selected_attempt)
        chosen_remote_receiver = None
        chosen_remote_sender = None
        if selected_attempt is not None:
            chosen_remote_receiver = selected_attempt["remote"]["receiver"]
            chosen_remote_sender = selected_attempt["remote"]["sender"]
        else:
            for attempt_name in ("primary", "fallback"):
                attempt = attempts.get(attempt_name)
                if attempt is not None and attempt["remote"]["receiver"].get("exists"):
                    chosen_remote_receiver = attempt["remote"]["receiver"]
                    chosen_remote_sender = attempt["remote"]["sender"]
                    break
        if chosen_remote_receiver is None:
            chosen_remote_receiver = {
                "host": usc["receiver_host"],
                "path": "%s/%s" % (receiver_root, artifacts["offload_batch_time_window_capture"]),
                "exists": False,
                "size_bytes": None,
            }
        if chosen_remote_sender is None:
            chosen_remote_sender = {
                "host": usc["sender_host"],
                "path": "%s/captures/%s" % (usc["remote_sender_root"], CANONICAL_SENDER_BATCH_CAPTURE_NAME),
                "exists": False,
                "size_bytes": None,
            }

        diagnostics = {
            "remote": {
                "receiver": {
                    "wrong_magic_bypass": self._remote_artifact_state(
                        handle,
                        usc["receiver_host"],
                        "%s/captures/wrong_magic_bypass.cap" % receiver_root,
                    ),
                    "wrong_port_bypass": self._remote_artifact_state(
                        handle,
                        usc["receiver_host"],
                        "%s/captures/wrong_port_bypass.cap" % receiver_root,
                    ),
                    "offload_batch_time_window": chosen_remote_receiver,
                },
                "sender": {
                    "offload_batch_sender": chosen_remote_sender,
                },
                "netfpga": {
                    "debug_status_post": self._remote_artifact_state(
                        handle,
                        usc["netfpga_host"],
                        "%s/%s" % (netfpga_results, Path(artifacts["debug_status_txt"]).name),
                    ),
                },
            },
            "local": {
                "receiver": {
                    "wrong_magic_bypass": _local_artifact_state(run_dir / "captures" / "wrong_magic_bypass.cap"),
                    "wrong_port_bypass": _local_artifact_state(run_dir / "captures" / "wrong_port_bypass.cap"),
                    "offload_batch_time_window": promoted["receiver"],
                },
                "sender": {
                    "offload_batch_sender": promoted["sender"],
                },
                "netfpga": {
                    "debug_status_post": _local_artifact_state(run_dir / artifacts["debug_status_txt"]),
                },
            },
            "receiver_capture_attempts": attempts,
            "receiver_capture_mode_attempted": [attempt["mode"] for attempt in attempts.values()],
            "receiver_capture_mode_used": selected_attempt["mode"] if selected_attempt is not None else None,
            "receiver_capture_primary_status": attempts.get("primary", {}).get("status"),
            "receiver_capture_fallback_status": attempts.get("fallback", {}).get("status"),
            "selected_attempt_name": selected_attempt["name"] if selected_attempt is not None else None,
        }
        diagnostics["capture_issue"] = _classify_receiver_batch_artifact(
            diagnostics["remote"]["receiver"]["offload_batch_time_window"],
            diagnostics["local"]["receiver"]["offload_batch_time_window"],
        )
        diagnostics["required_artifacts_ready"] = (
            diagnostics["local"]["receiver"]["offload_batch_time_window"]["exists"]
            and diagnostics["local"]["sender"]["offload_batch_sender"]["exists"]
            and diagnostics["local"]["netfpga"]["debug_status_post"]["exists"]
        )
        return diagnostics

    def _augment_result_from_artifacts(self, result, run_dir, manifest, diagnostics):
        result["artifact_diagnostics"] = diagnostics
        result["capture_issue"] = diagnostics.get("capture_issue")
        result["receiver_capture_mode_attempted"] = diagnostics.get("receiver_capture_mode_attempted", [])
        result["receiver_capture_mode_used"] = diagnostics.get("receiver_capture_mode_used")
        result["receiver_capture_primary_status"] = diagnostics.get("receiver_capture_primary_status")
        result["receiver_capture_fallback_status"] = diagnostics.get("receiver_capture_fallback_status")
        result["receiver_capture_cleanup_status"] = "completed"
        if result["capture_issue"] is not None and result.get("receiver_capture_fallback_status") in {"missing", None}:
            result["capture_resolution_status"] = "capture_dual_failed"
        elif result["receiver_capture_mode_used"] == "time_window" and result.get("capture_issue") is None:
            result["capture_resolution_status"] = "capture_primary_failed_fallback_passed"
        elif result["receiver_capture_mode_used"] == "count" and result.get("capture_issue") is None:
            result["capture_resolution_status"] = "capture_primary_passed"

        receiver_remote = diagnostics["remote"]["receiver"]["offload_batch_time_window"]
        receiver_local = diagnostics["local"]["receiver"]["offload_batch_time_window"]
        result["receiver_capture_remote_exists"] = receiver_remote["exists"]
        result["receiver_capture_remote_size_bytes"] = receiver_remote.get("size_bytes")
        result["receiver_capture_local_exists"] = receiver_local["exists"]
        result["receiver_capture_local_size_bytes"] = receiver_local.get("size_bytes")
        result["receiver_capture_count"] = receiver_local.get("packet_count")
        result["receiver_capture_remote_packet_count"] = receiver_local.get("packet_count")
        result["receiver_capture_local_packet_count"] = receiver_local.get("packet_count")

        sender_local = diagnostics["local"]["sender"]["offload_batch_sender"]
        result["sender_capture_local_exists"] = sender_local["exists"]
        result["sender_capture_local_size_bytes"] = sender_local.get("size_bytes")
        result["sender_capture_count"] = sender_local.get("packet_count")

        debug_local = diagnostics["local"]["netfpga"]["debug_status_post"]
        result["debug_status_local_exists"] = debug_local["exists"]
        if debug_local["exists"]:
            debug_status = _parse_debug_status_text(Path(debug_local["path"]).read_text(encoding="utf-8"))
            result["debug_status"] = debug_status
            result["offload_accept_count"] = debug_status.get("offload_accept_count")
            result["compute_done_count"] = debug_status.get("compute_done_count")
            result["engine_emit_count"] = debug_status.get("result_emit_count")
            if result.get("pipeline_verdict") is None and result.get("engine_emit_count") is not None:
                if result["engine_emit_count"] == int(manifest["counts"]["batch_packet_count"]):
                    result["pipeline_verdict"] = "engine_emit_complete"

    def _apply_batch_report_to_step_result(self, step_result, report_path, summary_path):
        report = _load_json(report_path)
        step_result["pipeline_verdict"] = report.get("pipeline_verdict")
        step_result["verdict"] = report.get("pipeline_verdict")
        step_result["correctness_verdict"] = report.get("correctness_verdict")
        step_result["missing_request_ids"] = report.get("missing_request_ids", [])
        step_result["mismatch_count"] = len(report.get("mismatches", []))
        step_result["missing_sample_count"] = len(report.get("missing_samples", []))
        step_result["sender_capture_count"] = report.get("sender_capture_count")
        step_result["receiver_capture_count"] = report.get("receiver_capture_count")
        step_result["engine_emit_count"] = report.get("engine_emit_count")
        step_result["capture_vs_emit_gap"] = report.get("capture_vs_emit_gap")
        step_result["report_json"] = _relpath(report_path, self.output_dir)
        if summary_path.exists():
            step_result["summary_md"] = _relpath(summary_path, self.output_dir)

    def _execute_batch_workload(self, run_dir, manifest, handle, workload):
        step_result = {
            "type": "batch",
            "variant": None,
            "batch_size": workload["batch_size"],
            "batch_time_window_seconds": workload["batch_time_window_seconds"],
            "batch_pre_replay_delay_seconds": workload["batch_pre_replay_delay_seconds"],
            "batch_include_smoke_steps": bool(workload.get("batch_include_smoke_steps", True)),
            "request_id_base": str(workload["request_id_base"]),
            "status": "pending",
            "failed_step": None,
            "error": None,
            "report_exit_code": None,
            "board_passed": False,
            "receiver_capture_mode_attempted": [],
            "receiver_capture_mode_used": None,
            "receiver_capture_primary_status": None,
            "receiver_capture_fallback_status": None,
        }
        diagnostics = self._run_capture_sequence(
            run_dir,
            manifest,
            handle,
            include_smoke_steps=bool(workload.get("batch_include_smoke_steps", True)),
        )
        self._augment_result_from_artifacts(step_result, run_dir, manifest, diagnostics)

        if not diagnostics.get("required_artifacts_ready"):
            step_result["status"] = "report_blocked"
            step_result["failed_step"] = "fetch" if step_result.get("capture_issue") == "fetch_side_issue" else "capture"
            step_result["error"] = "required local artifacts missing before report"
            return step_result

        report_result = self._run_report(run_dir, handle)
        step_result["report_exit_code"] = report_result.returncode
        report_path = run_dir / "board_eval_report.json"
        summary_path = run_dir / "board_test_summary.md"
        if report_path.exists():
            self._apply_batch_report_to_step_result(step_result, report_path, summary_path)
        step_result["board_passed"] = report_result.returncode == 0
        step_result["status"] = "passed" if step_result["board_passed"] else "report_failed"
        return step_result

    def _run_capture_sequence(self, run_dir, manifest, handle, include_smoke_steps=True):
        commands_dir = run_dir / "commands"
        pre_capture_delay_seconds = float(self.defaults["pre_capture_delay_seconds"])
        sender_host = manifest["usc"]["sender_host"]
        receiver_host = manifest["usc"]["receiver_host"]
        netfpga_host = manifest["usc"]["netfpga_host"]

        if include_smoke_steps:
            receiver_capture = self._start_remote_script(
                handle,
                receiver_host,
                commands_dir / "nf1_capture_wrong_magic.sh",
                tty=True,
            )
            time.sleep(pre_capture_delay_seconds)
            self._run_remote_script(handle, sender_host, commands_dir / "nf4_replay_wrong_magic.sh", tty=True)
            receiver_capture.wait()

            receiver_capture = self._start_remote_script(
                handle,
                receiver_host,
                commands_dir / "nf1_capture_wrong_port.sh",
                tty=True,
            )
            time.sleep(pre_capture_delay_seconds)
            self._run_remote_script(handle, sender_host, commands_dir / "nf4_replay_wrong_port.sh", tty=True)
            receiver_capture.wait()

        attempts = {}
        capture_mode = str(self.defaults["receiver_capture_mode"])
        if capture_mode in {"auto", "count"}:
            attempts["primary"] = self._run_batch_capture_attempt(run_dir, manifest, handle, "primary")
        primary_complete = attempts.get("primary", {}).get("status") == "complete"
        if capture_mode in {"auto", "time_window"} and not primary_complete:
            attempts["fallback"] = self._run_batch_capture_attempt(run_dir, manifest, handle, "fallback")

        self._run_remote_script(handle, netfpga_host, commands_dir / "nf3_debug_snapshot.sh", tty=False)
        return self._collect_artifact_diagnostics(run_dir, manifest, handle, attempts)

    def _run_report(self, run_dir, handle):
        batch_capture = run_dir / "captures" / "offload_batch_time_window.cap"
        sender_capture = run_dir / "captures" / "offload_batch_sender.cap"
        command = [
            sys.executable,
            str(BOARDCTL_PATH),
            "report",
            str(run_dir / "manifest.json"),
            "--batch-capture",
            str(batch_capture),
            "--sender-capture",
            str(sender_capture),
        ]
        return self._run_local(handle, command, check=False)

    def execute_experiment(self, experiment):
        run_dir = self.output_dir / experiment["run_name"]
        log_path = self._step_log_path(run_dir)
        result = {
            "experiment_name": experiment["name"],
            "run_name": experiment["run_name"],
            "repeat_index": experiment["repeat_index"],
            "run_dir": str(run_dir),
            "batch_size": experiment["batch_size"],
            "batch_time_window_seconds": experiment["batch_time_window_seconds"],
            "batch_pre_replay_delay_seconds": experiment["batch_pre_replay_delay_seconds"],
            "request_id_base": str(experiment["request_id_base"]),
            "workload_summary": experiment["workload_summary"],
            "workload_results": [],
            "status": "pending",
            "failed_step": None,
            "error": None,
            "report_exit_code": None,
            "board_passed": False,
            "receiver_capture_mode_attempted": [],
            "receiver_capture_mode_used": None,
            "receiver_capture_primary_status": None,
            "receiver_capture_fallback_status": None,
            "runner_log": _relpath(log_path, self.output_dir),
        }

        with open(log_path, "w", encoding="utf-8") as handle:
            self._log(handle, "run_name=%s" % experiment["run_name"])
            self._log(handle, "config=%s" % self.config_path)
            self._log(handle, "workloads=%s" % experiment["workload_summary"])
            self._log(handle, "prepare_limit=%s" % experiment["prepare_limit"])

            try:
                prepare_command = _build_prepare_command(run_dir, self.defaults, experiment)
                self._run_local(handle, prepare_command)
                self._run_local(handle, [sys.executable, str(BOARDCTL_PATH), "bringup", str(run_dir / "manifest.json")])
                self._run_local(handle, [sys.executable, str(BOARDCTL_PATH), "capture", str(run_dir / "manifest.json")])

                manifest = _load_json(run_dir / "manifest.json")
                manifest["sweep"] = {
                    "batch_pre_replay_delay_seconds": experiment["batch_pre_replay_delay_seconds"],
                    "capture_ready_delay_seconds": self.defaults["capture_ready_delay_seconds"],
                    "receiver_capture_mode": self.defaults["receiver_capture_mode"],
                    "receiver_capture_primary_mode": self.defaults["receiver_capture_primary_mode"],
                    "receiver_capture_fallback_mode": self.defaults["receiver_capture_fallback_mode"],
                }
                _write_json(run_dir / "manifest.json", manifest)
                self._stage_artifacts(run_dir, manifest, handle)
                self._run_remote_script(
                    handle,
                    manifest["usc"]["netfpga_host"],
                    run_dir / "commands" / "nf3_bringup.sh",
                    tty=False,
                )
                for workload in experiment["workloads"]:
                    if workload["type"] == "single_packet":
                        step_result = self._execute_single_packet_workload(run_dir, manifest, handle, workload)
                    elif workload["type"] == "batch":
                        step_result = self._execute_batch_workload(run_dir, manifest, handle, workload)
                    else:
                        raise ValueError("unsupported workload type: %s" % workload["type"])
                    result["workload_results"].append(step_result)
                    if step_result["type"] == "batch":
                        for key in [
                            "report_exit_code",
                            "receiver_capture_mode_attempted",
                            "receiver_capture_mode_used",
                            "receiver_capture_primary_status",
                            "receiver_capture_fallback_status",
                            "capture_issue",
                            "capture_resolution_status",
                            "receiver_capture_remote_exists",
                            "receiver_capture_remote_size_bytes",
                            "receiver_capture_local_exists",
                            "receiver_capture_local_size_bytes",
                            "receiver_capture_count",
                            "receiver_capture_remote_packet_count",
                            "receiver_capture_local_packet_count",
                            "sender_capture_local_exists",
                            "sender_capture_local_size_bytes",
                            "sender_capture_count",
                            "debug_status_local_exists",
                            "debug_status",
                            "offload_accept_count",
                            "compute_done_count",
                            "engine_emit_count",
                            "pipeline_verdict",
                            "missing_request_ids",
                            "mismatch_count",
                            "missing_sample_count",
                            "capture_vs_emit_gap",
                            "report_json",
                            "summary_md",
                        ]:
                            if key in step_result:
                                result[key] = step_result[key]
                    if step_result["status"] != "passed":
                        result["status"] = step_result["status"]
                        result["failed_step"] = step_result.get("failed_step")
                        result["error"] = step_result.get("error")
                        return result
                if result["workload_results"] and not any(
                    step.get("type") == "batch" for step in result["workload_results"]
                ):
                    last_step = result["workload_results"][-1]
                    result["pipeline_verdict"] = last_step.get("verdict")
                result["board_passed"] = True
                result["status"] = "passed"
            except subprocess.CalledProcessError as exc:
                result["status"] = "failed"
                result["failed_step"] = result["failed_step"] or "command"
                result["error"] = "command failed with exit code %s: %s" % (exc.returncode, exc.cmd)
            except Exception as exc:  # pragma: no cover - defensive guard for board orchestration
                result["status"] = "failed"
                result["failed_step"] = result["failed_step"] or "unexpected"
                result["error"] = str(exc)

        return result


def _render_markdown_summary(output_dir, config_path, results):
    total = len(results)
    passed = len([item for item in results if item.get("board_passed")])
    lines = [
        "# Board Sweep Summary",
        "",
        "- config: `%s`" % config_path,
        "- output_dir: `%s`" % output_dir,
        "- runs_total: `%d`" % total,
        "- runs_passed: `%d`" % passed,
        "- runs_failed: `%d`" % (total - passed),
        "",
        "| Run | Workloads | Batch | Window | Mode | Status | Verdict | Sender | Receiver | Engine | Missing IDs |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in results:
        lines.append(
            "| {run_name} | {workloads} | {batch_size} | {batch_time_window_seconds} | {capture_mode} | {status} | {pipeline_verdict} | {sender_capture_count} | {receiver_capture_count} | {engine_emit_count} | {missing_ids} |".format(
                run_name=item["run_name"],
                workloads=item.get("workload_summary", "-"),
                batch_size=_display_batch_size(item),
                batch_time_window_seconds=_display_batch_window(item),
                capture_mode=item.get("receiver_capture_mode_used") or "single_packet",
                status=item["status"],
                pipeline_verdict=item.get("pipeline_verdict") or "-",
                sender_capture_count=item.get("sender_capture_count", "-"),
                receiver_capture_count=item.get("receiver_capture_count", "-"),
                engine_emit_count=item.get("engine_emit_count", "-"),
                missing_ids=",".join(item.get("missing_request_ids", [])) or "-",
            )
        )
    failed_items = [item for item in results if not item.get("board_passed")]
    if failed_items:
        lines.extend(["", "## Failure Notes", ""])
        for item in failed_items:
            lines.append(
                "- {run_name}: status=`{status}`, failed_step=`{failed_step}`, capture_issue=`{capture_issue}`, "
                "primary=`{primary_status}`, fallback=`{fallback_status}`, receiver_mode=`{receiver_mode}`, "
                "receiver_remote=`{receiver_remote}`, receiver_local=`{receiver_local}`, engine_emit=`{engine_emit}`".format(
                    run_name=item["run_name"],
                    status=item.get("status", "-"),
                    failed_step=item.get("failed_step") or "-",
                    capture_issue=item.get("capture_issue") or "-",
                    primary_status=item.get("receiver_capture_primary_status") or "-",
                    fallback_status=item.get("receiver_capture_fallback_status") or "-",
                    receiver_mode=item.get("receiver_capture_mode_used") or "-",
                    receiver_remote="yes" if item.get("receiver_capture_remote_exists") else "no",
                    receiver_local="yes" if item.get("receiver_capture_local_exists") else "no",
                    engine_emit=item.get("engine_emit_count", "-"),
                )
            )
    return "\n".join(lines) + "\n"


def build_parser():
    parser = argparse.ArgumentParser(description="Run formal USC NetFPGA board sweeps from a single local entry point.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--password-file")
    parser.add_argument("--ssh-mode", choices=["sshpass", "system"])
    parser.add_argument("--out-dir")
    parser.add_argument("--force", action="store_true", default=False)
    return parser


def main():
    args = build_parser().parse_args()
    config_path = Path(args.config).resolve()
    config = _load_config(config_path)
    if args.password_file is not None:
        config["password_file"] = args.password_file
    if args.ssh_mode is not None:
        config["ssh_mode"] = args.ssh_mode
    defaults, experiments = _expand_experiments(config, config_path.parent)

    _ensure_local_dependency("ssh")
    _ensure_local_dependency("scp")
    password = None
    if defaults["ssh_mode"] == "sshpass":
        _ensure_local_dependency("sshpass")
        password = _resolve_password(defaults["ssh_mode"], defaults.get("password_file"))

    output_dir = Path(args.out_dir).resolve() if args.out_dir else _default_output_dir()
    if output_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % output_dir)
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    runner = SweepRunner(output_dir=output_dir, config_path=config_path, defaults=defaults, password=password)
    results = []
    for index, experiment in enumerate(experiments):
        result = runner.execute_experiment(experiment)
        results.append(result)
        if result["status"] == "failed" and not defaults["continue_on_error"]:
            break
        if index != len(experiments) - 1:
            pause_seconds = float(experiment.get("inter_run_pause_seconds", 0.0))
            if pause_seconds > 0:
                time.sleep(pause_seconds)

    summary = {
        "schema_version": 1,
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
