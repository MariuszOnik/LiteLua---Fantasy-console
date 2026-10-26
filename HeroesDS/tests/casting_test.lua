-- Tests of casting spells (HeroesDS/combat/casting.lua), run by test_combat.py through lupa.
-- Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local grid = require("combat.grid")
local stats = require("combat.stats")
local battle = require("combat.battle")
local magic = require("combat.magic")
local heroes = require("combat.heroes")
local abilities = require("combat.abilities")
local casting = require("combat.casting")
abilities.install(battle)
casting.install(battle)

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

local ALL = { elementals = 1, mechanical = 1, undead = 1 }
local function S(id, school, level, cost, typ, base, inc, flags, extra)
  local f = { combat = true }
  for k in pairs(flags) do f[k] = true end
  if flags.all then for k in pairs(ALL) do f[k] = true end end
  local s = { id = id, school = school, level = level, cost = cost, type = typ, base = base or 0,
              increase = inc or 0, flags = f, creature = "" }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local SPELLS = {
  ["magic arrow"] = S(71, "order", 1, 2, "damage", 20, 2, { damage = 1, enemies = 1, all = 1 }),
  fireball = S(43, "chaos", 3, 5, "damage", 40, 4, { damage = 1, enemies = 1, friends = 1, fire = 1, all = 1 }),
  ["chain lightning"] = S(17, "chaos", 5, 12, "damage", 80, 8, { damage = 1, enemies = 1, friends = 1, all = 1 }),
  bless = S(10, "life", 1, 2, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  curse = S(23, "death", 1, 2, "curse", 0, 0, { curse = 1, enemies = 1, resisted = 1, all = 1 }),
  slow = S(141, "order", 2, 3, "curse", 0, 0, { curse = 1, enemies = 1, resisted = 1, all = 1 }),
  ["nature haste"] = S(104, "nature", 1, 2, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  ["mass haste"] = S(87, "nature", 3, 6, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  ["summon wolf"] = S(177, "nature", 2, 4, "summoning", 60, 6, { summoning = 1, friends = 1 }, { creature = "wolf" }),
  resurrection = S(133, "life", 4, 8, "resurrection", 30, 3, { bodies = 1, friends = 1, healing = 1 }),
  ["raise skeletons"] = S(125, "death", 1, 2, "summoning", 40, 4,
                          { summoning = 1, bodies = 1, enemies = 1, friends = 1, undead = 1 }, { creature = "skeleton" }),
  teleport = S(178, "order", 2, 3, "blessing", 0, 0, { blessing = 1, friends = 1, enemies = 1, resisted_if_enemy = 1, all = 1 }),
  quicksand = S(123, "nature", 2, 3, "", 6, 0, {}),
  smoke = S(142, "death", 1, 2, "blessing", 0, 0, { enemies = 1, friends = 1, all = 1 }),
  ["rock growth"] = S(134, "nature", 1, 2, "", 0, 0, {}),
  heal = S(56, "life", 1, 2, "healing", 15, 0, { healing = 1, friends = 1 }),
  poison = S(111, "death", 1, 2, "damage", 10, 1, { curse = 1, damage = 1, enemies = 1, resisted = 1 }),
  dispel = S(27, "order", 1, 2, "blessing", 0, 0, { blessing = 1, enemies = 1, friends = 1, all = 1 }),
  ["magic mirror"] = S(74, "chaos", 3, 5, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  ["guardian angel"] = S(53, "life", 5, 12, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  ["celestial armor"] = S(16, "life", 3, 5, "blessing", 50, 5, { blessing = 1, friends = 1, all = 1 }),
  martyr = S(79, "life", 3, 5, "blessing", 0, 0, { blessing = 1, friends = 1, all = 1 }),
  stun = S(154, "order", 1, 2, "curse", 0, 0, { curse = 1, enemies = 1 }),
  ["lightning"] = S(69, "chaos", 3, 5, "damage", 70, 7, { damage = 1, enemies = 1, friends = 1, all = 1 }, { cast_by = { "faerie dragon" } }),
}

local CREATURES = {
  wolf = { name = "wilk", hp = 20, dmg = { 3, 5 }, attack = 12, defense = 10, move = 20, speed = 7,
           shots = 0, size = 3, level = 2, alignment = "nature", xp = 15, abilities = {} },
  skeleton = { name = "szkielet", hp = 4, dmg = { 1, 3 }, attack = 6, defense = 6, move = 15, speed = 4,
               shots = 0, size = 2, level = 1, alignment = "death", xp = 3, abilities = { undead = true } },
  ["faerie dragon"] = { name = "smok", hp = 40, dmg = { 8, 12 }, attack = 15, defense = 15, move = 20, speed = 8,
                        shots = 0, size = 3, level = 3, alignment = "nature", xp = 30, spell_points = 30,
                        spell_power = 10, abilities = { flying = true, spellcaster = true } },
}

local function cr(over, count)
  local def = { name = "test", hp = 10, dmg = { 2, 4 }, attack = 10, defense = 10, move = 10,
                speed = 3, shots = 0, size = 2, level = 1, alignment = "might", abilities = {} }
  for k, v in pairs(over or {}) do def[k] = v end
  local st = stats.creature("test", def, count or 10)
  st.morale_bonus = -1
  return st
end

-- A hero (speed 20, acts first) knowing every spell above at grandmaster in all schools
local function mage(over)
  local h = { name = "Mag", level = 10, alignment = "order", skills = { life = 5, order = 5, death = 5,
              chaos = 5, nature = 5 }, spells = {}, mana = 200 }
  for k in pairs(SPELLS) do h.spells[#h.spells + 1] = k end
  for k, v in pairs(over or {}) do h[k] = v end
  local st = heroes.stack(h, {})
  st.speed = 20
  return st
end

local function make(att, def, seed)
  local b = battle.new({ seed = seed or 1, spells = SPELLS, creatures = CREATURES,
                         sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
  b:take_events()
  return b
end

local function find(events, kind, key, value)
  local out = {}
  for _, e in ipairs(events) do
    if e.t == kind and (key == nil or e[key] == value) then out[#out + 1] = e end
  end
  return out
end

---------------------------------------------------------------------------------------------
function T.castable_cost_power()
  local m = mage({ skills = { order = 1 }, spells = { "magic arrow", "slow" }, mana = 2 })
  local b = make({ m }, { cr() })
  local c = casting.castable(b, m)
  eq(#c, 1); eq(c[1], "magic arrow", "Slow needs order 2")
  eq(casting.cost(b, "magic arrow", m), 2)
  m.spell_points = 1
  eq(#casting.castable(b, m), 0, "not enough mana")
  -- power: (20 + 2 x 10) x (100 + 20 x mind) / 100, + Sorcery on damage spells
  local p = mage({ skills = { order = 1, mind = 2, sorcery = 1 } })
  b = make({ p }, { cr() })
  eq(magic.power(b, "magic arrow", p), 40 * 160 // 100)
  m.effects["power drain"] = {}
  eq(casting.cost(b, "magic arrow", m), 4, "Power Drain doubles")
  -- items: a scroll casts without the skill, at half price when not known
  local db = { scroll = { effects = { { type = "scroll_spell", target = "self", amount = 0, spell = "fireball" } } },
               ring = { effects = { { type = "spell_cost", target = "self", amount = -1, spells = "all" } } } }
  local s = heroes.stack({ name = "S", level = 1, skills = {}, artifacts = { "scroll", "ring" }, mana = 20 }, db)
  b = make({ s }, { cr() })
  eq(casting.castable(b, s)[1], "fireball")
  eq(casting.cost(b, "fireball", s), (5 - 1) // 2)
end

function T.damage_spell()
  local m, e = mage(), cr({ hp = 10, magic_resistance = 50 }, 20)
  local b = make({ m }, { e })
  local o = b:options()
  eq(o.spells["magic arrow"].aim, "unit")
  local ev = assert(b:act({ type = "cast", spell = "magic arrow", target = e.id }))
  -- (20 + 2 x 10) x 1.0 (no Mind) = 40, half resisted
  local hit = find(ev, "spell", "stack", e.id)[1]
  eq(hit.damage, 20); eq(hit.killed, 2)
  eq(m.spell_points, 198)
  eq(find(ev, "cast")[1].spell, "magic arrow")
  eq(b:current().id, e.id, "the turn ends")
end

function T.fireball_area_friend_and_foe()
  local m = mage()
  local own, e1, e2, far = cr(), cr(), cr(), cr()
  local b = make({ m, own }, { e1, e2, far })
  own.x, own.y = 50, 50; e1.x, e1.y = 53, 50; e2.x, e2.y = 50, 54; far.x, far.y = 60, 60
  local ev = assert(b:act({ type = "cast", spell = "fireball", x = 51, y = 51 }))
  local hit = {}
  for _, e in ipairs(find(ev, "spell")) do hit[e.stack] = true end
  assert(hit[own.id] and hit[e1.id] and hit[e2.id], "4 cells around, friend and foe")
  assert(not hit[far.id])
  eq(find(ev, "cast_at")[1].x, 51)
  local fr = cr({ abilities = { fire_resistance = true } })
  eq(magic.can_target(b, "fireball", m, fr), false, "fire resistant")
end

function T.chain_lightning_halves()
  local m = mage()
  local e1, e2, e3 = cr({ hp = 1000 }, 1), cr({ hp = 1000 }, 1), cr({ hp = 1000 }, 1)
  local b = make({ m }, { e1, e2, e3 })
  e1.x, e1.y = 50, 50; e2.x, e2.y = 50, 55; e3.x, e3.y = 50, 62
  local ev = assert(b:act({ type = "cast", spell = "chain lightning", target = e1.id }))
  local hits = find(ev, "spell")
  eq(hits[1].damage, 160); eq(hits[2].stack, e2.id); eq(hits[2].damage, 80)
  eq(hits[3].damage, 40)
  eq(#hits, 4); eq(hits[4].stack, m.id, "then its own caster, the nearest left"); eq(hits[4].damage, 20)
end

function T.bless_curse_and_lengths()
  local m, own, e = mage(), cr(), cr()
  local b = make({ m, own }, { e })
  own.effects.curse = { power = 0 }
  assert(b:act({ type = "cast", spell = "bless", target = own.id }))
  assert(own.effects.bless and not own.effects.curse, "Bless takes Curse off")
  eq(own.effects.bless.turns, nil, "the rest of the battle")
  local r = cr({ magic_resistance = 100 })
  b = make({ mage() }, { r })
  local ev = assert(b:act({ type = "cast", spell = "curse", target = r.id }))
  eq(#find(ev, "resisted"), 1); eq(r.effects.curse, nil)
  local s = cr()
  local m2 = mage()
  b = make({ m2 }, { s })
  b:act({ type = "cast", spell = "stun", target = s.id })
  -- stun: 1 turn (+1 when cast on the stack whose turn it is): it loses its next turn
  eq(s.effects.stun, nil, "already lost its turn and counted down")
end

function T.mass_spell()
  local m, a1, a2, e = mage(), cr(), cr(), cr()
  local b = make({ m, a1, a2 }, { e })
  local ev = assert(b:act({ type = "cast", spell = "mass haste" }))
  assert(a1.effects["nature haste"] and a2.effects["nature haste"] and m.effects["nature haste"])
  eq(e.effects["nature haste"], nil, "friends only")
  eq(#find(ev, "spell"), 3)
end

function T.summon_and_merge()
  local m = mage()
  local b = make({ m }, { cr() })
  local ev = assert(b:act({ type = "cast", spell = "summon wolf" }))
  local s = find(ev, "summon")[1]
  local w = b.units[s.stack]
  eq(w.kind, "wolf"); eq(w.side, 0)
  eq(w.count, ((60 + 6 * 10) * 100 // 100) // 15, "power / experience")
  assert(w.summoned and w.acted)
  b:act({ type = "defend" })
  ev = assert(b:act({ type = "cast", spell = "summon wolf" }))
  eq(#find(ev, "revived"), 1, "merged with the first"); eq(w.count, 16)
end

function T.resurrection_and_raising()
  local m, own, e = mage(), cr({ hp = 10 }, 10), cr()
  local b = make({ m, own }, { e })
  own.count = 4
  local ev = assert(b:act({ type = "cast", spell = "resurrection", target = own.id }))
  eq(own.count, 10, "(30 + 30) x 100% = 60 hp: 6 back")
  eq(find(ev, "revived")[1].count, 6)
  -- raising from a dead enemy stack
  local d = cr({ hp = 10 }, 10)
  b = make({ mage() }, { d, cr() })
  d.count = 0; d.death_handled = true
  ev = assert(b:act({ type = "cast", spell = "raise skeletons", target = d.id }))
  local s = b.units[find(ev, "revived")[1].stack]
  eq(s.kind, "skeleton"); eq(s.side, 0)
  eq(s.count, math.min(80 // 3, 10, (10 * 10 + 3) // 4), "min(power / xp, the dead, their hp / 4)")
end

function T.field_spells()
  local m, e = mage(), cr()
  local b = make({ m }, { e })
  assert(b:act({ type = "cast", spell = "smoke", x = 60, y = 60 }))
  assert(b.field.smoke[grid.key(59, 59)] and b.field.smoke[grid.key(62, 62)], "a 4 x 4 cloud")
  b:act({ type = "defend" })
  local ok, err = b:act({ type = "cast", spell = "rock growth", x = e.x + 1, y = e.y + 1 })
  eq(ok, nil); eq(err, "no room")
  assert(b:act({ type = "cast", spell = "rock growth", x = 60, y = 45 }))
  assert(not b.field:is_open(61, 46), "a 3 x 3 rock")
  b:act({ type = "defend" })
  assert(b:act({ type = "cast", spell = "quicksand", x = 55, y = 40 }))
  local n = 0
  for _ in pairs(b.field.quicksand) do n = n + 1 end
  eq(n, 6, "power = cells")
  b:act({ type = "defend" })
  local tx, ty = m.x - 6, m.y
  assert(b:act({ type = "cast", spell = "teleport", target = m.id, x = tx, y = ty }))
  eq(m.x, tx)
end

function T.magic_mirror()
  local m, e = mage(), cr({ hp = 1000 }, 1)
  e.abilities.magic_mirror = true
  local b = make({ m }, { e })
  local ev = assert(b:act({ type = "cast", spell = "magic arrow", target = e.id }))
  local back = find(ev, "spell", "stack", m.id)[1]
  eq(back.damage, 20, "half of 40 back on the caster")
end

function T.guardian_angel_shield_martyr()
  local m, own, e = mage(), cr({ hp = 10 }, 5), cr({ dmg = { 100, 100 }, speed = 1 }, 1)
  local b = make({ m, own }, { e })
  assert(b:act({ type = "cast", spell = "guardian angel", target = own.id }))
  eq(own.effects["guardian angel"].power, 2, "(10 + 10) x 100 / 1000 lives")
  local killed = b:wound(own, 30, e)
  eq(killed, 3); eq(own.count, 4, "two came back"); eq(own.effects["guardian angel"], nil, "no lives left")
  -- Heavenly Shield soaks first
  local h = mage()
  b = make({ h }, { cr() })
  assert(b:act({ type = "cast", spell = "celestial armor" }))
  eq(h.effects["celestial armor"].power, 100)
  b:wound(h, 60, nil); eq(h.wounds, 0); eq(h.effects["celestial armor"].power, 40)
  -- Martyr: the second pick's damage goes to the first
  local p1, p2 = cr({ hp = 10 }, 10), cr({ hp = 10 }, 10)
  b = make({ mage(), p1, p2 }, { cr() })
  assert(b:act({ type = "cast", spell = "martyr", target = p1.id, second = p2.id }))
  b:wound(p2, 25, nil)
  eq(p2.count, 10); eq(p1.count, 8, "p1 took it")
end

function T.healing_cures()
  local m, own = mage(), cr({ hp = 30 }, 3)
  local b = make({ m, own }, { cr() })
  own.wounds = 20; own.poison = 5; own.effects.poison = { power = 0 }
  assert(b:act({ type = "cast", spell = "heal", target = own.id }))
  eq(own.wounds, 5); eq(own.effects.poison, nil); eq(own.poison, 0)
end

function T.dispel()
  local m, own = mage(), cr()
  local b = make({ m, own }, { cr() })
  own.effects.bless = { power = 0 }; own.effects.curse = { power = 0 }
  assert(b:act({ type = "cast", spell = "dispel", target = own.id }))
  eq(own.effects.bless, nil); eq(own.effects.curse, nil)
end

function T.creature_caster()
  local d = stats.creature("faerie dragon", CREATURES["faerie dragon"], 5)
  d.speed = 20
  local e = cr({ hp = 1000 }, 1)
  local b = make({ d }, { e })
  eq(d.caster.spells[1], "lightning")
  local o = b:options()
  assert(o.spells.lightning)
  local ev = assert(b:act({ type = "cast", spell = "lightning", target = e.id }))
  -- 70 x (10 x 100 x 5 / 100) / 100 = 70 x 50 / 100
  eq(find(ev, "spell")[1].damage, 70 * 50 // 100)
  eq(d.spell_points, 25)
end

-- Real data, when generated locally: a grandmaster hero casts every combat spell it can on
-- every kind of target, to catch errors on rare paths
function T.real_spells()
  local ls = loadfile(root .. "/extracted/rules/spells.lua")
  local lc = loadfile(root .. "/extracted/rules/creatures.lua")
  if not (ls and lc) then return end
  local spells, creatures = ls(), lc()
  local keys = {}
  for k, s in pairs(spells) do if s.flags and s.flags.combat then keys[#keys + 1] = k end end
  table.sort(keys)
  local cast = 0
  for i, key in ipairs(keys) do
    local h = { name = "Mag", level = 20, alignment = "life", mana = 500, spells = { key },
                skills = { life = 5, order = 5, death = 5, chaos = 5, nature = 5, sorcery = 5 } }
    local m = heroes.stack(h, {})
    m.speed = 30
    local own = stats.creature("peasant", creatures.peasant, 30)
    local foe = stats.creature("skeleton", creatures.skeleton, 30)
    local foe2 = stats.creature("orc", creatures.orc, 20)
    local b = battle.new({ seed = i * 7919, spells = spells, creatures = creatures,
                           sides = { [0] = { stacks = { m, own } }, [1] = { stacks = { foe, foe2 } } } })
    b:take_events()
    own.count = 20                                   -- some dead to bring back
    local aim = casting.aim(b, key)
    local tries = {}
    if aim == "none" then tries = { {} }
    elseif aim == "cell" then tries = { { x = foe.x + 1, y = foe.y + 1 }, { x = 60, y = 50 } }
    elseif aim == "two_units" then tries = { { target = own.id, second = m.id }, { target = m.id, second = own.id } }
    else
      for _, t in ipairs({ foe, foe2, own, m }) do
        tries[#tries + 1] = { target = t.id, x = m.x - 6, y = m.y }
      end
    end
    for _, c in ipairs(tries) do
      c.type, c.spell = "cast", key
      if b:act(c) then cast = cast + 1; break end
    end
  end
  assert(cast > 80, "spells cast: " .. cast)
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
