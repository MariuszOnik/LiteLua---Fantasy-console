-- HeroesDS C4b: a battle on the DS with stand-in graphics (COMBAT.md 9; H6, H8, H11).
-- Bottom screen: the whole field at 3/16, touched to choose; a first touch shows what
-- would happen (path, target, damage on the top screen), a second touch on the same
-- thing (or A) does it, B cancels. Buttons at the left: wait, defend. The computer plays
-- side 1 in a coroutine, yielding at grid.tick() every SLICE us, so the hourglass turns.
-- Top screen: round, the active stack, the selection with its damage preview, the turn
-- order and the log. X after the end: a new battle.

local stats = require("combat.stats")
local battle = require("combat.battle")
local abilities = require("combat.abilities")
local casting = require("combat.casting")
local grid = require("combat.grid")
local ai = require("combat.ai")
local view = require("view")
local setup = require("setup")
abilities.install(battle)
casting.install(battle)

local HUMAN = { [0] = true }   -- Y: the computer plays this side too (and back)
local SLICE = 20000      -- us of the computer's work per frame

local creatures = dofile("data/creatures.lua")
local spells = dofile("data/spells.lua")
if pathgrid then grid.shape() end

local seed = 1
local b           -- the battle
local opts        -- the human's options this turn (Battle:options), nil = to make
local dots        -- move dots of this turn
local sel         -- { cmd, preview, path, ghost, target } or { info = stack }
local job         -- the computer's turn (a coroutine)
local log_lines = {}
local frame = 0
local touching = false
local slice_start = 0

-- --- the log -------------------------------------------------------------------------------

