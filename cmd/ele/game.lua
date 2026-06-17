local mty = require'metaty'

--- Ele game library.
local M = mty.mod'ele.game'

M.Game = mty'Game' {
  -- Grids are rendered first -> last.
  'txt {ds.Grid}: list of grid objects containing text to display',
  'fg {ds.Grid}: list of grid objects containing foreground asciicolor',
  'bg {ds.Grid}: list of grid objects containing background asciicolor',
}

return M
