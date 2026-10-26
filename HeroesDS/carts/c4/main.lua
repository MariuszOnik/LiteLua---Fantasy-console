-- HeroesDS C4: a battle on the DS with stand-in graphics (COMBAT.md 9; H6, H8, H11).
-- Bottom screen: the whole field at 3/16, touched to choose; a touch shows what would
-- happen (path, target, damage on the top screen) and the stylus can be dragged to
-- correct it. OK (right) or A does it; a second touch on the same enemy or spell target
-- too, a touch on the ground never (it only corrects). B cancels. Buttons: wait and
-- defend at the left, the spell book and OK at the right. L or R held: the magnifier (x2 around the stylus, the stylus at an edge
-- scrolls). The d-pad moves a cursor; A then touches where it points. The computer plays
-- side 1 in a coroutine, yielding at grid.tick() every SLICE us, so the hourglass turns.
-- Events are shown one by one: stacks walk their path, hits show their damage.
-- Top screen: round, the active stack, the selection with its preview, the turn order,
-- the log. Y: the computer plays your side too. X after the end: a new battle.

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
local sel         -- { cmd, preview, path, ghost, target, marked, note } or { info = stack }
local book        -- the spell book: { list = { keys } } while open
local aiming      -- a spell waiting for its target: { key, aim, target? }
local job         -- the computer's turn (a coroutine)
local queue = {}  -- events still to show
local anim        -- the event being shown: { frames, t, at = { [stack] = path } }
local popups = {} -- { wx, wy, text, col, t }
local log_lines = {}
local frame = 0
local touching = false
local slice_start = 0
local focus = { 590, 512 }     -- scene point the magnifier looks at
local cursor                   -- { x, y } on the bottom screen while the d-pad is used
local dragging = false         -- the stylus went down on the field and is still down
local last_touch = { -1, -1 }

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

-- --- showing the events --------------------------------------------------------------------

