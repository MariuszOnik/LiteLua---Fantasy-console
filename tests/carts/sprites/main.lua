-- LiteLua P4b sprites test: PNG kinds, spr/sprx/sspr/sub, tint, zoom, VRAM.
-- A: stress test on/off (Up/Down: more/fewer sprites), B: back to the list.
-- Results of the checks go to the bottom screen and the log.

-- Result lines: shown on the bottom screen and written to the log
local out = {}
local function say(s)
  out[#out + 1] = s
  print(s)
end
local function draw_out(y)
  for i, l in ipairs(out) do
    text(l, 0, (y or 0) + (i - 1) * 8, l:sub(1, 4) == "FAIL" and 2 or 12)
  end
end

local fails = 0
local function check(name, cond, extra)
  if not cond then fails = fails + 1 end
  say((cond and "ok   " or "FAIL ") .. name .. (extra and (" " .. tostring(extra)) or ""))
end

local hero = image("hero")             -- 16 colors -> 4 bpp
local chars = image("chars", 16, 16)   -- frame grid
local pal = image("pal256")            -- 256 colors, tRNS on index 5
local rgba = image("rgba.png")         -- direct color, odd size
local gray = image("gray2")            -- 2-bit gray
local door = sub(chars, 16, 0, 16, 16) -- frame 1 as its own image

check("image size", hero.w == 16 and hero.h == 16 and rgba.w == 40 and rgba.h == 24)
check("frames", chars.frames == 4 and chars.w == 16 and hero.frames == 1)
check("cached", image("hero") == hero)
check("sub size", door.w == 16 and door.h == 16)
local ok, err = pcall(spr, chars, 0, 0, 4)
check("frame range", not ok and err:find("0..3", 1, true), err)
ok, err = pcall(image, "missing")
check("missing image", not ok and err:find("gfx/missing.png", 1, true), err)
ok, err = pcall(sub, hero, 8, 8, 16, 16)
check("sub outside", not ok, err)

-- VRAM: big.png takes all 256 KB, so it cannot load next to the others
ok, err = pcall(image, "big")
check("out of VRAM", not ok and err:find("video memory", 1, true), err)
say("A: stress  B: list")

local t = 0
local status = ""
local stress, count = false, 300
local draw_us, frames = 0, 0

function _update()
  t = t + 1
  if btnp("a") then stress = not stress end
  if btnp("up") then count = count + 100 end
  if btnp("down") and count > 100 then count = count - 100 end
  if btnp("b") then sys.exit() end
end

local function scene()
  cls(15)

  -- Plain sprites and flips
  spr(hero, 4, 4)
  spr(hero, 24, 4, 0, "x")
  spr(hero, 44, 4, 0, "y")
  spr(hero, 64, 4, 0, "xy")

  -- Frames, animated, and a sub image
  for f = 0, 3 do spr(chars, 4 + f * 18, 24, f) end
  spr(chars, 80, 24, t // 8 % 4)
  spr(door, 100, 24)

  -- Rotation and scale around the center
  sprx(hero, 140, 20, 0, t * 3)
  sprx(hero, 180, 20, 0, -t * 2, 2)
  sprx(chars, 225, 20, t // 8 % 4, 0, 1 + math.sin(t / 15) * 0.5, 2, "x")

  -- Part of an image, stretched
  sspr(pal, 16, 16, 32, 32, 4, 46, 64, 64)
  sspr(hero, 4, 4, 8, 8, 72, 46, 32, 32)

  -- Other PNG kinds
  spr(pal, 110, 46)
  spr(rgba, 180, 46)
  spr(gray, 230, 46)
  sspr(gray, 0, 0, 16, 16, 180, 76, 64, 32)

  -- Tint: one color, corner gradient, translucent sprite
  tint(2)
  spr(hero, 4, 116)
  tint(10, 4, 2, 6)
  sspr(hero, 0, 0, 16, 16, 24, 116, 48, 48)
  tint()
  alpha(0.5)
  sprx(hero, 100, 140, 0, 0, 3)
  alpha()

  -- Zoom: a 2x view in a clipped window
  rect(140, 112, 112, 76, 12)
  clip(141, 113, 110, 74)
  -- screen = (world - camera) * 2: world 0, 0 lands near 150, 120
  camera(-75 + t % 40 // 2, -60, 2)
  spr(hero, 0, 0)
  spr(chars, 18, 0, 2)
  circ(8, 8, 10, 11)
  line(-10, 20, 40, 20, 4)
  camera()
  clip()
end

local function stress_scene()
  cls(0)
  for i = 1, count do
    local x = (i * 37 + t) % 240
    local y = (i * 53) % 176
    spr(chars, x, y, i % 4)
  end
end

function _draw(screen)
  if screen == TOP then
    local t0 = micros()
    if stress then stress_scene() else scene() end
    draw_us = draw_us + (micros() - t0)
    frames = frames + 1
  else
    if frames >= 30 then
      local what = stress and (count .. " sprites") or "scene"
      status = ("%s: draw %d us/frame"):format(what, draw_us // frames)
      log(status)
      draw_us, frames = 0, 0
    end
    cls(0)
    draw_out()
    text(status, 0, 184, 4)
  end
end

say(fails == 0 and "ALL OK" or (fails .. " FAILED"))
