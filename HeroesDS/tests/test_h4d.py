"""Tests for tools/h4d.py on a synthetic actor_sequence (game data never goes into the repo).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4d  # noqa: E402


def record(name, box, rows, pixels, alphas, palette, kind=4):
    """One image record; rows are (x0, x1) spans, pixels and alphas per span pixel."""
    b = struct.pack("<HHHB", len(palette) + 1, 1, 24, 0)
    b += b"".join(bytes(c[::-1]) for c in palette)
    b += struct.pack("<H", len(name)) + name.encode() + bytes([kind]) + struct.pack("<4I", *box)
    off = 0
    for x0, x1 in rows:
        b += struct.pack("<HHI", x0, x1, off)
        off += x1 - x0
    b += bytes(pixels)
    if kind == 4:
        a = list(alphas) + [0] * (len(alphas) % 2)
        b += bytes(a[i] | a[i + 1] << 4 for i in range(0, len(a), 2))
        if pixels:
            b += bytes(((len(pixels) + 4 + 63) // 64 + 1) // 2)
    return b


def sequence(images, origin=(-361, -347), links=()):
    b = struct.pack("<HHH", 2, 2, len(images)) + b"".join(images)
    b += struct.pack("<iiH", *origin, len(links))
    for name, typ in links:
        b += struct.pack("<H", len(name)) + name.encode() + struct.pack("<H", typ)
    return b


RED, BLUE = (255, 0, 0), (0, 0, 255)


class SequenceTest(unittest.TestCase):
    def setUp(self):
        frame_a = record("frame 001 003", (10, 20, 13, 22), [(0, 2), (1, 3)], [1, 2, 1, 1], [15, 15, 8, 0],
                         [RED, BLUE])
        frame_b = record("frame 002", (11, 20, 13, 21), [(0, 2)], [2, 2], [15, 15], [RED, BLUE])
        shadow = record("shadow 001 003", (9, 21, 14, 23), [(0, 5), (0, 5)], [1] * 10, [7] * 10, [(0, 0, 0)])
        self.seq = h4d.parse(sequence([frame_a, frame_b, shadow], links=[("combat_actor.imp", 2)]))

    def test_images_and_trailer(self):
        self.assertEqual([i.name for i in self.seq.images], ["frame 001 003", "frame 002", "shadow 001 003"])
        self.assertEqual(self.seq.origin, (-361, -347))
        self.assertEqual(self.seq.links, [("combat_actor.imp", 2)])
        self.assertEqual(self.seq.header, struct.pack("<HHH", 2, 2, 3))

    def test_frame_numbers(self):
        self.assertEqual(self.seq.images[0].frames, [1, 3])
        self.assertEqual(self.seq.frame_count(), 3)
        self.assertEqual(self.seq.bounds(), (9, 20, 14, 23))

    def test_pixels_and_alpha(self):
        img = self.seq.images[0].rgba()
        self.assertEqual(img.size, (3, 2))
        self.assertEqual(img.getpixel((0, 0)), RED + (255,))
        self.assertEqual(img.getpixel((1, 0)), BLUE + (255,))
        self.assertEqual(img.getpixel((1, 1)), RED + (8 * 17,))
        self.assertEqual(img.getpixel((2, 1))[3], 0)      # alpha 0 -> transparent
        self.assertEqual(img.getpixel((2, 0))[3], 0)      # outside the span

    def test_render_composites_shadow_under_frame(self):
        frame = self.seq.render(3)                        # same images as frame 1
        self.assertEqual(frame.size, (5, 3))
        self.assertEqual(frame.getpixel((1, 0)), RED + (255,))
        self.assertEqual(frame.getpixel((0, 1))[3], 7 * 17)   # shadow only
        self.assertEqual(self.seq.render(2).getpixel((0, 1))[3], 0)   # frame 2 has no shadow

    def test_delta_frame_is_opaque(self):
        seq = h4d.parse(sequence([record("frame 001", (0, 0, 1, 1), [(0, 1)], [1], [], [RED], kind=1)]))
        self.assertEqual(seq.images[0].rgba().getpixel((0, 0)), RED + (255,))

    def test_garbage(self):
        with self.assertRaises(ValueError):
            h4d.parse(b"\x00" * 64)


if __name__ == "__main__":
    unittest.main()
