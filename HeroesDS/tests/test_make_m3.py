"""Tests for tools/make_m3.py (province meshes for the 3DS map).

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
        cls.regions, cls.borders = make_m3.build(cls.m)

    def test_outlines_close(self):
        # a 2x2 province with a diagonal pinch elsewhere: rings are closed loops
        prov = np.array([[0, 0, 1], [0, 1, 1], [2, 2, 1]])
        rings = make_m3.outlines(prov)
        for a, rs in rings.items():
            for ring in rs:
                self.assertEqual(len(ring), len(set(ring)), (a, ring))

    def test_tops_cover_the_map(self):
        # smoothing moves borders, but the tops still tile the whole grid
        rows, cols = self.m["province"].shape
        total = sum(tri_area(r["verts"], r["idx"][:r["top"]]) for r in self.regions)
        self.assertAlmostEqual(total, rows * cols, delta=rows * cols * 0.01)

    def test_each_region_keeps_its_size(self):
        prov = self.m["province"]
        for r in self.regions:
            cells = int((prov == r["id"]).sum())
            got = tri_area(r["verts"], r["idx"][:r["top"]])
            self.assertAlmostEqual(got, cells, delta=max(2.0, cells * 0.15), msg=r["name"])

    def test_vertex_limit_and_heights(self):
        for r in self.regions:
            self.assertLess(len(r["verts"]), 65536)
            ys = {v[1] for v in r["verts"][:1]}
            want = 0.0 if r["kind"] == make_m3.KIND_SEA else make_m3.LAND_H
            self.assertEqual(ys, {want})

    def test_file_layout(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "map3d.bin")
            nv, ni, nb = make_m3.write(path, self.m, self.regions, self.borders)
            with open(path, "rb") as f:
                data = f.read()
        magic, ver, nreg, nland, nfac = struct.unpack_from("<4sHHHH", data)
        self.assertEqual((magic, ver, nreg, nland), (b"HM3D", 1, len(self.regions), self.m["land"]))
        off = 28 + 20 * nfac + 76 * nreg
        bc = struct.unpack_from("<3I", data, off)
        self.assertEqual(sum(bc), nb)
        nn = sum(len(r["neigh"]) for r in self.regions)
        size = off + 12 + ((2 * nn + 3) & ~3) + 16 * nv + ((2 * ni + 3) & ~3) + 12 * nb
        self.assertEqual(len(data), size)


if __name__ == "__main__":
    unittest.main()
