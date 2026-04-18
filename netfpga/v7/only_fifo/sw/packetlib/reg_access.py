#!/usr/bin/env python

import os
import re


REGREAD_VALUE_RE = re.compile(r":\s*(0x[0-9a-fA-F]+)")


def _shell_quote(value):
    return "'" + str(value).replace("'", "'\"'\"'") + "'"


def _format_hex32(value):
    return "0x%08x" % (value & 0xffffffff)


class RegisterAccessor(object):
    def __init__(self, regread_bin=None, regwrite_bin=None):
        self.regread_bin = regread_bin or os.environ.get("REGREAD_BIN") or "regread"
        self.regwrite_bin = regwrite_bin or os.environ.get("REGWRITE_BIN") or "regwrite"

    def read_reg(self, addr):
        addr_text = _format_hex32(addr)
        cmd = "%s %s 2>&1" % (_shell_quote(self.regread_bin), addr_text)
        pipe = os.popen(cmd)
        try:
            output = pipe.read()
        finally:
            status = pipe.close()

        if status is not None:
            raise RuntimeError("regread failed for %s: %s" % (addr_text, output.strip()))

        value = None
        for line in output.splitlines():
            match = REGREAD_VALUE_RE.search(line)
            if match:
                value = int(match.group(1), 16)
        if value is None:
            raise RuntimeError("failed to parse regread output for %s: %s" % (addr_text, output.strip()))
        return value

    def write_reg(self, addr, value):
        addr_text = _format_hex32(addr)
        value_text = _format_hex32(value)
        cmd = "%s %s %s 2>&1" % (
            _shell_quote(self.regwrite_bin),
            addr_text,
            value_text,
        )
        pipe = os.popen(cmd)
        try:
            output = pipe.read()
        finally:
            status = pipe.close()

        if status is not None:
            raise RuntimeError("regwrite failed for %s <- %s: %s" % (addr_text, value_text, output.strip()))
        return {
            "addr": addr,
            "addr_text": addr_text,
            "value": value,
            "value_text": value_text,
            "output": output.strip(),
        }
