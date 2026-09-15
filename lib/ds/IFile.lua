local mty = require'metaty'
local ds = require'ds'

--- Indexed File: supports setting and getting fixed-length values (bytes) by
--- index, implementing the API of a list-like table.
local IFile = mty'ds.IFile' {
  'f [file]', 'path [str]', 'mode [str]',
  'len [int]', '_i [int]', '_m [str]: r/w mode',
  'sz [int]: the size of each value',
}

local mtype              = math.type
local sfmt, pack, unpack = mty.from(string, 'format,pack,unpack')
local info               = mty.from('ds.log  info')

getmetatable(IFile).__index = mty.hardIndex
IFile.__newindex            = mty.hardNewindex

--- seek to index in the "mode" m. Invariant: [$i <= len+1]
local function iseek(self, i, m, sz) --!> nil
  if self._i == i and self._m == m then return end
  self._m = m
  local to = (i-1) * sz
  local pos = assert(self.f:seek('set', to))
  assert(pos % sz == 0, 'pos incorrect')
end

--- This creates a new index file at path (path=nil uses tmpfile()).
--- Note: Use load if you want to load an existing index.
IFile.create = function(T, sz, path) --> IFile?, errmsg?
  assert(sz, 'must provide sz')
  local f,e; if path then f,e = ctx.open(path, 'w+')
  else                    f,e = ctx.tmpfile() end
  if not f then return f,e end
  return T{sz=sz, f=f, len=0, _i = 1, path=path, mode='w+'}
end

--- Reload IFile from path.
function IFile:reload() --> IFile?, errmsg?
  local f, err = ctx.open(self.path, self.mode or 'r+')
  if not f then return nil, err end
  local sz, bytes = self.sz, f:seek'end'
  f:seek('set', bytes - bytes % sz) -- truncate invalid bytes
  local len = bytes // sz
  self.f, self.len, self._i = f, len, len + 1
  return self
end

--- load an index file
IFile.load = function(T, sz, path, mode) --> IFile?, errmsg?
  assert(sz, 'must provide sz')
  return mty.construct(T, {sz=sz, path=path, mode=mode}):reload()
end

function IFile:flush() return self.f:flush() end
function IFile:__len() return self.len       end
IFile.__pairs = ipairs

function IFile:close()
  if self.f then self.f:close(); self.f = false end
end
function IFile:closed() --> bool
  return self.f and true or false
end

--- get bytes. If index out of bounds return nil.
--- Panic if there are read errors.
function IFile:getbytes(i) --!> str?
  if i > self.len then return end
  local sz = self.sz; iseek(self, i, 'r', sz)
  local v = assert(self.f:read(sz))
  assert(#v == sz, 'did not read sz bytes')
  self._i = i + 1
  return v
end
IFile.get = IFile.getbytes

function IFile:setbytes(i, v)
  local len = self.len; assert(i <= len + 1, 'newindex OOB')
  local sz = self.sz
  if #v ~= sz then error(sfmt('failed to write %i bytes', #v)) end
  iseek(self, i, 'w', sz); assert(self.f:write(v))
  if i > len then self.len = i end
  self._i = i + 1
end
IFile.set = IFile.setbytes

--- Move the IFile's path to [$to].
---
--- [$mv] must be of type [$fn(from, to)]. If not provided,
--- [$civix.mv] will be used.
---
--- This can be done on both closed and opened files.
---
--- The IFile will re-open on the new file regardless of the
--- previous state.
function IFile:move(to, mvFn) --> self
  assert(self.path, 'cannot move tmp file')
  mvFn = mvFn or require'civix'.mv
  if self.f then self:flush(); self:close() end
  mvFn(self.path, to); self.path = to
  self.mode = 'r+'
  return self:reload()
end

--- Get a new read-only instance with an independent file-descriptor.
---
--- Warning: currently the reader's len will be static, so this should
--- be mostly used for temporary cases. This might be changed in
--- the future.
function IFile:reader() --> IFile?, err?
  assert(self.path, 'reader only allowed on file with path')
  self:flush()
  local f,e = ctx.open(self.path, 'r'); if not f then return nil, e end
  local r = ds.copy(self)
  r.f, r.mode = f, 'r'
  return r
end

function IFile:__copy()
  local c = {}; for k, v in next, self, nil do c[k] = v end
  return setmetatable(c, getmetatable(self))
end

function IFile:__fmt(fmt)
  fmt:write('IFile(sz=', tostring(self.sz), ' ')
  if self.path then fmt:write(self.path) end
  fmt:write')'
end

return IFile
