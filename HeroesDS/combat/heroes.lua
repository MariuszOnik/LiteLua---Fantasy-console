-- HeroesDS combat: heroes in battle and their armies (MECHANICS.md 9, 13).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Game.swift
-- (heroCombatant), HeroSkills.swift (ArmyBonuses), CombatScreen.swift (armyFighters), with
-- the heroes4.exe addresses; plus what only the skills' text says (switches below).
--
-- A hero: { name, level, alignment, skills = { combat = 0..5, archery =, toughness =,
--   resistance =, offense =, defense =, tactics =, leadership =, ... }, artifacts = { key, ... }
--   (worn), size = 4 (its combat model) }. Artifacts come from artifacts.lua.

local stats = require("combat.stats")
local num = require("combat.num")

local heroes = {}

-- What the skills' text gives a hero beyond attack and defense (homm4-mac does not have
-- it; H2 / H7: the text, until the exe says otherwise): Melee expert+ First Strike,
-- grandmaster also Strikes Twice; Archery advanced+ no obstacle penalty, expert+ no range
-- penalty, master+ Ranged First Strike, grandmaster also Shoots Twice
heroes.skill_abilities = true

local RESISTANCE = { [0] = 0, 30, 50, 70, 80, 100 }

local function skill(h, k) return num.clamp((h.skills or {})[k] or 0, 0, 5) end

