-- Star Catcher - a small LiteLua example game.
--
-- Catch the falling stars with the basket, avoid the meteors.
-- Move with Left/Right, or touch the bottom screen. A: start / play again.
-- The best score is saved in save/best.txt (litelua/saves/starcatch/).

local particles = require("particles") -- src/particles.lua

local W, H = 256, 192
local BASKET_Y = H - 14

local state = "title" -- "title", "play" or "over"
local t = 0           -- frames since start (an integer clock, see "Numbers")
local score, best, lives = 0, 0, 3
local spawn_timer, shake = 0, 0

local player = { x = W // 2, w = 32, speed = 4 }

-- Falling things are kept in a pool too: dead ones are reused
local things = {}

-- Background stars, made once
local sky = {}

local function load_best()
  local f = io.open("save/best.txt")
  if f then
    best = tonumber(f:read("a")) or 0
    f:close()
  end
end

local function save_best()
  local f = io.open("save/best.txt", "w")
  if f then
    f:write(best)
    f:close()
  end
end

local function spawn()
  local thing
  for _, th in ipairs(things) do
    if not th.alive then thing = th break end
  end
  if not thing then
    thing = {}
    things[#things + 1] = thing
  end

  -- More meteors and faster falls as the score grows
  local meteor_chance = 0.2 + math.min(score, 60) / 200
  thing.alive = true
  thing.meteor = math.random() < meteor_chance
  thing.x = math.random(10, W - 10)
  thing.y = -10
  thing.vy = 1 + math.random() * (1 + score / 25)
end

local function new_game()
  score, lives, spawn_timer, shake = 0, 3, 0, 0
  player.x = W // 2
  for _, th in ipairs(things) do th.alive = false end
  state = "play"
end

function _init()
  load_best()
  for i = 1, 50 do
    sky[i] = { x = math.random(0, W - 1), y = math.random(0, H - 1),
               phase = math.random(0, 59) }
  end
end

local function update_play()
  -- Move: buttons or the touch screen (the basket follows the finger)
  if btn("left") then player.x = player.x - player.speed end
  if btn("right") then player.x = player.x + player.speed end
  local tx = touch()
  if tx then player.x = player.x + (tx - player.x) * 0.3 end
  local half = player.w // 2
  player.x = math.max(half, math.min(W - half, player.x))

  spawn_timer = spawn_timer - 1
  if spawn_timer <= 0 then
    spawn()
    spawn_timer = math.max(10, 32 - score // 3)
  end

  for _, th in ipairs(things) do
    if th.alive then
      th.y = th.y + th.vy
      local caught = th.y >= BASKET_Y - 4 and th.y <= BASKET_Y + 4
                     and math.abs(th.x - player.x) <= half + 3
      if caught then
        th.alive = false
        if th.meteor then
          lives = lives - 1
          shake = 12
          particles.burst(th.x, th.y, 2, 24)
          if lives == 0 then
            state = "over"
            if score > best then
              best = score
              save_best()
            end
          end
        else
          score = score + 1
          particles.burst(th.x, th.y, 4, 10)
        end
      elseif th.y > H + 10 then
        th.alive = false -- missed: no penalty for stars
      end
    end
  end
end

function _update()
  t = t + 1
  if shake > 0 then shake = shake - 1 end
  particles.update()

  if state == "play" then
    update_play()
  elseif btnp("a") or btnp("touch") then
    new_game()
  end
end

-- Text centered on the screen; with zoom 2 the screen is 128 wide
local function center(s, y, col, zoom)
  zoom = zoom or 1
  local w = textw(s)
  camera(0, 0, zoom)
  text(s, (W // zoom - w) // 2, y, col)
  camera()
end

local function draw_top()
  cls(0)

  -- Shake the world when a meteor hits
  local sx = shake > 0 and math.random(-2, 2) or 0
  camera(sx, 0)

  for _, s in ipairs(sky) do
    local twinkle = (t + s.phase) % 60 < 30
    pset(s.x, s.y, twinkle and 13 or 14)
  end

  for _, th in ipairs(things) do
    if th.alive then
      if th.meteor then
        circfill(th.x, th.y, 5, 2)
        circ(th.x, th.y, 6, 3)
      else
        circfill(th.x, th.y, 3, 4)
        line(th.x - 5, th.y, th.x + 5, th.y, 4)
        line(th.x, th.y - 5, th.x, th.y + 5, 4)
      end
    end
  end

  if state ~= "title" then
    local half = player.w // 2
    rectfill(player.x - half, BASKET_Y, player.w, 6, 10)
    rect(player.x - half, BASKET_Y - 3, player.w, 9, 11)
  end

  particles.draw()
  camera()

  if state == "title" then
    center("STAR CATCHER", 30, 4, 2)
    center("catch the stars, avoid the meteors", 100, 12)
    if t // 15 % 2 == 0 then center("press A or touch", 130, 11) end
  elseif state == "over" then
    center("GAME OVER", 30, 2, 2)
    center("score " .. score, 100, 12)
    if t // 15 % 2 == 0 then center("A: play again", 130, 11) end
  end
end

local function draw_bottom()
  cls(15)
  rectfill(0, 0, W, 14, 8)
  text("STAR CATCHER", 4, 3, 4)
  text(("score %d"):format(score), 4, 24, 12)
  text(("best  %d"):format(best), 4, 36, 13)

  for i = 1, 3 do
    circfill(W - 60 + i * 14, 28, 5, i <= lives and 2 or 1)
  end

  -- Touch area: the basket follows your finger here
  rectfill(0, 150, W, 42, 1)
  text("touch here to move", 74, 154, 13)
  if state == "play" then
    rectfill(player.x - player.w // 2, 172, player.w, 8, 10)
  end
end

function _draw(screen)
  if screen == TOP then draw_top() else draw_bottom() end
end
