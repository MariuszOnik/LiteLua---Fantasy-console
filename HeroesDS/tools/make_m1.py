"""Makes carts/m1: a piece of a Heroes IV map as raised, lit terrain on the DS (quad, D58).

Every cell of the window is composed on the PC (terrain, transitions, roads: h4mapview),
then "straightened": the 64x32 diamond is resampled into a TEX x TEX square whose x runs
along the cell's columns and y along its rows, so the cart only has to put the square's
corners on the diamond's top, right, bottom and left corner (raised by the corner heights)
with quad().  Equal squares are stored once; all of them make one 256-colour sheet.

  carts/m1/gfx/terrain.png    the squares, FRAME x FRAME frames (index 0 stays transparent)
  carts/m1/data/terrain.lua   window size, frame per cell (-1 outside the map), corner
                              heights and corner light (0..31) for (rows+1) x (cols+1)

Usage (from the repo root):
  python HeroesDS/tools/make_m1.py [--map M.h4c] [--heights H.h4c] [--window r,c,rows,cols]
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cartkit  # noqa: E402
import h4map  # noqa: E402
import h4mapview  # noqa: E402

CART = cartkit.cart_dir("m1")
TEX = 16             # texels per cell side
FRAME = TEX + 2      # a frame is the square with its edge texels repeated around it, so a
                     # stretched quad never samples the next frame or the sheet's padding
PER_ROW = 28         # frames per sheet row (28 * 18 = 504 wide)


def straighten(img):
    """32x64 RGBA diamond -> TEX x TEX RGB square (4x4 samples per texel)."""
    k = np.arange(TEX * 4) / (TEX * 4) + 0.5 / (TEX * 4)
    v, u = np.meshgrid(k, k, indexing="ij")             # v along rows, u along columns
    x = np.clip((32 + (u - v) * 32).astype(int), 0, 63)
    y = np.clip(((u + v) * 16).astype(int), 0, 31)
    s = img[y, x, :3]
    return s.reshape(TEX, 4, TEX, 4, 3).mean(axis=(1, 3))


def light(level, light_dir, rows, cols, r0, c0):
    """Corner light 10..31: 22 on flat ground, lighter facing the light, darker away (tint
    can only darken, so flat ground is not full white)."""
    lum = h4mapview.corner_light(level, light_dir)
    out = []
    for r in range(r0, r0 + rows + 1):
        for c in range(c0, c0 + cols + 1):
            out.append(int(round(np.clip(22 + (lum.get((r, c), 1.0) - 1) * 60, 10, 31))))
    return out


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--archive", default=os.path.join(cartkit.HEROES, "Data", "heroes4.h4r"))
    p.add_argument("--map", default=os.path.join(cartkit.HEROES, "droga i rzeka.h4c"))
    p.add_argument("--heights", default=os.path.join(cartkit.HEROES, "mapa ze wzniesieniem.h4c"),
                   help="take the corner heights from this map instead (same size)")
    p.add_argument("--window", default="24,0,32,26", help="first row, first column, rows, columns")
    p.add_argument("--sd", default=cartkit.SD)
    a = p.parse_args(argv[1:])
    r0, c0, rows, cols = (int(v) for v in a.window.split(","))

    m = h4map.parse(open(a.map, "rb").read())
    lv = m.levels[0]
    if a.heights:
        lv.heights = h4map.parse(open(a.heights, "rb").read()).levels[0].heights
    assets = h4mapview.Assets(a.archive)
    roads = h4mapview.road_types(lv)

    squares, index, frames = [], {}, []
    for r in range(r0, r0 + rows):
        for c in range(c0, c0 + cols):
            cell = lv.cells.get((r, c))
            if cell is None:
                frames.append(-1)
                continue
            sq = straighten(h4mapview.compose(assets, cell, r, c, roads.get((r, c), 0)))
            key = (sq * 255).astype(np.uint8).tobytes()
            if key not in index:
                index[key] = len(squares)
                squares.append(sq)
            frames.append(index[key])

    n = len(squares)
    sheet_rows = (n + PER_ROW - 1) // PER_ROW
    sheet = np.zeros((sheet_rows * FRAME, PER_ROW * FRAME, 3), np.float32)
    for i, sq in enumerate(squares):
        y, x = i // PER_ROW * FRAME, i % PER_ROW * FRAME
        sheet[y:y + FRAME, x:x + FRAME] = np.pad(sq, ((1, 1), (1, 1), (0, 0)), mode="edge")
    rgb = Image.fromarray((sheet * 255).astype(np.uint8))
    q = rgb.quantize(255, method=Image.Quantize.MEDIANCUT)
    idx = np.asarray(q, np.uint8) + 1                    # index 0 is transparent on the DS
    pal = [0, 0, 0] + q.getpalette()[:255 * 3]
    out = Image.fromarray(idx, "P")
    out.putpalette(pal)
    os.makedirs(os.path.join(CART, "gfx"), exist_ok=True)
    os.makedirs(os.path.join(CART, "data"), exist_ok=True)
    out.save(os.path.join(CART, "gfx", "terrain.png"))

    heights = [lv.height(r, c) for r in range(r0, r0 + rows + 1) for c in range(c0, c0 + cols + 1)]
    lights = light(lv, (1.0, -1.0), rows, cols, r0, c0)

    def arr(xs):
        return "{" + ",".join(str(x) for x in xs) + "}"
    with open(os.path.join(CART, "data", "terrain.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- made by HeroesDS/tools/make_m1.py from {os.path.basename(a.map)}\n")
        f.write(f"return {{\n  rows = {rows}, cols = {cols}, row0 = {r0}, col0 = {c0}, tex = {FRAME},\n")
        f.write(f"  frames = {arr(frames)},\n  heights = {arr(heights)},\n  light = {arr(lights)},\n}}\n")
    print(f"  {rows}x{cols} cells, {n} different squares, sheet {out.width}x{out.height} "
          f"({out.width * out.height // 1024} KB)")
    cartkit.deploy(CART, a.sd)


if __name__ == "__main__":
    main(sys.argv)
