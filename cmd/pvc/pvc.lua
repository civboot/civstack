#!/usr/bin/env -S lua
local shim  = require'shim'

--- Usage: [$pvc <subcmd> --help][{br}]
--- This is the [$pvc] command-line tool which can also be called directly from
--- Lua.
local pvc = shim.subcmds'pvc' {}

local mty   = require'metaty'
local ds    = require'ds'
local pth   = require'ds.path'
local ix    = require'civix'
local lines = require'lines'
local kev   = require'lines.kev'
local T = require'civtest'

local pu = require'pvc.unix'

local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push, concat = table.insert, table.concat
local sort = table.sort
local info = require'ds.log'.info
local trace = require'ds.log'.trace
local s = ds.simplestr
local construct = mty.construct
local toDir, pconcat = pth.toDir, pth.concat
local nice = pth.nice
local pk = ds.popk

local assertf = require'fmt'.assertf

local Base = shim.cmd'_base' {
  '_dir [string]: directory to execute in',
}

-- Constructor which pops dir and sets to _dir.
local function new(T, args)
  args = shim.parseStr(args)
  local dir = pk(args, 'dir')
  local cmd = shim.constructNew(T, args)
  cmd._dir = dir and toDir(dir) or pth.cwd()
  return cmd
end
Base.new = new
pvc.new  = new

--- Usage: [$pvc init dir --branch=main][{br}]
--- Initialize the current directory as a pvc directory.
--- This will create [$.pvc/] and [$.pvcpaths]
pvc.init = mty.extend(Base, 'init', {
  'branch [string]: the initial branch name',
    branch = 'main',
})

