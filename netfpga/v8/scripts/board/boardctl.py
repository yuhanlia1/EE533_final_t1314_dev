#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR / "sw") not in sys.path:
    sys.path.insert(0, str(ROOT_DIR / "sw"))

from board_debug.ann_packets import (  # noqa: E402
    ANN_TASK_MAGIC,
    DEFAULT_TASK_TYPE,
    build_task_frame_defaults,
    inspect_ann_frame,
)
from board_debug.model_batch_eval import (  # noqa: E402
    build_batch_frame_rows,
    compare_expected_observed,
    load_expected_outputs,
    load_test_vectors,
    observed_rows_from_frames,
    with_expected_request_ids,
)
from board_debug.pcap_io import read_pcap, write_pcap  # noqa: E402
from model_toolchain.bundle import build_model  # noqa: E402


DEFAULT_BITFILE = "nw_proc4_1_gpuimem.bit"
DEFAULT_REG_DEFINES = "reg_defines_v8.h"
DEFAULT_REMOTE_VERSION = "v8"
DEFAULT_NETFPGA_HOST = "netfpga@nf3.usc.edu"
DEFAULT_SENDER_HOST = "node3@nf4.usc.edu"
DEFAULT_RECEIVER_HOST = "node3@nf1.usc.edu"
DEFAULT_SENDER_IFACE = "port0"
DEFAULT_RECEIVER_IFACE = "port2"
DEFAULT_DST_MAC = "00:4e:46:32:43:00"
DEFAULT_SRC_MAC = "a0:36:9f:1d:48:c3"
DEFAULT_SRC_IP = "10.0.12.3"
DEFAULT_DST_IP = "10.0.14.3"
DEFAULT_UDP_SRC_PORT = 0x4001
DEFAULT_UDP_DST_PORT = 0x88B5
DEFAULT_REQUEST_ID_BASE = 0x1234
DEFAULT_BATCH_CAPTURE_TIME_WINDOW_SECONDS = 2.0
DEFAULT_TASK_TYPE_HEX = "0x%04x" % DEFAULT_TASK_TYPE
DEFAULT_WRONG_MAGIC = 0xBEEF
DEFAULT_WRONG_PORT = 0x9999
EXPERIMENT_MACS = [
    "00:4e:46:32:43:00",
    "00:4e:46:32:43:01",
    "00:4e:46:32:43:02",
    "00:4e:46:32:43:03",
]


