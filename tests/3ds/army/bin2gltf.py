"""A model for the 3DS army test (romfs/*.bin, format in make_army.py) -> glTF with its
animation as morph targets, to look at it in Blender before it goes to the 3DS.

  python bin2gltf.py romfs/polish.bin ATLAS.png OUT.gltf
ATLAS.png is the texture before tiling (make_knight.py saves it next to the M2TW output).
"""
import os, struct, sys
import numpy as np


def read(path):
    d = open(path, "rb").read()
    assert d[:4] == b"LLMS"
    nv, nt, nf, ts = struct.unpack_from("<4H", d, 4)
    p = 20
    uv = np.frombuffer(d, "<f4", nv * 2, p).reshape(nv, 2); p += nv * 8
    tri = np.frombuffer(d, "<u2", nt * 3, p).reshape(nt, 3); p += (nt * 6 + 3) & ~3
    frames = np.frombuffer(d, "<f4", nf * nv * 3, p).reshape(nf, nv, 3)
    return uv, tri, frames


if __name__ == "__main__":
    src, atlas, out = sys.argv[1:4]
    sys.path.insert(0, "E:/AI/IG/tools")
    import v3d
    uv, tri, frames = read(src)
    ob = dict(pos=frames[0].astype("<f4"), uv=uv.astype("<f4"), prims=[(tri.astype(np.uint16), 0)])
    v3d.write_gltf(out, [ob], [atlas], [("anim", [[(None, f) for f in frames]])], scale=1.0, fps=20)
    print(f"{out}: {len(uv)} verts, {len(tri)} tris, {len(frames)} frames")
