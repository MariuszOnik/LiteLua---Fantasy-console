"""Tree sprites for the battle prototype: from the local Imperial Glory archive (private use,
like the knights) -> romfs/trees.bin, one atlas of a few trees drawn as billboards.

  python make_trees.py [--pak "C:/Program Files/GOG Galaxy/Games/Imperial Glory/data.pak"]

trees.bin (little endian):
  "LLTR", u16 texsize, u16 sprites,
  sprites * (f32 u0, v0, u1, v1 -- the sprite in the atlas, v from the top; f32 width, height in metres)
  texsize^2 u16 RGBA5551 in the 3DS tile order (as tile_order in ../army/make_army.py)
"""
import argparse, io, os, struct, sys, zipfile
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SCEN = "Game/GameModes/Batalla/Escenarios/10/Models/"
SIZE = 512
# (source image, crop box in its pixels, place in the atlas (x, y, w, h), width, height in metres)
SPRITES = [
    ("Setarboleuropeo.tga", (0, 0, 512, 512), (0, 0, 256, 256), 11.0, 13.0),       # broad crown, dark
    ("Setarboleuropeo.tga", (512, 0, 1024, 512), (256, 0, 256, 256), 12.0, 13.0),   # broad crown, light
    ("Conoarbol.tga", (0, 0, 256, 512), (0, 256, 128, 256), 5.5, 11.0),             # slim conifer
    ("Setarboleuropeo.tga", (8, 516, 248, 764), (128, 256, 128, 128), 3.0, 3.0),    # bush (inside the
    ("Setarboleuropeo.tga", (264, 516, 504, 764), (128, 384, 128, 128), 3.0, 3.0),  # source's frame lines)
]


def tile_order_5551(img):
    n = img.shape[0]
    out = np.zeros(n * n, np.uint16)
    ys, xs = np.mgrid[0:n, 0:n]
    yf = n - 1 - ys
    tile = (yf >> 3) * (n >> 3) + (xs >> 3)
    x, y = xs & 7, yf & 7
    m = (x & 1) | ((y & 1) << 1) | ((x & 2) << 1) | ((y & 2) << 2) | ((x & 4) << 2) | ((y & 4) << 3)
    r, g, b, a = (img[..., i].astype(np.uint16) for i in range(4))
    out[tile * 64 + m] = ((r >> 3) << 11) | ((g >> 3) << 6) | ((b >> 3) << 1) | (a >= 128)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pak", default="C:/Program Files/GOG Galaxy/Games/Imperial Glory/data.pak")
    a = ap.parse_args()
    z = zipfile.ZipFile(a.pak)
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    table = bytearray()
    cache = {}
    for name, crop, (x, y, w, h), wm, hm in SPRITES:
        if name not in cache:
            cache[name] = Image.open(io.BytesIO(z.read(SCEN + name))).convert("RGBA")
        part = cache[name].crop(crop).resize((w, h), Image.LANCZOS)
        atlas.paste(part, (x, y))
        table += struct.pack("<6f", x / SIZE, y / SIZE, (x + w) / SIZE, (y + h) / SIZE, wm, hm)
    out = bytearray(b"LLTR") + struct.pack("<2H", SIZE, len(SPRITES)) + table
    out += tile_order_5551(np.asarray(atlas)).astype("<u2").tobytes()
    dst = os.path.join(HERE, "romfs", "trees.bin")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "wb").write(out)
    atlas.save(os.path.join(HERE, "romfs", "_trees_preview.png"))
    print(f"{dst}: {len(SPRITES)} sprites, atlas {SIZE}, {len(out)} bytes")


if __name__ == "__main__":
    main()
