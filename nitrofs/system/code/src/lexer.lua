-- Syntax colors for the code editor: splits a line of Lua into colored
-- pieces. Long comments and strings ([[ ]], --[==[ ]==]) can span lines, so
-- each line starts in a state: "" (normal), "c<level>" (inside a long
-- comment) or "s<level>" (inside a long string).

local M = {}

M.colors = {
  text = 12, keyword = 3, builtin = 11, number = 4, string = 5,
  comment = 14, punct = 13,
}
local C = M.colors

local keywords = {}
for w in ([[and break do else elseif end false for function goto if in
  local nil not or repeat return then true until while]]):gmatch("%a+") do
  keywords[w] = true
end

-- Names of the LiteLua API and the Lua standard library
local builtins = {}
for w in ([[_init _update _draw _quit TOP BOTTOM print log micros
  cls color alpha camera clip stroke pset line rect rectfill circ circfill
  tri trifill image sub spr sprx sspr tint text textw tilemap btn btnp btnr touch
  sound sfx sfx_stop music music_volume sys require io os math string table
  utf8 coroutine pairs ipairs next type tostring tonumber select error
  assert pcall xpcall setmetatable getmetatable rawget rawset rawequal
  rawlen load loadfile dofile self _ENV _G]]):gmatch("[%w_]+") do
  builtins[w] = true
end

local find, sub, byte = string.find, string.sub, string.byte

-- Display column after string s drawn from column d: one column per
-- character (UTF-8), a tab goes to the next multiple of 4
local function width(d, s)
  if not find(s, "[\t\128-\255]") then return d + #s end
  for i = 1, #s do
    local c = byte(s, i)
    if c == 9 then d = d + 4 - d % 4
    elseif c < 0x80 or c >= 0xc0 then d = d + 1 end
  end
  return d
end
M.width = width

-- Tabs replaced by spaces up to the next multiple of 4 (from column d)
local function untab(d, s)
  if not find(s, "\t", 1, true) then return s end
  local out = {}
  for i = 1, #s do
    local ch = sub(s, i, i)
    if ch == "\t" then
      local n = 4 - d % 4
      out[#out + 1] = (" "):rep(n)
      d = d + n
    else
      out[#out + 1] = ch
      local c = byte(ch)
      if c < 0x80 or c >= 0xc0 then d = d + 1 end
    end
  end
  return table.concat(out)
end

-- Splits 'line' (starting in 'state') into a flat list of pieces
-- { col1, text1, color1, col2, ... } and returns it with the end state.
-- Text has tabs expanded; whitespace between pieces is left out.
function M.lex(line, state)
  local out, n = {}, 0
  local i, d, len = 1, 0, #line

  local function put(s, col)
    if s ~= "" then
      out[n + 1], out[n + 2], out[n + 3] = d, untab(d, s), col
      n = n + 3
      d = width(d, s)
    end
  end

  -- Inside a long comment or string from an earlier line
  if state ~= "" then
    local kind, level = state:sub(1, 1), tonumber(state:sub(2))
    local close = "]" .. ("="):rep(level) .. "]"
    local _, e = find(line, close, 1, true)
    local col = kind == "c" and C.comment or C.string
    if not e then
      put(line, col)
      return out, state
    end
    put(sub(line, 1, e), col)
    i = e + 1
  end

  while i <= len do
    local s, e = find(line, "^[ \t]+", i)
    if s then
      d = width(d, sub(line, s, e))
      i = e + 1
    else
      local c = sub(line, i, i)
      local open_s, open_e, eq
      if c == "-" and sub(line, i + 1, i + 1) == "-" then
        open_s, open_e, eq = find(line, "^%[(=*)%[", i + 2)
        if open_s then
          local close = "]" .. eq .. "]"
          local _, ce = find(line, close, open_e + 1, true)
          if not ce then
            put(sub(line, i), C.comment)
            return out, "c" .. #eq
          end
          put(sub(line, i, ce), C.comment)
          i = ce + 1
        else
          put(sub(line, i), C.comment)
          return out, ""
        end
      elseif c == "[" and find(line, "^%[=*%[", i) then
        open_s, open_e, eq = find(line, "^%[(=*)%[", i)
        local close = "]" .. eq .. "]"
        local _, ce = find(line, close, open_e + 1, true)
        if not ce then
          put(sub(line, i), C.string)
          return out, "s" .. #eq
        end
        put(sub(line, i, ce), C.string)
        i = ce + 1
      elseif c == '"' or c == "'" then
        local j = i + 1
        while j <= len do
          local ch = sub(line, j, j)
          if ch == "\\" then j = j + 2
          elseif ch == c then break
          else j = j + 1 end
        end
        put(sub(line, i, j), C.string)
        i = j + 1
      elseif find(c, "%d") or (c == "." and find(line, "^%.%d", i)) then
        local _, ne = find(line, "^[%w%.]*", i)
        -- Exponent sign: 1e-5, 0x1p+4
        while find(sub(line, ne, ne), "[eEpP]") and find(line, "^[%+%-]", ne + 1) do
          _, ne = find(line, "^[%w%.]*", ne + 2)
        end
        put(sub(line, i, ne), C.number)
        i = ne + 1
      elseif find(c, "[%a_]") then
        local _, we = find(line, "^[%w_]*", i)
        local w = sub(line, i, we)
        put(w, keywords[w] and C.keyword or builtins[w] and C.builtin or C.text)
        i = we + 1
      elseif byte(c) >= 0x80 then
        local _, ue = find(line, "^[\128-\255]+", i)
        put(sub(line, i, ue), C.text)
        i = ue + 1
      else
        put(c, C.punct)
        i = i + 1
      end
    end
  end
  return out, ""
end

-- End state only: most lines have no brackets and are not lexed at all
function M.end_state(line, state)
  if state == "" then
    if not find(line, "[", 1, true) then return "" end
  elseif not find(line, "]", 1, true) then
    return state
  end
  local _, st = M.lex(line, state)
  return st
end

return M
