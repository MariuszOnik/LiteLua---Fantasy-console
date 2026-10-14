# SPDX-License-Identifier: Zlib
#
# Tests of tools/tiledmap.py (Tiled JSON -> LiteLua map, P8):
#   python -m unittest discover -s tests/tools -v

import base64
import json
import pathlib
import sys
import tempfile
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import lsong  # noqa: E402  (parse_lua reads the output back)
import tiledmap  # noqa: E402

FIXTURE = pathlib.Path(__file__).with_name("data") / "level2.tmj"


def tiled(layers, tw=16, **extra):
    m = {
        "orientation": "orthogonal", "infinite": False, "width": 4, "height": 3,
        "tilewidth": tw, "tileheight": tw, "layers": layers,
        "tilesets": [{
            "firstgid": 1, "name": "tiles", "image": "../gfx/tiles.png", "tilecount": 32,
            "tiles": [
                {"id": 0, "properties": [{"name": "solid", "type": "bool", "value": True}]},
                {"id": 1, "properties": [{"name": "solid", "type": "bool", "value": True}]},
                {"id": 2, "properties": [{"name": "solid", "type": "bool", "value": True}]},
                {"id": 6, "type": "hurt"},
                {"id": 7, "properties": [{"name": "coin", "type": "bool", "value": True},
                                         {"name": "score", "type": "int", "value": 10}]},
            ],
        }],
    }
    m.update(extra)
    return m


def layer(name, data, **extra):
    d = {"type": "tilelayer", "name": name, "width": 4, "height": 3, "data": data}
    d.update(extra)
    return d


class TiledMapTest(unittest.TestCase):
    def test_basic(self):
        m, warn = tiledmap.convert(tiled([
            layer("back", [0, 0, 14, 0] + [0] * 8),
            layer("main", [0, 8, 0, 0, 0, 0, 0, 7, 1, 2, 3, 1]),
        ]))
        self.assertEqual(warn, [])
        self.assertEqual((m["tile"], m["w"], m["h"]), (16, 4, 3))
        self.assertEqual([l["name"] for l in m["layers"]], ["back", "main"])
        self.assertEqual(m["layers"][1]["tileset"], "tiles")
        self.assertEqual(m["layers"][1]["data"][2], [1, 2, 3, 1])
        self.assertEqual(m["flags"], {"coin": [8], "hurt": [7], "solid": ["1-3"]})

    def test_lua_output_parses(self):
        m, _ = tiledmap.convert(tiled([layer("main", [1, 2, 3, 0] * 3)]))
        data = lsong.parse_lua(tiledmap.to_lua(m, "x.tmj"))
        self.assertEqual(data["mode"], "platform")
        self.assertEqual(data["layers"][0]["data"][1], [1, 2, 3, 0])
        self.assertEqual(data["flags"]["solid"], ["1-3"])

    def test_base64_zlib_and_flips(self):
        gids = [1, 2 | 0x80000000, 0, 0] + [0] * 8
        raw = b"".join(g.to_bytes(4, "little") for g in gids)
        enc = base64.b64encode(zlib.compress(raw)).decode()
        m, warn = tiledmap.convert(tiled([
            layer("main", enc, encoding="base64", compression="zlib")]))
        self.assertEqual(m["layers"][0]["data"][0], [1, 2, 0, 0])
        self.assertTrue(any("flipped" in w for w in warn))

    def test_object_layer_skipped(self):
        m, warn = tiledmap.convert(tiled([
            layer("main", [1] * 12), {"type": "objectgroup", "name": "spawns"}]))
        self.assertEqual(len(m["layers"]), 1)
        self.assertTrue(any("spawns" in w for w in warn))

    def test_errors(self):
        bad = [
            tiled([layer("main", [1] * 12)], orientation="isometric"),
            tiled([layer("main", [1] * 12)], infinite=True),
            tiled([layer("main", [1] * 12)], tw=12),
            tiled([layer("main", [1] * 11)]),
            tiled([layer(str(i), [1] * 12) for i in range(5)]),
            tiled([{"type": "objectgroup", "name": "only objects"}]),
        ]
        for t in bad:
            with self.assertRaises(tiledmap.TiledError):
                tiledmap.convert(t)

    def test_two_tilesets_in_one_layer(self):
        t = tiled([layer("main", [1, 40, 0, 0] + [0] * 8)])
        t["tilesets"].append({"firstgid": 33, "name": "more", "image": "more.png",
                              "tilecount": 16})
        with self.assertRaises(tiledmap.TiledError):
            tiledmap.convert(t)

    def test_fixture_matches_cart(self):
        # tests/carts/map/map/level2.lua is the converted fixture
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d) / "level2.lua"
            tiledmap.convert_file(FIXTURE, out)
            cart = ROOT / "tests" / "carts" / "map" / "map" / "level2.lua"
            self.assertEqual(out.read_text(encoding="utf-8"),
                             cart.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
