#!/usr/bin/env python

import os
import socket
import sys
import time
from optparse import OptionParser

from packetlib import json_compat
from packetlib.udp_ann_packets import (
    ACTION_OFFLOAD,
    ANN_TASK_MAGIC,
    ANN_UDP_DST_PORT,
    DEFAULT_DST_IP,
    DEFAULT_DST_MAC,
    DEFAULT_DST_PORT_MASK,
    DEFAULT_FEATURE_COUNT,
    DEFAULT_FEATURE_SEED,
    DEFAULT_REQUEST_ID,
    DEFAULT_SRC_IP,
    DEFAULT_SRC_MAC,
    DEFAULT_SRC_PORT,
    DEFAULT_TASK_TYPE,
    DEFAULT_UDP_SRC_PORT,
    OFFLOAD_RESULT_MAGIC,
    build_packet_artifacts,
    decode_task_payload,
    decode_packet_blob,
    hex_to_bytes,
    parse_feature_values,
    render_opl_words_text,
    task_magic_kind,
    write_pcap_single,
)


def _write_line(text):
    sys.stdout.write(text + "\n")


def _parse_int(value):
    if value is None:
        return None
    return int(value, 0)


def _byte_value(item):
    if PY3:
        return int(item)
    return ord(item)


def _write_text(path, text):
    handle = open(path, "w")
    try:
        handle.write(text)
    finally:
        handle.close()


def _write_json(path, value, sort_keys):
    handle = open(path, "w")
    try:
        handle.write(json_compat.dumps(value, indent=2, sort_keys=sort_keys))
        handle.write("\n")
    finally:
        handle.close()


def _load_json(path):
    handle = open(path, "r")
    try:
        return json_compat.loads(handle.read())
    finally:
        handle.close()


def _coerce_spec_value(value):
    if isinstance(value, dict):
        result = {}
        keys = value.keys()
        keys = list(keys)
        for key in keys:
            result[key] = _coerce_spec_value(value[key])
        return result
    if isinstance(value, (list, tuple)):
        result = []
        for item in value:
            result.append(_coerce_spec_value(item))
        return result
    return value


def _load_packet_spec_from_json(path):
    value = _load_json(path)
    if isinstance(value, list):
        raise ValueError("expected packet JSON object, got list")
    return _coerce_spec_value(value)


def _build_spec_from_options(options):
    spec = {
        "packet_kind": options.packet_kind,
        "name": options.name,
        "dst_mac": options.dst_mac,
        "src_mac": options.src_mac,
        "src_ip": options.src_ip,
        "dst_ip": options.dst_ip,
        "src_port": _parse_int(options.src_port),
        "dst_port_mask": _parse_int(options.dst_port_mask),
        "udp_src_port": _parse_int(options.udp_src_port),
        "udp_dst_port": _parse_int(options.udp_dst_port),
        "tcp_src_port": _parse_int(options.tcp_src_port),
        "tcp_dst_port": _parse_int(options.tcp_dst_port),
        "task_magic": _parse_int(options.task_magic),
        "request_id": _parse_int(options.request_id),
        "feature_count": _parse_int(options.feature_count),
        "emitted_feature_count": _parse_int(options.emitted_feature_count),
        "feature_seed": _parse_int(options.feature_seed),
        "task_type": _parse_int(options.task_type),
        "payload_len": _parse_int(options.payload_len),
        "payload_seed": _parse_int(options.payload_seed),
        "ethertype": _parse_int(options.ethertype),
        "ip_options_bytes": _parse_int(options.ip_options_bytes),
    }

    if options.feature_values:
        spec["explicit_features"] = parse_feature_values(options.feature_values)

    cleaned = {}
    keys = spec.keys()
    keys = list(keys)
    for key in keys:
        if spec[key] is not None:
            cleaned[key] = spec[key]
    return cleaned


