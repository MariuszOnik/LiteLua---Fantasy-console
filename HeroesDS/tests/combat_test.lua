-- Tests of the combat rules (HeroesDS/combat), run by test_combat.py through lupa.
-- Argument: the HeroesDS folder. Each test is a function in T; failures raise errors.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local num = require("combat.num")
local rng = require("combat.rng")
local grid = require("combat.grid")
local stats = require("combat.stats")
local damage = require("combat.damage")

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

-- A synthetic creature: attack / defense 10, 10 hp, damage 2..4, size 1
local function creature(over)
  local def = { name = "test", hp = 10, dmg = { 2, 4 }, attack = 10, defense = 10, move = 10,
                speed = 5, shots = 0, size = 1, level = 1, alignment = "might", abilities = {} }
  for k, v in pairs(over or {}) do def[k] = v end
  return def
end
local function stack(over, count, x, y, id)
  local st = stats.creature("test", creature(over), count or 1)
  st.x, st.y, st.id = x or 50, y or 50, id or 1
  return st
end

---------------------------------------------------------------------------------------------
function T.rng_msvc_sequence()
  local r = rng.new(1)   -- srand(1) of the C runtime: 41, 18467, 6334, 26500, 19169
  for _, want in ipairs({ 41, 18467, 6334, 26500, 19169 }) do eq(r:next(), want, "rand") end
  eq(r:hex(), string.format("%08x", r.state & 0xFFFFFFFF), "hex")
  local a, b = rng.new(12345), rng.new(12345)
  for _ = 1, 100 do eq(a:roll(3, 7), b:roll(3, 7), "same seed") end
  local r2 = rng.new(7)
  for _ = 1, 200 do local v = r2:roll(2, 4); assert(v >= 2 and v <= 4) end
  eq(rng.new(5):roll(4, 4), 4, "lo == hi")
end

function T.num_float32_and_rounding()
  eq(num.f32(16777217.0), 16777216.0, "2^24 + 1 rounds")
  eq(num.f32(0.5), 0.5, "exact")
  assert(num.f32(0.1) ~= 0.1 or num.FLOAT32, "0.1 is not a float")
  eq(num.round(2.5), 3); eq(num.round(-2.5), -3); eq(num.round(2.4999), 2)
  eq(math.type(num.round(7.0)), "integer", "round gives an integer")
  eq(num.trunc(-1.7), -1); eq(num.trunc(1.7), 1)
end

---------------------------------------------------------------------------------------------
function T.grid_field_and_scene()
  assert(not grid.on_field(0, 0), "far corner")
  assert(grid.on_field(51, 51), "centre")
  assert(grid.on_field(76, 51) and grid.on_field(33, 32), "deployment cells")
  assert(not grid.on_field(-1, 5) and not grid.on_field(102, 5), "outside")
  local sx, sy = grid.screen(51, 51)
  eq(sx, 590); eq(sy, 512)
  local wx, wy = grid.world(grid.screen(30.5, 70.25))
  eq(wx, 30.5); eq(wy, 70.25)
  local n = 0
  for x = 0, 101 do for y = 0, 101 do if grid.on_field(x, y) then n = n + 1 end end end
  assert(n > 4000 and n < 10404, "field cells: " .. n)
end

function T.grid_obstacles_and_footprints()
  local f = grid.new_field()
  f:add_obstacle("rock", 50, 50, 2, 3, true)
  f:add_obstacle("grass", 60, 60, 2, 2, false)
  assert(not f:is_open(51, 52) and f:is_open(52, 52))
  assert(f:fits(60, 60, 2), "ground cover blocks nothing")
  assert(not f:fits(48, 48, 3) and f:fits(47, 47, 3))
  local a = stack({}, 1, 40, 40, 1); a.size = 2
  local b = stack({}, 1, 42, 42, 2)          -- touches a at a corner
  local c = stack({}, 1, 43, 40, 3)
  assert(grid.adjacent(a, b) and grid.adjacent(b, a), "corner touch")
  assert(not grid.adjacent(a, c), "a gap of one cell")
  assert(grid.overlaps({ a, b }, 41, 41, 1, nil) and not grid.overlaps({ a, b }, 41, 41, 1, 1))
  b.count = 0
  assert(not grid.overlaps({ b }, 42, 42, 1), "the dead take no room")
end

