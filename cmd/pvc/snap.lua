local mty   = require'metaty'

--- pvc submodule containing logic for snapshots, aka complete directories of
--- files.
local snap = mty.mod'pvc.snap'

local ds    = require'ds'
local pth   = require'ds.path'
local ix    = require'civix'
local lines = require'lines'
local kev   = require'lines.kev'
local T     = require'civtest'
local pu    = require'pvc.unix'

local str                  = tostring
local srep, sfmt, sconcat  = mty.from(string, 'rep, format, concat')
local push, pop, concat    = mty.from'table    insert, remove, concat'
local sort                 = mty.from'table    sort'
local int                  = mty.from'math     tointeger'
local assertf              = mty.from'fmt      assertf'
local splitList            = mty.from'ds       splitList'
local info, trace          = mty.from'ds.log   info, trace'
local toDir, pconcat, nice = mty.from'ds.path  toDir, concat, nice'
local pfirst               = mty.from'ds.path  first'

local Path

snap.PVC      = '.pvc/'
snap.PVCINDEX = 'PVCINDEX'
snap.PVCPATCH = 'PVCPATCH'
snap.PVCIGNORE = '.pvcignore'


local SKIP_ON_LOAD = {[snap.PVCINDEX] = 1, [snap.PVCPATCH] = 1}

local X = tonumber('111', 8) -- any executable bit

local function pcmp(a, b) return a.p < b.p     end
local function psort(t)   return sort(t, pcmp) end

function snap.loadIndex(index) --> {Path}
  local i, paths = 0, {}
  for ln in ctx.lines(index) do if ln:find'%S' then
    i = i + 1
    local path = Path:from(ln)
    paths[i] = path; paths[path.p] = i
  end end
  return paths
end

--- Load a raw directory with .pvcignore etc as a list of Paths.
--- Note that this drops any information about the path origin id.
function snap.loadDirAsIndex(dir) --> {Path}
  local i, paths, ipath = 0, {}, dir..snap.PVCIGNORE
  local pindex = dir..snap.PVCINDEX
  local ignore = ix.exists(ipath) and lines.load(ipath) or {}
  local w = ix.Walk{dir}
  for path, pathTy in w do; local path=path
    local p = pth.relative(dir, path)
    local dotP = './'..p
    if pathTy == 'dir' then
      if (p == snap.PVC or ds.find(dotP, ignore)) then w:skip() end
      goto cont
    end
    if p == snap.PVCINDEX or ds.find('./'..p, ignore) then goto cont end
    local st = assertf(ix.stat(path), 'cannot stat %q', path)
    i = i + 1
    paths[p] = i; paths[i] = snap.Path{
      x=(0==st:mode()&X), mtime=st:modified(), p=p, 
    }
    ::cont::
  end
  return paths
end

-----------------------------------
-- Diff
-- TODO: move this below Snap

--- [$Diff:of(dir1, dir2)] returns what changed between two pvc dirs.
snap.Diff = mty'Diff' {
  'dir1 [path]', 'dir2 [path]',
  'equal   {path}',
  'changed {path}',
  'deleted {path}',
  'created {path}',
}
local Diff = snap.Diff

--- Return a copy with [$equal={}].
function Diff:reduced() --> Diff
  return mty.construct(getmetatable(self), {
    equal={},             changed=self.changed,
    deleted=self.deleted, created=self.created,
  })
end

