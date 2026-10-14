-- Help of this cart in the code editor (START): a manual page and the
-- functions of main.lua. Same format as docs/api/*.lua, plus 'text'.
return {
  title = "Map test",
  text = "A small platformer on two maps. D-pad: walk and climb ladders, "
      .. "A: jump, SELECT: the next level. Hold START for the pause menu: "
      .. "Save position / Load position keep the level and where the hero "
      .. "stands (save/pos.txt).",
  entries = {
    {
      name = "load_level", kind = "function",
      sig = "load_level(n)",
      args = { { "n", "integer", "index in LEVELS" } },
      desc = "Loads map n, counts its coins and puts the hero at the start.",
      example = [[
load_level(level % #LEVELS + 1)]],
    },
    {
      name = "respawn", kind = "function",
      sig = "respawn()",
      desc = "Puts the hero back at the start and counts a death.",
    },
  },
}
