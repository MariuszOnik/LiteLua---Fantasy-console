-- LiteLua launcher (system cart, P10): the list of the carts in
-- litelua/carts. Play, edit the code (the code editor @code) or make a new
-- game from the template. The list is on the bottom (touch) screen, the
-- chosen cart and the help on the top one.

local kb = require("keyboard")
local S = sys.system

local ROW_H = 12
local LIST_ROWS = 13           -- Rows of the list (y 0 .. 156)
local BAR_Y, BAR_H = 164, 26   -- Buttons on the bottom screen
local COLS = 42                -- Characters in a line of the top screen
local NAME_MAX = 32            -- Longest name of a new cart (as in C)
local STATE_FILE = "save/last.txt"

local items = {}               -- { name, title, error, lcart, writable } and the demo
local cursor, top = 1, 1
local mode = "list"            -- "list" or "new"
local new_name = ""
local msg, msg_frames, msg_col = nil, 0, 4

local function say(s, seconds, col)
  msg, msg_frames, msg_col = s, (seconds or 3) * 30, col or 4
end

-- --- carts --------------------------------------------------------------------

local function read_last()
  local f = io.open(STATE_FILE, "r")
  if not f then return nil end
  local s = f:read("l")
  f:close()
  return s
end

local function write_last(name)
  local f = io.open(STATE_FILE, "w")
  if f then f:write(name, "\n"); f:close() end
end

