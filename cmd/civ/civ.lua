#!/usr/bin/env -S lua
local shim = require'shim'

--- civ command
local civ = shim.subcmds'civ' {}

local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'
local pth = require'ds.path'
local info = require'ds.log'.info
local ix = require'civix'
local core = require'civ.core'

local G = mty.G
local sfmt = string.format
local push = ds.push
local assertf = fmt.assertf

local function tgtnamesSplit(args) --> pkgnames, tgtnames
  local pkgnames, tgtnames = {}, {}
  for _, tgtname in ipairs(args) do
    local tgt = core.TargetName:parse(tgtname)
    push(tgtnames, tostring(tgt))
    if not pkgnames[tgt.pkgname] then
      push(pkgnames, tgt.pkgname)
      pkgnames[tgt.pkgname] = true
    end
  end
  return pkgnames, tgtnames
end


function civ._pre()
  assert(not ix.isRoot(), "Do not run this command as root")
end

civ._Base = shim.cmd'_Base' {
  'config [string]: path to civ config.',
  'clean  [bool]',
}

--- Usage: [$civ init][{br}]
--- Initialize the repository. This should be run when starting a new repo.
civ.init = shim.cmd'init' {
  'config [string]: path to config.lua to output',
    config = core.DEFAULT_CONFIG,
  'llua [string]: the lua library name override for pkg-config, i.e. lua5.3',
    llua = 'lua',
}

