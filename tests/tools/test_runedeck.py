"""Runedeck battle rules (examples/carts/runedeck/src/battle.lua) with a
simple bot: many runs must finish without errors. Prints the win rate and
how far the bot gets, as a rough balance check.

Needs the lupa package (Lua 5.4 in Python); skipped without it.
"""
import os
import unittest

try:
    from lupa import lua54
except ImportError:
    lua54 = None

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "examples", "carts", "runedeck", "src").replace("\\", "/")

BOT = r"""
local B = require("battle")

-- Damage the enemies will do this turn
local function incoming()
  local sum = 0
  for _, e in ipairs(B.enemies) do
    if e.hp > 0 then
      local kind, dmg, times = B.intent(e)
      if dmg then sum = sum + dmg * (times or 1) end
    end
  end
  return sum
end

local function weakest()
  local best
  for i, e in ipairs(B.enemies) do
    if e.hp > 0 and (not best or e.hp < B.enemies[best].hp) then best = i end
  end
  return best
end

-- Plays cards until nothing is playable: block while hits are coming,
-- otherwise attack the weakest enemy
local function bot_turn()
  for _ = 1, 30 do
    if B.result() ~= "fight" then return end
    local need_block = incoming() > B.player.block
    local pick, score = nil, -1
    for i, id in ipairs(B.hand) do
      if B.playable(i) then
        local c = B.card(id)
        local s = 1
        if c.kind == "power" then s = 5 end
        if c.kind == "skill" and need_block then s = 4 end
        if c.kind == "attack" then s = need_block and 2 or 4 end
        if c.cost == 0 then s = s + 1 end
        if s > score then pick, score = i, s end
      end
    end
    if not pick then return end
    B.play(pick, B.card(B.hand[pick]).target and weakest() or nil)
  end
end

local D = require("dungeon")
local G = require("gear")

-- Takes an item: better gear is worn, scrolls teach their first card
local function take(id)
  local it = G.item(id)
  if it.slot == "scroll" then
    G.learn(B.rewards()[1])
  elseif it.slot == "potion" then
    G.pickup(id)
  else
    local worn = G.equip[it.slot]
    if not worn or G.item(worn).tier < it.tier then
      if G.pickup(id) then G.wear(#G.bag) end
    end
  end
end

local function drink_if_low()
  while B.player.hp < B.player.max * 0.5 and G.potion_slot() do G.drink(G.potion_slot()) end
end

-- Fights every monster group of every floor, in map order, and picks up
-- all items (those on the floor first, drops after each fight)
function run_once()
  B.new_run()
  G.new_run()
  for floor = 1, D.floors_total() do
    D.generate(floor)
    if floor > 1 then B.heal_part(0.3) end
    for _, it in ipairs(D.items) do take(it.id) end
    for _, m in ipairs(D.monsters) do
      drink_if_low()
      B.start_fight(m.group, D.hp_scale())
      local turns = 0
      while B.result() == "fight" do
        turns = turns + 1
        if turns > 60 then error("fight on floor " .. floor .. " never ends") end
        bot_turn()
        if B.result() ~= "fight" then break end
        for _, step in ipairs(B.end_turn()) do step() end
      end
      B.events = {}
      if B.result() == "lost" then return false, floor end
      if not m.boss and math.random(100) <= 60 then take(G.roll_loot(floor)) end
    end
  end
  return true, D.floors_total()
end

-- Flood fill from the player: stairs and every monster must be reachable
function check_floor(n)
  D.generate(n)
  local seen, stack, reach = {}, { { D.px, D.py } }, 0
  while #stack > 0 do
    local x, y = table.unpack(table.remove(stack))
    local k = y * 100 + x
    if not seen[k] and D.walkable(x, y) then
      seen[k] = true
      reach = reach + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        stack[#stack + 1] = { x + d[1], y + d[2] }
      end
    end
  end
  for _, m in ipairs(D.monsters) do
    if not seen[m.y * 100 + m.x] then error("monster not reachable on floor " .. n) end
  end
  local stairs = 0
  for y = 1, D.H do
    for x = 1, D.W do
      if D.map[y][x] == ">" then
        stairs = stairs + 1
        if not seen[y * 100 + x] then error("stairs not reachable on floor " .. n) end
      end
    end
  end
  if stairs ~= (D.last and 0 or 1) then error("floor " .. n .. " has " .. stairs .. " stairs") end
  return #D.monsters
end
"""


