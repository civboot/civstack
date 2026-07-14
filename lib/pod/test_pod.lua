
local mty = require'metaty'
local ds  = require'ds'
local pod = require'pod'
local testing = require'pod.testing'
local assertf = require'fmt'.assertf

local T = require'civtest'

local function podRound(P, v, primitive)
  local t = P(ds.deepcopy(v))
  local n = primitive or v
  T.eq(n, pod.toPod(t))
  T.eq(t, pod.fromPod(v, P))
end

T'isPod'; do
  T.eq(true,  pod.isPrim(true))
  T.eq(true,  pod.isPrim(false))
  T.eq(true,  pod.isPrim(3))
  T.eq(true,  pod.isPrim(3.3))
  T.eq(true,  pod.isPrim'hi')

  T.eq(nil,  pod.isPrim(function() end))
  T.eq(nil,  pod.isPrim(io.open'README.cxt'))

  T.eq(true, pod.isPrim{1, 2, a=3})
  T.eq(true, pod.isPrim{1, 2, a={4, 5, b=6}})
  T.eq(false, pod.isPrim{1, 2, a={4, 5, b=function() end}})
end


T'toPod'; do
  local test = mod'test'

  -- simple type
  test.A = pod(mty'A'{'a1 [int]#1', 'a2 [int]#2', b=3})
  assert(test.A.__toPod)
  T.eq('test.A', MOD_NAMES[test.A])
  T.eq(test.A, MOD_LOOKUP['test.A'])
  podRound(test.A, {a1=11})

  T.throws('contains value of type "test.A" that is not primitive pod',
    function() pod.toPod{test.A{a1=12}, test.A{a1=13}} end)

  testing.testAll(pod.toPod, pod.fromPod)

  -- type with a map
  test.M = pod(mty'M'{
    's [str] #1',
    'm {key: prim} #2',
  })
  podRound(test.M, {
    s='test string',
    m = {
      keya = 'valuea', [3] = 'value3',
      l = {'value list'},
    },
  })

  -- type with an inner type
  test.I = mty'I'{
    'n [number] #1',
    'iA [test.A] #2',
    'iI [test.I] #3',
    's  [str] #4',
    'ls {str} #5',
  }
  getmetatable(test.I).__call = function(T, t)
    t.iA = t.iA and test.A(t.iA) or nil
    t.iI = t.iI and test.I(t.iI) or nil
    return mty.construct(T, t)
  end
  pod(test.I)
  T.eq(pod.List{I=pod.BUILTIN_PODDER.string}, test.I.__podders.ls)
  podRound(test.I, {
    n = 33,
    iA = {a1 = -1, a2=222 },
    iI = {
      n = 4444,
      iI = { n = 55555 },
    },
    s = 'hi',
    ls = {'a', 'b'},
  })

  -- Complex type
  test.C = pod(mty'C'{ 'l {test.A}' })
  podRound(test.C, {l={ test.A{a1=11} }}, {l={ {a1=11} }})

end

T'freeze'; do
  local freeze = require'metaty.freeze'
  T.eq(true, pod.isPrim(freeze.frozen{}))
end

if not G.NOLIB then
T'ds.pod.serialize'; do
  testing.testAll(pod.ser, function(str, P)
    local t, len = pod.deser(str, P)
    T.eq(#str, len) -- decoded full length
    return t
  end)
end
end -- if not G.NOLIB