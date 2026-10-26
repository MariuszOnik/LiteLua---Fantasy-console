"""Tests for tools/h4atlas.py helpers (packing, palette, Lua output).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import sys
import unittest

from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4atlas  # noqa: E402


class PackTest(unittest.TestCase):
    def test_power_of_two_and_no_overlap(self):
        sizes = [(40, 50), (52, 49), (30, 70), (60, 20), (10, 10)]
        W, H, pos = h4atlas.pack(sizes)
        self.assertIn(W, (8, 16, 32, 64, 128, 256, 512, 1024))
        self.assertIn(H, (8, 16, 32, 64, 128, 256, 512, 1024))
        boxes = [(x, y, x + w, y + h) for (x, y), (w, h) in zip(pos, sizes)]
        for b in boxes:
            self.assertTrue(b[2] <= W and b[3] <= H)
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                self.assertFalse(a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3])

    def test_prefers_square_on_equal_area(self):
        W, H, _ = h4atlas.pack([(100, 100)] * 4)
        self.assertEqual((W, H), (256, 256))

    def test_too_big(self):
        with self.assertRaises(ValueError):
            h4atlas.pack([(2000, 10)])


class PaletteTest(unittest.TestCase):
    def test_index_zero_is_transparent(self):
        img = Image.new("RGBA", (4, 1))
        img.putdata([(0, 0, 0, 0), (255, 0, 0, 255), (0, 0, 255, 255), (255, 0, 0, 255)])
        p = h4atlas.to_palette(img, 255)
        self.assertEqual(p.mode, "P")
        self.assertEqual(p.info["transparency"], 0)
        px = h4atlas.pixels(p)
        self.assertEqual(px[0], 0)
        self.assertNotIn(0, px[1:])
        self.assertEqual(px[1], px[3])
        pal = p.getpalette()
        self.assertEqual(tuple(pal[px[1] * 3:px[1] * 3 + 3]), (255, 0, 0))

    def test_color_limit(self):
        img = Image.new("RGBA", (64, 1))
        img.putdata([(i * 4, 255 - i * 4, 0, 255) for i in range(64)])
        p = h4atlas.to_palette(img, 15)
        self.assertLessEqual(max(h4atlas.pixels(p)), 15)


class LuaTest(unittest.TestCase):
    def test_lua(self):
        text = h4atlas.lua(dict(fps=9, scale=0.5, image="a\"b", frames=[1, 2], rects=[[0, 0, 4, 4, -2, -4]], shadow=False))
        self.assertIn("fps = 9,", text)
        self.assertIn("scale = 0.5,", text)
        self.assertIn('image = "a\\"b",', text)
        self.assertIn("frames = { 1, 2 },", text)
        self.assertIn("{ 0, 0, 4, 4, -2, -4 },", text)
        self.assertIn("shadow = false,", text)


if __name__ == "__main__":
    unittest.main()
