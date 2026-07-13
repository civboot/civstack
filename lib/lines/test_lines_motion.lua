local mty = require'metaty'
local ds  = require'ds'
local T = require'civtest'

local decDistance, lcLe, lcGe, lcWithin,
      forword, backword, findBack,
      wordKind, pathKind, getRange,
      topLeft
      = mty.from[[lines.motion
      decDistance, lcLe, lcGe, lcWithin,
      forword, backword, findBack,
      wordKind, pathKind, getRange,
      topLeft
]]

T'distance'; do
  T.eq(3, decDistance(1, 4))
  T.eq(2, decDistance(5, 1))
  T.eq(5, decDistance(5, 5))
end

T'topLeft'; do
  T.eq({1,1}, {topLeft(1, nil, 5, nil)})
  T.eq({2,1}, {topLeft(2, nil, 3, nil)})
  T.eq({2,5}, {topLeft(7, 1, 2, 5)})
  T.eq({2,5}, {topLeft(2, 5, 7, 7)})
  T.eq({2,5}, {topLeft(2, 5, 7, 3)})
end

T'lc'; do
  assert(    lcLe(1,1,   1,3))
  assert(    lcLe(1,2,   1,3))
  assert(    lcLe(1,3,   1,3))
  assert(not lcLe(1,4,   1,3))

  assert(not lcGe(1,1,   1,3))
  assert(not lcGe(1,2,   1,3))
  assert(    lcGe(1,3,   1,3))
  assert(    lcGe(1,4,   1,3))

  assert(not lcWithin(1, 0,   1, 1,   1, 5))
  assert(    lcWithin(1, 1,   1, 1,   1, 5))
  assert(    lcWithin(1, 3,   1, 1,   1, 5))
  assert(    lcWithin(1, 5,   1, 1,   1, 5))
  assert(not lcWithin(1, 6,   1, 1,   1, 5))
  assert(not lcWithin(2, 3,   1, 1,   1, 5))

  assert(not lcWithin(1, 1,  1, 4,   3, 3))
  assert(not lcWithin(1, 3,  1, 4,   3, 3))
  assert(    lcWithin(1, 4,  1, 4,   3, 3))
  assert(    lcWithin(2, 4,  1, 4,   3, 3))
  assert(    lcWithin(3, 1,  1, 4,   3, 3))
  assert(    lcWithin(3, 3,  1, 4,   3, 3))
  assert(not lcWithin(3, 4,  1, 4,   3, 3))
  assert(not lcWithin(4, 1,  1, 4,   3, 3))
end

T'wordKind'; do
  T.eq('let', wordKind('a'))
  T.eq('()',  wordKind('('))
  T.eq('()',  wordKind(')'))
  T.eq('sym', wordKind('+'))
end

T'forword'; do
  T.eq(3, forword('a bcd'))
  T.eq(3, forword('  bcd'))
  T.eq(2, forword(' bcd'))
  T.eq(3, forword('--bcd'))
  T.eq(2, forword('a+ bcd'))
  T.eq(5, forword('+12 +de', 2))
end

T'backword'; do
  T.eq(3,   backword('a bcd', 4))
  T.eq(3,   backword('  bcd', 4))
  T.eq(nil, backword('  bcd', 3))
end

T'getRange'; do
  T.eq({1,2},   {getRange('ab cde', 1)})
  T.eq({1,2},   {getRange('ab cde', 2)})
  T.eq({3,3},   {getRange('ab cde', 3)})
  T.eq({4,6},   {getRange('ab cde', 4)})
end

T'findBack'; do
  T.eq({7, 8},   {findBack('12 45 12 ', '12')})
  T.eq({1, 2},   {findBack('12 45 12 ', '12', 6)})
end

T'pathKind'; do
  T.eq('path', pathKind'a')
  T.eq('path', pathKind'/')
  T.eq('path', pathKind'-')
  T.eq('()',   pathKind'(')
  T.eq('()',   pathKind')')
  T.eq('sym',  pathKind'+')
end

local function forpath(s, begin)
  return forword(s, begin, pathKind)
end
local function backpath(s, end_)
  return backword(s, end_, pathKind)
end

T'forpath'; do
  T.eq(3, forpath('a bcd'))
  T.eq(6, forpath('a/bcd"  '))
  T.eq(8, forpath('a/b/c.d" '))
end

T'backpath'; do
  T.eq(3, backpath('a b/c/d', 7))
end

local function pathRange(s, i) return getRange(s, i, pathKind) end
T'getRange'; do
  T.eq({3, 5}, {pathRange(' "a/b is the path" ', 4)})
end