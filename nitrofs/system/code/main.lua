-- LiteLua code editor: system cart @code (P11, D42).
-- Top screen: the code. Bottom screen: toolbar, messages and the keyboard.
-- Buttons: d-pad moves the cursor (L held: select, R: page / line start and
-- end), A new line, B backspace, Y undo (R+Y redo), X letters/symbols,
-- SELECT files.

local Buffer = require("buffer")
local lexer = require("lexer")
local kb = require("keyboard")

local S = sys.system
local COLS, ROWS = 42, 23     -- Code rows below the status bar
local TOOL_H = 14

-- --- state -------------------------------------------------------------------

local cart, info              -- Cart being edited and its description
local buffers, order = {}, {} -- Open files by path, in the order opened
local buf                     -- Current buffer
local mode = "carts"          -- code | files | carts | prompt | error
local msg, msg_col = "", 13
local frame = 0
local clipboard = ""
local err_line                -- Line of the last error in the current file

local function say(s, col)
  msg, msg_col = s, col or 13
  log("code: " .. s)
end

-- --- files -------------------------------------------------------------------

local function open_file(path)
  if buffers[path] then
    buf = buffers[path]
  else
    local text, e = S.read(cart, path)
    if not text then
      say(e, 2)
      return false
    end
    text = text:gsub("^\239\187\191", "") -- UTF-8 byte order mark
    buf = Buffer.new(path, text)
    buffers[path] = buf
    order[#order + 1] = path
  end
  err_line = nil
  mode = "code"
  return true
end

local function check(b)
  if not b.path:match("%.lua$") then return true end
  local f, e = load(table.concat(b.lines, "\n"), "@" .. b.path)
  if f then return true end
  return false, e
end

-- Saves the changed buffers; returns false if one could not be saved
local function save_all()
  if not info.writable then return true end
  for _, path in ipairs(order) do
    local b = buffers[path]
    if b.dirty then
      local ok, e = S.write(cart, path, b:text())
      if not ok then
        say(e, 2)
        return false
      end
      b.dirty = false
    end
  end
  return true
end

-- Position of "file:line:" in an error message (D13)
local function error_place(s)
  local file, line = s:match("^([^:\n]+):(%d+):")
  return file, tonumber(line)
end

local function goto_error(e)
  local file, line = error_place(e)
  if file and (buffers[file] or S.read(cart, file)) then
    open_file(file)
    buf:go_line(line)
    err_line = line
  end
  say(e:match("^[^\n]*"), 2)
end

-- --- the files list and the carts list ---------------------------------------

local list = { items = {}, cursor = 1, top = 1, dir = "" }
local LIST_Y, ROW_H, LIST_ROWS = 16, 11, 15

local function open_dir(dir)
  local files, e = S.files(cart, dir)
  if not files then
    say(e, 2)
    return
  end
  list.dir, list.items, list.cursor, list.top = dir, {}, 1, 1
  if dir ~= "" then list.items[1] = { name = "..", dir = true, up = true } end
  for _, f in ipairs(files) do list.items[#list.items + 1] = f end
  mode = "files"
end

local function open_cart(name, path)
  local i, e = S.cart(name)
  if not i then
    say(e, 2)
    return false
  end
  cart, info = name, i
  buffers, order, buf = {}, {}, nil
  list.dir = ""
  if i.error then say(i.error, 2) end
  if not path or not open_file(path) then open_dir("") end
  if not i.writable then say(name .. ": read only", 3) end
  return true
end

local function show_carts()
  list.items, list.cursor, list.top = {}, 1, 1
  for _, c in ipairs(S.carts()) do list.items[#list.items + 1] = c end
  mode = "carts"
end

local function list_choose()
  local item = list.items[list.cursor]
  if not item then return end
  if mode == "carts" then
    open_cart(item.name, item.entry or "main.lua")
  elseif item.up then
    open_dir(list.dir:match("^(.*)/[^/]*$") or "")
  elseif item.dir then
    open_dir(list.dir == "" and item.name or list.dir .. "/" .. item.name)
  else
    open_file(list.dir == "" and item.name or list.dir .. "/" .. item.name)
  end
end

-- --- prompt (new file / folder name) -----------------------------------------

local prompt = { text = "", what = "file" }

local function start_prompt(what)
  if not info.writable then
    say("read only cart", 3)
    return
  end
  prompt.text = list.dir == "" and "" or list.dir .. "/"
  prompt.what = what
  if what == "file" then prompt.text = prompt.text .. ".lua" end
  prompt.pos = #prompt.text - (what == "file" and 4 or 0)
  mode = "prompt"
end

local function finish_prompt()
  local path = prompt.text
  if path == "" then mode = "files"; return end
  local ok, e
  if prompt.what == "dir" then
    ok, e = S.mkdir(cart, path)
  elseif S.read(cart, path) then
    ok, e = false, path .. " exists"
  else
    ok, e = S.write(cart, path, "")
  end
  if not ok then
    say(e, 2)
    mode = "files"
    return
  end
  if prompt.what == "dir" then
    say("folder " .. path, 6)
    open_dir(path)
  else
    say("new " .. path, 6)
    open_file(path)
  end
end

local function prompt_key(a)
  local t, p = prompt.text, prompt.pos
  if a == "back" then
    if p > 0 then prompt.text, prompt.pos = t:sub(1, p - 1) .. t:sub(p + 1), p - 1 end
  elseif a == "enter" then
    finish_prompt()
  elseif a == "space" or a == "tab" then
    return
  elseif #a >= 1 then
    prompt.text, prompt.pos = t:sub(1, p) .. a .. t:sub(p + 1), p + #a
  end
end

-- --- error panel (after a game error, D13) -----------------------------------

local panel = { lines = {}, frames = {} }

local function show_error_panel(e)
  panel.lines, panel.frames = {}, {}
  for l in (e .. "\n"):gmatch("(.-)\n") do
    l = l:gsub("\t", "  ")
    panel.lines[#panel.lines + 1] = l
    local f, n = l:match("^%s*([^:%s]+):(%d+):")
    panel.frames[#panel.lines] = f and { f, tonumber(n) } or false
  end
  mode = "error"
end

-- --- running the game --------------------------------------------------------

local function state_data()
  local t = { "v1", cart }
  for i = #order, 1, -1 do
    local p = order[i]
    if buffers[p] == buf then table.remove(order, i); table.insert(order, 1, p) end
  end
  for _, p in ipairs(order) do
    local b = buffers[p]
    t[#t + 1] = ("%s\t%d\t%d\t%d"):format(p, b.cy, b.cx, b.top)
  end
  return table.concat(t, "\n")
end

local function restore(data)
  local lines = {}
  for l in data:gmatch("[^\n]+") do lines[#lines + 1] = l end
  if lines[1] ~= "v1" or not lines[2] then return false end
  if not open_cart(lines[2]) then return false end
  local first
  for i = #lines, 3, -1 do
    local p, y, x, top = lines[i]:match("^(.-)\t(%d+)\t(%d+)\t(%d+)$")
    if p and open_file(p) then
      local y2 = math.min(tonumber(y), #buf.lines)
      buf:set_cursor(y2, math.min(tonumber(x), #buf.lines[y2]))
      buf.top = math.min(tonumber(top), #buf.lines)
      first = buf
    end
  end
  if first then buf = first; mode = "code" end
  return true
end

local function run_game()
  if not save_all() then return end
  if buf then
    local ok, e = check(buf)
    if not ok then log("code: running with a syntax error: " .. e) end
  end
  say("running " .. cart)
  sys.system.run(cart, state_data())
end

-- --- toolbar -----------------------------------------------------------------

local tools = {}
local function tool_list()
  if mode == "code" then
    return { "Files", "Save", "Run", "Check", "Undo", "Cut", "Copy", "Paste" }
  elseif mode == "files" then
    return { "Code", "File+", "Dir+", "Carts", "Run" }
  elseif mode == "carts" then
    return { "Code" }
  elseif mode == "prompt" then
    return { "OK", "Cancel" }
  else
    return { "Close" }
  end
end

local actions = {}

function actions.Files() open_dir(list.dir or "") end
function actions.Code()
  if buf then mode = "code" else say("no file open", 3) end
end
function actions.Save()
  if not info.writable then say("read only cart", 3); return end
  if not buf.dirty then say("no changes") end
  if save_all() then
    local ok, e = check(buf)
    if ok then say("saved " .. buf.path, 6) else say("saved, but: " .. e, 3) end
  end
end
actions.Run = run_game
function actions.Check()
  local ok, e = check(buf)
  if ok then say("no syntax errors", 6) else goto_error(e) end
end
function actions.Undo()
  if not buf:undo_step() then say("nothing to undo") end
end
function actions.Cut()
  local t = buf:cut()
  if t then clipboard = t; say("cut " .. #t .. " bytes") else say("select with L + d-pad") end
end
function actions.Copy()
  local t = buf:copy()
  if t then clipboard = t; say("copied " .. #t .. " bytes") else say("select with L + d-pad") end
end
function actions.Paste()
  if clipboard == "" then say("clipboard is empty"); return end
  if not info.writable then say("read only cart", 3); return end
  buf:insert(clipboard, "paste")
end
actions["File+"] = function() start_prompt("file") end
actions["Dir+"] = function() start_prompt("dir") end
actions.Carts = show_carts
actions.OK = finish_prompt
function actions.Cancel() mode = "files" end
function actions.Close() mode = buf and "code" or "files" end

local function tool_at(tx)
  local names = tool_list()
  local w = 256 // #names
  return names[math.min(#names, tx // w + 1)]
end

-- --- input -------------------------------------------------------------------

-- Buttons with auto repeat, updated every frame in every mode, so a
-- button that switched the mode does not act again in the new one
local held, repeated = {}, {}
local function poll_buttons()
  for _, b in ipairs({ "up", "down", "left", "right", "a", "b" }) do
    local n = btn(b) and (held[b] or 0) + 1 or 0
    held[b] = n
    repeated[b] = n == 1 or (n > 10 and n % 2 == 0)
  end
end
local function rep(b) return repeated[b] end

-- The first sample after the stylus touches the screen is often off by a
-- few pixels, so a press counts from the second frame of a touch (or at
-- the release of a one-frame tap, with its position)
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

local function key_action(a)
  if mode == "prompt" then return prompt_key(a) end
  if mode ~= "code" then return end
  if not info.writable then say("read only cart", 3); return end
  if a == "back" then buf:backspace()
  elseif a == "enter" then buf:newline()
  elseif a == "tab" then buf:insert("  ")
  elseif a == "space" then buf:insert(" ")
  else buf:insert(a) end
  err_line = nil
end

local function update_code()
  local L, R = btn("l"), btn("r")
  if L and R then return end -- System combinations (L+R+B, ...)
  local b = buf
  local up, down, left, right = rep("up"), rep("down"), rep("left"), rep("right")
  if R then
    if up then b:vertical(-ROWS, L) end
    if down then b:vertical(ROWS, L) end
    if left then b:home(L) end
    if right then b:line_end(L) end
    if btnp("y") and not b:redo_step() then say("nothing to redo") end
  else
    if up then b:vertical(-1, L) end
    if down then b:vertical(1, L) end
    if left then b:left(L) end
    if right then b:right(L) end
    if btnp("y") then actions.Undo() end
  end
  if rep("b") then key_action("back") end
  if rep("a") then key_action("enter") end
  if btnp("x") then kb.toggle_layer() end
  if btnp("select") then actions.Files() end
end

local function update_list()
  local n = #list.items
  if rep("up") and list.cursor > 1 then list.cursor = list.cursor - 1 end
  if rep("down") and list.cursor < n then list.cursor = list.cursor + 1 end
  if btnp("a") then list_choose() return end
  if btnp("b") then
    if mode == "files" and list.dir ~= "" then
      open_dir(list.dir:match("^(.*)/[^/]*$") or "")
    elseif buf then
      mode = "code"
    end
  end
  if btnp("select") and buf then mode = "code" end
end

function _update()
  frame = frame + 1
  poll_buttons()
  local entered = mode
  local tx, ty, pressed = read_touch()

  if pressed and ty < TOOL_H then
    local name = tool_at(tx)
    if actions[name] then actions[name]() end
    return
  end

  if mode == "code" or mode == "prompt" then
    local a = kb.update(tx, ty, pressed)
    if a then key_action(a) end
    if mode == "code" then update_code() end
    if mode == "prompt" and btnp("b") then prompt_key("back") end
  elseif mode == "files" or mode == "carts" then
    if pressed and ty >= LIST_Y then
      local i = list.top + (ty - LIST_Y) // ROW_H
      if list.items[i] then
        if i == list.cursor then list_choose() else list.cursor = i end
      end
    end
    update_list()
  elseif mode == "error" then
    if pressed and ty >= LIST_Y then
      local i = (ty - LIST_Y) // 9 + 1
      local f = panel.frames[i]
      if f and (buffers[f[1]] or S.read(cart, f[1])) then
        open_file(f[1])
        buf:go_line(f[2])
        err_line = f[2]
      end
    end
    if btnp("a") or btnp("b") then actions.Close() end
  end

  -- Buttons that changed the mode stay quiet until released
  if mode ~= entered then
    for b, n in pairs(held) do
      if n > 0 then held[b] = -math.huge end
    end
  end

  if list.cursor < list.top then list.top = list.cursor end
  if list.cursor >= list.top + LIST_ROWS then list.top = list.cursor - LIST_ROWS + 1 end
end

-- --- drawing -----------------------------------------------------------------

local function gutter_cols(b)
  return #tostring(#b.lines) + 1
end

-- Keeps the cursor on the screen
local function follow(b, code_cols)
  if b.cy < b.top then b.top = b.cy end
  if b.cy >= b.top + ROWS then b.top = b.cy - ROWS + 1 end
  local d = b:dcol(b.cy, b.cx)
  if d < b.scroll_x then b.scroll_x = math.max(0, d - 8) end
  if d >= b.scroll_x + code_cols then b.scroll_x = d - code_cols + 8 end
end

-- One string per color for the visible lines: text() skips spaces, so the
-- layers drawn over each other need one call per color (cached while
-- nothing changes)
local cache = {}
local function layers(b, code_cols)
  if cache.b == b and cache.ver == b.ver and cache.top == b.top
     and cache.scroll_x == b.scroll_x then
    return cache.layers
  end
  local out = {}
  local last = b.scroll_x + code_cols
  for r = 0, ROWS - 1 do
    local y = b.top + r
    if y > #b.lines then break end
    local p = b:pieces(y)
    local col_at = {}
    for i = 1, #p, 3 do
      local d, s, c = p[i], p[i + 1], p[i + 2]
      if d >= last then break end
      local l = out[c]
      if not l then l = {}; out[c] = l end
      local row = l[r + 1]
      if not row then row = {}; l[r + 1] = row; col_at[c] = b.scroll_x end
      local at = col_at[c]
      local n = lexer.width(d, s)
      if n > b.scroll_x then
        if d < b.scroll_x then
          -- Cut the part left of the screen (whole characters)
          local skip = b.scroll_x - d
          s = s:sub((utf8.offset(s, skip + 1) or #s + 1))
          d = b.scroll_x
        end
        if d > at then row[#row + 1] = (" "):rep(d - at) end
        row[#row + 1] = s
        col_at[c] = n
      end
    end
  end
  local result = {}
  for c, rows in pairs(out) do
    local t = {}
    for r = 1, ROWS do t[r] = rows[r] and table.concat(rows[r]) or "" end
    result[#result + 1] = { c, table.concat(t, "\n") }
  end
  cache = { b = b, ver = b.ver, top = b.top, scroll_x = b.scroll_x, layers = result }
  return result
end

local function draw_code()
  local b = buf
  local g = gutter_cols(b)
  local code_x = g * 6
  local code_cols = COLS - g
  follow(b, code_cols)

  -- Status bar
  rectfill(0, 0, 256, 8, 8)
  local name = b.path .. (b.dirty and "*" or "")
  local pos = ("%d:%d"):format(b.cy, b:dcol(b.cy, b.cx) + 1)
  text(name, 1, 0, 12)
  text(pos, 256 - #pos * 6 - 1, 0, 13)

  -- Current line, error line, selection
  local cr = b.cy - b.top
  local function row_y(y) return 8 + (y - b.top) * 8 end
  if err_line and err_line >= b.top and err_line < b.top + ROWS then
    rectfill(0, row_y(err_line), 256, 8, 1)
  end
  rectfill(code_x, 8 + cr * 8, 256 - code_x, 8, 15)
  local y1, x1, y2, x2 = b:sel()
  if y1 then
    for y = math.max(y1, b.top), math.min(y2, b.top + ROWS - 1) do
      local d1 = y == y1 and b:dcol(y, x1) or 0
      local d2 = y == y2 and b:dcol(y, x2) or b:dcol(y, #b.lines[y]) + 1
      local sx = code_x + (d1 - b.scroll_x) * 6
      local w = (d2 - d1) * 6
      if sx < code_x then w, sx = w - (code_x - sx), code_x end
      if w > 0 then rectfill(sx, row_y(y), w, 8, 9) end
    end
  end

  -- Line numbers
  local nums = {}
  for r = 0, ROWS - 1 do
    local y = b.top + r
    if y > #b.lines then break end
    nums[#nums + 1] = ("%" .. (g - 1) .. "d"):format(y)
  end
  text(table.concat(nums, "\n"), 0, 8, 14)

  -- Code
  clip(code_x, 8, 256 - code_x, 184)
  -- The layer strings start at column b.scroll_x
  for _, l in ipairs(layers(b, code_cols)) do
    text(l[2], code_x, 8, l[1])
  end

  -- Cursor
  if frame % 30 < 20 then
    local cx = code_x + (b:dcol(b.cy, b.cx) - b.scroll_x) * 6
    rectfill(cx, 8 + cr * 8, 1, 8, 4)
  end
  clip()
end

local function draw_list_top()
  rectfill(0, 0, 256, 10, 8)
  if mode == "carts" then
    text("LiteLua code editor: choose a cart", 2, 1, 12)
    local c = list.items[list.cursor]
    if c then
      text(c.title or c.name, 4, 24, 12)
      text(c.name .. (c.lcart and "  (.lcart, read only)" or ""), 4, 34, 13)
      if c.error then text(c.error, 4, 48, 2) end
    end
  else
    text(cart .. "/" .. list.dir, 2, 1, 12)
    if not info.writable then text("read only", 196, 1, 3) end
    text("Open a file: touch it twice or A", 4, 24, 13)
    text("B: up a folder / back to the code", 4, 34, 13)
    text("File+ / Dir+: new file or folder", 4, 44, 13)
  end
  text("In the code: d-pad cursor, L+d-pad select", 4, 120, 14)
  text("R+up/down page, R+left/right line ends", 4, 130, 14)
  text("A new line, B backspace, X symbols", 4, 140, 14)
  text("Y undo, R+Y redo, SELECT files", 4, 150, 14)
  text("Run saves all files and starts the game;", 4, 164, 14)
  text("leaving it comes back here.", 4, 174, 14)
end

local function draw_prompt_top()
  rectfill(0, 0, 256, 10, 8)
  text(prompt.what == "dir" and "New folder" or "New file", 2, 1, 12)
  text(prompt.text, 4, 30, 12)
  if frame % 30 < 20 then rectfill(4 + prompt.pos * 6, 30, 1, 8, 4) end
  text("Enter or OK: create, Cancel: back", 4, 50, 13)
end

local function draw_toolbar()
  local names = tool_list()
  local w = 256 // #names
  for i, n in ipairs(names) do
    local x = (i - 1) * w
    rectfill(x + 1, 1, w - 2, TOOL_H - 2, 8)
    text(n, x + (w - textw(n)) // 2, 4, 12)
  end
end

local function draw_bottom()
  draw_toolbar()
  if mode == "code" or mode == "prompt" then
    text(msg:sub(1, COLS), 1, 18, msg_col)
    kb.draw()
  elseif mode == "files" or mode == "carts" then
    for r = 0, LIST_ROWS - 1 do
      local i = list.top + r
      local item = list.items[i]
      if not item then break end
      local y = LIST_Y + r * ROW_H
      if i == list.cursor then rectfill(0, y, 256, ROW_H, 9) end
      local label = mode == "carts" and (item.title or item.name)
        or item.name .. (item.dir and not item.up and "/" or "")
      local col = (mode == "carts" and item.error) and 2 or item.dir and 11 or 12
      if mode == "files" and buffers[(list.dir == "" and "" or list.dir .. "/") .. item.name]
         and buffers[(list.dir == "" and "" or list.dir .. "/") .. item.name].dirty then
        label = label .. "*"
      end
      text(label, 4, y + 2, col)
    end
    if #list.items == 0 then text("(empty)", 4, LIST_Y + 2, 14) end
    text(msg:sub(1, COLS), 1, 184, msg_col)
  else
    for i, l in ipairs(panel.lines) do
      local y = LIST_Y + (i - 1) * 9
      if y > 182 then break end
      text(l:sub(1, COLS), 1, y, panel.frames[i] and 11 or (i == 1 and 2 or 13))
    end
  end
end

function _draw(screen)
  cls(0)
  if screen == TOP then
    if mode == "code" then draw_code()
    elseif mode == "prompt" then draw_prompt_top()
    elseif mode == "error" then
      if buf then draw_code() else draw_list_top() end
    else draw_list_top() end
  else
    draw_bottom()
  end
end

-- --- start -------------------------------------------------------------------

local function load_clipboard()
  local f = io.open("save/clipboard.txt")
  if f then clipboard = f:read("a") or ""; f:close() end
end

function _quit()
  if clipboard ~= "" then
    local f = io.open("save/clipboard.txt", "w")
    if f then f:write(clipboard); f:close() end
  end
end

function _init()
  load_clipboard()
  local st = S.start
  if st.data then restore(st.data) end
  if st.reason == "edit" and st.cart then
    open_cart(st.cart, (S.cart(st.cart) or {}).entry or "main.lua")
  elseif st.reason == "error" and st.cart then
    if not cart or cart ~= st.cart then open_cart(st.cart) end
    goto_error(st.error)
    show_error_panel(st.error)
  elseif st.reason == "exit" and cart then
    say("back from " .. cart)
  end
  if not cart then show_carts() end
end
