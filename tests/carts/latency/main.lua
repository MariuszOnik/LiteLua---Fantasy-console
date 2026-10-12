-- LiteLua input latency test: both screens are black, white while A is held.
-- A script presses A in melonDS and times how long until the window turns
-- white (input -> picture). B: back to the list.

local held = false

function _update()
  held = btn("a")
  if btnp("b") then sys.exit() end
end

function _draw(surface)
  cls(held and 12 or 0)
end
