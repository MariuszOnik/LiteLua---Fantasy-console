-- HeroesDS combat: a stack and its derived stats (MECHANICS.md 3-5, 9, 13.2).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Combat.swift
-- (Combatant) and Battle.swift (speed, move, morale, luck), with the heroes4.exe addresses.
--
-- Spells on a stack are kept by their key in spells.lua ("bless", "slow", ...):
-- st.effects[key] = { power = ..., turns = ... } (turns nil: the rest of the battle).

local num = require("combat.num")
local f32 = num.f32

local stats = {}

-- A creature stack from a creatures.lua entry
function stats.creature(key, def, count)
  local abilities = {}
  for k in pairs(def.abilities or {}) do abilities[k] = true end
  return {
    kind = key, name = def.name, is_hero = false,
    count = count, count_start = count, wounds = 0,
    hp = def.hp, dmg_lo = def.dmg[1], dmg_hi = def.dmg[2],
    attack = def.attack, defense = def.defense,
    speed = def.speed, move = def.move, shots = def.shots, size = def.size or 1,
    level = def.level, alignment = def.alignment, xp = def.xp or 0,
    magic_resistance = def.magic_resistance or 0,
    spell_points = def.spell_points or 0, spell_power = def.spell_power or 0,
    abilities = abilities,
    shooter = (def.shots or 0) > 0 or abilities.ranged == true,
    normal_melee = abilities.normal_melee == true,
    morale = 0, luck = 0,   -- from the army (set by the battle)
    effects = {},
  }
end

-- Hero attack, ranged attack and defense by skill level 0..5 (exe 0x732090 / 0x731ff0)
local HERO_MELEE = { [0] = 10, 15, 20, 30, 40, 40 }
local HERO_RANGED = { [0] = 7, 10, 15, 20, 30, 30 }
local HERO_DEFENSE = { [0] = 10, 15, 20, 30, 40, 60 }

-- A hero as a stack of one (MECHANICS.md 9, 13.2). skills: { combat = 0..5, archery =,
-- toughness = , ... } (the exe's keywords, MECHANICS.md 13.1)
function stats.hero(name, level, skills, size)
  skills = skills or {}
  local function sk(k) return num.clamp(skills[k] or 0, 0, 5) end
  local archery = sk("archery")
  return {
    kind = "hero", name = name, is_hero = true, level_hero = level, skills = skills,
    count = 1, count_start = 1, wounds = 0,
    hp = 10 * level + 90,
    dmg_lo = (16 * level - 16) // 10 + 16, dmg_hi = (24 * level - 24) // 10 + 24,
    attack = HERO_MELEE[sk("combat")], ranged_attack = HERO_RANGED[archery],
    defense = HERO_DEFENSE[sk("toughness")],
    speed = 6, move = 0, size = size or 3,
    shots = archery == 0 and 0 or (archery == 5 and 24 or 12),
    level = 0, alignment = "", xp = 0,
    magic_resistance = 0, spell_points = 0, spell_power = 0,
    abilities = {},
    shooter = archery > 0, normal_melee = true,
    morale = 0, luck = 0,
    effects = {},
  }
end

function stats.under(st, key) return st.effects[key] ~= nil end
local under = stats.under

-- Abilities that spells grant (exe 0x5edcc0; the five wards for the x 2/3 damage)
local GRANTED_BY = {
  chaos_protection = { "protection from chaos" }, death_protection = { "protection from death" },
  life_protection = { "protection from life" }, nature_protection = { "protection from nature" },
  order_protection = { "protection from order" },
  cold_resistance = { "cold resistance" }, fire_resistance = { "fire resistance" },
  first_strike = { "first strike", "snake strike" }, freeze = { "freeze" },
  long_range = { "precision" }, magic_immunity = { "anti magic" }, magic_mirror = { "magic mirror" },
  mechanical = { "clone", "illusionary ally" }, undead = { "animate dead", "death call" },
  flying = { "flight" },
}

-- An ability, its own or one a spell on it grants; Bind Flyer takes flight away
function stats.has(st, ability)
  if ability == "flying" and under(st, "bind flyer") then return false end
  if st.abilities[ability] then return true end
  local by = GRANTED_BY[ability]
  if by and next(st.effects) ~= nil then
    for i = 1, #by do
      if st.effects[by[i]] then return true end
    end
  end
  return false
end
local has = stats.has

-- Hit points per creature with spells (exe 0x5f57a0): Giant Strength, Health and Prayer each
-- add (hp + 2) >> 2 in that order, then Dragon Strength doubles
local HP_SPELLS = { "giant strength", "health boost", "prayer" }
function stats.hit_points(st)
  local hp = st.hp
  for i = 1, 3 do
    if under(st, HP_SPELLS[i]) then hp = hp + ((hp + 2) >> 2) end
  end
  if under(st, "dragon strength") then hp = hp * 2 end
  return hp
end

function stats.total_health(st)
  return st.count * stats.hit_points(st) - st.wounds
end

-- Take `damage` hit points, killing whole creatures from the front; returns the killed
function stats.take(st, damage)
  local hp = stats.hit_points(st)
  local d = damage + st.wounds
  local killed = math.min(st.count, d // hp)
  st.count = st.count - killed
  d = d - killed * hp
  st.wounds = st.count > 0 and d or 0
  return killed
end

-- Speed (exe 0x5eda70): Haste or Speed +3 (not together), the Speed Potion another +3; Aging
-- halves, then Slow, Fatigue or Bind Flyer halve once
function stats.speed(st)
  local s = st.speed
  if under(st, "haste") or under(st, "nature haste") then s = s + 3 end
  if under(st, "speed") then s = s + 3 end
  if under(st, "aging") then s = s // 2 end
  if under(st, "order slow") or under(st, "slow") or under(st, "bind flyer") then s = s // 2 end
  return s
end

-- Move in cells, a float (exe 0x5efba0): Haste or Speed +9 cells; halved as the speed
function stats.move_cells(st)
  local m = f32(st.move)
  if under(st, "haste") or under(st, "nature haste") then m = f32(m + 9) end
  if under(st, "aging") then m = f32(m / 2) end
  if under(st, "order slow") or under(st, "slow") or under(st, "bind flyer") then m = f32(m / 2) end
  return m
end

-- Morale (exe 0x5f0020): Sorrow -10 and Mirth +10 first; none for mechanical and undead;
-- else the army's morale + the side's loss penalty, Morale +5, Despair -10, clamped
function stats.morale(st, loss_penalty)
  if under(st, "sorrow") then return -10 end
  if under(st, "spiritual fervor") then return 10 end
  if has(st, "mechanical") or has(st, "undead") then return 0 end
  local m = st.morale + (loss_penalty or 0)
  if under(st, "morale") then m = m + 5 end
  if under(st, "despair") then m = m - 10 end
  return num.clamp(m, -10, 10)
end

-- Luck (exe 0x5eff50): Fortune +10, Misfortune -10, else the army's luck, Luck +5, clamped
function stats.luck(st)
  if under(st, "fortune") then return 10 end
  if under(st, "misfortune") then return -10 end
  return num.clamp(st.luck + (under(st, "luck") and 5 or 0), -10, 10)
end

-- Living: what Stun, Weakness, Poison, Aging and the mind spells work on
function stats.living(st)
  return not (has(st, "undead") or has(st, "mechanical") or has(st, "elemental"))
end

return stats
