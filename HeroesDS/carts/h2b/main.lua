-- HeroesDS H2b: can LiteLua load and animate Heroes IV units?
-- 1. Load time and video memory of every atlas in data/list.lua.
-- 2. Load/free cycles of atlases of different sizes: does video memory come
--    back each time (no leak, no fragmentation errors)?
-- 3. A duel on the top screen: bandit (ne) vs bandit (sw). Only "wait" stays
--    loaded; an attack loads the attacker's melee and the defender's flinch
--    (the stall is shown), and frees the previous ones.
-- Results on the bottom screen and in litelua/log.txt.

local CYCLES = 20
local CYCLE_SET = { "bandit_wait_ne", "bandit_melee_ne", "bandit_flinch_sw",
                    "black_dragon_melee_sw_16c" }
local SHADOW_ALPHA = 0.45

local out = {}
local function say(s)
  out[#out + 1] = s
  print(s)
end

local function vram() return sys.stats().vram end

local function free_all()
  collectgarbage()
  collectgarbage()
end

-- --- animations --------------------------------------------------------------

-- Loads an animation: meta from data/<name>.lua, the atlas (one sub() image
-- per rectangle) and the shadow atlas (drawn enlarged with sspr)
local function load_anim(name)
  local a = dofile("data/" .. name .. ".lua")
  a.img = image(a.image)
  a.subs = {}
  for i, r in ipairs(a.rects) do a.subs[i] = sub(a.img, r[1], r[2], r[3], r[4]) end
  if a.shadow then a.simg = image(a.shadow) end
  return a
end

-- Draws frame f (1-based) of animation a with its ground point at x, y
local function draw_anim(a, f, x, y)
  local s = a.sframes[f]
  if a.simg and s > 0 then
    local r, z = a.srects[s], a.szoom
    alpha(SHADOW_ALPHA)
    sspr(a.simg, r[1], r[2], r[3], r[4], x + r[5], y + r[6], r[3] * z, r[4] * z)
    alpha()
  end
  local i = a.frames[f]
  if i > 0 then
    local r = a.rects[i]
    spr(a.subs[i], x + r[5], y + r[6])
  end
end

-- --- 1 and 2: measurement -------------------------------------------------------

local function measure()
  out = {}
  local list = dofile("data/list.lua")
  free_all()
  local base = vram()
  say(("VRAM at start: %d KB"):format(base // 1024))
  say("atlas                   ms   KB free")
  for _, name in ipairs(list) do
    local t0 = micros()
    local a = load_anim(name)
    local us = micros() - t0
    local used = vram() - base
    local info = ("  %dx%d, %d frames"):format(a.img.w, a.img.h, #a.frames)
    a = nil
    free_all()
    local back = vram() == base and "ok" or ("+" .. (vram() - base) // 1024)
    say(("%-21s %5.1f %4d %s"):format(name:sub(1, 21), us / 1000, used // 1024, back))
    say(info)
  end
  local t0, peak = micros(), 0
  for _ = 1, CYCLES do
    local keep = {}
    for i, n in ipairs(CYCLE_SET) do keep[i] = load_anim(n) end
    peak = math.max(peak, vram() - base)
    keep = nil
    free_all()
  end
  local us = micros() - t0
  say(("%d cycles of %d anims: %.0f ms each"):format(CYCLES, #CYCLE_SET, us / CYCLES / 1000))
  say(("peak %d KB, after: %s"):format(peak // 1024,
      vram() == base and "VRAM back" or ("LEAK " .. (vram() - base) // 1024 .. " KB")))
end

-- --- 3: the duel ------------------------------------------------------------------

local units
local stall = "-"

local function unit(prefix, dir, x, y)
  return { prefix = prefix, dir = dir, x = x, y = y,
           anims = { wait = load_anim(prefix .. "_wait_" .. dir) },
           state = "wait", t = 0 }
end

local function play(u, state)
  u.state, u.t = state, 0
end

-- Frame of the current animation (1-based) after t game frames at 30 FPS
local function frame_of(u)
  local a = u.anims[u.state]
  return u.t * a.fps // 30 + 1, a
end

local function attack(att, def)
  if att.state ~= "wait" or def.state ~= "wait" then return end
  local t0 = micros()
  for _, u in ipairs({ att, def }) do u.anims.melee, u.anims.flinch = nil, nil end
  free_all()
  att.anims.melee = load_anim(att.prefix .. "_melee_" .. att.dir)
  def.anims.flinch = load_anim(def.prefix .. "_flinch_" .. def.dir)
  stall = ("%.0f ms, VRAM %d KB"):format((micros() - t0) / 1000, vram() // 1024)
  print("attack: load " .. stall)
  play(att, "melee")
  att.target = def
end

local function step(u)
  u.t = u.t + 1
  local f, a = frame_of(u)
  -- The blow lands hit frames after the swing starts (FORMATS.md)
  if u.target and u.t * a.fps // 30 >= a.hit then
    play(u.target, "flinch")
    u.target = nil
  end
  if f > #a.frames then play(u, "wait") end
end

local function start()
  measure()
  units = { left = unit("bandit", "ne", 64, 172), right = unit("bandit", "sw", 186, 92) }
  say(("duel loaded: VRAM %d KB"):format(vram() // 1024))
end

start()

function _update()
  if btnp("a") then attack(units.left, units.right) end
  if btnp("b") then attack(units.right, units.left) end
  if btnp("x") then
    units = nil
    start()
  end
  step(units.left)
  step(units.right)
end

function _draw(screen)
  if screen == TOP then
    cls(4)
    for _, u in ipairs({ units.right, units.left }) do -- Farther unit first
      local f, a = frame_of(u)
      draw_anim(a, math.min(f, #a.frames), u.x, u.y)
    end
    text("A: left attacks  B: right attacks", 2, 2, 12)
    text("load: " .. stall, 2, 182, 12)
  else
    cls(0)
    text("HeroesDS H2b  X: measure again", 0, 0, 13)
    for i, l in ipairs(out) do text(l, 0, 10 + (i - 1) * 8, 12) end
  end
end
