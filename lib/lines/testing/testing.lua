--- testing helpers for ds related data structures
local M = mod and mod'lines.testing' or {}

local T = require'civtest'
local mty = require'metaty'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local info = mty.from'ds.log  info'

local concat = mty.from(table, 'concat')
local get    = mty.from(ds,    'get')
M.DATA = {}

--- test round-trip offset
local function offsetRound(t, l, c, off, expect, expectOff)
  local l2,c2 = lines.offset(t, off, l,c)
  T.eq(expect, {l2,c2}, 'offset result')
  local res = lines.offsetOf(t, l,c, l2,c2)
  T.eq(expectOff or off, res, 'offsetOf result')
end
M.DATA.offset = '12345\n789\n'
function M.testOffset(t)
  local l, c
  offsetRound(t, 1,2,  0,  {1, 2})
  offsetRound(t, 1,2,  1,  {1, 3})
  offsetRound(t, 1,3, -1,  {1, 2})
  offsetRound(t, 1,2, -1,  {1, 1})
  T.eq({1,1}, {lines.offset(t, -1, 1,1)})

  -- here
  offsetRound(t, 1,1, 3,   {1, 4})
  offsetRound(t, 1,1, 4,   {1, 5}) -- '5'
  offsetRound(t, 1,1, 5,   {1, 6}) -- '\n'
  offsetRound(t, 1,1, 6,   {2, 1}) -- '7'
  offsetRound(t, 1,1, 8,   {2, 3}) -- '9'
  offsetRound(t, 1,1, 9,   {2, 4}) -- '\n'
  offsetRound(t, 1,1, 10,  {3, 1}) -- ''
  offsetRound(t, 1,1, 12,  {3, 1}, 10) -- EOF

  offsetRound(t, 1,5, -3,  {1, 2}) -- '2'
  offsetRound(t, 1,5, -4,  {1, 1}) -- '1'
  offsetRound(t, 1,5, -5,  {1, 1}, -4) -- '1'

  offsetRound(t, 3,1, -1,  {2, 4}) -- '\n'
  offsetRound(t, 3,1, -2,  {2, 3}) -- '9'
  offsetRound(t, 3,1, -3,  {2, 2}) -- '8'
  offsetRound(t, 3,1, -4,  {2, 1}) -- '7'
  offsetRound(t, 3,1, -5,  {1, 6}) -- '\n'
  offsetRound(t, 3,1, -10, {1, 1}) -- '1'
  offsetRound(t, 3,1, -12, {1, 1}, -10) -- SoF

  -- Those are all "normal", let's do some OOB stuff
  offsetRound(t, 1,6,  1, {2, 1})
  offsetRound(t, 1,10, 1, {2, 1}) -- note (1, 6) is EOL
end

--- Test lines.remove on object. new must accept either a string or table of
--- lines to create a new object (does NOT need to be copied)
--- called for various data structures which implement lines
function M.testLinesRemove(new, assertEq, assertEqRemove)
  local assertEqR = assertEqRemove or T.eq
  local assertEq = assertEq or T.eq

  local function doRm(t, l,c, l2,c2, exR, ex)
    l,c, l2,c2 = lines.span(l,c, l2,c2)
    local s, l1,c1, l2a,c2a = lines.sub(t, l,c, l2,c2)
    T.eq({l,c}, {l1,c1}, 'actual start')
    assertEqR(exR, s, 'sub')
    local str = concat(s, '\n')
    local off = lines.offsetOf(t, l1,c1, l2a,c2a)
    local expOff = #str-1
    if l2a > #t or (l2a == #t and c2a > #get(t,l2a)) then
      expOff = expOff + 1 -- EoF will be missing '\n' char
    end
    T.eq(expOff, off, 'offsetOf result')
    T.eq({l2a,c2a}, {lines.offset(t, off, l1,c1)}, 'offset result')

    local b4 = new(ds.icopy(t))
    local r  = lines.remove(t, l,c, l2,c2)
    if rawget(t, 'dats') then t:flush() end -- TODO: get rid of this?
    assertEqR(exR, r, 'removed')
    assertEq(ex, t, 't after remove')
    -- now reverse the process
    local re = new(ds.icopy(t))
    lines.insert(re, r, l,c)
    assertEq(b4, re, 'reversed not same')
  end

  local t = new''
  lines.insert(t, 'foo bar', 1, 0)
  doRm(t, 1,3, 1,5, {'o b'}, new{'foar'})

  lines.insert(t, 'ab\n123', 1, 4)
    assertEq(new{'foaab', '123r'}, t)
  doRm(t, 1,3, 2,2, {'aab', '12'}, new{'fo3r'})

  t = new'a\nb'
  doRm(t, 1,2, 1,2, {'', ''},  new{'ab'})
  t = new'a\nb'
  doRm(t, 1,2, 2,0, {'', ''},  new{'ab'})
  doRm(t, 1,1, 2,1, {'ab'},    new{})

  t = new'ab\nc'; doRm(t, 1,2, 2,1, {'b', 'c'}, new{'a'})
  t = new'ab\nc'; doRm(t, 1,2, 2,2, {'b', 'c'}, new{'a'})

  t = new'ab\nc\n\nd'
  doRm(t, 2,3, nil,nil, {'c', '', ''}, new{'ab', 'd'})

  t = new'ab\nc'
  doRm(t, 2,1, 2,1, {'c'}, new{'ab', ''})
  doRm(t, 1,3, 2,0, {'', ''}, new{'ab'})

  -- remove \n (single)
  t = new'ab\nc'
  doRm(t, 1,3, 2,0, {'', ''}, new{'abc'})

  t = new'ab\nc\nde\n'
  doRm(t, 1,3, 2,0, {'', ''}, new{'abc', 'de', ''})

  -- remove first line
  t = new'ab\nc\nde\n'
  doRm(t, 1,1, 2,0, {'ab', ''}, new{'c', 'de', ''})

  -- join lines
  t = new'ab \n  c\nde\n'
  doRm(t, 1,4, 2,2, {'', '  '}, new{'ab c', 'de', ''})

  -- TODO: consider re-adding as a separate test
  -- t = new'a b c\nd e\nf g\nh i\n'
  -- fmt.print('t:', t)
  -- assertEqR({'d e', 'f g'}, lines.remove(t, 2, 3))
  -- assertEq(new{'a b c', 'h i', ''}, t)
end

return M
