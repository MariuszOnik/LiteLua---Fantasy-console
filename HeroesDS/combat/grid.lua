-- HeroesDS combat: the battlefield grid (MECHANICS.md 1, 2).
--
-- Rules ported from Anbrose/homm4-mac (MIT, (c) 2026 Anton Ozhigin): Battle.swift and
-- CombatActor.swift (Battlefield), which give the heroes4.exe addresses.
--
-- A square grid of 102 x 102 cells drawn as 32 x 16 diamonds; x runs down-left on screen,
-- y down-right. Only the cells whose centres fall inside the 1180 x 1024 scene are on the
-- field. A stack stands on size x size cells, (x, y) being its top corner.
--
-- Centres are half-integers, so distances and directions are computed in doubled
-- coordinates with integers; the path costs are floats (1 a step, 1.5 a diagonal) as in
-- the original, kept to 32-bit floats by num.f32.

local num = require("combat.num")
local f32 = num.f32

local grid = {}
local N = 102

-- Called now and then in long computations (path search, the computer's choices). Does
-- nothing; a screen running the computer's turn in a coroutine sets it to yield when its
-- time slice is over, so the display keeps moving (H11).
function grid.tick() end
grid.SIZE = N
grid.SCENE_W, grid.SCENE_H = 1180, 1024

function grid.key(x, y) return x * N + y end
function grid.xy(k) return k // N, k % N end

-- Scene point of a world point in cell units
function grid.screen(x, y)
  return (y - x) * 16 + 590, (x + y) * 8 + 512 - 8 * N
end

-- World point (cell units) under a scene point
function grid.world(sx, sy)
  local u = (sx - 590) / 16
  local v = (sy - 512 + 8 * N) / 8
  return (v - u) / 2, (v + u) / 2
end

-- Is the cell on the field: inside the grid, its centre inside the scene with a margin
-- (integer form of the scene position of the cell centre)
function grid.on_field(x, y)
  if x < 0 or y < 0 or x >= N or y >= N then return false end
  local sx = (y - x) * 16 + 590
  local sy = (x + y + 1) * 8 + 512 - 8 * N
  return sx > 24 and sx < 1180 - 24 and sy > 40 and sy < 1024 - 16
end
local on_field = grid.on_field

---------------------------------------------------------------------------------------------
-- Field: obstacles and spell-made ground

local Field = {}
Field.__index = Field

function grid.new_field()
  return setmetatable({
    blocked = {},     -- [key] = true: obstacle cells that block movement and shots
    obstacles = {},   -- { name, x, y, w, h, blocks }
    smoke = {},       -- [key] = true: Smoke clouds (shots through them count as obstructed)
    quicksand = {},   -- [key] = true
    moat = {},        -- [key] = true (sieges)
  }, Field)
end

function Field:add_obstacle(name, x, y, w, h, blocks)
  self.obstacles[#self.obstacles + 1] = { name = name, x = x, y = y, w = w, h = h, blocks = blocks }
  if blocks then
    for i = 0, w - 1 do
      for j = 0, h - 1 do self.blocked[(x + i) * N + y + j] = true end
    end
  end
end

function Field:is_open(x, y)
  return on_field(x, y) and not self.blocked[x * N + y]
end

-- Is a size x size footprint at (x, y) on the field and free of obstacles?
function Field:fits(x, y, s)
  for i = 0, s - 1 do
    for j = 0, s - 1 do
      if not self:is_open(x + i, y + j) then return false end
    end
  end
  return true
end

-- Does the footprint touch quicksand?
function Field:on_quicksand(x, y, s)
  if next(self.quicksand) == nil then return false end
  for i = 0, s - 1 do
    for j = 0, s - 1 do
      if self.quicksand[(x + i) * N + y + j] then return true end
    end
  end
  return false
end

-- Does the straight line between two world points pass one of `cells`? Sampled twice per
-- cell along the longer axis, in floats as the original.
function grid.crosses(cells, ax, ay, bx, by)
  local dx, dy = f32(bx - ax), f32(by - ay)
  local d = math.max(math.abs(dx), math.abs(dy))
  local steps = math.max(1, num.trunc(d * 2))
  for k = 1, steps - 1 do
    local t = f32(k / steps)
    local x = math.floor(f32(ax + f32(dx * t)))
    local y = math.floor(f32(ay + f32(dy * t)))
    if x >= 0 and y >= 0 and x < N and y < N and cells[x * N + y] then return true end
  end
  return false
end

-- Is the line between two world points obstructed by an obstacle (not smoke)?
function Field:obstructed(ax, ay, bx, by)
  return grid.crosses(self.blocked, ax, ay, bx, by)
end

---------------------------------------------------------------------------------------------
-- Stacks on the grid: anything with x, y, size, id, count (alive while count > 0)

function grid.centre(u)
  return u.x + u.size / 2, u.y + u.size / 2
end

function grid.overlaps(stacks, x, y, s, except_id)
  for i = 1, #stacks do
    local u = stacks[i]
    if u.count > 0 and u.id ~= except_id
        and x < u.x + u.size and u.x < x + s and y < u.y + u.size and u.y < y + s then
      return true
    end
  end
  return false
end

-- Do two footprints touch (share an edge or a corner)?
function grid.touches(x, y, s, b)
  return x <= b.x + b.size and b.x <= x + s and y <= b.y + b.size and b.y <= y + s
end
function grid.adjacent(a, b) return grid.touches(a.x, a.y, a.size, b) end

-- Centre difference b - a in doubled coordinates (integers)
function grid.delta2(a, b)
  return (2 * b.x + b.size) - (2 * a.x + a.size), (2 * b.y + b.size) - (2 * a.y + a.size)
end

-- Squared distance between centres, x 4 (integer); distance >= d cells <=> dist4 >= 4 d^2
function grid.dist4(a, b)
  local dx, dy = grid.delta2(a, b)
  return dx * dx + dy * dy
end

-- Distance between centres in cells (float)
function grid.distance(a, b)
  return f32(math.sqrt(grid.dist4(a, b)) / 2)
end

-- The nearest of 8 directions to a vector, as a step (-1..1, -1..1). The 22.5-degree
-- sector borders tested exactly: |dy| < (sqrt 2 - 1)|dx| <=> (|dx| + |dy|)^2 < 2 dx^2
function grid.dir8(dx, dy)
  local ax, ay = math.abs(dx), math.abs(dy)
  if ax == 0 and ay == 0 then return 1, 0 end
  local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
  local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
  local s2 = (ax + ay) * (ax + ay)
  if s2 < 2 * ax * ax then return sx, 0 end
  if s2 < 2 * ay * ay then return 0, sy end
  return sx, sy
end

-- Facing (sprite direction) for a world vector. The screen shows x down-left and y
-- down-right, so +x is sw, +y is se. (Visual only: the exe truncates degrees, which moves
-- the sector borders by under a degree.)
local FACING = {
  [-1] = { [-1] = "n", [0] = "ne", [1] = "e" },
  [0] = { [-1] = "nw", [0] = "ne", [1] = "se" },
  [1] = { [-1] = "w", [0] = "sw", [1] = "s" },
}
function grid.facing(dx, dy)
  local sx, sy = grid.dir8(dx, dy)
  if dx == 0 and dy == 0 then return "ne" end
  return FACING[sx][sy]
end

---------------------------------------------------------------------------------------------
-- Movement (MECHANICS.md 2): Dijkstra over footprint positions

local STEPS = {
  { 1, 0, 1.0 }, { -1, 0, 1.0 }, { 0, 1, 1.0 }, { 0, -1, 1.0 },
  { 1, 1, 1.5 }, { -1, -1, 1.5 }, { 1, -1, 1.5 }, { -1, 1, 1.5 },
}
local EPS = f32(0.001)

-- Binary heap of (cost, key), keys break no ties: the same code gives the same order on
-- every machine.
local function heap_push(h, c, k)
  local n = #h + 1
  h[n] = { c, k }
  while n > 1 do
    local p = n // 2
    if h[p][1] <= h[n][1] then break end
    h[p], h[n] = h[n], h[p]
    n = p
  end
end

local function heap_pop(h)
  local top = h[1]
  local last = table.remove(h)
  local n = #h
  if n > 0 then
    h[1] = last
    local i = 1
    while true do
      local l, r, m = 2 * i, 2 * i + 1, i
      if l <= n and h[l][1] < h[m][1] then m = l end
      if r <= n and h[r][1] < h[m][1] then m = r end
      if m == i then break end
      h[i], h[m] = h[m], h[i]
      i = m
    end
  end
  return top[1], top[2]
end

-- Where a mover can go this turn.
-- m = { id, x, y, size, budget (cells, float), flies, teleport,
--       zoc = { enemy stacks that hold it }, zoc_cost (cells), sand_cost, moat_cost (or nil) }
-- Returns cost[key] (cells, float) of each footprint position it can stop at, and the
-- parent[key] map of the cheapest paths (nil for teleport).
function grid.reachable(field, stacks, m)
  local size = m.size
  if m.teleport then
    local out = {}
    for x = 0, N - 1 do
      for y = 0, N - 1 do
        if field:fits(x, y, size) and not grid.overlaps(stacks, x, y, size, m.id) then
          local dx, dy = x - m.x, y - m.y
          out[x * N + y] = f32(math.sqrt(dx * dx + dy * dy))
        end
      end
    end
    return out
  end

  local flies = m.flies
  local limit = f32(m.budget + EPS)
  -- where the footprint may stand (lazily, per search)
  local blocked_memo, fits_memo = {}, {}
  local function blocked(x, y)
    local k = x * N + y
    local b = blocked_memo[k]
    if b == nil then
      if flies then b = x + size > N or y + size > N
      else b = not (field:fits(x, y, size) and not grid.overlaps(stacks, x, y, size, m.id)) end
      blocked_memo[k] = b
    end
    return b
  end
  local function fits(x, y)
    local k = x * N + y
    local f = fits_memo[k]
    if f == nil then f = field:fits(x, y, size); fits_memo[k] = f end
    return f
  end

  local zoc = m.zoc or {}
  local zoc_cost = m.zoc_cost or 0
  local sand, moat = m.sand_cost, m.moat_cost
  local dist, parent, out = {}, {}, {}
  local start = m.x * N + m.y
  dist[start] = 0
  local heap = { { 0, start } }
  local ticks = 0
  while #heap > 0 do
    ticks = ticks + 1
    if ticks & 31 == 0 then grid.tick() end
    local c, k = heap_pop(heap)
    if c <= dist[k] then
      out[k] = c
      local x, y = k // N, k % N
      -- the steps that leave the cell freely, when an enemy holds it: straight towards or
      -- away from each enemy touching the footprint
      local free
      for i = 1, #zoc do
        local e = zoc[i]
        if e.count > 0 and grid.touches(x, y, size, e) then
          local fx, fy = grid.dir8((2 * e.x + e.size) - (2 * x + size), (2 * e.y + e.size) - (2 * y + size))
          free = free or {}
          free[#free + 1] = fx * 3 + fy
          free[#free + 1] = -fx * 3 - fy
        end
      end
      for s = 1, 8 do
        local st = STEPS[s]
        local sdx, sdy, cost = st[1], st[2], st[3]
        local nx, ny = x + sdx, y + sdy
        if nx >= 0 and ny >= 0 and nx < N and ny < N then
          local nk = nx * N + ny
          local nc = f32(c + cost)
          if moat and field.moat[nk] then nc = f32(c + math.max(cost, moat)) end
          if sand and field:on_quicksand(nx, ny, size) then nc = f32(c + math.max(cost, sand)) end
          if free then
            local code, ok = sdx * 3 + sdy, false
            for i = 1, #free do if free[i] == code then ok = true break end end
            if not ok then nc = f32(nc + f32(zoc_cost * cost)) end
          end
          -- a diagonal step of a walker needs one of the two straight neighbours open
          local pass = nc <= limit and not blocked(nx, ny)
          if pass and cost > 1 and not flies then
            pass = (x + sdx < N and fits(x + sdx, y)) or (y + sdy < N and fits(x, y + sdy))
          end
          if pass and (dist[nk] == nil or nc < dist[nk]) then
            dist[nk] = nc
            parent[nk] = k
            heap_push(heap, nc, nk)
          end
        end
      end
    end
  end
  if flies then   -- a flyer passes over everything but lands only on a free place
    for k in pairs(out) do
      local x, y = k // N, k % N
      if not (field:fits(x, y, size) and not grid.overlaps(stacks, x, y, size, m.id)) then out[k] = nil end
    end
  end
  return out, parent
end

-- The path to (gx, gy) as a list of { x, y } (without the start), or nil when out of reach.
function grid.path(field, stacks, m, gx, gy)
  local cost, parent = grid.reachable(field, stacks, m)
  local goal = gx * N + gy
  if cost[goal] == nil then return nil end
  if m.teleport then return { { gx, gy } } end
  if m.flies then   -- a flight goes straight over everything
    local n = math.max(math.abs(gx - m.x), math.abs(gy - m.y))
    local line = {}
    for i = 1, n do
      local f = f32(i / n)
      line[i] = { m.x + num.round(f32((gx - m.x) * f)), m.y + num.round(f32((gy - m.y) * f)) }
    end
    return line
  end
  local out, k, start = {}, goal, m.x * N + m.y
  while k ~= start do
    table.insert(out, 1, { k // N, k % N })
    k = parent[k]
    if k == nil then return nil end
  end
  return out
end

return grid
