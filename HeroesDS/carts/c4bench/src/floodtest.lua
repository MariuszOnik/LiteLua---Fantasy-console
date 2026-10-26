-- HeroesDS C4a: what one big pathgrid search costs on the DS (a flyer over the whole field)
local grid = require("combat.grid")

return function(say)
  local g = grid.shape():clone()
  local N = grid.N
  local function run(opts, label)
    collectgarbage()
    local t0 = micros()
    local cost, _, prof = g:flood(opts)
    local t = micros() - t0
    local n = 0
    for _ in pairs(cost) do n = n + 1 end
    say(("%s: %d cells %d.%d ms"):format(label, n, t // 1000, t % 1000 // 100))
    if prof then say(("  prep %d search %d results %d us, %d pushes"):format(prof.prep, prof.search, prof.results, prof.pushes)) end
  end
  local base = { x = 45, y = 45, size = 5, budget = 38 * 32, fly = true, columns = true }
  run(base, "fly int")
  base.div = 32
  run(base, "fly div")
  collectgarbage("stop")
  run(base, "fly div no GC")
  collectgarbage("restart")
  base.fly = false
  run(base, "walk div")
  base.budget = 4 * 32; base.steps = { 1, 0, 32, -1, 0, 32, 0, 1, 32, 0, -1, 32, 1, 1, 48, -1, -1, 48, 1, -1, 48, -1, 1, 48 }
  run(base, "walk small")
end
