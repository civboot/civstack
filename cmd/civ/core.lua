local mty = require'metaty'

--- [*civ.core] contains types used by the civ build system.[{br}]
---
--- ["If you are just a user of civ this is likely not useful. This library is
---   useful primarily for those who want to extend civ and/or write their own
---   build/test macros.]
local M = mty.mod'civ.core'
local G = mty.G
G.MAIN = G.MAIN or M

local freeze = require'metaty.freeze'
local shim = require'shim'
local fmt = require'fmt'
local ds = require'ds'
local dload = require'ds.load'
local Iter = require'ds.Iter'
local log = require'ds.log'
local pth = require'ds.path'
local pod = require'pod'
local luk = require'luk'
local lson = require'lson'
local ix = require'civix'
local File = require'lines.File'
local T = require'civtest'

local forceset = freeze.forceset
local info = log.info
local sfmt = string.format
local getmt, setmt = getmetatable, setmetatable
local push, pop = ds.push, table.remove
local assertf = fmt.assertf
local Epoch = mty.from'ds.time Epoch'
local pretty = mty.from'fmt pretty'

local EMPTY = {}
local MOD_INVALID = '[^%w_.]+' -- lua mod name.

M.DIR = pth.canonical( (pth.last(pth.last(ds.srcdir() or ''))) )
M.LIB_EXT = '.so'
M.DEFAULT_CONFIG = '.civconfig.luk'
M.BASE_CONFIG = os.getenv'CIV_BASE' or pth.concat{pth.home(), '.config/civ.luk'}
M.DEFAULT_OUT = '.civ/'

local CIV_TGTNAME = 'civ:cmd/civ#civ'


-- #####################
-- # Target
-- Creating and processing target objects.

local function hubpathSplit(hp)
  local hub, pkgpath = hp:match'^([%w_]+):(.*)$'
  assertf(hub, 'invalid hubpath %q', hp)
  return hub, pkgpath
end

local function pkgnameValidate(pn) --> pkgname, hub, pkgpath
  assertf(not pn:find'//+',  '%q: cannot contain multiple /', pn)
  assertf(pn:sub(-1) ~= '/', '%q: cannot end with /', pn)
  local hub, pkgpath = pn:match'^([%w_]+):([%w_/]*)$'
  assertf(hub, 'invalid pkgname %q', pn)
  return pn, hub, pkgpath
end

local function pkgnameSplit(pn) --> hub, pkgpath
  local _, hub, pkgpath = pkgnameValidate(pn)
  return hub, pkgpath
end

local function tgtnameSplit(str) --> pkgname, name
  if str:find'#' then
    local pkgname, name = str:match'^(.*)#([%w_]+)$'
    if not pkgname then error(sfmt('invalid target name: %q', str)) end
    return pkgnameValidate(pkgname), name
  end
  local hub, pkgpath = pkgnameSplit(str)
  if pkgpath == '' then return hub..':', hub end
  local name = select(2, pth.last(pkgpath))
  assertf(not name:find'[^%w_]', 'invalid name: %q', str)
  return sfmt('%s:%s', hub, pkgpath), name
end
M.tgtnameSplit = tgtnameSplit

function M.tgtname(tgtname)
  local pkgname, name = tgtnameSplit(tgtname)
  return sfmt('%s#%s', pkgname, name)
end

--- Represents a pkgname.target parsed from a string
M.TargetName = mty'TargetName' {
  'pkgname [string]',
  'name [string]',
}
function M.TargetName:__tostring()
  return sfmt('%s#%s', self.pkgname, self.name)
end
M.TargetName.parse = function(T, tgtname)
  local pn, name = tgtnameSplit(tgtname)
  return T{ pkgname=pn, name=name }
end

