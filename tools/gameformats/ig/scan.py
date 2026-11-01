"""scan.py FILE... - list V3D chunks of known tags (objects, arrays, indices, submeshes, frames)."""
import struct, sys

TAGS = {0x1000, 0x1100, 0x1110, 0x2000, 0x2100, 0x2300, 0x2400, 0x7000}
for path in sys.argv[1:]:
    d = open(path, "rb").read()
    print("==", path, len(d))
    for o in range(len(d) - 8):
        tag, z, size = struct.unpack_from("<HHI", d, o)
        if z or tag not in TAGS or not 8 <= size <= len(d) - o:
            continue
        info = ""
        if tag == 0x2000:
            n = struct.unpack_from("<H", d, o + 8)[0]
            info = d[o + 10:o + 10 + n].split(b"\0")[0].decode("latin1") if n < 64 else ""
        elif tag == 0x2100:
            kind, stride, n = struct.unpack_from("<3I", d, o + 8)
            if size != 20 + n * stride:
                continue
            info = f"kind {kind:#x} stride {stride} n {n}"
        elif tag == 0x2300:
            two, n = struct.unpack_from("<2I", d, o + 8)
            if size != 16 + n * 2:
                continue
            info = f"indices {n} (tris {n // 3})"
        elif tag == 0x2400:
            info = " ".join(str(x) for x in struct.unpack_from(f"<{(size - 8) // 4}I", d, o + 8))
        elif tag == 0x7000:
            info = f"frame verts {(size - 68) / 12}"
        elif tag in (0x1110,):
            info = d[o + 8:o + 40].decode("latin1", "replace").replace("\0", ".")
        print(f"  {o:06x} {tag:04x} {size:7} {info}")
