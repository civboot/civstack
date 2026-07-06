local iotype = io.type

local T   = require'civtest'
local M   = require'fd'
local ds = require'ds'
local ix = require'civix'
local ixt = require'civix.testing'
local info = require'ds.log'.info

local push = table.insert

local S   = M.sys

local io_open = io.open
T.eq(M.io.open, io_open)

M.ioSync()
assert(io.open ~= io_open)

local p = '.out/fd.text'

---------------------
-- non-general tests

T'bitops'; do
  T.eq(0xFF00, 0xFFFF & (~0x00FF))
  T.eq(0xF0F0, 0xFFFF & (~0x0F0F))
end

T'isTruncate'; do
  T.eq(false, M.isTrunc'r')
  T.eq(true,  M.isTrunc'w')
  T.eq(true,  M.isTrunc'w+')
  T.eq(false, M.isTrunc'a')
  T.eq(false, M.isTrunc'a+')
end

T'open -> _write -> _read'; do
  local f = M.open(p, 'w'); T.eq(0, f:code())
  print'opened'
  T.eq(0, f:_write'line 1\nline 2\n'); print'wrote lines'
  f:close(); print'closed'
  f = M.open(p, 'r'); T.eq(0, f:code()) print'opened'
  T.eq(S.FD_EOF, f:_read()) print'read EOF'
  T.eq('line 1\nline 2\n', f:_pop())
  T.eq('file', M.type(f)); print'got type'
  f:flush();              print'flushed'
  f:close(); T.eq('closed file', M.type(f))
end

--------------------
-- General tests (sync or async with any io impl)
local fin = false

local function generalTest()
T'openWriteRead'; do
  local f = assert(io.open(p, 'w'))
  assert(f:write'line 1\nline 2\n'); f:close()

  f = assert(io.open(p, 'r'))
  T.eq('line 1\nline 2\n', f:read'a')
  T.eq('file', M.type(f))
  f:close();
  for _=1,10 do
    if M.type(f) ~= 'closed file' then ix.sleep(1e-4) end
  end
  T.eq('closed file', M.type(f))
  local lns = {}; for ln in M.lines(p) do push(lns, ln) end
  T.eq({'line 1', 'line 2'}, lns)
end

T'append'; do
  local f = assert(io.open(p, 'a'))
  T.eq(14, f:seek'cur')
  f:write'line 3\n'; T.eq(21, f:seek'cur')
end

T'read'; do
  local f = assert(io.open(p, 'r'))
  T.eq('line 1\nline 2\nline 3\n', f:read'a')
  T.eq(21, f:seek'cur')
  f:close()
end

T'readLine'; do
  local f = io.open(p, 'r')
  T.eq('line 1',   f:read'l')
  T.eq('line 2',   f:read'l')
  T.eq('line 3\n', f:read'L')
  T.eq(nil,        f:read'L')
  f:close()
end

--- check that both files behave the same
T'generalFile'; do
  local f = io.open(p, 'w+')
  f:write'hello!'
    -- TODO: try read'a' here for odd results
    T.eq(nil, f:read());
    T.eq(6, f:seek'cur')

  T.eq(0, f:seek'set')
    T.eq('hello!', f:read'a')
    T.eq(6, f:seek'cur')
    T.eq(nil, f:read())
    T.eq('',  f:read'a')

  T.eq(3, f:seek('set', 3))
    T.eq('lo!', f:read(3))
    T.eq(6, f:seek'cur'); T.eq(nil, f:read()) -- TODO: read'a' is weird here

  T.eq(0, f:seek'set');
    T.eq('hel', f:read(3)); T.eq(3, f:seek'cur')
    T.eq('lo!', f:read(3)); T.eq(6, f:seek'cur')
    T.eq('',  f:read'a')
    T.eq(nil, f:read())
end

T'fileno_and_friends'; do
  T.eq(type(io.stderr), 'userdata')
  assert(iotype(io.stderr))
  T.eq(0, M.fileno(io.stdin))
  T.eq(2, M.fileno(io.stderr))
  T.eq(false, M.isatty(io.tmpfile()))
  T.eq(false, M.isatty(M.tmpfile()))
  T.eq(true,  M.isatty(io.stderr))
  T.eq(true,  M.isatty(2))

  T.eq('chr', M.ftype(io.stdin))
  T.eq('chr', M.ftype(io.stdout))
  T.eq('file', M.ftype(io.tmpfile()))
end

fin=true
end -- generalTest

T.SUBNAME = '[ioStd]'; M.ioStd()
fin=false; generalTest(); assert(fin)

T.SUBNAME = '[ioSync]'; M.ioSync()
fin=false; generalTest(); assert(fin)

T.SUBNAME = ''

---------------------
-- Targeted tests (async)
local function pipeTest(r, w)
  w:write'hi there'
  T.eq('hi', r:read(2)); T.eq(' there', r:read(6))
end

T'pipe'; do pipeTest(S.pipe()) end

fin = 0
ixt.runAsyncTest(function()
T'pipe_async'; do
  local r, w = S.pipe()
  pipeTest(r:toNonblock(), w:toNonblock())
  T.eq(S.EWOULDBLOCK, r:_read(1))
  w:write'bye'
  T.eq('b', r:read(1)); T.eq('ye', r:read(2))
  fin = fin + 1
end

local text = 'line 1\nline 2\nline 3\nline 4\n'
T'FDT_write'; do
  local f = assert(M.openFDT(p, 'w')); info'opened'
  T.eq(M.FDT, getmetatable(f))
  T.eq(0, f:code())
  assert(f:write(text))
  f:close()
  fin = fin + 1
end

T'FDT_read'; do
  info'started test'
  local f = assert(M.openFDT(p)); info'opened'
  T.eq(M.FDT, getmetatable(f))
  T.eq(0, f:code())
  f:_read(); info'started read'
  while f:code() == S.FD_RUNNING do end
  T.eq(S.FD_EOF, f:code())
  T.eq(text, f:_pop())
  f:close()
  fin = fin + 1
end
end) -------------- runAsyncTest
T.eq(3, fin)

--- Now run the general test in async mode
T.SUBNAME = '[ioAsync]'
fin=false; ixt.runAsyncTest(generalTest); assert(fin)

M.ioStd(); T.SUBNAME = ''