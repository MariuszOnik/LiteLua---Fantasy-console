-- LiteLua API documentation: files (standard Lua functions limited to the
-- cartridge and its save folder).
-- Format: see docs/api/README.md.
return {
  module = "files",
  title = "Files",
  summary = "Reading cartridge files, saving data and loading modules. "
         .. "Paths are relative to the cartridge, \"save/...\" is the save folder.",
  since = "P3",
  entries = {
    {
      name = "io.open", kind = "function",
      sig = "io.open(path [, mode]) -> file",
      args = {
        { "path", "string", "e.g. \"data/level1.txt\" or \"save/game.txt\"" },
        { "mode", "string", "\"r\" (default), \"w\", \"a\", \"r+\"... ; \"b\" is allowed" },
      },
      ret = { { "file", "file handle, or nil and a message if it cannot be opened" } },
      desc = "Opens a file of the cartridge (read only) or, for paths starting "
          .. "with save/, a file in the game's save folder litelua/saves/<id> "
          .. "(read and write). Absolute paths, drives and .. are errors.",
      example = [[
local f = io.open("save/best.txt", "w")
f:write(best)
f:close()]],
    },
    {
      name = "io.lines", kind = "function",
      sig = "io.lines(path, ...) -> iterator",
      args = {
        { "path", "string", "file path, as for io.open" },
        { "...", "string", "read formats, default \"l\" (one line)" },
      },
      desc = "Iterates over the lines of a file and closes it at the end.",
      example = [[
for line in io.lines("data/words.txt") do
  words[#words + 1] = line
end]],
    },
    {
      name = "require", kind = "function",
      sig = "require(name) -> module",
      args = { { "name", "string", "module name, dots become folders" } },
      ret = { { "any", "the value returned by the module file" } },
      desc = "Loads a module once: src/<name>.lua, then lib/<name>.lua of the "
          .. "cartridge, then litelua/lib/<name>.lua shared on the SD card, then "
          .. "the libraries built into LiteLua. \"ai.path\" means ai/path.lua.",
      example = [[
local enemy = require("enemy")
local e = enemy.new(10, 20)]],
    },
    {
      name = "dofile", kind = "function",
      sig = "dofile(path) -> ...",
      args = { { "path", "string", "Lua file of the cartridge" } },
      ret = { { "...", "values returned by the file" } },
      desc = "Runs a Lua file of the cartridge every time it is called. Data "
          .. "files that return a table are a simple way to store levels.",
      example = [[
local level = dofile("data/level1.lua")]],
    },
    {
      name = "loadfile", kind = "function",
      sig = "loadfile(path [, mode [, env]]) -> function",
      args = {
        { "path", "string", "Lua file of the cartridge" },
        { "mode", "string", "ignored, only source code can be loaded" },
        { "env", "table", "environment of the chunk (optional)" },
      },
      ret = { { "function", "the compiled chunk, or nil and a message" } },
      desc = "Compiles a Lua file without running it.",
      example = [[
local chunk = assert(loadfile("data/script.lua"))
chunk()]],
    },
    {
      name = "os.remove", kind = "function",
      sig = "os.remove(path) -> true",
      args = { { "path", "string", "a file in save/" } },
      desc = "Deletes a save file. Only paths in save/ are allowed. "
          .. "os.rename(from, to) works the same way.",
      example = [[
os.remove("save/slot1.txt")]],
    },
  },
}
