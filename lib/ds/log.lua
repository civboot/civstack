local mty = require'metaty'

--- Simple logging library, set i.e. LOGLEVEL=INFO to enable logging.
---
--- This module has the functions [$trace info warn err crit] with the signature:
--- [$$function(fmt, ... [, data])]$ [+
--- * the ... are the format args which behave like [$fmt.format] (aka [$%q]
---   formats tables/etc).
--- * data is optional arbitrary data that can be serialized/formatted.
--- ]
--- To enable logging the user should set a global (or env var) LOGLEVEL
--- to oneof: C/CRIT/1 E/ERROR/2 W/WARN/3 I/INFO/4 T/TRACE/5
---
---
--- This module also sets (if not already set) the global LOGFN to [$ds.logFn]
--- which logs to stderr. This fn is called with signature
--- [$function(level, srcloc, fmt, ...)]
local M = mty.mod'ds.log'
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local G = mty.G

local push, sfmt = table.insert, string.format
local Fmt = fmt.Fmt
local io = io

--- It is intended that this be overriden with a better
--- time function.
function M._time() return os.date():match'%d%d:%d%d:%d%d' end

local LEVEL = ds.Checked{
  SLIENT=0, [0]='SILENT',
  C=1, CRIT=1,
  E=2, ERROR=2,
  W=3, WARN=3,
  I=4, INFO=4,
  T=5, TRACE=5,
  'CRIT', 'ERROR', 'WARN', 'INFO', 'TRACE'
}; M.LEVEL = LEVEL

M.CRIT, M.ERROR, M.WARN = LEVEL.CRIT, LEVEL.ERROR, LEVEL.WARN
M.INFO, M.TRACE = LEVEL.INFO, LEVEL.TRACE

local STYLES = {
  [M.WARN]  = 'warn',
  [M.ERROR] = 'error',
  [M.INFO]  = 'info',
}

local SHORT = ds.Checked{'C', 'E', 'W', 'I', 'T'}
--- Get the current log-level integer.
function M.levelInt(lvl) --> int
  local lvl = tonumber(lvl) or M.LEVEL[lvl]
  return M.LEVEL[lvl] and lvl or error('invalid lvl: '..tostring(lvl))
end
--- Get the current log-level string.
function M.levelStr(lvl) return M.LEVEL[M.levelInt(lvl)] end

--- Set the global logging level (default=os.getenv'LOGLEVEL')
function M.setLevel(lvl)
  G.LOGLEVEL = M.levelInt(lvl or os.getenv'LOGLEVEL' or 0)
end
M.setLevel(G.LOGLEVEL)

function M.logFn(lvl, loc, fmt, ...)
  if LOGLEVEL < lvl then return end
  local f, args, nargs = io.fmt, {...}, select('#', ...)
  f:styled(STYLES[lvl], sfmt('%s %s %s',
    SHORT[lvl], M._time(), loc), ': ')
  f:level(1)
  local i = f:formatArgs(fmt, args)
  if i == (nargs - 1) then f:write' '; f(args[i + 1]) -- data
  elseif i ~= nargs then error('invalid #args: '..nargs..' %fmts='..i) end
  f:level(-1); f:write'\n'; f:flush()
end
G.LOGFN = G.LOGFN or M.logFn

local function _log(lvl, fmt, ...)
  LOGFN(lvl, ds.shortloc(2), fmt, ...)
end

--- Log at level CRIT.
function M.crit(...)  if LOGLEVEL >= 1 then _log(1, ...) end end
--- Log at level ERROR.
function M.err(...)   if LOGLEVEL >= 2 then _log(2, ...) end end
--- Log at level WARN.
function M.warn(...)  if LOGLEVEL >= 3 then _log(3, ...) end end
--- Log at level INFO.
function M.info(...)  if LOGLEVEL >= 4 then _log(4, ...) end end
--- Log at level TRACE.
function M.trace(...) if LOGLEVEL >= 5 then _log(5, ...) end end

--- used in tests
M.LogTable = mty.record'LogTable'{
  'tee [fn(...)] call calls will also call tee',
}
function M.LogTable:__fmt(f)
  f:write'LogTable'; f:list(self)
end
M.LogTable.__eq = ds.ieq
function M.LogTable:__call(...)
  if self.tee then self.tee(...) end
  push(self, {...})
end

return M
