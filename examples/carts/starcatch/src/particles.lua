-- Particles for small explosions. All particles live in one pool created at
-- the start, so the game makes no garbage while it runs (no new tables per
-- frame): a burst reuses the oldest particles.

local M = {}

local COUNT = 64 -- Particles in the pool
local LIFE = 20  -- Frames a particle lives

local pool = {}
for i = 1, COUNT do
  pool[i] = { x = 0, y = 0, vx = 0, vy = 0, life = 0, color = 0 }
end
local next_index = 1

-- Throws 'count' particles of 'color' from x, y in all directions
function M.burst(x, y, color, count)
  for _ = 1, count do
    local p = pool[next_index]
    next_index = next_index % COUNT + 1
    local angle = math.random() * math.pi * 2
    local speed = 0.5 + math.random() * 2
    p.x, p.y = x, y
    p.vx, p.vy = math.cos(angle) * speed, math.sin(angle) * speed - 1
    p.life, p.color = LIFE, color
  end
end

function M.update()
  for i = 1, COUNT do
    local p = pool[i]
    if p.life > 0 then
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      p.vy = p.vy + 0.08 -- gravity
      p.life = p.life - 1
    end
  end
end

-- Fading squares: alpha goes down with the remaining life
function M.draw()
  for i = 1, COUNT do
    local p = pool[i]
    if p.life > 0 then
      alpha(p.life / LIFE)
      rectfill(p.x - 1, p.y - 1, 2, 2, p.color)
    end
  end
  alpha()
end

return M
