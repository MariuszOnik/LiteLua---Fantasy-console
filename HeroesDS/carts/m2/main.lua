-- HeroesDS M2: the political map of an invented land (data: HeroesDS/tools/make_m2.py)
-- with armies and ships (rules: src/war.lua).
-- Bottom screen: the map; drag the stylus or use the d-pad to scroll. Tap one of your
-- armies or war fleets, then a marked place: an army walks to a neighbouring province
-- or boards your fleet next to its port; a fleet sails up to two sea zones or lands
-- the army it carries. Tap a province or sea zone to see it. Y: end the turn (trade
-- ships sail on), A: paper map / relief, X: flat map / 3D view (LiteLua D60; L/R turn,
-- B zoom). Top screen: the turn, the selection, news.
-- Sea zones (provinces with sea = true, no owner) are where fleets sail: their
-- neighbours are the next zones and the coastal provinces (ports).
--
-- The ground is an isogrid per view: its frames are light grain with the ink of the
-- borders in them, all colour comes from the corners (paper: parchment mixed with the
-- owner; relief: the terrain, lit from the right as in the H4 editor). Both views come
-- coloured from make_m2.py; a province is recoloured here when its owner changes or
-- it is selected (paper view).

local M = dofile("data/map.lua")

local HW, HH = 8, 4             -- half a diamond on screen
local ROWS, COLS = M.rows, M.cols
local W1 = COLS + 1             -- corners per row
local RELIEF_SCALE = 0.08       -- pixels up per height unit (0..255) in the relief view
local PARCHMENT = { 226, 210, 170 }
local PAPER_SEA = { 170, 195, 205 }
local SEA, MOUNT = 0, 4         -- terrain numbers (M.terrains, 0-based)

local paper_grid, relief_grid
local relief = false            -- the view: paper map or relief
local view3d = false            -- X: the 3D view (camera3d) instead of the flat map
local t3x, t3y, yaw3 = 0, 0, 0  -- 3D: the tile the camera looks at, its turn
local ZOOMS = { 10, 16, 26 }    -- 3D: camera distances in tiles (B)
local zoom3 = 2
local PITCH3 = 50
local HSCALE3 = 0.012           -- 3D relief: tiles up per height unit (0..255)
local BACK = 0x101018           -- background and fog
local UNDER = { paper = 0xb4a078, relief = 0x5a6440 }  -- fills the DS's cracks
local selected                  -- province number (0-based) or nil
local camx, camy
local DRAG_START = 5            -- pixels the stylus moves before a touch scrolls
local press_x, press_y          -- where the current touch came down
local drag_x, drag_y, drag_moved
local recolor_ms = 0

local function rgb(c)
  return { c >> 16 & 255, c >> 8 & 255, c & 255 }
end

local NATURE, FACTION = {}, {}
for i, c in ipairs(M.nature) do NATURE[i - 1] = rgb(c) end
for i, f in ipairs(M.factions) do FACTION[i - 1] = rgb(f.color) end


local CELLS_OF = {}             -- province -> its cells
for k = 0, ROWS * COLS - 1 do
  local p = M.province[k + 1]
  if p >= 0 then
    CELLS_OF[p] = CELLS_OF[p] or {}
    table.insert(CELLS_OF[p], k)
  end
end

-- Colour of cell k (r * COLS + c) in the paper view without the selection, cached per
-- cell (CELL_R/G/B, k + 1) and refreshed when the owner changes; make_m2.py has the
-- same formula
local CELL_R, CELL_G, CELL_B = {}, {}, {}
local function cache_cell(k)
  local t, p = M.terrain[k + 1], M.province[k + 1]
  if t == SEA then
    CELL_R[k + 1], CELL_G[k + 1], CELL_B[k + 1] = PAPER_SEA[1], PAPER_SEA[2], PAPER_SEA[3]
  else
    -- land without a province (an islet) is plain parchment
    local o = p >= 0 and FACTION[M.provinces[p + 1].owner] or PARCHMENT
    local dark = (t == MOUNT and 0.82 or t == 3 and 0.93 or 1) * 0.5
    CELL_R[k + 1] = (PARCHMENT[1] + o[1]) * dark
    CELL_G[k + 1] = (PARCHMENT[2] + o[2]) * dark
    CELL_B[k + 1] = (PARCHMENT[3] + o[3]) * dark
  end
end
for k = 0, ROWS * COLS - 1 do cache_cell(k) end

local SEL_KEEP, SEL_ADD = 0.5, 125  -- the selected province: half its colour + light