--- A build target, the result of compiling a package.
M.Target = freeze.freezy(pod(mty'Target' {
  'pkgname [str]: name of package target is in.',
  'name [str]: the name of the target.',
  'kind [str]: the kind of target: build, test, executable',
  'dir [str]: directory of src files',
  'src {key: str}: list of input source files (strings).',
  'extra [builtin]: arbitrary value, used by run command',
  'dep {str}: list of input Target objects (dependencies).',
  'api [table]: the lang-specific exported import paths.',
 [[out [table]: POD table output segregated by language.[+
     * t: PoD in a k/v table, can be used to configure downstream targets.
     * data: list of raw files.
     * include: header file paths for native code (C/iA).
     * lib: dynamic library files (i.e. libfoo.so)
     * bin: executable binaries
     * lua: lua files
 ] ]],
  'link {str: str}: link outputs from -> to',
  'tag [table]: arbitrary attributes like test, testonly, etc.',
  'run [str]: executable script which performs the operation kind.',
  'mtime [ds.time.Epoch]: modified time of target and deps',
  'id     [int]: id of this target. Populated for Worker.',
  'depIds {int}: list of dependency target ids. Populated for Worker.',
}))
getmetatable(M.Target).__call = function(T, t)
  if type(t.src) == 'string' then t.src = {t.src} end
  if type(t.dep) == 'string' then t.dep = {t.dep} end
  t.dep = t.dep or {}
  t.tag = t.tag or {}
  if t.tag.builder ~= 'bootstrap' and
    not ds.indexOf(t.dep, CIV_TGTNAME) then
    push(t.dep, CIV_TGTNAME)
  end
  for i=1,#t.dep do t.dep[i] = M.tgtname(t.dep[i]) end
  return mty.construct(T, t)
end
function M.Target:tgtname()
  return sfmt('%s#%s', self.pkgname, self.name)
end

--- Return a copy of the target with ids used instead of deps.
local function targetWithIds(tgt, ids)
  tgt = ds.copy(tgt)
  local tgtname = tgt:tgtname()
  tgt.id = assertf(ids[tgtname], '%q target not found', tgtname)
  tgt.depIds = {}
  for i, dep in ipairs(tgt.dep) do
    tgt.depIds[i] = assertf(ids[dep], '%q target not found', dep)
  end
  return tgt
end

local function outPaths(to, dir, out)
  for k, o in pairs(out) do
    if type(o) == 'table' then
      assertf(type(k) == 'string', 'tables must have string key: %q', k)
      outPaths(to, pth.toDir(dir..k), o)
    elseif type(k) == 'number' then
      push(to, dir..o)
    else
      to[k] = dir..o
    end
  end
end

--- Fill [$to] with output path strings.
function M.Target:outPaths(dir) -- {path}
  local to = {}
  outPaths(to, dir or '', self.out)
  return to
end

-- #####################
-- # Civ
-- The Civ object and it's configuration.

--- A hub configuration
M.Hub = mty'Hub' {
  'name [string]: the name of the hub', name='this',
}

--- The user configuration, typically at ./.civconfig.lua
M.Cfg = mty'Cfg' {
  'path [string]: the path to this config file.',
  'basePath [string]: the base path of this config file.',
 [[host_os [string]: the operating system of this computer.'
    Typically equal to civix.OS]],
  'hubs {string: string}: table of hubname -> /absolute/dir/path',
  'buildDir [string]: directory to put build/test files.',
  'installDir [string]: directory to install files to.',
  'builder [BuilderCfg]: builder settings',
}
M.Cfg.__newindex = nil
getmetatable(M.Cfg).__call = function(T, self)
  for h, d in pairs(self.hubs) do self.hubs[h] = pth.abs(d) end
  self.builder = M.BuilderCfg(self.builder or {})
  return mty.construct(T, self)
end

--- Cfg.builder settings
M.BuilderCfg = mty'BuilderCfg' {
 [[direct [bool]: prefer building directly
   (running build scripts w/ dofile).
 ]],
}
M.BuilderCfg.__newindex = nil
getmetatable(M.BuilderCfg).__index = nil
getmetatable(M.BuilderCfg).__call = mty.constructUnchecked

local CFG_ERROR = 'No config exists at %s\nRecommended: ./bootstrap.lua init'
M.Cfg.load = function(T, path)
  local base, path = M.BASE_CONFIG, path or M.DEFAULT_CONFIG
  assertf(ix.exists(base), CFG_ERROR, base)
  assertf(ix.exists(path), CFG_ERROR, path)
  info('basePath=%q', base)
  local ok, cfg = dload(base, {HOME=pth.home()}); assert(ok, cfg)
  do
    info('cfgPath=%q', path)
    local ok, t = dload(path, {HOME=pth.home()});   assert(ok, t)
    ds.merge(cfg, t)
  end
  cfg.basePath, cfg.path = base, path
  return M.Cfg(cfg)
