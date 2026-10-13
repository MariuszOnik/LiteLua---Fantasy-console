-- LiteLua S1 test (D41): .lsong songs played live by the sequencer on the DS
-- sound channels (no WAV). X: next song   Up/Down: volume   A: beep (a
-- Maxmod effect at the same time)   B: play the current song once
-- Your own private songs (never in the repository): music/private.lsong,
-- private2.lsong .. private9.lsong

local songs = { "sky", "rock" }
for k = 1, 9 do
  local name = k == 1 and "private" or ("private" .. k)
  local f = io.open("music/" .. name .. ".lsong")
  if f then
    f:close()
    songs[#songs + 1] = name
  end
end

local beep = sound("beep")
local current, volume = 0, 1
local lines = {}

local function say(s)
  log(s)
  table.insert(lines, 1, s)
  if #lines > 9 then table.remove(lines) end
end

local function play(loop)
  local name = songs[current]
  local t0 = micros()
  music(name, loop)
  say(("%s: loaded in %d ms, mem %d KB%s"):format(name, (micros() - t0) // 1000,
    sys.stats().mem // 1024, loop and "" or " (once)"))
end

function _init()
  say(#songs .. " songs")
end

function _update()
  if btnp("x") then
    current = current % #songs + 1
    play(true)
  end
  if btnp("b") and current > 0 then play(false) end
  if btnp("a") then say("beep: " .. tostring(sfx(beep))) end
  if btnp("up") or btnp("down") then
    volume = math.max(0, math.min(1, volume + (btnp("up") and 0.1 or -0.1)))
    music_volume(volume)
    say(("volume %.1f"):format(volume))
  end
end

function _draw(surface)
  cls(surface == TOP and 1 or 0)
  if surface == TOP then
    text("Live songs (S1)", 4, 4, 12)
    text("X next song  B once  A beep", 4, 20, 13)
    text("Up/Down volume", 4, 30, 13)
    text(("now: %s  volume %.1f"):format(songs[current] or "-", volume), 4, 50, 4)
    local s = sys.stats()
    text(("cpu %d%%  update %d us"):format(s.cpu, s.update_us), 4, 60, 4)
  else
    for i, s in ipairs(lines) do text(s, 2, 2 + (i - 1) * 10, i == 1 and 12 or 13) end
  end
end
