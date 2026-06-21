local mty = require'metaty'

--- Typo game: learn how to type!
local M = mty.mod'civgame.typo'

local et = require'ele.types'
local egame = require'ele.game'
local ds = require'ds'
local vt100 = require'vt100'

local concat  = mty.from(table,   'concat')
local push    = mty.from(table,   'insert')
local sfmt    = mty.from(string,  'format')
local info    = mty.from'ds.log    info'
local Game, S = mty.from'ele.game  Game,Sprite'

local DONE = 'YOU WIN'

local want = {
  'do', 'so', 'hi', 'hello', 'at',
}

M.Typo = mty.extend(Game, 'Typo', {
  'user {chr}: the text the player has input.',
  'score [int]', score = 0,
  'wi [int]',    wi = 1,
})

function M.Typo:draw(ed, isRight)
  local h = self.th
  ds.clear(self.sprites)
  push(self.sprites, S{l=h-2,c=1, txt=sfmt('Score: %s', self.score)})
  push(self.sprites, S{l=h-1,c=1, txt=want[self.wi] or DONE})
  push(self.sprites, S{l=h  ,c=1, txt=concat(self.user)})
  return Game.draw(self, ed, isRight)
end

function M.Typo:keyinput(ed, ev)
  info('typo keyinput %q', ev)
  local chr = ev[1]
  chr = vt100.LITERALS[chr] or chr
  assert(1 == #chr)
  push(self.user, chr)
  info('typo keyinput %q', ev)
  local w = want[self.wi] or DONE
  if #self.user < #w then return end
  local score, u = 0, concat(self.user)
  info('scoring %q to %q', u, w)
  -- typed all the characters, calculate score
  for i=1,#w do
    if u:sub(i,i) == w:sub(i,i) then score = score + 1 end
  end
  ds.clear(self.user)
  self.wi, self.score = self.wi + 1, self.score + score
end

getmetatable(M).__call = function(_, ed)
  local g = M.Typo{
    mh = 3, mw = 10,
    user = {},
  }
  g.actions = {
    keyinput = function(ed, ev) g:keyinput(ed, ev) end,
  }
  ed:focus(g)
end
return M
