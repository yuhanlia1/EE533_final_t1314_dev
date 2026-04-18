# gen_hex.py
program = [
    0x00001137,
    0x00000013,
    0x00000013,
    0x00000013,
    0x80010113,
    0x00000013,
    0x00000013,
    0x00000013,
    0x00012023,
    0x0000006f,
]

NOP   = 0x00000013
DEPTH = 512

words = program + [NOP] * (DEPTH - len(program))

with open("imem.hex", "w") as f:
    for w in words:
        f.write(f"{w & 0xFFFFFFFF:08x}\n")

print("Generated imem.hex")