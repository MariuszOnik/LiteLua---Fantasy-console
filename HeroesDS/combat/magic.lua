-- HeroesDS combat: the core of spells shared by abilities and casting (MECHANICS.md 14).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): BattleSpells.swift
-- (canTarget, resistance, apply, remove, power, spellDamage, restore), with the heroes4.exe
-- addresses.
--
-- Spells come from spells.lua (make_rules.py), given to the battle as b.spells; they are
-- known by their key ("weakness"). A spell on a stack is st.effects[key] = { power, turns }.

local stats = require("combat.stats")
local under, has = stats.under, stats.has

local magic = {}

-- Spells that take others off when they land (exe add_spell 0x5f0220)
local OPPOSITE = {
  bless = { "curse" }, curse = { "bless" }, fortune = { "misfortune" }, misfortune = { "fortune" },
  haste = { "order slow", "slow" }, ["nature haste"] = { "order slow", "slow" },
  ["order slow"] = { "haste", "nature haste" }, slow = { "haste", "nature haste" },
  despair = { "spiritual fervor" }, sorrow = { "spiritual fervor" }, ["spiritual fervor"] = { "sorrow" },
  berserk = { "song of peace" }, ["song of peace"] = { "berserk" },
  ["sacred ground"] = { "animate dead", "death call", "raise skeletons", "raise ghost", "raise vampires" },
}
magic.OPPOSITE = OPPOSITE

-- Fixed lengths in the target's own turns (MECHANICS.md 14.6); the rest last the battle
local LENGTH = {
  confusion = 1, stun = 1, ["song of peace"] = 1, ["short hypnotism"] = 1, ["summon stinkbug"] = 1,
  quickness = 2, terror = 2, frozen = 2, blind = 3, cowardice = 3, hypnotize = 3, sanctuary = 6,
}
magic.LENGTH = LENGTH

-- The power skill of each school (MECHANICS.md 14.2)
magic.POWER_SKILL = { life = "spirit", order = "mind", death = "demonology", chaos = "pyromancy",
                      nature = "meditation" }

function magic.spell(b, key)
  local s = b.spells and b.spells[key]
  return s
end

local function flag(s, f) return s.flags and s.flags[f] == true end
magic.flag = flag

local RAISING = { ["raise ghost"] = true, ["raise skeletons"] = true, ["raise vampires"] = true,
                  ["animate dead"] = true, ["death call"] = true }
-- Cast on friends only (the Enemy flag is for the struck attacker)
local ON_FRIENDS = { ["holy retribution"] = true, fear = true, ["vampiric touch"] = true, ["pain mirror"] = true }

-- Creatures of a stack that died and could come back
function magic.dead_count(t)
  return math.max(0, t.count_start - (t.permanently_lost or 0) - t.count)
end

-- Resistance in percent of a stack to a spell (exe 0x40cac0): its own, then Magic
-- Resistance and a ward of the spell's school each take half of what is left
function magic.resistance(b, t, key, caster)
  if has(t, "spell_vulnerability") then return 0 end
  if caster and has(caster, "ignore_magic_resistance") then return 0 end
  if has(t, "magic_immunity") or under(t, "anti magic") then return 100 end
  local k = 100 - math.min(100, t.magic_resistance or 0)
  if under(t, "magic resistance") then k = k - k // 2 end
  local s = magic.spell(b, key)
  local school = s and s.school or ""
  local ward = (school == "life" and (has(t, "life_protection") or under(t, "protection from life")))
    or (school == "order" and under(t, "protection from order"))
    or (school == "death" and (has(t, "death_protection") or under(t, "protection from death")))
    or (school == "chaos" and (has(t, "chaos_protection") or under(t, "protection from chaos")))
    or (school == "nature" and under(t, "protection from nature"))
  if ward and not (caster and has(caster, "ignore_wards")) then k = k - k // 2 end
  return k > 0 and 100 - k or 100
end

-- Spell damage after resistance (Unholy Song on the target: a quarter more)
function magic.spell_damage(b, t, p, key, caster)
  local r = magic.resistance(b, t, key, caster)
  local d = r >= 100 and 0 or ((100 - r) * p + 99) // 100
  if under(t, "evil hour") then d = d + (d >> 2) end
  return d
end

