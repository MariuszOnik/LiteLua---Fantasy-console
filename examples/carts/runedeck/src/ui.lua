-- Things both scenes use: colors, images, sounds, buttons, text wrapping.
local U = {}

U.BG_TOP, U.BG_BOT = 0x1a1626, 0x221c2c
U.GOLD, U.INK, U.PAPER = 0xdcbe78, 0x141018, 0xd8c8a0
U.KIND_COL = { attack = 0x7a3a30, skill = 0x30486a, power = 0x5a3a72 }

-- Images: missing art returns nil (the caller draws a placeholder)
local art = {}
function U.img(id)
  if art[id] == nil then
    local ok, i = pcall(image, id)
    art[id] = ok and i or false
  end
  return art[id] or nil
end

local sounds = {}
function U.play(name, vol)
  if not sounds[name] then sounds[name] = sound(name) end
  sfx(sounds[name], vol or 0.8)
end

function U.inside(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

-- b = { x, y, w, h }; true when the stylus went down on it this frame
function U.tapped(b)
  if not btnp("touch") then return false end
  local tx, ty = touch()
  return tx ~= nil and U.inside(tx, ty, b.x, b.y, b.w, b.h)
end

function U.button(b, label, col)
  rectfill(b.x, b.y, b.w, b.h, col)
  rect(b.x, b.y, b.w, b.h, U.GOLD)
  local w = textw(label)
  text(label, b.x + (b.w - w) // 2, b.y + (b.h - 8) // 2, 0xffffff)
end

function U.wrap(s, cols)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    if #cur + #word + 1 > cols and #cur > 0 then
      lines[#lines + 1], cur = cur, word
    else
      cur = #cur > 0 and (cur .. " " .. word) or word
    end
  end
  lines[#lines + 1] = cur
  return lines
end

function U.center(s, y, col)
  text(s, (256 - textw(s)) // 2, y, col)
end

return U