def _dump_artifacts(metadata, dump_json):
    if dump_json:
        _write_line(json_compat.dumps(metadata, indent=2, sort_keys=True))
        return
    _write_line("name=%s" % metadata.get("name", metadata.get("packet_kind", "packet")))
    _write_line("packet_kind=%s" % metadata["packet_kind"])
    _write_line("selector_expected_action=%s" % metadata["selector_expected_action"])
    _write_line("wire_len=%d" % metadata["wire_len"])
    _write_line("internal_frame_len=%d" % metadata["internal_frame_len"])
    _write_line("expected_module_header=%s" % metadata["expected_module_header"])
    _write_line("wire_frame_hex=%s" % metadata["wire_frame_hex"])


def _write_artifact_files(out_dir, prefix, metadata):
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    base = os.path.join(out_dir, prefix)
    _write_json(base + ".json", metadata, True)
    _write_text(base + ".wire.hex", metadata["wire_frame_hex"] + "\n")
    _write_text(base + ".opl.txt", render_opl_words_text(metadata["opl_words"]))
    if metadata.get("udp_payload_hex") is not None:
        _write_text(base + ".udp_payload.hex", metadata["udp_payload_hex"] + "\n")


def _add_common_packet_options(parser):
    parser.add_option("--packet-kind", dest="packet_kind", default="udp_ann")
    parser.add_option("--name", dest="name")
    parser.add_option("--dst-mac", dest="dst_mac", default=DEFAULT_DST_MAC)
    parser.add_option("--src-mac", dest="src_mac", default=DEFAULT_SRC_MAC)
    parser.add_option("--src-ip", dest="src_ip", default=DEFAULT_SRC_IP)
    parser.add_option("--dst-ip", dest="dst_ip", default=DEFAULT_DST_IP)
    parser.add_option("--src-port", dest="src_port", default="0x%04x" % DEFAULT_SRC_PORT)
    parser.add_option("--dst-port-mask", dest="dst_port_mask", default="0x%04x" % DEFAULT_DST_PORT_MASK)
    parser.add_option("--udp-src-port", dest="udp_src_port", default="0x%04x" % DEFAULT_UDP_SRC_PORT)
    parser.add_option("--udp-dst-port", dest="udp_dst_port", default="0x%04x" % ANN_UDP_DST_PORT)
    parser.add_option("--tcp-src-port", dest="tcp_src_port", default="0x5001")
    parser.add_option("--tcp-dst-port", dest="tcp_dst_port", default="0x%04x" % ANN_UDP_DST_PORT)
    parser.add_option("--task-magic", dest="task_magic", default="0x%04x" % ANN_TASK_MAGIC)
    parser.add_option("--request-id", dest="request_id", default="0x%04x" % DEFAULT_REQUEST_ID)
    parser.add_option("--feature-count", dest="feature_count", default=str(DEFAULT_FEATURE_COUNT))
    parser.add_option("--emitted-feature-count", dest="emitted_feature_count")
    parser.add_option("--feature-seed", dest="feature_seed", default=str(DEFAULT_FEATURE_SEED))
    parser.add_option("--feature-values", dest="feature_values")
    parser.add_option("--task-type", dest="task_type", default="0x%04x" % DEFAULT_TASK_TYPE)
    parser.add_option("--payload-len", dest="payload_len", default="16")
    parser.add_option("--payload-seed", dest="payload_seed", default="0x10")
    parser.add_option("--ethertype", dest="ethertype", default="0x0806")
    parser.add_option("--ip-options-bytes", dest="ip_options_bytes", default="0")


def main_pktgen(argv=None):
    parser = OptionParser(usage="%prog [options]", description="Generate only_fifo packet artifacts.")
    _add_common_packet_options(parser)
    parser.add_option("--out-dir", dest="out_dir")
    parser.add_option("--output-prefix", dest="output_prefix")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))

    spec = _build_spec_from_options(options)
    metadata = build_packet_artifacts(spec)

    if options.out_dir:
        prefix = options.output_prefix
        if not prefix:
            prefix = metadata.get("name", metadata["packet_kind"])
        _write_artifact_files(options.out_dir, prefix, metadata)

    _dump_artifacts(metadata, options.dump_json)
    return 0


