"""Preview of a Heroes IV map's terrain (.h4c) as a PNG: textures, transitions, roads, heights.

Terrain tiles and transition masks follow the notes in tools/h4terrain.py and
tools/h4render.py of Anbrose/homm4-mac (MIT License, (c) 2026 Anton Ozhigin);
this is our own code.

  terrain.<name>.h4d    100 tiles of 64x32 that together form one patch (10 staggered
                        rows of 10).  Tile: u32 len, len bytes of RLE, 64 x u32 offset of
                        each scanline; a scanline is one screen column of the diamond
                        (1, 1, 3, 3 ... 31, 31, 31, 31 ... 1, 1 pixels, centred), runs of
                        u8 skip, u8 n, n palette indices.  Palette at the end:
                        u16 256, u16 0, u16 0, u8 0, 255 x BGR (index 0 transparent).
  transition.Transitions.h4d
                        u8 nsets, per set: u16 len + name, u32 count (93), count x
                        (u32 code, u8 bits, columns as above, each column padded to a
                        byte): bits 1 = hard mask, bits 4 = alpha 0..15 (low nibble first).
                        code = four base-4 digits: how far the shape reaches toward the
                        E, S, W and N corners of the cell.

Each cell is composed flat (its terrain, then overlays by `order`, then roads), lit by
the slope at its corners and warped onto the screen as two triangles whose corners are
raised by the corner heights.  Texture tiles come from the inner 6x6 tiles of the patch
by screen position, so the texture runs on across cells.

Usage:
  python h4mapview.py <heroes4.h4r> <map.h4c> <out.png> [--level N] [--height K]
                      [--scale S] [--light X,Y]
"""
import argparse
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4map  # noqa: E402
import h4r  # noqa: E402

TERRAIN_BASE = {0: "water", 1: "grass", 2: "rough", 3: "swamp", 4: "lava", 5: "snow",
                6: "sand", 7: "dirt", 8: "subterranean"}
TERRAIN_SINGLE = {9: "river.water", 10: "river.lava", 11: "river.ice", 12: "magic.all",
                  13: "magic.life", 14: "magic.order", 15: "magic.death", 16: "magic.chaos",
                  17: "magic.nature", 18: "magic.all"}
TWO_PATCHES = {"river.water", "river.lava", "river.ice", "magic.death", "magic.chaos", "magic.nature"}
# road piece kind: 1..3 = a shoulder of that road type, 0 = road body (type from its neighbours)
ROAD_FILE = {1: "road.gravel", 2: "road.dirt", 3: "road.cobblestone"}
COLUMN = [w for w in range(1, 32, 2) for _ in (0, 1)]
COLUMN += COLUMN[::-1]                                    # pixels in each of the 64 columns


