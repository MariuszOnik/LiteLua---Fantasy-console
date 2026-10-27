-- LiteLua API documentation: map (tile maps, P8).
-- Format: see docs/api/README.md.
return {
  module = "map",
  title = "Tile maps",
  summary = "Levels made of tiles: map/<name>.lua files (written by hand or "
         .. "converted from Tiled), drawn by the engine, with tile flags for "
         .. "collisions. Tile coordinates start at 0. isogrid: isometric "
         .. "ground with hills (D58).",
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
    {
      name = "isogrid", kind = "function",
      sig = "isogrid(img, cols, rows, [opts]) -> grid",
      args = {
        { "img", "image", "frames for the cells (square frames work best)" },
        { "cols", "integer", "cells across (1..1024)" },
        { "rows", "integer", "cells down (1..1024)" },
        { "opts", "table", "w, h: diamond size in pixels (even, default "
          .. "32 x 16); frames: cols * rows frame numbers, row by row (-1 = "
          .. "no cell, default 0); heights: (cols + 1) * (rows + 1) corner "
          .. "heights 0..32767 (default 0); colors: the same corners, colors "
          .. "multiplied with the frames (shading; default: the tint color)" },
      },
      ret = { { "grid", "the grid; its cells live in the engine" } },
      desc = "Isometric ground with hills: every cell is a diamond whose four "
          .. "corners are raised by their heights, drawn in one call (D58). A "
          .. "frame is stretched onto its diamond: its top left corner on the "
          .. "top corner of the cell, top right on the right, bottom right on "
          .. "the bottom, bottom left on the left. So frames are squares "
          .. "\"straightened\" from the diamond: x runs along the columns, y "
          .. "along the rows. Cell (x, y) has the corners (x, y) top, (x+1, y) "
          .. "right, (x+1, y+1) bottom and (x, y+1) left. Grid coordinates "
          .. "start at 0. The DS draws at most 2048 polygons per screen and a "
          .. "cell takes two, so keep about 900 cells or fewer on screen.",
      example = [[
ground = isogrid(image("ground", 16), 20, 20,
  { frames = cells, heights = hills })]],
    },
    {
      name = "grid:draw", kind = "function",
      sig = "grid:draw(x, y, [scale])",
      args = {
        { "x", "number", "world x of the top corner of cell (0, 0)" },
        { "y", "number", "world y of that corner" },
        { "scale", "number", "pixels up per height unit, 0..8, default 1" },
      },
      desc = "Draws the cells you can see, back to front, so a hill in front "
          .. "covers what is behind it. Works with camera (also zoom), clip "
          .. "and alpha. The top corner of cell (x, y) is at x + (x - y) * w / "
          .. "2, y + (x + y) * h / 2 when flat. Each diamond is drawn a pixel "
          .. "bigger on every side so raised cells leave no cracks.",
      example = [[
camera(camx, camy)
ground:draw(0, 0, 0.5)
camera()]],
    },
    {
      name = "grid:frame", kind = "function",
      sig = "grid:frame(x, y, [f]) -> f",
      args = {
        { "x", "integer", "cell column (0 .. cols - 1)" },
        { "y", "integer", "cell row (0 .. rows - 1)" },
        { "f", "integer", "new frame, -1 = no cell" },
      },
      ret = { { "integer", "the frame of the cell" } },
      desc = "Reads or changes the frame of a cell.",
      example = [[
ground:frame(3, 4, ROAD)]],
    },
    {
      name = "grid:height", kind = "function",
      sig = "grid:height(x, y, [h]) -> h",
      args = {
        { "x", "integer", "corner column (0 .. cols)" },
        { "y", "integer", "corner row (0 .. rows)" },
        { "h", "integer", "new height 0..32767" },
      },
      ret = { { "integer", "the height of the corner" } },
      desc = "Reads or changes the height of a corner (the four cells around "
          .. "it bend with it).",
      example = [[
ground:height(5, 5, ground:height(5, 5) + 8)  -- raise a hill]],
    },
    {
      name = "grid:color", kind = "function",
      sig = "grid:color(x, y, [col]) -> col",
      args = {
        { "x", "integer", "corner column (0 .. cols)" },
        { "y", "integer", "corner row (0 .. rows)" },
        { "col", "color", "new color of the corner" },
      },
      ret = { { "integer", "the color of the corner as 0xRRGGBB" } },
      desc = "Reads or changes the color of a corner, multiplied with the "
          .. "frames around it: light and shade on slopes. The first color "
          .. "set on a grid without colors makes all other corners white.",
      example = [[
ground:color(5, 5, 0xc0c0c0)  -- a bit darker]],
    },
    {
      name = "grid.cols", kind = "field", type = "integer",
      sig = "grid.cols, grid.rows, grid.w, grid.h",
      desc = "Cells across and down, and the diamond size in pixels.",
      example = [[
print(ground.cols, ground.rows)]],
    },
  },
}
