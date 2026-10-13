-- Text buffer of the code editor: lines, cursor, selection, undo/redo.
-- Positions are a line number y (1-based) and a byte offset x in the line
-- (0 = before the first byte). The cursor moves over whole UTF-8 characters.

local lexer = require("lexer")
local width = lexer.width

local B = {}
B.__index = B

local UNDO_MAX = 300

local function split(text)
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  return lines
end

function B.new(path, text)
  local crlf = text:find("\r\n", 1, true) ~= nil
  if crlf then text = text:gsub("\r\n", "\n") end
  local b = setmetatable({
    path = path, lines = split(text), crlf = crlf,
    cy = 1, cx = 0, want = 0, top = 1, scroll_x = 0,
    ay = nil, ax = nil,          -- Selection anchor
    undo = {}, redo = {},
    dirty = false, ver = 0,      -- ver changes with every edit (draw cache)
    st = { "" }, st_valid = 1,   -- Lexer state at the start of each line
    tok = {},                    -- Lexed lines (cache)
  }, B)
  return b
end

function B:text()
  local s = table.concat(self.lines, "\n")
  return self.crlf and s:gsub("\n", "\r\n") or s
end

-- --- positions ---------------------------------------------------------------

-- Display column of byte offset x in line y
function B:dcol(y, x)
  return width(0, self.lines[y]:sub(1, x))
end

-- Byte offset in line y closest to display column d (not inside a character)
function B:xfor(y, d)
  local line = self.lines[y]
  local col, x = 0, 0
  while x < #line do
    local nx = utf8.offset(line, 2, x + 1) or #line + 1
    local nc = width(col, line:sub(x + 1, nx - 1))
    if nc > d then break end
    col, x = nc, nx - 1
  end
  return x
end

local function before(y1, x1, y2, x2)
  return y1 < y2 or (y1 == y2 and x1 < x2)
end

-- Selection as y1, x1, y2, x2 (ordered), or nil
function B:sel()
  if not self.ay then return nil end
  local ay, ax, cy, cx = self.ay, self.ax, self.cy, self.cx
  if ay == cy and ax == cx then return nil end
  if before(ay, ax, cy, cx) then return ay, ax, cy, cx end
  return cy, cx, ay, ax
end

