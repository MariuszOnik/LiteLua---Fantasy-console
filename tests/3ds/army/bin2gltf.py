"""A model for the 3DS tests (romfs/*.bin: LLMS, make_army.py, or LLM2, make_knight.py) -> glTF
with its animations as morph targets, to look at it in Blender before it goes to the 3DS.

  python bin2gltf.py romfs/polish.bin ATLAS.png OUT.gltf
ATLAS.png is the texture before tiling (make_knight.py saves it next to the M2TW output).
"""
import os, struct, sys
import numpy as np


def read(path):
    """uv, triangles, frames, [(animation name, first frame, frames)] of an LLMS or LLM2 file."""
    d = open(path, "rb").read()
    nv, nt, nf, ts = struct.unpack_from("<4H", d, 4)
    if d[:4] == b"LLMS":
        p, anims = 20, [("anim", 0, nf)]
    else:
        assert d[:4] == b"LLM2", d[:4]
        na = struct.unpack_from("<H", d, 12)[0]
        anims = []
        for i in range(na):
            name, first, count = struct.unpack_from("<8s2H", d, 16 + 20 * i)
            anims.append((name.rstrip(b"\0").decode(), first, count))
        p = 16 + 20 * na
    uv = np.frombuffer(d, "<f4", nv * 2, p).reshape(nv, 2); p += nv * 8
    tri = np.frombuffer(d, "<u2", nt * 3, p).reshape(nt, 3); p += (nt * 6 + 3) & ~3
    frames = np.frombuffer(d, "<f4", nf * nv * 3, p).reshape(nf, nv, 3)
    return uv, tri, frames, anims


if __name__ == "__main__":
    src, atlas, out = sys.argv[1:4]
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tools", "gameformats", "ig"))
    import v3d
    uv, tri, frames, anims = read(src)
    ob = dict(pos=frames[0].astype("<f4"), uv=uv.astype("<f4"), prims=[(tri.astype(np.uint16), 0)])
    gl = [(name, [[(None, f) for f in frames[first:first + count]]]) for name, first, count in anims]
    v3d.write_gltf(out, [ob], [atlas], gl, scale=1.0, fps=20)
    print(f"{out}: {len(uv)} verts, {len(tri)} tris, {len(frames)} frames, animations "
          + ", ".join(n for n, _, _ in anims))
