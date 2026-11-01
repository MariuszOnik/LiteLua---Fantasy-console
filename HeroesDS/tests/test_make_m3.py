"""Tests for tools/make_m3.py (the flat textured 3D map for the 3DS, in tiles, with
counties and detail by distance).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import struct
import sys
import tempfile
import unittest
import zlib

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
        cls.regions, cls.counties, cls.borders, cls.chains = make_m3.build(cls.m)
        cls.land = [i for i, c in enumerate(cls.counties) if cls.regions[c["region"]]["kind"] != make_m3.KIND_SEA]

    def paint(self, x0, z0, span, size):
        painter = make_m3.Painter(self.m, self.counties, self.chains)
        return painter.paint(x0, z0, span, size, self.land)

    def test_outlines_close(self):
        # a province touching itself diagonally: rings are still simple loops
        prov = np.array([[0, 0, 1], [0, 1, 1], [2, 2, 1]])
        rings = make_m3.outlines(prov)
        for a, rs in rings.items():
            for ring in rs:
                self.assertEqual(len(ring), len(set(ring)), (a, ring))

    def test_counties_split_provinces(self):
        rng = np.random.default_rng(1)
        grid, prov_of = make_m3.counties(self.m, rng)
        prov = self.m["province"]
        for c, p in enumerate(prov_of):
            self.assertTrue((prov[grid == c] == p).all())
        # big land provinces get several counties, sea zones one
        for p in range(self.m["land"]):
            cells = int((prov == p).sum())
            if cells >= 3 * make_m3.COUNTY_CELLS:
                self.assertGreater(prov_of.count(p), 1)
        for p in range(self.m["land"], len(self.m["names"])):
            self.assertLessEqual(prov_of.count(p), 1)

    def test_tops_cover_the_map(self):
        # the borders move, but the tops still tile the whole grid
        rows, cols = self.m["province"].shape
        total = sum(tri_area(r["verts"], r["idx"][:r["top"]]) for r in self.regions)
        self.assertAlmostEqual(total, rows * cols, delta=rows * cols * 0.01)

    def test_selectable_counties_tile_their_province(self):
        # counties that can be selected (several in a province) have shapes; together
        # they cover the province's top
        by_region = {}
        for c in self.counties:
            if c["verts"]:
                by_region.setdefault(c["region"], []).append(tri_area(c["verts"], c["idx"][:c["top"]]))
        self.assertTrue(by_region)
        for reg, areas in by_region.items():
            self.assertGreater(len(areas), 1)
            r = self.regions[reg]
            whole = tri_area(r["verts"], r["idx"][:r["top"]])
            self.assertAlmostEqual(sum(areas), whole, delta=whole * 0.01, msg=r["name"])

    def test_each_region_keeps_its_size(self):
        prov = self.m["province"]
        for r in self.regions:
            cells = int((prov == r["id"]).sum())
            got = tri_area(r["verts"], r["idx"][:r["top"]])
            self.assertAlmostEqual(got, cells, delta=max(2.0, cells * 0.15), msg=r["name"])

    def test_borders_do_not_cross(self):
        lines = {k: (p, k[1]) for k, (p, _) in self.chains.cache.items()}
        self.assertEqual(make_m3.crossings(lines), set())

    def test_province_borders_join_provinces(self):
        self.assertTrue(self.borders)
        for b in self.borders:
            self.assertNotEqual(b["a"], b["b"])
            for side in (b["a"], b["b"]):
                self.assertNotEqual(self.regions[side]["kind"], make_m3.KIND_SEA)

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

    def test_texture_ids_match_counties(self):
        rows, cols = self.m["province"].shape
        rgb, ids = self.paint(0, 0, cols, 256)
        self.assertEqual([lv.shape[0] for lv in rgb], [256, 128, 64, 32, 16, 8])
        self.assertEqual(ids[0].dtype, np.uint16)
        grid, _ = make_m3.counties(self.m, np.random.default_rng(self.m["seed"] + 77))
        # a cell whose whole neighbourhood is one county: its middle pixel says that county
        hits = 0
        for r in range(2, rows - 2):
            for c in range(2, cols - 2):
                block = grid[r - 2:r + 3, c - 2:c + 3]
                if (block == grid[r, c]).all():
                    y, x = int((r + 0.5) * 256 / rows), int((c + 0.5) * 256 / cols)
                    self.assertEqual(ids[0][y, x], grid[r, c])
                    hits += 1
        self.assertGreater(hits, 30)

    def test_far_levels_drop_inner_lines(self):
        # at 2 pixels per cell (under K_PROVINCE) the land shows no province lines:
        # its pixels stay paper-coloured, only the coast is dark
        cols = self.m["province"].shape[1]
        rgb, ids = self.paint(0, 0, cols, 2 * cols // 8 * 8)
        lv = rgb[0].astype(int)
        land = np.isin(ids[0], self.land)
        inner = land.copy()
        for dy in (-2, 0, 2):
            for dx in (-2, 0, 2):
                inner &= np.roll(np.roll(land, dy, 0), dx, 1)
        dark = lv[inner].sum(1) < 300
        self.assertLess(dark.mean(), 0.02)

    def test_tiles_match_the_whole(self):
        # the north-east quarter drawn as a tile equals that quarter of the whole map at
        # the same scale: no seams between tiles
        cols = self.m["province"].shape[1]
        whole_rgb, whole_ids = self.paint(0, 0, cols, 128)
        tile_rgb, tile_ids = self.paint(cols / 2, 0, cols / 2, 64)
        self.assertGreater((tile_ids[0] == whole_ids[0][:64, 64:]).mean(), 0.99)
        diff = np.abs(tile_rgb[0].astype(int) - whole_rgb[0][:64, 64:].astype(int))
        self.assertLess(diff.mean(), 3)

    def test_styles_have_no_seams(self):
        # every surface (and the burnt edge) is laid over the whole map: a tile still
        # equals its quarter of the whole map
        cols = self.m["province"].shape[1]
        styles = os.path.join(os.path.dirname(__file__), "..", "styles")
        for name in ("parchment", "leather", "parchment-image"):
            style, folder = make_m3.load_style(os.path.join(styles, name + ".lua"))
            painter = make_m3.Painter(self.m, self.counties, self.chains, style, folder)
            whole, _ = painter.paint(0, 0, cols, 128, self.land)
            tile, _ = painter.paint(cols / 2, 0, cols / 2, 64, self.land)
            diff = np.abs(tile[0].astype(int) - whole[0][:64, 64:].astype(int))
            self.assertLess(diff.mean(), 4, name)

    def test_classic_style_is_the_default(self):
        styles = os.path.join(os.path.dirname(__file__), "..", "styles")
        style, _ = make_m3.load_style(os.path.join(styles, "classic.lua"))
        self.assertEqual(style, make_m3.map_style({}))

    def test_grain_repeats_without_a_seam(self):
        g = make_m3.grain_texture(1, 64).astype(int)
        inner = np.abs(np.diff(g, axis=1)).mean()
        across = np.abs(g[:, 0] - g[:, -1]).mean()   # the right edge meets the left
        self.assertLess(across, 2 * inner)
        self.assertLess(abs(g.mean() - 128), 6)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "grain.bin")
            make_m3.write_grain(path, 1)
            with open(path, "rb") as f:
                data = f.read()
        self.assertEqual(data[:4], b"HG01")
        size, raw, packed = struct.unpack_from("<III", data, 4)
        self.assertEqual(raw, sum((size >> k) ** 2 for k in range(6)))   # 256 .. 8
        self.assertEqual(len(zlib.decompress(data[16:16 + packed])), raw)

    def test_tile_file(self):
        rgb, ids = self.paint(0, 0, self.m["province"].shape[1], 64)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t.bin")
            make_m3.write_tile(path, rgb, ids)
            with open(path, "rb") as f:
                data = f.read()
        self.assertEqual(data[:4], b"HT01")
        pixels = sum((64 >> k) ** 2 for k in range(4))   # 64, 32, 16, 8
        off = 4
        for _ in range(2):
            raw, packed = struct.unpack_from("<II", data, off)
            self.assertEqual(raw, pixels * 2)
            self.assertEqual(len(zlib.decompress(data[off + 8:off + 8 + packed])), raw)
            off += 8 + ((packed + 3) & ~3)
        self.assertEqual(off, len(data))

    def test_file_layout(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "map3d.bin")
            nv, ni = make_m3.write(path, self.m, self.regions, self.counties, self.borders, 2)
            with open(path, "rb") as f:
                data = f.read()
        magic, ver, nreg, nland, nfac = struct.unpack_from("<4sHHHH", data)
        self.assertEqual((magic, ver, nreg, nland), (b"HM3D", 6, len(self.regions), self.m["land"]))
        tiles, ncty = struct.unpack_from("<HH", data, 28)
        self.assertEqual((tiles, ncty), (2, len(self.counties)))
        off = 32 + 20 * nfac + 80 * nreg + 52 * ncty
        nn = sum(len(r["neigh"]) for r in self.regions)
        off += ((2 * nn + 3) & ~3) + 16 * nv + ((2 * ni + 3) & ~3)
        nb, nlv = struct.unpack_from("<II", data, off)
        self.assertEqual(nb, len(self.borders))
        starts = [struct.unpack_from("<HHII", data, off + 8 + 12 * i) for i in range(nb)]
        self.assertEqual(sum(s[3] for s in starts), nlv)
        self.assertEqual(len(data), off + 8 + 12 * nb + 16 * nlv)

    def scenario_file(self, scen):
        """The scenario written out and read back like a file from the user."""
        text = make_m3.scenario_lua(scen, self.regions, self.counties)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "s.lua")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            return make_m3.load_scenario(path, self.regions, self.counties)

    def test_default_scenario_round_trip(self):
        scen = make_m3.default_scenario(self.m, self.regions, self.counties, cities=2)
        back = self.scenario_file(scen)
        self.assertEqual(back["player"], scen["player"])
        self.assertEqual(back["realms"], scen["realms"])
        self.assertEqual(back["provinces"], scen["provinces"])
        # city-states come only from realms with more than three provinces
        cities = [r for r in back["realms"] if r.get("city")]
        self.assertLessEqual(len(cities), 2)
        owned = {e["owner"] for e in back["provinces"] if "owner" in e}
        for c in cities:
            self.assertIn(c["id"], owned)

    def test_scenario_errors(self):
        scen = make_m3.default_scenario(self.m, self.regions, self.counties)
        land = next(e for e in scen["provinces"] if "owner" in e)
        sea = next(e for e in scen["provinces"] if "owner" not in e)
        cases = [
            lambda s: s.update(player="nobody"),
            lambda s: land.update(owner="nobody"),
            lambda s: sea.update(owner=s["realms"][0]["id"]),
            lambda s: s["realms"].append(dict(s["realms"][0])),
            lambda s: land.update(name="x" * 30),
        ]
        for spoil in cases:
            bad = make_m3.default_scenario(self.m, self.regions, self.counties)
            land = next(e for e in bad["provinces"] if "owner" in e)
            sea = next(e for e in bad["provinces"] if "owner" not in e)
            spoil(bad)
            with self.assertRaises(ValueError):
                make_m3.check_scenario(bad, self.regions, self.counties)


if __name__ == "__main__":
    unittest.main()
