local mty = require'metaty'

--- Typo game: learn how to type!
local M = mty.mod'civgame.typo'

local et = require'ele.types'
local egame = require'ele.game'
local ds = require'ds'
local concat = mty.from(string, 'concat')

local push = mty.from(table, 'insert')

M.Typo = mty.extend(egame.Game, 'Typo', {
  'user {chr}: the text the player has input.',
})

function M.Typo:draw(ed, isRight)
  ds.clear(g.sprites)
  push(g.sprites, egame.Sprite{l=1,c=1, txt=concat(self.user)})
  return egame.Game.draw(self, ed, isRight)
end

getmetatable(M).__call = function(_, ed)
  local g = M.Typo{
    mh = 3, mw = 10,
    user = {},
  }
  g.actions = {
    keyinput = function(ed, ev)
      local chr = ev[1]
      assert(1 == #chr)
      push(g.user, chr)
    end,
  }
  ed:focus(g)
end

return M
