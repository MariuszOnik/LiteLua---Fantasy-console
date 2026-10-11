-- LiteLua P3 test cart: files, sandbox, require, save folder, sys.
-- Shows "ok"/"FAIL" lines on the bottom screen and writes them to the log.

-- Result lines: shown on the bottom screen and written to the log
local out = {}
local function say(s)
  out[#out + 1] = s
  print(s)
end
local function draw_out(y)
  for i, l in ipairs(out) do
    text(l, 0, (y or 0) + (i - 1) * 8, l:sub(1, 4) == "FAIL" and 2 or 12)
  end
end

local fails = 0
local function check(name, cond, extra)
  if not cond then fails = fails + 1 end
  say((cond and "ok   " or "FAIL ") .. name .. (extra and (" " .. tostring(extra)) or ""))
end

local function errors(f, ...)
  local ok, err = pcall(f, ...)
  return not ok, err
end

-- require: src/, then lib/; chunk names are relative to the cart (D13)
local util = require("game.util")
check("require src/", util.source() == "@src/game/util.lua", util.source())
check("require lib/", require("helper").name == "cart lib helper")
local ok, err = pcall(require, "nothing.here")
check("require missing", not ok and err:find("src/nothing/here.lua", 1, true)
  and err:find("rom/lib/nothing/here.lua", 1, true))
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
local s = io.open("data/hello.txt")
check("seek", s and s:seek("end") > 0 and s:seek("set") == 0 and s:read("l") == "first line")
if s then s:close() end

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
check("sys.run missing", errors(sys.run, "no-such-cart"))

say(fails == 0 and "ALL OK" or (fails .. " FAILED"))
say("A: sys.run('bench')  B: sys.exit()")
say("Down: error  L+R+B: list")

function _update()
  if btnp("a") then sys.run("bench") end
  if btnp("b") then sys.exit() end
  if btnp("down") then util.fail() end
end

function _draw(screen)
  if screen == BOTTOM then
    cls(0)
    draw_out()
  else
    cls(1)
    text("Files and sandbox test", 4, 4, 12)
    text("results on the bottom screen", 4, 14, 13)
  end
end
