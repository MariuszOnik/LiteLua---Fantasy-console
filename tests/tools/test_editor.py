# SPDX-License-Identifier: Zlib
#
# Tests of the on-DS code editor (P11) on a PC: runs editor_test.lua with
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


if __name__ == "__main__":
    unittest.main()
