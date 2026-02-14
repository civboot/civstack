-- Test display functionality (not mutation)

local G = G or _G
local T = require'civtest'
local CT = require'civtest'
local mty = require'metaty'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local pth = require'ds.path'
local log = require'ds.log'
local path = require'ds.path'
local ac = require'asciicolor'
local etest = require'ele.testing'
local Fake = require'vt100.testing'.Fake
local edit = require'ele.edit'
local Session = require'ele.Session'
local et = require'ele.types'
local Buffer = require'lines.buffer'.Buffer
local ixt = require'civix.testing'

local info = mty.from'ds.log  info'

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

-- Test{th=5, ..., 'name', function(test) ed = test.s.ed; ... end}
local Test = mty.record'session.Test' {
  'th', th=4, 'tw', tw=20,
  'dat', 'open [path]',
  's [Session]',
}
getmetatable(Test).__call = function(Ty, t)
  assert(not running); running = true
  local path = ds.srcloc(1)
  t = mty.construct(Ty, t)
  t.s = t.s or Session:test{}; local ed = t.s.ed
  assert(ed.view == ed.edit)
  ed.display = Fake{h=t.th, w=t.tw, styler=ac.Styler{}}
  local name = assert(t[1], 'need name')
  print('## test_session.Test', name)
  local testFn = function()
    if t.dat then
      lines.insert(ed.edit.buf.dat, t.dat, 1)
    elseif t.open then ed:open(t.open) end
    t.s:handleEvents()
    assert(t[2], 'need [2]=fn')(t)
    T.eq(log.LogTable{}, ed.error)
    ed.run = false
  end
  ixt.runAsyncTest(function()
    local ok, err = ds.try(T.runTest, name, testFn, path)
    if not ok then
      io.fmt:styled('error', 'Session Test error:', '\n')
      io.fmt(err)
      io.fmt:write'\n'
      error'Session Test error'
    end
  end)
  assert(running); running = false
end

Test{'session', dat='', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, t = ed.edit.buf, ed.display
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
    T.eq('9 8', b.dat[1])
    T.eq(SI..'\n9 8\n\n', fmt(t))
  T.eq(log.LogTable{}, ed.error)

  s:play'space 7 enter 6'
    T.eq(SI..'\n9 8 7\n6\n', fmt(t))
end}

Test{'move', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
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
    T.eq(SC..'\n'..LINES3, fmt(ed.display))

  s:play'0';   T.eq({2, 1}, {e.l, e.c})
  s:play'2 w'; T.eq({2, 4}, {e.l, e.c})
  s:play'b';   T.eq({2, 2}, {e.l, e.c})
  s:play'l ^'; T.eq({2, 2}, {e.l, e.c})
  s:play'3 G'; T.eq({3, 2}, {e.l, e.c})
end}

Test{'backspace', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b = e.buf
  s:play'l l';    T.eq({1, 3}, {e.l, e.c})
  s:play'i back'; T.eq({1, 2}, {e.l, e.c})
    T.eq('13 5 7 9', b:get(1))
  T.eq(SI..'\n13 5 7 9\n 2 4 6\n', fmt(ed.display))
end}

