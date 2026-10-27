"""Makes carts/m1: a piece of a Heroes IV map as raised, lit terrain on the DS (quad, D58).

Every cell of the window is composed on the PC (terrain, transitions, roads: h4mapview),
then "straightened": the 64x32 diamond is resampled into a TEX x TEX square whose x runs
along the cell's columns and y along its rows, so the cart only has to put the square's
corners on the diamond's top, right, bottom and left corner (raised by the corner heights)
with quad().  Equal squares are stored once; all of them make one 256-colour sheet.

  carts/m1/gfx/terrain.png    the squares, FRAME x FRAME frames (index 0 stays transparent)
  carts/m1/data/terrain.lua   window size, frame per cell (-1 outside the map), corner
                              heights and slopes toward the light for (rows+1) x (cols+1),
                              and the objects back to front (h4objects.py)
  carts/m1/gfx/objects.png    the objects' pictures at half size and their shadows as black
                              shapes (the cart draws those with alpha: a palette image has
                              no soft transparency)

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
import h4objects  # noqa: E402

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


def slopes(level, light_dir, rows, cols, r0, c0):
    """Corner slope toward the light, -100..100: 0 flat, > 0 facing the light. The cart
    turns it into a shade with a strength it can change."""
    lum = h4mapview.corner_light(level, light_dir)
    out = []
    for r in range(r0, r0 + rows + 1):
        for c in range(c0, c0 + cols + 1):
            out.append(int(round(np.clip((lum.get((r, c), 1.0) - 1) * 100, -100, 100))))
    return out


def palette_image(rgba):
    """RGBA -> 255-colour palette image; alpha < 128 -> index 0 (transparent on the DS)."""
    a = np.asarray(rgba)
    q = rgba.convert("RGB").quantize(255, method=Image.Quantize.MEDIANCUT)
    idx = np.asarray(q, np.uint8) + 1
    idx[a[..., 3] < 128] = 0
    out = Image.fromarray(idx, "P")
    out.putpalette([0, 0, 0] + q.getpalette()[:255 * 3])
    return out


def object_sheet(m, archive, r0, c0, rows, cols):
    """The objects anchored in the window, back to front: (sheet, records). A record is
    the anchor cell (window coordinates), picture and shadow rectangles in the sheet and
    their offset from the top corner of the anchor cell, at half size."""
    arch = h4objects.h4r.Archive(archive)
    models = h4objects.Models(arch)
    objs = [o for o in h4map.find_objects(m, h4objects.names(arch))
            if o.level == 0 and r0 <= o.row < r0 + rows and c0 <= o.col < c0 + cols]

    def front(o):
        cells = models.get(o.name).occupied or [(0, 0)]
        return max(o.row + dr + o.col + dc for dr, dc in cells), o.col - o.row
    pieces, recs = [], []
    for o in sorted(objs, key=front):
        p = models.parts(o.name)
        if p is None:
            continue
        pic, shade, x, y = p
        size = (max(1, pic.width // 2), max(1, pic.height // 2))
        pic, shade = pic.resize(size, Image.LANCZOS), shade.resize(size, Image.LANCZOS)
        black = np.zeros((size[1], size[0], 4), np.uint8)
        black[..., 3] = np.where(np.asarray(shade)[..., 3] >= 48, 255, 0)
        recs.append({"r": o.row - r0, "c": o.col - c0, "dx": x // 2, "dy": y // 2,
                     "w": size[0], "h": size[1], "name": o.name})
        pieces.append((pic, Image.fromarray(black, "RGBA")))
    # shelves 256 wide: each picture, then its shadow
    W, x, y, shelf = 256, 0, 0, 0
    places = []
    for pic, shade in pieces:
        for im in (pic, shade):
            if x + im.width > W:
                x, y, shelf = 0, y + shelf, 0
            places.append((x, y))
            x += im.width
            shelf = max(shelf, im.height)
    sheet = Image.new("RGBA", (W, max(1, y + shelf)))
    for i, (pic, shade) in enumerate(pieces):
        sheet.alpha_composite(pic, places[2 * i])
        sheet.alpha_composite(shade, places[2 * i + 1])
        recs[i]["sx"], recs[i]["sy"] = places[2 * i]
        recs[i]["hx"], recs[i]["hy"] = places[2 * i + 1]
    return palette_image(sheet), recs


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--archive", default=os.path.join(cartkit.HEROES, "Data", "heroes4.h4r"))
    p.add_argument("--map", default=os.path.join(cartkit.HEROES, "obiekty.h4c"))
    p.add_argument("--heights", default="",
                   help="take the corner heights from this map instead (same size)")
    p.add_argument("--window", default="22,0,28,32", help="first row, first column, rows, columns")
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
    slope = slopes(lv, (0.0, 1.0), rows, cols, r0, c0)   # light as in h4mapview
    objects, recs = object_sheet(m, a.archive, r0, c0, rows, cols)
    objects.save(os.path.join(CART, "gfx", "objects.png"))

    def arr(xs):
        return "{" + ",".join(str(x) for x in xs) + "}"
    with open(os.path.join(CART, "data", "terrain.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- made by HeroesDS/tools/make_m1.py from {os.path.basename(a.map)}\n")
        f.write(f"return {{\n  rows = {rows}, cols = {cols}, row0 = {r0}, col0 = {c0}, tex = {FRAME},\n")
        f.write(f"  frames = {arr(frames)},\n  heights = {arr(heights)},\n  slope = {arr(slope)},\n")
        f.write("  objects = {   -- back to front; r, c: anchor cell; dx, dy: from its top corner\n")
        for o in recs:
            f.write("    {{ r = {r}, c = {c}, dx = {dx}, dy = {dy}, w = {w}, h = {h}, sx = {sx}, "
                    "sy = {sy}, hx = {hx}, hy = {hy} }},  -- {name}\n".format(**o))
        f.write("  },\n}}\n".replace("}}", "}"))
    print(f"  {rows}x{cols} cells, {n} different squares, sheet {out.width}x{out.height} "
          f"({out.width * out.height // 1024} KB); {len(recs)} objects, sheet "
          f"{objects.width}x{objects.height}")
    cartkit.deploy(CART, a.sd)


if __name__ == "__main__":
    main(sys.argv)
