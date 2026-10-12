-- LiteLua shapes test (D31): pixel exact circles and stroke() widths.
-- Top: circles r = 0..12 (filled, outline, stroke 2), large circles.
-- Bottom: thick lines, rectangles, triangles, translucent outlines.
-- A: stress test on/off (200 circfill + 200 circ, r = 6), B: back to the list.

local t = 0
local stress = false
local draw_us, frames, status = 0, 0, ""

function _update()
  t = t + 1
  if btnp("a") then stress = not stress end
  if btnp("b") then sys.exit() end
end

local function circles()
  cls(0)
  local x = 4
  for r = 0, 12 do
    circfill(x + r, 14 + 12 - r, r, 12)
    circ(x + r, 44 + 12 - r, r, 11)
    stroke(2)
    circ(x + r, 74 + 12 - r, r, 4)
    stroke()
    x = x + 2 * r + 4
    if x > 240 then x = 4 end
  end
  -- Large circles: polygons
  circfill(36, 150, 30, 10)
  circ(110, 150, 30, 11)
  stroke(4)
  circ(184, 150, 30, 5)
  stroke()
  -- Filled and outline of the same radius must match
  circfill(236, 150, 10, 2)
  circ(236, 150, 10, 12)
end

local function stress_scene()
  cls(0)
  for i = 1, 200 do
    local x = (i * 37 + t) % 250
    local y = (i * 53) % 186
    circfill(x, y, 6, i % 16)
    circ(x, y, 6, 12)
  end
end

local function bottom()
  cls(15)
  text("Shapes test (D31)  A: stress", 2, 2, 12)
  text(status, 2, 12, 4)
  for w = 1, 5 do
    stroke(w)
    local y = 26 + (w - 1) * 12
    line(8, y, 80, y, 12)                    -- horizontal
    line(90 + w * 10, 26, 90 + w * 10, 82, 11) -- vertical
    line(160, y, 250, y + 20, 5)             -- slanted
  end
  stroke(3)
  rect(8, 96, 60, 40, 4)
  tri(90, 136, 130, 96, 160, 136, 10)
  alpha(0.5)
  tri(170, 136, 210, 96, 250, 136, 2)       -- corners not blended twice
  alpha()
  stroke(6)
  rect(8, 146, 40, 40, 6)
  rect(56, 150, 10, 10, 6)                   -- too small: filled
  line(80, 160, 80, 160, 12)                 -- a point: 6x6 square
  stroke(2)
  line(100, 186, 250, 146, 3)
end

function _draw(surface)
  if surface == TOP then
    local t0 = micros()
    if stress then stress_scene() else circles() end
    draw_us = draw_us + (micros() - t0)
    frames = frames + 1
    if frames >= 30 then
      status = ("%s: draw %d.%d ms"):format(stress and "stress" or "scene",
        draw_us // frames // 1000, draw_us // frames % 1000 // 100)
      log(status)
      draw_us, frames = 0, 0
    end
  else
    bottom()
  end
end
