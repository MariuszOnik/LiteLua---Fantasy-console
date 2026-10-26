-- Tests of heroes in battle (HeroesDS/combat/heroes.lua), run by test_combat.py through
-- lupa. Argument: the HeroesDS folder.

local root = ...
package.path = root .. "/?.lua;" .. package.path

local stats = require("combat.stats")
local damage = require("combat.damage")
local battle = require("combat.battle")
local heroes = require("combat.heroes")
local abilities = require("combat.abilities")
abilities.install(battle)

local T = {}

local function eq(got, want, what)
  if got ~= want then
    error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
  end
end

-- Artifacts in the shape of artifacts.lua
local DB = {
  sword = { effects = { { type = "attack", target = "self", amount = 80, ranged = false } } },
  bow = { effects = { { type = "attack", target = "self", amount = 50, melee = false },
                      { type = "ability", target = "self", amount = 0, ability = "ranged" } } },
  buckler = { effects = { { type = "defense", target = "self", amount = 30, ranged = false } } },
  plate = { effects = { { type = "defense", target = "self", amount = 500 } } },
  amulet = { effects = { { type = "hit_points_pct", target = "self", amount = 50 },
                         { type = "magic_resistance_pct", target = "self", amount = 50 } } },
  axe = { effects = { { type = "extra_damage", target = "self", amount = 40, per_level = 4 } } },
  boots = { effects = { { type = "combat_move", target = "self", amount = 600 },
                        { type = "speed", target = "self", amount = -1 } } },
  ward = { effects = { { type = "spell_effect", target = "self", amount = 0, spell = "protection from chaos" } } },
  cloak = { effects = { { type = "set_bonus", target = "self", amount = 0, required = { "cloak", "ring" },
                          subs = { { type = "set_spell", target = "self", amount = 1, spell = "guardian angel" } } } } },
  ring = { effects = {} },
  warring = { effects = { { type = "damage_pct", target = "own_creatures", amount = 20 },
                          { type = "ability", target = "own_creatures", amount = 0, ability = "normal_melee" } } },
  fizbin = { effects = { { type = "spell_effect", target = "enemy_creatures", amount = 0, spell = "misfortune" } } },
}

local CREATURES = {
  pikeman = { name = "pikinier", hp = 15, dmg = { 3, 6 }, attack = 15, defense = 15, move = 15, speed = 5,
              shots = 0, size = 4, level = 1, alignment = "order", abilities = {} },
  archer = { name = "łucznik", hp = 10, dmg = { 2, 4 }, attack = 10, defense = 10, move = 15, speed = 6,
             shots = 12, size = 4, level = 1, alignment = "order", abilities = { ranged = true } },
}

---------------------------------------------------------------------------------------------
function T.hero_from_skills()
  local h = heroes.stack({ name = "H", level = 5, skills = { combat = 3, archery = 5, toughness = 2, resistance = 3 } })
  eq(h.attack, 30); eq(h.ranged_attack, 30); eq(h.defense, 20); eq(h.shots, 24)
  eq(h.magic_resistance, 70); eq(h.hp, 140); eq(h.move, 24); eq(h.size, 4)
  assert(h.abilities.first_strike and not h.abilities.strikes_twice, "Melee expert")
  assert(h.abilities.siege_machine and h.abilities.long_range and h.abilities.ranged_first_strike
         and h.abilities.shoots_twice, "Archery grandmaster")
  heroes.skill_abilities = false
  h = heroes.stack({ name = "H", level = 5, skills = { combat = 5, archery = 5 } })
  assert(next(h.abilities) == nil, "the switch is off")
  heroes.skill_abilities = true
  h = heroes.stack({ name = "H", level = 5, skills = { combat = 5, archery = 2 } })
  assert(h.abilities.strikes_twice and h.abilities.siege_machine and not h.abilities.long_range)
end