function Diff:hasDiff()
  return (#self.changed > 0) or (#self.deleted > 0) or (#self.created > 0)
end

function Diff:format(fmt, full)
  local function s(...) return fmt:styled(...) end
  if full then
    for _, line in ds.split(self:patch(), '\n') do
      local l2 = line:sub(1,2)
      if l2 == '--' or l2 == '++' or l2 == '@@' then s('notify', line, '\n')
      elseif line:sub(1,1) == '-' then s('base',   line, '\n')
      elseif line:sub(1,1) == '+' then s('change', line, '\n')
      else fmt:write(line, '\n') end
    end
  else
    if not self:hasDiff() then return s('bold', 'No Difference', '\n') end
    s('bold', 'Diff:', ' ', self.dir1, ' --> ', self.dir2, '\n')
    for _,path in ipairs(self.deleted) do s('base',   '-'..path, '\n') end
    for _,path in ipairs(self.created) do s('change', '+'..path, '\n') end
    for _,path in ipairs(self.changed) do s('notify', '~'..path, '\n') end
  end
end

function Diff:patch() --> patchText
  local d1, d2, patch = self.dir1, self.dir2, {}
  for _, path in ipairs(self.changed) do
    push(patch, pu.diff(d1..path.p, path.p, d2..path.p, path.p))
  end
  for _, path in ipairs(self.created) do
    push(patch, pu.diff(nil, nil, d2..path.p, path.p))
  end
  for _, path in ipairs(self.deleted) do
    push(patch, pu.diff(d1..path.p, path.p))
  end
  return concat(patch, '\n')
end

-----------------------------------
-- Snap

--- Object in index files in form [$(+-x)(mtime):(id)/p]
snap.Path = mty'Path' {
  'c [bool]: created',
  'd [bool]: deleted',
  'x [bool]: executable',
  'mtime [int]: modification time',
  'id [int]: last id modified in',
  'p [path]: the path value',
}
Path = snap.Path

function Path:__tostring() return concat{
  self.c and '+' or '', self.d and '-' or '', 
  self.x and 'x' or '', self.mtime or '',
  ':', self.id or '', '/', self.p,
}end

function Path:cleaned() --> Path
  return Path{x=self.x, id=self.id, p=self.p}
end

function Path:updateId(id) --> Path
  if self.m or self.c then self.id = id end
  return self
end

local function strNil(s) return (s~='') and true or nil end
function Path.from(T, str)
  local attrs, p = pfirst(str)
  local attrs = splitList(attrs, ':')
  local c, d, x, mtime = attrs[1]:match'([+]?)([-]?)(x?)(%d*)'
  return mty.construct(T, {
    c = strNil(c), d = strNil(d), x = strNil(x),
    mtime = int(mtime), id = int(attrs[2]), p = p, 
 })
end

--- return Path without the mtime.
function Path:noMTime() --> Path
  local p = ds.copy(self); p.mtime = nil
  return p
end

--- A snapshot with a set of indexed paths.
snap.Snap = mty'Snap' {
  'root  [path]: path to root dir',
  '_index {Path}: loaded index of paths in order, also keyed path->index',
}
local Snap = snap.Snap

getmetatable(Snap).__call = function(T, self)
  self.root  = assert(self.root or pop(self, 1), 'must provide root')
  return mty.construct(T, self)
end

function Snap:init() --> self
  local ipath = pth.concat{self.root, snap.PVCINDEX}
  self._index = ix.exists(ipath) and snap.loadIndex(ipath)
             or snap.loadDirAsIndex(self.root)
  return self
end

function Snap:index() --> {Path}
  if not self._index then self:init() end
  return self._index
end

--- call [$fn(path1, path2)] for all paths in both snap's indexes.
--- The value will be nil if it is missing in either path.
---
--- Note: the passed in paths are relative to root.
function Snap:map2(s2, fn)
  local idx1, idx2 = self:index(), s2:index()
  for _, p1 in ipairs(idx1) do fn(p1, idx2[idx2[p1.p]]) end
  for _, p2 in ipairs(idx2) do if not idx1[p2.p] then fn(nil, p2) end end
end

--- Copy self to dir
function Snap:copyTo(dir)
  local root, idx = self.root, self:index()
  for _, path in ipairs(idx) do
    ix.forceCp(root..path.p, dir..path.p)
  end
  local f = io.open(dir..snap.PVCINDEX, 'w')
  for _, path in ipairs(idx) do f:write(str(path), '\n') end
  f:flush(); f:close()
end

--- [$s1:diff(s2)] get the diff of two snaps.
function Snap:diff(s2) --> Diff
  local s1, peq = self, ix.pathEq
  local r1, r2 = s1.root, s2.root

  local equal, changed, deleted, created = {}, {}, {}, {}
  self:map2(s2, function(p1, p2)
    if p1 and p2 then
      if peq(r1..p1.p, r2..p2.p) then push(equal,   p1)
      else                            push(changed, p1) end
    elseif p1 then                    push(deleted, p1)
    else                              push(created, p2)
    end
  end)
  psort(equal); psort(changed); psort(deleted); psort(created)
  return Diff{
    dir1=r1, dir2=r2,
    equal=equal, changed=changed, deleted=deleted, created=created,
  }
end

return snap