local G = G or _G
--- filedescriptor: direct control of filedescriptors.
--- async operations support the LAP (see lib/lap) protocol.
---
--- Can override default `io` module for global async mode.
local M = mod and mod'fd' or {}

--- protocol globals (CIV and LAP protocols)
G.CWD = G.CWD or os.getenv'PWD' or os.getenv'CD' -- current working dir
G.LAP_FNS_ASYNC = G.LAP_FNS_ASYNC or {}
G.LAP_FNS_SYNC  = G.LAP_FNS_SYNC  or {}

--- cache the original values.
io._stdout, io._stderr = io.stdout, io.stderr

local trace = G.LOG and G.LOG.trace or function() end
local S = require'fd.lib' -- fd.c, fd.h
local mty = require'metaty'
local ds = require'ds'

local sfmt      = string.format
local push, pop = table.insert, table.remove
local yield     = coroutine.yield
local NL        = -string.byte'\n'
local iotype    = io.type
local sconcat   = string.concat -- note: from ds

local S_IFMT = S.S_IFMT
local fstmode = S.fstmode

S.POLLIO = S.POLLIN | S.POLLOUT

M.FMODE = mty.enum'FMODE' {
  sock = S.S_IFSOCK, link = S.S_IFLNK, file = S.S_IFREG,
  blk = S.S_IFBLK,  dir = S.S_IFDIR,  chr = S.S_IFCHR,
  fifo = S.S_IFIFO,
}
local fmodeName = M.FMODE.name

local MFLAGS = mty.enum'MFLAGS'{
  ['r']  = S.O_RDONLY, ['r+']= S.O_RDWR,
  ['w']  = S.O_WRONLY | S.O_CREAT | S.O_TRUNC,
  ['a']  = S.O_WRONLY | S.O_CREAT | S.O_APPEND,
  ['w+'] = S.O_RDWR   | S.O_CREAT | S.O_TRUNC,
  ['a+'] = S.O_RDWR   | S.O_CREAT | S.O_APPEND,
}
--- Given a string mode, return whether the file will be truncated.
function M.isTrunc(mode) --> bool
  return (assert(MFLAGS.id(mode), mode) & S.O_TRUNC) ~= 0
end

--- Given a string mode, return whether the file will be created
--- if it doesn't exist.
function M.isCreate(mode)
  return (assert(MFLAGS.id(mode), mode) & S.O_CREAT) ~= 0
end

local mflagsInt = MFLAGS.id

local AGAIN_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
}
local YIELD_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
  [S.FD_RUNNING] = true,
}
local DONE_CODE = { [S.FD_EOF] = true, [0] = true }

M.sys = S
M._sync  = mod and mod'fd(sync)'  or {} -- sync functions
M._async = mod and mod'fd(async)' or {} -- async functions
M.io = {}  -- io cache

--- Sync filedescriptor object implemented in C.[{br}]
--- Operations will block the current program until complete.
M.FD = S.FD

--- Async filedescriptor object implemented in C.[{br}]
--- Operations will yield if not yet complete.
M.FDT = S.FDT

--- Use to explicitly create a sync file-descriptor.
--- Operations will block the current program until complete.
M.newFD = S.newFD

--- Use to explicitly create a async file-descriptor.
--- Operations will yield if not yet complete.
M.newFDT = S.newFDT

M.PIPE_BUF = 512 -- POSIX.1

assert(S.FD.__index._close)
S.FD.__index.close    = S.FD.__index._close
S.FD.__close          = S.FD.__index._close
S.FD.__name = 'fd.FD'
function S.FD:__tostring() return sfmt('FD(%s)', self:fileno()) end

assert(S.FDT.__index._close)
local function finishRunning(self, kind, ...)
  while self:code() == S.FD_RUNNING do yield(kind or true, ...) end
end
function S.FDT.__index:close()
  finishRunning(self, 'sleep', 1e-4)
  self:_close();
end
S.FDT.__close         = S.FDT.__index.close
S.FDT.__name = 'fd.FDT'
S.FDT.__tostring = S.FD.__tostring

--- return whether two fstat's have equal modification times
--- FIXME: move this to civix
function M.modifiedEq(fs1, fs2)
  local s1, ns1 = fs1:modified()
  local s2, ns2 = fs2:modified()
  return (s1 == s2) and (ns1 == ns2)
end

----------------------------
-- WRITE / SEEK

function S.FD.__index:write(...)
  local s = sconcat('', ...)
  local c = self:_write(s, 0)
  while YIELD_CODE[c] do
    yield('poll', self:fileno(), S.POLLOUT)
    c = self:_write(s)
  end
  if c > 0 then return nil, self:codestr() end
  return self
