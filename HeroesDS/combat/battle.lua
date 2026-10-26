-- HeroesDS combat: a battle -- rounds, turn order, actions, events (MECHANICS.md 1-10,
-- COMBAT.md 4-8).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Battle.swift, with the
-- heroes4.exe addresses.
--
-- The only API the screen uses: battle.new, b:current(), b:options(), b:act(cmd),
-- b:preview(cmd), b:attack_positions(u, t), b.finished / b.winner, b:checksum().
-- Abilities (C3c), heroes (C3d) and spells (C3e) plug into the hooks in battle.hooks.

local num = require("combat.num")
local rng = require("combat.rng")
local grid = require("combat.grid")
local stats = require("combat.stats")
local damage = require("combat.damage")
local magic = require("combat.magic")
local f32 = num.f32
local under, has = stats.under, stats.has

local battle = {}
local Battle = {}
Battle.__index = Battle

-- The simultaneous exchange (decision H9): false -- the attacker's blow lands first and a
-- melee target it kills does nothing (homm4-mac without animation timings, the exe on equal
-- hit times); true -- the dead target still strikes back with the stack it had.
battle.dead_strike_back = false

-- The last round: past it the battle ends (homm4-mac: as an attacker's win)
battle.MAX_ROUNDS = 60

-- Hooks for later points: functions (b, ...) set by the ability / spell modules
battle.hooks = {
  start_of_turn = nil,   -- (b, u): regeneration, poison...
  extra_targets = nil,   -- (b, a, t, ranged) -> list of stacks also struck
  aftermath = nil,       -- (b, a, t, ranged, dmg, health_before)
  on_death = nil,        -- (b, u)
  fears = nil,           -- (b, t, a) -> true when t is too afraid to strike back
  stone_gaze = nil,      -- (b, a, t) -> extra damage of a blow
}

-- Deployment cells (exe 0xaae8b8): [formation][side][army slot] = { x, y }; formations
-- 0 loose, 1 tight, 2 square, 3/4 siege, 5 ship deck
battle.DEPLOYMENT = {
  [0] = { [0] = { { 76, 51 }, { 85, 55 }, { 76, 60 }, { 85, 64 }, { 76, 69 }, { 85, 73 }, { 76, 78 } },
          [1] = { { 33, 32 }, { 24, 37 }, { 33, 41 }, { 24, 46 }, { 33, 50 }, { 24, 55 }, { 33, 59 } } },
  [1] = { [0] = { { 77, 54 }, { 84, 57 }, { 77, 61 }, { 84, 64 }, { 77, 68 }, { 84, 71 }, { 77, 75 } },
          [1] = { { 32, 35 }, { 25, 39 }, { 32, 42 }, { 25, 46 }, { 32, 49 }, { 25, 53 }, { 32, 56 } } },
  [2] = { [0] = { { 77, 57 }, { 84, 57 }, { 77, 64 }, { 84, 64 }, { 77, 71 }, { 84, 71 }, { 91, 64 } },
          [1] = { { 32, 39 }, { 25, 39 }, { 32, 46 }, { 25, 46 }, { 32, 53 }, { 25, 53 }, { 18, 46 } } },
  [3] = { [0] = { { 76, 51 }, { 85, 55 }, { 76, 60 }, { 85, 64 }, { 76, 69 }, { 85, 73 }, { 76, 78 } },
          [1] = { { 43, 23 }, { 43, 31 }, { 43, 40 }, { 43, 49 }, { 43, 57 }, { 43, 67 }, { 43, 74 } } },
  [4] = { [0] = { { 76, 51 }, { 85, 55 }, { 76, 60 }, { 85, 64 }, { 76, 69 }, { 85, 73 }, { 76, 78 } },
          [1] = { { 43, 23 }, { 36, 38 }, { 43, 40 }, { 25, 50 }, { 43, 57 }, { 36, 61 }, { 43, 74 } } },
  [5] = { [0] = { { 71, 41 }, { 78, 48 }, { 71, 48 }, { 78, 55 }, { 71, 55 }, { 78, 62 }, { 71, 62 } },
          [1] = { { 31, 62 }, { 24, 55 }, { 31, 55 }, { 24, 48 }, { 31, 48 }, { 24, 41 }, { 31, 41 } } },
}

-- Alignments in the game's order; morale between two (exe 0x51ecf0 / 0xa643f8)
local ALIGN = { life = 0, order = 1, death = 2, chaos = 3, nature = 4, might = 5 }
local RELATION_MORALE = { [0] = 0, -1, -2, -5 }
local function relation(a, b)
  if a == b then return 0 end
  if a == 5 or b == 5 then return 2 end
  local d = (a - b) % 5
  return (d == 1 or d == 4) and 1 or 3
end

-- A stack's morale from its army (exe 0x640310): +1, then for every alignment present the
-- relation's penalty, -2 with undead in the army unless it is death
function battle.army_morale(own, army)
  local me = ALIGN[own] or 0
  local m, seen, undead = 1, {}, false
  for i = 1, #army do
    local a = ALIGN[army[i].alignment]
    if a and not seen[a] then seen[a] = true; m = m + RELATION_MORALE[relation(me, a)] end
    if has(army[i], "undead") then undead = true end
  end
  if undead and me ~= 2 then m = m - 2 end
  return m
end

-- Lasting effects that make a stack lose its turn
local DISABLING = { "blind", "stun", "terror", "confusion", "summon stinkbug", "frozen" }

---------------------------------------------------------------------------------------------
-- Setup

-- setup = { seed, field (grid.new_field(), optional),
--           sides = { [0] = { stacks = { st, ... }, formation = 0 }, [1] = ... },
--           spells (spells.lua, for abilities and casting) }
-- Each st comes from stats.creature / stats.hero; st.slot (0..6) picks the deployment cell
-- (default: the order in the list); st.morale_bonus / st.luck add to the army's.
function battle.new(setup)
  local b = setmetatable({
    rng = rng.new(setup.seed or 0),
    field = setup.field or grid.new_field(),
    spells = setup.spells or {},
    units = {}, order = {}, events = {},
    round = 0, version = 0,
    initial_health = { [0] = 0, [1] = 0 }, loss_penalty = { [0] = 0, [1] = 0 },
    experience = 0,
    finished = false, winner = nil,
  }, Battle)
  for side = 0, 1 do
    local s = setup.sides[side]
    local list = s.stacks
    local table_ = battle.DEPLOYMENT[s.formation or 0][side]
    local by_slot = {}
    for k = 1, #list do
      local u = list[k]
      u.id = #b.units + 1
      u.side = side
      local slot = u.slot or (k - 1)
      local cell = table_[math.min(slot, 6) + 1]
      local tx, ty = cell[1] - (u.size - 1) // 2, cell[2] - (u.size - 1) // 2
      local placed = false
      for r = 0, 23 do
        for dx = -r, r do
          for dy = -r, r do
            if not placed and math.max(math.abs(dx), math.abs(dy)) == r then
              local x, y = tx + dx, ty + dy
              if b.field:fits(x, y, u.size) and not grid.overlaps(b.units, x, y, u.size, nil) then
                u.x, u.y = x, y
                placed = true
              end
            end
          end
        end
        if placed then break end
      end
      assert(placed, "no room to deploy " .. tostring(u.name))
      u.facing = side == 0 and "ne" or "sw"
      u.moved = 0
      u.count_start = u.count
      u.permanently_lost = 0
      u.poison, u.plague, u.regeneration = 0, 0, 0   -- stored doses / healing per turn
      b.units[#b.units + 1] = u
      by_slot[slot] = u
    end
    b:close_ranks(s.formation or 0, by_slot)
    -- morale from the army
    for k = 1, #list do
      local u = list[k]
      u.morale = battle.army_morale(u.alignment, list) + (u.morale_bonus or 0)
    end
  end
  for side = 0, 1 do b.initial_health[side] = b:side_health(side) end
  b:start_round()
  return b
end

-- Tight and square formations close the ranks: stacks slide toward a neighbour (exe 0x62e830)
function Battle:close_ranks(formation, by_slot)
  local function pull(a, c, limit)
    local m, t = by_slot[a], by_slot[c]
    if not m or not t then return false end
    local dxw = (t.x * 16 + t.size * 8) - (m.x * 16 + m.size * 8)
    local dyw = (t.y * 16 + t.size * 8) - (m.y * 16 + m.size * 8)
    local dx = num.trunc(dxw / 16); dx = dx > 0 and 1 or (dx < 0 and -1 or 0)
    local dy = num.trunc(dyw / 16); dy = dy > 0 and 1 or (dy < 0 and -1 or 0)
    if dx == 0 and dy == 0 then return false end
    local steps = 0
    while steps < limit and self.field:fits(m.x + dx, m.y + dy, m.size)
        and not grid.overlaps(self.units, m.x + dx, m.y + dy, m.size, m.id) do
      m.x, m.y = m.x + dx, m.y + dy
      steps = steps + 1
    end
    return steps > 0
  end
  if formation == 1 then
    if pull(2, 4, 1) then while pull(4, 2, 1) and pull(2, 4, 1) do end end
    pull(0, 2, 100); pull(6, 4, 100); pull(1, 3, 100); pull(5, 3, 100)
  elseif formation == 2 then
    pull(2, 3, 100); pull(0, 2, 100); pull(4, 2, 100); pull(1, 3, 100)
    pull(5, 3, 100); pull(6, 3, 100); pull(0, 1, 100); pull(4, 5, 100)
  end
end

---------------------------------------------------------------------------------------------
-- Queries

function Battle:emit(e) self.events[#self.events + 1] = e end

function Battle:current()
  local id = self.order[1]
  return id and self.units[id] or nil
end

function Battle:side_of(u) return u.hypnotized and 1 - u.side or u.side end

function Battle:hostile(a, c)
  return self:side_of(a) ~= self:side_of(c) or under(a, "berserk") or under(c, "berserk")
end

function Battle:side_health(side)
  local h = 0
  for _, u in ipairs(self.units) do
    if u.side == side and u.count > 0 then h = h + stats.total_health(u) end
  end
  return h
end

function Battle:disabled(u)
  for i = 1, #DISABLING do
    if u.effects[DISABLING[i]] then return true end
  end
  return false
end

function Battle:morale(u) return stats.morale(u, self.loss_penalty[u.side]) end

-- The turn key (exe 0x5f3110): speed, +1000 unless morale failed, +1000 for good morale
-- (before the check: when the roll is under the morale); negated for a stack that waited
function Battle:turn_key(u)
  local k = stats.speed(u) + (u.bad_morale and 0 or 1000)
  local good
  if u.morale_checked then good = u.good_morale else good = u.morale_roll < self:morale(u) end
  if good then k = k + 1000 end
  return u.waited and -k or k
end

function Battle:sort_order(ids)
  local keys = {}
  for _, id in ipairs(ids) do keys[id] = self:turn_key(self.units[id]) end
  table.sort(ids, function(a, c)
    if keys[a] ~= keys[c] then return keys[a] > keys[c] end
    local ua, uc = self.units[a], self.units[c]
    if ua.side ~= uc.side then return ua.side < uc.side end
    return a < c
  end)
  return ids
end

-- The order of the rest of the round (for the queue bar)
function Battle:queue()
  local out = {}
  for i, id in ipairs(self.order) do
    if self.units[id].count > 0 then out[#out + 1] = id end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Rounds and turns

-- Losses sap morale (exe 0x576390): each side's loss is 10 x hit points lost / at the start
-- (negative); a side that lost more than the enemy takes the difference
function Battle:update_loss_morale()
  local loss = { [0] = 0, [1] = 0 }
  for side = 0, 1 do
    local start = self.initial_health[side]
    if start > 0 then
      local now = self:side_health(side)
      if now < start then loss[side] = -(((start - now) * 10) // start) end
    end
  end
  for side = 0, 1 do self.loss_penalty[side] = math.min(0, loss[side] - loss[1 - side]) end
end

function Battle:start_round()
  self.round = self.round + 1
  for _, u in ipairs(self.units) do
    u.acted, u.waited, u.retaliated = false, false, false
    u.morale_roll = self.rng:next() % 10
    u.morale_checked, u.good_morale, u.bad_morale = false, false, false
    u.moved = 0
  end
  for _, u in ipairs(self.units) do u.turn_started = false end
  self:emit({ t = "round", n = self.round })
  self:check_end()
  if self.finished then return end
  local ids = {}
  for _, u in ipairs(self.units) do if u.count > 0 then ids[#ids + 1] = u.id end end
  self.order = self:sort_order(ids)
  self:check_morale()
end

-- The end of each of the stack's own turns (exe 0x5f2730): every duration down by one
function Battle:count_down(u)
  local gone
  for key, e in pairs(u.effects) do
    if e.turns then
      if e.turns <= 1 then gone = gone or {}; gone[#gone + 1] = key
      else e.turns = e.turns - 1 end
    end
  end
  if gone then
    table.sort(gone)
    for _, key in ipairs(gone) do
      u.effects[key] = nil
      if key == "hypnotize" or key == "short hypnotism" then u.hypnotized = false end
    end
  end
end

-- The stack coming up: what acts at the start of its turn, a lost turn, then its morale
-- check, once a round (exe 0x5f3710): bad when 9 - roll < -morale (it falls behind everyone
-- who kept their +1000), good when roll < morale
function Battle:check_morale()
  self:update_loss_morale()
  while not self.finished do
    local u = self:current()
    if not u then break end
    if not u.turn_started then
      u.turn_started = true
      if u.count > 0 and battle.hooks.start_of_turn then battle.hooks.start_of_turn(self, u) end
      self:check_end()
      if self.finished then return end
      if u.count <= 0 then
        table.remove(self.order, 1)
        if #self.order == 0 then self:start_round() return end
        goto continue
      end
    end
    if not self:disabled(u) then break end
    if not u.effects.frozen then
      for i = 1, #DISABLING - 1 do
        if u.effects[DISABLING[i]] then
          self:emit({ t = "effect", stack = u.id, effect = DISABLING[i], lost_turn = true })
          break
        end
      end
    end
    u.acted = true
    table.remove(self.order, 1)
    self:count_down(u)
    if #self.order == 0 then self:start_round() return end
    ::continue::
  end
  while not self.finished do
    local u = self:current()
    if not u or u.morale_checked then break end
    u.morale_checked = true
    local m = self:morale(u)
    if 9 - u.morale_roll < -m then
      u.bad_morale = true
      self:emit({ t = "morale", stack = u.id, good = false })
      self:sort_order(self.order)
    elseif u.morale_roll < m then
      u.good_morale = true
      self:emit({ t = "morale", stack = u.id, good = true })
    end
  end
  if self.finished then return end
  local u = self:current()
  if u and self:disabled(u) then self:check_morale() return end
  -- a stack that defended keeps its doubled defense until its own next turn (exe 0x567ef0)
  if u then
    u.defending = false
    self:emit({ t = "turn", stack = u.id })
  end
end

function Battle:handle_deaths()
  for _, u in ipairs(self.units) do
    if u.count <= 0 and not u.death_handled then
      u.death_handled = true
      u.hypnotized, u.bound_by = false, nil
      if battle.hooks.on_death then battle.hooks.on_death(self, u) end
    end
  end
end

function Battle:check_end()
  if self.finished then return end
  self:handle_deaths()
  local alive = { [0] = false, [1] = false }
  for _, u in ipairs(self.units) do
    if u.count > 0 then alive[u.side] = true end
  end
  if not (alive[0] and alive[1]) or self.round > battle.MAX_ROUNDS then
    self.finished = true
    self.winner = alive[0] and 0 or 1
    self:emit({ t = "over", winner = self.winner })
  end
end

function Battle:end_action(u)
  u.acted = true
  if not (u.effects.hypnotize or u.effects["short hypnotism"]) then u.hypnotized = false end
  self:count_down(u)
  for i = #self.order, 1, -1 do
    if self.order[i] == u.id then table.remove(self.order, i) end
  end
  self.version = self.version + 1
  self:check_end()
  if not self.finished and #self.order == 0 then self:start_round()
  elseif not self.finished then self:check_morale() end
end

---------------------------------------------------------------------------------------------
-- Movement

function Battle:move_budget(u)
  if u.bound_by then return f32(0) end
  return stats.move_cells(u)
end

-- The grid's description of how u moves (zones of control, quicksand, flying)
function Battle:mover(u, budget)
  local flies = has(u, "flying")
  local zoc = {}
  if not has(u, "ignore_zones_of_control") then
    for _, e in ipairs(self.units) do
      if e.count > 0 and e.id ~= u.id and self:side_of(e) ~= self:side_of(u)
          and (not flies or has(e, "flying")) then
        zoc[#zoc + 1] = e
      end
    end
  end
  local cells = stats.move_cells(u)
  local walk = not flies and not under(u, "terrain walk")
  return {
    id = u.id, x = u.x, y = u.y, size = u.size,
    budget = budget or self:move_budget(u),
    flies = flies, teleport = has(u, "teleport") and not u.bound_by,
    zoc = zoc, zoc_cost = f32(cells / 4),
    sand_cost = (walk and next(self.field.quicksand) ~= nil) and math.max(1, f32(cells / 2)) or nil,
    moat_cost = (walk and next(self.field.moat) ~= nil and cells > 4) and f32(cells / 4) or nil,
  }
end

-- Footprint positions u can reach (cost in cells) and the path tree, cached until something
-- happens on the field
function Battle:reachable(u, budget)
  budget = budget or self:move_budget(u)
  local key = u.id .. "|" .. u.x .. "|" .. u.y .. "|" .. budget .. "|" .. self.version
  local c = self.reach_cache
  if c and c.key == key then return c.cost, c.parent end
  local cost, parent = grid.reachable(self.field, self.units, self:mover(u, budget))
  self.reach_cache = { key = key, cost = cost, parent = parent }
  return cost, parent
end

function Battle:path(u, x, y)
  local m = self:mover(u)
  local cost, parent = self:reachable(u)
  local goal = grid.key(x, y)
  if cost[goal] == nil then return nil end
  if m.teleport then return { { x, y } } end
  if m.flies then return grid.path(self.field, self.units, m, x, y) end
  local out, k, start = {}, goal, grid.key(u.x, u.y)
  while k ~= start do
    table.insert(out, 1, { grid.xy(k) })
    k = parent[k]
    if k == nil then return nil end
  end
  return out
end

-- The cheapest key in a cost map that passes `ok` (ties: the lowest key, so every machine
-- picks the same)
local function cheapest(cost, ok)
  local best, best_cost
  for k, c in pairs(cost) do
    if (best_cost == nil or c < best_cost or (c == best_cost and k < best)) and ok(k) then
      best, best_cost = k, c
    end
  end
  return best, best_cost
end

-- Towards a place further than this turn's move: the route there (searched as far as 12
-- turns), cut where this turn's movement ends
function Battle:step_toward(u, gx, gy)
  local far = f32(self:move_budget(u) * 12)
  local cost, parent = grid.reachable(self.field, self.units, self:mover(u, far))
  local k, start = grid.key(gx, gy), grid.key(u.x, u.y)
  if cost[k] == nil or parent == nil then return nil end
  local today = self:reachable(u)
  while k ~= start do
    if today[k] then return grid.xy(k) end
    k = parent[k]
    if k == nil then return nil end
  end
  return nil
end

function Battle:do_move(u, x, y)
  local p = self:path(u, x, y)
  if not p or #p == 0 then return false end
  u.moved = f32(u.moved + (self:reachable(u)[grid.key(x, y)] or 0))
  self:emit({ t = "move", stack = u.id, path = p, from = { u.x, u.y }, flying = has(u, "flying") })
  local prev = #p > 1 and p[#p - 1] or { u.x, u.y }
  u.facing = grid.facing(x - prev[1], y - prev[2])
  u.x, u.y = x, y
  self:release(u)
  return true
end

-- Moving frees what the stack held bound
function Battle:release(u)
  for _, v in ipairs(self.units) do
    if v.bound_by == u.id then v.bound_by = nil; v.effects.binding = nil end
  end
end

---------------------------------------------------------------------------------------------
-- Striking

function Battle:reach(u) return has(u, "long_weapon") and 1 or 0 end

function battle.in_reach(x, y, s, b, reach)
  return x <= b.x + b.size + reach and b.x <= x + s + reach
     and y <= b.y + b.size + reach and b.y <= y + s + reach
end

local function total_health(u) return stats.total_health(u) end

-- Cowardice (exe 0x5f5740): no attack on a stack with at least its total hit points
function Battle:afraid(u, t)
  return under(u, "cowardice") and total_health(t) >= total_health(u)
end

-- May u attack or shoot t now: an enemy (anyone under Berserk), not in Sanctuary, not
-- feared (Cowardice), u not under Song of Peace
function Battle:may_strike(u, t)
  return t.count > 0 and t.id ~= u.id and self:hostile(u, t) and not under(t, "sanctuary")
     and not self:afraid(u, t) and not under(u, "song of peace")
end

function Battle:can_retaliate(t, a)
  return t.count > 0 and not self:disabled(t) and not has(a, "no_retaliation")
     and not (battle.hooks.fears and battle.hooks.fears(self, t, a))
     and (not t.retaliated or has(t, "unlimited_retaliation"))
     and battle.in_reach(t.x, t.y, t.size, a, self:reach(t))
end

-- Blows per attack (exe 0x5f2160): Quickness 2, Cat Reflexes +1, Strikes / Shoots Twice +1;
-- shots cap the volleys
function Battle:strikes(u, ranged)
  local n = under(u, "quickness") and 2 or 1
  if under(u, "reflexes") then n = n + 1 end
  if has(u, ranged and "shoots_twice" or "strikes_twice") then n = n + 1 end
  if ranged and not has(u, "unlimited_shots") then n = math.max(1, math.min(n, u.shots)) end
  return n
end

function Battle:strikes_first(x, y)
  return has(x, "first_strike") and not has(y, "first_strike_immunity") and not has(y, "first_strike")
end

-- The block roll of the stack about to be struck (exe 0x5f3f20): never while stunned or frozen
function Battle:roll_block(u)
  u.blocking = false
  if not has(u, "block") or u.effects.stun or u.effects.frozen then return end
  if self.rng:next() % 100 < 30 then u.blocking = true end
end

-- Damage taken by a stack: whole creatures die from the front; the attacking side gets the
-- experience for the defender's dead
function Battle:wound(t, dmg, by)
  if dmg <= 0 or t.count <= 0 then return 0 end
  local killed = stats.take(t, math.min(dmg, total_health(t)))
  if dmg > 0 then t.effects.blind = nil end
  if t.side == 1 then self.experience = self.experience + killed * (t.xp or 0) end
  return killed
end

-- One blow of a on b (exe 0x553440 for the aftermath); secondary blows only do damage
function Battle:hit(a, b, ranged, secondary)
  local before = total_health(b)
  local base = damage.roll_base(a, self.rng)
  local dmg = damage.blow(a, b, base, {
    ranged = ranged, moved = ranged and 0 or num.trunc(a.moved),
    on_quicksand = self.field:on_quicksand(a.x, a.y, a.size),
  })
  if ranged then dmg = math.max(1, dmg // damage.range_divisor(self.field, a, b)) end
  local stoned = 0
  if not secondary and battle.hooks.stone_gaze then
    stoned = battle.hooks.stone_gaze(self, a, b)
    dmg = dmg + stoned
  end
  local lucky
  dmg, lucky = damage.lucky(self.rng, stats.luck(b), dmg)
  if lucky ~= nil then self:emit({ t = "luck", stack = b.id, good = lucky }) end
  dmg = math.min(dmg, before)
  local kind = ranged and "shoot" or "melee"
  if b.blocking then
    self:emit({ t = kind, stack = a.id, target = b.id, damage = 0, killed = 0, left = b.count })
    self:emit({ t = "blocked", stack = b.id })
    return 0
  end
  local killed = self:wound(b, dmg, a)
  self:emit({ t = kind, stack = a.id, target = b.id, damage = dmg, killed = killed, left = b.count })
  if b.count <= 0 then
    self:emit({ t = "die", stack = b.id })
    b.bound_by = nil
  end
  if stoned > 0 then self:emit({ t = "effect", stack = b.id, effect = "stone_gaze", left = b.count }) end
  if not secondary and battle.hooks.aftermath then
    if self.held then
      local held = self.held
      held[#held + 1] = function() battle.hooks.aftermath(self, a, b, ranged, dmg, before) end
    else
      battle.hooks.aftermath(self, a, b, ranged, dmg, before)
    end
  end
  return dmg
end

-- An ability or spell took hold on u (`name`), with any damage it does
function Battle:effect(u, name, dmg)
  local killed = 0
  if dmg and dmg > 0 then killed = self:wound(u, dmg, nil) end
  self:emit({ t = "effect", stack = u.id, effect = name, damage = dmg or 0, killed = killed, left = u.count })
  if dmg and dmg > 0 and u.count <= 0 then self:emit({ t = "die", stack = u.id }) end
end

-- Hit points back to a stack (Resurrection, Rebirth): its wounds, then its dead
function Battle:resurrect(u, power, spell)
  local before = u.count
  local amt = magic.restore(self, u, power)
  if u.count > before then
    self:emit({ t = "revived", stack = u.id, spell = spell, count = u.count - before, rose = before == 0 })
  elseif amt > 0 then
    self:emit({ t = "heal", stack = u.id, spell = spell, amount = amt, left = u.count })
  end
end

function Battle:extra_targets(a, t, ranged)
  if battle.hooks.extra_targets then return battle.hooks.extra_targets(self, a, t, ranged) end
  return {}
end

function Battle:blow(u, t)
  local extra = self:extra_targets(u, t, false)
  self:hit(u, t, false)
  for _, e in ipairs(extra) do if e.count > 0 then self:hit(u, e, false, true) end end
end

function Battle:volley(u, t)
  local extra = self:extra_targets(u, t, true)
  self:roll_block(t)
  if not has(u, "unlimited_shots") then u.shots = u.shots - 1 end
  self:hit(u, t, true)
  for _, e in ipairs(extra) do if e.count > 0 then self:hit(u, e, true, true) end end
end

-- Both strike at once (exe 0x56ef40 / 0x5695b0): each blow is rolled from the stacks as they
-- were before either lands; the deaths and the aftermath of both come after
function Battle:together(u, t, ranged, blow_u, blow_t)
  self.held = {}
  local pre_count, pre_wounds = t.count, t.wounds
  local mark = #self.events
  blow_u()
  local made_u = { table.unpack(self.events, mark + 1) }
  for i = #self.events, mark + 1, -1 do self.events[i] = nil end
  local made_t
  if not ranged and t.count <= 0 and not battle.dead_strike_back then
    made_t = { { t = "melee", stack = t.id, target = u.id, damage = 0, killed = 0, left = u.count } }
  else
    local after_count, after_wounds = t.count, t.wounds
    t.count, t.wounds = pre_count, pre_wounds
    mark = #self.events
    blow_t()
    made_t = { table.unpack(self.events, mark + 1) }
    for i = #self.events, mark + 1, -1 do self.events[i] = nil end
    t.count, t.wounds = after_count, after_wounds
  end
  local deaths = {}
  for _, e in ipairs(made_u) do if e.t == "die" then deaths[#deaths + 1] = e else self:emit(e) end end
  self:emit({ t = "together" })
  for _, e in ipairs(made_t) do if e.t == "die" then deaths[#deaths + 1] = e else self:emit(e) end end
  for _, e in ipairs(deaths) do self:emit(e) end
  local held = self.held
  self.held = nil
  for _, f in ipairs(held) do f() end
end

-- The melee exchange (exe 0x56ef40): without First Strike both strike at once; with it one
-- side strikes first and the other answers with what is left. A First Strike target strikes
-- first only when the attacker moved to attack. A block on either side puts the attacker first.
function Battle:melee_exchange(u, t, moved)
  local retaliates = self:can_retaliate(t, u)
  self:roll_block(t)
  local a_first = self:strikes_first(u, t) or u.blocking or t.blocking
  if retaliates and not a_first and self:strikes_first(t, u) and moved then
    t.retaliated = true
    self:blow(t, u)
    if u.count > 0 then self:roll_block(t); self:blow(u, t) end
  elseif retaliates and not a_first then
    t.retaliated = true
    self:together(u, t, false, function() self:blow(u, t) end, function() self:blow(t, u) end)
  else
    self:blow(u, t)
    if retaliates and self:can_retaliate(t, u) then t.retaliated = true; self:blow(t, u) end
  end
  for _ = 2, self:strikes(u, false) do
    if u.count > 0 and t.count > 0 then self:roll_block(t); self:blow(u, t) end
  end
  self:check_end()
end

-- Can u shoot now (it has shots and no enemy touches it)?
function Battle:can_shoot(u)
  if not ((u.shots > 0 or has(u, "unlimited_shots")) and u.shooter and not under(u, "forgetfulness")) then
    return false
  end
  for _, e in ipairs(self.units) do
    if e.count > 0 and self:side_of(e) ~= self:side_of(u) and grid.adjacent(u, e) then return false end
  end
  return true
end

-- Footprint positions reachable this turn from which u strikes t: { [key] = cost }
function Battle:attack_positions(u, t)
  local r, out = self:reach(u), {}
  if battle.in_reach(u.x, u.y, u.size, t, r) then out[grid.key(u.x, u.y)] = 0 end
  local cost = self:reachable(u)
  for k, c in pairs(cost) do
    local x, y = grid.xy(k)
    if battle.in_reach(x, y, u.size, t, r) then out[k] = c end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Actions of the current stack

local function fail(msg) return nil, msg end

function Battle:act_move(u, x, y)
  if self:reachable(u)[grid.key(x, y)] == nil then
    local nx, ny = self:step_toward(u, x, y)
    if not nx or (nx == u.x and ny == u.y) then return fail("out of reach") end
    x, y = nx, ny
  end
  if not self:do_move(u, x, y) then return fail("no path") end
  self:end_action(u)
  return true
end

function Battle:act_melee(u, t, x, y)
  if not self:may_strike(u, t) then return fail("not a target") end
  local positions = self:attack_positions(u, t)
  local pos
  if x then
    pos = grid.key(x, y)
    if positions[pos] == nil then return fail("cannot strike from there") end
  else
    pos = cheapest(positions, function() return true end)
  end
  if pos == nil then
    -- out of reach this turn: head for the nearest place it can be struck from
    local far = f32(self:move_budget(u) * 12)
    local cost = grid.reachable(self.field, self.units, self:mover(u, far))
    local r = self:reach(u)
    local best = cheapest(cost, function(k)
      local px, py = grid.xy(k)
      return battle.in_reach(px, py, u.size, t, r)
          and (not has(u, "flying") or self.field:fits(px, py, u.size))
          and not grid.overlaps(self.units, px, py, u.size, u.id)
    end)
    if not best then return fail("no way to the target") end
    return self:act_move(u, grid.xy(best))
  end
  local sx, sy = u.x, u.y
  local moved_cells = 0
  local px, py = grid.xy(pos)
  if px ~= u.x or py ~= u.y then
    moved_cells = self:reachable(u)[pos] or 0
    self:do_move(u, px, py)
  end
  u.facing = grid.facing(grid.delta2(u, t))
  self:melee_exchange(u, t, moved_cells * 100 >= 4)
  if under(u, "berserk") then u.effects.berserk = nil end   -- lasts until it has attacked
  -- Strike and Return: back to where it started
  if u.count > 0 and has(u, "strike_and_return") and (u.x ~= sx or u.y ~= sy)
      and not grid.overlaps(self.units, sx, sy, u.size, u.id) then
    self:emit({ t = "move", stack = u.id, path = { { sx, sy } }, from = { u.x, u.y }, flying = has(u, "flying") })
    u.x, u.y = sx, sy
  end
  self:end_action(u)
  return true
end

function Battle:act_shoot(u, t)
  if not self:may_strike(u, t) then return fail("not a target") end
  if not self:can_shoot(u) then return fail("cannot shoot") end
  u.facing = grid.facing(grid.delta2(u, t))
  -- a shooter shot at shoots back once a round, at once with the stack it has before the
  -- shot lands; only Ranged First Strike against one without it shoots first
  local shoots_back = t.count > 0 and not self:disabled(t) and not has(u, "no_retaliation")
      and (not t.retaliated or has(t, "unlimited_retaliation"))
  local back = shoots_back and self:can_shoot(t)
  if back and has(u, "ranged_first_strike") and not has(t, "ranged_first_strike") then
    self:volley(u, t)
    if t.count > 0 and not self:disabled(t) and self:can_shoot(t) then t.retaliated = true; self:volley(t, u) end
  elseif back then
    t.retaliated = true
    self:together(u, t, true, function() self:volley(u, t) end, function() self:volley(t, u) end)
  else
    self:volley(u, t)
  end
  for _ = 2, self:strikes(u, true) do
    if u.count > 0 and t.count > 0 and self:can_shoot(u) then self:volley(u, t) end
  end
  if under(u, "berserk") then u.effects.berserk = nil end
  self:check_end()
  self:end_action(u)
  return true
end

function Battle:can_wait(u) return not u.waited and not under(u, "berserk") end

-- What the current stack can do: { stack, move = { [key] = cost }, melee = { [id] = cheapest
-- key or false (only by walking further than this turn) }, shoot = { [id] = divisor },
-- wait, defend }
function Battle:options()
  local u = self:current()
  if self.finished or not u then return nil end
  local o = { stack = u.id, move = self:reachable(u), melee = {}, shoot = {},
              wait = self:can_wait(u), defend = true }
  local shooting = self:can_shoot(u)
  for _, t in ipairs(self.units) do
    if self:may_strike(u, t) then
      local pos = cheapest(self:attack_positions(u, t), function() return true end)
      o.melee[t.id] = pos or false
      if shooting then o.shoot[t.id] = damage.range_divisor(self.field, u, t) end
    end
  end
  return o
end

-- Perform a command for the current stack and return the events to play:
-- { type = "move", x, y } · { type = "melee", target, x?, y? } · { type = "shoot", target }
-- · { type = "wait" } · { type = "defend" }. A bad command changes nothing: nil, reason.
function Battle:act(cmd)
  local u = self:current()
  if self.finished or not u then return fail("the battle is over") end
  local ok, err
  local t = cmd.target and self.units[cmd.target]
  if cmd.type == "move" then
    ok, err = self:act_move(u, cmd.x, cmd.y)
  elseif cmd.type == "melee" then
    if not t then return fail("no target") end
    ok, err = self:act_melee(u, t, cmd.x, cmd.y)
  elseif cmd.type == "shoot" then
    if not t then return fail("no target") end
    ok, err = self:act_shoot(u, t)
  elseif cmd.type == "wait" then
    if not self:can_wait(u) then return fail("cannot wait") end
    u.waited = true
    self:emit({ t = "wait", stack = u.id })
    self:sort_order(self.order)
    self:check_morale()
    ok = true
  elseif cmd.type == "defend" then
    u.defending = true
    self:emit({ t = "defend", stack = u.id })
    self:end_action(u)
    ok = true
  else
    return fail("unknown command")
  end
  if not ok then return nil, err end
  self.log = self.log or {}
  self.log[#self.log + 1] = cmd
  local events = self.events
  self.events = {}
  return events
end

-- Events made before the first command (the first round and turn)
function Battle:take_events()
  local events = self.events
  self.events = {}
  return events
end

-- Expected result of a melee or shot, without rolls: { min, max, kills_min, kills_max,
-- back_min, back_max } (back: the strike back, when there is one)
function Battle:preview(cmd)
  local u = self:current()
  local t = cmd.target and self.units[cmd.target]
  if not u or not t then return nil end
  local ranged = cmd.type == "shoot"
  local moved = 0
  if not ranged and cmd.x then moved = num.trunc(f32(u.moved + (self:reachable(u)[grid.key(cmd.x, cmd.y)] or 0))) end
  local div = ranged and damage.range_divisor(self.field, u, t) or 1
  local lo, hi = damage.preview(u, t, { ranged = ranged, moved = moved }, div)
  local function kills(d)
    local hp = stats.hit_points(t)
    return math.min(t.count, (d + t.wounds) // hp)
  end
  local out = { min = lo, max = hi, kills_min = kills(lo), kills_max = kills(hi) }
  local back = ranged and (self:can_shoot(t) and not has(u, "no_retaliation")
      and (not t.retaliated or has(t, "unlimited_retaliation")))
    or (not ranged and t.count > 0 and not self:disabled(t) and not has(u, "no_retaliation")
      and (not t.retaliated or has(t, "unlimited_retaliation")))
  if back then
    local bdiv = ranged and damage.range_divisor(self.field, t, u) or 1
    out.back_min, out.back_max = damage.preview(t, u, { ranged = ranged }, bdiv)
  end
  return out
end

-- A short text of the whole state: the same on every machine for the same seed and commands
function Battle:checksum()
  local parts = { self.rng:hex(), self.round, self.finished and self.winner or "-" }
  for _, u in ipairs(self.units) do
    parts[#parts + 1] = string.format("%d:%d/%d@%d,%d s%d %s%s%s", u.id, u.count, u.wounds,
      u.x, u.y, u.shots or 0, u.acted and "a" or "", u.waited and "w" or "", u.retaliated and "r" or "")
  end
  for _, id in ipairs(self.order) do parts[#parts + 1] = "o" .. id end
  return table.concat(parts, " ")
end

return battle
