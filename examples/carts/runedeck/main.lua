-- Runedeck: a deck-building roguelike. Walk an ASCII dungeon; touching a
-- monster starts a card battle.
--   src/cards.lua, src/enemies.lua  game data (also read by tools/cardart.py)
--   src/battle.lua                  battle rules, no drawing
--   src/dungeon.lua                 the map: rooms, field of view, monsters
--   src/explore.lua, src/fight.lua  the two scenes (drawing and input)
--   src/ui.lua                      colors, images, sounds, buttons

local B = require("battle")
local D = require("dungeon")
local X = require("explore")
local F = require("fight")
local U = require("ui")

local scene        -- "explore", "fight", "over"
local foe          -- the map monster being fought
local won          -- true when the run ended with the boss beaten

local function enter_floor(n)
  D.generate(n)
  X.dirty()
  X.say(n == 1 and "You enter the ruins." or ("You go down to floor " .. n .. "."))
  if n > 1 then
    local h = B.heal_part(0.3)
    if h > 0 then X.say("You rest on the stairs: +" .. h .. " HP.") end
  end
  if D.last then X.say("Something big waits here...") end
  music()
end

local function new_run()
  B.new_run()
  X.clear_log()
  enter_floor(1)
  scene = "explore"
end

local function start_fight(m)
  foe = m
  local names = {}
  for i, id in ipairs(m.group) do names[i] = B.enemy_name(id) end
  X.say("Fight: " .. table.concat(names, ", ") .. "!")
  F.enter(m.group, D.hp_scale(), "Floor " .. D.floor)
  scene = "fight"
end

function _init()
  math.randomseed(micros())
  new_run()
end

function _update()
  if scene == "explore" then
    local res, m = X.update()
    if res == "fight" then
      start_fight(m)
    elseif res == "floor" then
      enter_floor(D.floor + 1)
    end
  elseif scene == "fight" then
    F.update()
    if F.result == "lost" then
      scene, won = "over", false
    elseif F.result == "won" then
      D.remove_monster(foe)
      if foe.boss then
        scene, won = "over", true
      else
        X.say("You won. HP " .. B.player.hp .. "/" .. B.player.max .. ".")
        X.dirty()
        music()
        scene = "explore"
      end
    end
  elseif scene == "over" then
    if btnp("a") or btnp("touch") then new_run() end
  end
end

function _draw(surface)
  if scene == "explore" then
    X.draw(surface)
  elseif scene == "fight" then
    F.draw(surface)
  elseif surface == TOP then
    cls(U.BG_TOP)
    U.center(won and "THE OGRE CHIEF FALLS!" or "YOU DIED", 80, U.GOLD)
    U.center(won and "You won the run." or ("on floor " .. D.floor .. " of " .. D.floors_total()), 96, 0xffffff)
  else
    cls(U.BG_BOT)
    U.center("Tap or press A for a new run", 90, U.GOLD)
  end
end
