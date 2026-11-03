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
local errorf               = mty.from'fmt      errorf'
local info, trace          = mty.from'ds.log   info, trace'
local s, pk                = mty.from'ds       simplestr, popk'
local toDir, pconcat, nice = mty.from'ds.path toDir, concat, nice'
local Snap                 = mty.from'pvc.snap Snap'

local EMPTY = {}

local BranchLog

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

function repo.asRev(br, id) return sfmt('%s@%s', br, id) end
function repo.revId(rev) 
  return rev and int(rev:match'^.*@(%d+)$') or 0
end
local asRev, revId = repo.asRev, repo.revId

local function splitRev(rev) --> br, id
  if not rev then return rev end
  local br,id = rev:match'^([%w_.]+)@(%d+)$'
  assertf(br, 'invalid splitRev: %q', rev)
  return br, int(id)
end

--- get a set of the lines in a file
local function loadLineSet(path) --> set
  local s = {}; for l in ctx.lines(path) do s[l] = true end; return s
end

--- Given an id return 01/23/45 (no extension)
function repo.rawIdPath(id)
  id = str(id)
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
-- BRANCH

repo.Branch = mty'Branch' {
  'name [string]',  'dir [dir]', '_rev [dir]', '_snap [dir]',
  '_base [string]', '_tip  [int]',
}
local Branch = repo.Branch
getmetatable(Branch).__call = function(T, self)
  assert(self.name and self.dir)
  self.dir = pth.canonical(pth.toDir(assert(self.dir)))
  self._rev, self._snap = self.dir..'rev/', self.dir..'snap/'
  return construct(T, self)
end

--- Usage: [$Branch:fake{name='bar', _base='foo@12', _tip=4}][{br}]
--- Used for testing.
function Branch.fake(T, self)
  self.dir = self.dir or ('/@'..self.name..'/')
  return T(self)
end

function Branch:base() --> rev
  if self._base ~= nil then return self._base end
  local bpath = self.dir..'base'
  self._base = ix.exists(bpath) and pth.read(bpath) or false
  return self._base
end

function Branch:setBase(rev)
  pth.write(self.dir..'base', rev)
  self._base = rev
end

function Branch:tip() --> int
  if self._tip ~= nil then return self._tip end
  self._tip = assert(int(pth.read(self.dir..'tip')))
  return self._tip
end

function Branch:setTip(id)
  assert(id > 0)
  pth.write(self.dir..'tip', str(id))
  self._tip = id
end

function Branch:patch(id) return self._rev..idPath(id)..'.p' end
function Branch:snap(id)  return self._snap..toDir(str(id))  end

