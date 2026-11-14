#!/usr/bin/env -S lua
local shim  = require'shim'

--- Usage: [$pvc <subcmd> --help][{br}]
--- Patch-based Version Control.
---
--- Commit, branch and refactor [$rev] (revisions) in the form of `branch@id`.
local pvc = shim.subcmds'pvc' {}

local mty   = require'metaty'
local ds    = require'ds'
local pth   = require'ds.path'
local ix    = require'civix'
local lines = require'lines'
local kev   = require'lines.kev'
local pod   = require'pod'
local T     = require'civtest'

local pu    = require'pvc.unix'
local snap  = require'pvc.snap'
local repo  = require'pvc.repo'

local str                  = tostring
local max                  = mty.from'math     max'
local srep, sfmt, sconcat  = mty.from'string   rep, format, concat'
local push, pop, concat    = mty.from'table    insert, remove, concat'
local construct            = mty.from'metaty   construct'
local notify, assertf      = mty.from'fmt      notify, assertf'
local errorf               = mty.from'fmt      errorf'
local info, trace          = mty.from'ds.log   info, trace'
local s, pk, int           = mty.from'ds       simplestr, popk, int'
local toDir, pconcat, nice = mty.from'ds.path  toDir, concat, nice'
local asRev, splitRev      = mty.from'pvc.repo asRev, splitRev'

local EMPTY = {}

