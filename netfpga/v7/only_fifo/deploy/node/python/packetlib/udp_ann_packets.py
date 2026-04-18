#!/usr/bin/env python

import socket
import sys


PY3 = sys.version_info[0] >= 3
if PY3:
    text_type = str
    string_types = (str,)
    integer_types = (int,)
else:
    text_type = unicode
    string_types = (str, unicode)
    integer_types = (int, long)


ACTION_BYPASS = "bypass"
ACTION_OFFLOAD = "offload"

IPV4_ETHERTYPE = 0x0800
IP_PROTOCOL_TCP = 0x06
IP_PROTOCOL_UDP = 0x11
ANN_UDP_DST_PORT = 0x88B5
ANN_TASK_MAGIC = 0xA11E
OFFLOAD_RESULT_MAGIC = 0xF11E

DEFAULT_DST_MAC = "0b:ad:c0:de:00:01"
DEFAULT_SRC_MAC = "f0:0d:ca:fe:00:02"
DEFAULT_SRC_IP = "192.168.1.1"
DEFAULT_DST_IP = "192.168.1.2"
DEFAULT_SRC_PORT = 0x0001
DEFAULT_DST_PORT_MASK = 0x0008
DEFAULT_REQUEST_ID = 0x1234
DEFAULT_TASK_TYPE = 0x0000
DEFAULT_FEATURE_COUNT = 8
DEFAULT_FEATURE_SEED = 3
DEFAULT_UDP_SRC_PORT = 0x4001


def _byte_chr(value):
    if PY3:
        return bytes((value & 0xFF,))
    return chr(value & 0xFF)


def _byte_ord(value):
    if isinstance(value, integer_types):
        return value
    return ord(value)


def _join_bytes(values):
    parts = []
    for value in values:
        parts.append(value)
    if PY3:
        return bytes().join(parts)
    return "".join(parts)


def _append_bytes(parts, raw):
    if raw is None:
        return
    parts.append(raw)


def _normalize_hex_text(text):
    if text is None:
        return ""
    text = str(text)
    text = text.replace("0x", "")
    text = text.replace("0X", "")
    text = text.replace(" ", "")
    text = text.replace("\t", "")
    text = text.replace("\r", "")
    text = text.replace("\n", "")
    text = text.replace(":", "")
    if len(text) % 2 != 0:
        raise ValueError("hex text must contain an even number of digits")
    return text.lower()


def hex_to_bytes(text):
    cleaned = _normalize_hex_text(text)
    parts = []
    index = 0
    while index < len(cleaned):
        parts.append(_byte_chr(int(cleaned[index:index + 2], 16)))
        index += 2
    return _join_bytes(parts)


def bytes_to_hex(raw):
    values = []
    for item in raw:
        values.append("%02x" % _byte_ord(item))
    return "".join(values)


def mac_to_bytes(text):
    parts = text.split(":")
    if len(parts) != 6:
        raise ValueError("invalid MAC address '%s'" % text)
    values = []
    for part in parts:
        values.append(_byte_chr(int(part, 16)))
    return _join_bytes(values)


def bytes_to_mac(raw):
    if len(raw) != 6:
        raise ValueError("expected 6-byte MAC, got %d" % len(raw))
    values = []
    for item in raw:
        values.append("%02x" % _byte_ord(item))
    return ":".join(values)


def ip_to_bytes(text):
    packed = socket.inet_aton(text)
    if PY3 and isinstance(packed, str):
        return packed.encode("latin1")
    return packed


def bytes_to_ip(raw):
    if len(raw) != 4:
        raise ValueError("expected 4-byte IPv4 address, got %d" % len(raw))
    parts = []
    for item in raw:
        parts.append(str(_byte_ord(item)))
    return ".".join(parts)


def be16(value):
    return _join_bytes((_byte_chr((value >> 8) & 0xFF), _byte_chr(value & 0xFF)))


def be32(value):
    return _join_bytes(
        (
            _byte_chr((value >> 24) & 0xFF),
            _byte_chr((value >> 16) & 0xFF),
            _byte_chr((value >> 8) & 0xFF),
            _byte_chr(value & 0xFF),
        )
    )