--- Usage: [$b:desc{id, max=10, index=true}]
function Branch:desc(c) --> {line}
  local t, f = {}, assert(io.open(self:patch(c[1])))
  for ln in f:lines'l' do
    -- keep PVCINDEX diff but stop on any other file diff.
    if (t[#t] or ''):sub(1,3) == '---' and
        (not c.index or not ln:find'... PVCINDEX') then
      pop(t); break
    end
    push(t, ln); if c.max and #t >= c.max then break end
  end
  f:close()
  return t
end

-----------------------------------
-- REPO

--- A [$.pvc/] repo with branches, snapshots and a current state.
repo.Repo = mty'Repo' {
  'w [string]: the work_tree, aka the live user code',
  'r [string]: repo dir, typically .../.pvc/',
  '_index [string]: .pvc/index',
  'atPath [string]: .../.pvc/at',
  '_branches {name: Branch}',
}
local Repo = repo.Repo

getmetatable(Repo).__call = function(T, self)
  self.w = self.w or pop(self)
  assert(self.w, 'must set w (work tree)')
  self.w = pth.canonical(toDir(self.w))

  self.r = self.r or pconcat{self.w, '.pvc/'}
  self.r = pth.canonical(toDir(self.r))
  self.atPath = self.r..'at'
  self._branches = self._branches or {}
  return construct(T, self)
end

function Repo:pvc(cmd)
  if type(cmd) == 'string' then cmd = {cmd} end
  local sub = assert(pop(cmd, 1), 'must provide subcommand')
  sub = assertf(require'pvc'[sub], '%s: invalid pvc subcmd', sub)
  cmd.work_tree, cmd.pvc_repo = self.w, self.r
  cmd.__repo = self
  return mty.construct(sub, cmd)()
end

function Repo:index()
  if not self._index then self._index = snap.loadIndex(self.r..'index') end
  return self._index
end

--- Get rev (br@id) the repo is currently at.
function Repo:at() return ds.trim(pth.read(self.atPath)) end --> rev
function Repo:_setAt(rev) pth.write(self.atPath, rev) end

function Repo:atBranch() --> name
  return assert(self:at():match'^(%w+)@')
end

function Repo:branch(name) --> Branch
  local b = self._branches[name]; if b then return b end
  b = Branch{name=name, dir=concat{self.r, '@', name, '/'}}
  self._branches[name] = b
  return b
end

function Repo:branches() --> {name: Branch}
  for e, ftype in ix.dir(self.r) do
    if ftype == 'dir' and e:sub(1,1)=='@' then
      self:branch(e:match'^@([._%w]+)') -- load
    end
  end
  return ds.copy(self._branches)
end

function repo._childGraph(branches)
  local g = {}
  for name, b in pairs(branches) do
    g[name] = g[name] or {}
    local base, bid = splitRev(b:base())
    assertf(not base or branches[base], '%s base not found: %s', name, base)
    g[base] = g[base] or {}
    g[base][name] = bid; push(g[base], name)
  end
  for _, ch in pairs(g) do
    table.sort(ch, function(a, b) return ch[a] < ch[b] end)
  end
  return g
end

--- Return the graph of [$branch -> {child}], where the [$false] branch
--- lacks a base (e.g. main).
---
--- The [${child}] is both a list and a map of which id the child is
--- branched from, e.g [{$ lang=lua}{'dev', dev=6,  'fix', fix=10}].
function Repo:childGraph() --> {name: {child}}
  return repo._childGraph(self:branches())
end

--- Usage: [$desc{rev, max=5, index=true}][{br}]
--- Usage: [$desc'br@id']
function Repo:desc(c) --> string
  if type(c) == 'string' then c = {c} end
  local br,id = self:splitRev(c[1])
  c = ds.copy(c); c[1] = id
  return concat(self:branch(br):desc(c), '\n')
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
  -- tip of some branch
  local br = rev:find'^@?tip$' and self:atBranch()
          or rev:match'^([%w_.]+)@?$' or rev:match'^([%w_.]+)@tip$' 
          or rev:find'^[%w_.]+$' and rev
          or errorf('invalid rev: %q', rev)
  return br, self:branch(br):tip()
end

--- Get the actual branch name @id (going through bases).
function Repo:actualBranch(br, id) --> br
  local b = self:branch(br); while true do
    local bbr, bid = splitRev(b:base())
    if not bid or bid<id then break end
    b = self:branch( (splitRev(b:base())) )
  end
  return b.name
end

function Repo:splitRev(rev) --> br, id
  return splitRev(self:rev(rev))
end

function Repo:splitRange(range) --> rev1, rev2
  if     not range          then range = 'at::local'
  elseif not range:find'::' then range = range..'::local' end
  local rev1, rev2 = range:match'^([^:]+)::(.*)'
  assertf(rev1, 'invalid range: %q', range)
  return rev1, rev2
end

--- Get path to patch
function Repo:patch(rev) --> /d/br/rev/01/23.p
  local br,id = self:splitRev(rev)
  return pconcat{self.r, '@'..br, 'rev', idPath(id)..'.p'}
end

--- Create snapshot 0
function Repo:snapshot0(br) --> snap.Snap
  local p = self:branch(br):snap(0); ix.mkDirs(p)
  return Snap{p}
end

--- Initialize a new branch.
--- This handles both initial base=nil, id=0 and from base.
function Repo:newBranch(name, baseRev) --> Branch
  assert(name, 'must specify new branch name')
  assert(not repo.RESERVED_NAMES[name], 'reserved branch name: %q', name)
  assert(name:find'^[%w._]+$',          'invalid branch name: %q', name)
  local b = self:branch(name)
  assertf(not ix.exists(b.dir), 'branch %s: %s already exists', name, b.dir)
  dbg('newBranch', name, 'from', baseRev)
  baseRev = self:rev(baseRev)
  local base,baseId
  dbg('  baseRev ->', baseRev)
  if baseRev ~= 'local' then base,baseId = self:splitRev(baseRev) end
  baseId = base and baseId or 0
  ix.mkTree(b.dir, {
    tip  = str(baseId),
    base = base and baseRev or nil,
    rev  = base and EMPTY   or repo.REV0,
    snap = EMPTY,
  }, true)
  local rev = asRev(name,baseId); self:_setAt(rev)
  notify('created branch %s from %s: %s', name, baseRev, pth.nice(b.dir))
  notify('now at %s', rev)
  return b
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
function Repo:snapshot(rev) --> Snap
  dbg('snapshot', rev)
  rev = self:rev(rev); if rev == 'local' then return self:localsnap() end
  local br,id = self:splitRev(rev); local b = self:branch(br)
  assertf(ix.exists(b.dir), 'branch %s does not exist', br)
  local bbr,bid=nil,0; if b:base() then bbr,bid = splitRev(b:base()) end
  if id <= bid then
    return not bbr and assert(id==0) and self:snapshot0(br)
        or self:snapshot(asRev(bbr,id))
  end
  if ix.exists(b:snap(id)) then return Snap{b:snap(id)}, rev end
  -- check base
  trace('creating snapshot for %s', rev)
  local fid; do -- fid="from fid", find from closest snapshot.
    if not ix.exists(b._snap) then ix.mkDir(b._snap) end
    local sdirs = ix.ls(b._snap)
    dbg('sdirs', sdirs)
    if sdirs[1] ~= '0' then table.insert(sdirs, 1, '0') end
    local fi = ds.binarySearch(sdirs, str(id)); assert(fi >= 0, fi)
    fid = ds.closest(id, int(sdirs[fi]) or bid, int(sdirs[fi+1]) or bid)
  end
  local fsnap = self:snapshot(fid==bid and b:base() or asRev(br,fid))
  local tmp = self:tmp(rev)
  trace('creating snapshot from %s in %s', fsnap, tmp)
  fsnap:copyTo(tmp)

  local patch = fid<=id and pu._patch or pu._rpatch
  local inc = fid<=id and 1 or -1
  for i=fid+inc,id,inc and 1 or -1 do
    if i == 0 then goto cont end
    local ppath = b:patch(i); trace('patching %s with %s', tmp, ppath)
    patch(tmp, ppath)
  ::cont:: end

  local tsnap = b:snap(id); assert(not ix.exists(tsnap))
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
  local b = self:branch(br)
  if id ~= b:tip() then error(s[[
    ERROR: working id is not at tip. Solutions:
    * branch from this id.
    * stash -> [$pvc at tip] -> unstash -> commit.
    * prune: move or delete downstream changes.
  ]])end
  local rev2 = asRev(br, id+1)
  trace('start commit from %s to %s', rev, rev2)
  local snap2 = b:snap(id+1)
  assertf(not ix.exists(snap2), 'snapshot %q already exists', snap2)
  local base   = self:snapshot(rev)
  local bindex = base:index()
  local tmp    = self:tmp(rev2)

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
  local idiff = assert(pu.diff(
    id>0 and base.root..snap.PVCINDEX, id>0 and snap.PVCINDEX,
    ipath,                             snap.PVCINDEX))
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
  b:setTip(id+1)
  notify('commited %s in %s', rev2, pfinal)
end

function Repo:setAt(rev, force)
  dbg('setAt', rev, force)
  local w, s1, s2 = self.w, self:localsnap(), self:snapshot(rev)
  local i1, i2 = s1:index(), s2:index()
  local copy, error = {}, {}
  for _, p2 in ipairs(i2) do
    dbg('setAt path', p2.p)
    local p1 = i1[i1[p2.p]]
    dbg('* has p1', p1 and true or false)
    if not p1 then push(copy, p2); goto cont end
    local path1 = s1.root..p1.p
    if (p1:cleaned()==p2 and p1.mtime==ix.mtime(path1))
       or ix.pathEq(path1, s2.root..p2.p)
    then goto cont end -- already equal, skip
    dbg('* copying', p2.p)
    push(copy, p2); if not force then push(error, p2.p) end
    dbg('* copy', copy)
    ::cont::
  end
  dbg('out of loop', copy, error)
  if #error > 0 then
    errorf('paths are modified:\n%s', concat(error, '\n'))
  end
  dbg('setAt copy', copy)
  for _, p in ipairs(copy) do ix.forceCp(s2.root..p.p, self.w..p.p) end
  self:_setAt(rev)
  notify('now at %s', rev)
end

local FAILED_MERGE = [[
FAILED MERGE
    to: %s
  base: %s
change: %s
 ERROR: %s]]

--- Cherry pick revision onto current commit, modifying work tree.
--- Return the snapshot that was cherry-picked.
function Repo:cp(rev, paths) --> Snap, error
  if not paths or ds.isEmpty(paths) then paths = nil end
  local from = self:rev'at'
  local d = self:diff(from, 'local'); if d:hasDiff() then
    notify'has diff:'; d:format(ctx.fmtlog, false)
    notify'Cannot cherry pick with diff'
    return nil, 'has diff'
  end
  local conflicts = false
  local br,id = self:splitRev(rev)
  local fsnap = self:snapshot(asRev(br,id-1))
  local csnap = self:snapshot(rev)
  local tsnap = self:localsnap()
  local fdir, tdir = fsnap.root, tsnap.root
  fsnap:map2(tsnap, function(fpath, tpath)
    fpath, tpath = fpath and fpath.p, tpath and tpath.p
    if paths and not paths[fpath or tpath]
       or (fpath or tpath):sub(1,3) == 'PVC' then return end
    local from, to = fpath and (fdir..fpath), tpath and (tdir..tpath)
    local chg = csnap.root..(fpath or tpath)
    local ok, err = pu.merge(to, from, chg)
    if not ok then
      conflicts = true
      ctx.fmtlog:styled('error', sfmt(FAILED_MERGE,
        to and nice(to), from and nice(from), nice(chg), err), '\n')
    end
  end)
  if conflicts then
    notify'failed to merge, fix conflicts and re-run'
    return nil, 'conflicts'
  end
  return csnap
end

--- Squash the top num commits of branch into a single commit.
function Repo:squash(br, num, desc)
  local b = self:branch(br)
  local id = b:tip() - num + 1
  -- Make sure no children branch from squashed commits
  for chld, cid in ipairs(self:childGraph()[br]) do
    if type(chld) ~= 'string' then goto cont end
    if cid >= id then errorf('%s branches at %s:%s', chld, b.name, cid) end
  ::cont::end
  if not desc then
    desc = {}; for i=id,b:tip() do push(desc, b:desc(i)) end
  end
  -- FIXME: do the squash
end

return repo