#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import board_metrics
import board_sweep


DEFAULT_CONFIG = ROOT_DIR / "scripts" / "board" / "rsu_demo_other_pros_rate.json"
DEFAULT_REQUEST_ID_BASE_START = "0x3000"
DEFAULT_RATE_POINTS = [10, 25, 50, 100, 200, 400, 800, 1200, 1600, 2000, 2400]
DEFAULT_SEND_DURATION_SECONDS = 2.0
DEFAULT_DRAIN_TIMEOUT_SECONDS = 1.0
DEFAULT_RATE_ACCURACY_TOLERANCE_RATIO = 0.20
DEFAULT_RATE_CHUNK_TARGET_SECONDS = 0.25
DEFAULT_TERM_WIDTH = 100
TERM_WIDTH_CAP = 100
RATE_STATE_JSON = "other_pros_rate_state.json"
RATE_SUMMARY_JSON = "other_pros_rate_summary.json"
RATE_SUMMARY_MD = "other_pros_rate_summary.md"
RECOMMENDED_FIGURE = ROOT_DIR / "bt" / "system_report" / "figures" / "rate_scan_energy_validity.png"
FALLBACK_SUMMARY_JSON = ROOT_DIR / "bt" / "system_report" / "summary.json"


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def _write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _term_width():
    return min(shutil.get_terminal_size((DEFAULT_TERM_WIDTH, 20)).columns, TERM_WIDTH_CAP)


def _print_separator(char="=", width=None):
    width = width or _term_width()
    print(char * width)


def _print_kv(key, value, indent=0, key_width=22):
    prefix = " " * int(indent)
    print("%s%-*s : %s" % (prefix, int(key_width), str(key), str(value)))


def _status_word(passed):
    return "PASS" if passed else "FAIL"


def _normalize_rates(raw_rates):
    if not isinstance(raw_rates, list) or not raw_rates:
        raise SystemExit("rate list must be a non-empty JSON list")
    values = []
    for raw in raw_rates:
        value = int(raw)
        if value <= 0:
            raise SystemExit("rate values must be > 0")
        values.append(value)
    return sorted(set(values))


def _parse_rates_arg(text):
    parts = [item.strip() for item in str(text).split(",") if item.strip()]
    if not parts:
        raise SystemExit("--rates must contain at least one integer value")
    return _normalize_rates([int(item) for item in parts])


def _load_rate_defaults(config_path: Path):
    config = _load_json(config_path)
    if not isinstance(config, dict):
        raise SystemExit("other pros rate config must be a JSON object")
    defaults = board_sweep._normalize_defaults(config, config_path.parent)
    configured_rates = config.get("default_rate_points_req_per_sec")
    if configured_rates is None:
        experiments = config.get("experiments") or []
        if experiments and isinstance(experiments[0], dict):
            configured_rates = experiments[0].get("rate_points_req_per_sec")
    return {
        "config_path": str(config_path),
        "runner_defaults": defaults,
        "request_id_base_start": str(config.get("request_id_base_start", DEFAULT_REQUEST_ID_BASE_START)),
        "default_rate_points_req_per_sec": _normalize_rates(
            configured_rates if configured_rates is not None else DEFAULT_RATE_POINTS
        ),
        "default_send_duration_seconds": float(
            config.get("default_send_duration_seconds", DEFAULT_SEND_DURATION_SECONDS)
        ),
        "default_drain_timeout_seconds": float(
            config.get("default_drain_timeout_seconds", DEFAULT_DRAIN_TIMEOUT_SECONDS)
        ),
        "default_rate_accuracy_tolerance_ratio": float(
            config.get("default_rate_accuracy_tolerance_ratio", DEFAULT_RATE_ACCURACY_TOLERANCE_RATIO)
        ),
        "default_rate_chunk_target_seconds": float(
            config.get("default_rate_chunk_target_seconds", DEFAULT_RATE_CHUNK_TARGET_SECONDS)
        ),
    }


