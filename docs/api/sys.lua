-- LiteLua API documentation: sys (switching cartridges).
-- Format: see docs/api/README.md.
return {
  module = "sys",
  title = "System",
  summary = "Starting another cartridge and leaving the current one.",
  since = "P3",
  entries = {
    {
      name = "sys.run", kind = "function",
      sig = "sys.run(name)",
      args = { { "name", "string", "folder or .lcart in litelua/carts" } },
      desc = "Starts another cartridge when the current callback returns. "
          .. "\"game\" finds the folder game or the file game.lcart. "
          .. "The current game is closed and all its memory is freed first. "
          .. "An error if the cartridge does not exist or its cart.lua is wrong.",
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
