-- Enemies and fights. Pure data, like cards.lua.
--
-- An enemy repeats its "moves" in order (or picks at random with
-- random = true, never the same move twice in a row). The move it will
-- make is shown over its head (its intent) during the player's turn.
-- A move is a list of effects, the same ops as cards (see cards.lua),
-- aimed at the player; "dmg" uses the enemy's strength and weak.
--   intent: "attack", "defend", "buff", "debuff" (icon over the head)
return {
  goblin = {
    name = "Goblin", hp = 18, size = 64,
    moves = {
      { intent = "attack", fx = { { "dmg", 6 } } },
      { intent = "attack", fx = { { "dmg", 4 }, { "apply", "weak", 1 } } },
    },
    art = "a small green goblin warrior holding a rusty dagger, full body, facing viewer",
  },
  slime = {
    name = "Slime", hp = 28, size = 64,
    random = true,
    moves = {
      { intent = "attack", fx = { { "dmg", 8 } } },
      { intent = "defend", fx = { { "block", 6 } } },
      { intent = "debuff", fx = { { "apply", "poison", 3 } } },
    },
    art = "a round toxic green slime blob with one big eye, full body",
  },
  archer = {
    name = "Bone Archer", hp = 24, size = 64,
    moves = {
      { intent = "attack", fx = { { "dmg", 3, 2 } } },
      { intent = "buff",   fx = { { "self", "str", 2 } } },
      { intent = "attack", fx = { { "dmg", 3, 2 } } },
    },
    art = "a skeleton archer drawing a bow, full body, facing viewer",
  },
  ogre = {
    name = "Ogre Chief", hp = 80, size = 96, boss = true,
    moves = {
      { intent = "attack", fx = { { "dmg", 11 } } },
      { intent = "defend", fx = { { "block", 10 }, { "self", "str", 2 } } },
      { intent = "debuff", fx = { { "apply", "vuln", 2 }, { "apply", "weak", 2 } } },
      { intent = "attack", fx = { { "dmg", 20 } } },
    },
    art = "a huge ogre chieftain with a spiked club and bone crown, full body, facing viewer",
  },

  -- A run: fights in order, the last one is the boss.
  -- After each won fight the player picks 1 of 3 random cards.
  fights = {
    { "goblin" },
    { "slime" },
    { "goblin", "archer" },
    { "slime", "goblin" },
    { "archer", "archer" },
    { "ogre" },
  },
}
