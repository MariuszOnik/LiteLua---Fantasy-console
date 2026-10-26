-- HeroesDS C4: the test battle's armies. A set-up (src/menu.lua) per side: a hero or none
-- ({ type, level, artifacts }) and up to 6 stacks ({ key, count }); setup.default(seed) is
-- the old seed-made one (as c4bench and ai_test.lua's real battles). Side 0 is the player.
--
-- A hero type is a school (life, order, death, chaos, nature, might) and a role (fighter,
-- archer, mage), as the game's hero models (combat_actor hero.<school>_<role>_male, made by
-- make_c4.py). Its skills grow with its level: L = 1 + level // 5 (at most 5) in its role's
-- skill (Melee, Archery, or the school's magic), lower ones beside; it knows the combat
-- spells of its school up to its magic skill's level.

local battle = require("combat.battle")
local heroes = require("combat.heroes")

local setup = {}

local SCHOOLS = { { "life", "Życie" }, { "order", "Ład" }, { "death", "Śmierć" },
                  { "chaos", "Chaos" }, { "nature", "Natura" }, { "might", "Moc" } }
local ROLES = { { "fighter", "wojownik" }, { "archer", "łucznik" }, { "mage", "mag" } }

setup.TYPES = {}   -- { id = "life_fighter", school, role, label }
for _, s in ipairs(SCHOOLS) do
  for _, r in ipairs(ROLES) do
    if not (s[1] == "might" and r[1] == "mage") then
      setup.TYPES[#setup.TYPES + 1] = { id = s[1] .. "_" .. r[1], school = s[1], role = r[1],
                                        label = s[2] .. " - " .. r[2] }
    end
  end
end

function setup.type_of(id)
  for _, t in ipairs(setup.TYPES) do if t.id == id then return t end end
  return setup.TYPES[1]
end

-- The hero of a set-up: its skills, spells and model
function setup.hero(h, side, spells)
  local t = setup.type_of(h.type)
  local L = math.min(5, 1 + h.level // 5)
  local low = math.max(0, L - 2)
  local skills = {}
  if t.role == "fighter" then skills.combat, skills.toughness = L, math.max(0, L - 1)
  elseif t.role == "archer" then skills.archery, skills.combat = L, low
  else skills.combat = 0 end
  local magic = 0
  if t.school ~= "might" then
    magic = t.role == "mage" and L or math.max(1, low)
    skills[t.school] = magic
  end
  local known = {}
  for key, s in pairs(spells) do
    if s.school == t.school and s.level <= magic and s.flags and s.flags.combat then known[#known + 1] = key end
  end
  table.sort(known)
  return { name = side == 0 and "Gracz" or "Wróg", level = h.level, skills = skills, spells = known,
           artifacts = h.artifacts, actor = "hero." .. t.id .. "_male" }
end

function setup.default(seed, creatures)
  local keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys)
  local function k(i) return keys[(i - 1) % #keys + 1] end
  return {
    [0] = { hero = { type = "chaos_fighter", level = 8, artifacts = {} },
            stacks = { { k(seed), 15 }, { k(seed * 3 + 1), 8 }, { k(seed * 7 + 2), 30 } } },
    [1] = { hero = { type = "death_mage", level = 8, artifacts = {} },
            stacks = { { k(seed * 11 + 3), 12 }, { k(seed * 13 + 4), 20 }, { k(seed * 17 + 5), 6 } } },
  }
end

-- data = { creatures, spells, artifacts }
function setup.battle(seed, data, cfg)
  cfg = cfg or setup.default(seed, data.creatures)
  local spec = { seed = seed * 7919, sides = {} }
  local actors = {}
  for s = 0, 1 do
    local army = {}
    for _, a in ipairs(cfg[s].stacks) do army[#army + 1] = { creature = a[1], count = a[2] } end
    local list = {}
    if cfg[s].hero then
      local h = setup.hero(cfg[s].hero, s, data.spells)
      list[1] = h
      actors[s] = h.actor
    end
    spec.sides[s] = { heroes = list, army = army }
  end
  local b_setup = heroes.build(spec, data)
  b_setup.creatures = data.creatures
  for s = 0, 1 do
    for _, st in ipairs(b_setup.sides[s].stacks) do
      if st.is_hero then st.actor = actors[s] end
    end
  end
  return battle.new(b_setup)
end

return setup
