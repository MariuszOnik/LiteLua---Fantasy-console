-- Items: equipment gives the cards of your deck, potions and scrolls are
-- used up. Pure data, like cards.lua ("art" = icon prompt for tools).
--
-- slot: "weapon", "armor", "shield", "charm" (equipment), "potion", "scroll"
-- cards: card ids this item puts in the deck while equipped
-- hp: extra max HP while equipped
-- heal: HP a potion gives back (potions can be drunk in fights too)
-- tier: 1 = found from floor 1, 2 = from floor 2, 3 = from floor 4
-- glyph on the map: ) weapon  [ armor  ] shield  " charm  ! potion  ? scroll
return {
  -- Weapons
  rusty_sword = {
    name = "Rusty Sword", slot = "weapon", tier = 0,
    cards = { "slash", "slash", "slash", "slash", "crush" },
    art = "a short rusty iron sword",
  },
  battle_axe = {
    name = "Battle Axe", slot = "weapon", tier = 1,
    cards = { "cleave", "cleave", "slash", "slash", "crush" },
    art = "a double-bladed steel battle axe",
  },
  venom_dagger = {
    name = "Venom Dagger", slot = "weapon", tier = 1,
    cards = { "venom", "venom", "jab", "jab", "slash" },
    art = "a curved dagger dripping green poison",
  },
  twin_knives = {
    name = "Twin Knives", slot = "weapon", tier = 2,
    cards = { "flurry", "flurry", "jab", "jab", "slash" },
    art = "two crossed throwing knives",
  },
  headsman_axe = {
    name = "Headsman Axe", slot = "weapon", tier = 3,
    cards = { "execute", "execute", "crush", "slash", "slash" },
    art = "a black executioner axe with a red glowing edge",
  },

  -- Armor
  leather_vest = {
    name = "Leather Vest", slot = "armor", tier = 0,
    cards = { "guard", "guard", "guard" },
    art = "a brown leather vest armor",
  },
  wind_cloak = {
    name = "Wind Cloak", slot = "armor", tier = 1,
    cards = { "breath", "breath", "guard" },
    art = "a flowing green hooded cloak",
  },
  chain_mail = {
    name = "Chain Mail", slot = "armor", tier = 2, hp = 5,
    cards = { "guard", "guard", "guard", "bulwark" },
    art = "a silver chain mail shirt",
  },
  plate_armor = {
    name = "Plate Armor", slot = "armor", tier = 3, hp = 10,
    cards = { "bulwark", "bulwark", "guard", "guard" },
    art = "a heavy steel plate armor breastplate",
  },

  -- Shields
  old_buckler = {
    name = "Old Buckler", slot = "shield", tier = 0,
    cards = { "guard", "slash" },
    art = "a small round wooden buckler shield",
  },
  spiked_shield = {
    name = "Spiked Shield", slot = "shield", tier = 1,
    cards = { "bash", "bash", "guard" },
    art = "a round iron shield with spikes",
  },
  tower_shield = {
    name = "Tower Shield", slot = "shield", tier = 2, hp = 5,
    cards = { "bulwark", "guard", "guard" },
    art = "a tall rectangular tower shield with a lion emblem",
  },

  -- Charms
  fury_ring = {
    name = "Ring of Fury", slot = "charm", tier = 1,
    cards = { "fury" },
    art = "a gold ring with a glowing red gem",
  },
  blood_amulet = {
    name = "Blood Amulet", slot = "charm", tier = 2,
    cards = { "pact", "pact" },
    art = "an amulet with a dark red blood drop gem",
  },
  toxic_charm = {
    name = "Toxic Charm", slot = "charm", tier = 2,
    cards = { "cloud" },
    art = "a small green glass vial charm on a chain",
  },
  iron_heart = {
    name = "Iron Heart", slot = "charm", tier = 1, hp = 12,
    cards = {},
    art = "an iron heart shaped pendant",
  },
  thief_ring = {
    name = "Thief's Ring", slot = "charm", tier = 1,
    cards = { "disarm", "jab" },
    art = "a silver ring with a black stone",
  },

  -- Used up
  potion = {
    name = "Healing Potion", slot = "potion", tier = 1, heal = 15,
    art = "a round glass bottle with red potion",
  },
  big_potion = {
    name = "Great Potion", slot = "potion", tier = 2, heal = 30,
    art = "a big glass flask with glowing pink potion",
  },
  scroll = {
    name = "Scroll of Cards", slot = "scroll", tier = 1,
    art = "a rolled parchment scroll with a red wax seal",
  },

  -- What you start with
  start = { weapon = "rusty_sword", armor = "leather_vest", shield = "old_buckler" },
  start_bag = { "potion" },

  -- Loot: chance (in %) of each kind when something drops
  loot = { scroll = 35, potion = 35, gear = 30 },
}