def _resolve_password(defaults, password_file):
    defaults = dict(defaults)
    defaults["password_file"] = password_file if password_file is not None else defaults.get("password_file")
    board_sweep._ensure_local_dependency("ssh")
    board_sweep._ensure_local_dependency("scp")
    if defaults["ssh_mode"] == "sshpass":
        board_sweep._ensure_local_dependency("sshpass")
    return board_sweep._resolve_password(defaults["ssh_mode"], defaults.get("password_file"))


def _state_path(run_dir: Path) -> Path:
    return run_dir / RATE_STATE_JSON


def _summary_json_path(run_dir: Path) -> Path:
    return run_dir / RATE_SUMMARY_JSON


def _summary_md_path(run_dir: Path) -> Path:
    return run_dir / RATE_SUMMARY_MD


def _load_state(run_dir: Path):
    state_path = _state_path(run_dir)
    if not state_path.exists():
        raise SystemExit("%s is missing; run other-pros-rate-init first" % state_path)
    return _load_json(state_path)


def _initial_prepare_experiment(run_name: str, request_id_base_start: str, send_duration_seconds: float):
    prepare_window_seconds = max(float(send_duration_seconds), DEFAULT_DRAIN_TIMEOUT_SECONDS)
    return {
        "run_name": run_name,
        "prepare_limit": 1,
        "sample_pool_mode": "truncate",
        "prepare_request_id_base": str(request_id_base_start),
        "prepare_batch_time_window_seconds": float(prepare_window_seconds),
        "mode": "latency_single",
    }


def _rate_experiment(rate_pps: int, defaults: dict, rate_index: int):
    expected_count = max(1, int(round(float(rate_pps) * float(defaults["send_duration_seconds"]))))
    request_id_base = "0x%04x" % ((int(str(defaults["request_id_base_start"]), 0) + (rate_index * 0x0100)) & 0xFFFF)
    return {
        "name": "other_pros_rate_live",
        "mode": "rate_scan",
        "run_name": "other_pros_rate_%spps_r01" % int(rate_pps),
        "repeat_index": 1,
        "offered_rate_req_per_sec": float(rate_pps),
        "send_duration_seconds": float(defaults["send_duration_seconds"]),
        "drain_timeout_seconds": float(defaults["drain_timeout_seconds"]),
        "expected_count": expected_count,
        "prepare_limit": expected_count,
        "sample_pool_mode": "repeat",
        "prepare_request_id_base": request_id_base,
        "prepare_batch_time_window_seconds": float(defaults["drain_timeout_seconds"]),
        "request_id_base": request_id_base,
        "rate_generation_mode": board_metrics.RATE_GENERATION_MODE_AUTO,
        "rate_accuracy_tolerance_ratio": float(defaults["rate_accuracy_tolerance_ratio"]),
        "rate_chunk_target_seconds": float(defaults["rate_chunk_target_seconds"]),
    }


def _is_zero_loss(result: dict) -> bool:
    return (
        bool(result.get("measurement_valid"))
        and int(result.get("drop_count", 0) or 0) == 0
        and int(result.get("mismatch_count", 0) or 0) == 0
    )


def _analyze_rate_results(rate_results):
    ordered = sorted(rate_results, key=lambda row: float(row.get("offered_rate_req_per_sec") or 0.0))
    passing = [item for item in ordered if _is_zero_loss(item)]
    max_zero_loss_pps = passing[-1]["offered_rate_req_per_sec"] if passing else None
    first_overload_pps = None
    for item in ordered:
        if not _is_zero_loss(item):
            first_overload_pps = item.get("offered_rate_req_per_sec")
            break
    return {
        "max_zero_loss_pps": max_zero_loss_pps,
        "first_overload_pps": first_overload_pps,
        "threshold_complete": first_overload_pps is not None,
        "overall_verdict": "pass" if passing else "fail",
    }


