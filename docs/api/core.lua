-- LiteLua API documentation: core (callbacks, screens, timing).
-- Format: see docs/api/README.md. Read by the on-DS editor (suggestions and
-- help) and by tools/apidoc.py (docs/API.md).
return {
  module = "core",
  title = "Core",
  summary = "Cart callbacks, screen constants and timing.",
  since = "P1",
  entries = {
    {
      name = "_init", kind = "callback",
      sig = "_init()",
      desc = "Called once after main.lua has been loaded, before the first frame.",
      example = [[
function _init()
  x, y = 128, 96
end]],
    },
    {
      name = "_update", kind = "callback",
      sig = "_update()",
      desc = "Called once per game frame (30 times per second), before drawing. "
          .. "Put game logic and input handling here.",
      example = [[
function _update()
  if btn("left") then x = x - 2 end
  if btn("right") then x = x + 2 end
end]],
    },
    {
      name = "_draw", kind = "callback",
      sig = "_draw(screen)",
      args = { { "screen", "integer", "TOP (0) or BOTTOM (1)" } },
      desc = "Called for each screen once per game frame, after _update: "
          .. "first with TOP, then with BOTTOM.",
      example = [[
function _draw(screen)
  if screen == TOP then
    -- draw the game
  else
    -- draw the map or the HUD
  end
end]],
    },
    {
      name = "TOP", kind = "const", type = "integer",
      sig = "TOP",
      desc = "Top screen id (0), passed to _draw.",
    },
    {
      name = "BOTTOM", kind = "const", type = "integer",
      sig = "BOTTOM",
      desc = "Bottom (touch) screen id (1), passed to _draw.",
    },
    {
      name = "micros", kind = "function",
      sig = "micros() -> integer",
      ret = { { "integer", "microseconds since boot" } },
      desc = "Time counter for measuring code speed. Wraps around after about "
          .. "128 seconds, so only use it for short intervals.",
      example = [[
local t = micros()
heavy_work()
print("took " .. (micros() - t) .. " us")]],
    },
  },
}
