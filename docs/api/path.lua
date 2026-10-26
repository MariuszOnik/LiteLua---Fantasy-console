-- LiteLua API documentation: path (path search on a grid, D57).
-- Format: see docs/api/README.md.
return {
  module = "path",
  title = "Path search",
  summary = "Where a unit can go and how: Dijkstra over a grid in the engine, "
         .. "about 50 times faster than the same code in Lua. Units may stand on "
         .. "a square of cells; costs are integers.",
  since = "D57",
  entries = {
    {
      name = "pathgrid", kind = "function",
      sig = "pathgrid(w, h) -> grid",
      args = { { "w", "integer", "cells across (up to 512)" },
               { "h", "integer", "cells down (up to 512)" } },
      ret = { { "grid", "a grid with all cells open" } },
      desc = "Makes a grid for path search. Each cell has flags: 1 closed (a "
          .. "wall), 2 slow, 4 mire (see grid:flood). The cells count in the "
          .. "cart's memory (one byte each).",
      example = [[
g = pathgrid(32, 24)
g:set(10, 5, 1)   -- a wall]],
    },
    {
      name = "grid:set", kind = "function",
      sig = "grid:set(x, y, flags)",
      desc = "Sets the flags of a cell (0 open, 1 closed, 2 slow, 4 mire, added "
          .. "together). Cells outside the grid are ignored.",
    },
    {
      name = "grid:get", kind = "function",
      sig = "grid:get(x, y) -> flags",
      desc = "The flags of a cell; outside the grid 1 (closed).",
    },
    {
      name = "grid:fits", kind = "function",
      sig = "grid:fits(x, y, [size]) -> boolean",
      desc = "Is a size x size square with its top-left cell at x, y inside the "
          .. "grid and on no closed cell? size is 1 by default.",
    },
    {
      name = "grid:clone", kind = "function",
      sig = "grid:clone() -> grid",
      desc = "A copy of the grid: make the walls once, copy them for each level.",
    },
    {
      name = "grid:flood", kind = "function",
      sig = "grid:flood(opts) -> cost, parent",
      args = { { "opts", "table", "x, y, size, budget, steps, corners, blockers, zones, "
                 .. "zone_costs, slow, mire, fly, columns, div" } },
      ret = { { "cost", "key -> cost of every place it can stop at" },
              { "parent", "key -> the key it came from (follow it back to the start)" } },
      desc = "Searches from x, y (the top-left cell of a size x size unit, size 1 "
          .. "by default) every place it reaches for at most budget. Keys are "
          .. "y * w + x (x * h + y with columns = true). steps: { dx, dy, cost, "
          .. "... }, by default 4 straight steps of 2 and 4 diagonal ones of 3. "
          .. "corners (true): a diagonal step needs one of its two straight "
          .. "neighbours free. blockers: { x, y, size, ... } squares it may not "
          .. "overlap (other units). zones: { x, y, size, ... } zones of control: "
          .. "leaving a place that touches one costs zone_costs[i] more for step i, "
          .. "unless it goes straight to or away from the zone. slow / mire: the "
          .. "least cost of a step onto a slow cell / with the unit on a mire cell. "
          .. "fly: passes over walls and blockers, lands only where it fits. "
          .. "div: costs come back divided by it (for fractions). cost and parent "
          .. "are read-only and work like tables for [key] and pairs() (in key "
          .. "order) — on a DS, filling real tables took as long as the search.",
      example = [[
local cost, parent = g:flood({ x = hx, y = hy, budget = 10 })
local k = ty * g.w + tx
if cost[k] then
  -- walk back from the target to the start
  local path = {}
  while k ~= hy * g.w + hx do
    table.insert(path, 1, { k % g.w, k // g.w })
    k = parent[k]
  end
end]],
    },
  },
}
