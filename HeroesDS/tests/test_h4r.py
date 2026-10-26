"""Tests for tools/h4r.py on a synthetic archive (game data never goes into the repo).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import gzip
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4r  # noqa: E402


def pstr(s):
    b = s.encode("latin-1")
    return struct.pack("<H", len(b)) + b


def make_archive(files, aliases):
    """files: {name: bytes}, aliases: {name: target}. Returns archive bytes."""
    blobs, data = {}, b""
    for name, content in files.items():
        packed = gzip.compress(content)
        blobs[name] = (8 + len(data), len(packed), len(content))
        data += packed
    entries = b""
    for name, (off, packed, size) in blobs.items():
        entries += struct.pack("<4I", off, packed, size, 0) + pstr(name) + pstr("C:\\src\\") + pstr("")
        entries += struct.pack("<I", 3)
    for name, target in aliases.items():
        size = len(files[target])
        entries += struct.pack("<4I", 0, 0, size, 0) + pstr(name) + pstr("") + pstr(target)
        entries += struct.pack("<I", 3)
    count = len(files) + len(aliases)
    return b"H4R\x05" + struct.pack("<I", 8 + len(data)) + data + struct.pack("<I", count) + entries


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.files = {"actor_sequence.imp.stand.e.h4d": b"frame data" * 50, "font.small.h4d": b"\x00\x01\x02"}
        fd, self.path = tempfile.mkstemp(suffix=".h4r")
        with os.fdopen(fd, "wb") as f:
            f.write(make_archive(self.files, {"layers.alias.h4d": "font.small.h4d"}))
        self.arc = h4r.Archive(self.path)

    def tearDown(self):
        self.arc.f.close()
        os.remove(self.path)

    def test_directory(self):
        self.assertEqual(len(self.arc.order), 3)
        self.assertEqual(self.arc.order[0].path, "C:\\src\\")
        self.assertEqual(self.arc.entries["layers.alias.h4d"].alias, "font.small.h4d")

    def test_read(self):
        for name, content in self.files.items():
            self.assertEqual(self.arc.read(name), content)

    def test_read_is_case_insensitive(self):
        self.assertEqual(self.arc.read("FONT.Small.h4d"), b"\x00\x01\x02")

    def test_alias(self):
        self.assertEqual(self.arc.read("layers.alias.h4d"), b"\x00\x01\x02")

    def test_find(self):
        self.assertEqual([e.name for e in self.arc.find("IMP")], ["actor_sequence.imp.stand.e.h4d"])

    def test_bad_magic(self):
        with open(self.path, "r+b") as f:
            f.write(b"XXXX")
        with self.assertRaises(ValueError):
            h4r.Archive(self.path)


if __name__ == "__main__":
    unittest.main()
