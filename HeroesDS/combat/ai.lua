-- HeroesDS combat: a simple computer opponent (COMBAT.md 11, C3f).
--
-- Ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Battle.swift (autoAct,
-- berserkAct) and BattleSpells.swift (aiTargets, aiAffected, aiValue, aiSpell, aiBlowValue).
-- The exe's own AI was not traced there; this is homm4-mac's estimate in hit points.
--
-- ai.act(b) plays the current stack's turn and returns its events. The screen calls it for
-- the computer's side, and for any stack under Berserk (ai.must_act).

local grid = require("combat.grid")
local stats = require("combat.stats")
local damage = require("combat.damage")
local magic = require("combat.magic")
local casting = require("combat.casting")
local under, has = stats.under, stats.has
local flag = magic.flag

local ai = {}

-- A stack that cannot be given orders: it acts on its own
function ai.must_act(b, u)
  return under(u, "berserk")
end

-- How dangerous a stack is: count x average damage x attack (x 2, only compared)
local function threat(u)
  return u.count * (u.dmg_lo + u.dmg_hi) * u.attack
end

-- The highest of `list` by `f`; ties: the lowest id
local function best_by(list, f)
  local best, bv
  for _, v in ipairs(list) do
    local x = f(v)
    if bv == nil or x > bv or (x == bv and v.id < best.id) then best, bv = v, x end
  end
  return best
end

---------------------------------------------------------------------------------------------
-- Spells

local SHORT = { blind = true, confusion = true, stun = true, terror = true, frozen = true,
                ["summon stinkbug"] = true, hypnotize = true, ["short hypnotism"] = true }
local NO_HIT_NOW = { poison = true, plague = true, ["poison attack"] = true }

