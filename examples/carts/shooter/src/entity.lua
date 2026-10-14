-- Entity: the base class of everything on the screen (a box with a color)
local class = require("middleclass")

local Entity = class("Entity")

function Entity:initialize(x, y, w, h, col)
  self.x, self.y, self.w, self.h, self.col = x, y, w, h, col
  self.alive = true
end

-- Boxes overlap: used for hits
function Entity:overlaps(o)
  return self.x < o.x + o.w and o.x < self.x + self.w
     and self.y < o.y + o.h and o.y < self.y + self.h
end

function Entity:draw()
  rectfill(self.x, self.y, self.w, self.h, self.col)
end

return Entity
