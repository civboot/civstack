local concat = table.concat
local getmt, type, rawget = getmetatable, type, rawget

local srep = string.rep
local sfmt = string.format
local push = table.insert
local rawget, rawset       = rawget, rawset
local next, pairs          = next, pairs
local _G = _G

rawset(_G, 'LUA_OPT', rawget(_G, 'LUA_OPT')
                   or tonumber(os.getenv'LUA_OPT' or 1))

local CONCRETE = {
  ['nil']=true, bool=true, boolean=true,
  number=true,  string=true,
}
local BUILTIN = {table=true}
for k,v in pairs(CONCRETE) do BUILTIN[k] = v end

local G = setmetatable({}, {
  __name='G(init globals)',
  __index    = function(_, k)    return rawget(_G, k)    end,
  __newindex = function(g, k, v) return rawset(_G, k, v) end,
})

-- Documentation globals
local weakk, weakv = {__mode='k'}, {__mode='v'}
G.MOD_NAMES  = G.MOD_NAMES  or setmetatable({}, weakk) -- obj -> name
G.MOD_LOC    = G.MOD_LOC    or setmetatable({}, weakk) -- obj -> path:loc
G.MOD_LOOKUP = G.MOD_LOOKUP or setmetatable({}, weakv) -- name -> obj

local function srcloc(level)
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  return loc:sub(2)..':'..info.currentline
end

local mod; mod = {
  __name = 'Mod',
  __index = function(m, k) error('mod does not have: '..k, 2) end,
  __newindex = function(m, k, v)
    rawset(m, k, v)
    if type(k) ~= 'string' then return end
    push(m.__attrs, k)
    local n = rawget(m, '__name')
    mod.save(m.__name..'.'..k, v)
  end,
}

-- member function (not method)
-- save v with name to PKG variables
function mod.save(name, v)
  if CONCRETE[type(v)] then return end
  MOD_LOC[v]       = MOD_LOC[v]       or srcloc(2)
  MOD_NAMES[v]     = MOD_NAMES[v]     or name
  MOD_LOOKUP[name] = MOD_LOOKUP[name] or v
end

setmetatable(mod, {
  __name='Mod',
  __call=function(T, name)
    assert(type(name) == 'string', 'must provide name str')
    local m = setmetatable({
      __name=name,
      __attrs={}, -- ordered attributes added after
      __doc=function(self, d) d:mod(self) end,
    }, {
      __name=sfmt('Mod<%s>', name),
      __index=mod.__index,
      __newindex=mod.__newindex,
      __tostring=function(m) return m.__name end
    })
    mod.save(name, m)
    return m
  end,
})

--- metaty: simple but effective Lua type system using metatable
local M = mod'metaty'

--- G allows assignment to globals and returns nil if a variable is missing.
---
--- Calling [$metaty.setup()] makes non-G globals typosafe.
M.G = G

--- Usage: [$local M = mty.mod'name'][{br}]
--- Create typosafe module.
M.mod = mod
--- Return whether the value is a module.
function M.isMod(t) --> boolean
  if type(t) ~= 'table' then return false end
  local mt = getmetatable(t)
  return mt and mt.__name and mt.__name:find'^Mod<'
end

-- TODO: remove these globals
G.G = G.G or G
G.mod = mod

local function noG(_, k)
  error(sfmt(
    'global %s is nil/unset. Initialize with G.%s = non_nil_value', k, k
  ), 2)
end
--- Setup lua's global environment to meet metaty protocol.
---
--- Currently this only makes non-[$G] global access typosafe (throw error if
--- not previously set).
function M.setup()
  setmetatable(_G, {
    __name='_G(metatable by metaty)',
    __index=noG, __newindex=noG,
  })
end

local function update(t, update)
  for k, v in pairs(update) do t[k] = v end; return t
end

-- set of concrete types
M.CONCRETE, M.BUILTIN = CONCRETE, BUILTIN
--- Return whether v is a nil, boolean, number or string.
function M.isConcrete(v) return CONCRETE[type(v)] end
--- Return whether v is a primitive value, aka concrete or a table with no metatable.
function M.isPrim(obj)
  return M.isConcrete(obj) or (obj == nil) or (getmetatable(obj) == nil)
