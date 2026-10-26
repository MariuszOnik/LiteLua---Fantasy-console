-- HeroesDS combat: the game's random stream.
--
-- The C runtime's LCG (x = x * 214013 + 2531011, bits 16..30), as Heroes IV rolls its
-- battles (MECHANICS.md 6.1). Works the same with 32-bit integers (LiteLua on the DS:
-- the product wraps) and 64-bit ones (a PC: the mask keeps the low 32 bits).

local rng = {}
rng.__index = rng

function rng.new(seed)
  return setmetatable({ state = seed & 0xFFFFFFFF }, rng)
end

-- Next value 0..32767
function rng:next()
  local s = (self.state * 214013 + 2531011) & 0xFFFFFFFF
  self.state = s
  return (s >> 16) & 0x7FFF
end

-- A roll in lo..hi, as the game does it: next() % (hi - lo + 1) + lo
function rng:roll(lo, hi)
  if hi > lo then return self:next() % (hi - lo + 1) + lo end
  return lo
end

-- The state as 8 hex digits, the same on 32 and 64 bits (for checksums)
function rng:hex()
  return string.format("%08x", self.state & 0xFFFFFFFF)
end

return rng
