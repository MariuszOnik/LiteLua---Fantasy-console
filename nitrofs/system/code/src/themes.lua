-- Color themes of the code area (D46). Colors: 0-15 = palette, otherwise
-- 0xRRGGBB. 'syntax' colors the classes of the lexer.

local M = {}

M.list = {
  {
    id = "soft", name = "Soft dark",
    bg = 0x1e2230, status_bg = 0x2a3042, status_fg = 0xc8ccd4, pos_fg = 0x8a93a6,
    gutter_bg = 0x1e2230, gutter_fg = 0x5a6274, line_bg = 0x272c3b,
    sel_bg = 0x3a4766, err_bg = 0x4a2a35, cursor = 0xe6c07b,
    syntax = {
      text = 0xc8ccd4, keyword = 0x7aa2d6, builtin = 0x7fc4c4, number = 0xd7b98a,
      string = 0x9cc28c, comment = 0x6b7385, punct = 0x98a0b0,
    },
  },
  {
    id = "light", name = "Light (Notepad++)",
    bg = 0xffffff, status_bg = 0xdcdcdc, status_fg = 0x000000, pos_fg = 0x505050,
    gutter_bg = 0xe8e8e8, gutter_fg = 0x808080, line_bg = 0xe8e8ff,
    sel_bg = 0xb4d4ff, err_bg = 0xffd0d0, cursor = 0x000000,
    syntax = {
      text = 0x000000, keyword = 0x0000ff, builtin = 0x0080c0, number = 0xff8000,
      string = 0x808080, comment = 0x008000, punct = 0x000080,
    },
  },
  {
    id = "classic", name = "Classic (high contrast)",
    bg = 0, status_bg = 8, status_fg = 12, pos_fg = 13,
    gutter_bg = 0, gutter_fg = 14, line_bg = 15,
    sel_bg = 9, err_bg = 1, cursor = 4,
    syntax = {
      text = 12, keyword = 3, builtin = 11, number = 4,
      string = 5, comment = 14, punct = 13,
    },
  },
}

M.default = "soft"

function M.get(id)
  for _, t in ipairs(M.list) do
    if t.id == id then return t end
  end
  return M.get(M.default)
end

return M
