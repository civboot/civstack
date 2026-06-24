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
local isupper    = mty.from'ds        isupper'
local info       = mty.from'ds.log    info'
local Game, S    = mty.from'ele.game  Game,Sprite'

local TUTORIAL = luk.import('civgame/typo.luk', pth.data())

-- Table of key => keyScore
local SCORE = {}
-- multiply score by this to get expected time in ms
local EXPECTED_MS_MULTIPLIER
do
  local function set(chrs, v)
    for c in chrs:gmatch'.' do SCORE[c] = v end
  end
  set("qzxc p;',./",  12) -- pinkie or hard
  set('QZXC P:"<>/',  15) -- shift + pinkie or hard

  set('12390',        14) -- easy numbers
  set('!@#()',        17) -- shift + easy numbers

  set('45678',        16) -- hard numbers
  set('$%^&*',        19) -- shift + hard numbers

  set('`-=[]\\',      18)  -- most hand movement
  set('~_+{}|',       21)  -- shift + most hand movement

  -- We expect hardest key to take ~half a second.
  -- 0.5s = timeMultiplier * 21 ==> timeM = 0.5 / score
  EXPECTED_MS_MULTIPLIER = 500 // 21
end
SCORE[' '] = 5

--- Calculate the score of the string.
function M.score(str)
  local s = 5
  for c in str:gmatch'.' do
    s = s + (SCORE[c] or isupper(c) and 15 or 10)
  end
  return s
end

M.Typo = mty.extend(Game, 'Typo', {
  'user {chr}: the text the player has input.',
  'score [int]', score = 0,
  'wi [int]',    wi = 1,
  'perfect [int]', perfect = 0,
  mh = 3, mw = 10,
})
getmetatable(M.Typo).__call = function(T, t)
  Game.__init(t)
  t.user = {}
  t.sprites = {}
  t.actions = {
    keyinput = function(ed, ev) t:keyinput(ed, ev) end,
  }
  return mty.construct(T, t)
end

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
  local fg, bg = {}, {}
  for i=1,#self.user do
    local ok = u:sub(i,i)==w:sub(i,i)
    push(fg, ok and 'B' or 'W')
    push(bg, ok and 'W' or 'R')
  end
  bg = concat(bg)..srep('W', #w - #bg)
  push(self.sprites, S{
    l=h-1,c=1, txt=u, fg=concat(fg), bg=bg,
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
  -- typed all the characters, check word and calculate score
  for i=1,#w do
    if u:sub(i,i) ~= w:sub(i,i) then return end
    score = score + 1
  end
  ds.clear(self.user)
  self.wi, self.score = self.wi + 1, self.score + score
end

getmetatable(M).__call = function(_, ed)
  ed:focus(M.Typo{})
end
return M
