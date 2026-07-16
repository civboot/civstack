G.METATY_CHECK = true

local ge = {}; for k in pairs(_G) do table.insert(ge, k) end
local M = require'metaty'
assert(LUA_OPT <= 2)

local mty, split = M, M.split

local add, sfmt = table.insert, string.format

local Tm = G.mod and mod'Tm' or {}

local function test(name, fn)
  print('# Test', name)
  fn()
end

local function assertEq(expect, result)
  if M.eq(expect, result) then return end
  error('Values not mty.eq: '..
    require'fmt'.Fmt:pretty{}:concat('',
      "! EXPECT: ", expect, '\n',
      "! RESULT: ", result, '\n'):tostring())
end

local function assertMatch(expectPat, result)
  if not result:match(expectPat) then
    error(sfmt('Does not match pattern:\nPattern: %q\n Result:  %s',
          expectPat, result))
  end
end

local function assertErrorPat(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then error(sfmt('! No error received, expected: %q', errPat)) end
  if not err:find(errPat, 1, plain) then error(sfmt(
    '! Expected error %q but got %q', errPat, err
  ))end
end

local function splitT(...)
  local t = {}; for st, item in split(...) do
    add(t, {item, st.si, st.ei})
  end
  return t
end
local LINES = '\nhi\n\nthere\nyou\n', '\n'

test('split', function()
  assertEq({
    {'hi',    1, 2},
    {'there', 4, 8},
    {'jane',  10, 13},
  }, splitT('hi there\njane'))

  assertEq({
    {'',      1,  0},
    {'hi',    2,  3},
    {'',      5,  4},
    {'there', 6,  10},
    {'you',   12, 14},
    {'',      16, 15},
  }, splitT(LINES, '\n'))
end)

test('ty', function()
  assert('string' == M.ty('hi'))
  assert('number' == M.ty(4))
  assert('table'  == M.ty({}))
  local mt = {}
  assert(mt       == M.ty(setmetatable({}, mt)))
end)

test('name', function()
  assertEq('string', M.tyName('string'))
  assertEq('string', M.tyName(M.ty('hi')))

  assertEq('number', M.tyName('number'))
  assertEq('number', M.tyName(M.ty(4)))

  assertEq('table',  M.tyName('table'))
  assertEq('table',  M.tyName(M.ty({})))

  local mt = {__name='F'}
  assertEq('F', M.tyName(mt))
  assertEq('F', M.tyName(M.ty(setmetatable({}, mt))))

  assertEq('string', M.name'hi')
  assertEq('table',  M.name{})
  assertEq('foo',    M.name(setmetatable({}, {__name='foo'})))

  Tm.A = mty'A'
  assertEq('Tm.A',   M.name(Tm.A))
  assertEq('Tm.A',   MOD_NAMES[Tm.A])
end)

test('record', function()
  local A = M'A'{'a2[any]', 'a1[any]'}
  assertEq({"a2", "a1", a1="[any]", a2="[any]"}, A.__fields)

  local B = mty'B'{
    'b1[number]#1',
    'b2[number]#2: has default', b2 = 32,
    'a[A]#3'
  }


  local a = A{a1='hi', a2=5}
  assert(A == getmetatable(a))
  assertEq('[any]', A.__fields.a1)
  assertEq('[any]', getmetatable(a).__fields.a2)
  assert(A == M.ty(a))
  assert('hi' == a.a1); assert(5 == a.a2)
  a.a2 = 4;             assert(4 == a.a2)

  local b = B{b1=5, a=a}
  assert(B == getmetatable(b))
  assertEq(5, b.b1); assertEq(32, b.b2) -- default
  b.b2 = 7;          assertEq(7, b.b2)

  assertErrorPat('"a3" is not a field of A',
    function() local x = a.a3 end)
  assertErrorPat('"a3" is not a field of A',
    function() a.a3 = 7 end)

  A.meth = function() end
  assertEq(A.meth, M.getmethod(A,   'meth'))
  assertEq(A.meth, M.getmethod(A{}, 'meth'))
  assertEq(nil,    M.getmethod(A{}, 'does-not-exist'))

  assertEq({'b1', 'b2', 'a', b1=1, b2=2, a=3}, B.__fieldIds)
end)

test('record maybe', function()
  local A = mty'A' {'a1[string]', 'a2[number]'}

  local a = A{a1='hi'}
    assertEq('hi', a.a1);   assertEq(nil, a.a2);
    assertEq(A{a1='hi'}, a)
  a.a2 = 4;   assertEq(4, a.a2);
              assertEq(A{a1='hi', a2=4}, a)
  a.a2 = nil; assertEq(nil, a.a2)
end)

test('extend type', function()
  local A = mty'A' {'a1[string]', 'a2[number]'}
  local a = A{}; assertEq('A', a.__name)

  local B = M.extend(A, 'B', {'b1[string]', b1='default'})
  assertEq('B', B.__name)
  local b = B{}; assertEq('B', b.__name)
  assertEq('default', b.b1)
end)

test('globals', function()
  local gr = {}; for k in pairs(_G) do table.insert(gr, k) end
  table.sort(ge); table.sort(gr);
  assertEq(ge, gr)
end)

test('enum', function()
  local E = M.enum'E' {
    A = 1, B = 2, C = 3,
  }
  assertEq('A', E.A); assertEq('B', E.B)
  assertEq('A', E.name'A'); assertEq('A', E.name(1))
  assertEq('C', E.name'C'); assertEq('C', E.name(3))

  assertEq(1, E.id'A'); assertEq(1, E.id(1))

  local fn = function() end
  assertErrorPat('missing variants',
    function() E:matcher {A=fn, B=fn} end)

  local var, val
  local m = E:matcher{
    A=function(v) var, val = 'A', v end,
    B=function(v) var, val = 'B', v end,
    C=function(v) var, val = 'C', v end,
  }
  m.A(22);  assertEq('A', var);  assertEq(22, val)
  m.B(33);  assertEq('B', var);  assertEq(33, val)
  m[3](44); assertEq('C', var); assertEq(44, val)
  assertEq(nil, m.D)

  local T = M'T' { 'i [int]', 'e [E]', e=E.A}
  local a1, a2 = T{i=3, e=E.A}, T{i=3, e=E.A}
  assertEq(a1, a2)
  a1.e = nil
  assertEq(a1, a2)
  assertEq(a2, a1)
end)

test('from', function()
  local record, enum = mty.from'metaty record,enum'
  assertEq(mty.record, record)
  assertEq(mty.enum,   enum)
end)

test('freeze', function()
  local freeze = require'metaty.freeze'
  local t = {1, 2, a=true, b=2, t={c='c3'}}
  local function assertGet()
    assertEq(true, t.a)
    assertEq(2,    t.b)
    assertEq('c3', t.t.c)
    assertEq(nil,  t.d)
    assertEq(2,    #t)
    local o = {}; for k, v in pairs(t) do o[k] = v end
    assertEq({1, 2, a=true, b=2, t=t.t}, o)
  end
  assertEq({next, t}, {pairs(t)})
  assertGet()
  assert(not freeze.FROZEN[t])
  freeze(t)
  assert(freeze.FROZEN[t])
  assertEq({freeze.frozenNext, t}, {pairs(t)})
  assertGet()
  assertErrorPat('"d" to frozen table', function()
    t.d = 'foo'
  end)
  assertErrorPat('"a" to frozen table', function()
    t.a = 'foo'
  end)
  assertErrorPat('"c" to frozen table', function()
    t.t.c = 'foo'
  end)
  assertEq(true, freeze.isFrozen(t.a))
  assertEq(true, freeze.isFrozen(t.t))

  local forceset = freeze.forceset
  forceset(t, 'z', 'last'); assertEq('last', t.z)
end)


test('freeze Type', function()
  local freeze = require'metaty.freeze'
  local A = freeze.freezy(mty'A' {'a1[string]', 'a2[number]'})
  local a = A{a1='hi'}
    assertEq('hi', a.a1);   assertEq(nil, a.a2);
    assertEq(A{a1='hi'}, a)

  a.a1 = 'bye'
  a.a2 = 42
    assertEq('bye', a.a1)
    assertEq(42, a.a2)
    assertEq(A{a1='bye', a2=42}, a)
  a:freeze()
    assertEq('bye', a.a1);   assertEq(42, a.a2);
    assertEq(A{a1='bye', a2=42}:freeze(), a)

  assertErrorPat('"a1" to frozen value', function()
    a.a1 = 'foo'
  end)
end)