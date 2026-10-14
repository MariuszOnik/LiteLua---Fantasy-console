-- LiteLua API documentation: the Lua standard library (a selection).
-- Format: see docs/api/README.md.
return {
  module = "lua",
  title = "Lua library",
  summary = "The most used functions of the Lua 5.4 standard library. Numbers "
         .. "are 32-bit (integers and floats). math works in radians; "
         .. "LiteLua drawing uses degrees.",
  since = "P11a",
  entries = {
    -- Basic functions
    {
      name = "pairs", kind = "function",
      sig = "pairs(t) -> iterator",
      args = { { "t", "table", "table to walk" } },
      desc = "Walks all keys and values of a table, in no fixed order.",
      example = [[
for k, v in pairs(scores) do
  print(k, v)
end]],
    },
    {
      name = "ipairs", kind = "function",
      sig = "ipairs(t) -> iterator",
      args = { { "t", "table", "array" } },
      desc = "Walks t[1], t[2], ... in order until the first nil.",
      example = [[
for i, e in ipairs(enemies) do
  e.x = e.x + e.dx
end]],
    },
    {
      name = "type", kind = "function",
      sig = "type(v) -> string",
      args = { { "v", "any", "a value" } },
      ret = { { "string", "\"nil\", \"number\", \"string\", \"boolean\", \"table\", \"function\"..." } },
      desc = "The type of a value as a string.",
      example = [[
if type(x) == "number" then x = x + 1 end]],
    },
    {
      name = "tostring", kind = "function",
      sig = "tostring(v) -> string",
      args = { { "v", "any", "a value" } },
      desc = "Turns any value into a string (numbers, true, nil...).",
      example = [[
text("Lives: " .. tostring(lives), 2, 2)]],
    },
    {
      name = "tonumber", kind = "function",
      sig = "tonumber(s, [base]) -> number | nil",
      args = { { "s", "string", "text with a number" }, { "base", "integer", "2-36, default 10" } },
      desc = "Reads a number from a string; nil if it is not a number.",
      example = [[
local best = tonumber(f:read("l")) or 0]],
    },
    {
      name = "select", kind = "function",
      sig = "select(n, ...) -> ...",
      args = { { "n", "integer | \"#\"", "first value to return, or \"#\" for the count" } },
      desc = "Returns the arguments from the n-th on, or their number for \"#\".",
      example = [[
local function count(...) return select("#", ...) end]],
    },
    {
      name = "error", kind = "function",
      sig = "error(msg, [level])",
      args = { { "msg", "any", "message" }, { "level", "integer", "1 = this function, 2 = its caller" } },
      desc = "Stops with an error. Unless caught by pcall, the error screen "
          .. "shows it with the file and line.",
      example = [[
if not img then error("missing image hero") end]],
    },
    {
      name = "assert", kind = "function",
      sig = "assert(v, [msg]) -> v",
      args = { { "v", "any", "value to check" }, { "msg", "string", "message if v is false or nil" } },
      desc = "Error if v is false or nil, otherwise returns all its arguments.",
      example = [[
local f = assert(io.open("data/level1.txt"))]],
    },
    {
      name = "pcall", kind = "function",
      sig = "pcall(f, ...) -> ok, ...",
      args = { { "f", "function", "function to call" } },
      ret = { { "boolean", "true, then the results; or false and the error" } },
      desc = "Calls f and catches its errors instead of stopping the game.",
      example = [[
local ok, err = pcall(load_level, 3)
if not ok then print(err) end]],
    },
    {
      name = "setmetatable", kind = "function",
      sig = "setmetatable(t, mt) -> t",
      args = { { "t", "table", "table" }, { "mt", "table", "metatable (nil removes it)" } },
      desc = "Sets the metatable, e.g. __index for classes and objects.",
      example = [[
local Enemy = {}
Enemy.__index = Enemy
local e = setmetatable({ x = 0 }, Enemy)]],
    },
    {
      name = "getmetatable", kind = "function",
      sig = "getmetatable(t) -> table | nil",
      args = { { "t", "any", "value" } },
      desc = "The metatable of a value.",
    },
    {
      name = "next", kind = "function",
      sig = "next(t, [k]) -> k, v",
      args = { { "t", "table", "table" }, { "k", "any", "previous key" } },
      desc = "The next key and value after k. next(t) == nil means the table is empty.",
      example = [[
if next(bullets) == nil then print("no bullets") end]],
    },
    {
      name = "rawget", kind = "function",
      sig = "rawget(t, k) -> v",
      desc = "t[k] without calling __index.",
    },
    {
      name = "rawset", kind = "function",
      sig = "rawset(t, k, v) -> t",
      desc = "t[k] = v without calling __newindex.",
    },
    {
      name = "load", kind = "function",
      sig = "load(s, [name], [mode], [env]) -> f | nil, err",
      args = { { "s", "string", "Lua source" }, { "name", "string", "chunk name for errors" } },
      desc = "Compiles source text into a function without running it (only "
          .. "text, binary chunks are refused). Returns nil and the error for "
          .. "a syntax error.",
      example = [[
local f, err = load("return 1 + 2")
print(f())  -- 3]],
    },
    -- string
    {
      name = "string.format", kind = "function",
      sig = "string.format(fmt, ...) -> s",
      args = { { "fmt", "string", "%d integer, %5.2f float, %s string, %x hex, %% percent" } },
      desc = "Builds a string from a template. Also s:format(...).",
      example = [[
text(("%05d"):format(score), 2, 2)
text(string.format("%.1f fps", fps), 2, 12)]],
    },
    {
      name = "string.sub", kind = "function",
      sig = "string.sub(s, i, [j]) -> s",
      args = { { "s", "string", "text" }, { "i", "integer", "first byte (negative: from the end)" },
               { "j", "integer", "last byte, default -1" } },
      desc = "A part of a string, by bytes. Also s:sub(i, j).",
      example = [[
local first = name:sub(1, 1)]],
    },
    {
      name = "string.len", kind = "function",
      sig = "string.len(s) -> integer",
      desc = "Length in bytes, the same as #s. For characters: utf8.len.",
    },
    {
      name = "string.upper", kind = "function",
      sig = "string.upper(s) -> s",
      desc = "Upper case (ASCII). Also string.lower.",
      example = [[
text(name:upper(), 2, 2)]],
    },
    {
      name = "string.lower", kind = "function",
      sig = "string.lower(s) -> s",
      desc = "Lower case (ASCII).",
    },
    {
      name = "string.rep", kind = "function",
      sig = "string.rep(s, n, [sep]) -> s",
      desc = "s repeated n times.",
      example = [[
text(("*"):rep(lives), 2, 2)]],
    },
    {
      name = "string.find", kind = "function",
      sig = "string.find(s, pat, [init], [plain]) -> i, j",
      args = { { "pat", "string", "pattern (or plain text if plain is true)" } },
      desc = "Position of the first match, or nil.",
      example = [[
if line:find("^%-%-") then -- a comment
end]],
    },
    {
      name = "string.match", kind = "function",
      sig = "string.match(s, pat) -> captures",
      desc = "The captures of the first match of a pattern, or nil. %d digit, "
          .. "%a letter, %s space, %w letter or digit, . any, + one or more, "
          .. "* zero or more, () capture.",
      example = [[
local k, v = line:match("^(%w+)=(%d+)$")]],
    },
    {
      name = "string.gmatch", kind = "function",
      sig = "string.gmatch(s, pat) -> iterator",
      desc = "Walks all matches of a pattern.",
      example = [[
for word in s:gmatch("%S+") do print(word) end]],
    },
    {
      name = "string.gsub", kind = "function",
      sig = "string.gsub(s, pat, repl, [n]) -> s, count",
      desc = "Replaces matches with a string, a table or the result of a function.",
      example = [[
local clean = s:gsub("%s+", " ")]],
    },
    {
      name = "string.byte", kind = "function",
      sig = "string.byte(s, [i]) -> integer",
      desc = "Code of the byte at i (default 1).",
    },
    {
      name = "string.char", kind = "function",
      sig = "string.char(...) -> s",
      desc = "A string from byte codes.",
    },
    -- table
    {
      name = "table.insert", kind = "function",
      sig = "table.insert(t, [pos], v)",
      desc = "Adds v at the end of an array, or at pos (moving the rest up).",
      example = [[
table.insert(bullets, { x = px, y = py })]],
    },
    {
      name = "table.remove", kind = "function",
      sig = "table.remove(t, [pos]) -> v",
      desc = "Removes and returns the last element, or the one at pos. Walk "
          .. "backwards when removing in a loop.",
      example = [[
for i = #bullets, 1, -1 do
  if bullets[i].y < 0 then table.remove(bullets, i) end
end]],
    },
    {
      name = "table.concat", kind = "function",
      sig = "table.concat(t, [sep]) -> s",
      desc = "Joins an array of strings: much faster than .. in a loop.",
      example = [[
local s = table.concat(lines, "\n")]],
    },
    {
      name = "table.sort", kind = "function",
      sig = "table.sort(t, [less])",
      args = { { "less", "function", "less(a, b): true if a goes before b" } },
      desc = "Sorts an array in place.",
      example = [[
table.sort(scores, function(a, b) return a > b end)]],
    },
    {
      name = "table.unpack", kind = "function",
      sig = "table.unpack(t, [i], [j]) -> ...",
      desc = "Returns the elements of an array as separate values.",
      example = [[
local x, y = table.unpack(pos)]],
    },
    -- math
    {
      name = "math.floor", kind = "function",
      sig = "math.floor(x) -> integer",
      desc = "Rounds down. x // 1 does the same for floats.",
      example = [[
local tile = math.floor(px / 16)]],
    },
    {
      name = "math.ceil", kind = "function",
      sig = "math.ceil(x) -> integer",
      desc = "Rounds up.",
    },
    {
      name = "math.abs", kind = "function",
      sig = "math.abs(x) -> number",
      desc = "Absolute value.",
    },
    {
      name = "math.min", kind = "function",
      sig = "math.min(x, ...) -> number",
      desc = "The smallest argument. Also math.max.",
      example = [[
x = math.max(0, math.min(x, 255))  -- clamp]],
    },
    {
      name = "math.max", kind = "function",
      sig = "math.max(x, ...) -> number",
      desc = "The largest argument.",
    },
    {
      name = "math.sqrt", kind = "function",
      sig = "math.sqrt(x) -> number",
      desc = "Square root. Compare squared distances to skip it.",
      example = [[
local d = math.sqrt(dx * dx + dy * dy)]],
    },
    {
      name = "math.sin", kind = "function",
      sig = "math.sin(r) -> number",
      desc = "Sine of an angle in radians (math.rad converts degrees). Also "
          .. "math.cos.",
      example = [[
local y = 96 + math.sin(t / 20) * 40]],
    },
    {
      name = "math.cos", kind = "function",
      sig = "math.cos(r) -> number",
      desc = "Cosine of an angle in radians.",
    },
    {
      name = "math.atan", kind = "function",
      sig = "math.atan(y, [x]) -> number",
      desc = "Angle in radians of the vector (x, y), -pi..pi; math.deg "
          .. "converts to degrees for sprx.",
      example = [[
local a = math.deg(math.atan(ty - y, tx - x))]],
    },
    {
      name = "math.rad", kind = "function",
      sig = "math.rad(deg) -> number",
      desc = "Degrees to radians.",
    },
    {
      name = "math.deg", kind = "function",
      sig = "math.deg(r) -> number",
      desc = "Radians to degrees.",
    },
    {
      name = "math.random", kind = "function",
      sig = "math.random([m], [n]) -> number",
      desc = "random(): float 0..1; random(n): integer 1..n; random(m, n): m..n.",
      example = [[
local x = math.random(0, 255)]],
    },
    {
      name = "math.randomseed", kind = "function",
      sig = "math.randomseed([x])",
      desc = "Starts the random numbers from x (the same x gives the same "
          .. "numbers).",
    },
    {
      name = "math.pi", kind = "field", type = "number",
      sig = "math.pi",
      desc = "3.14159...",
    },
    {
      name = "math.huge", kind = "field", type = "number",
      sig = "math.huge",
      desc = "Infinity: bigger than any number.",
    },
    {
      name = "math.maxinteger", kind = "field", type = "integer",
      sig = "math.maxinteger",
      desc = "The largest integer: 2147483647 (32-bit).",
    },
    {
      name = "math.tointeger", kind = "function",
      sig = "math.tointeger(x) -> integer | nil",
      desc = "x as an integer if it has no fraction, otherwise nil.",
    },
    -- utf8
    {
      name = "utf8.len", kind = "function",
      sig = "utf8.len(s) -> integer",
      desc = "Number of characters (Polish letters take 2 bytes each).",
      example = [[
local w = utf8.len("zażółć") * 6]],
    },
    {
      name = "utf8.char", kind = "function",
      sig = "utf8.char(...) -> s",
      desc = "A string from character codes.",
    },
    -- os
    {
      name = "os.time", kind = "function",
      sig = "os.time([t]) -> integer",
      desc = "Seconds since 1970 by the console clock.",
    },
    {
      name = "os.clock", kind = "function",
      sig = "os.clock() -> number",
      desc = "Processor time in seconds; for short measurements micros() is better.",
    },
    {
      name = "os.date", kind = "function",
      sig = "os.date([fmt], [t]) -> string | table",
      desc = "Date and time as text (\"%H:%M\") or a table (\"*t\").",
      example = [[
text(os.date("%H:%M"), 220, 2)]],
    },
    -- coroutine
    {
      name = "coroutine.wrap", kind = "function",
      sig = "coroutine.wrap(f) -> function",
      desc = "A function that runs f until it yields; the next call goes on "
          .. "from there. Good for cut scenes and enemy scripts.",
      example = [[
local script = coroutine.wrap(function()
  for i = 1, 30 do x = x + 2; coroutine.yield() end
end)]],
    },
    {
      name = "coroutine.yield", kind = "function",
      sig = "coroutine.yield(...)",
      desc = "Pauses the running coroutine.",
    },
    {
      name = "coroutine.create", kind = "function",
      sig = "coroutine.create(f) -> co",
      desc = "A new coroutine; run it with coroutine.resume.",
    },
    {
      name = "coroutine.resume", kind = "function",
      sig = "coroutine.resume(co, ...) -> ok, ...",
      desc = "Runs a coroutine until it yields or ends.",
    },
    {
      name = "coroutine.status", kind = "function",
      sig = "coroutine.status(co) -> string",
      desc = "\"suspended\", \"running\", \"normal\" or \"dead\".",
    },
  },
}
