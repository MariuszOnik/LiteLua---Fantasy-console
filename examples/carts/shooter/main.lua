-- Shooter: a tiny example of classes (middleclass) split into modules.
--   src/entity.lua  Entity - the base class (box, overlaps, draw)
--   src/player.lua  Player - d-pad and A
--   src/enemy.lua   Enemy and Tough (a subclass that takes 3 hits)
--   src/bullet.lua  Bullet and its pool
-- All objects are made at the start and reused: nothing new while playing,
-- so the garbage collector has nothing to do (D54).

local Player = require("player")
local Enemy = require("enemy")
local Bullet = require("bullet")

local player
local enemies = {}
local score, best, spawn_t, over = 0, 0, 0, false

-- 10 normal enemies and 3 tough ones, made once
for i = 1, 10 do enemies[i] = Enemy(0, 1); enemies[i].alive = false end
for i = 11, 13 do enemies[i] = Enemy.Tough(0, 1); enemies[i].alive = false end

local function start_game()
  player = Player(122, 170)
  for _, e in ipairs(enemies) do e.alive = false end
  for _, b in ipairs(Bullet.pool) do b.alive = false end
  score, spawn_t, over = 0, 0, false
end

-- A free enemy of the wanted class comes back at the top
local function spawn()
  local tough = math.random(1, 5) == 1
  for _, e in ipairs(enemies) do
    if not e.alive and e:isInstanceOf(Enemy.Tough) == tough then
      e:reset(math.random(0, 240), 1 + score / 40)
      return
    end
  end
end

function _init()
  start_game()
end

function _update()
  if over then
    if btnp("a") then start_game() end
    return
  end
  player:update()
  spawn_t = spawn_t + 1
  if spawn_t >= 25 then spawn_t = 0; spawn() end

  for _, b in ipairs(Bullet.pool) do
    if b.alive then b:update() end
  end
  for _, e in ipairs(enemies) do
    if e.alive then
      e:update()
      for _, b in ipairs(Bullet.pool) do
        if b.alive and b:overlaps(e) then
          b.alive = false
          if e:hit() then score = score + (e.class.HP) end
          break
        end
      end
      if e.alive and (e:overlaps(player) or e.y > 192) then
        e.alive = false
        player.lives = player.lives - 1
        if player.lives <= 0 then
          over, best = true, math.max(best, score)
        end
      end
    end
  end
end

-- The status line is a new string: made only when a number changes, not in
-- every frame
local status, shown_score, shown_best, shown_lives
local function status_text()
  local lives = math.max(0, player.lives)
  if score ~= shown_score or best ~= shown_best or lives ~= shown_lives then
    shown_score, shown_best, shown_lives = score, best, lives
    status = ("score %d   best %d   lives %d"):format(score, best, lives)
  end
  return status
end

function _draw(screen)
  if screen == TOP then
    cls(0)
    for _, e in ipairs(enemies) do if e.alive then e:draw() end end
    for _, b in ipairs(Bullet.pool) do if b.alive then b:draw() end end
    if not over then player:draw() end
    if over then
      text("GAME OVER", 101, 80, 2)
      text("A: play again", 89, 96, 12)
    end
  else
    cls(1)
    text("Shooter (classes example)", 4, 4, 12)
    text(status_text(), 4, 20, 4)
    text("d-pad: move   A: shoot", 4, 44, 13)
    text("red enemies take 3 hits", 4, 56, 13)
    text("The code: main.lua and src/*.lua", 4, 160, 14)
    text("Y on the launcher opens it", 4, 172, 14)
  end
end
