-- Tests of the computer opponent (HeroesDS/combat/ai.lua), run by test_combat.py through
-- lupa. Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local stats = require("combat.stats")
local battle = require("combat.battle")
local heroes = require("combat.heroes")
local abilities = require("combat.abilities")
local casting = require("combat.casting")
local ai = require("combat.ai")
abilities.install(battle)
casting.install(battle)

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

local function F(t) local f = { combat = true, elementals = true, mechanical = true, undead = true }
  for k in pairs(t) do f[k] = true end; return f end
local SPELLS = {
  fireball = { id = 43, school = "chaos", level = 3, cost = 5, type = "damage", base = 40, increase = 4,
               flags = F({ damage = 1, enemies = 1, friends = 1, fire = 1 }), creature = "" },
  ["magic arrow"] = { id = 71, school = "order", level = 1, cost = 2, type = "damage", base = 20, increase = 2,
                      flags = F({ damage = 1, enemies = 1 }), creature = "" },
  curse = { id = 23, school = "death", level = 1, cost = 2, type = "curse", base = 0, increase = 0,
            flags = F({ curse = 1, enemies = 1, resisted = 1 }), creature = "" },
}

local function cr(over, count)
  local def = { name = "test", hp = 10, dmg = { 2, 4 }, attack = 10, defense = 10, move = 10,
                speed = 5, shots = 0, size = 2, level = 1, alignment = "might", abilities = {} }
  for k, v in pairs(over or {}) do def[k] = v end
  local st = stats.creature("test", def, count or 10)
  st.morale_bonus = -1
  return st
end

local function make(att, def, seed)
  local b = battle.new({ seed = seed or 1, spells = SPELLS,
                         sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
  b:take_events()
  return b
end

local function find(events, kind)
  local out = {}
  for _, e in ipairs(events) do if e.t == kind then out[#out + 1] = e end end
  return out
end

---------------------------------------------------------------------------------------------
function T.shooter_shoots_the_most_dangerous()
  local s = cr({ speed = 9, shots = 10, abilities = { ranged = true } })
  local weak, strong = cr({}, 5), cr({ attack = 30 }, 20)
  local b = make({ s }, { weak, strong })
  local ev = assert(ai.act(b))
  eq(find(ev, "shoot")[1].target, strong.id)
end

function T.melee_strikes_or_walks()
  local a, near, far = cr({ speed = 9, move = 30 }), cr({}, 3), cr({ attack = 20 }, 30)
  local b = make({ a }, { near, far })
  near.x, near.y = a.x - 6, a.y; far.x, far.y = 30, 70
  local ev = assert(ai.act(b))
  eq(find(ev, "melee")[1].target, near.id, "the one it can reach")
  local w, e = cr({ speed = 9, move = 6 }), cr()
  b = make({ w }, { e })
  local x0 = w.x
  ev = assert(ai.act(b))
  eq(#find(ev, "move"), 1); assert(w.x < x0, "toward the enemy")
end

function T.caster_weighs_spell_against_blow()
  local h = heroes.stack({ name = "M", level = 10, skills = { chaos = 5, death = 5 }, spells = { "fireball", "curse" }, mana = 50 })
  h.speed = 20
  local e1, e2, e3 = cr({}, 10), cr({}, 10), cr({}, 10)
  local b = make({ h }, { e1, e2, e3 })
  e1.x, e1.y = 40, 40; e2.x, e2.y = 42, 40; e3.x, e3.y = 40, 42
  local ev = assert(ai.act(b))
  eq(find(ev, "cast")[1].spell, "fireball", "three stacks in the blast")
  eq(#find(ev, "spell"), 3)
  -- a lone, already cursed enemy, far: the curse is worth nothing, the fireball some
  local v = ai.spell_value(b, "curse", h, { target = e1.id })
  e1.effects.curse = { power = 0 }
  eq(ai.spell_value(b, "curse", h, { target = e1.id }), 0, "already under it")
  assert(v > 0)
end

function T.fireball_spares_own_side()
  local h = heroes.stack({ name = "M", level = 10, skills = { chaos = 5 }, spells = { "fireball" }, mana = 50 })
  h.speed = 20
  local own, e = cr({}, 30), cr({}, 2)
  local b = make({ h, own }, { e })
  own.x, own.y = 40, 40; e.x, e.y = 42, 40
  local v = ai.spell_value(b, "fireball", h, { x = 43, y = 41 })
  assert(v < 0, "own losses count twice: " .. v)
end

function T.berserk_acts_alone()
  local a = cr({ speed = 9, move = 20 })
  local friend = cr({}, 5)
  local e = cr()
  local b = make({ a, friend }, { e })
  friend.x, friend.y = a.x - 2, a.y                    -- right next to it
  a.effects.berserk = { power = 0 }
  assert(ai.must_act(b, a))
  local ev = assert(ai.act(b))
  eq(find(ev, "melee")[1].target, friend.id, "the nearest, friend or foe")
end

function T.run_stops_at_the_human()
  local a, d = cr({ speed = 3 }), cr({ speed = 9, move = 6 })
  local b = make({ a }, { d })
  eq(b:current().id, d.id)
  ai.run(b, { [1] = true })
  eq(b:current().id, a.id, "the human's turn")
end

-- Two computer armies to the end; the same seed gives the same battle
local function auto_battle(seed, creatures, spells, keys)
  local function st(i, n) local k = keys[(i - 1) % #keys + 1]; return stats.creature(k, creatures[k], n) end
  local att = { heroes.stack({ name = "A", level = 8, skills = { chaos = 3, life = 3, combat = 2 },
                               spells = { "fireball", "bless", "magic arrow", "lightning" } }, {}),
                st(seed, 15), st(seed * 3 + 1, 8), st(seed * 7 + 2, 30) }
  local def = { heroes.stack({ name = "D", level = 8, skills = { death = 3, order = 3, archery = 2 },
                               spells = { "curse", "slow", "magic arrow" } }, {}),
                st(seed * 11 + 3, 12), st(seed * 13 + 4, 20), st(seed * 17 + 5, 6) }
  local b = battle.new({ seed = seed * 7919, spells = spells, creatures = creatures,
                         sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
  local t0 = os.clock()
  ai.run(b, { [0] = true, [1] = true }, 2000)
  return b, os.clock() - t0
end

function T.real_auto_battles()
  local ls = loadfile(root .. "/extracted/rules/spells.lua")
  local lc = loadfile(root .. "/extracted/rules/creatures.lua")
  if not (ls and lc) then return end
  local spells, creatures = ls(), lc()
  local keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys)
  local ended, worst = 0, 0
  for seed = 1, 12 do
    local b, t = auto_battle(seed, creatures, spells, keys)
    if b.finished then ended = ended + 1 end
    worst = math.max(worst, t)
    if seed <= 2 then
      local again = auto_battle(seed, creatures, spells, keys)
      eq(again:checksum(), b:checksum(), "a replay")
    end
  end
  assert(ended >= 10, "battles that ended: " .. ended)
  AI_WORST = worst
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
return #names, AI_WORST
