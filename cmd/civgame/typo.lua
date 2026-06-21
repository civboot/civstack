local mty = require'metaty'

--- Typo game: learn how to type!
local M = mty.mod'civgame.typo'

local et = require'ele.types'
local egame = require'ele.game'
local ds = require'ds'
local pth = require'ds.path'
local vt100 = require'vt100'
local luk = require'luk'

local concat     = mty.from(table,   'concat')
local push, pop  = mty.from(table,   'insert, remove')
local sfmt, srep = mty.from(string,  'format, rep')
local info       = mty.from'ds.log    info'
local Game, S    = mty.from'ele.game  Game,Sprite'

local TUTORIAL = luk.import('civgame/typo.luk', pth.data())

dbg('TUTORIAL', TUTORIAL)

M.Typo = mty.extend(Game, 'Typo', {
  'user {chr}: the text the player has input.',
  'score [int]', score = 0,
  'wi [int]',    wi = 1,
})

function M.Typo:getData()
  return TUTORIAL[self.wi] or {want='!! DONE !!'}
end

function M.Typo:draw(ed, isRight)
  local h = self.th
  ds.clear(self.sprites)
  local title = TUTORIAL.title
  local t = self:getData()
  push(self.sprites, S{l=1,c=1, txt=title, fg=srep('W', #title)})
  push(self.sprites, S{l=2,c=1, txt=TUTORIAL.help})
  if t.help then push(self.sprites, S{l=h-4,c=1, txt=t.help}) end

  local w = t.want
  push(self.sprites, S{l=h-2,c=1, txt=w, fg=srep('c', #w) })

  local u = concat(self.user)
  u = u..srep(' ', #w - #u)
  push(self.sprites, S{
    l=h-1,c=1, txt=u, fg=srep('B', #u), bg=srep('W', #u),
  })
  push(self.sprites, S{l=h-1,c=1+#self.user, fg='W', bg='C'})

  local score = sfmt('Score: %s', self.score)
  push(self.sprites, S{l=h,c=1, txt=score, fg=srep('G', #score)})
  return Game.draw(self, ed, isRight)
end

function M.Typo:drawCursor(ed)
  ed.display.hide = true
end

function M.Typo:keyinput(ed, ev)
  info('typo keyinput %q', ev)
  local chr = ev[1]
  if chr == 'back' then
    return pop(self.user)
  end
  chr = vt100.LITERALS[chr] or chr
  assert(1 == #chr)
  push(self.user, chr)
  info('typo keyinput %q', ev)
  local w = assert(self:getData().want)
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
