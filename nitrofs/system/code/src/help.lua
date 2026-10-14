-- Help of the code editor (START): how to use the editor and the API
-- reference. The API comes from docs/api/*.lua (D12), copied into the ROM
-- as api/*.lua by build.ps1, so it always matches docs/API.md.

local M = {}

local COLS, ROWS = 42, 23
local LIST_Y, ROW_H, LIST_ROWS = 24, 11, 15 -- List below its title line

-- Order of the modules; others follow by name
local ORDER = { core = 1, gfx = 2, input = 3, sound = 4, files = 5, sys = 6, lua = 7,
                system = 8 }

local MANUAL = [[
LiteLua code editor

Top screen: the code. Bottom: buttons, a
message line and the keyboard. "sym"
switches to Lua symbols, "shf" is Shift
(tap twice: Caps Lock).

Buttons
  d-pad        move the cursor
  L + d-pad    select text
  R + up/down  page up/down
  R + l/r      line start/end
  A            new line (keeps indent)
  B            backspace
  Y / R+Y      undo / redo
  X            letters / symbols
  SELECT       files of the cart
  START        this help; on a name
               from the API: its page
  R + A        take the first suggestion

Suggestions
  The bar above the keyboard shows names
  that start with the word you type: the
  API, Lua keywords and names from your
  code (after "x." the fields of x).
  Touch one to put it in, ">" shows more.
  Inside f( ) the bar shows how to call
  f, the current argument in yellow.

Your own words
  words.lua in the cart lists more words
  for the suggestions: "name" or
  { name = "f", sig = "f(x)", desc = "" }
  START on a name in your code, then
  Word+ adds it to words.lua.

Options (Opts in this help)
  The color theme of the code: Soft
  dark, Light (Notepad++) or Classic.

Touch buttons
  Files  files and folders of the cart
  Save   save the changed files
  Run    save all and run the game;
         leaving it comes back here
  Check  syntax check without running
  Undo, Cut, Copy, Paste

Files view
  touch twice or A: open, B: up
  File+ / Dir+: new file or folder
  Ren: rename the chosen file/folder
  Del: delete it (touch Del twice;
       folders only when empty)
  Carts: edit another cartridge

Errors
  Y on the error screen of a game opens
  the editor at the line of the error.
  Touch a line of the stack traceback
  to go there.

Help
  Up/down choose, A open, B back,
  left/right scroll this page.
  "Copy ex" copies the example to the
  clipboard: Paste puts it in the code.]]

M.active = false
local S
local topics            -- { {title, summary, entries | manual} }
local level = "topics"  -- topics | entries
local topic             -- Chosen topic in level "entries"
local cursor, top = 1, 1
local scroll = 0
local detail, detail_key

-- Splits text into lines of at most 'cols' columns at spaces
local function wrap(s, cols, out, col, indent)
  indent = indent or ""
  for para in (s .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line ~= "" and utf8.len(line) + 1 + utf8.len(word) > cols then
        out[#out + 1] = { line, col }
        line = indent .. word
      else
        line = line == "" and word or line .. " " .. word
      end
    end
    out[#out + 1] = { line, col }
  end
end

local function load_topics()
  topics = { { title = "Editor", summary = "How to use the code editor",
               manual = true } }
  local files = S.files("@code", "api") or {}
  local mods = {}
  for _, f in ipairs(files) do
    if f.name:match("%.lua$") then
      local src = S.read("@code", "api/" .. f.name)
      local fn = src and load(src, "=" .. f.name, "t", {})
      local ok, t = false, nil
      if fn then ok, t = pcall(fn) end
      if ok and type(t) == "table" and t.entries then mods[#mods + 1] = t end
    end
  end
  table.sort(mods, function(a, b)
    local oa, ob = ORDER[a.module] or 99, ORDER[b.module] or 99
    if oa ~= ob then return oa < ob end
    return a.module < b.module
  end)
  M.modules = mods
  for _, m in ipairs(mods) do
    topics[#topics + 1] = { title = m.title or m.module, summary = m.summary or "",
                            entries = m.entries }
  end
end

local function items()
  if level == "topics" then return topics end
  return topic.entries
end

-- Lines of the page shown on the top screen
local function page()
  local list = items()
  local it = list[cursor]
  local key = level .. tostring(it)
  if detail_key == key then return detail end
  local out = {}
  if level == "topics" then
    if it.manual then
      for l in (MANUAL .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = { l, #out == 0 and 4 or 12 }
      end
    else
      out[1] = { it.title, 4 }
      out[2] = { "", 12 }
      wrap(it.summary, COLS, out, 12)
      out[#out + 1] = { "", 12 }
      out[#out + 1] = { #it.entries .. " entries: A to open the list", 13 }
    end
  else
    wrap(it.sig or it.name, COLS, out, 4, "  ")
    out[#out + 1] = { "", 12 }
    if it.args then
      for _, a in ipairs(it.args) do
        wrap(a[1] .. " (" .. a[2] .. "): " .. a[3], COLS, out, 11, "  ")
      end
    end
    if it.ret then
      for _, r in ipairs(it.ret) do
        wrap("-> " .. r[1] .. ": " .. r[2], COLS, out, 11, "  ")
      end
    end
    if it.args or it.ret then out[#out + 1] = { "", 12 } end
    if it.desc then wrap(it.desc, COLS, out, 12) end
    if it.example then
      out[#out + 1] = { "", 12 }
      out[#out + 1] = { "Example:", 13 }
      for l in (it.example .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = { l, 5 }
      end
    end
  end
  detail, detail_key, scroll = out, key, 0
  return out
end

-- Reads the API documentation once; returns the modules (also used by the
-- suggestions)
function M.load(sys_system)
  S = sys_system
  if not topics then load_topics() end
  return M.modules
end

-- Opens the help; 'word' (a name under the cursor) jumps to its entry
function M.open(sys_system, word)
  M.load(sys_system)
  M.active = true
  level, cursor, top = "topics", 1, 1
  if word and word ~= "" then
    for _, t in ipairs(topics) do
      for i, e in ipairs(t.entries or {}) do
        if e.name == word or e.name:match("[^%.]+$") == word and not word:find("%.") then
          level, topic, cursor = "entries", t, i
          return true
        end
      end
    end
  end
  return false
end

function M.toolbar()
  return { "Back", "Copy ex", "Word+", "Opts", "Close" }
end

-- Returns "close", or "copy" and the example text, or nil
local function back()
  if level == "entries" then
    for i, t in ipairs(topics) do
      if t == topic then cursor = i end
    end
    level, top = "topics", 1
    return nil
  end
  M.active = false
  return "close"
end

local function choose()
  if level == "topics" and topics[cursor].entries then
    topic, level, cursor, top = topics[cursor], "entries", 1, 1
  end
end

function M.tool(name)
  if name == "Back" then return back() end
  if name == "Close" then M.active = false; return "close" end
  if name == "Word+" then return "word" end
  if name == "Opts" then return "opts" end
  if name == "Copy ex" then
    local it = level == "entries" and topic.entries[cursor]
    if it and it.example then return "copy", it.example end
    return "none"
  end
end

-- One frame of input: rep = auto-repeated buttons, tap = touch position
-- (tx, ty) when the stylus was pressed
function M.update(rep, tx, ty)
  local list = items()
  if rep.up and cursor > 1 then cursor = cursor - 1 end
  if rep.down and cursor < #list then cursor = cursor + 1 end
  local lines = #page()
  if rep.right and scroll + ROWS < lines then scroll = scroll + ROWS - 2 end
  if rep.left and scroll > 0 then scroll = math.max(0, scroll - ROWS + 2) end
  if tx and ty >= LIST_Y then
    local i = top + (ty - LIST_Y) // ROW_H
    if list[i] then
      if i == cursor then choose() else cursor = i end
    end
  end
  if btnp("a") then choose() end
  if btnp("start") then M.active = false; return "close" end
  if btnp("b") then return back() end
  if cursor < top then top = cursor end
  if cursor >= top + LIST_ROWS then top = cursor - LIST_ROWS + 1 end
end

function M.draw_top()
  local p = page()
  for r = 1, ROWS + 1 do
    local l = p[scroll + r]
    if not l then break end
    text(l[1], 1, (r - 1) * 8, l[2])
  end
  if scroll + ROWS + 1 < #p then text(">", 250, 184, 13) end
  if scroll > 0 then text("<", 250, 0, 13) end
end

function M.draw_bottom()
  local list = items()
  local title = level == "topics" and "Help" or "Help: " .. topic.title
  text(title, 1, LIST_Y - 8, 13)
  for r = 0, LIST_ROWS - 1 do
    local i = top + r
    local it = list[i]
    if not it then break end
    local y = LIST_Y + r * ROW_H
    if i == cursor then rectfill(0, y, 256, ROW_H, 9) end
    local label = it.title or it.name
    text(label, 4, y + 2, it.kind == "callback" and 3 or 12)
  end
end

return M
