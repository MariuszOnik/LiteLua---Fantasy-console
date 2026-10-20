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

function run_once()
  B.new_run()
  while true do
    B.start_fight()
    local turns = 0
    while B.result() == "fight" do
      turns = turns + 1
      if turns > 60 then error("fight " .. B.fight_no .. " never ends") end
      bot_turn()
      if B.result() ~= "fight" then break end
      for _, step in ipairs(B.end_turn()) do step() end
    end
    B.events = {}
    if B.result() == "lost" then return false, B.fight_no end
    if B.fight_no == B.fights_total() then return true, B.fight_no end
    B.add_card(B.rewards()[1])
  end
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
        print(f"\nrunedeck bot: {wins}/{runs} wins, died at fight: "
              + ", ".join(f"{k}:{v}" for k, v in sorted(reached.items())))
        self.assertGreater(sum(reached.values()), 0)


if __name__ == "__main__":
    unittest.main()
