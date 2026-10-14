-- LiteLua API documentation: sys (switching cartridges).
-- Format: see docs/api/README.md.
return {
  module = "sys",
  title = "System",
  summary = "Starting another cartridge, leaving the current one, the console.",
  since = "P3",
  entries = {
    {
      name = "sys.run", kind = "function",
      sig = "sys.run(name)",
      args = { { "name", "string", "folder or .lcart in litelua/carts" } },
      desc = "Starts another cartridge when the current callback returns. "
          .. "\"game\" finds the folder game or the file game.lcart. "
          .. "The current game is closed and all its memory is freed first. "
          .. "An error if the cartridge does not exist or its cart.lua is wrong. "
          .. "A name starting with @ runs a built-in system cartridge: "
          .. "sys.run(\"@code\") opens the code editor.",
      example = [[
if btnp("start") then sys.run("mygame2") end]],
    },
    {
      name = "sys.exit", kind = "function",
      sig = "sys.exit()",
      desc = "Closes the game when the current callback returns and goes back "
          .. "to the cartridge list.",
      example = [[
if btnp("select") then sys.exit() end]],
    },
    {
      name = "sys.menu", kind = "function",
      sig = "sys.menu(label, [fn])",
      args = {
        { "label", "string", "1-20 characters" },
        { "fn", "function", "called when the item is chosen; nil removes the item" },
      },
      desc = "Adds your own item to the pause menu (hold START), e.g. Save and "
          .. "Load: the game decides what to save. Up to 3 items, shown after "
          .. "Resume; the same label again replaces the function. Choosing it "
          .. "closes the menu, the game goes on and fn is called (before the "
          .. "next _update).",
      example = [[
sys.menu("Save", function()
  local f = io.open("save/game.txt", "w")
  f:write(level, " ", score, "\n")
  f:close()
end)]],
    },
    {
      name = "sys.info", kind = "function",
      sig = "sys.info() -> table",
      ret = { { "table", "console, cpu_mhz, ram_kb" } },
      desc = "The console the game runs on: console is \"DS\" or \"DSi\" "
          .. "(also a 3DS in DSi mode), cpu_mhz 67 or 134 (the DSi runs Lua "
          .. "about twice as fast), ram_kb 4096 or 16384. Games should run on "
          .. "a DS; use the DSi only for extras.",
      example = [[
local extra = sys.info().console == "DSi"
max_particles = extra and 400 or 150]],
    },
    {
      name = "sys.stats", kind = "function",
      sig = "sys.stats() -> table",
      ret = { { "table", "numbers of the last frame and memory use, see below" } },
      desc = "Performance numbers, also shown by the overlay (hold L+R, press "
          .. "Y). Fields: fps, cpu (% of the 33 ms frame), update_us, draw_us, "
          .. "draw_top_us, draw_bottom_us (microseconds), mem, mem_peak, "
          .. "mem_limit (Lua memory, bytes), ram_free (bytes), vram, vram_total "
          .. "(video memory, bytes), polys_top, polys_bottom, verts_top, "
          .. "verts_bottom (sent to the 3D engine for each screen).",
      example = [[
local s = sys.stats()
if s.cpu > 90 then log("slow frame", s.update_us, s.draw_us) end]],
    },
  },
}
