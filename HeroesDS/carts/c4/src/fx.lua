-- HeroesDS C4: sounds and actor facts from the original game (tools/make_c4.py --fx).
-- Sounds: sfx/<actor>_<melee|ranged|flinch|die>.wav and sfx/spell_<spell>.wav (8-bit
-- 11025 Hz: their memory counts in the Lua limit), loaded when first played, freed when
-- not played for a while. data/actors.lua: each actor's height (screen px at 3/16, where
-- spell effects hang) and the missile it shoots.

local sprites = require("sprites")

local fx = {}

local f = loadfile("data/actors.lua")
local actors = f and f() or {}

local sounds = {}     -- [name] = { snd, last } or false (no such file)
local clock = 0
local KEEP = 600      -- frames a sound stays loaded unplayed

-- The actor (creature key or hero actor) of a stack
function fx.actor(u) return u.actor or u.kind end

function fx.height(u)
  local a = actors[sprites.base(fx.actor(u))]
  return a and a.height or 12
end

function fx.missile(u)
  local a = actors[sprites.base(fx.actor(u))]
  return a and a.missile
end

-- Plays sfx/<name>.wav when there is one; true if it played
function fx.play(name, vol)
  local s = sounds[name]
  if s == nil then
    local ok, snd = pcall(sound, name)
    s = ok and snd and { snd = snd } or false
    sounds[name] = s
  end
  if not s then return false end
  s.last = clock
  sfx(s.snd, vol or 1)
  return true
end

-- A stack's sound: "melee", "ranged" (else melee), "flinch", "die"
function fx.stack(u, what)
  local base = sprites.base(fx.actor(u))
  if fx.play(base .. "_" .. what) then return end
  if what == "ranged" then fx.play(base .. "_melee") end
end

-- A spell's sound (the game plays Curse's when the spell has none)
function fx.spell(key)
  if not fx.play("spell_" .. sprites.base(key)) then fx.play("spell_curse") end
end

-- Once a frame: frees the sounds not played for KEEP frames
function fx.tick()
  clock = clock + 1
  if clock % 120 ~= 0 then return end
  for name, s in pairs(sounds) do
    if s and clock - s.last > KEEP then sounds[name] = nil end
  end
end

return fx
