local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local pth = require'ds.path'
local T = require'civtest'
local lines = require'lines'
local testing = require'lines.testing'
local U3File  = require'lines.U3File'
local File    = require'lines.File'
local EdFile  = require'lines.EdFile'
local Gap     = require'lines.Gap'
local ix      = require'civix'

local G = mty.G
local push, icopy = table.insert, ds.icopy
local s = ds.simplestr

local O = '.out/lines_file/'
local TXT, IDX = O..'lines.txt', O..'lines.idx'
local SMALL = ds.srcdir()..'data/small.txt'

local get, set = ds.get, ds.set

local info = require'ds.log'.info

ix.mkDirs(O)

local function loadu3s(f)
  local pos, t = f:seek'cur', {}; assert(pos)
  info('end: %i', f:seek'end')
  f:seek'set'
  for u3 in f:lines(3) do push(t, (('>I3'):unpack(u3))) end
  f:seek('set', pos) -- reset
  return t
end

local fin = false
local function tests()
T'U3File'; do
  local u = U3File:create()
  u:set(1, 11); u:set(2, 22); u:set(3, 33)
  T.eq(11, u:get(1))
  T.eq(22, u:get(2))
  T.eq(33, u:get(3)); T.eq(nil, rawget(u, 3))
  T.eq({11, 22, 33}, loadu3s(u.f))
  T.eq(11, u:get(1)) -- testing loadu3s
  T.eq(3, #u)

  u:set(2, 20); T.eq(3, #u)
    T.eq({11, 20, 33}, loadu3s(u.f))
    T.eq(11, u:get(1)); T.eq(20, u:get(2)); T.eq(33, u:get(3))

  u:set(1, 10); u:set(4, 44); u:set(5, 55)
  T.eq({10, 20, 33, 44, 55}, loadu3s(u.f))
  T.eq(10, u:get(1))
  T.eq(55, u:get(5))

  local l = {}; for i=1,#u do l[i] = u:get(i) end
  T.eq({10, 20, 33, 44, 55}, l)
  T.eq(5, #u)

  u = U3File:create(IDX)
  ds.extend(u, {0, 3, 5, 7})
  T.eq(0, u:get(1))
  T.eq(7, u:get(4))

  -- Move the idx file
  local to = IDX..'2'
  assert(u:move(to));
    T.exists(to)
    assert(not ix.exists(IDX))
  T.eq(to, u.path)
  T.eq({0, 3, 5, 7}, ds.icopy(u))
  T.eq({0, 3, 5, 7}, loadu3s(u.f))
end

T'reindex'; do
  local reindex = File._reindex
  local idx, f = {}, io.tmpfile()
  local txt = 'hi\nthere\nindex'
  f:write(txt); f:flush(); f:seek'set'
  T.eq(#txt, reindex(f, idx))
    T.eq({0, 3, 9}, idx)

  idx = {} f:write'\n'; f:flush(); f:seek'set'
  T.eq(#txt + 1, reindex(f, idx))
    T.eq({0, 3, 9, 15}, idx)

  -- test indexing from a l,pos
  idx = {0, 3}; f:seek('set', 9)
  T.eq(#txt + 1, reindex(f, idx, 3, 9))
    T.eq({0, 3, 9, 15}, idx)
end

T'File'; do
  local f = assert(File()); f.cache = ds.Forget{}
  T.eq('lines.File()', fmt(f))
  T.eq(0, #f); T.eq({}, ds.icopy(f))

  local dat = {'one', 'two', 'three'}
  ds.extend(f, dat)
    -- TODO: sometimes this has length 102 (!!)
    T.eq({0, 4, 8}, ds.icopy(f.idx))
    T.eq('one',   f:get(1))
    T.eq('three', f:get(3))
    T.eq(dat, ds.icopy(f))

  T.eq('one', f:get(1))
  f:set(4, 'four'); push(dat, 'four')
    T.eq(dat, ds.icopy(f))
  T.eq(4, #f); T.eq('four', f:get(#f))

  f:write': still in line four'; f:flush()
  T.eq('four: still in line four',          f:get(4))
  f:write' and this'; f:flush()
  T.eq('four: still in line four and this', f:get(4))

  T.eq('one\ntwo\nthree\n', pth.read(SMALL))
  f = assert(File{path=SMALL}); f.cache = ds.Forget{}
  T.eq({'one', 'two', 'three', ''}, ds.icopy(f))
  T.eq('two', f:get(2))

  f = File{TXT, mode='w+'}
  f:write'line 1\nline 2\nline 3'; f:flush()
  -- TODO: for some reason this sometimes has a HUGE number of indexes.
  -- ... are these tests running concurrently and I'm actually seeing
  -- the result of that?
  T.eq({0, 7, 14}, ds.icopy(f.idx))
  T.eq({'line 1', 'line 2', 'line 3'}, ds.icopy(f))

  local r = assert(f:reader())
  T.eq(3, #r)
  T.eq({'line 1', 'line 2', 'line 3'}, ds.icopy(r))
end

local function edEq(a, b, msg)
  T.eq(EdFile, getmetatable(a))
  T.eq(EdFile, getmetatable(b))
  T.eq(ds.icopy(a), ds.icopy(b), msg)
end

T'EdFile_index'; do
  local ef = mty.construct(EdFile, {lens={}, dats={
    ds.Slc{si=1, ei=2},
    ds.Slc{si=3, ei=6},
  }})

  -- test indexing logic itself
  T.eq(1, ef:_datindex(1))
  T.eq(1, ef:_datindex(2))
  T.eq({2}, ef.lens)

  T.eq(2, ef:_datindex(3))
  T.eq({2, 6}, ef.lens)
  T.eq(2, ef:_datindex(6))
  T.eq(6, #ef)

  ef.lens[2] = nil
  T.eq(nil, ef:_datindex(7))
  T.eq({2, 6}, ef.lens)
  T.eq(nil, ef:_datindex(0))

  -- test getting the index
  ef.dats = {
    {'one', 'two'},
    {'three', 'four', 'five', 'six'},
  }
  ef.lens = {}
  T.eq('one',   ef:get(1)); T.eq({2},    ef.lens)
  T.eq('three', ef:get(3)); T.eq({2, 6}, ef.lens)
  T.eq('six',   ef:get(6))
  T.eq(6, #ef)
end

T'EdFile_newindex'; do
  local S = function(si, ei) return ds.Slc{si=si, ei=ei} end
  local ef = EdFile()
  T.eq(0, #ef)
  T.eq({S(1, 0)},    ef.dats)

  ef:set(1, 'one')
  T.eq({S(1,1)}, ef.dats)
  T.eq({1},      ef.lens)
  T.eq('one', ef:get(1))

  ef:set(2, 'two')
  T.eq({S(1,2)}, ef.dats)
  T.eq({2}, ef.lens)
  T.eq('one', ef:get(1))
  T.eq('two', ef:get(2))

  ef:set(1, 'one 1')
  T.eq({Gap'one 1', S(2,2)}, ef.dats)
  T.eq({}, ef.lens)
  T.eq({'one 1', 'two'}, icopy(ef))
  T.eq({1, 2}, ef.lens); T.eq(2, #ef)
end

T'EdFile_write'; do
  local ed = EdFile(TXT, 'w+')
  ed:write'one\nthree\nfive'
  ed:flush()
  T.eq(3, #ed)
  T.eq('one\nthree\nfive', pth.read(TXT))
  T.eq({ds.Slc{si=1, ei=3}}, ed.dats)
  ed:write' 5'
  T.eq('five 5', ed:get(3))

  ds.inset(ed, 2, {'two'})
  local expect = {'one', 'two', 'three', 'five 5'}
  T.eq(expect, ds.icopy(ed))
  ds.inset(ed, 1, {'zero'})
  T.eq({
    'zero', 'one', 'two', 'three', 'five 5'
  }, ds.icopy(ed))
  T.eq({
    Gap'zero',
    ds.Slc{si=1, ei=1}, -- one
    Gap'two',
    ds.Slc{si=2, ei=3}, -- three\nfive 5
  }, ed.dats)

  ds.inset(ed, 1, {'zero 0', 'one 1'}, 2)
  expect = {
    'zero 0', 'one 1',
    'two', 'three', 'five 5'
  }
  T.eq(expect, ds.icopy(ed))
  T.eq({
    Gap'zero 0\none 1\ntwo',
    ds.Slc{si=2, ei=3}, -- three\nfive 5
  }, ed.dats)
  T.eq(5, #ed)
  ed:set(1, 'zero 0') -- same
  T.eq(expect, ds.icopy(ed))

  local f = assert(io.open(O..'ed.dump', 'w+'))
  ed:dumpf(f)
  f:flush(); f:seek'set'
  T.eq(5, #ed)
  T.eq(s[[
    zero 0
    one 1
    two
    three
    five 5
  ]], pth.read(O..'ed.dump'))
end

T'EdFile_big'; do
  local ed = EdFile(TXT, 'w+')
  for i=1,100 do ed:set(#ed+1, 'line '..i) end
  -- TODO: sometimes this reports 200 (ioAsync)
  T.eq(100, #ed)

  T.eq(ed:get(3), 'line 3')
  T.eq({ds.Slc{si=1, ei=100}}, ed.dats)

  ed:set(3, 'line 3.0')
  T.eq(ed:get(2), 'line 2')
  T.eq(ed:get(3), 'line 3.0')
  T.eq(ed:get(4), 'line 4')

  ds.inset(ed, 7, {'line 7.0', 'line 7.1', 'line 7.2'}, 1)
  T.eq(ed:get(6), 'line 6')
  T.eq(ed:get(7), 'line 7.0')
  T.eq(ed:get(10), 'line 8')
  T.eq(102, #ed)
end

local function newEdFile(text, ...)
  local ed = assert(EdFile())
  if type(text) == 'string' then ed:write(text)
  else ds.extend(ed, text) end
  ed:flush()
  return ed
end

T'EdFile_linesOffset'; do
  testing.testOffset(newEdFile(testing.DATA.offset))
end

T'EdFile_linesRemove'; do
  testing.testLinesRemove(newEdFile, edEq, ds.noop)
end

T'EdFile_inset'; do
  require'ds.testing'.testInsetStr(newEdFile, edEq)
end
fin = true
end -- tests()

fin = false; tests(); assert(fin)

if G.NOLIB then return end

-- Continue tests with fd
local fd = require'fd'

fd.ioSync(); T.SUBNAME = '[ioSync]'
fin = false; tests(); assert(fin)

-- TODO: file async not working.
-- T.SUBNAME = '[ioAsync]'
-- fin=false; require'civix.testing'.runAsyncTest(tests); assert(fin)

fd.ioStd(); T.SUBNAME = ''