def _load_metadata_from_input(json_in):
    metadata = _load_packet_spec_from_json(json_in)
    if metadata.get("wire_frame_hex") is None and metadata.get("packet_kind") is not None:
        metadata = build_packet_artifacts(metadata)
    return metadata


def _send_udp_payload(dst_ip, dst_port, payload, bind_ip, bind_port, repeat, interval_ms):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if bind_ip is not None or bind_port is not None:
            if bind_ip is None:
                bind_ip = ""
            if bind_port is None:
                bind_port = 0
            sock.bind((bind_ip, bind_port))

        index = 0
        while index < repeat:
            sock.sendto(payload, (dst_ip, dst_port))
            if index + 1 < repeat:
                time.sleep(float(interval_ms) / 1000.0)
            index += 1
    finally:
        sock.close()


def main_pktsend(argv=None):
    parser = OptionParser(usage="%prog [options]", description="Send only_fifo UDP payloads using a normal UDP socket.")
    _add_common_packet_options(parser)
    parser.add_option("--json-in", dest="json_in")
    parser.add_option("--repeat", dest="repeat", default="1")
    parser.add_option("--interval-ms", dest="interval_ms", default="100")
    parser.add_option("--bind-ip", dest="bind_ip")
    parser.add_option("--bind-port", dest="bind_port")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))

    if options.json_in:
        metadata = _load_metadata_from_input(options.json_in)
    else:
        spec = _build_spec_from_options(options)
        metadata = build_packet_artifacts(spec)

    if metadata["packet_kind"] not in ("udp_ann", "udp_raw"):
        parser.error("pktsend only supports UDP packet kinds")

    payload_hex = metadata.get("udp_payload_hex")
    if payload_hex is None:
        parser.error("packet metadata does not contain udp_payload_hex")

    payload = hex_to_bytes(payload_hex)
    dst_ip = metadata.get("dst_ip", options.dst_ip)
    dst_port = _parse_int(metadata.get("udp_dst_port", options.udp_dst_port))
    bind_ip = options.bind_ip
    bind_port = _parse_int(options.bind_port)

    _send_udp_payload(
        dst_ip=dst_ip,
        dst_port=dst_port,
        payload=payload,
        bind_ip=bind_ip,
        bind_port=bind_port,
        repeat=int(options.repeat),
        interval_ms=int(options.interval_ms),
    )

    if options.dump_json:
        _write_line(json_compat.dumps(metadata, indent=2, sort_keys=True))
    _write_line("sent %d UDP datagram(s) to %s:%d" % (int(options.repeat), dst_ip, dst_port))
    return 0


def _classify_received_payload(payload, expected_magic):
    observed_magic = None
    observed_kind = "unexpected"
    observation = "unexpected_payload"
    if len(payload) >= 2:
        observed_magic = _byte_value(payload[0]) << 8
        observed_magic = observed_magic | _byte_value(payload[1])
        if observed_magic == OFFLOAD_RESULT_MAGIC:
            observed_kind = ACTION_OFFLOAD
            observation = "offload_observed"
        elif observed_magic == ANN_TASK_MAGIC:
            observed_kind = ACTION_BYPASS
            observation = "bypass_observed"

    matches_expected = None
    if expected_magic is not None and observed_magic is not None:
        matches_expected = observed_magic == expected_magic

    observed_magic_text = None
    observed_magic_kind = None
    if observed_magic is not None:
        observed_magic_text = "0x%04x" % observed_magic
        observed_magic_kind = task_magic_kind(observed_magic)

    return {
        "observation": observation,
        "observed_kind": observed_kind,
        "observed_magic": observed_magic_text,
        "observed_magic_kind": observed_magic_kind,
        "matches_expected": matches_expected,
        "payload_decode": decode_task_payload(payload),
    }


