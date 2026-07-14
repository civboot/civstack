local G = G or _G
--- pod: plain old data
local M = G.mod and mod'pod' or setmetatable({}, {})

local mty = require'metaty'
local ds = require'ds'
local push = table.insert
local mtype = math.type
local sfmt = string.format
local getmt = getmetatable
local info = require'ds.log'.info

local assertf = mty.from'fmt  assertf'
local CONCRETE, BUILTIN = mty.CONCRETE, mty.BUILTIN
local ty = mty.ty

local lib, ser, deser
if not G.NOLIB then
  lib = require'pod.lib'
  ser, deser = lib.ser, lib.deser

  --- serialize the value (without calling toPod on it)
  M.serRaw = ser--(value) --> string
  
  --- deserialize the value (without calling fromPod on it)
  M.deserRaw = deser--(string) --> value
end

--- Pod: configuration for converting values to/from POD.
M.Pod = mty'Pod'{
  'fieldIds [boolean]: if true use the fieldIds when possible',
  'mtPodFn  [(mt) -> boolean]: function to classify if mt is pod',
    mtPodFn = function() end,
  'enumIds [boolean]: if true use enum id variants, else name variants',
}
local Pod = M.Pod
Pod.DEFAULT = Pod{}

local function _isPrim(v, isPrimFn) --> isPrim, notPrimV
  local mt = type(v); if mt ~= 'table' then return BUILTIN[mt] end
  mt = ty(v);         if mt ~= 'table' then return isPrimFn(v), v end
  for k, v in pairs(v) do
    if not _isPrim(k, isPrimFn) then return false, k end
    if not _isPrim(v, isPrimFn) then return false, v end
  end
  return true
end

local isPrim
--- Return true if the value is primitive "plain old data" that can be decrypted
--- without type information.
---
--- A primitive is defined as a concrete type (bool, num, string) or a
--- metatable-less table containing only primitive types.
---
--- The [$isPrimFn] fn takes [$v] and should return true if it is primitive pod.
function M.isPrim(v, isPrimFn) --> isPrim, whyNotTy
  return _isPrim(v, isPrimFn or ds.retFalse)
end
isPrim = M.isPrim

--- A type who's sole job is converting values to/from POD.
M.Podder = mty'Podder' {
  'name [string]',
  '__toPod   [(self, pset, v) -> p]',
  '__fromPod [(self, pset, p) -> v]',
}
function M.Podder:__tostring() return self.name end
function M.isPodder(P) --> isPodder, whyNot?
  if not mty.callable(P.__toPod) and mty.callable(P.__fromPod) then
    return false, 'must implement __toPod and __fromPod'
  end
  if not G.MOD_NAMES[P] then return false, 'must be in MOD_NAMES' end
  return true
end

local function makePrimPodder(ty)
  local expected = 'expected '..ty
  local f = function(self, pod, v)
    if v == nil then return end
    if type(v) ~= ty then error(sfmt(
      'expected %s got %s', ty, type(v))
    )end
    return v
  end
  return M.Podder{name=ty, __toPod=f, __fromPod=f}
end
local function tpInt(self, pod, i)
  if i == nil then return end
  if mtype(i) ~= 'integer' then error('expected integer got '..type(i)) end
  return i
end

M.BUILTIN_PODDER = {
  ['nil'] = makePrimPodder'nil',
  boolean = makePrimPodder'boolean',
  number = makePrimPodder'number',
  string = makePrimPodder'string',
  table = makePrimPodder'table',
  integer = M.Podder{
    name='integer', __toPod=tpInt, __fromPod=tpInt,
  },
}
local BUILTIN_PODDER = M.BUILTIN_PODDER
function M.tableToPod(T, pod, t)
  if type(t) ~= 'table' then error('expected table got '..type(t)) end
  local ok, whyNot = isPrim(t, pod.mtPodFn)
  if ok then return t end
  error(sfmt('table contains value of type %q that is not primitive pod',
    mty.fullname(whyNot)))
end

BUILTIN_PODDER.table.__toPod = M.tableToPod
BUILTIN_PODDER.int = BUILTIN_PODDER.integer
BUILTIN_PODDER.str = BUILTIN_PODDER.string

for k, p in pairs(BUILTIN_PODDER) do M[k] = p end
M.nil_ = BUILTIN_PODDER['nil']

--- Handles concrete non-nil types (boolean, number, string)
M.key = mty'key' {}
function M.key:__toPod(pod, v)
  if CONCRETE[type(v)] then return v end
  error('nonconrete type: '..type(v))
end
M.key.__fromPod = M.key.__toPod
BUILTIN_PODDER.key = M.key

--- Handles all primitive types (nil, boolean, number, string, table)
M.prim = mty'prim' {}; local prim = M.prim

assert(MOD_LOOKUP['pod.prim'] == M.prim)

function prim:__toPod(pod, v)
  local ty = type(v)
  if ty == 'table' then
    assert(isPrim(v, pod.mtPodFn), 'table is not plain-old-data')
    return v
  elseif BUILTIN[ty]   then return v end
  error('nonprimitive type: '..type(v))
end
function prim:__fromPod(pod, v)
  if BUILTIN[type(v)] then return v end
  error('nonprimitive type: '..type(v))
end
BUILTIN_PODDER.prim = prim

--- Poder for a list of items with a type.
--- Note that this defines the mechanism to decrypt a list, you should not
--- use this to directly contain any data.
M.List = mty'List' {'I [Podder]: the type of each list item'}
function M.List.__toPod(T, pod, l)
  local I, p = T.I, {}
  for i, v in ipairs(l) do p[i] = I:__toPod(pod, v) end
  return p
