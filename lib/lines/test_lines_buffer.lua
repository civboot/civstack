local ds  = require'ds'
local fmt = require'fmt'
local T = require'civtest'

local buffer = require'lines.buffer'

local Gap = require'lines.Gap'
local Buffer = buffer.Buffer
local C = buffer.Change

T'insert & remove'; do
  local b = Buffer.new'a\nb\n'; local g = b.dat
  T.eq('a\nb\n', fmt(g))
  b:changeStart(0,0)
  b:insert('l', 1);         T.eq('la\nb\n',      fmt(g));
  b:insert(' hi', 1, 'end') T.eq('la hi\nb\n',   fmt(g))
  b:insert('la', 1, -3)     T.eq('lala hi\nb\n', fmt(g))
  b:remove(1, -3, 1, -1)    T.eq('lala\nb\n', fmt(g))

  T.eq({'lala', 'b', ''}, ds.icopy(g))
  b:insert('\nlob\n', 1,5)
  T.eq({'lala', 'lob', '', 'b', ''}, ds.icopy(g))
end

T'clear'; do
  local b = Buffer.new'a\nb\n'; local g = b.dat
  T.eq('a\nb\n', fmt(g))
  b:changeStart(0,0)
  b:remove(1,#b); T.eq('', fmt(g))
                  T.eq({''}, ds.icopy(g))
  b:insert('hi', 1)
  T.eq('hi', fmt(g)); T.eq({'hi'}, ds.icopy(g))
end

T'undoIns'; do
  local b = Buffer.new(''); local g = b.dat

  local ch1 = C{1,1, k='INSERT', s='hello '}
  local ch2 = C{1,7, k='INSERT', s='world!'}
  b:changeStart(0, 0)
  local ch = b:insert('hello ', 1, 2)
  T.eq(ch1, ch)
  T.eq('hello ', fmt(g))

  b:changeStart(0, 1)
  ch = b:insert('world!', 1, 7)
  T.eq(ch2, ch)
  T.eq('hello world!', fmt(g))

  -- undo + redo + undo again
  local chs = b:undo()
  T.eq({C{k='START', 0, 1}, ch2}, chs)
  T.eq('hello ', fmt(g))

  chs = b:redo()
  T.eq({C{k='START', 0,1}, ch2}, chs)
  T.eq('hello world!', fmt(g))

  chs = b:undo()
  T.eq({C{k='START', 0,1}, ch2}, chs)
  T.eq('hello ', fmt(g))

  -- undo final, then redo twice
  chs = b:undo()
  T.eq({C{k='START', 0,0}, ch1}, chs)
  T.eq('', fmt(g))
  b:redo(); chs = b:redo()
  T.eq({C{k='START', 0,1}, ch2}, chs)
  T.eq('hello world!', fmt(g))
end

T'undoInsRm'; do
  local b = Buffer.new(''); local g, ch = b.dat
  local ch1 = C{1,1, k='INSERT', s='12345\n'}
  local ch2 = C{1,1, k='REMOVE', s='12'}
  b:changeStart(0, 0)
  ch = b:insert('12345\n', 1, 2); T.eq(ch1, ch)

  b:changeStart(0, 1)
  ch = b:remove(1, 1, 1, 2);      T.eq(ch2, ch)
  T.eq('345\n', fmt(g))

  ch = b:undo()[2]                T.eq(ch2, ch)
  T.eq('12345\n', fmt(g))

  ch = b:redo()[2]                T.eq(ch2, ch)
  T.eq('345\n', fmt(g))
end

T'undoReal'; do -- undo/redo word deleting
  local START = "4     It's nice to have some real data"
  local b = Buffer.new(START); local g, ch = b.dat
  local ch1 = C{1,7, k='REMOVE', s='It'}
  local ch2 = C{1,7, k='REMOVE', s="'"}
  local ch3 = C{1,7, k='REMOVE', s="'s "}
  b:changeStart(0, 0)
  ch = b:remove(1, 7, 1, 8); T.eq(ch1, ch)
  T.eq("4     's nice to have some real data", fmt(g))
  ch = b:remove(1, 7, 1, 7); T.eq(ch2, ch)
  T.eq("4     s nice to have some real data", fmt(g))

  local chs = b:undo();      T.eq({C{k='START', 0,0}, ch1, ch2}, chs)
  T.eq("4     It's nice to have some real data", fmt(g))
  ch = b:redo();             T.eq({C{k='START', 0,0}, ch1, ch2}, chs)
  T.eq("4     s nice to have some real data", fmt(g))
end

T'undoMulti'; do -- undo/redo across multi lines
  local START = '123\n456\n789\nabc'
  local b = Buffer.new(START); local g, ch = b.dat
  T.eq(false, b:changed())
  T.eq(START, fmt(g))
  local ch1 = C{1,4, k='REMOVE', s='\n'}
  local ch2 = C{1,7, k='REMOVE', s='\n'}
  b:changeStart(0,0)
    T.eq(false, b:changed())
  ch = b:remove(1, 4, 1, 4); T.eq(ch1, ch)
    T.eq(true, b:changed())
  T.eq('123456\n789\nabc', fmt(g))

  b:changeStart(0,0) T.eq(false, b:changed())
  ch = b:remove(1, 7, 1, 7); T.eq(ch2, ch)
    T.eq('123456789\nabc', fmt(g))
    T.eq(true, b:changed())

  ch = b:undo()[2]                T.eq(ch2, ch)
  T.eq('123456\n789\nabc', fmt(g))

  ch = b:undo()[2]                T.eq(ch1, ch)
  T.eq(START, fmt(g))

  local ch3 = C{2,1, k='REMOVE', s='456\n789\n'}
  ch = b:remove(2, 3)             T.eq(ch3, ch)
end

T'removeReal'; do
  local START = '123\n456\n789\n'
  local b = Buffer.new(START); local g, ch = b.dat
  b:remove(1, 2)
  T.eq('789\n', fmt(g))
end

T'color'; do
  local START = '1 3\n4 6\n7 9\n'
  local b = Buffer{dat=Gap(START), fg=Gap(START), bg=Gap(START)}
  b:remove(2, 2) -- remove second line
  T.eq('1 3\n7 9\n', fmt(b.dat))
  T.eq('1 3\n7 9\n', fmt(b.fg))

  b:undo()
  T.eq('1 3\n4 6\n7 9\n', fmt(b.dat))
  T.eq('1 3\nz z\n7 9\n', fmt(b.fg))
  T.eq('1 3\nz z\n7 9\n', fmt(b.bg))

  b:insert('- 2 -', 1,2)
  T.eq('1- 2 - 3\n4 6\n7 9\n', fmt(b.dat))
  T.eq('1z z z 3\nz z\n7 9\n', fmt(b.fg))

  b:append'a b c'
  T.eq('1- 2 - 3\n4 6\n7 9\n\na b c', fmt(b.dat))
  T.eq('1z z z 3\nz z\n7 9\n\nz z z', fmt(b.fg))
end

T'color-highlighted'; do
  -- The highlighter is lazy and only colors the last character of a line
  local START = '1 3\n4 6\n7 9\n'
  local b = Buffer{dat=Gap(START), fg=Gap'A\n\nC\n', bg=Gap'X\nY\n\n'}
  b:insert('5 ', 2,3)
  T.eq('1 3\n4 5 6\n7 9\n', fmt(b.dat))
  T.eq(  'A\n  z  \nC\n',   fmt(b.fg))
  T.eq(  'X\nYYz Y\n\n',    fmt(b.bg))

  b:remove(2, 2) -- remove second line
  T.eq('1 3\n7 9\n', fmt(b.dat))
  T.eq('A\nC\n', fmt(b.fg))
  T.eq('X\n\n',  fmt(b.bg))

  b:insert('0 ', 1,1)
  T.eq('0 1 3\n7 9\n', fmt(b.dat))
  T.eq('z AAA\nC\n', fmt(b.fg))
  T.eq('z XXX\n\n',  fmt(b.bg))
end
