-- Test display functionality (not mutation)

local G = G or _G
local T      = require'civtest'
local mty    = require'metaty'
local fmt    = require'fmt'
local ds     = require'ds'
local lines  = require'lines'
local Stack  = require'ds.Stack'
local pth    = require'ds.path'
local log    = require'ds.log'
local path   = require'ds.path'
local Grid   = require'ds.Grid'
local ac     = require'asciicolor'
local agame  = require'asciigame'
local Buffer = require'lines.buffer'.Buffer
local ixt    = require'civix.testing'
local Fake   = require'vt100.testing'.Fake
local etest  = require'ele.testing'
local et     = require'ele.types'
local edit   = require'ele.edit'
local egame  = require'ele.game'
local Session = require'ele.Session'
local bindings = require'ele.bindings'

local info = mty.from'ds.log  info'
local push = mty.from(table, 'insert')

local _PWD = PWD
G.PWD = path.abs(ds.srcdir())

local SC = '[mode:command]'
local SI = '[mode:insert]'
local SS = '[mode:system]'
local SMALL = 'data/small.lua'
local LINES3 =
  '1 3 5 7 9\n'
..' 2 4 6\n'
..''

local function y(v) coroutine.yield(v or true) end

local function run(s)
  while (#s.keys + #s.events > 0) do coroutine.yield(true) end
end

local running = false

local function noTmp(s)
  return s:gsub('/tmp/lua_%w+', 'TMP')
end

-- Test{th=5, ..., 'name', function(test) ed = test.s.ed; ... end}
local Test = mty.record'session.Test' {
  'th', th=4, 'tw', tw=20,
  'dat', 'open [path]',
  's [Session]',
}
getmetatable(Test).__call = function(Ty, t)
  local srcloc = ds.srcloc(1)
  assert(not running); running = true
  t = mty.construct(Ty, t)
  t.s = t.s or Session:test{}; local ed = t.s.ed
  assert(ed.view == ed.pane)
  ed.display = Fake{h=t.th, w=t.tw, styler=ac.Styler{}}
  local name = assert(t[1], 'need name')
  print('## test_session.Test', name)
  local testFn = function()
    if t.dat then
      lines.insert(ed.pane.buf.dat, t.dat, 1,1)
    elseif t.open then ed:open(t.open) end
    t.s:handleEvents()
    assert(t[2], 'need [2]=fn')(t)
    T.eq(log.LogTable{}, ed.error)
    ed.run = false
  end
  ixt.runAsyncTest(function()
    local ok, err = ds.try(T.runTest, name, testFn, srcloc)
    if not ok then
      io.fmt:styled('error', 'Session Test error:', '\n')
      io.fmt(err)
      io.fmt:write'\n'
      error'Session Test error'
    end
  end)
  ed:rmTmp()
  assert(running); running = false
end

Test{'insert', dat='', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b, t = ed.pane.buf, ed.display
  T.eq('command', ed.mode)
  T.eq('\n\n\n', fmt(t))

  s:play'Z' -- unknown
    T.eq(1, #ed.error)
    T.matches('unbound chord: Z', fmt(ed.error[1]))
  ds.clear(ed.error)

  local again = { action='chain', tag='again', {mode='insert'} }
  s:play'i'
    T.eq('insert', ed.mode) -- next mode
    T.eq(nil, ed.ext.keys.next) -- selected in keyinput
    T.eq(nil, ed.ext.again) -- again not yet started
    T.eq(again, ed.ext.nextAgain)
  T.eq(log.LogTable{}, ed.error)

  ds.extend(again, {
    { "9", action="insert", tag='mut' },
    { " ", action="insert", tag='mut' },
    { "8", action="insert", tag='mut' },
  })
  s:play'9 space 8'; ed:draw()
    T.eq('9 8', b.dat:get(1))
    T.eq(SI..'\n9 8 \n\n', fmt(t))
    T.eq(nil, ed.ext.again) -- still, not stored
    T.eq(again, ed.ext.nextAgain)
  T.eq(log.LogTable{}, ed.error)

  push(again, {mode='command'})
  s:play'esc'
    T.eq(again, ed.ext.again) -- finally stored
    T.eq(nil, ed.ext.nextAgain)

  s:play'i space 7 enter 6' -- write ' 7\n6'
    T.eq(SI..'\n9 8 7\n6 \n', fmt(t))

  s:play'esc h r space' -- replace 6 w/space
    T.eq(SC..'\n9 8 7\n  \n', fmt(t))
end}

Test{'move', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  T.eq(3, #e.buf)
  T.eq('command', ed.mode)
  T.eq('\n\n\n', fmt(ed.display))

  s:play'' -- draw
    T.eq(SC..'\n1 3 5 7 9\n 2 4 6\n', fmt(ed.display))

  s:play'j';   T.eq({2, 1}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
  s:play'2 k'; T.eq({1, 1}, {e.l, e.c})
  s:play'$';   T.eq({1, 9}, {e.l, e.c})
  s:play'j';   T.eq({2, 9}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3:gsub('4 6', '4 6 '), fmt(ed.display))

  s:play'0';   T.eq({2, 1}, {e.l, e.c})
  s:play'2 w'; T.eq({2, 4}, {e.l, e.c})
  s:play'b';   T.eq({2, 2}, {e.l, e.c})
  s:play'l ^'; T.eq({2, 2}, {e.l, e.c})
  s:play'3 G'; T.eq({3, 2}, {e.l, e.c})
  s:play'g g'; T.eq({1, 1}, {e.l, e.c})
  s:play'G';   T.eq({3, 1}, {e.l, e.c})
end}

Test{'backspace', dat='   a\n', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b = e.buf
  e.l,e.c = 1,5
  s:play'i'
  s:play'back'; T.eq('   \n', fmt(b.dat)); T.eq({1, 4}, {e.l, e.c})
  s:play'back'; T.eq('  \n',  fmt(b.dat)); T.eq({1, 3}, {e.l, e.c})
  s:play'back'; T.eq('\n',    fmt(b.dat)); T.eq({1, 1}, {e.l, e.c})
  e.l,e.c = 2,1
  s:play'back'; T.eq('',      fmt(b.dat)); T.eq({1, 1}, {e.l, e.c})
end}

Test{'change_undo', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b = e.buf
  s:play'f 3 C h i'   T.eq({1, 5}, {e.l, e.c})
    T.eq(SI..'\n1 hi \n 2 4 6\n', fmt(ed.display))
  s:play'esc u'   T.eq({1, 3}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))

  e.l,e.c = 1,1
  s:play'i a space b space c space'
    T.eq(SI..'\n'..'a b c '..LINES3, fmt(ed.display))
  s:play'esc u'   T.eq({1, 1}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
  s:play'w D'
    T.eq(SC..'\n1  \n 2 4 6\n', fmt(ed.display))
  s:play'u'   T.eq({1, 3}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
end}

local SMALL_1 = '\n'..[[
 0-- a small lua file for test
 1local M = {}
 2
 3function M.main()
 4  print'hello world'
 5end
 6
| data/small.lua:1.1 (b#6) ===]]
Test{'open', open=SMALL, th=9, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b, BID = e.buf, et.INIT_BUFS + 2
  T.eq(b.id, BID)
  T.eq(SMALL, pth.nice(b.dat.path))
  s:play'' -- draws
    T.eq('-- a small lua file for tests', b:get(1))
    T.eq(SC..SMALL_1, fmt(ed.display))
  s:play'd f space'
    T.eq('a small lua file for tests', b:get(1))
  e = ed:open(SMALL)
    T.eq(b.id, BID)
    assert(rawequal(b, e.buf), 'buf is new')
    T.eq('a small lua file for tests', b:get(1)) -- no change to contents
end}

local SPLIT_1 = '\n'..[[
 0-- a small lua file for te 0-- a small lua file for test
 1local M = {}               1local M = {}
 2                           2
| data/small.lua:1.1 (b#6) =| data/small.lua:1.1 (b#6) ===]]
local SPLIT_2 = '\n'..[[
 0-- a small lua file for te 1-- a small lua file for test
 1local M = {}               0local M = {}
 2                           1
| data/small.lua:1.1 (b#6) =| data/small.lua:2.7 (b#6) ===]]
local SPLIT_3 = '\n'..[[
 0-- a small lua file for tests
 1local M = {}
 2
| data/small.lua:1.1 (b#6) =================================]]

Test{'window', open=SMALL, th=5, tw=60, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b, BID = e.buf, et.INIT_BUFS + 2
  local d = ed.display

  T.eq(b.id, BID)
  T.eq(SMALL, pth.nice(b.dat.path))
  s:play'g L'
    T.eq(SC..SPLIT_1, fmt(ed.display))
    T.eq(et.VSplit, mty.ty(ed.view))
    T.eq(e, ed.view[1])
    T.eq(ed.pane, ed.view[2])
    assert(e ~= ed.pane)

  local sp = ed.view
  local e1, e2 = sp[1], sp[2]
  s:play'j f M'
    T.eq({1,1}, {e1.l,e1.c})
    T.eq({2,7}, {e2.l,e2.c})
    T.eq(SC..SPLIT_2, fmt(ed.display))

  s:play'g c'; e = ed.pane
    T.eq(log.LogTable{}, ed.error)
    T.eq(ed.view, e)
    T.eq(SC..SPLIT_3, fmt(d))
    T.eq({1,1}, {e.l,e.c})
    T.eq({2,3}, {d.l, d.c})
end}

local LINES3_wLN = [[
 01 3 5 7 9
 1 2 4 6
 2
| TMP:1.1 (b#5) ==]]
local INSERTED_3 = [[
 0inserted
  
  
| TMP:1.9 (b#5) ==]]
Test{'empty', dat=LINES3, th=5, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local g = e.buf.dat
  T.eq(require'lines.Gap', mty.ty(g))
  s:play''
    T.eq(SC..'\n'..LINES3_wLN, noTmp(fmt(ed.display)))

  e:clear(); T.eq({''}, ds.icopy(g))
    e:insert'inserted'
    T.eq({'inserted'}, ds.icopy(g))
    s:play''; T.eq(SC..'\n'..INSERTED_3:gsub('inserted', 'inserted '),
      noTmp(fmt(ed.display)))
end}


local NAV_1 = [[
 1% p:-/%.
 0./data/
 1  * small.lua
 2  * seuss/
  
| TMP:2.8 b#nav ( ]]

local NAV_2 = [[
 3% p:-/%.
 2./data/
 1  * small.lua
 0  * seuss/
 1    * thing1.txt
| TMP:4.8 b#nav ( ]]

-- FIXME: I'm not sure about the extra newline
local NAV_3 = [[
 5% p:-/%.
 4./data/
 3  * small.lua
 2  * seuss/
 1
| TMP:6.8 b#nav ( ]]

local BUF_1 = [[
 0b#search   TMP
 1b#misc     TMP
 2b#nav      TMP
 3b#find     TMP
 4b#5        TMP
| TMP:1.1 b#nav ( ]]

Test{'nav', open=SMALL, th=7, tw=30, function(tst)
  local s, ed = tst.s, tst.s.ed
  s:play'g .'
  local e = tst.s.ed.pane
    T.eq(SS..'\n'..NAV_1:gsub('data/', 'data/ '), noTmp(fmt(ed.display)))
    T.eq('system', ed.mode)
    T.eq({2,8}, {e.l,e.c})
    T.eq(1, ed.pane.locations.max)
    T.ieq({et.EditLoc{b='nav', l=1,c=1}}, ed.pane.locations)

  s:play'esc'; T.eq('command', ed.mode)

  s:play's j j l' -- expand seuss
    T.eq('system', ed.mode)
    T.eq(SS..'\n'..NAV_2, noTmp(fmt(ed.display)))
    T.eq({4,8}, {e.l,e.c})

  s:play'2 j h' -- go down, but then unexpand
    T.eq(SS..'\n'..NAV_3, noTmp(fmt(ed.display)))
    T.eq({6,8}, {e.l,e.c})

  s:play'2 k l j enter' -- go to thing1.txt
  e = tst.s.ed.pane
    T.matches('data/seuss/thing1%.txt$', e:path())
    T.eq('command', ed.mode)

  -- The 'o' is gone because of bufSearch
  local searchMode = '[m de:system]\n'
  s:play'g b'
    T.eq(searchMode..BUF_1, noTmp(fmt(ed.display)))
    T.eq('system', ed.mode)
  s:play'd a t a / enter enter'
    T.matches('data/small.lua$', ed.pane:path())
  s:play'g b' -- should be same as before
    T.eq(searchMode..BUF_1, noTmp(fmt(ed.display)))
end}

Test{'overlay', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local ov = ed.overlay; ov.ext.show = true
  ov:insert('THE OVERLAY', 1,1)
  s:play''
    T.eq('THE OVERLAYnd]\n'..LINES3, fmt(ed.display))

  e.c = 4
  s:play''
    T.eq('[moTHE OVERLAY\n'..LINES3, fmt(ed.display))

  ov:insert('\n--NEXT LINE--', 1,12)
  s:play''
    T.eq(SC..'\n'..'1 3 5 7 9\n 2 THE OVERLAY  \n   --NEXT LINE--',
         fmt(ed.display))
end}

Test{'overlay', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local ov = ed.overlay; ov.ext.show = true
  ov:insert('THE OVERLAY', 1,1)
  s:play''
    T.eq('THE OVERLAYnd]\n'..LINES3, fmt(ed.display))

  e.c = 4
  s:play''
    T.eq('[moTHE OVERLAY\n'..LINES3, fmt(ed.display))

  ov:insert('\n--NEXT LINE--', 1,12)
  s:play''
    T.eq(SC..'\n'..'1 3 5 7 9\n 2 THE OVERLAY  \n   --NEXT LINE--',
         fmt(ed.display))
end}

Test{'visual', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane

  T.eq(ed.modes.visual, bindings.visual)

  s:play'l v'
    T.eq('visual', ed.mode)
    T.eq({1,2}, {e.ol,e.oc})
    T.eq({1,2}, {e.l,e.c})

  s:play'j l l'
    T.eq('visual', ed.mode)
    T.eq({1,2}, {e.ol,e.oc})
    T.eq({2,4}, {e.l,e.c})
end}

Test{'searchBuf', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local ov = ed.overlay
  local sbuf = ed:namedBuffer'search'

  s:play'/ 5 space 6 back 7'
    T.eq('5 7', fmt(ov.dat)); T.eq('5 7', ed.search)
    T.eq(true,  ov.ext.show)
    T.eq('5 7'..SC:sub(4)..'\n'..LINES3, fmt(ed.display))
    T.eq({1,1}, {e.l,e.c})

  s:play'enter'
    T.eq('5 7', fmt(ov.dat)); T.eq('5 7', ed.search)
    T.eq(false,  ov.ext.show)
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
    T.eq({1,5}, {e.l,e.c})
    T.eq('\n5 7', fmt(sbuf.dat))

  s:play'/ 4 space 6 ^n'
    T.eq('4 6', fmt(ov.dat)); T.eq('4 6', ed.search)
    T.eq(true,  ov.ext.show)
    T.eq({2,4}, {e.l,e.c})
    T.eq(SC..'\n1 34 67 9\n 2 4 6\n', fmt(ed.display))

  s:play'esc'
    T.eq('4 6', fmt(ov.dat)); T.eq('4 6', ed.search)

  s:play'N'
    T.eq('4 6', fmt(ov.dat)); T.eq('5 7', ed.search)
    T.eq(false,  ov.ext.show)
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
    T.eq({1,5}, {e.l,e.c})
end}
 
Test{'session', dat='', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b, t = ed.pane.buf, ed.display
  T.eq('command', ed.mode)
  T.eq('\n\n\n', fmt(t))

  s:play'Z' -- unknown
    T.eq(1, #ed.error)
    T.matches('unbound chord: Z', fmt(ed.error[1]))
  ds.clear(ed.error)

  s:play'i'
    T.eq('insert', ed.mode) -- next mode
    T.eq(nil, ed.ext.keys.next) -- selected in keyinput
  T.eq(log.LogTable{}, ed.error)

  s:play'9 space 8'; ed:draw()
    T.eq('9 8', b.dat:get(1))
    T.eq(SI..'\n9 8 \n\n', fmt(t))
  T.eq(log.LogTable{}, ed.error)

  -- simulate paste where ^j is enter.
  s:play'space 7 ^j 6'
    T.eq(SI..'\n9 8 7\n6 \n', fmt(t))

  s:play'^j space space 1 ^j space space 2 ^j'
    T.eq(SI..'\n  1\n  2\n ', fmt(t))
end}

-- a common coding session
local CODE = [[
function abc(d)
  e = d + 1
end
]]
Test{'coding', dat=CODE, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.pane
  local b, t = ed.pane.buf, ed.display
  T.eq('command', ed.mode)
  local locs = function(lcs)
    local s = Stack{}
    for _, lc in ipairs(lcs) do
      s:push(et.EditLoc:parse(lc, 'b#5'))
    end
    s.top = lcs.top or #lcs
    s.max = lcs.max or #lcs
    return s
  end
  -- start at (1.1)
  s:play'2 G' -- goto 2.1
    T.eq(locs{'1.1'}, ed.pane.locations)
    T.eq({2,1}, {e.l,e.c})
    T.eq('  e = d + 1', b:get(e.l))

  s:play'G' -- goto end (4.1)
    T.eq(locs{'1.1', '2.1'}, ed.pane.locations)
    T.eq({4,1}, {e.l,e.c})

  s:play'B' -- jump (-1), back to 2.1
    T.eq(locs{'1.1', '2.1', '4.1', top=1}, ed.pane.locations)
    T.eq({2,1}, {e.l,e.c})

  s:play'^b' -- jump (+1), "forward" to 4.1
    T.eq(locs{'1.1', '2.1', '4.1'}, ed.pane.locations)
    T.eq({4,1}, {e.l,e.c})

  s:play'B' -- jump (-1), back to 2.1
    T.eq(locs{'1.1', '2.1', '4.1', top=1}, ed.pane.locations)
    T.eq({2,1}, {e.l,e.c})

  s:play'o'
    T.eq(
    "function abc(d)\n"
  .."  e = d + 1\n  \nend\n", fmt(b.dat))
    T.eq({3,3}, {e.l,e.c})
    T.eq('insert', ed.mode)
    T.eq(locs{'1.1', '2.1', '4.1', top=1}, ed.pane.locations)

  -- Test "." aka "again"
  local again = {
    action="chain", tag="again",
    {
      action="chain", mode="insert", tag='mut',
      {action="move", cols=1, move="eol" },
      {"\n", action="insert", tag='mut'},
      {action="autoIndent", tag='mut'},
    },
    {"h", action="insert", tag='mut'},
    {"i", action="insert", tag='mut'},
    {mode="command"},
  }
  s:play'h i esc'; local bt = ed.pane.buf
    T.eq(again, ed.ext.again)
  s:play'.' -- inserts hi\n again
    T.ieq({"function abc(d)", "  e = d + 1", "  hi", "  hi", "end", ""},
          bt.dat)

  s:play'g n'
    T.eq(locs{'1.1', '4.5'}, ed.pane.locations)

  s:play'B' -- jump (-1), back to b#4
    T.eq(locs{'1.1', '4.5', '1.1 b#6', top=1}, ed.pane.locations)
end}

local SPLITV3 = [[
function afunctfunct
  e = d +   e =  e =
end       end  end]]

local SPLITV2 = [[
function afunction a
  e = d +   e = d + 
end       end]]

Test{'splitTwice', dat=CODE, function(tst)
  local s, ed = tst.s, tst.s.ed
  local d = ed.display

  s:play'g L  g L' -- split twice
    T.eq(SC..'\n'..SPLITV3, fmt(ed.display))
    T.eq({2,16}, {d.l,d.c})

  s:play'g c' -- close right view
    local e = ed.pane
    T.eq({1,1}, {e.l,e.c})
    T.eq(SC..'\n'..SPLITV2, fmt(ed.display))
    T.eq({2,1}, {d.l,d.c})
end}


local GAME_1 = [[
[mode:command]
xx(1,3)xxxxxxxxxxxxx
x(2,2)xxxxxxxxxxxxxx
xxxxxxxxxxxxxxxxxxxx]]

Test{'gameBasic', dat=CODE, function(tst)
  local s, ed = tst.s, tst.s.ed
  local d, e = ed.display, ed.pane

  local keyEv
  local g = egame.Game{
    mh = 3, mw = 10,
    actions = {
      keyinput = function(ed, ev) keyEv = ev end,
    },
  }
  push(g.sprites, agame.Sprite{l=1,c=1,
    txt=ds.paint('x', 4, 20),
    bg =ds.paint(' ', 4, 20),
    bg =ds.paint(' ', 4, 20),
  })
  push(g.sprites, agame.Sprite{l=1,c=3, txt='(1,3)'})
  push(g.sprites, agame.Sprite{l=2,c=2, txt='(2,2)'})
  ed:focus(g)
    T.eq(g, ed.pane)
    T.eq(g, ed.view)

  s:play'H'
    T.eq(GAME_1, fmt(d))
    T.eq({'H', action='keyinput'}, keyEv)

  ed:focus(e.buf)
    T.eq(true, g.closed)
    T.eq(nil,  g.container)
end}

G.PWD = _PWD