local function popup(id, s, col)
  local u = b.units[id]
  if not u then return end
  popups[#popups + 1] = { u.x + u.size / 2, u.y + u.size / 2, s, col, 0 }
end

-- Starts showing one event: the log line, and an animation that holds the next ones
local function show(e)
  local f = EVENT[e.t]
  if f then say(f(e)) end
  if e.t == "move" then
    local u = b.units[e.stack]
    local pts = { e.from }
    for _, p in ipairs(e.path) do pts[#pts + 1] = p end
    if e.flying and #pts > 2 then pts = { e.from, e.path[#e.path] } end
    local n = 0
    for i = 2, #pts do n = n + math.max(math.abs(pts[i][1] - pts[i - 1][1]), math.abs(pts[i][2] - pts[i - 1][2])) end
    anim = { frames = math.max(4, math.min(24, n)), t = 0, stack = u, pts = pts, len = n }
  elseif e.t == "melee" or e.t == "shoot" or (e.t == "spell" and e.damage ~= 0) then
    local hit = e.t == "spell" and e.stack or e.target
    if e.damage > 0 then popup(hit, "-" .. e.damage, 2)
    elseif e.damage < 0 then popup(e.stack, "+" .. -e.damage, 5)
    else popup(hit, "0", 13) end
    anim = { frames = 10, t = 0 }
  elseif e.t == "heal" then
    popup(e.stack, "+" .. e.amount, 5)
    anim = { frames = 8, t = 0 }
  elseif e.t == "die" or e.t == "cast" or e.t == "blocked" then
    anim = { frames = 6, t = 0 }
  end
end

-- Where a moving stack is drawn: along its path, by the animation's progress
local function moving_at()
  if not (anim and anim.stack) then return nil end
  local d = anim.len * anim.t / anim.frames
  local pts = anim.pts
  for i = 2, #pts do
    local a, c = pts[i - 1], pts[i]
    local l = math.max(math.abs(c[1] - a[1]), math.abs(c[2] - a[2]))
    if d <= l and l > 0 then
      local f = d / l
      return { [anim.stack] = { a[1] + (c[1] - a[1]) * f, a[2] + (c[2] - a[2]) * f } }
    end
    d = d - l
  end
  return nil
end

local function play(events)
  for _, e in ipairs(events or {}) do queue[#queue + 1] = e end
end

-- One frame of the show; true while it holds the game
local function showing()
  for i = #popups, 1, -1 do
    local p = popups[i]
    p[5] = p[5] + 1
    if p[5] > 24 then table.remove(popups, i) end
  end
  if anim then
    anim.t = anim.t + 1
    if anim.t >= anim.frames then anim = nil end
    return true
  end
  while #queue > 0 and not anim do show(table.remove(queue, 1)) end
  return anim ~= nil
end

-- --- the battle ----------------------------------------------------------------------------

local function reset_turn()
  opts, dots, sel, book, aiming = nil, nil, nil, nil, nil
end

local function new_battle()
  b = setup.battle(seed, creatures, spells)
  reset_turn()
  job, anim, queue, popups = nil, nil, {}, {}
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
    and a.spell == c.spell and a.second == c.second
end

local function confirm()
  local ev, err = b:act(sel.cmd)
  if not ev then say("Nie można: " .. tostring(err)) end
  play(ev)
  reset_turn()
end

-- --- choosing ------------------------------------------------------------------------------

-- The world cell under a screen point
local function cell_at(px, py)
  local wx, wy = view.to_world(px, py)
  return math.floor(wx), math.floor(wy)
end

-- The command a touch at (px, py) means for a move or an attack, or an info selection
local function choose(px, py)
  local u = b:current()
  local wx, wy = view.to_world(px, py)
  local t = view.stack_at(b.units, px, py)
  if t and t ~= u and opts.melee[t.id] ~= nil then
    if opts.shoot[t.id] then return { type = "shoot", target = t.id }, t end
    -- the place to strike from: where it stands when it can, else the one nearest the stylus
    local positions = b:attack_positions(u, t)
    if positions[grid.key(u.x, u.y)] then return { type = "melee", target = t.id, x = u.x, y = u.y }, t end
    local best, bd
    for k in pairs(positions) do
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

-- A spell's command from a touch, by its aim; nil while it needs more (aiming keeps it)
local function aim_spell(px, py)
  local t = view.stack_at(b.units, px, py)
  local x, y = cell_at(px, py)
  local a = aiming
  local cmd = { type = "cast", spell = a.key }
  if a.aim == "cell" then
    cmd.x, cmd.y = x, y
  elseif a.aim == "unit" then
    if not t then return nil end
    cmd.target = t.id
  elseif a.aim == "unit_or_cell" then
    if t then cmd.target = t.id else cmd.x, cmd.y = x, y end
  elseif a.aim == "unit_and_point" then
    if not t then return nil end
    cmd.target, cmd.x, cmd.y = t.id, x, y
  elseif a.aim == "two_units" or a.aim == "unit_then_cell" then
    if not a.target then
      if not t then return nil end
      a.target = t.id
      say(spell_name(a.key) .. ": " .. name_of(t.id) .. (a.aim == "two_units" and ", teraz drugi oddział" or ", teraz miejsce"))
      return nil
    end
    cmd.target = a.target
    if a.aim == "two_units" then
      if not t then return nil end
      cmd.second = t.id
    else
      cmd.x, cmd.y = x, y
    end
  end
  return cmd
end

local function select_spell(cmd, again)
  if again and sel and same(sel.cmd, cmd) then return confirm() end
  local targets, err = casting.check(b, b:current(), cmd)
  if not targets then
    sel = { cmd = cmd, bad = err }
    return
  end
  local marked = {}
  for _, t in ipairs(targets) do marked[t] = true end
  sel = { cmd = cmd, marked = marked, count = #targets }
end

-- A touch (again = a new press, not a drag) chooses; a new press on the same enemy or
-- spell target does it
local function pick(px, py, again)
  if aiming then
    local cmd = aim_spell(px, py)
    if cmd then select_spell(cmd, again and cmd.target ~= nil) end
    return
  end
  local cmd, t = choose(px, py)
  if not cmd then
    if again then sel = t and { info = t } or nil end
    return
  end
  if again and t and sel and same(sel.cmd, cmd) then return confirm() end
  if sel and same(sel.cmd, cmd) then return end
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

-- Buttons at the sides of the field
local BUTTONS = {
  { x = 1, y = 4, label = "Cz", cmd = { type = "wait" }, ok = function() return opts.wait end },
  { x = 1, y = 48, label = "Ob", cmd = { type = "defend" }, ok = function() return true end },
  { x = 240, y = 4, label = "Ks", book = true, ok = function() return next(opts.spells) ~= nil end },
  { x = 240, y = 148, label = "OK", go = true, ok = function() return sel and sel.cmd and not sel.bad end },
}

local function button_at(px, py)
  if px >= view.OX and px < 238 then return nil end
  for _, bt in ipairs(BUTTONS) do
    if px >= bt.x and px < bt.x + 15 and py >= bt.y and py < bt.y + 40 then return bt end
  end
end

-- The spell book: a list over the field, one row of 16 px a spell
local function open_book()
  local list = {}
  for key in pairs(opts.spells) do list[#list + 1] = key end
  table.sort(list, function(a, c) return spell_name(a) < spell_name(c) end)
  book = { list = list }
  sel, aiming = nil, nil
end

local function book_touch(px, py)
  local i = (py - 20) // 16 + 1
  local key = book.list[i]
  book = nil
  if not key or px < 20 or px > 236 then return end
  local aim = opts.spells[key].aim
  aiming = { key = key, aim = aim }
  if aim == "none" then   -- no target: the next touch on the field (or A) casts it
    select_spell({ type = "cast", spell = key })
    return
  end
  say(spell_name(key) .. ": wskaż cel")
end

-- --- input ---------------------------------------------------------------------------------

-- The magnifier: L or R held; the stylus at an edge scrolls
local function magnifier(tx, ty)
  local held = btn("l") or btn("r")
  if held and view.zoom == 1 then
    local u = b:current()
    if tx then focus = { view.to_scene(tx, ty) }
    elseif u then focus = { grid.screen(u.x + u.size / 2, u.y + u.size / 2) } end
  elseif held and tx then
    local dx = (tx < 24 and -6) or (tx > 232 and 6) or 0
    local dy = (ty < 16 and -6) or (ty > 176 and 6) or 0
    focus[1], focus[2] = focus[1] + dx / 0.375, focus[2] + dy / 0.375
  end
  view.set_camera(held and 2 or 1, focus[1], focus[2])
end

-- The d-pad cursor; returns its point when A touches with it
local function dpad()
  local dx = (btn("left") and -2 or 0) + (btn("right") and 2 or 0)
  local dy = (btn("up") and -2 or 0) + (btn("down") and 2 or 0)
  if dx ~= 0 or dy ~= 0 then
    cursor = cursor or { 128, 96 }
    cursor[1] = math.max(0, math.min(255, cursor[1] + dx))
    cursor[2] = math.max(0, math.min(191, cursor[2] + dy))
  end
end

-- --- frames --------------------------------------------------------------------------------

new_battle()

function _update()
  frame = frame + 1
  local tx, ty = touch()
  local pressed = tx and not touching
  touching = tx ~= nil
  if tx then cursor = nil end
  magnifier(tx, ty)
  dpad()

  if btnp("y") then
    HUMAN[0] = not HUMAN[0]
    say(HUMAN[0] and "Grasz sam" or "Komputer gra za ciebie (Y)")
    reset_turn()
  end
  if showing() then return end
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
  if btnp("b") then
    if book or aiming then book, aiming = nil, nil end
    sel = nil
  end
  if btnp("a") then
    if cursor then tx, ty, pressed = cursor[1], cursor[2], true
    elseif sel and sel.cmd and not sel.bad then return confirm() end
  end
  if not tx then dragging = false end
  if dragging and tx and not pressed and not book then   -- the stylus dragged: correct
    local free = not aiming or aiming.aim == "cell" or aiming.aim == "unit_or_cell"
    if free and (tx ~= last_touch[1] or ty ~= last_touch[2]) then pick(tx, ty, false) end
    last_touch = { tx, ty }
    return
  end
  if pressed then last_touch = { tx, ty } end
  if not pressed then return end
  if book then return book_touch(tx, ty) end
  local bt = button_at(tx, ty)
  if bt then
    if not bt.ok() then return end
    if bt.book then return open_book() end
    if not bt.go then sel = { cmd = bt.cmd } end
    return confirm()
  end
  dragging = true
  pick(tx, ty, true)
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
  if u.caster then extra[#extra + 1] = "mana " .. (u.spell_points or 0) end
  if u.shots and u.shots > 0 and u.shooter then extra[#extra + 1] = "strzały " .. u.shots end
  for k in pairs(u.effects) do extra[#extra + 1] = spell_name(k) end
  if #extra > 0 then text(table.concat(extra, ", "), 2, y + 18, 13) end
end

local function draw_selection(y)
  if aiming and not sel then
    text(spell_name(aiming.key) .. ": wskaż cel na polu", 2, y, 4)
    return
  end
  if not sel then return end
  if sel.info then return stack_lines(sel.info, y, view.stack_color(sel.info)) end
  local c = sel.cmd
  if c.type == "cast" then
    text(("Czar: %s (%d many)"):format(spell_name(c.spell), opts.spells[c.spell].cost), 2, y, 4)
    if sel.bad then text("nie można: " .. tostring(sel.bad), 2, y + 9, 2)
    else text(("cele: %d"):format(sel.count), 2, y + 9, 12) end
  elseif c.type == "move" then
    text(("Ruch na %d,%d"):format(c.x, c.y), 2, y, 4)
  elseif c.type == "melee" and not c.x then
    text(("Atak na %s"):format(name_of(c.target)), 2, y, 4)
    text("za daleko - podejdzie w jego stronę", 2, y + 9, 3)
  elseif sel.preview then
    local p = sel.preview
    text(("%s %s"):format(c.type == "shoot" and "Strzał w" or "Atak na", name_of(c.target)), 2, y, 4)
    text(("obrażenia %d-%d, zabici %d-%d"):format(p.min, p.max, p.kills_min, p.kills_max), 2, y + 9, 12)
    if p.back_min then text(("odwet %d-%d"):format(p.back_min, p.back_max), 2, y + 18, 3) end
  end
  if not sel.bad then text("OK / A: wykonaj", 152, y + 18, 13) end
end

local function draw_top()
  cls(0)
  local u = b:current()
  if b.finished then
    text(b.winner == 0 and "ZWYCIĘSTWO" or "PORAŻKA", 2, 2, b.winner == 0 and 5 or 2)
    text("X lub dotyk: nowa bitwa", 2, 12, 13)
  else
    text(("Runda %d"):format(b.round), 2, 2, 13)
    if not HUMAN[0] then text("auto (Y)", 60, 2, 14) end
    if u then
      stack_lines(u, 12, view.stack_color(u))
      if not human_turn() and not anim then
        text("Tura przeciwnika...", 120, 2, 3)
        hourglass(236, 30)
      end
    end
    if human_turn() then draw_selection(44) end
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
  for i = 0, 10 do
    local l = log_lines[n - i]
    if l then text(l, 2, 182 - i * 9, i == 0 and 12 or 13) end
  end
end

local function draw_book()
  rectfill(18, 2, 220, 188, 0)
  rect(18, 2, 220, 188, 13)
  text("Księga czarów (B: zamknij)", 24, 6, 4)
  for i, key in ipairs(book.list) do
    local y = 20 + (i - 1) * 16
    text(spell_name(key), 24, y + 4, 12)
    text(tostring(opts.spells[key].cost), 214, y + 4, 10)
    line(20, y + 15, 235, y + 15, 15)
  end
end

local function draw_bottom()
  cls(15)
  local turn = human_turn() and not anim
  view.draw_field({ units = b.units, active = not b.finished and b:current() or nil,
                    dots = turn and not aiming and dots or nil, path = sel and sel.path,
                    ghost = sel and sel.ghost, target = sel and sel.target,
                    marked = sel and sel.marked, at = moving_at(),
                    blink = frame % 20 < 12 })
  for _, p in ipairs(popups) do
    local px, py = view.to_screen(p[1], p[2])
    text(p[3], px - #p[3] * 3, py - 12 - p[5] // 2, p[4])
  end
  if turn and opts then
    for _, bt in ipairs(BUTTONS) do
      local ok = bt.ok()
      rectfill(bt.x, bt.y, 15, 40, 15)
      rect(bt.x, bt.y, 15, 40, ok and 12 or 14)
      text(bt.label, bt.x + 2, bt.y + 16, ok and 12 or 14)
    end
  end
  if book then draw_book() end
  if cursor then
    line(cursor[1] - 4, cursor[2], cursor[1] + 4, cursor[2], 4)
    line(cursor[1], cursor[2] - 4, cursor[1], cursor[2] + 4, 4)
  end
end

function _draw(screen)
  if screen == TOP then draw_top() else draw_bottom() end
end
