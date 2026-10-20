-- Title scene: continue the saved run, start a new one with a random seed
-- or type a seed (the same seed makes the same floors).
-- T.update() returns "continue", or "new", seed.

local U = require("ui")

local T = {}

local GOLD = U.GOLD
local saved      -- the saved run or nil
local mode       -- "menu" or "seed" (typing a seed)
local digits     -- the seed being typed
local sel = 1

local MENU = {
  { id = "continue", y = 40 },
  { id = "new", y = 74 },
  { id = "seed", y = 108 },
}
local function btn(m) return { x = 48, y = m.y, w = 160, h = 26 } end

-- digit pad: 1-9, <-, 0, OK
local PAD = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "<", "0", "OK" }
local function pad_btn(i)
  local k = i - 1
  return { x = 56 + (k % 3) * 50, y = 40 + (k // 3) * 36, w = 46, h = 32 }
end

function T.enter(run)
  saved, mode, digits = run, "menu", ""
  sel = saved and 1 or 2
  music()
end

local function random_seed()
  return math.random(100000, 999999)
end

local function press_pad(k)
  if k == "<" then
    digits = digits:sub(1, -2)
  elseif k == "OK" then
    if #digits > 0 then return "new", tonumber(digits) end
    mode = "menu"
  elseif #digits < 6 then
    digits = digits .. k
  end
  U.play("pick", 0.5)
end

local function choose(id)
  if id == "continue" and saved then return "continue" end
  if id == "new" then return "new", random_seed() end
  if id == "seed" then mode, digits = "seed", "" end
end

function T.update()
  if mode == "seed" then
    if btnp("b") then mode = "menu" end
    for i, k in ipairs(PAD) do
      if U.tapped(pad_btn(i)) then return press_pad(k) end
    end
    return
  end
  if btnp("up") then sel = sel > 1 and sel - 1 or 3 end
  if btnp("down") then sel = sel < 3 and sel + 1 or 1 end
  if not saved and sel == 1 then sel = btnp("up") and 3 or 2 end
  if btnp("a") then return choose(MENU[sel].id) end
  for i, m in ipairs(MENU) do
    if U.tapped(btn(m)) then sel = i; return choose(m.id) end
  end
end

function T.draw(surface)
  if surface == TOP then
    cls(U.BG_TOP)
    local a = U.img("ogre")
    if a then spr(a, 80, 70) end
    rectfill(0, 24, 256, 30, 0x0c0a10)
    U.center("R U N E D E C K", 30, GOLD)
    U.center("a deck-building dungeon crawl", 42, 0xa09080)
    U.center("Walk the ruins. Fight with cards.", 172, 0x908878)
    return
  end
  cls(U.BG_BOT)
  if mode == "seed" then
    U.center("Seed: " .. (digits == "" and "_" or digits), 14, GOLD)
    for i, k in ipairs(PAD) do U.button(pad_btn(i), k, k == "OK" and 0x6a3020 or 0x403850) end
    U.center("B: back", 182, 0x908878)
    return
  end
  for i, m in ipairs(MENU) do
    local label = m.id == "continue" and (saved and ("Continue: floor " .. saved.floor) or "No saved run")
      or m.id == "new" and "New run" or "New run with a seed"
    local col = (m.id == "continue" and not saved) and 0x303030 or (i == sel and 0x6a3020 or 0x403850)
    U.button(btn(m), label, col)
  end
  if saved then U.center("Seed " .. saved.seed, 140, 0x908878) end
  U.center("D-pad + A, or the stylus", 178, 0x908878)
end

return T
