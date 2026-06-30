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

local MAX_LEVEL = 6

-- Table of key => keyScore
local SCORE = {}
-- multiply score by this to get expected time in ms
local EXPECTED_MS_MULTIPLIER
local SHIFT, SPACE       = 3, 5
local EASY               = 10
local PINKIE             = 12
local EASY_NUM, HARD_NUM = 14, 16
local HARDEST            = 18

do
  local function set(chrs, v)
    for c in chrs:gmatch'.' do SCORE[c] = v end
  end
  set("qzxc p;',./",  PINKIE)
  set('QZXC P:"<>?',  PINKIE+SHIFT)

  set('12390',        EASY_NUM)
  set('!@#()',        EASY_NUM+SHIFT)

  set('45678',        HARD_NUM)
  set('$%^&*',        HARD_NUM+SHIFT)

  set('`-=[]\\',      HARDEST)
  set('~_+{}|',       HARDEST+SHIFT)

  -- We expect hardest key to take ~half a second.
  -- 2.0s = timeMultiplier * 21 ==> timeM = 2.0 / score
  EXPECTED_MS_MULTIPLIER = 2000 // 21
end
SCORE[' '] = SPACE
M.SCORE = SCORE

--- Calculate the:
--- * total raw score of the string
--- * sum of unique scores
--- * maximum character score
function M.rawScore(str) --> int, int, int
  local scores = {}
  local s, u, m = 5, 0, 0
  for c in str:gmatch'.' do
    local cs = SCORE[c] or (EASY + (isupper(c) and SHIFT or 0))
    if not scores[cs] then
      u = u + cs; scores[cs] = true;
    end
    s = s + cs
    m = max(m, cs)
  end
  return s, u, m
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
  local txt = sfmt('%s%.1f %s (=%s)', (c>0) and '+' or '-', abs(c/1000), n, m/1000)
  return statusSprite(txt, (c>0.5) and 'G' or (c>0) and 'g' or 'y')
end

