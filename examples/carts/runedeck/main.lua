-- Runedeck: a deck-building roguelike. Walk an ASCII dungeon; touching a
-- monster starts a card battle.
--   src/cards.lua, src/enemies.lua  game data (also read by tools/cardart.py)
--   src/battle.lua                  battle rules, no drawing
--   src/dungeon.lua                 the map: rooms, field of view, monsters
--   src/items.lua, src/gear.lua     items, equipment and the deck they make
--   src/explore.lua, src/fight.lua, src/bag.lua  the scenes (drawing, input)
--   src/title.lua, src/save.lua     title screen, seed, saving the run
--   src/ui.lua                      colors, images, sounds, buttons

local B = require("battle")
local G = require("gear")
local D = require("dungeon")
local X = require("explore")
local F = require("fight")
local K = require("bag")
local T = require("title")
local S = require("save")
local U = require("ui")

local DROP_CHANCE = 60   -- % of won fights that leave an item

local scene        -- "title", "explore", "fight", "bag", "pick" (scroll), "over"
local foe          -- the map monster being fought
local won          -- true when the run ended with the boss beaten
local seed         -- of this run: the same seed makes the same floors

-- The floor comes from the seed alone, everything after it is random again
local function make_floor(n)
  math.randomseed(seed * 8 + n)
  D.generate(n)
  math.randomseed(micros())
  X.dirty()
end

local function save_run()
  S.save({ seed = seed, floor = D.floor, hp = B.player.hp,
           equip = G.equip, bag = G.bag, learned = G.learned })
end

local function enter_floor(n)
  make_floor(n)
  X.say(n == 1 and "You enter the ruins." or ("You go down to floor " .. n .. "."))
  if n > 1 then
    local h = B.heal_part(0.3)
    if h > 0 then X.say("You rest on the stairs: +" .. h .. " HP.") end
  end
  if D.last then X.say("Something big waits here...") end
  save_run()
  music("explore")
end

local function new_run(s)
  seed = s
  B.new_run()
  G.new_run()
  X.clear_log()
  X.say("Seed " .. seed .. ".")
  enter_floor(1)
  scene = "explore"
end

local function continue_run(run)
  seed = run.seed
  B.new_run()
  G.new_run()
  G.equip, G.bag, G.learned = run.equip or {}, run.bag or {}, run.learned or {}
  G.rebuild()
  B.player.hp = math.max(1, math.min(B.player.max, run.hp or B.player.max))
  X.clear_log()
  make_floor(run.floor)
  X.say("Floor " .. run.floor .. " again. Seed " .. seed .. ".")
  music("explore")
  scene = "explore"
end

local function to_title()
  T.enter(S.load())
  scene = "title"
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
  to_title()
end

function _update()
  if scene == "title" then
    local res, s = T.update()
    if res == "continue" then
      continue_run(S.load())
    elseif res == "new" then
      new_run(s)
    end
  elseif scene == "explore" then
    local res, m = X.update()
    if res == "fight" then
      start_fight(m)
    elseif res == "floor" then
      enter_floor(D.floor + 1)
    elseif res == "bag" then
      K.enter()
      scene = "bag"
    end
  elseif scene == "bag" then
    local res, i = K.update()
    if res == "close" then
      X.dirty()
      scene = "explore"
    elseif res == "read" then
      G.drop(i)
      F.enter_pick()
      scene = "pick"
    end
  elseif scene == "pick" then
    F.update()
    if F.result == "picked" then
      if F.picked then
        G.learn(F.picked)
        X.say("You learn " .. B.card(F.picked).name .. ".")
      end
      scene = "bag"
    end
  elseif scene == "fight" then
    F.update()
    if F.result == "lost" then
      scene, won = "over", false
      S.clear()
    elseif F.result == "won" then
      D.remove_monster(foe)
      if foe.boss then
        scene, won = "over", true
        S.clear()
      else
        X.say("You won. HP " .. B.player.hp .. "/" .. B.player.max .. ".")
        if math.random(100) <= DROP_CHANCE and not D.item_at(foe.x, foe.y) then
          D.add_item(foe.x, foe.y, G.roll_loot(D.floor))
          X.say("It dropped something.")
        end
        X.dirty()
        music("explore")
        scene = "explore"
      end
    end
  elseif scene == "over" then
    if btnp("a") or btnp("touch") then to_title() end
  end
end

function _draw(surface)
  if scene == "title" then
    T.draw(surface)
  elseif scene == "explore" then
    X.draw(surface)
  elseif scene == "fight" or scene == "pick" then
    F.draw(surface)
  elseif scene == "bag" then
    K.draw(surface)
  elseif surface == TOP then
    cls(U.BG_TOP)
    U.center(won and "THE OGRE CHIEF FALLS!" or "YOU DIED", 80, U.GOLD)
    U.center(won and "You won the run." or ("on floor " .. D.floor .. " of " .. D.floors_total()), 96, 0xffffff)
    U.center("Seed " .. seed, 112, 0xa09080)
  else
    cls(U.BG_BOT)
    U.center("Tap or press A", 90, U.GOLD)
  end
end
