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
local removed, renamed
local frame_keys, touch_xy, prev_keys = {}, nil, {}
local drawn = 0
local env = _G
env.log = function(s) if DEBUG then print(s) end end
env.btn = function(n) return frame_keys[n] == true end
env.btnp = function(n) return frame_keys[n] == true and not prev_keys[n] end
env.btnr = function(n) return prev_keys[n] == true and not frame_keys[n] end
env.touch = function() if touch_xy then return touch_xy[1], touch_xy[2] end end
for _, n in ipairs({ "cls", "rectfill", "clip" }) do env[n] = function() end end
env.text = function(s) drawn = drawn + #s end
env.textw = function(s) return #s * 6, 8 end
env.TOP, env.BOTTOM = 0, 1
local real_io = io
env.io = { open = function() return nil end }
-- The API docs as the help reads them from the ROM (api/*.lua)
local API = { "core", "gfx", "map", "input", "sound", "files", "sys", "lua", "system" }
for _, m in ipairs(API) do
  local f = assert(real_io.open(ROOT .. "/docs/api/" .. m .. ".lua", "rb"))
  files["@code/api/" .. m .. ".lua"] = f:read("a")
  f:close()
end
local ran
env.sys = { system = {
  start = { reason = "edit", cart = "game" },
  cart = function(n) return { name = n, title = n, entry = "main.lua", writable = true } end,
  carts = function() return { { name = "game", title = "game", entry = "main.lua" } } end,
  files = function(c, d)
    if c == "@code" and d == "api" then
      local t = {}
      for _, m in ipairs(API) do t[#t + 1] = { name = m .. ".lua" } end
      return t
    end
    if d == "" then return { { name = "src", dir = true }, { name = "main.lua" } } end
    return { { name = "x.lua" } }
  end,
  read = function(c, p) return files[c .. "/" .. p] end,
  write = function(c, p, d) files[c .. "/" .. p] = d; return true end,
  mkdir = function() return true end,
  remove = function(c, p) removed = p; return true end,
  rename = function(c, a, b) renamed = a .. ">" .. b; return true end,
  run = function(c, d) ran = d end,
} }
env.require = require
DEBUG = false
-- Strict: reading an undefined global is an error (catches a local used in a
-- function above its declaration, which Lua silently reads as a global)
setmetatable(_G, { __index = function(_, k)
  error("undefined global '" .. tostring(k) .. "'", 2)
end })
package.loaded.buffer, package.loaded.lexer = nil, nil
local f = assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua", "t", env))
f()
env._init()
local function frame(keys, tx, ty)
  prev_keys = frame_keys
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
assert(ran and ran:match("^v2\ngame\nmain.lua\nmain.lua\t"), "run data: " .. tostring(ran))

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
-- Help: START on "cls" in the code opens its page
frame({}, 140, 5); frame() -- Cancel the prompt
frame({ select = true }); frame() -- back to the code
frame({ start = true }); frame()
local shown = {}
env.text = function(s) shown[#shown + 1] = s end
frame()
local all = table.concat(shown, "\n")
assert(all:find("Help", 1, true), "help list drawn")
frame({}, 230, 5); frame() -- Close (3rd of 3 buttons)
env.text = function(s) drawn = drawn + #s end

-- Files view (the help was opened from it): Ren and Del (Del needs a
-- second touch)
frame({ down = true }); frame() -- cart.lua... choose an entry
frame({}, 100, 5); frame()      -- Ren (4th of 8 = x 96..127)
frame({}, 5, 70); frame()       -- type "q"
frame({}, 230, 165); frame()    -- ent
assert(renamed, "renamed")
frame({}, 140, 5); frame()      -- Del: asks
assert(not removed, "Del asks first")
frame({}, 140, 5); frame()      -- Del again
assert(removed, "removed")

-- Suggestions (P11a)
local suggest = require("suggest")
local mods = {}
for _, m in ipairs(API) do
  mods[#mods + 1] = assert(load(files["@code/api/" .. m .. ".lua"], m, "t", {}))()
end
suggest.init(mods)
local function q(text)
  local sb = Buffer.new("s.lua", text)
  sb:set_cursor(#sb.lines, #sb.lines[#sb.lines])
  suggest.scan(sb)
  return sb, suggest.query(sb)
end
local _, list, pre = q("local player = 1\nprint(player)\npl")
eq(list[1], "player", "code name first"); eq(pre, 2, "prefix")
_, list = q("sys.r"); eq(list[1], "run", "api field")
_, list = q("string.fo"); eq(list[1], "format", "lua library field")
_, list = q("self.speed = 1\nself.sp"); eq(list[1], "speed", "code field")
_, list = q('x = "pl'); eq(list, nil, "no suggestions in a string")
_, list = q("-- re"); eq(list, nil, "no suggestions in a comment")
local sb2 = q("rectfill(1, 2")
local sig, arg = suggest.signature(sb2)
eq(sig, "rectfill(x, y, w, h, [col])", "signature"); eq(arg, 2, "argument")
local a1, a2 = suggest.arg_range(sig, arg); eq(sig:sub(a1, a2), "y", "argument range")
eq(sig:sub(suggest.arg_range(sig, 5)), "[col]", "optional argument")
_, list = q("local level = tilemap(\"a\")\nlevel:dr"); eq(list[1], "draw", "map method")
eq((suggest.signature(q("level:hit(x, "))), "map:hit(x, y, w, h, [flag], [layer]) -> tx, ty | nil",
   "method signature")

-- In the editor: type "cl" on the keyboard, R+A takes the first suggestion
env.sys.system.start = { reason = "edit", cart = "game" }
f = assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua", "t", env)); f()
env._init(); frame()
frame({}, 90, 140); frame()   -- c
frame({}, 215, 110); frame()  -- l
frame({ r = true, a = true }); frame()
frame({}, 40, 5); frame()     -- Save
assert(files["game/main.lua"]:find("^cls"), "suggestion inserted: " .. files["game/main.lua"]:sub(1, 20))

-- The cart's own words (words.lua, D46)
suggest.set_words({ "spawn_enemy", { name = "Enemy.new", sig = "Enemy.new(x, y)" } })
_, list = q("spa"); eq(list[1], "spawn_enemy", "cart word")
_, list = q("Enemy.n"); eq(list[1], "new", "cart field")
eq((suggest.signature(q("Enemy.new(1, "))), "Enemy.new(x, y)", "cart signature")
suggest.set_words({})

-- Word+ in the help writes words.lua; Opts opens the theme list
frame({ start = true }); frame()      -- help on the word under the cursor
frame({}, 120, 5); frame()            -- Word+ (3rd of 5 buttons)
local wsrc = assert(files["game/words.lua"], "words.lua written")
local wl = assert(load(wsrc, "words", "t", {}))()
assert(type(wl[1]) == "string", "a word in words.lua")
frame({}, 170, 5); frame()            -- Opts (4th of 5)
frame({ down = true }); frame()       -- preview the next theme
frame({ a = true }); frame()          -- keep it (save fails: io stub)
frame({}, 240, 5); frame()            -- Close the help

-- Tabs (P11d): two files open, Y+right switches, Y alone undoes on release
env.sys.system.start = { reason = "edit", cart = "game" }
f = assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua", "t", env)); f()
env._init(); frame()
frame({ select = true }); frame()      -- files view: src/, main.lua
frame({ a = true }); frame()           -- into src/
frame({ down = true }); frame()        -- x.lua (after "..")
frame({ a = true }); frame()           -- open src/x.lua: second tab
local shown = {}
env.text = function(s) shown[#shown + 1] = s end
frame()
local all = table.concat(shown, "|")
assert(all:find("main.lua", 1, true) and all:find("x.lua", 1, true), "both tabs drawn: " .. all:sub(1, 80))
env.text = function(s) drawn = drawn + #s end
frame({}, 5, 70); frame()               -- type q into x.lua
frame({ y = true }); frame({ y = true, right = true }); frame({ y = true }); frame()
frame({}, 40, 5); frame()               -- Save (main.lua is current now)
assert(files["game/main.lua"]:sub(1, 1) ~= "q", "q went to x.lua, not main.lua")
frame({ y = true }); frame({ y = true, left = true }); frame() -- back to x.lua
frame({ y = true }); frame()            -- Y alone: undo the q on release
frame({}, 40, 5); frame()
eq(files["game/src/x.lua"], "return 1\n", "undo in x.lua")

print("all editor tests passed, drawn chars " .. drawn)
