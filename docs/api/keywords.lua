-- LiteLua API documentation: the Lua keywords (for the help of the editor:
-- START on a keyword opens its page). Format: see docs/api/README.md.
return {
  module = "keywords",
  title = "Lua keywords",
  summary = "The words of the Lua language itself: blocks, loops, conditions, "
         .. "values. Each page shows how the word is used.",
  since = "P10b",
  entries = {
    {
      name = "function", kind = "keyword",
      sig = "function name(args) ... end",
      desc = "Defines a function. 'local function' makes it local to the file "
          .. "(faster, and other files do not see it). A function is also a "
          .. "value: function(args) ... end can be stored or passed on. "
          .. "'...' as the last argument takes any number of arguments.",
      example = [[
local function add(a, b)
  return a + b
end
sys.menu("Save", function() save() end)]],
    },
    {
      name = "local", kind = "keyword",
      sig = "local name [= value]",
      desc = "Declares a variable visible only in the current block (file, "
          .. "function, loop). Without local a variable is global. Locals are "
          .. "faster; use them everywhere you can.",
      example = [[
local speed = 2
local x, y = 128, 96]],
    },
    {
      name = "if", kind = "keyword",
      sig = "if cond then ... [elseif cond then ...] [else ...] end",
      desc = "Runs a block when the condition is true. Only false and nil are "
          .. "false: 0 and \"\" are true.",
      example = [[
if lives == 0 then
  state = "over"
elseif lives < 3 then
  warn = true
else
  warn = false
end]],
    },
    {
      name = "then", kind = "keyword",
      sig = "if cond then ... end",
      desc = "Starts the block of an if or elseif.",
      example = [[
if btnp("a") then jump() end]],
    },
    {
      name = "elseif", kind = "keyword",
      sig = "elseif cond then ...",
      desc = "Another condition of an if, checked when the ones before were "
          .. "false.",
      example = [[
if hp > 50 then col = 6
elseif hp > 20 then col = 4
else col = 2 end]],
    },
    {
      name = "else", kind = "keyword",
      sig = "else ...",
      desc = "The block of an if that runs when no condition was true.",
      example = [[
if ok then print("ok") else print("no") end]],
    },
    {
      name = "end", kind = "keyword",
      sig = "end",
      desc = "Closes a block: function, if, for, while, do.",
      example = [[
for i = 1, 3 do
  print(i)
end]],
    },
    {
      name = "for", kind = "keyword",
      sig = "for i = a, b [, step] do ... end",
      desc = "A loop. Counting: i goes from a to b (step 1, or the given step, "
          .. "may be negative). Over a table: for k, v in pairs(t) or "
          .. "for i, v in ipairs(t). The loop variables are local.",
      example = [[
for i = 1, 10 do print(i) end
for i = 10, 1, -1 do print(i) end
for i, e in ipairs(enemies) do e:update() end]],
    },
    {
      name = "in", kind = "keyword",
      sig = "for k, v in iterator do ... end",
      desc = "Part of a for loop over an iterator (pairs, ipairs, "
          .. "string.gmatch...).",
      example = [[
for word in s:gmatch("%S+") do print(word) end]],
    },
    {
      name = "while", kind = "keyword",
      sig = "while cond do ... end",
      desc = "Repeats the block as long as the condition is true (checked "
          .. "before each round). A game should not wait in a loop: do one "
          .. "step per _update instead.",
      example = [[
local n = 1
while n < 100 do n = n * 2 end]],
    },
    {
      name = "do", kind = "keyword",
      sig = "do ... end",
      desc = "Starts the block of for and while; alone, do ... end makes a "
          .. "block for local variables.",
      example = [[
do
  local tmp = 5
  print(tmp)
end]],
    },
    {
      name = "repeat", kind = "keyword",
      sig = "repeat ... until cond",
      desc = "Repeats the block until the condition is true (checked after "
          .. "each round, so the block runs at least once).",
      example = [[
local x
repeat x = math.random(1, 10) until x ~= last]],
    },
    {
      name = "until", kind = "keyword",
      sig = "repeat ... until cond",
      desc = "Ends a repeat loop when its condition is true.",
      example = [[
repeat n = n - 1 until n <= 0]],
    },
    {
      name = "break", kind = "keyword",
      sig = "break",
      desc = "Leaves the innermost for, while or repeat loop at once.",
      example = [[
for i, e in ipairs(enemies) do
  if e.boss then found = e; break end
end]],
    },
    {
      name = "goto", kind = "keyword",
      sig = "goto label   ...   ::label::",
      desc = "Jumps to a label in the same function; mostly used as "
          .. "'continue' in loops.",
      example = [[
for i, e in ipairs(list) do
  if e.dead then goto continue end
  e:update()
  ::continue::
end]],
    },
    {
      name = "return", kind = "keyword",
      sig = "return [values]",
      desc = "Ends a function and gives back values (any number). At the end "
          .. "of a module file, return gives the module to require.",
      example = [[
local function minmax(a, b)
  if a < b then return a, b end
  return b, a
end]],
    },
    {
      name = "and", kind = "keyword",
      sig = "a and b",
      desc = "True if both are true. Gives a if a is false or nil, otherwise "
          .. "b. With or it makes a short if: cond and x or y.",
      example = [[
if alive and btnp("a") then jump() end
local col = hit and 2 or 12]],
    },
    {
      name = "or", kind = "keyword",
      sig = "a or b",
      desc = "True if one of them is true. Gives a if a is true, otherwise b, "
          .. "so 'x or default' fills in a missing value.",
      example = [[
local name = player.name or "nobody"]],
    },
    {
      name = "not", kind = "keyword",
      sig = "not a",
      desc = "true if a is false or nil, otherwise false.",
      example = [[
if not paused then update_game() end]],
    },
    {
      name = "nil", kind = "keyword",
      sig = "nil",
      desc = "No value: a variable that was never set, a missing table field. "
          .. "Setting a field to nil removes it.",
      example = [[
if enemy.target == nil then find_target(enemy) end
items.sword = nil]],
    },
    {
      name = "true", kind = "keyword",
      sig = "true",
      desc = "The boolean true.",
      example = [[
local running = true]],
    },
    {
      name = "false", kind = "keyword",
      sig = "false",
      desc = "The boolean false. Only false and nil count as false in "
          .. "conditions.",
      example = [[
p.ground = false]],
    },
  },
}
