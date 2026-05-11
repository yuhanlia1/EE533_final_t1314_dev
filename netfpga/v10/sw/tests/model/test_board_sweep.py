from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_BOARD_SWEEP_SPEC = importlib.util.spec_from_file_location(
    "board_sweep_module",
    ROOT_DIR / "scripts" / "board" / "board_sweep.py",
)
board_sweep = importlib.util.module_from_spec(_BOARD_SWEEP_SPEC)
assert _BOARD_SWEEP_SPEC.loader is not None
_BOARD_SWEEP_SPEC.loader.exec_module(board_sweep)

from board_debug.ann_packets import build_task_frame_defaults
from board_debug.pcap_io import write_pcap


class BoardSweepTests(unittest.TestCase):
    def _runner_defaults(self) -> dict:
        return board_sweep._normalize_defaults({}, ROOT_DIR)

    def _single_bypass_manifest(self) -> dict:
        return {
            "model": {"result_mode": "compact_class_score"},
            "network": {"dst_udp_port": "0x88b5"},
            "smoke": {
                "wrong_magic_request_id": "0x1200",
                "wrong_port_request_id": "0x1201",
            },
        }

    def test_load_password_file_parses_single_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "ssh_passkey.txt"
            path.write_text("secret123\n", encoding="utf-8")

            self.assertEqual(board_sweep._load_password_file(path), "secret123")

    def test_load_password_file_rejects_multiple_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "ssh_passkey.txt"
            path.write_text("secret123\nextra\n", encoding="utf-8")

            with self.assertRaises(SystemExit):
                board_sweep._load_password_file(path)

    def test_load_password_file_rejects_legacy_labeled_format(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "ssh_passkey.txt"
            path.write_text("Password: secret123\n", encoding="utf-8")

            with self.assertRaises(SystemExit):
                board_sweep._load_password_file(path)

    def test_resolve_password_uses_prompt_when_file_is_missing(self) -> None:
        class _InteractiveStdin:
            @staticmethod
            def isatty() -> bool:
                return True

        prompted = []

        def _prompt(prompt_text: str) -> str:
            prompted.append(prompt_text)
            return "secret123"

        password = board_sweep._resolve_password(
            "sshpass",
            password_file=None,
            prompt_func=_prompt,
            stdin=_InteractiveStdin(),
        )

        self.assertEqual(password, "secret123")
        self.assertEqual(prompted, ["USC password: "])

    def test_resolve_password_requires_interactive_terminal_without_file(self) -> None:
        class _NonInteractiveStdin:
            @staticmethod
            def isatty() -> bool:
                return False

        with self.assertRaises(SystemExit):
            board_sweep._resolve_password(
                "sshpass",
                password_file=None,
                prompt_func=lambda _prompt: "secret123",
                stdin=_NonInteractiveStdin(),
            )

    def test_remote_transport_builds_sshpass_ssh_and_scp_commands(self) -> None:
        transport = board_sweep.RemoteTransport("sshpass", "secret123")

        ssh_command = transport.ssh_command("netfpga@nf3.usc.edu", tty=True)
        scp_command = transport.scp_command(recursive=True)

        self.assertEqual(ssh_command[:4], ["sshpass", "-p", "secret123", "ssh"])
        self.assertIn("-tt", ssh_command)
        self.assertIn("StrictHostKeyChecking=no", ssh_command)
        self.assertIn("KexAlgorithms=+diffie-hellman-group14-sha1", ssh_command)
        self.assertEqual(scp_command[:4], ["sshpass", "-p", "secret123", "scp"])
        self.assertIn("-r", scp_command)

    def test_expand_experiments_resolves_relative_paths_and_repeats(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            config_dir = Path(tmpdir)
            (config_dir / "ssh_passkey.txt").write_text("secret123\n", encoding="utf-8")
            config = {
                "model": "models/demo.json",
                "reg_defines": "config/reg_defines_v8.h",
                "password_file": "ssh_passkey.txt",
                "experiments": [
                    {
                        "name": "Batch 4",
                        "batch_size": 4,
                        "batch_time_window_seconds": 2.5,
                        "request_id_base": "0x2200",
                        "replay_repeat": 2,
                    }
                ],
            }

            defaults, experiments = board_sweep._expand_experiments(config, config_dir)

            self.assertEqual(defaults["model"], str((config_dir / "models" / "demo.json").resolve()))
            self.assertEqual(defaults["reg_defines"], str((config_dir / "config" / "reg_defines_v8.h").resolve()))
            self.assertEqual(defaults["password_file"], str((config_dir / "ssh_passkey.txt").resolve()))
            self.assertEqual([item["run_name"] for item in experiments], ["batch_4_r01", "batch_4_r02"])
            self.assertEqual(experiments[0]["batch_time_window_seconds"], 2.5)
            self.assertEqual(experiments[0]["batch_pre_replay_delay_seconds"], board_sweep.DEFAULT_PRE_CAPTURE_DELAY_SECONDS)
            self.assertEqual(experiments[1]["repeat_index"], 2)
            self.assertEqual(
                experiments[0]["workloads"],
                [
                    {"type": "single_packet", "variant": "wrong_magic"},
                    {"type": "single_packet", "variant": "wrong_port"},
                    {
                        "type": "batch",
                        "batch_size": 4,
                        "request_id_base": "0x2200",
                        "batch_time_window_seconds": 2.5,
                        "batch_pre_replay_delay_seconds": board_sweep.DEFAULT_PRE_CAPTURE_DELAY_SECONDS,
                        "batch_include_smoke_steps": True,
                    },
                ],
            )

    def test_expand_experiments_keeps_batch_pre_replay_delay_seconds(self) -> None:
        defaults, experiments = board_sweep._expand_experiments(
            {
                "experiments": [
                    {
                        "name": "batch5_delay",
                        "batch_size": 5,
                        "batch_pre_replay_delay_seconds": 1.0,
                    }
                ]
            },
            ROOT_DIR,
        )

        self.assertEqual(defaults["pre_capture_delay_seconds"], board_sweep.DEFAULT_PRE_CAPTURE_DELAY_SECONDS)
        self.assertEqual(experiments[0]["batch_pre_replay_delay_seconds"], 1.0)

    def test_expand_experiments_supports_single_packet_only_workloads(self) -> None:
        _defaults, experiments = board_sweep._expand_experiments(
            {
                "experiments": [
                    {
                        "name": "single_only",
                        "workloads": [
                            {"type": "single_packet", "variant": "offload"},
                            {"type": "single_packet", "variant": "wrong_magic"},
                        ],
                    }
                ]
            },
            ROOT_DIR,
        )

        self.assertEqual(experiments[0]["prepare_limit"], 1)
        self.assertIsNone(experiments[0]["batch_size"])
        self.assertEqual(experiments[0]["workload_summary"], "offload,wrong_magic")
        self.assertEqual(
            experiments[0]["workloads"],
            [
                {"type": "single_packet", "variant": "offload"},
                {"type": "single_packet", "variant": "wrong_magic"},
            ],
        )

    def test_expand_experiments_supports_batch_only_workloads(self) -> None:
        _defaults, experiments = board_sweep._expand_experiments(
            {
                "experiments": [
                    {
                        "name": "batch_only",
                        "workloads": [
                            {
                                "type": "batch",
                                "batch_size": 6,
                                "request_id_base": "0x1434",
                                "batch_time_window_seconds": 2.5,
                                "batch_pre_replay_delay_seconds": 0.75,
                            }
                        ],
                    }
                ]
            },
            ROOT_DIR,
        )

        self.assertEqual(experiments[0]["prepare_limit"], 6)
        self.assertEqual(experiments[0]["batch_size"], 6)
        self.assertEqual(experiments[0]["workload_summary"], "batch6")
        self.assertEqual(
            experiments[0]["workloads"],
            [
                {
                    "type": "batch",
                    "batch_size": 6,
                    "request_id_base": "0x1434",
                    "batch_time_window_seconds": 2.5,
                    "batch_pre_replay_delay_seconds": 0.75,
                    "batch_include_smoke_steps": True,
                }
            ],
        )

    def test_expand_experiments_supports_batch_only_workloads_without_smoke_steps(self) -> None:
        _defaults, experiments = board_sweep._expand_experiments(
            {
                "experiments": [
                    {
                        "name": "batch_only_pure",
                        "workloads": [
                            {
                                "type": "batch",
                                "batch_size": 8,
                                "request_id_base": "0x3100",
                                "batch_time_window_seconds": 3.0,
                                "batch_pre_replay_delay_seconds": 0.5,
                                "batch_include_smoke_steps": False,
                            }
                        ],
                    }
                ]
            },
            ROOT_DIR,
        )

        self.assertEqual(experiments[0]["prepare_limit"], 8)
        self.assertFalse(experiments[0]["batch_include_smoke_steps"])
        self.assertEqual(
            experiments[0]["workloads"][0]["batch_include_smoke_steps"],
            False,
        )

    def test_build_prepare_command_includes_boardctl_arguments(self) -> None:
        defaults = {
            "model": str(ROOT_DIR / "dataset" / "export" / "rsu_ann_model_int16.json"),
            "bitfile": "demo.bit",
            "netfpga_host": "nf3",
            "sender_host": "nf4",
            "receiver_host": "nf1",
            "sender_iface": "port0",
            "receiver_iface": "port2",
            "dst_mac": "00:11:22:33:44:55",
        }
        experiment = {
            "run_name": "batch4_r01",
            "prepare_limit": 4,
            "sample_pool_mode": "repeat",
            "prepare_request_id_base": "0x1234",
            "prepare_batch_time_window_seconds": 2.0,
        }

        command = board_sweep._build_prepare_command(Path("/tmp/demo_run"), defaults, experiment)

        rendered = " ".join(command)
        self.assertIn("boardctl.py prepare", rendered)
        self.assertIn("--limit 4", rendered)
        self.assertIn("--sample-pool-mode repeat", rendered)
        self.assertIn("--bitfile demo.bit", rendered)
        self.assertIn("--request-id-base 0x1234", rendered)
        self.assertIn("--batch-time-window-seconds 2.0", rendered)
        self.assertIn("--dst-mac 00:11:22:33:44:55", rendered)

    def test_single_packet_bypass_verdict_accepts_wrong_magic_udp_unknown(self) -> None:
        runner = board_sweep.SweepRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        manifest = self._single_bypass_manifest()
        frame, _meta = build_task_frame_defaults(
            task_magic=board_sweep.DEFAULT_WRONG_MAGIC,
            request_id=0x1200,
            udp_dst_port=int(manifest["network"]["dst_udp_port"], 0),
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            capture_path = Path(tmpdir) / "wrong_magic.cap"
            write_pcap(capture_path, [frame])

            verdict = runner._single_packet_bypass_verdict(
                manifest,
                {"path": capture_path},
                "wrong_magic",
            )

        self.assertEqual(verdict["verdict"], "bypass_ok")
        self.assertEqual(verdict["frame_kind"], "udp_unknown")
        self.assertEqual(verdict["payload_magic"], "0xbeef")
        self.assertEqual(verdict["udp_dst_port"], "0x88b5")
        self.assertEqual(verdict["request_id"], "0x1200")

    def test_single_packet_bypass_verdict_accepts_wrong_port_ann_task(self) -> None:
        runner = board_sweep.SweepRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        manifest = self._single_bypass_manifest()
        frame, _meta = build_task_frame_defaults(
            task_magic=board_sweep.ANN_TASK_MAGIC,
            request_id=0x1201,
            udp_dst_port=board_sweep.DEFAULT_WRONG_PORT,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            capture_path = Path(tmpdir) / "wrong_port.cap"
            write_pcap(capture_path, [frame])

            verdict = runner._single_packet_bypass_verdict(
                manifest,
                {"path": capture_path},
                "wrong_port",
            )

        self.assertEqual(verdict["verdict"], "bypass_ok")
        self.assertEqual(verdict["frame_kind"], "ann_task")
        self.assertEqual(verdict["payload_magic"], "0xa11e")
        self.assertEqual(verdict["udp_dst_port"], "0x9999")
        self.assertEqual(verdict["request_id"], "0x1201")

    def test_single_packet_bypass_verdict_rejects_wrong_magic_request_id_mismatch(self) -> None:
        runner = board_sweep.SweepRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        manifest = self._single_bypass_manifest()
        frame, _meta = build_task_frame_defaults(
            task_magic=board_sweep.DEFAULT_WRONG_MAGIC,
            request_id=0x1299,
            udp_dst_port=int(manifest["network"]["dst_udp_port"], 0),
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            capture_path = Path(tmpdir) / "wrong_magic_bad.cap"
            write_pcap(capture_path, [frame])

            verdict = runner._single_packet_bypass_verdict(
                manifest,
                {"path": capture_path},
                "wrong_magic",
            )

        self.assertEqual(verdict["verdict"], "bypass_mismatch")

    def test_markdown_summary_reports_verdicts_and_missing_ids(self) -> None:
        results = [
            {
                "run_name": "batch4_r01",
                "batch_size": 4,
                "batch_time_window_seconds": 2.0,
                "workload_summary": "wrong_magic,wrong_port,batch4",
                "receiver_capture_mode_used": "count",
                "status": "passed",
                "pipeline_verdict": "healthy",
                "sender_capture_count": 4,
                "receiver_capture_count": 4,
                "engine_emit_count": 4,
                "missing_request_ids": [],
            },
            {
                "run_name": "batch5_r01",
                "batch_size": 5,
                "batch_time_window_seconds": 2.5,
                "workload_summary": "batch5",
                "receiver_capture_mode_used": "time_window",
                "status": "report_failed",
                "pipeline_verdict": "capture_side_miss",
                "sender_capture_count": 5,
                "receiver_capture_count": 4,
                "engine_emit_count": 5,
                "missing_request_ids": ["0x1234"],
                "receiver_capture_primary_status": "missing",
                "receiver_capture_fallback_status": "partial",
            },
        ]

        rendered = board_sweep._render_markdown_summary(Path("/tmp/out"), Path("/tmp/config.json"), results)

        self.assertIn("runs_total: `2`", rendered)
        self.assertIn("runs_passed: `0`", rendered)
        self.assertIn("| batch5_r01 | batch5 | 5 | 2.5 | time_window | report_failed | capture_side_miss | 5 | 4 | 5 | 0x1234 |", rendered)
        self.assertIn("## Failure Notes", rendered)
        self.assertIn("capture_issue=`-`", rendered)
        self.assertIn("primary=`missing`", rendered)
        self.assertIn("fallback=`partial`", rendered)

    def test_classify_receiver_batch_artifact_distinguishes_fetch_and_capture_issues(self) -> None:
        self.assertIsNone(
            board_sweep._classify_receiver_batch_artifact({"exists": True}, {"exists": True})
        )
        self.assertEqual(
            board_sweep._classify_receiver_batch_artifact({"exists": True}, {"exists": False}),
            "fetch_side_issue",
        )
        self.assertEqual(
            board_sweep._classify_receiver_batch_artifact({"exists": False}, {"exists": False}),
            "receiver_capture_issue",
        )

    def test_attempt_artifact_status_distinguishes_complete_partial_missing(self) -> None:
        complete = {
            "remote": {"receiver": {"exists": True}, "sender": {"exists": True}},
            "local": {
                "receiver": {"exists": True, "packet_count": 5},
                "sender": {"exists": True, "packet_count": 5},
            },
        }
        partial = {
            "remote": {"receiver": {"exists": True}, "sender": {"exists": True}},
            "local": {
                "receiver": {"exists": True, "packet_count": 3},
                "sender": {"exists": True, "packet_count": 5},
            },
        }
        missing = {
            "remote": {"receiver": {"exists": False}, "sender": {"exists": False}},
            "local": {
                "receiver": {"exists": False, "packet_count": None},
                "sender": {"exists": False, "packet_count": None},
            },
        }

        self.assertEqual(board_sweep._attempt_artifact_status(complete, 5), "complete")
        self.assertEqual(board_sweep._attempt_artifact_status(partial, 5), "partial")
        self.assertEqual(board_sweep._attempt_artifact_status(missing, 5), "missing")

    def test_run_capture_sequence_skips_smoke_when_disabled(self) -> None:
        class _FinishedCapture:
            def wait(self, timeout=None):
                return 0

        class _CaptureSequenceRunner(board_sweep.SweepRunner):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.started = []
                self.ran = []
                self.attempts = []

            def _start_remote_script(self, handle, host, script_path, tty=False):
                self.started.append(Path(script_path).name)
                return _FinishedCapture()

            def _run_remote_script(self, handle, host, script_path, tty=False):
                self.ran.append(Path(script_path).name)
                return None

            def _run_batch_capture_attempt(self, run_dir, manifest, handle, attempt_name):
                self.attempts.append(attempt_name)
                return {"status": "complete"}

            def _collect_artifact_diagnostics(self, run_dir, manifest, handle, attempts):
                return {"attempts": attempts, "required_artifacts_ready": False}

        runner = _CaptureSequenceRunner(
            output_dir=Path("/tmp/out"),
            config_path=Path("/tmp/config.json"),
            defaults=self._runner_defaults(),
        )
        manifest = {
            "usc": {
                "sender_host": "node3@nf4.usc.edu",
                "receiver_host": "node3@nf1.usc.edu",
                "netfpga_host": "netfpga@nf3.usc.edu",
            }
        }

        runner._run_capture_sequence(Path("/tmp/demo_run"), manifest, handle=None, include_smoke_steps=False)

        self.assertEqual(runner.started, [])
        self.assertEqual(runner.attempts, ["primary"])
        self.assertEqual(runner.ran, ["nf3_debug_snapshot.sh"])


if __name__ == "__main__":
    unittest.main()
