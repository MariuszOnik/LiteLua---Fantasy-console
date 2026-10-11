-- LiteLua API documentation: gfx (drawing on the screen).
-- Format: see docs/api/README.md.
return {
  module = "gfx",
  title = "Graphics",
  summary = "Drawing shapes. Call these in _draw; the screen is redrawn every "
         .. "frame. Colors: 0-15 = palette, or 0xRRGGBB.",
  since = "P4",
  entries = {
    {
      name = "cls", kind = "function",
      sig = "cls([col])",
      args = { { "col", "color", "background color, default 0" } },
      desc = "Clears the screen with a color. Also covers everything drawn "
          .. "before it in this frame. Call it first in _draw.",
      example = [[
function _draw(screen)
  cls(1)
end]],
    },
    {
      name = "color", kind = "function",
      sig = "color([col])",
      args = { { "col", "color", "new default color, default 12" } },
      desc = "Sets the color used by drawing functions called without one.",
      example = [[
color(8)
rect(10, 10, 20, 20)]],
    },
    {
      name = "alpha", kind = "function",
      sig = "alpha([a])",
      args = { { "a", "number", "0 (invisible) .. 1 (opaque), default 1" } },
      desc = "Sets the opacity of everything drawn after it. The DS has 32 "
          .. "levels. Call alpha() to go back to opaque.",
      example = [[
alpha(0.5)
circfill(64, 64, 20, 8)
alpha()]],
    },
    {
      name = "camera", kind = "function",
      sig = "camera([x, y])",
      args = {
        { "x", "number", "world x shown at the left edge, default 0" },
        { "y", "number", "world y shown at the top edge, default 0" },
      },
      desc = "Moves the view: x, y is subtracted from all coordinates drawn "
          .. "after it. camera() resets it. Use it to scroll the world and "
          .. "reset it before drawing the HUD.",
      example = [[
camera(player.x - 128, player.y - 96)
draw_world()
camera()
draw_hud()]],
    },
    {
      name = "clip", kind = "function",
      sig = "clip([x, y, w, h])",
      args = {
        { "x", "number", "left edge on the screen" },
        { "y", "number", "top edge on the screen" },
        { "w", "number", "width" },
        { "h", "number", "height" },
      },
      desc = "Draws only inside this screen rectangle (the camera does not "
          .. "move it). clip() draws on the whole screen again.",
      example = [[
clip(8, 8, 100, 50)
draw_map()
clip()]],
    },
    {
      name = "pset", kind = "function",
      sig = "pset(x, y, [col])",
      args = {
        { "x", "number", "x" }, { "y", "number", "y" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws one pixel.",
      example = [[
pset(10, 20, 7)]],
    },
    {
      name = "line", kind = "function",
      sig = "line(x1, y1, x2, y2, [col])",
      args = {
        { "x1", "number", "start x" }, { "y1", "number", "start y" },
        { "x2", "number", "end x" }, { "y2", "number", "end y" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws a line, both end points included.",
      example = [[
line(0, 0, 255, 191, 8)]],
    },
    {
      name = "rect", kind = "function",
      sig = "rect(x, y, w, h, [col])",
      args = {
        { "x", "number", "left" }, { "y", "number", "top" },
        { "w", "number", "width" }, { "h", "number", "height" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws the 1 pixel outline of a rectangle, inside x .. x+w-1, "
          .. "y .. y+h-1. A negative width or height extends left or up.",
      example = [[
rect(10, 10, 32, 16, 12)]],
    },
    {
      name = "rectfill", kind = "function",
      sig = "rectfill(x, y, w, h, [col])",
      args = {
        { "x", "number", "left" }, { "y", "number", "top" },
        { "w", "number", "width" }, { "h", "number", "height" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws a filled rectangle.",
      example = [[
rectfill(0, 180, 256, 12, 0)]],
    },
    {
      name = "circ", kind = "function",
      sig = "circ(x, y, r, [col])",
      args = {
        { "x", "number", "center x" }, { "y", "number", "center y" },
        { "r", "number", "radius" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws the outline of a circle (made of up to 48 lines).",
      example = [[
circ(128, 96, 40, 11)]],
    },
    {
      name = "circfill", kind = "function",
      sig = "circfill(x, y, r, [col])",
      args = {
        { "x", "number", "center x" }, { "y", "number", "center y" },
        { "r", "number", "radius" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws a filled circle.",
      example = [[
circfill(x, y, 4, 8)]],
    },
    {
      name = "tri", kind = "function",
      sig = "tri(x1, y1, x2, y2, x3, y3, [col])",
      args = {
        { "x1", "number", "corner 1 x" }, { "y1", "number", "corner 1 y" },
        { "x2", "number", "corner 2 x" }, { "y2", "number", "corner 2 y" },
        { "x3", "number", "corner 3 x" }, { "y3", "number", "corner 3 y" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws the outline of a triangle.",
      example = [[
tri(10, 10, 50, 10, 30, 40, 9)]],
    },
    {
      name = "trifill", kind = "function",
      sig = "trifill(x1, y1, x2, y2, x3, y3, [col])",
      args = {
        { "x1", "number", "corner 1 x" }, { "y1", "number", "corner 1 y" },
        { "x2", "number", "corner 2 x" }, { "y2", "number", "corner 2 y" },
        { "x3", "number", "corner 3 x" }, { "y3", "number", "corner 3 y" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws a filled triangle.",
      example = [[
trifill(128, 20, 100, 70, 156, 70, 10)]],
    },
  },
}
