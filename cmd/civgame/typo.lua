local mty = require'metaty'

--- Typo game: learn how to type!
local M = mty.mod'civgame.typo'

local et = require'ele.types'
local egame = require'ele.game'
local ds = require'ds'
local pth = require'ds.path'
local vt100 = require'vt100'
local luk = require'luk'
local ix = require'civix'

local concat             = mty.from(table,   'concat')
local push, pop          = mty.from(table,   'insert, remove')
local sfmt, srep         = mty.from(string,  'format, rep')
local min, max, abs      = mty.from(math,    'min, max, abs')
local int, isupper       = mty.from'ds        int, isupper'
local info               = mty.from'ds.log    info'
local Game, S            = mty.from'ele.game  Game,Sprite'

local TUTORIAL = luk.import('civgame/typo.luk', pth.data())

local MAX_LEVEL = 10

-- Table of key => keyScore
local SCORE = {}
-- multiply score by this to get expected time in ms
local EXPECTED_MS_MULTIPLIER
do
  local function set(chrs, v)
    for c in chrs:gmatch'.' do SCORE[c] = v end
  end
  set("qzxc p;',./",  12) -- pinkie or hard
  set('QZXC P:"<>?',  15) -- shift + pinkie or hard

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
M.SCORE = SCORE

--- Calculate the raw score of the string.
function M.rawScore(str)
  local s = 5
  for c in str:gmatch'.' do
    local cs = SCORE[c] or isupper(c) and 13 or 10
    dbg('%q score: %s', c, cs)
    s = s + cs
  end
  return s
end

M.Typo = mty.extend(Game, 'Typo', {
  'user {chr}: the text the player has input.',
  'lvl [int]: current level', lvl=0,
  'score [int]',   score = 0,
  'wi [int]',      wi = 1,
  'miss [int]: count of non-consecutive backspaces', miss = 0,
  'lastWasBackspace [bool]', lastWasBackspace = false,
  'great [int]: rolling additional multiplier (permille)', great = 0,
  'fast [int]: rolling additional multiplier (permille)', fast = 0,
  'start [ds.Epoch]: time since epoch word was started',
  'status [ds.Deq[Sprite]]: rolling multipliers applied',
  mh = 3, mw = 10,
})
getmetatable(M.Typo).__call = function(T, t)
  Game.__init(t)
  t.user = {}
  t.sprites = {}
  t.actions = {
    keyinput = function(ed, ev) t:keyinput(ed, ev) end,
  }
  t.start = ix.epoch()
  t.status = ds.Deq{}
  return mty.construct(T, t)
end

