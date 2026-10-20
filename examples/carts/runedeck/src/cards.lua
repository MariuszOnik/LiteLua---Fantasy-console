-- Card pool. Pure data (no code): the game reads it with require, and
-- tools read it on the PC to generate the art (field "art" = image prompt).
--
-- Effects ("fx") run in order. Each is a list: { op, args... }
--   { "dmg", n }          deal n to the target (strength, weak, vulnerable apply)
--   { "dmg", n, times }   deal n, times times
--   { "dmg_all", n }      deal n to every enemy ({ "dmg_all", n, times })
--   { "pierce", n }       deal n, ignoring block
--   { "dmg_block" }       deal damage equal to your block
--   { "block", n }        gain n block
--   { "draw", n }         draw n cards
--   { "energy", n }       gain n energy
--   { "hp", n }           change your HP by n (negative = lose)
--   { "apply", status, n }      give the target n of a status
--   { "apply_all", status, n }  give every enemy n of a status
--   { "self", status, n }       give yourself n of a status
-- Statuses: "vuln" (takes 50% more), "weak" (deals 25% less),
--   "poison" (loses n HP each turn, then n-1), "str" (+n damage per hit)
-- "target": true when the card needs an enemy chosen with the stylus.
-- "exec": damage doubles when the target is at half HP or less.
return {
  slash = {
    name = "Slash", cost = 1, kind = "attack", target = true,
    text = "Deal 6.",
    fx = { { "dmg", 6 } },
    art = "a steel sword slashing diagonally with a bright arc of motion",
  },
  guard = {
    name = "Guard", cost = 1, kind = "skill",
    text = "Block 5.",
    fx = { { "block", 5 } },
    art = "a round wooden shield with iron rim, glowing blue",
  },
  crush = {
    name = "Crush", cost = 2, kind = "attack", target = true,
    text = "Deal 9. Vulnerable 2.",
    fx = { { "dmg", 9 }, { "apply", "vuln", 2 } },
    art = "a heavy iron war hammer smashing down, cracks and sparks",
  },
  cleave = {
    name = "Cleave", cost = 1, kind = "attack",
    text = "Deal 5 to all.",
    fx = { { "dmg_all", 5 } },
    art = "a huge double-bladed battle axe in a wide horizontal swing",
  },
  bash = {
    name = "Shield Bash", cost = 1, kind = "attack", target = true,
    text = "Deal your Block.",
    fx = { { "dmg_block" } },
    art = "a spiked shield ramming forward with motion lines",
  },
  breath = {
    name = "Second Wind", cost = 1, kind = "skill",
    text = "Block 7. Draw 1.",
    fx = { { "block", 7 }, { "draw", 1 } },
    art = "a swirl of white wind around a glowing green leaf",
  },
  venom = {
    name = "Venom Blade", cost = 1, kind = "attack", target = true,
    text = "Deal 3. Poison 4.",
    fx = { { "dmg", 3 }, { "apply", "poison", 4 } },
    art = "a curved dagger dripping bright green poison",
  },
  cloud = {
    name = "Toxic Cloud", cost = 2, kind = "skill",
    text = "Poison 5 to all.",
    fx = { { "apply_all", "poison", 5 } },
    art = "a bubbling purple and green poison cloud with a skull shape",
  },
  fury = {
    name = "Fury", cost = 1, kind = "power",
    text = "Strength +2.",
    fx = { { "self", "str", 2 } },
    art = "a clenched fist wrapped in red flames",
  },
  disarm = {
    name = "Disarm", cost = 0, kind = "skill", target = true,
    text = "Weak 2.",
    fx = { { "apply", "weak", 2 } },
    art = "a broken sword snapped in half, pieces flying",
  },
  jab = {
    name = "Quick Jab", cost = 0, kind = "attack", target = true,
    text = "Deal 3. Draw 1.",
    fx = { { "dmg", 3 }, { "draw", 1 } },
    art = "a small fast dagger thrust with yellow speed lines",
  },
  bulwark = {
    name = "Bulwark", cost = 2, kind = "skill",
    text = "Block 12.",
    fx = { { "block", 12 } },
    art = "a tall stone tower shield with a carved lion emblem",
  },
  flurry = {
    name = "Flurry", cost = 1, kind = "attack", target = true,
    text = "Deal 2 three times.",
    fx = { { "dmg", 2, 3 } },
    art = "three thrown knives flying in a fan",
  },
  pact = {
    name = "Blood Pact", cost = 0, kind = "skill",
    text = "Lose 3 HP. Energy +2.",
    fx = { { "hp", -3 }, { "energy", 2 } },
    art = "a glowing red rune drawn in blood on a dark stone",
  },
  execute = {
    name = "Execute", cost = 2, kind = "attack", target = true, exec = true,
    text = "Deal 8. Double if foe at half HP.",
    fx = { { "dmg", 8 } },
    art = "a black executioner axe with a glowing red edge",
  },
  parry = {
    name = "Parry", cost = 1, kind = "attack", target = true,
    text = "Block 4. Deal 4.",
    fx = { { "block", 4 }, { "dmg", 4 } },
    art = "a thin rapier blade deflecting sparks",
  },
  whirl = {
    name = "Whirlwind", cost = 2, kind = "attack",
    text = "Deal 4 to all, twice.",
    fx = { { "dmg_all", 4, 2 } },
    art = "a sword spinning in a blue whirlwind",
  },
  leech = {
    name = "Leech", cost = 1, kind = "attack", target = true,
    text = "Deal 5. Heal 3.",
    fx = { { "dmg", 5 }, { "hp", 3 } },
    art = "a vampire fang dripping a red drop",
  },
  focus = {
    name = "Focus", cost = 1, kind = "skill",
    text = "Draw 2.",
    fx = { { "draw", 2 } },
    art = "a glowing blue eye inside a triangle",
  },
  plague = {
    name = "Plague Strike", cost = 2, kind = "attack", target = true,
    text = "Deal 6. Poison 6.",
    fx = { { "dmg", 6 }, { "apply", "poison", 6 } },
    art = "a rusty mace covered in green plague mist",
  },
  shatter = {
    name = "Shatter", cost = 1, kind = "skill",
    text = "Vulnerable 2 to all.",
    fx = { { "apply_all", "vuln", 2 } },
    art = "a cracked crystal breaking into shards",
  },
  cry = {
    name = "Battle Cry", cost = 1, kind = "skill",
    text = "Strength +1. Block 4.",
    fx = { { "self", "str", 1 }, { "block", 4 } },
    art = "a war horn with sound waves",
  },
  smite = {
    name = "Smite", cost = 2, kind = "attack", target = true,
    text = "Deal 14.",
    fx = { { "dmg", 14 } },
    art = "a golden holy mace with a bright light burst",
  },
  pierce = {
    name = "Pierce", cost = 1, kind = "attack", target = true,
    text = "Deal 7, ignores Block.",
    fx = { { "pierce", 7 } },
    art = "a long steel spear tip thrusting forward",
  },
  fortify = {
    name = "Fortify", cost = 2, kind = "skill",
    text = "Block 9. Draw 1.",
    fx = { { "block", 9 }, { "draw", 1 } },
    art = "a stone wall with a glowing blue rune",
  },

  -- Deck at the start of a run
  starter = { "slash", "slash", "slash", "slash", "slash",
              "guard", "guard", "guard", "guard", "crush" },
}
