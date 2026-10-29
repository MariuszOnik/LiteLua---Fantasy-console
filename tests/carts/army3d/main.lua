-- Test of the 3D layer (D60): terrain in perspective (isogrid:draw3d) and
-- regiments of Cossacks musketeers as billboards. Measures how many soldiers
-- a DS can draw. The soldier atlas is made locally from the game's sprites:
--   python tools/cossacks_atlas.py <extractor out>/MBA tests/carts/army3d
--
-- D-pad: left/right turn, up/down tilt; L/R: zoom; stylus: move the view;
-- A: number of soldiers; B: terrain strips + fog / strips / cells / off; X: stand / shoot / march;
-- Y: reset the camera; select: 16 / 8 directions (gfx/soldier8.png, --dirs 5).

local MAP = 48                       -- tiles per side
local COUNTS = { 200, 500, 1000, 1500 }
local MAX = 1536
local FILES, RANKS = 12, 3           -- a regiment: 12 files, 3 ranks
local GAP_X, GAP_Y = 0.3, 0.45       -- tiles between soldiers
local SCALE = 1 / 56                 -- tiles per texel (a soldier ~0.5 tile)
local MODES = { "stand", "shoot", "march" }
local MARCH = 0.6                    -- tiles per second
local TURN_MS = 8000
local turn_at = 0

local ok, S16 = pcall(require, "soldier")
local ok8, S8 = pcall(require, "soldier8")
local S = S16
local ground, troops, troops16, troops8
local heights = {}                   -- corner heights in tiles, [r * (MAP + 1) + c]
local soldiers = {}                  -- { x, y, dir }
local GROUNDS = { "fog", "strips", "cells", "off" }  -- fog: also coarse far away
local SKY = 0x8ab4d8
local count_i, mode_i, ground_i = 2, 1, 1
local grass_ground
local cx, cy, yaw, pitch, dist
local drag
local last = { terrain = 0, troops = 0, update = 0 }

local function reset_camera()
  cx, cy, yaw, pitch, dist = MAP / 2, MAP / 2 + 2, 0, 40, 10
end

local function hill(x, y)
  return 0.9 * math.sin(x * 0.23) * math.cos(y * 0.17)
       + 0.6 * math.sin((x + y) * 0.11 + 1)
       + 1.6
end

-- Height of the ground under x, y (tiles), interpolated between corners
local function height_at(x, y)
  local c, r = math.floor(x), math.floor(y)
  if c < 0 or r < 0 or c >= MAP or r >= MAP then return 0 end
  local fx, fy = x - c, y - r
  local W = MAP + 1
  local t, rr = heights[r * W + c], heights[r * W + c + 1]
  local l, b = heights[(r + 1) * W + c], heights[(r + 1) * W + c + 1]
  return (t * (1 - fx) + rr * fx) * (1 - fy) + (l * (1 - fx) + b * fx) * fy
end