def _rate_row(result):
    return {
        "run_name": result.get("run_name"),
        "run_dir": result.get("run_dir"),
        "runner_log": result.get("runner_log"),
        "offered_rate_req_per_sec": result.get("offered_rate_req_per_sec"),
        "actual_send_rate_req_per_sec": result.get("actual_send_rate_req_per_sec"),
        "goodput_result_per_sec": result.get("goodput_result_per_sec"),
        "measurement_valid": bool(result.get("measurement_valid")),
        "drop_count": int(result.get("drop_count", 0) or 0),
        "drop_ratio": result.get("drop_ratio"),
        "mismatch_count": int(result.get("mismatch_count", 0) or 0),
        "rate_error_ratio": result.get("rate_error_ratio"),
        "pipeline_verdict": result.get("pipeline_verdict"),
        "rate_generation_mode_used": result.get("rate_generation_mode_used"),
        "sender_capture_count": result.get("sender_capture_count"),
        "receiver_capture_count": result.get("receiver_capture_count"),
        "engine_emit_count": result.get("engine_emit_count"),
        "zero_loss_pass": _is_zero_loss(result),
        "status": result.get("status"),
    }


def _base_summary(run_dir: Path, state: dict):
    return {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "run_dir": str(run_dir),
        "config_path": state.get("config_path"),
        "init_run_dir": state.get("init_run_dir"),
        "rate_points_req_per_sec": list(state.get("default_rate_points_req_per_sec", [])),
        "send_duration_seconds": state.get("default_send_duration_seconds"),
        "drain_timeout_seconds": state.get("default_drain_timeout_seconds"),
        "rate_accuracy_tolerance_ratio": state.get("default_rate_accuracy_tolerance_ratio"),
        "rate_chunk_target_seconds": state.get("default_rate_chunk_target_seconds"),
        "result_count": 0,
        "max_zero_loss_pps": None,
        "first_overload_pps": None,
        "threshold_complete": False,
        "overall_verdict": "pending",
        "recommended_figure": str(RECOMMENDED_FIGURE.resolve()),
        "fallback_summary_json": str(FALLBACK_SUMMARY_JSON.resolve()),
        "rate_results": [],
    }


