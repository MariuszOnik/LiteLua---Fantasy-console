-- Dungeon floor: rooms and corridors, field of view, monsters on the map.
-- No drawing here; main.lua draws D.map / D.seen / D.monsters.
local ENEMIES = require("enemies")
local G = require("gear")

local D = {}

D.W, D.H = 42, 22       -- one screen of 6x8 characters (2 rows for the HUD)
local VIEW = 7          -- how far the player sees

-- Tiles: "#" wall, "." floor, ">" stairs, " " rock (never seen)
local function new_grid(fill)
  local g = {}
  for y = 1, D.H do
    local row = {}
    for x = 1, D.W do row[x] = fill end
    g[y] = row
  end
  return g
end

local function carve(x1, y1, x2, y2)
  for y = math.min(y1, y2), math.max(y1, y2) do
    for x = math.min(x1, x2), math.max(x1, x2) do D.map[y][x] = "." end
  end
end

local function overlaps(r, rooms)
  for _, o in ipairs(rooms) do
    if r.x - 1 <= o.x + o.w and o.x - 1 <= r.x + r.w
       and r.y - 1 <= o.y + o.h and o.y - 1 <= r.y + r.h then
      return true
    end
  end
  return false
end

local function center(r) return r.x + r.w // 2, r.y + r.h // 2 end

-- Random free floor tile in room r
local function spot(r)
  for _ = 1, 50 do
    local x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
    if D.map[y][x] == "." and not D.monster_at(x, y) and not D.item_at(x, y)
       and not (x == D.px and y == D.py) then
      return x, y
    end
  end
end

function D.monster_at(x, y)
  for _, m in ipairs(D.monsters) do
    if m.x == x and m.y == y then return m end
  end
end

local GLYPH = { weapon = ")", armor = "[", shield = "]", charm = '"', potion = "!", scroll = "?" }
local GLYPH_COL = { weapon = 0xc0c8e0, armor = 0xc0c8e0, shield = 0xc0c8e0, charm = 0xffd040,
                    potion = 0xff5070, scroll = 0xf0e0b0 }