end

---------------
-- Pre module: environment variables
local IS_ENV = { ['true']=true,   ['1']=true,
                 ['false']=false, ['0']=false, ['']=false }
local EMPTY = {}

--- Given a string return whether os.getenv returns 'true' or '1'.
function M.isEnv(var)
  var = os.getenv(var); if var then return IS_ENV[var] end
end
--- Same as isEnv but first checks globals.
function M.isEnvG(var) -- is env or globals
  if G[var] ~= nil then return G[var] end
  return M.isEnv(var)
end

--- Get method of table if it exists.[{br}]
--- This first looks for the item directly on the table, then the item in the
--- table's metatable. It does NOT use the table's normal [$__index].
function M.getmethod(t, method)
  return rawget(t, method) or rawget(getmt(t) or EMPTY, method)
end

---------------
-- general functions and constants
M.DEPTH_ERROR = '{!max depth reached!}'

--- Get the type of the value which is either the values metatable or the
--- string result of [$type(v)].
function M.ty(v) --> type
  local t = type(v)
  return t == 'table' and getmt(v) or t
end
local getTy = M.ty

--- Given a type return it's name.
function M.tyName(T, default) --> string
  local Tty = type(T)
  return Tty == 'string' and T
    or ((Tty == 'table') and rawget(T, '__name'))
    or default or Tty
end

--- Given an object (function, table, userdata) return its name.
--- Return it's string type if it's not one of the above types.
function M.name(o)
  local ty = type(o)
  return ty == 'function' and M.fninfo(o)
      or ty == 'table'    and M.tyName(getTy(o))
      or ty == 'userdata' and M.tyName(getmt(o), 'userdata')
      or ty
end

--- Get the fullname of the object's type. This is typically
--- the same as looking it up in [$MOD_NAMES].
function M.fullname(o)
  local ty = type(o)
  return ty == 'function' and G.MOD_NAMES[o]
      or ty == 'table'    and G.MOD_NAMES[getTy(o)]
      or ty == 'userdata' and G.MOD_NAMES[getmt(o)]
      or ty
end

--- Return whether obj is callable (function or has [$mt.__call]).
function M.callable(obj) --> bool
  if type(obj) == 'function' then return true end
  local m = getmt(obj)
  return m and rawget(m, '__call') and true
end
local function metaget(t, k)   return rawget(getmt(t), k) end

--- keywords https://www.lua.org/manual/5.4/manual.html
M.KEYWORD = {}; for kw in string.gmatch([[
and       break     do        else      elseif    end
false     for       function  goto      if        in
local     nil       not       or        repeat    return
then      true      until     while
]], '%w+') do M.KEYWORD[kw] = true end

--- Return whether s can be used directly as a key
--- in syntax.
function M.validKey(s) --> boolean
  return type(s) == 'string' and
    not (M.KEYWORD[s] or tonumber(s)
         or s:find'[^_%w]')
end

--- Extract name,loc from function value.
function M.fninfo(fn) --> name, loc
  local info
  local name = MOD_NAMES[fn]; if not name then
    info = debug.getinfo(fn)
    name = info.name
  end
  local loc = MOD_LOC[fn]; if not loc then
    info = info or debug.getinfo(fn, 'Sl'); loc = info.source
    if loc:sub(1,1) == '@' then
      loc = loc:sub(2)..':'..info.linedefined
    else loc = nil end
  end
  return name or 'function', loc
end

--- Extract name,loc from any value (typically mod/type/function).
function M.anyinfo(v) --> name, loc
  if type(v) == 'function' then return M.fninfo(v) end
  if M.isPrim(v)           then return type(v), nil end
  local name, loc = MOD_NAMES[v], MOD_LOC[v]
  name = name or M.name(v)
  if loc and loc:find'%[' then loc = nil end
  return name, loc
end