def _default_reg_defines_path():
    candidates = [
        ROOT_DIR / DEFAULT_REG_DEFINES,
        ROOT_DIR / "sw" / DEFAULT_REG_DEFINES,
        ROOT_DIR / "deploy" / "netfpga" / "config" / DEFAULT_REG_DEFINES,
        ROOT_DIR / "deploy" / "buildhost" / "config" / DEFAULT_REG_DEFINES,
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return str(candidates[0])


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


def _relpath(base_dir, path):
    return os.path.relpath(str(path), str(base_dir))


def _run_dir_from_args(args):
    if args.out_dir:
        return Path(args.out_dir).resolve()
    return (ROOT_DIR / "runs" / args.run_name).resolve()


def _make_run_name(model_path):
    stem = Path(model_path).stem
    return datetime.now().strftime("%Y%m%d_%H%M%S_") + stem


def _ensure_clean_dir(path, force):
    if path.exists():
        if not force:
            raise SystemExit("%s already exists; use --force to replace it" % path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _mac_to_hi_lo(mac_text):
    compact = int(mac_text.replace(":", ""), 16)
    return (compact >> 32) & 0xFFFF, compact & 0xFFFFFFFF


def _load_define_map(path):
    defines = {}
    pattern = re.compile(r"^\s*#define\s+([A-Z0-9_]+)\s+(0x[0-9a-fA-F]+)")
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            match = pattern.match(line)
            if match:
                defines[str(match.group(1))] = int(match.group(2), 16)
    return defines


def _prepare_batch_pcaps(run_dir, vectors, expected_rows, args):
    pcap_dir = run_dir / "pcaps"
    pcap_dir.mkdir(parents=True, exist_ok=True)

    frame_rows = build_batch_frame_rows(
        vectors,
        request_id_base=_parse_int(args.request_id_base),
        dst_mac=args.dst_mac,
        src_mac=args.src_mac,
        src_ip=args.src_ip,
        dst_ip=args.dst_ip,
        udp_src_port=_parse_int(args.src_udp_port),
        udp_dst_port=_parse_int(args.dst_udp_port),
        task_type=_parse_int(args.task_type),
    )
    if not frame_rows:
        raise SystemExit("no test vectors available for board run preparation")

    batch_pcap = pcap_dir / "offload_batch.pcap"
    write_pcap(batch_pcap, [row["frame"] for row in frame_rows])

    smoke_pcap = pcap_dir / "offload_smoke_0.pcap"
    write_pcap(smoke_pcap, [frame_rows[0]["frame"]])

    wrong_magic_frame, wrong_magic_meta = build_task_frame_defaults(
        dst_mac=args.dst_mac,
        src_mac=args.src_mac,
        src_ip=args.src_ip,
        dst_ip=args.dst_ip,
        task_magic=DEFAULT_WRONG_MAGIC,
        request_id=frame_rows[0]["request_id"],
        task_type=_parse_int(args.task_type),
        explicit_features=[int(value) for value in vectors[0]["input_s16"]],
        udp_src_port=_parse_int(args.src_udp_port),
        udp_dst_port=_parse_int(args.dst_udp_port),
    )
    wrong_magic_pcap = pcap_dir / "wrong_magic_bypass.pcap"
    write_pcap(wrong_magic_pcap, [wrong_magic_frame])

    wrong_port_frame, wrong_port_meta = build_task_frame_defaults(
        dst_mac=args.dst_mac,
        src_mac=args.src_mac,
        src_ip=args.src_ip,
        dst_ip=args.dst_ip,
        task_magic=ANN_TASK_MAGIC,
        request_id=(frame_rows[0]["request_id"] + 1) & 0xFFFF,
        task_type=_parse_int(args.task_type),
        explicit_features=[int(value) for value in vectors[0]["input_s16"]],
        udp_src_port=_parse_int(args.src_udp_port),
        udp_dst_port=DEFAULT_WRONG_PORT,
    )
    wrong_port_pcap = pcap_dir / "wrong_port_bypass.pcap"
    write_pcap(wrong_port_pcap, [wrong_port_frame])

    smoke_meta = {
        "batch_frames": [
            {
                "name": row["name"],
                "request_id": "0x%04x" % row["request_id"],
                "wire_frame_hex": row["metadata"]["wire_frame_hex"],
            }
            for row in frame_rows
        ],
        "wrong_magic": wrong_magic_meta,
        "wrong_port": wrong_port_meta,
        "expected_rows": expected_rows,
    }
    _write_json(pcap_dir / "offload_meta.json", smoke_meta)

    return {
        "frame_rows": frame_rows,
        "batch_pcap": batch_pcap,
        "smoke_pcap": smoke_pcap,
        "wrong_magic_pcap": wrong_magic_pcap,
        "wrong_port_pcap": wrong_port_pcap,
    }


def _build_manifest(run_dir, bundle_result, vectors, expected_rows, pcap_info, args):
    run_name = Path(run_dir).name
    remote_netfpga_root = "~/scripts/%s/%s_netfpga" % (DEFAULT_REMOTE_VERSION, run_name)
    remote_netfpga_results = "~/scripts/%s/%s_results" % (DEFAULT_REMOTE_VERSION, run_name)
    remote_sender_root = "~/%s/%s_sender" % (DEFAULT_REMOTE_VERSION, run_name)
    remote_receiver_root = "~/%s/%s_receiver" % (DEFAULT_REMOTE_VERSION, run_name)

    manifest = {
        "schema_version": 1,
        "run_name": run_name,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "bitfile": args.bitfile,
        "reg_defines_snapshot": _relpath(run_dir, run_dir / "config" / Path(args.reg_defines).name),
        "model": {
            "source": str(Path(args.model).resolve()),
            "input_dim": bundle_result.input_dim,
            "output_dim": bundle_result.output_dim,
            "result_mode": bundle_result.result_mode,
            "result_base": "0x%08x" % bundle_result.result_base,
            "layer_count": bundle_result.layer_count,
        },
        "network": {
            "dst_mac": args.dst_mac,
            "src_mac": args.src_mac,
            "src_ip": args.src_ip,
            "dst_ip": args.dst_ip,
            "src_udp_port": "0x%04x" % _parse_int(args.src_udp_port),
            "dst_udp_port": "0x%04x" % _parse_int(args.dst_udp_port),
            "task_type": "0x%04x" % _parse_int(args.task_type),
            "request_id_base": "0x%04x" % _parse_int(args.request_id_base),
        },
        "usc": {
            "netfpga_host": args.netfpga_host,
            "sender_host": args.sender_host,
            "receiver_host": args.receiver_host,
            "sender_iface": args.sender_iface,
            "receiver_iface": args.receiver_iface,
            "router_op_lut_macs": EXPERIMENT_MACS,
            "remote_netfpga_root": remote_netfpga_root,
            "remote_netfpga_results": remote_netfpga_results,
            "remote_sender_root": remote_sender_root,
            "remote_receiver_root": remote_receiver_root,
        },
        "artifacts": {
            "bundle_dir": _relpath(run_dir, run_dir / "bundle"),
            "selected_test_vectors": _relpath(run_dir, run_dir / "board_test_vectors.json"),
            "selected_expected_outputs": _relpath(run_dir, run_dir / "board_expected_outputs.json"),
            "offload_batch_pcap": _relpath(run_dir, pcap_info["batch_pcap"]),
            "offload_smoke_pcap": _relpath(run_dir, pcap_info["smoke_pcap"]),
            "wrong_magic_pcap": _relpath(run_dir, pcap_info["wrong_magic_pcap"]),
            "wrong_port_pcap": _relpath(run_dir, pcap_info["wrong_port_pcap"]),
            "capture_dir": "captures",
            "offload_batch_time_window_capture": "captures/offload_batch_time_window.cap",
            "debug_status_txt": "debug_status_post.txt",
            "observed_json": "observed_results.json",
            "report_json": "board_eval_report.json",
            "summary_md": "board_test_summary.md",
        },
        "counts": {
            "selected_samples": len(vectors),
            "batch_packet_count": len(pcap_info["frame_rows"]),
            "smoke_packet_count": 1,
        },
        "smoke": {
            "offload_sample": vectors[0]["name"],
            "wrong_magic_request_id": "0x%04x" % pcap_info["frame_rows"][0]["request_id"],
            "wrong_port_request_id": "0x%04x" % ((pcap_info["frame_rows"][0]["request_id"] + 1) & 0xFFFF),
        },
        "capture": {
            "batch_modes": ["count", "time_window"],
            "batch_time_window_seconds": float(args.batch_time_window_seconds),
        },
    }
    return manifest


def _manifest_path(path_or_run_dir):
    candidate = Path(path_or_run_dir)
    if candidate.is_dir():
        return candidate / "manifest.json"
    return candidate


def _resolve_manifest(manifest_path):
    manifest_path = _manifest_path(manifest_path).resolve()
    manifest = _load_json(manifest_path)
    run_dir = manifest_path.parent
    return run_dir, manifest_path, manifest


def _artifact_path(run_dir, manifest, key):
    return run_dir / manifest["artifacts"][key]


def _format_request_id(value):
    if value is None:
        return None
    return "0x%04x" % (int(value) & 0xFFFF)


def _parse_debug_status_text(text):
    parsed = {}
    if not text:
        return parsed
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        try:
            parsed[key] = int(value, 0)
        except ValueError:
            parsed[key] = value
    return parsed


def _classify_capture_mode(batch_capture_path):
    name = Path(batch_capture_path).name
    if "time_window" in name:
        return "time_window"
    if name == "offload_batch.cap" or "count" in name:
        return "count"
    return "custom"


def _missing_request_ids(expected_rows, missing_names):
    expected_by_name = {row.get("name"): row for row in expected_rows}
    missing = []
    for name in missing_names:
        row = expected_by_name.get(name)
        if row is None or row.get("request_id") is None:
            continue
        missing.append(_format_request_id(row["request_id"]))
    return missing


def _request_ids_from_rows(rows):
    request_ids = []
    for row in rows:
        if row.get("request_id") is None:
            continue
        request_ids.append(_format_request_id(row["request_id"]))
    return request_ids


def _sender_rows_from_frames(frames, udp_dst_port=None):
    captured = []
    for frame in frames:
        try:
            row = inspect_ann_frame(frame)
        except ValueError:
            continue
        if row.get("frame_kind") != "ann_task":
            continue
        row_udp_dst_port = row.get("udp_dst_port")
        if udp_dst_port is not None and row_udp_dst_port is not None and int(str(row_udp_dst_port), 0) != udp_dst_port:
            continue
        captured.append(row)
    return captured


def _augment_batch_summary(summary, manifest, expected_rows, observed_rows, batch_capture_path, debug_status_text=None):
    sent_count = int(manifest["counts"]["batch_packet_count"])
    capture_count = len(observed_rows)
    debug_status = _parse_debug_status_text(debug_status_text)
    debug_emit_count = debug_status.get("result_emit_count")
    debug_compute_done_count = debug_status.get("compute_done_count")
    debug_frame_hold_count = debug_status.get("frame_hold_count")
    debug_offload_accept_count = debug_status.get("offload_accept_count")

    summary["sent_count"] = sent_count
    summary["capture_count"] = capture_count
    summary["batch_capture_mode"] = _classify_capture_mode(batch_capture_path)
    summary["batch_capture_path"] = str(batch_capture_path)
    summary["missing_request_ids"] = _missing_request_ids(expected_rows, summary.get("missing_samples", []))
    if debug_status:
        summary["debug_counters"] = debug_status
        summary["debug_emit_count"] = debug_emit_count
        summary["debug_compute_done_count"] = debug_compute_done_count
        summary["debug_frame_hold_count"] = debug_frame_hold_count
        summary["debug_offload_accept_count"] = debug_offload_accept_count
        if debug_emit_count is not None:
            summary["capture_vs_emit_gap"] = int(debug_emit_count) - capture_count

        if debug_emit_count == sent_count and capture_count < sent_count:
            summary["pipeline_verdict"] = "capture_side_miss"
        elif debug_compute_done_count == sent_count and debug_emit_count is not None and debug_emit_count < sent_count:
            summary["pipeline_verdict"] = "egress_emit_issue"
        elif debug_frame_hold_count == sent_count and debug_compute_done_count is not None and debug_compute_done_count < sent_count:
            summary["pipeline_verdict"] = "engine_compute_issue"
        elif debug_offload_accept_count is not None and debug_offload_accept_count < sent_count:
            summary["pipeline_verdict"] = "ingress_dispatch_issue"
        elif debug_emit_count == sent_count and capture_count == sent_count:
            summary["pipeline_verdict"] = "healthy"
    return summary


def _augment_sender_receiver_summary(summary, manifest, sender_rows, observed_rows, debug_status_text=None):
    sent_count = int(manifest["counts"]["batch_packet_count"])
    sender_capture_count = len(sender_rows)
    receiver_capture_count = len(observed_rows)
    debug_status = _parse_debug_status_text(debug_status_text)
    debug_emit_count = debug_status.get("result_emit_count")

    summary["expected_request_ids"] = [
        _format_request_id((_parse_int(manifest["network"]["request_id_base"]) + index) & 0xFFFF)
        for index in range(sent_count)
    ]
    summary["sender_capture_count"] = sender_capture_count
    summary["receiver_capture_count"] = receiver_capture_count
    summary["sender_request_ids"] = _request_ids_from_rows(sender_rows)
    summary["receiver_request_ids"] = _request_ids_from_rows(observed_rows)
    if debug_status:
        summary["engine_emit_count"] = debug_emit_count
        if debug_status.get("last_emit_request_id") is not None:
            summary["engine_last_emit_request_id"] = _format_request_id(debug_status["last_emit_request_id"])
    return summary


def _write_shell(path, text):
    _write_text(path, text)
    os.chmod(path, 0o755)


def _remote_shell_path(path_text):
    if path_text.startswith("~/"):
        return "$HOME/" + path_text[2:]
    return path_text


def _render_stage_script(run_dir, manifest):
    usc = manifest["usc"]
    return """#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="{run_dir}"

ssh {netfpga_host} "mkdir -p {netfpga_root} {netfpga_results}"
scp -r "$RUN_DIR/deploy_netfpga/." {netfpga_host}:{netfpga_root}/
scp -r "$RUN_DIR/bundle" {netfpga_host}:{netfpga_root}/bundle

ssh {sender_host} "mkdir -p {sender_root}/pcaps {sender_root}/captures"
scp -r "$RUN_DIR/pcaps/." {sender_host}:{sender_root}/pcaps/

ssh {receiver_host} "mkdir -p {receiver_root}/captures"
""".format(
        run_dir=str(run_dir),
        netfpga_host=usc["netfpga_host"],
        sender_host=usc["sender_host"],
        receiver_host=usc["receiver_host"],
        netfpga_root=usc["remote_netfpga_root"],
        netfpga_results=usc["remote_netfpga_results"],
        sender_root=usc["remote_sender_root"],
        receiver_root=usc["remote_receiver_root"],
    )


def _render_bringup_script(run_dir, manifest):
    usc = manifest["usc"]
    bundle_dir = _remote_shell_path("%s/bundle" % usc["remote_netfpga_root"])
    result_root = _remote_shell_path(usc["remote_netfpga_results"])
    reg_path = run_dir / manifest["reg_defines_snapshot"]
    defines = _load_define_map(reg_path)
    mac_lines = []
    for index, mac_text in enumerate(usc["router_op_lut_macs"]):
        hi_addr = defines["ROUTER_OP_LUT_MAC_%d_HI_REG" % index]
        lo_addr = defines["ROUTER_OP_LUT_MAC_%d_LO_REG" % index]
        hi_value, lo_value = _mac_to_hi_lo(mac_text)
        mac_lines.append("regwrite 0x%08x 0x%08x" % (hi_addr, hi_value))
        mac_lines.append("regwrite 0x%08x 0x%08x" % (lo_addr, lo_value))

    if manifest["model"]["result_mode"] == "compact_class_score":
        result_mode_cmd = (
            'perl bin/annctl engine result-config {base} {count} compact'.format(
                base=manifest["model"]["result_base"],
                count=manifest["model"]["output_dim"],
            )
        )
    else:
        result_mode_cmd = "perl bin/annctl engine result-clear"

    return """#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT="{run_root}"
RESULT_ROOT="{result_root}"
export ANNCTL_STATE_DIR="$RESULT_ROOT/annctl_state"

mkdir -p "$RUN_ROOT" "$RESULT_ROOT" "$ANNCTL_STATE_DIR"
cd "$RUN_ROOT"

/home/netfpga/bin/nf_download ~/bitfiles/{bitfile}
if ! ps -ef | grep [r]kd >/dev/null 2>&1; then
  /home/netfpga/bin/rkd
fi

{mac_restore}

perl bin/annctl regs read sw_engine_ctrl
perl bin/annctl regs read hw_engine_status
perl bin/annctl cpu load "{bundle_dir}/cpu_build/image.txt"
perl bin/annctl gpu imem-load "{bundle_dir}/gpu_build/compiled_gpu_imem.txt"
perl bin/annctl gpu param-load "{bundle_dir}/gpu_build/compiled_gpu_params.txt"
{result_mode_cmd}
perl bin/annctl engine enable
perl bin/annctl engine status
perl bin/annctl engine debug-clear
perl bin/annctl engine debug-status
""".format(
        run_root=_remote_shell_path(usc["remote_netfpga_root"]),
        result_root=result_root,
        bitfile=manifest["bitfile"],
        mac_restore="\n".join(mac_lines),
        bundle_dir=bundle_dir,
        result_mode_cmd=result_mode_cmd,
    )


def _render_capture_workflow(run_dir, manifest):
    usc = manifest["usc"]
    artifacts = manifest["artifacts"]
    batch_count = manifest["counts"]["batch_packet_count"]
    batch_time_window_seconds = float(manifest.get("capture", {}).get("batch_time_window_seconds", DEFAULT_BATCH_CAPTURE_TIME_WINDOW_SECONDS))
    batch_capture = _remote_shell_path("%s/captures/offload_batch.cap" % usc["remote_receiver_root"])
    sender_batch_capture = _remote_shell_path("%s/captures/offload_batch_sender.cap" % usc["remote_sender_root"])
    batch_capture_time_window = _remote_shell_path("%s/%s" % (
        usc["remote_receiver_root"],
        artifacts["offload_batch_time_window_capture"],
    ))
    wrong_magic_capture = _remote_shell_path("%s/captures/wrong_magic_bypass.cap" % usc["remote_receiver_root"])
    wrong_port_capture = _remote_shell_path("%s/captures/wrong_port_bypass.cap" % usc["remote_receiver_root"])
    sender_pcap_root = _remote_shell_path("%s/pcaps" % usc["remote_sender_root"])

    capture_filter = "udp and src host {src_ip} and dst host {dst_ip}".format(
        src_ip=manifest["network"]["src_ip"],
        dst_ip=manifest["network"]["dst_ip"],
    )

    scripts = {
        "nf1_capture_offload_batch.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c {count} '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=_remote_shell_path("%s/captures" % usc["remote_receiver_root"]),
            iface=usc["receiver_iface"],
            count=batch_count,
            capture_filter=capture_filter,
            capture_path=batch_capture,
        ),
        "nf4_capture_offload_batch_sender.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c {count} '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=_remote_shell_path("%s/captures" % usc["remote_sender_root"]),
            iface=usc["sender_iface"],
            count=batch_count,
            capture_filter=capture_filter,
            capture_path=sender_batch_capture,
        ),
        "nf1_capture_offload_batch_time_window.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
rm -f "{capture_path}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U '{capture_filter}' -w "{capture_path}" >/dev/null 2>&1 &
TCPDUMP_PID=$!
sleep {capture_window}
kill -INT "$TCPDUMP_PID" >/dev/null 2>&1 || true
wait "$TCPDUMP_PID" || true
""".format(
            capture_dir=_remote_shell_path("%s/captures" % usc["remote_receiver_root"]),
            iface=usc["receiver_iface"],
            capture_filter=capture_filter,
            capture_path=batch_capture_time_window,
            capture_window=("{:g}".format(batch_time_window_seconds)),
        ),
        "nf1_capture_wrong_magic.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c 1 '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=_remote_shell_path("%s/captures" % usc["remote_receiver_root"]),
            iface=usc["receiver_iface"],
            capture_filter=capture_filter,
            capture_path=wrong_magic_capture,
        ),
        "nf1_capture_wrong_port.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{capture_dir}"
sudo /usr/sbin/tcpdump -i {iface} -nn -U -c 1 '{capture_filter}' -w "{capture_path}"
""".format(
            capture_dir=_remote_shell_path("%s/captures" % usc["remote_receiver_root"]),
            iface=usc["receiver_iface"],
            capture_filter=capture_filter,
            capture_path=wrong_port_capture,
        ),
        "nf4_replay_offload_batch.sh": """#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"
""".format(
            iface=usc["sender_iface"],
            pcap_path="%s/%s" % (sender_pcap_root, Path(artifacts["offload_batch_pcap"]).name),
        ),
        "nf4_replay_wrong_magic.sh": """#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"
""".format(
            iface=usc["sender_iface"],
            pcap_path="%s/%s" % (sender_pcap_root, Path(artifacts["wrong_magic_pcap"]).name),
        ),
        "nf4_replay_wrong_port.sh": """#!/usr/bin/env bash
set -euo pipefail
sudo /usr/bin/tcpreplay -i {iface} "{pcap_path}"
""".format(
            iface=usc["sender_iface"],
            pcap_path="%s/%s" % (sender_pcap_root, Path(artifacts["wrong_port_pcap"]).name),
        ),
        "nf3_debug_snapshot.sh": """#!/usr/bin/env bash
set -euo pipefail
RUN_ROOT="{run_root}"
RESULT_ROOT="{result_root}"
mkdir -p "$RESULT_ROOT"
cd "$RUN_ROOT"
perl bin/annctl engine debug-status > "$RESULT_ROOT/{debug_name}"
cat "$RESULT_ROOT/{debug_name}"
""".format(
            run_root=_remote_shell_path(usc["remote_netfpga_root"]),
            result_root=_remote_shell_path(usc["remote_netfpga_results"]),
            debug_name=Path(artifacts["debug_status_txt"]).name,
        ),
        "local_fetch_captures.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{local_capture_dir}"
scp {receiver_host}:{remote_capture_dir}/*.cap "{local_capture_dir}/"
""".format(
            local_capture_dir=str(run_dir / "captures"),
            receiver_host=usc["receiver_host"],
            remote_capture_dir="%s/captures" % usc["remote_receiver_root"],
        ),
        "local_fetch_sender_captures.sh": """#!/usr/bin/env bash
set -euo pipefail
mkdir -p "{local_capture_dir}"
scp {sender_host}:{remote_capture_dir}/*.cap "{local_capture_dir}/"
""".format(
            local_capture_dir=str(run_dir / "captures"),
            sender_host=usc["sender_host"],
            remote_capture_dir="%s/captures" % usc["remote_sender_root"],
        ),
        "local_fetch_debug.sh": """#!/usr/bin/env bash
set -euo pipefail
scp {netfpga_host}:{remote_debug_path} "{local_debug_path}"
""".format(
            netfpga_host=usc["netfpga_host"],
            remote_debug_path="%s/%s" % (
                _remote_shell_path(usc["remote_netfpga_results"]),
                Path(artifacts["debug_status_txt"]).name,
            ),
            local_debug_path=str(run_dir / artifacts["debug_status_txt"]),
        ),
    }
    return scripts


def _render_markdown_summary(manifest, batch_summary, wrong_magic_row, wrong_port_row, debug_status_text=None):
    lines = []
    lines.append("# Board Test Summary")
    lines.append("")
    lines.append("- run_name: `%s`" % manifest["run_name"])
    lines.append("- bitfile: `%s`" % manifest["bitfile"])
    lines.append("- result_mode: `%s`" % manifest["model"]["result_mode"])
    lines.append("- batch_alignment: `%s`" % batch_summary.get("alignment_mode", "sequence"))
    lines.append("- selected_samples: `%s`" % manifest["counts"]["selected_samples"])
    lines.append("")
    lines.append("## Bypass Smoke")
    lines.append("")
    if wrong_magic_row is not None:
        lines.append("- `wrong_magic_bypass`: payload_magic=`%s`, udp_dst_port=`%s`" % (
            wrong_magic_row.get("payload_magic", "n/a"),
            wrong_magic_row.get("udp_dst_port", "n/a"),
        ))
    else:
        lines.append("- `wrong_magic_bypass`: no capture parsed")
    if wrong_port_row is not None:
        lines.append("- `wrong_port_bypass`: payload_magic=`%s`, udp_dst_port=`%s`" % (
            wrong_port_row.get("payload_magic", "n/a"),
            wrong_port_row.get("udp_dst_port", "n/a"),
        ))
    else:
        lines.append("- `wrong_port_bypass`: no capture parsed")
    lines.append("")
    lines.append("## Batch")
    lines.append("")
    lines.append("- sample_count: `%s`" % batch_summary.get("sample_count", 0))
    lines.append("- sent_count: `%s`" % batch_summary.get("sent_count", "n/a"))
    lines.append("- observed_count: `%s`" % batch_summary.get("observed_count", 0))
    lines.append("- capture_count: `%s`" % batch_summary.get("capture_count", "n/a"))
    lines.append("- batch_capture_mode: `%s`" % batch_summary.get("batch_capture_mode", "n/a"))
    if "sender_capture_count" in batch_summary:
        lines.append("- sender_capture_count: `%s`" % batch_summary.get("sender_capture_count", "n/a"))
    if "receiver_capture_count" in batch_summary:
        lines.append("- receiver_capture_count: `%s`" % batch_summary.get("receiver_capture_count", "n/a"))
    lines.append("- class_matches: `%s`" % batch_summary.get("class_matches", 0))
    lines.append("- wire_matches: `%s`" % batch_summary.get("wire_matches", 0))
    lines.append("- missing_samples: `%s`" % len(batch_summary.get("missing_samples", [])))
    missing_request_ids = batch_summary.get("missing_request_ids", [])
    lines.append("- missing_request_ids: `%s`" % ",".join(missing_request_ids) if missing_request_ids else "- missing_request_ids: `-`")
    lines.append("- mismatches: `%s`" % len(batch_summary.get("mismatches", [])))
    if "debug_emit_count" in batch_summary:
        lines.append("- debug_emit_count: `%s`" % batch_summary.get("debug_emit_count"))
    if "engine_emit_count" in batch_summary:
        lines.append("- engine_emit_count: `%s`" % batch_summary.get("engine_emit_count"))
    if "capture_vs_emit_gap" in batch_summary:
        lines.append("- capture_vs_emit_gap: `%s`" % batch_summary.get("capture_vs_emit_gap"))
    if "pipeline_verdict" in batch_summary:
        lines.append("- pipeline_verdict: `%s`" % batch_summary.get("pipeline_verdict"))
    if batch_summary.get("expected_request_ids"):
        lines.append("- expected_request_ids: `%s`" % ",".join(batch_summary["expected_request_ids"]))
    if batch_summary.get("sender_request_ids"):
        lines.append("- sender_request_ids: `%s`" % ",".join(batch_summary["sender_request_ids"]))
    if batch_summary.get("receiver_request_ids"):
        lines.append("- receiver_request_ids: `%s`" % ",".join(batch_summary["receiver_request_ids"]))
    if batch_summary.get("engine_last_emit_request_id"):
        lines.append("- engine_last_emit_request_id: `%s`" % batch_summary["engine_last_emit_request_id"])
    if debug_status_text:
        lines.append("")
        lines.append("## Debug Snapshot")
        lines.append("")
        lines.append("```text")
        lines.extend(debug_status_text.rstrip().splitlines())
        lines.append("```")
    return "\n".join(lines) + "\n"


def prepare_cmd(args):
    run_dir = _run_dir_from_args(args)
    _ensure_clean_dir(run_dir, args.force)

    (run_dir / "captures").mkdir(parents=True, exist_ok=True)
    (run_dir / "commands").mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT_DIR / "deploy" / "netfpga", run_dir / "deploy_netfpga")
    (run_dir / "config").mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(args.reg_defines), run_dir / "config" / Path(args.reg_defines).name)
    shutil.copy2(Path(args.model), run_dir / "model_source.json")

    bundle_result = build_model(args.model, str(run_dir / "bundle"))
    vectors = load_test_vectors(bundle_result.test_vector_path)
    expected_rows = load_expected_outputs(bundle_result.expected_output_path)
    if args.limit is not None:
        limit = int(args.limit)
        vectors = vectors[:limit]
        expected_rows = expected_rows[:limit]

    _write_json(run_dir / "board_test_vectors.json", vectors)
    _write_json(run_dir / "board_expected_outputs.json", expected_rows)

    pcap_info = _prepare_batch_pcaps(run_dir, vectors, expected_rows, args)
    manifest = _build_manifest(run_dir, bundle_result, vectors, expected_rows, pcap_info, args)
    _write_json(run_dir / "manifest.json", manifest)

    print("run_dir=%s" % run_dir)
    print("manifest=%s" % (run_dir / "manifest.json"))
    print("bundle_dir=%s" % (run_dir / "bundle"))
    print("pcap_dir=%s" % (run_dir / "pcaps"))
    print("selected_samples=%d" % len(vectors))
    print("result_mode=%s" % bundle_result.result_mode)
    return 0


def bringup_cmd(args):
    run_dir, _manifest_path_value, manifest = _resolve_manifest(args.manifest)
    commands_dir = run_dir / "commands"
    commands_dir.mkdir(parents=True, exist_ok=True)
    _write_shell(commands_dir / "local_stage_netfpga.sh", _render_stage_script(run_dir, manifest))
    _write_shell(commands_dir / "nf3_bringup.sh", _render_bringup_script(run_dir, manifest))
    print("generated %s" % (commands_dir / "local_stage_netfpga.sh"))
    print("generated %s" % (commands_dir / "nf3_bringup.sh"))
    return 0


def capture_cmd(args):
    run_dir, _manifest_path_value, manifest = _resolve_manifest(args.manifest)
    commands_dir = run_dir / "commands"
    commands_dir.mkdir(parents=True, exist_ok=True)
    scripts = _render_capture_workflow(run_dir, manifest)
    for name, content in scripts.items():
        _write_shell(commands_dir / name, content)
    print("generated capture workflow scripts under %s" % commands_dir)
    return 0


def _load_single_capture(path):
    frames = read_pcap(path)
    if not frames:
        return None
    rows = observed_rows_from_frames(frames, accept_bypass=True, udp_dst_port=None)
    if not rows:
        return None
    return rows[0]


def report_cmd(args):
    run_dir, _manifest_path_value, manifest = _resolve_manifest(args.manifest)
    request_id_base = _parse_int(manifest["network"]["request_id_base"])
    expected_rows = with_expected_request_ids(
        load_expected_outputs(_artifact_path(run_dir, manifest, "selected_expected_outputs")),
        request_id_base=request_id_base,
    )

    batch_capture = Path(args.batch_capture) if args.batch_capture else _artifact_path(run_dir, manifest, "capture_dir") / "offload_batch.cap"
    frames = read_pcap(batch_capture)
    observed_rows = observed_rows_from_frames(
        frames,
        expected_rows=expected_rows,
        result_mode=manifest["model"]["result_mode"],
        accept_bypass=False,
        udp_dst_port=_parse_int(manifest["network"]["dst_udp_port"]),
        request_id_base=request_id_base,
    )
    summary = compare_expected_observed(expected_rows, observed_rows)
    summary["alignment_mode"] = "request_id"
    summary["request_id_base"] = manifest["network"]["request_id_base"]

    sender_capture = Path(args.sender_capture) if args.sender_capture else _artifact_path(run_dir, manifest, "capture_dir") / "offload_batch_sender.cap"
    sender_frames = read_pcap(sender_capture) if sender_capture.exists() else []
    sender_rows = _sender_rows_from_frames(
        sender_frames,
        udp_dst_port=_parse_int(manifest["network"]["dst_udp_port"]),
    )

    wrong_magic_path = Path(args.wrong_magic_capture) if args.wrong_magic_capture else _artifact_path(run_dir, manifest, "capture_dir") / "wrong_magic_bypass.cap"
    wrong_port_path = Path(args.wrong_port_capture) if args.wrong_port_capture else _artifact_path(run_dir, manifest, "capture_dir") / "wrong_port_bypass.cap"

    wrong_magic_row = _load_single_capture(wrong_magic_path) if wrong_magic_path.exists() else None
    wrong_port_row = _load_single_capture(wrong_port_path) if wrong_port_path.exists() else None
    debug_status_path = run_dir / manifest["artifacts"]["debug_status_txt"]
    debug_status_text = debug_status_path.read_text(encoding="utf-8") if debug_status_path.exists() else None
    summary = _augment_batch_summary(
        summary,
        manifest,
        expected_rows,
        observed_rows,
        batch_capture,
        debug_status_text=debug_status_text,
    )
    summary = _augment_sender_receiver_summary(
        summary,
        manifest,
        sender_rows,
        observed_rows,
        debug_status_text=debug_status_text,
    )
    if debug_status_text is not None:
        summary["debug_status_path"] = manifest["artifacts"]["debug_status_txt"]
    _write_json(run_dir / manifest["artifacts"]["observed_json"], observed_rows)
    _write_json(run_dir / manifest["artifacts"]["report_json"], summary)
    _write_text(
        run_dir / manifest["artifacts"]["summary_md"],
        _render_markdown_summary(manifest, summary, wrong_magic_row, wrong_port_row, debug_status_text=debug_status_text),
    )

    print("observed_json=%s" % (run_dir / manifest["artifacts"]["observed_json"]))
    print("report_json=%s" % (run_dir / manifest["artifacts"]["report_json"]))
    print("summary_md=%s" % (run_dir / manifest["artifacts"]["summary_md"]))
    print("mismatches=%d" % len(summary["mismatches"]))
    print("missing_samples=%d" % len(summary["missing_samples"]))
    return 0 if not summary["mismatches"] and not summary["missing_samples"] else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Prepare and organize formal USC NetFPGA ANN board runs.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare = subparsers.add_parser("prepare", help="build bundle, select vectors, and generate pcaps + manifest")
    prepare.add_argument("--model", default=str(ROOT_DIR / "sw" / "testdata" / "ann_model_mlp_int16.json"))
    prepare.add_argument("--out-dir")
    prepare.add_argument("--run-name")
    prepare.add_argument("--limit")
    prepare.add_argument("--force", action="store_true", default=False)
    prepare.add_argument("--bitfile", default=DEFAULT_BITFILE)
    prepare.add_argument("--reg-defines", default=_default_reg_defines_path())
    prepare.add_argument("--netfpga-host", default=DEFAULT_NETFPGA_HOST)
    prepare.add_argument("--sender-host", default=DEFAULT_SENDER_HOST)
    prepare.add_argument("--receiver-host", default=DEFAULT_RECEIVER_HOST)
    prepare.add_argument("--sender-iface", default=DEFAULT_SENDER_IFACE)
    prepare.add_argument("--receiver-iface", default=DEFAULT_RECEIVER_IFACE)
    prepare.add_argument("--dst-mac", default=DEFAULT_DST_MAC)
    prepare.add_argument("--src-mac", default=DEFAULT_SRC_MAC)
    prepare.add_argument("--src-ip", default=DEFAULT_SRC_IP)
    prepare.add_argument("--dst-ip", default=DEFAULT_DST_IP)
    prepare.add_argument("--src-udp-port", default="0x%04x" % DEFAULT_UDP_SRC_PORT)
    prepare.add_argument("--dst-udp-port", default="0x%04x" % DEFAULT_UDP_DST_PORT)
    prepare.add_argument("--task-type", default=DEFAULT_TASK_TYPE_HEX)
    prepare.add_argument("--request-id-base", default="0x%04x" % DEFAULT_REQUEST_ID_BASE)
    prepare.add_argument("--batch-time-window-seconds", type=float, default=DEFAULT_BATCH_CAPTURE_TIME_WINDOW_SECONDS)
    prepare.set_defaults(func=prepare_cmd)

    bringup = subparsers.add_parser("bringup", help="generate nf3 stage + bring-up scripts from a run manifest")
    bringup.add_argument("manifest")
    bringup.set_defaults(func=bringup_cmd)

    capture = subparsers.add_parser("capture", help="generate nf1/nf4 capture + replay scripts from a run manifest")
    capture.add_argument("manifest")
    capture.set_defaults(func=capture_cmd)

    report = subparsers.add_parser("report", help="parse capture pcaps and generate observed/report artifacts")
    report.add_argument("manifest")
    report.add_argument("--batch-capture")
    report.add_argument("--sender-capture")
    report.add_argument("--wrong-magic-capture")
    report.add_argument("--wrong-port-capture")
    report.set_defaults(func=report_cmd)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "run_name", None) is None and args.command == "prepare":
        args.run_name = _make_run_name(args.model)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
