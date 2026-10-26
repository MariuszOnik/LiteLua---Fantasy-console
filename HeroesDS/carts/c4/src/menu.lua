-- HeroesDS C4: the test battle's set-up (a temporary menu). Bottom screen: tabs for the
-- two sides; the hero row opens the hero panel (present or not, type, level 1-30, up to 6
-- artifacts); each of up to 6 stacks: touch its name to pick the creature from a list,
-- - / + change the count by the step (1, 10, 100), x removes it. "Walka!" (or START)
-- starts the battle. Top screen: the creature or artifact in question. The set-up is kept
-- in save/army.txt (lines "side hero type level", "side art key", "side key count").

local setup = require("setup")

local menu = {}

local MAX, MAX_ART = 6, 6
local ROW_Y, ROW_H = 40, 20

local creatures, artifacts, keys, art_keys
local cfg            -- { [0] = { hero = { type, level, artifacts } or false, stacks = { { key, count } } } }
local side = 0
local step = 1
local focus          -- { kind = "creature" | "artifact", key } shown on the top screen
local picker         -- { title, list, label, pick, top } while a list is open
local panel = false  -- the hero panel is open
local message

local function cname(key) return creatures[key] and creatures[key].name or key end
local function aname(key) return artifacts[key] and artifacts[key].name or key end

local function cut(s, n)
  if utf8.len(s) > n then return s:sub(1, utf8.offset(s, n + 1) - 1) end
  return s
end

-- --- saving --------------------------------------------------------------------------------

local function save()
  local f = io.open("save/army.txt", "w")
  if not f then return end
  for s = 0, 1 do
    local h = cfg[s].hero
    if h then
      f:write(("%d hero %s %d\n"):format(s, h.type, h.level))
      for _, a in ipairs(h.artifacts) do f:write(("%d art %s\n"):format(s, a)) end
    end
    for _, st in ipairs(cfg[s].stacks) do f:write(("%d %s %d\n"):format(s, st[1], st[2])) end
  end
  f:close()
end

local function load()
  local f = io.open("save/army.txt")
  if not f then return nil end
  local c = { [0] = { hero = false, stacks = {} }, [1] = { hero = false, stacks = {} } }
  for line in f:lines() do
    local s, rest = line:match("^(%d) (.*)$")
    s = tonumber(s)
    if s and c[s] then
      local ty, lv = rest:match("^hero (%S+) (%d+)$")
      local art = rest:match("^art (.+)$")
      local key, n = rest:match("^(.-) (%d+)$")
      if ty then c[s].hero = { type = setup.type_of(ty).id, level = tonumber(lv), artifacts = {} }
      elseif art then
        if c[s].hero and artifacts[art] and #c[s].hero.artifacts < MAX_ART then
          table.insert(c[s].hero.artifacts, art)
        end
      elseif key and creatures[key] and #c[s].stacks < MAX then c[s].stacks[#c[s].stacks + 1] = { key, tonumber(n) } end
    end
  end
  f:close()
  return c
end

-- --- the set-up ----------------------------------------------------------------------------

local ART_ORDER = { item = 1, treasure = 2, minor = 3, fragment = 4, major = 5, relic = 6, divine = 7 }

