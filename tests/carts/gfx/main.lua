-- LiteLua P4a graphics test: every drawing function on the top screen.
-- A: stress test on/off (Up/Down: more/fewer rectangles), B: back to the list.
-- The bottom screen (text console until P6) shows the draw time.

local t = 0
local stress, count = false, 500
local draw_us, frames = 0, 0

function _init()
  io.write('\27[2J')
  print("P4a graphics test")
  print("A: stress test  Up/Down: count")
  print("B: back to the list")
end

function _update()
  t = t + 1
  if btnp("a") then stress = not stress end
  if btnp("up") then count = count + 100 end
  if btnp("down") and count > 100 then count = count - 100 end
  if btnp("b") then sys.exit() end
end

local function scene()
  cls(1)

  -- Palette: 16 swatches
  for i = 0, 15 do
    rectfill(i * 16, 0, 16, 10, i)
    rect(i * 16, 0, 16, 10, 0)
  end

  -- Lines in all directions from a center
  for a = 0, 15 do
    local r = a * math.pi / 8
    line(40, 50, 40 + math.cos(r) * 30, 50 + math.sin(r) * 30, 4 + a % 8)
  end

  -- Rectangles: outline, filled, negative size, 1 px
  rect(80, 20, 40, 30, 12)
  rectfill(84, 24, 32, 22, 2)
  rectfill(130, 50, -10, -30, 5)
  pset(140, 20, 12)
  pset(142, 20, 0xff0000)

  -- Circles of different sizes
  circ(170, 40, 20, 11)
  circfill(170, 40, 12, 10)
  circfill(205, 30, 2, 12)
  circfill(215, 30, 5, 12)
  circ(235, 40, 8, 4)

  -- Triangles
  trifill(10, 100, 50, 90, 30, 130, 6)
  tri(60, 90, 100, 100, 70, 130, 3)

  -- Alpha: overlapping translucent circles
  alpha(0.5)
  circfill(130, 110, 20, 2)
  circfill(150, 110, 20, 10)
  circfill(140, 125, 20, 5)
  alpha()

  -- Camera: a moving square drawn at a fixed world position
  camera(-math.floor(math.sin(t / 20) * 20), 0)
  rectfill(190, 90, 20, 20, 9)
  rect(188, 88, 24, 24, 12)
  camera()

  -- Clip: the stripes only show inside the frame
  rect(10, 145, 80, 40, 12)
  clip(11, 146, 78, 38)
  for i = 0, 12 do
    line(i * 10 - 20 + t % 10, 140, i * 10 + 20 + t % 10, 190, 4)
  end
  clip()

  -- Color names are numbers; 0xRRGGBB works too
  color(0x41a6f6)
  rectfill(110, 150, 30, 30)
  color()
  rectfill(150, 150, 30, 30, 0xffffff)
  rectfill(160, 160, 10, 10, 0x000000)
end

local function stress_scene()
  cls(0)
  for i = 1, count do
    local x = (i * 37 + t) % 250
    local y = (i * 53) % 186
    rectfill(x, y, 6, 6, i % 16)
  end
end

function _draw(screen)
  if screen == TOP then
    local t0 = micros()
    if stress then stress_scene() else scene() end
    draw_us = draw_us + (micros() - t0)
    frames = frames + 1
  elseif frames >= 30 then
    io.write(('\27[5;0H%-31s'):format(stress and ("stress: " .. count .. " rects") or "scene"))
    io.write(('\27[6;0H%-31s'):format(("draw: %d.%d ms"):format(draw_us // frames // 1000,
      draw_us // frames % 1000 // 100)))
    io.write(('\27[7;0H%-31s'):format(("Lua mem: %d KB"):format(collectgarbage("count") // 1)))
    draw_us, frames = 0, 0
  end
end
