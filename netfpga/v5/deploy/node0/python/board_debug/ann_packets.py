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


CUSTOM_ETHERTYPE = 0x88B5
ANN_TASK_MAGIC = 0xA11E
ANN_RESULT_MAGIC = 0xA11F
ANN_RESULT_VERSION = 0x01
ANN_RESULT_TYPE_NN = 0x0002

DEFAULT_DST_MAC = "0b:ad:c0:de:00:01"
DEFAULT_SRC_MAC = "f0:0d:ca:fe:00:02"
DEFAULT_SRC_PORT = 0x0001
DEFAULT_DST_PORT_MASK = 0x0008
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


class ParsedResultFrame(object):
    def __init__(
        self,
        dst_mac,
        src_mac,
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
            "dst_mac": self.dst_mac,
            "src_mac": self.src_mac,
            "ethertype": "0x%04x" % CUSTOM_ETHERTYPE,
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


def be16(value):
    return _join_bytes(((value >> 8) & 0xFF, value & 0xFF))


def read_be16(raw):
    if len(raw) != 2:
        raise ValueError("expected 2 bytes, got %d" % len(raw))
    return (_byte_ord(raw[0]) << 8) | _byte_ord(raw[1])


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


def build_task_frame(
    dst_mac,
    src_mac,
    task_magic,
    request_id,
    feature_count,
    task_type,
    emitted_feature_count,
    feature_seed,
    explicit_features,
    src_port,
    dst_port_mask,
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

    payload_parts = []
    _append_bytes(payload_parts, be16(task_magic))
    _append_bytes(payload_parts, be16(request_id))
    _append_bytes(payload_parts, be16(feature_count))
    _append_bytes(payload_parts, be16(task_type))
    for value in features:
        _append_bytes(payload_parts, be16(value))

    if PY3:
        payload = bytes().join(payload_parts)
    else:
        payload = "".join(payload_parts)
    wire_frame = mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(CUSTOM_ETHERTYPE) + payload
    internal_frame = _join_bytes((0x00, 0x00)) + wire_frame
    data_word_count = (len(internal_frame) + 7) // 8
    module_header = (
        ((dst_port_mask & 0xFFFF) << 48)
        | ((data_word_count & 0xFFFF) << 32)
        | ((src_port & 0xFFFF) << 16)
        | (len(internal_frame) & 0xFFFF)
    )

    feature_hex = []
    for value in features:
        feature_hex.append("0x%04x" % value)

    if explicit_features is not None:
        feature_source = "explicit"
    else:
        feature_source = "seed:%d" % feature_seed

    metadata = {
        "dst_mac": dst_mac,
        "src_mac": src_mac,
        "ethertype": "0x%04x" % CUSTOM_ETHERTYPE,
        "task_magic": "0x%04x" % task_magic,
        "request_id": "0x%04x" % request_id,
        "feature_count_field": feature_count,
        "emitted_feature_count": emitted_feature_count,
        "task_type": "0x%04x" % task_type,
        "src_port": "0x%04x" % src_port,
        "dst_port_mask": "0x%04x" % dst_port_mask,
        "feature_values_be16": feature_hex,
        "feature_source": feature_source,
        "wire_len": len(wire_frame),
        "internal_frame_len": len(internal_frame),
        "internal_data_word_count": data_word_count,
        "expected_module_header": "0x%016x" % module_header,
        "wire_frame_hex": _raw_to_hex(wire_frame),
    }
    return wire_frame, metadata


def build_task_frame_defaults(
    dst_mac=DEFAULT_DST_MAC,
    src_mac=DEFAULT_SRC_MAC,
    task_magic=ANN_TASK_MAGIC,
    request_id=DEFAULT_REQUEST_ID,
    feature_count=DEFAULT_FEATURE_COUNT,
    task_type=DEFAULT_TASK_TYPE,
    emitted_feature_count=None,
    feature_seed=DEFAULT_FEATURE_SEED,
    explicit_features=None,
    src_port=DEFAULT_SRC_PORT,
    dst_port_mask=DEFAULT_DST_PORT_MASK,
):
    return build_task_frame(
        dst_mac,
        src_mac,
        task_magic,
        request_id,
        feature_count,
        task_type,
        emitted_feature_count,
        feature_seed,
        explicit_features,
        src_port,
        dst_port_mask,
    )


def build_result_frame(
    request_id,
    result_data_0,
    result_data_1,
    dst_mac=DEFAULT_DST_MAC,
    src_mac=DEFAULT_SRC_MAC,
    result_status=0x00,
    result_type=ANN_RESULT_TYPE_NN,
    result_len=4,
):
    payload_parts = []
    _append_bytes(payload_parts, be16(ANN_RESULT_MAGIC))
    _append_bytes(payload_parts, _byte_chr(ANN_RESULT_VERSION))
    _append_bytes(payload_parts, _byte_chr(result_status & 0xFF))
    _append_bytes(payload_parts, be16(request_id))
    _append_bytes(payload_parts, be16(result_type))
    _append_bytes(payload_parts, be16(result_len))
    _append_bytes(payload_parts, be16(s16_to_u16(result_data_0)))
    _append_bytes(payload_parts, be16(s16_to_u16(result_data_1)))
    _append_bytes(payload_parts, _join_bytes((0x00, 0x00)))
    if PY3:
        payload = bytes().join(payload_parts)
    else:
        payload = "".join(payload_parts)
    return mac_to_bytes(dst_mac) + mac_to_bytes(src_mac) + be16(CUSTOM_ETHERTYPE) + payload


def parse_result_frame(frame, result_mode):
    if len(frame) < 30:
        raise ValueError("ANN result frame too short: %d bytes" % len(frame))

    ethertype = read_be16(frame[12:14])
    if ethertype != CUSTOM_ETHERTYPE:
        raise ValueError("unexpected EtherType in ANN frame: 0x%04x" % ethertype)

    payload = frame[14:]
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
        if result_data_0_s16 >= result_data_1_s16:
            predicted_class = 0
            predicted_score = result_data_0_s16
        else:
            predicted_class = 1
            predicted_score = result_data_1_s16

    return ParsedResultFrame(
        dst_mac=bytes_to_mac(frame[0:6]),
        src_mac=bytes_to_mac(frame[6:12]),
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
        wire_frame_hex=_raw_to_hex(frame),
    )


def build_task_frame_compat(**kwargs):
    return build_task_frame_defaults(**kwargs)
