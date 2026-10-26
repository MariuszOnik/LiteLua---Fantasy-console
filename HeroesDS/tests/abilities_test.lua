-- Tests of creature abilities (HeroesDS/combat/abilities.lua, magic.lua), run by
-- test_combat.py through lupa. Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local grid = require("combat.grid")
local stats = require("combat.stats")
local battle = require("combat.battle")
local magic = require("combat.magic")
local abilities = require("combat.abilities")
abilities.install(battle)

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

-- The spells the abilities use, with the flags of the game's table (spells.lua)
local ALL = { elementals = true, mechanical = true, undead = true }
local function F(t, all) local f = {}; for k in pairs(t) do f[k] = true end
  if all then for k in pairs(ALL) do f[k] = true end end; return f end
local SPELLS = {
  weakness = { school = "death", cost = 3, base = 0, flags = F({ curse = 1, enemies = 1, resisted = 1 }, true) },
  stun = { school = "order", cost = 2, base = 0, flags = F({ curse = 1, enemies = 1 }) },
  aging = { school = "death", cost = 3, base = 0, flags = F({ curse = 1, enemies = 1, friends = 1, resisted = 1 }) },
  blind = { school = "order", cost = 8, base = 0, flags = F({ curse = 1, enemies = 1, resisted = 1, elementals = 1, mechanical = 1 }) },
  curse = { school = "death", cost = 2, base = 0, flags = F({ curse = 1, enemies = 1, resisted = 1 }, true) },
  ["short hypnotism"] = { school = "order", cost = 5, base = 0, flags = F({ curse = 1, enemies = 1, mind = 1 }) },
  frozen = { school = "order", cost = 8, base = 0, flags = F({ curse = 1, enemies = 1, cold = 1, resisted = 1 }, true) },
  lightning = { school = "chaos", cost = 5, base = 70, flags = F({ damage = 1, enemies = 1, friends = 1 }, true) },
  poison = { school = "death", cost = 2, base = 10, flags = F({ curse = 1, damage = 1, enemies = 1, resisted = 1 }) },
  ["fire shield"] = { school = "chaos", cost = 2, base = 0, flags = F({ enemies = 1, friends = 1, fire = 1 }, true) },
  fear = { school = "death", cost = 5, base = 0, flags = F({ enemies = 1, friends = 1 }, true) },
  panic = { school = "death", cost = 2, base = 0, flags = F({ enemies = 1, fear = 1, mind = 1, resisted = 1 }) },
  rebirth = { school = "life", cost = 12, base = 55, flags = F({ bodies = 1, friends = 1, healing = 1 }) },
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
  return battle.new({ seed = seed or 1, spells = SPELLS,
                      sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
end

local function find(events, kind, key, value)
  local out = {}
  for _, e in ipairs(events) do
    if e.t == kind and (key == nil or e[key] == value) then out[#out + 1] = e end
  end
  return out
end

local function place(u, x, y) u.x, u.y = x, y end

-- a (speed 9) next to d (speed 3): d at (50, 50), a at (50, 52)
local function duel(over_a, over_d, na, nd, seed)
  local a, d = cr(over_a, na), cr(over_d, nd)
  if over_a and over_a.speed == nil then a.speed = 9 end
  if not over_a or not over_a.speed then a.speed = 9 end
  if not over_d or not over_d.speed then d.speed = 3 end
  local b = make({ a }, { d }, seed)
  place(a, 50, 52); place(d, 50, 50)
  b:take_events()
  return b, a, d
end

---------------------------------------------------------------------------------------------
function T.hydra_strikes_every_adjacent_enemy()
  local h = cr({ speed = 9, abilities = { hydra_strike = true } }, 5)
  local e1, e2, e3 = cr({ speed = 3 }), cr({ speed = 3 }), cr({ speed = 3 })
  local b = make({ h }, { e1, e2, e3 })
  place(h, 50, 50); place(e1, 50, 52); place(e2, 52, 50); place(e3, 60, 60)
  local ev = assert(b:act({ type = "melee", target = e1.id }))
  local struck = {}
  for _, e in ipairs(find(ev, "melee", "stack", h.id)) do struck[e.target] = true end
  assert(struck[e1.id] and struck[e2.id], "both neighbours")
  assert(not struck[e3.id], "not the far one")
end

function T.three_headed_two_nearest()
  local c = cr({ speed = 9, abilities = { ["3_headed_attack"] = true } }, 5)
  local t, n1, n2, n3 = cr({ speed = 3 }), cr({ speed = 3 }), cr({ speed = 3 }), cr({ speed = 3 })
  local b = make({ c }, { t, n1, n2, n3 })
  c.size, t.size = 4, 2
  place(c, 50, 50); place(t, 54, 51)       -- t touches c
  place(n1, 54, 53); place(n2, 54, 49)     -- beside both
  place(n3, 48, 48)                         -- beside c only
  local ev = assert(b:act({ type = "melee", target = t.id }))
  local hits = find(ev, "melee", "stack", c.id)
  eq(#hits, 3, "the target and two more")
  for _, e in ipairs(hits) do assert(e.target ~= n3.id, "beside the target too") end
end

function T.breath_strikes_behind_friend_or_foe()
  local dr = cr({ speed = 9, abilities = { breath_attack = true } }, 3)
  local own = cr({ speed = 2 })
  local t, behind = cr({ speed = 3 }), cr({ speed = 3 })
  local b = make({ dr, own }, { t, behind })
  place(dr, 50, 56); place(t, 50, 54); place(own, 50, 51); place(behind, 60, 60)
  local ev = assert(b:act({ type = "melee", target = t.id }))
  local hits = find(ev, "melee", "stack", dr.id)
  eq(#hits, 2); eq(hits[2].target, own.id, "its own stack behind the target")
  own.abilities.fire_resistance = true
  eq(#abilities.extra_targets(b, dr, t, false), 0, "fire resistance keeps it out")
end

function T.area_shot_hits_all_around()
  local cy = cr({ speed = 9, shots = 5, abilities = { ranged = true, area_effect = true } }, 3)
  local t, n, own = cr({ speed = 3 }), cr({ speed = 3 }), cr({ speed = 2 })
  local b = make({ cy, own }, { t, n })
  place(t, 40, 40); place(n, 42, 40); place(own, 40, 42)
  local ev = assert(b:act({ type = "shoot", target = t.id }))
  local hit = {}
  for _, e in ipairs(find(ev, "shoot", "stack", cy.id)) do hit[e.target] = true end
  assert(hit[t.id] and hit[n.id] and hit[own.id], "everything next to the target")
end

function T.poison_then_each_turn()
  local b, a, d = duel({ abilities = { poison = true }, dmg = { 8, 8 } }, { hp = 50 }, 10, 10)
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local dealt = find(ev, "melee", "stack", a.id)[1].damage
  eq(d.poison, dealt >> 2, "a quarter of the blow")
  assert(d.effects.poison, "poisoned")
  -- d's turn comes right after: the poison acts at its start, in the same events
  local doses = find(ev, "effect", "effect", "poison")
  eq(#doses, 2, "taking hold, then at the start of d's turn")
  eq(doses[2].damage, d.poison)
  -- Death Ward halves the dose
  b, a, d = duel({ abilities = { poison = true }, dmg = { 8, 8 } }, { hp = 50, abilities = { death_protection = true } }, 10, 10)
  ev = assert(b:act({ type = "melee", target = d.id }))
  dealt = find(ev, "melee", "stack", a.id)[1].damage
  eq(d.poison, (dealt // 2) >> 2)
end

function T.fire_shield_burns_the_attacker()
  local b, a, d = duel({ hp = 100, dmg = { 10, 10 } }, { hp = 100, abilities = { fire_shield = true, no_retaliation = false } }, 4, 10)
  d.retaliated = true                        -- only the shield answers
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local dealt = find(ev, "melee", "stack", a.id)[1].damage
  local burn = find(ev, "effect", "effect", "fire shield")[1]
  eq(burn.stack, a.id); eq(burn.damage, (dealt + 3) >> 2)
  a.abilities.fire_resistance = true
  b, a, d = duel({ hp = 100, abilities = { fire_resistance = true } }, { hp = 100, abilities = { fire_shield = true } }, 4, 10)
  d.retaliated = true
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "effect", "effect", "fire shield"), 0, "fire cannot touch it")
end

function T.stun_takes_the_next_turn()
  -- a blow taking 60% of the health: 55% to stun; find a seed that stuns
  local stunned
  for seed = 1, 40 do
    local b, a, d = duel({ abilities = { stunning = true }, dmg = { 6, 6 } }, { hp = 10 }, 10, 10, seed * 7919 + 13)
    d.retaliated = true
    local ev = assert(b:act({ type = "melee", target = d.id }))
    if #find(ev, "effect", "effect", "stun") == 2 then   -- taking hold, then the lost turn
      stunned = true
      local lost = find(ev, "effect", "lost_turn", true)
      eq(#lost, 1); eq(lost[1].stack, d.id, "d lost its turn")
      eq(b:current().id, a.id, "a again, next round")
      eq(d.effects.stun, nil, "counted down")
      break
    end
  end
  assert(stunned, "some seed stuns")
  -- not the undead
  local b, a, d = duel({ abilities = { stunning = true }, dmg = { 100, 100 } }, { hp = 10000, abilities = { undead = true } }, 10, 1)
  local ev = b:act({ type = "melee", target = d.id })
  eq(#find(ev, "effect", "effect", "stun"), 0)
end

function T.weakness_and_resistance()
  local b, a, d = duel({ abilities = { weakness = true } }, { hp = 100 }, 1, 10)
  d.retaliated = true
  b:act({ type = "melee", target = d.id })
  assert(d.effects.weakness, "weakened")
  b, a, d = duel({ abilities = { weakness = true } }, { hp = 100, magic_resistance = 100 }, 1, 10)
  d.retaliated = true
  local ev = assert(b:act({ type = "melee", target = d.id }))
  eq(d.effects.weakness, nil)
  eq(find(ev, "resisted")[1].spell, "weakness")
  eq(magic.resistance(b, cr({ magic_resistance = 50 }), "weakness"), 50)
  local w = cr({ magic_resistance = 50 }); w.effects["magic resistance"] = {}
  eq(magic.resistance(b, w, "weakness"), 75, "half of what is left")
  w.effects["protection from death"] = {}
  eq(magic.resistance(b, w, "weakness"), 87, "and a ward of the school: 25 - 12")
end

function T.lightning_and_vampire()
  local b, a, d = duel({ abilities = { lightning = true } }, { hp = 1000, magic_resistance = 50 }, 3, 10)
  d.retaliated = true
  local ev = assert(b:act({ type = "melee", target = d.id }))
  eq(find(ev, "effect", "effect", "lightning")[1].damage, 45, "30 x 3, half resisted")
  b, a, d = duel({ abilities = { vampire = true }, hp = 10, dmg = { 30, 30 } }, { hp = 1000 }, 5, 10)
  d.retaliated = true
  a.count = 3                                -- two dead
  local hp0 = stats.total_health(a)
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(a.count, 5, "the dead are back (75 hp drained, 20 needed)")
  eq(#find(ev, "effect", "effect", "vampirism"), 1)
  assert(stats.total_health(a) > hp0)
end

function T.regeneration()
  local b, a, d = duel({ abilities = { regeneration = true }, hp = 80 }, {}, 3, 1)
  a.wounds = 70
  b:act({ type = "defend" }); b:act({ type = "defend" })
  eq(a.wounds, 20, "50 at the start of its turn")
end

function T.fear_stops_the_strike_back()
  local b, a, d = duel({ abilities = { panic = true } }, { hp = 100 }, 5, 10)
  local ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "melee", "stack", d.id), 0, "too afraid")
  b, a, d = duel({ abilities = { panic = true } }, { hp = 100, abilities = { death_protection = true } }, 5, 10)
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "melee", "stack", d.id), 1, "Death Ward")
  b, a, d = duel({ abilities = { panic = true } }, { hp = 100, abilities = { undead = true } }, 5, 10)
  ev = assert(b:act({ type = "melee", target = d.id }))
  eq(#find(ev, "melee", "stack", d.id), 1, "the undead know no fear (Mind)")
end

function T.rebirth()
  local b, a, d = duel({ dmg = { 50, 50 } }, { hp = 40, abilities = { rebirth = true } }, 20, 3)
  d.spell_points = 12
  local ev = assert(b:act({ type = "melee", target = d.id }))
  local rv = find(ev, "revived")
  eq(#rv, 1); eq(rv[1].rose, true)
  eq(d.count, 3, "55 x 3 = 165 hp: 3 of 40 hp back (at most its start)")
  eq(d.spell_points, 0)
  assert(not b.finished)
end

function T.stone_gaze()
  local b, a, d = duel({ abilities = { stone_gaze = true }, dmg = { 1, 1 } }, { hp = 20 }, 4, 10)
  d.retaliated = true
  local ev = assert(b:act({ type = "melee", target = d.id }))
  -- 4 x 1 = 4 base, plus 250 x 4 / 1000 of a 20 hp creature = 20
  eq(find(ev, "melee", "stack", a.id)[1].damage, 24)
  eq(#find(ev, "effect", "effect", "stone_gaze"), 1)
end

function T.binding_holds_until_the_binder_moves()
  local b, a, d = duel({ abilities = { binding = true } }, { hp = 100 }, 5, 10)
  d.retaliated = true
  b:act({ type = "melee", target = d.id })
  eq(d.bound_by, a.id)
  local o = b:options()
  eq(o.stack, d.id)
  local n = 0
  for _ in pairs(o.move) do n = n + 1 end
  eq(n, 1, "only where it stands")
  b:act({ type = "defend" })
  b:act({ type = "move", x = a.x + 3, y = a.y + 3 })
  eq(d.bound_by, nil, "released")
end

function T.devouring()
  local found
  for seed = 1, 30 do
    local b, a, d = duel({ abilities = { devouring = true } }, { hp = 1000 }, 30, 10, seed * 7919 + 13)
    d.retaliated = true
    local ev = assert(b:act({ type = "melee", target = d.id }))
    local dv = find(ev, "effect", "effect", "devour")[1]
    if dv then
      assert(dv.damage % 1000 == 0 and dv.damage <= 3000, "whole creatures, at most a tenth of 30")
      found = true
      break
    end
  end
  assert(found)
end

function T.hypnotize_turns_a_stack()
  local found
  for seed = 1, 60 do
    local b, a, d = duel({ abilities = { hypnotize = true } }, { hp = 1000 }, 5, 10, seed * 7919 + 13)
    d.retaliated = true
    b:act({ type = "melee", target = d.id })
    if d.hypnotized then
      eq(b:side_of(d), 0, "fights for the other side")
      found = true
      break
    end
  end
  assert(found)
end

function T.on_death_clears_spells()
  local b, a, d = duel({ dmg = { 100, 100 } }, {}, 10, 1)
  d.effects.bless = { power = 0 }
  d.effects["guardian angel"] = { power = 1 }
  b:act({ type = "melee", target = d.id })
  eq(d.effects.bless, nil); assert(d.effects["guardian angel"], "kept")
end

-- Real data, when generated locally: whole battles between many kinds of creatures with all
-- their abilities, to catch errors on rare paths
function T.real_battles()
  local lc = loadfile(root .. "/extracted/rules/creatures.lua")
  local ls = loadfile(root .. "/extracted/rules/spells.lua")
  if not (lc and ls) then return end
  local creatures, spells = lc(), ls()
  local keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys)
  local function stack(i, n)
    local key = keys[(i - 1) % #keys + 1]
    return stats.creature(key, creatures[key], n)
  end
  local ended = 0
  for i = 1, 25 do
    local att = { stack(i, 12), stack(i * 7 + 3, 5) }
    local def = { stack(i * 13 + 5, 8), stack(i * 31 + 11, 20) }
    local b = battle.new({ seed = i * 7919, spells = spells,
                           sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
    local n = 0
    while not b.finished and n < 400 do
      local o = b:options()
      local best
      for id in pairs(o.shoot) do if not best or id < best then best = id end end
      local ev
      if best then ev = b:act({ type = "shoot", target = best }) end
      if not ev then
        best = nil
        for id in pairs(o.melee) do if not best or id < best then best = id end end
        if best then ev = b:act({ type = "melee", target = best }) end
      end
      if not ev then ev = assert(b:act({ type = "defend" })) end
      n = n + 1
    end
    if b.finished then ended = ended + 1 end
  end
  assert(ended > 15, "most battles end: " .. ended)
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