--- You probably want split instead.
--- Usage: [$for ctx, line in rawsplit, text, {'\n', 1} do]
function M.rawsplit(subj, ctx) --> (state, splitstr)
  local pat, i = table.unpack(ctx)
  if not i then return end
  if i > #subj then
    ctx.si, ctx.ei, ctx[2] = #subj+1, #subj, nil
    return ctx, ''
  end
  local s, e = subj:find(pat, i)
  ctx.si, ctx.ei, ctx[2] = i, (s and (s-1)) or #subj, e and (e+1)
  return ctx, subj:sub(ctx.si, ctx.ei)
end

--- split the subj by pattern. [$ctx] has two keys: [$si] (start index) and
--- [$ei] (end index)
--- [{$$ lang=lua}
--- for ctx, line in split(text, '\n') do -- split lines
---   ... do something with line
--- end
--- ]$
function M.split(subj, pat--[[%s+]], index--[[1]]) --> (cxt, str) iter
  return M.rawsplit, subj, {pat or '%s+', index or 1}
end

--- The [$__copy] method.
function M.copyMethod(self)
  local c = {}
  for k, v in pairs(self) do c[k] = v end
  return setmetatable(c, getmetatable(self))
end

--- The default __fmt method.
function M.fmt(self, f)
  local mt = getmt(self)
  local len, fields = #self, rawget(mt, '__fields')
  local multi = len + #fields > 1 -- use multiple lines
  f:write(rawget(mt, '__name'));
  f:level(1);  f:write(multi and f.tableStart or '{')
  f:items(self, #fields > 0,
          multi and (len>0) and (#fields>0) and f.listEnd)
  f:keyvals(self, fields)
  f:level(-1); f:write(multi and f.tableEnd or '}')
end

--- The default __tostring method.
function M.tostring(self)
  local mt = getmt(self)
  return sfmt('%s@%p', rawget(mt, '__name'), self)
end

local function cleanupFieldTy(tyStr)
  return tyStr:match'%[(.*)%]' or tyStr
end

function M._docFields(R, d, name, kind)
  local fmt = require'fmt'
  local fields = {}
  for _, fname in ipairs(R.__fields or EMPTY) do
    if not fname:match'^_' then push(fields, fname) end
  end
  if #fields > 0 then
    d:bold(kind..':'); d:write'[+\n'; 
    for _, fname in ipairs(fields) do
      d:write'* '; d:level(1)
      local fullName = sfmt('%s.%s', name, fname)
      d:write(sfmt('[{*name=%s}%s]', fullName, fname))
      local ty = fields[fname]; if type(ty) == 'string' then
        d:write' '; d:code(cleanupFieldTy(ty))
      end
      local default = rawget(R, fname); if default ~= nil then
        d:write' '
        if MOD_NAMES[default] then
          d:code('='..MOD_NAMES[default])
        else
          local dstr = fmt(default)
          d:code('='..(#dstr <= 16 and dstr
                    or (M.name(default)..'() instance')))
        end
      end
      local doc = R.__docs[fname]; if doc then
        d:check(fullName, doc)
        d:write'\n'; d:write(doc)
      end
      d:level(-1); d:write'\n'
    end
    d:write']\n'
  end
end

function M._docMethods(R, d, name)
  local methods = {}
  for _, k in ipairs(R.__attrs) do
    if k:match'^_' then goto continue end
    local v = rawget(R, k)
    if not d.done[v] and M.callable(v) then
      d.done[v] = true
      push(methods, k); methods[k] = v
    end
    ::continue::
  end
  if #methods > 0 then
    d:bold'Methods'; d:write' [+\n'; 
    for _, name in ipairs(methods) do
      d:write'* '; d:level(1)
      d:declfn(methods[name], name, sfmt('%s.%s', R.__name, name))
      d:level(-1); d:write'\n'
    end
    d:write']\n'
  end
end

--- The default __doc method.
---
--- ["d is of type [$doc.Documenter].
---   Tests are in cmd/doc/test.lua ]
function M.doc(R, d)
  d.done[R] = true
  local name, loc = M.anyinfo(R)
  local cmt, code = d:extractCode(loc)
  d:header(d.tyHeader, 'Record '..R.__name, name)
  -- Comments
  if cmt and #cmt > 0 then
    d:check(name, cmt)
    for _, c in ipairs(cmt) do
      d:write(c); d:write'\n'
    end
    d:write'\n'
  end
  M._docFields(R, d, name, 'Fields')
  M._docMethods(R, d, name)
end

-----------------------------
-- Equality

local function nativeEq(a, b) return a == b end

local function eqDeep(a, b)
  if rawequal(a, b)     then return true   end
  if getTy(a) ~= getTy(b) then return false  end
  local aLen, eq = 0, M.eq
  for aKey, aValue in pairs(a) do
    local bValue = b[aKey]
    if not M.eq(aValue, bValue) then return false end
    aLen = aLen + 1
  end
  local bLen = 0
  -- Note: #b only returns length of integer indexes
  for bKey in pairs(b) do bLen = bLen + 1 end
  return aLen == bLen
end

local NATIVE_TY_EQ = {
  number   = rawequal,   boolean = rawequal, string = rawequal,
  userdata = nativeEq,   thread  = nativeEq,
  ['nil']  = rawequal,   ['function'] = rawequal,
  ['table'] = function(a, b)
    if a == b then return true end
    local mt = getmt(a)
    if type(mt) == 'table' and rawget(mt, '__eq') then
      return false -- true equality already tested
    end
    return eqDeep(a, b)
  end,
}

--- Compare two values (any values) for equality. This will
--- recursively check tables for equality.
function M.eq(a, b) return NATIVE_TY_EQ[type(a)](a, b) end --> bool

-----------------------
-- record

--- Throws a formatted index error when called.
function M.indexError(R, k, lvl)
  error(sfmt('%q is not a field of %s', k, R.__name), lvl or 2)
end

--- Usage: [$getmetable(MyType).__index = mty.index][{br}]
--- Allows integers to be insert into your value. This is the default __index.
function M.index(R, k) -- Note: R is record's metatable
  if type(k) == 'string' and not rawget(R, '__fields')[k] then
    M.indexError(R, k, 3)
  end
end
--- Usage: [$getmetable(MyType).__index = mty.index][{br}]
--- Allows nothing except your type's fields to be insert into
--- your value.
function M.hardIndex(R, k)
  if type(k) ~= 'string' or not rawget(R, '__fields')[k] then
    M.indexError(R, k, 3)
  end
end

--- Usage: [$MyType.__newindex = mty.newindex][{br}]
--- (record default) this allows non-string keys to always be insert.
function M.newindex(r, k, v)
  if type(k) == 'string' and not metaget(r, '__fields')[k] then
    M.indexError(getmt(r), k, 3)
  end
  rawset(r, k, v)
end
--- Usage: [$MyType.__newindex = mty.hardNewindex][{br}]
--- This allows only registered fields to be insert.
function M.hardNewindex(r, k, v)
  if type(k) ~= 'string' or not metaget(r, '__fields')[k] then
    M.indexError(getmt(r), k, 3)
  end
  rawset(r, k, v)
end

local function fieldsCheck(T, fields, t)
  local tkey; while true do
    tkey = next(t, tkey); if not tkey then return end
    if type(tkey) == 'string' and not fields[tkey] then
      error(sfmt('[%s] unrecognized field: %s', T.__name, tkey))
    end
  end
end

--- Usage: [$getmetatable(MyType).__call = mty.constructChecked]
---
--- Check type with field typochecking. This is the default when
--- [$LUA_OPT <= 2]
function M.constructChecked(T, t)
  fieldsCheck(T, rawget(T, '__fields'), t)
  return setmetatable(t, T)
end
--- Usage: [$getmetatable(MyType).__call = mty.constructUnchecked]
---
--- Check type with field typochecking. This is the default when
--- [$LUA_OPT >= 3].
function M.constructUnchecked(T, t)
  return setmetatable(t, T)
end
--- [$constructChecked] or [$constructUnchecked] depending on [$LUA_OPT].
M.construct = (G.LUA_OPT <= 2 and M.constructChecked) or M.constructUnchecked

local function extendFields(fields, ids, docs, R)
  for i=1,#R do
    local spec = rawget(R, i); rawset(R, i, nil)
    -- name [type] : some docs, but [type] and ':' are optional.
    local name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.-)%s*$'
    if not name then -- check for {type}
      name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b{})%s*:?%s*(.*)%s*$'
    end
    if not name then
      name, fdoc = spec:match'^([%w_]+)%s*:?%s*(.-)%s*$'
    end
    if not name then error('invalid spec: '..spec) end
    if #name==0 then error('empty name: '..spec) end
    push(fields, name); fields[name] = tyname or true
    local id, iddoc = fdoc:match'^%s*#(%d+)%s*:?%s*(.*)%s*$'
    if id then
      id = tonumber(id); fdoc = iddoc
      if ids[id] or ids[name] then
        error('id specified multiple times: '..name)
      end
      ids[name] = id; ids[id] = name
    end
    docs[name] = (fdoc ~= '') and fdoc or nil
  end
  return fields, ids, docs
