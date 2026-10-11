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
      args = { { "name", "string", "folder name in litelua/carts" } },
      desc = "Starts another cartridge when the current callback returns. "
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
  },
}