def main_pktrecv(argv=None):
    parser = OptionParser(usage="%prog [options]", description="Receive only_fifo UDP payloads using a normal UDP socket.")
    parser.add_option("--json-in", dest="json_in")
    parser.add_option("--bind-ip", dest="bind_ip", default="")
    parser.add_option("--bind-port", dest="bind_port")
    parser.add_option("--count", dest="count", default="1")
    parser.add_option("--timeout-ms", dest="timeout_ms", default="5000")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))

    metadata = None
    expected_magic = None
    expected_kind = None
    if options.json_in:
        metadata = _load_metadata_from_input(options.json_in)
        if metadata.get("expected_rx_magic") is not None:
            expected_magic = _parse_int(metadata["expected_rx_magic"])
        expected_kind = metadata.get("expected_rx_kind")

    bind_port = _parse_int(options.bind_port)
    if bind_port is None and metadata is not None:
        bind_port = _parse_int(metadata.get("udp_dst_port"))
    if bind_port is None:
        bind_port = ANN_UDP_DST_PORT

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(float(int(options.timeout_ms)) / 1000.0)

    observations = []
    timed_out = False
    try:
        sock.bind((options.bind_ip, bind_port))
        index = 0
        while index < int(options.count):
            try:
                payload, peer = sock.recvfrom(65535)
            except socket.timeout:
                timed_out = True
                break
            observation = _classify_received_payload(payload, expected_magic)
            observation["peer_ip"] = peer[0]
            observation["peer_port"] = peer[1]
            observation["payload_len"] = len(payload)
            hex_parts = []
            for item in payload:
                hex_parts.append("%02x" % _byte_value(item))
            observation["payload_hex"] = "".join(hex_parts)
            observations.append(observation)
            index += 1
    finally:
        sock.close()

    bind_ip_text = options.bind_ip
    if not bind_ip_text:
        bind_ip_text = "0.0.0.0"

    expected_magic_text = None
    if expected_magic is not None:
        expected_magic_text = "0x%04x" % expected_magic

    summary = {
        "bind_ip": bind_ip_text,
        "bind_port": bind_port,
        "count": len(observations),
        "expected_kind": expected_kind,
        "expected_magic": expected_magic_text,
        "observations": observations,
        "all_match_expected": True,
        "timed_out": timed_out,
    }

    for observation in observations:
        if observation["matches_expected"] is False:
            summary["all_match_expected"] = False

    if options.dump_json:
        _write_line(json_compat.dumps(summary, indent=2, sort_keys=True))
    else:
        for observation in observations:
            line = "received %s from %s:%d on %s:%d" % (
                observation["observation"],
                observation["peer_ip"],
                observation["peer_port"],
                summary["bind_ip"],
                bind_port,
            )
            if observation["observed_magic"] is not None:
                line = line + " magic=%s" % observation["observed_magic"]
            if observation["matches_expected"] is not None:
                if observation["matches_expected"]:
                    matches_expected_bit = 1
                else:
                    matches_expected_bit = 0
                line = line + " matches_expected=%d" % matches_expected_bit
            _write_line(line)
        if timed_out:
            _write_line("receive timeout after %d datagram(s)" % len(observations))

    if timed_out:
        return 1
    return 0


def main_pktdecode(argv=None):
    parser = OptionParser(usage="%prog [options]", description="Decode only_fifo wire-frame or UDP-payload hex.")
    parser.add_option("--json-in", dest="json_in")
    parser.add_option("--hex", dest="hex_text")
    parser.add_option("--hex-file", dest="hex_file")
    parser.add_option("--blob-kind", dest="blob_kind", default="wire")
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))

    blob = None
    if options.json_in:
        metadata = _load_metadata_from_input(options.json_in)
        if options.blob_kind == "wire":
            blob = hex_to_bytes(metadata["wire_frame_hex"])
        elif options.blob_kind == "udp_payload":
            blob = hex_to_bytes(metadata["udp_payload_hex"])
        else:
            parser.error("unsupported blob kind '%s'" % options.blob_kind)
    elif options.hex_text:
        blob = hex_to_bytes(options.hex_text)
    elif options.hex_file:
        handle = open(options.hex_file, "r")
        try:
            blob = hex_to_bytes(handle.read())
        finally:
            handle.close()
    else:
        parser.error("one of --json-in, --hex, or --hex-file is required")

    decoded = decode_packet_blob(blob, options.blob_kind)
    if options.dump_json:
        _write_line(json_compat.dumps(decoded, indent=2, sort_keys=True))
    else:
        _write_line(json_compat.dumps(decoded, indent=2, sort_keys=True))
    return 0


