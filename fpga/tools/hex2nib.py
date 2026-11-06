#!/usr/bin/env python3
"""Convert an `objcopy -O verilog` byte hex file into a nibble-per-entry
$readmemh file for fpga/rtl/qspi_pmod_emu.v (nibble 2n = byte n [7:4],
nibble 2n+1 = byte n [3:0]).

usage: hex2nib.py firmware.hex out_nibbles.hex
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
mem = {}
addr = 0
for tok in open(src).read().split():
    if tok.startswith("@"):
        addr = int(tok[1:], 16)
    else:
        mem[addr] = int(tok, 16)
        addr += 1

flash = {a: v for a, v in mem.items() if a < 0x1000000}   # flash image only
out = []
last = None
for a in sorted(flash):
    if last is None or a != last + 1:
        out.append(f"@{2 * a:x}")
    out.append(f"{flash[a] >> 4:x}")
    out.append(f"{flash[a] & 0xF:x}")
    last = a
open(dst, "w").write("\n".join(out) + "\n")
print(f"{len(flash)} bytes -> {2 * len(flash)} nibbles in {dst}")
