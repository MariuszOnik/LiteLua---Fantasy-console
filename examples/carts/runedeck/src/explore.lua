-- Explore scene: the ASCII dungeon on the top screen, log and a touch pad
-- on the bottom one. Rules of the map are in dungeon.lua.
-- D-pad (held = repeat) or the touch pad moves, A / the pad center waits.
-- main.lua calls X.update(); it returns "fight", monster when a fight
-- starts, "floor" when the player took the stairs.

local D = require("dungeon")
local B = require("battle")
local U = require("ui")

local X = {}

local GOLD = U.GOLD
local TOP_Y = 8                        -- the map starts under the HUD row
local log = {}                         -- last messages, newest last
local rows                             -- cached text runs per map row
local hold_t = 0

function X.say(msg)
  log[#log + 1] = msg
  if #log > 7 then table.remove(log, 1) end
end

function X.clear_log() log = {} end

-- Map rows as runs of same-colored text ------------------------------------

local TILE_COL = {
  ["#"] = { 0x9a8a78, 0x403830 },      -- visible, remembered
  ["."] = { 0x5a5048, 0x2a2622 },
  [">"] = { 0xffd040, 0x806820 },
}

local function cell(x, y)
  if x == D.px and y == D.py then return "@", 0xffffff end
  local vis = D.vis[y][x]
  if vis then
    local m = D.monster_at(x, y)
    if m then return m.glyph, m.col end
  end
  if not D.seen[y][x] then return " " end
  local t = D.map[y][x]
  return t, TILE_COL[t][vis and 1 or 2]
end

-- Rebuilt only after something moved: drawing is then ~10 text() per row
function X.dirty() rows = nil end

local function build()
  rows = {}
  for y = 1, D.H do
    local runs, cur = {}, nil
    for x = 1, D.W do
      local ch, col = cell(x, y)
      if ch == " " then
        if cur then cur.s = cur.s .. " " end
      elseif cur and cur.col == col then
        cur.s = cur.s .. ch
      else
        cur = { x = (x - 1) * 6 + 2, s = ch, col = col }
        runs[#runs + 1] = cur
      end
    end
    rows[y] = runs
  end
end

-- Turn ----------------------------------------------------------------------

-- One player action (dx, dy = 0, 0 waits). Returns like X.update.
local function act(dx, dy)
  local res, m = nil, nil
  if dx ~= 0 or dy ~= 0 then
    res, m = D.step(dx, dy)
    if res == nil then return end          -- bumped a wall: no turn
    if res == "fight" then return "fight", m end
  end
  X.dirty()
  if res == "stairs" then return "floor" end
  m = D.monsters_turn()
  if m then return "fight", m end
end

local PAD = { x = 152, y = 92, s = 30 }   -- 3x3 touch pad, cell size s
local DIRS = { { 0, -1, 1, 0 }, { -1, 0, 0, 1 }, { 1, 0, 2, 1 }, { 0, 1, 1, 2 }, { 0, 0, 1, 1 } }

function X.update()
  local dx, dy = 0, 0
  local pressed = false
  for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }) do
    if btnp(d[1]) then
      dx, dy, pressed, hold_t = d[2], d[3], true, 0
    elseif btn(d[1]) then
      hold_t = hold_t + 1
      if hold_t > 8 and hold_t % 4 == 0 then dx, dy, pressed = d[2], d[3], true end
    end
  end
  if btnp("a") then pressed = true end
  if btnp("touch") then
    local tx, ty = touch()
    for _, d in ipairs(DIRS) do
      if tx and U.inside(tx, ty, PAD.x + d[3] * PAD.s, PAD.y + d[4] * PAD.s, PAD.s, PAD.s) then
        dx, dy, pressed = d[1], d[2], true
      end
    end
  end
  if pressed then return act(dx, dy) end
end

-- Drawing -------------------------------------------------------------------

local function draw_top()
  cls(0x0c0a10)
  local p = B.player
  text("HP " .. p.hp .. "/" .. p.max, 2, 0, 0xff8080)
  text("Deck " .. #p.deck, 92, 0, 0xc0b0ff)
  local f = "Floor " .. D.floor .. "/" .. D.floors_total()
  text(f, 254 - textw(f), 0, GOLD)
  if not rows then build() end
  for y, runs in ipairs(rows) do
    local py = TOP_Y + (y - 1) * 8
    for _, r in ipairs(runs) do text(r.s, r.x, py, r.col) end
  end
end

local function draw_bottom()
  cls(U.BG_BOT)
  local p = B.player
  rectfill(4, 4, 248, 6, 0x3a1010)
  rectfill(4, 4, 248 * p.hp // p.max, 6, 0xd03030)
  text("HP " .. p.hp .. "/" .. p.max .. "   Deck " .. #p.deck .. " cards", 4, 14, 0xffffff)
  for i, msg in ipairs(log) do
    text(msg, 4, 30 + (i - 1) * 9, i == #log and 0xffffff or 0x908878)
  end
  -- touch pad
  for _, d in ipairs(DIRS) do
    local x, y = PAD.x + d[3] * PAD.s, PAD.y + d[4] * PAD.s
    rectfill(x + 1, y + 1, PAD.s - 2, PAD.s - 2, 0x3a3048)
    rect(x + 1, y + 1, PAD.s - 2, PAD.s - 2, 0x6a5a80)
  end
  local cx, cy = PAD.x + PAD.s * 3 // 2, PAD.y + PAD.s * 3 // 2
  trifill(cx - 6, cy - 22, cx + 6, cy - 22, cx, cy - 30, GOLD)
  trifill(cx - 6, cy + 22, cx + 6, cy + 22, cx, cy + 30, GOLD)
  trifill(cx - 22, cy - 6, cx - 22, cy + 6, cx - 30, cy, GOLD)
  trifill(cx + 22, cy - 6, cx + 22, cy + 6, cx + 30, cy, GOLD)
  text("z", cx - 3, cy - 4, GOLD)
  text("@ you  > stairs", 4, 158, 0x908878)
  text("letters: monsters", 4, 168, 0x908878)
  text("A / z: wait", 4, 178, 0x908878)
end

function X.draw(surface)
  if surface == TOP then draw_top() else draw_bottom() end
end

return X