end

function M._namedRecord(name, R, loc)
  rawset(R, '__name', name)
  local fieldIds = {}; for id in ipairs(R.reserved or {}) do
    fieldIds[id] = id
  end; R.reserved = nil
  R.__fields, R.__fieldIds, R.__docs = extendFields({}, fieldIds, {}, R)
  R.__fmt      = rawget(R, '__fmt')      or M.fmt
  R.__copy     = rawget(R, '__copy')     or M.copyMethod
  R.__doc      = rawget(R, '__doc')      or M.doc
  R.__tostring = rawget(R, '__tostring') or M.tostring
  R.__index    = rawget(R, '__index')    or R
  R.__attrs    = rawget(R, '__attrs')    or {}
  local mtR = {
    __name     = 'Ty<'..R.__name..'>',
    __newindex = mod and mod.__newindex,
    __tostring = function() return R.__name end,
  }
  local R = setmetatable(R, mtR)
  if G.LUA_OPT <= 2 then
    mtR.__call    = M.constructChecked
    mtR.__index   = M.index
    rawset(R, '__newindex', rawget(R, '__newindex') or M.newindex)
  else
    mtR.__call = M.constructUnchecked
  end
  return R
end

--- Usage: [$$record'name'{ 'field [type]: documentation' }]$
---
--- Start a new record. See module documentation for details.
function M.record(name)
  assert(type(name) == 'string' and #name > 0,
         'must set name to string')
  return function(R) return M._namedRecord(name, R) end
