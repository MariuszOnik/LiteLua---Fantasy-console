"""Tests for tools/h4table.py and tools/make_rules.py helpers (synthetic data).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import h4table  # noqa: E402
import make_rules  # noqa: E402


def s16(text):
    b = text.encode("cp1250")
    return struct.pack("<H", len(b)) + b


def table(rows, groups=None):
    b = struct.pack("<I", len(rows))
    if groups is not None:
        b += struct.pack("<I", len(groups) + 1) + b"".join(s16(g) for g in groups)
    for r in rows:
        b += struct.pack("<H", len(r)) + b"".join(s16(c) for c in r)
    return b


class TableTest(unittest.TestCase):
    def test_with_groups(self):
        rows = [["Keyword", "Name", "Low"], ["bandit", "bandyta", "1"], ["imp", "chochlik", "1"]]
        groups, out = h4table.parse(table(rows, ["", "Dmg"]))
        self.assertEqual(groups, ["", "Dmg"])
        self.assertEqual(out, rows)

    def test_without_groups(self):
        rows = [["hero1", "Ąnna", "f"], ["hero2", "Żbik", "m"]]
        _, out = h4table.parse(table(rows))
        self.assertEqual(out, rows)       # cp1250 text survives

    def test_records(self):
        recs = h4table.records([["Keyword", "", "Level"], ["bandit", "x", "1"], ["imp"]])
        self.assertEqual(recs[0], {"Keyword": "bandit", "Level": "1"})
        self.assertEqual(recs[1], {"Keyword": "imp", "Level": ""})


class RulesTest(unittest.TestCase):
    def test_num(self):
        self.assertEqual(make_rules.num(" 27 "), 27)
        self.assertEqual(make_rules.num(""), 0)
        self.assertEqual(make_rules.num("n/a", 5), 5)

    def test_fallback_abilities(self):
        name2kw = {"latanie": "flying", "krótki zasięg": "short_range"}
        self.assertEqual(make_rules.fallback_abilities("Latanie, Coś", 0, name2kw), ["flying"])
        self.assertEqual(make_rules.fallback_abilities("Krótki zasięg", 6, name2kw), ["short_range", "ranged"])

    def test_lua_value(self):
        text = make_rules.lua_value({"hp": 10, "dmg": [1, 3], "abilities": {"flying": True},
                                     "cost": {"gold": 20}, "3_headed": True})
        self.assertEqual(text, '{ hp = 10, dmg = { 1, 3 }, abilities = { flying = true }, '
                               'cost = { gold = 20 }, ["3_headed"] = true }')


if __name__ == "__main__":
    unittest.main()
