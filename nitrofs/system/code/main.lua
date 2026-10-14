-- LiteLua code editor: system cart @code (P11, D42).
-- Top screen: the code. Bottom screen: toolbar, messages and the keyboard.
-- Buttons: d-pad moves the cursor (L held: select, R: page / line start and
-- end), A new line, B backspace, Y undo (R+Y redo), X letters/symbols,
-- Y+left/right switch the tab of an open file, Y+B close it (P11d),
-- R+A the first suggestion of the bar above the keyboard (P11a),
-- SELECT files, START help.

local Buffer = require("buffer")
local lexer = require("lexer")
local kb = require("keyboard")
local help = require("help")
local suggest = require("suggest")
local themes = require("themes")

local S = sys.system
local COLS, ROWS = 42, 23     -- Code rows below the status bar
local TOOL_H = 14

-- --- state -------------------------------------------------------------------

local cart, info              -- Cart being edited and its description
local buffers, order = {}, {} -- Open files by path, in the order opened
local buf                     -- Current buffer
local mode = "carts"          -- code | files | carts | prompt | error | help
local help_from               -- Mode to go back to from the help
local settings = { theme = themes.default } -- save/settings.lua (D46)
local theme = themes.get(settings.theme)
local msg, msg_col = "", 13
local frame = 0
local clipboard = ""
local err_line                -- Line of the last error in the current file

local msg_frame = -1000         -- Frame of the last message

local function say(s, col)
  msg, msg_col, msg_frame = s, col or 13, frame
  log("code: " .. s)
end

-- --- files -------------------------------------------------------------------

-- Open files are tabs (P11d, D47): at most MAX_TABS; opening one more
-- closes the saved tab used longest ago (an unsaved one never closes itself)
local MAX_TABS = 5
local use_count = 0

local function use(b)
  use_count = use_count + 1
  b.used = use_count
end

local function make_room()
  if #order < MAX_TABS then return true end
  local oldest
  for i, p in ipairs(order) do
    local b = buffers[p]
    if not b.dirty and b ~= buf and (not oldest or b.used < buffers[order[oldest]].used) then
      oldest = i
    end
  end
  if not oldest then
    say("5 files with unsaved changes: save first", 3)
    return false
  end
  buffers[order[oldest]] = nil
  table.remove(order, oldest)
  return true
end