end

--- Start a new record which acts as a lua module (i.e. the file returns it).
function M.recordMod(name)
  return function(R)
    R = M._namedRecord(name, R)
    mod.save(R.__name, R)
    return R
  end
end

--- Return true if [$t] is a record value.
function M.isRecord(t)
  if type(t) ~= 'table' then return false end
  local mt = getmt(t)
  return mt and mt.__name and mt.__name:find'^Ty<'
end

--- Usage: [$mty.extend(MyBase, 'NewName', {...new fields...})]
---
--- Extend the Type with (optional) new name and (optional) additional fields.
function M.extend(Type, name, fields)
  assert(type(Type) == 'table' and getmt(Type), 'arg 1 must be Type')
  assert(type(name) == 'string',                'arg 2 must be name')
  name, fields = name or Type.__name, fields or {}
  local E, mt = update({}, Type), update({}, getmt(Type))
  E.__name, mt.__name = name, 'Ty<'..name..'>'
  E.__index = E
  E.__fields   = update({}, E.__fields);
  E.__fieldIds = update({}, E.__fieldIds);
  E.__fields, E.__fieldIds, E.__docs = extendFields(
    update({}, E.__fields),
    update({}, E.__fieldIds),
    update({}, E.__docs),
    fields
  )
  for k, v in pairs(fields) do E[k] = v end
  return setmetatable(E, mt)