def patch_alt(r, c):
    """Most terrains have two patches (.1/.2), alternating in 10x10 blocks of cells."""
    return (r // 10 + c // 10) % 2 + 1


def terrain_file(t, v, r=0, c=0):
    if t in TERRAIN_BASE:
        return f"{TERRAIN_BASE[t]}.{min(v, 1) + 1}.{patch_alt(r, c)}"
    s = TERRAIN_SINGLE.get(t)
    return f"{s}.{patch_alt(r, c)}" if s in TWO_PATCHES else s


def road_types(level):
    """Road type of every cell, after MapScene.swift: shoulders carry their type; a body
    cell takes the type most of its 8 neighbours have (repeated until nothing changes),
    an isolated body is dirt."""
    types, pending = {}, []
    for k, cell in level.cells.items():
        kinds = [rd[0] for rd in cell.roads]
        shoulders = [t for t in kinds if t in ROAD_FILE]
        if cell.road in ROAD_FILE:              # the cell's own road type (h4map.Cell.road)
            types[k] = cell.road
        elif shoulders:
            types[k] = max(shoulders)
        elif 0 in kinds:
            pending.append(k)
    changed = True
    while pending and changed:
        changed, rest = False, []
        for r, c in pending:
            votes = {}
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    t = types.get((r + dr, c + dc))
                    if (dr or dc) and t:
                        votes[t] = votes.get(t, 0) + 1
            if votes:
                types[(r, c)] = max(votes, key=votes.get)
                changed = True
            else:
                rest.append((r, c))
        pending = rest
    for k in pending:
        types[k] = 2
    return types


def columns(values):
    """Per-column values (64 lists) -> 32x64 array, each column centred like the tiles and
    its end values copied outward, so a warped diamond samples no see-through edge."""
    out = np.zeros((32, 64), np.float32)
    for x, col in enumerate(values):
        y0 = (32 - len(col)) // 2
        out[y0:y0 + len(col), x] = col
        out[:y0, x] = col[0]
        out[y0 + len(col):, x] = col[-1]
    return out


def parse_tiles(b):
    """terrain.*.h4d -> list of 32x64x4 float arrays (RGBA 0..1)."""
    pal_off = len(b) - 772
    pal = np.zeros((256, 4), np.float32)
    for i in range(255):
        bgr = b[pal_off + 7 + i * 3:pal_off + 10 + i * 3]
        pal[i + 1] = (bgr[2] / 255, bgr[1] / 255, bgr[0] / 255, 1)
    tiles, pos = [], 0
    while pos < pal_off:
        n = struct.unpack_from("<I", b, pos)[0]
        rle = b[pos + 4:pos + 4 + n]
        offs = struct.unpack_from("<64I", b, pos + 4 + n) + (n,)
        pos += 4 + n + 256
        cols = []
        for x in range(64):
            seg, row, i = rle[offs[x]:offs[x + 1]], [], 0
            while i < len(seg):
                row += [0] * seg[i]
                if i + 1 < len(seg):
                    cnt = seg[i + 1]
                    row += list(seg[i + 2:i + 2 + cnt])
                    i += 2 + cnt
                else:
                    i += 1
            cols.append(row[:COLUMN[x]] + [0] * (COLUMN[x] - len(row)))
        tiles.append(pal[columns(cols).astype(np.int32)])
    return tiles


def parse_masks(b):
    """transition.Transitions.h4d -> {set name: [(code, 32x64 alpha 0..1), ...]}."""
    sets, pos = {}, 1
    for _ in range(b[0]):
        ln = struct.unpack_from("<H", b, pos)[0]
        name = b[pos + 2:pos + 2 + ln].decode("latin-1")
        count = struct.unpack_from("<I", b, pos + 2 + ln)[0]
        pos += 6 + ln
        masks = []
        for _ in range(count):
            code, bits = struct.unpack_from("<IB", b, pos)
            pos += 5
            cols = []
            for w in COLUMN:
                nb = (w * bits + 7) // 8
                v = int.from_bytes(b[pos:pos + nb], "little")
                pos += nb
                cols.append([(v >> (k * bits)) & ((1 << bits) - 1) for k in range(w)])
            # the outermost pixel of a column carries stray values along the edge
            # (dotted lines in water_to_land); take the next pixel inward instead
            cols = [c if len(c) < 3 else [c[1]] + c[1:-1] + [c[-2]] for c in cols]
            masks.append((code, columns(cols) / ((1 << bits) - 1)))
        sets[name] = masks
    return sets


class Assets:
    def __init__(self, archive):
        self.archive = h4r.Archive(archive)
        self.masks = parse_masks(self.archive.read("transition.Transitions.h4d"))
        self.tilesets = {}

    def tiles(self, name):
        if name not in self.tilesets:
            self.tilesets[name] = parse_tiles(self.archive.read(f"terrain.{name}.h4d"))
        return self.tilesets[name]


WATER = {0, 3, 9}   # water, swamp, water river: swamp too, its soft edges match the editor
SHORE_SWAP = False  # the other pairing gives hard lines along cell edges (checked)


def overlay_set(base, over, r, c):
    """Mask set for an overlay of terrain `over` on cell (r, c) of terrain `base`, after
    MapScene.swift of homm4-mac: water on water "water", land on land "land", water on land
    "water_to_land", land on water "land_to_water"; the variant 1..3 by position.  Both
    cells along a shore carry an overlay; only this pairing makes their gradients meet."""
    n = (r * 3 + c * 5) % 3 + 1
    if (base in WATER) == (over in WATER):
        return f"water {min(n, 2)}" if over in WATER else f"land {n}"
    if (over in WATER) != SHORE_SWAP:
        return f"water_to_land {n}"
    return f"land_to_water {n}"


def compose(assets, cell, r, c, road_type=0):
    """The cell's flat 32x64 RGBA image: terrain, then overlays and roads by their order
    byte (roads sit at 10..14, so terrain drawn after a road nibbles its edges).  A road
    shoulder is drawn through its mask, a road body through the inverted mask (the
    terrain shows inside the mask)."""
    ti = tile_index(r, c)
    img = assets.tiles(terrain_file(cell.type, cell.variant, r, c))[ti].copy()
    items = [(o[3], "terrain", o) for o in cell.overlays] + [(rd[2], "road", rd) for rd in cell.roads]
    if cell.road in ROAD_FILE and not cell.roads:
        items.append((10, "road", (cell.road, None, 10)))   # all road: no mask needed
    for _, kind, item in sorted(items, key=lambda i: i[0]):
        if kind == "terrain":
            t, v, mask, _ = item
            name = terrain_file(t, v, r, c)
            if not name:
                continue
            a = assets.masks[overlay_set(cell.type, t, r, c)][mask][1]
        else:
            piece, mask, _ = item
            name = ROAD_FILE.get(piece or road_type)
            if not name or (mask is not None and mask >= 93):
                continue
            name = f"{name}.{patch_alt(r, c)}"
            if mask is None:
                a = np.ones((32, 64), np.float32)
            else:
                a = assets.masks["road 1"][mask][1]
                if piece == 0:
                    a = 1 - a
        tile = assets.tiles(name)[ti]
        a = a[..., None] * tile[..., 3:]
        img[..., :3] = img[..., :3] * (1 - a) + tile[..., :3] * a
    return img


def tile_index(r, c):
    row, col = r + c, (c - r - (r + c) % 2) // 2
    return (row % 6 + 2) * 10 + (col % 6 + 2)


def corner_light(level, light):
    """Brightness per corner from the slope: > 1 facing the light, < 1 turned away."""
    lr, lc = light
    out = {}
    for (r, c) in level.heights:
        dr = level.height(r + 1, c) - level.height(r - 1, c)
        dc = level.height(r, c + 1) - level.height(r, c - 1)
        out[(r, c)] = float(np.clip(1 - (dr * lr + dc * lc) / 128, 0.5, 1.4))
    return out


def draw_triangle(canvas, img, src, dst, lum):
    """Affine-map triangle src (tile x, y) onto dst (screen x, y), lit by lum at its corners."""
    (x0, y0), (x1, y1), (x2, y2) = dst
    det = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(det) < 1e-6:
        return
    left, right = int(np.floor(min(x0, x1, x2))), int(np.ceil(max(x0, x1, x2)))
    top, bottom = int(np.floor(min(y0, y1, y2))), int(np.ceil(max(y0, y1, y2)))
    left, top = max(left, 0), max(top, 0)
    right, bottom = min(right, canvas.shape[1]), min(bottom, canvas.shape[0])
    if left >= right or top >= bottom:
        return
    ys, xs = np.mgrid[top:bottom, left:right] + 0.5
    w0 = ((y1 - y2) * (xs - x2) + (x2 - x1) * (ys - y2)) / det
    w1 = ((y2 - y0) * (xs - x2) + (x0 - x2) * (ys - y2)) / det
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-3) & (w1 >= -1e-3) & (w2 >= -1e-3)
    u = w0 * src[0][0] + w1 * src[1][0] + w2 * src[2][0]
    v = w0 * src[0][1] + w1 * src[1][1] + w2 * src[2][1]
    px = img[np.clip(v.astype(int), 0, 31), np.clip(u.astype(int), 0, 63)]
    shade = (w0 * lum[0] + w1 * lum[1] + w2 * lum[2])[..., None]
    ok = inside & (px[..., 3] > 0)
    region = canvas[top:bottom, left:right]
    region[ok] = np.clip(px[..., :3] * shade, 0, 1)[ok]


