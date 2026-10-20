-- The run is saved when the player enters a floor (the floor itself is
-- made again from the seed). Dying or winning deletes the save.
-- The file is Lua data ("return { ... }"), read back without running code
-- that could reach the API (empty environment).
local S = {}

local PATH = "save/run.lua"

local function write(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{"
    for k, x in pairs(v) do
      if type(k) == "string" then
        out[#out + 1] = k .. "="
      else
        out[#out + 1] = "[" .. k .. "]="
      end
      write(x, out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  else
    out[#out + 1] = tostring(v)
  end
end

function S.save(run)
  local out = { "return " }
  write(run, out)
  local f = io.open(PATH, "w")
  if not f then return false end
  f:write(table.concat(out))
  f:close()
  return true
end

-- The saved run, or nil
function S.load()
  local f = io.open(PATH, "r")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  local chunk = load(s, "save", "t", {})
  if not chunk then return nil end
  local ok, run = pcall(chunk)
  if ok and type(run) == "table" and run.seed and run.floor then return run end
end

function S.clear()
  pcall(os.remove, PATH)
end

return S