-- A corner takes the mean colour of the cells around it (the selected province lighter)
local function corner_color(r, c)
  local sr, sg, sb, n = 0, 0, 0, 0
  local province, sel = M.province, selected
  for rr = r - 1, r do
    if rr >= 0 and rr < ROWS then
      for cc = c - 1, c do
        if cc >= 0 and cc < COLS then
          local i = rr * COLS + cc + 1
          local r1, g1, b1 = CELL_R[i], CELL_G[i], CELL_B[i]
          if sel and province[i] == sel then
            r1, g1, b1 = r1 * SEL_KEEP + SEL_ADD, g1 * SEL_KEEP + SEL_ADD, b1 * SEL_KEEP + SEL_ADD
          end
          sr, sg, sb, n = sr + r1, sg + g1, sb + b1, n + 1
        end
      end
    end
  end
  local h = 0.5 * n
  sr, sg, sb = (sr + h) // n, (sg + h) // n, (sb + h) // n
  return math.tointeger(sr > 255 and 255 or sr) << 16 | math.tointeger(sg > 255 and 255 or sg) << 8
    | math.tointeger(sb > 255 and 255 or sb)
end

-- Every corner the cells of a province touch (r * W1 + c), built on first use
local CORNERS_OF = {}

-- Recolours the corners of province p, paper view
local function recolor(p)
  local t0 = micros()
  local corners = CORNERS_OF[p]
  if not corners then
    local seen = {}
    corners = {}
    for _, k in ipairs(CELLS_OF[p]) do
      local r, c = k // COLS, k % COLS
      for q = r * W1 + c, (r + 1) * W1 + c, W1 do
        for kk = q, q + 1 do
          if not seen[kk] then seen[kk] = true corners[#corners + 1] = kk end
        end
      end
    end
    CORNERS_OF[p] = corners
  end
  local grid = paper_grid
  for _, k in ipairs(corners) do
    local r, c = k // W1, k % W1
    grid:color(c, r, corner_color(r, c))
  end
  recolor_ms = (micros() - t0) / 1000
end

local war = require("war")
local st                        -- the game (src/war.lua)
local unit                      -- the selected army or fleet
local targets = {}              -- place -> "move" | "board" | "sail" | "land"
local MARK = { move = 0xffffff, board = 0x5080ff, sail = 0x5080ff, land = 0xffd040 }

function _init()
  local img = image("paper", M.tex)
  local opts = { w = HW * 2, h = HH * 2, frames = M.frames, heights = M.heights, colors = M.paper }
  paper_grid = isogrid(img, COLS, ROWS, opts)
  opts.colors = M.relief
  relief_grid = isogrid(img, COLS, ROWS, opts)
  M.paper, M.relief, M.heights, M.frames = nil, nil, nil, nil   -- the grids keep them
  collectgarbage()
  -- the player leads the faction with the most provinces
  local count = {}
  for _, pr in ipairs(M.provinces) do
    if not pr.sea then count[pr.owner] = (count[pr.owner] or 0) + 1 end
  end
  local player = 0
  for f, n in pairs(count) do
    if n > (count[player] or 0) then player = f end
  end
  st = war.new(M, player)
  -- start at the player's first army
  local a
  for _, x in ipairs(st.armies) do
    if x.owner == player then a = x break end
  end
  local pr = M.provinces[(a and a.at or 0) + 1]
  camx = (pr.c - pr.r) * HW - 128
  camy = (pr.c + pr.r) * HH - 96
end

local function grid() return relief and relief_grid or paper_grid end
local function hscale3() return relief and HSCALE3 or 0 end

-- The province under a point of the bottom screen (flat map: heights ignored)
local function province_at(sx, sy)
  local c, r
  if view3d then
    local x, y = pick3d(sx, sy, grid(), hscale3())
    if not x then return nil end
    c, r = math.floor(x), math.floor(y)
  else
    local u, v = (sx + camx) / HW, (sy + camy) / HH
    c, r = math.floor((u + v) / 2), math.floor((v - u) / 2)
  end
  if r < 0 or r >= ROWS or c < 0 or c >= COLS then return nil end
  local p = M.province[r * COLS + c + 1]
  return p >= 0 and p or nil
end

local function select(p)
  local old = selected
  selected = p
  if old then recolor(old) end
  if p then recolor(p) end
end

-- Screen position of a province's capital (a sea zone's centre), nil if behind the
-- 3D camera
local function place_xy(p)
  local pr = M.provinces[p + 1]
  if view3d then
    -- far places are in the fog: skip them before projecting (floats are slow)
    local dx, dy, far = pr.c - t3x, pr.r - t3y, ZOOMS[zoom3] * 3
    if dx * dx + dy * dy > far * far then return nil end
    local h = grid():height(pr.c, pr.r) * hscale3()
    return project3d(pr.c + 0.5, pr.r + 0.5, h)
  end
  return (pr.c - pr.r) * HW - camx, (pr.c + pr.r + 1) * HH - camy
