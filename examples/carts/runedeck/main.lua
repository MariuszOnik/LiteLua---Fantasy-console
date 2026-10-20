-- Runedeck: a small deck-building roguelike (prototype).
--   src/cards.lua, src/enemies.lua  game data (also read by tools/cardart.py)
--   src/battle.lua                  battle rules, no drawing
-- Top screen: enemies and what they will do. Bottom screen: your hand.
-- Stylus: tap a card to pick it, tap again (or a target button) to play.
-- Buttons: left/right pick, A play, B cancel, START end turn.

local B = require("battle")

-- Screen states: "fight", "enemy" (enemy turn playing), "reward", "over"
local state
local sel           -- selected hand slot or nil
local targeting     -- true while choosing an enemy for the selected card
local steps, step_t -- enemy turn: list of actions and the frame counter
local rewards       -- the 3 card ids after a won fight
local popups = {}   -- floating numbers: { x, y, text, col, t }
local frame = 0

-- Colors
local BG_TOP, BG_BOT = 0x1a1626, 0x221c2c
local GOLD, INK, PAPER = 0xdcbe78, 0x141018, 0xd8c8a0
local KIND_COL = { attack = 0x7a3a30, skill = 0x30486a, power = 0x5a3a72 }

-- Images: missing art just leaves the window empty
local art = {}
local function img(id)
  if art[id] == nil then
    local ok, i = pcall(image, id)
    art[id] = ok and i or false
  end
  return art[id] or nil
end

-- Layout ------------------------------------------------------------------

local CARD_W, CARD_H, HAND_Y = 48, 64, 126