function T.hero_artifacts()
  local h = heroes.stack({ name = "H", level = 10, skills = { resistance = 1 },
                           artifacts = { "sword", "buckler", "plate", "amulet", "axe", "boots", "ward" } }, DB)
  eq(h.attack, 18, "10 + 8 melee"); eq(h.ranged_attack, 7, "the sword is melee only")
  eq(h.defense, 10 + 3 + 50); eq(h.ranged_defense, 10 + 50, "the buckler is melee only")
  eq(h.hp, 190 * 150 // 100)
  eq(h.magic_resistance, 30 + 35, "half of what is left")
  eq(h.dmg_lo, 30 + 80); eq(h.dmg_hi, 45 + 80, "40 + 4 x level")
  eq(h.move, 30, "+600 move points = 6 cells"); eq(h.speed, 5)
  assert(h.effects["protection from chaos"], "a lasting spell")
  local b = heroes.stack({ name = "B", level = 1, artifacts = { "bow" } }, DB)
  assert(b.shooter); eq(b.shots, 12); eq(b.ranged_attack, 12); eq(b.attack, 10)
  local one = heroes.stack({ name = "C", level = 1, artifacts = { "cloak" } }, DB)
  eq(one.effects["guardian angel"], nil, "half a set")
  local set = heroes.stack({ name = "C", level = 1, artifacts = { "cloak", "ring" } }, DB)
  eq(set.effects["guardian angel"].power, 1, "the whole set")
end

function T.ranged_defense_in_damage()
  local h = heroes.stack({ name = "H", level = 1, artifacts = { "buckler" } }, DB)   -- 13 / 10
  local a = stats.creature("x", CREATURES.pikeman, 1)                                 -- attack 15
  eq(damage.blow(a, h, 13, { ranged = false }), 15, "15 / 13 x 13")
  eq(damage.blow(a, h, 13, { ranged = true }), 20, "15 / 10 x 13 = 19.5")
end

function T.army_bonus()
  local list = {
    { name = "A", level = 1, skills = { offense = 2, tactics = 2, leadership = 3 }, artifacts = { "warring" } },
    { name = "B", level = 1, skills = { offense = 4, defense = 1 } },
  }
  local bonus = heroes.army_bonus(list, DB)
  eq(bonus.attack_pct, 40 + 20, "the best Offense + the ring"); eq(bonus.defense_pct, 10)
  eq(bonus.speed, 2); eq(bonus.move, 4, "Tactics 2: 4.5 cells, truncated")
  eq(bonus.morale, 3); eq(bonus.luck, 3)
  local st = stats.creature("pikeman", CREATURES.pikeman, 10)
  heroes.apply_bonus(st, bonus)
  eq(st.attack, 15 * 160 // 100); eq(st.defense, 16); eq(st.speed, 7); eq(st.move, 19)
  eq(st.luck, 3); eq(st.morale_bonus, 3)
  assert(st.normal_melee, "an ability for the army")
  local t5 = heroes.army_bonus({ { name = "T", level = 1, skills = { tactics = 5 } } }, DB)
  eq(t5.move, 9, "+3 on the screen")
end

function T.build_a_battle()
  local spec = { seed = 5, sides = {
    [0] = { heroes = { { name = "Gem", level = 6, alignment = "order", skills = { combat = 3, leadership = 1 },
                         artifacts = { "fizbin" } } },
            army = { { creature = "pikeman", count = 20 }, { creature = "archer", count = 15 } } },
    [1] = { army = { { creature = "pikeman", count = 25 } } },
  } }
  local setup = heroes.build(spec, { creatures = CREATURES, artifacts = DB, spells = {} })
  local st0 = setup.sides[0].stacks
  eq(#st0, 3); assert(st0[1].is_hero); eq(st0[1].slot, 0); eq(st0[2].slot, 1); eq(st0[3].slot, 2)
  eq(st0[2].luck, 1, "Leadership")
  assert(setup.sides[1].stacks[1].effects.misfortune, "the Fizbin on the enemy")
  local b = battle.new(setup)
  eq(b.units[1].x, 76 - 1, "the hero in slot 0, size 4"); eq(b.units[1].morale, 1 + 0 + 0)
  eq(b.units[2].morale, 1 + 1, "army morale + Leadership")
  local n = 0
  while not b.finished and n < 300 do
    local o = b:options()
    local best
    for id in pairs(o.shoot) do if not best or id < best then best = id end end
    local ev = best and b:act({ type = "shoot", target = best })
    if not ev then
      for id in pairs(o.melee) do if not best or id < best then best = id end end
      ev = best and b:act({ type = "melee", target = best })
    end
    if not ev then assert(b:act({ type = "defend" })) end
    n = n + 1
  end
  assert(b.finished)
end

function T.hero_first_strike()
  local spec = { seed = 1, sides = {
    [0] = { heroes = { { name = "H", level = 10, skills = { combat = 3 } } } },
    [1] = { army = { { creature = "pikeman", count = 5 } } },
  } }
  local setup = heroes.build(spec, { creatures = CREATURES, artifacts = DB, spells = {} })
  setup.sides[0].stacks[1].speed = 20
  local b = battle.new(setup)
  local h, p = b.units[1], b.units[2]
  h.x, h.y = 50, 54; p.x, p.y = 50, 50
  b:take_events()
  local ev = assert(b:act({ type = "melee", target = p.id }))
  local together = 0
  for _, e in ipairs(ev) do if e.t == "together" then together = together + 1 end end
  eq(together, 0, "the hero strikes first")
end

-- Real data, when generated locally: every artifact worn by a hero builds a stack
function T.real_artifacts()
  local la = loadfile(root .. "/extracted/rules/artifacts.lua")
  if not la then return end
  local db = la()
  local n = 0
  for key in pairs(db) do
    local h = heroes.stack({ name = "H", level = 10, skills = { combat = 2, archery = 2 }, artifacts = { key } }, db)
    assert(h.hp > 0 and h.attack > 0 and h.defense > 0 and h.move >= 1 and h.speed >= 1, key)
    heroes.army_bonus({ { name = "H", level = 1, artifacts = { key } } }, db)
    n = n + 1
  end
  assert(n > 200, "artifacts: " .. n)
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