def _render_summary_markdown(summary: dict) -> str:
    lines = [
        "# Other Pros Rate-Scan Summary",
        "",
        "- run_dir: `%s`" % summary.get("run_dir"),
        "- config_path: `%s`" % summary.get("config_path"),
        "- init_run_dir: `%s`" % summary.get("init_run_dir"),
        "- rate_points_req_per_sec: `%s`" % summary.get("rate_points_req_per_sec"),
        "- send_duration_seconds: `%s`" % summary.get("send_duration_seconds"),
        "- drain_timeout_seconds: `%s`" % summary.get("drain_timeout_seconds"),
        "- max_zero_loss_pps: `%s`" % summary.get("max_zero_loss_pps"),
        "- first_overload_pps: `%s`" % summary.get("first_overload_pps"),
        "- threshold_complete: `%s`" % summary.get("threshold_complete"),
        "- overall_verdict: `%s`" % str(summary.get("overall_verdict", "pending")).upper(),
        "- recommended_figure: `%s`" % summary.get("recommended_figure"),
        "",
        "| Rate (pps) | Verdict | Valid | Drops | Mismatch | Goodput | RateCtrl |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in summary.get("rate_results", []):
        lines.append(
            "| {rate} | {verdict} | {valid} | {drops} | {mismatch} | {goodput} | {rate_ctrl} |".format(
                rate=item.get("offered_rate_req_per_sec"),
                verdict="PASS" if item.get("zero_loss_pass") else "FAIL",
                valid="yes" if item.get("measurement_valid") else "no",
                drops=item.get("drop_count"),
                mismatch=item.get("mismatch_count"),
                goodput=(
                    "%0.3f" % float(item["goodput_result_per_sec"])
                    if item.get("goodput_result_per_sec") is not None
                    else "-"
                ),
                rate_ctrl=item.get("rate_generation_mode_used") or "-",
            )
        )
    return "\n".join(lines) + "\n"


def _write_summary(run_dir: Path, summary: dict):
    _write_json(_summary_json_path(run_dir), summary)
    _write_text(_summary_md_path(run_dir), _render_summary_markdown(summary))


def _print_scan_header(run_dir: Path, rates):
    width = _term_width()
    _print_separator("=", width=width)
    print("RSU Other Pros Demo")
    _print_separator("=", width=width)
    _print_kv("Focus", "High-Flow Stability", key_width=18)
    _print_kv("Method", "Rate Scan", key_width=18)
    _print_kv("Run Dir", run_dir, key_width=18)
    _print_kv("Rates", ",".join(str(rate) for rate in rates), key_width=18)
    _print_separator("-", width=width)


def _print_rate_result_line(result):
    verdict = _status_word(_is_zero_loss(result))
    message = "%s pps : %s | valid=%s drop=%s mismatch=%s" % (
        int(float(result["offered_rate_req_per_sec"])),
        verdict,
        "yes" if result.get("measurement_valid") else "no",
        int(result.get("drop_count", 0) or 0),
        int(result.get("mismatch_count", 0) or 0),
    )
    if result.get("actual_send_rate_req_per_sec") is not None:
        message += " | actual_send=%0.2f" % float(result["actual_send_rate_req_per_sec"])
    print("  " + message)


def _print_scan_footer(summary: dict):
    width = _term_width()
    _print_separator("-", width=width)
    _print_kv("Max Zero-Loss Rate", "%s pps" % summary.get("max_zero_loss_pps"), key_width=22)
    _print_kv("First Overload Rate", "%s pps" % summary.get("first_overload_pps"), key_width=22)
    _print_kv("Threshold Complete", summary.get("threshold_complete"), key_width=22)
    _print_kv("Recommended Figure", summary.get("recommended_figure"), key_width=22)
    _print_kv("Result", str(summary.get("overall_verdict", "fail")).upper(), key_width=22)
    _print_kv("Step Summary", _summary_md_path(Path(summary["run_dir"])).name, key_width=22)
    _print_separator("=", width=width)


class OtherProsRateRunner(board_metrics.MetricsRunner):
    def _prepare_rate_run(self, handle, experiment, run_bringup):
        run_dir = self.output_dir / experiment["run_name"]
        prepare_command = board_sweep._build_prepare_command(run_dir, self.defaults, experiment)
        self._run_local(handle, prepare_command)
        self._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "bringup", str(run_dir / "manifest.json")])
        self._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "capture", str(run_dir / "manifest.json")])
        manifest = board_metrics._load_json(run_dir / "manifest.json")
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
            "rate_generation_mode": experiment.get("rate_generation_mode", board_metrics.RATE_GENERATION_MODE_AUTO),
            "rate_accuracy_tolerance_ratio": experiment.get("rate_accuracy_tolerance_ratio"),
            "rate_chunk_target_seconds": experiment.get("rate_chunk_target_seconds"),
        }
        manifest["metrics"].update(rate_replay_pcaps)
        manifest["sweep"] = {
            "batch_pre_replay_delay_seconds": experiment.get(
                "batch_pre_replay_delay_seconds",
                self.defaults["pre_capture_delay_seconds"],
            ),
            "capture_ready_delay_seconds": self.defaults["capture_ready_delay_seconds"],
            "receiver_capture_mode": self.defaults["receiver_capture_mode"],
            "receiver_capture_primary_mode": self.defaults["receiver_capture_primary_mode"],
            "receiver_capture_fallback_mode": self.defaults["receiver_capture_fallback_mode"],
            "receiver_capture_completion_timeout_seconds": experiment.get("completion_timeout_seconds"),
        }
        board_metrics._write_json(run_dir / "manifest.json", manifest)
        self._stage_artifacts(run_dir, manifest, handle)
        if run_bringup:
            self._run_remote_script(
                handle,
                manifest["usc"]["netfpga_host"],
                run_dir / "commands" / "nf3_bringup.sh",
                tty=False,
            )
        return run_dir, manifest

    def execute_live_rate_experiment(self, experiment, run_bringup=False):
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
            run_dir, manifest = self._prepare_rate_run(handle, experiment, run_bringup=run_bringup)
            prepared_count = int(manifest["counts"]["batch_packet_count"])
            result["prepared_count"] = prepared_count
            result["source_test_vector_count"] = int(manifest["counts"].get("source_test_vector_count", prepared_count))
            result["prepared_sample_count"] = int(manifest["counts"].get("prepared_sample_count", prepared_count))
            result["sample_pool_mode"] = manifest["counts"].get("sample_pool_mode", "truncate")
            result["sample_pool_unique_count"] = int(manifest["counts"].get("sample_pool_unique_count", prepared_count))
            result["sample_pool_repeated"] = bool(manifest["counts"].get("sample_pool_repeated", False))
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
            primary_attempt["rate_generation_mode"] = board_metrics.RATE_GENERATION_MODE_PACED
            result["rate_generation_mode_attempted"].append(board_metrics.RATE_GENERATION_MODE_PACED)

            fallback_attempt = None
            if (
                str(experiment.get("rate_generation_mode", board_metrics.RATE_GENERATION_MODE_AUTO))
                == board_metrics.RATE_GENERATION_MODE_AUTO
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
                fallback_attempt["rate_generation_mode"] = board_metrics.RATE_GENERATION_MODE_CHUNKED
                result["rate_generation_mode_attempted"].append(board_metrics.RATE_GENERATION_MODE_CHUNKED)

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
            self._copy_rate_attempt_capture(chosen_sender, board_metrics.RATE_SENDER_CAPTURE_NAME)
            self._copy_rate_attempt_capture(chosen_receiver, board_metrics.RATE_RECEIVER_CAPTURE_NAME)
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


def init_command(args: argparse.Namespace) -> int:
    config_path = Path(args.config).resolve()
    defaults = _load_rate_defaults(config_path)
    runner_defaults = dict(defaults["runner_defaults"])
    password = _resolve_password(runner_defaults, args.password_file)
    run_dir = Path(args.out_dir).resolve()
    if run_dir.exists():
        if not args.force:
            raise SystemExit("%s already exists; use --force to replace it" % run_dir)
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)

    configured_rates = _parse_rates_arg(args.rates) if args.rates else list(defaults["default_rate_points_req_per_sec"])
    send_duration_seconds = (
        float(args.send_duration_seconds)
        if args.send_duration_seconds is not None
        else float(defaults["default_send_duration_seconds"])
    )
    drain_timeout_seconds = (
        float(args.drain_timeout_seconds)
        if args.drain_timeout_seconds is not None
        else float(defaults["default_drain_timeout_seconds"])
    )

    init_experiment = _initial_prepare_experiment(
        "other_pros_rate_init_board",
        defaults["request_id_base_start"],
        send_duration_seconds,
    )
    runner = OtherProsRateRunner(output_dir=run_dir, config_path=config_path, defaults=runner_defaults, password=password)
    log_path = runner.log_dir / (run_dir.name + "_other_pros_rate_init.log")

    with open(log_path, "w", encoding="utf-8") as handle:
        prepare_command = board_sweep._build_prepare_command(run_dir / init_experiment["run_name"], runner_defaults, init_experiment)
        runner._log(handle, "run_dir=%s" % run_dir)
        runner._run_local(handle, prepare_command)
        init_manifest_path = run_dir / init_experiment["run_name"] / "manifest.json"
        runner._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "bringup", str(init_manifest_path)])
        runner._run_local(handle, [sys.executable, str(board_sweep.BOARDCTL_PATH), "capture", str(init_manifest_path)])
        manifest = board_metrics._load_json(init_manifest_path)
        runner._stage_artifacts(run_dir / init_experiment["run_name"], manifest, handle)
        runner._run_remote_script(
            handle,
            manifest["usc"]["netfpga_host"],
            run_dir / init_experiment["run_name"] / "commands" / "nf3_bringup.sh",
            tty=False,
        )

    state = {
        "schema_version": 1,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "run_dir": str(run_dir),
        "config_path": str(config_path),
        "init_run_dir": init_experiment["run_name"],
        "request_id_base_start": defaults["request_id_base_start"],
        "default_rate_points_req_per_sec": configured_rates,
        "default_send_duration_seconds": send_duration_seconds,
        "default_drain_timeout_seconds": drain_timeout_seconds,
        "default_rate_accuracy_tolerance_ratio": float(defaults["default_rate_accuracy_tolerance_ratio"]),
        "default_rate_chunk_target_seconds": float(defaults["default_rate_chunk_target_seconds"]),
    }
    _write_json(_state_path(run_dir), state)
    summary = _base_summary(run_dir, state)
    _write_summary(run_dir, summary)

    print("run_dir=%s" % run_dir)
    print("state_json=%s" % _state_path(run_dir))
    print("summary_json=%s" % _summary_json_path(run_dir))
    print("summary_md=%s" % _summary_md_path(run_dir))
    print("next_step=other-pros-rate-scan")
    return 0


