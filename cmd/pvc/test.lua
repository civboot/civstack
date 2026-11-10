
local pvc = require'pvc'
local repo = require'pvc.repo'
local snap = require'pvc.snap'
local pT = require'pvc.testing'
local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local fd = require'fd'
local ix = require'civix'

local concat            = mty.from'table   concat'
local P                 = mty.from'pvc.snap  Path'
local TD, D = 'cmd/pvc/testdata/', pth.abs'.out/pvc/'
local pc = pth.concat
local s = ds.simplestr

ix.rmRecursive(D)

local H = pT.Harness{branches=TD, out=D}

T'snap'; do
  T.eq(true, snap.EXCLUDE_SET.PVCPLAN)
end

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

T'branches'; do
  local B = function(t) return repo.Branch:fake(t) end
  local brs = {
    main = B{name='main', _base=false,    _tip=12},
    fix  = B{name='fix',  _base='main@10', _tip=2},
    dev  = B{name='dev',  _base='main@6', _tip=8},
    ftr  = B{name='ftr',  _base='dev@7',  _tip=3},
  }

  T.eq({
    [false] = {'main'},
    main = {
      'dev', dev=6,
      'fix', fix=10,
    },
      fix = {},
      dev = {'ftr', ftr=7},
        ftr = {},
  }, repo._childGraph(brs))
end

T'new Repo'; do
  local r = R()
  T.eq('/c/.pvc/',      r.r)
end;

