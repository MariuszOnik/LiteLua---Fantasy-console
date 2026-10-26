"""Tests of the combat engine in Lua (HeroesDS/combat): runs combat_test.lua with Lua 5.4
from the lupa package (skipped when it is not installed: pip install lupa).

Run from the repo root:  python -m unittest discover -s HeroesDS/tests
"""
import pathlib
import unittest

try:
    import lupa.lua54 as lua54
except ImportError:
    lua54 = None

HEROES = pathlib.Path(__file__).resolve().parents[1]
TEST = pathlib.Path(__file__).with_name("combat_test.lua")


@unittest.skipIf(lua54 is None, "lupa (Lua 5.4 for Python) is not installed")
class CombatTest(unittest.TestCase):
    def test_rules(self):
        rt = lua54.LuaRuntime()
        run = rt.eval("function(path, root) return assert(loadfile(path))(root) end")
        count = run(str(TEST), HEROES.as_posix())
        self.assertGreater(count, 10)


if __name__ == "__main__":
    unittest.main()
