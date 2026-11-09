local mty   = require'metaty'

local T   = require'civtest'
local fmt = require'fmt'
local ds  = require'ds'
local pth = require'ds.path'
local ix   = require'civix'
local pvc  = require'pvc'
local repo = require'pvc.repo'
local snap = require'pvc.snap'

--- pvc testing utilities.
local pT = mty.mod'pvc.testing'

local int         = mty.from'ds  int'

--- Create a test harness from testdata.
pT.Harness = mty'Harness' {
  'branches [dir]: path to dir of [$pvc pull] ready branches.',
  'out [dir]: output dir of live test working directories',
}
getmetatable(pT.Harness).__call = function(Ty, self)
  self.branches = pth.canonical(pth.toDir(self.branches))
  self.out      = pth.canonical(pth.toDir(self.out))
  dbg('harness', self)
  return mty.construct(Ty, self)
end

--- Usage: [{$$ lang=lua]
--- harness:test{
---   'testName', 'main@1',
---   -- branch to start at and branch name=dir/ to pull
---   -- from branches/ dir.
---   {main='main/', dev='dev3/'},
---   function(r) ... run test ... end,
--- }
--- ]$
function pT.Harness:test(cfg)
  local name, rev, brs, fn = table.unpack(cfg)
  T(name)
  local r = repo.Repo{w=self.out..name}
  ix.rmRecursive(r.w)
  r:pvc{'init'}
  ix.rmRecursive(r.r..'@main/'); ix.rm(r.w..'.pvcignore')
  for br, dir in pairs(brs) do
    r:pvc{'pull', br, self.branches..dir}
  end
  dbg('harness at', rev)
  r:pvc{'at', rev}
  local f = ds.bytearray(); local fm = fmt.Fmt{to=f, style=false}
  ctx:push{stdout=f, fmtout=fm}
  fn(r)
  ctx:pop()
end

--- Get the path to the patch in [$branches/dir/rev/{id}.p].
function pT.Harness:patch(trev) --> path
  local dir, id = trev:match'^(.+)@(%d+)$'
  return pth.concat{self.branches, dir, 'rev', repo.rawIdPath(int(id))..'.p'}
end

function pT.Harness:patchStr(trev) return pth.read(self:patch(trev)) end

local IGNORE_BRANCH_DIR = {['snap/']=true}
function pT.Harness:branchDirEq(expectBrName, resultBrDir, ignore)
  ignore = ignore and ds.copy(IGNORE_BRANCH_DIR, ignore) or IGNORE_BRANCH_DIR
  T.dirs(self.branches..expectBrName, resultBrDir, ignore)
end

return pT