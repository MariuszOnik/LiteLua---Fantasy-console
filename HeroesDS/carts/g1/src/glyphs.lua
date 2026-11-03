-- HeroesDS G1: the stacks drawn from code, no image files. A bitmap is a few strings, one
-- character per pixel; it is turned once into runs (row, first column, length, character),
-- and each run is drawn with one rectfill, so a stack costs a few dozen calls.
-- . none  x side colour  X side light  o outline  w white  y gold  g grey  G dark grey
-- f skin  r red

local glyphs = {}

local BMP = {
  knight = {
    "...oo...",
    "..oggo..",
    "..oggo.y",
    ".oxxxxoy",
    ".oxXxxoy",
    "..oxxo..",
    "..o..o..",
    ".oo..oo." },
  archer = {
    "..ooo...",
    ".offo.o.",
    ".offo.og",
    "oxxxxo.g",
    ".oxxxxog",
    "..oxxo.g",
    "..o..oo.",
    ".oo..o.." },
  skeleton = {
    "..www...",
    ".wowow..",
    ".wwwww..",
    "..wow..g",
    ".wwxwwwg",
    "..www..g",
    "..w.w...",
    ".ww.ww.." },
  dragon = {
    "........oo..",
    "..o....oxxo.",
    ".oxo..oxXxyo",
    "oxXxooxxxxo.",
    ".oxxxxxxxo..",
    "..oxxxxxo...",
    "..ox.ox.....",
    ".oo.oo......" },
  griffin = {
    "oo......o.",
    "oXo....oyo",
    ".oXXo.oxxo",
    "..oXXxxxo.",
    "...oxxxxo.",
    "...oxxxo..",
    "...o.o.o..",
    "..oo.oo..." },
  imp = {
    "o....o..",
    "ofo.ofo.",
    ".offfo..",
    ".ofrfo.y",
    "..oxxo.y",
    ".oxxxxoy",
    "..o..o..",
    ".oo..oo." },
  hero = {
    ".y.y.y..",
    ".yyyyy..",
    ".offfo..",
    "oXxxxXo.",
    "oxXyXxo.",
    "oxxXxxo.",
    ".o...o..",
    "oo...oo." },
}

local COL = { o = 0, w = 12, y = 4, g = 13, G = 14, f = 3, r = 2 }

local function compile(rows)
  local w, h, runs = #rows[1], #rows, {}
  for r = 1, h do
    local row, q = rows[r], 1
    while q <= w do
      local ch = row:sub(q, q)
      if ch == "." then
        q = q + 1
      else
        local s = q
        while q <= w and row:sub(q, q) == ch do q = q + 1 end
        runs[#runs + 1] = { r - 1, s - 1, q - s, ch }
      end
    end
  end
  return { w = w, h = h, runs = runs }
end

local compiled = {}
for name, rows in pairs(BMP) do compiled[name] = compile(rows) end

-- Draws bitmap `name` with its bottom centre at (bx, by), k screen pixels per pixel,
-- mirrored when flip; c, cl: the side's colours; tint: one colour for all but the outline;
-- nothing below clip_y (sinking into the ground). Returns the top y.
function glyphs.draw(name, bx, by, k, flip, c, cl, tint, clip_y)
  local b = compiled[name]
  local x0 = (bx - b.w * k / 2) // 1
  local y0 = (by - b.h * k) // 1
  clip_y = clip_y or 1e9
  local runs = b.runs
  for i = 1, #runs do
    local run = runs[i]
    local y = y0 + run[1] * k
    if y + k <= clip_y then
      local ch = run[4]
      local col
      if ch == "x" then col = c elseif ch == "X" then col = cl else col = COL[ch] end
      if tint and ch ~= "o" then col = tint end
      local q = flip and (b.w - run[2] - run[3]) or run[2]
      rectfill(x0 + q * k, y, run[3] * k, k, col)
    end
  end
  return y0
end

-- Roguelike letters: a 3x5 font (bit 4 = left column), each dot 2k pixels, on a dark tile
local FONT = {
  H = { 5, 5, 7, 5, 5 }, K = { 5, 5, 6, 5, 5 }, A = { 2, 5, 7, 5, 5 }, G = { 3, 4, 5, 5, 3 },
  I = { 7, 2, 2, 2, 7 }, S = { 3, 4, 2, 1, 6 }, D = { 6, 5, 5, 5, 6 },
}

-- Draws letter ch with its bottom centre at (bx, by); returns the top y
function glyphs.letter(ch, bx, by, k, col, clip_y)
  local p = 2 * k
  local w, h = 3 * p, 5 * p
  local x, y = (bx - w / 2) // 1, (by - h) // 1
  if clip_y and y + h > clip_y then return y - k end
  rectfill(x - k, y - k, w + 2 * k, h + 2 * k, 0)
  local g = FONT[ch]
  for r = 1, 5 do
    local bits, q = g[r], 0
    while q < 3 do
      if bits & (4 >> q) ~= 0 then
        local s = q
        while q < 3 and bits & (4 >> q) ~= 0 do q = q + 1 end
        rectfill(x + s * p, y + (r - 1) * p, (q - s) * p, p, col)
      else
        q = q + 1
      end
    end
  end
  return y - k
end

return glyphs
