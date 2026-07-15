local mty = require'metaty'
local G = mty.G

local shim = require'shim'
local Iter = require'ds.Iter'
local fmt = require'fmt'
local ds = require'ds'
local dload = require'ds.load'
local info = require'ds.log'.info
local pth = require'ds.path'
local lson = require'lson'
local fd = require'fd'
local ix = require'civix'
local core = require'civ.core'
local File = require'lines.File'
local forceLoadIdx = require'lines.futils'.forceLoadIdx

local sfmt = string.format
local push, pop = ds.push, table.remove
local EMPTY = {}

local SINGLETON -- single instance

--- [*civ.Worker] encapsulates a single civ worker, i.e. the
--- process which actually performs build/test actions.[{br}]
---
--- ["If you are just a user of civ this is likely not useful. This library is
---   useful primarily for those who want to extend civ and/or write their own
---   build/test macros.]
local Worker = mty.recordMod'civ.Worker' {
  'ids {int}: the target ids to work on.',
  'cfg [civ.core.Cfg]',
  'tgtsDb [lines.File]: indexed line-file of targets by id',
  'tgtsCache [id -> Target]: already loaded targets',
}
getmetatable(Worker).__call = function(T, self)
  assert(self.ids,    'must set ids')
  assert(self.cfg,    'must set cfg')
  assert(self.tgtsDb, 'must set tgtsDb')
  self.tgtsCache = self.tgtsCache or {}
  self = mty.construct(T, self)
  return self
end

--- Usage: [$worker = Worker:get()]
Worker.get = function(T, args)
  if SINGLETON then return SINGLETON end
  shim.runSetup()
  args = args or G.arg
  args = shim.parse(args)
  info('parsing Worker from args %q', args)
  local ids = {}
  local ids = Iter:ofList(args):mapV(math.tointeger):to()
  assert(#ids > 0, 'must specify at least one id')
  SINGLETON = T {
    ids = ids,
    cfg = core.Cfg:load(assert(args.config, '--config not set')),
    tgtsDb = assert(File {
      path = assert(args.tgtsDb, '--tgtsDb not set'),
      mode = 'r',
      loadIdxFn = forceLoadIdx,
    }),
  }
  return SINGLETON
end

function Worker:target(id) --> Target
  local tgt = self.tgtsCache[id]; if tgt then return tgt end
  local tgtLson = self.tgtsDb:get(id)
  if not tgtLson or tgtLson=='' then error('no target id '..id) end
  tgt = lson.decode(tgtLson, core.Target)
  self.tgtsCache[id] = tgt
  return tgt
end

--- Copy output files from [$$tgt.out[outKey]]$.
function Worker:copyOut(tgt)
  local out = tgt:outPaths(self.cfg.buildDir)
  for from, to in pairs(out) do
    if type(from) == 'string' then
      local from = tgt.dir..from
      fmt.assertf(not ix.exists(to), 'to %q already exists', to)
      fmt.assertf(ix.exists(from), 'src %q does not exists', from)
      ix.forceCp(from, to)
    end
  end
  return true
end

function Worker:link(tgt)
  local O = self.cfg.buildDir
  for from, to in pairs(tgt.link or EMPTY) do
    local f, t = O..from, O..to
    info('ln %q -> %q: %q', f, t, pth.relative(t, f))
    ix.sh{'ln', '-s', pth.relative(t, f), t}
    if select(2, pth.last(pth.dir(t))) == 'bin/' then
      info('chmod a+x', f)
      local f = assert(io.open(f))
      ix.chmod(f, ix.stat(f):mode() | tonumber('111', 8))
      f:close()
    end
  end
end

--- Make self the singleton (future calls to Worker.get will return)
function Worker:set() SINGLETON = self; return self end

--- Remove this as singleton.
function Worker:close() SINGLETON = nil             end

return Worker