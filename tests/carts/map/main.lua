-- Map test (P8): a small platformer on map/level1.lua.
-- d-pad: walk, climb ladders; A: jump; SELECT: next level (level1 is ASCII,
-- level2 was converted from Tiled: tests/tools/data/level2.tmj). Top screen:
-- the game with a camera following the hero. Bottom screen: the whole map
-- zoomed out, statistics. Pause menu (hold START): Save / Load position.

local LEVELS = { "level1", "level2" }
local level = 1
local m = tilemap(LEVELS[level])
local hero = image("hero", 16, 16)
-- Sounds and music: tests/carts/map/make_audio.py
local snd = { jump = sound("jump"), coin = sound("coin"), hurt = sound("hurt") }
music("grass_run")
local T = m.tile

-- Hit box inside the 16x16 sprite
local BX, BY, BW, BH = 3, 2, 10, 14
local START_X, START_Y = 16, 8 * T

local p = { x = START_X, y = START_Y, vx = 0, vy = 0, ground = false,
            climb = false, flip = false, frame = 0 }
local coins, deaths, total = 0, 0, #m:find(8)
local camx = 0
local walk_t = 0
-- Jump buffer: A pressed a moment before landing still jumps. Coyote time:
-- a jump is still possible a moment after walking off an edge. Both are
-- counted in game frames (30 per second).
local JUMP_BUFFER, COYOTE = 4, 4
local jump_buf, coyote = 0, 0
local jumps, presses = 0, 0 -- Shown on the bottom screen: every press should jump

local function solid_at(x, y, w, h)
  return m:hit(x + BX, y + BY, w or BW, h or BH, "solid", "main")
end

local function respawn()
  p.x, p.y, p.vx, p.vy, p.climb = START_X, START_Y, 0, 0, false
  deaths = deaths + 1
end

-- Moves one axis a pixel at a time and stops at solid tiles
local function move_x(dx)
  local step = dx > 0 and 1 or -1
  for _ = 1, math.floor(math.abs(dx) + 0.5) do
    if solid_at(p.x + step, p.y) then p.vx = 0 return end
    p.x = p.x + step
  end
end

-- Standing on something: a solid tile or the top of a one-way platform
-- right under the feet. Checked every frame, not only when the hero moved.
local function standing()
  if solid_at(p.x, p.y + 1) then return true end
  local feet = p.y + BY + BH -- First pixel below the box
  return feet % T == 0 and m:hit(p.x + BX, feet, BW, 1, "platform", "main") ~= nil
end

local function move_y(dy)
  local step = dy > 0 and 1 or -1
  for _ = 1, math.floor(math.abs(dy) + 0.5) do
    local ny = p.y + step
    local blocked = solid_at(p.x, ny)
    -- One-way platforms: only the feet crossing the top of the tile stop
    if not blocked and step > 0 and not p.climb then
      local feet = p.y + BY + BH -- First pixel below the box
      if feet % T == 0 and m:hit(p.x + BX, feet, BW, 1, "platform", "main") then
        blocked = true
      end
    end
    if blocked then
      p.vy = 0
      return
    end
    p.y = ny
  end
end

local function load_level(n)
  level = n
  m = tilemap(LEVELS[level])
  coins, total = 0, #m:find(8)
  respawn()
  deaths = 0
end

