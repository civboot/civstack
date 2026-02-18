--- testing helpers for ds related data structures
local M = mod and mod'lines.testing' or {}

local T = require'civtest'
local mty = require'metaty'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local log = require'ds.log'
M.DATA = {}

--- test round-trip offset
local function offsetRound(t, l, c, off, expect, expectOff)
  local l2, c2 = lines.offset(t, off, l, c)
  T.eq(expect, {l2, c2})
  local res = lines.offsetOf(t, l, c, l2, c2)
  T.eq(expectOff or off, res)
end
M.DATA.offset = '12345\n6789\n'
function M.testOffset(t)
  local l, c
  offsetRound(t, 1, 2, 0,   {1, 2})
  offsetRound(t, 1, 2, 1,   {1, 3})
  offsetRound(t, 1, 3, -1,  {1, 2})
  offsetRound(t, 1, 2, -1,  {1, 1})
  T.eq({1, 1}, {lines.offset(t, -1, 1, 1)})

  -- here
  offsetRound(t, 1, 1, 3,   {1, 4})
  offsetRound(t, 1, 1, 4,   {1, 5}) -- '5'
  offsetRound(t, 1, 1, 5,   {1, 6}) -- '\n'
  offsetRound(t, 1, 1, 6,   {2, 1}) -- '6'
  offsetRound(t, 1, 1, 9,   {2, 4}) -- '9'
  offsetRound(t, 1, 1, 10,  {2, 5}) -- '\n'
  offsetRound(t, 1, 1, 11,  {3, 1}) -- ''
  offsetRound(t, 1, 1, 12,  {3, 1}, 11) -- EOF

  offsetRound(t, 1, 5, -3,  {1, 2}) -- '2'
  offsetRound(t, 1, 5, -4,  {1, 1}) -- '1'
  offsetRound(t, 1, 5, -5,  {1, 1}, -4) -- '1'

  offsetRound(t, 3, 1, -1,  {2, 5}) -- '\n'
  offsetRound(t, 3, 1, -2,  {2, 4}) -- '9'
  offsetRound(t, 3, 1, -3,  {2, 3}) -- '8'
  offsetRound(t, 3, 1, -4,  {2, 2}) -- '7'
  offsetRound(t, 3, 1, -5,  {2, 1}) -- '6'
  offsetRound(t, 3, 1, -6,  {1, 6}) -- '\n'
  offsetRound(t, 3, 1, -11, {1, 1}) -- '\n'
  offsetRound(t, 3, 1, -12, {1, 1}, -11) -- BOF

  -- Those are all "normal", let's do some OOB stuff
  offsetRound(t, 1, 6 , 1, {2, 1})
  offsetRound(t, 1, 10, 1, {2, 1}) -- note (1, 6) is EOL
end

--- Test lines.remove on object. new must accept either a string or table of
--- lines to create a new object (does NOT need to be copied)
--- called for various data structures which implement lines
function M.testLinesRemove(new, assertEq, assertEqRemove)
  local assertEqR = assertEqRemove or T.eq
  local assertEq = assertEq or T.eq
  local t = new''
  lines.insert(t, 'foo bar', 1, 0)
  assertEqR({'o b'}, lines.remove(t, 1, 3, 1, 5))
  assertEq(new{'foar'}, t)

  lines.insert(t, 'ab\n123', 1, 4)
  assertEq(new{'foaab', '123r'}, t)
  assertEqR({'aab', '12'}, lines.remove(t, 1, 3, 2, 2))
  assertEq(new{'fo', '3r'}, t)

  t = new'a\nb'
  assertEqR({''}, lines.remove(t, 1, 2, 2, 0)) -- remove newline
  assertEq(new{'ab'}, t)
  assertEqR({'ab'}, lines.remove(t, 1, 1, 2, 1))
  assertEq(new{}, t)

  t = new'a\nb'
  assertEqR({''}, lines.remove(t, 1, 2, 1, 2)) -- alternate remove newline
  assertEq(new{'ab'}, t)

  t = new'ab\nc'
  assertEqR({'b', 'c'}, lines.remove(t, 1, 2, 2, 1))
  assertEq(new{'a', ''}, t)

  t = new'ab\nc'
  assertEqR({'b', 'c'}, lines.remove(t, 1, 2, 2, 2))
  assertEq(new{'a'}, t)

  t = new'ab\nc\n\nd'
  assertEqR({'c', ''}, lines.remove(t, 2, 3))
  if rawget(t, 'dats') then t:flush() end
  assertEq(new{'ab', 'd'}, t)

  t = new'ab\nc'

  assertEqR({'c'}, lines.remove(t, 2, 1, 2, 1)) -- remove c
  assertEq(new{'ab', ''}, t)
  assertEqR({''}, lines.remove(t, 1, 3, 2, 0)) -- remove \n (lineskip)
  assertEq(new{'ab'}, t)

  t = new'ab\nc'
  assertEqR({''}, lines.remove(t, 1, 3, 1, 3)) -- remove \n (single)
  assertEq(new{'abc'}, t)

  t = new'ab\nc\nde\n'
  -- remove \n (single)
  assertEqR({''}, lines.remove(t, 1, 3, 1, 3))
  assertEq(new{'abc', 'de', ''}, t)

  -- remove first line
  t = new'ab\nc\nde\n'
  assertEqR({'ab'}, lines.remove(t, 1,1, 1,3))
  assertEq(new{'c', 'de', ''}, t)

  -- join lines
  t = new'ab \n  c\nde\n'
  assertEqR({'', '  '}, lines.remove(t, 1,4, 2,2))
  assertEq(new{'ab c', 'de', ''}, t)

  -- TODO: consider re-adding as a separate test
  -- t = new'a b c\nd e\nf g\nh i\n'
  -- fmt.print('t:', t)
  -- assertEqR({'d e', 'f g'}, lines.remove(t, 2, 3))
  -- assertEq(new{'a b c', 'h i', ''}, t)
end

return M