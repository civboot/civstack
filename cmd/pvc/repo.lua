local mty   = require'metaty'

--- pvc submodule containing most logic for managing the pvc repository.
local repo = mty.mod'pvc.repo'

local ds    = require'ds'
local pth   = require'ds.path'
local ix    = require'civix'
local lines = require'lines'
local kev   = require'lines.kev'
local T     = require'civtest'
local snap  = require'pvc.snap'
local pu    = require'pvc.unix'

local str                  = G.tostring
local srep, sfmt, sconcat  = mty.from(string, 'rep, format, concat')
local push, pop, concat    = mty.from(table,  'insert, remove, concat')
local int                  = mty.from(math,   'tointeger')
local construct            = mty.from'metaty   construct'
local notify, assertf      = mty.from'fmt      notify, assertf'
local info, trace          = mty.from'ds.log   info, trace'
local s, pk                = mty.from'ds       simplestr, popk'
local toDir, pconcat, nice = mty.from'ds.path toDir, concat, nice'
local Snap                 = mty.from'pvc.snap Snap'

local EMPTY = {}

-----------------------
-- CONSTANTS

local AT    = {['@'] = true, at = true}
local LOCAL = {['.'] = true, [''] = true, ['local'] = true}

repo.DOT = '.pvc/'
repo.INIT_PVCIGNORE = [[
%.git/
%.civ/
%.out/
]]
repo.REV0  = {['00.p'] = 'zero patch'}

--- reserved branch names
repo.RESERVED_NAMES = { ['.']=1, ['local']=1, at=1, tip=1 }

-----------------------------------
-- Utilities

local function asRev(br, id) return sfmt('%s@%s', br, id) end

--- get a set of the lines in a file
local function loadLineSet(path) --> set
  local s = {}; for l in ctx.lines(path) do s[l] = true end; return s
end