def read_be16(raw):
    if len(raw) != 2:
        raise ValueError("expected 2 bytes, got %d" % len(raw))
    return (_byte_ord(raw[0]) << 8) | _byte_ord(raw[1])


def read_be32(raw):
    if len(raw) != 4:
        raise ValueError("expected 4 bytes, got %d" % len(raw))
    return (
        (_byte_ord(raw[0]) << 24)
        | (_byte_ord(raw[1]) << 16)
        | (_byte_ord(raw[2]) << 8)
        | _byte_ord(raw[3])
    )


def eop_ctrl(valid_bytes):
    if valid_bytes == 1:
        return 0x80
    if valid_bytes == 2:
        return 0x40
    if valid_bytes == 3:
        return 0x20
    if valid_bytes == 4:
        return 0x10
    if valid_bytes == 5:
        return 0x08
    if valid_bytes == 6:
        return 0x04
    if valid_bytes == 7:
        return 0x02
    if valid_bytes == 8:
        return 0x01
    return 0x00


def feature_values(seed, count):
    values = []
    index = 0
    while index < count:
        magnitude = seed + index + 1
        if (index % 2) == 0:
            signed_value = magnitude
        else:
            signed_value = -magnitude
        values.append(signed_value & 0xFFFF)
        index += 1
    return values


def parse_feature_values(text):
    values = []
    raw_tokens = text.split(",")
    for raw_token in raw_tokens:
        token = raw_token.strip().strip("\"'")
        if token:
            values.append(int(token, 0) & 0xFFFF)
    if not values:
        raise ValueError("explicit feature list must contain at least one value")
    return values


def int_value(value, default=None):
    if value is None:
        return default
    if isinstance(value, string_types):
        return int(value, 0)
    return int(value)


def task_magic_kind(value):
    magic = int_value(value, 0) & 0xFFFF
    if magic == ANN_TASK_MAGIC:
        return "task"
    if magic == OFFLOAD_RESULT_MAGIC:
        return "offload_result"
    return "other"


def rewrite_udp_payload_for_offload(raw):
    if len(raw) < 2:
        return raw
    return be16(OFFLOAD_RESULT_MAGIC) + raw[2:]


def build_pattern_bytes(count, seed):
    parts = []
    index = 0
    while index < count:
        parts.append(_byte_chr((seed + index) & 0xFF))
        index += 1
    return _join_bytes(parts)


def ipv4_header_checksum(raw):
    total = 0
    length = len(raw)
    index = 0
    while index < length:
        word = (_byte_ord(raw[index]) << 8)
        if index + 1 < length:
            word = word | _byte_ord(raw[index + 1])
        total = total + word
        total = (total & 0xFFFF) + (total >> 16)
        index += 2
    total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def _feature_hex_list(values):
    feature_hex = []
    for value in values:
        feature_hex.append("0x%04x" % (value & 0xFFFF))
    return feature_hex


def build_task_payload(
    task_magic,
    request_id,
    feature_count,
    task_type,
    emitted_feature_count,
    feature_seed,
    explicit_features,
):
    if explicit_features is not None:
        features = []
        for value in explicit_features:
            features.append(int(value) & 0xFFFF)
        if emitted_feature_count is None:
            emitted_feature_count = len(features)
    else:
        if emitted_feature_count is None:
            emitted_feature_count = feature_count
        features = feature_values(feature_seed, emitted_feature_count)

    payload_parts = []
    _append_bytes(payload_parts, be16(task_magic))
    _append_bytes(payload_parts, be16(request_id))
    _append_bytes(payload_parts, be16(feature_count))
    _append_bytes(payload_parts, be16(task_type))
    for value in features:
        _append_bytes(payload_parts, be16(value))

    payload = _join_bytes(payload_parts)
    metadata = {
        "task_magic": "0x%04x" % (task_magic & 0xFFFF),
        "request_id": "0x%04x" % (request_id & 0xFFFF),
        "feature_count_field": int(feature_count),
        "emitted_feature_count": int(emitted_feature_count),
        "task_type": "0x%04x" % (task_type & 0xFFFF),
        "feature_values_be16": _feature_hex_list(features),
        "udp_payload_hex": bytes_to_hex(payload),
    }
    return payload, metadata