-- Can this spell land on that stack (exe 0x5b37d0 / 0x5b3ca0)? any_side: an ability's spell,
-- which ignores the friend / enemy flags
function magic.can_target(b, key, u, t, any_side)
  local s = magic.spell(b, key)
  if not s then return false end
  if t.count <= 0 then
    if not flag(s, "bodies") or magic.dead_count(t) <= 0 then return false end
  end
  local enemy = b:hostile(t, u)
  if not any_side then
    if enemy and not flag(s, "enemies") then return false end
    if not enemy and not flag(s, "friends") then return false end
    if enemy then
      if under(u, "song of peace") and (flag(s, "curse") or flag(s, "damage")) then return false end
      if b:afraid(u, t) then return false end
    end
  end
  -- magic immunity, Anti-Magic and Sanctuary turn every spell away, friendly ones too
  if has(t, "magic_immunity") or under(t, "anti magic") or under(t, "sanctuary") then return false end
  local negate = flag(s, "mind") and has(u, "negate_mind_immunity")
  if not negate then
    if has(t, "undead") and not flag(s, "undead") then return false end
    if has(t, "mechanical") and not under(t, "clone") and not under(t, "illusionary ally")
        and not flag(s, "mechanical") then return false end
    if has(t, "elemental") and not flag(s, "elementals") then return false end
    if flag(s, "mind") and (has(t, "undead") or has(t, "mechanical") or has(t, "elemental")
        or has(t, "mind_immunity")) then return false end
  end
  -- raising needs dead creatures and no Necromancy Ward; Animate Dead the undead only
  if RAISING[key] then
    if magic.dead_count(t) == 0 or under(t, "sacred ground") then return false end
    if key == "animate dead" and not has(t, "undead") then return false end
  end
  if (key == "resurrection" or key == "rebirth") and magic.dead_count(t) == 0 and t.wounds == 0 then return false end
  if key == "divine intervention" and t.count <= 0 and not t.is_hero then return false end
  if not any_side and enemy and ON_FRIENDS[key] then return false end
  if key == "holy water" and not enemy and t.id ~= u.id then return false end
  if key == "celestial armor" and t.id ~= u.id then return false end
  if flag(s, "fire") and has(t, "fire_resistance") then return false end
  if flag(s, "cold") and has(t, "cold_resistance") then return false end
  if key == "blind" and has(t, "blind") then return false end
  if (key == "bless" or key == "curse") and t.dmg_lo == t.dmg_hi then return false end
  if key == "bind flyer" and not has(t, "flying") then return false end
  if key == "precision" and not t.shooter then return false end
  if (key == "holy word" or key == "divine retribution")
      and (t.is_hero or not (t.alignment == "death" or has(t, "undead"))) then return false end
  if (key == "prayer" or key == "evil hour") and t.alignment ~= "life" then return false end
  if key == "life drain" and (t.id == u.id or not (t.alignment == "life" or t.alignment == "nature")) then return false end
  if key == "plague" and t.alignment == "death" then return false end
  if key == "banish" and (not t.summoned
      or magic.spell_damage(b, t, magic.power(b, key, u), key, u) < stats.hit_points(t)) then return false end
  return true
end

-- Spells that take something off (exe 0x5f03d8 / 0x5f02fc / 0x61ca30): kind "all", "good"
-- (blessings and summons) or "bad" (curses); never those that cannot be dispelled. A
-- summoned stack whose summon goes vanishes.
function magic.dispel(b, t, kind)
  local keys = {}
  for key in pairs(t.effects) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local s = magic.spell(b, key)
    if s and not flag(s, "no_dispel") then
      local ok = kind == "all"
        or (kind == "good" and (flag(s, "blessing") or flag(s, "summoning")))
        or (kind == "bad" and flag(s, "curse"))
      if ok then
        magic.remove(b, t, key)
        if t.summoned and t.summoned_by == key and t.count > 0 then
          t.permanently_lost, t.count, t.wounds = t.count_start, 0, 0
          b:emit({ t = "die", stack = t.id }); b:emit({ t = "bodies_gone", stack = t.id })
        end
      end
    end
  end
end

-- A spell taken off a stack (exe 0x5f23d0)
function magic.remove(b, t, key)
  if t.effects[key] == nil then return end
  t.effects[key] = nil
  -- a hit point spell gone leaves the top creature alive
  if t.count > 0 and t.wounds >= stats.hit_points(t) then t.wounds = stats.hit_points(t) - 1 end
  if key == "martyr" then t.martyr = nil end
  if key == "binding" then t.bound_by = nil end
  if key == "hypnotize" or key == "short hypnotism" then t.hypnotized = false end
  if key == "poison" then t.poison = 0 end
  if key == "plague" then t.plague = 0 end
  if key == "regeneration" then t.regeneration = 0 end
end

