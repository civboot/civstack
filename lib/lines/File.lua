local mty = require'metaty'

--- Usage: [$File{'path/to/file.txt', mode='r'}][{br}]
--- Indexed file of lines supporting modes 'r' and 'a+'.
---
--- ["use EdFile instead if you need to do non-append edits]
local File = mty.recordMod'File' {
  'path [string]: path of this file.',
  "mode [string]: 'r', 'a' or 'a+'",
  'f   [file]: open (normal) file object',
  'idx [U3File]: line index of f',
  'cache [WeakV]: cache of lines',
  'loadIdxFn: default=lines.futils.loadIdx',
  '_ln  [int]:  current line num (false=end)',
  '_pos [bool]: current file pos',
}

local G = mty.G
local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'
local U3File = require'lines.U3File'
local ix = require'civix'
local loadIdx = require'lines.futils'.loadIdx
local fd; if not G.NOLIB then fd = require'fd' end

local trace = require'ds.log'.trace
local largs = lines._args
local push, concat = table.insert, table.concat
local getmt = getmetatable
local split, construct = mty.split, mty.construct
local index, newindex = mty.hardIndex, mty.newindex
local check, WeakV = ds.check, ds.WeakV
local get, set = ds.get, ds.set

getmetatable(File).__index = mty.hardIndex
File.__newindex            = mty.hardNewindex

File.IDX_DIR = pth.concat{pth.home(), '.data/lines'}

File._initnew = ds.noop -- empty file: do nothing
function File:_reindex(idx, l, pos) --!> nil
  local f = self
  l, pos = l or 1, pos or 0
  if f:seek'end' == 0 then return end
  assert(f:seek('set', pos))
  local lines = f:lines'L'
  local prev = lines()
  while true do
    set(idx, l, pos); l = l + 1
    local line = lines(); if not line then break end
    pos, prev = pos + #prev, line
  end
  pos = pos + #prev
  if prev:sub(-1) == '\n' then
    set(idx, l, pos)
  end
  return pos
end

getmetatable(File).__call = function(T, t) --> File?, errmsg?
  t = t or {}
  if type(t) == 'string' then t = {path=t} end
  if t[1]                then t.path = t[1]; t[1] = nil end
  trace('%s.init%q', mty.tyName(T), t)
  local f, err, idx
  if t.tmp then
    f = t.tmp; t.tmp = nil
    idx, err = U3File:create(); if not idx then return nil, err end
    T._reindex(f, idx); f:flush(); idx:flush()
  elseif not t.path then
    f, err = ctx.tmpfile();      if not f   then return nil, err end
    idx, err = U3File:create(); if not idx then return nil, err end
    T._initnew(f, idx)
  elseif type(t.path) == 'string' then
    t.mode = t.mode or 'r'
    trace('opening path %s %s', t.path, t.mode)
    f, err = ctx.open(t.path, t.mode); if not f then return nil, err end
    local ipath = pth.concat{T.IDX_DIR, t.path}
    idx, err = (t.loadIdxFn or loadIdx)(f, ipath, t.mode, T._reindex)
    if not idx then return nil, err end
  else error'invalid path' end
  t.f, t.idx, t.cache = f, idx, WeakV{}
  return construct(T, t)
end

function File:close()
  if self.idx then self.idx:close()             end
  if self.f   then self.f:close(); self.f = false end
end
function File:flush() --> ok, errmsg?
  local o,e = self.idx:flush(); if not o then return o,e end
  o,e = self.f:flush()          if not o then return o,e end
  if not G.NOLIB then
    local fs, e = ix.stat(self.f); if not fs then return nil,e end
    return ix.setModified(self.idx.f, fs:modified())
  end
end

--- append to file
function File:write(...) --> ok, errmsg?
  local f, idx, cache, pos, o,e = self.f, self.idx, self.cache
  local t = largs(...)
  local tlen = #t
  if tlen == 0 then return end
  if self._ln or not self._pos then
    pos,e = f:seek'end'; if not pos then return pos,e end
    self._ln = false
  else pos = self._pos end
  self._pos = false
  o,e = f:write(t[1]); if not o then return o,e end
  pos = pos + #t[1]
  local len = #idx -- start length
  if len == 0 then len = 1; idx:set(1, 0) end
  cache[len] = nil
  for l=2,tlen do
    local line = t[l];
    o,e = f:write('\n', line); if not o then return o,e end
    len = len + 1; idx:set(len, pos + 1)
    pos = pos + 1 + #line
  end
  self._pos = pos
end

function File:__len() return #self.idx end

--- Get line at index
function File:get(i) --> line
  local cache = self.cache
  local line = cache[i]; if line then return line end
  local f, idx, pos, err = self.f, self.idx, self._pos
  if i > #idx then return end -- line num OOB
  if not pos or i ~= self._ln then -- update file pos
    pos = assert(self.idx:get(i))
    assert(f:seek('set', pos))
  end
  line = check(2, f:read'L') or ''
  self._pos = pos + #line
  if line:sub(-1) == '\n' then line = line:sub(1, -2) end
  self._ln, cache[i] = i + 1, line
  return line
end

--- Set line at index
function File:set(i, v)
  local f, idx, cache, pos = self.f, self.idx, self.cache, self._pos
  local len = #idx; assert(i == len + 1, 'only append allowed')
  if not pos or self._ln then pos = assert(f:seek'end') end
  self._ln, self._pos = false, false
  if pos == 0 then
    assert(f:write(v))
    self._pos = pos + #v
  else
    assert(f:write('\n', v))
    self._pos = pos + #v + 1
    pos = pos + 1
  end
  idx:set(i, pos); cache[i] = v
end

function File:__fmt(f)
  f:write'lines.File('
  if self.path then f:write(self.path) end
  f:write')'
end

--- Get a new read-only instance with an independent file-descriptor.
---
--- This allows reading the file while another coroutine writes it (via
--- [<lap.html>]).
function File:reader() --> lines.File?, err?
  local path = assert(self.path, 'reader only allowed on file with path')
  local idx = self.idx:reader()
  local f,e = ctx.open(self.path, 'r'); if not f then return nil, e end
  local new = ds.copy(self)
  new.f, new.idx, new.mode = f, idx, 'r'
  return new
end

File.extend = ds.defaultExtend
File.icopy  = ds.defaultICopy

return File
