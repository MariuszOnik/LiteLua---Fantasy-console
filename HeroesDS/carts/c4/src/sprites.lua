-- HeroesDS C4: the stacks' animations from the original game (H4, H5): atlases made by
-- tools/make_c4.py --gfx (style test1, scale 3/16 = the field's), loaded when first drawn
-- and freed when not drawn for a while. Meta: data/anim/<actor>_<state>.lua = { [dir] =
-- h4atlas meta }; rects ox, oy are relative to the actor's ground point in screen pixels.

local sprites = {}

local metas = {}     -- [actor_state] = { [dir] = meta } or false (none)
local used = {}      -- [meta] = frame it was last drawn in (its images are loaded)
local clock = 0
local KEEP = 300     -- frames an animation stays loaded unused

local FALLBACK = { e = { "se", "ne" }, w = { "sw", "nw" }, n = { "ne", "nw" }, s = { "se", "sw" },
                   ne = { "n", "e" }, nw = { "n", "w" }, se = { "s", "e" }, sw = { "s", "w" } }

-- The actor's file name: what make_c4.py makes of a creature key or a hero actor
function sprites.base(actor)
  return (actor:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

local function meta_of(base, state, dir)
  local key = base .. "_" .. state
  local m = metas[key]
  if m == nil then
    local f = loadfile("data/anim/" .. key .. ".lua")
    m = f and f() or false
    metas[key] = m
  end
  if not m then return nil end
  if m[dir] then return m[dir] end
  for _, d in ipairs(FALLBACK[dir] or {}) do if m[d] then return m[d] end end
  return (next(m)) and m[next(m)]
end

-- The animation (meta with its images) of an actor, or nil when there is none
function sprites.get(actor, state, dir)
  local m = meta_of(sprites.base(actor), state, dir or "sw")
  if not m then return nil end
  if not used[m] then
    m.img = image(m.image)
    m.simg = m.shadow and image(m.shadow) or nil
  end
  used[m] = clock
  return m
end

-- Frames of an animation, and how long it plays in game frames (30 a second)
function sprites.length(m)
  return #m.frames, math.max(1, (#m.frames * 30 + m.fps - 1) // m.fps)
end

-- Frame number (1-based) t game frames after the start; loop or stay on the last
function sprites.frame(m, t, loop)
  local f = t * m.fps // 30
  if loop then return f % #m.frames + 1 end
  return math.min(f, #m.frames - 1) + 1
end

-- Draws frame f of m with its ground point at x, y, k times bigger (the magnifier)
function sprites.draw(m, f, x, y, k)
  local s = m.sframes[f]
  if m.simg and s and s > 0 then
    local r, z = m.srects[s], m.szoom * k
    alpha(m.salpha)
    sspr(m.simg, r[1], r[2], r[3], r[4], x + r[5] * k, y + r[6] * k, r[3] * z, r[4] * z)
    alpha()
  end
  local i = m.frames[f]
  if i and i > 0 then
    local r = m.rects[i]
    sspr(m.img, r[1], r[2], r[3], r[4], x + r[5] * k, y + r[6] * k, r[3] * k, r[4] * k)
  end
end

-- Once a frame: frees the animations not drawn for KEEP frames
function sprites.tick()
  clock = clock + 1
  if clock % 60 ~= 0 then return end
  local freed = false
  for m, last in pairs(used) do
    if clock - last > KEEP then
      m.img, m.simg, used[m] = nil, nil, nil
      freed = true
    end
  end
  if freed then collectgarbage() end
end

return sprites
