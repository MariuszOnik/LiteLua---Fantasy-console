-- LiteLua VM benchmark (P2, D19). Runs as the cart "bench".
-- Results go to the bottom screen and to litelua/log.txt.
-- The first two tests are the P0 baseline from D3 (200k iterations).

local N = 200000

local function add(a, b) return a + b end

local tests = {
  { "int %", function()
      local s = 0
      for i = 1, N do s = s + i % 7 end
      return s
    end },
  { "float *", function()
      local f = 0.0
      for i = 1, N do f = f + i * 0.5 end
      return f
    end },
  { "int //", function()
      local s = 0
      for i = 1, N do s = s + i // 7 end
      return s
    end },
  { "call", function()
      local s = 0
      for i = 1, N do s = add(s, i) end
      return s
    end },
  { "field", function()
      local p = { x = 0, vx = 1 }
      for i = 1, N do p.x = p.x + p.vx end
      return p.x
    end },
  { "array", function()
      local t = {}
      for i = 1, 256 do t[i] = i end
      local s = 0
      for i = 1, N do s = s + t[(i & 255) + 1] end
      return s
    end },
  { "concat", function()
      local s
      for i = 1, N // 10 do s = "n" .. i end
      return s
    end },
  { "sqrt", function()
      local sqrt, s = math.sqrt, 0.0
      for i = 1, N // 10 do s = s + sqrt(i) end
      return s
    end },
}

-- Integer // and % must floor (Lua semantics) also with negative operands.
-- Operands come from a table so the compiler cannot fold the constants.
local function check_div()
  local cases = {
    { 7, 2, 3, 1 }, { -7, 2, -4, 1 }, { 7, -2, -4, -1 }, { -7, -2, 3, -1 },
    { 6, 3, 2, 0 }, { -6, 3, -2, 0 }, { 5, -1, -5, 0 },
    { math.mininteger, -1, math.mininteger, 0 },
    { math.maxinteger, 10, 214748364, 7 },
  }
  for _, c in ipairs(cases) do
    local a, b = c[1], c[2]
    if a // b ~= c[3] or a % b ~= c[4] then
      error(("%d // %d = %d, %% = %d; expected %d, %d")
        :format(a, b, a // b, a % b, c[3], c[4]))
    end
  end
  assert(not pcall(function() return cases[1][1] // 0 end))
  assert(not pcall(function() return cases[1][1] % 0 end))
end

io.write('\27[2J')
check_div()
print("int // and %: ok")
print("LiteLua VM benchmark, N=" .. N)
local total = 0
for _, t in ipairs(tests) do
  collectgarbage()
  local t0 = micros()
  t[2]()
  local us = micros() - t0
  total = total + us
  print(("%-8s %6d.%d ms"):format(t[1], us // 1000, us % 1000 // 100))
end
print(("total    %6d ms"):format(total // 1000))
print(("mem: %d KB"):format(collectgarbage("count") // 1))
print("done")
