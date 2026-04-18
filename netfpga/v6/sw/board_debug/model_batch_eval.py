#!/usr/bin/env python

import socket
import sys
import time

try:
    import json
except ImportError:
    json = None

from board_debug.ann_packets import (
    DEFAULT_DST_MAC,
    DEFAULT_DST_PORT_MASK,
    DEFAULT_REQUEST_ID,
    DEFAULT_SRC_MAC,
    DEFAULT_SRC_PORT,
    DEFAULT_TASK_TYPE,
    build_task_frame_defaults,
    parse_result_frame,
)

try:
    from board_debug import json_compat
except ImportError:
    import json_compat


try:
    TimeoutError
except NameError:
    class TimeoutError(Exception):
        pass


def _read_json(path):
    handle = open(path, "r")
    try:
        text = handle.read()
    finally:
        handle.close()

    if json is not None:
        try:
            return json.loads(text)
        except:
            pass
    try:
        return json_compat.loads(text)
    except:
        exc = sys.exc_info()[1]
        raise ValueError("failed to parse JSON %s: %s" % (path, exc))


def load_test_vectors(path):
    raw = _read_json(path)
    if not isinstance(raw, list):
        raise ValueError("%s must contain a JSON list" % path)
    vectors = []
    index = 0
    while index < len(raw):
        entry = raw[index]
        if not isinstance(entry, dict):
            raise ValueError("%s: vector %d must be an object" % (path, index))
        if "name" in entry:
            name = str(entry.get("name"))
        else:
            name = "sample%d" % index
        values = entry.get("input_s16", entry.get("input"))
        if not isinstance(values, list):
            raise ValueError("%s: vector %d missing input_s16/input list" % (path, index))
        parsed_values = []
        value_index = 0
        while value_index < len(values):
            parsed_values.append(int(values[value_index]))
            value_index += 1
        vectors.append({"name": name, "input_s16": parsed_values})
        index += 1
    return vectors


def load_expected_outputs(path):
    raw = _read_json(path)
    if not isinstance(raw, list):
        raise ValueError("%s must contain a JSON list" % path)
    rows = []
    index = 0
    while index < len(raw):
        entry = raw[index]
        if not isinstance(entry, dict):
            raise ValueError("%s: row %d must be an object" % (path, index))
        if "name" in entry:
            name = str(entry.get("name"))
        else:
            name = "sample%d" % index
        rows.append(
            {
                "name": name,
                "predicted_class": int(entry["predicted_class"]),
                "wire_result_data_0_u16": int(str(entry["wire_result_data_0_u16"]), 0),
                "wire_result_data_1_u16": int(str(entry["wire_result_data_1_u16"]), 0),
                "result_mode": str(entry.get("result_mode", "legacy_logits")),
            }
        )
        index += 1
    return rows


def load_observed_outputs(path):
    raw = _read_json(path)
    if not isinstance(raw, list):
        raise ValueError("%s must contain a JSON list" % path)
    rows = []
    index = 0
    while index < len(raw):
        entry = raw[index]
        if not isinstance(entry, dict):
            raise ValueError("%s: row %d must be an object" % (path, index))
        if "name" in entry:
            name = str(entry.get("name"))
        else:
            name = "sample%d" % index
        rows.append(
            {
                "name": name,
                "predicted_class": int(entry["predicted_class"]),
                "wire_result_data_0_u16": int(str(entry["wire_result_data_0_u16"]), 0),
                "wire_result_data_1_u16": int(str(entry["wire_result_data_1_u16"]), 0),
                "request_id": int(entry.get("request_id", index)),
            }
        )
        index += 1
    return rows


