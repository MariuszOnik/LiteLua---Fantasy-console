-- Armies and ships on the province map (M2): the rules, without any drawing.
--
-- Places are province numbers of data/map.lua (0-based): land provinces and sea zones
-- (sea = true). An army stands in a land province or rides a fleet (army.fleet). A war
-- fleet sails up to FLEET_MOVES zones a turn and can carry one army: the army boards
-- from a coastal province next to the fleet's zone and lands in a coastal province next
-- to it. Entering a province held by another faction takes it when nobody defends it;
-- with defenders there is a battle (for now the bigger army wins, the H4 battle cart
-- comes later). Trade ships sail on their own between two ports of their faction.

local W = {}

W.FLEET_MOVES = 2

local function is_sea(st, p) return st.map.provinces[p + 1].sea == true end
local function neighbours(st, p) return st.map.provinces[p + 1].neighbours end

local function adjacent(st, a, b)
  for _, n in ipairs(neighbours(st, a)) do
    if n == b then return true end
  end
  return false
end

-- Zones a fleet reaches from zone z in up to `moves` steps: { zone = steps }
local function reach(st, z, moves)
  local seen, front = { [z] = 0 }, { z }
  for step = 1, moves do
    local nxt = {}
    for _, a in ipairs(front) do
      for _, b in ipairs(neighbours(st, a)) do
        if is_sea(st, b) and seen[b] == nil then
          seen[b] = step
          nxt[#nxt + 1] = b
        end
      end
    end
    front = nxt
  end
  seen[z] = nil
  return seen
end

-- Shortest list of zones from zone a to zone b (both included), or nil
local function sea_path(st, a, b)
  local prev, front = { [a] = a }, { a }
  while #front > 0 and prev[b] == nil do
    local nxt = {}
    for _, x in ipairs(front) do
      for _, y in ipairs(neighbours(st, x)) do
        if is_sea(st, y) and prev[y] == nil then
          prev[y] = x
          nxt[#nxt + 1] = y
        end
      end
    end
    front = nxt
  end
  if prev[b] == nil then return nil end
  local path, x = { b }, b
  while x ~= a do
    x = prev[x]
    table.insert(path, 1, x)
  end
  return path
end

local function coast_zones(st, p)
  local out = {}
  for _, n in ipairs(neighbours(st, p)) do
    if is_sea(st, n) then out[#out + 1] = n end
  end
  return out
end

local function log(st, msg)
  table.insert(st.log, 1, msg)
  if #st.log > 4 then st.log[5] = nil end
end

-- A new game on map m: every faction gets an army in its two first provinces and a war
-- fleet off its first port; factions with two ports on different zones a trade ship.
-- player: the faction the player leads.
function W.new(m, player)
  local st = { map = m, player = player, turn = 1, armies = {}, fleets = {}, log = {} }
  local nf = #m.factions
  for f = 0, nf - 1 do
    local own, ports = {}, {}
    for i, pr in ipairs(m.provinces) do
      if not pr.sea and pr.owner == f then
        own[#own + 1] = i - 1
        if #coast_zones(st, i - 1) > 0 then ports[#ports + 1] = i - 1 end
      end
    end
    for k = 1, math.min(2, #own) do
      st.armies[#st.armies + 1] = { owner = f, at = own[k], size = 10 + (own[k] * 7) % 21 }
    end
    if #ports > 0 then
      st.fleets[#st.fleets + 1] = { owner = f, at = coast_zones(st, ports[1])[1] }
    end
    -- a trade route between the first port and the farthest other one by sea
    local best
    for k = 2, #ports do
      local path = sea_path(st, coast_zones(st, ports[1])[1], coast_zones(st, ports[k])[1])
      if path and #path > 1 and (not best or #path > #best.path) then
        best = { from = ports[1], to = ports[k], path = path }
      end
    end
    if best then
      st.fleets[#st.fleets + 1] = { owner = f, at = best.path[1], trade = best, step = 1, dir = 1 }
    end
  end
  return st
end

function W.armies_at(st, p)
  local out = {}
  for _, a in ipairs(st.armies) do
    if a.at == p and not a.fleet then out[#out + 1] = a end
  end
  return out
end

function W.fleets_at(st, z)
  local out = {}
  for _, f in ipairs(st.fleets) do
    if f.at == z then out[#out + 1] = f end
  end
  return out
end

-- Where a unit of the player can go now: { place = "move" | "board" | "land" | "sail" }
function W.targets(st, unit)
  local out = {}
  if unit.owner ~= st.player or unit.moved or unit.trade then return out end
  if unit.size then                                  -- an army
    if unit.fleet then return out end
    for _, n in ipairs(neighbours(st, unit.at)) do
      if not is_sea(st, n) then
        out[n] = "move"
      else
        for _, f in ipairs(W.fleets_at(st, n)) do
          if f.owner == st.player and not f.trade and not f.cargo then out[n] = "board" end
        end
      end
    end
  else                                               -- a war fleet
    for z in pairs(reach(st, unit.at, W.FLEET_MOVES)) do out[z] = "sail" end
    if unit.cargo and not unit.cargo.moved then      -- boarded this turn: lands next turn
      for _, n in ipairs(neighbours(st, unit.at)) do
        if not is_sea(st, n) then out[n] = "land" end
      end
    end
  end
  return out
end

-- An army comes into land province p (on foot or from a ship)
local function enter(st, army, p)
  local pr = st.map.provinces[p + 1]
  local foes = {}
  for _, a in ipairs(W.armies_at(st, p)) do
    if a.owner ~= army.owner then foes[#foes + 1] = a end
  end
  army.at, army.moved = p, true
  if #foes > 0 then
    local strength = 0
    for _, a in ipairs(foes) do strength = strength + a.size end
    local f = st.map.factions
    if army.size >= strength then
      for _, a in ipairs(foes) do
        for i, b in ipairs(st.armies) do
          if b == a then table.remove(st.armies, i) break end
        end
      end
      army.size = math.max(1, army.size - strength // 2)
      log(st, ("%s won the battle at %s"):format(f[army.owner + 1].name, pr.name))
    else
      for i, b in ipairs(st.armies) do
        if b == army then table.remove(st.armies, i) break end
      end
      log(st, ("%s lost the battle at %s"):format(f[army.owner + 1].name, pr.name))
      return "lost"
    end
  end
  if pr.owner ~= army.owner then
    pr.owner = army.owner
    log(st, ("%s took %s"):format(st.map.factions[army.owner + 1].name, pr.name))
    return "taken"
  end
  return "moved"
end

-- Carries out what W.targets allowed; returns the kind and, when a province changed
-- hands, "taken" (the caller recolours it)
function W.act(st, unit, place)
  local kind = W.targets(st, unit)[place]
  if not kind then return nil end
  if kind == "move" then
    return kind, enter(st, unit, place)
  elseif kind == "board" then
    for _, f in ipairs(W.fleets_at(st, place)) do
      if f.owner == st.player and not f.trade and not f.cargo then
        f.cargo, unit.fleet, unit.moved = unit, f, true
        unit.at = place
        break
      end
    end
  elseif kind == "sail" then
    unit.at, unit.moved = place, true
    if unit.cargo then unit.cargo.at = place end
  elseif kind == "land" then
    local army = unit.cargo
    unit.cargo, army.fleet = nil, nil
    unit.moved = true
    return kind, enter(st, army, place)
  end
  return kind
end

-- Next turn: trade ships sail one zone along their route (back and forth), every unit
-- may act again
function W.end_turn(st)
  for _, f in ipairs(st.fleets) do
    if f.trade then
      local path = f.trade.path
      if f.step + f.dir < 1 or f.step + f.dir > #path then f.dir = -f.dir end
      f.step = f.step + f.dir
      f.at = path[f.step]
    end
    f.moved = false
  end
  for _, a in ipairs(st.armies) do a.moved = false end
  st.turn = st.turn + 1
end

return W