local Base = shim.cmd'_base' {
  'work_tree [path]: working directory where code is',
  'pvc_repo  [path]: path to pvc repo, typically work_tree/.pvc/',
  'out       [file]: where to output to',
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

--- Usage: [$pvc status][{br}]
--- Show the current status of at vs tip.
pvc.status = mty.extend(Base, 'status', {})
function pvc.status:__call()
  local r = self.__repo
  local diff = r:diff('at', 'local'):reduced()
  local f = ctx.fmtout
  f:styled('bold', 'at '); f:styled('string', r:at(), '\n')
  if diff:hasDiff() then
    f:styled('bold', 'Changed files:', '\n'); diff:format(f, false)
  else f:styled('bold', 'No changes in working tree', '\n') end
end

--- Usage: [$pvc log rev=at][{br}]
--- Show the branch structure starting at rev.
pvc.log = mty.extend(Base, 'status', {
  "before[int]: number of id's before rev to output", before=5,
  'max [int]: maximum number of lines to output',
})
function pvc.log:__call()
  local r = self.__repo
  local f, br,id = ctx.fmtout, r:splitRev(self[1] or 'at')
  info('pvc log %s@%s', br,id)
  local c = {br, max(0, id-self.before), rem=self.max}
  function c.fn(depth, br,id)
    local b = r:branch(br)
    f:styled('meta', srep('* ', depth))
    local rev = asRev(r:actualBranch(br,id),id)
    f:styled('string', rev, ' ')
    if rev == r:at() then f:styled('meta', '[at]', ' ') end
    f:write(concat(b:desc{id, max=1}, '\n'))
    f:write'\n'
  end
  r:walk(c)
end

--- Usage: [$pvc diff rev1::rev2 paths...][{br}]
--- Show the difference between rev1 and rev2.
--- With no args, this shows the difference between at::local, or
--- the changes from the current commit to the work_tree.
pvc.diff = mty.extend(Base, 'diff', { })
function pvc.diff:__call() --> diff.Diff
  local r = self.__repo
  local r1, r2 = r:splitRange(table.remove(self, 1))
  trace('diff %q vs %q', r1, r2)
  local diff = r:diff(r1, r2)
  diff:format(ctx.fmtout, true)
  return diff
end

--- Usage: [$pvc patch path/to/patch.p...]
--- Apply a series of patches
pvc.patch = mty.extend(Base, 'patch', {
  'exclude {path}: paths to exclude from patches.',
    exclude=snap.EXCLUDE,
})
function pvc.patch:__call()
  local r = self.__repo
  local ppath = r:tmp'patch'..'patch.p'
  local exclude = ds.Set:from(self.exclude)
  for _, path in ipairs(self) do
    local f = assert(ctx.open(ppath, 'w'))
    snap.trimPatch(pth.read(path), exclude, f)
    f:flush(); assert(f:close())
    pu._patch(r.w, ppath)
  end
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

--- Usage: [$$pvc at [rev] --force]$[{br}]
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
  if not rev then ctx.stdout:write(r:at(), '\n'); return r:at() end
  r:setAt(rev, f); return rev
end

--- Usage: [$$pvc tip [branch]]$[{br}]
--- Get the tip id of branch.
pvc.tip = mty.extend(Base, 'tip', {})
function pvc.tip:__call()
  local r = self.__repo
  ctx.stdout:write(str(r:tip(self[1] or r:splitRev'at')), '\n')
end

--- Usage: [$snap rev][{br}]
--- Get the snapshot (directory) of rev. You should treat this dir as readonly.
pvc.snap = mty.extend(Base, 'snap', {})
function pvc.snap:__call() --> dir/
  local s = self.__repo:snapshot(self[1] or 'at')
  ctx.stdout:write(s, '\n'); return s
end

--- Usage: [$pvc upload branchName path/to/dir]
--- Backs up the branch to the directory, making a complete copy of the
--- rev/ and metadata files but not copying snapshots.[{br}]
pvc.upload = mty.extend(Base, 'upload', {
  'force [bool]: if true delete any existing directories.',
})
function pvc.upload:__call()
  local br, d, r = self[1], self[2], self.__repo
  local b = r:branch(br)
  if d then -- simple directory upload
    if ix.exists(d) then
      assertf(self.force, 'already exists: %s', d); ix.rmRecursive(d)
    end
    ix.cpRecursive(b.dir, d, {['snap/'] = -1})
    return notify('uploaded %s to directory %s', br, d)
  end
  local bbr, bid = splitRev(b:base()); local bb = r:branch(bbr)
  assertf(bb:isRemote(), 'cannot upload to non-remote branch %q', bbr.name)
  local tdrop
  if bb:tip() < b:tip() then tdrop=true; bb:reset(b:tip() end
  for i = bid+1,b:tip() do
    if bb:identical(i, asRev(br,i)) then bid = i
    else goto different end
  end
  return notify('remote base %s already identical to %s%s', bbr, br,
    tdrop and sfmt(' (except dropped commits after %s)', b:tip()) or '')
  ::different::
  bb:reset(bid)
  for i = bid+1,b:tip() do bb:commit(asRev(br,i)) end
  return notify('remote base %s updated %s -> %s', bbr, bid, b:tip())
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

--- Usage: [$$pvc branch name [from]]$[{br}]
--- Start new branch [$name] branching off of [$from].
pvc.branch = mty.extend(Base, 'branch', {
  'checkout [bool]: whether to checkout the branch', checkout=true,
})
function pvc.branch:__call()
  local r = self.__repo;
  local br, base = self[1], r:rev(self[2] or 'at')
  r:newBranch(br, base)
  if shim.bool(self.checkout) then
    if r:at() == base then
      local bbr, bid = splitRev(base)
      r:_setAt(asRev(br, bid))
    else r:setAt(self[1]) end
  end
end

--- Usage: [$pvc cp rev paths...][{br}]
--- Cherry pick revision into working tree. If [$paths] are passed
--- then only cherry pick those paths.
pvc.cp = mty.extend(Base, 'cp', {
  "commit [string|true]: if true use rev's description, else use string as desc",
})
function pvc.cp:__call()
  local r = self.__repo; local rev = assert(pop(self), 'must specify rev')
  local desc = self.commit==true and r:desc{rev} or self.commit
  assert(r:cp(rev, #self>0 and ds.Set:from(self)))
  if desc then r:commit(desc, r:diff('at', 'local')) end
  notify('cherrypicked%s %s', desc and ' and committed' or '', rev)
end

--- Usage: [$$pvc squash int 'some description']$[{br}]
--- Squash some number of commits at tip.
--- The description will be their concatenated descriptions by default.
pvc.squash = mty.extend(Base, 'squash', {})
function pvc.squash:__call()
  local r, num = self.__repo
  local num = assert(int(self[1]), 'must specify number to squash')
  if num <= 0 then return notify'squash num <= 0, skipping' end
  r:squash(r:splitRev'at', num, --[[desc]]self[2])
end


--- histedit usage:        [$pvc plan branch@id]
--- Rebase usage:          [$pvc plan br=newBase@id]
---
--- plan is the swiss-army knife to create an editable plan to rebase,
--- reorder, split, squash or otherwise modify commits and commit history.
---
--- Creates a PVCPLAN and, if run=true, executes it. [$run] is default true
--- for rebases and default false for non-rebsaes. If no rev/rebase is given
--- then resumes an existing plan.
---
--- A plan is stored in the PVCPLAN file and is simply a series of commands
--- which create new ".branch" branches and cherry pick (cp) a series of
--- commits. They can also squash commits.
pvc.plan = mty.extend(Base, 'squash', {
  'run [bool]: set to false to not run the plan', run=true,
  'skip [int]: number of items to skip in a plan. [$run] must be true.',
 [[finish [bool]: if [$true] ONLY finish the plan (swap .branches).
   If false, never finish the plan even after successful run.
 ]],
})
function pvc.plan:runPlan()
  if not self.run then return end
  local r = self.__repo
  r:runPlan(nil, self.skip)
  if not (self.finish==false) then r:finishPlan() end
end
function pvc.plan:__call()
  self.run, self.skip = shim.bool(self.run), shim.int(self.skip)
  self.finish = shim.bool(self.finish)
  local r = self.__repo; local g = r:childGraph()
  if self.finish then return r:finishPlan() end
  local arg = self[1]; if not self[1] then
    dbg'pvc.plan - run only'
    return self:runPlan()
  end
  local arg = assert(self[1], 'FIXME: just run')
  local id,br,base = nil, arg:match'^([%w._]+)=(.+)$'
  if br then -- rebase
    repo.checkBranch(br)
    id = select(2, splitRev(r:branch(br):base())) + 1
  else -- histedit
    br,id = r:splitRev(arg)
    base = asRev(r:actualBranch(br,id-1),id-1)
  end
  local p = {
    sfmt('branch .%s %s', br, base),
    {'at', '.'..br},
  }
  r:walk{br,id, p[#p],
    fn=function(depth, br,id, p)
      push(p, sfmt('cp %s --commit', asRev(br,id)))
    end,
    childFn = function(_, par, br,id, p)
      push(p, sfmt('branch .%s %s', br, asRev(par,id)))
      push(p, {'at', '.'..br})
      return p[#p]
    end,
  }
  r:dumpPlan(p)
  self:runPlan()
end

--- Usage: [$$pvc remote name pvc.git.Git path/to/.git/]$[{br}]
--- Add a remote branch named "name" of type [$pvc.git.Git]
--- The path to e.g [$.git/] is optional if the repo is in your
--- work-tree.
pvc.remote = mty.extend(Base, 'remote', {
  'rname [string?]: optional remote branch name (default=name)',
  'init [bool]: initialize the repo, this is rare outside of testing',
})
function pvc.remote:__call() --> Remote
  dbg('remote', self)
  local r, name = self.__repo, self[1]
  local ty = assert(self[2], 'must specify repo type')
  local b = setmetatable(r:_newBranch(name), nil)
  b.ty, b.rem, b.rname = ty, self[3], self.rname or name
  b = assertf(ds.wantpath(b.ty), 'unknown type: %q', b.ty)(b)
  b.r = r; b:init()
  dbg('remote branch', b)
  if not self.init then assert(b:tip(), 'remote tip cannot be found') end
  ix.mkTree(b.dir, { snap = EMPTY })
  b.r = nil; b:dump(); b.r = r
  if self.init then b:create() end
  return b
end

if shim.isMain(pvc) then pvc:main(G.arg) end
return pvc