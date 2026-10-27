-- HeroesDS M1: a piece of a Heroes IV map as raised, lit terrain (isogrid, D58).
-- Bottom screen: the terrain; drag the stylus or use the d-pad to scroll.
-- A: heights on/off, X: light on/off, B: shade strength, L/R: flatter/steeper
-- hills, Y: isogrid (C) or one quad() per cell from Lua (to compare).
-- Objects (T.objects) are drawn over the terrain back to front, one picture per
-- model (gfx/obj/<n>.png, shadow included). A model is loaded when it comes near
-- the screen; past the budget the least recently seen one is dropped.
-- SELECT: budget 96 KB / 20 KB (to watch models being dropped and loaded again).
-- Top screen: the cost of drawing it. Data: HeroesDS/tools/make_m1.py.

local T = dofile("data/terrain.lua")

local HW, HH = 16, 8            -- half width and half height of a cell on screen
local ROWS, COLS = T.rows, T.cols
local W1 = COLS + 1             -- corners per row
local FRAMES, HEIGHTS, SLOPE = T.frames, T.heights, T.slope
local FLAT = 25                 -- light level of flat ground (31 = white; tint only darkens)
local STRENGTHS = { 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.6 }

local img, grid, plain
local OBJECTS, MODELS = T.objects or {}, T.models or {}
local BUDGETS = { 96 * 1024, 20 * 1024 }
local budget = 1                -- index into BUDGETS
local MARGIN = 64               -- pixels around the screen that count as near
local cache = {}                -- model -> { img =, seen = frame }
local cached, frame_no = 0, 0   -- bytes in the cache, frames drawn
local loads, drops, load_us = 0, 0, 0
local gray = {}                 -- light level 0..31 -> tint color
local LIGHT = {}                -- corner -> light level, from SLOPE and the strength
local strength = 6              -- index into STRENGTHS (0.4; B changes it)
local lift = {}                 -- corner -> pixels up (heights * scale), Lua mode
local scale = 0.5               -- pixels per height unit (the PC's 1 at 64x32 tiles)
local heights_on, light_on = true, true
local camx, camy = 0, 0
local drag_x, drag_y
local draw_us, drawn = 0, 0
local use_c = true

local function set_scale(s)
  scale = s
  local k = heights_on and s or 0
  for i = 1, #HEIGHTS do lift[i] = HEIGHTS[i] * k end
end

-- Light level of every corner: flat ground FLAT, slopes lighter or darker
local function set_strength(k)
  strength = k
  local s = STRENGTHS[k]
  for i = 1, #SLOPE do
    local l = math.floor(FLAT + SLOPE[i] * s + 0.5)
    LIGHT[i] = l < 0 and 0 or l > 31 and 31 or l
  end
  if grid then
    for y = 0, ROWS do
      for x = 0, COLS do
        grid:color(x, y, gray[LIGHT[y * W1 + x + 1]])
      end
    end
  end
end

function _init()
  img = image("terrain", T.tex)
  for l = 0, 31 do
    gray[l] = (l * 255 // 31) * 0x10101
  end
  local opts = { w = HW * 2, h = HH * 2, frames = FRAMES, heights = HEIGHTS }
  plain = isogrid(img, COLS, ROWS, opts)
  grid = isogrid(img, COLS, ROWS, opts)
  set_strength(strength)
  set_scale(scale)
  -- start with the middle of the window in the middle of the screen
  camx = (COLS - ROWS) // 2 * HW - 128
  camy = (COLS + ROWS) // 2 * HH - 96
end

function _update()
  local tx, ty = touch()
  if tx then
    if drag_x then
      camx = camx - (tx - drag_x)
      camy = camy - (ty - drag_y)
    end
    drag_x, drag_y = tx, ty
  else
    drag_x = nil
  end
  if btn("left") then camx = camx - 3 end
  if btn("right") then camx = camx + 3 end
  if btn("up") then camy = camy - 3 end
  if btn("down") then camy = camy + 3 end
  if btnp("a") then heights_on = not heights_on; set_scale(scale) end
  if btnp("x") then light_on = not light_on end
  if btnp("l") then set_scale(math.max(0, scale - 0.125)) end
  if btnp("r") then set_scale(math.min(8, scale + 0.125)) end
  if btnp("y") then use_c = not use_c end
  if btnp("b") then set_strength(strength % #STRENGTHS + 1) end
  if btnp("select") then budget = budget % #BUDGETS + 1 end
end

-- The same in Lua, one quad() per cell. Cells back to front: s = c + r is the
-- screen row, d = c - r the screen column; a cell can be lifted by up to
-- 255 * scale pixels, so rows below the screen count too.
local function draw_lua()
  local n = 0
  local maxlift = 255 * scale
  local s1 = math.max(0, (camy - HH) // HH)
  local s2 = math.min(ROWS + COLS - 2, (camy + 192 + HH + maxlift) // HH + 1)
  local d1, d2 = (camx - HW) // HW, (camx + 256 + HW) // HW + 1
  if not light_on then tint() end
  for s = s1, s2 do
    local y = s * HH - camy
    local d = d1
    if (d - s) % 2 ~= 0 then d = d + 1 end
    while d <= d2 do
      local c, r = (s + d) // 2, (s - d) // 2
      if r >= 0 and r < ROWS and c >= 0 and c < COLS then
        local f = FRAMES[r * COLS + c + 1]
        local i = r * W1 + c + 1
        if f >= 0 and y - HH - lift[i] < 192 then
          local x = d * HW - camx
          if light_on then
            tint(gray[LIGHT[i]], gray[LIGHT[i + 1]], gray[LIGHT[i + W1 + 1]], gray[LIGHT[i + W1]])
          end
          -- one pixel bigger on every side: the DS leaves 1-pixel cracks between
          -- polygons whose shared edge has an odd slope (raised corners)
          quad(img, f, x, y - HH - 1 - lift[i], x + HW + 1, y - lift[i + 1],
               x, y + HH + 1 - lift[i + W1 + 1], x - HW - 1, y - lift[i + W1])
          n = n + 1
        end
      end
      d = d + 2
    end
  end
  return n
end

-- Video memory of a model's picture: sides padded to powers of two, 4 bits a pixel
local function cost(k)
  local m = MODELS[k]
  local w, h = 8, 8
  while w < m.w do w = w * 2 end
  while h < m.h do h = h * 2 end
  return w * h // 2
end

-- The picture of model k, loaded if needed. Room is made by dropping the models
-- seen longest ago, but never one seen in this frame.
local function picture(k)
  local e = cache[k]
  if not e then
    local need, dropped = cost(k), false
    while cached + need > BUDGETS[budget] do
      local oldest
      for j, c in pairs(cache) do
        if not oldest or c.seen < cache[oldest].seen then oldest = j end
      end
      if not oldest or cache[oldest].seen == frame_no then break end
      cache[oldest] = nil
      cached = cached - cost(oldest)
      drops, dropped = drops + 1, true
    end
    if dropped then collectgarbage() end   -- frees the dropped textures now
    local t0 = micros()
    e = { img = image("obj/" .. k) }
    load_us = micros() - t0
    cache[k], cached, loads = e, cached + need, loads + 1
  end
  e.seen = frame_no
  return e.img
end

-- Each object at the top corner of its anchor cell, raised with the ground there;
-- only the ones near the screen (camera camx, camy) are drawn and kept loaded
local function draw_objects()
  frame_no = frame_no + 1
  local k = heights_on and scale or 0
  for _, o in ipairs(OBJECTS) do
    local m = MODELS[o.m]
    local x = (o.c - o.r) * HW + o.dx
    local y = (o.c + o.r) * HH - HH - HEIGHTS[o.r * W1 + o.c + 1] * k + o.dy
    if x < camx + 256 + MARGIN and x + m.w > camx - MARGIN
        and y < camy + 192 + MARGIN and y + m.h > camy - MARGIN then
      spr(picture(o.m), x, y)
    end
  end
end

function _draw(screen)
  cls(0x101018)
  if screen == BOTTOM then
    local t0 = micros()
    if use_c then
      camera(camx, camy)
      -- the top corner of cell (0, 0) is HH above the centre row 0 of draw_lua
      local g = light_on and grid or plain
      g:draw(0, -HH, heights_on and scale or 0)
      draw_objects()
      camera()
      drawn = -1
    else
      drawn = draw_lua()
    end
    draw_us = micros() - t0
  else
    text("HeroesDS M1: terrain", 8, 8, 7)
    text(("drawing (Y): %s"):format(use_c and "isogrid (C)" or "quad per cell (Lua)"), 8, 28, 6)
    text(("terrain draw: %.1f ms"):format(draw_us / 1000), 8, 40, 6)
    if drawn >= 0 then text(("cells drawn: %d"):format(drawn), 8, 52, 6) end
    text(("heights: %s  x%.3f"):format(heights_on and "on" or "off", scale), 8, 64, 6)
    text(("light: %s  shade (B): %.2f"):format(light_on and "on" or "off", STRENGTHS[strength]), 8, 76, 6)
    text(("camera: %d, %d"):format(camx, camy), 8, 88, 6)
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    text(("objects: %d models, %d/%d KB (SELECT)"):format(n, cached // 1024, BUDGETS[budget] // 1024), 8, 100, 6)
    text(("loaded %d, dropped %d, last load %.1f ms"):format(loads, drops, load_us / 1000), 8, 112, 6)
    text(("video memory: %d KB"):format(sys.stats().vram // 1024), 8, 124, 6)
    text("stylus/d-pad scroll, A heights", 8, 160, 5)
    text("X light, B shade, L/R hills, Y C/Lua", 8, 172, 5)
  end
end
