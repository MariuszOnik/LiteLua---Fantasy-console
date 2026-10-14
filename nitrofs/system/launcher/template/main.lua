-- $TITLE
-- Move the ball with the D-pad. Hold START for the pause menu.

local x, y = 128, 96

function _update()
  if btn("left") then x = x - 2 end
  if btn("right") then x = x + 2 end
  if btn("up") then y = y - 2 end
  if btn("down") then y = y + 2 end
end

function _draw(screen)
  if screen == TOP then
    cls(1)
    circfill(x, y, 8, 10)
  else
    cls(0)
    text("$TITLE", 4, 4, 12)
    text("Move the ball with the D-pad", 4, 20, 13)
  end
end
