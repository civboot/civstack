#!/usr/bin/env -S lua
local shim  = require'shim'

--- Usage: [$pvc <subcmd> --help][{br}]
--- This is the [$pvc] command-line tool which can also be called directly from
--- Lua.
---
--- pvc uses [$rev] (revision) semantics of 'branch@id' where "branch" is a
--- branch name (e.g "main") and id is an incrementing patch id, where later
--- ids are always later patches.
---
--- Special branch names include: [+
--- * 'local' or just '': the local work tree (live code).
--- * 'at': the current branch@id.
--- * 'at@id', '@id' or just 'id': the current branch at a different id.
--- ]
--- Special id names include: [+
--- * 'tip': when used alone, the tip of the current branch.
---   'branch@tip' or just 'branch' mean the tip of the specified branch.
--- ]
local pvc = shim.subcmds'pvc' {}

local mty   = require'metaty'
local ds    = require'ds'
local pth   = require'ds.path'
local ix    = require'civix'
local lines = require'lines'
local kev   = require'lines.kev'
local T     = require'civtest'

local pu    = require'pvc.unix'
local snap  = require'pvc.snap'
local repo  = require'pvc.repo'

local srep, sfmt, sconcat  = mty.from(string, 'rep, format, concat')
local push, concat         = mty.from(table,  'insert, concat')
local construct            = mty.from'metaty   construct'
local notify, assertf      = mty.from'fmt      notify, assertf'
local errorf               = mty.from'fmt      errorf'

local info, trace          = mty.from'ds.log   info, trace'
local s, pk                = mty.from'ds       simplestr, popk'
local toDir, pconcat, nice = mty.from'ds.path  toDir, concat, nice'

local Base = shim.cmd'_base' {
  'work_tree [path]: working directory where code is',
  'pvc_repo  [path]: path to pvc repo, typically work_tree/.pvc/',
  '__repo [repo.Repo]',
}

function Base.new(T, args)
  info('pvc %q', args)
  args = shim.parseStr(args)
  args.work_tree = toDir(args.work_tree or ctx.CWD)
  args.pvc_repo = toDir(args.pvc_repo or pth.concat{args.work_tree, '.pvc/'})
  args.__repo = repo.Repo{w=args.work_tree, r=args.pvc_dir}
  return shim.constructNew(T, args)
end
pvc.new = Base.new

--- Usage: [$pvc init dir --branch=main][{br}]
--- Initialize the current directory as a pvc directory.
--- This will create [$.pvc/] and [$.pvcpaths]
pvc.init = mty.extend(Base, 'init', {
  'branch [string]: the initial branch name',
    branch = 'main',
})
function pvc.init:__call() --> repo.Repo
  self.__repo:init(self.branch)
  ctx.fmtlog:styled('notice', 'initialized pvc repo '..self.__repo.r, '\n')
  return self.__repo
end


--- Usage: [$pvc diff rev1::rev2 paths...][{br}]
--- Show the difference between rev1 and rev2.
--- With no args, this shows the difference between at::local, or
--- the changes from the current commit to the work_tree.
pvc.diff = mty.extend(Base, 'diff', { })
function pvc.diff:__call() --> diff.Diff
  local range = table.remove(self, 1) 
  if     not range          then range = 'at::local'
  elseif not range:find'::' then range = range..'::local' end
  local rev1, rev2 = range:match'^([^:]+)::(.*)'
  assertf(rev1, 'invalid range: %q', range)
  trace('diff %q vs %q', rev1, rev2)
  local diff = self.__repo:diff(rev1, rev2)
  diff:format(ctx.fmtout, true)
  return diff
end

--- Usage: [$pvc commit 'message' -- specific/paths to/commit][{br}]
--- Commit local changes to the current branch, creating
--- a new id.
---
--- The message is prepended to anything in the file ./PATCH. The ./PATCH
--- file is deleted after the commit is complete.
pvc.commit = mty.extend(Base, 'commit', {})
function pvc.commit:__call()
  local r = self.__repo; local ppatch = r.w..'PATCH'
  local desc = {}; if self[1] then push(desc, self[1]); push(desc, '') end
  if ix.exists(ppatch) then push(desc, pth.read(ppatch)) end
  desc = concat(desc, '\n'); assert(desc:find'%S', 'empty commit description')
  r:commit(ds.trim(desc), r:diff('at', 'local'))
  ix.rm(ppatch)
end

--- Usage: [$pvc at [rev] --force][{br}]
--- If [$rev] is not given, just returns current branch#id.
---
--- Otherwise, sets the active [$branch@id], causing the local directory to be
--- updated to be that snapshot.
---
--- If any local changes would be overwritten this will fail unless force=true.
---
--- ["[$at branch@id] is called a "checkout" in other version
---   control systems.]
pvc.at = mty.extend(Base, 'at', {
  [[force [bool]: overwrite local changes]],
})
function pvc.at:__call()
  local w, r, f = self.work_tree, self.__repo, self.force
  local rev = f and (self[1] or r:at()) or self[1]
  if not rev then ctx.stdout:write(r:at(), '\n'); return end
  local s1, s2 = r:localsnap(), r:snapshot(rev)
  local i1, i2 = s1:index(), s2:index()
  local copy, block = {}, {}
  for _, p2 in ipairs(i2) do
    local p1 = i1[i1[p2.p]]
    if not p1 then push(copy, p2); goto cont end
    local path1 = s1.root..p1.p
    if (p1:cleaned()==p2 and p1.mtime==ix.mtime(path1))
       or ix.pathEq(path1, s2.root..p2.p)
    then goto cont end -- already equal, skip
    if f then push(copy, p2) else push(block, p2) end
    ::cont::
  end
  if #block > 0 then errorf('paths are modified:\n%s', concat(block)) end
  for _, p in ipairs(copy) do ix.forceCp(s2.root..p.p, w..p.p) end
  notify('now at %s', rev)
end

--- Usage: [$pvc upload branchName path/to/dir]
--- Backs up the branch to the directory, making a complete copy of the
--- rev/ and metadata files but not copying snapshots.[{br}]
--- TODO: support upload to remote repo.
pvc.upload = mty.extend(Base, 'upload', {
  'force [bool]: if true delete any existing directories.',
})
function pvc.upload:__call()
  local br, d, r = self[1], self[2], self.__repo
  if ix.exists(d) then
    assertf(self.force, 'already exists: %s', d); ix.rmRecursive(d)
  end
  ix.cpRecursive(r:bdir(br), d, {['snap/'] = -1})
  notify('uploaded %s to %s', br, d)
end

--- Usage: [$pvc pull branchName path/to/dir]
--- Restore the branch from path/to/dir.[{br}]
--- TODO: support pulling from remote repo.
pvc.pull = mty.extend(Base, 'pull', {
  'force [bool]: if true delete an existing branch.',
})
function pvc.pull:__call()
  local br, d, r = self[1], self[2], self.__repo
  local bdir = r:bdir(br)
  T.path(d, { tip = true, rev = {} })
  if ix.exists(bdir) then
    assertf(self.force, '%s already exists: %s', br, bdir)
    ix.rmRecursive(bdir)
  end
  ix.cpRecursive(d, bdir, {['snap/'] = -1})
  notify('pulled %s from %s', br, d)
end

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

if shim.isMain(pvc) then pvc:main(G.arg) end
return pvc