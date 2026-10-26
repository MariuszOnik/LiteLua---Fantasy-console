-- HeroesDS H2b: can LiteLua load and animate Heroes IV units, and which look
-- works on the DS?
-- Top screen: a duel, bandit (bottom left, ne) vs black dragon (top right, sw),
-- in one of three styles (L / R): oldschool, smooth, current (DS_GRAPHICS.md).
-- Only "wait" stays loaded; an attack loads the attacker's melee and the
-- defender's flinch (the stall is shown) and frees the previous ones.
-- X: measure load time and video memory of the style's atlases, and
-- load/free cycles, step by step (a coroutine), so the screens keep updating.
-- Results on the bottom screen and in litelua/log.txt.

local CYCLES = 10
local UNITS = { bandit = { dir = "ne", x = 70, y = 176 },
                dragon = { dir = "sw", x = 178, y = 112 } }
local STATES = { "wait", "melee", "flinch" }

local styles = dofile("data/styles.lua")
local style_i = 1

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
-- per rectangle) and the shadow atlas (drawn with sspr, enlarged szoom times)
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
    alpha(a.salpha)
    sspr(a.simg, r[1], r[2], r[3], r[4], x + r[5], y + r[6], r[3] * z, r[4] * z)
    alpha()
  end
  local i = a.frames[f]
  if i > 0 then
    local r = a.rects[i]
    spr(a.subs[i], x + r[5], y + r[6])
  end
end

local function anim_name(unit, state)
  return styles[style_i] .. "_" .. unit .. "_" .. state
end

-- --- measurement (a coroutine) ---------------------------------------------------

local function measure()
  out = {}
  free_all()
  local base = vram()
  say(("style %s, VRAM at start %d KB"):format(styles[style_i], base // 1024))
  say("anim              ms   KB  atlas")
  for unit in pairs(UNITS) do
    for _, st in ipairs(STATES) do
      local name = anim_name(unit, st)
      local t0 = micros()
      local a = load_anim(name)
      local us = micros() - t0
      local used = vram() - base
      local size = ("%dx%d"):format(a.img.w, a.img.h)
      a = nil
      free_all()
      say(("%-15s %6.1f %4d  %s%s"):format(unit .. " " .. st, us / 1000, used // 1024, size,
          vram() == base and "" or " LEAK"))
      coroutine.yield()
    end
  end
  local t0, peak, idle = micros(), 0, 0
  local progress = #out + 1 -- A line of the screen only, not logged
  for c = 1, CYCLES do
    local keep = {}
    for unit in pairs(UNITS) do
      for _, st in ipairs(STATES) do keep[#keep + 1] = load_anim(anim_name(unit, st)) end
    end
    peak = math.max(peak, vram() - base)
    keep = nil
    free_all()
    out[progress] = ("cycle %d/%d"):format(c, CYCLES)
    local t1 = micros()
    coroutine.yield()
    idle = idle + micros() - t1
  end
  out[progress] = nil
  say(("all 6 anims at once: %d KB, load %.0f ms"):format(peak // 1024,
      (micros() - t0 - idle) / CYCLES / 1000))
  say(vram() == base and "VRAM back after every cycle" or
      ("LEAK " .. (vram() - base) // 1024 .. " KB"))
end

-- --- the duel ------------------------------------------------------------------------

local units
local stall = "-"

local function new_unit(name)
  local u = UNITS[name]
  return { name = name, x = u.x, y = u.y, anims = { wait = load_anim(anim_name(name, "wait")) },
           state = "wait", t = 0 }
end

local function start_duel()
  units = nil
  free_all()
  units = { left = new_unit("bandit"), right = new_unit("dragon") }
  stall = ("-  VRAM %d KB"):format(vram() // 1024)
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
  att.anims.melee = load_anim(anim_name(att.name, "melee"))
  def.anims.flinch = load_anim(anim_name(def.name, "flinch"))
  stall = ("%.0f ms, VRAM %d KB"):format((micros() - t0) / 1000, vram() // 1024)
  print(styles[style_i] .. " attack: load " .. stall)
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

local job -- The measurement coroutine while it runs

start_duel()
out = { "A: bandit attacks   B: dragon attacks",
        "L / R: style        X: measure" }

function _update()
  if job then
    local ok, err = coroutine.resume(job)
    if not ok then error(err) end
    if coroutine.status(job) == "dead" then
      job = nil
      start_duel()
    end
    return
  end
  if btnp("l") or btnp("r") then
    style_i = (style_i + (btnp("r") and 0 or -2)) % #styles + 1 -- 1-based wrap
    start_duel()
    return
  end
  if btnp("a") then attack(units.left, units.right) end
  if btnp("b") then attack(units.right, units.left) end
  if btnp("x") then
    units = nil
    job = coroutine.create(measure)
    return
  end
  step(units.left)
  step(units.right)
end

function _draw(screen)
  if screen == TOP then
    cls(4)
    if not units then
      text("measuring...", 90, 90, 12)
      return
    end
    for _, u in ipairs({ units.right, units.left }) do -- Farther unit first
      local f, a = frame_of(u)
      draw_anim(a, math.min(f, #a.frames), u.x, u.y)
    end
    text("style: " .. styles[style_i] .. "  (L/R)", 2, 2, 12)
    text("load: " .. stall, 2, 184, 12)
  else
    cls(0)
    text("HeroesDS H2b", 0, 0, 13)
    for i, l in ipairs(out) do text(l, 0, 10 + (i - 1) * 9, 12) end
  end
end