-- A lasting spell put on a stack: its opposites go; a fixed length gets a turn more when it
-- lands on the stack whose turn it is
function magic.apply(b, t, key, power)
  local opp = OPPOSITE[key]
  if opp then
    for i = 1, #opp do magic.remove(b, t, opp[i]) end
  end
  if key == "hypnotize" or key == "short hypnotism" then
    if t.hypnotized or under(t, "hypnotize") or under(t, "short hypnotism") then
      magic.remove(b, t, "hypnotize"); magic.remove(b, t, "short hypnotism")
      return
    end
    t.hypnotized = true
  end
  if key == "guardian angel" then   -- lives, at most its count
    t.effects[key] = { power = math.min(power or 0, t.count) }
    return
  end
  if key == "hand of death" then   -- exactly min(power, count) creatures die
    local n = math.min(power or 0, t.count)
    t.count = t.count - n
    if t.count == 0 then t.wounds = 0 end
    if t.side == 1 then b.experience = b.experience + n * (t.xp or 0) end
    b:emit({ t = "spell", stack = t.id, spell = key, damage = 0, killed = n, left = t.count })
    if t.count <= 0 then b:emit({ t = "die", stack = t.id }) end
    return
  end
  if key == "mana" then   -- spell points for the target
    if t.caster then t.spell_points = (t.spell_points or 0) + (power or 0) end
    return
  end
  local n = LENGTH[key]
  local cur = b:current()
  t.effects[key] = { power = power or 0, turns = n and (n + ((cur and cur.id == t.id) and 1 or 0)) or nil }
end

-- An ability's spell put on a struck stack (exe 0x575f70): only if it can land, resisted when
-- the spell is resisted. Returns true when it took hold.
function magic.on_hit(b, key, t, a)
  if not magic.can_target(b, key, a, t, true) then return false end
  local s = magic.spell(b, key)
  if flag(s, "resisted") or (flag(s, "resisted_if_enemy") and b:side_of(a) ~= b:side_of(t)) then
    local r = magic.resistance(b, t, key)
    if r >= 100 or b.rng:next() % 100 < r then
      b:emit({ t = "resisted", stack = t.id, spell = key })
      return false
    end
  end
  magic.apply(b, t, key, 0)
  b:emit({ t = "effect", stack = t.id, effect = key })
  return true
end

-- Hit points back to a stack: the top creature's wounds first, then dead creatures, never
-- more than it started with. Returns the hit points restored.
function magic.restore(b, t, hp)
  local h = math.max(1, stats.hit_points(t))
  local amt = math.max(0, math.min(hp, t.wounds + h * magic.dead_count(t)))
  if amt <= 0 then return 0 end
  local was_dead = t.count <= 0
  local total = stats.total_health(t) + amt
  t.count = (total + h - 1) // h
  t.wounds = t.count * h - total
  if was_dead then t.death_handled = false end
  return amt
end

-- A creature's spell power (exe 0x865200): level 0; damage, summoning and Resurrection
-- x Spell Power x count / 100; Rebirth x the starting count
function magic.creature_power(b, key, u)
  local s = magic.spell(b, key)
  if not s then return 0 end
  local pct = 100
  if flag(s, "damage") or flag(s, "summoning") or key == "resurrection" then
    pct = (u.spell_power or 0) * pct * u.count // 100
  elseif key == "rebirth" then
    pct = pct * u.count_start
  end
  return magic.scale(b, s, key, pct, 0)
end

-- (base + increase x level) x pct / 100; Guardian Angel and Hand of Death (10 + level) x pct
-- / 1000; a summons divides by the creature's experience
function magic.scale(b, s, key, pct, level)
  local p = s.base * pct // 100
  if (s.increase or 0) ~= 0 then p = (s.base + s.increase * level) * pct // 100 end
  if key == "guardian angel" or key == "hand of death" then p = (10 + level) * pct // 1000 end
  if flag(s, "summoning") and not flag(s, "bodies") and s.creature and s.creature ~= "" then
    local cr = b.creatures and b.creatures[s.creature]
    if cr and (cr.xp or 0) > 0 then p = math.max(1, p // cr.xp) end
  end
  return p
end

-- A spell's power for its caster (exe 0x865200): a hero (b.caster set on the stack) casts at
-- its level, pct = 100 + 20 per level of the school's power skill (+ Sorcery 20 a level on
-- damage spells) + its items; a creature at level 0 (creature_power)
function magic.power(b, key, u)
  local c = u.caster
  if not c or c.creature then return magic.creature_power(b, key, u) end
  local s = magic.spell(b, key)
  if not s then return 0 end
  local pct = 100 + 20 * (c.skills[magic.POWER_SKILL[s.school] or ""] or 0) + (c.power_bonus[key] or 0)
  if flag(s, "damage") then pct = pct + 20 * (c.skills.sorcery or 0) end
  return magic.scale(b, s, key, pct, c.level)
end

return magic