end
function M.List.__fromPod(T, pod, p)
  local I, l = T.I, {}
  for i, v in ipairs(p) do l[i] = I:__fromPod(pod, v) end
  return l
end

--- Poder for a map of key/value pairs.
--- Note that this defines the mechanism to decrypt a map, you should not
--- use this to directly contain any data.
M.Map = mty'Map' {
  'K [Podder]: keys type', K=M.key,
  'V [Podder]: values type',
}
function M.Map:__toPod(pod, m)
  local K, V, p = self.K, self.V, {}
  for k, v in pairs(m) do
    p[K:__toPod(pod, k)] = V:__toPod(pod, v)
  end
  return p
end
function M.Map:__fromPod(pod, p)
  local K, V, m = self.K, self.V, {}
  for k, v in pairs(p) do
    m[K:__fromPod(pod, k)] = V:__fromPod(pod, v)
  end
  return m
end

function M.toPod(v, podder, pod)
  if not podder then
    local ty = type(v)
    if ty == 'table' then
      podder = getmt(v) or M.table
      if podder == 'table' then podder = M.table end
    else
      podder = BUILTIN_PODDER[ty] or error('not pod: '..ty)
    end
  end
  return podder:__toPod(pod or Pod.DEFAULT, v)
end
function M.fromPod(v, poder, pod)
  return (poder or prim):__fromPod(pod or Pod.DEFAULT, v)
end
local toPod, fromPod = M.toPod, M.fromPod

--- Default __toPod for metatype records
function M.mty_toPod(T, pod, t)
  local p, podders = {}, T.__podders
  if pod.fieldIds then
    local fieldIds = T.__fieldIds
    for k, v in pairs(t) do
      p[fieldIds[k]] = podders[k]:__toPod(pod, v)
    end
  else
    for k, v in pairs(t) do
      p[k] = podders[k]:__toPod(pod, v)
    end
  end
  return p
end

--- Default __fromPod for metatype records
function M.mty_fromPod(T, pod, p)
  local t, podders, fieldIds = {}, T.__podders, T.__fieldIds
  for k, v in pairs(p) do local k=k
    if type(k) == 'number' then k = fieldIds[k] end
    t[k] = podders[k]:__fromPod(pod, v)
  end
  return T(t)
end

--- lookup podder from types, primitive, MOD_LOOKUP
local function lookupPodder(T, types, name)
  if G.MOD_NAMES[T] == name then return T end
  local p = types[name] or BUILTIN_PODDER[name] or G.MOD_LOOKUP[name]
         or error('Cannot find type '..name)
  if not (p.__toPod and p.__fromPod) then
    error(name.." doesn't implement both __toPod and __fromPod")
  end
  return p
end

--- Make metaty type convertable to/from plain-old-data
---
--- Typically this is called by calling the module itself,
--- i.e. [$$pod(mty'myType'{'field [int]#1'})]$
function M.implPod(T, tys)
  tys = tys or {}
  local errs, podders, podder = {}, {}, nil
  for _, field in ipairs(T.__fields) do
    local tyname = T.__fields[field]
    if type(tyname) ~= 'string' then
      push(errs, field..' does not have tyname specified') end
    if tyname:match'%b[]' then
      podder = lookupPodder(T, tys, tyname:sub(2,-2))
    elseif tyname:match'%b{}' then
      tyname = tyname:sub(2,-2)
      local kname, vname = tyname:match'^%s*(.-)%s*:%s*(.-)%s*$'
      if kname then
        podder = M.Map {
          K=lookupPodder(T, tys, kname), V=lookupPodder(T, tys, vname),
        }
      else podder = M.List{I=lookupPodder(T, tys, tyname)} end
    else error('unrecognized tyname: '..tyname) end
    podders[field] = podder
  end
  if #errs > 0 then error(sfmt(
    'Errors: \n * %s\n', table.concat(errs, '\n * ')
  ))end
  T.__podders = podders
  T.__toPod = M.mty_toPod
  T.__fromPod = M.mty_fromPod
  return T
end

--- Serialize value, converting it to a compact string.
--- Note: this function first calls toPod on the value.
function M.ser(value) --> string
  return ser(toPod(value))
end

--- Deserialize value from a compact string (and call fromPod on it)
--- [$index] (default=1) is where to start in [$str]
function M.deser(str, P, index) --> value, lenUsed
  local p, elen = deser(str, index)
  return fromPod(p, P), elen
end

--- dump ser(...) to f, which can be a path or file.
function M.dump(f, ...)
  local close
  if type(f) == 'string' then
    f = assert(io.open(f, 'w')); close = true
  end
  local ok, err = f:write(M.ser(...)); f:flush()
  if close then f:close() end; assert(ok, err)
end

--- load [$deser(f:read'a', ...)], f can be a path or file.
function M.load(f, ...)
  local close
  if type(f) == 'string' then
    f = assert(io.open(f)); close = true
  end
  local str, err = f:read'a'; if close then f:close() end
  assert(str, err); return M.deser(str, ...)
end

do
  local frozen = require'metaty.freeze'.frozen
  function frozen:__toPod(pod, v)
    local p = {}
    for k, v in pairs(self) do p[k] = toPod(v, nil, pod) end
    return p
  end
  function frozen.__fromPod(T, pod, v)
    assert(type(v) == 'table')
    return v
  end
end

getmt(M).__call = function(M, ...) return M.implPod(...) end
return M