def screen(n, r, c, pad):
    """Centre of cell (r, c) on the canvas; the playable diamond is a rectangle on screen."""
    return (c - r + n // 2 + 2) * 32, (c + r - n // 2 + 2) * 16 + pad


def render(assets, m, level=0, k=1.0, light=(0.0, 1.0)):
    lv = m.levels[level]
    n = m.size
    pad = int(256 * k)
    canvas = np.zeros(((n + 6) * 16 + pad, (n + 4) * 32, 3), np.float32)
    canvas[:] = (0.05, 0.05, 0.08)
    lum = corner_light(lv, light)
    roads = road_types(lv)
    # tile corners: top, right, bottom, left (tile x, y)
    T, R, B, L = (32, 0), (64, 16), (32, 32), (0, 16)
    for r, c in sorted(lv.cells, key=lambda p: (p[0] + p[1], p[1] - p[0])):
        img = compose(assets, lv.cells[(r, c)], r, c, roads.get((r, c), 0))
        x, y = screen(n, r, c, pad)
        corner = {"T": (r, c), "R": (r, c + 1), "B": (r + 1, c + 1), "L": (r + 1, c)}
        sp = {"T": (x, y - 16), "R": (x + 32, y), "B": (x, y + 16), "L": (x - 32, y)}
        dst = {key: (sp[key][0], sp[key][1] - lv.height(*corner[key]) * k) for key in sp}
        li = {key: lum[corner[key]] for key in sp}
        src = {"T": T, "R": R, "B": B, "L": L}
        for tri in (("L", "T", "R"), ("L", "R", "B")):
            draw_triangle(canvas, img, [src[t] for t in tri], [dst[t] for t in tri],
                          [li[t] for t in tri])
    return Image.fromarray((canvas * 255).astype(np.uint8))


def main(argv):
    p = argparse.ArgumentParser(description="Heroes IV map terrain -> PNG")
    p.add_argument("archive")
    p.add_argument("map")
    p.add_argument("out")
    p.add_argument("--level", type=int, default=0)
    p.add_argument("--height", type=float, default=1.0, help="screen pixels per height unit")
    p.add_argument("--scale", type=float, default=1.0, help="shrink the PNG (0.5 = half)")
    p.add_argument("--light", default="0,1",
                   help="light direction in (row, col) steps; 0,1 matches the editor "
                        "(fitted to an editor screenshot, docs/FORMATS.md)")
    a = p.parse_args(argv[1:])
    m = h4map.parse(open(a.map, "rb").read())
    img = render(Assets(a.archive), m, a.level, a.height, tuple(float(v) for v in a.light.split(",")))
    if a.scale != 1:
        img = img.resize((int(img.width * a.scale), int(img.height * a.scale)), Image.LANCZOS)
    img.save(a.out)
    print(f"{m.name!r} level {a.level} -> {a.out} {img.width}x{img.height}")


if __name__ == "__main__":
    main(sys.argv)