T'Repo init'; do
  local r = pvc.init {work_tree=D}
  T.path(D, {
    ['.pvcignore'] = repo.INIT_PVCIGNORE,
    ['.pvc'] = {
      at = 'main@0',
      ['@main'] = { base = false, tip  = '0' }
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
  r:setAt('main', true)
  T.eq('main@0', r:at())
  T.eq(D..'.pvc/@main/', r:branch'main'.dir)
  T.eq(D..'.pvc/@main/rev/01.p', r:patch'main@1')
  T.eq(D..'.pvc/@main/snap/1/',  r:branch'main':snap(1))
  T.throws('branch "dne" does not exist', function()
    T.eq(nil, r:branch'dne')
  end)
end

local M1_PVCINDEX = [[
--- /dev/null
+++ PVCINDEX
@@ -0,0 +1 @@
++x:/.pvcignore
]]
local M1_PVCIGNORE = [[
--- /dev/null
+++ .pvcignore
@@ -0,0 +1,4 @@
+%.git/
+%.civ/
+%.out/
+%.gitignore
\ No newline at end of file]]

T'trimPatch'; do
  local p1 = pth.read(TD..'main/rev/01.p')
  T.eq('first commit\n\n'..M1_PVCINDEX..'\n'..M1_PVCIGNORE..'\n', p1)
  local function tp(...) return tostring(snap.trimPatch(...)) end
  T.eq(M1_PVCINDEX..M1_PVCIGNORE..'\n', tp(p1, {}))
  T.eq(M1_PVCIGNORE..'\n',              tp(p1, {PVCINDEX=1}))
end

local SKIP = {['.pvc/']=1, PVCINDEX=1}

local NUM_1   = 'zero\nfifty\none hundred'
local NUM_UP  = 'zero\nfifty\neighty\nninety\none hundred'
local NUM_LOW = 'zero\nten\ntwenty\nfifty\none hundred'
local NUM_2   = 'zero\nten\ntwenty\nfifty\neighty\nninety\none hundred'

H:test{'main', 'main@2', {main = 'main/'},
function(r)
  T.eq('main@2', r:at())
  T.eq('main@2', r:pvc'at')
  T.path(r.w..'.pvcignore', repo.INIT_PVCIGNORE..'%.gitignore')
  T.path(r.w..'num.txt',    NUM_1)
  T.dirs(r.w, r:branch'main':snap(2), SKIP)

  r:pvc'at main@0'; T.eq('main@0', r:pvc'at')
  T.path(r.w, {['.pvcignore'] = false, ['num.txt']=false}, SKIP)
  T.dirs(r.w, r:branch'main':snap(0), SKIP)
end}

H:test{'upper', 'main@2', {main = 'main/'},
function(r)
  r:pvc{'patch', H:patch'upper@3'}; T.path(r.w..'num.txt', NUM_UP )
  T.throws('paths are modified:\nnum.txt', function()
    r:pvc{'at', 'main@2'}  -- cannot checkout with changes
  end)
  T.path(r.w..'num.txt', NUM_UP )
  r:pvc{'branch', 'upper'}; local b = r:branch'upper'
    T.eq('main@2', b:base())
    T.eq(r.w..'.pvc/@main/snap/2/', r:snapshot'upper@2'.root)
    T.eq(r.w..'.pvc/@main/snap/0/', r:snapshot'upper@0'.root)

  r:pvc{'at', 'upper@2', force=true} -- main@2
  T.path(r.w..'num.txt',    NUM_1)
  r:pvc{'patch', H:patch'upper@3'}; T.path(r.w..'num.txt', NUM_UP )
  r:pvc{'commit', 'upper: add 80,90'}
  H:branchDirEq('upper', r:branch'upper'.dir) 
end}

H:test{'lower', 'main@2', {main = 'main/'},
function(r)
  r:pvc{'branch', 'lower'}
  pth.write(r.w..'num.txt', NUM_LOW); r:pvc{'commit', 'lower: add 10,20'}
  H:branchDirEq('lower', r:branch'lower'.dir)
  T.eq('', tostring(ctx.stdout))
  r:pvc'log'; T.eq(s[[
  main@0 zero patch
  main@1 first commit
  main@2 num.txt: first commit
  * lower@3 [at] lower: add 10,20
  ]], tostring(ctx.stdout))
end}

H:test{'cherrypick', 'main@2', {main='main/', upper='upper/', lower='lower/'},
function(r) -- direct grafts of upper+lower
  assert(r:cp'upper@3'); T.path(r.w..'num.txt', NUM_UP )
  r:pvc{'commit', r:desc'upper@3'}
  T.fileEq(H:patch'upper@3', r:patch'main@3')

  assert(r:cp'lower@3'); T.path(r.w..'num.txt', NUM_2)
  r:pvc{'commit', r:desc'lower@3'}
  H:branchDirEq('main_merged', r:branch'main'.dir)
end}

H:test{'cherrypick_commit', 'main@2', {main='main/', upper='upper/', lower='lower/'},
function(r) -- direct grafts of upper+lower using --commit
  r:pvc{'cp', 'upper@3', commit=true}
  r:pvc{'cp', 'lower@3', commit=true}
  H:branchDirEq('main_merged', r:branch'main'.dir)
end}

H:test{'squash', 'main@4', {main='main_merged'},
function(r)
  r:pvc{'squash', 2}
  T.path(r.w..'num.txt', NUM_2)
  H:branchDirEq('main_squashed', r:branch'main'.dir)
end}


local MAIN_PLAN = [[return {
"branch .main main@0",
{"at", ".main",
  "cp main@1 --commit",
  "cp main@2 --commit",
  "cp main@3 --commit",
  "cp main@4 --commit",
},
} --end]]..'\n'

H:test{'plan_main', 'main@1', {main = 'main_merged/'},
function(r)
  r:pvc{'plan', 'main@1', run=false}; T.path(r.w..'PVCPLAN', MAIN_PLAN)
  r:pvc{'plan', run=true, finish=false}
  local db = r:branch'.main'
  H:branchDirEq('main_merged', db.dir, {
    base=true, ["rev/00.p"]=true,
  })
  T.eq({'.main', 'main'}, ds.orderedKeys(r:branches()))
  r:pvc{'plan', run=false, finish=true}
  H:branchDirEq('main_merged', r:branch'main'.dir)
  T.eq({'main'}, ds.orderedKeys(r:branches()))
  T.eq(nil, r._branches['.main'])
  -- TODO: should the plan try to return to the original commit???
  T.eq('main@4', r:at()) 
end}

local BRANCHES_PLAN = [[return {
"branch .main main@0 --done",
{"at", ".main", done=true,
  "cp main@1 --commit --done",
  "cp main@2 --commit --done",
  "branch .lower main@2 --done",
  {"at", ".lower", done=true,
    "cp lower@3 --commit --done",
  },
  "branch .upper main@2 --done",
  {"at", ".upper", done=true,
    "cp upper@3 --commit --done",
  },
},
} --end]]..'\n'
H:test{'plan_branches', 'main@1', {main='main/', upper='upper/', lower='lower/'},
function(r)
  r:pvc{'plan', 'main@1'}; T.path(r.w..'PVCPLAN', BRANCHES_PLAN)
  H:branchDirEq('main/',  r:branch'main'.dir)
  H:branchDirEq('upper/', r:branch'upper'.dir)
  H:branchDirEq('lower/', r:branch'lower'.dir)
  T.eq('upper@3', r:at()) 
end}

local REBASE_PLAN=[[return {
"branch .lower main@3 --done",
{"at", ".lower", done=true,
  "cp lower@3 --commit --done",
},
} --end]]..'\n'
H:test{'plan_rebase', 'main@2', {main='main/', upper='upper/', lower='lower/'},
function(r)
  r:pvc{'cp', 'upper@3', commit=true}
  r:pvc{'plan', 'lower=main@3'}; T.path(r.w..'PVCPLAN', REBASE_PLAN)
  T.eq('lower@4', r:at())
  T.path(r.w..'num.txt', NUM_2)
  H:branchDirEq('main_upper/',  r:branch'main'.dir)
  H:branchDirEq('upper/', r:branch'upper'.dir) -- unchanged
  H:branchDirEq('lower_rebased/', r:branch'lower'.dir)
end}