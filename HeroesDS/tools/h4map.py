"""Reader for Heroes of Might and Magic IV maps (.h4c): header, terrain cells, heights.

Layout from the notes in tools/h4map.py of Anbrose/homm4-mac (MIT License,
(c) 2026 Anton Ozhigin) plus our own tests (docs/FORMATS.md); this is our own code.

File: "H4CAMPAIGN", u32 22, u8 0, then a gzip stream (little endian inside):
  header   u16 version (27..29)   [version 28+: u16 ?]
           u16 size (76, 152, 228, 304)   u8 levels (1 = surface, 2 = + underground)   u32 ?
           u8 nplayers, nplayers x 5 bytes,  u16 len + name,  u8 difficulty?,
           u16 len + description
  ...      players, objects (not decoded here; `objects` keeps their raw bytes)
  cells    levels x one record per playable cell.  The playable area is the diamond
           |r - (size-1)/2| + |c - (size-1)/2| <= size/2 of the size x size grid,
           row-major (2964 cells for 76).
           cell  u8 type, u8 variant, u8 road, 4 bytes ?, u16 8, u8 n, n x overlay,
                 u8 m, m x road piece
           road     the cell's road type (0 none, 1 gravel, 2 dirt, 3 cobblestone): the cell
                    is road (all road when it has no road pieces); shoulders next to a road
                    keep 0.  Passability is not stored: the editor derives it from the
                    terrain (water and rivers block, even under a road) and the objects.
           overlay  u8 type, u8 variant, u16 mask, u8 order    another terrain drawn
                    through mask number `mask` of transition.Transitions
           road piece  u8 kind (1..3 a shoulder of that road type, 0 the road body), u8 mask,
                    u8 0, u8 order  (pieces and overlays are drawn by order; roads 10..14)
  heights  levels x one u8 per corner of the playable cells (the corners of the diamond,
           row-major: rows of 3, 5, 7 ... size+1 ... 7, 5, 3 corners; 3117 for 76).
           Corner (r, c) is the top corner of cell (r, c) on screen; 0 = flat,
           ~1 screen pixel per unit at 64x32 tiles.  The file ends there.

The cells are found by trying each start after the header: a start is right when
parsing all cells ends exactly where the height grids begin (an empty map repeats
the same 11 bytes, so a weaker test locks onto a wrong offset).

Usage:
  python h4map.py <map.h4c>          prints a summary
"""
import gzip
import struct
import sys
from collections import Counter
from dataclasses import dataclass, field

TERRAIN_NAMES = ["water", "grass", "rough", "swamp", "lava", "snow", "sand", "dirt",
                 "subterranean", "water river", "lava river", "ice river", "magic plains",
                 "field of life", "enchanted stone", "cursed ground", "scorched earth",
                 "magic garden", "field of glory"]


@dataclass
class Cell:
    type: int
    variant: int
    extra: bytes                                   # road type + 4 unknown bytes
    overlays: list = field(default_factory=list)   # (type, variant, mask, order)
    roads: list = field(default_factory=list)      # (kind, mask, order)

    @property
    def road(self):
        return self.extra[0]


@dataclass
class Level:
    cells: dict      # (r, c) -> Cell
    heights: dict    # (r, c) corner -> 0..255

    def height(self, r, c):
        return self.heights.get((r, c), 0)


@dataclass
class Map:
    version: int
    size: int
    name: str
    description: str
    levels: list
    objects: bytes   # undecoded bytes between the header and the cells


def diamond(size):
    mid = (size - 1) / 2
    return [(r, c) for r in range(size) for c in range(size)
            if abs(r - mid) + abs(c - mid) <= size / 2]


def corners(size):
    return sorted({(r + a, c + b) for r, c in diamond(size) for a in (0, 1) for b in (0, 1)})


def unpack(raw):
    if raw[:10] == b"H4CAMPAIGN":
        raw = raw[raw.find(b"\x1f\x8b\x08"):]
    return gzip.decompress(raw)


def _str(d, pos):
    n = struct.unpack_from("<H", d, pos)[0]
    return d[pos + 2:pos + 2 + n].decode("latin-1"), pos + 2 + n


def parse_header(d):
    version = struct.unpack_from("<H", d, 0)[0]
    pos = 4 if version >= 28 else 2
    size = struct.unpack_from("<H", d, pos)[0]
    levels = d[pos + 2]
    nplayers = d[pos + 7]
    pos += 8 + nplayers * 5
    name, pos = _str(d, pos)
    desc, pos = _str(d, pos + 1)
    return version, size, levels, name, desc, pos


def parse_cells(d, pos, count, stop):
    """count cells from pos, or None as soon as a field is out of range."""
    cells = []
    for _ in range(count):
        if pos + 11 > stop:
            return None, pos
        t, v, n = d[pos], d[pos + 1], d[pos + 9]
        if t >= len(TERRAIN_NAMES) or v > 3 or n > 8:
            return None, pos
        overlays = []
        for p in range(pos + 10, pos + 10 + 5 * n, 5):
            ot, ov, mask, order = struct.unpack_from("<BBHB", d, p)
            if ot >= len(TERRAIN_NAMES) or mask >= 93:
                return None, pos
            overlays.append((ot, ov, mask, order))
        q = pos + 10 + 5 * n
        m = d[q] if q < stop else 99
        if m > 8:
            return None, pos
        roads = [(d[p], d[p + 1], d[p + 3]) for p in range(q + 1, q + 1 + 4 * m, 4)]
        cells.append(Cell(t, v, bytes(d[pos + 2:pos + 7]), overlays, roads))
        pos = q + 1 + 4 * m
    return cells, pos


def parse(raw):
    d = unpack(raw)
    version, size, nlevels, name, desc, pos = parse_header(d)
    cells_at, corner_list = diamond(size), corners(size)
    heights_at = len(d) - nlevels * len(corner_list)
    count = nlevels * len(cells_at)
    for start in range(pos, heights_at - 11 * count + 1):
        cells, end = parse_cells(d, start, count, heights_at)
        if cells is not None and end == heights_at:
            break
    else:
        raise ValueError("terrain cells not found")
    levels = []
    for lv in range(nlevels):
        part = cells[lv * len(cells_at):(lv + 1) * len(cells_at)]
        hb = d[heights_at + lv * len(corner_list):heights_at + (lv + 1) * len(corner_list)]
        levels.append(Level(dict(zip(cells_at, part)), dict(zip(corner_list, hb))))
    return Map(version, size, name, desc, levels, bytes(d[pos:start]))


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    m = parse(open(argv[1], "rb").read())
    print(f"{m.name!r} v{m.version}: {m.size}x{m.size}, {len(m.levels)} level(s), "
          f"{len(m.objects)} bytes before the cells")
    for i, lv in enumerate(m.levels):
        types = Counter((c.type, c.variant) for c in lv.cells.values())
        over = sum(len(c.overlays) for c in lv.cells.values())
        roads = sum(len(c.roads) for c in lv.cells.values())
        road_cells = sum(1 for c in lv.cells.values() if c.road)
        extra = Counter(c.extra[1:] for c in lv.cells.values())
        hs = list(lv.heights.values())
        print(f" level {i}: " + ", ".join(f"{TERRAIN_NAMES[t]}/{v} x{n}" for (t, v), n in types.most_common()))
        print(f"   {over} overlays, {road_cells} road cells, {roads} road pieces, height max {max(hs)}, "
              f"{sum(1 for h in hs if h)} raised corners, unknown bytes {extra.most_common(3)}")


if __name__ == "__main__":
    main(sys.argv)
