-- Idea 2: a picture of parchment (styles/parchment.png: SDXL 1.0 through ComfyUI,
-- tools/paperart.py --seeds 12, the dark edges cut off) repeated over the map; unexplored
-- land is blank parchment.
return {
  map = {
    surface = "image",
    image = "parchment.png",
    image_cells = 18,            -- cells one copy of the picture covers
    paper = { 240, 224, 186 },
    sea = { 168, 190, 178 },
    shore = { 228, 224, 198 },
    rim = 0.8,
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
    border = { color = { 125, 32, 20 }, alpha = 0.85, width = 1.0, pattern = "------  .  ", dash = 11 },
    select = { pattern = "----   ", color = { 45, 26, 12 }, alpha = 0.9, width = 1.8, dash = 5, fill = 0.12 },
    labels = {
      province = { 52, 30, 12 },
      county = { 98, 70, 40 },
      shadow = { 60, 40, 20 },
      selected = { 255, 248, 225 },
    },
    grain = { strength = 0, cells = 3 },
  },
}
