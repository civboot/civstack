local G = G or _G
local M = G.mod and mod'pod.testing' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds  = require'ds'
local pod = require'pod'
local T  = require'civtest'

--- Test [$eq(v, decFn(encFn(v))]
--- If expectEncoding is provided then test [$eq(expectEncoding, encFn(v)]
function M.round(v, encFn, decFn, expectEncoding) --> (enc, dec)
  local P = mty.ty(v); if type(P) == 'string' then P = nil end
  local enc = encFn(v, P)
  if expectEncoding ~= nil then
    T.binEq(expectEncoding, enc)
  end
  local dec = decFn(enc, P)
  T.eq(v, dec)
  return enc, dec
end
function M.roundList(values, encFn, decFn)
  for _, v in ipairs(values) do
    local ok, err = ds.try(M.round, v, encFn, decFn)
    if not ok then
      fmt.errorf('for value:\n%q\n  got: %s', v, err)
    end
  end
end

M.BOOLS = { false, true, }
M.INTS = {
  0, 1, 2, 10, 0xFF,   0x100,  0xFFFF,
    -1,   -10, -0xFF, -0x100, -0xFFFF,
}
M.STRINGS = {
  'a', 'abc', '01234', 'A0B1',
  '🚀rocket🚀',
}
M.BYTES = {
  'zero\x00okay', 'ff\xFFokay',
}
M.LISTS = {
  {},
  {0}, {'0'},
  M.BOOLS,
  M.STRINGS,
  M.BYTES,
  ds.flatten{M.BOOLS, M.STRINGS, M.BYTES},
}

M.MAPS = {
  {a=1}, {akey='akeyval', bkey='bkeyval'},
  {[4]='1num', [7]='7num'},
  {table = {innerkey='inner value'}},
  {bools = M.BOOLS},
  {ints = M.INTS},
  {strings = M.STRINGS},
  {lists = M.LISTS},
}

M.TABLES = {
  {'one', 'two', 'three', key='value'},
  {[-2] = 'neg 2', [-1] = 'neg 1', [0] = 'zero', 'one', 'two'}
}

M.BUILTIN = ds.flatten {
  M.BOOLS, M.STRINGS, M.BYTES, M.LISTS, M.MAPS, M.TABLES,
}

M.E = mty.enum'E' {
  FIRST  = 1,
  SECOND = 2,
}

--- A simple type
M.A = pod(mty'A'{
  'i [int]#1',
  'e [pod.testing.E] #2', e=M.E.SECOND,
})

-- type with an embedded map
M.M = pod(mty'M'{
  's [str] #1',
  'm {key: prim} #2',
})

-- type with inner types (including recursive)
M.I = mty'I'{
  'n [number] #1',
  'iA [pod.testing.A] #2',
  'iI [pod.testing.I] #3',
}
getmetatable(M.I).__call = function(T, t)
  t.iA = t.iA and M.A(t.iA) or nil
  t.iI = t.iI and M.I(t.iI) or nil
  return mty.construct(T, t)
end
pod(M.I)

function M.roundMetaty(encFn, decFn)
  local round = function(v) return M.round(v, encFn, decFn) end

  round(M.A{})
  round(M.A{i=42, e=M.E.FIRST})
end

function M.testAll(...)
  M.roundList(M.BUILTIN, ...)
  M.roundMetaty(...)
end

return M