function T.grid_distance_and_directions()
  local a = stack({}, 1, 10, 10); a.size = 4
  local b = stack({}, 1, 40, 10); b.size = 4
  eq(grid.dist4(a, b), 3600); eq(grid.distance(a, b), 30.0)
  eq(select(1, grid.dir8(10, 1)), 1); eq(select(2, grid.dir8(10, 1)), 0)
  local x, y = grid.dir8(5, 5); eq(x, 1); eq(y, 1)
  x, y = grid.dir8(-1, 10); eq(x, 0); eq(y, 1)
  -- the border at 22.5 degrees: tan = 0.41421...
  x, y = grid.dir8(1000, 414); eq(y, 0)
  x, y = grid.dir8(1000, 415); eq(y, 1)
  eq(grid.facing(-1, 0), "ne"); eq(grid.facing(1, 0), "sw")
  eq(grid.facing(0, 1), "se"); eq(grid.facing(-3, -3), "n"); eq(grid.facing(0, 0), "ne")
end

function T.grid_line_of_fire()
  local f = grid.new_field()
  f:add_obstacle("wall", 50, 40, 1, 20, true)
  assert(f:obstructed(45.5, 45.5, 55.5, 45.5), "through the wall")
  assert(not f:obstructed(45.5, 30.5, 55.5, 30.5), "past its end")
  f.smoke[grid.key(48, 30)] = true
  assert(grid.crosses(f.smoke, 45.5, 30.5, 55.5, 30.5), "through smoke")
end

local function mover(st, budget)
  return { id = st.id, x = st.x, y = st.y, size = st.size, budget = num.f32(budget) }
end

