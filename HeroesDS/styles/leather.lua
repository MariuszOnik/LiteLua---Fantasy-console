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
    gamma = 1.35,                -- lighter half-tones: 1 = as drawn
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
      unseen = { 58, 38, 24, 225 },
      seen = { 112, 82, 56, 100 },
    },
    border = { color = { 222, 182, 92 }, alpha = 0.9, width = 1.0 },
    labels = {
      province = { 246, 228, 186 },
      county = { 225, 200, 156 },
      shadow = { 20, 10, 5 },
      selected = { 255, 240, 190 },
    },
    grain = { strength = 0, cells = 3 },
  },
}
