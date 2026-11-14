local mty   = require'metaty'

--- pvc submodule for git remote submodule.
local git = mty.mod'pvc.git'

local ds = require'ds'
local pth = require'ds.path'
local pod = require'pod'
local ix  = require'civix'
local repo = require'pvc.repo'

local Sh             = mty.from'civix     Sh'
local sfmt           = mty.from'string    format'
local assertf        = mty.from'fmt       assertf'
local int            = mty.from'ds        int'
local Branch, Remote, asRev = mty.from'pvc.repo\
      Branch, Remote, asRev'

git.Git = pod(mty.extend(repo.Remote, 'Git', {
  rem ='.git/',
}))
local Git = git.Git

local function pushPaths(s, args)
  for _, path in ipairs(s:index()) do push(args, path.p) end
end

--- Run a git subcommand.
--- Note: this sets git-dir
function Git:git(subcmd) --> Sh
  dbg('Git:git', self.r.w)
  return Sh(ds.extend({'git', 'git-dir='..self.rem}, subcmd))
end

--- Get the id of a hash or name
function Git:_id(hashOrName) --> int
  return int(self:git{'rev-list', count=hashOrName}().out)
end

function Git:tip() return self:_id(self.rname) end

--- Get the hash of a "git id"
function Git:_hash(id) --> string
  if type(id) == 'string' then return id end
  local tip = self:tip()
  assertf(id <= tip, 'id > %s (tip)', tip)
  return self:git{'rev-parse', sfmt('%s~%s', tip-id+1)}().out
end

function Git:_wt(dir) return '--work-tree='..(dir or self.r.w) end

--- Create the snapshot of a git id.
function Git:snap(id) --> path
  local p = Branch.snap(self, id); if ix.exists(p) then return p end
  local hash = self:_hash(id)
  local tmp = self.r:tmp(asRev(self.rname,id))
  ( self:git{'archive', hash} | {'tar', '-x', '-C', tmp} )()
  ix.mv(tmp, p)
  return p
end

--- Return true if id and rev are identical (no diff).
function Git:identical(id, rev) --> bool
  local s = self.r:snapshot(rev); local wt = self:_wt(s.root)
  local cmd = self:git{wt, 'diff', '--quiet', self._hash(id), check=false}
  pushPaths(s, cmd.args)
  return 0 == cmd():rc()
end

--- Commit rev to git. Note: this is blind, it is the caller's job
--- to ensure rev-1 is already the git rname branch's tip (e.g with reset)
function Git:commit(rev)
  local desc = self.r:desc{rev}
  local sh = self:git{wt, 'commit', '-m', desc}
  for _, path in ipairs(s:index()) do if path:modified() then
    push(sh.args, path.p)
  end end
  sh()
end

--- Force set current branch
function Git:_setBranch()
  self:git{self:_wt(), 'symbolic-ref', 'HEAD', 'refs/heads/'..self.rname}
end

--- Reset branch to id without modifying working tree.
function Git:reset(id)
  self:_setBranch()
  self:git{self:_wt(), 'reset', '--soft', self:_hash(id)}
end

--- Only used for testing.
---rem must end in .git/ to use due to how finiky git init is.
function Git:create()
  dbg'git create'
  local cwd, last = pth.last(self.rem); assert(last == '.git', self.rem)
  Sh{'git', 'init', '-b', self.rname, cwd=cwd}()
end

return git