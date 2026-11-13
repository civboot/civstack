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

--- Create Sh of git subcmd.
function Git:git(subcmd) --> Sh
  dbg('Git:git', self.r.w)
  return Sh(ds.extend({'git', cwd=self.r.w}, subcmd))
end

--- Get the id of a hash or name
function Git:_id(hashOrName) --> int
  return int(self:git{'rev-list', count=hashOrName}().out)
end

function Git:tip() return self:_id(self.rname) end

--- Get the hash of a "git id"
function Git:_hash(id) --> string
  local tip = self:tip()
  assertf(id <= tip, 'id > %s (tip)', tip)
  return self:git{'rev-parse', sfmt('%s~%s', tip-id+1)}().out
end

--- Create the snapshot of a git id.
function Git:snap(id) --> path
  local p = Branch.snap(self, id); if ix.exists(p) then return p end
  local hash = self:_hash(id)
  local tmp = self.r:tmp(asRev(self.rname,id))
  ( self:git{'archive', hash} | {'tar', '-x', '-C', tmp} )()
  ix.mv(tmp, p)
  return p
end

function Git:commit(desc)
  self:git{'git', 'symbolic-ref', 'HEAD', 'refs/heads/'..self.rname}()
  self:git{'git', 'commit', '-a', '-m', desc}()
end

-- Only used for testing.
function Git:create()
  dbg'git create'
  self:git{'init', '-b', self.rname}()
end

return git