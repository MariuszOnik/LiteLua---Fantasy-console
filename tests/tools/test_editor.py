# SPDX-License-Identifier: Zlib
#
# Tests of the on-DS code editor (P11) and the launcher (P10) on a PC: runs
# editor_test.lua and launcher_test.lua with
# Lua 5.4 from the lupa package (skipped when it is not installed):
#   pip install lupa
#   python -m unittest discover -s tests/tools -v

import pathlib
import unittest

try:
    import lupa.lua54 as lua54
except ImportError:
    lua54 = None

ROOT = pathlib.Path(__file__).resolve().parents[2]
TEST = pathlib.Path(__file__).with_name("editor_test.lua")


@unittest.skipIf(lua54 is None, "lupa (Lua 5.4 for Python) is not installed")
class EditorTest(unittest.TestCase):
    def test_editor(self):
        rt = lua54.LuaRuntime()
        run = rt.eval("function(path, root) return assert(loadfile(path))(root) end")
        run(str(TEST), ROOT.as_posix())

    def test_words_reload(self):
        # A fresh Lua state: the test sets its own globals
        rt = lua54.LuaRuntime()
        run = rt.eval("function(path, root) return assert(loadfile(path))(root) end")
        run(str(TEST.with_name("editor_words_test.lua")), ROOT.as_posix())

    def test_launcher(self):
        rt = lua54.LuaRuntime()
        run = rt.eval("function(path, root) return assert(loadfile(path))(root) end")
        run(str(TEST.with_name("launcher_test.lua")), ROOT.as_posix())


if __name__ == "__main__":
    unittest.main()
