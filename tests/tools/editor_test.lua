-- SPDX-License-Identifier: Zlib
--
-- Tests of the code editor (nitrofs/system/code, P11) on a PC with a stubbed
-- LiteLua API; run by test_editor.py (needs the Python package lupa).
local ROOT = ...
package.path = ROOT .. "/nitrofs/system/code/src/?.lua;" .. package.path

local function eq(a, b, what)
  if a ~= b then error(("%s: got %q, want %q"):format(what, tostring(a), tostring(b)), 2) end
end

-- Lexer
local lexer = require("lexer")
local p, st = lexer.lex('local x = "a" -- hi', "")
eq(p[2], "local", "kw"); eq(p[3], 3, "kw col")
eq(p[#p - 1], "-- hi", "comment")
p, st = lexer.lex("s = [[abc", ""); eq(st, "s0", "long string open")
p, st = lexer.lex("abc]] x", "s0"); eq(st, "", "long close"); eq(p[2], "abc]]", "long piece")
p, st = lexer.lex("--[==[ x", ""); eq(st, "c2", "long comment")
p = lexer.lex("\tx = 1e-5", ""); eq(p[1], 4, "tab col"); eq(p[#p - 1], "1e-5", "number")
p = lexer.lex("a = 'zażółć'", ""); eq(lexer.width(0, "zażółć"), 6, "utf8 width")

-- Buffer
local Buffer = require("buffer")
local b = Buffer.new("t.lua", "abc\ndef\n")
eq(#b.lines, 3, "lines")
b:set_cursor(1, 3); b:insert("X"); b:insert("Y")
eq(b.lines[1], "abcXY", "insert")
eq(#b.undo, 1, "typing merged")
b:newline(); eq(b.lines[2], "", "newline"); eq(b.cy, 2, "cy")
b:insert("  q"); b:newline(); eq(b.lines[3], "  ", "indent kept")
b:undo_step(); b:undo_step(); b:undo_step(); b:undo_step()
eq(b:text(), "abc\ndef\n", "undo all")
b:redo_step(); eq(b.lines[1], "abcXY", "redo")
b:set_cursor(1, 1); b.ay, b.ax = 2, 2
eq(b:copy(), "bcXY\nde", "copy")
local t = b:cut(); eq(b.lines[1], "af", "cut"); eq(t, "bcXY\nde", "cut text")
b:set_cursor(1, 1); b:insert(t, "paste"); eq(b:text(), "abcXY\ndef\n", "paste")
b:set_cursor(2, 0); b:backspace(); eq(b.lines[1], "abcXYdef", "join"); b:backspace()
eq(b.lines[1], "abcXdef", "back"); b:undo_step(); eq(b:text(), "abcXY\ndef\n", "undo back merged")
local u = Buffer.new("u.lua", "zażółć")
u:set_cursor(1, #u.lines[1]); u:left(); u:left(); eq(u.lines[1]:sub(u.cx + 1), "łć", "utf8 left")
u:backspace(); eq(u.lines[1], "zażłć", "utf8 back")
local w = Buffer.new("w.lua", "a\r\nb"); eq(w:text(), "a\r\nb", "crlf")
eq(b:state_at(3), "", "state")

-- main.lua with a stubbed API
local files = {
  ["game/main.lua"] = "function _draw()\n  cls(1)\nend\n",
  ["game/src/x.lua"] = "return 1\n",
}
local frame_keys, touch_xy = {}, nil
local drawn = 0
local env = _G
env.log = function() end
env.btn = function(n) return frame_keys[n] == true end
env.btnp = function(n) return frame_keys[n] == true end
env.touch = function() if touch_xy then return touch_xy[1], touch_xy[2] end end
for _, n in ipairs({ "cls", "rectfill", "clip" }) do env[n] = function() end end
env.text = function(s) drawn = drawn + #s end
env.textw = function(s) return #s * 6, 8 end
env.TOP, env.BOTTOM = 0, 1
env.io = { open = function() return nil end }
local ran
env.sys = { system = {
  start = { reason = "edit", cart = "game" },
  cart = function(n) return { name = n, title = n, entry = "main.lua", writable = true } end,
  carts = function() return { { name = "game", title = "game", entry = "main.lua" } } end,
  files = function(c, d)
    if d == "" then return { { name = "src", dir = true }, { name = "main.lua" } } end
    return { { name = "x.lua" } }
  end,
  read = function(c, p) return files[c .. "/" .. p] end,
  write = function(c, p, d) files[c .. "/" .. p] = d; return true end,
  mkdir = function() return true end,
  run = function(c, d) ran = d end,
} }
env.require = require
package.loaded.buffer, package.loaded.lexer = nil, nil
local f = assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua", "t", env))
f()
env._init()
local function frame(keys, tx, ty)
  frame_keys, touch_xy = keys or {}, tx and { tx, ty }
  env._update(); env._draw(0); env._draw(1)
end
frame()
assert(drawn > 0, "drawn")
-- Type "q" with the keyboard: row 2 (y 32+32..), first key
frame({}, 5, 70); frame()
frame({ down = true }); frame({}); frame({ a = true }); frame()
-- Toolbar: Save (2nd of 8 = x 40), Run (3rd = x 72)
frame({}, 40, 5); frame()
eq(files["game/main.lua"]:sub(1, 1), "q", "saved typed q")
frame({}, 72, 5); frame()
assert(ran and ran:match("^v1\ngame\nmain.lua\t"), "run data: " .. tostring(ran))

-- Return from an error
env.sys.system.start = { reason = "error", cart = "game", data = ran,
  error = "src/x.lua:1: boom\nstack traceback:\n\tsrc/x.lua:1: in main chunk" }
f = assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua", "t", env)); f()
env._init(); frame()
frame({}, 10, 16 + 2 * 9 + 2); frame() -- touch the traceback frame
frame({ a = true }); frame()
-- Files view and new file prompt
frame({ select = true }); frame()
frame({}, 60, 5); frame() -- File+
frame({}, 5, 70); frame(); frame({}, 230, 225 - 60); frame()
print("all editor tests passed, drawn chars " .. drawn)