-- x of hand slot i (cards overlap when there are many)
local function card_x(i, n)
  local step = n > 1 and math.min(CARD_W + 2, (256 - 8 - CARD_W) // (n - 1)) or 0
  local total = step * (n - 1) + CARD_W
  return (256 - total) // 2 + (i - 1) * step
end

-- Center x of enemy i of n on the top screen
local function enemy_x(i, n) return 256 * i // (n + 1) end
local ENEMY_FEET = 150

local END_BTN = { x = 194, y = 4, w = 58, h = 16 }

local function inside(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

-- Target buttons over the hand, one per living enemy
local function target_buttons()
  local list = {}
  local alive = {}
  for i, e in ipairs(B.enemies) do if e.hp > 0 then alive[#alive + 1] = i end end
  local w = 76
  local x0 = (256 - (#alive * (w + 4) - 4)) // 2
  for k, i in ipairs(alive) do
    list[k] = { i = i, x = x0 + (k - 1) * (w + 4), y = 96, w = w, h = 20 }
  end
  return list
end

-- Sound -------------------------------------------------------------------

local sounds = {}
local function play(name, vol)
  if not sounds[name] then sounds[name] = sound(name) end
  sfx(sounds[name], vol or 0.8)
end

local function fight_music()
  music(B.enemies[1].def.boss and "boss" or "battle")
end

-- Popups ------------------------------------------------------------------

local function popup_pos(who)
  if who == B.player then return 30, 30, BOTTOM end
  for i, e in ipairs(B.enemies) do
    if e == who then
      return enemy_x(i, #B.enemies), ENEMY_FEET - e.def.size // 2, TOP
    end
  end
end

local function take_events()
  local played = {}
  for _, ev in ipairs(B.events) do
    if ev.snd and not played[ev.snd] then
      played[ev.snd] = true
      play(ev.snd)
    end
    local x, y, s = popup_pos(ev.who)
    if x and ev.text ~= "" then
      popups[#popups + 1] = { x = x + math.random(-6, 6), y = y, s = s,
                              text = ev.text, col = ev.col, t = 0 }
    end
  end
  B.events = {}
end

-- Game flow ---------------------------------------------------------------

local function new_run()
  B.new_run()
  B.start_fight()
  B.events = {}
  fight_music()
  state, sel, targeting = "fight", nil, false
end

local function after_action()
  take_events()
  local r = B.result()
  if r == "lost" then
    state = "over"
    music("defeat", false)
  elseif r == "won" then
    music("victory", false)
    if B.fight_no == B.fights_total() then
      state = "over"
    else
      rewards, state = B.rewards(), "reward"
    end
  end
end

local function try_play(i, t)
  local c = B.card(B.hand[i])
  if c.target and not t then
    if B.alive_enemies() == 1 then
      for k, e in ipairs(B.enemies) do if e.hp > 0 then t = k end end
    else
      targeting = true
      return
    end
  end
  if B.play(i, t) then
    sel, targeting = nil, false
    play(c.kind == "attack" and "slash" or "card", 0.6)
    after_action()
  else
    play("deny")
  end
end

local function end_turn()
  sel, targeting = nil, false
  steps, step_t, state = B.end_turn(), 0, "enemy"
end

local function next_fight(card)
  if card then B.add_card(card) end
  B.start_fight()
  B.events = {}
  fight_music()
  state, sel, targeting = "fight", nil, false
end

-- Input -------------------------------------------------------------------

local function fight_input()
  local n = #B.hand
  if btnp("start") then return end_turn() end
  if btnp("b") then sel, targeting = nil, false end
  if n > 0 and (btnp("left") or btnp("right")) then
    targeting = false
    local d = btnp("left") and -1 or 1
    sel = sel and ((sel - 1 + d) % n + 1) or (d > 0 and 1 or n)
    play("pick", 0.5)
  end
  if btnp("a") and sel then
    if targeting then
      local tb = target_buttons()
      try_play(sel, tb[1] and tb[1].i)
    else
      try_play(sel)
    end
  end

  if not btnp("touch") then return end
  local tx, ty = touch()
  if not tx then return end
  if inside(tx, ty, END_BTN.x, END_BTN.y, END_BTN.w, END_BTN.h) then return end_turn() end
  if targeting then
    for _, b in ipairs(target_buttons()) do
      if inside(tx, ty, b.x, b.y, b.w, b.h) then return try_play(sel, b.i) end
    end
  end
  -- topmost card first (later cards are drawn over earlier ones)
  for i = n, 1, -1 do
    local x = card_x(i, n)
    local y = HAND_Y - (i == sel and 12 or 0)
    if inside(tx, ty, x, y, CARD_W, CARD_H) then
      if sel == i and not targeting then
        try_play(i)
      else
        sel, targeting = i, false
        play("pick", 0.5)
      end
      return
    end
  end
  sel, targeting = nil, false
end

local function reward_x(k) return 40 + (k - 1) * 64 end
local REWARD_Y = 60
local SKIP_BTN = { x = 98, y = 150, w = 60, h = 18 }

local function reward_input()
  if not btnp("touch") then return end
  local tx, ty = touch()
  if not tx then return end
  for k, id in ipairs(rewards) do
    if inside(tx, ty, reward_x(k), REWARD_Y, CARD_W, CARD_H) then return next_fight(id) end
  end
  if inside(tx, ty, SKIP_BTN.x, SKIP_BTN.y, SKIP_BTN.w, SKIP_BTN.h) then next_fight() end
end

function _init()
  math.randomseed(micros())
  new_run()
end

function _update()
  frame = frame + 1
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.t, p.y = p.t + 1, p.y - 0.7
    if p.t > 40 then table.remove(popups, i) end
  end

  if state == "fight" then
    fight_input()
  elseif state == "enemy" then
    step_t = step_t + 1
    if step_t >= 14 then
      step_t = 0
      table.remove(steps, 1)()
      after_action()
      if state == "enemy" and #steps == 0 then
        state = "fight"
        play("turn", 0.6)
      end
    end
  elseif state == "reward" then
    reward_input()
  elseif state == "over" then
    if btnp("touch") or btnp("a") then new_run() end
  end
end

-- Drawing -----------------------------------------------------------------

local function status_text(st)
  local s = ""
  if st.str ~= 0 then s = s .. "S" .. st.str .. " " end
  if st.weak > 0 then s = s .. "W" .. st.weak .. " " end
  if st.vuln > 0 then s = s .. "V" .. st.vuln .. " " end
  if st.poison > 0 then s = s .. "P" .. st.poison .. " " end
  return s
end

local function bar(x, y, w, v, max, col)
  rectfill(x, y, w, 5, 0x3a1010)
  rectfill(x, y, w * v // max, 5, col)
  rect(x, y, w, 5, INK)
end

local function button(b, label, col)
  rectfill(b.x, b.y, b.w, b.h, col)
  rect(b.x, b.y, b.w, b.h, GOLD)
  local w = textw(label)
  text(label, b.x + (b.w - w) // 2, b.y + (b.h - 8) // 2, 0xffffff)
end

-- One card, top left at x, y
local function draw_card(id, x, y, dim)
  local c = B.card(id)
  rectfill(x, y, CARD_W, CARD_H, KIND_COL[c.kind])
  rect(x, y, CARD_W, CARD_H, dim and 0x605040 or GOLD)
  rectfill(x + 3, y + 10, 42, 36, INK)
  local a = img(id)
  if a then spr(a, x + 4, y + 11) end
  -- name, a word per line
  rectfill(x + 3, y + 47, 42, 15, PAPER)
  local ly = y + 48
  for word in c.name:gmatch("%S+") do
    text(word:sub(1, 7), x + 4, ly, INK)
    ly = ly + 7
  end
  circfill(x + 6, y + 5, 5, dim and 0x404040 or 0x2858c8)
  circ(x + 6, y + 5, 5, 0xe0e0ff)
  text(tostring(c.cost), x + 4, y + 2, 0xffffff)
  if dim then
    alpha(0.4)
    rectfill(x, y, CARD_W, CARD_H, 0)
    alpha()
  end
end

local INTENT_COL = { attack = 0xe04030, defend = 0x4080e0, buff = 0x40c060, debuff = 0xa050d0 }

local function draw_intent(e, cx, y)
  local kind, dmg, times = B.intent(e)
  local col = INTENT_COL[kind]
  local label = dmg and (times and (dmg .. "x" .. times) or tostring(dmg)) or ""
  local w = 12 + textw(label)
  local x = cx - w // 2
  if kind == "attack" then
    trifill(x, y + 9, x + 9, y, x + 10, y + 2, col)
    line(x + 1, y + 5, x + 5, y + 9, GOLD)
  elseif kind == "defend" then
    circfill(x + 5, y + 4, 5, col)
  elseif kind == "buff" then
    trifill(x, y + 9, x + 5, y, x + 10, y + 9, col)
  else
    trifill(x, y, x + 5, y + 9, x + 10, y, col)
  end
  text(label, x + 12, y + 1, 0xffffff)
end

local function draw_top()
  cls(BG_TOP)
  rectfill(0, ENEMY_FEET, 256, 42, 0x2a2236)
  local p = B.player
  text("HP " .. p.hp .. "/" .. p.max, 4, 4, 0xff8080)
  text("Fight " .. B.fight_no .. "/" .. B.fights_total(), 184, 4, GOLD)

  local n = #B.enemies
  for i, e in ipairs(B.enemies) do
    local cx = enemy_x(i, n)
    local s = e.def.size
    if e.hp > 0 then
      local a = img(e.id)
      if a then
        spr(a, cx - s // 2, ENEMY_FEET - s)
      else
        rectfill(cx - s // 2, ENEMY_FEET - s, s, s, 0x506040)
      end
      if state ~= "reward" then draw_intent(e, cx, ENEMY_FEET - s - 14) end
      local w = 56
      bar(cx - w // 2, ENEMY_FEET + 4, w, e.hp, e.max, 0xd03030)
      local hp = e.hp .. "/" .. e.max
      text(hp, cx - textw(hp) // 2, ENEMY_FEET + 11, 0xffffff)
      if e.block > 0 then text("[" .. e.block .. "]", cx - w // 2 - 22, ENEMY_FEET + 2, 0x80b0ff) end
      local st = status_text(e.st)
      text(st, cx - textw(st) // 2, ENEMY_FEET + 21, 0xd0a0ff)
      text(e.def.name, cx - textw(e.def.name) // 2, ENEMY_FEET + 31, 0xa09080)
    end
  end

  for _, pp in ipairs(popups) do
    if pp.s == TOP then text(pp.text, pp.x - 6, pp.y, pp.col) end
  end

  if state == "over" then
    local msg = B.player.hp > 0 and "YOU WIN!" or "DEFEATED"
    rectfill(0, 80, 256, 30, 0)
    text(msg, (256 - textw(msg)) // 2, 85, GOLD)
    local m2 = "Fight " .. B.fight_no .. " of " .. B.fights_total()
    text(m2, (256 - textw(m2)) // 2, 97, 0xffffff)
  elseif state == "reward" then
    rectfill(0, 80, 256, 20, 0)
    local msg = "Victory! Pick a card."
    text(msg, (256 - textw(msg)) // 2, 86, GOLD)
  end
end

local function wrap(s, cols)
  local lines, line_ = {}, ""
  for word in s:gmatch("%S+") do
    if #line_ + #word + 1 > cols and #line_ > 0 then
      lines[#lines + 1], line_ = line_, word
    else
      line_ = #line_ > 0 and (line_ .. " " .. word) or word
    end
  end
  lines[#lines + 1] = line_
  return lines
end

local function draw_bottom()
  cls(BG_BOT)
  if state == "reward" then
    text("Add one card to your deck:", 50, 30, GOLD)
    for k, id in ipairs(rewards) do
      draw_card(id, reward_x(k), REWARD_Y)
      local c = B.card(id)
      for j, l in ipairs(wrap(c.text, 10)) do
        text(l, reward_x(k) - 6, REWARD_Y + CARD_H + 2 + (j - 1) * 8, 0xd0d0d0)
      end
    end
    button(SKIP_BTN, "Skip", 0x403850)
    return
  end
  if state == "over" then
    text("Tap to start a new run", 62, 90, GOLD)
    return
  end

  local p = B.player
  -- energy gem, block, statuses, piles
  circfill(16, 16, 12, 0xd09020)
  circ(16, 16, 12, 0xfff0a0)
  text(B.energy .. "/3", 6, 13, INK)
  text("Block " .. p.block, 34, 6, 0x80b0ff)
  text(status_text(p.st), 34, 16, 0xd0a0ff)
  text("Deck " .. #B.draw_pile .. "  Used " .. #B.discard, 4, 114, 0x908070)
  button(END_BTN, state == "enemy" and "..." or "End turn", state == "enemy" and 0x303030 or 0x6a3020)

  -- details of the selected card
  if sel and B.hand[sel] then
    local c = B.card(B.hand[sel])
    rectfill(4, 34, 248, 54, 0x120e18)
    rect(4, 34, 248, 54, GOLD)
    text(c.name .. "  (" .. c.cost .. " energy, " .. c.kind .. ")", 10, 38, GOLD)
    for j, l in ipairs(wrap(c.text, 39)) do text(l, 10, 50 + (j - 1) * 9, 0xffffff) end
    if not targeting then
      local hint = B.playable(sel) and "Tap again to play" or "Not enough energy"
      text(hint, 10, 76, 0x909090)
    end
  end
  if targeting then
    text("Choose a target:", 10, 76, 0xffd080)
    for _, b in ipairs(target_buttons()) do
      button(b, B.enemies[b.i].def.name:sub(1, 12), 0x6a3020)
    end
  end

  local n = #B.hand
  for i, id in ipairs(B.hand) do
    local y = HAND_Y - (i == sel and 12 or 0)
    draw_card(id, card_x(i, n), y, not B.playable(i))
  end

  for _, pp in ipairs(popups) do
    if pp.s == BOTTOM then text(pp.text, pp.x, pp.y, pp.col) end
  end
end

function _draw(surface)
  if surface == TOP then draw_top() else draw_bottom() end
end
