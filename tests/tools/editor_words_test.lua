-- SPDX-License-Identifier: Zlib
--
-- Regression test (D46): a word deleted from words.lua and saved in the editor
-- must leave the suggestions. Run by test_editor.py.
local ROOT = ...
package.path = ROOT .. "/nitrofs/system/code/src/?.lua;" .. ROOT .. "/nitrofs/lib/?.lua;"
  .. package.path
local files = {
  ["game/main.lua"] = "function _draw()\n  cls(1)\nend\n",
  ["game/words.lua"] = 'return {\n  "zebra_word",\n  "yak_word",\n}\n',
}
local keys, tap = {}, nil
log = function() end
btn = function(n) return keys[n] == true end
local prev = {}
btnp = function(n) return keys[n] == true and not prev[n] end
btnr = function(n) return prev[n] == true and not keys[n] end
touch = function() if tap then return tap[1], tap[2] end end
for _, n in ipairs({ "cls", "rectfill", "clip", "text" }) do _G[n] = function() end end
textw = function(s) return #s * 6, 8 end
TOP, BOTTOM = 0, 1
io = { open = function() return nil end }
sys = { system = {
  start = { reason = "edit", cart = "game" },
  cart = function(n) return { name = n, entry = "main.lua", writable = true } end,
  carts = function() return {} end,
  files = function() return { { name = "main.lua" }, { name = "words.lua" } } end,
  read = function(c, p) return files[c .. "/" .. p] end,
  write = function(c, p, d) files[c .. "/" .. p] = d; return true end,
} }
assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua"))()
_init()
local suggest = require("suggest")
local Buffer = require("buffer")
local function frame(k, x, y) prev = keys; keys, tap = k or {}, x and { x, y }; _update(); _draw(0); _draw(1) end
local function q(t)
  local b = Buffer.new("x.lua", t); b:set_cursor(1, #t); suggest.scan(Buffer.new("e.lua", ""))
  local l = suggest.query(b); return l and table.concat(l, ",") or "-"
end
assert(q("zeb") == "zebra_word" and q("ya") == "yak_word", "words loaded")
-- Open words.lua through the files view and delete line 2 ("zebra_word")
frame({ select = true }); frame()
frame({ down = true }); frame()
frame({ a = true }); frame()
frame({ down = true }); frame()
-- Select the whole line 2 with L + down and cut it
frame({ l = true, down = true }); frame({ l = true })
frame({}, 180, 5); frame() -- Cut (6th of 8)
frame({}, 40, 5); frame()  -- Save
assert(not files["game/words.lua"]:find("zebra"), "line deleted and saved")
assert(q("zeb") == "-", "deleted word still suggested: " .. q("zeb"))
assert(q("ya") == "yak_word", "other word kept")

-- Word+ only adds a line before the last } (comments and the rest stay)
local mine = 'return {\n  -- my words\n  "yak_word" -- no comma here\n}\n'
files["game/words.lua"] = mine
frame({ y = true }); frame({ y = true, left = true }); frame() -- tab main.lua
frame({ start = true }); frame()   -- help on "function" under the cursor
frame({}, 120, 5); frame()         -- Word+ (3rd of 5)
local now = files["game/words.lua"]
assert(now:sub(1, #mine - 2) == mine:sub(1, #mine - 2), "start of the file kept:\n" .. now)
assert(now:find("-- my words", 1, true) and now:find("-- no comma here", 1, true), "comments kept")
local t = assert(load(now, "words", "t", {}))()
assert(t[1] == "yak_word" and t[2] == "function", "new word added: " .. now)

