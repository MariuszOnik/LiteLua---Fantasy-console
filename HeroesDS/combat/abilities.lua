-- HeroesDS combat: creature abilities as battle hooks (MECHANICS.md 12).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Battle.swift
-- (extraTargets, aftermath 0x553440, startOfTurn 0x567ef0, handleDeaths 0x5f53c0, fears),
-- with the heroes4.exe addresses. Random rolls come in the exe's order.
--
-- abilities.install(battle) plugs them in. Abilities that only change stats are in
-- stats / damage; the ones only the game's text describes (mana_leech, random_curse,
-- sea_bonus) are not here (MECHANICS.md 12.10).

local num = require("combat.num")
local grid = require("combat.grid")
local stats = require("combat.stats")
local magic = require("combat.magic")
local f32 = num.f32
local under, has, living = stats.under, stats.has, stats.living

local abilities = {}

local function others(b, a, t)
  local out = {}
  for _, u in ipairs(b.units) do
    if u.count > 0 and u.id ~= a.id and u.id ~= t.id then out[#out + 1] = u end
  end
  return out
end

-- The other stacks a blow also strikes: Multiple Attack every adjacent enemy, 3-Headed the
-- enemies beside both, Breath the stack right behind the target (friend or foe), an area
-- shot everything around the target
function abilities.extra_targets(b, a, t, ranged)
  local list, out = others(b, a, t), {}
  if ranged then
    if not (has(a, "area_effect") or has(a, "large_area_effect")) then return out end
    for _, u in ipairs(list) do if grid.adjacent(u, t) then out[#out + 1] = u end end
    return out
  end
  if has(a, "hydra_strike") then
    for _, u in ipairs(list) do
      if b:side_of(u) ~= b:side_of(a) and grid.adjacent(a, u) then out[#out + 1] = u end
    end
    return out
  end
  if has(a, "3_headed_attack") then
    for _, u in ipairs(list) do
      if b:side_of(u) ~= b:side_of(a) and grid.adjacent(a, u) and grid.adjacent(t, u) then
        out[#out + 1] = u
      end
    end
    table.sort(out, function(p, q)
      local dp, dq = grid.dist4(p, t), grid.dist4(q, t)
      if dp ~= dq then return dp < dq end
      return p.id < q.id
    end)
    while #out > 2 do out[#out] = nil end
    return out
  end
  if has(a, "breath_attack") or has(a, "arc_breath_attack") then
    -- the point size / 2 + 1.5 cells beyond the target's centre, on the line from the attacker
    local ax, ay = grid.centre(a)
    local tx, ty = grid.centre(t)
    local dx, dy = f32(tx - ax), f32(ty - ay)
    local len = math.max(f32(0.001), f32(math.sqrt(f32(f32(dx * dx) + f32(dy * dy)))))
    local reach = f32(t.size / 2 + 1.5)
    local px = f32(tx + f32(f32(dx / len) * reach))
    local py = f32(ty + f32(f32(dy / len) * reach))
    for _, u in ipairs(list) do
      if not has(u, "fire_resistance")
          and px >= u.x - 0.5 and px <= u.x + u.size + 0.5
          and py >= u.y - 0.5 and py <= u.y + u.size + 0.5 then
        out[#out + 1] = u
      end
    end
  end
  return out
end

local function power_of(u, key)
  local e = u.effects[key]
  return e and e.power or 0
end

-- The abilities that act after a blow lands (exe 0x553440), in the exe's order
function abilities.aftermath(b, a, t, ranged, dmg, health_before)
  -- Retribution on the target: its power on the melee attacker; Fire Aura on the attacker:
  -- its power as fire damage on the target, after resistance
  if not ranged and under(t, "holy retribution") and a.count > 0
      and magic.can_target(b, "holy retribution", t, a, true) then
    b:effect(a, "holy retribution", math.min(stats.total_health(a),
      magic.spell_damage(b, a, power_of(t, "holy retribution"), "holy retribution")))
  end
  if not ranged and under(a, "firebreathing") and t.count > 0
      and magic.can_target(b, "fire_aura_effect", a, t, true) then
    b:effect(t, "firebreathing", math.min(stats.total_health(t),
      magic.spell_damage(b, t, power_of(a, "firebreathing"), "fire_aura_effect")))
  end
  -- Poison: a quarter of the damage dealt (halved by Death Ward), Poison Attack its power
  -- (halved too); the larger dose stays
  local dose = 0
  if has(a, "poison") then dose = dose + ((has(t, "death_protection") and dmg // 2 or dmg) >> 2) end
  if under(a, "poison attack") then
    local p = power_of(a, "poison attack")
    dose = dose + (has(t, "death_protection") and p // 2 or p)
  end
  if dose > 0 and t.count > 0 and magic.can_target(b, "poison", a, t, true) then
    t.poison = math.max(t.poison or 0, dose)
    t.effects.poison = t.effects.poison or { power = 0 }
    b:effect(t, "poison")
  end
  -- Fire Shield: a quarter of a melee blow burns the attacker, half of that when the
  -- shield's owner has Chaos Ward (as the exe has it)
  if not ranged and has(t, "fire_shield") and a.count > 0 and magic.can_target(b, "fire shield", t, a, true) then
    local burn = (dmg + 3) >> 2
    if has(t, "chaos_protection") then burn = (burn + 1) >> 1 end
    if burn > 0 then b:effect(a, "fire shield", math.min(burn, stats.total_health(a))) end
  end
  if t.count > 0 then
    if has(a, "weakness") and living(t) and not under(t, "weakness") then magic.on_hit(b, "weakness", t, a) end
    -- Stun: damage as a percentage of the health it had, less 5; no resistance roll
    if has(a, ranged and "ranged_stun" or "stunning") and living(t) then
      local chance = dmg * 100 // math.max(1, health_before) - 5
      if b.rng:next() % 100 < chance then magic.apply(b, t, "stun", 0); b:effect(t, "stun") end
    end
  end
  if not ranged and t.count > 0 then
    if has(a, "aging") and not under(t, "aging") then magic.on_hit(b, "aging", t, a) end
    if has(a, "blinding") and not has(t, "blind") and b.rng:next() % 100 < 30 then magic.on_hit(b, "blind", t, a) end
    if has(a, "curse") and not under(t, "curse") then magic.on_hit(b, "curse", t, a) end
    -- Devouring: each attacker has a 1 in 10 chance to swallow a creature, at most a tenth
    if has(a, "devouring") then
      local eaten = 0
      for _ = 1, math.min(a.count, 100) do
        if b.rng:next() % 10 == 0 then eaten = eaten + 1 end
      end
      if a.count > 100 then eaten = eaten * a.count // 100 end
      eaten = math.min(eaten, (a.count + 9) // 10, t.count)
      if eaten > 0 then
        b:effect(t, "devour", eaten * stats.hit_points(t) - (t.count == eaten and t.wounds or 0))
      end
    end
  end
  if not ranged and t.count > 0 then
    -- Hypnotize: 30%, Charm for a turn; on a stack already hypnotized it frees it
    if has(a, "hypnotize") and b.rng:next() % 10 < 3 and magic.can_target(b, "short hypnotism", a, t, true) then
      if under(t, "hypnotize") or under(t, "short hypnotism") then
        magic.remove(b, t, "hypnotize"); magic.remove(b, t, "short hypnotism")
      else
        magic.apply(b, t, "short hypnotism", 0)
        b:effect(t, "short hypnotism")
      end
    end
    if has(a, "binding") and not has(t, "insubstantial") and t.bound_by == nil then
      t.bound_by = a.id
      t.effects.binding = { power = 0 }
      b:effect(t, "binding")
    end
    -- Lightning: 30 damage per attacking creature, as the spell
    if has(a, "lightning") and magic.can_target(b, "lightning", a, t, true) then
      b:effect(t, "lightning", math.min(stats.total_health(t), magic.spell_damage(b, t, 30 * a.count, "lightning")))
    end
    -- Freeze: where Frozen can land, 30%, then the resistance roll
    if t.count > 0 and has(a, "freeze") and magic.can_target(b, "frozen", a, t, true)
        and b.rng:next() % 100 < 30 then
      magic.on_hit(b, "frozen", t, a)
    end
  end
  -- Life Draining and Vampiric Touch: half the damage (rounded up), halved again by Death
  -- Ward, from a living target, bringing back the attacker's dead up to its starting count
  if not ranged and a.count > 0 and (has(a, "vampire") or under(a, "vampiric touch")) and living(t)
      and (a.wounds > 0 or a.count < a.count_start) then
    local drain = (dmg + 1) >> 1
    if has(t, "death_protection") then drain = (drain + 1) >> 1 end
    if magic.restore(b, a, drain) > 0 then b:emit({ t = "effect", stack = a.id, effect = "vampirism", left = a.count }) end
  end
end

-- The start of a stack's turn (exe 0x567ef0): Regeneration heals the top creature (the
-- ability 50, a hero 20 + 2 x level; else the spell's power), then Poison and Plague
function abilities.start_of_turn(b, u)
  local heal = u.regeneration or 0
  if has(u, "regeneration") then heal = u.is_hero and 20 + 2 * (u.level_hero or 1) or 50 end
  if heal > 0 and u.wounds > 0 then
    local h = math.min(heal, u.wounds)
    u.wounds = u.wounds - h
    b:emit({ t = "heal", stack = u.id, spell = "regeneration", amount = h, left = u.count })
  end
  for _, kind in ipairs({ "poison", "plague" }) do
    local dmg = u[kind] or 0
    if dmg > 0 and u.count > 0 then
      b:effect(u, kind, math.min(dmg, stats.total_health(u)))
    end
  end
end

-- Aura of Fear on the attacker, or its Panic: no strike back unless the fear cannot touch
-- the target or it has Death Ward (exe 0x5f2810)
function abilities.fears(b, t, a)
  if under(a, "fear") and magic.can_target(b, "fear", a, t, true) and not has(t, "death_protection") then
    return true
  end
  if has(a, "panic") and magic.can_target(b, "panic", a, t, true) and not has(t, "death_protection") then
    return true
  end
  return false
end

-- Spells that stay on a dead stack: what summoned it, Guardian Angel, Necromancy Ward
local function keeps(b, key)
  if key == "guardian angel" or key == "sacred ground" then return true end
  local s = magic.spell(b, key)
  return s ~= nil and s.flags ~= nil and s.flags.summoning == true
end

-- A stack wiped out (exe 0x5f53c0): its spells go; then a Phoenix's Rebirth brings back
-- 55 x its starting count hit points, if it has the spell points
function abilities.on_death(b, u)
  local gone = {}
  for key in pairs(u.effects) do if not keeps(b, key) then gone[#gone + 1] = key end end
  table.sort(gone)
  for _, key in ipairs(gone) do u.effects[key] = nil end
  u.poison, u.plague, u.regeneration = 0, 0, 0
  if under(u, "clone") or under(u, "illusionary ally") or magic.dead_count(u) <= 0 then return end
  local s = magic.spell(b, "rebirth")
  if has(u, "rebirth") and s and (u.spell_points or 0) >= s.cost then
    u.spell_points = u.spell_points - s.cost
    b:resurrect(u, magic.creature_power(b, "rebirth", u), "rebirth")
  end
end

-- Stone Gaze in the blow itself (exe 0x5ee990): 250/100/50/20 thousandths of a target of
-- level 1/2/3/4 per attacking creature turn to stone, once that makes half a creature.
-- Returns the extra damage (0 when none).
function abilities.stone_gaze(b, a, t)
  if not has(a, "stone_gaze") or not living(t) or has(t, "blind") or has(t, "magic_immunity") then return 0 end
  local per = ({ 250, 100, 50, 20 })[math.min(3, math.max(0, (t.level or 0) - 1)) + 1]
  if per * a.count < 500 then return 0 end
  return (stats.hit_points(t) * per * a.count + 500) // 1000
end

function abilities.install(battle)
  battle.hooks.extra_targets = abilities.extra_targets
  battle.hooks.aftermath = abilities.aftermath
  battle.hooks.start_of_turn = abilities.start_of_turn
  battle.hooks.fears = abilities.fears
  battle.hooks.on_death = abilities.on_death
  battle.hooks.stone_gaze = abilities.stone_gaze
end

return abilities
