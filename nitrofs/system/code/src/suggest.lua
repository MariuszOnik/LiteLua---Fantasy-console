-- Suggestions of the code editor (P11a): names that start with the word
-- before the cursor, from the API (docs/api, the same data as the help),
-- the Lua keywords and the names used in the code. After "x." or "x:" the
-- fields of x; inside the parentheses of a known function its signature
-- with the current argument.

local lexer = require("lexer")

local M = {}

local KEYWORDS = { "and", "break", "do", "else", "elseif", "end", "false",
  "for", "function", "goto", "if", "in", "local", "nil", "not", "or",
  "repeat", "return", "then", "true", "until", "while" }
local is_keyword = {}
for _, k in ipairs(KEYWORDS) do is_keyword[k] = true end

local MAX = 24          -- Candidates kept for the bar

local api = {}          -- Full name ("sys.run") -> entry
local globals = {}      -- Names without a dot: API, module tables, keywords
local api_fields = {}   -- "sys" -> { "exit", "info", "run", ... }
local methods, method_api = {}, {} -- "map:draw" -> "draw" (P8)
local code_names, code_fields = {}, {} -- From the code: name -> count
local recent, recent_n = {}, 0         -- Chosen names -> order of choice
local cart_names, cart_fields, cart_api = {}, {}, {} -- words.lua

function M.init(modules)
  local seen = {}
  local function global(n)
    if not seen[n] then seen[n] = true; globals[#globals + 1] = n end
  end
  for _, k in ipairs(KEYWORDS) do global(k) end
  for _, m in ipairs(modules) do
    for _, e in ipairs(m.entries) do
      api[e.name] = e
      local base, field = e.name:match("^(.*)%.([%w_]+)$")
      local method = e.name:match("^[%w_]+:([%w_]+)$")
      if method then
        -- "map:draw": suggested after any "x:" (the type of x is not known)
        methods[#methods + 1] = method
        method_api[method] = e
      elseif base then
        local t = api_fields[base]
        if not t then t = {}; api_fields[base] = t end
        t[#t + 1] = field
        global(e.name:match("^[%w_]+"))
      else
        global(e.name)
      end
    end
  end
end

function M.entry(name) return api[name] or cart_api[name] end

-- Words of the cart (words.lua, D46): "name" or { name =, sig =, desc = }
function M.set_words(list)
  cart_names, cart_fields, cart_api = {}, {}, {}
  for _, w in ipairs(list) do
    local e = type(w) == "table" and w or { name = w }
    local n = e.name
    if type(n) == "string" and n:match("^[%a_][%w_%.]*$") then
      cart_api[n] = e
      local base, field = n:match("^(.*)%.([%w_]+)$")
      if base then
        local t = cart_fields[base]
        if not t then t = {}; cart_fields[base] = t end
        t[#t + 1] = field
        cart_names[#cart_names + 1] = n:match("^[%w_]+")
      else
        cart_names[#cart_names + 1] = n
      end
    end
  end
end

-- Names and fields used in the code of buffer b (counted). Cheap enough to
-- run when the cursor leaves an edited line, not after every key.
function M.scan(b)
  local names, fields = {}, {}
  for _, line in ipairs(b.lines) do
    for w in line:gmatch("[%a_][%w_]*") do
      if #w > 1 and not is_keyword[w] then names[w] = (names[w] or 0) + 1 end
    end
    for base, f in line:gmatch("([%a_][%w_]*)[%.:]([%a_][%w_]*)") do
      local t = fields[base]
      if not t then t = {}; fields[base] = t end
      t[f] = (t[f] or 0) + 1
    end
  end
  code_names, code_fields = names, fields
end

function M.chosen(name)
  recent_n = recent_n + 1
  recent[name] = recent_n
end

-- True if the cursor is inside a string or a comment
local function in_text(b)
  local p = b:pieces(b.cy)
  local d = b:dcol(b.cy, b.cx)
  local C = lexer.colors
  -- The character before the cursor (column d - 1) decides
  for i = 1, #p, 3 do
    local d1 = p[i]
    if d1 > d - 1 then break end
    local col = p[i + 2]
    if (col == C.string or col == C.comment)
       and d - 1 < lexer.width(d1, p[i + 1]) then
      return true
    end
  end
  return false
end

-- Candidates for the word before the cursor: list of names and the length
-- of the prefix they replace, or nil
function M.query(b)
  local line = b.lines[b.cy]:sub(1, b.cx)
  if in_text(b) then return nil end

  local found, seen = {}, {}
  local function add(n, pre)
    if #n > #pre and n:sub(1, #pre) == pre and not seen[n] then
      seen[n] = true
      found[#found + 1] = n
    end
  end

  local base, sep, pre = line:match("([%a_][%w_%.]*)([%.:])([%w_]*)$")
  if base then
    for _, f in ipairs(api_fields[base] or {}) do add(f, pre) end
    if sep == ":" then
      for _, f in ipairs(methods) do add(f, pre) end
    end
    for _, f in ipairs(cart_fields[base] or {}) do add(f, pre) end
    local last = base:match("[%w_]+$")
    for f in pairs(code_fields[last] or {}) do add(f, pre) end
    if #found == 0 and pre == "" then return nil end
  else
    pre = line:match("[%a_][%w_]*$")
    if not pre then return nil end
    for _, n in ipairs(cart_names) do add(n, pre) end
    for _, n in ipairs(globals) do add(n, pre) end
    for n in pairs(code_names) do add(n, pre) end
  end
  if #found == 0 then return nil end

  local fcount = base and (code_fields[base:match("[%w_]+$")] or {}) or code_names
  table.sort(found, function(x, y)
    local rx, ry = recent[x] or 0, recent[y] or 0
    if rx ~= ry then return rx > ry end
    local cx, cy = fcount[x] or 0, fcount[y] or 0
    if cx ~= cy then return cx > cy end
    if #x ~= #y then return #x < #y end
    return x < y
  end)
  for i = MAX + 1, #found do found[i] = nil end
  return found, #pre, base
end

-- Inside the parentheses of a known function: its signature and the number
-- of the current argument
function M.signature(b)
  local line = b.lines[b.cy]
  local depth, arg = 0, 1
  for i = b.cx, 1, -1 do
    local c = line:sub(i, i)
    if c == ")" then
      depth = depth + 1
    elseif c == "(" then
      if depth == 0 then
        local name = line:sub(1, i - 1):match("([%a_][%w_%.:]*)%s*$")
        local method = name and name:match(":([%w_]+)$")
        local e = name and (api[name] or cart_api[name] or (method and method_api[method]))
        if e and e.sig then return e.sig, arg end
        return nil
      end
      depth = depth - 1
    elseif c == "," and depth == 0 then
      arg = arg + 1
    end
  end
  return nil
end

-- Column range of argument 'arg' in a signature ("rect(x, y, w, h, [col])")
function M.arg_range(sig, arg)
  local open = sig:find("(", 1, true)
  if not open then return nil end
  local depth, n, start = 0, 1, open + 1
  for i = open + 1, #sig do
    local c = sig:sub(i, i)
    if c == "[" or c == "(" then depth = depth + 1
    elseif (c == "]" or c == ")") and depth > 0 then depth = depth - 1
    elseif (c == "," and depth == 0) or (c == ")" and depth == 0) then
      if n == arg then return start, i - 1 end
      n, start = n + 1, i + 2
      if c == ")" then break end
    end
  end
  if n == arg then return start, #sig end
  return nil
end

return M