end
function M.FDT.__index:write(...)
  local s = sconcat('', ...)
  while self:_write(s) do end
  finishRunning(self, 'poll', self:_evfileno(), S.POLLIN)
  if self:code() > 0 then return nil, self:codestr() end
  return self
end

local WHENCE = { set=S.SEEK_SET, cur=S.SEEK_CUR, ['end']=S.SEEK_END }
function S.FD.__index:seek(whence, offset)
  whence = assert(WHENCE[whence or 'cur'], 'unrecognized whence')
  while self:_seek(offset or 0, whence) do end
  finishRunning(self, 'poll', self:getpoll(S.POLLIN | S.POLLOUT))
  if(self:code() > 0) then return nil, self:codestr() end
  return self:pos()
end

function S.FD.__index:flush()
  self:_flush(); finishRunning(self, 'sleep', 1e-4)
  if self:code() ~= 0 then return nil, self:codestr() else return true end
end

function S.FD.__index:flags()
  local code, flags = self:_getflags()
  if code ~= 0 then error(self:codestr()) end
  return flags
end
function S.FD.__index:toNonblock()
  if self:_setflags(S.O_NONBLOCK | self:flags()) ~= 0 then
    return nil, self:codestr()
  end; return self
end
function S.FD.__index:toBlock()
  if self:_setflags(~S.O_NONBLOCK & self:flags()) ~= 0 then
    return nil, self:codestr()
  end; return self
end
function S.FD.__index:isAsync()
  return (self:flags() & S.O_NONBLOCK) ~= 0
end

function S.FD.__index:getpoll(events)
  return self:fileno(), events
end
function S.FDT.__index:getpoll()
  return self:_evfileno(), S.POLLIN
end

----------------------------
-- READ

--- FD's read may need to be called multiple times (O_NONBLOCK)
--- FDT's read CANNOT be called multiple times.
local function readLap(fd, c)
  if DONE_CODE[c]    then return end
  if YIELD_CODE[c]   then
    yield('poll', fd:getpoll(S.POLLIN))
    return true
  end
  return nil, fd:codestr()
end
function S.FD.__index:_readTill(till)
  while readLap(self, self:_read(till)) do end
end
function S.FDT.__index:_readTill(till)
  self:_read(till)
  while readLap(self, self:code()) do end
end

--- Different read modes
local function iden(x) return x end
local function noNL(s)
  return s and (s:sub(-1) == '\n') and s:sub(1, -2) or s
end
local function readAll(fd) fd:_readTill(); return fd:_pop() or '' end
local function readLine(fd, lineFn)
  local s = fd:_pop(NL); if s then return lineFn(s) end
  fd:_readTill(NL)
  local out = lineFn(fd:_pop(NL) or fd:_pop())
  return out
end
local function readLineNoNL(fd)  return readLine(fd, noNL) end
local function readLineYesNL(fd) return readLine(fd, iden) end
local function readAmt(fd, amt)
  assert(amt > 0, 'read non-positive amount')
  local s = fd:_pop(amt); if s then return s end
  fd:_readTill(amt)
  return fd:_pop(amt) or fd:_pop()
end

local READ_MODE = {
  a=readAll, ['*a']=readAll, l=readLineNoNL, L=readLineYesNL,
}
local function modeFn(mode)
  local fn = (type(mode) == 'number') and readAmt or READ_MODE[mode or 'l']
  if not fn then error('mode not supported: '..tostring(mode)) end
  return fn
end
function S.FD.__index:read(mode)
  return modeFn(mode)(self, mode)
end

function S.FD.__index:lines(mode)
  local fn = modeFn(mode or 'l')
  return function() return fn(self, mode) end
end

----------------------------
-- FDT
--- Note that FDT is IDENTICAL to FD except it's possible
--- that code() will be a FD_RUNNING. This is already handled,
--- as that is included as a YIELD_CODE (FD can be non-blocking)
S.FDT.__index.seek       = S.FD.__index.seek
S.FDT.__index.read       = S.FD.__index.read
S.FDT.__index.lines      = S.FD.__index.lines
S.FDT.__index.flush      = S.FD.__index.flush
S.FDT.__index.flags      = S.FD.__index.flags
S.FDT.__index.toNonblock = function() error'invalid' end
S.FDT.__index.toBlock    = function() error'invalid' end
S.FDT.__index.isAsync    = function() return true end


