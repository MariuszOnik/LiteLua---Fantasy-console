-- Bag scene: worn equipment and the bag on the bottom screen, the chosen
-- item and the deck it makes on the top one.
-- Stylus: tap a box to choose, then a button. D-pad chooses, A = main
-- action (wear / take off / drink / read), Y = drop, B or X = close.
-- K.update() returns "close", or "read", i when a scroll is opened.

local G = require("gear")
local B = require("battle")
local U = require("ui")
local F = require("fight")

local K = {}

local GOLD = U.GOLD
local BOX = 36
local sel = 1               -- 1..4 worn slots, 5..12 bag
local msg                   -- last message under the buttons

local function box_pos(i)
  if i <= 4 then return 4 + (i - 1) * 40, 12 end
  local k = i - 5
  return 4 + (k % 4) * 40, 72 + (k // 4) * 40
end

local ACT_BTN = { x = 172, y = 12, w = 80, h = 22 }
local DROP_BTN = { x = 172, y = 40, w = 80, h = 22 }
local CLOSE_BTN = { x = 172, y = 150, w = 80, h = 22 }

-- Item id in box i, and what the main button does with it
local function item_in(i)
  if i <= 4 then return G.equip[G.SLOTS[i]] end
  return G.bag[i - 4]
end

local function action(i)
  local id = item_in(i)
  if not id then return nil end
  if i <= 4 then return "Take off" end
  local slot = G.item(id).slot
  if slot == "potion" then return "Drink" end
  if slot == "scroll" then return "Read" end
  return "Wear"
end

function K.enter()
  msg = nil
  if not item_in(sel) then sel = 5 end
end

local function do_action()
  local id, act = item_in(sel), action(sel)
  if not act then return end
  local name = G.item(id).name
  if act == "Take off" then
    if G.unwear(G.SLOTS[sel]) then msg = "Took off " .. name .. "." else msg = "The bag is full." end
  elseif act == "Drink" then
    local n = G.drink(sel - 4)
    msg = "+" .. n .. " HP."
    U.play("buff")
  elseif act == "Read" then
    return "read", sel - 4
  else
    G.wear(sel - 4)
    msg = "Now wearing " .. name .. "."
    U.play("block")
  end
end

local function do_drop()
  if sel > 4 and item_in(sel) then
    msg = "Dropped " .. G.item(G.drop(sel - 4)).name .. "."
  end
end

function K.update()
  if btnp("b") or btnp("x") then return "close" end
  if btnp("left") then sel = sel > 1 and sel - 1 or 12 end
  if btnp("right") then sel = sel < 12 and sel + 1 or 1 end
  if btnp("up") then sel = sel > 4 and sel - 4 or sel end
  if btnp("down") then sel = sel <= 8 and sel + 4 or sel end
  if btnp("a") then return do_action() end
  if btnp("y") then do_drop() end
  if btnp("touch") then
    local tx, ty = touch()
    if not tx then return end
    for i = 1, 12 do
      local x, y = box_pos(i)
      if U.inside(tx, ty, x, y, BOX, BOX) then sel = i; U.play("pick", 0.5) end
    end
    if U.inside(tx, ty, ACT_BTN.x, ACT_BTN.y, ACT_BTN.w, ACT_BTN.h) then return do_action() end
    if U.inside(tx, ty, DROP_BTN.x, DROP_BTN.y, DROP_BTN.w, DROP_BTN.h) then do_drop() end
    if U.inside(tx, ty, CLOSE_BTN.x, CLOSE_BTN.y, CLOSE_BTN.w, CLOSE_BTN.h) then return "close" end
  end
end

-- Drawing -------------------------------------------------------------------

local SLOT_NAME = { "Weapon", "Armor", "Shield", "Charm" }

local function draw_box(i)
  local x, y = box_pos(i)
  local id = item_in(i)
  rectfill(x, y, BOX, BOX, 0x141018)
  rect(x, y, BOX, BOX, i == sel and GOLD or 0x4a4058)
  if i == sel then rect(x + 1, y + 1, BOX - 2, BOX - 2, GOLD) end
  if id then
    local a = U.img("i_" .. id)
    if a then spr(a, x + 2, y + 2) else text(G.item(id).name:sub(1, 5), x + 2, y + 14, 0xffffff) end
  end
end

local function draw_bottom()
  cls(U.BG_BOT)
  text("Worn", 4, 2, 0x908878)
  for i = 1, 4 do
    draw_box(i)
    local x = box_pos(i)
    text(SLOT_NAME[i], x, 50, 0x908878)
  end
  text("Bag " .. #G.bag .. "/" .. G.BAG_MAX, 4, 62, 0x908878)
  for i = 5, 12 do draw_box(i) end
  local act = action(sel)
  U.button(ACT_BTN, act and (act .. " (A)") or "-", act and 0x6a3020 or 0x303030)
  U.button(DROP_BTN, "Drop (Y)", (sel > 4 and item_in(sel)) and 0x403850 or 0x303030)
  U.button(CLOSE_BTN, "Close (B)", 0x403850)
  local p = B.player
  text("HP " .. p.hp .. "/" .. p.max, 172, 72, 0xff8080)
  text("Deck " .. #p.deck, 172, 82, 0xc0b0ff)
  if msg then
    for j, l in ipairs(U.wrap(msg, 13)) do text(l, 172, 100 + (j - 1) * 9, 0xffffff) end
  end
end

local function draw_top()
  cls(U.BG_TOP)
  local id = item_in(sel)
  if id then
    local it = G.item(id)
    text(it.name, 4, 4, GOLD)
    local info
    if it.slot == "potion" then
      info = "Potion: heals " .. it.heal .. " HP. Also in fights."
    elseif it.slot == "scroll" then
      info = "Read it to learn 1 of 3 cards."
    else
      info = it.slot:sub(1, 1):upper() .. it.slot:sub(2) .. ", gives these cards"
      if it.hp then info = info .. ", +" .. it.hp .. " max HP" end
      local worn = G.equip[it.slot]
      if sel > 4 and worn then text("Instead of: " .. G.item(worn).name, 4, 24, 0xa09080) end
    end
    text(info, 4, 14, 0xffffff)
    for k, c in ipairs(it.cards or {}) do
      if k <= 5 then F.draw_card(c, 4 + (k - 1) * 50, 36) end
    end
  else
    text(sel <= 4 and ("No " .. SLOT_NAME[sel]:lower() .. " worn.") or "Empty.", 4, 4, 0x908878)
  end
  -- the whole deck
  local list = G.deck_summary()
  rectfill(0, 106, 256, 86, 0x120e18)
  text("Your deck: " .. #B.player.deck .. " cards", 4, 110, GOLD)
  for k, e in ipairs(list) do
    local col, row = (k - 1) // 8, (k - 1) % 8
    text(e[2] .. "x " .. B.card(e[1]).name, 4 + col * 126, 122 + row * 8, 0xd0d0d0)
  end
end

function K.draw(surface)
  if surface == TOP then draw_top() else draw_bottom() end
end

return K
