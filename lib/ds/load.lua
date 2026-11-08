local mty = require'metaty'

--- load lua modules with custom or default environment in a sandboxed
--- environment. This is extremely useful for configurations written in lua or
--- writing your own config-like language.
---
--- The default environment (ds.load.ENV) has safe default functions which
--- cannot access state and missing unsafe functions like getmetatable or the
--- debug module.
---
--- [{:h4}loading]
--- To perform the load, call this module with:
--- [$$
---   (path, env={}, envMeta=ds.load.ENV) -> ok, result
--- ]$
--- inputs: [+
--- * path: path to load (lua-syntax file).
--- * env: global environment.
--- * envMeta: metatable of global environment. If env
---   already has a metatable this is ignored.
--- ]
---
--- outputs: [+
--- * ok: boolean to indicate load success or failure of script.
--- * result: result or loading or ds.Error.
--- ]
---
--- Throws an error if the path is not valid lua code.
local M = mty.mod'ds.load'

local ds = require'ds'
local log = require'ds.log'
local fmt = require'fmt'

local getmt, setmt = getmetatable, setmetatable
local sfmt = string.format

--- Default environment for sandboxed loading.
M.ENV = {
  __name = 'ds.load.ENV',
  format=fmt.format,
  insert=table.insert, push=ds.push,
  sort=ds.sort,
  extend=ds.extend, update=ds.update, merge=ds.merge,
  concat=table.concat,
  tostring=tostring, tointeger=math.tointeger,
  s=ds.simplestr,
  tonumber=tonumber,
  pairs=pairs,   ipairs=ipairs,
  isEmpty = ds.isEmpty,
  error=error,   assert=fmt.assertf,

  record = mty.record, enum = mty.enum,
  type = type, ty = mty.ty,

  warn = log.warn, info = log.info, trace = log.trace,
}; M.ENV.__index = M.ENV
setmetatable(M.ENV, {
  __index = function(_, k)
    error(sfmt('%s: not a defined global', k))
  end,
})

--- Similar to lua's [$loadfile] but follows conventions of [$ds.load(...)].
--- Unlike loadfile, this throws an error if the path doesn't parse.
function M.loadfile(path, env, envMeta) --> fn?, ds.Error?
  env = env or {}
  if not getmt(env) then setmt(env, envMeta or M.ENV) end
  local fn, err = loadfile(path, nil, env)
  if not fn then
    return nil, ds.Error { msg = err, traceback = { path }, }
  end
  return fn
end

getmetatable(M).__call = function(_, path, env, envMeta) --> ok, result
  local fn, err = M.loadfile(path, env, envMeta)
  if not fn then return false, err end
  return ds.try(fn)
end
return M