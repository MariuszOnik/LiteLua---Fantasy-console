-- LiteLua P4c text test: the built-in 6x8 font, Polish letters, textw.
-- A: stress test on/off (Up/Down: more/fewer lines), B: back to the list.

-- Result lines: shown on the bottom screen and written to the log
local out = {}
local function say(s)
  out[#out + 1] = s
  print(s)
end
local function draw_out(y)
  for i, l in ipairs(out) do
    text(l, 0, (y or 0) + (i - 1) * 8, l:sub(1, 4) == "FAIL" and 2 or 12)
  end
end

local fails = 0
local function check(name, cond, extra)
  if not cond then fails = fails + 1 end
  say((cond and "ok   " or "FAIL ") .. name .. (extra and (" " .. tostring(extra)) or ""))
end

local w, h = textw("Hello")
check("textw", w == 30 and h == 8, w .. "x" .. h)
w, h = textw("ab\nlonger line\n")
check("textw lines", w == 66 and h == 24, w .. "x" .. h)
w = textw("zażółć")
check("textw utf-8", w == 36, w)
w = textw("a\tb")
check("textw tab", w == 30, w)
check("textw empty", select(2, textw("")) == 0)
say(fails == 0 and "ALL OK" or (fails .. " FAILED"))
say("A: stress  B: list")

-- All glyphs of the font, 16 per line
local all = {}
for c = 32, 126 do all[#all + 1] = string.char(c) end
all[#all + 1] = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ€"
local sheet = table.concat(all)
local lines = {}
for i = 0, 7 do
  local s = ""
  local n = 0
  for _, cp in utf8.codes(sheet) do
    if n // 16 == i then s = s .. utf8.char(cp) end
    n = n + 1
  end
  lines[#lines + 1] = s
end
sheet = table.concat(lines, "\n")

local t = 0
local status = ""
local stress, count = false, 20
local draw_us, frames = 0, 0

function _update()
  t = t + 1
  if btnp("a") then stress = not stress end
  if btnp("up") then count = count + 4 end
  if btnp("down") and count > 4 then count = count - 4 end
  if btnp("b") then sys.exit() end
end

local function scene()
  cls(0)
  text(sheet, 2, 2, 12)

  text("Zażółć gęślą jaźń!", 110, 2, 4)
  text("ZAŻÓŁĆ GĘŚLĄ JAŹŃ", 110, 12, 5)
  text("Line 1\nLine 2\n\tTabbed", 110, 24, 11)

  -- Measured box around a text
  local msg = "Score: " .. t
  local tw, th = textw(msg)
  rectfill(110, 52, tw + 4, th + 4, 2)
  text(msg, 112, 54, 12)

  -- Palette colors
  for i = 0, 15 do text(string.format("%X", i), 110 + i * 8, 64, i) end
  text("0xRRGGBB", 110, 74, 0xff8800)

  -- Translucent text over a shape, zoomed text
  rectfill(2, 70, 100, 20, 9)
  alpha(0.5)
  text("half transparent", 4, 76, 12)
  alpha()
  camera(-80, -42, 2) -- world 0, 0 at screen 160, 84
  text("Zoom 2x", 0, 0, 10)
  camera()

  -- The code editor will look like this: 42 columns x 24 rows
  rectfill(0, 96, 256, 96, 15)
  local code = {
    "-- main.lua",
    "local x, y = 128, 96",
    "",
    "function _update()",
    "\tif btn(\"left\") then x = x - 2 end",
    "\tif btn(\"right\") then x = x + 2 end",
    "end",
    "",
    "function _draw(screen)",
    "\tcls(1)",
    "\tcircfill(x, y, 8, 10)  -- żółw",
    "end",
  }
  for i, l in ipairs(code) do
    text(("%2d"):format(i), 0, 96 + (i - 1) * 8, 14)
    text(l, 18, 96 + (i - 1) * 8, i == 5 and 4 or 12)
  end
  if t // 15 % 2 == 0 then rectfill(18 + 6 * 7, 96 + 4 * 8, 1, 8, 12) end
end

local function stress_scene()
  cls(0)
  local line = "The quick brown fox jumps over the lazy"
  for i = 1, count do
    text(line, 0, (i - 1) * 8 % 192, (i + t // 10) % 15 + 1)
  end
end

function _draw(screen)
  if screen == TOP then
    local t0 = micros()
    if stress then stress_scene() else scene() end
    draw_us = draw_us + (micros() - t0)
    frames = frames + 1
  else
    if frames >= 30 then
      local what = stress and (count .. " lines x 39 chars") or "scene"
      status = ("%s: draw %d us/frame"):format(what, draw_us // frames)
      log(status)
      draw_us, frames = 0, 0
    end
    cls(0)
    draw_out()
    text(status, 0, 184, 4)
  end
end
