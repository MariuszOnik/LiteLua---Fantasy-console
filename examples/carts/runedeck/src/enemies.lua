-- Enemies and fights. Pure data, like cards.lua.
--
-- An enemy repeats its "moves" in order (or picks at random with
-- random = true, never the same move twice in a row). The move it will
-- make is shown over its head (its intent) during the player's turn.
-- A move is a list of effects, the same ops as cards (see cards.lua),
-- aimed at the player; "dmg" uses the enemy's strength and weak.
--   intent: "attack", "defend", "buff", "debuff" (icon over the head)
-- glyph, color: how it looks on the map (a group shows the first enemy,
-- in capitals). slow = true: moves every other turn on the map.
return {
  goblin = {
    name = "Goblin", hp = 18, size = 64, glyph = "g", color = 0x60d040,
    moves = {
      { intent = "attack", fx = { { "dmg", 6 } } },
      { intent = "attack", fx = { { "dmg", 4 }, { "apply", "weak", 1 } } },
    },
    art = "a small green goblin warrior holding a rusty dagger, full body, facing viewer",
  },
  slime = {
    name = "Slime", hp = 28, size = 64, glyph = "s", color = 0x40e0a0,
    random = true,
    moves = {
      { intent = "attack", fx = { { "dmg", 8 } } },
      { intent = "defend", fx = { { "block", 6 } } },
      { intent = "debuff", fx = { { "apply", "poison", 3 } } },
    },
    art = "a round toxic green slime blob with one big eye, full body",
  },
  archer = {
    name = "Bone Archer", hp = 24, size = 64, glyph = "k", color = 0xe0e0c0,
    moves = {
      { intent = "attack", fx = { { "dmg", 3, 2 } } },
      { intent = "buff",   fx = { { "self", "str", 2 } } },
      { intent = "attack", fx = { { "dmg", 3, 2 } } },
    },
    art = "a skeleton archer drawing a bow, full body, facing viewer",
  },
  ogre = {
    name = "Ogre Chief", hp = 80, size = 96, boss = true, glyph = "&", color = 0xff6030,
    moves = {
      { intent = "attack", fx = { { "dmg", 11 } } },
      { intent = "defend", fx = { { "block", 10 }, { "self", "str", 2 } } },
      { intent = "debuff", fx = { { "apply", "vuln", 2 }, { "apply", "weak", 2 } } },
      { intent = "attack", fx = { { "dmg", 20 } } },
    },
    art = "a huge ogre chieftain with a spiked club and bone crown, full body, facing viewer",
  },

  rat = {
    name = "Rat Swarm", hp = 12, size = 64, glyph = "r", color = 0xb08860,
    moves = {
      { intent = "attack", fx = { { "dmg", 2, 3 } } },
      { intent = "attack", fx = { { "dmg", 5 } } },
    },
    art = "a swarm of three brown sewer rats with red eyes",
  },
  bat = {
    name = "Cave Bat", hp = 14, size = 64, glyph = "b", color = 0x9070c0,
    random = true,
    moves = {
      { intent = "attack", fx = { { "dmg", 5 } } },
      { intent = "debuff", fx = { { "apply", "weak", 2 } } },
      { intent = "attack", fx = { { "dmg", 3, 2 } } },
    },
    art = "a purple cave bat with spread wings, facing viewer",
  },
  zombie = {
    name = "Zombie", hp = 36, size = 64, glyph = "z", color = 0x70a050, slow = true,
    moves = {
      { intent = "attack", fx = { { "dmg", 10 } } },
      { intent = "debuff", fx = { { "apply", "poison", 4 } } },
      { intent = "attack", fx = { { "dmg", 7 } } },
    },
    art = "a rotting green zombie with torn clothes, full body, facing viewer",
  },
  wraith = {
    name = "Wraith", hp = 22, size = 64, glyph = "w", color = 0xa0c0ff,
    moves = {
      { intent = "debuff", fx = { { "apply", "vuln", 2 }, { "apply", "weak", 1 } } },
      { intent = "attack", fx = { { "dmg", 8 } } },
      { intent = "attack", fx = { { "dmg", 4, 2 } } },
    },
    art = "a pale blue hooded ghost wraith floating, facing viewer",
  },
  cultist = {
    name = "Cultist", hp = 26, size = 64, glyph = "c", color = 0xd04060,
    moves = {
      { intent = "buff", fx = { { "self", "str", 3 } } },
      { intent = "attack", fx = { { "dmg", 5 } } },
      { intent = "attack", fx = { { "dmg", 5 } } },
    },
    art = "a cultist in a red robe holding a ritual dagger, full body, facing viewer",
  },
  orc = {
    name = "Orc Brute", hp = 40, size = 64, glyph = "o", color = 0x80a040,
    moves = {
      { intent = "attack", fx = { { "dmg", 12 } } },
      { intent = "defend", fx = { { "block", 8 } } },
      { intent = "attack", fx = { { "dmg", 6, 2 } } },
    },
    art = "a muscular green orc warrior with a big cleaver, full body, facing viewer",
  },
  mage = {
    name = "Dark Mage", hp = 30, size = 64, glyph = "m", color = 0xc060ff,
    random = true,
    moves = {
      { intent = "debuff", fx = { { "apply", "poison", 5 } } },
      { intent = "attack", fx = { { "dmg", 9 } } },
      { intent = "defend", fx = { { "block", 10 } } },
    },
    art = "a dark mage in a purple robe casting a spell, full body, facing viewer",
  },

  -- Dungeon floors, top to bottom: how many monsters, which groups they
  -- are (one is picked for each), and on the last floor the boss.
  -- items: treasures lying on the floor (monsters drop more)
  floors = {
    { name = "Sewers", monsters = 5, items = 4,
      groups = { { "goblin" }, { "slime" }, { "rat" }, { "bat" } } },
    { name = "Sewers", monsters = 6, items = 3,
      groups = { { "goblin", "goblin" }, { "slime" }, { "rat", "rat" }, { "bat", "goblin" }, { "archer" } } },
    { name = "Crypt", monsters = 6, items = 3,
      groups = { { "zombie" }, { "archer" }, { "wraith" }, { "archer", "bat" }, { "cultist" } } },
    { name = "Crypt", monsters = 6, items = 3,
      groups = { { "zombie", "archer" }, { "wraith", "wraith" }, { "cultist", "cultist" }, { "zombie", "bat" } } },
    { name = "Orc Den", monsters = 5, items = 3,
      groups = { { "orc" }, { "mage" }, { "orc", "cultist" }, { "mage", "archer" } }, boss = { "ogre" } },
  },
}