local function say(s)
  if utf8.len(s) > 42 then s = s:sub(1, utf8.offset(s, 42) - 1) end   -- the screen's width
  log_lines[#log_lines + 1] = s
  if #log_lines > 40 then table.remove(log_lines, 1) end
end

local function name_of(id)
  local u = b.units[id]
  if not u then return "?" end
  return u.is_hero and ("Bohater " .. u.name) or u.name
end

local function spell_name(key)
  return spells[key] and spells[key].name or key
end

local EVENT = {
  round = function(e) return ("-- Runda %d --"):format(e.n) end,
  melee = function(e) return ("%s bije %s: %d, zabici %d"):format(name_of(e.stack), name_of(e.target), e.damage, e.killed) end,
  shoot = function(e) return ("%s strzela w %s: %d, zabici %d"):format(name_of(e.stack), name_of(e.target), e.damage, e.killed) end,
  blocked = function(e) return name_of(e.stack) .. " blokuje" end,
  die = function(e) return name_of(e.stack) .. " ginie" end,
  luck = function(e) return e.good and "Szczęście!" or "Pech!" end,
  morale = function(e) return name_of(e.stack) .. (e.good and ": dobre morale" or ": złe morale") end,
  wait = function(e) return name_of(e.stack) .. " czeka" end,
  defend = function(e) return name_of(e.stack) .. " broni się" end,
  cast = function(e) return ("%s rzuca %s"):format(name_of(e.stack), spell_name(e.spell)) end,
  cast_at = function(e) return ("%s rzuca %s"):format(name_of(e.stack), spell_name(e.spell)) end,
  spell = function(e)
    if e.damage > 0 then return ("%s: %d, zabici %d"):format(name_of(e.stack), e.damage, e.killed) end
    if e.damage < 0 then return ("%s: +%d PW"):format(name_of(e.stack), -e.damage) end
    return ("%s: %s"):format(name_of(e.stack), spell_name(e.spell))
  end,
  resisted = function(e) return name_of(e.stack) .. " odpiera czar" end,
  effect = function(e) return ("%s: %s"):format(name_of(e.stack), spell_name(e.effect)) end,
  heal = function(e) return ("%s: +%d PW"):format(name_of(e.stack), e.amount) end,
  revived = function(e) return ("%s: wstaje %d"):format(name_of(e.stack), e.count) end,
  summon = function(e) return name_of(e.stack) .. " przywołany" end,
  over = function(e) return e.winner == 0 and "Zwycięstwo!" or "Porażka." end,
}

local function play(events)
  for _, e in ipairs(events or {}) do
    local f = EVENT[e.t]
    if f then say(f(e)) end
  end
end

-- --- the battle ----------------------------------------------------------------------------

local function new_battle()
  b = setup.battle(seed, creatures, spells)
  opts, dots, sel, job = nil, nil, nil, nil
  log_lines = {}
  say(("Bitwa %d"):format(seed))
  play(b:take_events())
end

local function human_turn()
  local u = b:current()
  return u and not b.finished and HUMAN[b:side_of(u)] and not ai.must_act(b, u)
end

-- The computer yields here once its slice is used (H11)
grid.tick = function()
  if coroutine.isyieldable() and micros() - slice_start >= SLICE then coroutine.yield() end
end

local function computer()
  if not job then job = coroutine.create(function() return ai.act(b) end) end
  slice_start = micros()
  local ok, ev = coroutine.resume(job)
  if not ok then error(ev) end
  if coroutine.status(job) == "dead" then
    job = nil
    play(ev)
  end
end

local function same(a, c)
  return a and c and a.type == c.type and a.target == c.target and a.x == c.x and a.y == c.y
end

-- The command a touch at (px, py) means, or an info selection
local function choose(px, py)
  local u = b:current()
  local wx, wy = view.to_world(px, py)
  local t = view.stack_at(b.units, px, py)
  if t and t ~= u and opts.melee[t.id] ~= nil then
    if opts.shoot[t.id] then return { type = "shoot", target = t.id }, t end
    -- the place to strike from: the one nearest the stylus
    local best, bd
    for k in pairs(b:attack_positions(u, t)) do
      local x, y = grid.xy(k)
      local dx, dy = x + u.size / 2 - wx, y + u.size / 2 - wy
      local d = dx * dx + dy * dy
      if not bd or d < bd or (d == bd and k < best) then best, bd = k, d end
    end
    if best then
      local x, y = grid.xy(best)
      return { type = "melee", target = t.id, x = x, y = y }, t
    end
    return { type = "melee", target = t.id }, t
  end
  if t then return nil, t end
  -- the ground: the reachable place whose centre is nearest the stylus
  local best, bd
  for k in pairs(opts.move) do
    local x, y = grid.xy(k)
    local dx, dy = x + u.size / 2 - wx, y + u.size / 2 - wy
    local d = dx * dx + dy * dy
    if not bd or d < bd or (d == bd and k < best) then best, bd = k, d end
  end
  if not best or best == grid.key(u.x, u.y) then return nil end
  local x, y = grid.xy(best)
  return { type = "move", x = x, y = y }
end

local function confirm()
  local ev, err = b:act(sel.cmd)
  if not ev then say("Nie można: " .. tostring(err)) end
  play(ev)
  opts, dots, sel = nil, nil, nil
end

local function pick(px, py)
  local cmd, t = choose(px, py)
  if not cmd then
    sel = t and { info = t } or nil
    return
  end
  if sel and same(sel.cmd, cmd) then return confirm() end
  local u = b:current()
  sel = { cmd = cmd, target = t }
  if cmd.type == "melee" and not cmd.x then return end
  if cmd.type == "move" then
    sel.path = b:path(u, cmd.x, cmd.y)
    sel.ghost = { cmd.x, cmd.y }
  else
    sel.preview = b:preview(cmd)
    if cmd.x then
      sel.ghost = { cmd.x, cmd.y }
      if cmd.x ~= u.x or cmd.y ~= u.y then sel.path = b:path(u, cmd.x, cmd.y) end
    end
  end
end

-- Buttons at the left of the field
local BUTTONS = {
  { y = 4, label = "Cz", cmd = { type = "wait" }, ok = function() return opts.wait end },
  { y = 48, label = "Ob", cmd = { type = "defend" }, ok = function() return true end },
}

local function button_at(px, py)
  if px >= view.OX then return nil end
  for _, bt in ipairs(BUTTONS) do
    if py >= bt.y and py < bt.y + 40 then return bt end
  end
end

-- --- frames --------------------------------------------------------------------------------

new_battle()

function _update()
  frame = frame + 1
  local tx, ty = touch()
  local pressed = tx and not touching
  touching = tx ~= nil

  if btnp("y") then
    HUMAN[0] = not HUMAN[0]
    say(HUMAN[0] and "Grasz sam" or "Komputer gra za ciebie (Y)")
    opts, dots, sel = nil, nil, nil
  end
  if b.finished then
    if btnp("x") or pressed then seed = seed + 1; new_battle() end
    return
  end
  if not human_turn() then
    computer()
    return
  end
  if not opts then
    opts = b:options()
    dots = view.move_dots(opts.move, b:current().size)
  end
  if btnp("b") then sel = nil end
  if btnp("a") and sel and sel.cmd then return confirm() end
  if pressed then
    local bt = button_at(tx, ty)
    if bt then
      if bt.ok() then sel = { cmd = bt.cmd }; return confirm() end
      return
    end
    pick(tx, ty)
  end
end

-- An hourglass turning over every second
local function hourglass(cx, cy)
  local a = (frame % 30) / 30 * math.pi
  local c, s = math.cos(a), math.sin(a)
  local function p(x, y) return cx + x * c - y * s, cy + x * s + y * c end
  local x1, y1 = p(-8, -11); local x2, y2 = p(8, -11); local x3, y3 = p(0, 0)
  trifill(x1, y1, x2, y2, x3, y3, 4)
  x1, y1 = p(-8, 11); x2, y2 = p(8, 11)
  trifill(x1, y1, x2, y2, x3, y3, 3)
end

local function stack_lines(u, y, col)
  text(("%s  x%d"):format(name_of(u.id), u.count), 2, y, col)
  text(("Atak %d  Obr %d  PW %d/%d  Szyb %d  Ruch %d"):format(u.attack, u.defense,
    stats.hit_points(u) - u.wounds, stats.hit_points(u), u.speed, u.move), 2, y + 9, 13)
  local extra = {}
  if u.shots and u.shots > 0 and u.shooter then extra[#extra + 1] = "strzały " .. u.shots end
  for k in pairs(u.effects) do extra[#extra + 1] = spell_name(k) end
  if #extra > 0 then text(table.concat(extra, ", "), 2, y + 18, 13) end
end

local function draw_top()
  cls(0)
  local u = b:current()
  if b.finished then
    text(b.winner == 0 and "ZWYCIĘSTWO" or "PORAŻKA", 2, 2, b.winner == 0 and 5 or 2)
    text("X lub dotyk: nowa bitwa", 2, 12, 13)
  else
    text(("Runda %d"):format(b.round), 2, 2, 13)
    if u then
      stack_lines(u, 12, view.stack_color(u))
      if not human_turn() then
        text("Tura przeciwnika...", 120, 2, 3)
        hourglass(236, 30)
      end
    end
    if sel then
      local y = 44
      if sel.info then
        stack_lines(sel.info, y, view.stack_color(sel.info))
      elseif sel.cmd.type == "move" then
        text(("Ruch na %d,%d - dotknij jeszcze raz"):format(sel.cmd.x, sel.cmd.y), 2, y, 4)
      elseif sel.cmd.type == "melee" and not sel.cmd.x then
        text(("Atak na %s"):format(name_of(sel.cmd.target)), 2, y, 4)
        text("za daleko - podejdzie w jego stronę", 2, y + 9, 3)
        text("dotknij jeszcze raz / A", 140, y + 18, 13)
      elseif sel.preview then
        local p = sel.preview
        text(("%s %s"):format(sel.cmd.type == "shoot" and "Strzał w" or "Atak na", name_of(sel.cmd.target)), 2, y, 4)
        text(("obrażenia %d-%d, zabici %d-%d"):format(p.min, p.max, p.kills_min, p.kills_max), 2, y + 9, 12)
        if p.back_min then text(("odwet %d-%d"):format(p.back_min, p.back_max), 2, y + 18, 3) end
        text("dotknij jeszcze raz / A", 140, y + 18, 13)
      end
    end
    -- the turn order
    local x = 2
    for _, id in ipairs(b:queue()) do
      local q = b.units[id]
      rectfill(x, 74, 10, 8, view.stack_color(q))
      x = x + 12
      if x > 250 then break end
    end
  end
  -- the log, newest at the bottom
  local n = #log_lines
  for i = 0, 11 do
    local l = log_lines[n - i]
    if l then text(l, 2, 182 - i * 9, i == 0 and 12 or 13) end
  end
end

local function draw_bottom()
  cls(15)
  view.draw_field({ units = b.units, active = not b.finished and b:current() or nil,
                    dots = human_turn() and dots or nil, path = sel and sel.path,
                    ghost = sel and sel.ghost, target = sel and sel.target,
                    blink = frame % 20 < 12 })
  if human_turn() then
    for _, bt in ipairs(BUTTONS) do
      local ok = opts and bt.ok()
      rect(1, bt.y, 15, 40, ok and 12 or 14)
      text(bt.label, 3, bt.y + 16, ok and 12 or 14)
    end
  end
end

function _draw(screen)
  if screen == TOP then draw_top() else draw_bottom() end
end