function T.grid_reachable_costs()
  local f = grid.new_field()
  local u = stack({}, 1, 50, 50)
  local cost = grid.reachable(f, { u }, mover(u, 2))
  eq(cost[grid.key(50, 50)], 0, "start")
  eq(cost[grid.key(52, 50)], 2.0, "two straight")
  eq(cost[grid.key(51, 51)], 1.5, "diagonal")
  eq(cost[grid.key(52, 52)], nil, "3 is over budget")
  eq(cost[grid.key(52, 51)], nil, "2.5 is over budget")
  local path = grid.path(f, { u }, mover(u, 2), 52, 50)
  eq(#path, 2); eq(path[2][1], 52); eq(path[2][2], 50)
end

function T.grid_walkers_flyers_teleport()
  local f = grid.new_field()
  f:add_obstacle("wall", 52, 40, 1, 21, true)   -- x = 52, y 40..60
  local u = stack({}, 1, 50, 50)
  local cost = grid.reachable(f, { u }, mover(u, 6))
  eq(cost[grid.key(54, 50)], nil, "the wall is in the way")
  local m = mover(u, 6); m.flies = true
  cost = grid.reachable(f, { u }, m)
  eq(cost[grid.key(54, 50)], 4.0, "a flyer passes over")
  eq(cost[grid.key(52, 50)], nil, "but does not land on it")
  m = mover(u, 6); m.teleport = true
  cost = grid.reachable(f, { u }, m)
  assert(cost[grid.key(80, 50)] ~= nil, "teleport goes anywhere free")
  -- a diagonal step past an obstacle corner needs an open straight neighbour
  f = grid.new_field()
  f:add_obstacle("a", 51, 50, 1, 1, true)
  f:add_obstacle("b", 50, 51, 1, 1, true)
  cost = grid.reachable(f, { u }, mover(u, 1.5))
  eq(cost[grid.key(51, 51)], nil, "squeezing between two corners")
end

function T.grid_zones_of_control()
  local f = grid.new_field()
  local u = stack({}, 1, 50, 50, 1)
  local e = stack({}, 1, 51, 50, 2)      -- right next to u, along +x
  local m = mover(u, 10); m.zoc = { e }; m.zoc_cost = num.f32(10 / 4)
  local cost = grid.reachable(f, { u, e }, m)
  eq(cost[grid.key(49, 50)], 1.0, "straight away from the enemy is free")
  eq(cost[grid.key(50, 51)], 2.5, "sideways would pay 1 + 2.5; away first, then a diagonal")
  eq(cost[grid.key(49, 49)], 2.0, "around: away first, then free")
  -- no way around: rocks behind and above u
  local g = grid.new_field()
  g:add_obstacle("back", 49, 49, 1, 3, true)
  g:add_obstacle("top", 50, 49, 2, 1, true)
  cost = grid.reachable(g, { u, e }, m)
  eq(cost[grid.key(50, 51)], 1 + 2.5, "sideways pays a quarter of the move")
  eq(cost[grid.key(51, 51)], 1.5 + 2.5 * 1.5, "a diagonal pays it x 1.5")
  m.zoc = {}
  cost = grid.reachable(f, { u, e }, m)
  eq(cost[grid.key(50, 51)], 1.0, "Ignore Zones of Control")
end

---------------------------------------------------------------------------------------------
function T.stats_derived()
  local st = stack({ speed = 7, move = 20 })
  eq(stats.speed(st), 7)
  st.effects.haste = {}; eq(stats.speed(st), 10); eq(stats.move_cells(st), 29.0)
  st.effects.slow = {}; eq(stats.speed(st), 5); eq(stats.move_cells(st), 14.5)
  local h = stack({ hp = 10 })
  h.effects.prayer = {}; eq(stats.hit_points(h), 13)
  h.effects["dragon strength"] = {}; eq(stats.hit_points(h), 26)
  local u = stack({ abilities = { undead = true } })
  u.morale = 5; eq(stats.morale(u, 0), 0, "undead have no morale")
  local m = stack(); m.morale = 8; m.effects.morale = {}
  eq(stats.morale(m, -1), 10, "clamped")
  m.effects.sorrow = {}; eq(stats.morale(m, 0), -10)
  local l = stack(); l.luck = 3; l.effects.luck = {}; eq(stats.luck(l), 8)
  local fl = stack({ abilities = { flying = true } })
  assert(stats.has(fl, "flying")); fl.effects["bind flyer"] = {}
  assert(not stats.has(fl, "flying"), "Bind Flyer")
  local p = stack(); p.effects["protection from chaos"] = {}
  assert(stats.has(p, "chaos_protection"), "granted by a spell")
end

function T.stats_take_and_hero()
  local st = stack({ hp = 10 }, 5)
  eq(stats.take(st, 23), 2); eq(st.count, 3); eq(st.wounds, 3)
  eq(stats.take(st, 7), 1); eq(st.count, 2); eq(st.wounds, 0)
  eq(stats.take(st, 100), 2); eq(st.count, 0); eq(st.wounds, 0)
  local h = stats.hero("Gem", 10, { combat = 2, toughness = 1, archery = 5 })
  eq(h.hp, 190); eq(h.dmg_lo, 30); eq(h.dmg_hi, 45)
  eq(h.attack, 20); eq(h.defense, 15); eq(h.ranged_attack, 30); eq(h.shots, 24)
end

---------------------------------------------------------------------------------------------
function T.damage_ratio()
  local a, b = stack(), stack()
  eq(damage.blow(a, b, 50, {}), 50, "equal attack and defense")
  a.attack = 20; eq(damage.blow(a, b, 50, {}), 100)
  a.attack = 1; b.defense = 100; eq(damage.blow(a, b, 100, {}), 5, "ratio floor 0.05")
  a.attack = 1000; b.defense = 10; eq(damage.blow(a, b, 10, {}), 200, "ratio ceiling 20")
  a.attack, b.defense = 10, 10
  a.effects["evil hour"] = {}; eq(damage.blow(a, b, 10, {}), 8, "x 0.8")
  a.effects = {}
  b.defending = true; eq(damage.blow(a, b, 10, {}), 5, "defend doubles")
  b.defending = false
  eq(damage.blow(a, b, 1, {}), 1, "at least 1")
  a.attack, b.defense = 9, 12
  eq(damage.blow(a, b, 10, {}), 8, "7.5 rounds up")
end

function T.damage_modifiers()
  local a, b = stack(), stack()
  a.abilities.charging = true
  eq(damage.blow(a, b, 100, { moved = 10 }), 113, "Charge after 10 cells")
  eq(damage.blow(a, b, 100, { moved = 5 }), 100, "no Charge at 5 cells")
  local s = stack({ shots = 6 })
  eq(damage.blow(s, b, 100, {}), 50, "shooter in melee")
  s.normal_melee = true; eq(damage.blow(s, b, 100, {}), 100, "Normal Melee")
  eq(damage.blow(s, b, 100, { ranged = true }), 100, "shooting")
  local c = stack({ alignment = "chaos" })
  b.effects["protection from chaos"] = {}
  eq(damage.blow(c, b, 30, {}), 20, "ward x 2/3")
  local d = stack({ abilities = { breath_attack = true } })
  local r = stack({ abilities = { fire_resistance = true } })
  eq(damage.blow(d, r, 31, {}), 15, "fire against fire resistance")
  local k = stack({ abilities = { block = true } })
  eq(damage.blow(a, k, 10, { quick = true }), 7, "Block in auto-resolve")
  eq(damage.blow(a, k, 10, {}), 10, "Block is a roll in battle")
  local g = stack({ abilities = { giantslayer = true } })
  eq(damage.blow(g, stack({ level = 4 }), 10, {}), 20, "Giantslayer")
end

function T.damage_hero_divides_defense()
  local h = stats.hero("H", 1, { combat = 2 })   -- melee 20, divides by 2
  local t = stack({ defense = 30 })
  eq(damage.blow(h, t, 30, {}), 40, "20 / (30 / 2)")
  damage.hero_divides_defense = false
  eq(damage.blow(h, t, 30, {}), 20, "rule off: 20 / 30")
  damage.hero_divides_defense = true
  local low = stack({ defense = 9 })
  eq(damage.blow(h, low, 9, {}), 20, "a defense of 10 or less is not divided")
  local mid = stack({ defense = 15 })
  eq(damage.blow(h, mid, 10, {}), 20, "not below 10")
  local enemy_hero = stats.hero("E", 1, { toughness = 3 })   -- defense 30
  eq(damage.blow(h, enemy_hero, 30, {}), 20, "a hero's defense is never divided")
end

function T.damage_range_bless_curse_roll()
  local a = stack({ dmg = { 2, 5 } })
  local lo, hi = damage.range(a); eq(lo, 2); eq(hi, 5)
  a.effects.bless = {}; lo, hi = damage.range(a); eq(lo, 5); eq(hi, 5)
  a.effects = { curse = {} }; lo, hi = damage.range(a); eq(lo, 2); eq(hi, 2)
  a.effects = { strength = {} }; lo, hi = damage.range(a); eq(lo, 2); eq(hi, 7)
  local big = stack({ dmg = { 1, 1 } }, 25)
  eq(damage.roll_base(big, rng.new(1)), 25, "10 rolls x 25 / 10")
  local r1, r2 = rng.new(99), rng.new(99)
  local s = stack({ dmg = { 1, 10 } }, 7)
  local base = damage.roll_base(s, r1)
  local sum = 0
  for _ = 1, 7 do sum = sum + r2:roll(1, 10) end
  eq(base, sum, "one roll per creature")
  local pmin, pmax = damage.preview(stack({ dmg = { 2, 4 } }, 10), stack(), {})
  eq(pmin, 20); eq(pmax, 40)
end

function T.damage_range_divisor()
  local f = grid.new_field()
  local a = stack({ shots = 5 }, 1, 50, 10)
  local b = stack({}, 1, 50, 49)          -- 39 cells
  eq(damage.range_divisor(f, a, b), 1)
  b.y = 50; eq(damage.range_divisor(f, a, b), 2, "40 cells")
  a.abilities.short_range = true; eq(damage.range_divisor(f, a, b), 4)
  b.y = 30; eq(damage.range_divisor(f, a, b), 2, "short range, 20 cells")
  a.abilities = { long_range = true }; b.y = 90; eq(damage.range_divisor(f, a, b), 1)
  f:add_obstacle("rock", 49, 60, 3, 1, true)
  eq(damage.range_divisor(f, a, b), 2, "obstacle in the way")
  a.abilities.siege_machine = true; eq(damage.range_divisor(f, a, b), 1, "No Obstacle Penalty")
end

function T.damage_luck()
  -- seed 1 gives 41, 18467, 6334: rolls % 10 = 1, 7, 4
  local r = rng.new(1)
  local d, good = damage.lucky(r, 2, 30); eq(d, 20); eq(good, true)
  d, good = damage.lucky(r, -8, 30); eq(d, 45); eq(good, false)
  d, good = damage.lucky(r, 3, 30); eq(d, 30); eq(good, nil)
  d = damage.lucky(r, 0, 30); eq(d, 30, "no luck, no roll")
  eq(r:next(), 26500, "luck 0 took no roll")
end

-- Real data, when generated locally (make_rules.py; not in the repo)
function T.real_creatures()
  local load = loadfile(root .. "/extracted/rules/creatures.lua")
  if not load then return end
  local n = 0
  for key, def in pairs(load()) do
    local st = stats.creature(key, def, 10)
    st.x, st.y, st.id = 50, 50, 1
    assert(st.size >= 1 and st.size <= 7, key .. " size")
    assert(stats.hit_points(st) > 0 and stats.speed(st) >= 0, key)
    local lo, hi = damage.range(st)
    assert(lo >= 1 and hi >= lo, key .. " damage")
    assert(damage.blow(st, st, damage.roll_base(st, rng.new(n)), {}) >= 1, key .. " blow")
    n = n + 1
  end
  eq(n, 74, "creatures")
end

---------------------------------------------------------------------------------------------
local names = {}
for name in pairs(T) do names[#names + 1] = name end
table.sort(names)
local failed = {}
for _, name in ipairs(names) do
  local ok, err = pcall(T[name])
  if not ok then failed[#failed + 1] = name .. ": " .. tostring(err) end
end
if #failed > 0 then error(#failed .. " failed:\n" .. table.concat(failed, "\n"), 0) end
return #names
