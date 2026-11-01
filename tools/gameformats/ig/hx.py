"""hx.py FILE [START [END]] - hexdump with int32/float32 columns (offsets in hex)."""
import struct, sys

d = open(sys.argv[1], "rb").read()
a = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0
b = int(sys.argv[3], 16) if len(sys.argv) > 3 else len(d)
print("size", len(d), hex(len(d)))
for o in range(a, min(b, len(d)), 16):
    row = d[o:o + 16].ljust(16, b"\0")
    ints = struct.unpack("<4i", row)
    fl = struct.unpack("<4f", row)
    asc = "".join(chr(c) if 32 <= c < 127 else "." for c in row)
    print(f"{o:05x} {row.hex(' ', 4)}  {' '.join(f'{i:>10}' for i in ints)} | "
          f"{' '.join(f'{f:9.3g}' for f in fl)} | {asc}")
