#!/usr/bin/env python

import struct
import time


PCAP_MAGIC_USEC_LE = b"\xd4\xc3\xb2\xa1"
PCAP_MAGIC_USEC_BE = b"\xa1\xb2\xc3\xd4"
PCAP_MAGIC_NSEC_LE = b"\x4d\x3c\xb2\xa1"
PCAP_MAGIC_NSEC_BE = b"\xa1\xb2\x3c\x4d"
PCAP_LINKTYPE_ETHERNET = 1


def write_pcap(path, frames, linktype=PCAP_LINKTYPE_ETHERNET, snaplen=65535):
    handle = open(path, "wb")
    try:
        handle.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, snaplen, linktype))
        ts_usec = 0
        base_sec = int(time.time())
        for frame in frames:
            raw = bytes(frame)
            handle.write(struct.pack("<IIII", base_sec, ts_usec, len(raw), len(raw)))
            handle.write(raw)
            ts_usec += 1
    finally:
        handle.close()


def read_pcap(path):
    handle = open(path, "rb")
    try:
        header = handle.read(24)
        if len(header) != 24:
            raise ValueError("%s: truncated pcap global header" % path)

        magic = header[0:4]
        if magic == PCAP_MAGIC_USEC_LE or magic == PCAP_MAGIC_NSEC_LE:
            endian = "<"
        elif magic == PCAP_MAGIC_USEC_BE or magic == PCAP_MAGIC_NSEC_BE:
            endian = ">"
        else:
            raise ValueError("%s: unsupported pcap magic %r" % (path, magic))

        frames = []
        while True:
            packet_header = handle.read(16)
            if not packet_header:
                break
            if len(packet_header) != 16:
                raise ValueError("%s: truncated pcap packet header" % path)
            _ts_sec, _ts_sub, incl_len, _orig_len = struct.unpack(endian + "IIII", packet_header)
            frame = handle.read(incl_len)
            if len(frame) != incl_len:
                raise ValueError("%s: truncated pcap packet body" % path)
            frames.append(frame)
    finally:
        handle.close()
    return frames