-- default: a set-up to start from when nothing is saved (setup.default)
function menu.init(creature_table, artifact_table, default)
  creatures, artifacts = creature_table, artifact_table
  keys = {}
  for k in pairs(creatures) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local la, lb = creatures[a].level or 0, creatures[b].level or 0
    if la ~= lb then return la < lb end
    return cname(a) < cname(b)
  end)
  art_keys = {}
  for k in pairs(artifacts) do art_keys[#art_keys + 1] = k end
  table.sort(art_keys, function(a, b)
    local la, lb = ART_ORDER[artifacts[a].level] or 9, ART_ORDER[artifacts[b].level] or 9
    if la ~= lb then return la < lb end
    return aname(a) < aname(b)
  end)
  cfg = load() or default
end

function menu.config() return cfg end

-- --- lists (creatures, artifacts) ----------------------------------------------------------

local function open_list(title, list, label, kind, current, pick)
  picker = { title = title, list = list, label = label, kind = kind, pick = pick, top = 1 }
  for n, k in ipairs(list) do
    if k == current then picker.top = math.max(1, math.min(#list - 8, n - 4)) end
  end
end

local function creature_list(slot)
  local list = cfg[side].stacks
  open_list("Wybierz stwora", keys, function(k) return ("%d %s"):format(creatures[k].level or 0, cname(k)) end,
    "creature", list[slot] and list[slot][1], function(key)
      if list[slot] then list[slot][1] = key else list[#list + 1] = { key, 10 } end
      focus = { kind = "creature", key = key }
    end)
end

local function artifact_list()
  local h = cfg[side].hero
  open_list("Wybierz artefakt", art_keys, aname, "artifact", nil, function(key)
    if #h.artifacts < MAX_ART then table.insert(h.artifacts, key) end
    focus = { kind = "artifact", key = key }
  end)
end

local function inside(x, y, x0, y0, w, h) return x >= x0 and x < x0 + w and y >= y0 and y < y0 + h end

local function list_touch(tx, ty)
  local p = picker
  if inside(tx, ty, 232, 20, 24, 76) then p.top = math.max(1, p.top - 9); return end
  if inside(tx, ty, 232, 100, 24, 76) then p.top = math.max(1, math.min(#p.list - 8, p.top + 9)); return end
  if ty < 20 or ty >= 20 + 9 * 18 then picker = nil; return end
  local key = p.list[p.top + (ty - 20) // 18]
  if key then p.pick(key) end
  picker = nil
end

-- --- the hero panel ------------------------------------------------------------------------

local function panel_touch(tx, ty)
  local c = cfg[side]
  if inside(tx, ty, 196, 0, 60, 18) then panel = false; return end
  if inside(tx, ty, 0, 22, 256, 18) then
    c.hero = not c.hero and { type = side == 0 and "chaos_fighter" or "death_mage", level = 8, artifacts = {} } or false
    return
  end
  local h = c.hero
  if not h then return end
  if inside(tx, ty, 0, 44, 256, 18) then
    local i = 1
    for n, t in ipairs(setup.TYPES) do if t.id == h.type then i = n end end
    i = (tx < 128 and i - 2 or i) % #setup.TYPES + 1
    h.type = setup.TYPES[i].id
  elseif inside(tx, ty, 0, 66, 256, 18) then
    h.level = math.max(1, math.min(30, h.level + (tx < 128 and -1 or 1)))
  elseif ty >= 98 then
    local i = (ty - 98) // 13 + 1
    local a = h.artifacts[i]
    if a then
      if tx >= 228 then table.remove(h.artifacts, i) else focus = { kind = "artifact", key = a } end
    elseif i == #h.artifacts + 1 and i <= MAX_ART then
      artifact_list()
    end
  end
end

-- --- input ---------------------------------------------------------------------------------

-- Returns "start" when the battle should begin
function menu.update(tx, ty, pressed)
  if picker then
    if btnp("up") then picker.top = math.max(1, picker.top - 1) end
    if btnp("down") then picker.top = math.max(1, math.min(#picker.list - 8, picker.top + 1)) end
    if btnp("b") then picker = nil end
    if pressed then list_touch(tx, ty) end
    return nil
  end
  if btnp("b") then panel = false end
  if btnp("start") then pressed, tx, ty, panel = true, 200, 4, false end
  if not pressed then return nil end
  message = nil
  if panel then panel_touch(tx, ty); return nil end
  if ty < 18 then
    if tx < 64 then side = 0 elseif tx < 128 then side = 1
    elseif tx >= 176 then
      for s = 0, 1 do
        if #cfg[s].stacks == 0 and not cfg[s].hero then
          message = (s == 0 and "Twoja" or "Wroga") .. " armia jest pusta"
          return nil
        end
      end
      save()
      return "start"
    end
    return nil
  end
  local c = cfg[side]
  if inside(tx, ty, 0, 20, 256, 18) then panel = true; return nil end
  if inside(tx, ty, 0, 172, 256, 20) then
    step = step == 1 and 10 or (step == 10 and 100 or 1)
    return nil
  end
  local i = (ty - ROW_Y) // ROW_H + 1
  if i < 1 or i > MAX then return nil end
  local st = c.stacks[i]
  if not st then
    if i == #c.stacks + 1 then creature_list(i) end
    return nil
  end
  focus = { kind = "creature", key = st[1] }
  if tx < 130 then creature_list(i)
  elseif tx < 156 then st[2] = math.max(1, st[2] - step)
  elseif tx >= 196 and tx < 222 then st[2] = math.min(9999, st[2] + step)
  elseif tx >= 228 then table.remove(c.stacks, i)
  end
  return nil
end

-- --- drawing -------------------------------------------------------------------------------

local function button(x, y, w, h, label, col)
  rect(x, y, w, h, col or 13)
  text(label, x + (w - utf8.len(label) * 6) // 2, y + (h - 8) // 2, col or 12)
end

local function hero_line(h)
  if not h then return "Bohater: brak" end
  return ("Bohater: %s, poz. %d"):format(setup.type_of(h.type).label, h.level)
end

local function draw_list()
  local p = picker
  text(p.title .. " (B: wróć)", 2, 4, 4)
  for r = 0, 8 do
    local key = p.list[p.top + r]
    if key then
      local y = 20 + r * 18
      rectfill(0, y, 230, 17, r % 2 == 0 and 15 or 0)
      text(cut(p.label(key), 37), 4, y + 5, 12)
    end
  end
  button(232, 20, 24, 76, "^")
  button(232, 100, 24, 76, "v")
end

local function draw_panel()
  local c = cfg[side]
  text(side == 0 and "Twój bohater" or "Bohater wroga", 4, 5, 4)
  button(196, 0, 60, 18, "OK", 5)
  rectfill(0, 22, 256, 18, 15)
  text(c.hero and "Jest: tak (dotknij: usuń)" or "Jest: nie (dotknij: dodaj)", 4, 27, 12)
  local h = c.hero
  if not h then return end
  rectfill(0, 44, 256, 18, 15)
  text("<", 4, 49, 13); text(">", 246, 49, 13)
  local label = setup.type_of(h.type).label
  text(label, 128 - utf8.len(label) * 3, 49, 12)
  rectfill(0, 66, 256, 18, 15)
  text("-", 4, 71, 13); text("+", 246, 71, 13)
  text(("Poziom %d"):format(h.level), 100, 71, 12)
  text("Artefakty:", 4, 88, 13)
  for i = 1, MAX_ART do
    local y = 98 + (i - 1) * 13
    local a = h.artifacts[i]
    if a then
      text(cut(aname(a), 36), 4, y + 2, focus and focus.key == a and 4 or 12)
      text("x", 236, y + 2, 2)
    elseif i == #h.artifacts + 1 then
      text("+ dodaj artefakt", 4, y + 2, 13)
    end
  end
end

function menu.draw_bottom()
  cls(0)
  if picker then return draw_list() end
  if panel then return draw_panel() end
  button(0, 0, 63, 18, "Ty", side == 0 and 10 or 14)
  button(64, 0, 63, 18, "Wróg", side == 1 and 3 or 14)
  button(176, 0, 80, 18, "Walka!", 5)
  local c = cfg[side]
  rectfill(0, 20, 256, 18, 15)
  text(cut(hero_line(c.hero), 42), 4, 25, c.hero and 12 or 14)
  for i = 1, MAX do
    local y = ROW_Y + (i - 1) * ROW_H
    local st = c.stacks[i]
    if st then
      rectfill(0, y, 256, ROW_H - 2, 15)
      text(cut(cname(st[1]), 20), 4, y + 5, focus and focus.key == st[1] and 4 or 12)
      button(132, y + 1, 22, ROW_H - 4, "-")
      text(tostring(st[2]), 158, y + 5, 12)
      button(198, y + 1, 22, ROW_H - 4, "+")
      button(230, y + 1, 22, ROW_H - 4, "x", 2)
    elseif i == #c.stacks + 1 then
      text("+ dodaj oddział", 4, y + 5, 13)
    end
  end
  text(("krok: %d (dotknij)"):format(step), 4, 178, 13)
  if message then text(message, 120, 178, 2) end
end

-- What an artifact does, from its effects (type, whom, amount)
local WHOM = { self = "bohater", own_creatures = "armia", all = "wszyscy", enemy_creatures = "wróg",
               enemy_heroes = "bohater wroga" }
local function effect_text(e)
  local s = e.type:gsub("_", " ")
  if e.spell and type(e.spell) == "string" then s = s .. " " .. e.spell end
  if e.amount and e.amount ~= 0 then s = s .. " " .. (e.amount > 0 and "+" or "") .. e.amount end
  return s .. " (" .. (WHOM[e.target] or e.target or "?") .. ")"
end

local function draw_focus_creature(key)
  local d = creatures[key]
  text(cname(key), 2, 46, 12)
  local lines = {
    ("poziom %d   %s"):format(d.level or 0, d.alignment or ""),
    ("atak %d   obrona %d"):format(d.attack, d.defense),
    ("punkty życia %d   obrażenia %d-%d"):format(d.hp, d.dmg[1], d.dmg[2]),
    ("szybkość %d   ruch %d   strzały %d"):format(d.speed, d.move, d.shots or 0),
    ("rozmiar %d   odporność %d%%"):format(d.size or 1, d.magic_resistance or 0),
  }
  for i, l in ipairs(lines) do text(l, 2, 46 + i * 10, 13) end
  local ab = {}
  for k in pairs(d.abilities or {}) do ab[#ab + 1] = k end
  table.sort(ab)
  local s, y = "", 112
  for _, a in ipairs(ab) do
    if utf8.len(s) + #a + 2 > 42 then text(s, 2, y, 10); y = y + 9; s = "" end
    s = s == "" and a or (s .. ", " .. a)
  end
  if s ~= "" then text(s, 2, y, 10) end
end

local function draw_focus_artifact(key)
  local a = artifacts[key]
  text(cut(aname(key), 42), 2, 44, 12)
  text(("%s, %s"):format(a.level or "", a.slot or ""), 2, 56, 13)
  local y = 70
  for _, e in ipairs(a.effects or {}) do
    if e.type == "set_bonus" then
      text("komplet:", 2, y, 13); y = y + 9
      for _, sub in ipairs(e.subs or {}) do text(cut("  " .. effect_text(sub), 42), 2, y, 10); y = y + 9 end
    else
      text(cut(effect_text(e), 42), 2, y, 10); y = y + 9
    end
    if y > 180 then break end
  end
end

function menu.draw_top()
  cls(0)
  text("Walka testowa: ustaw armie", 2, 2, 4)
  text("Bohater: dotknij jego wiersza.", 2, 13, 13)
  text("Stwór: nazwa = wybór, -/+ = liczba.", 2, 22, 13)
  text("START lub Walka! = start bitwy.", 2, 31, 13)
  local f = focus
  if picker then
    local key = picker.list[picker.top + 4]
    if key then f = { kind = picker.kind, key = key } end
  end
  if not f then return end
  if f.kind == "creature" and creatures[f.key] then draw_focus_creature(f.key)
  elseif f.kind == "artifact" and artifacts[f.key] then draw_focus_artifact(f.key) end
end

return menu
