-- LiteLua API documentation: gfx (drawing on the screen).
-- Format: see docs/api/README.md.
return {
  module = "gfx",
  title = "Graphics",
  summary = "Drawing shapes and images. Call these in _draw; the screen is "
         .. "redrawn every frame. Colors: 0-15 = palette, or 0xRRGGBB.",
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
      sig = "camera([x, y, [zoom]])",
      args = {
        { "x", "number", "world x shown at the left edge, default 0" },
        { "y", "number", "world y shown at the top edge, default 0" },
        { "zoom", "number", "scale 1/16 .. 16, default 1" },
      },
      desc = "Moves and zooms the view: everything drawn after it appears at "
          .. "(position - camera) * zoom. camera() resets it. Use it to scroll "
          .. "the world and reset it before drawing the HUD. Lines and "
          .. "outlines stay 1 pixel wide when zoomed.",
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
    {
      name = "image", kind = "function",
      sig = "image(name, [fw, fh]) -> image",
      args = {
        { "name", "string", "file in gfx/ without .png, e.g. \"hero\"" },
        { "fw", "integer", "frame width (optional)" },
        { "fh", "integer", "frame height, default fw" },
      },
      ret = { { "image", "the image; fields w, h (frame size) and frames" } },
      desc = "Loads gfx/<name>.png of the cart into video memory. With a "
          .. "frame size the image is a sheet of frames numbered from 0, left "
          .. "to right, top to bottom. Loading the same name again returns the "
          .. "same image. PNG with a palette of up to 16 or 256 colors uses "
          .. "the least memory; palette index 0 (or alpha 0) is transparent. "
          .. "Images are at most 1024x1024; video memory holds 256 KB.",
      example = [[
hero = image("hero")
walk = image("walk", 16, 16)
print(walk.frames)]],
    },
    {
      name = "sub", kind = "function",
      sig = "sub(img, x, y, w, h, [fw, fh]) -> image",
      args = {
        { "img", "image", "source image" },
        { "x", "integer", "left of the part" }, { "y", "integer", "top" },
        { "w", "integer", "width" }, { "h", "integer", "height" },
        { "fw", "integer", "frame width (optional)" },
        { "fh", "integer", "frame height, default fw" },
      },
      ret = { { "image", "an image showing only that part" } },
      desc = "Makes an image from a part of another one, without copying: "
          .. "it uses the same video memory. Works everywhere an image does.",
      example = [[
tiles = image("tiles")
door = sub(tiles, 32, 0, 16, 24)
spr(door, 100, 80)]],
    },
    {
      name = "spr", kind = "function",
      sig = "spr(img, x, y, [frame], [flip])",
      args = {
        { "img", "image", "image to draw" },
        { "x", "number", "left" }, { "y", "number", "top" },
        { "frame", "integer", "frame number from 0, default 0" },
        { "flip", "string", "\"x\", \"y\" or \"xy\" to mirror" },
      },
      desc = "Draws an image (or one frame of it) with its top left corner "
          .. "at x, y.",
      example = [[
spr(walk, x, y, t // 6 % walk.frames)
spr(walk, x, y, 0, "x")  -- facing left]],
    },
    {
      name = "sprx", kind = "function",
      sig = "sprx(img, x, y, [frame], [angle], [sx], [sy], [flip])",
      args = {
        { "img", "image", "image to draw" },
        { "x", "number", "center x" }, { "y", "number", "center y" },
        { "frame", "integer", "frame number from 0, default 0" },
        { "angle", "number", "rotation in degrees, clockwise, default 0" },
        { "sx", "number", "horizontal scale, default 1" },
        { "sy", "number", "vertical scale, default sx" },
        { "flip", "string", "\"x\", \"y\" or \"xy\" to mirror" },
      },
      desc = "Draws an image rotated and scaled around its center x, y. "
          .. "Positions can have fractions.",
      example = [[
sprx(ship, x, y, 0, angle)
sprx(coin, 64, 40, 0, 0, 2)  -- twice as big]],
    },
    {
      name = "sspr", kind = "function",
      sig = "sspr(img, sx, sy, sw, sh, dx, dy, [dw], [dh], [flip])",
      args = {
        { "img", "image", "source image" },
        { "sx", "integer", "part left" }, { "sy", "integer", "part top" },
        { "sw", "integer", "part width" }, { "sh", "integer", "part height" },
        { "dx", "number", "screen left" }, { "dy", "number", "screen top" },
        { "dw", "number", "drawn width, default sw" },
        { "dh", "number", "drawn height, default sh" },
        { "flip", "string", "\"x\", \"y\" or \"xy\" to mirror" },
      },
      desc = "Draws any part of an image, stretched to dw x dh. A negative "
          .. "dw or dh mirrors it.",
      example = [[
sspr(tiles, 0, 0, 8, 8, 10, 10, 32, 32)]],
    },
    {
      name = "tint", kind = "function",
      sig = "tint([col]) / tint(c1, c2, c3, c4)",
      args = {
        { "col", "color", "color multiplied with the images drawn next" },
        { "c1..c4", "color", "corners: top left, top right, bottom right, "
          .. "bottom left" },
      },
      desc = "Colors the images drawn after it: white keeps the image as it "
          .. "is, other colors darken and tint it. Four colors make a "
          .. "gradient over the corners. tint() removes it. Shapes are not "
          .. "affected.",
      example = [[
tint(2)              -- red flash when hit
spr(hero, x, y)
tint()]],
    },
    {
      name = "text", kind = "function",
      sig = "text(s, x, y, [col])",
      args = {
        { "s", "string", "text; \\n starts a new line, \\t goes to the next "
          .. "multiple of 4 columns" },
        { "x", "number", "left" }, { "y", "number", "top" },
        { "col", "color", "color, default: color()" },
      },
      desc = "Draws text with the built-in font: every character is 6x8 "
          .. "pixels (42 columns x 24 rows fit on a screen). ASCII and the "
          .. "Polish letters are included; other characters show as a box. "
          .. "Works with camera (also zoom), clip and alpha.",
      example = [[
text("Score: " .. score, 2, 2, 12)
text("Zażółć gęślą jaźń", 2, 12, 4)]],
    },
    {
      name = "textw", kind = "function",
      sig = "textw(s) -> w, h",
      args = { { "s", "string", "text" } },
      ret = {
        { "integer", "width in pixels of the longest line" },
        { "integer", "height in pixels of all lines" },
      },
      desc = "Measures text, e.g. to center it or draw a box behind it.",
      example = [[
local w = textw(msg)
text(msg, (256 - w) // 2, 90)]],
    },
  },
}