--- Update the multipliers and get the final multiplier and Mult statuses
--- to display.
---
--- This uses Typo's current multipliers and miss count.
function M.Typo:updateMult(txt, elapsedMs, expectedMs) --> float, {Mult}
  dbg('updateMult', txt, elapsedMs, expectedMs)
  local status, fast, great = {}, self.fast, self.great
  local fastMult = M.Mult{name='speed is fast'}
  if elapsedMs <= (expectedMs // 2) then
    if fast < 2000 then fast = min(2000, fast + 500) end
    if elapsedMs <= (expectedMs // 4) then
      fast, fastMult.name = min(3000, fast + 200), 'speed is ludicrous'
    end
  elseif fast > 0 and elapsedMs >= (expectedMs * 0.6) then
    fast, fastMult.name = max(0, fast - 500), 'speed is slowing'
  end
  if self.fast ~= fast then
    ds.update(fastMult, {mult=fast, change=fast - self.fast})
    self.fast = fast
    push(status, fastMult)
  end

  local miss, great, greatMult = self.miss, self.great, M.Mult{name='great'}
  if miss / #txt <= 0.2 then
    if great < 2000 then great = min(2000, great + 500) end
    if miss == 0 then
      great, greatMult.name = min(3000, great + 200), 'perfect'
    end
  elseif great > 0 and miss / #txt >= 0.5 then
    great, greatMult.name = max(0, great - 500), 'missed a few!'
  end
  if self.great ~= great then
    dbg('great', great, great - self.great)
    ds.update(greatMult, {mult=great, change=great - self.great})
    dbg('greatMult', greatMult)
    self.great = great
    push(status, greatMult)
  end

  -- Compute final multiplier
  dbg('great&fast', great, fast)
  dbg('elapsed', elapsedMs, 'expected', expectedMs)
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
  -- FIXME: score should be a bar that "fills up" to gain levels.
  local h,w = self.th, self.tw
  dbg('th,tw', h,w)
  local d = ed.display
  dbg('dh,dw', d.h,d.w)

  ds.clear(self.sprites)
  local title = TUTORIAL.title
  local t = self:getData()
  if not t then
    self.wi = 1; t = self:getData()
  end
  push(self.sprites, S{l=1,c=1, txt=title, fg=srep('W', #title)})
  push(self.sprites, S{l=2,c=1, txt=TUTORIAL.help})
  if t.help then push(self.sprites, S{l=h-4,c=1, txt=t.help}) end

  -- Display status objects
  while #self.status > 8 do self.status() end -- reduce to len 8
  local l = h-5
  local st = self.status
  for s=st.right,st.left,-1 do
    dbg('status[s]', s, l, #self.status)
    local sp = self.status[s]
    sp.l,sp.c = l,5; push(self.sprites, sp)
    l = l - 1
  end

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
  -- draw cursor
  push(self.sprites, S{l=h-1,c=1+#self.user, fg='W', bg='C'})

  local score = sfmt('Score: %s  Fast: x%.1f  Great: x%.1f',
                     self.score, self.fast/1000, self.great/1000)
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
  -- timer starts on first character
  if not self.start then self.start = ix.epoch() end
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
  local elapsed, expected = elapsed:asMs(), 200 + self:expectedTimeMs(score)
  local mult, changes = self:updateMult(u, elapsed, expected)
  score = int((score * mult / 1000) - (self.miss * self:missCost()))
  dbg('score', score, mult, self.miss, self:missCost())
  local scoreTxt = sfmt('%s%s score (%s missed, time %.1f/%.1f)',
                        score>=0 and '+' or '', score, self.miss,
                        elapsed/1000, expected/1000)
  self.status:push(statusSprite(scoreTxt, score >= 0 and 'c' or 'r'))
  if self.lvl <= 0 and score < 0 then
    self.status:push(statusSprite(
      sfmt('TUTORIAL MODE: score %.1f cancelled', score), 'f'))
    score = 0
  end
  for _, ch in ipairs(changes) do self.status:push(ch:sprite()) end
  ds.clear(self.user)
  self.wi, self.score = self.wi + 1, self.score + score
  self.miss, self.lastWasBackspace = 0, false
  self.start = nil
end

----------------------------
-- ## Code Extraction

-- Maximums for each phase of the game.
local BEGIN = SPACE + EASY
local EARLY = (BEGIN) + (EASY+SHIFT) + PINKIE
local MID   = (EARLY) + (PINKIE+SHIFT) + EASY_NUM
local LATE  = (MID)   + (SHIFT+EASY_NUM) + HARD_NUM + HARDEST

M.Categorizer = mty'Categorizer' {
  'begin {string}: beginning game lines',
  'early {string}: early game lines',
  'mid {string}: mid game lines',
  'late {string}: late game lines',
  'endGame {string}: end game lines',
}
getmetatable(M.Categorizer).__call = function(T, t)
  t.begin, t.early = t.begin or {}, t.early or {}
  t.mid, t.late    = t.mid or {},   t.late or {}
  t.endGame        = t.endGame or {}
  return mty.construct(T, t)
end

function M.Categorizer:categorize(line)
  line = ds.trim(line); if #line <= 3 then return end
  local s, u, m = M.rawScore(line)
  if     u <= BEGIN and m <= EASY_NUM then self.begin[line]   = s
  elseif u <= EARLY and m <= HARD_NUM then self.early[line]   = s
  elseif u <= MID   and m <= HARDEST  then self.mid[line]     = s
  elseif u <= LATE                    then self.late[line]    = s
  else self.endGame[line] = true end
end

local function sortedLines(lineScoreMap)
  return ds.orderedKeys(lineScoreMap, function(a, b)
    return lineScoreMap[a] < lineScoreMap[b]
  end)
end

function M.Categorizer:finish()
  return {
    sortedLines(self.begin),
    sortedLines(self.early),
    sortedLines(self.mid),
    sortedLines(self.late),
    sortedLines(self.endGame),
  }
end

----------------------------
-- Shim Commandline
getmetatable(M).__call = function(_, ed)
  ed:focus(M.Typo{})
end
return M
