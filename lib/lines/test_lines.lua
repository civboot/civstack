
local fmt = require'fmt'
local lines = require'lines'
local ds = require'ds'
local testing = require'lines.testing'
local Gap = require'lines.Gap'
local T = require'civtest'

local O = '.out/lines_test/'
require'civix'.mkDirs(O)

T'new'; do
  T.eq({'one', 'two 2', ''}, lines'one\ntwo 2\n')
  T.eq({'one', 'two 2', ''}, lines._args'one\ntwo 2\n')
  T.eq({'one', 'two 2', ''}, lines._args('one\n', 'two 2\n'))
end

T'sort'; do
  local sort = lines.sort
  T.eq({1, 1, 2, 2}, {sort(1, 1, 2, 2)})
  T.eq({1, 1, 2, 2}, {sort(2, 2, 1, 1)})
  T.eq({1, 5, 2, 1}, {sort(1, 5, 2, 1)})
  T.eq({1, 5, 2, 1}, {sort(2, 1, 1, 5)})
end

T'sub'; do
  local lsub = lines.sub
  local l = lines'ab\nc\n\nd'
  T.eq({''},                       lsub(l, 1,1, 0,0))
  T.eq({''},                       lsub(l, 1,1, 1,0))
  T.eq({'ab'},                     lsub(l, 1,1, 1,2))
  T.eq({{'ab', ''}, 1,1, 1,3},    {lsub(l, 1,1, 1,3)})
  T.eq({'ab', ''},                 lsub(l, 1,1, 2,0))
  T.eq({'b', 'c'},                 lsub(l, 1,2, 2,1))
  T.eq({'', ''},                   lsub(l, 1,3, 2,0))

  l = lines"4     It's nice to have some real data"
  T.eq({'It'},     lsub(l, 1,7,  1,8))
  T.eq({"'"},      lsub(l, 1,9,  1,9))
  T.eq({"4     It's"}, lsub(l, 1,0,  1,10))
  T.eq({" nice"},  lsub(l, 1,11, 1,15))

  -- select lines
  l = lines'ab\nc\n\nd'
  T.eq({''},            lsub(l, 1, 0))
  T.eq({'ab', ''},      lsub(l, 1, 1))
  T.eq({'ab', 'c', ''}, lsub(l, 1, 2))
  T.eq({'c', '', ''},   lsub(l, 2, 3))
end

T'find'; do
  local t = lines'12345\n6789\n98765\n'
  T.eq({1, 3,4}, {lines.find(t, '34', 1, 1)})
  T.eq({2, 1,2}, {lines.find(t, '67', 1, 3)})
  T.eq({2, 1,1}, {lines.find(t, '6', 1, 3)})
  T.eq({3, 4,4}, {lines.find(t, '6', 2, 2)})

  T.eq({3, 4,4}, {lines.findBack(t, '6', 3)})
  T.eq({3, 4,4}, {lines.findBack(t, '6', 3, 4)})
  T.eq({2, 1,1}, {lines.findBack(t, '6', 3, 3)})
end

T'offset'; do
  testing.testOffset(lines(testing.DATA.offset))
end