@unittest.skipIf(lua54 is None, "lupa is not installed")
class RunedeckTest(unittest.TestCase):
    def test_bot_runs(self):
        lua = lua54.LuaRuntime()
        lua.execute(f'package.path = "{SRC}/?.lua;" .. package.path')
        lua.execute(BOT)
        run_once = lua.globals().run_once
        runs, wins, reached = 300, 0, {}
        lua.execute("math.randomseed(1)")
        for _ in range(runs):
            won, fight = run_once()
            wins += bool(won)
            reached[fight] = reached.get(fight, 0) + 1
        print(f"\nrunedeck bot: {wins}/{runs} wins, last floor: "
              + ", ".join(f"{k}:{v}" for k, v in sorted(reached.items())))
        self.assertGreater(sum(reached.values()), 0)

    def test_floors(self):
        lua = lua54.LuaRuntime()
        lua.execute(f'package.path = "{SRC}/?.lua;" .. package.path')
        lua.execute(BOT)
        lua.execute("math.randomseed(2)")
        check = lua.globals().check_floor
        for _ in range(100):
            for n in range(1, 6):
                self.assertGreater(check(n), 0)

    def test_main_flow(self):
        """main.lua with a fake API: walk into a monster, win, back on the map"""
        lua = lua54.LuaRuntime()
        cart = os.path.dirname(SRC)
        lua.execute(f'package.path = "{SRC}/?.lua;" .. package.path')
        lua.execute(STUBS)
        lua.execute(f'dofile("{cart}/main.lua")')
        g = lua.globals()
        run = lua.eval("""function(keys, tx, ty)
          pressed, touch_x, touch_y = keys, tx, ty
          _update(); drawn = {}; _draw(TOP); _draw(BOTTOM)
          pressed, touch_x, touch_y = {}, nil, nil
          return drawn
        end""")
        keys = lambda *k: lua.table_from({n: True for n in k})
        g._init()
        drawn = run(keys())
        self.assertIn("New run", list(drawn.values()))
        drawn = run(keys("a"))                     # title: New run
        self.assertIn("You enter the ruins.", list(drawn.values()))
        self.assertIn("return", lua.eval('saves["save/run.lua"] or ""'))
        # put a monster right of the player and walk into it
        lua.execute("""local D = require("dungeon")
          D.map[D.py][D.px + 1] = "."
          D.monsters = { { x = D.px + 1, y = D.py, group = { "goblin" }, glyph = "g", col = 0 } }""")
        drawn = run(keys("right"))
        self.assertIn("End turn", list(drawn.values()))
        # the goblin dies; after the enemy turn the reward screen comes
        lua.execute('require("battle").enemies[1].hp = 0')
        run(keys("start"))
        for _ in range(40):
            drawn = run(keys())
        self.assertIn("You won. HP 60/60.", list(drawn.values()))
        self.assertEqual(lua.eval('#require("dungeon").monsters'), 0)
        # the bag: wear an axe from the bag, the deck changes
        lua.execute('local G = require("gear"); G.pickup("battle_axe")')
        drawn = run(keys("x"))
        self.assertIn("Your deck: 10 cards", list(drawn.values()))
        run(keys("down"))                          # worn weapon -> bag slot 1
        run(keys("right"))                         # bag slot 2: the axe
        drawn = run(keys("a"))
        self.assertIn("Battle Axe.", list(drawn.values()))
        self.assertIn("2x Cleave", list(drawn.values()))
        # a scroll: read it, learn the first card
        lua.execute('require("gear").pickup("scroll")')
        n_before = lua.eval('#require("battle").player.deck')
        # choose the scroll with the stylus: bag box 3 is at x 84, y 72
        run(keys("touch"), 90, 80)
        drawn = run(keys("a"))
        self.assertIn("Learn one card:", list(drawn.values()))
        run(keys("right"))
        drawn = run(keys("a"))
        self.assertEqual(lua.eval('#require("battle").player.deck'), n_before + 1)
        # the save of floor 1 continues with the gear worn at that moment
        g._init()
        drawn = run(keys())
        self.assertIn("Continue: floor 1", list(drawn.values()))
        drawn = run(keys("a"))
        self.assertIn("Floor 1 again.", " ".join(str(v) for v in drawn.values()))
        self.assertEqual(lua.eval('#require("battle").player.deck'), 10)

    def test_seed_makes_same_floor(self):
        lua = lua54.LuaRuntime()
        lua.execute(f'package.path = "{SRC}/?.lua;" .. package.path')
        f = lua.eval("""function(seed, n)
          local D = require("dungeon")
          math.randomseed(seed * 8 + n)
          D.generate(n)
          local rows = {}
          for y = 1, D.H do rows[y] = table.concat(D.map[y]) end
          for _, m in ipairs(D.monsters) do rows[#rows + 1] = m.x .. "," .. m.y .. m.glyph end
          for _, it in ipairs(D.items) do rows[#rows + 1] = it.x .. "," .. it.y .. it.id end
          return table.concat(rows, "/")
        end""")
        self.assertEqual(f(123456, 3), f(123456, 3))
        self.assertNotEqual(f(123456, 3), f(654321, 3))


STUBS = r"""
TOP, BOTTOM = 0, 1
pressed, drawn = {}, {}
function btnp(k) return pressed[k] == true end
function btn(k) return pressed[k] == true end
function touch() return touch_x, touch_y end
function text(s) drawn[#drawn + 1] = s end
function textw(s) return #s * 6, 8 end
function micros() return 1 end
function image() error("no art in tests") end
function sound(n) return n end
-- save/ files live in memory
saves = {}
local real_open = io.open
io.open = function(path, mode)
  if path:sub(1, 5) ~= "save/" then return real_open(path, mode) end
  if (mode or "r"):sub(1, 1) == "w" then
    local buf = {}
    return { write = function(self, s) buf[#buf + 1] = s end,
             close = function() saves[path] = table.concat(buf) end }
  end
  if not saves[path] then return nil end
  return { read = function() return saves[path] end, close = function() end }
end
os.remove = function(path) saves[path] = nil return true end
for _, f in ipairs({ "cls", "rect", "rectfill", "circ", "circfill", "line", "trifill",
                     "spr", "alpha", "sfx", "music" }) do _G[f] = function() end end
"""


if __name__ == "__main__":
    unittest.main()