end

--- Holds top-level data structures and algorithms for
--- processing civ build graphs (pkgname graphs).
M.Civ = mty'Civ' {
  'cfg [Cfg]: the user config',
  'thisHub [string]', 'thisPkg [string]',
  'hubs: table of hub -> dir (cfg.hubs)',
  'pkgs: table of pkgname -> pkg',
  'luk [luk.Luk]',
  'cycle',
  'worker [civ.Worker]: direct worker',
  'lastTargets {tgtname: Target}: the last targets',
  'ENV [table]: environment for running workers',
}
getmetatable(M.Civ).__call = function(T, self)
  local cfg = assert(self.cfg, 'must set cfg')
  local B = assert(cfg.buildDir, 'must set cfg.buildDir')
  B = pth.abs(B); cfg.buildDir = B
  self.hubs = cfg.hubs
  self.pkgs = self.pkgs or {}
  self.lastTargets = self.lastTargets or {}

  if not self.luk then
    local lukEnv = ds.update(ds.rawcopy(luk.ENV), {
      Target = M.Target,
    })
    lukEnv.__index = lukEnv
    self.luk  = luk.Luk{envMeta=lukEnv}
  end
  self.luk.envMeta.CFG = cfg
  self.cycle = self.cycle or {}
  self.ENV = ds.update({
    'HOME='..pth.home(),
    'PATH='..os.getenv'PATH',
    'LD_LIBRARY_PATH='..B..'lib/',
    'LUA_PATH='       ..B..'lua/?.lua',
    'LUA_CPATH='      ..B..'lib/lib?.so',
    'LUA_SETUP='      ..LUA_SETUP,
    'LOGLEVEL='       ..G.LOGLEVEL,
  }, self.ENV or {})
  if ix.exists'HUB.luk' then
    local hdir = pth.dir(pth.abs'HUB.luk')
    info('local hub %s', hdir)
    local ok, h = dload'HUB.luk'; assert(ok, h)
    self.thisHub = M.Hub(h).name
    self.hubs[self.thisHub] = hdir
  end
  self = mty.construct(T, self)
  self.luk.pathFn = function(p) return self:abspath(p) end
  return self
end

function M.Civ.load(T, cfgPath)
  info('Civ:load(cfgPath=%q)', cfgPath)
  if cfgPath then cfgPath = pth.abs(cfgPath) end
  local self = {}
  local hpath, hdir, cwd = ix.findBack'HUB.luk'
  if hpath then
    cwd, hdir = pth.cwd(), pth.dir(hpath)
    self.thisPkg = pth.toNonDir(pth.relative(hdir, cwd))
    info('thisPkg=%q', self.thisPkg)
    pth.cd(hdir)
  end
  self.cfg = M.Cfg:load(cfgPath)
  return T(self)
end

local function tmatch(tgt, pat)
  if pat:find'[^%w_]' then return tgt:match(pat) end
  return tgt == pat and tgt
end