--- Get the expected time in milliseconds.
function M.Typo:expectedTimeMs(score)
  local et = EXPECTED_MS_MULTIPLIER * score
  return et - (et * self.lvl // (MAX_LEVEL * 2))
end

function M.Typo:missCost() return max(10, self.lvl) end

M.Mult = mty'Mult' {
  'name [str]',
  'mult [int]: multiplier * 1000',
  'change [int]: multipler change * 1000',
}

local function statusSprite(txt, fg)
  return S{txt=txt, fg=srep(fg or ' ', #txt)}
end

function M.Mult:sprite()
  local n, m, c = self.name, self.mult, self.change
  local txt = sfmt('%s%.1f %s (%s)', (c>0) and '+' or '-', abs(c), n, m)
  return statusSprite(txt, (c>0.5) and 'G' or (c>0) and 'g' or 'r')
end

--- Update the multipliers and get the final multiplier and Mult statuses
--- to display.
---
--- This uses Typo's current multipliers and miss count.
function M.Typo:updateMult(txt, elapsedMs, expectedMs) --> float, {Mult}
  dbg('updateMult', txt, elapsedMs, expectedMs)
  local status, fast, great = {}, self.fast, self.great
  local fastMult = M.Mult{name='faster'}
  if elapsedMs <= (expectedMs // 2) then
    if fast < 2 then fast = min(2000, fast + 500) end
    if elapsedMs <= (expectedMs // 4) then
      fast, fastMult.name = min(3000, fast + 200), 'ludicrous'
    end
  elseif fast > 0 and elapsedMs >= (expectedMs * 0.6) then
    fast, fastMult.name = max(0, fast - 500), 'slowing'
  end
  if self.fast ~= fast then
    ds.update(fastMult, {mult=fast, change=fast - self.fast})
    self.fast = fast
    push(status, fastMult)
  end

  local miss, great, greatMult = self.miss, self.great, M.Mult{name='great'}
  if miss / #txt <= 0.2 then
    if great < 2 then great = min(2000, great + 500) end
    if miss == 0 then
      great, greatMult.name = min(3000, great + 200), 'perfect'
    end
  elseif great > 0 and miss / #txt >= 0.3 then
    great, greatMult.name = max(0, great - 500), 'missed a few!'
  end
  if self.great ~= great then
    ds.update(greatMult, {mult=great, change=great - self.great})
    self.great = great
    push(status, greatMult)
  end

  -- Compute final multiplier
  dbg('great&fast', great, fast)
  local mult = min(4000, 1000 + great + fast)
  if elapsedMs > expectedMs then 
    mult = -min(2000, int(1000 * (elapsedMs - expectedMs) / expectedMs))
  end
  return mult, status
end

function M.Typo:getData()
  return TUTORIAL[self.wi]
end

function M.Typo:draw(ed, isRight)
  -- FIXME: need to display mults
  -- FIXME: score should be a bar that "fills up" to gain levels.
  local h = self.th
  ds.clear(self.sprites)
  local title = TUTORIAL.title
  local t = self:getData()
  if not t then
    self.wi = 1; t = self:getData()
  end
  push(self.sprites, S{l=1,c=1, txt=title, fg=srep('W', #title)})
  push(self.sprites, S{l=2,c=1, txt=TUTORIAL.help})
  if t.help then push(self.sprites, S{l=h-4,c=20, txt=t.help}) end

  -- Display status objects
  while #self.status > 8 do self.status() end -- reduce to len 8
  do local s = 1; for l=h-4, h-4-#self.status, -1 do
    local sp = self.status[s]
    sp.l,sp.c = l,20; push(self.sprites, sp)
    s = s + 1
  end end

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

  local score = sfmt('Score: %s  Fast: x%.1f  Great: x%.1f',
                     self.score, self.fast, self.great)
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
    if not self.lastWasBackspace then
      self.lastWasBackspace, self.miss = true, self.miss + 1
    end
    return pop(self.user)
  end
  self.lastWasBackspace = false
  chr = vt100.LITERALS[chr] or chr
  assert(1 == #chr)
  push(self.user, chr)
  local u, w = concat(self.user), assert(self:getData().want)
  if u ~= w then return end -- Not done until identical
  info('scoring %q to %q', u, w)
  local now = ix.epoch()
  local elapsed = now - self.start
  local score = M.rawScore(u)
  local mult, changes = self:updateMult(
    u, elapsed:asMs(), 100 + self:expectedTimeMs(score))
  score = int((score * mult) - (self.miss * self:missCost()))
  dbg('score', score, mult, self.miss, self:missCost())
  if score ~= 0 then
    local scoreTxt = sfmt('Score %s%s (%s missed)',
                          score>0 and '+' or '-', score, self.miss)
    self.status:push(statusSprite(scoreTxt, score >= 0 and ' ' or 'r'))
  end
  for _, ch in ipairs(changes) do self.status:push(ch:sprite()) end
  ds.clear(self.user)
  self.wi, self.score = self.wi + 1, self.score + score
  self.start, self.miss, self.lastWasBackspace = now, 0, false
end

getmetatable(M).__call = function(_, ed)
  ed:focus(M.Typo{})
end
return M
