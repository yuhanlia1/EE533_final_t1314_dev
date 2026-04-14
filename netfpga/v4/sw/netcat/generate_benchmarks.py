#!/usr/bin/env python3
"""
CSV-to-BIN generator (Python 3.8-friendly)

• Adds the fixed 12-digit word 000000000000.
• Converts the next 16 comma-separated decimal bytes (0-255) of each row
  to 16-digit, zero-padded hex words.
• Writes a .bin file per row, appending 0x00 + "<label>_<row#>\\n".
"""

from pathlib import Path
import csv
from typing import List, Optional, Union

###############################################################################
#  Original helper (unchanged)
###############################################################################
def write_multiple_hex_nibbles(
    hex_list: List[str],
    filename: Union[str, Path] = "payload.bin",
    tail_text: Optional[str] = None,
    *,
    encoding: str = "utf-8",
    add_null: bool = False,
) -> None:
    """Writes concatenated hex bytes plus optional ASCII/UTF-8 trail."""
    full_hex = "".join(h.replace(" ", "").replace("0x", "") for h in hex_list)
    if len(full_hex) % 2:
        raise ValueError("Combined hex must have an even number of digits.")
    data = bytes.fromhex(full_hex)

    with open(filename, "wb") as f:
        f.write(data)
        if tail_text is not None:
            if add_null:
                f.write(b"\x00")          # delimiter
            f.write(tail_text.encode(encoding))

    print(f"Wrote {len(data):4d} hex-bytes", end="")
    if tail_text is not None:
        print(f" + {len(tail_text):2d} text-bytes", end="")
    print(f" → {filename}")


###############################################################################
#  CSV → BIN logic (5 rows for BENIGN, 2 rows for others)
###############################################################################
LABEL_INFO = {
    "./csv_folder/BENIGN.csv":                   ("good", 200),
    "./csv_folder/DDoS.csv":                     ("ddos", 200),
    "./csv_folder/Heartbleed.csv":               ("heartbleed", 200),
    "./csv_folder/PortScan.csv":                 ("portscan", 200),
    "./csv_folder/Web_Attack_Brute_Force.csv":   ("web_attack_brute_force", 200),
    "./csv_folder/Web_Attack_Sql_Injection.csv": ("web_attack_sql_injection", 200),
}

HEADER_HEX = "000000000000"        # 12-digit constant
OUT_DIR    = Path("bin_payloads")
OUT_DIR.mkdir(exist_ok=True)

def dec_row_to_hex_words(dec_values: List[int]) -> List[str]:
    """Return ['000000000000', '00000000000000DB', …] for first 16 ints."""
    if len(dec_values) < 16:
        raise ValueError("Row has fewer than 16 data points")
    words = [HEADER_HEX]
    for v in dec_values[:16]:
        if not (0 <= v <= 255):
            raise ValueError(f"Byte value {v} out of range 0–255")
        words.append(f"{v:02X}".zfill(16))   # 14 zeros + 2-digit hex
    return words

def process_csv(csv_path: Path, label_prefix: str, row_limit: int) -> None:
    """Convert up to *row_limit* rows of *csv_path* into .bin files."""
    with csv_path.open(newline="") as f:
        reader = csv.reader(f)
        for idx, row in enumerate(reader, start=1):
            if idx > row_limit:
                break
            if not row:
                continue

            try:
                ints = [int(x.strip()) for x in row if x.strip()]
                hex_words = dec_row_to_hex_words(ints)
            except ValueError as exc:
                print(f"⚠︎ Skipping row {idx} in {csv_path.name}: {exc}")
                continue

            bin_name  = OUT_DIR / f"{label_prefix}_{idx}.bin"
            tail_text = f"{label_prefix}_{idx}\n"
            write_multiple_hex_nibbles(
                hex_words,
                filename=bin_name,
                tail_text=tail_text,
                add_null=True,
            )

def main() -> None:
    for csv_file, (prefix, limit) in LABEL_INFO.items():
        path = Path(csv_file)
        if not path.is_file():
            print(f"⚠︎ {csv_file} not found – skipping")
            continue
        print(f"Processing {csv_file} … (first {limit} rows)")
        process_csv(path, prefix, limit)

if __name__ == "__main__":
    main()
