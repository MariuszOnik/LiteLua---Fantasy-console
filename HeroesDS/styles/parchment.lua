-- Old parchment: stains, fibres, a burnt edge; unexplored land is blank parchment
-- (terra incognita). See classic.lua for what every field means.
return {
  map = {
    surface = "parchment",
    stain = 1.0,                 -- stains and blotches: 0 .. 1.5
    paper = { 240, 224, 186 },
    sea = { 168, 190, 178 },
    shore = { 228, 224, 198 },
    rim = 0.8,
    patterns = { land = "------  .  " },   -- province borders: dash, dot
    dash = 1.5,
    lines = {
      coast = { 62, 38, 20 },
      land = { 96, 62, 34 },
      county = { 142, 112, 76 },
      sea = { 196, 204, 184 },
    },
  },
  view = {
    background = { 52, 38, 26 },
    tint = 0.5,
    neutral = { 205, 190, 156 },
    fog = {
      unseen = { 222, 206, 168, 240 },
      seen = { 190, 172, 136, 110 },
    },
    border = { show = false, color = { 125, 32, 20 }, alpha = 0.85, width = 1.0, pattern = "------  .  ", dash = 11 },
    select = { mode = "fill", pattern = "----   ", color = { 45, 26, 12 }, alpha = 0.9, width = 1.8, dash = 5, fill = 0.32, flicker = 0.35, period = 3.5, gap = 0.08, soft = 3 },
    labels = {
      province = { 52, 30, 12 },
      county = { 98, 70, 40 },
      shadow = { 60, 40, 20 },
      selected = { 255, 248, 225 },
    },
    grain = { strength = 0, cells = 3 },
  },
}
