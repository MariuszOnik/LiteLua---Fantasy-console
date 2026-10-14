-- Player: moves with the d-pad, shoots with A
local Entity = require("entity")
local Bullet = require("bullet")

local Player = Entity:subclass("Player")

function Player:initialize(x, y)
  Entity.initialize(self, x, y, 12, 10, 11)
  self.cooldown = 0
  self.lives = 3
end

function Player:update()
  if btn("left") then self.x = math.max(0, self.x - 3) end
  if btn("right") then self.x = math.min(256 - self.w, self.x + 3) end
  self.cooldown = math.max(0, self.cooldown - 1)
  if btn("a") and self.cooldown == 0 then
    if Bullet.fire(self.x + self.w // 2 - 1, self.y - 6) then
      self.cooldown = 6
    end
  end
end

-- A ship with a nose: the parent's draw plus a little more
function Player:draw()
  Entity.draw(self)
  rectfill(self.x + 4, self.y - 3, 4, 3, self.col)
end

return Player