local function load_items(select)
  items = S.carts()
  items[#items + 1] = { demo = true, title = "Built-in demo" }
  cursor = #items > 1 and 1 or #items
  for i, it in ipairs(items) do
    if it.name and it.name == select then cursor = i end
  end
end

-- The manifest of a cart (author, version, desc), read once when needed
local function manifest(it)
  if it.demo or it.error then return nil end
  if it.manifest == nil then
    it.manifest = S.manifest(it.name) or false
  end
  return it.manifest or nil
end

-- --- actions ------------------------------------------------------------------

local function play()
  local it = items[cursor]
  if it.demo then
    S.demo()
  elseif it.error then
    say("cannot run: cart.lua is broken (Y: edit it)", 4, 2)
  else
    write_last(it.name)
    sys.run(it.name)
  end
end

local function edit()
  local it = items[cursor]
  if it.demo then
    say("the demo is built in: no files to edit", 3, 2)
  else
    write_last(it.name)
    S.edit(it.name)
  end
end

local function open_new()
  mode, new_name = "new", ""
  kb.layer, kb.shift = "letters", 0
end

local function valid_name_char(c)
  return c:match("^[%w_%-]$") ~= nil
end

local function template(path, name)
  local s = assert(S.read("@launcher", "template/" .. path))
  local id = name:lower()
  -- Plain replacement: no pattern characters in the name (letters, _ -)
  return (s:gsub("%$ID", id):gsub("%$TITLE", name))
end

local function create()
  local name = new_name
  if name == "" then say("type a name first", 3, 2); return end
  local ok, err = S.create(name)
  if not ok then say(err, 4, 2); return end
  for _, f in ipairs({ "cart.lua", "main.lua" }) do
    ok, err = S.write(name, f, template(f, name))
    if not ok then say(err, 4, 2); return end
  end
  write_last(name)
  S.edit(name)
end

-- --- input --------------------------------------------------------------------

-- Buttons with auto repeat
local held, repeated = {}, {}
local function poll_buttons()
  for _, b in ipairs({ "up", "down", "l", "r" }) do
    local n = btn(b) and (held[b] or 0) + 1 or 0
    held[b] = n
    repeated[b] = n == 1 or (n > 10 and n % 2 == 0)
  end
end

-- The first sample after the stylus touches the screen is often off by a
-- few pixels, so a press counts from the second frame of a touch (or at
-- the release of a one-frame tap, with its position); same as the editor
local touch_frames, last_tx, last_ty = 0, 0, 0
local function read_touch()
  local tx, ty = touch()
  if tx then
    touch_frames = touch_frames + 1
    last_tx, last_ty = tx, ty
    return tx, ty, touch_frames == 2
  end
  local tap = touch_frames == 1
  touch_frames = 0
  if tap then return last_tx, last_ty, true end
  return nil
end

local LIST_BUTTONS = { { "Play", play }, { "Edit", edit }, { "New", open_new } }
local NEW_BUTTONS = { "OK", "Back" }

local function button_at(tx, n)
  return math.min(n, tx * n // 256 + 1)
end

local function update_list(tx, ty, pressed)
  local lr = btn("l") and btn("r") -- L+R+...: system buttons
  if repeated.up and cursor > 1 then cursor = cursor - 1 end
  if repeated.down and cursor < #items then cursor = cursor + 1 end
  if not lr then
    if repeated.l then cursor = math.max(1, cursor - LIST_ROWS) end
    if repeated.r then cursor = math.min(#items, cursor + LIST_ROWS) end
    if btnp("a") then play()
    elseif btnp("y") then edit()
    elseif btnp("x") then open_new() end
  end

  if pressed then
    if ty >= BAR_Y then
      LIST_BUTTONS[button_at(tx, #LIST_BUTTONS)][2]()
    else
      local i = top + ty // ROW_H
      if i <= #items and ty < LIST_ROWS * ROW_H then
        if i == cursor then play() else cursor = i end
      end
    end
  end

  if cursor < top then top = cursor end
  if cursor >= top + LIST_ROWS then top = cursor - LIST_ROWS + 1 end
end

local function new_key(a)
  if a == "back" then
    new_name = new_name:sub(1, -2)
  elseif a == "enter" then
    create()
  elseif a == "space" or a == "tab" then
    say("no spaces: use _ or -", 3, 2)
  elseif #a == 1 and valid_name_char(a) then
    if #new_name < NAME_MAX then new_name = new_name .. a end
  else
    say("only letters, digits, _ and -", 3, 2)
  end
end

local function update_new(tx, ty, pressed)
  if pressed and ty < kb.y then
    if tx >= 160 then
      if button_at(tx - 160, 2) == 1 then create() else mode = "list" end
    end
    return
  end
  local a = kb.update(tx, ty, pressed)
  if a then new_key(a) end
  if btnp("a") then create()
  elseif btnp("b") then mode = "list"
  elseif btnp("x") then kb.toggle_layer() end
end

-- --- drawing ------------------------------------------------------------------

-- Splits text into lines of at most 'cols' characters, at spaces if it can
local function wrap(s, cols)
  local lines = {}
  for para in (s .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      while utf8.len(word) and utf8.len(word) > cols do
        if line ~= "" then lines[#lines + 1] = line; line = "" end
        local cut = utf8.offset(word, cols + 1)
        lines[#lines + 1] = word:sub(1, cut - 1)
        word = word:sub(cut)
      end
      if line == "" then line = word
      elseif utf8.len(line) + 1 + utf8.len(word) <= cols then line = line .. " " .. word
      else lines[#lines + 1] = line; line = word end
    end
    lines[#lines + 1] = line
  end
  return lines
end

local function header(title, right)
  rectfill(0, 0, 256, 12, 8)
  text(title, 4, 2, 4)
  if right then text(right, 252 - textw(right), 2, 13) end
end

local function draw_message()
  if msg then
    rectfill(0, 136, 256, 12, 0)
    text(msg, 4, 138, msg_col)
  end
end

local function draw_top_list()
  local n = #items - 1
  header("LiteLua", n == 1 and "1 cart" or n .. " carts")
  local it = items[cursor]
  local y = 22
  text(it.title or it.name, 4, y, 12)
  y = y + 12
  local m = manifest(it)
  if m then
    local by = {}
    if type(m.author) == "string" and m.author ~= "" then by[#by + 1] = "by " .. m.author end
    if type(m.version) == "string" and m.version ~= "" then by[#by + 1] = "v" .. m.version end
    if #by > 0 then text(table.concat(by, "  "), 4, y, 13); y = y + 12 end
    if type(m.desc) == "string" then
      y = y + 2
      for i, line in ipairs(wrap(m.desc, COLS)) do
        if i > 7 then break end
        text(line, 4, y, 13)
        y = y + 10
      end
    end
  elseif it.error then
    for i, line in ipairs(wrap(it.error, COLS)) do
      if i > 6 then break end
      text(line, 4, y, 2)
      y = y + 10
    end
  end
  local where
  if it.demo then where = "built into LiteLua"
  elseif it.lcart then where = "carts/" .. it.name .. " (read only)"
  else where = "carts/" .. it.name end
  text(where, 4, 122, 14)

  if n == 0 then text("No carts yet: X makes a new game", 4, 100, 4) end
  draw_message()
  text("A: play  Y: edit code  X: new game", 4, 152, 13)
  text("In a game, hold START: pause menu", 4, 164, 14)
  text("L+R+B: back here at once", 4, 174, 14)
  text("Hold L+R+START: quit LiteLua", 4, 184, 14)
end

local function draw_bottom_list()
  for i = 0, LIST_ROWS - 1 do
    local it = items[top + i]
    if not it then break end
    local y = i * ROW_H
    local sel = top + i == cursor
    if sel then rectfill(0, y, 256, ROW_H, 9) end
    local col = it.error and 2 or it.demo and 13 or 12
    text(it.title or it.name, 6, y + 2, sel and 12 or col)
    if it.lcart then text("lcart", 250 - textw("lcart"), y + 2, sel and 12 or 14) end
  end
  if top > 1 then text("^", 248, 0, 13) end
  if top + LIST_ROWS <= #items then text("v", 248, 150, 13) end

  local w = 256 // #LIST_BUTTONS
  for i, b in ipairs(LIST_BUTTONS) do
    local x = (i - 1) * w
    rectfill(x + 2, BAR_Y, w - 4, BAR_H, 15)
    text(b[1], x + (w - textw(b[1])) // 2, BAR_Y + 9, 12)
  end
end

local function draw_top_new()
  header("New game")
  text("Name of the game folder in litelua/carts:", 4, 24, 13)
  text("letters, digits, _ and - (up to " .. NAME_MAX .. ")", 4, 36, 13)
  text("The game starts from a small example and", 4, 60, 14)
  text("opens in the code editor.", 4, 70, 14)
  draw_message()
  text("A or OK: make it  B or Back: cancel", 4, 172, 13)
  text("X: letters / symbols", 4, 184, 14)
end

local function draw_bottom_new()
  rectfill(0, 0, 256, kb.y, 15)
  rectfill(4, 6, 152, 18, 0)
  text(new_name .. "_", 8, 11, 12)
  for i, label in ipairs(NEW_BUTTONS) do
    local x = 160 + (i - 1) * 48
    rectfill(x + 2, 4, 44, 22, i == 1 and 6 or 14)
    text(label, x + (48 - textw(label)) // 2, 11, 12)
  end
  kb.draw()
end

-- --- callbacks ----------------------------------------------------------------

function _init()
  load_items(read_last())
end

function _update()
  poll_buttons()
  local tx, ty, pressed = read_touch()
  if msg then
    msg_frames = msg_frames - 1
    if msg_frames <= 0 then msg = nil end
  end
  if mode == "list" then update_list(tx, ty, pressed)
  else update_new(tx, ty, pressed) end
end

function _draw(screen)
  cls(0)
  if mode == "list" then
    if screen == TOP then draw_top_list() else draw_bottom_list() end
  else
    if screen == TOP then draw_top_new() else draw_bottom_new() end
  end
end