function B:get(y1, x1, y2, x2)
  if y1 == y2 then return self.lines[y1]:sub(x1 + 1, x2) end
  local parts = { self.lines[y1]:sub(x1 + 1) }
  for y = y1 + 1, y2 - 1 do parts[#parts + 1] = self.lines[y] end
  parts[#parts + 1] = self.lines[y2]:sub(1, x2)
  return table.concat(parts, "\n")
end

-- End position of 'text' inserted at y, x
local function text_end(y, x, text)
  local nl, last = 0, nil
  for pos in text:gmatch("()\n") do nl, last = nl + 1, pos end
  if nl == 0 then return y, x + #text end
  return y + nl, #text - last
end

-- --- raw edits (no undo) -----------------------------------------------------

function B:touch(y)
  self.ver = self.ver + 1
  self.dirty = true
  if self.st_valid > y then self.st_valid = y end
end

function B:raw_insert(y, x, text)
  self:touch(y)
  local lines = self.lines
  local line = lines[y]
  local head, tail = line:sub(1, x), line:sub(x + 1)
  if not text:find("\n", 1, true) then
    lines[y] = head .. text .. tail
    return y, x + #text
  end
  local parts = split(text)
  lines[y] = head .. parts[1]
  for i = 2, #parts do table.insert(lines, y + i - 1, parts[i]) end
  local ey = y + #parts - 1
  local ex = #lines[ey]
  lines[ey] = lines[ey] .. tail
  return ey, ex
end

function B:raw_delete(y1, x1, y2, x2)
  self:touch(y1)
  local lines = self.lines
  local text = self:get(y1, x1, y2, x2)
  lines[y1] = lines[y1]:sub(1, x1) .. lines[y2]:sub(x2 + 1)
  local n = y2 - y1
  if n > 0 then
    local count = #lines
    table.move(lines, y2 + 1, count, y1 + 1)
    for i = count - n + 1, count do lines[i] = nil end
  end
  return text
end

-- --- edits with undo ---------------------------------------------------------

-- Runs fn as one undo step. Typing ('kind' "type") and deleting with
-- backspace ("back") merge with the step before while the cursor did not
-- move in between.
function B:edit(fn, kind)
  local g = { ops = {}, by = self.cy, bx = self.cx }
  self.group = g
  fn()
  self.group = nil
  if #g.ops == 0 then return end
  self.redo = {}
  g.ay, g.ax = self.cy, self.cx

  local last = self.undo[#self.undo]
  if kind and last and last.kind == kind and last.ay == g.by and last.ax == g.bx
     and #last.ops == 1 and #g.ops == 1 then
    local a, o = last.ops[1], g.ops[1]
    if kind == "type" and a.t == "i" and o.t == "i" then
      a.text = a.text .. o.text
      last.ay, last.ax = g.ay, g.ax
      return
    elseif kind == "back" and a.t == "d" and o.t == "d" then
      a.text = o.text .. a.text
      a.y, a.x = o.y, o.x
      last.ay, last.ax = g.ay, g.ax
      return
    end
  end
  g.kind = kind
  self.undo[#self.undo + 1] = g
  if #self.undo > UNDO_MAX then table.remove(self.undo, 1) end
end

function B:op_insert(y, x, text)
  if text == "" then return y, x end
  self.group.ops[#self.group.ops + 1] = { t = "i", y = y, x = x, text = text }
  return self:raw_insert(y, x, text)
end

function B:op_delete(y1, x1, y2, x2)
  local text = self:raw_delete(y1, x1, y2, x2)
  if text ~= "" then
    self.group.ops[#self.group.ops + 1] = { t = "d", y = y1, x = x1, text = text }
  end
  return text
end

function B:set_cursor(y, x, keep_sel)
  self.cy, self.cx = y, x
  self.want = self:dcol(y, x)
  if not keep_sel then self.ay = nil end
end

-- Deletes the selection inside an edit; true if there was one
function B:delete_sel()
  local y1, x1, y2, x2 = self:sel()
  self.ay = nil
  if not y1 then return false end
  self:op_delete(y1, x1, y2, x2)
  self:set_cursor(y1, x1)
  return true
end

function B:insert(text, kind)
  self:edit(function()
    self:delete_sel()
    local y, x = self:op_insert(self.cy, self.cx, text)
    self:set_cursor(y, x)
  end, (kind or "type") == "type" and not text:find("\n", 1, true) and "type" or nil)
end

-- New line keeping the indentation of the current one
function B:newline()
  local indent = self.lines[self.cy]:match("^[ \t]*")
  if #indent > self.cx then indent = indent:sub(1, self.cx) end
  self:insert("\n" .. indent, "line")
end

function B:backspace()
  self:edit(function()
    if self:delete_sel() then return end
    local y, x = self.cy, self.cx
    if x > 0 then
      local px = utf8.offset(self.lines[y], -1, x + 1) - 1
      self:op_delete(y, px, y, x)
      self:set_cursor(y, px)
    elseif y > 1 then
      local px = #self.lines[y - 1]
      self:op_delete(y - 1, px, y, 0)
      self:set_cursor(y - 1, px)
    end
  end, "back")
end

function B:cut()
  local y1, x1, y2, x2 = self:sel()
  if not y1 then return nil end
  local text = self:get(y1, x1, y2, x2)
  self:edit(function() self:delete_sel() end)
  return text
end

function B:copy()
  local y1, x1, y2, x2 = self:sel()
  return y1 and self:get(y1, x1, y2, x2)
end

local function apply(self, op, undo)
  if (op.t == "i") == undo then
    local ey, ex = text_end(op.y, op.x, op.text)
    self:raw_delete(op.y, op.x, ey, ex)
  else
    self:raw_insert(op.y, op.x, op.text)
  end
end

function B:undo_step()
  local g = table.remove(self.undo)
  if not g then return false end
  for i = #g.ops, 1, -1 do apply(self, g.ops[i], true) end
  self.redo[#self.redo + 1] = g
  self:set_cursor(g.by, g.bx)
  return true
end

function B:redo_step()
  local g = table.remove(self.redo)
  if not g then return false end
  for i = 1, #g.ops do apply(self, g.ops[i], false) end
  self.undo[#self.undo + 1] = g
  self:set_cursor(g.ay, g.ax)
  return true
end

-- --- cursor movement ---------------------------------------------------------

-- 'select': extend the selection (L held) instead of dropping it
local function moving(self, select)
  if select then
    if not self.ay then self.ay, self.ax = self.cy, self.cx end
  else
    self.ay = nil
  end
end

function B:left(select)
  moving(self, select)
  local y, x = self.cy, self.cx
  if x > 0 then
    x = utf8.offset(self.lines[y], -1, x + 1) - 1
  elseif y > 1 then
    y = y - 1
    x = #self.lines[y]
  end
  self.cy, self.cx = y, x
  self.want = self:dcol(y, x)
end

function B:right(select)
  moving(self, select)
  local y, x = self.cy, self.cx
  local line = self.lines[y]
  if x < #line then
    x = (utf8.offset(line, 2, x + 1) or #line + 1) - 1
  elseif y < #self.lines then
    y, x = y + 1, 0
  end
  self.cy, self.cx = y, x
  self.want = self:dcol(y, x)
end

function B:vertical(dy, select)
  moving(self, select)
  local y = math.max(1, math.min(#self.lines, self.cy + dy))
  self.cy = y
  self.cx = self:xfor(y, self.want)
end

function B:home(select)
  moving(self, select)
  local indent = #self.lines[self.cy]:match("^[ \t]*")
  self.cx = self.cx == indent and 0 or indent
  self.want = self:dcol(self.cy, self.cx)
end

function B:line_end(select)
  moving(self, select)
  self.cx = #self.lines[self.cy]
  self.want = self:dcol(self.cy, self.cx)
end

function B:go_line(y)
  y = math.max(1, math.min(#self.lines, y))
  self:set_cursor(y, #self.lines[y]:match("^[ \t]*"))
end

-- --- syntax colors -----------------------------------------------------------

-- Lexer state at the start of line y
function B:state_at(y)
  local st, lines = self.st, self.lines
  for i = self.st_valid, y - 1 do
    st[i + 1] = lexer.end_state(lines[i], st[i])
  end
  if y > self.st_valid then self.st_valid = y end
  return st[y]
end

-- Colored pieces of line y (cached while the line and its state are the same)
function B:pieces(y)
  local st = self:state_at(y)
  local line = self.lines[y]
  local c = self.tok[y]
  if c and c.src == line and c.st == st then return c.list end
  local list = lexer.lex(line, st)
  self.tok[y] = { src = line, st = st, list = list }
  return list
end

return B
