-- HeroesDS combat: number helpers shared by the rules.
--
-- The original rules compute a few things in 32-bit floats (the attack/defense ratio, path
-- costs). LiteLua on the DS is built with LUA_32BITS, so its floats are 32-bit already; Lua on
-- a PC uses 64-bit doubles. f32() rounds a double to the nearest float, which makes every
-- single + - * / sqrt give the same result as float arithmetic, so tests on a PC agree with
-- the console bit for bit. On the DS f32 does nothing.

local num = {}

-- 2^24 + 1 is not a float: it rounds to 2^24 when numbers are 32-bit
num.FLOAT32 = (16777217.0 == 16777216.0)

if num.FLOAT32 then
  num.f32 = function(x) return x end
else
  local pack, unpack = string.pack, string.unpack
  num.f32 = function(x) return (unpack("<f", pack("<f", x))) end
end
local f32 = num.f32

-- Float constants as the original's Float literals (0.8 is not exact in binary)
num.K05 = f32(0.05)
num.K08 = f32(0.8)
num.K085 = f32(0.85)

-- Round half away from zero (Swift's rounded()), returns an integer
function num.round(x)
  if x < 0 then return -num.round(-x) end
  local f = math.floor(x)
  if x - f >= 0.5 then f = f + 1 end
  return math.tointeger(f) or f
end

-- Truncate toward zero (Swift's Int(x)), returns an integer
function num.trunc(x)
  local f = x < 0 and math.ceil(x) or math.floor(x)
  return math.tointeger(f) or f
end

function num.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

return num
