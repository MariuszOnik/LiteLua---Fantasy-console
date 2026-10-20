-- Battle rules: no drawing here, only state. main.lua reads the state and
-- calls play() / end_turn(). Rules are described in DESIGN.md.
local CARDS = require("cards")
local ENEMIES = require("enemies")

local B = {}

local HAND_MAX = 10

-- Events for the screen and the speakers: { who, text, col, snd }
-- (text "" = only a sound)
B.events = {}
local function event(who, text, col, snd)
  B.events[#B.events + 1] = { who = who, text = text, col = col, snd = snd }
end

local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

local function fighter(hp)
  return { hp = hp, max = hp, block = 0, st = { vuln = 0, weak = 0, poison = 0, str = 0 } }
end

-- Run ---------------------------------------------------------------------

function B.new_run()
  local p = fighter(60)
  p.deck = {}
  for i, id in ipairs(CARDS.starter) do p.deck[i] = id end
  B.player = p
end

-- Fight -------------------------------------------------------------------

local function choose_move(e)
  local moves = e.def.moves
  if e.def.random then
    local m
    repeat m = math.random(#moves) until m ~= e.move or #moves == 1
    e.move = m
  else
    e.move = e.move % #moves + 1
  end
end

-- group: list of enemy ids; hp_scale: enemy HP multiplier (deeper = more)
function B.start_fight(group, hp_scale)
  local p = B.player
  p.block = 0
  p.st = fighter(1).st
  B.enemies = {}
  for i, id in ipairs(group) do
    local def = ENEMIES[id]
    local e = fighter(math.floor(def.hp * (hp_scale or 1)))
    e.id, e.def, e.move = id, def, 0
    choose_move(e)
    B.enemies[i] = e
  end
  B.draw_pile, B.hand, B.discard = {}, {}, {}
  for i, id in ipairs(p.deck) do B.draw_pile[i] = id end
  shuffle(B.draw_pile)
  B.turn = 0
  B.start_turn()
end

function B.alive_enemies()
  local n = 0
  for _, e in ipairs(B.enemies) do if e.hp > 0 then n = n + 1 end end
  return n
end

-- "fight", "won" or "lost"
function B.result()
  if B.player.hp <= 0 then return "lost" end
  if B.alive_enemies() == 0 then return "won" end
  return "fight"
end

local function draw(n)
  for _ = 1, n do
    if #B.hand >= HAND_MAX then return end
    if #B.draw_pile == 0 then
      if #B.discard == 0 then return end
      B.draw_pile, B.discard = B.discard, {}
      shuffle(B.draw_pile)
    end
    B.hand[#B.hand + 1] = table.remove(B.draw_pile)
  end
end

local function hurt(who, n, color, snd)
  if n <= 0 then return end
  who.hp = math.max(0, who.hp - n)
  if who.hp == 0 and who ~= B.player then snd = "die" end
  event(who, "-" .. n, color or 0xff4040, snd or (who == B.player and "hurt" or "hit"))
end

-- Damage: (base + str) x0.75 if weak x1.5 if vulnerable, then block first
local function attack(from, to, base)
  if to.hp <= 0 then return end
  local d = base + from.st.str
  if from.st.weak > 0 then d = d * 0.75 end
  if to.st.vuln > 0 then d = d * 1.5 end
  d = math.max(0, math.floor(d))
  local absorbed = math.min(to.block, d)
  to.block = to.block - absorbed
  if absorbed > 0 then event(to, "-" .. absorbed, 0x60a0ff, "clang") end
  hurt(to, d - absorbed)
end

-- Poison at the start of the owner's turn
local function tick_poison(who)
  if who.st.poison > 0 then
    hurt(who, who.st.poison, 0x60ff60, "poison")
    who.st.poison = who.st.poison - 1
  end
end

-- Weak and vulnerable count down at the end of the owner's turn
local function tick_end(who)
  if who.st.weak > 0 then who.st.weak = who.st.weak - 1 end
  if who.st.vuln > 0 then who.st.vuln = who.st.vuln - 1 end
end

-- Runs a list of effects. "self" is who uses them, "target" the chosen
-- foe, "foes" everyone on the other side.
local function run_fx(fx, self, target, foes, card)
  for _, f in ipairs(fx) do
    local op = f[1]
    if op == "dmg" then
      local n = f[2]
      if card and card.exec and target.hp * 2 <= target.max then n = n * 2 end
      for _ = 1, f[3] or 1 do attack(self, target, n) end
    elseif op == "dmg_all" then
      for _ = 1, f[3] or 1 do
        for _, e in ipairs(foes) do attack(self, e, f[2]) end
      end
    elseif op == "pierce" then
      local block = target.block
      target.block = 0
      attack(self, target, f[2])
      target.block = block
    elseif op == "dmg_block" then
      attack(self, target, self.block)
    elseif op == "block" then
      self.block = self.block + f[2]
      event(self, "+" .. f[2], 0x60a0ff, "block")
    elseif op == "draw" then
      draw(f[2])
    elseif op == "energy" then
      B.energy = B.energy + f[2]
    elseif op == "hp" then
      if f[2] < 0 then hurt(self, -f[2]) else self.hp = math.min(self.max, self.hp + f[2]) end
    elseif op == "apply" then
      if target.hp > 0 then target.st[f[2]] = target.st[f[2]] + f[3] end
      event(target, "", 0, "debuff")
    elseif op == "apply_all" then
      for _, e in ipairs(foes) do
        if e.hp > 0 then e.st[f[2]] = e.st[f[2]] + f[3] end
      end
      event(self, "", 0, "debuff")
    elseif op == "self" then
      self.st[f[2]] = self.st[f[2]] + f[3]
      event(self, "", 0, "buff")
    end
  end
end

function B.start_turn()
  local p = B.player
  B.turn = B.turn + 1
  B.energy = 3
  p.block = 0
  tick_poison(p)
  draw(5)
end

function B.card(id) return CARDS[id] end

function B.enemy_name(id) return ENEMIES[id].name end

-- Heals the player by a part of max HP; returns how much
function B.heal_part(part)
  local p = B.player
  local n = math.min(p.max - p.hp, math.floor(p.max * part))
  p.hp = p.hp + n
  return n
end

-- Can the card in hand slot i be played now?
function B.playable(i)
  local c = CARDS[B.hand[i]]
  return c.cost <= B.energy
end

-- Plays hand slot i at enemy number t (nil for cards without a target)
function B.play(i, t)
  local id = B.hand[i]
  local c = CARDS[id]
  if c.cost > B.energy then return false end
  local target = t and B.enemies[t]
  if c.target and (not target or target.hp <= 0) then return false end
  B.energy = B.energy - c.cost
  table.remove(B.hand, i)
  -- powers stay in play for the fight: they do not go to the discard pile
  if c.kind ~= "power" then B.discard[#B.discard + 1] = id end
  local alive = {}
  for _, e in ipairs(B.enemies) do if e.hp > 0 then alive[#alive + 1] = e end end
  run_fx(c.fx, B.player, target, alive, c)
  return true
end

-- The player's turn ends. Returns the list of enemy actions, as functions
-- main.lua calls one after another with a pause between them.
function B.end_turn()
  for _, id in ipairs(B.hand) do B.discard[#B.discard + 1] = id end
  B.hand = {}
  tick_end(B.player)
  local steps = {}
  for _, e in ipairs(B.enemies) do
    if e.hp > 0 then
      steps[#steps + 1] = function()
        if e.hp <= 0 or B.player.hp <= 0 then return end
        e.block = 0
        tick_poison(e)
        if e.hp <= 0 then return end
        run_fx(e.def.moves[e.move].fx, e, B.player, { B.player })
        tick_end(e)
        choose_move(e)
      end
    end
  end
  steps[#steps + 1] = function()
    if B.result() == "fight" then B.start_turn() end
  end
  return steps
end

-- What enemy e will do: intent name and the damage it shows (or nil)
function B.intent(e)
  local m = e.def.moves[e.move]
  local dmg, times
  for _, f in ipairs(m.fx) do
    if f[1] == "dmg" then
      local d = f[2] + e.st.str
      if e.st.weak > 0 then d = d * 0.75 end
      if B.player.st.vuln > 0 then d = d * 1.5 end
      dmg, times = math.floor(d), f[3]
    end
  end
  return m.intent, dmg, times
end

-- Rewards: 3 different random cards that are not in the starter set
function B.rewards()
  local pool = {}
  for id, c in pairs(CARDS) do
    if type(c) == "table" and c.cost and id ~= "slash" and id ~= "guard" then
      pool[#pool + 1] = id
    end
  end
  table.sort(pool) -- pairs order is not fixed
  shuffle(pool)
  return { pool[1], pool[2], pool[3] }
end

function B.add_card(id)
  B.player.deck[#B.player.deck + 1] = id
end

return B
