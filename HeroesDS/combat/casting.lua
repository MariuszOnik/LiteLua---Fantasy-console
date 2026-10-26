-- HeroesDS combat: casting spells in battle (MECHANICS.md 14).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): BattleSpells.swift
-- (castable, cost, aim, castTargets, areaMembers, cast, summon, raise, phantom, freeSpot,
-- teleport, displacement, quicksand, rock growth, sparks), with the heroes4.exe addresses.
--
-- casting.install(battle) adds the "cast" command: { type = "cast", spell = key, target = id,
-- x, y (a cell: area spells, Teleport's destination, the pointer of Sparks / Displacement),
-- second = id (Sacrifice, Martyr) }.

local num = require("combat.num")
local grid = require("combat.grid")
local stats = require("combat.stats")
local magic = require("combat.magic")
local f32 = num.f32
local under, has = stats.under, stats.has
local flag = magic.flag

local casting = {}

-- Mass spell -> the single spell it casts on every valid target (exe 0x98bf08)
casting.MASS_OF = {
  bloodfrenzy = "bloodlust", ["divine aura"] = "holy armor", ["divine retribution"] = "holy word",
  ["greater forgetfulness"] = "forgetfulness", ["mass bless"] = "bless", mass_blur = "blur",
  ["mass cancellation"] = "cancellation", ["mass curse"] = "curse", ["mass dispel"] = "dispel",
  ["mass exorcism"] = "exorcism", ["mass first strike"] = "first strike", ["mass fortune"] = "fortune",
  ["mass haste"] = "nature haste", ["mass healing"] = "heal", ["mass misfortune"] = "misfortune",
  ["mass precision"] = "precision", ["mass protection from chaos"] = "protection from chaos",
  ["mass protection from death"] = "protection from death",
  ["mass protection from nature"] = "protection from nature",
  ["mass protection from order"] = "protection from order", ["mass slayer"] = "slayer",
  ["mass slow"] = "order slow", ["mass snake strike"] = "snake strike", ["mass sorrow"] = "sorrow",
  ["mass spiritual fervor"] = "spiritual fervor", ["mass weakness"] = "weakness",
}
-- Mass spells of their own: every stack they can affect
local MASS_ONLY = { ["divine protection"] = true, ["evil hour"] = true, ["life drain"] = true,
  ["mana flare"] = true, plague = true, prayer = true, ["sacred ground"] = true, sanctuary = true,
  ["steal all enchantments"] = true, ["divine retribution"] = true }
-- Combat spells only abilities, items or other spells apply
local NO_FACTORY = { binding = true, ["cold resistance"] = true, ["fire shield"] = true, panic = true,
  ["protection from life"] = true, stone_gaze = true, robe_of_the_guardian = true,
  sacrifice_client = true, rebirth = true }
-- Area radius in world units, 16 a cell (exe 0x718870)
local AREA = { fireball = 64, ["kreegan fire"] = 64, ["cloud of confusion"] = 64, despair = 64,
               ["choking gas"] = 64, inferno = 112 }
local AIM_CELL = { fireball = true, inferno = true, ["kreegan fire"] = true, ["cloud of confusion"] = true,
  despair = true, ["choking gas"] = true, smoke = true, quicksand = true, ["rock growth"] = true }
-- The effect a spell leaves (exe 0x865580 and the clouds)
local REMAP = { ["cloud of confusion"] = "confusion", luck = "fortune", morale = "spiritual fervor",
                immortality = "guardian angel" }
-- Damage (or healing) kept and dealt at the start of each of the target's turns
local LASTING = { plague = true, poison = true, regeneration = true, ["poison attack"] = true }
local DISPEL = { dispel = "all", ["mass dispel"] = "all", ["anti magic"] = "all",
  cancellation = "good", ["mass cancellation"] = "good", exorcism = "bad", ["mass exorcism"] = "bad" }
local CURES = { heal = true, ["mass healing"] = true, ["simple healing"] = true }

---------------------------------------------------------------------------------------------
-- Casters

-- Creature casters (cast_by in spells.lua): their spells in the exe's order (by id)
function casting.prepare(b)
  local by = {}
  for key, s in pairs(b.spells) do
    for _, c in ipairs(s.cast_by or {}) do
      by[c] = by[c] or {}
      by[c][#by[c] + 1] = key
    end
  end
  for _, list in pairs(by) do
    table.sort(list, function(p, q) return b.spells[p].id < b.spells[q].id end)
  end
  b.creature_spells = by
  for _, u in ipairs(b.units) do casting.creature_caster(b, u) end
end

function casting.creature_caster(b, u)
  if u.is_hero or u.caster then return end
  local list = b.creature_spells and b.creature_spells[u.kind]
  if list then
    u.caster = { creature = true, level = 0, skills = {}, spells = list, free = {}, known = {},
                 power_bonus = {}, cost_items = {} }
  end
end

local function contains(list, key)
  if list == "all" then return true end
  if type(list) ~= "table" then return false end
  for _, x in ipairs(list) do if x == key then return true end end
  return false
end

-- A cast's cost (exe 0x5ebe10, items 0x725300): the book's cost with the items' percent and
-- flat changes (a scroll halves its own spell); + the spell's cost under Power Drain, again
-- under Magic Leech, - 2 under Mana Flare; at least 1
function casting.cost(b, key, u)
  local s = magic.spell(b, key)
  local c = u.caster
  if not s or not c then return 0 end
  local k = s.cost
  if not c.creature then
    local pct, flat = 100, 0
    for _, e in ipairs(c.cost_items) do
      if contains(e.spells, key) then flat = flat + (e.amount or 0); pct = pct * (100 + (e.cost or 0)) // 100 end
    end
    k = math.max(1, s.cost * pct // 100 + flat)
    if c.free[key] and not c.known[key] then k = math.max(1, k // 2) end
  end
  if under(u, "power drain") then k = k + s.cost end
  if under(u, "magic leech") then k = k + s.cost end
  if under(u, "mana flare") then k = k - 2 end
  return math.max(1, k)
end

-- Spells u can cast now: known, a combat spell, affordable, the school skill high enough
function casting.castable(b, u)
  local c, out = u.caster, {}
  if not c or u.count <= 0 then return out end
  for _, key in ipairs(c.spells) do
    local s = magic.spell(b, key)
    if s and flag(s, "combat") and not NO_FACTORY[key]
        and casting.cost(b, key, u) <= (u.spell_points or 0)
        and (c.creature or c.free[key] or (c.skills[s.school] or 0) >= s.level) then
      out[#out + 1] = key
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Aiming and targets

function casting.untargeted(b, key)
  if key == "cloud of confusion" or key == "despair" or key == "choking gas" then return false end
  local s = magic.spell(b, key)
  if not s then return false end
  return casting.MASS_OF[key] ~= nil or MASS_ONLY[key] or key == "armageddon" or key == "celestial armor"
    or (s.type == "summoning" and not flag(s, "bodies") and key ~= "clone" and key ~= "illusionary ally")
end

-- How a spell is aimed: "none", "unit", "cell", "unit_or_cell" (Fire Ring), "unit_and_point"
-- (Sparks, Displacement), "two_units" (Sacrifice, Martyr), "unit_then_cell" (Teleport)
function casting.aim(b, key)
  if AIM_CELL[key] then return "cell" end
  if key == "fire ring" then return "unit_or_cell" end
  if key == "burning hands" or key == "displacement" then return "unit_and_point" end
  if key == "sacrifice" or key == "martyr" then return "two_units" end
  if key == "teleport" then return "unit_then_cell" end
  return casting.untargeted(b, key) and "none" or "unit"
end

-- Integer round(sqrt(n)) for n >= 0
local function round_sqrt(n)
  local r = math.floor(math.sqrt(n))
  while r * r > n do r = r - 1 end
  while (r + 1) * (r + 1) <= n do r = r + 1 end
  if n - r * r > r then r = r + 1 end
  return r
end

-- The stacks an area holds (exe 0x717030): round(distance from the centre to the footprint's
-- centre) - size x 8 < radius, in world units, and the spell can affect them, friend or foe
function casting.area_members(b, key, u, cx, cy, radius)
  local out = {}
  for _, v in ipairs(b.units) do
    if v.count > 0 then
      local dx, dy = v.x * 16 + v.size * 8 - cx, v.y * 16 + v.size * 8 - cy
      if round_sqrt(dx * dx + dy * dy) - v.size * 8 < radius and magic.can_target(b, key, u, v) then
        out[#out + 1] = v
      end
    end
  end
  return out
end

-- The stacks a cast touches, or nil when the target is not a valid one
function casting.targets(b, key, u, target, x, y)
  local m = casting.MASS_OF[key]
  local out = {}
  if m then
    for _, v in ipairs(b.units) do if v.count > 0 and magic.can_target(b, m, u, v) then out[#out + 1] = v end end
    return out
  end
  if key == "armageddon" then
    for _, v in ipairs(b.units) do
      if v.count > 0 and v.id ~= u.id and magic.can_target(b, key, u, v) then out[#out + 1] = v end
    end
    return out
  end
  if key == "divine intervention" then
    for _, v in ipairs(b.units) do if magic.can_target(b, key, u, v) then out[#out + 1] = v end end
    return out
  end
  if MASS_ONLY[key] then
    for _, v in ipairs(b.units) do if v.count > 0 and magic.can_target(b, key, u, v) then out[#out + 1] = v end end
    return out
  end
  local aim = casting.aim(b, key)
  if aim == "none" then return key == "celestial armor" and { u } or {} end
  if aim == "cell" then
    if not x or x < 0 or y < 0 or x >= grid.SIZE or y >= grid.SIZE then return nil end
    if AREA[key] then return casting.area_members(b, key, u, x * 16 + 8, y * 16 + 8, AREA[key]) end
    return {}
  end
  if aim == "unit_or_cell" and target == nil then   -- Fire Ring on a cell: 72 around it
    if not x or x < 0 or y < 0 or x >= grid.SIZE or y >= grid.SIZE then return nil end
    return casting.area_members(b, key, u, x * 16 + 8, y * 16 + 8, 72)
  end
  local t = target and b.units[target]
  if not t or not magic.can_target(b, key, u, t) then return nil end
  if key == "fire ring" then   -- round a stack: 48 + its size x 8, the stack itself spared
    local ring = casting.area_members(b, key, u, t.x * 16 + t.size * 8, t.y * 16 + t.size * 8, 48 + t.size * 8)
    for i = #ring, 1, -1 do if ring[i].id == t.id then table.remove(ring, i) end end
    return ring
  end
  return { t }
end

---------------------------------------------------------------------------------------------
-- The field spells

function casting.free_spot(b, near, size)
  local best, best_d = {}, nil
  local cx, cy = near.x * 16 + near.size * 8, near.y * 16 + near.size * 8
  -- the cells whose centre is at most 16 r from (cx, cy) along each axis, growing r: once
  -- the nearest free place is that close, nothing outside can be nearer or as near, and the
  -- ones found come in the same order as a scan of the whole field
  local n, r = grid.SIZE, 4
  while true do
    best, best_d = {}, nil
    local x0, x1 = math.max(0, -((size * 8 + 16 * r - cx) // 16)), math.min(n - 1, (cx - size * 8 + 16 * r) // 16)
    local y0, y1 = math.max(0, -((size * 8 + 16 * r - cy) // 16)), math.min(n - 1, (cy - size * 8 + 16 * r) // 16)
    for x = x0, x1 do
      grid.tick()
      for y = y0, y1 do
        if b.field:fits(x, y, size) and not grid.overlaps(b.units, x, y, size, nil) then
          local dx, dy = x * 16 + size * 8 - cx, y * 16 + size * 8 - cy
          local d = dx * dx + dy * dy
          if best_d == nil or d < best_d then best_d = d; best = { { x, y } }
          elseif d == best_d then best[#best + 1] = { x, y } end
        end
      end
    end
    if (best_d and best_d <= (16 * r) ^ 2) or r >= n then break end
    r = r * 2
  end
  if #best == 0 then return nil end
  local p = best[b.rng:next() % #best + 1]
  return p[1], p[2]
end

-- Teleport's destination (exe 0x87eef0): free, and reachable over the field with walls,
-- obstacles and stacks in between as barriers
function casting.teleport_ok(b, t, gx, gy)
  local function free(x, y) return b.field:fits(x, y, t.size) and not grid.overlaps(b.units, x, y, t.size, t.id) end
  if not free(gx, gy) then return false end
  local seen, stack = { [grid.key(t.x, t.y)] = true }, { { t.x, t.y } }
  while #stack > 0 do
    local p = table.remove(stack)
    if p[1] == gx and p[2] == gy then return true end
    for dx = -1, 1 do
      for dy = -1, 1 do
        local nx, ny = p[1] + dx, p[2] + dy
        local k = grid.key(nx, ny)
        if (dx ~= 0 or dy ~= 0) and nx >= 0 and ny >= 0 and nx < grid.SIZE and ny < grid.SIZE
            and not seen[k] and free(nx, ny) then
          seen[k] = true
          stack[#stack + 1] = { nx, ny }
        end
      end
    end
  end
  return false
end

-- Displacement's push (exe 0x8609f0): from the pointer through the stack's centre, as far as
-- 8 cells while the way is free
function casting.displacement(b, t, px, py)
  local dx = t.x * 16 + t.size * 8 - (px * 16 + 8)
  local dy = t.y * 16 + t.size * 8 - (py * 16 + 8)
  local len = f32(math.sqrt(dx * dx + dy * dy))
  if len <= 0 then return t.x, t.y end
  local vx, vy = num.trunc(f32(f32(10 * dx) / len)), num.trunc(f32(f32(10 * dy) / len))
  local m = math.max(math.abs(vx), math.abs(vy))
  if m == 0 then return t.x, t.y end
  local ex, ey = t.x, t.y
  for k = 1, 8 do
    local ox, oy = num.trunc(k * vx / m), num.trunc(k * vy / m)
    if ox * ox + oy * oy > 64 then break end
    local x, y = t.x + ox, t.y + oy
    if not b.field:fits(x, y, t.size) or grid.overlaps(b.units, x, y, t.size, t.id) then break end
    ex, ey = x, y
  end
  return ex, ey
end

function casting.quicksand_ok(b, x, y)
  return b.field:is_open(x, y) and not b.field.quicksand[grid.key(x, y)] and not grid.overlaps(b.units, x, y, 1, nil)
end

-- Rock Growth's place (exe 0x87a590): 3 x 3 free cells, every enemy at least 5 cells away
function casting.rock_ok(b, x, y, u)
  for i = -1, 1 do
    for j = -1, 1 do
      if not b.field:is_open(x + i, y + j) or grid.overlaps(b.units, x + i, y + j, 1, nil) then return false end
    end
  end
  for _, v in ipairs(b.units) do
    if v.count > 0 and b:hostile(v, u) then
      local gx = math.max(0, v.x - (x + 1), (x - 1) - (v.x + v.size - 1))
      local gy = math.max(0, v.y - (y + 1), (y - 1) - (v.y + v.size - 1))
      if math.max(gx, gy) < 5 then return false end
    end
  end
  return true
end

-- Sparks (Burning Hands, exe 0x866160): the half disc in front of the caster
function casting.sparks_targets(b, u, fx, fy)
  local n = u.size + 6
  local cx, cy = u.x * 16 + u.size * 8, u.y * 16 + u.size * 8
  local hit, seen = {}, {}
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      if (2 * i + 1 - n) ^ 2 + (2 * j + 1 - n) ^ 2 <= n * n + 2 then
        local x, y = u.x - 3 + i, u.y - 3 + j
        -- within 90 degrees of the facing: a non-negative dot product
        if (x * 16 + 8 - cx) * fx + (y * 16 + 8 - cy) * fy >= 0 then
          for _, v in ipairs(b.units) do
            if v.count > 0 and v.id ~= u.id and not seen[v.id]
                and x >= v.x and x < v.x + v.size and y >= v.y and y < v.y + v.size
                and magic.can_target(b, "burning hands", u, v) then
              seen[v.id] = true
              hit[#hit + 1] = v
            end
          end
        end
      end
    end
  end
  return hit
end

-- Sparks aims like a melee attack: of the places u can strike t from this turn, the one whose
-- direction from t is nearest the pointer's
function casting.sparks_position(b, u, t, px, py)
  local tx, ty = t.x * 16 + t.size * 8, t.y * 16 + t.size * 8
  local wx, wy
  if px then wx, wy = px * 16 + 8 - tx, py * 16 + 8 - ty
  else wx, wy = u.x * 16 + u.size * 8 - tx, u.y * 16 + u.size * 8 - ty end
  local wl = f32(math.sqrt(wx * wx + wy * wy))
  -- the places it can reach (and its own) touching t: only in the box around t
  local keys, cost, N = {}, b:reachable(u), grid.N
  for x = math.max(0, t.x - u.size), math.min(N - 1, t.x + t.size) do
    for y = math.max(0, t.y - u.size), math.min(N - 1, t.y + t.size) do
      local k = grid.key(x, y)
      if cost[k] or (x == u.x and y == u.y) then keys[#keys + 1] = k end
    end
  end
  table.sort(keys)
  local best, best_cos
  for _, k in ipairs(keys) do
    local x, y = grid.xy(k)
    if x <= t.x + t.size and t.x <= x + u.size and y <= t.y + t.size and t.y <= y + u.size
        and not grid.overlaps(b.units, x, y, u.size, u.id) then
      local ax, ay = x * 16 + u.size * 8 - tx, y * 16 + u.size * 8 - ty
      local al = f32(math.sqrt(ax * ax + ay * ay))
      local cos = (al > 0 and wl > 0) and f32(f32(ax * wx + ay * wy) / f32(al * wl)) or 1
      if best_cos == nil or cos > best_cos then best, best_cos = k, cos end
    end
  end
  if not best then return nil end
  return grid.xy(best)
end

---------------------------------------------------------------------------------------------
-- What spells do

local function strike(b, t, dmg, key)
  local d = math.min(dmg, stats.total_health(t))
  local killed = b:wound(t, d, nil)
  b:emit({ t = "spell", stack = t.id, spell = key, damage = d, killed = killed, left = t.count })
  if t.count <= 0 then b:emit({ t = "die", stack = t.id }) end
  b:flush()
  return killed
end
casting.strike = strike

local function resisted(b, t, key, u)
  local r = magic.resistance(b, t, key, u)
  if r >= 100 or b.rng:next() % 100 < r then
    b:emit({ t = "resisted", stack = t.id, spell = key })
    return true
  end
  return false
end

-- A summoned or raised stack on the caster's side (exe 0x87bdd0): a second cast adds to the
-- stack this spell brought before; else a new stack next to the caster (or on the bodies)
function casting.summon(b, key, kind, count, u, corpse, copy)
  local side = b:side_of(u)
  for _, old in ipairs(b.units) do
    if old.count > 0 and old.summoned and old.summoned_by == key and old.side == side and old.kind == kind then
      old.count, old.count_start = old.count + count, old.count_start + count
      b:emit({ t = "revived", stack = old.id, spell = key, count = count, rose = false })
      return old
    end
  end
  local st
  if copy then
    st = {}
    for k, v in pairs(copy) do st[k] = v end
    st.abilities = {}
    for k, v in pairs(copy.abilities) do st.abilities[k] = v end
    st.xp = 0
  else
    local def = b.creatures and b.creatures[kind]
    if not def then return nil end
    st = stats.creature(kind, def, count)
    if b.sizes and b.sizes[kind] then st.size = b.sizes[kind] end
  end
  st.count, st.wounds, st.effects = count, 0, { [key] = { power = 0 } }
  st.caster = nil
  local x, y
  if corpse and corpse.size == st.size and not grid.overlaps(b.units, corpse.x, corpse.y, corpse.size, corpse.id) then
    x, y = corpse.x, corpse.y
  else
    x, y = casting.free_spot(b, corpse or u, st.size)
  end
  if not x then return nil end
  st.id, st.side, st.x, st.y = #b.units + 1, side, x, y
  st.facing = side == 0 and "ne" or "sw"
  st.moved, st.count_start, st.permanently_lost = 0, count, 0
  st.poison, st.plague, st.regeneration = 0, 0, 0
  st.summoned, st.summoned_by, st.acted = true, key, true
  st.morale_roll, st.turn_started = 9, true
  st.morale, st.luck = st.morale or 0, st.luck or 0
  b.units[#b.units + 1] = st
  casting.creature_caster(b, st)
  if copy then b:emit({ t = "phantom", stack = st.id, of = copy.id })
  elseif flag(magic.spell(b, key), "bodies") then b:emit({ t = "revived", stack = st.id, spell = key, count = count, rose = true })
  else b:emit({ t = "summon", stack = st.id }) end
  return st
end

-- Raising (exe 0x8058f0): Raise Skeletons / Ghost / Vampires make min(power, the dead,
-- ceil(dead x their hp / the raised one's)); Animate Dead and Death Call raise the corpse's
-- own creature, power in hit points. The bodies used are gone for good.
function casting.raise(b, key, p, u, t)
  local dead = magic.dead_count(t)
  local hp_dead = math.max(1, stats.hit_points(t))
  local kind, made, used
  if key == "animate dead" or key == "death call" then
    kind = t.kind
    local amt = math.min(p, dead * hp_dead)
    made = (amt + hp_dead - 1) // hp_dead
    used = made
  else
    kind = magic.spell(b, key).creature
    local cr = b.creatures and b.creatures[kind]
    if not cr then return end
    local hp_raised = math.max(1, cr.hp)
    made = math.min(p, dead, (dead * hp_dead + hp_raised - 1) // hp_raised)
    used = math.min(dead, (made * hp_raised + hp_dead - 1) // hp_dead)
  end
  if made <= 0 then return end
  t.permanently_lost = (t.permanently_lost or 0) + used
  local corpse = (t.count <= 0 and magic.dead_count(t) == 0) and t or nil
  if corpse then b:emit({ t = "bodies_gone", stack = t.id }) end
  casting.summon(b, key, kind, made, u, corpse)
end

---------------------------------------------------------------------------------------------
-- The cast

-- Can u cast `key` at this target now? Returns the targets, or nil and a reason
function casting.check(b, u, cmd)
  local key = cmd.spell
  local ok = false
  for _, k in ipairs(casting.castable(b, u)) do if k == key then ok = true end end
  if not ok then return nil, "cannot cast" end
  local s = magic.spell(b, key)
  local targets = casting.targets(b, key, u, cmd.target, cmd.x, cmd.y)
  if not targets then return nil, "not a target" end
  if flag(s, "summoning") and not flag(s, "bodies") and key ~= "clone" and key ~= "illusionary ally" then
    local cr = b.creatures and b.creatures[s.creature]
    if not cr then return nil, "unknown creature" end
  end
  if key == "teleport" then
    local t = targets[1]
    if not t or not cmd.x or not casting.teleport_ok(b, t, cmd.x, cmd.y) then return nil, "no way there" end
  elseif key == "rock growth" then
    if not casting.rock_ok(b, cmd.x, cmd.y, u) then return nil, "no room" end
  elseif key == "quicksand" then
    if not casting.quicksand_ok(b, cmd.x, cmd.y) then return nil, "no room" end
  elseif key == "smoke" then
    if not grid.on_field(cmd.x, cmd.y) then return nil, "off the field" end
  end
  if key == "sacrifice" or key == "martyr" then
    local t2 = cmd.second and b.units[cmd.second]
    if not t2 or cmd.second == cmd.target or not magic.can_target(b, key, u, t2) then return nil, "no second target" end
  end
  return targets
end

function casting.cast(b, u, cmd)
  local targets, err = casting.check(b, u, cmd)
  if not targets then return nil, err end
  local key = cmd.spell
  local s = magic.spell(b, key)
  if under(u, "sanctuary") then magic.remove(b, u, "sanctuary") end
  local cost = casting.cost(b, key, u)
  u.spell_points = u.spell_points - cost
  -- Magic Leech: its caster gets 1 spell point per 2 the target spends
  if under(u, "magic leech") and u.leeched_by then
    local l = b.units[u.leeched_by]
    if l and l.count > 0 and l.caster then l.spell_points = (l.spell_points or 0) + cost // 2 end
  end
  local p = magic.power(b, key, u)
  local ids = {}
  for i, t in ipairs(targets) do ids[i] = t.id end
  b:emit({ t = "cast", stack = u.id, spell = key, targets = ids })
  local mark = #b.events
  if AREA[key] or key == "fire ring" then
    local cx, cy = cmd.x, cmd.y
    local t = cmd.target and b.units[cmd.target]
    if not cx and t then cx, cy = t.x + t.size // 2, t.y + t.size // 2 end
    if cx then b:emit({ t = "cast_at", stack = u.id, spell = key, x = cx, y = cy }) end
  end
  local effect = casting.MASS_OF[key] or REMAP[key] or key
  local kind = LASTING[effect] and "lasting" or s.type

  if kind == "lasting" then
    for _, t in ipairs(targets) do
      local dmg = magic.spell_damage(b, t, p, key)
      if effect == "poison" then t.poison = dmg
      elseif effect == "plague" then t.plague = dmg
      elseif effect == "regeneration" then t.regeneration = p end
      t.effects[effect] = t.effects[effect] or { power = p }
      b:emit({ t = "spell", stack = t.id, spell = effect, damage = 0, killed = 0, left = t.count })
    end
  elseif kind == "damage" and key == "holy water" and targets[1] and b:side_of(targets[1]) == b:side_of(u) then
    for _, e in ipairs({ "bless", "protection from death" }) do
      magic.apply(b, targets[1], e, p)
      b:emit({ t = "spell", stack = targets[1].id, spell = e, damage = 0, killed = 0, left = targets[1].count })
    end
  elseif kind == "damage" and key == "burning hands" then
    local t = targets[1]
    local x, y = casting.sparks_position(b, u, t, cmd.x, cmd.y)
    if x then
      if x ~= u.x or y ~= u.y then b:do_move(u, x, y) end
      u.facing = grid.facing(grid.delta2(u, t))
      local fx, fy = grid.dir8(grid.delta2(u, t))
      for _, v in ipairs(casting.sparks_targets(b, u, fx, fy)) do strike(b, v, magic.spell_damage(b, v, p, key), key) end
    end
  elseif kind == "damage" then
    local drained = 0
    for _, t in ipairs(targets) do
      local d = math.min(magic.spell_damage(b, t, p, key), stats.total_health(t))
      strike(b, t, d, key)
      drained = drained + d // 2
    end
    if key == "life drain" and drained > 0 then
      local amt = magic.restore(b, u, drained)
      b:emit({ t = "spell", stack = u.id, spell = key, damage = -amt, killed = 0, left = u.count })
    end
    -- Chain Lightning: the power halves before each jump, to the nearest stack not yet
    -- struck (ties at random), at most five stacks
    if key == "chain lightning" and targets[1] then
      local hit, from, pw = { [targets[1].id] = true }, targets[1], p
      local n = 1
      while n < 5 do
        pw = pw // 2
        if pw <= 0 then break end
        local best, ties = nil, {}
        for _, v in ipairs(b.units) do
          if v.count > 0 and not hit[v.id] and magic.can_target(b, key, u, v) then
            local dx = v.x * 16 + v.size * 8 - from.x * 16 - from.size * 8
            local dy = v.y * 16 + v.size * 8 - from.y * 16 - from.size * 8
            local d = dx * dx + dy * dy
            if best == nil or d < best then best = d; ties = { v } elseif d == best then ties[#ties + 1] = v end
          end
        end
        if #ties == 0 then break end
        local nx = ties[b.rng:next() % #ties + 1]
        strike(b, nx, magic.spell_damage(b, nx, pw, key), key)
        hit[nx.id] = true; from = nx; n = n + 1
      end
    end
  elseif key == "divine intervention" then
    for _, t in ipairs(targets) do
      local gone = {}
      for e in pairs(t.effects) do
        local es = magic.spell(b, e)
        if es and flag(es, "curse") then gone[#gone + 1] = e end
      end
      table.sort(gone)
      for _, e in ipairs(gone) do magic.remove(b, t, e) end
      local healed
      if t.count > 0 then healed = math.min(p, t.wounds); t.wounds = t.wounds - healed
      else healed = magic.restore(b, t, p) end
      b:emit({ t = "spell", stack = t.id, spell = key, damage = -healed, killed = 0, left = t.count })
    end
  elseif key == "banish" then
    for _, t in ipairs(targets) do
      local hp = math.max(1, stats.hit_points(t))
      strike(b, t, magic.spell_damage(b, t, p, key, u) // hp * hp, key)
    end
  elseif DISPEL[key] then
    for _, t in ipairs(targets) do
      if not (b:side_of(t) ~= b:side_of(u) and (flag(s, "resisted") or flag(s, "resisted_if_enemy"))
          and resisted(b, t, key, u)) then
        magic.dispel(b, t, DISPEL[key])
        if key == "anti magic" then magic.apply(b, t, "anti magic", p) end
        b:emit({ t = "spell", stack = t.id, spell = effect, damage = 0, killed = 0, left = t.count })
      end
    end
  elseif key == "steal enchantment" or key == "steal all enchantments" then
    for _, t in ipairs(targets) do
      while true do
        local friends = {}
        for _, v in ipairs(b.units) do if v.count > 0 and not b:hostile(v, u) then friends[#friends + 1] = v end end
        local keys = {}
        for e in pairs(t.effects) do keys[#keys + 1] = e end
        table.sort(keys, function(p1, q1)
          local a1, b1 = magic.spell(b, p1), magic.spell(b, q1)
          return (a1 and a1.id or 999) < (b1 and b1.id or 999)
        end)
        local eligible = {}
        for _, e in ipairs(keys) do
          local es = magic.spell(b, e)
          if es and flag(es, "blessing") and not flag(es, "no_dispel") then
            for _, f in ipairs(friends) do
              if magic.can_target(b, e, u, f) then eligible[#eligible + 1] = e; break end
            end
          end
        end
        if #eligible == 0 then break end
        local e = eligible[b.rng:next() % #eligible + 1]
        local takers = {}
        for _, f in ipairs(friends) do if magic.can_target(b, e, u, f) then takers[#takers + 1] = f end end
        local r = takers[b.rng:next() % #takers + 1]
        local pw = t.effects[e].power or 0
        magic.remove(b, t, e)
        magic.apply(b, r, e, pw)
        b:emit({ t = "spell", stack = r.id, spell = e, damage = 0, killed = 0, left = r.count })
        if key == "steal enchantment" then break end
      end
    end
  elseif key == "teleport" or key == "displacement" then
    for _, t in ipairs(targets) do
      if not (b:hostile(t, u) and resisted(b, t, key, u)) then
        local fx, fy = t.x, t.y
        local tx, ty
        if key == "teleport" then tx, ty = cmd.x, cmd.y
        else tx, ty = casting.displacement(b, t, cmd.x or fx, cmd.y or fy) end
        if tx ~= fx or ty ~= fy then
          b:release(t); t.bound_by = nil; t.effects.binding = nil
          t.x, t.y = tx, ty
          b:emit({ t = key == "teleport" and "teleported" or "displaced", stack = t.id, from = { fx, fy }, to = { tx, ty } })
        end
      end
    end
  elseif key == "quicksand" then
    local painted, ring, seen = {}, { { cmd.x, cmd.y } }, { [grid.key(cmd.x, cmd.y)] = true }
    while #painted < p and #ring > 0 do
      table.sort(ring, function(q1, q2)
        local d1 = (q1[1] - cmd.x) ^ 2 + (q1[2] - cmd.y) ^ 2
        local d2 = (q2[1] - cmd.x) ^ 2 + (q2[2] - cmd.y) ^ 2
        if d1 ~= d2 then return d1 < d2 end
        return grid.key(q1[1], q1[2]) < grid.key(q2[1], q2[2])
      end)
      local c = table.remove(ring, 1)
      if casting.quicksand_ok(b, c[1], c[2]) then
        painted[#painted + 1] = { c[1], c[2] }
        b.field.quicksand[grid.key(c[1], c[2])] = true
        b.field:changed()
      end
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local k = grid.key(nx, ny)
        if grid.on_field(nx, ny) and not seen[k] then seen[k] = true; ring[#ring + 1] = { nx, ny } end
      end
    end
    b:emit({ t = "obstacle", spell = key, cells = painted })
  elseif key == "smoke" then
    local cells = {}
    for i = -1, 2 do
      for j = -1, 2 do
        if grid.on_field(cmd.x + i, cmd.y + j) then
          b.field.smoke[grid.key(cmd.x + i, cmd.y + j)] = true
          cells[#cells + 1] = { cmd.x + i, cmd.y + j }
        end
      end
    end
    b:emit({ t = "obstacle", spell = key, cells = cells })
  elseif key == "rock growth" then
    local cells = {}
    for i = -1, 1 do
      for j = -1, 1 do
        b.field:block(cmd.x + i, cmd.y + j)
        cells[#cells + 1] = { cmd.x + i, cmd.y + j }
      end
    end
    b:emit({ t = "obstacle", spell = key, cells = cells })
  elseif kind == "resurrection" then
    if targets[1] then b:resurrect(targets[1], p, key) end
  elseif kind == "summoning" and flag(s, "bodies") then
    if targets[1] then casting.raise(b, key, p, u, targets[1]) end
  elseif key == "martyr" then
    local t, t2 = targets[1], b.units[cmd.second]
    magic.apply(b, t2, "martyr", p)
    t2.martyr = t.id
    b:emit({ t = "spell", stack = t2.id, spell = key, damage = 0, killed = 0, left = t2.count })
  elseif kind == "sacrifice" then
    local t, t2 = targets[1], b.units[cmd.second]
    local hp, killed = stats.total_health(t), t.count
    t.count, t.wounds, t.permanently_lost = 0, 0, t.count_start
    b:emit({ t = "spell", stack = t.id, spell = key, damage = hp, killed = killed, left = 0 })
    b:emit({ t = "die", stack = t.id }); b:emit({ t = "bodies_gone", stack = t.id })
    b:resurrect(t2, 2 * hp, key)
  elseif kind == "healing" then
    for _, t in ipairs(targets) do
      local healed = math.min(p, t.wounds)
      t.wounds = t.wounds - healed
      if CURES[effect] or CURES[key] then
        for _, e in ipairs({ "poison", "stun", "plague" }) do magic.remove(b, t, e) end
      end
      b:emit({ t = "spell", stack = t.id, spell = key, damage = -healed, killed = 0, left = t.count })
    end
  elseif kind == "summoning" then
    if key == "clone" or key == "illusionary ally" then
      local t = targets[1]
      local hp = math.max(1, stats.hit_points(t))
      casting.summon(b, key, t.kind, (p + hp - 1) // hp, u, nil, t)
    else
      casting.summon(b, key, s.creature, p, u)
    end
  else
    for _, t in ipairs(targets) do
      local enemy = b:side_of(t) ~= b:side_of(u)
      if not ((flag(s, "resisted") or (enemy and flag(s, "resisted_if_enemy"))) and resisted(b, t, key)) then
        if key == "acid" and t.count <= 0 then   -- on the dead: the bodies are gone
          t.permanently_lost = t.count_start
          b:emit({ t = "spell", stack = t.id, spell = key, damage = 0, killed = 0, left = 0 })
          b:emit({ t = "bodies_gone", stack = t.id })
        else
          magic.apply(b, t, effect, p)
          if effect == "magic leech" then t.leeched_by = u.id end
          if effect ~= "hand of death" then
            b:emit({ t = "spell", stack = t.id, spell = effect, damage = 0, killed = 0, left = t.count })
          end
        end
      end
    end
  end

  -- Magic Mirror (exe 0x614b10): a curse or damage spell that landed comes back on its caster
  -- at half strength, unless the caster is already under it
  if (flag(s, "curse") or flag(s, "damage")) and u.count > 0 then
    local res = {}
    for i = mark + 1, #b.events do
      local e = b.events[i]
      if e.t == "resisted" then res[e.stack] = true end
    end
    for _, t in ipairs(targets) do
      if has(t, "magic_mirror") and not res[t.id] and b:hostile(t, u) and u.count > 0
          and not under(u, effect) and magic.can_target(b, key, t, u, true) then
        b:emit({ t = "effect", stack = t.id, effect = "magic mirror", damage = 0, killed = 0, left = t.count })
        if s.type == "damage" then strike(b, u, magic.spell_damage(b, u, p // 2, key), key)
        else
          magic.apply(b, u, effect, p // 2)
          b:emit({ t = "spell", stack = u.id, spell = effect, damage = 0, killed = 0, left = u.count })
        end
      end
    end
  end
  -- Spell Shackle: 10 x the cost burns the caster, after its own resistance
  if under(u, "spell shackle") and u.count > 0 then
    strike(b, u, magic.spell_damage(b, u, 10 * cost, "spell shackle"), "spell shackle")
  end
  b:check_end()
  b:end_action(u)
  return true
end

-- For options(): the spells u can cast with their aim
function casting.options(b, u)
  local out = {}
  for _, key in ipairs(casting.castable(b, u)) do
    out[key] = { aim = casting.aim(b, key), cost = casting.cost(b, key, u) }
  end
  return out
end

function casting.install(battle)
  battle.hooks.prepare = casting.prepare
  battle.hooks.cast = casting.cast
  battle.hooks.spell_options = casting.options
  battle.hooks.summon_for = casting.creature_caster
end

return casting
