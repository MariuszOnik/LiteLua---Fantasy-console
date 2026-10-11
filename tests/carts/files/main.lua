-- LiteLua P3 test cart: files, sandbox, require, save folder, sys.
-- Prints "ok"/"FAIL" lines to the console and the log.

local fails = 0
local function check(name, cond, extra)
  if not cond then fails = fails + 1 end
  print((cond and "ok   " or "FAIL ") .. name .. (extra and (" " .. tostring(extra)) or ""))
end

local function errors(f, ...)
  local ok, err = pcall(f, ...)
  return not ok, err
end

io.write('\27[2J')

-- require: src/, then lib/; chunk names are relative to the cart (D13)
local util = require("game.util")
check("require src/", util.source() == "@src/game/util.lua", util.source())
check("require lib/", require("helper").name == "cart lib helper")
local ok, err = pcall(require, "nothing.here")
check("require missing", not ok and err:find("src/nothing/here.lua", 1, true))
local _, e2 = pcall(util.fail)
check("error has file:line", e2:find("src/game/util.lua:9:", 1, true), e2)

-- Reading cart files
local f = io.open("data/hello.txt")
check("io.open data/", f and f:read("l") == "first line")
if f then f:close() end
local n = 0
for _ in io.lines("data/hello.txt") do n = n + 1 end
check("io.lines", n == 2)
check("./ path", io.open("./data//hello.txt") ~= nil)

-- Writing is only allowed in save/
check("write cart file", errors(io.open, "data/hello.txt", "w"))
check("'..' rejected", errors(io.open, "../bench/main.lua"))
check("absolute rejected", errors(io.open, "/litelua/log.txt"))
check("drive rejected", errors(io.open, "fat:/litelua/log.txt"))
check("missing -> nil", io.open("data/none.txt") == nil)

local w = assert(io.open("save/test.txt", "w"))
w:write("saved ", 42, "\n")
w:close()
local r = io.open("save/test.txt")
check("save/ write+read", r and r:read("a") == "saved 42\n")
if r then r:close() end
check("os.rename save/", os.rename("save/test.txt", "save/test2.txt"))
check("os.remove save/", os.remove("save/test2.txt"))
check("os.remove cart", errors(os.remove, "main.lua"))

-- Removed functions
check("no os.execute", os.execute == nil and os.exit == nil and os.getenv == nil)
check("no io.popen", io.popen == nil)
check("no binary chunks", load(string.dump(function() end)) == nil)
check("load text", load("return 1 + 1")() == 2)
check("dofile", errors(dofile, "data/none.lua"))
check("os.time", type(os.time()) == "number")

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
print("A: sys.run('bench')  B: sys.exit()")
print("X: error  L+R+B: list")

function _update()
  if btnp("a") then sys.run("bench") end
  if btnp("b") then sys.exit() end
  if btnp("x") then util.fail() end
end
