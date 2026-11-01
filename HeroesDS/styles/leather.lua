-- A map drawn on old leather: pores, creases, gold-tooled borders, light names.
-- See classic.lua for what every field means.
return {
  map = {
    surface = "leather",
    stain = 1.0,                 -- creases and pores: 0 .. 1.5
    paper = { 176, 128, 84 },
    sea = { 124, 120, 98 },
    shore = { 172, 146, 106 },
    rim = 0.6,
    gamma = 1.6,                 -- lighter half-tones: 1 = as drawn
    patterns = { land = "------  .  " },   -- province borders: dash, dot
    dash = 1.5,
    lines = {
      coast = { 36, 20, 10 },
      land = { 58, 34, 18 },
      county = { 98, 66, 40 },
      sea = { 146, 128, 98 },
    },
  },
  view = {
    background = { 26, 18, 12 },
    tint = 0.45,
    neutral = { 190, 160, 120 },
    fog = {
      unseen = { 132, 98, 68, 215 },
      seen = { 150, 116, 82, 85 },
    },
    border = { show = false, color = { 222, 182, 92 }, alpha = 0.9, width = 1.0, pattern = "------  .  ", dash = 11 },
    select = { mode = "fill", pattern = "----   ", color = { 30, 16, 6 }, alpha = 0.9, width = 1.8, dash = 5, fill = 0.32, flicker = 0.35, period = 3.5, gap = 0.08, soft = 3 },
    labels = {
      province = { 246, 228, 186 },
      county = { 225, 200, 156 },
      shadow = { 20, 10, 5 },
      selected = { 255, 240, 190 },
    },
    grain = { strength = 0, cells = 3 },
  },
}
