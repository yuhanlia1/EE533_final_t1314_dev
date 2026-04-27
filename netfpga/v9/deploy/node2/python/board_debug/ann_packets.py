#!/usr/bin/env python

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


IPV4_ETHERTYPE = 0x0800
CUSTOM_ETHERTYPE = IPV4_ETHERTYPE
IP_PROTOCOL_UDP = 0x11
ANN_UDP_DST_PORT = 0x88B5
ANN_TASK_MAGIC = 0xA11E
ANN_RESULT_MAGIC = 0xA11F
ANN_RESULT_VERSION = 0x01
ANN_RESULT_TYPE_NN = 0x0002

DEFAULT_DST_MAC = "00:11:22:33:44:55"
DEFAULT_SRC_MAC = "66:77:88:99:aa:bb"
DEFAULT_SRC_IP = "192.168.1.1"
DEFAULT_DST_IP = "192.168.1.2"
DEFAULT_UDP_SRC_PORT = 0x4000
DEFAULT_UDP_DST_PORT = ANN_UDP_DST_PORT
DEFAULT_SRC_PORT = DEFAULT_UDP_SRC_PORT
DEFAULT_DST_PORT_MASK = DEFAULT_UDP_DST_PORT
DEFAULT_REQUEST_ID = 0x1234
DEFAULT_TASK_TYPE = 0x0000
DEFAULT_FEATURE_COUNT = 8
DEFAULT_FEATURE_SEED = 3


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
        parts.append(_byte_chr(value))
    if PY3:
        return bytes().join(parts)
    return "".join(parts)


def _append_bytes(parts, raw):
    if raw is None:
        return
    parts.append(raw)


def _raw_to_hex(raw):
    values = []
    for item in raw:
        values.append("%02x" % _byte_ord(item))
    return "".join(values)


def _replace_slice(raw, start, end, replacement):
    return raw[:start] + replacement + raw[end:]


class ParsedResultFrame(object):
    def __init__(
        self,
        dst_mac,
        src_mac,
        ip_src,
        ip_dst,
        udp_src_port,
        udp_dst_port,
        udp_checksum,
        request_id,
        result_status,
        result_type,
        result_len,
        result_data_0_u16,
        result_data_1_u16,
        result_data_0_s16,
        result_data_1_s16,
        predicted_class,
        predicted_score_s16,
        wire_frame_hex,
    ):
        self.dst_mac = dst_mac
        self.src_mac = src_mac
        self.ip_src = ip_src
        self.ip_dst = ip_dst
        self.udp_src_port = udp_src_port
        self.udp_dst_port = udp_dst_port
        self.udp_checksum = udp_checksum
        self.request_id = request_id
        self.result_status = result_status
        self.result_type = result_type
        self.result_len = result_len
        self.result_data_0_u16 = result_data_0_u16
        self.result_data_1_u16 = result_data_1_u16
        self.result_data_0_s16 = result_data_0_s16
        self.result_data_1_s16 = result_data_1_s16
        self.predicted_class = predicted_class
        self.predicted_score_s16 = predicted_score_s16
        self.wire_frame_hex = wire_frame_hex

    def to_json_dict(self):
        return {
            "frame_kind": "ann_result",
            "dst_mac": self.dst_mac,
            "src_mac": self.src_mac,
            "ethertype": "0x%04x" % IPV4_ETHERTYPE,
            "ip_src": self.ip_src,
            "ip_dst": self.ip_dst,
            "ip_protocol": "0x%02x" % IP_PROTOCOL_UDP,
            "udp_src_port": "0x%04x" % self.udp_src_port,
            "udp_dst_port": "0x%04x" % self.udp_dst_port,
            "udp_checksum": "0x%04x" % self.udp_checksum,
            "request_id": self.request_id,
            "result_status": "0x%02x" % self.result_status,
            "result_type": "0x%04x" % self.result_type,
            "result_len": self.result_len,
            "wire_result_data_0_u16": "0x%04x" % self.result_data_0_u16,
            "wire_result_data_1_u16": "0x%04x" % self.result_data_1_u16,
            "logits_s16": [self.result_data_0_s16, self.result_data_1_s16],
            "predicted_class": self.predicted_class,
            "predicted_score_s16": self.predicted_score_s16,
            "wire_frame_hex": self.wire_frame_hex,
        }