--- Usage: [$civ build hub:tgt#name][{br}]
--- Build targets which match the pattern.
civ.build   = mty.extend(civ._Base, 'build', {})

--- Usage: [$civ test hub:tgt#name][{br}]
--- Test targets which match the pattern.
civ.test   = mty.extend(civ.build, 'test', {})

--- Usage: [$civ run hub:tgt#name -- ...args][{br}]
--- Build+run a single build target which has a single bin or link output.
civ.run    = mty.extend(civ.build, 'run', {})

--- Usage: [$civ install hub:tgt#name][{br}]
--- Install targets which match the pattern.
civ.install = mty.extend(civ._Base, 'install', {
  "force [bool]: do not confirm deletion of files.",
})

local BASE_TEMPL = [[
-- holds the config table, returned at end.
local C = {}

-- the host operating system. This primarily affects
-- what build flags are used when compiling C code.
C.host_os = %q

-- A table of hubname -> /absolute/dir/path/
-- This should contain the "software hubs" (which contain HUB.lua files)
-- that you want your project to depend on when being built.
C.hubs = {
  -- This hub, which contains libraries and software for
  -- the civboot tech stack (along with this build tool).
  civ = %q,

  -- The sys hub, which contains system-specific rules for building
  -- source code.
  sys = %q,
}

-- The directory where `civ install` puts files.
C.installDir = HOME..'.local/civ/'

-- OS-specific configuration for builder job.
C.builder = {
  lua = {
    -- flags to link to system lua
    cc = %q,
  },
}

return C -- return for civ to read.
]]

local CONFIG_TEMPL = [[
-- This file extends the base config (at ~/.config/civ.luk by default).
local C = {} -- config

-- Additional hubs for this project (local)
C.hubs = {}

-- The directory where `civ build` and `civ test` puts files.
C.buildDir = '.civ/'

return C
]]

local BASH_ADD = [[
CIV=%s
export PATH=$PATH:$CIV/bin:$CIV/lua
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CIV/lib
export LUA_PATH="$LUA_PATH;$CIV/lua/?.lua"
export LUA_CPATH="$LUA_CPATH;$CIV/lib/lib?.so"
export LUA_SETUP=vt100
]]

function civ.init:__call()
  civ._pre()
  info('civ init', self)
  local cfg
  if not ix.exists(core.BASE_CONFIG) then
    local luaFlags = ds.splitList(ds.trim(
      ( ix.sh('pkg-config --cflags --libs '..self.llua) )
    ))
    pth.write(core.BASE_CONFIG, fmt.format(BASE_TEMPL,
      ix.OS, core.DIR, core.DIR..'sys/', luaFlags))
    io.fmt:styled('notify', 'Wrote base config to: ')
    io.fmt:styled('path', core.BASE_CONFIG, '\n')
  end
  if not ix.exists(self.config) then
    pth.write(self.config, CONFIG_TEMPL)
    io.fmt:styled('notify', 'Wrote project config to: ')
    io.fmt:styled('path', self.config, '\n')
  end
end

function civ._build(base, cv, tgtnames)
  assert(cv.cfg.buildDir, 'must set buildDir')
  if base.clean or G.BOOTSTRAP then
    ix.rmRecursive(cv.cfg.buildDir)
  end
  ix.mkDirs(cv.cfg.buildDir)
  local out = cv:build(tgtnames)
  local f = io.fmt
  f:styled('notify', 'targets built', '\n')
  for _, tgtname in ipairs(tgtnames) do
    f:write(sfmt('  %s\n', tgtname))
  end
  return out
end

function civ._test(base, cv, tgtnames)
  local ordered = civ._build(base, cv, tgtnames)
  local ran = cv:test(tgtnames, ordered)
  local f = io.fmt
  f:styled('good', #ran..' tests passed:', '\n')
  for _, tgtname in ipairs(ran) do
    f:write'  '; f:styled('good', tgtname, '\n')
  end
  f:styled('notify', 'civ test: complete', '\n')
end


function civ.build:__call()
  civ._pre()
  info('build %q', self)
  local cv = core.Civ:load(self.config)
  return civ._build(self, cv, cv:expandAll(self))
end

function civ.test:__call()
  civ._pre()
  info('test %q', self)
  local cv = core.Civ:load(self.config)
  return civ._test(self, cv, cv:expandAll(self))
end

function civ.run:__call()
  civ._pre()
  local cmd = shim.popRaw(self) or {}
  info('run %q', cmd)
  assert(#self == 1, 'usage: civ run hub:tgtname')
  local cv = core.Civ:load(self.config)
  local tgtnames = cv:expandAll(self)
  assertf(#tgtnames == 1, 'must run a single target, expanded to: %q',
         tgtnames)
  local tgt = cv:target(tgtnames[1])
  local bin
  local getBin = function(p)
    if p:match'^bin/' then
      assertf(not bin, 'multiple bin outputs:\n%s\n%s', bin, p)
      bin = p
    end
  end
  for _, to in pairs(tgt:outPaths'')      do getBin(to) end
  for _, link in pairs(tgt.link or EMPTY) do getBin(link) end
  assertf(bin, 'no bin found in %s', tgt:tgtname())

  civ._build(self, cv, tgtnames)
  table.insert(cmd, 1, cv.cfg.buildDir..bin)
  info('running: %q', cmd)
  cmd.ENV = cv.ENV
  cmd.stdout = io.stdout
  return ix.sh(cmd)
end

function civ.install:__call()
  civ._pre()
  info('install %q', self)
  local cv = core.Civ:load(self.config)
  local tgtnames = cv:expandAll(self)
  local D = cv.cfg.installDir
  assert(D, 'must set config.installDir')
  if not shim.bool(self.force) and ix.exists(D) then
    io.fmt:styled('warn',
      sfmt('This will delete %s - continue (Y/N)?', D), ' ')
    local inp = io.read'l'
    if inp:sub(1,1):lower() ~= 'y' then
      io.fmt:styled('warn', sfmt('replied %q, exiting', inp), '\n')
      return
    end
  end
  io.fmt:styled('notify', 'installing in ')
  io.fmt:styled('path', D, '\n')
  civ._build(self, cv, tgtnames)
  ix.rmRecursive(cv.cfg.installDir)
  ix.cpRecursive(cv.cfg.buildDir, cv.cfg.installDir)
  io.fmt:styled('notify', 'Installed in '); io.fmt:styled('path', D, '\n')
  for _, tgtname in ipairs(tgtnames) do
    io.fmt:write(sfmt('  %s\n', tgtname))
  end
  io.fmt:styled('notify',
    'Add (something like) the following to your ~/.bashrc', '\n')
  local d = pth.toNonDir(D)
  io.fmt:styled('code', BASH_ADD:format(pth.toNonDir(d)), '\n')
end

if shim.isMain(civ) then civ:main(arg) end
return civ