def main_pktbatch(argv=None):
    parser = OptionParser(usage="%prog [options]", description="Generate a batch of only_fifo packet artifacts.")
    parser.add_option("--spec", dest="spec")
    parser.add_option("--count", dest="count", default="0")
    parser.add_option("--out-dir", dest="out_dir")
    parser.add_option("--request-id-base", dest="request_id_base", default="0x%04x" % DEFAULT_REQUEST_ID)
    parser.add_option("--feature-seed-base", dest="feature_seed_base", default=str(DEFAULT_FEATURE_SEED))
    parser.add_option("--dump-json", dest="dump_json", action="store_true", default=False)
    options, args = parser.parse_args(argv)
    if args:
        parser.error("unexpected positional arguments: %s" % " ".join(args))
    if not options.out_dir:
        parser.error("--out-dir is required")

    if options.spec:
        specs = _load_json(options.spec)
        if not isinstance(specs, list):
            parser.error("--spec must point to a JSON array")
    else:
        specs = []
        count = int(options.count)
        request_id_base = _parse_int(options.request_id_base)
        feature_seed_base = _parse_int(options.feature_seed_base)
        index = 0
        while index < count:
            specs.append(
                {
                    "name": "sample_%02d" % index,
                    "packet_kind": "udp_ann",
                    "request_id": request_id_base + index,
                    "feature_seed": feature_seed_base + index,
                }
            )
            index += 1

    manifest = []
    for spec in specs:
        normalized_spec = _coerce_spec_value(spec)
        metadata = build_packet_artifacts(normalized_spec)
        prefix = metadata.get("name", metadata["packet_kind"])
        _write_artifact_files(options.out_dir, prefix, metadata)
        manifest.append(
            {
                "name": prefix,
                "packet_kind": metadata["packet_kind"],
                "selector_expected_action": metadata["selector_expected_action"],
                "expected_rx_kind": metadata.get("expected_rx_kind"),
                "expected_rx_magic": metadata.get("expected_rx_magic"),
                "json_path": prefix + ".json",
                "wire_hex_path": prefix + ".wire.hex",
                "opl_path": prefix + ".opl.txt",
            }
        )

    _write_json(os.path.join(options.out_dir, "batch_manifest.json"), manifest, True)

    if options.dump_json:
        _write_line(json_compat.dumps(manifest, indent=2, sort_keys=True))
    else:
        _write_line("generated %d packet artifact set(s) in %s" % (len(manifest), options.out_dir))
    return 0


def main_pktpcap(argv=None):
    parser = OptionParser(usage="%prog [options] output.pcap", description="Write a single only_fifo UDP frame to a pcap file.")
    _add_common_packet_options(parser)
    parser.add_option("--json-in", dest="json_in")
    options, args = parser.parse_args(argv)
    if len(args) != 1:
        parser.error("expected exactly one positional argument: output.pcap path")
    out_path = args[0]

    if options.json_in:
        metadata = _load_metadata_from_input(options.json_in)
    else:
        spec = _build_spec_from_options(options)
        metadata = build_packet_artifacts(spec)

    wire_hex = metadata["wire_frame_hex"]
    raw_frame = hex_to_bytes(wire_hex)
    write_pcap_single(out_path, raw_frame)
    _write_line("wrote %d-byte frame to %s" % (len(raw_frame), out_path))
    _write_line("frame hex: %s" % wire_hex)
    return 0