-- Pause menu items (hold START): the game decides what a save holds; here
-- the level and the hero's position (the coins start again)
local SAVE = "save/pos.txt"
local message, message_t = nil, 0
sys.menu("Save position", function()
  local f = assert(io.open(SAVE, "w"))
  f:write(("%d %d %d\n"):format(level, p.x // 1, p.y // 1))
  f:close()
  message, message_t = "saved", 60
end)
sys.menu("Load position", function()
  local f = io.open(SAVE, "r")
  if not f then message, message_t = "nothing saved yet", 60; return end
  local lv, x, y = f:read("n", "n", "n")
  f:close()
  load_level(lv)
  p.x, p.y = x, y
  message, message_t = "loaded", 60
end)

function _update()
  if message_t > 0 then message_t = message_t - 1 end
  if btnp("select") then load_level(level % #LEVELS + 1) return end
  local on_ladder = m:hit(p.x + BX + 3, p.y + BY, BW - 6, BH, "ladder", "main")
  if on_ladder and (btn("up") or btn("down")) then p.climb = true end
  if not on_ladder then p.climb = false end

  p.vx = 0
  if btn("left") then p.vx = -1.6; p.flip = true end
  if btn("right") then p.vx = 1.6; p.flip = false end

  if p.climb then
    p.vy = (btn("up") and -1.2 or 0) + (btn("down") and 1.2 or 0)
    if btnp("a") then p.climb = false; p.vy = -4; sfx(snd.jump) end
  else
    local in_water = m:hit(p.x + BX, p.y + BY, BW, BH, "water", "main")
    p.vy = math.min(p.vy + (in_water and 0.15 or 0.4), in_water and 1.5 or 6)
    if btnp("a") then jump_buf = JUMP_BUFFER; presses = presses + 1 end
    if jump_buf > 0 and (coyote > 0 or in_water) then
      p.vy = in_water and -3 or -6.2
      jump_buf, coyote = 0, 0
      jumps = jumps + 1
      sfx(snd.jump, 0.8, 0, in_water and 0.7 or 1)
    end
  end
  jump_buf = math.max(0, jump_buf - 1)

  move_x(p.vx)
  move_y(p.vy)
  p.ground = p.vy >= 0 and standing()
  if p.ground then p.vy = 0 end
  coyote = p.ground and COYOTE or math.max(0, coyote - 1)

  -- Coins: take the tile away
  local cx, cy = m:hit(p.x + BX, p.y + BY, BW, BH, "coin", "main")
  if cx then
    m:set(cx, cy, 0, "main")
    coins = coins + 1
    sfx(snd.coin, 0.8, math.max(-1, math.min(1, (cx * T - camx - 128) / 128)))  -- panned
  end
  if m:hit(p.x + BX + 2, p.y + BY + 6, BW - 4, BH - 6, "hurt", "main")
     or p.y > m.h * T then
    sfx(snd.hurt)
    respawn()
  end

  walk_t = p.vx ~= 0 and walk_t + 1 or 0
  p.frame = (not p.ground and not p.climb) and 3 or (p.vx ~= 0 and 1 + (walk_t // 5) % 2 or 0)

  local world_w = m.w * T
  camx = math.max(0, math.min(p.x + 8 - 128, world_w - 256))
end

function _draw(s)
  if s == TOP then
    cls(10)
    camera(camx, 0)
    m:draw()
    spr(hero, p.x, p.y, p.frame, p.flip and "x" or nil)
  else
    cls(0)
    -- The whole map, zoomed out to the width of the screen
    local zoom = 256 / (m.w * T)
    camera(0, -40 / zoom, zoom)
    rectfill(0, 0, m.w * T, m.h * T, 10)
    m:draw()
    rectfill(p.x, p.y, 16, 16, 2)
    rect(camx, 0, 256, m.h * T, 12)
    camera()
    local tx, ty = m:cell(p.x + 8, p.y + 15)
    text(("coins %d/%d  deaths %d"):format(coins, total, deaths), 4, 4, 12)
    text(("tile under %d,%d = %d"):format(tx, ty, m:get(tx, ty + 1, "main")), 4, 14, 13)
    text("A jump, up/down ladder, SELECT level", 4, 160, 13)
    text(LEVELS[level], 200, 4, 11)
    if message_t > 0 then text(message, 200, 14, 4) end
    text(("A pressed %d, jumps %d"):format(presses, jumps), 4, 148, 11)
    text(tostring(m), 4, 172, 14)
  end
end
