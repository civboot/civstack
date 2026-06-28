
local G = G or _G
local T      = require'civtest'
local mty    = require'metaty'
local fmt    = require'fmt'
local ac     = require'asciicolor'
local ds     = require'ds'
local log    = require'ds.log'

local ixt    = require'civix.testing'
local Fake   = require'vt100.testing'.Fake
local etest  = require'ele.testing'
local et     = require'ele.types'
local edit   = require'ele.edit'
local egame  = require'ele.game'
local Session = require'ele.Session'

local typo   = require'civgame.typo'

local sfmt           = mty.from(string, 'format')
local info           = mty.from'ds.log  info'
local print, assertf = mty.from'fmt     print, assertf'
local Mult = typo.Mult

local running = false

-- Test{th=5, ..., 'name', function(test) ed = test.s.ed; ... end}
local Test = mty'civgame.Test' {
  'th', th=20, 'tw', tw=60,
  's [Session]',
  'game [ele.types.BasePane]',
}

getmetatable(Test).__call = function(Ty, t)
  t = mty.construct(Ty, t)
  local srcloc = ds.srcloc(1)
  assert(not running); running = true
  t.s = t.s or Session:test{}; local ed = t.s.ed
  local d = Fake{h=t.th, w=t.tw, styler=ac.Styler{}}
  ed.display = d
  T.eq({t.th,t.tw}, {d.h,d.w})
  local name = assert(t[1],   'need [1]=name')
  local game = assert(t.game, 'need game')
  print('## test_civgame', name)
  local testFn = function()
    ed:focus(game)
    t.s:handleEvents()
    assert(t[2], 'need [2]=fn')(t)
    T.eq(log.LogTable{}, ed.error)
    ed.run = false
  end
  ixt.runAsyncTest(function()
    local ok, err = ds.try(T.runTest, name, testFn, srcloc)
    if not ok then
      io.fmt:styled('error', 'civgame.Test error:', '\n')
      io.fmt(err)
      io.fmt:write'\n'
      error'civgame.Test error'
    end
    assert(running); running = false
  end)
end


-------------
-- typo

local TYPO_EXPECTED = [[
[mode:command]
Tutorial 1: type "SKIP!" to skip
Home position:
* thumbs over space
* pointer fingers normally on "f" and "j"
* middle fingers normally on "d" and "k"







    +32 score (1 missed, time 0.0/2.6)
    +0.7 speed is ludicrous (=0.7)
Home row: put left pointer finger on "f" key thumb on space.
Type: "f" "space" "j"
f j
   
Score: 32  Fast: x0.7  Great: x0.0]]

T'typo'; do
  -- Check that all non-alpha chars have a score assigned.
  for c=32,126 do; local c = string.char(c)
    assertf(c:match'[a-zA-Z]' or typo.SCORE[c], 'add to SCORE: %q', c)
  end

  T.eq(5 + 10*2 + 12, typo.rawScore'abc')

  local t = typo.Typo{}
  t.lvl = 0;  T.eq(1995, t:expectedTimeMs(21))
  t.lvl = 1;  T.eq(1896, t:expectedTimeMs(21))
  t.lvl = 2;  T.eq(1796, t:expectedTimeMs(21))

  t.lvl = 1
  T.eq({2200, {
    Mult{ name="speed is fast",  mult=500, change=500 }, 
    Mult{ name="perfect",        mult=700, change=700 },
  }}, {t:updateMult("j", 250, 500)})
end

Test{'typo session', game=typo.Typo{}, function(tst)
  local s, ed, g = tst.s, tst.s.ed, tst.s.ed.pane
  s:play'h'
    T.eq(log.LogTable{}, ed.error)
    T.eq({'h'}, g.user)
    T.eq(0,     g.miss) -- miss not counted until backspace

  s:play'back j j'
    T.eq(log.LogTable{}, ed.error)
    T.eq({}, g.user) -- cleared for next
    T.eq(0,  g.miss) -- miss cleared
    T.eq(32, g.score)
    T.eq(TYPO_EXPECTED, fmt(ed.display))
end}
