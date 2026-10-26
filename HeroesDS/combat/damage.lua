-- HeroesDS combat: damage of one blow (MECHANICS.md 6, 13.2).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Combat.swift
-- (QuickCombat.damage, spellDamage) and Battle.swift (rangeDivisor, luckyDamage), with the
-- heroes4.exe addresses. The attack / defense chain is in 32-bit floats as in the original.

local num = require("combat.num")
local grid = require("combat.grid")
local stats = require("combat.stats")
local f32 = num.f32
local under, has = stats.under, stats.has

local damage = {}

-- Decision H7: a hero's Melee / Archery divides the natural defense of enemy creatures
-- (only the game's text says so). Set to false to play as homm4-mac does.
damage.hero_divides_defense = true
-- Divisor of the target's defense x 100 by skill level 1..5 (MECHANICS.md 13.2)
local MELEE_DIV = { 150, 200, 300, 400, 400 }
local ARCHERY_DIV = { 100, 150, 200, 200, 200 }

-- Damage range per creature with spells (exe 0x5edfc0 / 0x5ee110 / 0x5ee020): Bless rolls
-- the maximum, Curse the minimum; Dragon Strength doubles, Strength and Giant Strength add
-- a quarter (rounded up for the maximum)
function damage.range(st)
  local lo = under(st, "bless") and st.dmg_hi or st.dmg_lo
  local hi = under(st, "curse") and st.dmg_lo or st.dmg_hi
  if under(st, "curse") then lo = st.dmg_lo end
  local function adj(d, is_max)
    if under(st, "dragon strength") then d = d * 2 end
    if under(st, "strength") then d = d + (is_max and (d + 3) // 4 or d // 4) end
    if under(st, "giant strength") then d = d + (is_max and (d + 3) // 4 or d // 4) end
    return d
  end
  return adj(lo, false), adj(hi, true)
end

-- The rolled base damage of a stack: one roll per creature, a stack of ten or more rolls ten
-- times and scales the sum by count / 10
function damage.roll_base(st, rng)
  local lo, hi = damage.range(st)
  local sum = 0
  if st.count >= 10 then
    for _ = 1, 10 do sum = sum + rng:roll(lo, hi) end
    return sum * st.count // 10
  end
  for _ = 1, st.count do sum = sum + rng:roll(lo, hi) end
  return sum
end

-- The target's defense before spells, divided by an attacking hero's Melee / Archery (H7)
local function natural_defense(a, b, ranged)
  local d = ranged and b.ranged_defense or b.defense   -- heroes: items may differ by kind
  if a.is_hero and not b.is_hero and damage.hero_divides_defense and d > 10 then
    local lvl = a.skills[ranged and "archery" or "combat"] or 0
    local div = lvl > 0 and (ranged and ARCHERY_DIV or MELEE_DIV)[math.min(lvl, 5)] or 100
    if div > 100 then d = math.max(10, d * 100 // div) end
  end
  return d
end

local WARD = { life = "life_protection", death = "death_protection", chaos = "chaos_protection",
               order = "order_protection", nature = "nature_protection" }

-- Damage of a hitting b with an already rolled base (exe 0x5ee380).
-- opts: ranged, moved (whole cells walked this turn, for Charge), on_quicksand (attacker),
-- quick (auto-resolve: Block takes 30% off instead of a roll)
function damage.blow(a, b, base, opts)
  local ranged = opts.ranged
  local points = (opts.moved or 0) * 100
  if not ranged and has(a, "charging") and points > 500 then
    base = base * (points * 10 // 350 + 85) // 100
  end
  if b.level == 4 and (has(a, "giantslayer") or has(a, ranged and "ranged_giantslayer" or "melee_giantslayer")) then
    base = base * 2
  end
  if b.level == 4 and under(a, "slayer") then base = base * 3 // 2 end

  -- attack: a shooter's melee is halved without Normal Melee; spells on the attacker (0x5ee170)
  local attack = f32(ranged and (a.ranged_attack or a.attack) or a.attack)
  if not ranged and a.shooter and not a.normal_melee then attack = f32(attack * 0.5) end
  if under(a, "weakness") then attack = f32(attack * 0.75) end
  if under(a, "aging") then attack = f32(attack * 0.75) end
  if under(a, "binding") then attack = f32(attack * 0.5) end
  if not ranged and under(a, "bloodlust") then attack = f32(attack * 1.25) end
  if not ranged and opts.on_quicksand then attack = f32(attack * 0.75) end
  if ranged and under(a, "precision") then attack = f32(attack * 1.25) end
  if under(a, "prayer") then attack = f32(attack * 1.25) end
  if under(a, "evil hour") then attack = f32(attack * num.K08) end
  if under(a, "choking gas") then attack = f32(attack * num.K085) end

  -- defense: doubled when defending; spells on the target (0x5f1ed0)
  local defense = f32(math.max(1, natural_defense(a, b, ranged)) * (b.defending and 2 or 1))
  if ranged and under(b, "blur") then defense = f32(defense * 1.5) end
  if b.defending and under(b, "divine protection") then defense = f32(defense * 1.5) end
  if under(b, "holy armor") then defense = f32(defense * 1.25) end
  if under(b, "stoneskin") then defense = f32(defense * 1.25) end
  if under(b, "acid") then defense = f32(defense * num.K08) end
  if under(b, "ray of suffering") then defense = f32(defense * num.K08) end
  if under(b, "evil hour") then defense = f32(defense * num.K08) end
  if under(b, "choking gas") then defense = f32(defense * num.K085) end
  if has(b, "insubstantial") then defense = f32(defense * 2) end
  if ranged and has(b, "skeletal") then defense = f32(defense * 2) end
  if under(b, "aging") then defense = f32(defense * num.K08) end

  local ratio = num.clamp(f32(attack / defense), num.K05, 20)   -- exe 0x650e30
  local d = num.round(f32(base * ratio))
  local ward = WARD[a.alignment]
  if ward and has(b, ward) then d = d * 100 // 150 end
  if (has(a, "fire_attack") or has(a, "breath_attack") or has(a, "arc_breath_attack")
      or (ranged and has(a, "large_area_effect"))) and has(b, "fire_resistance") then
    d = d >> 1
  end
  if has(a, "cold_attack") and has(b, "cold_resistance") then d = d >> 1 end
  d = math.max(1, d)
  if opts.quick and has(b, "block") then d = (d * 7 + 5) // 10 end
  return math.max(1, d)
end

-- The damage range shown before an attack (min and max base, no luck, no block roll)
function damage.preview(a, b, opts, divisor)
  local lo, hi = damage.range(a)
  local dmin = damage.blow(a, b, lo * a.count, opts)
  local dmax = damage.blow(a, b, hi * a.count, opts)
  divisor = divisor or 1
  return math.max(1, dmin // divisor), math.max(1, dmax // divisor)
end

-- The ranged damage divisor (exe 0x650dc0): Long Range none; Short Range /2 from 20 cells
-- and /4 from 40; others /2 from 40 cells; doubled when an obstacle or smoke is in the way,
-- unless the shooter has No Obstacle Penalty (siege_machine). The distance is truncated to
-- whole cells: d >= n <=> 4 d^2 >= 4 n^2 in doubled coordinates.
function damage.range_divisor(field, a, b)
  local d4 = grid.dist4(a, b)
  local div
  if has(a, "long_range") then div = 1
  elseif has(a, "short_range") then div = d4 >= 6400 and 4 or (d4 >= 1600 and 2 or 1)
  else div = d4 >= 6400 and 2 or 1 end
  if not has(a, "siege_machine") then
    local ax, ay = grid.centre(a)
    local bx, by = grid.centre(b)
    if field:obstructed(ax, ay, bx, by)
        or (next(field.smoke) ~= nil and grid.crosses(field.smoke, ax, ay, bx, by)) then
      div = div * 2
    end
  end
  return div
end

-- The luck of the stack struck, rolled when a blow lands (exe 0x5f2c50): good luck
-- (roll < luck) leaves two thirds, bad luck (roll < -luck) adds half.
-- Returns the damage and true / false for good / bad luck (nil: none).
function damage.lucky(rng, luck, dmg)
  if luck == 0 then return dmg end
  local r = rng:next() % 10
  if r < luck then return math.max(1, 2 * dmg // 3), true end
  if r < -luck then return dmg + (dmg >> 1), false end
  return dmg
end

return damage
