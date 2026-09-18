local mty = require'metaty'

--- Library of game-related types and utilities.
local M = mty.mod'asciigame'

--- A sprite with a location. Used by games to more easily write
--- to the Game grid by simply appending the txt/fg/bg.
M.Sprite = mty'Sprite' {
  'l [int]: line number', 'c [int]: column number',
  'txt [str]',
  'fg  [str]',
  'bg  [str]',
}

return M