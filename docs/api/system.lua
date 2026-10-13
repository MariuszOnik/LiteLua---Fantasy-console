-- LiteLua API documentation: sys.system (system carts only).
-- Format: see docs/api/README.md.
return {
  module = "system",
  title = "System carts",
  summary = "Extra functions of the built-in system carts (the code editor). "
         .. "Games do not have sys.system.",
  since = "P11",
  entries = {
    {
      name = "sys.system.start", kind = "table",
      sig = "sys.system.start -> table",
      desc = "Why the system cart was started. Fields: reason (\"run\": "
          .. "sys.run(\"@code\"), \"edit\": Y on the cart list, \"exit\": the "
          .. "game started with sys.system.run has ended, \"error\": Y on the "
          .. "error screen), cart (name of the game), data (the string given "
          .. "to sys.system.run), error (the message with the stack traceback).",
      example = [[
local st = sys.system.start
if st.reason == "error" then show(st.error) end]],
    },
    {
      name = "sys.system.carts", kind = "function",
      sig = "sys.system.carts() -> list",
      ret = { { "table", "array of cart descriptions" } },
      desc = "The carts in litelua/carts, sorted. Each is a table: name, title, "
          .. "id, entry (from cart.lua), lcart (a .lcart file), system, "
          .. "writable (a folder on the SD card), error (cart.lua is broken; "
          .. "the files can still be read and written).",
      example = [[
for _, c in ipairs(sys.system.carts()) do
  print(c.name, c.title or c.error)
end]],
    },
    {
      name = "sys.system.cart", kind = "function",
      sig = "sys.system.cart(name) -> table | nil, err",
      args = { { "name", "string", "cart name, \"@code\" for a system cart" } },
      ret = { { "table", "description like in sys.system.carts" } },
      desc = "Describes one cart.",
      example = [[
local c = sys.system.cart("mygame")
if c and not c.writable then print("read only") end]],
    },
    {
      name = "sys.system.files", kind = "function",
      sig = "sys.system.files(cart, [dir]) -> list | nil, err",
      args = {
        { "cart", "string", "cart name" },
        { "dir", "string", "folder in the cart, default: the top" },
      },
      ret = { { "table", "array of { name = \"x.lua\", dir = true | nil }" } },
      desc = "Lists a folder of a cart (also of a .lcart): folders first, then "
          .. "files, sorted by name. Names starting with a dot are left out.",
      example = [[
for _, f in ipairs(sys.system.files("mygame", "src")) do
  print(f.name, f.dir and "folder" or "")
end]],
    },
    {
      name = "sys.system.read", kind = "function",
      sig = "sys.system.read(cart, path) -> s | nil, err",
      args = { { "cart", "string", "cart name" }, { "path", "string", "file in the cart" } },
      ret = { { "string", "the whole file" } },
      desc = "Reads a file of any cart, also of a .lcart or a system cart.",
      example = [[
local src = sys.system.read("mygame", "main.lua")]],
    },
    {
      name = "sys.system.write", kind = "function",
      sig = "sys.system.write(cart, path, s) -> true | nil, err",
      args = {
        { "cart", "string", "cart name" }, { "path", "string", "file in the cart" },
        { "s", "string", "new contents" },
      },
      desc = "Writes a file of a cart folder on the SD card (.lcart files and "
          .. "system carts are read only). Safe: the data goes to <file>.new "
          .. "first and replaces the file only when it was written completely. "
          .. "The folder must exist.",
      example = [[
local ok, err = sys.system.write("mygame", "src/util.lua", text)
if not ok then print(err) end]],
    },
    {
      name = "sys.system.mkdir", kind = "function",
      sig = "sys.system.mkdir(cart, path) -> true | nil, err",
      args = { { "cart", "string", "cart name" }, { "path", "string", "new folder" } },
      desc = "Creates a folder in a cart folder on the SD card (succeeds if it "
          .. "exists).",
      example = [[
sys.system.mkdir("mygame", "src")]],
    },
    {
      name = "sys.system.remove", kind = "function",
      sig = "sys.system.remove(cart, path) -> true | nil, err",
      args = { { "cart", "string", "cart name" }, { "path", "string", "file or folder" } },
      desc = "Deletes a file, or a folder if it is empty, in a cart folder on "
          .. "the SD card. There is no undo.",
      example = [[
local ok, err = sys.system.remove("mygame", "src/old.lua")]],
    },
    {
      name = "sys.system.rename", kind = "function",
      sig = "sys.system.rename(cart, from, to) -> true | nil, err",
      args = {
        { "cart", "string", "cart name" }, { "from", "string", "file or folder" },
        { "to", "string", "new path (may be in another folder)" },
      },
      desc = "Renames or moves a file or folder in a cart folder on the SD "
          .. "card. An error if 'to' exists.",
      example = [[
sys.system.rename("mygame", "src/a.lua", "src/enemy.lua")]],
    },
    {
      name = "sys.system.run", kind = "function",
      sig = "sys.system.run(cart, [data])",
      args = {
        { "cart", "string", "game to run" },
        { "data", "string", "anything up to 64 KB, given back later" },
      },
      desc = "Runs a game when the current callback returns, like sys.run. When "
          .. "the game ends (L+R+B, sys.exit, SELECT on the error screen), "
          .. "this system cart starts again with sys.system.start.reason = "
          .. "\"exit\" and the data, so it can go back to where it was. Y on the "
          .. "error screen opens the code editor with reason \"error\".",
      example = [[
sys.system.run("mygame", "main.lua:12")]],
    },
  },
}
