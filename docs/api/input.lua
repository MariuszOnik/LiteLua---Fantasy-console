-- LiteLua API documentation: input (buttons, touch screen).
-- Format: see docs/api/README.md.
return {
  module = "input",
  title = "Input",
  summary = "Buttons and the touch screen. Sampled once per game frame.",
  since = "P1",
  entries = {
    {
      name = "btn", kind = "function",
      sig = "btn(name) -> boolean",
      args = { { "name", "string", "button name, see below" } },
      ret = { { "boolean", "true while the button is held" } },
      desc = "Button names: a b x y l r start select up down left right touch. "
          .. "\"touch\" means the screen is touched. An unknown name is an error.",
      example = [[
if btn("left") then x = x - 1 end
if btn("right") then x = x + 1 end]],
    },
    {
      name = "btnp", kind = "function",
      sig = "btnp(name) -> boolean",
      args = { { "name", "string", "button name" } },
      ret = { { "boolean", "true in the frame the button was pressed" } },
      desc = "Use for actions that should happen once per press (jump, menu). "
          .. "Buttons are read every screen refresh (60 times a second), so even "
          .. "a press shorter than a game frame is seen in the next frame.",
      example = [[
if btnp("a") then jump() end]],
    },
    {
      name = "btnr", kind = "function",
      sig = "btnr(name) -> boolean",
      args = { { "name", "string", "button name" } },
      ret = { { "boolean", "true in the frame the button was released" } },
      desc = "Use for actions on release, e.g. charged shots.",
      example = [[
if btn("b") then charge = charge + 1 end
if btnr("b") then shoot(charge); charge = 0 end]],
    },
    {
      name = "touch", kind = "function",
      sig = "touch() -> x, y | nil",
      ret = {
        { "integer", "x on the bottom screen (0-255)" },
        { "integer", "y on the bottom screen (0-191)" },
      },
      desc = "Returns the stylus position while the screen is touched, "
          .. "otherwise nil.",
      example = [[
local tx, ty = touch()
if tx then
  px, py = tx, ty
end]],
    },
    {
      name = "touchp", kind = "function",
      sig = "touchp() -> x, y | nil",
      since = "D59",
      ret = {
        { "integer", "x where the stylus came down (0-255)" },
        { "integer", "y where the stylus came down (0-191)" },
      },
      desc = "In the frame btnp(\"touch\") is true: the point where the stylus "
          .. "came down, otherwise nil. The stylus is read every screen refresh, "
          .. "so a tap shorter than a game frame still has its point (touch() "
          .. "may already be nil then). Use it with touchr() for taps that must "
          .. "not be lost.",
      example = [[
local px, py = touchp()
if px then press_x, press_y = px, py end
if btnr("touch") and press_x then
  click(press_x, press_y)   -- also for a very short tap
  press_x = nil
end]],
    },
    {
      name = "touchr", kind = "function",
      sig = "touchr() -> x, y | nil",
      since = "D59",
      ret = {
        { "integer", "x where the stylus last was (0-255)" },
        { "integer", "y where the stylus last was (0-191)" },
      },
      desc = "In the frame btnr(\"touch\") is true: the last point read before "
          .. "the stylus was lifted, otherwise nil.",
    },
  },
}
