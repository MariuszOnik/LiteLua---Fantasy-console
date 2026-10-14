-- Enemy: falls down and sways; Tough is an enemy that needs 3 hits
local Entity = require("entity")

local Enemy = Entity:subclass("Enemy")

function Enemy:initialize(x, speed)
  Entity.initialize(self, x, -10, 10, 10, 6)
  self.speed, self.hp, self.t = speed, 1, math.random(0, 100)
end

-- Reuses a dead enemy for a new wave (no new tables while playing)
function Enemy:reset(x, speed)
  self.x, self.y, self.speed, self.alive = x, -10, speed, true
  self.hp = self.class.HP
end
Enemy.static.HP = 1

function Enemy:update()
  self.t = self.t + 1
  self.y = self.y + self.speed
  self.x = self.x + math.sin(self.t / 10)
end

-- Returns true when the hit destroyed it
function Enemy:hit()
  self.hp = self.hp - 1
  if self.hp <= 0 then self.alive = false; return true end
  return false
end

local Tough = Enemy:subclass("Tough")
Tough.static.HP = 3

function Tough:initialize(x, speed)
  Enemy.initialize(self, x, speed * 0.6)
  self.w, self.h, self.col, self.hp = 14, 14, 2, 3
end

function Tough:draw()
  Enemy.draw(self)
  -- Hits left as dots
  for i = 1, self.hp do rectfill(self.x + i * 4 - 3, self.y + 5, 2, 2, 12) end
end

Enemy.Tough = Tough
return Enemy
