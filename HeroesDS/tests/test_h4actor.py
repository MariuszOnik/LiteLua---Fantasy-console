"""Tests for tools/h4actor.py on synthetic actor files (game data never goes into the repo).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4actor  # noqa: E402


def s(text):
    return struct.pack("<H", len(text)) + text.encode()


def state(name, fps, dirs, hit=None):
    b = s(name) + bytes([fps]) + (bytes([hit]) if hit is not None else b"")
    return b + b"".join(s(d) for d in dirs)


FOUR = ["imp.combat.die.ne", "imp.combat.die.se", "imp.combat.die.se", "imp.combat.die.sw",
        "imp.combat.die.sw", "imp.combat.die.sw", "imp.combat.die.nw", "imp.combat.die.ne"]
EIGHT = [f"imp.combat.melee.{d}" for d in h4actor.DIRECTIONS]


class CombatActorTest(unittest.TestCase):
    def setUp(self):
        b = struct.pack("<HBB3H", 6, 3, 70, 16, 48, 16)
        b += b"".join(struct.pack("<3i", i, 2, 40) for i in range(8))
        b += struct.pack("<H", 3) + state("block", 9, [""] * 8, 0) + state("die", 9, FOUR, 0)
        b += state("melee", 10, EIGHT, 6) + struct.pack("<2i", -1, 2)
        self.a = h4actor.parse(b, "combat_actor.imp.h4d")

    def test_header(self):
        a = self.a
        self.assertEqual((a["version"], a["footprint"], a["height"]), (6, 3, 70))
        self.assertEqual(a["distances"], (16, 48, 16))
        self.assertEqual(a["launch"][7], (7, 2, 40))
        self.assertEqual(a["draw_offset"], (-1, 2))
        self.assertEqual(a["rest"], b"")

    def test_states(self):
        st = self.a["states"]
        self.assertEqual(list(st), ["block", "die", "melee"])
        self.assertEqual(st["block"]["dirs"], {})
        self.assertEqual(st["die"]["dirs"]["e"], "imp.combat.die.se")
        self.assertEqual((st["melee"]["fps"], st["melee"]["hit_frame"]), (10, 6))
        self.assertEqual(st["melee"]["dirs"]["n"], "imp.combat.melee.n")

    def test_version5_has_no_launch_block(self):
        b = struct.pack("<HBB3H", 5, 2, 50, 16, 64, 16) + struct.pack("<H", 1) + state("melee", 9, EIGHT, 4)
        a = h4actor.parse(b, "combat_actor.x.h4d")
        self.assertEqual(a["launch"], [])
        self.assertEqual(a["states"]["melee"]["hit_frame"], 4)


class AdvActorTest(unittest.TestCase):
    def test_adv(self):
        dirs = [f"imp.walk.{d}" for d in h4actor.DIRECTIONS]
        b = struct.pack("<HB3H", 3, 1, 4, 32, 4) + struct.pack("<H", 1) + state("walk", 10, dirs)
        b += struct.pack("<4i", 0, -6, -11, -34)
        a = h4actor.parse(b, "adv_actor.imp.h4d")
        self.assertEqual(a["distances"], (4, 32, 4))
        self.assertEqual(a["states"]["walk"]["fps"], 10)
        self.assertEqual(a["states"]["walk"]["dirs"]["sw"], "imp.walk.sw")
        self.assertEqual((a["offset"], a["flag"]), ((0, -6), (-11, -34)))

    def test_wrong_kind(self):
        with self.assertRaises(ValueError):
            h4actor.parse(b"\x03\x00", "actor_sequence.imp.walk.e.h4d")


if __name__ == "__main__":
    unittest.main()
