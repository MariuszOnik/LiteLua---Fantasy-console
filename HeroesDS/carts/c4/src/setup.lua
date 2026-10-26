-- HeroesDS C4b: test armies. A hero and three stacks a side, picked from creatures.lua by
-- the seed (the armies of c4bench and ai_test.lua's real battles); side 0 is the player.

local stats = require("combat.stats")
local battle = require("combat.battle")
local heroes = require("combat.heroes")

local setup = {}

function setup.battle(seed, creatures, spells)
  local keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys)
  local function st(i, n) local k = keys[(i - 1) % #keys + 1]; return stats.creature(k, creatures[k], n) end
  local att = { heroes.stack({ name = "Gracz", level = 8, skills = { chaos = 3, life = 3, combat = 2 },
                               spells = { "fireball", "bless", "magic arrow", "lightning" } }, {}),
                st(seed, 15), st(seed * 3 + 1, 8), st(seed * 7 + 2, 30) }
  local def = { heroes.stack({ name = "Wróg", level = 8, skills = { death = 3, order = 3, archery = 2 },
                               spells = { "curse", "slow", "magic arrow" } }, {}),
                st(seed * 11 + 3, 12), st(seed * 13 + 4, 20), st(seed * 17 + 5, 6) }
  att[1].actor, def[1].actor = "hero.life_fighter_male", "hero.death_mage_female"   -- make_c4.py
  return battle.new({ seed = seed * 7919, spells = spells, creatures = creatures,
                      sides = { [0] = { stacks = att }, [1] = { stacks = def } } })
end

return setup
