#!/usr/bin/env python

import struct
import time


PCAP_MAGIC_USEC_LE = b"\xd4\xc3\xb2\xa1"
PCAP_MAGIC_USEC_BE = b"\xa1\xb2\xc3\xd4"
PCAP_MAGIC_NSEC_LE = b"\x4d\x3c\xb2\xa1"
PCAP_MAGIC_NSEC_BE = b"\xa1\xb2\x3c\x4d"
PCAP_LINKTYPE_ETHERNET = 1


def _record_timestamp_fields(record, default_base_sec, default_ts_usec):
    if isinstance(record, dict):
        if record.get("timestamp_seconds") is not None:
            timestamp_seconds = float(record["timestamp_seconds"])
            ts_sec = int(timestamp_seconds)
            ts_usec = int(round((timestamp_seconds - float(ts_sec)) * 1000000.0))
            if ts_usec >= 1000000:
                ts_sec += ts_usec // 1000000
                ts_usec = ts_usec % 1000000
            return ts_sec, ts_usec
        if record.get("ts_sec") is not None and record.get("ts_sub") is not None:
            return int(record["ts_sec"]), int(record["ts_sub"])
    return int(default_base_sec), int(default_ts_usec)


def _record_frame_bytes(record):
    if isinstance(record, dict):
        return bytes(record["frame"])
    return bytes(record)


def write_pcap(path, frames, linktype=PCAP_LINKTYPE_ETHERNET, snaplen=65535):
    handle = open(path, "wb")
    try:
        handle.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, snaplen, linktype))
        ts_usec = 0
        base_sec = int(time.time())
        for record in frames:
            ts_sec, ts_usec_value = _record_timestamp_fields(record, base_sec, ts_usec)
            raw = _record_frame_bytes(record)
            handle.write(struct.pack("<IIII", ts_sec, ts_usec_value, len(raw), len(raw)))
            handle.write(raw)
            ts_usec += 1
    finally:
        handle.close()


def read_pcap(path):
    records = read_pcap_records(path)
    return [record["frame"] for record in records]


def read_pcap_records(path):
    handle = open(path, "rb")
    try:
        header = handle.read(24)
        if len(header) != 24:
            raise ValueError("%s: truncated pcap global header" % path)

        magic = header[0:4]
        if magic == PCAP_MAGIC_USEC_LE or magic == PCAP_MAGIC_NSEC_LE:
            endian = "<"
            time_scale = 1000000 if magic == PCAP_MAGIC_USEC_LE else 1000000000
        elif magic == PCAP_MAGIC_USEC_BE or magic == PCAP_MAGIC_NSEC_BE:
            endian = ">"
            time_scale = 1000000 if magic == PCAP_MAGIC_USEC_BE else 1000000000
        else:
            raise ValueError("%s: unsupported pcap magic %r" % (path, magic))

        records = []
        while True:
            packet_header = handle.read(16)
            if not packet_header:
                break
            if len(packet_header) != 16:
                raise ValueError("%s: truncated pcap packet header" % path)
            ts_sec, ts_sub, incl_len, orig_len = struct.unpack(endian + "IIII", packet_header)
            frame = handle.read(incl_len)
            if len(frame) != incl_len:
                raise ValueError("%s: truncated pcap packet body" % path)
            records.append(
                {
                    "ts_sec": ts_sec,
                    "ts_sub": ts_sub,
                    "timestamp_seconds": float(ts_sec) + (float(ts_sub) / float(time_scale)),
                    "incl_len": incl_len,
                    "orig_len": orig_len,
                    "frame": frame,
                }
            )
    finally:
        handle.close()
    return records
