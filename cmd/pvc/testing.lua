local mty   = require'metaty'

local T   = require'civtest'
local pth = require'ds.path'
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
  local r = repo.Repo{w=self.out..name)
  ix.rmRecursive(r.w)
  r:pvc{'init'}
  for br, dir in pairs(brs) do
    r:pvc{'pull', br, self.branches..dir}
  end
  fn(r)
end

--- Get the path to the patch in [$branches/dir/rev/{id}.p].
function pT.Harness:patch(trev) --> path
  local dir, id = trev:match'^(.+)@(%d+)$'
  return pth.concat{self.branches, dir, 'rev', repo.rawIdPath(int(id))..'.p'}
end

function pT.Harness:patchStr(trev) return pth.read(self:patch(trev)) end

return pT