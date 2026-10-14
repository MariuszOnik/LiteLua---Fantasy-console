-- LiteLua API documentation: map (tile maps, P8).
-- Format: see docs/api/README.md.
return {
  module = "map",
  title = "Tile maps",
  summary = "Levels made of tiles: map/<name>.lua files (written by hand or "
         .. "converted from Tiled), drawn by the engine, with tile flags for "
         .. "collisions. Tile coordinates start at 0.",
  since = "P8",
  entries = {
    {
      name = "tilemap", kind = "function",
      sig = "tilemap(name) -> map",
      args = { { "name", "string", "file map/<name>.lua of the cart" } },
      ret = { { "map", "the map; its tiles live in the engine" } },
      desc = "Loads a map. The file is data (nothing in it runs): tile (8, 16 "
          .. "or 32 pixels), up to 4 layers, each with a tileset (an image in "
          .. "gfx/, cut into tiles) and its tiles as text rows with a legend or "
          .. "as numbers, and flags for collisions. Tile 0 is empty; tile n is "
          .. "frame n - 1 of the tileset. See README, \"Tile maps\".",
      example = [[
level = tilemap("level1")
print(level.w, level.h, level.tile)]],
    },
    {
      name = "map:draw", kind = "function",
      sig = "map:draw([layer])",
      args = { { "layer", "string | integer", "one layer (name or number), default: all" } },
      desc = "Draws the tiles you can see, in the order of the layers. Works "
          .. "with camera (also zoom), clip, alpha and tint. Draw a layer "
          .. "after the sprites to put it in front of them.",
      example = [[
camera(camx, 0)
level:draw("back")
level:draw("main")
spr(hero, x, y)
level:draw("front")]],
    },
    {
      name = "map:get", kind = "function",
      sig = "map:get(tx, ty, [layer]) -> id",
      args = {
        { "tx", "integer", "tile column (0 = left)" }, { "ty", "integer", "tile row (0 = top)" },
        { "layer", "string | integer", "default: the layer \"main\", or the first" },
      },
      ret = { { "integer", "tile id; 0 = empty, also outside the map" } },
      desc = "The tile at a tile position.",
      example = [[
local tx, ty = level:cell(x, y + 16)
if level:get(tx, ty) == 0 then fall() end]],
    },
    {
      name = "map:set", kind = "function",
      sig = "map:set(tx, ty, id, [layer])",
      args = { { "id", "integer", "new tile, 0 = empty" } },
      desc = "Changes a tile, e.g. a collected coin or a broken block. Outside "
          .. "the map nothing happens. The file is not changed.",
      example = [[
local cx, cy = level:hit(x, y, 16, 16, "coin")
if cx then level:set(cx, cy, 0); coins = coins + 1 end]],
    },
    {
      name = "map:cell", kind = "function",
      sig = "map:cell(px, py) -> tx, ty",
      desc = "The tile position under a pixel position.",
      example = [[
local tx, ty = level:cell(x + 8, y + 15)]],
    },
    {
      name = "map:hit", kind = "function",
      sig = "map:hit(x, y, w, h, [flag], [layer]) -> tx, ty | nil",
      args = {
        { "x, y, w, h", "number", "rectangle in pixels (a hit box)" },
        { "flag", "string", "tile flag, default \"solid\"" },
        { "layer", "string | integer", "default: the layer \"main\", or the first" },
      },
      ret = { { "integer", "position of the first such tile, or nil" } },
      desc = "Is there a tile with the flag under the rectangle? The core of "
          .. "collisions: move, test, and step back or stop. A map without "
          .. "flags counts every tile that is not 0.",
      example = [[
if level:hit(x + dx, y, 12, 16) then
  dx = 0  -- a wall
end
x = x + dx]],
    },
    {
      name = "map:flag", kind = "function",
      sig = "map:flag(id, name) -> boolean",
      desc = "Does tile id have the flag?",
      example = [[
if level:flag(level:get(tx, ty), "ladder") then climb() end]],
    },
    {
      name = "map:find", kind = "function",
      sig = "map:find(id, [layer]) -> list",
      ret = { { "table", "array of { x =, y = } tile positions" } },
      desc = "All places of a tile, e.g. to put enemies where the map has "
          .. "marker tiles (then remove the markers with set).",
      example = [[
for _, p in ipairs(level:find(20)) do
  add_enemy(p.x * 16, p.y * 16)
  level:set(p.x, p.y, 0)
end]],
    },
    {
      name = "map.w", kind = "field", type = "integer",
      sig = "map.w, map.h, map.tile, map.layers",
      desc = "Width and height in tiles, tile size in pixels, and the list of "
          .. "layer names.",
      example = [[
local world_w = level.w * level.tile]],
    },
  },
}