def compare_expected_observed(expected_rows, observed_rows):
    expected_by_name = {}
    observed_by_name = {}
    names = []

    for row in expected_rows:
        key = str(row["name"])
        expected_by_name[key] = row
        names.append(key)

    for row in observed_rows:
        key = str(row["name"])
        observed_by_name[key] = row

    mismatches = []
    missing_samples = []
    confusion = {}
    class_matches = 0
    wire_matches = 0

    for name in names:
        expected = expected_by_name[name]
        observed = observed_by_name.get(name)
        if observed is None:
            missing_samples.append(name)
            mismatches.append({"name": name, "reason": "missing_observation"})
            continue

        exp_class = int(expected["predicted_class"])
        obs_class = int(observed["predicted_class"])
        confusion_key = "%d->%d" % (exp_class, obs_class)
        confusion[confusion_key] = confusion.get(confusion_key, 0) + 1

        exp_wire0 = int(str(expected["wire_result_data_0_u16"]), 0)
        exp_wire1 = int(str(expected["wire_result_data_1_u16"]), 0)
        obs_wire0 = int(str(observed["wire_result_data_0_u16"]), 0)
        obs_wire1 = int(str(observed["wire_result_data_1_u16"]), 0)

        if exp_class == obs_class:
            class_matches += 1
        if exp_wire0 == obs_wire0 and exp_wire1 == obs_wire1:
            wire_matches += 1
        else:
            mismatches.append(
                {
                    "name": name,
                    "reason": "wire_mismatch",
                    "expected_class": exp_class,
                    "observed_class": obs_class,
                    "expected_wire_result_data_0_u16": "0x%04x" % exp_wire0,
                    "expected_wire_result_data_1_u16": "0x%04x" % exp_wire1,
                    "observed_wire_result_data_0_u16": "0x%04x" % obs_wire0,
                    "observed_wire_result_data_1_u16": "0x%04x" % obs_wire1,
                }
            )

    sample_count = len(expected_rows)
    observed_count = len(observed_rows)
    if sample_count:
        class_accuracy = float(class_matches) / float(sample_count)
        wire_accuracy = float(wire_matches) / float(sample_count)
    else:
        class_accuracy = 0.0
        wire_accuracy = 0.0

    return {
        "sample_count": sample_count,
        "observed_count": observed_count,
        "matched_count": sample_count - len(missing_samples),
        "class_matches": class_matches,
        "wire_matches": wire_matches,
        "class_accuracy": class_accuracy,
        "wire_accuracy": wire_accuracy,
        "missing_samples": missing_samples,
        "mismatches": mismatches,
        "confusion_matrix": confusion,
    }


def _recv_matching_result_with_mode(sock, request_id, timeout_ms, result_mode):
    deadline = time.time() + (float(timeout_ms) / 1000.0)
    while time.time() < deadline:
        remaining = deadline - time.time()
        if remaining < 0.001:
            remaining = 0.001
        sock.settimeout(remaining)
        frame = sock.recv(2048)
        try:
            parsed = parse_result_frame(frame, result_mode)
        except ValueError:
            continue
        if parsed.request_id != request_id:
            continue
        row = parsed.to_json_dict()
        row["request_id"] = parsed.request_id
        return row
    raise TimeoutError("timed out waiting for ANN result request_id=0x%04x" % request_id)


def run_live_batch(
    iface,
    test_vectors,
    expected_rows,
    request_id_base=DEFAULT_REQUEST_ID,
    timeout_ms=1000,
    interval_ms=50,
    dst_mac=DEFAULT_DST_MAC,
    src_mac=DEFAULT_SRC_MAC,
    src_port=DEFAULT_SRC_PORT,
    dst_port_mask=DEFAULT_DST_PORT_MASK,
    task_type=DEFAULT_TASK_TYPE,
):
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    try:
        sock.bind((iface, 0))
        observed_rows = []
        if expected_rows:
            result_mode = str(expected_rows[0].get("result_mode", "legacy_logits"))
        else:
            result_mode = "legacy_logits"
        index = 0
        while index < len(test_vectors):
            vector = test_vectors[index]
            request_id = (request_id_base + index) & 0xFFFF
            frame, _ignored = build_task_frame_defaults(
                dst_mac=dst_mac,
                src_mac=src_mac,
                request_id=request_id,
                explicit_features=[int(value) for value in vector["input_s16"]],
                src_port=src_port,
                dst_port_mask=dst_port_mask,
                task_type=task_type,
            )
            sock.send(frame)
            observed = _recv_matching_result_with_mode(sock, request_id, timeout_ms, result_mode)
            observed["name"] = str(vector["name"])
            observed_rows.append(observed)
            if index + 1 < len(test_vectors):
                time.sleep(float(interval_ms) / 1000.0)
            index += 1
    finally:
        sock.close()

    summary = compare_expected_observed(expected_rows, observed_rows)
    return summary, observed_rows
