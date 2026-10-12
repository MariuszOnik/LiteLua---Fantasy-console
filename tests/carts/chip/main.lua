-- LiteLua S0 test (D40): live chiptune synthesis on the DS sound channels,
-- together with Maxmod (sound effects and a module from P7).
-- X: synth on/off   Y: mode 0 (parameters in place) / 1 (restart channels)
-- A: beep (Maxmod effect)   B: boom   SELECT: module music on/off
-- The numbers are written to the log every 2 seconds. L+R+B: back.

local beep, boom = sound("beep"), sound("boom")
local mode, module_on, t = 0, false, 0
local lines = {}

local function say(s)
  log(s)
  table.insert(lines, 1, s)
  if #lines > 9 then table.remove(lines) end
end

local function report()
  local s = chiptest.stats()
  say(("synth %s mode %d: irq max %d us avg %d us, gap %d..%d us, late %d, fifo %d/s"):format(
    s.on and "on" or "off", s.mode, s.irq_max_us, s.irq_avg_us, s.gap_min_us, s.gap_max_us,
    s.late, s.ticks > 0 and s.msgs * 60 // s.ticks or 0))
end

function _init()
  chiptest.start(mode)
  say("synth started (mode 0)")
end

function _update()
  t = t + 1
  if btnp("x") then
    if chiptest.stats().on then chiptest.stop() say("synth stopped")
    else chiptest.start(mode) say("synth started") end
  end
  if btnp("y") then
    mode = 1 - mode
    chiptest.start(mode)
    say("mode " .. mode .. (mode == 0 and " (in place)" or " (restart)"))
  end
  if btnp("a") then say("beep: " .. tostring(sfx(beep))) end
  if btnp("b") then say("boom: " .. tostring(sfx(boom))) end
  if btnp("select") then
    module_on = not module_on
    if module_on then music("song") else music() end
    say("module " .. (module_on and "on" or "off"))
  end
  if t % 60 == 0 and chiptest.stats().on then report() end
end

function _draw(surface)
  cls(surface == TOP and 1 or 0)
  if surface == TOP then
    text("S0: live chiptune (D40)", 4, 4, 12)
    text("X synth on/off  Y mode in place/restart", 4, 20, 13)
    text("A beep  B boom  SELECT module", 4, 30, 13)
    local s = chiptest.stats()
    text(("mode %d  ticks %d"):format(s.mode, s.ticks), 4, 50, 4)
    text(("irq max %d us  avg %d us"):format(s.irq_max_us, s.irq_avg_us), 4, 60, 4)
    text(("tick gap %d .. %d us  late %d"):format(s.gap_min_us, s.gap_max_us, s.late), 4, 70, 4)
  else
    for i, s in ipairs(lines) do text(s, 2, 2 + (i - 1) * 10, i == 1 and 12 or 13) end
  end
end