end

-- Every army on land and every fleet with where its token is: { unit, x, y }
local function tokens()
  local out, count = {}, {}
  for _, a in ipairs(st.armies) do
    if not a.fleet then
      local x, y = place_xy(a.at)
      local k = count[a.at] or 0
      count[a.at] = k + 1
      if x then out[#out + 1] = { a, x - 3 + k * 9, y - 6 } end
    end
  end
  for _, f in ipairs(st.fleets) do
    local x, y = place_xy(f.at)
    local k = count[f.at] or 0
    count[f.at] = k + 1
    if x then out[#out + 1] = { f, x - 6 + k * 13, y - 4 } end
  end
  return out
end

-- A tap that did not drag: an order for the selected unit, a unit, or a place
local function tap(sx, sy)
  local p = province_at(sx, sy)
  for _, t in ipairs(tokens()) do
    if math.abs(sx - t[2]) <= 6 and sy >= t[3] - 10 and sy <= t[3] + 4 then
      unit = t[1]
      targets = war.targets(st, unit)
      return
    end
  end
  if unit and p and targets[p] then
    local _, result = war.act(st, unit, p)
    if result == "taken" then
      for _, k in ipairs(CELLS_OF[p]) do cache_cell(k) end
      recolor(p)
    end
    targets = war.targets(st, unit)
    return
  end
  unit, targets = nil, {}
  select(p)
end

-- X: the same place stays in the middle of the screen
local function toggle_view()
  if view3d then
    camx = (t3x - t3y) * HW - 128
    camy = (t3x + t3y) * HH - 96
  else
    local u, v = (128 + camx) / HW, (96 + camy) / HH
    t3x, t3y = (u + v) / 2, (v - u) / 2
  end
  view3d = not view3d
end

-- Moves the map by dx, dy pixels of the screen
local function scroll(dx, dy)
  if view3d then
    local k = ZOOMS[zoom3] / 150
    local a = math.rad(yaw3)
    t3x = t3x - (dx * math.cos(a) - dy * math.sin(a)) * k
    t3y = t3y - (dx * math.sin(a) + dy * math.cos(a)) * k
    t3x = math.max(0, math.min(COLS, t3x))
    t3y = math.max(0, math.min(ROWS, t3y))
  else
    camx, camy = camx - dx, camy - dy
  end
end

function _update()
  -- A touch is a tap at the point the stylus came down, unless the stylus moves more
  -- than DRAG_START first (a resting stylus jitters): then it scrolls the map
  local px, py = touchp()
  if px then press_x, press_y, drag_x, drag_y, drag_moved = px, py, px, py, false end
  local tx, ty = touch()
  if tx and press_x then
    if not drag_moved and math.abs(tx - press_x) + math.abs(ty - press_y) > DRAG_START then
      drag_moved = true
    end
    if drag_moved then
      scroll(tx - drag_x, ty - drag_y)
      drag_x, drag_y = tx, ty
    end
  end
  if btnr("touch") and press_x then
    if not drag_moved then tap(press_x, press_y) end
    press_x = nil
  end
  if btn("left") then scroll(3, 0) end
  if btn("right") then scroll(-3, 0) end
  if btn("up") then scroll(0, 3) end
  if btn("down") then scroll(0, -3) end
  if btnp("a") then relief = not relief end
  if btnp("x") then toggle_view() end
  if view3d then
    if btn("l") then yaw3 = yaw3 - 3 end
    if btn("r") then yaw3 = yaw3 + 3 end
    if btnp("b") then zoom3 = zoom3 % #ZOOMS + 1 end
  end
  if btnp("y") then
    war.end_turn(st)
    targets = unit and war.targets(st, unit) or {}
  end
end

local draw_us = 0

local function draw_army(a, x, y)
  local col = M.factions[a.owner + 1].color
  line(x, y - 9, x, y + 2, 0x302018)                  -- the pole
  rectfill(x + 1, y - 9, 7, 5, col)                   -- the banner
  rect(x + 1, y - 9, 7, 5, 0x302018)
  if a == unit then rect(x - 2, y - 11, 12, 15, 0xffffff) end
end

local function draw_fleet(f, x, y)
  local col = f.trade and 0xf0f0f0 or M.factions[f.owner + 1].color
  rectfill(x - 5, y, 11, 3, f.trade and 0x8a6a40 or 0x503020)       -- the hull
  trifill(x, y - 8, x, y - 1, x + 5, y - 1, col)                    -- the sail
  line(x, y - 9, x, y, 0x302018)
  if f.trade then rectfill(x - 4, y - 4, 3, 3, M.factions[f.owner + 1].color) end
  if f.cargo then rectfill(x - 4, y - 7, 3, 3, M.factions[f.owner + 1].color) end
  if f == unit then rect(x - 7, y - 11, 15, 16, 0xffffff) end
end

function _draw(screen)
  if screen == BOTTOM then
    cls(BACK)
    local t0 = micros()
    if view3d then
      local d = ZOOMS[zoom3]
      camera3d(t3x, t3y, yaw3, PITCH3, d)
      fog3d(BACK, d * 1.5, d * 2.8)
      grid():draw3d(hscale3(), 0, 18, relief and UNDER.relief or UNDER.paper)
    else
      camera(camx, camy)
      if relief then
        relief_grid:draw(0, 0, RELIEF_SCALE)
      else
        paper_grid:draw(0, 0, 0)
      end
      camera()
    end
    if not relief then
      -- capitals: a dot and the name (screen positions)
      for i, pr in ipairs(M.provinces) do
        local x, y = place_xy(i - 1)
        if x and x > -40 and x < 296 and y > -10 and y < 200 then
          local w = textw(pr.name)
          local col = i - 1 == selected and 0xffffff or pr.sea and 0x46648c or 0x302018
          if not pr.sea then rectfill(x - 1, y - 1, 3, 3, 0x302018) end
          text(pr.name, x - w // 2, y + 3, col)
        end
      end
    end
    for p, kind in pairs(targets) do
      local x, y = place_xy(p)
      if x then circ(x, y, 6, MARK[kind]) end
    end
    for _, t in ipairs(tokens()) do
      if t[1].size then draw_army(t[1], t[2], t[3]) else draw_fleet(t[1], t[2], t[3]) end
    end
    draw_us = micros() - t0
  else
    cls(0x181410)
    local me = M.factions[st.player + 1]
    text(("Turn %d - you lead %s"):format(st.turn, me.name), 8, 8, 7)
    rectfill(230, 6, 16, 10, me.color)
    text(("A: %s  X: %s  Y: end turn"):format(relief and "relief" or "paper",
      view3d and "3D" or "flat"), 8, 22, 6)
    if view3d then text("3D: L/R turn, B zoom, stylus/d-pad move", 8, 30, 5) end
    local y = 40
    if unit then
      local f = M.factions[unit.owner + 1].name
      local at = M.provinces[unit.at + 1].name
      if unit.size then
        text(("%s army of %d at %s"):format(f, unit.size, at), 8, y, 7)
      elseif unit.trade then
        text(("%s trade ship at %s"):format(f, at), 8, y, 7)
        text(("route %s - %s"):format(M.provinces[unit.trade.from + 1].name,
          M.provinces[unit.trade.to + 1].name), 8, y + 12, 6)
      else
        text(("%s fleet at %s%s"):format(f, at, unit.cargo and (" with " .. unit.cargo.size) or ""), 8, y, 7)
      end
      local n = 0
      for _ in pairs(targets) do n = n + 1 end
      if unit.owner == st.player and not unit.trade then
        text(n > 0 and "tap a marked place" or "no more moves this turn", 8, y + 24, 6)
      end
    elseif selected then
      local pr = M.provinces[selected + 1]
      text(pr.name, 8, y, 7)
      text(pr.sea and "sea zone (no owner)" or ("owner: " .. M.factions[pr.owner + 1].name), 8, y + 12, 6)
      local land, seas = {}, {}
      for _, j in ipairs(pr.neighbours) do
        local nb = M.provinces[j + 1]
        table.insert(nb.sea and seas or land, nb.name)
      end
      text((pr.sea and "ports: " or "next: ") .. table.concat(land, ", "):sub(1, 34), 8, y + 24, 6)
      if #seas > 0 then
        text((pr.sea and "seas: " or "coast: ") .. table.concat(seas, ", "):sub(1, 34), 8, y + 36, 6)
      end
    else
      text("tap an army or a fleet", 8, y, 6)
    end
    for i, msg in ipairs(st.log) do text(msg, 8, 110 + i * 12, i == 1 and 7 or 5) end
    text(("draw %.1f ms  recolour %.1f ms"):format(draw_us / 1000, recolor_ms), 8, 180, 5)
  end
end
