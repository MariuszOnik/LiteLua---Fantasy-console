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
HERE = pathlib.Path(__file__).parent


def run_lua(name):
    # A fresh Lua state per file: the modules keep their switches (battle.dead_strike_back)
    rt = lua54.LuaRuntime()
    run = rt.eval("function(path, root) return assert(loadfile(path))(root) end")
    return run(str(HERE / name), HEROES.as_posix())


@unittest.skipIf(lua54 is None, "lupa (Lua 5.4 for Python) is not installed")
class CombatTest(unittest.TestCase):
    def test_rules(self):
        self.assertGreater(run_lua("combat_test.lua"), 10)

    def test_battle(self):
        self.assertGreater(run_lua("battle_test.lua"), 10)

    def test_abilities(self):
        self.assertGreater(run_lua("abilities_test.lua"), 10)

    def test_heroes(self):
        self.assertGreater(run_lua("heroes_test.lua"), 5)

    def test_casting(self):
        self.assertGreater(run_lua("casting_test.lua"), 10)

    def test_ai(self):
        count, _worst = run_lua("ai_test.lua")
        self.assertGreater(count, 5)


if __name__ == "__main__":
    unittest.main()
