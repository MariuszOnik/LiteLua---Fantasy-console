"""Tests for tools/h4map.py on synthetic maps (game data never goes into the repo).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import gzip
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4map  # noqa: E402
import h4objects  # noqa: E402

GRASS = bytes([1, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0])


def make_map(size=76, levels=1, cells=None, heights=None, objects=b""):
    """A version-29 map: header, `objects` bytes, cells (default all grass), heights."""
    name, desc = b"test", b""
    d = struct.pack("<HHHBIB", 29, 0, size, levels, 0, 0)
    d += struct.pack("<H", len(name)) + name + b"\x01" + struct.pack("<H", len(desc)) + desc
    d += objects
    ncells, ncorners = len(h4map.diamond(size)), len(h4map.corners(size))
    d += cells if cells is not None else GRASS * ncells * levels
    d += heights if heights is not None else bytes(ncorners * levels)
    return b"H4CAMPAIGN" + struct.pack("<IB", 22, 0) + gzip.compress(d)


class TestH4Map(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(len(h4map.diamond(76)), 2964)
        self.assertEqual(len(h4map.corners(76)), 3117)
        self.assertEqual(len(h4map.corners(152)), 12009)

    def test_flat_map_with_padding_that_looks_like_cells(self):
        # bytes before the cells repeat the cell pattern: only the exact end may decide
        m = h4map.parse(make_map(objects=GRASS[3:] + GRASS * 5))
        self.assertEqual(m.size, 76)
        self.assertEqual(len(m.objects), len(GRASS[3:] + GRASS * 5))
        cells = m.levels[0].cells
        self.assertEqual(len(cells), 2964)
        self.assertTrue(all(c.type == 1 and not c.overlays for c in cells.values()))

    def test_heights_follow_corner_order(self):
        corners = h4map.corners(76)
        hb = bytes(i % 251 for i in range(len(corners)))
        lv = h4map.parse(make_map(heights=hb)).levels[0]
        for i in (0, 1500, len(corners) - 1):
            self.assertEqual(lv.height(*corners[i]), i % 251)
        self.assertEqual(lv.height(0, 0), 0)                  # outside the diamond

    def test_road_byte(self):
        n = len(h4map.diamond(76))
        road = bytes([1, 0, 1, 0, 0, 0, 0, 8, 0, 0, 0])       # grass, road type 1
        cells = h4map.parse(make_map(cells=road + GRASS * (n - 1))).levels[0].cells
        self.assertEqual(cells[h4map.diamond(76)[0]].road, 1)
        self.assertEqual(cells[h4map.diamond(76)[1]].road, 0)

    def test_overlays_roads_and_two_levels(self):
        n = len(h4map.diamond(76))
        special = bytes([0, 1, 0, 0, 0, 0, 0, 8, 0, 2]) + bytes([1, 0, 6, 0, 7, 6, 0, 24, 0, 5])
        special += bytes([1, 2, 9, 0, 3])                    # one cobblestone road piece
        under = bytes([8, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0])
        cells = special + GRASS * (n - 1) + under * n
        ncorners = len(h4map.corners(76))
        heights = bytes(ncorners) + bytes([200]) + bytes(ncorners - 1)
        m = h4map.parse(make_map(levels=2, cells=cells, heights=heights))
        first = m.levels[0].cells[h4map.diamond(76)[0]]
        self.assertEqual((first.type, first.variant), (0, 1))
        self.assertEqual(first.overlays, [(1, 0, 6, 7), (6, 0, 24, 5)])
        self.assertEqual(first.roads, [(2, 9, 3)])
        self.assertTrue(all(c.type == 8 for c in m.levels[1].cells.values()))
        self.assertEqual(m.levels[1].height(*h4map.corners(76)[0]), 200)
        self.assertEqual(max(m.levels[0].heights.values()), 0)


def object_record(row, col, name, cats=("decorative", "tree", "pine"), body=b""):
    def s16(t):
        return struct.pack("<H", len(t)) + t.encode()
    rec = struct.pack("<iiBI", row, col, 0, 0) + s16(name) + struct.pack("<H", 0)
    for i, c in enumerate(cats):
        rec += struct.pack("<H", i) + s16(c)
    return rec + body


def model_header(w, h, occupied, top=(), left=()):
    def mask(n, cells):
        b = bytearray((n + 7) // 8)
        for i in cells:
            b[i // 8] |= 1 << (i % 8)
        return bytes(b)
    return (struct.pack("<HBHHH", 6, 0, 1, w, h) + mask(w * h, occupied)
            + mask((h + 1) * w, top) + mask((w + 1) * h, left))


class TestObjects(unittest.TestCase):
    def test_find_objects(self):
        objects = bytes([6, 0, 0, 0]) + object_record(35, 8, "castle.Asylum.Fort", ("town", "chaos", "left"),
                                                    b"seq" + bytes(40))
        objects += object_record(29, 20, "trees.Desert.04")
        m = h4map.parse(make_map(objects=objects))
        found = h4map.find_objects(m, {"castle.asylum.fort", "trees.desert.04"})
        self.assertEqual([(o.row, o.col, o.name, o.type, o.kind) for o in found],
                         [(35, 8, "castle.Asylum.Fort", "town", "left"),
                          (29, 20, "trees.Desert.04", "decorative", "pine")])

    def test_model_footprint_and_gate(self):
        # 2 x 2, all occupied; an entry edge on the +row side of cell (1, 0): left bit x * h + y
        md = h4objects.parse_model(model_header(2, 2, range(4), left=[2 * 2 + 0]))
        self.assertEqual(sorted(md.occupied), [(0, 0), (0, 1), (1, 0), (1, 1)])
        self.assertEqual(md.triggers(), {(1, 0)})

    def test_passability(self):
        n = len(h4map.diamond(76))
        water = bytes([0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0])
        m = h4map.parse(make_map(cells=water + GRASS * (n - 1)))
        first = h4map.diamond(76)[0]

        class Fake:
            def get(self, name):
                return h4objects.parse_model(model_header(1, 2, [0, 1], left=[1 * 2 + 0]))
        obj = h4map.Placed(37, 37, 0, "mine.Gold", "mine", "gold_mine", "left", 0)
        p = h4objects.passability(m, 0, [obj], Fake())
        self.assertEqual(p[first], "water")
        self.assertEqual(p[(37, 37)], "trigger")
        self.assertEqual(p[(37, 38)], "blocked")


if __name__ == "__main__":
    unittest.main()
