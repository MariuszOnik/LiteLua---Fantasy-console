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
      name = "_quit", kind = "callback",
      sig = "_quit()",
      desc = "Called when the game is left without an error: L+R+B, L+R+START, "
          .. "sys.exit() or sys.run(). Use it to save the game. Drawing does "
          .. "nothing here and sys.run/sys.exit are gone. It may take at most "
          .. "1 second; an error or a longer run only goes to the log and the "
          .. "game is closed anyway. Not called after an error.",
      example = [[
function _quit()
  local f = io.open("save/progress.txt", "w")
  f:write(level)
  f:close()
end]],
    },
    {
      name = "_draw", kind = "callback",
      sig = "_draw(surface)",
      args = { { "surface", "integer", "TOP (0) or BOTTOM (1)" } },
      desc = "Called for each drawing surface once per game frame: first "
          .. "with TOP, then with BOTTOM. A surface is 256x192; on the DS "
          .. "TOP is the top screen and BOTTOM the touch screen. The surfaces "
          .. "are drawn in turns, one per screen refresh, so each _draw has "
          .. "about 16 ms. Each _draw starts with the default color, alpha, "
          .. "camera, clip, tint and background: nothing carries over from "
          .. "the other surface or the last frame.",
      example = [[
function _draw(surface)
  if surface == TOP then
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
      name = "print", kind = "function",
      sig = "print(...)",
      args = { { "...", "any", "values, separated by tabs" } },
      desc = "Writes the values to the log file litelua/log.txt on the SD "
          .. "card and to the console overlay (hold L+R, press X). It does not "
          .. "draw on the game screens; use text() for that. io.write also "
          .. "goes to the console overlay.",
      example = [[
print("score", score)]],
    },
    {
      name = "log", kind = "function",
      sig = "log(...)",
      args = { { "...", "any", "values, separated by tabs" } },
      desc = "Writes the values only to the log file litelua/log.txt on the "
          .. "SD card, with the time since start. The file is saved once per "
          .. "frame; logging every frame slows the game down.",
      example = [[
log("enemy spawned at", x, y)]],
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
