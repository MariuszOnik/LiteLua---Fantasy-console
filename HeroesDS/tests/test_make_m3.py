"""Tests for tools/make_m3.py (the flat textured 3D map for the 3DS).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
try:
    import mapbox_earcut  # noqa: F401
    import make_m3
except ImportError:
    make_m3 = None


def tri_area(v, idx):
    a = 0.0
    for t in range(0, len(idx), 3):
        (x1, _, z1, _), (x2, _, z2, _), (x3, _, z3, _) = (v[i] for i in idx[t:t + 3])
        a += abs((x2 - x1) * (z3 - z1) - (x3 - x1) * (z2 - z1)) / 2
    return a


@unittest.skipIf(make_m3 is None, "needs mapbox_earcut")
class MeshTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = make_m3.m2.generate(5, 40, 14, 1.0)
        cls.regions, cls.chains = make_m3.build(cls.m)

    def test_outlines_close(self):
        # a province touching itself diagonally: rings are still simple loops
        prov = np.array([[0, 0, 1], [0, 1, 1], [2, 2, 1]])
        rings = make_m3.outlines(prov)
        for a, rs in rings.items():
            for ring in rs:
                self.assertEqual(len(ring), len(set(ring)), (a, ring))

    def test_tops_cover_the_map(self):
        # the borders move, but the tops still tile the whole grid
        rows, cols = self.m["province"].shape
        total = sum(tri_area(r["verts"], r["idx"][:r["top"]]) for r in self.regions)
        self.assertAlmostEqual(total, rows * cols, delta=rows * cols * 0.01)

    def test_each_region_keeps_its_size(self):
        prov = self.m["province"]
        for r in self.regions:
            cells = int((prov == r["id"]).sum())
            got = tri_area(r["verts"], r["idx"][:r["top"]])
            self.assertAlmostEqual(got, cells, delta=max(2.0, cells * 0.15), msg=r["name"])

    def test_borders_do_not_cross(self):
        lines = {k: (p, k[1]) for k, (p, _) in self.chains.cache.items()}
        self.assertEqual(make_m3.crossings(lines), set())

    def test_vertex_limit_and_flat(self):
        for r in self.regions:
            self.assertLess(len(r["verts"]), 65536)
            self.assertEqual({v[1] for v in r["verts"]}, {0.0})

    def test_tile_order_is_a_permutation(self):
        for size in (8, 64):
            order = make_m3.tile_order(size).ravel()
            self.assertEqual(sorted(order), list(range(size * size)))

    def test_mip_levels(self):
        img = np.zeros((64, 64, 3), np.uint8)
        levels = make_m3.mip_levels(img)
        self.assertEqual([lv.shape[0] for lv in levels], [64, 32, 16, 8])

    def test_texture_ids_match_regions(self):
        old = make_m3.TEX
        make_m3.TEX = 256
        try:
            rgb, ids = make_m3.render_texture(self.m, self.regions, self.chains, size=256)
        finally:
            make_m3.TEX = old
        self.assertEqual(rgb.shape, (256, 256, 3))
        rows, cols = self.m["province"].shape
        prov = self.m["province"]
        # a cell whose whole neighbourhood is one region: its middle pixel says that region
        index = {r["id"]: i for i, r in enumerate(self.regions)}
        hits = 0
        for r in range(2, rows - 2):
            for c in range(2, cols - 2):
                block = prov[r - 2:r + 3, c - 2:c + 3]
                if (block == prov[r, c]).all():
                    y, x = int((r + 0.5) * 256 / rows), int((c + 0.5) * 256 / cols)
                    self.assertEqual(ids[y, x], index[int(prov[r, c])])
                    hits += 1
        self.assertGreater(hits, 50)

    def test_file_layout(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "map3d.bin")
            nv, ni = make_m3.write(path, self.m, self.regions)
            with open(path, "rb") as f:
                data = f.read()
        magic, ver, nreg, nland, nfac = struct.unpack_from("<4sHHHH", data)
        self.assertEqual((magic, ver, nreg, nland), (b"HM3D", 3, len(self.regions), self.m["land"]))
        off = 28 + 20 * nfac + 80 * nreg
        nn = sum(len(r["neigh"]) for r in self.regions)
        size = off + ((2 * nn + 3) & ~3) + 16 * nv + ((2 * ni + 3) & ~3)
        self.assertEqual(len(data), size)


if __name__ == "__main__":
    unittest.main()
