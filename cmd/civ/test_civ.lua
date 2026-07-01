
local T = require'civtest'
local mty = require'metaty'
local freeze = require'metaty.freeze'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local luk = require'luk'
local civ = require'civ'
local core = require'civ.core'

local Epoch = mty.from'ds.time  Epoch'

local D = pth.resolve(ds.srcdir()..'../..')
local O = D..'.out/civ/'

local HUBS = { civ = D, sys = D..'sys/' }

local CFG_PATH = O..'civconfig.lua'

local CFG = ([[
return {
  buildDir = %q,
  hubs = {
    civ = %q, sys = %q,
  },
}
]]):format(O, D, D..'sys/')

ix.mkDirs(O); pth.write(CFG_PATH, CFG)

local cfg = core.Cfg:load(CFG_PATH)
local function newCiv()
  ix.rmRecursive(O); ix.mkDirs(O)
  pth.write(CFG_PATH, CFG)
  return core.Civ{cfg=cfg}
end

local LUA_BUILD = "sys:lua/build.lua"

local METATY_PKG = core.Target {
  pkgname="civ:lib/metaty", name="metaty",
  dir = pth.abs(D.."lib/metaty/"),
  src={"metaty.lua", "freeze.lua"},
  out={lua={
    ['metaty.lua']="metaty.lua",
    ['freeze.lua'] = 'metaty/freeze.lua',
  }},
  api={'metaty', 'metaty.freeze'},
  tag={builder='bootstrap'},
  kind='build', run=LUA_BUILD,
}

local FMT_PKG = core.Target {
  pkgname='civ:lib/fmt', name='fmt',
  dir = pth.abs(D.."lib/fmt/"),
  src={ 'fmt.lua', 'binary.lua' },
  dep={'civ:lib/metaty#metaty'},
  out={lua={
    ['fmt.lua']    = 'fmt.lua',
    ['binary.lua'] = 'fmt/binary.lua',
  }},
  link={["lua/fmt/binary.lua"]="bin/seebin"},
  api={'fmt', 'fmt.binary'},
  tag={builder='bootstrap'},
  kind='build', run=LUA_BUILD,
}

T'Target' do
  local lson = require'lson'
  local pod = require'pod'
  local function getTarget()
    return core.Target {
      out={lua={"metaty.lua", ['freeze.lua'] = 'metaty/freeze.lua'}},
      api={'metaty', 'metaty.freeze'},
    }
  end
  local t = getTarget()
  T.eq({'metaty', 'metaty.freeze'}, t.api)
  local p = luk.value(luk.Table{t = getTarget()})
  T.eq(getTarget(), p.t)
  T.eq('metaty',             t.api[1])
  T.eq('metaty.freeze',      t.api[2])

  local fs = freeze.forceset
  fs(p,   'pkgname', 'p')
  fs(p.t, 'pkgname', 'p')
  T.eq('p', p.pkgname)
  T.eq('p', p.t.pkgname)
  local t2 = getTarget()
  t2.pkgname = 'p'
  T.eq('p', t2.pkgname)
  T.eq(t2, p.t)

  local p = luk.Table{t = t}:freeze()
  T.eq({'metaty', 'metaty.freeze'}, p.t.api)

  T.eq('["metaty","metaty.freeze"]', lson.json(t.api))

  local t = getTarget()
  T.eq({"D/lua/metaty.lua",
        ["freeze.lua"] = "D/lua/metaty/freeze.lua"}, t:outPaths'D/')

  t.mtime = Epoch(6, 7)

  local p = pod.toPod(t)
  T.eq(p.mtime, {6, 7})
  T.eq(Epoch(6,7), pod.fromPod({6, 7}, Epoch))

  local tLson = lson.json(t)
  local tDe = lson.decode(tLson, core.Target)
  T.eq(Epoch(6, 7), tDe.mtime)
  T.eq({'civ:cmd/civ#civ'}, tDe.dep)
  T.eq(t, tDe)
  t.mtime = Epoch(6, 77)
  assert(not mty.eq(t, tDe))
end

