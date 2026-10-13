local M = {}

function M.fail()
  local t = nil
  return t.field -- error on purpose: line 5
end

return M
