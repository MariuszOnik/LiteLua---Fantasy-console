-- A test of the C4 battle cart (HeroesDS/carts/c4) on a PC: LiteLua's API is faked, the
-- player's turns are played by touches (defend, and once the hero's Magic Arrow from the
-- spell book), then Y lets the computer finish the battle. Run by test_combat.py through
-- lupa; needs extracted/rules (make_rules.py). Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. root .. "/carts/c4/src/?.lua;" .. package.path

if not loadfile(root .. "/extracted/rules/creatures.lua") then return 0 end

-- --- LiteLua, faked ------------------------------------------------------------------------
local input = { held = {}, pressed = {} }
function touch() if input.touch then return input.touch[1], input.touch[2] end end
function btn(n) return input.held[n] or false end
function btnp(n) return input.pressed[n] or false end
for _, f in ipairs({ "cls", "text", "rect", "rectfill", "line", "pset", "trifill", "log",
                    "sspr", "alpha" }) do
  _G[f] = function() end
end
local images = 0
function image(name) images = images + 1; return { name = name } end
function collectgarbage() end
TOP, BOTTOM = 0, 1
local t0 = os.clock()
function micros() return math.floor((os.clock() - t0) * 1e6) end
local real_loadfile = loadfile
function loadfile(p, ...)   -- the cart's animations, when make_c4.py --gfx made them
  local name = p:match("^data/anim/(.*)$")
  return real_loadfile(name and (root .. "/carts/c4/data/anim/" .. name) or p, ...)
end
local real_dofile = dofile
function dofile(p)
  local name = p:match("^data/(.*)$")
  return real_dofile(name and (root .. "/extracted/rules/" .. name) or p)
end

local setup = require("setup")
local make, B = setup.battle, nil
setup.battle = function(...) B = make(...); return B end
assert(loadfile(root .. "/carts/c4/main.lua"))()
local view = require("view")
local casting = require("combat.casting")

local frames = 0
local function frame(n)
  for _ = 1, n or 1 do
    _update(); _draw(TOP); _draw(BOTTOM)
    input.pressed = {}
    frames = frames + 1
  end
end
local function tap(x, y)
  input.touch = { x // 1, y // 1 }
  frame()
  input.touch = nil
  frame()
end
local function centre(u) return view.to_screen(u.x + u.size / 2, u.y + u.size / 2) end
local function spell_name(key) return B.spells[key] and B.spells[key].name or key end

-- --- the player's turns --------------------------------------------------------------------
local cast_done = false
for _ = 1, 400 do
  frame(30)                                   -- let the shows and the computer finish
  if B.finished then break end
  local u = B:current()
  if B:side_of(u) == 0 then
    if u.caster and not cast_done then
      local keys = {}
      for key in pairs(casting.options(B, u)) do keys[#keys + 1] = key end
      table.sort(keys, function(a, c) return spell_name(a) < spell_name(c) end)
      local row
      for i, k in ipairs(keys) do if k == "magic arrow" then row = i end end
      assert(row, "no Magic Arrow in the book")
      local mana = u.spell_points
      tap(247, 20)                              -- the book
      tap(100, 20 + (row - 1) * 16 + 8)         -- Magic Arrow
      local enemy
      for _, e in ipairs(B.units) do if e.side == 1 and e.count > 0 and not e.is_hero then enemy = e break end end
      local x, y = centre(enemy)
      tap(x, y)                                 -- the target: the preview
      assert(u.spell_points == mana, "cast on the first touch")
      tap(x, y)                                 -- the same again: cast
      assert(u.spell_points < mana, "Magic Arrow was not cast")
      cast_done = true
    else
      tap(8, 68)                                -- defend
    end
  end
end
assert(cast_done or B.finished, "the hero never had a turn")

-- --- the computer finishes -----------------------------------------------------------------
input.pressed = { y = true }
frame()
for _ = 1, 20000 do
  if B.finished then break end
  frame()
end
assert(B.finished, "the battle did not end")
if real_loadfile(root .. "/carts/c4/data/anim/bandit_wait.lua") then
  assert(images > 0, "no animation was loaded")
end
return frames