--- Given an id return 01/23/45 (no extension)
function repo.rawIdPath(id)
  id = tostring(id)
  id = ((#id % 2) == 1 and '0' or '')..id
  return id:gsub('(%d%d)', '%1/'):sub(1,-2)
end
local idPath = repo.rawIdPath

local function loadInt(path) return int(pth.read(path)) end

local PATCH_RESERVED = {['---']=1, ['+++']=1, ['!!']=1, ['@@@']=1}

local function isPatchLike(line)
  return PATCH_RESERVED[line:sub(1,3)] or PATCH_RESERVED[line:sub(1,2)]
end

local function checkDesc(desc)
  desc = ds.trim(desc or '')
  if not desc:find'%S' then return nil,  'commit must provide description' end
  for _, line in ds.split(desc, '\n') do
    if isPatchLike(line) then
      return nil, sfmt("desc line invalid: %q", line)
    end
  end
  return desc
end

-----------------------------------
-- REPO

--- A [$.pvc/] repo with branches, snapshots and a current state.
repo.Repo = mty'Repo' {
  'w [string]: the work_tree, aka the live user code',
  'r [string]: repo dir, typically .../.pvc/',
  '_index [string]: .pvc/index',
  'atPath [string]: .../.pvc/at',
}
local Repo = repo.Repo

getmetatable(Repo).__call = function(T, self)
  self.w = self.w or pop(self)
  assert(self.w, 'must set w (work tree)')
  self.w = pth.canonical(toDir(self.w))

  self.r = self.r or pconcat{self.w, '.pvc/'}
  self.r = pth.canonical(toDir(self.r))
  self.atPath = self.r..'at'
  return construct(T, self)
end

function Repo:index()
  if not self._index then self._index = snap.loadIndex(self.r..'index') end
  return self._index
end

--- Get rev (br@id) the repo is currently at.
function Repo:at() return pth.read(self.atPath) end --> rev
function Repo:_setAt(rev)
  pth.write(self.atPath, rev)
end

function Repo:atBranch() --> branch
  return assert(self:at():match'^(%w+)@')
end

--- Get the branch directory.
function Repo:bdir(br) --> .pvc/br/
  if br:sub(1,1) == '/' then return br end
  return pconcat{self.r, '@'..br, '/'}
end

--- Get the base of the branch
function Repo:base(br) --> rev
  return pth.read(self:bdir(br)..'base')
end

--- Get the tip of the branch.
function Repo:tip(br) --> int
  return int(pth.read(self:bdir(br)..'tip'))
end
function Repo:setTip(br, id)
  assert(id > 0)
  pth.write(self:bdir(br)..'tip', id)
end

--- Converts a rev into (typically) branch@id form. Exceptions include: [+
--- * nil/local become 'local', meaning the local snapshot.
--- * /path/to/dir/ is kept and must be a snapshot path with an index.
--- ]
--- See [@pvc] docs for all special names and ids (local, at, tip, etc).
function Repo:rev(rev) --> rev
  if not rev or LOCAL[rev]   then return 'local' end
  if type(rev) == 'number'   then return asRev(self:atBranch(), rev) end
  if rev:find'^[%w_.]+@%d+$' then return rev end
  if AT[rev]                 then return self:at() end
  local nrev = rev:match'^@(%d+)$'
  if nrev                    then return asRev(self:atBranch(), nrev) end
  if rev:find'^/'            then return rev end
  if rev:find'^[%w_.]+@tip$' or rev:find'^[%w_.]+@?$' then
    return asRev(rev, self:tip(rev))
  end
  if rev:find'^@?tip$' then
    local br = self:atBranch()
    return asRev(br, self:tip(br))
  end
  assertf(rev:find'^[%w_.]+$', 'invalid rev: %q', rev)
  return rev, self:tip(rev)
end

function Repo:splitRev(rev) --> br, id
  local r = self:rev(rev)
  local br,id = r:match'^([%w_.]+)@(%d+)$'
  assertf(br, 'invalid splitRev: %q -> %q', rev, r)
  return br, int(id)
end

--- Get path to patch
function Repo:patch(rev) --> /d/br/rev/01/23.p
  local br,id = self:splitRev(rev)
  return pconcat{self.r, '@'..br, 'rev', idPath(id)..'.p'}
end

--- Get snapshot dir and index
function Repo:snapPath(rev) --> /d/br/snap/123/
  rev = self:rev(rev); assert(rev ~= 'local')
  local br,id = self:splitRev(rev)
  return pconcat{self.r, '@'..br, 'snap', tostring(id), '/'}
end

--- Create snapshot 0
function Repo:snapshot0(br) --> snap.Snap
  local p = self:snapPath(asRev(br,0)); ix.mkDirs(p)
  return Snap{p}
end

--- Initialize a new branch.
--- This handles both initial base=nil, id=0 and from base.
function Repo:newBranch(name, baseRev) --> ../branch/
  assert(not repo.RESERVED_NAMES[name], 'reserved branch name: %q', name)
  assert(name:find'^[%w._]+$',          'invalid branch name: %q', name)
  local dir = self:bdir(name)
  assertf(not ix.exists(dir), 'branch %s: %s already exists', name, dir)
  baseRev = self:rev(baseRev)
  local base,baseId
  if baseRev ~= 'local' then base,baseId = self:splitRev(baseRev) end
  ix.mkTree(dir, {
    tip  = tostring(baseId or 0),
    base = base and baseRev or '@0',
    rev  = base and EMPTY   or repo.REV0,
    snap = EMPTY,
  }, true)
  return dir
end

--- Initialize a new repository with main br name (default='main').
function Repo:init(br) --> self
  br = br or 'main'
  if ix.exists(self.r) then error(self.r..' already exists') end
  ix.mkTree(self.r, { 
    at = asRev(br,0),
    index = '',
    tmp = {},
  }, true)
  self:newBranch(br, nil)
  local ign = self.w..snap.PVCIGNORE
  if not ix.exists(ign) then
    pth.write(ign, repo.INIT_PVCIGNORE)
    notify('created initial %s', ign)
  end
  return self
end

--- Return empty temporary folder of name.
--- Deletes the tmp dir if it already exists.
function Repo:tmp(name) --> .pvc/tmp/name
  local d = pconcat{self.r, 'tmp', name, '/'}
  if ix.exists(d) then ix.rmRecursive(d) end
  ix.mkDirs(d)
  return d
end

function Repo:localsnap()
  local s, ridx = Snap{self.w}, self:index()
  for _, p in ipairs(s:index()) do
    local rpath = ridx[p.p]; if rpath then p.id = rpath.id end
  end  
  return s
end

--- Snapshot the br@id by applying patches.
--- Return the materialized snapshot and the rev.
function Repo:snapshot(rev) --> Snap, rev
  rev = self:rev(rev)
  if rev == 'local' then return self:localsnap(), rev end
  do 
    local s = self:snapPath(rev)
    if ix.exists(s) then return Snap{s}, rev end
  end
  local br,id = self:splitRev(rev)
  if id == 0 then return self:snapshot0(br), rev end
  local brDir= self:bdir(br)
  -- check base
  local brev = self:base(br)
  local bbr,bid = self:splitRev(brev)
  -- if the id is part of base then return that instead
  if id <= bid then return self:snapshot(asRev(bbr,id)) end

  trace('creating snapshot for %s', rev)
  local sdir, fid = brDir..'snap/'
  do -- find "from id" of the closest snapshot
    if not ix.exists(sdir) then ix.mkDir(sdir) end
    local sdirs = ix.ls(sdir)
    dbg('sdirs', sdirs)
    if sdirs[1] ~= '0' then table.insert(sdirs, 1, '0') end
    local fi = ds.binarySearch(sdirs, str(id)); assert(fi >= 0, fi)
    fid = ds.closest(id, int(sdirs[fi]) or bid, int(sdirs[fi+1]) or bid)
  end
  local fsnap = self:snapshot((fid==bid) and brev or asRev(br,fid))
  local tmp = self:tmp(rev)
  trace('creating snapshot from %s in %s', fsnap, tmp)
  fsnap:copyTo(tmp)

  local patch = (fid <= id) and pu._patch or pu._rpatch
  for i=fid,id,(fid<=id) and 1 or -1 do
    if i == 0 then goto cont end
    local ppath = self:patch(asRev(br,i))
    trace('patching %s with %s', tmp, ppath)
    patch(tmp, ppath)
  ::cont:: end

  local tsnap = self:snapPath(rev); assert(not ix.exists(tsnap))
  ix.mv(tmp, tsnap); info('created snapshot %s', tsnap)
  return Snap{tsnap}
end

--- Compare [$br1@id] to [$br2@id]
function Repo:diff(r1, r2) --> snap.Diff
  r1, r2 = self:rev(r1), self:rev(r2); info('Repo:diff %s %s', r1, r2)
  return self:snapshot(r1):diff(self:snapshot(r2))
end

--- Commit
function Repo:commit(desc, diff) --> rev2
  desc = assert(checkDesc(desc))
  local rev = self:at()
  local br,id = self:splitRev(rev)
  local dir = self:bdir(br)
  if id ~= self:tip(dir) then error(s[[
    ERROR: working id is not at tip. Solutions:
    * branch from this id.
    * stash -> [$pvc at tip] -> unstash -> commit.
    * prune: move or delete downstream changes.
  ]])end
  local rev2 = asRev(br, id+1)
  trace('start commit from %s to %s', rev, rev2)
  local snap2 = self:snapPath(rev2)
  assertf(not ix.exists(snap2), 'snapshot %q already exists', snap2)
  local base =  self:snapshot(rev)
  local bindex = base:index()
  local tmp  = self:tmp(rev2)

  local function updatePath(p)
    p = p:cleaned()
    local ip = bindex[bindex[p.p]]
    if ip and (ip.c or ip.m) then p.id = id end
    return p
  end

  local nindex = {}
  for _, p in ipairs(diff.deleted) do
    p = updatePath(p); p.d = true; push(nindex, p)
  end
  for _, p in ipairs(diff.created) do
    p = updatePath(p); p.c = true; push(nindex, p)
  end
  for _, p in ipairs(diff.changed) do
    p = updatePath(p); p.m = true; push(nindex, p)
  end
  for _, p in ipairs(diff.equal) do
    p = updatePath(p);             push(nindex, p)
  end
  table.sort(nindex, function(a, b) return a.p < b.p end)
  local ipath = tmp..snap.PVCINDEX 
  local f = assert(ctx.open(ipath, 'w'))
  for _, p in ipairs(nindex) do f:write(str(p), '\n') end
  f:flush(); f:close()

  -- Apply the patch
  local idiff = assert(id==0 and pu.diff(nil, nil, ipath, snap.PVCINDEX)
                or pu.diff(base.root..snap.PVCINDEX, snap.PVCINDEX, 
                           ipath,                    snap.PVCINDEX))
  ix.rm(ipath) -- remove, idiff in pu._patch re-updates
  base:copyTo(tmp)

  local ppath = tmp..snap.PVCPATCH
  local f = assert(ctx.open(ppath, 'w'))
  f:write(desc, '\n\n')
  f:write(idiff, '\n')
  f:write(diff:patch())
  f:flush(); f:close()

  pu._patch(tmp, ppath)
  local pfinal = self:patch(rev2); ix.cp(ppath, pfinal)
  ix.mv(tmp, snap2)
  self:_setAt(rev2)
  self:setTip(br, id+1)
  notify('commited %s in %s', rev2, pfinal)
end


function Repo:setAt(nbr, nid)
  local cbr,cid = self:at()
  local ndir = self:bdir(cbr); nid = nid or self:tip(ndir)
  trace('at %s@%i -> %s@%i', cbr, cid, nbr, nid)

  local csnap = self:snapshot(cbr,cid)
  -- FIXME: finish from pvc.atId
end

return repo