local function open_file(path)
  if buffers[path] then
    buf = buffers[path]
  else
    local text, e = S.read(cart, path)
    if not text then
      say(e, 2)
      return false
    end
    if not make_room() then return false end
    text = text:gsub("^\239\187\191", "") -- UTF-8 byte order mark
    buf = Buffer.new(path, text)
    buffers[path] = buf
    order[#order + 1] = path
    -- The tabs are on the top screen, which is not a touch screen
    if #order == 2 then say("2 files open: Y+left/right switches, Y+B closes", 4) end
  end
  use(buf)
  err_line = nil
  mode = "code"
  return true
end

-- Next (dir 1) or previous (-1) tab
local function switch_tab(dir)
  if #order < 2 then say("one file open: SELECT opens more"); return end
  local cur = 1
  for i, p in ipairs(order) do
    if buffers[p] == buf then cur = i end
  end
  buf = buffers[order[(cur - 1 + dir) % #order + 1]]
  use(buf)
  err_line = nil
end

local function check(b)
  if not b.path:match("%.lua$") then return true end
  local f, e = load(table.concat(b.lines, "\n"), "@" .. b.path)
  if f then return true end
  return false, e
end

-- Saves the changed buffers; returns false if one could not be saved
-- words.lua is reloaded when it is saved (D46); load_words is defined below
local WORDS = "words.lua"
local load_words

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
      if path == WORDS then load_words() end
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

-- --- words.lua: the cart's own words for the suggestions (D46) -------------

local words = {}              -- Entries of words.lua: "name" or { name, sig, desc }

local function load_data(src, name)
  local f = src and load(src, "=" .. name, "t", {})
  if not f then return nil end
  local ok, t = pcall(f)
  return ok and type(t) == "table" and t or nil
end

function load_words()
  words = {}
  local src = S.read(cart, WORDS)
  if src then
    local t = load_data(src, WORDS)
    if t then
      words = t
    else
      say(WORDS .. " is not a list of words", 3)
    end
  end
  suggest.set_words(words)
end

local function words_text(list)
  local out = {
    "-- Words for the suggestions of the code editor (D46): \"name\" or",
    "-- { name = \"spawn\", sig = \"spawn(x, y)\", desc = \"...\" }.",
    "-- Word+ in the help adds a line before the last } (nothing else changes).",
    "return {",
  }
  for _, w in ipairs(list) do
    if type(w) == "string" then
      out[#out + 1] = ("  %q,"):format(w)
    elseif type(w) == "table" and w.name then
      local parts = { ("name = %q"):format(w.name) }
      if w.sig then parts[#parts + 1] = ("sig = %q"):format(w.sig) end
      if w.desc then parts[#parts + 1] = ("desc = %q"):format(w.desc) end
      out[#out + 1] = "  { " .. table.concat(parts, ", ") .. " },"
    end
  end
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

-- Adds word w to the text of words.lua as a new line before the closing }
-- of the returned table, leaving everything else (comments too) as it is.
-- Returns the new text, or nil when the file does not end with }.
local function append_word(src, w)
  local head, tail = src:match("^(.*)}(%s*)$")
  if not head then return nil end
  -- The last thing before } outside comments: a separator is needed unless
  -- it is { , or ;
  local code = head:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
  local last = code:match("(%S)%s*$")
  local sep = (last == "{" or last == "," or last == ";") and "" or ", "
  if not head:match("\n%s*$") then head = head .. "\n" end
  return head .. ("  %s%q,\n"):format(sep, w) .. "}" .. tail
end

local function load_settings()
  local f = io.open("save/settings.lua")
  if f then
    local t = load_data(f:read("a"), "settings.lua")
    f:close()
    if t then
      for k, v in pairs(t) do settings[k] = v end
    end
  end
  theme = themes.get(settings.theme)
end

local function save_settings()
  local f = io.open("save/settings.lua", "w")
  if not f then say("cannot save the settings", 2); return end
  f:write(("return { theme = %q }\n"):format(settings.theme))
  f:close()
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
  load_words()
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

local function item_path(item)
  return list.dir == "" and item.name or list.dir .. "/" .. item.name
end

local function start_prompt(what)
  if not info.writable then
    say("read only cart", 3)
    return
  end
  prompt.what = what
  if what == "rename" then
    local item = list.items[list.cursor]
    if not item or item.up then say("choose a file or folder first", 3); return end
    prompt.from = item_path(item)
    prompt.text = prompt.from
    -- Cursor before the extension
    prompt.pos = #prompt.text - #(prompt.text:match("%.[^./]*$") or "")
  else
    prompt.text = list.dir == "" and "" or list.dir .. "/"
    if what == "file" then prompt.text = prompt.text .. ".lua" end
    prompt.pos = #prompt.text - (what == "file" and 4 or 0)
  end
  mode = "prompt"
end

-- Open buffers follow a renamed file or folder
local function rename_buffers(from, to)
  for i, p in ipairs(order) do
    local np
    if p == from then np = to
    elseif p:sub(1, #from + 1) == from .. "/" then np = to .. p:sub(#from + 1) end
    if np then
      local b = buffers[p]
      buffers[p], buffers[np], order[i], b.path = nil, b, np, np
    end
  end
end

-- Open buffers of a deleted file are dropped (unsaved changes too)
local function drop_buffer(path)
  for i, p in ipairs(order) do
    if p == path then
      if buffers[p] == buf then buf = nil end
      buffers[p] = nil
      table.remove(order, i)
      break
    end
  end
  if not buf and order[1] then buf = buffers[order[1]] end
end

local function finish_prompt()
  local path = prompt.text
  if path == "" then mode = "files"; return end
  local ok, e
  if prompt.what == "rename" then
    if path == prompt.from then mode = "files"; return end
    ok, e = S.rename(cart, prompt.from, path)
    if ok then
      rename_buffers(prompt.from, path)
      say("renamed to " .. path, 6)
      open_dir(path:match("^(.*)/[^/]*$") or "")
    else
      say(e, 2)
      mode = "files"
    end
    return
  elseif prompt.what == "dir" then
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
  local t = { "v2", cart, buf and buf.path or "" }
  for _, p in ipairs(order) do
    local b = buffers[p]
    t[#t + 1] = ("%s\t%d\t%d\t%d"):format(p, b.cy, b.cx, b.top)
  end
  return table.concat(t, "\n")
end

local function restore(data)
  local lines = {}
  for l in data:gmatch("[^\n]+") do lines[#lines + 1] = l end
  -- v1: the current file first; v2: the current file, then the tabs in order
  local v2 = lines[1] == "v2"
  if not (v2 or lines[1] == "v1") or not lines[2] then return false end
  if not open_cart(lines[2]) then return false end
  local current = v2 and lines[3]
  local first, cur
  for i = v2 and 4 or 3, #lines do
    local p, y, x, top = lines[i]:match("^(.-)\t(%d+)\t(%d+)\t(%d+)$")
    if p and open_file(p) then
      local y2 = math.min(tonumber(y), #buf.lines)
      buf:set_cursor(y2, math.min(tonumber(x), #buf.lines[y2]))
      buf.top = math.min(tonumber(top), #buf.lines)
      first = first or buf
      if p == current then cur = buf end
    end
  end
  buf = cur or first
  if buf then use(buf); mode = "code" end
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

-- --- suggestions (P11a) ----------------------------------------------------

-- The bar between the toolbar and the keyboard: names to complete the word
-- before the cursor, or the signature of the function being called
local BAR_Y, BAR_H = TOOL_H + 1, 15
local bar = { key = nil, list = nil, pre = 0, sig = nil, arg = 0, page = 1,
              boxes = {} }
local scan = { b = nil, ver = -1, cy = 0 }

local function update_bar()
  local b = buf
  -- Names from the code: rescanned when the cursor leaves an edited line
  if scan.b ~= b or (scan.ver ~= b.ver and scan.cy ~= b.cy) then
    suggest.scan(b)
    scan.b, scan.ver, scan.cy = b, b.ver, b.cy
  end
  if scan.ver == b.ver then scan.cy = b.cy end
  local key = tostring(b) .. ":" .. b.ver .. ":" .. b.cy .. ":" .. b.cx
  if bar.key == key then return end
  bar.key, bar.page = key, 1
  bar.list, bar.pre = suggest.query(b)
  bar.sig, bar.arg = nil, 0
  if not bar.list then bar.sig, bar.arg = suggest.signature(b) end
end

local function accept(name)
  if not info.writable then say("read only cart", 3); return end
  buf:insert(name:sub(bar.pre + 1))
  suggest.chosen(name)
  bar.key = nil
end

-- Boxes of the current page: { x1, x2, name } and the arrow (more pages)
local function layout_bar()
  local boxes, x = {}, 0
  local list = bar.list or {}
  local i = 1
  -- Skip the names of earlier pages
  for _ = 2, bar.page do
    local px = 0
    while list[i] and px + #list[i] * 6 + 8 <= 240 do
      px = px + #list[i] * 6 + 8
      i = i + 1
    end
  end
  while list[i] and x + #list[i] * 6 + 8 <= 240 do
    local w = #list[i] * 6 + 8
    boxes[#boxes + 1] = { x, x + w, list[i] }
    x = x + w
    i = i + 1
  end
  bar.more = list[i] ~= nil or bar.page > 1
  bar.boxes = boxes
end

local function bar_tap(tx)
  if tx >= 240 and bar.more then
    local had = #bar.boxes
    bar.page = bar.page + 1
    layout_bar()
    if #bar.boxes == 0 or had == 0 then bar.page = 1 end
    return
  end
  for _, bx in ipairs(bar.boxes) do
    if tx >= bx[1] and tx < bx[2] then accept(bx[3]); return end
  end
end

local function draw_bar()
  -- A new message is shown for 2 seconds, then the bar comes back
  if frame - msg_frame < 60 or not (bar.list or bar.sig) then
    bar.boxes, bar.more = {}, false
    text(msg:sub(1, COLS), 1, BAR_Y + 4, msg_col)
  elseif bar.list then
    layout_bar()
    for i, bx in ipairs(bar.boxes) do
      rectfill(bx[1] + 1, BAR_Y + 1, bx[2] - bx[1] - 2, BAR_H - 2, i == 1 and bar.page == 1 and 9 or 15)
      text(bx[3], bx[1] + 4, BAR_Y + 4, 12)
    end
    if bar.more then
      rectfill(241, BAR_Y + 1, 14, BAR_H - 2, 14)
      text(">", 245, BAR_Y + 4, 12)
    end
  elseif bar.sig then
    local s = bar.sig:sub(1, COLS)
    text(s, 1, BAR_Y + 4, 13)
    local a1, a2 = suggest.arg_range(bar.sig, bar.arg)
    if a1 and a1 <= COLS then
      text(bar.sig:sub(a1, math.min(a2, COLS)), 1 + (a1 - 1) * 6, BAR_Y + 4, 4)
    end
  end
end

-- --- toolbar -----------------------------------------------------------------

local tools = {}
local function tool_list()
  if mode == "code" then
    return { "Files", "Save", "Run", "Check", "Undo", "Cut", "Copy", "Paste" }
  elseif mode == "files" then
    return { "Code", "File+", "Dir+", "Ren", "Del", "Carts", "Run", "Help" }
  elseif mode == "carts" then
    return { "Code", "Help" }
  elseif mode == "help" then
    return help.toolbar()
  elseif mode == "options" then
    return { "OK", "Back" }
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
actions.Ren = function() start_prompt("rename") end

-- Del asks first: the second touch within 3 seconds deletes
local del_path, del_frame
function actions.Del()
  if not info.writable then say("read only cart", 3); return end
  local item = list.items[list.cursor]
  if not item or item.up then say("choose a file or folder first", 3); return end
  local path = item_path(item)
  if del_path ~= path or frame - del_frame > 90 then
    del_path, del_frame = path, frame
    say("touch Del again to delete " .. path, 3)
    return
  end
  del_path = nil
  local ok, e = S.remove(cart, path)
  if not ok then say(e, 2); return end
  drop_buffer(path)
  say("deleted " .. path, 6)
  local cur = list.cursor
  open_dir(list.dir)
  list.cursor = math.max(1, math.min(cur, #list.items))
end

-- Word under the cursor ("sys.run", "rectfill") or the selected word, for
-- the help and Word+
local function word_at_cursor()
  if mode ~= "code" or not buf then return nil end
  local sel = buf:copy()
  if sel and sel:match("^[%a_][%w_%.]*$") then return sel end
  local line, x = buf.lines[buf.cy], buf.cx
  local s, e = x + 1, x
  while s > 1 and line:sub(s - 1, s - 1):match("[%w_.]") do s = s - 1 end
  while e < #line and line:sub(e + 1, e + 1):match("[%w_.]") do e = e + 1 end
  local w = line:sub(s, e):gsub("^%.+", ""):gsub("%.+$", "")
  return w
end

local help_word -- Word under the cursor when the help was opened

function actions.Help()
  local from = mode
  if mode == "help" then return end
  help_word = word_at_cursor()
  local found = help.open(S, help_word)
  help_from, mode = from, "help"
  if help_word and help_word:match("^[%a_]") and not found then
    say("'" .. help_word .. "' is not in the API; Word+ adds it", 13)
  end
end

local function has_word_in(list, w)
  for _, e in ipairs(list) do
    if e == w or (type(e) == "table" and e.name == w) then return true end
  end
  return false
end

local function has_word(w) return has_word_in(words, w) end

-- Word+: adds the word under the cursor to the cart's words.lua (D46)
local function add_word()
  local w = help_word
  if not w or not w:match("^[%a_][%w_%.]*$") then
    say("put the cursor on a name in the code first", 3)
    return
  end
  if not info.writable then say("read only cart", 3); return end
  if has_word(w) then say(w .. " is already in " .. WORDS, 13); return end
  if buffers[WORDS] and buffers[WORDS].dirty then
    say("save " .. WORDS .. " first", 3)
    return
  end
  -- A new file gets the header; an existing one only gets one more line
  local src = S.read(cart, WORDS)
  local text = src and append_word(src, w) or words_text({ w })
  local t = text and load_data(text, WORDS)
  if not (t and has_word_in(t, w)) then
    say(WORDS .. ": cannot add, the file must end with }", 2)
    return
  end
  local ok, e = S.write(cart, WORDS, text)
  if not ok then say(e, 2); return end
  if buffers[WORDS] then drop_buffer(WORDS) end
  load_words()
  say("added " .. w .. " to " .. WORDS, 6)
end

-- --- options (D46) -------------------------------------------------------------

local opts = { cursor = 1, preview = nil }
local SAMPLE = [[
-- Theme preview
local speed = 2.5

function _update()
  if btn("left") then
    x = x - speed -- move
  end
end

function _draw(s)
  cls(1)
  text("Score: " .. score, 2, 2)
end]]

local function open_options()
  opts.preview = opts.preview or Buffer.new("theme preview", SAMPLE)
  opts.preview:set_cursor(5, 4)
  for i, t in ipairs(themes.list) do
    if t.id == settings.theme then opts.cursor = i end
  end
  mode = "options"
end

local function choose_theme(i)
  opts.cursor = i
  theme = themes.list[i]
end

local function confirm_theme()
  settings.theme = themes.list[opts.cursor].id
  save_settings()
  say("theme: " .. themes.list[opts.cursor].name, 6)
  mode = "help"
end

local function cancel_options()
  theme = themes.get(settings.theme)
  mode = "help"
end
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

-- Y is also a modifier (P11d): Y+left/right switch tabs, Y+B closes the
-- tab, so undo (R+Y: redo) happens when Y is released without them
local y_used = false
local close_path -- Unsaved tab waiting for a second Y+B

local function close_tab()
  local p = buf.path
  if buf.dirty and close_path ~= p then
    close_path = p
    say(p .. " not saved: Y+B again closes it", 3)
    return
  end
  close_path = nil
  drop_buffer(p)
  say("closed " .. p)
  if buf then use(buf) else open_dir(list.dir or "") end
end

local function update_code()
  local L, R = btn("l"), btn("r")
  if L and R then return end -- System combinations (L+R+B, ...)
  local b = buf
  local up, down, left, right = rep("up"), rep("down"), rep("left"), rep("right")
  if btnp("y") then y_used = false end
  if btn("y") then
    if left or right then
      switch_tab(left and -1 or 1)
      y_used = true
    end
    if btnp("b") then
      close_tab()
      y_used = true
    end
    return
  end
  if btnr("y") and not y_used then
    if R then
      if not b:redo_step() then say("nothing to redo") end
    else
      actions.Undo()
    end
  end
  if R then
    if up then b:vertical(-ROWS, L) end
    if down then b:vertical(ROWS, L) end
    if left then b:home(L) end
    if right then b:line_end(L) end
  else
    if up then b:vertical(-1, L) end
    if down then b:vertical(1, L) end
    if left then b:left(L) end
    if right then b:right(L) end
  end
  if rep("b") then key_action("back") end
  if R and btnp("a") then
    if bar.list and bar.list[1] then accept(bar.list[1]) else say("no suggestion", 3) end
  elseif not R and rep("a") then
    key_action("enter")
  end
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

  if mode == "options" then
    if pressed and ty < TOOL_H then
      if tool_at(tx) == "OK" then confirm_theme() else cancel_options() end
    else
      local n = #themes.list
      if rep("up") and opts.cursor > 1 then choose_theme(opts.cursor - 1) end
      if rep("down") and opts.cursor < n then choose_theme(opts.cursor + 1) end
      if pressed and ty >= LIST_Y then
        local i = (ty - LIST_Y) // ROW_H
        if themes.list[i] then
          if i == opts.cursor then confirm_theme() else choose_theme(i) end
        end
      end
      if btnp("a") then confirm_theme()
      elseif btnp("b") or btnp("start") then cancel_options() end
    end
    if mode ~= "options" then
      for b, n in pairs(held) do if n > 0 then held[b] = -math.huge end end
    end
    return
  end

  local help_result, help_text
  if pressed and ty < TOOL_H then
    local name = tool_at(tx)
    if mode == "help" then
      help_result, help_text = help.tool(name)
    elseif actions[name] then
      actions[name]()
      return
    end
  elseif mode == "help" then
    help_result, help_text = help.update(repeated, pressed and tx, pressed and ty)
  elseif btnp("start") then
    actions.Help()
    return
  end
  if help_result == "close" then
    mode = help_from or (buf and "code" or "carts")
  elseif help_result == "copy" then
    clipboard = help_text
    say("example copied: Paste puts it in the code", 6)
  elseif help_result == "none" then
    say("no example here", 3)
  elseif help_result == "word" then
    add_word()
  elseif help_result == "opts" then
    open_options()
    return
  end

  if mode == "help" then
    -- Handled above
  elseif mode == "code" and pressed and ty < kb.y then
    bar_tap(tx)
    update_code()
  elseif mode == "code" or mode == "prompt" then
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

-- Lexer color -> class name, for the theme
local class_of = {}
for k, v in pairs(lexer.colors) do class_of[v] = k end

-- Tabs of the open files in the status bar (P11d): names without folders,
-- shortened to fit, the current one on the code background
local function draw_tabs(width)
  local th = theme
  local n = #order
  local cols = width // 6
  local each = math.max(3, cols // n - 1)
  local x = 0
  for _, p in ipairs(order) do
    local b = buffers[p]
    local name = p:match("[^/]+$") .. (b.dirty and "*" or "")
    if #name > each then name = name:sub(1, each - 1) .. "~" end
    local w = #name * 6 + 4
    if b == buf then rectfill(x, 0, w, 8, th.bg) end
    text(name, x + 2, 0, b == buf and th.status_fg or th.pos_fg)
    x = x + w + 2
    if x > width then break end
  end
end

local function draw_code(b)
  b = b or buf
  local th = theme
  local g = gutter_cols(b)
  local code_x = g * 6
  local code_cols = COLS - g
  follow(b, code_cols)

  -- Background, gutter, status bar
  rectfill(0, 8, 256, 184, th.bg)
  rectfill(0, 8, code_x - 2, 184, th.gutter_bg)
  rectfill(0, 0, 256, 8, th.status_bg)
  local pos = ("%d:%d"):format(b.cy, b:dcol(b.cy, b.cx) + 1)
  local pos_x = 256 - #pos * 6 - 1
  if b == buf and #order > 1 then
    draw_tabs(pos_x - 4)
  else
    text(b.path .. (b.dirty and "*" or ""), 1, 0, th.status_fg)
  end
  text(pos, pos_x, 0, th.pos_fg)

  -- Current line, error line, selection
  local cr = b.cy - b.top
  local function row_y(y) return 8 + (y - b.top) * 8 end
  local el = b == buf and err_line
  if el and el >= b.top and el < b.top + ROWS then
    rectfill(0, row_y(el), 256, 8, th.err_bg)
  end
  rectfill(code_x, 8 + cr * 8, 256 - code_x, 8, th.line_bg)
  local y1, x1, y2, x2 = b:sel()
  if y1 then
    for y = math.max(y1, b.top), math.min(y2, b.top + ROWS - 1) do
      local d1 = y == y1 and b:dcol(y, x1) or 0
      local d2 = y == y2 and b:dcol(y, x2) or b:dcol(y, #b.lines[y]) + 1
      local sx = code_x + (d1 - b.scroll_x) * 6
      local w = (d2 - d1) * 6
      if sx < code_x then w, sx = w - (code_x - sx), code_x end
      if w > 0 then rectfill(sx, row_y(y), w, 8, th.sel_bg) end
    end
  end

  -- Line numbers
  local nums = {}
  for r = 0, ROWS - 1 do
    local y = b.top + r
    if y > #b.lines then break end
    nums[#nums + 1] = ("%" .. (g - 1) .. "d"):format(y)
  end
  text(table.concat(nums, "\n"), 0, 8, th.gutter_fg)

  -- Code
  clip(code_x, 8, 256 - code_x, 184)
  -- The layer strings start at column b.scroll_x
  for _, l in ipairs(layers(b, code_cols)) do
    text(l[2], code_x, 8, th.syntax[class_of[l[1]]] or l[1])
  end

  -- Cursor
  if frame % 30 < 20 then
    local cx = code_x + (b:dcol(b.cy, b.cx) - b.scroll_x) * 6
    rectfill(cx, 8 + cr * 8, 1, 8, th.cursor)
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
    text("Ren / Del: rename / delete the chosen", 4, 54, 13)
    text("START or Help: how to use, the API", 4, 64, 13)
  end
  text("In the code: d-pad cursor, L+d-pad select", 4, 120, 14)
  text("R+up/down page, R+left/right line ends", 4, 130, 14)
  text("A new line, B backspace, X symbols", 4, 140, 14)
  text("Y undo, R+Y redo, SELECT files, START help", 4, 150, 14)
  text("Run saves all files and starts the game;", 4, 164, 14)
  text("leaving it comes back here.", 4, 174, 14)
end

local function draw_prompt_top()
  rectfill(0, 0, 256, 10, 8)
  text(prompt.what == "dir" and "New folder" or prompt.what == "rename"
       and "Rename " .. prompt.from or "New file", 2, 1, 12)
  text(prompt.text, 4, 30, 12)
  if frame % 30 < 20 then rectfill(4 + prompt.pos * 6, 30, 1, 8, 4) end
  text("Enter or OK: " .. (prompt.what == "rename" and "rename" or "create")
       .. ", Cancel: back", 4, 50, 13)
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
  if mode == "options" then
    text("Color theme of the code", 1, LIST_Y - 1, 13)
    for i, t in ipairs(themes.list) do
      local y = LIST_Y + i * ROW_H
      if i == opts.cursor then rectfill(0, y, 256, ROW_H, 9) end
      text(t.name .. (t.id == settings.theme and "  (saved)" or ""), 4, y + 2, 12)
    end
    text("Up/down: preview  A or OK: keep", 1, 160, 13)
    text("B or Back: cancel", 1, 170, 13)
    text(msg:sub(1, COLS), 1, 184, msg_col)
  elseif mode == "help" then
    help.draw_bottom()
    text(msg:sub(1, COLS), 1, 184, msg_col)
  elseif mode == "code" then
    update_bar()
    draw_bar()
    kb.draw()
  elseif mode == "prompt" then
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
    elseif mode == "help" then help.draw_top()
    elseif mode == "options" then draw_code(opts.preview)
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
  load_settings()
  suggest.init(help.load(S) or {})
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
