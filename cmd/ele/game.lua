local mty = require'metaty'

--- Ele game library.
local M = mty.mod'ele.game'

M.Game = mty'Game' {
  -- Grids are rendered first -> last.
  'txt {ds.Grid}: list of grid objects containing text to display',
  'fg {ds.Grid}: list of grid objects containing foreground asciicolor',
  'bg {ds.Grid}: list of grid objects containing background asciicolor',
}

function M.Game:draw(ed, isRight)
  local d = ed.display

end

--- A sprite with a location. Used by games to more easily write
--- to the Game grid by simply appending the txt/fg/bg.
M.Sprite = mty'Sprite' {
  'l [int]: line number', 'c [int]: column number',
  'txt [ds.Grid]',
  'fg [ds.Grid]',
  'bg [ds.Grid]',
}

return M
