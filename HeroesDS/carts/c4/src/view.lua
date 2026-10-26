-- HeroesDS C4b: the battlefield on the bottom screen with stand-in graphics (H6, H8).
-- The whole H4 scene (1180x1024) at 3/16 is 221x192 px, centred; a grid cell is a 6x3 px
-- diamond, a stack a coloured diamond over its footprint with its count.

local grid = require("combat.grid")

local view = {}

local K = 3 / 16
view.W = grid.SCENE_W * K // 1          -- 221
view.OX = (256 - view.W) // 2           -- 17: room for buttons at the sides
view.OY = 0

-- Screen point of a world point (cell units)
function view.to_screen(wx, wy)
  local sx, sy = grid.screen(wx, wy)
  return view.OX + sx * K, view.OY + sy * K
end

-- World point (cell units) under a screen point
function view.to_world(px, py)
  return grid.world((px - view.OX) / K, (py - view.OY) / K)
end

-- The four corners of a footprint: top, right, bottom, left
function view.corners(x, y, s)
  local tx, ty = view.to_screen(x, y)
  local rx, ry = view.to_screen(x, y + s)
  local bx, by = view.to_screen(x + s, y + s)
  local lx, ly = view.to_screen(x + s, y)
  return tx, ty, rx, ry, bx, by, lx, ly
end

local function diamond(x, y, s, col)
  local tx, ty, rx, ry, bx, by, lx, ly = view.corners(x, y, s)
  trifill(tx, ty, rx, ry, bx, by, col)
  trifill(tx, ty, bx, by, lx, ly, col)
end

local function outline(x, y, s, col)
  local tx, ty, rx, ry, bx, by, lx, ly = view.corners(x, y, s)
  line(tx, ty, rx, ry, col)
  line(rx, ry, bx, by, col)
  line(bx, by, lx, ly, col)
  line(lx, ly, tx, ty, col)
end
view.outline = outline

-- Colours: side 0 blue, side 1 red; heroes lighter
local COLOR = { [0] = { 9, 10 }, [1] = { 2, 3 } }

function view.stack_color(u)
  return COLOR[u.side][u.is_hero and 2 or 1]
end

-- Dots over the places a stack can move to (one place in 9, made once per turn)
function view.move_dots(cost, size)
  local dots = {}
  for k in pairs(cost) do
    local x, y = grid.xy(k)
    if x % 3 == 0 and y % 3 == 0 then
      local px, py = view.to_screen(x + size / 2, y + size / 2)
      dots[#dots + 1] = px // 1
      dots[#dots + 1] = py // 1
    end
  end
  return dots
end

-- The field: the scene, the move dots, the stacks (farther first), the active one and the
-- selection on top. st = { units, active (stack), dots, path, target, blink }
function view.draw_field(st)
  rectfill(view.OX, view.OY, view.W, 192, 7)
  local dots = st.dots
  if dots then
    for i = 1, #dots, 2 do pset(dots[i], dots[i + 1], 5) end
  end
  local list = {}
  for _, u in ipairs(st.units) do if u.count > 0 then list[#list + 1] = u end end
  table.sort(list, function(a, b)
    local da, db = a.x + a.y + a.size, b.x + b.y + b.size
    if da ~= db then return da < db end
    return a.id < b.id
  end)
  for _, u in ipairs(list) do
    local col = view.stack_color(u)
    if st.target == u and st.blink then col = 12 end
    diamond(u.x, u.y, u.size, col)
  end
  if st.path then
    local u = st.active
    local px, py = view.to_screen(u.x + u.size / 2, u.y + u.size / 2)
    for _, p in ipairs(st.path) do
      local qx, qy = view.to_screen(p[1] + u.size / 2, p[2] + u.size / 2)
      line(px, py, qx, qy, 4)
      px, py = qx, qy
    end
  end
  if st.ghost then outline(st.ghost[1], st.ghost[2], st.active.size, 4) end
  if st.active and st.blink then outline(st.active.x, st.active.y, st.active.size, 12) end
  for _, u in ipairs(list) do
    local cx, cy = view.to_screen(u.x + u.size / 2, u.y + u.size / 2)
    local s = tostring(u.count)
    text(s, cx - #s * 3, cy - 4, u.is_hero and 0 or 12)
  end
end

-- The stack under a screen point (a cell of slack around small ones), or nil
function view.stack_at(units, px, py)
  local wx, wy = view.to_world(px, py)
  local best, bd
  for _, u in ipairs(units) do
    if u.count > 0 then
      local cx, cy = u.x + u.size / 2, u.y + u.size / 2
      local r = u.size / 2 + 1
      local dx, dy = wx - cx, wy - cy
      if math.abs(dx) <= r and math.abs(dy) <= r then
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = u, d end
      end
    end
  end
  return best
end

return view
