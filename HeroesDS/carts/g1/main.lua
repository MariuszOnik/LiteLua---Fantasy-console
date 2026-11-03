-- HeroesDS G1: a test battle with no sprites and no game data (the Lua version of
-- HeroesDS/glyphtest/index.html). The field is the C4 one (combat/grid.lua's scene at 3/16,
-- view.lua's magnifier), stacks are 8x8 bitmaps from src/glyphs.lua or letters, spells
-- are lines and circles. The battle rules are a stand-in, not combat/.
--
-- Touch the ground or an enemy to choose (a marker shows it), touch it again or A to do
-- it, B cancels (B with nothing chosen: wait). X look, Y magnifier, L/R spell, SELECT auto.
-- The top screen shows what the bottom one costs (sys.stats: time and polygons).

local glyphs = require("glyphs")

-- ------------------------------------------------------------------ geometry

local N, SCENE_W, SCENE_H, BASE = 102, 1180, 1024, 3 / 16
local OX = (256 - SCENE_W * BASE // 1) // 2   -- 17: black bars at the sides
local GROUND = 0x4b692f
local zoom, K, camx, camy = 1, BASE, 0, 0

local function grid_screen(x, y) return (y - x) * 16 + 590, (x + y) * 8 + 512 - 8 * N end

local function to_screen(wx, wy)
  local sx, sy = grid_screen(wx, wy)
  return OX + (sx - camx) * K, (sy - camy) * K
end

local function to_world(px, py)
  local sx, sy = camx + (px - OX) / K, camy + py / K
  local u, v = (sx - 590) / 16, (sy - 512 + 8 * N) / 8
  return (v - u) / 2, (v + u) / 2
end

-- u = y - x across the screen, v = x + y down it
local function from_uv(u, v) return (v - u) / 2, (v + u) / 2 end

local function clamp_world(x, y)
  local u = math.max(-34, math.min(34, y - x))
  local v = math.max(44, math.min(160, x + y))
  return from_uv(u, v)
end

local function set_camera(z, wx, wy)
  zoom, K = z, BASE * z
  if z == 1 then camx, camy = 0, 0; return end
  local fx, fy = grid_screen(wx, wy)
  camx = fx - (128 - OX) / K
  camy = fy - 96 / K
  camx = math.max(-OX / K, math.min(camx, SCENE_W - (256 - OX) / K))
  camy = math.max(0, math.min(camy, SCENE_H - 192 / K))
end

-- ------------------------------------------------------------------ sound

local S = {}
local SFX = { "step", "sword", "arrow", "thunk", "die", "fire", "boom", "bolt", "ice",
              "select", "turn" }
local function play(name, vol, pitch)
  if S[name] then sfx(S[name], vol or 1, 0, pitch or 1) end
end

-- ------------------------------------------------------------------ battle data

local TYPES = {
  hero     = { name = "Bohater",  ch = "H", hp = 60,  atk = 9,  speed = 16, size = 3 },
  knight   = { name = "Rycerz",   ch = "K", hp = 30,  atk = 6,  speed = 14, size = 3 },
  archer   = { name = "Łucznik",  ch = "A", hp = 10,  atk = 3,  speed = 10, size = 3, ranged = true },
  griffin  = { name = "Gryf",     ch = "G", hp = 30,  atk = 7,  speed = 24, size = 3 },
  imp      = { name = "Chochlik", ch = "I", hp = 4,   atk = 2,  speed = 18, size = 3 },
  skeleton = { name = "Szkielet", ch = "S", hp = 6,   atk = 2,  speed = 12, size = 3 },
  dragon   = { name = "Smok",     ch = "D", hp = 200, atk = 38, speed = 26, size = 5 },
}
local SIDE = { [0] = { c = 9, l = 10, name = "Niebiescy" }, [1] = { c = 2, l = 3, name = "Czerwoni" } }
local SPELLS = { "brak", "ogien", "blyskawica", "lod" }
local SPELL_NAME = { brak = "brak", ogien = "ogień", blyskawica = "błyskawica", lod = "lód" }

local units, order, fxs, logs = {}, {}, {}, {}
local deco, grain = {}, {}
local turn_i, round, active, task, waiting, over = 0, 1, nil, nil, false, nil
local frame, mode, spell, auto = 0, "bmp", 1, false
local pending = nil          -- the chosen action, waiting for a second touch or A

local function add_log(t)
  if utf8.len(t) and utf8.len(t) > 41 then t = t:sub(1, utf8.offset(t, 42) - 1) end
  logs[#logs + 1] = t
  if #logs > 6 then table.remove(logs, 1) end
end

local function alive(u) return u.count > 0 end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function unit_screen(u) return to_screen(u.x, u.y) end

local function make_deco()
  deco, grain = {}, {}
  for _ = 1, 18 do
    local x, y = from_uv(-14 + math.random() * 28, 50 + math.random() * 105)
    deco[#deco + 1] = { x = x, y = y, tree = math.random() < 0.6 }
  end
  table.sort(deco, function(a, b) return a.x + a.y < b.x + b.y end)
  for _ = 1, 160 do
    grain[#grain + 1] = { math.random() * SCENE_W, math.random() * SCENE_H,
                          math.random() < 0.7 and 6 or 15 }
  end
end

local next_turn

local function new_battle()
  math.randomseed(micros())
  make_deco()
  set_camera(zoom, 51, 51)
  local armies = {
    { { "hero", 1 }, { "knight", 14 }, { "archer", 22 }, { "griffin", 8 }, { "knight", 10 },
      { "archer", 18 }, { "imp", 30 } },
    { { "dragon", 1 }, { "skeleton", 40 }, { "archer", 16 }, { "imp", 25 }, { "griffin", 6 },
      { "skeleton", 35 } },
  }
  units = {}
  local id = 0
  for side = 0, 1 do
    local army = armies[side + 1]
    for i, a in ipairs(army) do
      local T = TYPES[a[1]]
      local x, y = from_uv(side == 1 and 27 or -27, 58 + (i - 1) * (96 / (#army - 1)))
      id = id + 1
      units[#units + 1] = { id = id, type = a[1], side = side, count = a[2], hp = T.hp,
        x = x, y = y, size = T.size, face = side == 1 and -1 or 1, hop = 0, ox = 0, oy = 0,
        flash = 0, frozen = 0, dying = 0 }
    end
  end
  order = {}
  for _, u in ipairs(units) do order[#order + 1] = u end
  table.sort(order, function(a, b)
    local sa, sb = TYPES[a.type].speed, TYPES[b.type].speed
    if sa ~= sb then return sa > sb end
    return a.id < b.id
  end)
  fxs, logs = {}, {}
  turn_i, round, over, task, waiting, pending = 0, 1, nil, nil, false, nil
  add_log("Nowa bitwa!")
  music("battle")
  next_turn()
end

-- ------------------------------------------------------------------ actions
-- Each action runs in a coroutine; one yield = one frame (30 per second).

local function wait(n) for _ = 1, n do coroutine.yield() end end

local function walk(u, tx, ty)
  tx, ty = clamp_world(tx, ty)
  local fx0, fy0 = u.x, u.y
  local d = math.sqrt((tx - fx0) ^ 2 + (ty - fy0) ^ 2)
  if d < 0.5 then return end
  local ax = to_screen(fx0, fy0)
  local bx = to_screen(tx, ty)
  if math.abs(bx - ax) > 1 then u.face = bx > ax and 1 or -1 end
  local n = math.max(5, math.floor(d * 0.8))
  local hops = math.max(1, math.floor(d / 4 + 0.5))
  local last = 0
  for i = 1, n do
    u.x, u.y = fx0 + (tx - fx0) * i / n, fy0 + (ty - fy0) * i / n
    local h = (i / n) * hops
    u.hop = math.abs(math.sin(h * math.pi)) * 3
    if h // 1 > last then last = h // 1; play("step", 0.35) end
    coroutine.yield()
  end
  u.hop = 0
end

local function damage(a, t, amount)
  amount = math.max(1, math.floor(amount + 0.5))
  local T = TYPES[t.type]
  local pool = (t.count - 1) * T.hp + t.hp - amount
  local before = t.count
  if pool <= 0 then
    t.count, t.hp, t.dying = 0, 0, 12
    play("die")
  else
    t.count = math.ceil(pool / T.hp)
    t.hp = pool - (t.count - 1) * T.hp
  end
  t.flash = 4
  local cx, cy = unit_screen(t)
  fxs[#fxs + 1] = { k = "num", x = cx, y = cy - 12 * zoom, t = 0, text = "-" .. amount }
  add_log((a and TYPES[a.type].name .. " > " or "") .. T.name .. ": " .. amount
          .. " (-" .. (before - t.count) .. ")")
end

local function hit_power(a) return a.count * TYPES[a.type].atk * (0.8 + math.random() * 0.4) end

local function lunge(a, t)
  local ax, ay = unit_screen(a)
  local tx, ty = unit_screen(t)
  local l = math.sqrt((tx - ax) ^ 2 + (ty - ay) ^ 2)
  if l == 0 then l = 1 end
  local dx, dy = (tx - ax) / l, (ty - ay) / l
  if math.abs(tx - ax) > 1 then a.face = tx > ax and 1 or -1 end
  for i = 0, 8 do
    local p = math.sin(i / 8 * math.pi) * 5 * zoom
    a.ox, a.oy = dx * p, dy * p
    if i == 4 then play("sword"); damage(a, t, hit_power(a)) end
    coroutine.yield()
  end
  a.ox, a.oy = 0, 0
  wait(5)
end

local function shoot(a, t)
  local ax = unit_screen(a)
  local tx = unit_screen(t)
  if math.abs(tx - ax) > 1 then a.face = tx > ax and 1 or -1 end
  local n = math.max(6, math.floor(dist(a, t) * 0.4))
  local f = { k = "arrow", a = a, t = t, i = 0, n = n }
  fxs[#fxs + 1] = f
  play("arrow")
  while f.i < n do f.i = f.i + 1; coroutine.yield() end
  f.done = true
  play("thunk")
  damage(a, t, hit_power(a) * 0.7)
  wait(5)
end

local function melee(a, t)
  local reach = (a.size + t.size) / 2 + 0.5
  local d = dist(a, t)
  if d > reach then
    local step = math.min(d - reach, TYPES[a.type].speed)
    walk(a, a.x + (t.x - a.x) / d * step, a.y + (t.y - a.y) / d * step)
    if dist(a, t) > reach + 0.6 then add_log(TYPES[a.type].name .. " idzie"); return end
  end
  lunge(a, t)
end

local function cast(a, t, kind)
  add_log(TYPES[a.type].name .. " czaruje: " .. SPELL_NAME[kind])
  local ax, ay = unit_screen(a)
  local tx, ty = unit_screen(t)
  if kind == "ogien" then
    local f = { k = "fireball", x = ax, y = ay - 8 * zoom, trail = {} }
    fxs[#fxs + 1] = f
    play("fire")
    local n = 11
    for i = 1, n do
      f.x = ax + (tx - ax) * i / n
      f.y = (ay - 8 * zoom) + (ty - ay) * i / n - math.sin(i / n * math.pi) * 14
      f.trail[#f.trail + 1] = { f.x, f.y, 6 }
      coroutine.yield()
    end
    f.done = true
    fxs[#fxs + 1] = { k = "boom", x = tx, y = ty - 4 * zoom, t = 0 }
    play("boom")
    damage(nil, t, 70 + math.random() * 30)
    wait(10)
  elseif kind == "blyskawica" then
    local f = { k = "bolt", x = tx, y = ty - 6 * zoom, t = 0 }
    fxs[#fxs + 1] = f
    play("bolt")
    for i = 0, 6 do
      f.t = i
      if i == 2 then damage(nil, t, 90 + math.random() * 40) end
      coroutine.yield()
    end
    f.done = true
    wait(4)
  else
    local f = { k = "ice", x = tx, y = ty - 4 * zoom, t = 0 }
    fxs[#fxs + 1] = f
    play("ice")
    for i = 0, 9 do f.t = i; coroutine.yield() end
    f.done = true
    t.frozen = 20
    damage(nil, t, 45 + math.random() * 20)
    wait(8)
  end
end

local function ai_turn(u)
  wait(6)
  local foes = {}
  for _, e in ipairs(units) do if e.side ~= u.side and alive(e) then foes[#foes + 1] = e end end
  if #foes == 0 then return end
  local T, t = TYPES[u.type], foes[1]
  for _, e in ipairs(foes) do
    if T.ranged then
      if e.count * TYPES[e.type].atk > t.count * TYPES[t.type].atk then t = e end
    elseif dist(u, e) < dist(u, t) then t = e end
  end
  if T.ranged then shoot(u, t) else melee(u, t) end
end

local function start(fn, ...)
  local args = table.pack(...)
  task = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
  waiting, pending = false, nil
end

next_turn = function()
  for s = 0, 1 do
    local any = false
    for _, u in ipairs(units) do if u.side == s and alive(u) then any = true end end
    if not any then
      over = s == 0 and "PRZEGRANA" or "WYGRANA"
      add_log(over .. "!")
      music(s == 0 and "defeat" or "victory", false)
      active, waiting = nil, false
      return
    end
  end
  repeat
    turn_i = turn_i + 1
    if turn_i > #order then turn_i, round = 1, round + 1 end
  until alive(order[turn_i])
  active = order[turn_i]
  if zoom == 2 then set_camera(2, active.x, active.y) end
  if active.side == 1 or auto then
    start(ai_turn, active)
  else
    waiting = true
    play("turn", 0.6)
  end
end

-- ------------------------------------------------------------------ input

local function pick_unit(px, py)
  local best, bd = nil, 1e9
  for _, u in ipairs(units) do
    if alive(u) then
      local cx, cy = unit_screen(u)
      local hw = (u.size > 3 and 7 or 5) * zoom + 2
      if math.abs(px - cx) <= hw and py <= cy + 3 and py >= cy - 12 * zoom then
        local d = math.abs(px - cx) + math.abs(py - (cy - 4 * zoom))
        if d < bd then bd, best = d, u end
      end
    end
  end
  return best
end

-- The action a touch at (px, py) would do, or nil
local function plan(px, py)
  local a = active
  local u = pick_unit(px, py)
  if u and u.side ~= a.side then
    return { k = "attack", t = u, spell = SPELLS[spell] }
  elseif u then
    if u ~= a then add_log("To twój oddział") end
    return nil
  end
  local wx, wy = to_world(px, py)
  local d = math.sqrt((wx - a.x) ^ 2 + (wy - a.y) ^ 2)
  local sp = TYPES[a.type].speed
  if d > sp then wx, wy = a.x + (wx - a.x) / d * sp, a.y + (wy - a.y) / d * sp end
  wx, wy = clamp_world(wx, wy)
  return { k = "move", x = wx, y = wy, px = px, py = py }
end

local function same(p, q)
  if not p or not q or p.k ~= q.k then return false end
  if p.k == "attack" then return p.t == q.t end
  local ax, ay = to_screen(p.x, p.y)
  local bx, by = to_screen(q.x, q.y)
  return math.abs(ax - bx) <= 8 and math.abs(ay - by) <= 8
end

local function confirm()
  local p, a = pending, active
  if not p or not waiting then return end
  if p.k == "move" then
    start(walk, a, p.x, p.y)
  elseif p.spell ~= "brak" then
    spell = 1
    start(cast, a, p.t, p.spell)
  elseif TYPES[a.type].ranged then
    start(shoot, a, p.t)
  else
    start(melee, a, p.t)
  end
end

local function tap(px, py)
  if over then new_battle(); return end
  if not waiting or not active then return end
  local p = plan(px, py)
  if not p then return end
  if same(p, pending) then confirm(); return end
  pending = p
  play("select", 0.7)
end

-- ------------------------------------------------------------------ callbacks

function _init()
  for _, name in ipairs(SFX) do
    local ok, s = pcall(sound, name)
    if ok then S[name] = s end
  end
  music_volume(0.7)
  new_battle()
end

function _update()
  frame = frame + 1
  if btnp("x") then mode = mode == "bmp" and "txt" or "bmp" end
  if btnp("y") then set_camera(zoom == 1 and 2 or 1, active and active.x or 51, active and active.y or 51) end
  if btnp("r") then spell = spell % #SPELLS + 1; if pending then pending.spell = SPELLS[spell] end end
  if btnp("l") then spell = (spell - 2) % #SPELLS + 1; if pending then pending.spell = SPELLS[spell] end end
  if btnp("select") then
    auto = not auto
    if auto and waiting and active then start(ai_turn, active) end
  end
  if btnp("a") then
    if over then new_battle() else confirm() end
  end
  if btnp("b") and waiting and active then
    if pending then
      pending = nil
    else
      add_log(TYPES[active.type].name .. " czeka")
      start(wait, 2)
    end
  end
  local tx, ty = touchp()
  if tx then tap(tx, ty) end

  if task then
    local ok, err = coroutine.resume(task)
    if not ok then error(err) end
    if coroutine.status(task) == "dead" then task = nil; next_turn() end
  end
  for _, u in ipairs(units) do
    if u.flash > 0 then u.flash = u.flash - 1 end
    if u.frozen > 0 then u.frozen = u.frozen - 1 end
    if u.dying > 0 then u.dying = u.dying - 1 end
  end
  for i = #fxs, 1, -1 do
    local f = fxs[i]
    if f.k == "num" or f.k == "boom" then f.t = f.t + 1 end
    if f.done or (f.k == "num" and f.t > 20) or (f.k == "boom" and f.t > 9) then
      table.remove(fxs, i)
    end
  end
end

-- ------------------------------------------------------------------ drawing: field

local function footprint(u, c, x, y, size)
  x, y, size = x or u.x, y or u.y, size or u.size
  local h = size / 2
  local tx, ty = to_screen(x - h, y - h)
  local rx, ry = to_screen(x - h, y + h)
  local bx, by = to_screen(x + h, y + h)
  local lx, ly = to_screen(x + h, y - h)
  line(tx, ty, rx, ry, c); line(rx, ry, bx, by, c)
  line(bx, by, lx, ly, c); line(lx, ly, tx, ty, c)
end

local function draw_field()
  local k = zoom
  rectfill(OX - camx * K, -camy * K, SCENE_W * K, SCENE_H * K, GROUND)
  for _, g in ipairs(grain) do pset(OX + (g[1] - camx) * K, (g[2] - camy) * K, g[3]) end
  for _, d in ipairs(deco) do
    local cx, cy = to_screen(d.x, d.y)
    if d.tree then
      rectfill(cx - k // 2, cy - 2 * k, k, 2 * k, 0)
      trifill(cx, cy - 9 * k, cx - 4 * k, cy - 2 * k, cx, cy - 2 * k, 5)
      trifill(cx, cy - 9 * k, cx, cy - 2 * k, cx + 4 * k, cy - 2 * k, 6)
    else
      circfill(cx, cy - k, 2 * k, 14)
      pset(cx - k, cy - 2 * k, 13)
    end
  end
end

local function move_ring(u)
  local sp = TYPES[u.type].speed
  for i = 0, 47 do
    local a = i / 48 * math.pi * 2
    local x, y = clamp_world(u.x + math.cos(a) * sp, u.y + math.sin(a) * sp)
    local px, py = to_screen(x, y)
    pset(px, py, 5)
  end
end

local function draw_pending()
  local p, a = pending, active
  if not p then return end
  local blink = (frame // 4) % 2 == 0
  local ax, ay = unit_screen(a)
  if p.k == "move" then
    local tx, ty = to_screen(p.x, p.y)
    for i = 1, 9 do                                  -- dotted path
      local q = i / 10
      pset(ax + (tx - ax) * q, ay + (ty - ay) * q, 12)
    end
    footprint(a, blink and 4 or 12, p.x, p.y)
    pset(tx, ty, 4)
  else
    local tx, ty = unit_screen(p.t)
    for i = 1, 9 do
      local q = i / 10
      pset(ax + (tx - ax) * q, ay - 4 * zoom + (ty - ay) * q, 3)
    end
    footprint(p.t, blink and 2 or 12, nil, nil, p.t.size + 1)
  end
end

local function draw_unit(u)
  local T, k = TYPES[u.type], zoom
  local cx, cy = unit_screen(u)
  local dead = not alive(u)
  if dead and u.dying == 0 then                     -- a corpse: grey bones
    line(cx - 3 * k, cy, cx + 3 * k, cy - k, 14)
    line(cx - 2 * k, cy - k, cx + 2 * k, cy + k, 13)
    return
  end
  if not dead then
    local c = SIDE[u.side].c
    if u == active then c = (frame // 4) % 2 == 1 and 4 or 12 end
    footprint(u, c)
  end
  local bob = 0
  if not dead and u.hop == 0 and u.ox == 0 and math.sin((frame * 2 + u.id * 7) / 14) > 0.7 then bob = 1 end
  local gx, gy, clip = cx + u.ox, cy + 1 - u.hop - bob + u.oy, nil
  local tint
  if u.flash > 0 and u.flash % 2 == 1 then tint = 12 elseif u.frozen > 0 then tint = 11 end
  if dead then gy = gy + (1 - u.dying / 12) * 8 * k; clip = cy + 1; tint = 13 end
  local top
  local sd = SIDE[u.side]
  if mode == "bmp" then
    top = glyphs.draw(u.type, gx, gy, k, u.face < 0, sd.c, sd.l, tint, clip)
  else
    top = glyphs.letter(T.ch, gx, gy, k, tint or (u.type == "hero" and 4 or sd.l), clip)
  end
  if not dead then                                  -- the count in the side's colour
    local t = tostring(u.count)
    local w = #t * 6 + 1
    local bx, by = (cx - w / 2) // 1, (top - 10) // 1
    rectfill(bx, by, w, 9, sd.c)
    text(t, bx + 1, by + 1, 12)
  end
end

local function draw_fx()
  for _, f in ipairs(fxs) do
    if f.k == "num" then
      local x = f.x - #f.text * 3
      text(f.text, x + 1, f.y - f.t + 1, 0)
      text(f.text, x, f.y - f.t, 12)
    elseif f.k == "arrow" and not f.done then
      local ax, ay = unit_screen(f.a)
      local tx, ty = unit_screen(f.t)
      local p, ah = f.i / f.n, 8 * zoom
      local p2 = math.max(0, p - 0.08)
      local x = ax + (tx - ax) * p
      local y = ay - ah + (ty - ay) * p - math.sin(p * math.pi) * 18
      local x2 = ax + (tx - ax) * p2
      local y2 = ay - ah + (ty - ay) * p2 - math.sin(p2 * math.pi) * 18
      line(x2, y2, x, y, 12); pset(x, y, 4)
    elseif f.k == "fireball" and not f.done then
      for _, p in ipairs(f.trail) do
        if p[3] > 0 then
          pset(p[1] + math.random(-1, 1), p[2] + math.random(-1, 1), p[3] > 4 and 4 or p[3] > 2 and 3 or 2)
          p[3] = p[3] - 1
        end
      end
      circfill(f.x, f.y, 3, 3); circfill(f.x, f.y, 1, 4)
    elseif f.k == "boom" then
      local r = 2 + f.t * 2
      circfill(f.x, f.y, math.max(1, r - 6), f.t < 3 and 12 or 4)
      circ(f.x, f.y, r, f.t < 4 and 4 or f.t < 6 and 3 or 2)
      for i = 0, 9 do
        local a = i * 0.63 + f.t * 0.4
        pset(f.x + math.cos(a) * r * 1.3, f.y + math.sin(a) * r * 0.7, 3)
      end
    elseif f.k == "bolt" and not f.done and f.t < 5 then
      local x, y = f.x + math.random(-10, 10), 0
      local c = f.t % 2 == 1 and 11 or 12
      for i = 1, 8 do
        local nx = i == 8 and f.x or f.x + math.random(-8, 8)
        local ny = f.y * i / 8
        line(x, y, nx, ny, c); line(x + 1, y, nx + 1, ny, 10)
        x, y = nx, ny
      end
      if f.t < 2 then circ(f.x, f.y, 3 + f.t * 4, 12) end
    elseif f.k == "ice" and not f.done then
      local r = math.max(0, 18 - f.t * 2)
      for i = 0, 7 do
        local a = i / 8 * math.pi * 2 + 0.3
        local x0, y0 = f.x + math.cos(a) * (r + 5), f.y + math.sin(a) * (r + 5) * 0.6
        local x1, y1 = f.x + math.cos(a) * r, f.y + math.sin(a) * r * 0.6
        line(x0, y0, x1, y1, i % 2 == 1 and 11 or 12)
      end
      if f.t > 7 then circ(f.x, f.y, (f.t - 7) * 4, 11) end
    end
  end
end

local function draw_bottom()
  cls(0)
  draw_field()
  if waiting and active then move_ring(active) end
  local list = {}
  for _, u in ipairs(units) do list[#list + 1] = u end
  table.sort(list, function(a, b)
    local la, lb = alive(a), alive(b)
    if la ~= lb then return lb end                 -- the dead below
    local da, db = a.x + a.y, b.x + b.y
    if da ~= db then return da < db end
    return a.id < b.id
  end)
  for _, u in ipairs(list) do draw_unit(u) end
  draw_pending()
  draw_fx()
  rectfill(0, 0, OX, 192, 0)
  rectfill(256 - OX, 0, OX, 192, 0)
  if over then
    rectfill(56, 76, 144, 34, 0); rect(56, 76, 144, 34, 4)
    local w = textw(over)
    text(over, 128 - w // 2, 82, 4)
    text("dotknij albo A: nowa bitwa", 128 - textw("dotknij albo A: nowa bitwa") // 2, 96, 13)
  end
end

-- ------------------------------------------------------------------ drawing: top screen

local avg_us, avg_poly = 0, 0

local function bar(x, y, w, v, max, c)
  rect(x, y, w, 5, 14)
  rectfill(x + 1, y + 1, ((w - 2) * math.min(1, v / max)) // 1, 3, c)
end

local function draw_top()
  cls(0)
  rectfill(0, 0, 256, 11, 15)
  text("HeroesDS G1 - bez sprajtów", 3, 2, 4)
  local m = mode == "bmp" and "bitmapy" or "litery"
  text(m, 253 - textw(m), 2, 13)
  if active and not over then
    local T, sd = TYPES[active.type], SIDE[active.side]
    rectfill(4, 15, 44, 44, 0x0b0c14); rect(4, 15, 44, 44, sd.c)
    if mode == "bmp" then
      glyphs.draw(active.type, 26, 53, active.size > 3 and 3 or 4, active.side == 1, sd.c, sd.l,
                  active.frozen > 0 and 11 or nil)
    else
      glyphs.letter(T.ch, 26, 50, 3, active.type == "hero" and 4 or sd.l)
    end
    text(T.name, 54, 15, 12)
    text(sd.name .. (waiting and "  - twój ruch" or ""), 54, 25, sd.l)
    text("ilość " .. active.count .. "  HP " .. active.hp .. "/" .. T.hp, 54, 35, 13)
    text("atak " .. T.atk .. "  ruch " .. T.speed .. (T.ranged and "  strzela" or ""), 54, 45, 13)
    if pending then
      local what = pending.k == "move" and "ruch" or
                   (pending.spell ~= "brak" and SPELL_NAME[pending.spell] or "atak")
      text(what .. ": dotknij znowu albo A", 54, 52 + 3, 4)
    elseif SPELLS[spell] ~= "brak" then
      text("czar: " .. SPELL_NAME[SPELLS[spell]] .. " (L/R)", 54, 55, 11)
    end
  end
  text("Runda " .. round, 4, 64, 4)
  for side = 0, 1 do
    local n, all = 0, 0
    for _, u in ipairs(units) do
      if u.side == side then all = all + 1; if alive(u) then n = n + 1 end end
    end
    text(SIDE[side].name, 66 + side * 96, 62, SIDE[side].l)
    bar(66 + side * 96, 71, 88, n, all, SIDE[side].c)
  end
  rectfill(2, 80, 252, 58, 0x0b0c14)
  for i, t in ipairs(logs) do text(t, 5, 82 + (i - 1) * 9, i == #logs and 12 or 14) end
  local st = sys.stats()
  avg_us = avg_us * 0.9 + (st.draw_bottom_us or 0) * 0.1
  avg_poly = avg_poly * 0.9 + (st.polys_bottom or 0) * 0.1
  rectfill(0, 142, 256, 50, 15)
  text(string.format("dół: %.1f ms  %d poly  cpu %d%%", avg_us / 1000, avg_poly // 1,
       (st.cpu or 0) // 1), 3, 144, 12)
  text(string.format("fps %d  pamięć Lua %d KB", (st.fps or 0) // 1, (st.mem or 0) // 1024), 3, 153, 13)
  text("dotyk: wybierz, drugi raz/A: zrób", 3, 163, 14)
  text("B anuluj/czekaj  X wygląd  Y lupa", 3, 172, 14)
  text("L/R czar  SELECT auto", 3, 181, 14)
end

function _draw(surface)
  if surface == TOP then draw_top() else draw_bottom() end
end