Test{'change_undo', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b = e.buf
  s:play'f 3 C h i'   T.eq({1, 5}, {e.l, e.c})
    T.eq(SI..'\n1 hi\n 2 4 6\n', fmt(ed.display))
  s:play'esc u'   T.eq({1, 3}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))

  e.l,e.c = 1,1
  s:play'i a space b space c space'
    T.eq(SI..'\n'..'a b c '..LINES3, fmt(ed.display))
  s:play'esc u'   T.eq({1, 1}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
  s:play'w D'
    T.eq(SC..'\n1 \n 2 4 6\n', fmt(ed.display))
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
| data/small.lua:1.1 (b#5) ===]]
Test{'open', open=SMALL, th=9, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
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
| data/small.lua:1.1 (b#5) =| data/small.lua:1.1 (b#5) ===]]
local SPLIT_2 = '\n'..[[
 0-- a small lua file for te 1-- a small lua file for test
 1local M = {}               0local M = {}
 2                           1
| data/small.lua:1.1 (b#5) =| data/small.lua:2.7 (b#5) ===]]
local SPLIT_3 = '\n'..[[
 0-- a small lua file for tests
 1local M = {}
 2
| data/small.lua:1.1 (b#5) =================================]]

Test{'window', open=SMALL, th=5, tw=60, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, BID = e.buf, et.INIT_BUFS + 2
  local d = ed.display

  T.eq(b.id, BID)
  T.eq(SMALL, pth.nice(b.dat.path))
  s:play'g L'
    T.eq(SC..SPLIT_1, fmt(ed.display))
    T.eq(et.VSplit, mty.ty(ed.view))
    T.eq(e, ed.view[1])
    T.eq(ed.edit, ed.view[2])
    assert(e ~= ed.edit)

  local sp = ed.view
  local e1, e2 = sp[1], sp[2]
  s:play'j f M'
    T.eq({1,1}, {e1.l,e1.c})
    T.eq({2,7}, {e2.l,e2.c})
    T.eq(SC..SPLIT_2, fmt(ed.display))

  s:play'g c'; e = ed.edit
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
| (b#4:1.1) ==================]]
local INSERTED_3 = [[
 0inserted
  
  
| (b#4:1.9) ==================]]
Test{'empty', dat=LINES3, th=5, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local g = e.buf.dat
  T.eq(require'lines.Gap', mty.ty(g))
  s:play''
    T.eq(SC..'\n'..LINES3_wLN, fmt(ed.display))

  e:clear(); T.eq({''}, ds.icopy(g))
    e:insert'inserted'
    T.eq({'inserted'}, ds.icopy(g))
    s:play''; T.eq(SC..'\n'..INSERTED_3, fmt(ed.display))
end}


local NAV_1 = [[
 0./data/
 1  * seuss/
 2  * small.lua
  
  
| b#nav:1.8 (b#2) ============]]

local NAV_2 = [[
 1./data/
 0  * seuss/
 1    * thing1.txt
 2    * thing2.txt
 3  * small.lua
| b#nav:2.8 (b#2) ============]]

-- FIXME: I'm not sure about the extra newline
local NAV_3 = [[
 3./data/
 2  * seuss/
 1  * small.lua
 0
  
| b#nav:4.8 (b#2) ============]]

local BUF_1 = [[
 0b#search   (tmp)
 1b#nav      (tmp)
 2b#find     (tmp)
 3b#4        (tmp)
 4b#5        ./data/small.lua
| b#nav:1.1 (b#2) ============]]


Test{'nav', open=SMALL, th=7, tw=30, function(tst)
  local s, ed = tst.s, tst.s.ed
  s:play'g .'
  local e = tst.s.ed.edit
    T.eq(SS..'\n'..NAV_1, fmt(ed.display))
    T.eq('system', ed.mode)
    T.eq({1,8}, {e.l,e.c})

  s:play'esc'; T.eq('command', ed.mode)

  s:play's j l' -- expand seuss
    T.eq('system', ed.mode)
    T.eq(SS..'\n'..NAV_2, fmt(ed.display))
    T.eq({2,8}, {e.l,e.c})

  s:play'2 j h' -- go down, but then unexpand
    T.eq(SS..'\n'..NAV_3, fmt(ed.display))
    T.eq({4,8}, {e.l,e.c})

  s:play'2 k l j enter' -- go to thing1.txt
  e = tst.s.ed.edit
    T.matches('data/seuss/thing1%.txt$', e:path())
    T.eq('command', ed.mode)

  s:play'g b'
    T.eq(SS..'\n'..BUF_1, fmt(ed.display))
    T.eq('system', ed.mode)
  s:play'4 j enter'
    T.matches('data/small.lua$', ed.edit:path())
  s:play'g b' -- should be same as before
    T.eq(SS..'\n'..BUF_1, fmt(ed.display))
end}

Test{'overlay', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
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
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
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

Test{'searchBuf', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
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

G.PWD = _PWD
