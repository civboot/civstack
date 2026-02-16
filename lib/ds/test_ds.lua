local function testloc()  return require'ds'.srcloc() end
local function testshort() return require'ds'.shortloc() end
local loc1, loc2 = testloc(), testshort()
local function a() error'a error' end
local function b() a() end; local c = function() b() end

local push, yield = table.insert, coroutine.yield
local pop = table.remove
local sfmt = string.format

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'; local M = ds
local lines = require'lines'
local testing = require'lines.testing'
local M = require'ds'
local time = require'ds.time'

local T = require'civtest'

local bound, isWithin, sort2, absDec,
  indexOf, copy, deepcopy,
  trim,
  extend, clear, merge,
  getOrSet, getp, setp,
  drain, reverse,
  Set
  = mty.from(M, [[
  bound, isWithin, sort2, absDec,
  indexOf, copy, deepcopy,
  trim,
  extend, clear, merge,
  getOrSet, getp, setp,
  drain, reverse,
  Set
]])
local Duration, Epoch, DateTime = mty.from'ds.time  Duration,Epoch,DateTime'
local d8 = require'ds.utf8'
local dp = M.dotpath
local pth = require'ds.path'
local s = M.simplestr
local LL = require'ds.LL'

local D = ds.srcdir()

---------------------
-- ds.lua

T'loc'; do
  -- FIXME
  -- T.eq('lib/tests/test_ds.lua:3', loc1)
  -- T.eq('ds/test_ds.lua:3', loc2)

  -- T.eq(   'lib/tests/',          M.srcdir())
  -- local function fn()
  --    T.eq(   'lib/tests/',          M.srcdir())
  --    T.eq(   'lib/tests/',          M.srcdir(1))
  -- end; fn()
end

T'simplestr'; do
  T.eq('a', [[
a]])
  T.eq('this is\n  a simple str.', s[[
    this is
      a simple str.]])

  T.eq('easy',    s[[easy]])
  T.eq('easy  ',  s[[  easy  ]])
  T.eq('easy\nhi\nthere',  s[[easy
    hi
    there]])
  T.eq('easy',  s[[
  easy]])
  T.eq('newline\n\n', s[[
  newline

  ]])
end

T'binString'; do
  T.eq('0000_1000', M.bin(8))
  T.eq('1100_1010', M.bin(0xCA))
  T.eq('1000',      M.bin(8, 4))
  T.eq('0_1000',    M.bin(8, 5))
end

