-- Loaded with require("game.util") from src/
local M = {}

function M.source()
  return debug.getinfo(1, "S").source
end

function M.fail()
  error("error inside src/game/util.lua")
end

return M
