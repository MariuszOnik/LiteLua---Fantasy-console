"""Heroes IV map objects: their footprints from the models, and passability of a map level.

Model header layout from Sprite.swift / Pathing.swift of Anbrose/homm4-mac (MIT License,
(c) 2026 Anton Ozhigin); this is our own code.

adv_object.<name>.h4d starts with the model header (little endian):
  u16 version, u8, u16 k, u16 w, u16 h,
  footprint   w x h bits (ceil(n / 8) bytes, low bit first): bit i = cell (i % w, i // w),
              i.e. (row + i % w, col + i // w) from the object's position; set = occupied
  k >= 1:     top edges  (h + 1) x w bits: bit y * w + x = the edge on the -col side of
                         cell (x, y) (y = h: below the last column)
              left edges (w + 1) x h bits: bit x * h + y = the edge on the -row side of
                         cell (x, y) (x = w: past the last row)
              A hero enters the object across these edges (a town: the two edges of its
              gate); a cell with such an edge is a trigger cell, where a route may end.

Passability of a level (as homm4-mac's Passability): water and rivers block (a river needs
a bridge, even under a road); every occupied footprint cell blocks; trigger cells are
where a hero stands to use an object.  Not stored in the map: the editor shows the same.

Usage:
  python h4objects.py <heroes4.h4r> <map.h4c> [out.png] [--level N]
      lists the objects with their footprints; out.png: the terrain preview with blocked
      cells red, water/river blue and trigger cells yellow
"""
import argparse
import os
import struct
import sys
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4map  # noqa: E402
import h4r  # noqa: E402

BLOCKING_TERRAIN = {0, 9, 10, 11}    # water, water/lava/ice river


@dataclass
class Model:
    w: int = 1
    h: int = 1
    occupied: list = field(default_factory=list)   # (dr, dc)
    top: set = field(default_factory=set)          # (x, y): edge on the -col side of cell
    left: set = field(default_factory=set)         # (x, y): edge on the -row side of cell

    def triggers(self):
        """Cells (dr, dc) with an entry edge."""
        out = set()
        for x in range(self.w):
            for y in range(self.h):
                if {(x, y), (x, y + 1)} & self.top or {(x, y), (x + 1, y)} & self.left:
                    out.add((x, y))
        return out


def names(archive):
    """Lower-case model names of the archive (adv_object.<name>.h4d -> <name>)."""
    return {e.name[11:-4].lower() for e in archive.find("adv_object.")}


def parse_model(d):
    ver, _, k, w, h = struct.unpack_from("<HBHHH", d, 0)
    if not (1 <= w <= 16 and 1 <= h <= 16 and ver >= 3):
        return Model()

    def bits(at, n):
        return [(d[at + i // 8] >> (i % 8)) & 1 for i in range(n)]
    n_a, n_t = (w * h + 7) // 8, ((h + 1) * w + 7) // 8
    occ = bits(9, w * h)
    m = Model(w, h, [(i % w, i // w) for i, b in enumerate(occ) if b])
    if k >= 1:
        m.top = {(i % w, i // w) for i, b in enumerate(bits(9 + n_a, (h + 1) * w)) if b}
        m.left = {(i // h, i % h) for i, b in enumerate(bits(9 + n_a + n_t, (w + 1) * h)) if b}
    return m


class Models:
    def __init__(self, archive):
        self.archive = archive if isinstance(archive, h4r.Archive) else h4r.Archive(archive)
        self.cache = {}

    def get(self, name):
        key = name.lower()
        if key not in self.cache:
            try:
                self.cache[key] = parse_model(self.archive.read(f"adv_object.{name}.h4d"))
            except KeyError:
                self.cache[key] = Model()
        return self.cache[key]


def passability(m, level, objects, models):
    """{cell: "water" | "blocked" | "trigger"} for the cells of one level that are not
    plain walkable ground (a trigger cell stays usable even inside a footprint)."""
    lv = m.levels[level]
    out = {k: "water" for k, c in lv.cells.items() if c.type in BLOCKING_TERRAIN}
    for o in objects:
        if o.level != level:
            continue
        model = models.get(o.name)
        for dr, dc in model.occupied:
            out[(o.row + dr, o.col + dc)] = "blocked"
    for o in objects:
        if o.level == level:
            for dr, dc in models.get(o.name).triggers():
                out[(o.row + dr, o.col + dc)] = "trigger"
    return out


def overlay(img, m, level, cells, pad, k=1.0):
    """Tints the cells of the preview image (h4mapview.render at scale 1)."""
    from PIL import ImageDraw
    import h4mapview
    lv = m.levels[level]
    colors = {"water": (40, 90, 255, 90), "blocked": (255, 30, 30, 110), "trigger": (255, 230, 0, 150)}
    layer = img.convert("RGBA")
    over = layer.copy()
    over.putalpha(0)
    draw = ImageDraw.Draw(over)
    for (r, c), what in cells.items():
        x, y = h4mapview.screen(m.size, r, c, pad)
        pts = [(x, y - 16 - lv.height(r, c) * k), (x + 32, y - lv.height(r, c + 1) * k),
               (x, y + 16 - lv.height(r + 1, c + 1) * k), (x - 32, y - lv.height(r + 1, c) * k)]
        draw.polygon(pts, fill=colors[what], outline=colors[what][:3] + (255,))
    return __import__("PIL.Image", fromlist=["Image"]).alpha_composite(layer, over)


def main(argv):
    p = argparse.ArgumentParser(description="Heroes IV map objects and passability")
    p.add_argument("archive")
    p.add_argument("map")
    p.add_argument("out", nargs="?")
    p.add_argument("--level", type=int, default=0)
    a = p.parse_args(argv[1:])
    arch = h4r.Archive(a.archive)
    m = h4map.parse(open(a.map, "rb").read())
    objs = h4map.find_objects(m, names(arch))
    models = Models(arch)
    for o in objs:
        md = models.get(o.name)
        print(f"({o.row:3d},{o.col:3d}) L{o.level} {o.name:32s} {o.type}/{o.subtype}/{o.kind}  "
              f"{md.w}x{md.h}, {len(md.occupied)} occupied, triggers {sorted(md.triggers())}")
    if a.out:
        import h4mapview
        img = h4mapview.render(h4mapview.Assets(arch.filename), m, a.level)
        img = overlay(img, m, a.level, passability(m, a.level, objs, models), int(256))
        img.convert("RGB").save(a.out)
        print("->", a.out)


if __name__ == "__main__":
    main(sys.argv)
