-- Test event handling actions

local mty = require'metaty'
local fmt = require'fmt'
local T = require'civtest'
local ds = require'ds'
local pth = require'ds.path'
local Buffer = require'lines.buffer'.Buffer
local Gap = require'lines.Gap'
local pod = require'pod'
local lson = require'lson'
local ix = require'civix'
local et = require'ele.types'
local B = require'ele.bindings'
local M = require'ele.actions'
local Edit = require'ele.edit'.Edit
local Editor = require'ele.Editor'

local info = mty.from'ds.log  info'
local State, BufState, PaneState = mty.from'ele.types\
      State, BufState, PaneState'

local nav = M.nav
local O = './.out/ele/'; if ix.exists(O) then ix.rmRecursive(O) end
ix.mkDir(O)

local function newEditor(lines)
  local ed = Editor{}
  B.install(ed)
  local e = ed:focus()
  e.buf:insert(lines, 1)
  return ed
end

local function cleanup(ed) ed:rmTmp() end

local lines3 =
  '1 3 5 7 9\n'
..'  3 5\n'
..'1 3 5 7 9\n'

T'move'; do
  local d = newEditor(lines3..'word1 word2\n'); local e = d.pane
  local function assertMove(mv, ev, l, c)
    ev.move = mv; M.move(d, ev)
    T.eq({l, c}, {e.l, e.c})
  end

  T.eq({1, 1}, {e.l, e.c})

  -- move some cols
  assertMove(nil, {cols=1}, 1, 2)
  assertMove(nil, {cols=-3}, 1, -1)

  -- forword/backword
  assertMove('forword',  {},        1, 3)
  assertMove('forword',  {times=2}, 1, 7)
  assertMove('backword', {},        1, 5)
  assertMove('forword',  {times=5}, 1, 11)

  -- endword
  e.l,e.c = 1,1; assertMove('endword', {},  1,3)
  e.l,e.c = 4,1; assertMove('endword', {},  4,5)
                 assertMove('endword', {},  4,11)

  -- move lines
  e.l, e.c = 1, 9; assertMove('lines', {lines=1}, 2, 9)
  e.l, e.c = 1, 9; assertMove('lines', {lines=2}, 3, 9)

  -- find
  e.l, e.c = 1, 1
  assertMove('find',     {find='3'},     1, 3)
  assertMove('find',     {find=' '},     1, 4)
  assertMove('find',     {find=' '},     1, 6)
  assertMove('find',     {find='9'},     1, 9)
  assertMove('findback', {findback='1'}, 1, 1)
  cleanup(d)
end

T'remove'; do
  local d = newEditor(lines3); local e, b = d.pane, d.pane.buf
  local y = d.pane.yank
  local function assertRemove(mv, ev, l, c)
    ev.move = mv; M.remove(d, ev)
    T.eq({l, c}, {e.l, e.c})
  end

  T.eq({1, 1}, {e.l, e.c})
  assertRemove('forword', {}, 1, 1) -- remove word '1'
    T.eq('3 5 7 9', b:get(1))
    T.eq('  3 5', b:get(2))
  assertRemove('find', {find='7', cols=-1}, 1, 1) -- remove before 7
    T.eq('7 9', b:get(1))
    T.eq("7 9\n  3 5\n1 3 5 7 9\n", fmt(b.dat))
  info'removing 2 lines'
  assertRemove('lines', {lines=0, times=2}, 1, 1) -- remove two lines
    T.eq('1 3 5 7 9\n', fmt(b.dat))
  e.c = 4; assertRemove(nil, {off=-1, cols1=-1}, 1, 3) -- backspace delete '3'
    T.eq('1  5 7 9\n', fmt(b.dat))
  e.c = 4; assertRemove(nil, {off=-1}, 1, 3) -- backspace delete ' 5'
    T.eq('1  7 9\n', fmt(b.dat))
    T.eq(y[y.right], {' 5'})
  e.c = 1; M.paste(d, {action='paste', index=1})
    T.eq(' 51  7 9\n', fmt(b.dat))
  e.c = 1; assertRemove('find', {find=' ', times=2}, 1,1)
    T.eq('7 9\n', fmt(b.dat))

  info'removing first line'
  cleanup(d)

  d = newEditor(lines3); local e, b = d.pane, d.pane.buf
  e.l, e.c = 1,1
  assertRemove('lines', {lines=0, times=1}, 1,1) -- remove one lines
    T.eq('  3 5\n1 3 5 7 9\n', fmt(b.dat))
    T.eq({'1 3 5 7 9', ''}, d.yank[d.yank.right])
  M.paste(d, {action='paste', index=1})
    T.eq('  3 5\n1 3 5 7 9\n1 3 5 7 9\n', fmt(b.dat))
  cleanup(d)

  info'join lines'
  d = newEditor'ab\ncd\n  z\n'; local e, b = d.pane, d.pane.buf
  e.c = 3
  assertRemove('nextLineText', {cols=-1}, 1,1)
    T.eq('abcd\n  z\n', fmt(b.dat))
  e.c = 5
  assertRemove('nextLineText', {cols=-1}, 1,1)
    T.eq('abcdz\n', fmt(b.dat))
  cleanup(d)
