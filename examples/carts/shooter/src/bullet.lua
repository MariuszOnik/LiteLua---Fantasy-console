-- Bullet and its pool: all bullets are made once and reused, so shooting
-- makes no garbage (making objects is the slow part, D54)
local Entity = require("entity")

local Bullet = Entity:subclass("Bullet")

function Bullet:initialize()
  Entity.initialize(self, 0, 0, 2, 6, 12)
  self.alive = false
end

-- Reuses a bullet: start it at x, y
function Bullet:reset(x, y)
  self.x, self.y, self.alive = x, y, true
end

function Bullet:update()
  self.y = self.y - 6
  if self.y < -self.h then self.alive = false end
end

-- The pool
local pool = {}
for i = 1, 16 do pool[i] = Bullet() end
Bullet.pool = pool

-- Takes a free bullet from the pool; nil when all are flying
function Bullet.fire(x, y)
  for i = 1, #pool do
    local b = pool[i]
    if not b.alive then b:reset(x, y); return b end
  end
end

return Bullet
