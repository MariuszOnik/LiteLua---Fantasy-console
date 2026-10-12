-- LiteLua sound test (P7). Sounds are made by make_assets.py.
-- A: beep   B: boom (stereo file, random pan)   Y: beep, random pitch
-- X: music: module (song.mas) -> streamed WAV (tune.wav) -> off
-- Up/Down: music volume   SELECT: free the sounds and load them again
-- (Lua memory must go back)   L+R+B: back to the list

local beep, boom
local tracks = { "song", "tune.wav", false }
local track = 0
local volume = 1
local lines = {}

local function say(s)
  log(s)
  table.insert(lines, 1, s)
  if #lines > 8 then table.remove(lines) end
end

local function load_sounds()
  beep = sound("beep")
  boom = sound("boom")
  say(("loaded: beep %.2f s, boom %.2f s (%d Hz)"):format(beep.length,
    boom.length, boom.rate))
end

local function mem_kb()
  return sys.stats().mem // 1024
end

function _init()
  load_sounds()
  say("mem " .. mem_kb() .. " KB")
end

function _update()
  if btnp("a") then say("beep: handle " .. tostring(sfx(beep))) end
  if btnp("b") then say("boom: handle " .. tostring(sfx(boom, 1, math.random() * 2 - 1))) end
  if btnp("y") then sfx(beep, 0.8, 0, 0.5 + math.random() * 1.5) end
  if btnp("x") then
    track = track % #tracks + 1
    local t = tracks[track]
    if t then music(t) else music() end
    say(("music %s, mem %d KB"):format(t or "off", mem_kb()))
  end
  if btnp("up") or btnp("down") then
    volume = math.max(0, math.min(1, volume + (btnp("up") and 0.1 or -0.1)))
    music_volume(volume)
    say(("music volume %.1f"):format(volume))
  end
  if btnp("select") then
    local before = mem_kb()
    sfx_stop()
    beep, boom = nil, nil
    collectgarbage()
    say(("freed: %d -> %d KB"):format(before, mem_kb()))
    load_sounds()
  end
end

function _quit()
  log("sound test: _quit, mem " .. mem_kb() .. " KB")
end

function _draw(surface)
  cls(surface == TOP and 1 or 0)
  if surface == TOP then
    text("Sound test (P7)", 4, 4, 12)
    text("A beep  B boom  Y pitch", 4, 24, 13)
    text("X music: module/stream/off", 4, 34, 13)
    text("Up/Down volume  SELECT reload", 4, 44, 13)
    text(("music: %s  volume %.1f"):format(tracks[track] or "off", volume), 4, 70, 4)
    text(("Lua + sound memory: %d KB"):format(mem_kb()), 4, 82, 4)
  else
    for i, s in ipairs(lines) do text(s, 2, 2 + (i - 1) * 10, i == 1 and 12 or 13) end
  end
end
