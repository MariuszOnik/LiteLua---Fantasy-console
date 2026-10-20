-- Equipment, bag and the deck built from them. No drawing here.
-- The deck = cards of the equipped items + cards learned from scrolls.
local ITEMS = require("items")
local CARDS = require("cards")
local B = require("battle")

local G = {}

G.SLOTS = { "weapon", "armor", "shield", "charm" }
G.BAG_MAX = 8
G.BASE_HP = 60

function G.item(id) return ITEMS[id] end

function G.new_run()
  G.equip = {}
  for slot, id in pairs(ITEMS.start) do G.equip[slot] = id end
  G.bag = {}
  for i, id in ipairs(ITEMS.start_bag) do G.bag[i] = id end
  G.learned = {}
  G.rebuild()
  B.player.hp = B.player.max
end

-- Deck and max HP from what is worn. HP stays, but not over the max.
function G.rebuild()
  local deck, hp = {}, G.BASE_HP
  for _, slot in ipairs(G.SLOTS) do
    local it = ITEMS[G.equip[slot]]
    if it then
      for _, c in ipairs(it.cards) do deck[#deck + 1] = c end
      hp = hp + (it.hp or 0)
    end
  end
  for _, c in ipairs(G.learned) do deck[#deck + 1] = c end
  local p = B.player
  p.deck = deck
  local gained = hp - (p.max or hp)
  p.max = hp
  -- more max HP also heals that much; less max HP cuts HP down
  p.hp = math.max(1, math.min(hp, p.hp + math.max(0, gained)))
end

-- Picks an item up. Returns false when the bag is full.
function G.pickup(id)
  if #G.bag >= G.BAG_MAX then return false end
  G.bag[#G.bag + 1] = id
  return true
end

function G.drop(i)
  return table.remove(G.bag, i)
end

-- Wears bag item i; what was worn goes to its place in the bag
function G.wear(i)
  local id = G.bag[i]
  local slot = ITEMS[id].slot
  local old = G.equip[slot]
  G.equip[slot] = id
  if old then G.bag[i] = old else table.remove(G.bag, i) end
  G.rebuild()
end

-- Takes off the item in a slot (to the bag)
function G.unwear(slot)
  if not G.equip[slot] or #G.bag >= G.BAG_MAX then return false end
  G.bag[#G.bag + 1] = G.equip[slot]
  G.equip[slot] = nil
  G.rebuild()
  return true
end

-- Drinks bag item i (a potion). Returns HP healed.
function G.drink(i)
  local it = ITEMS[G.bag[i]]
  table.remove(G.bag, i)
  local p = B.player
  local n = math.min(p.max - p.hp, it.heal)
  p.hp = p.hp + n
  return n
end

-- First potion in the bag, or nil
function G.potion_slot()
  for i, id in ipairs(G.bag) do
    if ITEMS[id].slot == "potion" then return i end
  end
end

function G.potions()
  local n = 0
  for _, id in ipairs(G.bag) do
    if ITEMS[id].slot == "potion" then n = n + 1 end
  end
  return n
end

-- A scroll teaches one card
function G.learn(card)
  G.learned[#G.learned + 1] = card
  G.rebuild()
end

function G.forget(i)
  table.remove(G.learned, i)
  G.rebuild()
end

-- Random loot for floor n: an item id
local function pick(list) return list[math.random(#list)] end

function G.roll_loot(n)
  local max_tier = n >= 4 and 3 or n >= 2 and 2 or 1
  local r, kind = math.random(100), nil
  if r <= ITEMS.loot.scroll then
    kind = "scroll"
  elseif r <= ITEMS.loot.scroll + ITEMS.loot.potion then
    kind = "potion"
  else
    kind = "gear"
  end
  local list = {}
  for id, it in pairs(ITEMS) do
    if type(it) == "table" and it.slot and it.tier and it.tier >= 1 and it.tier <= max_tier then
      local gear = it.slot ~= "potion" and it.slot ~= "scroll"
      if (kind == "gear" and gear) or it.slot == kind then list[#list + 1] = id end
    end
  end
  table.sort(list) -- pairs order is not fixed
  return pick(list)
end

-- Counts of each card in the deck, sorted by name: { { id, n }, ... }
function G.deck_summary()
  local counts, list = {}, {}
  for _, c in ipairs(B.player.deck) do
    if not counts[c] then
      counts[c] = 0
      list[#list + 1] = c
    end
    counts[c] = counts[c] + 1
  end
  table.sort(list, function(a, b) return CARDS[a].name < CARDS[b].name end)
  for i, c in ipairs(list) do list[i] = { c, counts[c] } end
  return list
end

return G
