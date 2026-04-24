#!/usr/bin/env python

import re
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


def _unicode_chr(value):
    if PY3:
        return chr(value)
    return unichr(value)


def _decode_string(value):
    if PY3:
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return value
    if isinstance(value, unicode):
        return value
    return value.decode("utf-8")


def _encode_string(value):
    if not isinstance(value, string_types):
        value = str(value)
    value = _decode_string(value)
    parts = ['"']
    for ch in value:
        code = ord(ch)
        if ch == '"':
            parts.append('\\"')
        elif ch == '\\':
            parts.append('\\\\')
        elif ch == '\b':
            parts.append('\\b')
        elif ch == '\f':
            parts.append('\\f')
        elif ch == '\n':
            parts.append('\\n')
        elif ch == '\r':
            parts.append('\\r')
        elif ch == '\t':
            parts.append('\\t')
        elif code < 32:
            parts.append("\\u%04x" % code)
        else:
            parts.append(ch)
    parts.append('"')
    return "".join(parts)


def _dump_value(value, indent, sort_keys, level):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, integer_types):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, string_types):
        return _encode_string(value)
    if isinstance(value, (list, tuple)):
        return _dump_list(value, indent, sort_keys, level)
    if isinstance(value, dict):
        return _dump_dict(value, indent, sort_keys, level)
    return _encode_string(str(value))


def _dump_list(values, indent, sort_keys, level):
    if not values:
        return "[]"
    if indent is None:
        parts = []
        for value in values:
            parts.append(_dump_value(value, indent, sort_keys, level + 1))
        return "[" + ", ".join(parts) + "]"

    prefix = " " * (indent * (level + 1))
    closing = " " * (indent * level)
    parts = []
    for value in values:
        parts.append(prefix + _dump_value(value, indent, sort_keys, level + 1))
    return "[\n" + ",\n".join(parts) + "\n" + closing + "]"


def _dump_dict(values, indent, sort_keys, level):
    if not values:
        return "{}"
    keys = values.keys()
    keys = list(keys)
    if sort_keys:
        keys.sort()

    if indent is None:
        parts = []
        for key in keys:
            parts.append("%s: %s" % (_encode_string(str(key)), _dump_value(values[key], indent, sort_keys, level + 1)))
        return "{%s}" % ", ".join(parts)

    prefix = " " * (indent * (level + 1))
    closing = " " * (indent * level)
    parts = []
    for key in keys:
        parts.append(
            "%s%s: %s" % (
                prefix,
                _encode_string(str(key)),
                _dump_value(values[key], indent, sort_keys, level + 1),
            )
        )
    return "{\n" + ",\n".join(parts) + "\n" + closing + "}"


def dumps(value, indent=None, sort_keys=False):
    return _dump_value(value, indent, sort_keys, 0)


def dump(value, handle, indent=None, sort_keys=False):
    handle.write(dumps(value, indent=indent, sort_keys=sort_keys))


class _Parser(object):
    def __init__(self, text):
        self.text = _decode_string(text)
        self.length = len(self.text)
        self.index = 0

    def parse(self):
        value = self.parse_value()
        self.skip_ws()
        if self.index != self.length:
            raise ValueError("extra data after JSON value")
        return value

    def current(self):
        return self.text[self.index]

    def skip_ws(self):
        while self.index < self.length and self.text[self.index] in " \t\r\n":
            self.index += 1

    def parse_value(self):
        self.skip_ws()
        if self.index >= self.length:
            raise ValueError("unexpected end of JSON input")
        ch = self.current()
        if ch == '"':
            return self.parse_string()
        if ch == "{":
            return self.parse_object()
        if ch == "[":
            return self.parse_array()
        if ch == "t":
            return self.parse_literal("true", True)
        if ch == "f":
            return self.parse_literal("false", False)
        if ch == "n":
            return self.parse_literal("null", None)
        return self.parse_number()

    def parse_literal(self, token, value):
        end = self.index + len(token)
        if self.text[self.index:end] != token:
            raise ValueError("invalid JSON literal")
        self.index = end
        return value

    def parse_string(self):
        self.index += 1
        parts = []
        while self.index < self.length:
            ch = self.text[self.index]
            self.index += 1
            if ch == '"':
                return "".join(parts)
            if ch != "\\":
                parts.append(ch)
                continue
            if self.index >= self.length:
                raise ValueError("unterminated escape sequence")
            esc = self.text[self.index]
            self.index += 1
            if esc == '"':
                parts.append('"')
            elif esc == "\\":
                parts.append("\\")
            elif esc == "/":
                parts.append("/")
            elif esc == "b":
                parts.append("\b")
            elif esc == "f":
                parts.append("\f")
            elif esc == "n":
                parts.append("\n")
            elif esc == "r":
                parts.append("\r")
            elif esc == "t":
                parts.append("\t")
            elif esc == "u":
                hex_text = self.text[self.index:self.index + 4]
                if len(hex_text) != 4 or not re.match("^[0-9a-fA-F]{4}$", hex_text):
                    raise ValueError("invalid unicode escape")
                self.index += 4
                parts.append(_unicode_chr(int(hex_text, 16)))
            else:
                raise ValueError("invalid escape character")
        raise ValueError("unterminated JSON string")

    def parse_array(self):
        items = []
        self.index += 1
        self.skip_ws()
        if self.index < self.length and self.current() == "]":
            self.index += 1
            return items
        while True:
            items.append(self.parse_value())
            self.skip_ws()
            if self.index >= self.length:
                raise ValueError("unterminated JSON array")
            ch = self.current()
            self.index += 1
            if ch == "]":
                return items
            if ch != ",":
                raise ValueError("expected ',' or ']' in JSON array")

    def parse_object(self):
        value = {}
        self.index += 1
        self.skip_ws()
        if self.index < self.length and self.current() == "}":
            self.index += 1
            return value
        while True:
            self.skip_ws()
            if self.index >= self.length or self.current() != '"':
                raise ValueError("expected string key in JSON object")
            key = self.parse_string()
            self.skip_ws()
            if self.index >= self.length or self.current() != ":":
                raise ValueError("expected ':' after JSON object key")
            self.index += 1
            value[key] = self.parse_value()
            self.skip_ws()
            if self.index >= self.length:
                raise ValueError("unterminated JSON object")
            ch = self.current()
            self.index += 1
            if ch == "}":
                return value
            if ch != ",":
                raise ValueError("expected ',' or '}' in JSON object")

    def parse_number(self):
        start = self.index
        if self.current() == "-":
            self.index += 1
        while self.index < self.length and self.text[self.index].isdigit():
            self.index += 1
        if self.index < self.length and self.text[self.index] == ".":
            self.index += 1
            while self.index < self.length and self.text[self.index].isdigit():
                self.index += 1
        if self.index < self.length and self.text[self.index] in "eE":
            self.index += 1
            if self.index < self.length and self.text[self.index] in "+-":
                self.index += 1
            while self.index < self.length and self.text[self.index].isdigit():
                self.index += 1
        token = self.text[start:self.index]
        if token.find(".") >= 0 or token.find("e") >= 0 or token.find("E") >= 0:
            return float(token)
        return int(token)


def loads(text):
    return _Parser(text).parse()


def load(handle):
    return loads(handle.read())
