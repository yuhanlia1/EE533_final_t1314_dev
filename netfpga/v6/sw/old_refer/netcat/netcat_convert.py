from typing import List

def to_fixed_hex(row: str) -> List[str]:
    # keep every value except the final one
    nums = [int(x) for x in row.split(",")][:-1]

    hex_list = ["000000000000"]                 # index 0 – twelve zeros
    hex_list.extend(f"{n:016X}" for n in nums)  # remaining 16-digit hex values
    return hex_list

row1 = "219,224,0,203,239,0,255,0,0,0,224,202,198,166,235,238,0"
print(to_fixed_hex(row1))


row2 = "234,119,0,254,218,0,0,0,0,0,119,244,138,182,213,213,1"
print(to_fixed_hex(row2))


row3 = "28,44,146,0,0,0,255,0,219,241,44,77,173,143,0,0,1"
print(to_fixed_hex(row3))