T'bool_and_none'; do
  local none = assert(M.none)
  T.eq(false, M.bool())
  T.eq(false, M.bool(false))
  T.eq(false, M.bool(none))
  T.eq(true, M.bool(true))
  T.eq(true, M.bool(''))
  T.eq(true, M.bool(0))
  T.eq(true, M.bool({}))
  assert(none) -- truthy, use ds.bool for falsy
  assert(rawequal(none, none))
  assert(none == none)
  T.eq(none, none)
  assert(none ~= {})
  assert(not mty.eq(none, {}))
  T.eq('none', getmetatable(none))
  T.eq('none', mty.ty(none))
  T.eq('none', fmt(none))
  local err = 'invalid operation on sentinel'
  T.throws(err, function() none.foo = 3 end)
  T.throws(err, function() return #none end)
end

T'imm'; do
  T.eq({}, M.empty)
  T.eq(nil, next(M.empty))
  T.eq(0,  #M.empty)
  T.eq('table', getmetatable(M.empty))

  local t = M.Imm{1, 2, v=3}
  T.eq(1, t[1])
  T.eq(3, t.v)
  T.eq('table', getmetatable(t))
  assert('table', debug.getmetatable(t).__metatable)
  T.eq('table', mty.ty(t))
  T.throws('cannot modify Imm', function() t.b = 8 end)
  T.throws('cannot modify Imm', function() t.v = 8 end)
  T.eq('<!imm data!>', next(t))
  local j = {1, 2, v=3}
  local k = M.Imm{1, 2, v=4}
  assert(t == t); assert(t ~= j)
  T.eq(t, t)
  T.eq(t, j)

  assert(t ~= k); assert(not mty.eq(t, k))
  T.eq('{1, k=5}', fmt(M.Imm{1, k=5}))
  T.eq('table', mty.tyName(M.Imm{}))

  T.eq({1, 2, v=3}, j) -- table vs Imm
  assert(not mty.eq({1, 2}, j))

  T.eq({kind='Empty'}, M.Imm{kind='Empty'})
end

T'number'; do
  assert(0, absDec(1)); assert(0, absDec(-1))

  assert(1 == bound(0, 1, 5))
  assert(1 == bound(-1, 1, 5))
  assert(3 == bound(3, 1, 5))
  assert(5 == bound(7, 1, 5))
  assert(5 == bound(5, 1, 5))
  assert(    isWithin(1, 1, 5))
  assert(not isWithin(0, 1, 5))
  assert(    isWithin(3, 1, 5))
  assert(    isWithin(5, 1, 5))
  assert(not isWithin(6, 1, 5))

  local a, b = sort2(1, 2); assert(a == 1); assert(b == 2)
  local a, b = sort2(2, 1); assert(a == 1); assert(b == 2)

  T.eq(4, ds.max(1, 4))
  T.eq(3, ds.max(3, 2))
end

T'str'; do
  T.eq('hi there', trim('  hi there\n '))
  T.eq('hi there', trim('hi there'))
  local multi = [[  one

three
four

]]
  T.eq('  one\n\nthree\nfour\n\n', multi)
  T.eq('one\n\nthree\nfour', trim(multi))

  T.eq('  a b c', M.trimEnd'  a b c')
  T.eq('  a b c', M.trimEnd'  a b c\n  ')

  T.eq(' a bc d e ', M.squash'  a   bc \td\te ')

  local u8 = "high🫸 five 🫷!"
  -- test utf8.offset itself
  local off = utf8.offset
  T.eq(4, off(u8, 4))
  T.eq(5, off(u8, 5)) -- start of 🫸
  T.eq(9, off(u8, 6));     T.eq(' five 🫷!', u8:sub(9))
  T.eq(9, off(u8, 1, 9))
  T.eq(19, off(u8, 8, 9)); T.eq('!', u8:sub(19))
  T.eq(2, off('a', 2))

  T.eq("high", M.usub(u8, 1, 4))
  T.eq("🫸 f", M.usub(u8, 5, 7))
  T.eq("🫷!",  M.usub(u8, -2))
  T.eq("e 🫷", M.usub(u8, -4, -2))
  T.eq('',     M.usub(u8, 100))
end

T'table'; do
  local t1, t2 = {1, 2}, {3, 4}
  assert(1 == indexOf(t2, 3)); assert(2 == indexOf(t2, 4))

  t1.a = t2
  local r = deepcopy(t1)
  assert(r[1] == 1)
  assert(r.a[1] == 3)
  t2[1] = 8
  assert(r.a[1] == 3)

  local t = {a=8, b=9}
  assert(8 == M.popk(t, 'a')) assert(9 == M.popk(t, 'b'))
  assert(0 == #t)

  T.eq(5,   getOrSet({a=5}, 'a', function() return 7 end))
  T.eq(7,   getOrSet({b=5}, 'a', function() return 7 end))
  T.eq(7,   getp({a={b=7}}, {'a', 'b'}))
  T.eq(nil, getp({}, {'a', 'b'}))

  T.eq({'d', 'e'},
    M.rmleft({'a', 'b', 'c', 'd', 'e'}, {'a', 'b', 'c'}))
  local t = {}
  setp(t, dp'a.b',   4);   T.eq(4, t.a.b)
  setp(t, dp'a.a.a', 5);   T.eq(5, t.a.a.a)
  setp(t, dp'a.a.a', nil); T.eq(nil, t.a.a.a)
  setp(t, dp'a.b',   4);   T.eq(4, t.a.b)

  t = {}; for i, v in M.inext, {4, 5, 8}, 0 do t[i] = v end
  T.eq({4, 5, 8}, t)
  t = {}; for i, v in M.iprev, {4, 5, 8}, 4 do t[i] = v end
  T.eq({4, 5, 8}, t)
  t = {}; for i, v in M.ireverse{4, 5, 8} do t[i] = v end
  T.eq({4, 5, 8}, t)

  t = {}; for i, v in M.islice({5, 6, 7, 8, 9}, 2, 4) do push(t, v) end
  T.eq({6, 7, 8}, t)

  t = {}
  M.walk(
    {1, 2, a=3, inner={b=9, c='hi'}},
    function(k, v) t[k] = v end,
    function(k, v) t[k] = true end)
  T.eq({1, 2, a=3, b=9, c='hi', inner=true}, t)

  t = M.Forget{a=4}
  T.eq(4, t.a)
  t.b = 7; t[1] = 4
  T.eq(nil, t.b); T.eq(nil, t[1])

  T.eq({1, 2}, merge({1}, {2}))
  T.eq({1, 2, a='a2'}, merge({1, a='a1'}, {2, a='a2'}))
  T.eq({
    l = {1, 2},
    t = {a='a1', b='b2'},
  }, merge({l={1}, t={a='a1', b='b1'}}, {l={2}, t={b='b2'}}))

  T.eq(2, M.pairlen{1, 2})
  T.eq(3, M.pairlen{1, 2, z=4})

  T.eq({4, 2, 3}, M.icopy{4, 2, 3, a=4})

  T.eq({'a', 'b', 'c'}, M.orderedKeys{a=1, b=2, c=3})
  T.eq({'a', 'b', 'c', a=1, b=2, c=3}, M.pushSortedKeys{a=1, b=2, c=3})

  T.eq({1}, M.sortUnique{1})
  T.eq({'a', 'b', 'c'}, M.sortUnique{'c', 'b', 'a'})
  T.eq({'a', 'b', 'c'}, M.sortUnique{'a', 'c', 'b', 'a'})
  T.eq({'.', 'h', 's'}, M.sortUnique{'h', '.', 's', 'h'})

  T.eq({1,2,3,4,5}, M.orderedMerge({1,3,5}, {2, 4}))
end

T'freeze'; do
  local freeze = require'metaty.freeze'
  local t = freeze{1, 2, a='a1', b='b2', t={3, 4}}
  T.eq(1, t[1]); T.eq(2, t[2]); T.eq('a1', t.a)
  local c = ds.copy(t)
  T.eq(t, c)
end

T'Slc'; do
  local Slc = M.Slc
  local a = Slc{si=2, ei=10}
  T.eq(9, #a); T.eq('Slc[2:10]', fmt(a))
  T.eq({Slc{si=2, ei=14}}, {a:merge(Slc{si=4, ei=14})})

  local expect = {Slc{si=2, ei=10}, Slc{si=12, ei=13}}
  T.eq(expect, {a:merge(Slc{si=12, ei=13})})
  T.eq(expect, {Slc{si=12, ei=13}:merge(a)})
end

T'list'; do
  local t = {4, 5, 6}
  T.eq(4, M.geti(t, 1))
  T.eq(6, M.geti(t, -1))
  T.eq(5, M.geti(t, -2))

  T.eq({1, 2, 3}, extend({1}, {2, 3}))
  local t = {4, 5}; extend(t, {1, 2})
  T.eq({4, 5, 1, 2}, t)
  T.eq({}, clear{1, 2, 3})

  T.eq({1,2,5,7}, M.flatten{{1,2},{5},{7}})

  local l = {'a', 'b', 'c', 1, 2, 3}
  T.eq({1, 2, 3}, drain(l, 3))
  T.eq({'a', 'b', 'c'}, l)
  T.eq({}, drain(l, 0))
  T.eq({'a', 'b', 'c'}, l)
  T.eq({'c'}, drain(l, 1))
  T.eq({'a', 'b'}, l)
  T.eq({'a', 'b'}, drain(l, 7))
  T.eq({}, l)

  T.eq({2, 1},    reverse({1, 2}))
  T.eq({3, 2, 1}, reverse({1, 2, 3}))

  require'ds.testing'.testInset(ds.iden)
  require'ds.testing'.testInsetStr(ds.iden)
end

T'Set'; do
  local s = Set{'a', 'b', 'c'}
  T.eq(Set{'a', 'c', 'b'}, s)
  T.eq(Set{'a', 'b'}, s:union(Set{'a', 'b', 'z'}))
  T.eq(Set{'a'}, s:diff(Set{'b', 'c', 'z'}))
end

T'LL'; do
  local h, _ = LL(2)
  T.eq({2}, h:tolist())

  -- '+' and '-'
  local res = h - LL(4)      T.eq({2, 4}, h:tolist())
  local t = h:tail();        assert(rawequal(t, res))
  _= h - (LL(5) + 6);        T.eq({2, 4, 5, 6}, h:tolist())

  -- pop
  h = LL:from{1, 2, 3, 4};   T.eq({1, 2, 3, 4}, h:tolist())
  local n2 = h.r
  local n3 = n2.r
    assert(not (rawequal(h, n2) or rawequal(h, n3)))
    assert(rawequal(n2,  h:get(1)))
    assert(rawequal(h,   n2.l))

  T.eq(nil, n2:rm())
    T.eq({1, 3, 4}, h:tolist())
    assert(rawequal(h.r, n3))
    assert(rawequal(h,   n3.l))
    assert(rawequal(n3, h:rm())) -- new head

  -- insert
  h = LL:from{1, 3, 4}
  h:insert(2);        T.eq({1, 2, 3, 4},    h:tolist())
    assert(rawequal(h, h.r.l))
  h:tail():insert(5); T.eq({1, 2, 3, 4, 5}, h:tolist())
    T.eq(4, h:tail().l.v)

  T.eq('LL{1 -> 3 -> 5}', fmt((LL:from{1, 3, 5})))
end

T'binary-search'; do
  local bs = M.binarySearch
  local t = {1, 5, 8, 10, 12, 33}
  T.eq(0,   bs(t, -1))
  T.eq(1,   bs(t, 1))  T.eq(1,   bs(t, 4))
  T.eq(2,   bs(t, 5))  T.eq(2,   bs(t, 7))
  T.eq(5,   bs(t, 12)) T.eq(5,   bs(t, 32))
  T.eq(6,   bs(t, 33)) T.eq(6,   bs(t, 1024))
end

T'time'; do
  local N = require'ds.time'.NANO
  local d = Duration(3, 500)
  T.eq(Duration(2, 500),     Duration(3, 500) - Duration(1))
  T.eq(Duration(2, N - 900), Duration(3, 0)   - Duration(0, 900))
  T.eq(Duration(2, N - 800), Duration(3, 100) - Duration(0, 900))
  T.eq(Duration(2), Duration:fromMs(2000))
  assert(Duration(2) < Duration(3))
  assert(Duration(2) < Duration(2, 100))
  assert(not (Duration(2) < Duration(2)))
  T.eq(Duration(1.5), Duration(1, N // 2))
  T.eq('1.5s', tostring(Duration(1.5)))

  T.eq(Epoch(1) - Duration(1), Epoch(0))
  T.eq(Epoch(1) - Epoch(0), Duration(1))
  local e =    Epoch(1000001, 12342)
  T.eq(Duration(1), e - Epoch(1000000, 12342))
  T.eq('Epoch(1.5s)', tostring(Epoch(1.5)))
  assert(not mty.eq(e, Epoch(1,1)))
  assert(not mty.eq(e, Epoch(1000001, 12345)))
  T.eq(e, ds.max(e, Epoch(1,1)))
  T.eq(e, ds.max(Epoch(1,1), e))

  T.eq(true, rawequal(e, ds.max(e, Epoch(1000001 - 1, 12342))))
  local e2 = Epoch(1000001, 12342 + 1)
  T.eq(e2, ds.max(e2, e))
  T.eq(e2, ds.max(e, e2))

  local e1 = Epoch(1769988703.7927)
  local e2 = Epoch(1769920691.902)
  T.eq(e1, ds.max(e1, e2))

  local tz = time.Tz:of(-7)
  T.eq('Z', time.Z.name)
  T.eq('-07:00', tz.name)

  local dtZ = DateTime:of(1, time.Z)
  T.eq(DateTime{ y=1970, yd=0,  s=1,     ns=0, tz=time.Z, wd=5 }, dtZ)
  T.eq(Epoch(1), dtZ:epoch())

  local s = 1770002194 -- epoch time stamp
  local dt = DateTime:of(s, time.Z)
  T.eq(DateTime{ y=2026, yd=32, s=11794, ns=0, tz=time.Z, wd=2 }, dt)

  T.eq(2026,      dt.y)
  T.eq({2,2},     {dt:date()})
  T.eq({3,16,34}, {dt:time()})
  T.eq('2026-02-02T03:16:34Z', tostring(dt))
  T.eq(Epoch(s), dt:epoch())

  dt.ns, dt.tz = nil, nil -- to test _ofFuture()
  T.eq(dt, DateTime:_ofFuture(s))
end

local function assertPath(fn, expect, p)
  T.eq(expect, fn(p))       -- pass in string
  T.eq(expect, fn(pth(p))) -- pass in table
end
T'ds_path'; do
  T.eq({'a', 'b', 'c'},  pth('a/b/c'))
  T.eq({'/', 'b', 'c'},  pth('/b/c'))
  T.eq({'a', 'b', 'c/'}, pth('a/b/c/'))
  T.eq({},               pth'')
  T.eq({'a', 'b', 'c'},  pth{'a', 'b', 'c'})
  T.eq({'/', 'b', 'c'},  pth{'/', 'b', 'c'})

  local pc = pth.concat
  T.eq('foo/bar',   pc{'foo/', 'bar'})
  T.eq('/foo/bar',  pc{'/foo/', 'bar'})
  T.eq('/foo/bar/', pc{'/foo/', 'bar/'})
  T.eq('',          pc{''})
  T.eq('foo',       pc{'', 'foo'})
  T.eq('foo',       pc{'foo', ''})
  T.eq('a/b',       pc{'a', '', 'b'})
  T.eq('a/b',       pc{'a/', '', 'b'})

  local pr = pth.resolve
  T.eq('/.a',      pr('/.a'))
  T.eq('/..a',     pr('/..a'))
  T.eq('/a.',      pr('/a.'))
  T.eq('/a..',     pr('/a..'))
  T.eq('a/',       pr'a/b/..')
  T.eq('b',        pr'a/../b')
  T.eq('b/',       pr'a/../b/')
  T.eq('/a/b/', pr('..',       '/a/b/c/'))
  T.eq('/a/d/', pr('../../d/', '/a/b/c/'))
  T.eq('//',       pr('/a/..')) -- FIXME
  T.eq('',         pr('a/..'))
  T.throws('before root', function() pr('/..')    end)
  T.throws('before root', function() pr('/../..') end)
  T.throws('before root', function() pr('/../../a') end)
  T.throws('before root', function() pr('/a/../..') end)
  T.throws('before root', function() pr('/a/../../') end)

  assert(#pth.cwd() ~= 1, pth.cwd())
  T.eq(pth.abs'', pth.cwd())
  T.eq(pth.abs{}, pth(pth.cwd()))

  local pn = pth.nice
  T.eq('./',        pn('a/..'))
  T.eq('/a/b/',     pn('..', '/a/b/c/'))
  T.eq('d/e',       pn('/a/b/c/d/e',  '/a/b/c'))
  T.eq('d/e/',      pn('/a/b/c/d/e/', '/a/b/c'))
  T.eq('a',         pn('./a'))

  local pe = pth.ext
  assertPath(pe, 'foo', 'coo.foo')
  assertPath(pe, 'foo', 'a/b/c.foo')
  assertPath(pe, 'bar', 'a/b.c/d.foo.bar')

  local pf = pth.first
  T.eq({'/',  'a/b/c/'}, {pf'/a/b/c/'})
  T.eq({'a',  'b/c/'},   {pf'a/b/c/'})
  T.eq({'/',  'a/b/'},   {pf'/a/b/'})
  T.eq({'/',  'a/b'},    {pf'/a/b'})
  T.eq({'/',  'b'},      {pf'/b'})
  T.eq({'b',  ''},       {pf'b'})
  T.eq({'/',  'b/'},     {pf'/b/'})
  T.eq({'/',  ''},       {pf'/'})

  local function plast(expect, p)
    T.eq(expect,    {pth.last(p)})
    T.eq(expect[1], pth.dir(p))
  end
  plast({'/a/b/', 'c/'}, '/a/b/c/')
  plast({'a/b/', 'c/'},  'a/b/c/')
  plast({'/a/', 'b/'},   '/a/b/')
  plast({'/a/', 'b'},    '/a/b')
  plast({'/',  'b'},     '/b')
  plast({'./', 'b'},     'b')
  plast({'/',  'b/'},    '/b/')
  plast({nil,  '/'},     '/')

  T.eq(true, pth.isDir('/'))
  T.eq('/',  pth.toDir('/'))
  T.eq('a/', pth.toDir('a'))
  T.eq('a',  pth.toNonDir('a'))
  T.eq('a',  pth.toNonDir('a/'))

  T.eq({'y', 'z/z', 'a/', 'a/b/'},
    M.sort({'a/', 'a/b/', 'z/z', 'y'}, pth.cmpDirsLast))

  local rel = pth.relative
  T.eq('a/b',        rel('',   'a/b'))
  T.eq('../a/b',     rel('c/', 'a/b'))
  T.eq('../bin/foo', rel('lua/foo.lua', 'bin/foo'))
  T.eq('baz/bob', rel('/foo/bar',  '/foo/baz/bob'))
  T.eq('../baz/bob', rel('/foo/bar/', '/foo/baz/bob'))
  T.eq('../baz/bob', rel('/foo/bar/', '/foo/baz/bob'))
  T.eq('../baz/bob', rel('/foo/bar/', '/foo/baz/bob'))
  T.eq('bar/baz/', rel('/foo/', '/foo/bar/baz/'))
end

local heap = require'ds.heap'

local function pushh(h, t)
  for i, v in ipairs(t) do h:add(v) end
end

local function assertPops(expect, h)
  local t = {}; while #h > 0 do
    push(t, h:pop())
  end
  T.eq(expect, t)
end
T'heap'; do
  local h = heap.Heap{1, 5, 9, 10, 3, 2}
  assertPops({1, 2, 3, 5, 9, 10}, h)
  T.eq(0, #h)
  pushh(h, {8, 111, -1, 333, 42})
  T.eq(heap.Heap{-1, 42, 8, 333, 111}, h)
  assertPops({-1, 8, 42, 111, 333}, h)

  h = heap.Heap{1, 5, 9, 10, 3, 2, cmp=M.gt}
  assertPops({10, 9, 5, 3, 2, 1}, h)

  h = heap.Heap{{3}, {2}, {1}, cmp=function(a, b) return a[1] < b[1] end}
  assertPops({{1}, {2}, {3}}, h)
end

T'dag'; do
  local childrenMap = {
    a = {'b', 'c'},
    b = {'c', 'd'},
    c = {'d'}, d = {},
  }
  local res = M.dagSort({'a'}, childrenMap)

  T.eq({'d', 'c', 'b', 'a'}, M.dagSort({'a'}, childrenMap))
  childrenMap.d = {'a'}
  local res, cycle = M.dagSort({'a'}, childrenMap)
  assert(not res)
  T.eq({'a', 'b', 'c', 'd', 'a'}, cycle)
end

T'bimap'; do
  local bm = M.BiMap{'one', 'two'}
  T.eq(bm[1], 'one');   T.eq(bm.one, 1)
  T.eq(bm[2], 'two');   T.eq(bm.two, 2)
  bm[3] = 'three'
  T.eq(bm[3], 'three'); T.eq(bm.three, 3)
  T.eq('BiMap{"one", "two", "three", one=1, three=3, two=2}',
           fmt(bm))

  local bm = M.BiMap{a='A'}
  T.eq(bm.a, 'A'); T.eq(bm.A, 'a')
  bm.b = 'B'
  T.eq(bm.b, 'B'); T.eq(bm.B, 'b')
  T.eq('BiMap{A="a", B="b", a="A", b="B"}'
       , fmt(bm))
end

T'deq'; do
  local d = M.Deq()
  d:pushRight(4); T.eq(1, #d)
  d:pushRight(5); T.eq(2, #d)
  d:pushLeft(3);  T.eq(3, #d)
  T.eq(3, d());          T.eq(2, #d)
  T.eq(5, d:popRight()); T.eq(1, #d)
  T.eq(4, d());          T.eq(0, #d)

  d = M.Deq()
  d:extendRight{1, 2}; d:extendLeft{4, 5}; d:extendRight{6, 7}
  setmetatable(d, nil)
  T.eq({[-1]=4, [0]=5, 1, 2, 6, 7, left=-1, right=4},
    setmetatable(d, nil))
  T.eq({4, 5, 1, 2, 6, 7}, setmetatable(d, M.Deq):drain())
  T.eq({left=1, right=0}, setmetatable(d, nil))
end

local TB = [[
stack traceback:
        [C]: in function 'string.gsub'
        lib/ds/ds.lua:1064: in function 'ds.tracelist'
        lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>
]]
T'error'; do
  T.throws('expect failure', function()
    M.check(3, nil, nil, 'expect failure', 'other')
  end)
  T.eq({'a', nil, 'c'}, {M.check(2, 'a', nil, 'c')})

  T.eq({
    "[C]: in function 'string.gsub'",
    "lib/ds/ds.lua:1064: in function 'ds.tracelist'",
    "lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>"
  }, M.tracelist(TB))

  local ok, err = M.try(c)
  T.eq(false, ok)
  M.clear(err.traceback, 4)
  local expect = M.Error{
    msg='a error',
    traceback={
      D.."test_ds.lua:4",
      D.."test_ds.lua:4: in upvalue 'a'",
      D.."test_ds.lua:5: in upvalue 'b'",
    },
  }
  T.eq(expect, err)

  local cor = coroutine.create(c)
  local ok, msg = coroutine.resume(cor)
  assert(not ok)

  push(expect.traceback, D.."test_ds.lua:5: in function <"..D.."test_ds.lua:5>")
  T.eq(expect, M.Error.from(msg, cor))
end

---------------------
-- ds/Iter.lua
T'ds.Iter'; do
  local It = require'ds.Iter'
  local t = {4, 5, 'six', 7}

  local isNumber = function(v) return type(v) == 'number' end
  local numberVals = function(k, v) return isNumber(v)    end
  local plus2 = function(v) return v + 2 end
  local vToString = function(k, v) return k, tostring(v)  end

  T.eq(t, It:ofList(t):to())
  T.eq(t, It:of(t):to())
  T.eq(t, It:ofList(t):valsTo())
  T.eq({1, 2, 3, 4}, It:ofList(t):keysTo())

  T.eq({4, 5, [4]=7}, It:ofList(t):filter(numberVals):to())
  T.eq({1, 2, 4}, It:ofList(t):filter(numberVals):keysTo())
  T.eq({4, 5, 7}, It:ofList(t):filter(numberVals):valsTo())

  T.eq({4, 5, 7}, It:ofList(t):filterV(isNumber):valsTo())
  T.eq({6, 7, 9},
    It:ofList(t):filterV(isNumber):mapV(plus2):valsTo())

  local strs = {'4', '5', 'six', '7'}
  T.eq(strs, It:ofList(t):map(vToString):to())
  T.eq(strs, It:ofList(t):mapV(tostring):to())
  T.eq({1, 2, 3, 4}, It:ofList(t):mapV(tostring):keysTo())

  T.eq({['1'] = 4, ['2'] = 5, ['3'] = 'six', ['4'] = 7},
    It:of(t):mapK(tostring):to())

  local lk = {11, 22, 33, 44, 55, 'unused', 77, six=666}
  T.eq({11, 22, 33,  44}, It:ofList(t):lookupK(lk):keysTo())
  T.eq({44, 55, 666, 77}, It:of(t):lookupV(lk):to())


  local it = It:ofList(t):lookupK(lk)
  local res = {}; for k, v in it do push(res, k)end
  T.eq({11, 22, 33,  44}, res)

  local it = It:ofList(t):lookupK(lk)
  local res = {}; for k, v in it do push(res, k)end
  T.eq({11, 22, 33,  44}, res)

  -- reset
  local res = {}; for k, v in it:reset() do push(res, k)end
  T.eq({11, 22, 33,  44}, res)

  local it = It:ofList(t):lookupV(lk)
  local res = {}; for k, v in it do res[k] = v end
  T.eq({44, 55, 666, 77}, res)

  -- use a big table
  local t = {}; for i=100,1,-1 do t[sfmt('%03i', i)] = i end
  T.eq(t['001'], 1); T.eq(t['100'], 100);
  local expect = {}; for i=1,100  do expect[i] = i end
  T.eq(expect, It:ofOrdMap(t):valsTo())
  T.eq(expect, It:ofOrdMap(t):index():to())

  T.eq({a=1, b=2, c=3}, It:of{'a', 'b', 'c'}:swap():to())

  local t = {10, 20, 30, 40, 50, 60}
  T.eq({40, 50, 60},             It:ofSlc(t, 4):valsTo())
  T.eq({[4]=40, [5]=50, [6]=60}, It:ofSlc(t, 4):to())

  T.eq({[2]=20, [4]=40}, It:of(t):keyIn{[2]=1,  [4]=1}:to())
  T.eq({[2]=20, [4]=40}, It:of(t):valIn{[20]=1, [40]=1}:to())

  T.eq(true,  It:of{true, true, true}:all())
  T.eq(false, It:of{true, false, true}:all())
  T.eq(true,  It:of{false, false, true, false}:any())
  T.eq(false, It:of{false, false, false, false}:any())

  It{ipairs{11, 12, 13}}:assertEq(It{ipairs{11, 12, 13}})

  local i = 0
  local it = It{function()
    if i >= 3 then return end
    i = i + 1; return i, 10 + i
  end}
  It{ipairs{11, 12, 13}}:assertEq(it)

  it = It:ofUnpacked{{11, 'first'}, {22, 'second'}}
  T.eq({11, 'first'},  {it()})
  T.eq({22, 'second'}, {it()})
  T.eq(nil, it())
end

---------------------
-- ds/utf8.lua

local function testU8(expect, chrs)
  local len = d8.decodelen(chrs[1]); assert(len, 'len is nil')
  T.eq(#chrs, len)
  c = d8.decode(chrs)
  T.eq(expect, utf8.char(c))
end

-- chrs were gotten from python:
--   print('{'+', '.join('0x%X' % c for c in '🙃'.encode('utf-8'))+'}')
-- Edge case characters are from:
--   https://design215.com/toolbox/ascii-utf8.php
T'u8edges'; do
  testU8('\0', {0})
  testU8(' ', {0x20})
  testU8('a', {string.byte('a')})
  testU8('~', {0x7E})

  testU8('¡', {0xC2, 0xA1})
  testU8('ƒ', {0xC6, 0x92})
  testU8('߿', {0xDF, 0xBF})

  testU8('ࠀ', {0xE0, 0xA0, 0x80})
  testU8('ἰ', {0xE1, 0xBC, 0xB0})
  testU8('‡', {0xE2, 0x80, 0xA1})
  testU8('➤', {0xE2, 0x9E, 0xA4})
  testU8('⮝', {0xE2, 0xAE, 0x9D})
  testU8('€', {0xE2, 0x82, 0xAC})
  testU8('�', {0xEF, 0xBF, 0xBD})

  testU8('𒀀',  {0xF0, 0x92, 0x80, 0x80})
  testU8('🙃', {0xF0, 0x9F, 0x99, 0x83})
  testU8('🧿', {0xF0, 0x9F, 0xA7, 0xBF})
end

-----------------
-- Log
T'log'; do
  local L = require'ds.log'
  local fn, lvl = assert(LOGFN), assert(LOGLEVEL)
  local logs = {}
  LOGLEVEL = L.levelInt'INFO'
  LOGFN = function(lvl, loc, ...)
    push(logs, {lvl, ...}) -- skip loc
  end
  L.info'test info';              T.eq({4, 'test info'}, pop(logs))
  L.info('test %s', 'fmt')
    T.eq({4, 'test %s', 'fmt'}, pop(logs))

  L.info('test %s', 'data', {1})
    T.eq({4, 'test %s', 'data', {1}}, pop(logs))

  LOGLEVEL = L.levelInt'WARN'
  L.info'test no log'; T.eq(0, #logs)
  L.warn'test warn';   T.eq({3, 'test warn'}, pop(logs))
  T.eq(0, #logs)
  LOGFN = fn

  LOGLEVEL = L.levelInt'INFO'
  -- test writing
  local cxt = ' [%d:]+ ds/test_ds.lua:%d+: '
  local iofmt = io.fmt
  local f = io.tmpfile()
  io.fmt = fmt.Fmt:pretty{to=f}
  local assertLog = function(lvl, expect, fn, ...)
    f:seek'set'; fn(...); f:seek'set'
    local res = f:read'a'
    local m = lvl..cxt; T.matches(m, res)
    T.eq(expect, res:sub(#res:match(m) + 1))
  end
  assertLog('I', 'test 42\n', L.info, 'test %s', 42)
  assertLog('I', 'test data {1}\n', L.info, 'test %s', 'data', {1})
  assertLog('I', 't {\n    1, 2, \n    key=42\n  }\n',
            L.info, 't', {1, 2, key=42})
  io.fmt = iofmt
  LOGLEVEL = lvl
end

-----------------
-- Grid
T'Grid'; do
  local Grid = require'ds.Grid'
  local g = Grid{h=3, w=20}
    T.eq('\n\n', fmt(g))
  g:insert(2, 2, 'hello')
    T.eq('\n hello\n', fmt(g))
  g:insert(2, 4, ' is my friend') -- keeps 'he'
    T.eq('\n he is my friend\n', fmt(g))

  g:clear(); T.eq('\n\n', fmt(g))
  g:insert(1, 3, 'hi\n  bye\nfin')
    T.eq('  hi\n'
           ..'    bye\n'
           ..'  fin', fmt(g))

  g:insert(1, 10, 'there\nthen\n!')
    T.eq('  hi     there\n'
           ..'    bye  then\n'
           ..'  fin    !', fmt(g))

  g = Grid{h=3, w=20}
  g:insert(1, 1, {"13 5 7 9", " 2 4 6", ""})
    T.eq('13 5 7 9\n 2 4 6\n', fmt(g))

  g = Grid{h=3, w=20}
  g:insert(2, 3, "hi")
    T.eq('\n  hi\n', fmt(g))
  g:insert(1, 6, "ab\ncd\nef")
    T.eq(
      '     ab\n'
    ..'  hi cd\n'
    ..'     ef', fmt(g))
end

-----------------
-- ds.lib (ds.c, ds.h)

if G.NOLIB then print'skip bytearray' else
T'bytearray'; do
  local bytearray = ds.bytearray
  T.eq('bytearray', bytearray.__name)
  T.eq('bytearray type', getmetatable(bytearray).__name)

  local b = bytearray"test data";
  T.eq('test data', tostring(b))
  T.eq('test data', b:sub())
  T.eq(9, #b)
  T.eq('st',   b:sub(3,4))
  T.eq('data', b:sub(-4));   T.eq('data', b:sub(-4, -1))
  T.eq('dat', b:sub(-4, 8)); T.eq('dat', b:sub(-4, -2))
  b:extend(', and more data.', '.. and some more')
  T.eq('test data, and more data... and some more', b:sub())

  b:write'fun.'
  T.eq('fun. data', b:sub(1,9))
  T.eq(4, b:pos())

  b:len(9);       T.eq('fun. data',    b:sub())
  b:len(12, 'z'); T.eq('fun. datazzz', b:sub())
  
  b:write" That's what programming in lua is!"
  T.eq("fun. That's what programming in lua is!", b:sub())
  b:len(4); b:replace(1, "Wow"); T.eq("Wow.", b:sub())
  b:pos(0); T.eq("Wo", b:read(2)); T.eq("w.", b:read'*a');
  b:pos(0); b:write'line 1\nline 2'
  b:pos(0); T.eq('line 1',   b:read'l'); T.eq('line 2', b:read'l')
            T.eq(nil, b:read'l')
  b:pos(0); T.eq('line 1\n', b:read'L'); T.eq('line 2', b:read'L')
            T.eq(nil, b:read'L')
  b:pos(0);
  local lines = {}; for l in b:lines() do push(lines, l) end
  T.eq({'line 1', 'line 2'}, lines)

  b:close()
  T.eq('', b:sub())
end
end -- if not G.NOLIB

T'string.concat'; do
  local sc = string.concat
  T.eq('',             sc(''))
  T.eq('one',          sc(' ', 'one'))
  T.eq('1 2',          sc(' ', '1', 2))
  T.eq('12',           sc('', '1', 2))
  T.eq('one-two-true', sc('-', 'one', 'two', 'true'))
end

T'table.update'; do
  local tu = table.update
  T.eq({},       tu({},  {}))
  T.eq({1},      tu({},  {1}))
  T.eq({1, a=3}, tu({1}, {a=3}))
  T.eq({1, a=3, b=44, c=5},
        tu({1, a=3, b=4}, {b=44, c=5}))
end

T'table.push'; do
  local tp = table.push
  local t = {1, 2, a=3}
  T.eq(3, tp(t, 3)); T.eq({1, 2, 3, a=3}, t)
end

T'load'; do
  local dload = require'ds.load'
  local env = {}
  local ok, res = dload(D..'data/load_data.lua', env)
  assert(ok, res or 'unknown')
  T.eq({answer=42, formatted='answer: 42'}, res)

  T.eq(getmetatable(env), dload.ENV); setmetatable(env, nil)
  T.eq(env, {global_ = 'global value'})
end

T'want'; do
  T.eq(ds,          mty.want'ds')
  T.eq(nil,         mty.want'lkja;lskjdflksajdf')
  T.eq(ds,          ds.wantpath'ds')
  T.eq(ds.wantpath, ds.wantpath'ds.wantpath')
  T.eq(mty,         ds.wantpath'metaty')
  T.eq(true,        ds.wantpath'metaty.CONCRETE.boolean')
end