-- Puts item id on the map at x, y
function D.add_item(x, y, id)
  local slot = G.item(id).slot
  D.items[#D.items + 1] = { x = x, y = y, id = id, glyph = GLYPH[slot], col = GLYPH_COL[slot] }
end

function D.remove_item(it)
  for i, o in ipairs(D.items) do
    if o == it then table.remove(D.items, i) return end
  end
end

function D.item_at(x, y)
  for _, it in ipairs(D.items) do
    if it.x == x and it.y == y then return it end
  end
end

-- Builds floor number n (1 = top). Returns nothing; state is in D.
function D.generate(n)
  local spec = ENEMIES.floors[n]
  D.floor, D.last = n, n == #ENEMIES.floors
  D.map, D.seen, D.vis = new_grid("#"), new_grid(false), new_grid(false)
  D.monsters, D.items = {}, {}

  local rooms = {}
  for _ = 1, 200 do
    if #rooms >= 9 then break end
    local w, h = math.random(4, 9), math.random(3, 5)
    local r = { x = math.random(2, D.W - w - 1), y = math.random(2, D.H - h - 1), w = w, h = h }
    if not overlaps(r, rooms) then rooms[#rooms + 1] = r end
  end
  if #rooms < 4 then return D.generate(n) end -- rare: try again
  -- left to right, so corridors do not cross the whole map
  table.sort(rooms, function(a, b) return a.x < b.x end)
  for i, r in ipairs(rooms) do
    carve(r.x, r.y, r.x + r.w - 1, r.y + r.h - 1)
    if i > 1 then
      local x1, y1 = center(rooms[i - 1])
      local x2, y2 = center(r)
      if math.random(2) == 1 then
        carve(x1, y1, x2, y1); carve(x2, y1, x2, y2)
      else
        carve(x1, y1, x1, y2); carve(x1, y2, x2, y2)
      end
    end
  end
  D.rooms = rooms

  D.px, D.py = center(rooms[1])
  local last = rooms[#rooms]
  local sx, sy = center(last)
  if D.last then
    -- the boss waits in the last room instead of stairs
    D.monsters[#D.monsters + 1] = { x = sx, y = sy, group = spec.boss, boss = true,
      glyph = ENEMIES[spec.boss[1]].glyph, col = ENEMIES[spec.boss[1]].color, state = "guard" }
  else
    D.map[sy][sx] = ">"
  end

  -- monsters in the rooms after the first one
  for k = 1, spec.monsters do
    local r = rooms[2 + (k - 1) % (#rooms - 1)]
    local x, y = spot(r)
    if x then
      local group = spec.groups[math.random(#spec.groups)]
      local def = ENEMIES[group[1]]
      -- most sleep, the rest wander; none knows where the player is yet
      D.monsters[#D.monsters + 1] = { x = x, y = y, group = group,
        glyph = #group > 1 and def.glyph:upper() or def.glyph, col = def.color,
        state = math.random(100) <= 60 and "sleep" or "wander", slow = def.slow, lost = 0 }
    end
  end
  -- treasures anywhere but the first room
  for _ = 1, spec.items or 0 do
    local x, y = spot(rooms[math.random(2, #rooms)])
    if x then D.add_item(x, y, G.roll_loot(n)) end
  end
  D.update_view()
end

-- Line of sight (Bresenham): walls block, the end tile itself may be a wall
local function clear_line(x0, y0, x1, y1)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    if x0 == x1 and y0 == y1 then return true end
    if D.map[y0][x0] == "#" and not (x0 == D.px and y0 == D.py) then return false end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

function D.update_view()
  for y = 1, D.H do
    local row = D.vis[y]
    for x = 1, D.W do row[x] = false end
  end
  for y = math.max(1, D.py - VIEW), math.min(D.H, D.py + VIEW) do
    for x = math.max(1, D.px - VIEW), math.min(D.W, D.px + VIEW) do
      local dx, dy = x - D.px, y - D.py
      if dx * dx + dy * dy <= VIEW * VIEW + VIEW and clear_line(D.px, D.py, x, y) then
        D.vis[y][x], D.seen[y][x] = true, true
      end
    end
  end
end

function D.walkable(x, y)
  return x >= 1 and y >= 1 and x <= D.W and y <= D.H and D.map[y][x] ~= "#"
end

-- Player tries to step by dx, dy. Returns "fight", m (bumped a monster),
-- "stairs", "item", it (stands on an item), "moved" or nil (wall).
function D.step(dx, dy)
  local x, y = D.px + dx, D.py + dy
  local m = D.monster_at(x, y)
  if m then return "fight", m end
  if not D.walkable(x, y) then return nil end
  D.px, D.py = x, y
  D.update_view()
  if D.map[y][x] == ">" then return "stairs" end
  local it = D.item_at(x, y)
  if it then return "item", it end
  return "moved"
end

-- Monster states: "sleep" (notices the player only right next to it, or
-- by chance 2 steps away), "wander" (walks around, notices the player in
-- sight up to NOTICE steps away), "hunt" (walks to the player; after LOSE
-- turns without seeing them it wanders again), "guard" (the boss: waits).
local NOTICE, LOSE = 4, 6
D.noticed = {}  -- monsters that noticed the player this turn (for the log)

local function step_to(m, tx, ty)
  local dx, dy = tx - m.x, ty - m.y
  local sx, sy = (dx > 0 and 1 or dx < 0 and -1 or 0), (dy > 0 and 1 or dy < 0 and -1 or 0)
  local tries = math.abs(dx) >= math.abs(dy) and { { sx, 0 }, { 0, sy } } or { { 0, sy }, { sx, 0 } }
  for _, t in ipairs(tries) do
    local nx, ny = m.x + t[1], m.y + t[2]
    if (t[1] ~= 0 or t[2] ~= 0) and D.walkable(nx, ny) and not D.monster_at(nx, ny)
       and not (nx == D.px and ny == D.py) then
      m.x, m.y = nx, ny
      return true
    end
  end
end

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Monsters act after each player turn. Returns a monster that reached the
-- player (a fight starts), or nil.
function D.monsters_turn()
  D.noticed = {}
  D.turn = (D.turn or 0) + 1
  for _, m in ipairs(D.monsters) do
    local dx, dy = D.px - m.x, D.py - m.y
    local dist = math.max(math.abs(dx), math.abs(dy))
    local sees = D.vis[m.y][m.x]          -- sight works both ways
    if m.state == "guard" then
      if dist == 1 and dx * dy == 0 then return m end
    else
      if m.state ~= "hunt" and sees then
        local wakes = dist <= 1
          or (m.state == "wander" and dist <= NOTICE)
          or (m.state == "sleep" and dist <= 2 and math.random(100) <= 30)
        if wakes then
          m.state, m.lost = "hunt", 0
          D.noticed[#D.noticed + 1] = m
        end
      end
      if m.state == "hunt" then
        if sees then m.lost = 0 else m.lost = m.lost + 1 end
        if m.lost > LOSE then m.state = "wander" end
      end
      if not (m.slow and D.turn % 2 == 0) then
        if m.state == "hunt" then
          if math.abs(dx) + math.abs(dy) == 1 then return m end
          step_to(m, D.px, D.py)
        elseif m.state == "wander" and math.random(100) <= 50 then
          local d = DIRS4[math.random(4)]
          step_to(m, m.x + d[1], m.y + d[2])
        end
      end
    end
  end
end

function D.remove_monster(m)
  for i, o in ipairs(D.monsters) do
    if o == m then table.remove(D.monsters, i) return end
  end
end

function D.floors_total() return #ENEMIES.floors end

-- Enemy HP grows with depth
function D.hp_scale() return 1 + 0.12 * (D.floor - 1) end

return D