def scan_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state = _load_state(run_dir)
    config_path = Path(state["config_path"]).resolve()
    defaults = _load_rate_defaults(config_path)
    runner_defaults = dict(defaults["runner_defaults"])
    password = _resolve_password(runner_defaults, args.password_file)
    rates = _parse_rates_arg(args.rates) if args.rates else list(state["default_rate_points_req_per_sec"])
    scan_defaults = {
        "request_id_base_start": state["request_id_base_start"],
        "send_duration_seconds": (
            float(args.send_duration_seconds)
            if args.send_duration_seconds is not None
            else float(state["default_send_duration_seconds"])
        ),
        "drain_timeout_seconds": (
            float(args.drain_timeout_seconds)
            if args.drain_timeout_seconds is not None
            else float(state["default_drain_timeout_seconds"])
        ),
        "rate_accuracy_tolerance_ratio": float(state["default_rate_accuracy_tolerance_ratio"]),
        "rate_chunk_target_seconds": float(state["default_rate_chunk_target_seconds"]),
    }
    runner = OtherProsRateRunner(output_dir=run_dir, config_path=config_path, defaults=runner_defaults, password=password)

    for rate_index, rate in enumerate(rates):
        experiment = _rate_experiment(rate, scan_defaults, rate_index)
        step_run_dir = run_dir / experiment["run_name"]
        step_log_path = runner.log_dir / (experiment["run_name"] + ".log")
        if step_run_dir.exists():
            if not args.force:
                raise SystemExit("%s already exists; use --force to rerun rate %s" % (step_run_dir, rate))
            shutil.rmtree(step_run_dir)
        if step_log_path.exists() and args.force:
            step_log_path.unlink()

    _print_scan_header(run_dir, rates)
    rate_results = []
    for rate_index, rate in enumerate(rates):
        experiment = _rate_experiment(rate, scan_defaults, rate_index)
        result = runner.execute_live_rate_experiment(experiment, run_bringup=False)
        rate_results.append(_rate_row(result))
        _print_rate_result_line(result)
    analysis = _analyze_rate_results(rate_results)
    summary = {
        **_base_summary(run_dir, state),
        "updated_at": datetime.now().isoformat(timespec="seconds"),
        "rate_points_req_per_sec": list(rates),
        "send_duration_seconds": scan_defaults["send_duration_seconds"],
        "drain_timeout_seconds": scan_defaults["drain_timeout_seconds"],
        "rate_accuracy_tolerance_ratio": scan_defaults["rate_accuracy_tolerance_ratio"],
        "rate_chunk_target_seconds": scan_defaults["rate_chunk_target_seconds"],
        "result_count": len(rate_results),
        "rate_results": rate_results,
        **analysis,
    }
    _write_summary(run_dir, summary)
    _print_scan_footer(summary)
    return 0 if summary["overall_verdict"] == "pass" else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Live rate-scan wrapper for the Other Pros demo section.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init", help="Prepare one board bring-up and freeze default scan settings.")
    init_parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    init_parser.add_argument("--password-file")
    init_parser.add_argument("--out-dir", required=True)
    init_parser.add_argument("--rates", help="Comma-separated pps list to store as the default live scan ladder.")
    init_parser.add_argument("--send-duration-seconds", type=float)
    init_parser.add_argument("--drain-timeout-seconds", type=float)
    init_parser.add_argument("--force", action="store_true", default=False)
    init_parser.set_defaults(func=init_command)

    scan_parser = subparsers.add_parser("scan", help="Run the live rate-scan ladder using an existing init run_dir.")
    scan_parser.add_argument("--run-dir", required=True)
    scan_parser.add_argument("--password-file")
    scan_parser.add_argument("--rates", help="Comma-separated pps list to override the stored live scan ladder.")
    scan_parser.add_argument("--send-duration-seconds", type=float)
    scan_parser.add_argument("--drain-timeout-seconds", type=float)
    scan_parser.add_argument("--force", action="store_true", default=False)
    scan_parser.set_defaults(func=scan_command)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
