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
  if flag(s, "fire") and has(t, "fire_resistance") then return false end
  if flag(s, "cold") and has(t, "cold_resistance") then return false end
  if key == "blind" and has(t, "blind") then return false end
  if (key == "bless" or key == "curse") and t.dmg_lo == t.dmg_hi then return false end
  if key == "bind flyer" and not has(t, "flying") then return false end
  if key == "precision" and not t.shooter then return false end
  return true
end

-- A spell taken off a stack (exe 0x5f23d0)
function magic.remove(b, t, key)
  t.effects[key] = nil
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
-- x Spell Power x count / 100; Rebirth x the starting count. (Heroes: C3d / C3e.)
function magic.creature_power(b, key, u)
  local s = magic.spell(b, key)
  if not s then return 0 end
  local pct = 100
  if flag(s, "damage") or flag(s, "summoning") or key == "resurrection" then
    pct = (u.spell_power or 0) * pct * u.count // 100
  elseif key == "rebirth" then
    pct = pct * u.count_start
  end
  return s.base * pct // 100
end

return magic
