-- HeroesDS C4a: speed of the combat engine. The same code runs on the DS (main.lua) and on
-- a PC (tools/make_c4bench.py through lupa), so the timings and the end states compare.
--
-- bench.reachable(env) times Battle:reachable for every stack of a fresh battle;
-- bench.battle(env, seed) plays one computer-vs-computer battle (the setup of ai_test.lua's
-- real_auto_battles) and times every ai.act, with the time spent in the spell choice
-- (ai.best_spell) and in path search (grid.reachable) inside it.
-- env: { clock = microseconds, creatures, spells, yield = called between turns,
--        slice = us }: with `slice`, run inside a coroutine, a turn yields at grid.tick()
-- once its slice is used up (H11) - the time away does not count, and r.stall is the
-- longest piece of work between two yields.

local stats = require("combat.stats")
local battle = require("combat.battle")
local heroes = require("combat.heroes")
local abilities = require("combat.abilities")
local casting = require("combat.casting")
local grid = require("combat.grid")
local ai = require("combat.ai")
abilities.install(battle)
casting.install(battle)

local bench = {}

-- The clock without the time spent yielded
local clock, paused = nil, 0
local function active() return clock() - paused end

-- Time spent in the wrapped functions, in microseconds, while `acc` is set
local acc
local function timed(name, f)
  return function(...)
    if not acc then return f(...) end
    local t0 = active()
    local r = table.pack(f(...))
    acc[name] = (acc[name] or 0) + active() - t0
    return table.unpack(r, 1, r.n)
  end
end
ai.best_spell = timed("spell", ai.best_spell)
grid.reachable = timed("path", grid.reachable)

local function keys_of(creatures)
  local keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- The armies of ai_test.lua's auto_battle
function bench.new_battle(env, seed)
  local creatures, keys = env.creatures, keys_of(env.creatures)
  local function st(i, n) local k = keys[(i - 1) % #keys + 1]; return stats.creature(k, creatures[k], n) end
  local att = { heroes.stack({ name = "A", level = 8, skills = { chaos = 3, life = 3, combat = 2 },
                               spells = { "fireball", "bless", "magic arrow", "lightning" } }, {}),
                st(seed, 15), st(seed * 3 + 1, 8), st(seed * 7 + 2, 30) }
  local def = { heroes.stack({ name = "D", level = 8, skills = { death = 3, order = 3, archery = 2 },
                               spells = { "curse", "slow", "magic arrow" } }, {}),
                st(seed * 11 + 3, 12), st(seed * 13 + 4, 20), st(seed * 17 + 5, 6) }
  return battle.new({ seed = seed * 7919, spells = env.spells, creatures = creatures,
                      sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
end

-- Battle:reachable without its cache, `runs` times for every stack: { avg, worst } in us
function bench.reachable(env, runs)
  clock, paused = env.clock, 0
  local b = bench.new_battle(env, 1)
  local sum, n, worst = 0, 0, 0
  for _, u in ipairs(b.units) do
    for _ = 1, runs or 10 do
      b.reach_cache = nil
      local t0 = clock()
      b:reachable(u)
      local t = clock() - t0
      sum, n, worst = sum + t, n + 1, math.max(worst, t)
    end
    if env.yield then env.yield() end
  end
  return { avg = sum // n, worst = worst }
end

-- With pathgrid: does the C search give the same costs and parents as the Lua one for
-- every stack? Returns the number of differing entries
function bench.compare(env)
  local b = bench.new_battle(env, 1)
  local diff = 0
  local function same(a, c)
    for k, v in pairs(a) do if c[k] ~= v or math.type(c[k]) ~= math.type(v) then diff = diff + 1 end end
    for k in pairs(c) do if a[k] == nil then diff = diff + 1 end end
  end
  for _, u in ipairs(b.units) do
    for _, far in ipairs({ 1, 12 }) do
      local m = b:mover(u, b:move_budget(u) * far)
      local c1, p1 = grid.reachable(b.field, b.units, m)
      grid.native = false
      local c2, p2 = grid.reachable(b.field, b.units, m)
      grid.native = true
      same(c1, c2); same(p1 or {}, p2 or {})
    end
  end
  return diff
end

-- One battle to the end: turns, rounds, winner, times in us (total, avg and worst turn,
-- spell choice, path search, longest stall) and the checksum of the end state
function bench.battle(env, seed, limit)
  clock, paused = env.clock, 0
  local b = bench.new_battle(env, seed)
  b:take_events()
  local r = { seed = seed, turns = 0, total = 0, worst = 0, stall = 0, slices = 0 }
  local start -- active time when the current slice began
  if env.slice then
    grid.tick = function()
      local now = clock()
      if now - start >= env.slice and coroutine.isyieldable() then
        r.stall = math.max(r.stall, now - start)
        r.slices = r.slices + 1
        coroutine.yield(r)
        paused = paused + clock() - now
        start = clock()
      end
    end
  end
  acc = {}
  for _ = 1, limit or 2000 do
    if b.finished or not b:current() then break end
    local u = b:current()
    local t0 = active()
    start = clock()
    assert(ai.act(b))
    r.stall = math.max(r.stall, clock() - start)
    local t = active() - t0
    if t > (r.worst_t or 0) then r.worst_t, r.worst_who = t, (u.name or "?") .. " r" .. b.round end
    r.mem = math.max(r.mem or 0, collectgarbage("count") // 1)
    b:take_events()
    r.turns, r.total, r.worst = r.turns + 1, r.total + t, math.max(r.worst, t)
    if env.yield then env.yield(r) end
  end
  grid.tick = function() end
  r.spell, r.path = acc.spell or 0, acc.path or 0
  acc = nil
  r.avg = r.turns > 0 and r.total // r.turns or 0
  r.rounds, r.finished, r.winner = b.round, b.finished, b.winner
  r.checksum = b:checksum()
  return r
end

return bench