--- Usage: [$pvc diff branch1=at branch2=local][{br}]
--- Show the difference between two branches.  The default is [$at] (the
--- current commit) vs [$local] (the local working directory).[{br}]
---
--- This command accepts either [$branch#id] names or [$paths/to/dir/], where
--- that dir/ has a [$.pvcpaths] file.
pvc.diff = mty.extend(Base, 'diff', {
  'paths [bool]: show only changed paths',
})

--- Usage: [$pvc commit -- my message][{br}]
--- Commit local changes to the current branch, creating
--- a new id.
---
--- If no message is given this uses the COMMIT file
--- for the message, if it exists.
pvc.commit = mty.extend(Base, 'commit', {})

--- Usage: [$pvc at branchId --hard][{br}]
--- If [$branchId] is not given, just returns current branch#id.
---
--- Otherwise, sets the active [$branch#id], causing the local
--- directory to be updated to be that content.
--- This will , this will fail (unless [$force=true]) if it would
--- cause any local changes to be overwritten.
---
--- ["[$at branch] is called a "checkout" in other version
---   control systems.]
pvc.at = mty.extend(Base, 'at', {
 [[force [bool]: overwrite local changes.
   If given without [$branch], resets to current commit
 ]],
})

--- Usage: [$$pvc tip [branch=current]]$[{br}]
--- Get the tip id of branch.
pvc.tip = mty.extend(Base, 'tip', {})

--- Usage: [$$pvc branch name [from=current]]$[{br}]
--- Start new branch [$name] branching off of [$from].
---
--- If [$from] is a [$path/to/dir] then it will graft
--- those changes into the local repo as the named [$branch].
--- (often used by maintainers to accept patches).
pvc.branch = mty.extend(Base, 'branch', {})

--- Usage: [$$pvc show [branch#id] --before=10]$[{br}]
--- Show the commits before/after [$branch#id].[{br}]
---
--- If [$branch#id] is not given, print all branches.
pvc.show = mty.extend(Base, 'show', {
  'before [int]: number of records before id to show',
    num=10,
  'after [int]: number of records after id to show',
    num=5,
 [[paths [bool]: show only paths.]],
})

--- Usage: [$$pvc desc branch#id=current [$to/new.cxt]]$[{br}]
--- Get or set the description for a single branch id.[{br}]
---
--- The new description can be passed via [$to/new.cxt] or
--- after [$--] (like commit).
pvc.desc = mty.extend(Base, 'desc', {})

--- Usage: [$$pvc squash [name#id]]$[{br}]
--- Combine changes and descriptions from [$branch id -> endId] (inclusive)
--- into a single commit. You can then edit the description using
--- [$pvc desc branch#id].[{br}]
---
--- This enables making lots of small commits and then
--- "squashing" them into a single commit once they are
--- in a good state.
pvc.squash = mty.extend(Base, 'squash', {
  'branch [string]: the branch to squash',
    branch='current',
})

--- Usage: [$$rebase [branch=current] --id=10]$[{br}]
--- Change the base of [$branch] to [$id].[{br}]
---
--- Rebase is a fundamental operation. It allows you to make or accept changes
--- on your "main" branch while you work on development branches which are
--- behind the main. See [<#basic>] for more details.
pvc.rebase = mty.extend(Base, 'rebase', {
  'id [int]: the id of base to change to',
})

--- Usage: [$$grow --branch=current [from]]$[{br}]
--- Copy changes in [$from] onto [$branch].
--- ["In other version control systems this is called a
---   "fast forward merge"]
pvc.grow = mty.extend(Base, 'grow', {
  'branch [string]: the branch to mutate',
})

--- Usage: [$prune branch#id][+
--- * if [$#id]: delete ids [$id -> tip] (inclusive).
--- * else: delete branch
--- ]
pvc.prune = mty.extend(Base, 'prune', {})

--- Usage: [$export branch to/][{br}]
--- Copy all patch files in the branch to [$to/].
--- ["The resulting directory is commonly sent to
---   [$tar -zcvf branch.tar.gz path/] and then [$branch.tar.gz] sent to a
---   maintainer to be merged.
--- ]
pvc.export = mty.extend(Base, 'export', {})

--- Usage: [$$snap [branch#id=current]]$[{br}]
--- Get the snapshot directory of branch#id.
---
--- The snapshot contains a copy of files at that commit.
pvc.snap = mty.extend(Base, 'snap', {})

pvc.DOT = '.pvc/'
pvc.PVC_DONE = 'PVC_DONE'
pvc.PVCPATHS = '.pvcpaths' -- file
pvc.PVCIGNORE = '.pvcignore' -- file
pvc.INIT_PVCPATHS = '.pvcpaths\n.pvcignore\n'
pvc.INIT_PVCIGNORE = [[
%.git/
%.civ/
%.out/
]]
pvc.INIT_PATCH = [[
# initial patch
--- /dev/null
+++ .pvcpaths
.pvcpaths
]]

local toint = math.tointeger

--- this exists for tests to override
function pvc._backupId() return tostring(ix.epoch():asSeconds()) end

--- reserved branch names
pvc._RESERVED_NAMES = { ['local']=1, at=1, tip=1, }

-----------------------------------
-- Utilities

--- get a set of the lines in a file
local function loadLineSet(path) --> set
  local s = {}; for l in io.lines(path) do s[l] = true end; return s
end

local function loadPaths(P) --> list
  local paths = ds.BiMap(lines.load(P..pvc.PVCPATHS))
  if not paths[pvc.PVCPATHS] then push(paths, pvc.PVCPATHS) end
  return paths
end

local function loadIgnore(P) --> list
  local ignore = {'%./%.pvc/'}
  local path = P..'.pvcignore'
  if not ix.exists(path) then return ignore end
  for line in io.lines(path) do
    if line == '' or line:sub(1,1) == '#' then --ignore
    else push(ignore, line)
    end
  end
  return ignore
end

--- copy all paths in [$from/.pvcpaths] -> [$to/]
local function cpPaths(from, to)
  trace('cpPaths %s -> %s', from, to)
  for path in io.lines(from..pvc.PVCPATHS) do
    ix.forceCp(from..path, to..path)
  end
end

local function readInt(path) return toint(pth.read(path)) end

--- call [$fn(path1, path2)] for all files in [$dir/.pvcpaths]
--- the value will be nil if it is missing in either path.
---
--- Note: the passed in paths are still relative.
local function mapPvcPaths(dir1, dir2, fn)
  local paths1, paths2 = loadPaths(dir1), loadPaths(dir2)
  for _, p1 in ipairs(paths1) do fn(p1, paths2[p1] and p1 or nil) end
  for _, p2 in ipairs(paths2) do
    if not paths1[p2] then fn(nil, p2) end
  end
end

local function untracked(P) --> list[string]
  trace('untracked %s', P)
  local out, paths = {}, ds.Set(loadPaths(P))
  local ignore = loadIgnore(P)
  local w = ix.Walk{P}
  for path, fty in w do local path=path
    path = path:sub(#P+1)
    if path == '' then goto cont end
    local mpath = './'..path -- path for matching
    trace('ut path %q', mpath)
    if paths[path] then goto cont end
    if fty == 'dir' then
      for _, pat in ipairs(ignore) do
        if pat:sub(-1,-1) == '/' and mpath:find(pat) then
          w:skip(); goto cont
        end
      end
    else
      for _, pat in ipairs(ignore) do
        if pat:sub(-1,-1) ~= '/' and mpath:find(pat) then
          goto cont
        end
      end
      push(out, path)
    end
    ::cont::
  end
  table.sort(out)
  return out
end


-----------------------------------
-- Patch Logic

local postCmd = {
  rename = function(a, b) info('rename %q %q', a, b); civix.mv(a, b) end,
  swap   = function(a, b) info('swap %q %q', a, b); civix.swap(a, b) end,
}

--- Given a patch string perform post-patch requirements in dir.
---
--- These must be given near the top of the patch file, before the first
--- [$---].  Supported commands (arguments are actually tab separated):
--- [$$
--- ! rename before  after
--- ! swap   first   second
--- ]$
---
--- If reverse is given it does the opposite; also this should be called BEFORE
--- calling [$patch(reverse=true)]
function pvc._patchPost(dir, patch, reverse)
  for line in io.lines(patch) do
    if line:sub(1,3) == '---' then break end -- stop after first diff
    if line:sub(1,1) == '!' then
      local cmd, a, b = table.unpack(ds.splitList(line:match'!%s*(.*)'))
      if reverse then a, b = b, a end
      (postCmd[cmd] or error('unknown cmd: '..cmd))(pconcat{dir, a}, pconcat{dir, b})
    end
  end
end

--- forward patch, applying diff to dir
function pvc._patch(dir, diff)
  pu._patch(dir, diff)
  pvc._patchPost(dir, diff)
end

--- reverse patch, applying diff to dir
function pvc._rpatch(dir, diff)
  pvc._patchPost(dir, diff, true)
  pu._rpatch(dir, diff)
end

--- calculate necessary directory depth.
--- Example: 01/23/12345.p has dirDepth=4
function pvc._calcPatchDepth(id)
  local len = #tostring(id); if len <= 2 then return 0 end
  return len - (2 - (len % 2))
end

-----------------------------------
-- Diff

--- [$Diff:of(dir1, dir2)] returns what changed between two pvc dirs.
pvc.Diff = mty'Diff' {
  'dir1 [string]', 'dir2 [string]',
  'equal   [list]',
  'changed [list]',
  'deleted [list]',
  'created [list]',
}

pvc.Diff.of = function(T, d1, d2)
  local peq = ix.pathEq
  local t = (type(d1) == 'table') and d1 or {dir1=d1, dir2=d2}
  t = T(t)
  local equal, changed, deleted, created = {}, {}, {}, {}
  mapPvcPaths(d1, d2, function(p1, p2)
    if p1 and p2 then
      if peq(d1..p1, d2..p2) then push(equal,   p1)
      else                        push(changed, p1) end
    elseif p1 then                push(deleted, p1)
    else                          push(created, p2)
    end
  end)
  sort(equal); sort(changed); sort(deleted); sort(created)
  t.equal, t.changed, t.deleted, t.created =
    equal,   changed,   deleted,   created
  return t
end

function pvc.Diff:hasDiff()
  return (#self.changed > 0) or (#self.deleted > 0) or (#self.created > 0)
end

function pvc.Diff:format(fmt, full)
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

function pvc.Diff:patch() --> patchText
  local d1, d2, patch = self.dir1, self.dir2, {}
  for _, path in ipairs(self.changed) do
    push(patch, pu.diff(d1..path, path, d2..path, path))
  end
  for _, path in ipairs(self.created) do
    push(patch, pu.diff(nil, nil, d2..path, path))
  end
  for _, path in ipairs(self.deleted) do
    push(patch, pu.diff(d1..path, path))
  end
  return concat(patch, '\n')
end

--------------------------------------------
-- Branch

--- return the branch path in project regardless of whether it exists
function pvc.branchDir(P, branch, dot)
  assert(branch, 'branch is nil')
  assert(not pvc._RESERVED_NAMES[branch], 'branch name is reserved')
  return pth.concat{P, dot or '.pvc', branch, '/'}
end

function pvc._getbase(bdir, br) --> br, id
  local bpath = bdir..'base'
  if ix.exists(bpath) then return pvc._parseBranch(pth.read(bpath))
  else return br, 0 end
end
function pvc._rawtip(bdir, id) --> id
  if id then pth.write(toDir(bdir)..'tip', tostring(id))
  else return readInt(toDir(bdir)..'tip') end
end
function pvc.depth(bdir) return readInt(toDir(bdir)..'commit/depth') end

function pvc._patchPath(bdir, id, last, depth) --> string?
  depth = depth or pvc.depth(bdir)
  if pvc._calcPatchDepth(id) > depth then return end
  local dirstr = tostring(id):sub(1,-3)
  dirstr = srep('0', depth - #dirstr)..dirstr -- zero padded
  local path = {bdir, 'commit'}; for i=1,#dirstr,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, tostring(id)..(last or '.p'))
  return pconcat(path)
end

--- Get the snap/ path regardless of whether it exists
function pvc.snapDir(bdir, id) --> string?
  return pvc._patchPath(bdir, id, '.snap/')
end

local function initSnap0(snap)
  ix.forceWrite(snap..pvc.PVCPATHS, '.pvcpaths\n')
  ix.forceWrite(snap..'PVC_DONE', '\n')
end

local function initBranch(bdir, id)
  assert(id >= 0)
  assertf(not ix.exists(bdir), '%s already exists', bdir)
  local depth = pvc._calcPatchDepth(id + 1000)
  trace('initbranch %s', bdir)
  ix.mkTree(bdir, {
    tip=tostring(id), commit = {depth=tostring(depth)},
  }, true)
  if id ~= 0 then return bdir end
  local ppath = pvc._patchPath(bdir, id, '', depth)
  initSnap0(ppath..'.snap/')
end

--- Snapshot the branch#id by applying patches.
--- Return the snapshot directory
function pvc.snapshot(P, br,id) --> .../id.snap/
  trace('snapshot %s#%s', br,id)
  -- f=from, t=to
  local bdir = pvc.branchDir(P, br)
  local snap = pvc.snapDir(bdir, id)
  if ix.exists(snap) then return snap, id end
  if id == 0 then return initSnap0(snap) end
  local bbr,bid = pvc._getbase(bdir, br)
  if id == bid then return pvc.snapshot(P, bbr,bid) end
  trace('findSnap %s id=%s with base %s#%s', bdir, id, bbr,bid)

  local tip      = pvc._rawtip(bdir)
  local fsnap, fid -- find the snap/id to patch from
  local idl, idr = id-1, id+1
  while (bid <= idl) or (idr <= tip) do
    snap = pvc._patchPath(bdir, idl, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = pvc.snapDir(bdir,idl), idl; break
    end
    if bid == idl then
      fsnap, fid = pvc.snapshot(P, bbr,bid), idl; break
    end
    snap = pvc._patchPath(bdir, idr, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = pvc.snapDir(bdir,idr), idr; break
    end
    idl, idr = idl-1, idr+1
  end
  if not fsnap then error(bdir..' does not have snapshot '..id) end
  local tsnap = pvc.snapDir(bdir, id)
  trace('creating snapshot %s from %s', tsnap, fsnap)
  if ix.exists(tsnap) then ix.rmRecursive(tsnap) end
  ix.mkDir(tsnap)
  cpPaths(fsnap, tsnap)
  local patch = (fid <= id) and pu._patch or pu._rpatch
  local inc   = (fid <= id) and 1       or -1
  fid = fid + inc
  while true do
    local ppath = pvc._patchPath(bdir, fid)
    trace('patching %s with %s', tsnap, ppath)
    patch(tsnap, ppath)
    if fid == id then break end
    fid = fid + inc
  end
  pth.write(tsnap..pvc.PVC_DONE, '')
  info('created snapshot %s', tsnap)
  return tsnap
end

--- increase the depth of branch by 2, adding a [$00/] directory.
function pvc._deepen(bdir)
  local depth, pp, zz = pvc.depth(bdir), bdir..'commit/', bdir..'00/'
  ix.mv(pp, zz); ix.mkDir(pp) ix.mv(zz, pp)
  pth.write(pp..'depth', tostring(depth + 2))
end

-----------------
-- Project Methods

function pvc._parseBranch(str, bdefault, idefault) --> branch, id
  local i = str:find'#'
  if i              then return str:sub(1,i-1), toint(str:sub(i+1))
  elseif toint(str) then return bdefault,       toint(str)
  else                   return str,            idefault end
end

--- get or hard set the current branch/id
function pvc._rawat(P, branch, id)
  local apath = pth.concat{P, '.pvc/at'}
  if branch then pth.write(apath, sfmt('%s#%s', branch, id))
  else    return pvc._parseBranch(pth.read(apath)) end
end

--- get or set where the working id is at.
function pvc.atId(P, nbr,nid) --!> branch?, id?
  -- c=current, n=next
  local cbr, cid = pvc._rawat(P); if not nbr then return cbr, cid end
  local npath = pvc.branchDir(P, nbr)

  nid = nid or pvc._rawtip(npath)
  trace('at %s#%i -> %s#%i', cbr, cid, nbr, nid)
  local csnap  = pvc.snapshot(P, cbr,cid)
  local nsnap  = pvc.snapshot(P, nbr,nid)
  trace('at snaps %s -> %s', csnap, nsnap)

  local npaths = loadPaths(nsnap)

  local ok, cpPaths, rmPaths = true, {}, {}
  for _, path in ipairs(npaths) do
    local lpath, npath = P..path, nsnap..path
    if ix.pathEq(lpath, npath) then goto cont end -- local==next
    if ix.pathEq(lpath, csnap..path) then -- local didn't change
      if not ix.pathEq(csnap..path, npath) then -- next did change
        push(cpPaths, path)
      end
      goto cont
    end
    -- else local path changed
    if ix.pathEq(csnap..path, npath) then
      io.fmt:styled('meta',  sfmt('keeping changed %s', path), '\n')
    else
      io.fmt:styled('error', sfmt('path %s changed',    path), '\n')
      ok = false
    end
    ::cont::
  end
  -- look at paths in current but not next
  for path in io.lines(csnap..pvc.PVCPATHS) do
    if npaths[path]              then goto cont end
    if not ix.exists(P..path) then goto cont end -- already deleted
    if ix.pathEq(P..path, csnap..path) then push(rmPaths, path)
    else
      f:styled('error',
        sfmt('path %s changed but would be removed', path), '\n')
      ok = false
    end
    ::cont::
  end
  if not ok then error(sfmt(s[[

    ERROR: local changes (%s#%s) would be trampled by checkout %s#%s
    Solutions:
    * commit the current changes
    * revert the current changes
  ]], cbr,cid, nbr,nid)) end
  for _, path in ipairs(cpPaths) do
    trace('checkout cp: %s', path)
    ix.forceCp(nsnap..path, P..path)
  end
  for _, path in ipairs(rmPaths) do
    trace('checkout rm: %s', path)
    ix.rmRecursive(P..path)
  end
  pvc._rawat(P, nbr,nid)
  io.fmt:styled('notify', sfmt('pvc: at %s#%s', nbr,nid), '\n')
end

--- update paths file (path) with the added and removed items
function pvc._pathsUpdate(P, add, rm)
  local pfile = pth.concat{P, pvc.PVCPATHS}
  local paths = assert(lines.load(pfile), pfile)
  if add then ds.extend(paths, add) end
  if rm and rm[1] then rm = ds.Set(rm) end
  local rmFn = rm and function(v1, v2) return rm[v2] or (v1 == v2) end
            or ds.eq
  ds.sortUnique(paths, nil, rmFn)
  push(paths, '')
  lines.dump(paths, pfile)
end

--- resolve a branch name. It can be one of: [+
--- * A directory with [$/] in it.
--- * [$branch] or [$branch#id]
--- * Special: at
--- ]
function pvc.resolve(P, branch) --> br, id, bdir
  local br, id = pvc._parseBranch(branch)
  if not br then error('unknown branch: '..branch) end
  if br == 'local' then error('local not valid here') end
  if br == 'at'  then br, id = pvc._rawat(P) end
  return br, id, pvc.branchDir(P, br)
end

--- resolve and take snapshot, permits local
function pvc.resolveSnap(P, branch) --> snap/, br, id, bdir
  if branch:find'/' then return branch end -- directory
  if branch == 'local' then return P end
  local br, id, bdir = pvc.resolve(P, branch)
  return pvc.snapshot(P, br, id or pvc._rawtip(bdir)), br, id, bdir
end

--- resolve two branches into their branch directories. Defaults:[+
--- * br1 = 'at'
--- * br2 = 'local'
--- ]
function pvc.resolve2(P, br1, br2) --> branch1/ branch2/
  return  pvc.resolveSnap(P, br1 or 'at'),
          pvc.resolveSnap(P, br2 or 'local')
end

function pvc._diff(P, branch1, branch2) --> Diff
  return pvc.Diff:of(pvc.resolve2(P, branch1, branch2))
end

--- Create a patch file from two branch arguments (see resolve2).
function pvc._patch(P, br1, br2) --> string, s1, s2
  return pvc.Diff:of(pvc.resolve2(P, br1, br2)):patch()
end


local function isPatchLike(line)
  return line:sub(1,3) == '---'
      or line:sub(1,3) == '+++'
      or line:sub(1,2) == '!!'
end
function pvc._commit(P, desc) --> snap/, id
  assert(desc, 'commit must provide description')
  for _, line in ds.split(desc, '\n') do
    assert(not isPatchLike(line),
      "commit message cannot have any of the following"
    .." at the start of a line: +++, ---, !!")
  end

  local br, id = pvc._rawat(P)
  local bp, cid = pvc.branchDir(P, br), id+1
  trace('start commit %s/%s', br, cid)
  if id ~= pvc._rawtip(bp) then error(s[[
    ERROR: working id is not at tip. Solutions:
    * stash -> at tip -> unstash -> commit
    * prune: move or delete downstream changes.
  ]])end
  pvc._pathsUpdate(P) -- sort unique

  -- b=base c=change
  local bsnap = pvc.snapshot(P, br,id)
  local patchf = pvc._patchPath(bp, cid)
  local diff = pvc.Diff:of(bsnap, P)
  if not diff:hasDiff() then
    error('invalid commit: no differences detected')
  end
  if pvc._calcPatchDepth(cid) > pvc.depth(bp) then pvc._deepen(bp) end
  ix.forceWrite(patchf,
    sconcat('\n', desc, diff:patch()))
  local csnap = pvc.snapshot(P, br,cid)
  for path in io.lines(P..pvc.PVCPATHS) do
    T.pathEq(P..path, csnap..path)
  end
  pvc._rawtip(bp, cid); pvc._rawat(P, br, cid)
  io.fmt:styled('notify', sfmt('commited %s#%s to %s', br, cid, patchf), '\n')
  return csnap, cid
end

--- get the conventional brName, id for a branch,id pair
function pvc.nameId(P, branch,id) --> br,id
  local br,bid; if not branch then br,bid = pvc.atId(P)
  else                             br,bid = pvc._parseBranch(branch) end
  return br, id or bid or pvc._rawtip(pvc.branchDir(P, br))
end

function pvc._branch(P, name, fbr,fid) --> bdir, id
  local fpath = pvc.branchDir(P, fbr)
  if not ix.exists(fpath) then error(fpath..' does not exist') end
  fid = fid or pvc._rawtip(fpath)
  local npath = pvc.branchDir(P, name)
  initBranch(npath, fid)
  pth.write(npath..'base', sfmt('%s#%s', fbr,fid))
  return npath, fid
end

local NOT_BRANCH = { backup = 1, at = 1}
local function branchesRm(a, b) return NOT_BRANCH[a] end

--- get all branches
function pvc.branches(P) --> list
  local entries = {}
  local d = P..'.pvc/'
  for e in ix.dir(d) do
    if not NOT_BRANCH[e] and ix.pathtype(d..e) == 'dir' then
      push(entries, pth.toNonDir(e))
    end
  end
  sort(entries)
  return entries
end

function pvc._checkBranch(P, name, checks, dir)
  dir = dir or P..name
  local bbr,bid = pvc._getbase(dir, nil)
  local tip     = pvc._rawtip(dir)
  if tip <= bid then error(sfmt('tip %i <= baseid %i'..tip, bid)) end
  -- TODO: check that patch files exist, etc.

  if checks.base and not bbr then error(from..' does not have base') end
  if bbr then
    local bt = pvc._rawtip(pvc.branchDir(P, bbr))
    if bid > bt then error(sfmt(
      '%s base.id %s > %s tip of %i', from, bid, bbr, bt
    ))end
    -- TODO(sig): check signature
  end
  if checks.children then -- check that it has no children

  end
end

function pvc.__graft(P, name, from)
  local ndir = P..name
  if ix.exists(ndir) then error(ndir..' already exists') end
  pvc._checkBranch(P, name, {base=1}, from)
  ix.cpRecursive(from, ndir)
end

local FAILED_MERGE = [[
FAILED MERGE
    to: %s
  base: %s
change: %s
 ERROR: %s]]

function pvc._merge(tdir, bdir, cdir) --!>
  trace('pvc.merge to=%s base=%s change=%s', tdir, bdir, cdir)
  local paths, conflicts = {}, false
  mapPvcPaths(bdir, cdir, function(bpath, cpath)
    local to     = tdir..(cpath or bpath)
    local base   = bpath and (bdir..bpath) or nil
    local change = cpath and (cdir..cpath) or nil
    local ok, err = pu.merge(to, base, change)
    if not ok then
      io.fmt:styled('error', sfmt(
        FAILED_MERGE,
        nice(to), nice(base), nice(change),
        err), '\n')
      conflicts = true
    end
  end)
  assert(not conflicts, 'failed to merge, fix conflicts and then re-run')
end

--- return a backup directory (uses the timestamp)
function pvc.backupDir(P, name) --> string
  for _=1,10 do
    local b = sfmt('%s.pvc/backup/%s-%s/', P, name, pvc._backupId())
    if ix.exists(b) then ix.sleep(0.01) else return b end
  end
  error('could not find empty backup')
end

--- rebase the branch (current branch) to make it's baseid=id
function pvc._rebase(P, branch, id) --> backup/dir/
  local cbr = branch

  --- process: repeatedly use merge on the (new) branch__rebase branch.
  --- the final result will be in to's last snapshot id
  --- Nomenclature: b=base c=current t=to
  local cpath = pvc.branchDir(P, cbr)
  local bbr, bid = pvc._getbase(cpath, cbr)
  pvc.atId(P, bbr,bid) -- checkout base to ensure cleaner checkout at end

  if bbr == cbr then error('the base of '..cbr..' is itself') end
  if id == bid then
    io.user:styled('notify', 'base is already '..id, '\n')
    return
  end
  local bdir = pvc.branchDir(P, bbr)
  local btip = pvc._rawtip(bdir)
  if id > btip then error(id..' is > tip of '..btip) end

  local cdir, cid = pvc.branchDir(P, cbr), bid + 1
  local ctip      = pvc._rawtip(cdir)
  local tbr       = cbr..'__rebase'
  local tdir      = pvc.branchDir(P, tbr)
  local ttip      = id + pvc._rawtip(cdir) - bid

  local op = sfmt('rebase %s %s', cbr, bid)
  local tsnap; if ix.exists(tdir) then
    -- rebase 'to' branch already exists, continue existing rebase.
    assert(ix.exists(tsnap))
    T.pathEq(tdir..'op', op)
    T.eq({bbr,bid}, pvc._getbase(tdir))
    cid   = toint(pth.read(tdir..'rebase'))
    tsnap = pvc.snapDir(tdir, ttip)
  else -- create new 'to' branch for rebase branch
    pvc._branch(P, tbr, bbr,id)
    pth.write(tdir..'op', op)
    tsnap = pvc.snapDir(tdir, ttip); ix.mkDirs(tsnap)
    cpPaths(pvc.snapshot(P, bbr,id), tsnap)
  end
  local tid = id + 1
  local tprev = pvc.snapshot(P, bbr,id) -- hard-code first prev

  while cid <= ctip do
    assert(tid <= ttip)
    local bsnap = pvc.snapshot(P, cbr,bid)
    pth.write(tdir..'rebase', tostring(cid))
    local desc = pvc._desc(pvc._patchPath(cdir, cid))
    pvc._merge(tsnap, bsnap, pvc.snapshot(P, cbr,cid))
    tprev = tprev or pvc.snapshot(P, tbr,tid-1)
    local tpatch = pvc._patchPath(tdir,tid)
    trace('writing patch %s', tpatch)
    ix.forceWrite(tpatch,
      concat(desc, '\n')..'\n'..pvc.Diff:of(tprev, tsnap):patch())
    tprev = nil
    bid, cid, tid = bid + 1, cid + 1, tid + 1
  end

  local backup = pvc.backupDir(P, cbr); ix.mkDirs(backup)
  ix.mv(cdir, backup)
  io.fmt:styled('notify',
    sfmt('pvc: rebase %s to %s#%s done. Backup at %s', cbr, bbr, id, backup),
    '\n')
  pvc._rawtip(tdir, ttip)
  ix.rm(tdir..'op'); ix.rm(tdir..'rebase')
  ix.mv(tdir, cdir)
  pvc.atId(P, cbr,ttip)
  return backup
end

--- Grow [$to] by copying patches [$from]
function pvc._grow(P, to, from) --!>
  local fbr, fdir = assert(from, 'must set from'), pvc.branchDir(P, from)
  local ftip = pvc._rawtip(fdir)
  local bbr, bid = pvc._getbase(fdir)
  local tbr = to or pvc._rawat(P)
  if bbr ~= tbr then error(sfmt(
    'the base of %s is %s, not %s', from, bbr, tbr
  ))end
  local tdir = pvc.branchDir(P, tbr)
  local ttip = pvc._rawtip(tdir)
  if bid ~= ttip then error(sfmt(
    'rebase required (%s tip=%s, %s base id=%s)', tbr, ttip, bbr, bid
  ))end
  if ftip == bid then error(sfmt(
    "rebase not required: %s base is equal to it's tip (%s)", fbr, bid
  ))end
  pvc.atId(P, tbr,ttip)
  if pvc._diff(P):hasDiff() then error'local changes detected' end
  -- TODO(sig): check signature
  for id=bid+1, pvc._rawtip(fdir) do
    local tpath = pvc._patchPath(tdir, id)
    assert(not ix.exists(tpath))
    local fpath = pvc._patchPath(fdir, id)
    info('copying: %s -> %s', fpath, tpath)
    ix.forceCp(fpath, tpath)
  end
  pvc._rawtip(tdir, ftip)
  local back = pvc.backupDir(P, fbr)
  io.fmt:styled('notify',
    sfmt('deleting %s (mv %s -> %s)', fbr, fdir, back), '\n')
  ix.mkDirs(pth.last(back)); ix.mv(fdir, back)
  io.fmt:styled('notify', sfmt('grew %s tip to %s', tbr, ftip), '\n')
  pvc.atId(P, tbr,ftip)
end

--- return the description of ppath
function pvc._desc(ppath, num) --> {string}
  local desc = {}
  for line in io.lines(ppath) do
    if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
      then break end
    push(desc, line); if num and #desc >= num then break end
  end
  return desc
end

--- squash num commits together before br#id.
function pvc._squash(P, br, bot,top)
  assert(br and bot, 'must set br + bot')
  local bdir = pvc.branchDir(P, br)
  local tip, bbr, bid = pvc._rawtip(bdir), pvc._getbase(P, br)
  top = top or tip
  trace('squash %s [%s %s]', br, bot,top)
  assert(top > 0)
  if top - bot <= 0 then
    io.fmt:styled('error', sfmt('squashing ids [%s - %s] is a noop', bot, top), '\n')
    return
  end
  if bot <= bid then error(sfmt('bottom %i <= base id %s', top, bid)) end
  if top >  tip then error(sfmt('top %i > tip %i', top, tip)) end
  pvc.atId(P, br,top)
  local back = pvc.backupDir(P, br..'-squash'); ix.mkDirs(back)
  local desc = {}
  local last = pvc._patchPath(bdir, tip)
  if not ix.exists(last) then error(last..' does not exist') end

  local patch = pvc.Diff:of(pvc.snapshot(P, br,bot-1), pvc.snapshot(P, br,top))
    :patch()
  -- move [bot,top] commits to backup/ and remove their .snap/ directories.
  for i=bot,top do
    local path = pvc._patchPath(bdir, i)
    ds.extend(desc, pvc._desc(path))
    local bpatch = back..i..'.p'
    ix.mv(path, bpatch)
    io.fmt:styled('notify', sfmt('mv %s %s', path, bpatch), '\n')
    ix.rmRecursive(pvc.snapDir(bdir, i))
  end
  -- write the squashed patch file
  local f = io.open(pvc._patchPath(bdir, bot), 'w')
  for _, line in ipairs(desc) do f:write(line, '\n') end
  f:write(patch); f:close()

  ix.rmRecursive(pvc.snapDir(bdir, bot)) -- TODO: remove this I think

  -- move the patch files above top down to be above squashed bot
  local bi = bot
  for i=top+1, tip do; bi = bi + 1
    ix.rmRecursive(pvc.snapDir(bdir, i))
    local botPat = pvc._patchPath(bdir, bi)
    local topPat = pvc._patchPath(bdir, i)
    io.fmt:styled('notify', sfmt('mv %s %s', topPat, botPat), '\n')
    ix.mv(topPat, botPat)
  end

  pvc._rawat(P, br,bot); pvc._rawtip(bdir,bi)
  io.fmt:styled('notify',
    sfmt('squashed [%s - %s] into %s. New tip=%i', bot, top, bot, bi), '\n')
end

local function popdir(args)
  return pth.toDir(pk(args, 'dir') or pth.cwd())
end

function pvc.init:__call()
  local P = self._dir
  local dot = P..'.pvc/';
  if ix.exists(dot) then error(dot..' already exists') end
  ix.mkTree(dot, {backup = {}}, true)
  initBranch(pvc.branchDir(P, self.branch), 0)
  pth.write(P..pvc.PVCPATHS, pvc.INIT_PVCPATHS)
  pth.write(P..pvc.PVCIGNORE, pvc.INIT_PVCIGNORE)
  pvc._rawat(P, self.branch, 0)
  io.fmt:styled('notice', 'initialized pvc repo '..dot, '\n')
end

function pvc.diff:__call()
  trace('diff%q', self)
  local P = self._dir
  local d = pvc._diff(P, self[1], self[2])
  d:format(io.fmt, not self.paths)
  if self.paths then
    for _, path in ipairs(untracked(P)) do
      io.user:styled('notify', path, '\n')
    end
  end
  io.fmt:write'\n'
  return d
end

function pvc.commit:__call()
  local P = self._dir
  local desc = shim.popRaw(self)
  if desc then desc = concat(desc, ' ')
  else         desc = pth.read(P..'COMMIT') end
  return pvc._commit(P, desc)
end

function pvc.at:__call()
  local D, branch = self._dir, self[1]
  if branch then return pvc.atId(D, pvc._parseBranch(branch)) end
  branch = sfmt('%s#%s', pvc._rawat(D))
  print(branch)
  return branch
end

function pvc.tip:__call() --> 'branch#tip'
  local P = self._dir
  local br = self[1] or pvc._rawat(P)
  local bdir = pvc.branchDir(P, br)
  local tip = pvc._rawtip(bdir)
  local out = sfmt('%s#%s', br, tip)
  print(out)
  return out
end

function pvc.branch:__call()
  local D = self._dir
  local name = assert(self[1], 'must provide branch name')
  assert(not name:find'/', "branch name must not include '/'")

  local fbr,fid = self[2]
  if fbr and fbr:find'/' then return pvc.__graft(D, name, fbr) end
  if fbr then fbr, fid = pvc._parseBranch(fbr)
  else        fbr, fid = pvc._rawat(D) end
  local bpath, id = pvc._branch(D, name, fbr,fid)
  pvc.atId(D, name)
end

-- TODO: need tests
function pvc.show:__call()
  assert(self._dir)
  local D = self._dir
  local full = not self.paths
  if not self[1] then -- just show all branches
    local branches = pvc.branches(D)
    for _, br in ipairs(branches) do
      if full then
        local bdir = pvc.branchDir(D, br)
        local tip, base,bid = pvc._rawtip(bdir), pvc._getbase(bdir, nil)
        io.user:styled('notify', sfmt('%s\ttip=%s%s',
          br, tip, base and sfmt('\tbase=%s#%s', base,bid) or ''), '\n')
      else io.user:styled('notify', br, '\n') end
    end
    return branches
  end
  local br, id = pvc._parseBranch(self[1])
  if not br or br == 'at' then br, id = pvc._rawat(D) end

  local num, dir = toint(self.num or 10), pvc.branchDir(D, br)
  if not id then id = pvc._rawtip(dir) end
  local bbr, bid = pvc._getbase(dir)
  for i=id,id-num+1,-1 do
    if i <= 0 then break end
    if i == bid then
      br, dir = bbr, pvc.branchDir(D, bbr)
      bbr, bid = pvc._getbase(dir)
    end
    local ppath = pvc._patchPath(dir, i)
    local desc = pvc._desc(ppath, not full and 1 or nil)
    io.user:styled('notify', sfmt('%s#%s:', br,i), '')
    io.user:level(1)
    io.user:write(full and '\n' or ' ', concat(desc, '\n'))
    io.user:level(-1)
    io.user:write'\n'
  end
end

-- TODO: need tests
function pvc.desc:__call()
  local P = self._dir
  local br, id, bdir = pvc.resolve(P,
    self[1] == '--' and 'at' or self[1] or 'at')
  local desc = shim.popRaw(self)
  if desc        then desc = concat(desc, ' ')
  elseif self[2] then desc = pth.read(self[2]) end
  local oldp = pvc._patchPath(bdir, id)
  local olddesc = concat(pvc._desc(oldp), '\n')
  if not desc then return print(olddesc) end
  -- Write new description
  local newp = sconcat('', bdir, tostring(id))
  local n = assert(io.open(newp, 'w'))
  n:write(desc, '\n')
  local o = assert(io.open(oldp, 'r'))
  for line in o:lines() do -- skip old desc
    if isPatchLike(line) then n:write(line, '\n'); break end
  end
  for line in o:lines() do n:write(line, '\n') end
  n:close(); o:close()
  local back = pvc.backupDir(P, sfmt('%s#%s', br, id)); ix.mkDirs(back)
  back = back..id..'.p'
  ix.mv(oldp, back)
  io.fmt:styled('notify', sfmt('moved %s -> %s', oldp, back), '\n')
  io.fmt:styled('notify', 'Old description (deleted):', '\n', olddesc, '\n')
  ix.mv(newp, oldp)
  io.fmt:styled('notify', 'updated desc of '..oldp, '\n')
end

function pvc.squash:__call()
  trace('squash%q', self)
  local P = self._dir
  local br, bot,top
  if self[1] then
    br, bot = pvc.resolve(P, self[1])
    top     = self[2] and toint(self[2])
  else -- local commits
    br, bot = pvc.atId(P); top = bot + 1
    pvc._commit(P, '')
  end
  pvc._squash(P, br, bot,top)
end

function pvc.rebase:__call()
  local P = self._dir
  local br = self[1] or pvc._rawat(P)
  self.id = shim.number(self.id)
  local base = pvc._getbase(pvc.branchDir(P,br))
  pvc._rebase(P, br, self.id or pvc._rawtip(pvc.branchDir(P, base)))
end

function pvc.grow:__call()
  return pvc._grow(self._dir, self.branch, self[1])
end

function pvc.prune:__call()
  local D = self._dir
  local br, id = pvc.resolve(assert(self[1], 'must specify branch'))
  local bdir = pvc.branchDir(D, br)
  assert(ix.exists(bdir), bdir..' does not exist')
  local back = pvc.backupDir(D, br); ix.mkDirs(back)
  if id then
    id = toint(id); local tip = pvc._rawtip(bdir)
    local d = pvc.depth(bdir)
    local undo = {}
    for i=id,tip do
      local from = pvc._patchPath(bdir,id, d)
      local to   = sfmt('%s%s.p', back, id)
      ix.mv(from, to)
      push(undo, sfmt('mv %s %s', to, from))
    end
    pth.write(back..'UNDO', table.concat(undo, '\n'))
    io.fmt:styled('notify', sfmt('pruned [%s -> %s]. Undo with %s',
      id, tip, back..'UNDO'))
  else
    ix.mv(bdir, back)
    io.fmt:styled('notify', sfmt('moved %s -> %s', bdir, back))
  end
end

function pvc.export:__call()
  local D = self._dir
  local br = assert(self[1], 'must specify branch')
  local to = pth.toDir(assert(self[2],
             'must specify to/ directory'))
  if ix.exists(to) then
    error('to/ directory already exists: '..to)
  end

  local bdir = pvc.branchDir(D, br)
  local tip, bbr,bid = pvc._rawtip(bdir), pvc._getbase(bdir,nil)

  ix.mkDirs(to..'commit/')
  pth.write(bdir..'tip', tip)
  ix.cp(bdir..'commit/depth', to..'commit/depth')
  if bbr then pth.write(bdir..'base', sfmt('%s#%s', bbr,bid)) end
  -- Note: if base then first id isn't there
  for id=bbr and (bid+1) or bid, tip do
    ix.forceCp(pvc._patchPath(bdir,id, pvc._patchPath(to,id)))
  end
  io.fmt:styled('notify', sfmt('exported %s to %s', bdir, to))
  return to
end

function pvc.snap:__call()
  local P = self._dir
  local br, id = pvc.resolve(P, self[1] or 'at')
  local snap = pvc.snapshot(P, br, id)
  io.stdout:write(snap, '\n')
  return pth.nice(snap)
end

if shim.isMain(pvc) then pvc:main(arg) end
return pvc
