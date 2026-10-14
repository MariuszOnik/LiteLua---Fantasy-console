-- SPDX-License-Identifier: Zlib
--
-- Tests of the launcher (nitrofs/system/launcher, P10) on a PC with a stubbed
-- LiteLua API; run by test_editor.py (needs the Python package lupa).
local ROOT = ...
package.path = ROOT .. "/nitrofs/lib/?.lua;" .. package.path

local function eq(a, b, what)
  if a ~= b then error(("%s: got %q, want %q"):format(what, tostring(a), tostring(b)), 2) end
end

local real_open = io.open -- io is stubbed below
local function readfile(path)
  local f = assert(real_open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local saved = {}       -- save/ files of the launcher
local files = {}       -- "cart/path" -> contents
local calls = {}
local keys, prev, tap = {}, {}, nil
local carts = {
  { name = "alpha", title = "Alpha", writable = true },
  { name = "broken", error = "cart.lua:1: bad", writable = true },
  { name = "zed.lcart", title = "Zed", lcart = true },
}

log = function() end
btn = function(n) return keys[n] == true end
btnp = function(n) return keys[n] == true and not prev[n] end
btnr = function(n) return prev[n] == true and not keys[n] end
touch = function() if tap then return tap[1], tap[2] end end
for _, n in ipairs({ "cls", "rectfill", "text" }) do _G[n] = function() end end
textw = function(s) return #s * 6, 8 end
TOP, BOTTOM = 0, 1
io = { open = function(path, m)
  if m == "r" then
    if not saved[path] then return nil end
    local s = saved[path]
    return { read = function() return (s:match("[^\n]*")) end, close = function() end }
  end
  return { write = function(_, ...) saved[path] = table.concat({ ... }) end,
           close = function() end }
end }
sys = {
  run = function(n) calls[#calls + 1] = "run " .. n end,
  system = {
    start = { reason = "run" },
    carts = function()
      local t = {}
      for i, c in ipairs(carts) do t[i] = setmetatable({}, { __index = c }) end
      return t
    end,
    manifest = function(n) return n == "alpha" and { author = "me", desc = "A game." } or nil end,
    read = function(c, p)
      eq(c, "@launcher", "template cart")
      return readfile(ROOT .. "/nitrofs/system/launcher/" .. p)
    end,
    write = function(c, p, d) files[c .. "/" .. p] = d; return true end,
    create = function(n)
      if n == "alpha" then return nil, "'alpha' exists" end
      calls[#calls + 1] = "create " .. n
      return true
    end,
    edit = function(n) calls[#calls + 1] = "edit " .. n end,
    demo = function() calls[#calls + 1] = "demo" end,
  },
}

local function frame(k, t)
  prev = keys
  keys = k or {}
  tap = t
  _update()
  _draw(TOP)
  _draw(BOTTOM)
end

local function start()
  calls = {}
  assert(loadfile(ROOT .. "/nitrofs/system/launcher/main.lua"))()
  _init()
end

-- A on the first cart runs it and remembers it
start()
frame({ a = true }); frame()
eq(calls[1], "run alpha", "play")
eq(saved["save/last.txt"], "alpha\n", "remembered")

-- The next start selects the remembered cart; down + Y edits the next one
saved["save/last.txt"] = "broken\n"
start()
frame({ a = true }); frame()
eq(#calls, 0, "a broken cart does not run")
frame({ y = true }); frame()
eq(calls[1], "edit broken", "edit a broken cart")

-- The last entry is the demo (down three times)
start()
frame({ down = true }); frame(); frame({ down = true }); frame()
frame({ a = true }); frame()
eq(calls[1], "demo", "demo")

-- New game: X, type "Foo-1" with the keyboard (shift for F), OK
start()
frame({ x = true }); frame()
local kb = require("keyboard")
local function key_pos(label)
  for r, row in ipairs(kb.layers[kb.layer]) do
    local u = 0
    for _, k in ipairs(row) do
      if k[1] == label then
        return math.floor((u + k[2] / 2) * 25.6), kb.y + (r - 1) * kb.row_h + 10
      end
      u = u + k[2]
    end
  end
  error("no key " .. label)
end
local function type_key(label)
  local x, y = key_pos(label)
  frame(nil, { x, y }); frame(nil, { x, y }); frame()
end
for _, k in ipairs({ "shf", "f", "o", "o", " ", "1" }) do
  if k == " " then
    kb.toggle_layer(); type_key("-"); kb.toggle_layer()
  else
    type_key(k)
  end
end
frame(nil, { 180, 15 }); frame(nil, { 180, 15 }); frame() -- OK
eq(calls[1], "create Foo-1", "create")
eq(calls[2], "edit Foo-1", "edit the new game")
assert(files["Foo-1/cart.lua"]:find('id = "foo-1"', 1, true), "id in cart.lua")
assert(files["Foo-1/cart.lua"]:find('title = "Foo-1"', 1, true), "title in cart.lua")
assert(files["Foo-1/main.lua"]:find('text("Foo-1"', 1, true), "title in main.lua")
assert(load(files["Foo-1/main.lua"]), "template compiles")

-- A name that exists: the error is shown, nothing else happens
start()
frame({ x = true }); frame()
for _, k in ipairs({ "a", "l", "p", "h", "a" }) do type_key(k) end
frame({ a = true }); frame()
eq(#calls, 0, "no create for an existing name")

print("launcher tests ok")
