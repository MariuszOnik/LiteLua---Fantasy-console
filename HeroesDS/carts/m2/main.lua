-- HeroesDS M2: the political map of an invented land (data: HeroesDS/tools/make_m2.py).
-- Bottom screen: the map; drag the stylus or use the d-pad to scroll, tap a province
-- to select it. A: paper map / relief, X: give the selected province to the next
-- faction (to try the colours). Top screen: the selected province.
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
local selected                  -- province number (0-based) or nil
local camx, camy
local drag_x, drag_y, drag_moved
local recolor_ms = 0

local function rgb(c)
  return { c >> 16 & 255, c >> 8 & 255, c & 255 }
end

local NATURE, FACTION = {}, {}
for i, c in ipairs(M.nature) do NATURE[i - 1] = rgb(c) end
for i, f in ipairs(M.factions) do FACTION[i - 1] = rgb(f.color) end


-- Colour of cell (r, c) in the paper view (r, g, b); make_m2.py has the same formula
local function cell_color(r, c)
  local i = r * COLS + c + 1
  local t, p = M.terrain[i], M.province[i]
  local col
  if t == SEA then
    col = { PAPER_SEA[1], PAPER_SEA[2], PAPER_SEA[3] }
  else
    -- land without a province (an islet) is plain parchment
    local o = p >= 0 and FACTION[M.provinces[p + 1].owner] or PARCHMENT
    local dark = t == MOUNT and 0.82 or t == 3 and 0.93 or 1
    col = { (PARCHMENT[1] + o[1]) * 0.5 * dark, (PARCHMENT[2] + o[2]) * 0.5 * dark,
            (PARCHMENT[3] + o[3]) * 0.5 * dark }
  end
  if selected and p == selected then
    col = { col[1] * 0.8 + 60, col[2] * 0.8 + 60, col[3] * 0.8 + 60 }
  end
  return col[1], col[2], col[3]
end

-- A corner takes the mean colour of the cells around it
local function corner_color(r, c)
  local sr, sg, sb, n = 0, 0, 0, 0
  for rr = r - 1, r do
    for cc = c - 1, c do
      if rr >= 0 and rr < ROWS and cc >= 0 and cc < COLS then
        local r1, g1, b1 = cell_color(rr, cc)
        sr, sg, sb, n = sr + r1, sg + g1, sb + b1, n + 1
      end
    end
  end
  local function ch(v)
    v = math.floor(v / n + 0.5)
    return v < 0 and 0 or v > 255 and 255 or v
  end
  return ch(sr) << 16 | ch(sg) << 8 | ch(sb)
end

-- Recolours every corner the given cells (list of r * COLS + c) touch, paper view
local function recolor(cells)
  local t0 = micros()
  local corners = {}
  for _, k in ipairs(cells) do
    local r, c = k // COLS, k % COLS
    for rr = r, r + 1 do
      for cc = c, c + 1 do corners[rr * W1 + cc] = true end
    end
  end
  for k in pairs(corners) do
    local r, c = k // W1, k % W1
    paper_grid:color(c, r, corner_color(r, c))
  end
  recolor_ms = (micros() - t0) / 1000
end

local CELLS_OF = {}             -- province -> its cells
for k = 0, ROWS * COLS - 1 do
  local p = M.province[k + 1]
  if p >= 0 then
    CELLS_OF[p] = CELLS_OF[p] or {}
    table.insert(CELLS_OF[p], k)
  end
end

function _init()
  local img = image("paper", M.tex)
  local opts = { w = HW * 2, h = HH * 2, frames = M.frames, heights = M.heights, colors = M.paper }
  paper_grid = isogrid(img, COLS, ROWS, opts)
  opts.colors = M.relief
  relief_grid = isogrid(img, COLS, ROWS, opts)
  M.paper, M.relief, M.heights, M.frames = nil, nil, nil, nil   -- the grids keep them
  collectgarbage()
  -- the middle of the map in the middle of the screen
  camx = -128
  camy = (ROWS + COLS) // 2 * HH - 96
end

-- The province under a point of the bottom screen (heights ignored)
local function province_at(sx, sy)
  local u, v = (sx + camx) / HW, (sy + camy) / HH
  local c, r = math.floor((u + v) / 2), math.floor((v - u) / 2)
  if r < 0 or r >= ROWS or c < 0 or c >= COLS then return nil end
  local p = M.province[r * COLS + c + 1]
  return p >= 0 and p or nil
end

local function select(p)
  local old = selected
  selected = p
  if old then recolor(CELLS_OF[old]) end
  if p then recolor(CELLS_OF[p]) end
end

function _update()
  local tx, ty = touch()
  if tx then
    if drag_x then
      if math.abs(tx - drag_x) + math.abs(ty - drag_y) > 0 then drag_moved = true end
      camx = camx - (tx - drag_x)
      camy = camy - (ty - drag_y)
    else
      drag_moved = false
    end
    drag_x, drag_y = tx, ty
  elseif drag_x then
    if not drag_moved then select(province_at(drag_x, drag_y)) end
    drag_x = nil
  end
  if btn("left") then camx = camx - 3 end
  if btn("right") then camx = camx + 3 end
  if btn("up") then camy = camy - 3 end
  if btn("down") then camy = camy + 3 end
  if btnp("a") then relief = not relief end
  if btnp("x") and selected then
    local pr = M.provinces[selected + 1]
    pr.owner = (pr.owner + 1) % #M.factions
    recolor(CELLS_OF[selected])
  end
end

local draw_us = 0

function _draw(screen)
  if screen == BOTTOM then
    cls(0x101018)
    local t0 = micros()
    camera(camx, camy)
    if relief then
      relief_grid:draw(0, 0, RELIEF_SCALE)
    else
      paper_grid:draw(0, 0, 0)
    end
    if not relief then
      -- capitals: a dot and the name
      for i, pr in ipairs(M.provinces) do
        local x = (pr.c - pr.r) * HW
        local y = (pr.c + pr.r + 1) * HH
        if x > camx - 40 and x < camx + 296 and y > camy - 10 and y < camy + 200 then
          rectfill(x - 1, y - 1, 3, 3, 0x302018)
          local w = textw(pr.name)
          text(pr.name, x - w // 2, y + 3, i - 1 == selected and 0xffffff or 0x302018)
        end
      end
    end
    camera()
    draw_us = micros() - t0
  else
    cls(0x181410)
    text("HeroesDS M2: political map", 8, 8, 7)
    text(("view (A): %s"):format(relief and "relief" or "paper map"), 8, 24, 6)
    text(("draw %.1f ms, recolour %.0f ms"):format(draw_us / 1000, recolor_ms), 8, 36, 6)
    text(("Lua memory %d KB"):format(collectgarbage("count") // 1), 8, 48, 6)
    if selected then
      local pr = M.provinces[selected + 1]
      text(pr.name, 8, 60, 7)
      text("owner: " .. M.factions[pr.owner + 1].name .. "  (X: change)", 8, 72, 6)
      local names = {}
      for _, j in ipairs(pr.neighbours) do names[#names + 1] = M.provinces[j + 1].name end
      text("neighbours:", 8, 88, 6)
      local line, y = "", 100
      for _, nm in ipairs(names) do
        if #line + #nm + 2 > 40 then
          text(line, 8, y, 6)
          line, y = "", y + 12
        end
        line = line == "" and nm or line .. ", " .. nm
      end
      if line ~= "" then text(line, 8, y, 6) end
    else
      text("tap a province", 8, 60, 6)
    end
    text("stylus/d-pad scroll, tap to select", 8, 172, 5)
  end
end
