-- OOP benchmark (P10c, D54): the same class "Enemy" (5 fields, methods
-- update and hit) written five ways. For each: the time and the memory of
-- creating objects, and the time and the garbage of calling methods.
-- Results on the screens and in litelua/log.txt. A: run again.

local class = require("middleclass")

local NEW = 2000          -- Objects created per variant
local OBJS, FRAMES = 100, 100 -- Method calls: OBJS objects x FRAMES frames

-- --- the five variants -----------------------------------------------------

-- 1. Plain metatable: the fields in the constructor (the table is created
--    with room for them at once)
local Plain = {}
Plain.__index = Plain
function Plain.new(x, y)
  return setmetatable({ x = x, y = y, vx = 1, vy = 0, hp = 3 }, Plain)
end
function Plain:update() self.x = self.x + self.vx; self.y = self.y + self.vy end
function Plain:hit(n) self.hp = self.hp - n end

-- 2. middleclass: the fields are set one by one in initialize
local MC = class("MC")
function MC:initialize(x, y)
  self.x, self.y, self.vx, self.vy, self.hp = x, y, 1, 0, 3
end
function MC:update() self.x = self.x + self.vx; self.y = self.y + self.vy end
function MC:hit(n) self.hp = self.hp - n end

-- 3. A middleclass subclass: initialize and update inherited (one level)
local Sub = MC:subclass("Sub")
function Sub:hit(n) MC.hit(self, n * 2) end

-- 4. Closures: every object has its own functions (no self, no metatable)
local function closure_new(x, y)
  local o = { x = x, y = y, vx = 1, vy = 0, hp = 3 }
  function o.update() o.x = o.x + o.vx; o.y = o.y + o.vy end
  function o.hit(n) o.hp = o.hp - n end
  return o
end

-- 5. middleclass with allocate making room for the fields at once (the
--    trick from D54: no table growth in initialize)
local MCF = class("MCF")
function MCF.static:allocate()
  return setmetatable({ class = self, x = 0, y = 0, vx = 0, vy = 0, hp = 0 },
                      self.__instanceDict)
end
MCF.initialize = MC.initialize
MCF.update = MC.update
MCF.hit = MC.hit

local variants = {
  { "plain",   function(x, y) return Plain.new(x, y) end, ":" },
  { "mclass",  function(x, y) return MC:new(x, y) end, ":" },
  { "msub",    function(x, y) return Sub:new(x, y) end, ":" },
  { "closure", closure_new, "." },
  { "mc+room", function(x, y) return MCF:new(x, y) end, ":" },
}

-- --- measuring ---------------------------------------------------------------

local out = {}
local function say(s)
  out[#out + 1] = s
  print(s)
end

-- Runs f(a, b) with the garbage collector stopped: microseconds and the
-- bytes allocated meanwhile (memory kept and garbage alike)
local function measure(f, a, b)
  collectgarbage()
  collectgarbage("stop")
  local m0 = collectgarbage("count")
  local t0 = micros()
  f(a, b)
  local us = micros() - t0
  local kb = collectgarbage("count") - m0
  collectgarbage("restart")
  return us, kb * 1024
end

local keep -- Objects of the current variant (kept alive while measuring)

local function create(new)
  for i = 1, NEW do keep[i] = new(i, i) end
end

-- FRAMES frames of OBJS objects: update and hit on each
local function calls_colon(objs)
  for _ = 1, FRAMES do
    for i = 1, OBJS do
      local o = objs[i]
      o:update()
      o:hit(0)
    end
  end
end

local function calls_dot(objs)
  for _ = 1, FRAMES do
    for i = 1, OBJS do
      local o = objs[i]
      o.update()
      o.hit(0)
    end
  end
end

local function run()
  out = {}
  say(("new: %d objects; calls: %d x %d frames"):format(NEW, OBJS, FRAMES))
  say("variant  new us/obj B/obj  call us   garbage")
  for _, v in ipairs(variants) do
    local name, new, how = v[1], v[2], v[3]
    keep = {}
    for i = 1, NEW do keep[i] = false end -- The list itself is not measured
    local us_new, b_new = measure(create, new)

    local objs = {}
    for i = 1, OBJS do objs[i] = keep[i] end
    local calls = how == ":" and calls_colon or calls_dot
    calls(objs) -- Warm-up: one-time allocations (the call stack) not counted
    local us_call, b_call = measure(calls, objs)
    local n = OBJS * FRAMES * 2
    say(("%-8s %8.1f %5d %8.2f %6d B"):format(name, us_new / NEW, b_new // NEW,
        us_call / n, b_call // 1))
    keep = nil
  end
  say(("call us: one call; garbage: all %d calls"):format(OBJS * FRAMES * 2))
  say("(~100 B: the Lua stack growing again after")
  say("the full GC before measuring, not per call)")
  say(("Lua mem now: %d KB"):format(collectgarbage("count") // 1))
end

run()

function _update()
  if btnp("a") then run() end
end

function _draw(screen)
  cls(0)
  if screen == TOP then
    text("OOP benchmark (P10c)  A: run again", 0, 0, 13)
    for i, l in ipairs(out) do text(l, 0, 12 + (i - 1) * 10, 12) end
  else
    text("Results are also in litelua/log.txt", 0, 0, 13)
    text("B/obj: memory of one object (with", 0, 16, 14)
    text("the garbage its creation left)", 0, 26, 14)
    text("mc+room: middleclass, allocate makes", 0, 42, 14)
    text("room for the fields (see D54)", 0, 52, 14)
  end
end
