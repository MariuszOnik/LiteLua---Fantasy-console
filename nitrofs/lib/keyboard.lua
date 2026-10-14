-- On-screen keyboard of the code editor (bottom screen): QWERTY letters and
-- a layer of Lua symbols. Keys are pressed with the stylus.

local M = {}

M.y = 32       -- Top of the keyboard on the bottom screen
M.row_h = 32
local UNIT = 25.6 -- 10 units per row (256 pixels)

-- A key: { label, units wide, action }. Action: text to insert, or one of
-- "shift", "layer", "back", "enter", "tab", "space"
local function keys(s)
  local t = {}
  for ch in s:gmatch(".") do t[#t + 1] = { ch, 1, ch } end
  return t
end
local function add(t, ...)
  for _, k in ipairs({ ... }) do t[#t + 1] = k end
  return t
end

local bottom_row = function(layer_label)
  return {
    { layer_label, 1.5, "layer" }, { "tab", 1, "tab" }, { "space", 3.5, "space" },
    { "(", 1, "(" }, { ")", 1, ")" }, { "=", 1, "=" }, { "ent", 1, "enter" },
  }
end

M.layers = {
  letters = {
    keys("1234567890"),
    keys("qwertyuiop"),
    add(keys("asdfghjkl"), { "<-", 1, "back" }),
    add({ { "shf", 1, "shift" } }, table.unpack(add(keys("zxcvbnm"),
        { ",", 1, "," }, { ".", 1, "." }))),
    bottom_row("sym"),
  },
  symbols = {
    keys("+-*/%^#=~_"),
    keys("()[]{}<>\"'"),
    add(keys(".,:;\\|&!?"), { "<-", 1, "back" }),
    { { "..", 1, ".." }, { "==", 1, "==" }, { "~=", 1, "~=" }, { "<=", 1, "<=" },
      { ">=", 1, ">=" }, { "--", 1, "--" }, { "[[", 1, "[[" }, { "]]", 1, "]]" },
      { "@", 1, "@" }, { "$", 1, "$" } },
    bottom_row("abc"),
  },
}

-- Shifted characters of the letter layer (like a PC keyboard)
local shifted = {
  ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%",
  ["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")",
  [","] = "<", ["."] = ">", ["("] = "[", [")"] = "]", ["="] = "+",
}

M.layer = "letters"
M.shift = 0          -- 0 off, 1 next key only, 2 caps lock
M.down = nil         -- Key under the stylus { row, index }
M.held = 0           -- Frames the key has been held (backspace repeats)

local function key_x(row, i)
  local u = 0
  for j = 1, i - 1 do u = u + row[j][2] end
  return math.floor(u * UNIT + 0.5), math.floor((u + row[i][2]) * UNIT + 0.5)
end

local function key_at(tx, ty)
  local r = (ty - M.y) // M.row_h + 1
  local row = M.layers[M.layer][r]
  if ty < M.y or not row then return nil end
  for i = 1, #row do
    local x1, x2 = key_x(row, i)
    if tx >= x1 and tx < x2 then return r, i end
  end
end

-- What a key produces now (shift applied)
local function output(k)
  local a = k[3]
  if #a == 1 and M.layer == "letters" and M.shift > 0 then
    return shifted[a] or a:upper()
  end
  return a
end

-- Handles the stylus for one frame. Returns the action of a pressed key
-- (text or a command name), or nil.
function M.update(tx, ty, pressed)
  if not tx then
    M.down = nil
    return nil
  end
  if pressed then
    local r, i = key_at(tx, ty)
    M.down = r and { r, i } or nil
    M.held = 0
    if not r then return nil end
    local k = M.layers[M.layer][r][i]
    local a = k[3]
    if a == "shift" then
      M.shift = (M.shift + 1) % 3
      return nil
    elseif a == "layer" then
      M.layer = M.layer == "letters" and "symbols" or "letters"
      return nil
    end
    local out = output(k)
    if M.shift == 1 and #a == 1 then M.shift = 0 end
    return out
  end
  -- Held: backspace repeats
  if M.down then
    M.held = M.held + 1
    local k = M.layers[M.layer][M.down[1]][M.down[2]]
    if k[3] == "back" and M.held > 10 and M.held % 2 == 0 then return "back" end
  end
  return nil
end

function M.toggle_layer()
  M.layer = M.layer == "letters" and "symbols" or "letters"
end

function M.draw()
  local rows = M.layers[M.layer]
  for r = 1, #rows do
    local row = rows[r]
    local y = M.y + (r - 1) * M.row_h
    for i = 1, #row do
      local k = row[i]
      local x1, x2 = key_x(row, i)
      local down = M.down and M.down[1] == r and M.down[2] == i
      local special = #k[3] > 1 and k[3] ~= k[1]
      local bg = down and 9 or special and 14 or 15
      if k[3] == "shift" and M.shift > 0 then bg = M.shift == 2 and 6 or 7 end
      rectfill(x1 + 1, y + 1, x2 - x1 - 2, M.row_h - 2, bg)
      local label = k[1]
      if #k[3] == 1 and M.layer == "letters" and M.shift > 0 then
        label = output(k)
      end
      local w = textw(label)
      text(label, x1 + (x2 - x1 - w) // 2, y + 12, 12)
    end
  end
end

return M