--- Expand a pattern to it's targets.
--- This has the side effect of loading all related packages.
function M.Civ:expand(pat) --> targets
  if pat:sub(1,1) == ':' then pat = self.thisHub..pat end
  if not pat:find':' then
    pat = sfmt('%s:%s%s', self.thisHub, pth.toDir(self.thisPkg), pat)
  end
  local hub, pkgpat = pat:match'^([%w_]+):(.*)$'
  assertf(hub, 'invalid pkg pat: %q', pat)
  local hubdir = assertf(self.hubs[hub], 'unknown hub: %s', hub)
  local pkgdir, tgtpat = pkgpat:match'([^#]*)(#?.*)'
  local pkgroot, pkgpat = pkgdir:match'([%w_/]*)/?(.*)'
  pkgpat, pkgroot = pkgpat or '', pkgroot or ''
  local pkgnames = {}
  local hublist = pth(hubdir)
  local w, dirs; if pkgpat == '' then
    -- no regex in pkgdir, only look in root directory
    dirs = Iter:of{[pth.concat{hubdir, pkgroot}]='dir'}
  else
    -- walk the directory
    w = ix.Walk{pth.concat{hubdir, pkgroot}}
    dirs = w
  end
  for path, ftype in dirs do
    if w and ftype=='dir' and
        select(2, pth.last(path)):match'^%.' then
      log.info('skipping dir %q', path)
      w:skip()
      goto continue;
    end
    if ftype == 'dir' and path:match(pkgpat)
        and ix.exists(pth.concat{path, 'PKG.luk'}) then
      path = pth.rmleft(pth(path), hublist)
      push(pkgnames, sfmt('%s:%s', hub, pth.toNonDir(pth.concat(path))))
    end
    ::continue::
  end
  self:loadPkgs(pkgnames)
  local tgtnames = {}
  if tgtpat == '' then 
    for _, pkg in ipairs(pkgnames) do push(tgtnames, M.tgtname(pkg)) end
  else
    tgtpat = tgtpat:sub(2) -- remove '#'
    if tgtpat == '' then tgtpat = '.' end
    for _, pkgname in ipairs(pkgnames) do
      local pkg = self.pkgs[pkgname]
      for _, tgt in pairs(pkg) do
        if mty.ty(tgt) ~= M.Target then goto continue end
        if tmatch(tgt.name, tgtpat) then push(tgtnames, tgt:tgtname()) end
        ::continue::
      end
    end
  end
  tgtnames = ds.sort(tgtnames)
  assertf(#tgtnames > 0, '%q did not resolve to any targets', pat)
  return tgtnames
end

--- Given a list of hub:foo/.*#.* patterns, expand them.
function M.Civ:expandAll(tgtpats) --> tgtnames
  local tgtnames = {}
  for _, tgtpat in ipairs(tgtpats) do
    ds.extend(tgtnames, self:expand(tgtpat))
  end
  return tgtnames
end

function M.Civ:getPkgname(dep) --> pkgname
  return dep:match'^([%w_]+:[%w_/]*)'
end

--- Given a pkg:path/to/file convert to an abspath (used for Luk).
function M.Civ:abspath(pkgpath) --> abspath
  local hub, p = pkgpath:match'([%w_]+):(.*)'
  if not hub then error(pkgpath..' must start with "hub:"') end
  local apath = pth.concat{self.hubs[hub] or error('unknown hub: '..hub),
                           p}
  return apath
end

--- Get pkgname's full directory.
function M.Civ:pkgDir(pkgname) --> dir/
  local hub, p = pkgname:match'^([%w_]+):([%w_/]*)$'
  if not hub then error('invalid pkgname: '..pkgname) end
  p = pth.concat{self.hubs[hub] or error('unknown hub: '..hub), p}
  return p == '' and p or pth.toDir(p)
end

function M.Civ:tgtDir(tgt) --> dir/
  return self:pkgDir(assert(tgt.pkgname))
end

function M.Civ:target(tgt) --> Target?, errmsg
  if mty.ty(tgt) == M.Target   then return tgt
  elseif type(tgt) == 'string' then
    tgt = M.TargetName:parse(tgt)
  end
  local pkg = self.pkgs[tgt.pkgname]
  if not pkg then return nil, tgt.pkgname..': pkg not found' end
  local t = pkg[tgt.name]; if t then return t end
  return nil, sfmt('%s: target %q not found in pkg', tgt, tgt.name)
end

--- Get the "modtime" of the whole target.
function M.Civ:tgtMod(tgt) --> ds.time.Epoch
  if tgt.mtime then return tgt.mtime end
  local mtime = Epoch(-1, 0)
  for _, src in pairs(tgt.src or EMPTY) do
    local ftime = Epoch(ix.stat(tgt.dir..src):modified())
    mtime = ds.max(mtime, ftime)
  end
  for _, dep in pairs(tgt.dep or EMPTY) do
    mtime = ds.max(mtime, self:target(dep).mtime)
  end
  assert(mtime.s > 0, 'tgt contained no src or dep')
  forceset(tgt, 'mtime', mtime)
  return mtime
end

function M.Civ:loadPkg(pkgname)
  pkgnameValidate(pkgname)
  local pkg, err = self.pkgs[pkgname]; if pkg then return pkg end
  luk._checkCycle(self.cycle, pkgname)
  info('loading pkg %q', pkgname)
  push(self.cycle, pkgname); self.cycle[pkgname] = 1

  local pkgfile = pkgname
  if not pkgname:sub(-1) ~= ':' then pkgfile = pkgfile..'/' end
  pkgfile = pkgfile..'PKG.luk'
  pkg = assert(self.luk:import(pkgfile))
  assertf(mty.ty(pkg) == luk.Table,
    '%q did not return a table', pkgfile)
  forceset(pkg, 'pkgname', pkgname)
  for k, tgt in pairs(pkg) do -- validation
    assertf(type(k) == 'string',
      '%s.%q: must have only string keys', pkgname, k)
    assertf(not k:find'[^%w_]',
      '%s.%q: keys must be of [%w_]', pkgname, k)
    assertf(type(tgt) == 'string' or mty.ty(tgt) == M.Target,
      '%s.%s is not a string or Target: %q', pkgname, k, tgt)
  end
  for k, tgt in pairs(pkg) do -- load deps
    if mty.ty(tgt) == M.Target then
      forceset(tgt, 'pkgname', pkgname)
      forceset(tgt, 'name',    k)
      forceset(tgt, 'dir',     self:abspath(pkgname)..'/')
      for _, dep in ipairs(tgt.dep) do
        local dty = mty.ty(dep)
        assertf(dty == 'string',
          'target %s has invalid dep type %q', tgt:tgtname(), dty)
        local pkgnameDep = self:getPkgname(dep)
        if pkgnameDep ~= pkgname then
          self:loadPkg(pkgnameDep)
        end
      end
    end
  end

  assert(pop(self.cycle) == pkgname); self.cycle[pkgname] = nil
  self.pkgs[pkgname] = pkg
  push(self.pkgs, pkg)
  info('pkg loaded: %q', pkgname)
  return pkg
end

--- Load the pkgs and update self.pkgs with values.
function M.Civ:loadPkgs(pkgnames)
  for _, pn in ipairs(pkgnames) do self:loadPkg(pn) end
end

--- recursively find all deps
function M.Civ:targetDepMap(tgts, depMap)
  for i, tgtname in ipairs(tgts) do
    assertf(type(tgtname) == 'string')
    if not depMap[tgtname] then
      local tgt = assertf(self:target(tgtname), 'unknown target %s', tgtname)
      depMap[tgtname] = tgt.dep or EMPTY
      self:targetDepMap(tgt.dep or EMPTY, depMap)
    end
  end
end

function M.Civ:run(stage, tgtname, script, ids)
  local cmd = {
    script,
    '--config='..self.cfg.path,
    sfmt('--tgtsDb=%stargets.json', self.cfg.buildDir),
    ENV=self.ENV, rc = true, stdout = io.stdout,
  }
  for _, id in ipairs(ids) do push(cmd, tostring(id)) end
  info('%s cmd: %q', stage, cmd)
  local out,err,s = ix.sh(cmd)
  if s:rc() ~= 0 then
    error(ds.Error{msg=sfmt('%s failed with rc=%s', tgtname, s:rc())})
  end
end

function M.Civ:prebuild(prevTgts, tgts) --> toBuild, ordered
  info('Civ.prebuild: %q', tgts)
  tgts = ds.icopy(tgts)
  for k in pairs(prevTgts) do push(tgts, k) end -- also build all prev targets

  for _, tgtname in ipairs(tgts) do self:loadPkg(tgtnameSplit(tgtname)) end

  local depMap = {}; self:targetDepMap(tgts, depMap)
  local ordered, cycle = ds.dagSort(tgts, depMap)
  assertf(not cycle, 'import cycle detected: %q', cycle)

  local toBuild = {}
  for id, tgtname in ipairs(ordered) do
    local tgt = self:target(tgtname)
    tgtname = tgt:tgtname()
    if not G.BOOTSTRAP then self:tgtMod(tgt) end
    if tgt.kind ~= 'build' then
      info('target not kind=build: %q', tgtname)
    elseif not G.BOOTSTRAP and mty.eq(tgt, prevTgts[tgtname]) then
      info('target from cache: %q (%q)', tgtname, tgt.mtime)
    else
      info('target being built: %q', tgtname)
      if not G.BOOTSTRAP then
        io.fmt(require'lines.diff'.Diff(
          pretty(prevTgts[tgtname]), pretty(tgt)))
      end
      toBuild[tgtname] = true
    end
  end

  return toBuild, ordered
end

--- Build the target.
function M.Civ:build(tgts) --> ordered, tgtsCache
  local tgtsDbPath = self.cfg.buildDir..'targets.json'
  local prevTgts = ix.exists(tgtsDbPath) and M.loadPrevTargets(tgtsDbPath) or {}
  local toBuild, ordered = self:prebuild(prevTgts, tgts)
  info('actually building %q', toBuild)
  info('ordered %q', ordered)

  -- For creating and running build scripts inline
  local main = G.MAIN
  G.MAIN = nil
  local worker = require'civ.Worker' {
    ids = {}, cfg = self.cfg, tgtsCache = {}, tgtsDb = {},
  }:set()

  local ids = {} -- map tgtname -> id
  local cfgArg    = '--config='..assert(self.cfg.path)
  local tgtsDbArg = '--tgtsDb='..tgtsDbPath
  ix.mkDirs(self.cfg.buildDir..'bin/')
  local tgtFile = assert(File { path = tgtsDbPath, mode = 'w' })
  for id, tgtname in ipairs(ordered) do
    local tgt = self:target(tgtname)
    tgtname = tgt:tgtname(); ids[tgtname] = id
    local tgt = targetWithIds(tgt, ids)
    push(worker.tgtsCache, tgt) -- for inline
    tgtFile:write(lson.json(tgt)); tgtFile:write'\n'
    tgtFile:flush()
    if not toBuild[tgtname] then
      goto skip
    end
    local prev = prevTgts[tgtname] if prev then
      info('removing previous %q', tgtname)
      for _, out in pairs(prev:outPaths(self.cfg.buildDir)) do
        assert(ix.rm(out))
      end
      for _, ln in pairs(prev.link or EMPTY) do
        ln = self.cfg.buildDir..ln
        assert(ix.rm(ln))
      end
    end
    local hub, bpath = hubpathSplit(tgt.run)
    local script = self.hubs[hub]..bpath
    if tgt.tag.builder == 'bootstrap'
        or (tgt.tag.builder == 'direct' and self.cfg.builder.direct) then
      -- build directly in-process: script must have no deps outside of civ.
      ds.clear(worker.ids); worker.ids[1] = id
      info('build direct: %q', script)
      dofile(script); G.MAIN = nil
    else -- build in a separate process
      assertf(not G.BOOTSTRAP, '%s not tagged as bootstrap', tgtname)
      info('build in worker: %q', script)
      self:run('build', tgtname, script, {id})
    end
    ::skip::
  end
  worker:close()
  G.MAIN = main
  return ordered, worker.tgtsCache
end

--- Test the targets.
function M.Civ:test(tgtnames, ordered, tgtsCache)
  local tgtId = {}
  for i, tgtname in ipairs(ordered) do tgtId[tgtname] = i end
  local worker; if G.BOOTSTRAP then
    worker = require'civ.Worker' {
      ids = {}, cfg = self.cfg, tgtsCache = tgtsCache, tgtsDb = {},
    }:set()
  end
  local main = G.MAIN
  G.MAIN = nil
  local ran = {}
  for _, tgtname in ipairs(tgtnames) do
    info('Civ:test %q', tgtname)
    local tgt = assert(self:target(tgtname))
    if tgt.kind ~= 'test' then goto continue end
    local id = assert(tgtId[tgt:tgtname()])
    local hub, bpath = hubpathSplit(tgt.run)
    local script = self.hubs[hub]..bpath
    if G.BOOTSTRAP then
      ds.clear(worker.ids); worker.ids[1] = id
      info('test direct: %q', script)
      dofile(script); G.MAIN = nil
    else
      self:run('test', tgtname, script, {id})
    end
    push(ran, tgtname)
    ::continue::
  end
  G.MAIN = main
  info'Civ:test complete'
  return ran
end

function M.loadPrevTargets(jsonPath)
  local tgts = {}
  for line in io.lines(jsonPath) do
    local tgt = lson.decode(line, M.Target)
    local tgtname = tgt:tgtname()
    assertf(not tgts[tgtname], 'duplicate tgtname %q', tgtname)
    tgt.id, tgt.depIds = nil, nil
    tgts[tgtname] = tgt
  end
  return tgts
end

return M