-- Effects of the worn artifacts, set bonuses included (all parts worn)
function heroes.artifact_effects(h, db)
  local worn, out = {}, {}
  for _, key in ipairs(h.artifacts or {}) do worn[key] = true end
  for _, key in ipairs(h.artifacts or {}) do
    local a = db and db[key]
    for _, e in ipairs(a and a.effects or {}) do
      if e.type == "set_bonus" then
        local all = true
        for _, r in ipairs(e.required or {}) do if not worn[r] then all = false end end
        if all then for _, s in ipairs(e.subs or {}) do out[#out + 1] = s end end
      else
        out[#out + 1] = e
      end
    end
  end
  return out
end

local function on_self(e) return e.target == "self" or e.target == "all" end
local function on_army(e) return e.target == "own_creatures" or e.target == "all" end

-- A hero as a stack (Game.swift heroCombatant): skills, then the worn artifacts; hero
-- attack and defense from items are in tenths of a point, move in move points (100 a cell)
function heroes.stack(h, db)
  local st = stats.hero(h.name, h.level, h.skills, h.size)
  st.alignment = h.alignment or ""
  st.hero = h
  local hp_pct, resist = 0, RESISTANCE[skill(h, "resistance")]
  local move = 0
  st.ranged_defense = st.defense
  for _, e in ipairs(heroes.artifact_effects(h, db)) do
    if on_self(e) then
      local t, amt = e.type, e.amount or 0
      if t == "attack" then
        if e.melee ~= false then st.attack = st.attack + amt // 10 end
        if e.ranged ~= false then st.ranged_attack = (st.ranged_attack or st.attack) + amt // 10 end
      elseif t == "defense" then
        -- melee and ranged defense apart (homm4-mac adds both to one)
        if e.melee ~= false then st.defense = st.defense + amt // 10 end
        if e.ranged ~= false then st.ranged_defense = st.ranged_defense + amt // 10 end
      elseif t == "hit_points_pct" then hp_pct = hp_pct + amt
      elseif t == "extra_damage" then
        local extra = amt + (e.per_level or 0) * h.level // math.max(1, e.divisor or 1)
        st.dmg_lo, st.dmg_hi = st.dmg_lo + extra, st.dmg_hi + extra
      elseif t == "speed" then st.speed = math.max(1, st.speed + amt)
      elseif t == "magic_resistance_pct" then resist = resist + (100 - resist) * amt // 100
      elseif t == "combat_move" then move = move + amt
      elseif t == "morale" then st.morale_bonus = (st.morale_bonus or 0) + amt
      elseif t == "luck" then st.luck = st.luck + amt
      elseif t == "ability" then
        st.abilities[e.ability] = true
        if e.ability == "ranged" then st.shooter = true; if st.shots == 0 then st.shots = 12 end end
      elseif t == "spell_effect" or t == "set_spell" then
        if type(e.spell) == "string" then st.effects[e.spell] = { power = e.amount or 0 } end
      end
    end
  end
  if st.ranged_defense == st.defense then st.ranged_defense = nil end
  st.hp = st.hp * (100 + hp_pct) // 100
  st.magic_resistance = math.min(100, resist)
  st.move = math.max(1, 24 + move // 100)
  st.caster = heroes.caster(h, db)
  st.spell_points = st.caster.mana
  if heroes.skill_abilities then
    local melee, archery = skill(h, "combat"), skill(h, "archery")
    if melee >= 3 then st.abilities.first_strike = true end
    if melee >= 5 then st.abilities.strikes_twice = true end
    if archery >= 2 then st.abilities.siege_machine = true end
    if archery >= 3 then st.abilities.long_range = true end
    if archery >= 4 then st.abilities.ranged_first_strike = true end
    if archery >= 5 then st.abilities.shoots_twice = true end
  end
  return st
end

-- A hero's spell book (BattleSpells.swift Caster, Artifacts.swift): known spells
-- (h.spells), those of worn spell books (cast with the school skill) and scrolls (without),
-- spell points h.mana or the maximum (10 + 10 per level of Healing, Enchantment,
-- Occultism, Conjuration, Herbalism + items), power bonuses of items per spell
function heroes.caster(h, db)
  local effects = heroes.artifact_effects(h, db)
  local spells, free, power_bonus, items_points = {}, {}, {}, 0
  for _, k in ipairs(h.spells or {}) do spells[k] = true end
  local cost_items = {}
  for _, e in ipairs(effects) do
    if on_self(e) then
      if e.type == "spellbook" and type(e.spells) == "table" then
        for _, k in ipairs(e.spells) do spells[k] = true end
      elseif e.type == "scroll_spell" and type(e.spell) == "string" then
        spells[e.spell] = true; free[e.spell] = true
      elseif e.type == "spell_points" then items_points = items_points + (e.amount or 0)
      elseif e.type == "spell_power_pct" then
        power_bonus[#power_bonus + 1] = e
      elseif e.type == "spell_cost" then cost_items[#cost_items + 1] = e
      end
    end
  end
  local list = {}
  for k in pairs(spells) do list[#list + 1] = k end
  table.sort(list)
  local bonus = {}
  for _, k in ipairs(list) do
    for _, e in ipairs(power_bonus) do
      local all = e.spells == "all"
      if not all and type(e.spells) == "table" then
        for _, x in ipairs(e.spells) do if x == k then all = true end end
      end
      if all then bonus[k] = (bonus[k] or 0) + (e.amount or 0) end
    end
  end
  local max = 10 + 10 * (skill(h, "healing") + skill(h, "enchantment") + skill(h, "black")
    + skill(h, "conjuration") + skill(h, "herbalism")) + (h.spell_point_bonus or 0) + items_points
  local known = {}
  for _, k in ipairs(h.spells or {}) do known[k] = true end
  return { level = h.level, skills = h.skills or {}, spells = list, free = free, known = known,
           power_bonus = bonus, cost_items = cost_items, mana = h.mana or max, max_mana = max }
end

-- Bonuses of an army's heroes for its creatures (HeroSkills.swift ArmyBonuses): the best
-- hero's Offense / Defense (+10% a level), Tactics (speed +level, move 3, 4, 6, 7, 9 cells:
-- the game shows a third of a cell's move), Leadership (morale and, as its text says,
-- luck +level); then every hero's items working on the army
function heroes.army_bonus(list, db)
  local function best(k)
    local m = 0
    for _, h in ipairs(list) do m = math.max(m, skill(h, k)) end
    return m
  end
  local t = best("tactics")
  local bonus = {
    attack_pct = 10 * best("offense"), defense_pct = 10 * best("defense"),
    speed = t, move = t == 0 and 0 or num.trunc(3 * (1 + 0.5 * (t - 1))),
    morale = best("leadership"), luck = best("leadership"),
    resistance = 0, abilities = {}, spells = {},
  }
  for _, h in ipairs(list) do
    for _, e in ipairs(heroes.artifact_effects(h, db)) do
      if on_army(e) then
        local ty, amt = e.type, e.amount or 0
        if ty == "damage_pct" then bonus.attack_pct = bonus.attack_pct + amt
        elseif ty == "defense" then bonus.defense_pct = bonus.defense_pct + amt
        elseif ty == "speed" then bonus.speed = bonus.speed + amt
        elseif ty == "morale" then bonus.morale = bonus.morale + amt
        elseif ty == "luck" then bonus.luck = bonus.luck + amt
        elseif ty == "magic_resistance_pct" then bonus.resistance = bonus.resistance + amt
        elseif ty == "combat_move" then bonus.move = bonus.move + amt // 100
        elseif ty == "ability" then bonus.abilities[#bonus.abilities + 1] = e.ability
        elseif ty == "spell_effect" and type(e.spell) == "string" then bonus.spells[#bonus.spells + 1] = e.spell
        end
      end
    end
  end
  return bonus
end

-- A creature stack with the bonuses (ArmyBonuses.apply)
function heroes.apply_bonus(st, bonus)
  st.attack = st.attack * (100 + bonus.attack_pct) // 100
  st.defense = st.defense * (100 + bonus.defense_pct) // 100
  st.speed = st.speed + bonus.speed
  st.move = st.move + bonus.move
  st.morale_bonus = (st.morale_bonus or 0) + bonus.morale
  st.luck = st.luck + bonus.luck
  if bonus.resistance > 0 then
    st.magic_resistance = st.magic_resistance + (100 - st.magic_resistance) * bonus.resistance // 100
  end
  for _, a in ipairs(bonus.abilities) do
    st.abilities[a] = true
    if a == "normal_melee" then st.normal_melee = true end
  end
  for _, sp in ipairs(bonus.spells) do st.effects[sp] = st.effects[sp] or { power = 0 } end
end

-- Spells an army's items put on the enemy (Fizbin of Misfortune): { creatures = {}, heroes = {} }
function heroes.enemy_spells(list, db)
  local out = { creatures = {}, heroes = {} }
  for _, h in ipairs(list) do
    for _, e in ipairs(heroes.artifact_effects(h, db)) do
      if e.type == "spell_effect" and type(e.spell) == "string" then
        if e.target == "enemy_creatures" then out.creatures[#out.creatures + 1] = e.spell end
        if e.target == "enemy_heroes" then out.heroes[#out.heroes + 1] = e.spell end
      end
    end
  end
  return out
end

-- A battle setup from armies: spec = { seed, field, sides = { [0] = { heroes = { hero, ... },
-- army = { { creature = key, count = n }, ... }, formation = 0 }, [1] = ... } },
-- data = { creatures = creatures.lua, artifacts = artifacts.lua, spells = spells.lua,
-- sizes = { [key] = footprint } (optional, else the creature's size) }.
-- Heroes take the first slots, then the stacks (CombatScreen.swift armyFighters).
function heroes.build(spec, data)
  local setup = { seed = spec.seed, field = spec.field, spells = data.spells, sides = {} }
  for side = 0, 1 do
    local s = spec.sides[side]
    local list = s.heroes or {}
    local bonus = heroes.army_bonus(list, data.artifacts)
    local stacks = {}
    for k, h in ipairs(list) do
      local st = heroes.stack(h, data.artifacts)
      st.slot = k - 1
      stacks[#stacks + 1] = st
    end
    for k, a in ipairs(s.army or {}) do
      local def = assert(data.creatures[a.creature], "no creature " .. tostring(a.creature))
      local st = stats.creature(a.creature, def, a.count)
      if data.sizes and data.sizes[a.creature] then st.size = data.sizes[a.creature] end
      heroes.apply_bonus(st, bonus)
      st.slot = #list + k - 1
      stacks[#stacks + 1] = st
    end
    setup.sides[side] = { stacks = stacks, formation = s.formation, enemy = heroes.enemy_spells(list, data.artifacts) }
  end
  -- the items' spells on the other side
  for side = 0, 1 do
    local en = setup.sides[1 - side].enemy
    for _, st in ipairs(setup.sides[side].stacks) do
      for _, sp in ipairs(st.is_hero and en.heroes or en.creatures) do
        st.effects[sp] = st.effects[sp] or { power = 0 }
      end
    end
  end
  return setup
end

return heroes