-- Every target the spell could be cast at now: { target, x, y }
local function targets_of(b, key, u)
  local aim = casting.aim(b, key)
  local out = {}
  if aim == "none" then return { {} } end
  if aim == "cell" then
    for _, v in ipairs(b.units) do
      if v.count > 0 then out[#out + 1] = { x = v.x + v.size // 2, y = v.y + v.size // 2 } end
    end
    return out
  end
  if aim == "unit" or aim == "unit_or_cell" or aim == "unit_and_point" then
    for _, v in ipairs(b.units) do
      if magic.can_target(b, key, u, v) then out[#out + 1] = { target = v.id } end
    end
  end
  return out
end

-- The stacks a cast would touch
local function affected(b, key, u, o)
  if key == "burning hands" and o.target then
    local t = b.units[o.target]
    local x, y = casting.sparks_position(b, u, t, nil, nil)
    if not x then return {} end
    local ox, oy = u.x, u.y
    u.x, u.y = x, y
    local fx, fy = grid.dir8(grid.delta2(u, t))
    local list = casting.sparks_targets(b, u, fx, fy)
    u.x, u.y = ox, oy
    return list
  end
  return casting.targets(b, key, u, o.target, o.x, o.y) or {}
end

-- What a spell is worth to the caster's side, in hit points
function ai.spell_value(b, key, u, o)
  local s = magic.spell(b, key)
  local effect = casting.MASS_OF[key] or key
  local p = magic.power(b, key, u)
  if flag(s, "summoning") and not flag(s, "bodies") then
    local cr = b.creatures and b.creatures[s.creature]
    if cr then return p * cr.hp end
  end
  local v = 0
  for _, t in ipairs(affected(b, key, u, o)) do
    local enemy = b:side_of(t) ~= b:side_of(u)
    local r = magic.resistance(b, t, key)
    if (s.type == "damage" and not NO_HIT_NOW[effect]) or effect == "hand of death" or effect == "banish" then
      local d = r >= 100 and 0 or (p * (100 - r) + 99) // 100
      if effect == "hand of death" then d = d * stats.hit_points(t) end
      d = math.min(d, stats.total_health(t))
      v = v + (enemy and d or -2 * d)
    elseif flag(s, "summoning") and flag(s, "bodies") then
      local cr = b.creatures and b.creatures[s.creature]
      if cr then v = v + math.min(p, magic.dead_count(t)) * cr.hp
      else v = v + math.min(p, magic.dead_count(t) * stats.hit_points(t)) end
    elseif s.type == "healing" or s.type == "resurrection" or flag(s, "bodies") then
      local lost = math.max(0, t.count_start - t.count) * stats.hit_points(t) + t.wounds
      v = v + (enemy and 0 or math.min(p, lost))
    elseif not under(t, effect) and t.count > 0 then
      local hp = stats.total_health(t) // (SHORT[effect] and 2 or 5)
      if enemy and flag(s, "enemies") then
        v = v + ((flag(s, "resisted") or flag(s, "resisted_if_enemy")) and hp * (100 - r) // 100 or hp)
      elseif not enemy and flag(s, "friends") then
        v = v + hp
      end
    end
  end
  return v
end

-- The best spell u can cast now: { spell, target, x, y, value } or nil
function ai.best_spell(b, u)
  local best
  for _, key in ipairs(casting.castable(b, u)) do
    for _, o in ipairs(targets_of(b, key, u)) do
      grid.tick()
      local v = ai.spell_value(b, key, u, o)
      if v > (best and best.value or 0) then
        best = { spell = key, target = o.target, x = o.x, y = o.y, value = v }
      end
    end
  end
  return best
end

-- What u's own blow or shot is worth now: its average damage on the enemy it would hit
function ai.blow_value(b, u, enemies)
  local ranged = b:can_shoot(u)
  local best = 0
  for _, t in ipairs(enemies) do
    local ok = ranged or next(b:attack_positions(u, t)) ~= nil
    if ok then
      local div = ranged and damage.range_divisor(b.field, u, t) or 1
      local lo, hi = damage.preview(u, t, { ranged = ranged }, div)
      best = math.max(best, math.min(stats.total_health(t), (lo + hi) // 2))
    end
  end
  return best
end

---------------------------------------------------------------------------------------------
-- Turns

local function cheapest_attack(b, u, t)
  local best, bc
  for k, c in pairs(b:attack_positions(u, t)) do
    if bc == nil or c < bc or (c == bc and k < best) then best, bc = k, c end
  end
  return best, bc
end

local function round_sqrt(n)
  local r = math.floor(math.sqrt(n))
  while r * r > n do r = r - 1 end
  while (r + 1) * (r + 1) <= n do r = r + 1 end
  if n - r * r > r then r = r + 1 end
  return r
end

-- A Berserk stack (exe 0x5740cc) never casts: it shoots the nearest stack of either side if it
-- can (distance between centres less both radii, ties at random), else attacks the one it
-- reaches cheapest (ties at random), else waits once, then defends
local function berserk(b, u)
  local cands = {}
  for _, v in ipairs(b.units) do if b:may_strike(u, v) then cands[#cands + 1] = v end end
  if b:can_shoot(u) and #cands > 0 then
    local function d(v)
      local dx = v.x * 16 + v.size * 8 - u.x * 16 - u.size * 8
      local dy = v.y * 16 + v.size * 8 - u.y * 16 - u.size * 8
      return (round_sqrt(dx * dx + dy * dy) - 8 * u.size - 8 * v.size + 8) >> 4
    end
    local m, ties = nil, {}
    for _, v in ipairs(cands) do
      local x = d(v)
      if m == nil or x < m then m = x; ties = { v } elseif x == m then ties[#ties + 1] = v end
    end
    local ev = b:act({ type = "shoot", target = ties[b.rng:next() % #ties + 1].id })
    if ev then return ev end
  end
  local m, ties = nil, {}
  for _, v in ipairs(cands) do
    local _, c = cheapest_attack(b, u, v)
    if c then
      if m == nil or c < m then m = c; ties = { v } elseif c == m then ties[#ties + 1] = v end
    end
  end
  if #ties > 0 then
    local ev = b:act({ type = "melee", target = ties[b.rng:next() % #ties + 1].id })
    if ev then return ev end
  end
  if not u.waited then
    local ev = b:act({ type = "wait" })
    if ev then return ev end
  end
  return b:act({ type = "defend" })
end

-- Play the current stack's turn: cast when the best spell is worth more than its blow;
-- shooters shoot the most dangerous enemy; others attack what they can reach (the most
-- dangerous), else walk toward the nearest enemy; else defend
function ai.act(b)
  local u = b:current()
  if b.finished or not u then return nil, "the battle is over" end
  if under(u, "berserk") then return berserk(b, u) end
  local enemies = {}
  for _, v in ipairs(b.units) do if b:may_strike(u, v) then enemies[#enemies + 1] = v end end
  if #enemies == 0 then return b:act({ type = "defend" }) end
  if u.caster then
    local c = ai.best_spell(b, u)
    if c and c.value > ai.blow_value(b, u, enemies) then
      local ev = b:act({ type = "cast", spell = c.spell, target = c.target, x = c.x, y = c.y })
      if ev then return ev end
    end
  end
  if b:can_shoot(u) then
    local t = best_by(enemies, threat)
    local ev = b:act({ type = "shoot", target = t.id })
    if ev then return ev end
  end
  local reach = {}
  for _, v in ipairs(enemies) do if cheapest_attack(b, u, v) then reach[#reach + 1] = v end end
  if #reach > 0 then
    local t = best_by(reach, threat)
    local ev = b:act({ type = "melee", target = t.id })
    if ev then return ev end
  end
  -- toward the nearest enemy: the reachable place whose centre is nearest it
  local nearest = best_by(enemies, function(v) return -grid.dist4(u, v) end)
  local best, bd
  local nx, ny = 2 * nearest.x + nearest.size, 2 * nearest.y + nearest.size
  for k in pairs(b:reachable(u)) do
    local x, y = grid.xy(k)
    local dx, dy = 2 * x + u.size - nx, 2 * y + u.size - ny
    local d = dx * dx + dy * dy
    if bd == nil or d < bd or (d == bd and k < best) then best, bd = k, d end
  end
  if best and best ~= grid.key(u.x, u.y) then
    local x, y = grid.xy(best)
    local ev = b:act({ type = "move", x = x, y = y })
    if ev then return ev end
  end
  return b:act({ type = "defend" })
end

-- Let the computer play while it is its turn (sides: { [0] = bool, [1] = bool } for the
-- computer's sides). Returns all the events, stopping when a human side has the turn.
function ai.run(b, sides, limit)
  local all = {}
  for _ = 1, limit or 1000 do
    local u = b:current()
    if b.finished or not u then break end
    if not (sides[b:side_of(u)] or ai.must_act(b, u)) then break end
    local ev = assert(ai.act(b))
    for _, e in ipairs(ev) do all[#all + 1] = e end
  end
  return all
end

return ai