----------------------------
-- PollList
M.PollList = setmetatable({
__name='PollList',
__index = {
  __len = function(pl) return pl._pl:size() - #pl.avail end,
  resize = function(pl, newSize)
    local size = pl._pl:size(); assert(newSize >= size, 'attempted shrink')
    pl._pl:resize(newSize); for i=size,newSize-1 do push(pl.avail, i) end
  end,
  insert = function(pl, fileno, events)
    local i = pl.map[fileno] or pop(pl.avail)
    if not i then
      pl:resize((pl._pl:size() == 0) and 8 or pl._pl.size() * 2)
      i = assert(pop(pl.avail), 'failed to resize')
    end
    pl._pl:set(i, fileno, events)
    pl.map[fileno] = i
  end,
  ready = function(pl, timeoutSec)
    return pl._pl:ready(math.floor(timeoutSec * 1000))
  end,
  remove = function(pl, fileno)
    local i = assert(pl.map[fileno])
    push(pl.avail, i); pl.map[fileno] = nil;
    pl._pl:set(i, -1, 0)
  end,
}}, {
  __call=function(ty_)
    return setmetatable({
      _pl=S.pollList(),
      map  = {}, -- map of fileno -> pl[index]
      avail = {}, -- list of available indexes
    }, ty_)
  end,
})

----------------------------
-- io backfill

function M.openWith(openFn, path, mode)
  mode = mode or 'r'
  local flags = mflagsInt(mode:gsub('b', ''))
  local f = openFn(path, flags); finishRunning(f, 'sleep', 1e-4)
  if f:code() ~= 0 then return nil, f:codestr() end
  return f
end
function M.openFD(...) return M.openWith(S.openFD, ...)  end
function M.openFDT(...) return M.openWith(S.openFDT, ...) end
function M.open(...)
  return M.openWith((LAP_ASYNC and S.openFDT) or S.openFD, ...)
end
function M.close(fd) fd:close() end
function M.tmpfileFn(sysFn)
  local f = sysFn(); finishRunning(f, 'sleep', 1e-4)
  if f:code() ~= 0 then return nil, f:codestr() end
  return f
end
M._sync.tmpfile  = function() return M.tmpfileFn(S.tmpFD)  end
M._async.tmpfile = function() return M.tmpfileFn(S.tmpFDT) end
M.tmpfile = M._sync.tmpfile

function M.read(...)
  local inp = M.input()
  io.stderr:flush()
  return inp:read(...)
end
function M.lines(path, mode)
  dbg('fd.lines', path, mode)
  mode = mode or 'l'
  if not path then return M.input():lines(mode) end
  local fd = M.open(path)
  local fn = function()
    if not fd then return end
    local l = fd:read(mode)
    if l then return l end
    fd:close(); fd = nil
  end
  return fn, nil, nil, fd
end
function M.write(...) return M.output():write(...) end

function M.openFileno(fileno)
  local fd = S.newFD(); fd:_setfileno(fileno)
  return fd
end
M.stdin  = M.openFileno(S.STDIN_FILENO)
M.stdout = M.openFileno(S.STDOUT_FILENO)

function M.input() return M.stdin end
function M.output() return M.stdout end
function M.flush() return M.output():flush() end

local FD_TYPES = {[S.FD] = true, [S.FDT] = true}

function M.type(fd)
  local mt = getmetatable(fd)
  if mt and FD_TYPES[mt] then
    return (fd:fileno() >= 0) and 'file' or 'closed file'
  end
  return iotype(fd)
end
function M.fileno(fd)
  if iotype(fd) then return S.fileno(fd) end
  if type(fd) == 'userdata' then return fd:fileno() end
  local meth = rawget(getmetatable(fd), 'fileno')
  return meth and meth(fd)
end
local fileno = M.fileno
function M.ftype(f)
  return fmodeName(S_IFMT & fstmode(fileno(f)))
end
function M.isatty(fd)
  fd = type(fd) == 'number' and fd or fileno(fd)
  return fd and S.isatty(fd)
end

----------------------------
-- To Sync / Async

push(LAP_FNS_ASYNC, function()
  for k, v in pairs(M._async) do M[k] = v end
end)
push(LAP_FNS_SYNC, function()
  for k, v in pairs(M._sync)  do M[k] = v end
end)

local IO_KEYS = {}; for k in ([[
open   close  tmpfile
read   lines  write
stdout stdin
input  output flush
type
]]):gmatch'%w+' do push(IO_KEYS, k) end

local function copyKeysM(keys, from, to)
  for _, k in ipairs(keys) do
    to[k] = assert(rawget(from, k) or M[k])
  end
end
copyKeysM(IO_KEYS, io, M.io)

--- Switch the global [$io] module to use builtin functions.
function M.ioStd()
  assert(not LAP_ASYNC); copyKeysM(IO_KEYS, M.io,    io)
end
--- Switch the global [$io] module to use sync functions from
--- this module.
function M.ioSync()
  assert(not LAP_ASYNC); copyKeysM(IO_KEYS, M._sync, io)
end
--- Switch the global [$io] module to use async functions from
--- this module.
function M.ioAsync()
  assert(LAP_ASYNC);     copyKeysM(IO_KEYS, M._async, io)
end

return M