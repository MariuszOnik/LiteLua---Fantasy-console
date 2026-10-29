-- LiteLua API documentation: view3d (3D layer, D60 - experimental).
-- Format: see docs/api/README.md.
return {
  module = "view3d",
  title = "3D view",
  summary = "Experimental (D60): a perspective camera over a ground of tiles, "
         .. "isogrid terrain in 3D and batches of billboards (sprites from "
         .. "many directions that face the camera, e.g. soldiers). Drawn "
         .. "behind all 2D drawing of the same screen.",
  since = "D60",
  entries = {
    {
      name = "camera3d", kind = "function",
      sig = "camera3d(x, y, yaw, pitch, dist, [fov], [z])",
      args = {
        { "x", "number", "tile x the camera looks at" },
        { "y", "number", "tile y (rows grow to the south)" },
        { "yaw", "number", "degrees: 0 = the camera is south of the point "
            .. "and looks north, 90 = it is west of it" },
        { "pitch", "number", "degrees above the ground, 5..89" },
        { "dist", "number", "tiles from the point, 0.5..200" },
        { "fov", "number", "vertical field of view in degrees, default 50" },
        { "z", "number", "height of the point in tiles, default 0" },
      },
      desc = "Sets the camera of the 3D layer for the rest of this _draw "
          .. "(every _draw starts with yaw 0, pitch 45, dist 12 at 0, 0). "
          .. "Only about 60 tiles around the point can be drawn. The 3D layer "
          .. "is behind every 2D primitive of the screen, drawn before or "
          .. "after it: use cls for the sky and draw the HUD in 2D.",
      example = [[
camera3d(px, py, yaw, 40, 10)
ground:draw3d(1 / 16, 32)
army:draw3d(micros() // 1000)]],
    },
    {
      name = "fog3d", kind = "function",
      sig = "fog3d([col], [near], [far])",
      args = {
        { "col", "number", "fog color, usually the sky (cls); none = off" },
        { "near", "number", "tiles from the eye where it starts, default dist" },
        { "far", "number", "tiles where it covers everything, default 3 * near" },
      },
      desc = "Hardware fog of the 3D layer for the rest of this _draw (off at "
          .. "the start of each _draw). It grows evenly with distance. Nothing "
          .. "beyond far is drawn at all, which saves vertices.",
      example = [[
cls(SKY)
camera3d(x, y, yaw, 40, 10)
fog3d(SKY, 15, 30)]],
    },
    {
      name = "grid:draw3d", kind = "function",
      sig = "grid:draw3d([hscale], [tpt], [lod], [under])",
      args = {
        { "hscale", "number", "tiles up per height unit, default 1/16" },
        { "tpt", "integer", "texels per tile 1..32: one repeated texture "
            .. "instead of frames; default 0 = frames" },
        { "lod", "number", "with tpt: farther than this from the eye (tiles) "
            .. "every second corner, a quarter of the polygons; 0 = off" },
        { "under", "number", "color of a flat quad just under each chunk: "
            .. "fills the cracks the DS leaves between polygons (use the "
            .. "average ground color); default none" },
      },
      desc = "Draws an isogrid as terrain in the view of camera3d: cell (c, r) "
          .. "is the square c..c+1, r..r+1, its corners raised by their "
          .. "heights and shaded by their colors. With tpt the whole image "
          .. "(power-of-two sides) repeats over the ground and every row is "
          .. "one strip: about half the vertices of frames (the DS draws at "
          .. "most 6144 vertices and 2048 polygons per screen). The ground is "
          .. "kept as display lists of 8x8 cells, sent by DMA and tested "
          .. "for visibility by the hardware; they are rebuilt only when the "
          .. "grid or the arguments change.",
      example = [[
ground = isogrid(image("grass"), 48, 48, { heights = hs, colors = cols })
ground:draw3d(1 / 16, 32, 20, 0x426430)]],
    },
    {
      name = "billboards", kind = "function",
      sig = "billboards(img, n, [opts]) -> b",
      args = {
        { "img", "image", "frames of all directions and animations; its "
            .. "anchor is the point that stands on the ground" },
        { "n", "integer", "number of billboards, 1..4096 (all hidden)" },
        { "opts", "table", "dirs = 9 directions stored (south, turning "
            .. "west, to north; the rest are mirrored; 5 = 8 around, 1 = "
            .. "none), scale = tiles per texel (default 1/32)" },
      },
      ret = { { "b", "the batch; field n" } },
      desc = "A batch of sprites drawn in one call, each facing the camera with "
          .. "the frame of its direction seen from the camera. Positions, "
          .. "walking and animation are computed in C, so a Lua call is needed "
          .. "only when a billboard gets a new order.",
      example = [[
local img = anchor(image("soldier", 20, 30), 0.55, 0.78)
army = billboards(img, 600, { dirs = 9, scale = 1 / 56 })]],
    },
    {
      name = "b:anim", kind = "function",
      sig = "b:anim(id, first, frames, [ms], [loop])",
      args = {
        { "id", "integer", "animation 0..31" },
        { "first", "integer", "first frame (direction 0, step 0)" },
        { "frames", "integer", "steps per direction" },
        { "ms", "integer", "ms per step, default 100" },
        { "loop", "boolean", "default true; false stops on the last step" },
      },
      desc = "Defines an animation: the frame of stored direction d, step f is "
          .. "first + d * frames + f.",
      example = [[
army:anim(1, WALK, 10, 70)]],
    },
    {
      name = "b:set", kind = "function",
      sig = "b:set(i, x, y, z, dir, anim, [t0])",
      args = {
        { "i", "integer", "billboard 1..n" },
        { "x", "number", "tile x" },
        { "y", "number", "tile y" },
        { "z", "number", "tiles up (above the ground, see b:ground)" },
        { "dir", "integer", "0..15: 0 south, 4 west, 8 north, 12 east" },
        { "anim", "integer", "animation id, -1 = hidden" },
        { "t0", "integer", "time the animation starts, ms (default 0)" },
      },
      desc = "Places a billboard, standing still.",
      example = [[
army:set(1, 10.5, 20, 0, 8, WALK, micros() // 1000)]],
    },
    {
      name = "b:pos", kind = "function",
      sig = "b:pos(i, x, y, [z])",
      desc = "Moves a billboard to x, y (and z) and stops it.",
    },
    {
      name = "b:move", kind = "function",
      sig = "b:move(i, vx, vy, t)",
      args = {
        { "i", "integer", "billboard 1..n" },
        { "vx", "number", "tiles per second east" },
        { "vy", "number", "tiles per second south" },
        { "t", "integer", "time the walk starts, ms" },
      },
      desc = "From time t the billboard walks with this speed (from where it "
          .. "is at t). b:get tells where it is; 0, 0 stops it there.",
      example = [[
army:move(i, 0, -0.6, micros() // 1000)]],
    },
    {
      name = "b:get", kind = "function",
      sig = "b:get(i, t) -> x, y",
      ret = { { "number", "tile x and y of billboard i at time t (ms)" } },
      desc = "Where a billboard is at time t.",
    },
    {
      name = "b:ground", kind = "function",
      sig = "b:ground([grid], [hscale])",
      args = {
        { "grid", "isogrid", "terrain under the billboards; nil = none" },
        { "hscale", "number", "as in grid:draw3d, default 1/16" },
      },
      desc = "Billboards stand on this terrain: their z is added to the ground "
          .. "height under them, also while they walk.",
    },
    {
      name = "b:draw3d", kind = "function",
      sig = "b:draw3d(t, [lod])",
      args = {
        { "t", "integer", "time in ms (animations and walking)" },
        { "lod", "number", "farther than this from the eye (tiles) only every "
            .. "second billboard, beyond twice as far every fourth; 0 = all" },
      },
      desc = "Draws the billboards in the view of camera3d. Each one is 4 "
          .. "vertices (the DS draws at most 6144 per screen), so a far view "
          .. "of a big army needs lod.",
    },
  },
}
