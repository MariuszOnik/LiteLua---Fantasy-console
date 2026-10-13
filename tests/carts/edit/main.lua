-- Editor test (P11). A: error in src/util.lua (Y on the error screen goes
-- to the line). B: sys.exit(), back to the editor when started from it.
local util = require("util")
local n = 0

function _update()
  n = n + 1
  if btnp("a") then util.fail() end
  if btnp("b") then sys.exit() end
end

function _draw(s)
  cls(s == TOP and 8 or 1)
  if s == TOP then
    text("Editor test: frame " .. n, 4, 4, 12)
    text("A: error in src/util.lua", 4, 20, 13)
    text("B: exit (back to the editor)", 4, 30, 13)
  end
end