def mac_to_bytes(text):
    parts = text.split(":")
    if len(parts) != 6:
        raise ValueError("invalid MAC address '%s'" % text)
    values = []
    for part in parts:
        values.append(int(part, 16))
    return _join_bytes(values)


def bytes_to_mac(raw):
    if len(raw) != 6:
        raise ValueError("expected 6-byte MAC address, got %d bytes" % len(raw))
    values = []
    for item in raw:
        values.append("%02x" % _byte_ord(item))
    return ":".join(values)


def ipv4_to_bytes(text):
    parts = text.split(".")
    if len(parts) != 4:
        raise ValueError("invalid IPv4 address '%s'" % text)
    values = []
    for part in parts:
        value = int(part, 10)
        if value < 0 or value > 255:
            raise ValueError("invalid IPv4 octet '%s' in '%s'" % (part, text))
        values.append(value)
    return _join_bytes(values)


def bytes_to_ipv4(raw):
    if len(raw) != 4:
        raise ValueError("expected 4-byte IPv4 address, got %d bytes" % len(raw))
    values = []
    for item in raw:
        values.append(str(_byte_ord(item)))
    return ".".join(values)


def be16(value):
    return _join_bytes(((value >> 8) & 0xFF, value & 0xFF))


def be32(value):
    return _join_bytes(
        (
            (value >> 24) & 0xFF,
            (value >> 16) & 0xFF,
            (value >> 8) & 0xFF,
            value & 0xFF,
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


def u16_to_s16(value):
    value = value & 0xFFFF
    if value & 0x8000:
        return value - 0x10000
    return value


def s16_to_u16(value):
    return value & 0xFFFF


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
    for raw_token in text.split(","):
        token = raw_token.strip().strip("\"'")
        if token:
            values.append(int(token, 0) & 0xFFFF)
    if not values:
        raise ValueError("explicit feature list must contain at least one value")
    return values


def ipv4_header_checksum(header):
    if len(header) % 2 != 0:
        raise ValueError("IPv4 header length must be even, got %d" % len(header))
    total = 0
    index = 0
    while index < len(header):
        total += read_be16(header[index:index + 2])
        index += 2
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def _build_ipv4_header(src_ip, dst_ip, total_len):
    parts = []
    _append_bytes(parts, _byte_chr(0x45))
    _append_bytes(parts, _byte_chr(0x00))
    _append_bytes(parts, be16(total_len))
    _append_bytes(parts, be16(0x1234))
    _append_bytes(parts, be16(0x4000))
    _append_bytes(parts, _byte_chr(0x40))
    _append_bytes(parts, _byte_chr(IP_PROTOCOL_UDP))
    _append_bytes(parts, be16(0x0000))
    _append_bytes(parts, ipv4_to_bytes(src_ip))
    _append_bytes(parts, ipv4_to_bytes(dst_ip))
    if PY3:
        header = bytes().join(parts)
    else:
        header = "".join(parts)
    checksum = ipv4_header_checksum(header)
    return _replace_slice(header, 10, 12, be16(checksum))


def _build_udp_payload(task_magic, request_id, feature_count, task_type, features):
    payload_parts = []
    _append_bytes(payload_parts, be16(task_magic))
    _append_bytes(payload_parts, be16(request_id))
    _append_bytes(payload_parts, be16(feature_count))
    _append_bytes(payload_parts, be16(task_type))
    for value in features:
        _append_bytes(payload_parts, be16(value))
    if PY3:
        return bytes().join(payload_parts)
    return "".join(payload_parts)


def _predict_class(result_data_0_s16, result_data_1_s16, result_mode):
    if result_mode == "compact_class_score":
        return None, result_data_1_s16
    if result_data_0_s16 >= result_data_1_s16:
        return 0, result_data_0_s16
    return 1, result_data_1_s16


def _parse_udp_frame_fields(frame):
    if len(frame) < 14 + 20 + 8:
        raise ValueError("UDP frame too short: %d bytes" % len(frame))

    ethertype = read_be16(frame[12:14])
    if ethertype != IPV4_ETHERTYPE:
        raise ValueError("unexpected EtherType in UDP frame: 0x%04x" % ethertype)

    version_ihl = _byte_ord(frame[14])
    version = (version_ihl >> 4) & 0x0F
    ihl_words = version_ihl & 0x0F
    ip_header_len = ihl_words * 4

    if version != 4:
        raise ValueError("unexpected IP version %d" % version)
    if ihl_words < 5:
        raise ValueError("invalid IPv4 IHL %d" % ihl_words)
    if len(frame) < 14 + ip_header_len + 8:
        raise ValueError("frame too short for IPv4 header length %d" % ip_header_len)

    protocol = _byte_ord(frame[14 + 9])
    if protocol != IP_PROTOCOL_UDP:
        raise ValueError("unexpected IPv4 protocol 0x%02x" % protocol)

    total_length = read_be16(frame[14 + 2:14 + 4])
    if total_length < ip_header_len + 8:
        raise ValueError("invalid IPv4 total length %d" % total_length)
    if len(frame) < 14 + total_length:
        raise ValueError("truncated IPv4 frame: total_length=%d actual=%d" % (total_length, len(frame) - 14))

    udp_offset = 14 + ip_header_len
    udp_length = read_be16(frame[udp_offset + 4:udp_offset + 6])
    if udp_length < 8:
        raise ValueError("invalid UDP length %d" % udp_length)
    if len(frame) < udp_offset + udp_length:
        raise ValueError("truncated UDP frame: udp_length=%d actual=%d" % (udp_length, len(frame) - udp_offset))

    payload_offset = udp_offset + 8
    payload_end = udp_offset + udp_length
    payload = frame[payload_offset:payload_end]

    return {
        "dst_mac": bytes_to_mac(frame[0:6]),
        "src_mac": bytes_to_mac(frame[6:12]),
        "ethertype": ethertype,
        "ip_src": bytes_to_ipv4(frame[14 + 12:14 + 16]),
        "ip_dst": bytes_to_ipv4(frame[14 + 16:14 + 20]),
        "ip_header_len": ip_header_len,
        "ip_total_length": total_length,
        "ip_protocol": protocol,
        "udp_src_port": read_be16(frame[udp_offset:udp_offset + 2]),
        "udp_dst_port": read_be16(frame[udp_offset + 2:udp_offset + 4]),
        "udp_length": udp_length,
        "udp_checksum": read_be16(frame[udp_offset + 6:udp_offset + 8]),
        "payload": payload,
        "payload_offset": payload_offset,
        "wire_frame_hex": _raw_to_hex(frame),
    }


def build_task_frame(
    dst_mac,
    src_mac,
    src_ip,
    dst_ip,
    task_magic,
    request_id,
    feature_count,
    task_type,
    emitted_feature_count,
    feature_seed,
    explicit_features,
    udp_src_port,
    udp_dst_port,
):
    if explicit_features is not None:
        features = []
        for value in explicit_features:
            features.append(int(value) & 0xFFFF)
        emitted_feature_count = len(features)
        feature_count = len(features)
    else:
        if emitted_feature_count is None:
            actual_emitted = feature_count
        else:
            actual_emitted = emitted_feature_count
        features = feature_values(feature_seed, actual_emitted)
        emitted_feature_count = actual_emitted

    payload = _build_udp_payload(task_magic, request_id, feature_count, task_type, features)
    udp_len = 8 + len(payload)
    ip_total_len = 20 + udp_len
    ip_header = _build_ipv4_header(src_ip, dst_ip, ip_total_len)
    udp_header = be16(udp_src_port) + be16(udp_dst_port) + be16(udp_len) + be16(0x0000)
    wire_frame = mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(IPV4_ETHERTYPE) + ip_header + udp_header + payload

    feature_hex = []
    for value in features:
        feature_hex.append("0x%04x" % value)

    if explicit_features is not None:
        feature_source = "explicit"
    else:
        feature_source = "seed:%d" % feature_seed

    metadata = {
        "frame_kind": "ann_task",
        "dst_mac": dst_mac,
        "src_mac": src_mac,
        "ethertype": "0x%04x" % IPV4_ETHERTYPE,
        "ip_src": src_ip,
        "ip_dst": dst_ip,
        "ip_protocol": "0x%02x" % IP_PROTOCOL_UDP,
        "ip_total_length": ip_total_len,
        "udp_src_port": "0x%04x" % udp_src_port,
        "udp_dst_port": "0x%04x" % udp_dst_port,
        "udp_length": udp_len,
        "udp_checksum": "0x0000",
        "task_magic": "0x%04x" % task_magic,
        "request_id": "0x%04x" % request_id,
        "feature_count_field": feature_count,
        "emitted_feature_count": emitted_feature_count,
        "task_type": "0x%04x" % task_type,
        "feature_values_be16": feature_hex,
        "feature_source": feature_source,
        "wire_len": len(wire_frame),
        "payload_len": len(payload),
        "wire_frame_hex": _raw_to_hex(wire_frame),
    }
    return wire_frame, metadata


def build_task_frame_defaults(
    dst_mac=DEFAULT_DST_MAC,
    src_mac=DEFAULT_SRC_MAC,
    src_ip=DEFAULT_SRC_IP,
    dst_ip=DEFAULT_DST_IP,
    task_magic=ANN_TASK_MAGIC,
    request_id=DEFAULT_REQUEST_ID,
    feature_count=DEFAULT_FEATURE_COUNT,
    task_type=DEFAULT_TASK_TYPE,
    emitted_feature_count=None,
    feature_seed=DEFAULT_FEATURE_SEED,
    explicit_features=None,
    udp_src_port=DEFAULT_UDP_SRC_PORT,
    udp_dst_port=DEFAULT_UDP_DST_PORT,
):
    return build_task_frame(
        dst_mac,
        src_mac,
        src_ip,
        dst_ip,
        task_magic,
        request_id,
        feature_count,
        task_type,
        emitted_feature_count,
        feature_seed,
        explicit_features,
        udp_src_port,
        udp_dst_port,
    )


def rewrite_result_frame(
    frame,
    request_id,
    result_data_0,
    result_data_1,
    result_status=0x00,
    result_type=ANN_RESULT_TYPE_NN,
    result_len=4,
):
    fields = _parse_udp_frame_fields(frame)
    payload = fields["payload"]
    if len(payload) < 14:
        raise ValueError("ANN task payload too short for in-place result rewrite: %d bytes" % len(payload))

    rewritten = frame
    payload_offset = fields["payload_offset"]
    rewritten = _replace_slice(rewritten, payload_offset + 0, payload_offset + 2, be16(ANN_RESULT_MAGIC))
    rewritten = _replace_slice(rewritten, payload_offset + 2, payload_offset + 3, _byte_chr(ANN_RESULT_VERSION))
    rewritten = _replace_slice(rewritten, payload_offset + 3, payload_offset + 4, _byte_chr(result_status & 0xFF))
    rewritten = _replace_slice(rewritten, payload_offset + 4, payload_offset + 6, be16(request_id))
    rewritten = _replace_slice(rewritten, payload_offset + 6, payload_offset + 8, be16(result_type))
    rewritten = _replace_slice(rewritten, payload_offset + 8, payload_offset + 10, be16(result_len))
    rewritten = _replace_slice(rewritten, payload_offset + 10, payload_offset + 12, be16(s16_to_u16(result_data_0)))
    rewritten = _replace_slice(rewritten, payload_offset + 12, payload_offset + 14, be16(s16_to_u16(result_data_1)))
    return rewritten


def build_result_frame(
    request_id,
    result_data_0,
    result_data_1,
    dst_mac=DEFAULT_DST_MAC,
    src_mac=DEFAULT_SRC_MAC,
    src_ip=DEFAULT_SRC_IP,
    dst_ip=DEFAULT_DST_IP,
    udp_src_port=DEFAULT_UDP_SRC_PORT,
    udp_dst_port=DEFAULT_UDP_DST_PORT,
    result_status=0x00,
    result_type=ANN_RESULT_TYPE_NN,
    result_len=4,
):
    task_frame, _ignored = build_task_frame_defaults(
        dst_mac=dst_mac,
        src_mac=src_mac,
        src_ip=src_ip,
        dst_ip=dst_ip,
        request_id=request_id,
        udp_src_port=udp_src_port,
        udp_dst_port=udp_dst_port,
    )
    return rewrite_result_frame(
        task_frame,
        request_id=request_id,
        result_data_0=result_data_0,
        result_data_1=result_data_1,
        result_status=result_status,
        result_type=result_type,
        result_len=result_len,
    )


def parse_result_frame(frame, result_mode="legacy_logits"):
    fields = _parse_udp_frame_fields(frame)
    if fields["udp_dst_port"] != ANN_UDP_DST_PORT:
        raise ValueError("unexpected ANN UDP destination port: 0x%04x" % fields["udp_dst_port"])

    payload = fields["payload"]
    if len(payload) < 14:
        raise ValueError("ANN result payload too short: %d bytes" % len(payload))

    magic = read_be16(payload[0:2])
    if magic != ANN_RESULT_MAGIC:
        raise ValueError("unexpected ANN result magic: 0x%04x" % magic)

    version = _byte_ord(payload[2])
    if version != ANN_RESULT_VERSION:
        raise ValueError("unexpected ANN result version: 0x%02x" % version)

    result_data_0_u16 = read_be16(payload[10:12])
    result_data_1_u16 = read_be16(payload[12:14])
    result_data_0_s16 = u16_to_s16(result_data_0_u16)
    result_data_1_s16 = u16_to_s16(result_data_1_u16)

    if result_mode == "compact_class_score":
        predicted_class = result_data_0_u16
        predicted_score = result_data_1_s16
    else:
        predicted_class, predicted_score = _predict_class(result_data_0_s16, result_data_1_s16, result_mode)

    return ParsedResultFrame(
        dst_mac=fields["dst_mac"],
        src_mac=fields["src_mac"],
        ip_src=fields["ip_src"],
        ip_dst=fields["ip_dst"],
        udp_src_port=fields["udp_src_port"],
        udp_dst_port=fields["udp_dst_port"],
        udp_checksum=fields["udp_checksum"],
        request_id=read_be16(payload[4:6]),
        result_status=_byte_ord(payload[3]),
        result_type=read_be16(payload[6:8]),
        result_len=read_be16(payload[8:10]),
        result_data_0_u16=result_data_0_u16,
        result_data_1_u16=result_data_1_u16,
        result_data_0_s16=result_data_0_s16,
        result_data_1_s16=result_data_1_s16,
        predicted_class=predicted_class,
        predicted_score_s16=predicted_score,
        wire_frame_hex=fields["wire_frame_hex"],
    )


def inspect_ann_frame(frame, result_mode="legacy_logits"):
    fields = _parse_udp_frame_fields(frame)
    payload = fields["payload"]
    info = {
        "frame_kind": "udp_unknown",
        "dst_mac": fields["dst_mac"],
        "src_mac": fields["src_mac"],
        "ethertype": "0x%04x" % fields["ethertype"],
        "ip_src": fields["ip_src"],
        "ip_dst": fields["ip_dst"],
        "ip_protocol": "0x%02x" % fields["ip_protocol"],
        "udp_src_port": "0x%04x" % fields["udp_src_port"],
        "udp_dst_port": "0x%04x" % fields["udp_dst_port"],
        "udp_length": fields["udp_length"],
        "udp_checksum": "0x%04x" % fields["udp_checksum"],
        "payload_len": len(payload),
        "payload_hex": _raw_to_hex(payload),
        "wire_frame_hex": fields["wire_frame_hex"],
    }

    if len(payload) < 2:
        return info

    payload_magic = read_be16(payload[0:2])
    info["payload_magic"] = "0x%04x" % payload_magic

    if len(payload) >= 8:
        info["request_id"] = read_be16(payload[2:4])
        info["feature_count_field"] = read_be16(payload[4:6])
        info["task_type"] = "0x%04x" % read_be16(payload[6:8])
        if payload_magic == ANN_TASK_MAGIC:
            info["frame_kind"] = "ann_task"
            return info

    if payload_magic == ANN_RESULT_MAGIC and len(payload) >= 14:
        parsed = parse_result_frame(frame, result_mode)
        return parsed.to_json_dict()

    return info


def build_task_frame_compat(**kwargs):
    return build_task_frame_defaults(**kwargs)