T'tgtname'; do
  T.eq({'foo:bar',  'baz'}, {core.tgtnameSplit'foo:bar#baz'})
  T.eq({'foo:bar',  'bar'}, {core.tgtnameSplit'foo:bar'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:#foo'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:'})
end

T'loadPkg'; do
  local c = newCiv()

  local metatyPkg = c:loadPkg'civ:lib/metaty'
  T.eq({'metaty', 'metaty.freeze'}, METATY_PKG.api)
  T.eq(luk.Table{
    pkgname="civ:lib/metaty",
    summary="Simple but effective Lua type system.",
    metaty=METATY_PKG,
  }:freeze(), metatyPkg)

  local fmtPkg = c:loadPkg'civ:lib/fmt'
  T.eq(FMT_PKG, fmtPkg.fmt)
end

local fd_out = {
  lua = { ['fd.lua']='fd.lua', }
}
local libfd_out = {
  include = { ['fd.h'] = 'fd.h' },
  lib     = { 'libfd.so' },
}

T'loadFd'; do
  local l = newCiv()
  l:loadPkgs{'civ:lib/fd'}
  T.eq(METATY_PKG.out, l.pkgs['civ:lib/metaty'].metaty.out)
  local fdpkg = l.pkgs['civ:lib/fd']
  T.eq(fd_out,          fdpkg.fd.out)
  T.eq({'fd.c'},  fdpkg.libfd.src)
  T.eq(libfd_out,       fdpkg.libfd.out)
end

T'loadLinesTesting'; do
  local l = newCiv()
  l:loadPkgs{'civ:lib/lines/testing'}
  T.eq({
    lua = { ['testing.lua'] = 'lines/testing.lua' },
  }, l.pkgs['civ:lib/lines/testing'].testing.out)
end

T'expand'; do
  local l = newCiv()
  T.eq({"civ:lib/metaty#metaty"},             l:expand'civ:lib/metaty#.*')
  T.eq({"civ:lib/ds#ds", "civ:lib/ds#dslib"}, l:expand'civ:lib/ds#')
  T.eq({
    "civ:lib/ds#ds", "civ:lib/ds#dslib",
    "civ:lib/ds/testing#testing",
  }, l:expand'civ:lib/ds/.*#')
  T.eq({"civ:lib/ds#ds"}, l:expand'civ:lib/ds')
  T.eq({"civ:lib/ds#ds"}, l:expand'civ:lib/ds#ds')
end

T'buildMetaty'; do
  local l = newCiv()
  l:loadPkgs{'civ:lib/metaty'}
  l:build{'civ:lib/metaty'}
  T.path('.out/civ/', {
    ['lua/'] = {
      ['metaty.lua'] = io.open'lib/metaty/metaty.lua',
    }
  })
end

T'buildDs'; do
  local l = newCiv()
  l:loadPkgs{'civ:lib/ds'}
  local dsPkg = l.pkgs['civ:lib/ds']
  T.eq({"civ:lib/metaty#metaty", "civ:lib/fmt#fmt", "civ:lib/ds#dslib"},
       dsPkg.ds.dep)
  T.eq(core.Target{
    pkgname="civ:lib/ds",
    name="dslib",
    dir=pth.abs(D.."lib/ds/"),
    src={"ds.c"},
    extra=cfg.builder.lua.cc,
    dep={},
    out={
      include={['ds.h'] = "ds.h"},
      lib={"libds.so"},
    },
    tag={ builder = 'bootstrap' },
    kind='build', run="sys:cc/build.lua",
  }, dsPkg.dslib)

  l:build{'civ:lib/ds'}

  T.path('.out/civ/include', {
    ['ds.h'] = io.open'lib/ds/ds.h',
  })
  T.exists'.out/civ/lib/libds.so'
end

T'buildCiv'; do
  local l = newCiv()
  l:loadPkgs{'civ:cmd/civ'}
  l:build{'civ:cmd/civ'}
end

T'testMetaty'; do
  local l = newCiv()
  local p = 'civ:lib'
  local t = p..'#test_meta'
  l:loadPkgs{p}
  l:test({t}, l:build{t})
end
