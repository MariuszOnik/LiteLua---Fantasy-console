-- SPDX-License-Identifier: Zlib
--
-- Test: help/*.lua of a cart adds topics to the help of the code editor, and
-- START on a name documented there opens its page. Run by test_editor.py.
local ROOT = ...
package.path = ROOT .. "/nitrofs/system/code/src/?.lua;" .. ROOT .. "/nitrofs/lib/?.lua;"
  .. package.path
local files = {
  ["game/main.lua"] = "spawn(1, 2)\n",
  ["game/help/game.lua"] = 'return { title = "My game", text = "Catch the stars.",\n'
    .. '  entries = { { name = "spawn", sig = "spawn(x, y)", desc = "Makes one." },\n'
    .. '    { desc = "no name: left out" } } }\n',
}
local keys, prev, tap = {}, {}, nil
local shown = {} -- Text drawn in the last frame
log = function() end
btn = function(n) return keys[n] == true end
btnp = function(n) return keys[n] == true and not prev[n] end
btnr = function(n) return prev[n] == true and not keys[n] end
touch = function() if tap then return tap[1], tap[2] end end
for _, n in ipairs({ "cls", "rectfill", "clip" }) do _G[n] = function() end end
text = function(s) shown[#shown + 1] = s end
textw = function(s) return #s * 6, 8 end
TOP, BOTTOM = 0, 1
io = { open = function() return nil end }
sys = { system = {
  start = { reason = "edit", cart = "game" },
  cart = function(n) return { name = n, entry = "main.lua", writable = true } end,
  carts = function() return {} end,
  files = function(c, dir)
    if c == "@code" then return {} end -- No API files: only the cart's help
    if dir == "help" then return { { name = "game.lua" } } end
    return { { name = "help", dir = true }, { name = "main.lua" } }
  end,
  read = function(c, p) return files[c .. "/" .. p] end,
  write = function(c, p, d) files[c .. "/" .. p] = d; return true end,
} }
assert(loadfile(ROOT .. "/nitrofs/system/code/main.lua"))()
_init()
local function frame(k)
  prev = keys; keys = k or {}; shown = {}
  _update(); _draw(0); _draw(1)
end
local function has(s)
  for _, t in ipairs(shown) do if t:find(s, 1, true) then return true end end
  return false
end

-- START with the cursor on "spawn": the page of the cart's entry
frame({ start = true }); frame()
assert(has("spawn(x, y)") and has("Makes one."), "page of spawn from help/game.lua")

-- The topics: the editor's manual, then "My game" with its text
frame({ b = true }); frame()   -- Back to the topics, the cursor on "My game"
assert(has("My game") and has("Catch the stars."), "manual page of the cart")
assert(has("1 entries"), "the entry without a name is left out")
print("editor help tests ok")
