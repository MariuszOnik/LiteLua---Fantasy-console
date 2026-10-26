-- HeroesDS C4a: how fast is the combat engine on the DS?
-- Loads the engine and the rules, times path search, then plays computer-vs-computer
-- battles. The computer's turn runs in a coroutine and yields every SLICE us (H11), so
-- the hourglass on the top screen keeps turning; a stutter there = a long stall.
-- End states are compared with the PC run (data/pc.lua, tools/make_c4bench.py): the
-- engine must give the same battle bit for bit.

local SLICE = 20000   -- us of work per frame during the computer's turn
local BATTLES = 12

local out = {}
local function say(s)
  out[#out + 1] = s
  if #out > 20 then table.remove(out, 1) end
  print(s)
end

local function ms(us) return ("%d.%d"):format(us // 1000, us % 1000 // 100) end

local status = "loading"
local turn -- the battle being played: { seed, turns, stall } so far
local frame = 0

local function run()
  local t0, m0 = micros(), collectgarbage("count")
  local bench = require("bench")
  local t1 = micros()
  local creatures = dofile("data/creatures.lua")
  local spells = dofile("data/spells.lua")
  local t2 = micros()
  collectgarbage()
  say(("load: code %s ms, rules %s ms, %d KB"):format(ms(t1 - t0), ms(t2 - t1),
    (collectgarbage("count") - m0) // 1))
  if pathgrid then
    local t = micros()
    require("combat.grid").shape()
    say(("field shape for pathgrid: %s ms"):format(ms(micros() - t)))
  end
  local pcf = loadfile("data/pc.lua")
  local pc = pcf and pcf() or {}

  local env = { clock = micros, creatures = creatures, spells = spells, slice = SLICE,
                yield = function(r) coroutine.yield(r) end }
  status = "path search"
  local r = bench.reachable(env, 5)
  say(("reachable: avg %s ms, worst %s ms%s"):format(ms(r.avg), ms(r.worst),
    pc.reach and (" (PC x%d)"):format(r.avg // math.max(1, pc.reach.avg)) or ""))
  say(r.diff and ("C vs Lua search: %d differences"):format(r.diff) or "no pathgrid: Lua search")

  collectgarbage()
  say(("Lua memory now %d KB, peak so far %d KB"):format(collectgarbage("count") // 1,
    sys.stats().mem_peak // 1024))
  local same, sum_avg, worst, stall = 0, 0, 0, 0
  for seed = 1, BATTLES do
    status = "battle " .. seed
    local b = bench.battle(env, seed)
    local ref = pc.battles and pc.battles[seed]
    local ok = ref and ref.checksum == b.checksum
    if ok then same = same + 1 end
    sum_avg = sum_avg + b.avg
    worst, stall = math.max(worst, b.worst), math.max(stall, b.stall)
    say(("#%d %dr %dt avg%d max%d st%d %s"):format(seed, b.rounds, b.turns, b.avg // 1000,
      b.worst // 1000, b.stall // 1000, ref and (ok and "=PC" or "DIFF") or ""))
    log(("  spell %s ms, path %s ms of %s ms; %d slices"):format(ms(b.spell), ms(b.path),
      ms(b.total), b.slices))
    if ref and not ok then log("  DS: " .. b.checksum, "\n  PC: " .. ref.checksum) end
  end
  say(("turn avg %s ms, worst %s ms, stall %s ms"):format(ms(sum_avg // BATTLES), ms(worst), ms(stall)))
  say(("same as PC: %d / %d   mem peak %d KB"):format(same, BATTLES, sys.stats().mem_peak // 1024))
  status = "done"
end

local job = coroutine.create(run)
say(("%s %d MHz"):format(sys.info().console, sys.info().cpu_mhz))

function _update()
  frame = frame + 1
  if job and coroutine.status(job) ~= "dead" then
    local ok, r = coroutine.resume(job)
    if not ok then error(r) end
    if type(r) == "table" then turn = r end
  end
end

-- An hourglass turning over every second: it moves only while frames are drawn
local function hourglass(cx, cy)
  local a = (frame % 30) / 30 * math.pi
  local c, s = math.cos(a), math.sin(a)
  local function p(x, y) return cx + x * c - y * s, cy + x * s + y * c end
  local x1, y1 = p(-12, -16); local x2, y2 = p(12, -16); local x3, y3 = p(0, 0)
  trifill(x1, y1, x2, y2, x3, y3, 10)
  x1, y1 = p(-12, 16); x2, y2 = p(12, 16)
  trifill(x1, y1, x2, y2, x3, y3, 9)
end

function _draw(screen)
  if screen == TOP then
    cls(1)
    text("HeroesDS C4a: combat speed", 2, 2, 12)
    text(status, 2, 14, 12)
    if turn and turn.turns then
      text(("turns %d  stall %s ms"):format(turn.turns, ms(turn.stall)), 2, 26, 12)
    end
    if status ~= "done" then hourglass(128, 110) end
    text(("fps %d"):format(sys.stats().fps), 2, 182, 12)
  else
    cls(0)
    for i, l in ipairs(out) do text(l, 0, (i - 1) * 9, 12) end
  end
end
