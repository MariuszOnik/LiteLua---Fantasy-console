-- The map's look (tools/make_m3.py --style; docs/FORMATS.md "style.lua").
-- Colours are { r, g, b } or { r, g, b, alpha }, 0..255.
-- map:  baked into the textures by make_m3.py -- change it, then build again.
-- view: read by the 3DS at start (romfs:/style.lua); a copy on the SD card at
--       sdmc:/3ds/heroes3d/style.lua goes over it: edit it there, start the game again.
return {
  map = {
    surface = "plain",           -- plain, parchment, leather, image
    paper = { 252, 248, 238 },   -- the land
    sea = { 150, 190, 200 },
    shore = { 235, 240, 225 },   -- the sea lighter near the coast
    rim = 0,                     -- the map's own edge burnt dark: 0 .. 1
    gamma = 1.0,                 -- over 1: lighter half-tones (the whole picture)
    lines = {
      coast = { 40, 28, 18 },
      land = { 70, 48, 30 },     -- between provinces
      county = { 120, 95, 70 },
      sea = { 200, 222, 228 },   -- between sea zones
    },
  },
  view = {
    background = { 150, 190, 200 },   -- around the map
    tint = 0.62,                      -- how strong the realms' colours are (1 = full)
    neutral = { 190, 180, 160 },      -- land nobody owns
    fog = {
      unseen = { 102, 102, 119, 204 },   -- never seen: graphite mist
      seen = { 153, 153, 153, 102 },     -- seen before: a grey veil
    },
    border = {                        -- realms' borders
      color = { 107, 20, 15 }, alpha = 0.85, width = 1.0,
      pattern = "-",                  -- per slice: '-' ink, ' ' gap, '.' dot
      dash = 8,                       -- one pattern = this many line widths
    },
    select = {                        -- the selected province
      pattern = "",                   -- "": a pulsing light; else a line like border's
      color = { 40, 25, 15 }, alpha = 0.9,
      width = 1.6,                    -- x the borders' width
      dash = 5,
      fill = 0,                       -- a faint light over it too: 0 .. 1
    },
    labels = {
      province = { 20, 12, 4 },
      county = { 70, 50, 30 },
      shadow = { 40, 25, 15 },        -- under realms' names
      selected = { 255, 255, 255 },
    },
    grain = { strength = 0, cells = 3 },   -- paper grain over the map: 0 .. 1, cells per copy
  },
}