end

T'insert'; do
  local d = newEditor'1 2 3\n4 5 6'; local e, b = d.pane, d.pane.buf
  local function assertInsert(txt, ev, l, c)
    ev[1] = txt; M.insert(d, ev)
    T.eq({l, c}, {e.l, e.c})
  end
  T.eq(d, e:getEditor())
  T.eq({1, 1}, {e.l, e.c})
  assertInsert('4 5 ', {}, 1, 5)
    T.eq('4 5 1 2 3', b:get(1))
    T.eq('4 5 6',     b:get(2))
  assertInsert('6 7\n', {}, 2, 1)
    T.eq('4 5 6 7\n1 2 3\n4 5 6', fmt(b.dat))
  cleanup(d)

  d = newEditor'a b\n  c\nd'; e, b = d.pane, d.pane.buf
  e.l,e.c = 3,1
  M.autoIndent(d, {})
    T.eq('a b\n  c\n  d', fmt(b.dat))
  cleanup(d)
end

local NAV1 = [[
/focus/path/
  * f
  * d/
    * d/
    * f
/some/other/path
]]
T'nav'; do
  local d = newEditor(NAV1)
  assert(d.pane.container == d)
  local e, b = d.pane, d.pane.buf

  T.eq('./focus/path/', nav.getFocus'-./focus/path/\n')
  T.eq(nil,             nav.getFocus'focus/path/\n')
  T.eq({'  ', '*', 'f'}, {nav.getEntry'  * f'})
  T.eq(1, nav.findFocus(b, 1))
  T.eq(1, nav.findFocus(b, 2))
  T.eq(1, nav.findFocus(b, 5))
  T.eq(5, nav.findEnd(b, 1))
  T.eq(4, nav.findEnd(b, 4))
  T.eq(5, nav.findEnd(b, 5))

  T.eq('/focus/path/',     nav.getPath(b, 1))
  T.eq('/focus/path/f',    nav.getPath(b, 2))
  T.eq('/focus/path/d/',   nav.getPath(b, 3))
  T.eq('/focus/path/d/d/', nav.getPath(b, 4))
  T.eq('/focus/path/d/f',  nav.getPath(b, 5))

  T.eq(5,   nav.findEnd(b, 1))
  T.eq(2,   nav.findEnd(b, 2))
  T.eq(5,   nav.findEnd(b, 3))
  T.eq(4,   nav.findEnd(b, 4))
  T.eq(5,   nav.findEnd(b, 5))
  T.eq(6,   nav.findEnd(b, 6))

  nav.backEntry(d, b, 4)
  T.eq('/focus/path/\n  * f\n  * d/\n/some/other/path\n', fmt(b.dat))

  nav.backEntry(d, b, 3)
  T.eq('/focus/path/\n/some/other/path\n', fmt(b.dat))

  b.dat:set(2, '  * f')
  nav.backEntry(d, b, 1)
  T.eq('/focus/path/\n', fmt(b.dat))

  nav.backEntry(d, b, 1)
  T.eq('/focus/\n', fmt(b.dat))

  b.dat:set(1, '/focus/path/')

  local r, entries = nil, {'f', 'd/'}
  info'expanding entries'
  d.navLs = function(p) r = p; return entries end
  nav.expandEntry(d, b, 1)
  T.eq('/focus/path/', r)
  T.eq('/focus/path/\n  * f\n  * d/\n', fmt(b.dat))
  T.eq('/focus/path/', b:get(1))
  T.eq({3, 2}, {nav.findEnd(b, 1)})

  d.navLs = function(p)
    if p:find'/d/$' then return entries end
  end
  nav.expandEntry(d, b, 1)
  T.eq('/focus/path/\n  * f\
  * d/\
    * f\
    * d/\n', fmt(b.dat))

  T.eq(et.INIT_BUFS + 1, #d.buffers)
  local test_txt = O..'test.txt'
  b:insert(test_txt..'\n', 2)
  e.l, e.c = 2, 1
  T.eq(test_txt, nav.getPath(b, 2,1))
  nav.goPath(d, true)
  T.eq(et.INIT_BUFS + 2, #d.buffers)
  local e = d.pane
  T.eq(pth.abs(pth.resolve(test_txt)), e.buf.dat.path)
  T.eq({1,1}, {e.l, e.c})
  e:changeStart()
  local content = 'some text\ninserted from actions'
  e:insert(content); e:save(d)
  T.path(test_txt, content)
  cleanup(d)
end

T'namedBuffer'; do
  local d = newEditor''
  T.ieq(d.DEFAULT_BUFFERS, ds.sort(ds.keys(d.namedBuffers)))
  local n = d:namedBuffer'nav'
  T.eq(et.INIT_BUFS - 1, n.id)
  cleanup(d)
end

T'help'; do
  local ed = newEditor''
  local ov = ed:getBuffer'b#misc'
  M.help(ed)
  T.matches('""  {}\ncommand mode:', fmt(ov.dat))
  cleanup(ed)
end

T'state'; do
  local d1 = newEditor''
  local e1, b1 = d1.pane, d1.pane.buf
  local spath = pth.abs(O..'state.txt')
  local b2 = d1:namedBuffer('a', O..'state.txt')
  local e2 = d1:focus(b2)
  b2:insert('line in state\n', 1)
  e2:save(d1)
  e2:split(et.VSplit)
  d1:focus(e1)

  local st = d1:state()
  local expect = State{
    ID=et.ID, pane=e1.id,
    buffers={
      BufState{id=b1.id,           path=b1:path(), l=1,c=1},
      BufState{id=b2.id, name="a", path=spath,     l=1,c=1},
    },
    view=PaneState{
      ty="ele.types.VSplit",
      chld={
        PaneState{
          ty="ele.edit.Edit",
          dat={ id=12, vc=1, vl=1, l=1,c=1, path=b1:path() }
        }, PaneState{
          ty="ele.edit.Edit",
          dat={ id=14, vc=1, vl=1, l=1,c=1, path=spath }
        }
      }
    },
  }
  T.eq(expect, st)

  pth.write(O..'elestate.lson', lson.lson(st))
  T.eq(st, lson.load(O..'elestate.lson', et.State))
  T.eq(d1, d1.pane:getEditor())

  local d2 = newEditor'':loadState(st)
  local v = d2.view
  T.eq(d2.pane, v[1])
  T.eq(v, d2.pane.container)
  T.eq(d2, v.container)
  T.eq(d2, d2.pane:getEditor())

  T.eq(d2.pane:path(),    b1:path())
  T.eq(d2.view[2]:path(), b2:path())

  assert(d2:namedBuffer'nav')

  info('cleaning up d1'); cleanup(d1)
  info('cleaning up d2'); cleanup(d2)
end