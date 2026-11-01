"""walk.py FILE START - follow V3D chunks: u16 tag, u16 zero, u32 size (incl. 8-byte header)."""
import struct, sys

d = open(sys.argv[1], "rb").read()
o = int(sys.argv[2], 16)
while o + 8 <= len(d):
    tag, z, size = struct.unpack_from("<HHI", d, o)
    if size < 8 or o + size > len(d):
        print(f"{o:05x} stop: tag {tag:04x} z {z} size {size}")
        break
    body = d[o + 8:o + min(size, 40)]
    print(f"{o:05x} tag {tag:04x} z {z} size {size:6} | {body.hex(' ')}")
    o += size
print(f"end {o:05x} / {len(d):05x}")