local function build_ground()
  local img = image("ground", 32)
  local W = MAP + 1
  local hs, cols, frames = {}, {}, {}
  for r = 0, MAP do
    for c = 0, MAP do
      heights[r * W + c] = hill(c, r)
    end
  end
  for r = 0, MAP do
    for c = 0, MAP do
      local h = heights[r * W + c]
      hs[#hs + 1] = math.floor(h * 16 + 0.5)
      -- light from the north-west: brighter where the ground faces it
      local dx = (heights[r * W + math.min(c + 1, MAP)] - heights[r * W + math.max(c - 1, 0)])
      local dy = (heights[math.min(r + 1, MAP) * W + c] - heights[math.max(r - 1, 0) * W + c])
      local light = math.max(0.55, math.min(1, 0.82 + (dx + dy) * 0.35))
      local v = math.floor(255 * light)
      cols[#cols + 1] = v << 16 | v << 8 | v
    end
  end
  local rnd = 1
  for r = 0, MAP - 1 do
    for c = 0, MAP - 1 do
      rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
      local f = (rnd >> 16) % 2
      if c >= 6 and c < 14 and r >= 30 and r < 40 then f = 2 end   -- a field
      if c == 34 then f = 3 end                                     -- a road
      frames[#frames + 1] = f
    end
  end
  ground = isogrid(img, MAP, MAP, { w = 32, frames = frames, heights = hs, colors = cols })
  -- one repeated grass texture: the field and the road are corner colors
  for r = 0, MAP do
    for c = 0, MAP do
      local i = r * W + c + 1
      local v = cols[i] & 0xff
      if c >= 6 and c <= 14 and r >= 30 and r <= 40 then
        cols[i] = math.min(255, v * 2) << 16 | math.min(255, v * 9 // 8) << 8 | v // 2
      elseif c == 34 or c == 35 then
        cols[i] = math.min(255, v * 7 // 4) << 16 | math.min(255, v * 5 // 4) << 8 | v // 2
      end
    end
  end
  grass_ground = isogrid(image("grass"), MAP, MAP, { w = 32, heights = hs, colors = cols })
end

local function build_troops(name, S)
  local img = image(name, S.w, S.h)
  anchor(img, S.ax, S.ay)
  local b = billboards(img, MAX, { dirs = S.dirs, scale = SCALE })
  local a = S.anims
  b:anim(0, a.STAND.first, a.STAND.frames)
  b:anim(1, a.WALK.first, a.WALK.frames, 70)
  b:anim(2, a.PATTACK.first, a.PATTACK.frames, 11 * 160 // a.PATTACK.frames)
  b:ground(grass_ground)               -- z = 0: on the ground, followed in C
  return b
end

-- Regiments of two armies facing each other across the middle of the map
local function place()
  local n = COUNTS[count_i]
  soldiers = {}
  local per = FILES * RANKS
  local regs = (n + per - 1) // per
  local rw = FILES * GAP_X + 1.0                -- regiment width with a gap
  local per_line = 7
  for i = 0, regs - 1 do
    local side = i % 2                          -- 0 north (faces south), 1 south
    local k = i // 2
    local line, slot = k // per_line, k % per_line
    local x0 = MAP / 2 - per_line * rw / 2 + slot * rw
    local y0 = side == 0 and MAP / 2 - 3 - line * 2.2 or MAP / 2 + 3 + line * 2.2
    for j = 0, per - 1 do
      if #soldiers == n then break end
      local f, rk = j % FILES, j // FILES
      local x = x0 + f * GAP_X + ((rk % 2) * 0.1)
      local y = y0 + (side == 0 and -rk or rk) * GAP_Y
      soldiers[#soldiers + 1] = { x = x, y = y, dir = side == 0 and 0 or 8, t0 = (j * 37) % 900 }
    end
  end
  local anim = mode_i - 1
  local now = micros() // 1000
  for i = 1, MAX do
    local s = soldiers[i]
    if s then
      troops:set(i, s.x, s.y, 0, s.dir, anim, s.t0)
      if MODES[mode_i] == "march" then
        troops:move(i, 0, s.dir == 0 and MARCH or -MARCH, now)
      end
    else
      troops:set(i, 0, 0, 0, 0, -1)
    end
  end
  turn_at = now + TURN_MS
end

-- Marching regiments turn back every TURN_MS: one Lua call per soldier then,
-- the walk itself is computed in C
local function turn_back(now)
  for i, s in ipairs(soldiers) do
    s.dir = (s.dir + 8) % 16
    local x, y = troops:get(i, now)
    troops:set(i, x, y, 0, s.dir, 1, s.t0)
    troops:move(i, 0, s.dir == 0 and MARCH or -MARCH, now)
  end
  turn_at = now + TURN_MS
end

function _init()
  reset_camera()
  if not ok then return end
  build_ground()
  troops16 = build_troops("soldier", S16)
  if ok8 then troops8 = build_troops("soldier8", S8) end
  troops = troops16
  place()
end

function _update()
  if not ok then return end
  local t0 = micros()
  if btn("left") then yaw = yaw - 2 end
  if btn("right") then yaw = yaw + 2 end
  if btn("up") then pitch = math.min(80, pitch + 1) end
  if btn("down") then pitch = math.max(15, pitch - 1) end
  if btn("l") then dist = math.min(40, dist * 1.03) end
  if btn("r") then dist = math.max(3, dist / 1.03) end
  if btnp("y") then reset_camera() end
  if btnp("b") then ground_i = ground_i % #GROUNDS + 1 end
  if btnp("a") then count_i = count_i % #COUNTS + 1; place() end
  if btnp("x") then mode_i = mode_i % #MODES + 1; place() end
  if btnp("select") and troops8 then
    troops, S = troops == troops16 and troops8 or troops16, S == S16 and S8 or S16
    place()
  end

  -- the stylus drags the ground: right on the screen is (cos yaw, sin yaw)
  local tx, ty = touch()
  if tx then
    if drag then
      local k = dist / 160
      local a = math.rad(yaw)
      local dx, dy = (tx - drag[1]) * k, (ty - drag[2]) * k
      cx = cx - (dx * math.cos(a) - dy * math.sin(a))
      cy = cy - (dx * math.sin(a) + dy * math.cos(a))
    end
    drag = { tx, ty }
  else
    drag = nil
  end

  local now = micros() // 1000
  if MODES[mode_i] == "march" and now >= turn_at then turn_back(now) end
  last.update = micros() - t0
end

function _draw(screen)
  if screen == TOP then
    cls(0x101820)
    if not ok then
      text("No gfx/soldier.png: run tools/cossacks_atlas.py", 4, 4, 8)
      return
    end
    local s = sys.stats()
    local lines = {
      "army3d (D60)",
      string.format("soldiers %d  mode %s  dirs %d", #soldiers, MODES[mode_i],
                    2 * (S.dirs - 1)),
      string.format("fps %d  cpu %d%%", s.fps, s.cpu),
      string.format("terrain %s %.1f ms  troops %.1f ms", GROUNDS[ground_i],
                    last.terrain / 1000, last.troops / 1000),
      string.format("update %.1f ms", last.update / 1000),
      string.format("polys %d  verts %d", s.polys_bottom, s.verts_bottom),
      string.format("vram %d KB  mem %d KB", s.vram // 1024, s.mem // 1024),
      string.format("yaw %d pitch %d dist %.1f", yaw % 360, pitch, dist),
      "",
      "A count  B terrain  X mode  Y reset",
      "select 16/8 directions",
      "d-pad turn/tilt  L/R zoom  stylus pan",
    }
    for i, l in ipairs(lines) do text(l, 4, 4 + (i - 1) * 10, 12) end
    return
  end

  cls(SKY)
  if not ok then return end
  camera3d(cx, cy, yaw, pitch, dist, 50, height_at(cx, cy))
  local t = micros()
  local g = GROUNDS[ground_i]
  if g == "fog" then fog3d(SKY, dist * 1.5, dist * 3) end
  if g == "fog" then
    grass_ground:draw3d(1 / 16, 32, 20)   -- coarse 20 tiles from the eye
  elseif g == "strips" then
    grass_ground:draw3d(1 / 16, 32)
  elseif g == "cells" then
    ground:draw3d(1 / 16)
  end
  local t1 = micros()
  troops:draw3d(t // 1000, g == "fog" and 16 or 0)  -- thinned out far away
  local t2 = micros()
  last.terrain, last.troops = t1 - t, t2 - t1
end