end

--- Extend the type with new name and use as a module.
function M.extendMod(T, name, fields)
  T = M.extend(T, name, fields)
  mod.save(name, T)
  return T
end

local function enum_tostring(E) return E.__name end
local function enum_toPod(E, pset, e)
  if pset.enumIds then return E.id(e) else return E.name(e) end
end
local function enum_fromPod(E, pset, e) return E.name(e) end
local function enum_partialMatcher(E, fnMap)
  for name, fn in pairs(fnMap) do
    if not E.__names[name] then error(name..' is not in enum '..E.__name) end
    if not M.callable(fn) then error(name ..'is not callable') end
  end
  for name, id in pairs(E.__names) do
    if fnMap[name] then fnMap[id] = fnMap[name] end
  end
  return fnMap
end
local function enum_matcher(E, fnMap)
  local missing = {}
  for name in pairs(E.__names) do
    if not fnMap[name] then push(missing, name) end
  end
  if #missing > 0 then
    error('missing variants (or set default): '
          ..table.concat(missing, ' '))
  end
  return E:partialMatcher(fnMap)
end

local ENUM_INVALID = {id=1, name=1, matcher=1, partialMatcher=2}
local function namedEnum(ename, nameIds)
  local names, ids = {}, {}
  for name, id in pairs(nameIds) do
    assert(type(name) == 'string' and #name > 0,
      'keys must be string names')
    assert(math.type(id) == 'integer' and id >= 0,
      'values must be integer ids greater >= 0')
    assert(not ENUM_INVALID[name], 'must not name variant id, name')
    assert(name:sub(1,2) ~= '__', "name must not start with '__'")
    names[name] = name; names[id] = name
    ids[name]   = id;   ids[id]   = id
  end
  local errmsg = ' is not a variant of enum '..ename
  local E = {
    __name = ename,
    __names=nameIds,
    name = function(v) return names[v]
                       or error(tostring(v)..errmsg) end,
    id = function(v) return ids[v]
                     or error(tostring(v)..errmsg) end,
    __tostring = enum_tostring,
    matcher = enum_matcher, partialMatcher = enum_partialMatcher,
  }
  for name in pairs(nameIds) do E[name] = name end
  E.__toPod, E.__fromPod = enum_toPod, enum_fromPod
  return setmetatable(E, {
    __name = ename, __tostring = E.__tostring,
    __index = function(k) error(sfmt(
      'enum %s has no method %s', ename, k
    )) end
  })
end

--- Usage: [$mty.enum'name' { A = 1, B = 2, ... }][{br}]
--- Create an enum type. See module documentation.
function M.enum(name)
  assert(type(name) == 'string' and #name > 0,
        'must name the enum using a string')
  return function(nameIds) return namedEnum(name, nameIds) end
end


--- like require but returns nil if not found.
function M.want(mod) --> module?
  local ok, m = xpcall(function() return require(mod) end, debug.traceback)
  if ok then return m end
  local expect = sfmt("module '%s' not found", mod)
  if not m:find(expect, 1, true) then
    error(sfmt('mty.want expected error %q, got:\n%s', expect, m))
  end
end

--- Usage: [$local bar, baz = mty.from'foo bar,baz'][{br}]
--- Usage: [$local sfmt, srep = mty.from(string, 'format,rep')][{br}]
--- Shortcut for: [{$$ lang=lua}
--- local foo = require'foo'
--- local bar, baz = foo.bar, foo.baz
--- ]$
function M.from(a, b)
  local m, str -- mod and str to split
  if b then
    m = type(a)=='string' and assert(require(a), a) or a
    str = b
  else
    m = assert(require(a:match'[^%s,]+'))
    str = a:match'[^%s,]+[%s,]*(.*)'
  end
  local o = {}
  for _, s in M.split(str:match'^%s*(.-)%s*$', '[%s\n,]+') do
    push(o, ( assert(m[s], s) ))
  end
  return table.unpack(o)
end

getmt(M).__call = function(T, name) return M.record(name) end
assert(M.setup)
return M