def build_ipv4_header(protocol, src_ip, dst_ip, payload_len, ip_options_bytes):
    if (ip_options_bytes % 4) != 0:
        raise ValueError("IPv4 options bytes must be a multiple of 4")

    version = 4
    ihl_words = 5 + (ip_options_bytes // 4)
    total_len = 20 + ip_options_bytes + payload_len

    parts = []
    _append_bytes(parts, _byte_chr(((version & 0xF) << 4) | (ihl_words & 0xF)))
    _append_bytes(parts, _byte_chr(0x00))
    _append_bytes(parts, be16(total_len))
    _append_bytes(parts, be16(0x1234))
    _append_bytes(parts, be16(0x4000))
    _append_bytes(parts, _byte_chr(0x40))
    _append_bytes(parts, _byte_chr(protocol & 0xFF))
    _append_bytes(parts, be16(0x0000))
    _append_bytes(parts, ip_to_bytes(src_ip))
    _append_bytes(parts, ip_to_bytes(dst_ip))

    option_index = 0
    while option_index < ip_options_bytes:
        _append_bytes(parts, _byte_chr((0xE0 + option_index) & 0xFF))
        option_index += 1

    header_wo_checksum = _join_bytes(parts)
    checksum = ipv4_header_checksum(header_wo_checksum)
    return header_wo_checksum[:10] + be16(checksum) + header_wo_checksum[12:]


def build_ipv4_udp_frame(
    dst_mac,
    src_mac,
    src_ip,
    dst_ip,
    udp_src_port,
    udp_dst_port,
    udp_payload,
    ip_options_bytes,
):
    udp_len = 8 + len(udp_payload)
    ipv4_header = build_ipv4_header(IP_PROTOCOL_UDP, src_ip, dst_ip, udp_len, ip_options_bytes)
    udp_header = be16(udp_src_port) + be16(udp_dst_port) + be16(udp_len) + be16(0x0000)
    return mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(IPV4_ETHERTYPE) + ipv4_header + udp_header + udp_payload


def build_ipv4_tcp_frame(
    dst_mac,
    src_mac,
    src_ip,
    dst_ip,
    tcp_src_port,
    tcp_dst_port,
    tcp_payload,
    ip_options_bytes,
):
    ipv4_header = build_ipv4_header(IP_PROTOCOL_TCP, src_ip, dst_ip, 20 + len(tcp_payload), ip_options_bytes)
    tcp_header = (
        be16(tcp_src_port)
        + be16(tcp_dst_port)
        + be32(0x01020304)
        + be32(0x05060708)
        + _byte_chr(0x50)
        + _byte_chr(0x18)
        + be16(0x1000)
        + be16(0x0000)
        + be16(0x0000)
    )
    return mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(IPV4_ETHERTYPE) + ipv4_header + tcp_header + tcp_payload


def build_non_ipv4_frame(dst_mac, src_mac, ethertype, payload):
    return mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(ethertype) + payload


def build_short_ipv4_udp_prefix_frame(dst_mac, src_mac, src_ip):
    raw = []
    _append_bytes(raw, mac_to_bytes(dst_mac))
    _append_bytes(raw, mac_to_bytes(src_mac))
    _append_bytes(raw, be16(IPV4_ETHERTYPE))
    _append_bytes(raw, _byte_chr(0x45))
    _append_bytes(raw, _byte_chr(0x00))
    _append_bytes(raw, be16(0x0020))
    _append_bytes(raw, be16(0x1234))
    _append_bytes(raw, be16(0x4000))
    _append_bytes(raw, _byte_chr(0x40))
    _append_bytes(raw, _byte_chr(IP_PROTOCOL_UDP))
    _append_bytes(raw, be16(0x0000))
    _append_bytes(raw, ip_to_bytes(src_ip))
    _append_bytes(raw, _byte_chr(0xC0))
    _append_bytes(raw, _byte_chr(0xA8))
    return _join_bytes(raw)


def build_udp_ann_frame(
    dst_mac,
    src_mac,
    src_ip,
    dst_ip,
    udp_src_port,
    udp_dst_port,
    task_magic,
    request_id,
    feature_count,
    task_type,
    emitted_feature_count,
    feature_seed,
    explicit_features,
):
    payload, payload_metadata = build_task_payload(
        task_magic=task_magic,
        request_id=request_id,
        feature_count=feature_count,
        task_type=task_type,
        emitted_feature_count=emitted_feature_count,
        feature_seed=feature_seed,
        explicit_features=explicit_features,
    )
    frame = build_ipv4_udp_frame(
        dst_mac=dst_mac,
        src_mac=src_mac,
        src_ip=src_ip,
        dst_ip=dst_ip,
        udp_src_port=udp_src_port,
        udp_dst_port=udp_dst_port,
        udp_payload=payload,
        ip_options_bytes=0,
    )
    return frame, payload, payload_metadata


def build_opl_packet(raw_frame, src_port, dst_port_mask):
    internal_frame = _byte_chr(0x00) + _byte_chr(0x00) + raw_frame
    data_word_count = (len(internal_frame) + 7) // 8
    module_header = (
        ((dst_port_mask & 0xFFFF) << 48)
        | ((data_word_count & 0xFFFF) << 32)
        | ((src_port & 0xFFFF) << 16)
        | (len(internal_frame) & 0xFFFF)
    )
    words = [
        {
            "index": 0,
            "data": "0x%016x" % module_header,
            "ctrl": "0x%02x" % 0xFF,
            "data_int": module_header,
            "ctrl_int": 0xFF,
        }
    ]

    word_index = 0
    byte_index = 0
    while byte_index < len(internal_frame):
        valid_bytes = len(internal_frame) - byte_index
        if valid_bytes > 8:
            valid_bytes = 8
        packed_word = 0
        lane = 0
        while lane < valid_bytes:
            packed_word = packed_word | (_byte_ord(internal_frame[byte_index + lane]) << (56 - (lane * 8)))
            lane += 1
        if word_index == data_word_count - 1:
            ctrl_value = eop_ctrl(valid_bytes)
        else:
            ctrl_value = 0x00
        words.append(
            {
                "index": word_index + 1,
                "data": "0x%016x" % packed_word,
                "ctrl": "0x%02x" % ctrl_value,
                "data_int": packed_word,
                "ctrl_int": ctrl_value,
            }
        )
        byte_index += valid_bytes
        word_index += 1

    metadata = {
        "wire_len": len(raw_frame),
        "internal_frame_len": len(internal_frame),
        "internal_data_word_count": data_word_count,
        "expected_module_header": "0x%016x" % module_header,
        "opl_words": words,
    }
    return metadata


def render_opl_words_text(opl_words):
    lines = []
    for item in opl_words:
        lines.append("%03d %s %s" % (item["index"], item["data"], item["ctrl"]))
    return "\n".join(lines) + "\n"


def decode_task_payload(raw):
    info = {
        "payload_len": len(raw),
        "payload_hex": bytes_to_hex(raw),
    }
    if len(raw) < 8:
        info["decode_status"] = "short_payload"
        return info

    feature_values_u16 = []
    index = 8
    while index + 1 < len(raw):
        feature_values_u16.append(read_be16(raw[index:index + 2]))
        index += 2

    info.update(
        {
            "decode_status": "ok",
            "task_magic": "0x%04x" % read_be16(raw[0:2]),
            "task_magic_kind": task_magic_kind(read_be16(raw[0:2])),
            "request_id": "0x%04x" % read_be16(raw[2:4]),
            "feature_count_field": read_be16(raw[4:6]),
            "task_type": "0x%04x" % read_be16(raw[6:8]),
            "feature_values_be16": _feature_hex_list(feature_values_u16),
        }
    )
    return info


def selector_expected_action_for_wire_frame(raw):
    if len(raw) + 2 < 46:
        return ACTION_BYPASS
    if len(raw) < 14:
        return ACTION_BYPASS
    if read_be16(raw[12:14]) != IPV4_ETHERTYPE:
        return ACTION_BYPASS
    if len(raw) < 34:
        return ACTION_BYPASS

    version_ihl = _byte_ord(raw[14])
    version = (version_ihl >> 4) & 0xF
    ihl_words = version_ihl & 0xF
    if version != 4 or ihl_words != 5:
        return ACTION_BYPASS
    if _byte_ord(raw[23]) != IP_PROTOCOL_UDP:
        return ACTION_BYPASS

    ipv4_header_len = ihl_words * 4
    udp_base = 14 + ipv4_header_len
    if len(raw) < udp_base + 10:
        return ACTION_BYPASS

    udp_dst_port = read_be16(raw[udp_base + 2:udp_base + 4])
    task_magic = read_be16(raw[udp_base + 8:udp_base + 10])
    if udp_dst_port == ANN_UDP_DST_PORT and task_magic == ANN_TASK_MAGIC:
        return ACTION_OFFLOAD
    return ACTION_BYPASS


def decode_wire_frame(raw):
    info = {
        "wire_len": len(raw),
        "wire_frame_hex": bytes_to_hex(raw),
        "selector_expected_action": selector_expected_action_for_wire_frame(raw),
    }
    if len(raw) < 14:
        info["decode_status"] = "short_eth"
        return info

    ethertype = read_be16(raw[12:14])
    info["decode_status"] = "ok"
    info["dst_mac"] = bytes_to_mac(raw[0:6])
    info["src_mac"] = bytes_to_mac(raw[6:12])
    info["ethertype"] = "0x%04x" % ethertype

    if ethertype != IPV4_ETHERTYPE:
        return info

    if len(raw) < 34:
        info["ipv4_status"] = "short_ipv4"
        return info

    version_ihl = _byte_ord(raw[14])
    version = (version_ihl >> 4) & 0xF
    ihl_words = version_ihl & 0xF
    ipv4_header_len = ihl_words * 4
    info["ipv4_version"] = version
    info["ipv4_ihl_words"] = ihl_words
    info["ipv4_total_len"] = read_be16(raw[16:18])
    info["ipv4_protocol"] = "0x%02x" % _byte_ord(raw[23])
    info["src_ip"] = bytes_to_ip(raw[26:30])
    info["dst_ip"] = bytes_to_ip(raw[30:34])

    if len(raw) < 14 + ipv4_header_len:
        info["ipv4_status"] = "short_ipv4_options"
        return info

    if _byte_ord(raw[23]) != IP_PROTOCOL_UDP:
        return info

    udp_base = 14 + ipv4_header_len
    if len(raw) < udp_base + 8:
        info["udp_status"] = "short_udp"
        return info

    udp_len = read_be16(raw[udp_base + 4:udp_base + 6])
    udp_payload = raw[udp_base + 8:]
    info["udp_src_port"] = "0x%04x" % read_be16(raw[udp_base:udp_base + 2])
    info["udp_dst_port"] = "0x%04x" % read_be16(raw[udp_base + 2:udp_base + 4])
    info["udp_len"] = udp_len
    info["udp_payload_hex"] = bytes_to_hex(udp_payload)
    info["udp_payload"] = decode_task_payload(udp_payload)
    return info


def build_packet_artifacts(spec):
    packet_kind = spec.get("packet_kind", "udp_ann")
    dst_mac = spec.get("dst_mac", DEFAULT_DST_MAC)
    src_mac = spec.get("src_mac", DEFAULT_SRC_MAC)
    src_ip = spec.get("src_ip", DEFAULT_SRC_IP)
    dst_ip = spec.get("dst_ip", DEFAULT_DST_IP)
    src_port = int_value(spec.get("src_port", DEFAULT_SRC_PORT), DEFAULT_SRC_PORT) & 0xFFFF
    dst_port_mask = int_value(spec.get("dst_port_mask", DEFAULT_DST_PORT_MASK), DEFAULT_DST_PORT_MASK) & 0xFFFF
    ip_options_bytes = int_value(spec.get("ip_options_bytes", 0), 0)

    if packet_kind == "udp_ann":
        explicit_features = spec.get("explicit_features")
        frame, payload, payload_metadata = build_udp_ann_frame(
            dst_mac=dst_mac,
            src_mac=src_mac,
            src_ip=src_ip,
            dst_ip=dst_ip,
            udp_src_port=int_value(spec.get("udp_src_port", DEFAULT_UDP_SRC_PORT), DEFAULT_UDP_SRC_PORT) & 0xFFFF,
            udp_dst_port=int_value(spec.get("udp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF,
            task_magic=int_value(spec.get("task_magic", ANN_TASK_MAGIC), ANN_TASK_MAGIC) & 0xFFFF,
            request_id=int_value(spec.get("request_id", DEFAULT_REQUEST_ID), DEFAULT_REQUEST_ID) & 0xFFFF,
            feature_count=int_value(spec.get("feature_count", DEFAULT_FEATURE_COUNT), DEFAULT_FEATURE_COUNT),
            task_type=int_value(spec.get("task_type", DEFAULT_TASK_TYPE), DEFAULT_TASK_TYPE) & 0xFFFF,
            emitted_feature_count=int_value(spec.get("emitted_feature_count"), None),
            feature_seed=int_value(spec.get("feature_seed", DEFAULT_FEATURE_SEED), DEFAULT_FEATURE_SEED),
            explicit_features=explicit_features,
        )
        metadata = {
            "packet_kind": packet_kind,
            "dst_mac": dst_mac,
            "src_mac": src_mac,
            "src_ip": src_ip,
            "dst_ip": dst_ip,
            "udp_src_port": "0x%04x" % (int_value(spec.get("udp_src_port", DEFAULT_UDP_SRC_PORT), DEFAULT_UDP_SRC_PORT) & 0xFFFF),
            "udp_dst_port": "0x%04x" % (int_value(spec.get("udp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF),
            "src_port": "0x%04x" % src_port,
            "dst_port_mask": "0x%04x" % dst_port_mask,
        }
        metadata.update(payload_metadata)
        metadata["udp_payload_hex"] = bytes_to_hex(payload)
    elif packet_kind == "udp_raw":
        udp_payload = build_pattern_bytes(int(spec.get("payload_len", 16)), int(spec.get("payload_seed", 0x10)))
        frame = build_ipv4_udp_frame(
            dst_mac=dst_mac,
            src_mac=src_mac,
            src_ip=src_ip,
            dst_ip=dst_ip,
            udp_src_port=int_value(spec.get("udp_src_port", DEFAULT_UDP_SRC_PORT), DEFAULT_UDP_SRC_PORT) & 0xFFFF,
            udp_dst_port=int_value(spec.get("udp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF,
            udp_payload=udp_payload,
            ip_options_bytes=ip_options_bytes,
        )
        metadata = {
            "packet_kind": packet_kind,
            "dst_mac": dst_mac,
            "src_mac": src_mac,
            "src_ip": src_ip,
            "dst_ip": dst_ip,
            "udp_src_port": "0x%04x" % (int_value(spec.get("udp_src_port", DEFAULT_UDP_SRC_PORT), DEFAULT_UDP_SRC_PORT) & 0xFFFF),
            "udp_dst_port": "0x%04x" % (int_value(spec.get("udp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF),
            "payload_len": len(udp_payload),
            "payload_seed": int_value(spec.get("payload_seed", 0x10), 0x10),
            "udp_payload_hex": bytes_to_hex(udp_payload),
            "src_port": "0x%04x" % src_port,
            "dst_port_mask": "0x%04x" % dst_port_mask,
            "ip_options_bytes": ip_options_bytes,
        }
    elif packet_kind == "tcp":
        tcp_payload = build_pattern_bytes(int_value(spec.get("payload_len", 20), 20), int_value(spec.get("payload_seed", 0x20), 0x20))
        frame = build_ipv4_tcp_frame(
            dst_mac=dst_mac,
            src_mac=src_mac,
            src_ip=src_ip,
            dst_ip=dst_ip,
            tcp_src_port=int_value(spec.get("tcp_src_port", 0x5001), 0x5001) & 0xFFFF,
            tcp_dst_port=int_value(spec.get("tcp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF,
            tcp_payload=tcp_payload,
            ip_options_bytes=ip_options_bytes,
        )
        metadata = {
            "packet_kind": packet_kind,
            "dst_mac": dst_mac,
            "src_mac": src_mac,
            "src_ip": src_ip,
            "dst_ip": dst_ip,
            "tcp_src_port": "0x%04x" % (int_value(spec.get("tcp_src_port", 0x5001), 0x5001) & 0xFFFF),
            "tcp_dst_port": "0x%04x" % (int_value(spec.get("tcp_dst_port", ANN_UDP_DST_PORT), ANN_UDP_DST_PORT) & 0xFFFF),
            "payload_len": len(tcp_payload),
            "payload_seed": int_value(spec.get("payload_seed", 0x20), 0x20),
            "src_port": "0x%04x" % src_port,
            "dst_port_mask": "0x%04x" % dst_port_mask,
            "ip_options_bytes": ip_options_bytes,
        }
    elif packet_kind == "non_ipv4":
        payload = build_pattern_bytes(int_value(spec.get("payload_len", 32), 32), int_value(spec.get("payload_seed", 0x30), 0x30))
        ethertype = int_value(spec.get("ethertype", 0x0806), 0x0806) & 0xFFFF
        frame = build_non_ipv4_frame(dst_mac=dst_mac, src_mac=src_mac, ethertype=ethertype, payload=payload)
        metadata = {
            "packet_kind": packet_kind,
            "dst_mac": dst_mac,
            "src_mac": src_mac,
            "ethertype": "0x%04x" % ethertype,
            "payload_len": len(payload),
            "payload_seed": int_value(spec.get("payload_seed", 0x30), 0x30),
            "src_port": "0x%04x" % src_port,
            "dst_port_mask": "0x%04x" % dst_port_mask,
        }
    elif packet_kind == "short_ipv4_udp_prefix":
        frame = build_short_ipv4_udp_prefix_frame(dst_mac=dst_mac, src_mac=src_mac, src_ip=src_ip)
        metadata = {
            "packet_kind": packet_kind,
            "dst_mac": dst_mac,
            "src_mac": src_mac,
            "src_ip": src_ip,
            "src_port": "0x%04x" % src_port,
            "dst_port_mask": "0x%04x" % dst_port_mask,
        }
    else:
        raise ValueError("unsupported packet_kind '%s'" % packet_kind)

    opl_metadata = build_opl_packet(frame, src_port=src_port, dst_port_mask=dst_port_mask)
    metadata["wire_frame_hex"] = bytes_to_hex(frame)
    metadata["wire_len"] = len(frame)
    metadata["selector_expected_action"] = selector_expected_action_for_wire_frame(frame)
    metadata["name"] = spec.get("name", packet_kind)
    metadata.update(opl_metadata)

    if metadata.get("udp_payload_hex") is not None:
        expected_rx_payload = hex_to_bytes(metadata["udp_payload_hex"])
        if metadata["selector_expected_action"] == ACTION_OFFLOAD:
            expected_rx_payload = rewrite_udp_payload_for_offload(expected_rx_payload)
        metadata["expected_rx_kind"] = metadata["selector_expected_action"]
        metadata["expected_rx_udp_payload_hex"] = bytes_to_hex(expected_rx_payload)
        if len(expected_rx_payload) >= 2:
            metadata["expected_rx_magic"] = "0x%04x" % read_be16(expected_rx_payload[0:2])
            metadata["expected_rx_magic_kind"] = task_magic_kind(read_be16(expected_rx_payload[0:2]))
        else:
            metadata["expected_rx_magic"] = None
            metadata["expected_rx_magic_kind"] = None
    else:
        metadata["expected_rx_kind"] = metadata["selector_expected_action"]
        metadata["expected_rx_udp_payload_hex"] = None
        metadata["expected_rx_magic"] = None
        metadata["expected_rx_magic_kind"] = None
    return metadata


def decode_packet_blob(blob, blob_kind):
    if blob_kind == "wire":
        return decode_wire_frame(blob)
    if blob_kind == "udp_payload":
        return decode_task_payload(blob)
    raise ValueError("unsupported blob_kind '%s'" % blob_kind)


def write_pcap_single(filepath, raw_frame_bytes):
    import struct
    import time
    ts = int(time.time())
    pkt_len = len(raw_frame_bytes)
    global_header = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1)
    pkt_header = struct.pack("<IIII", ts, 0, pkt_len, pkt_len)
    with open(filepath, "wb") as f:
        f.write(global_header)
        f.write(pkt_header)
        f.write(raw_frame_bytes)
