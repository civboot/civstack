
local pvc = require'pvc'
local repo = require'pvc.repo'
local snap = require'pvc.snap'
local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local fd = require'fd'
local ix = require'civix'

local P     = mty.from'pvc.snap  Path'
local TD, D = 'cmd/pvc/testdata/', pth.abs'.out/pvc/'
local pc = pth.concat
local s = ds.simplestr

ix.rmRecursive(D)

-----------------------------
-- REPO

T'rawIdPath'; do
  T.eq('00',    repo.rawIdPath(0))
  T.eq('01',    repo.rawIdPath(1))
  T.eq('12',    repo.rawIdPath(12))
  T.eq('01/23', repo.rawIdPath(123))
end

T'Path'; do
  local p = 'x:42/foo/bar.txt';
    T.eq(P{x=true, id=42, p='foo/bar.txt'}, P:from(p))
    T.eq(p, tostring(P:from(p)))
  local p = ':43/foo/baz.txt'
  T.eq(P{x=nil,  id=43, p='foo/baz.txt'}, P:from(p))
    T.eq(p, tostring(P:from(p)))
  local p = '+x112:3/bob'
  T.eq(P{c=true, x=true, mtime=112, id=3, p='bob'}, P:from(p))
    T.eq(p, tostring(P:from(p)))
end

local function R()
  return repo.Repo{'/c'}
end

T'new Repo'; do
  local r = R()
  T.eq('/c/.pvc/',      r.r)
end;

T'Repo.paths'; do
  local r = R()
  T.eq('/c/.pvc/@foo/rev/01.p', r:patch'foo@1')
  T.eq('/c/.pvc/@foo/snap/1/',  r:snapPath'foo@1')
end

T'Repo init'; do
  pvc.init {work_tree=D}
  T.path(D, {
    ['.pvcignore'] = repo.INIT_PVCIGNORE,
    ['.pvc'] = {
      at = 'main@0',
      ['@main'] = { base = '@0', tip  = '0' }
    }
  })
  T.eq(s[[
  --- /dev/null
  +++ .pvcignore
  @@ -0,0 +1,3 @@
  +%.git/
  +%.civ/
  +%.out/
  ]], pvc.diff{work_tree=D}:patch())
end