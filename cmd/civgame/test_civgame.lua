
local G = G or _G
local T      = require'civtest'
local mty    = require'metaty'
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

local info   = mty.from'ds.log  info'
local print  = mty.from'fmt     print'

local running = false

-- Test{th=5, ..., 'name', function(test) ed = test.s.ed; ... end}
local Test = mty.record'civgame.Test' {
  'th', th=10, 'tw', tw=60,
  's [Session]',
  'game [ele.types.BasePane]',
}

getmetatable(Test).__call = function(Ty, t)
  local srcloc = ds.srcloc(1)
  assert(not running); running = true
  t.s = t.s or Session:test{}; local ed = t.s.ed
  ed.display = Fake{h=t.th, w=t.tw, styler=ac.Styler{}}
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

Test{'typo', game=typo.Typo{}, function(tst)
  local s, ed, g = tst.s, tst.s.ed, tst.s.ed.pane
  s:play'h'
    T.eq({'h'}, g.user)
end}