T'inset'; do
  local t = {''}
  T.eq(1, #t)
  lines.insert(t, 'foo bar', 1, 0)
  T.eq('foo bar', lines.join(t))
  lines.insert(t, 'baz ', 1,5)
  T.eq('foo baz bar', lines.join(t))
  lines.insert(t, '\nand', 1, 4)
  T.eq('foo\nand baz bar', lines.join(t))
  lines.insert(t, 'buz ', 2, 5)
  T.eq('foo\nand buz baz bar', lines.join(t))

  t = {''}
  lines.insert(t, 'foo\nbar', 1, 1)
  T.eq('foo\nbar', lines.join(t))
end

T'remove'; do
  testing.testLinesRemove(function(t)
    return type(t) == 'string' and lines(t) or t
  end)
end

T'box'; do
  local l = lines(
    '1 3 5 7 9\n'
  ..' 2 4 6\n'
  ..'a c d e f g h')
  T.eq({'1 3', ' 2 '        }, lines.box(l, 1,1, 2,3))
  T.eq({' 3 ', '2 4'        }, lines.box(l, 1,2, 2,4))
  T.eq({'7 9', '',   'e f g'}, lines.box(l, 1,7, 3,11))

  T.eq({'7 9  ', '     ', 'e f g'}, lines.box(l, 1,7, 3,11, ' '))
end

T'autoIndent'; do
  local ai = lines.autoIndent
  local l = {
    'ab',
    '  cd',
    '    ef',
    '  gh',   -- 3
    '',       -- 4
    '  ij',
    'kl',
  }

  T.eq('  ',   ai(l, 1))
  T.eq('    ', ai(l, 2))
  T.eq('  ',   ai(l, 3))
  T.eq('  ',   ai(l, 4))
  T.eq('  ',   ai(l, 5))
  T.eq('  ',   ai(l, 6))
end

------------------------
-- Gap Tests

T'Gap.set'; do
  local g = Gap'ab\nc\n\nd'
  T.eq('ab\nc\n\nd', fmt(g))
  T.eq({'ab', 'c', '', 'd'}, g.bot)
  g:setGap(3)
  T.eq({'ab', 'c', ''}, g.bot)
  T.eq({'d'},           g.top)
  T.eq('ab\nc\n\nd', fmt(g))
end

T'Gap.inset'; do
  -- FIXME: Gap actually passes testInset lol. Need to
  --   assert inputs are strings.
  require'ds.testing'.testInsetStr(Gap)
end

T'Gap lines.insert'; do
  T.eq(1, #Gap'')
  local g = Gap(); T.eq(0, #g)
  lines.insert(g, 'foo bar', 1, 0)
  T.eq('foo bar', fmt(g))
  g:setGap(1)
  T.eq(1, #g); T.eq(1, #g.bot)

  lines.insert(g, 'baz ', 1, 5)
  T.eq('foo baz bar', fmt(g))

  lines.insert(g, '\nand', 1, 4)
  T.eq('foo\nand baz bar', fmt(g))
  lines.insert(g, 'buz ', 2, 5)
  T.eq('foo\nand buz baz bar', fmt(g))

  g = Gap()
  lines.insert(g, 'foo\nbar', 1, 1)
  T.eq('foo\nbar', fmt(g))
end

T'Gap.remove'; do
  testing.testLinesRemove(Gap)
end

local function subTests(g)
  T.eq({'ab', ''},      lines.sub(g, 1, 1))
  T.eq({'ab', 'c', ''}, lines.sub(g, 1, 2))
  T.eq({'c', '', ''},   lines.sub(g, 2, 3))
  T.eq({'ab', ''},      lines.sub(g, 1, 1, 1, 3))
  T.eq({'b', 'c'},      lines.sub(g, 1, 2, 2, 1))
end
T'Gap.sub'; do
  local g = Gap'ab\nc\n\nd'
  g:setGap(4); subTests(g)
  g:setGap(1); subTests(g)
  g:setGap(2); subTests(g)

  g = Gap"4     It's nice to have some real data"
  T.eq({'It'},    lines.sub(g, 1, 7, 1, 8))
  T.eq({"'"},     lines.sub(g, 1, 9, 1, 9))
  T.eq({"s"},     lines.sub(g, 1, 10, 1, 10))
  T.eq({" nice"}, lines.sub(g, 1, 11, 1, 15))
end

T'Gap.offset'; do
  local testOffset = testing.testOffset
  local g = Gap(testing.DATA.offset)
  testOffset(g)
  g:setGap(1); testOffset(g)
  g:setGap(2); testOffset(g)
  g:setGap(4); testOffset(g)
end

T'Gap.find'; do
  local g = Gap'12345\n6789\n98765\n'
  T.eq({1, 3,4}, {lines.find(g, '34', 1, 1)})
  T.eq({2, 1,2}, {lines.find(g, '67', 1, 3)})
  T.eq({2, 1,1}, {lines.find(g, '6',  1, 3)})
  T.eq({3, 4,4}, {lines.find(g, '6',  2, 2)})
end

T'Gap.ipairs'; do
  local g = Gap'12345\n6789\n98765\n'
  local t = {}; for i, v in ipairs(g) do
    T.eq(g[i], g[i]) t[i] = v
  end
  T.eq({'12345', '6789', '98765', ''}, t)
  T.eq({'12345', '6789', '98765', ''}, ds.icopy(g))
end

T'Gap.extend'; do
  local g = Gap'123'
  ds.extend(g, {'456', '7'})
  T.eq('123\n456\n7', fmt(g))
end

T'Gap.write'; do
  local g = Gap''
  g:write'hi'; T.eq('hi', fmt(g))
  g:write' there\n'; T.eq('hi there\n', fmt(g))
  g:write'  next\nline'; T.eq('hi there\n  next\nline', fmt(g))
end

T'Gap.clear'; do
  local g = Gap'a\nb\n'
  T.eq('a\nb\n', fmt(g))
  g:inset(1, nil, #g); T.eq('', fmt(g))
  T.eq({}, ds.icopy(g))
  g:set(1, 'hi')
  g:set(2, 'bye')
  T.eq('hi\nbye', fmt(g))
end

T'Gap.dumpf'; do
  local t = {'some lines', 'more lines', 'final lines'}
  lines.dump(t, O..'dumpf.txt', nil, 10)
  T.path(O..'dumpf.txt', table.concat(t, '\n'))
end

T'Writer'; do
  local W = require'lines.Writer'; local w = W{}
  w:write'hi there'
  T.eq({'hi there'}, ds.icopy(w))
  w:write' bob'
  T.eq({'hi there bob'}, ds.icopy(w))
  w:write'\nand jane'
  T.eq({'hi there bob', 'and jane'}, ds.icopy(w))
  w:write' and sue\nand zebe\n'
  T.eq({'hi there bob', 'and jane and sue',
             'and zebe', ''}, ds.icopy(w))
end
