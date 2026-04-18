from typing import Optional

def write_multiple_hex_nibbles(
        hex_list,
        filename: str = "payload.bin",
        tail_text: Optional[str] = None,
        *,
        encoding: str = "utf-8",
        add_null: bool = False,
):
    """
    Writes the concatenated hex bytes, plus an optional ASCII/UTF-8 trail.
    """
    full_hex = "".join(h.replace(" ", "").replace("0x", "") for h in hex_list)
    if len(full_hex) % 2:
        raise ValueError("Combined hex must have an even number of digits.")
    data = bytes.fromhex(full_hex)

    with open(filename, "wb") as f:
        f.write(data)
        if tail_text is not None:
            if add_null:
                f.write(b"\x00")            # optional delimiter
            f.write(tail_text.encode(encoding))

    print(f"Wrote {len(data)} hex-bytes", end="")
    if tail_text is not None:
        print(f" + {len(tail_text)} text-bytes", end="")
    print(f" to '{filename}'")


hex_data1 = ['000000000000', '00000000000000DB', '00000000000000E0', '0000000000000000', '00000000000000CB', '00000000000000EF', '0000000000000000', '00000000000000FF', '0000000000000000', '0000000000000000', '0000000000000000', '00000000000000E0', '00000000000000CA', '00000000000000C6', '00000000000000A6', '00000000000000EB', '00000000000000EE']
hex_data2 = ['000000000000', '00000000000000EA', '0000000000000077', '0000000000000000', '00000000000000FE', '00000000000000DA', '0000000000000000', '0000000000000000', '0000000000000000', '0000000000000000', '0000000000000000', '0000000000000077', '00000000000000F4', '000000000000008A', '00000000000000B6', '00000000000000D5', '00000000000000D5']
# hex_data3 = ['000000000000', '000000000000001C', '000000000000002C', '0000000000000092', '0000000000000000', '0000000000000000', '0000000000000000', '00000000000000FF', '0000000000000000', '00000000000000DB', '00000000000000F1', '000000000000002C', '000000000000004D', '00000000000000AD', '000000000000008F', '0000000000000000', '0000000000000000']

# write_multiple_hex_nibbles(hex_data1, "sample1.bin")
# write_multiple_hex_nibbles(hex_data2, "sample2.bin")
# write_multiple_hex_nibbles(hex_data3, "sample3.bin")


write_multiple_hex_nibbles(hex_data1, "sample1.bin", tail_text="Hello World!!\n", add_null=True)
write_multiple_hex_nibbles(hex_data2, "sample2.bin", tail_text="DDOS ATTACK!\n", add_null=True)
