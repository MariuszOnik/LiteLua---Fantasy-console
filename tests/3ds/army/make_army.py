"""Soldier model for the 3DS army test: an Imperial Glory unit -> romfs/soldier.bin.

The game's assets stay local (private use, like the H4 and Cossacks art): this reads them
with the V3D reader kept outside the repo (E:/AI/IG/tools/v3d.py, see its docstring).

  python make_army.py [--ig E:/AI/IG] [--nation 20Polonia] [--unit Fusilero]

soldier.bin (little endian):
  "LLMS", u16 verts, u16 tris, u16 frames, u16 texsize, f32 seconds per loop, f32 metres/s
  verts * (u, v) f32          as in the game: v from the top
  tris * 3 u16                (+2 bytes padding when tris is odd)
  frames * verts * (x, y, z)  f32, metres, Y up, the soldier faces +Z
  texsize^2 u16 RGB565        8x8 tiles from the bottom row up, Morton order inside
"""
import argparse, os, struct, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def tile_order(img):
    """RGB565 pixels in the 3DS texture order (as texIndex in HeroesDS/3ds/source/main.c)."""
    n = img.shape[0]
    out = np.zeros(n * n, np.uint16)
    ys, xs = np.mgrid[0:n, 0:n]
    yf = n - 1 - ys
    tile = (yf >> 3) * (n >> 3) + (xs >> 3)
    x, y = xs & 7, yf & 7
    m = (x & 1) | ((y & 1) << 1) | ((x & 2) << 1) | ((y & 2) << 2) | ((x & 4) << 2) | ((y & 4) << 3)
    r, g, b = (img[..., i].astype(np.uint16) for i in range(3))
    out[tile * 64 + m] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ig", default="E:/AI/IG")
    ap.add_argument("--nation", default="20Polonia")
    ap.add_argument("--unit", default="Fusilero")
    ap.add_argument("--mesh", default="GenericoA")
    ap.add_argument("--anim", default="Andar1")
    ap.add_argument("--seconds", type=float, default=1.06)   # .TOTALTIME in <mesh>_ANM.sb
    ap.add_argument("--speed", type=float, default=1.6)      # .MOVBYSEC 160 cm
    a = ap.parse_args()
    sys.path.insert(0, os.path.join(a.ig, "tools"))
    import v3d

    base = os.path.join(a.ig, "Models", "00EjercitoBase", "Infanteria", a.mesh)
    objs, _ = v3d.read_mesh(os.path.join(base, a.mesh + ".V3D"))
    ob = objs[0]
    frames = [p for _, p in v3d.read_anim(os.path.join(base, a.anim + ".V3D"), objs)[0]]
    tex = Image.open(os.path.join(a.ig, "Models", a.nation, "Infanteria", a.unit + ".dds")).convert("RGB")
    n = tex.size[0]
    assert tex.size == (n, n) and n & (n - 1) == 0, tex.size

    nv, nt = len(ob["pos"]), len(ob["idx"])
    uv = ob["uv"].astype("<f4")  # v from the top: the tile order already flips the rows
    out = bytearray(b"LLMS")
    out += struct.pack("<4H2f", nv, nt, len(frames), n, a.seconds, a.speed)
    out += uv.tobytes()
    out += ob["idx"].astype("<u2").tobytes()
    if nt % 2:
        out += b"\0\0"
    for p in frames:
        out += (p * 0.01).astype("<f4").tobytes()
    out += tile_order(np.asarray(tex)).astype("<u2").tobytes()
    os.makedirs(os.path.join(HERE, "romfs"), exist_ok=True)
    dst = os.path.join(HERE, "romfs", "soldier.bin")
    open(dst, "wb").write(out)
    print(f"{dst}: {nv} verts, {nt} tris, {len(frames)} frames, texture {n}, {len(out)} bytes")


if __name__ == "__main__":
    main()
