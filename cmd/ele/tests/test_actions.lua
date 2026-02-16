-- Test event handling actions

local mty = require'metaty'
local fmt = require'fmt'
local T = require'civtest'
local ds = require'ds'
local pth = require'ds.path'
local Buffer = require'lines.buffer'.Buffer
local Gap = require'lines.Gap'
local ix = require'civix'
local et = require'ele.types'
local B = require'ele.bindings'
local M = require'ele.actions'
local Edit = require'ele.edit'.Edit
local Editor = require'ele.Editor'

local info = mty.from'ds.log  info'

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

local lines3 =
  '1 3 5 7 9\n'
..'  3 5\n'
..'1 3 5 7 9\n'

T'move'; do
  local d = newEditor(lines3); local e = d.edit
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
end

T'remove'; do
  local d = newEditor(lines3); local e, b = d.edit, d.edit.buf
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
  e.c = 1; M.paste(d, {action='paste', index=1})
    T.eq(' 51  7 9\n', fmt(b.dat))
  e.c = 1; assertRemove('find', {find=' ', times=2}, 1,1)
    T.eq('7 9\n', fmt(b.dat))

  info'removing first line'
  d = newEditor(lines3); local e, b = d.edit, d.edit.buf
  e.l, e.c = 1,1
  assertRemove('lines', {lines=0, times=1}, 1,1) -- remove one lines
    T.eq('  3 5\n1 3 5 7 9\n', fmt(b.dat))
    T.eq({'1 3 5 7 9', ''}, d.yank[d.yank.right])
  M.paste(d, {action='paste', index=1})
    T.eq('  3 5\n1 3 5 7 9\n1 3 5 7 9\n', fmt(b.dat))
end

T'insert'; do
  local d = newEditor'1 2 3\n4 5 6'; local e, b = d.edit, d.edit.buf
  local function assertInsert(txt, ev, l, c)
    ev[1] = txt; M.insert(d, ev)
    T.eq({l, c}, {e.l, e.c})
  end
  T.eq({1, 1}, {e.l, e.c})
  assertInsert('4 5 ', {}, 1, 5)
    T.eq('4 5 1 2 3', b:get(1))
    T.eq('4 5 6',     b:get(2))
  assertInsert('6 7\n', {}, 2, 1)
    T.eq('4 5 6 7\n1 2 3\n4 5 6', fmt(b.dat))
end

local NAV1 = [[
/focus/path/
  * f
  * d/
    * d/
    * f
]]
T'nav'; do
  local d = newEditor(NAV1)
  assert(d.edit.container == d)
  local e, b = d.edit, d.edit.buf

  T.eq('./focus/path/', nav.getFocus'-./focus/path/\n')
  T.eq(nil,             nav.getFocus'focus/path/\n')
  T.eq({'  ', '*', 'f'}, {nav.getEntry'  * f'})
  T.eq(1, nav.findFocus(b, 1))
  T.eq(1, nav.findFocus(b, 2))
  T.eq(1, nav.findFocus(b, 5))
  T.eq(5, nav.findEnd(b, 1))
  T.eq(5, nav.findEnd(b, 4))
  T.eq(5, nav.findEnd(b, 5))

  T.eq('/focus/path/',     nav.getPath(b, 1))
  T.eq('/focus/path/f',    nav.getPath(b, 2))
  T.eq('/focus/path/d/',   nav.getPath(b, 3))
  T.eq('/focus/path/d/d/', nav.getPath(b, 4))
  T.eq('/focus/path/d/f',  nav.getPath(b, 5))

  T.eq(nil, nav.findEntryEnd(b, 1))
  T.eq(2,   nav.findEntryEnd(b, 2))
  T.eq(5,   nav.findEntryEnd(b, 3))
  T.eq(4,   nav.findEntryEnd(b, 4))
  T.eq(5,   nav.findEntryEnd(b, 5))

  nav.backEntry(b, 4)
  T.eq('/focus/path/\n  * f\n  * d/\n', fmt(b.dat))

  nav.backEntry(b, 3)
  T.eq('/focus/path/\n', fmt(b.dat))

  b.dat:set(2, '  * f')
  nav.backEntry(b, 1)
  T.eq('/focus/path/\n', fmt(b.dat))

  nav.backEntry(b, 1)
  T.eq('/focus/\n', fmt(b.dat))

  b.dat:set(1, '/focus/path/')

  local r, entries = nil, {'f', 'd/'}
  nav.expandEntry(b, 1, function(p) r = p; return entries end)
  T.eq('/focus/path/', r)
  T.eq('/focus/path/\n  * f\n  * d/\n', fmt(b.dat))

  T.eq(et.INIT_BUFS + 1, #d.buffers)
  local test_txt = O..'test.txt'
  b:insert(test_txt..'\n', 2)
  e.l, e.c = 2, 1
  T.eq(test_txt, nav.getPath(b, 2,1))
  nav.goPath(d, true)
  T.eq(et.INIT_BUFS + 2, #d.buffers)
  local e = d.edit
  T.eq(pth.abs(pth.resolve(test_txt)), e.buf.dat.path)
  T.eq({1,1}, {e.l, e.c})
  e:changeStart()
  local content = 'some text\ninserted from actions'
  e:insert(content); e:save(d)
  T.path(test_txt, content)
end

T'namedBuffer'; do
  local d = newEditor''
  T.eq({'find', 'nav', 'overlay', 'search'}, ds.sort(ds.keys(d.namedBuffers)))
  local n = d:namedBuffer'nav'
  T.eq(et.INIT_BUFS - 1, n.id)
end