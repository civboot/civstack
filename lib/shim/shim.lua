local mty = require'metaty'

--- shim: command line library for lua.
local M = mty.mod'shim'
local G = mty.G

local push, sfmt = table.insert, string.format
local lower = string.lower
local mtype, tointeger = math.type, math.tointeger

G.LUA_SETUP = G.LUA_SETUP or os.getenv'LUA_SETUP' or 'ds'

local ENV_VALS = {['true'] = true, ['1'] = true }
local EMPTY = {}

--- Parse either a string or list and convert them to key=value table.
--- v can be either a list of [${'strings', '--option=foo'}]
--- or [${'strings", option='foo'}] or a combination of both. If v is a string then
--- it is split on whitespace and parsed as a list.
---
--- Note: this handles repeat keys by creating and appending a list for that key.
function M.parse(v) --> args
  if type(v) == 'string' then return M.parseStr(v)
  else                        return M.parseList(v) end
end

--- Add k,v to table, turning into a list if it already exists.
local function addKV(t, k, v)
  local e = t[k]; if e then
    if type(e) == 'table' then push(e, v)
    else t[k] = {e, v} end
  else t[k] = v end
end

--- parses the string by splitting via whitespace.
--- Asserts the string contains no special chars: [$$'"[]]$
--- This is for convinience, use a table if it's not enough.
---
--- Note: if the input is already a table it just returns it.
function M.parseStr(str) --> args
  str = str or {}
  if type(str) == 'table' then return str end
  if str:find'[%[%]\'"]' then error(
    [[parseStr does not support chars '"[]: ]]..str
  )end
  local args = {}; for a in str:gmatch'%S+' do push(args, a) end
  return M.parseList(args)
end

--- Note: typically use parse() or parseStr() instead.
function M.parseList(strlist) --> args
  local t = {}; for i, arg in ipairs(strlist) do
    if arg == '--' then -- lone '--' indicates special parsing
      table.move(strlist, i, #strlist, #t+1, t)
      break
    elseif arg:find'^%-%-[^-]+' then
      local k, v = arg:match('(.-)=(.*)', 3)
      if k then addKV(t, k, v)
      else      addKV(t, arg:sub(3), true) end
    else        push(t, arg) end
  end
  return t
end

--- Helper for dealing with [$-s --short] arguments. Mutates
--- args to convert short paramaters to their long counterpart.
function M.short(args, short, long, value) --> nil
  if args[short] then args[long] = value; args[short] = nil end
end

local BOOLS = {
  [true]=true,   ['true']=true,   ['yes']=true, ['1']=true,
  [false]=false, ['false']=false, ['no']=false, ['0']=false,
}

--- Duck type: always return a boolean (except for nil).
--- See BOOLS (above) for mapping.
function M.bool(v)
  if v == nil then return nil end
  local b = BOOLS[v] if b ~= nil then return b end
  error('invalid boolean: '..tostring(v))
end
M.boolean = M.bool
function M.bools(args, ...)
  for _, arg in ipairs{...} do
    args[arg] = M.boolean(args[arg])
  end
end

--- Duck type: always return a number
function M.number(num) --> number
  if num == nil then return nil end
  return (type(num)=='number') and num or tonumber(num)
end

--- Duck type: always return a integer.
function M.int(int) --> int
  if int == nil then return nil end
  return (mtype(int)=='integer') and int or tointeger(int)
end

local TOSTR = {
  ['nil'] = '', boolean = tostring, number = tostring,
  string = tostring,
}
--- Duck type: always return a string
--- This is useful for some APIs where you want to convert
--- number/true/false to strings
--- ["Converts nil to '']
function M.string(v)
  local f = TOSTR[type(v)]; if f then return f(v) end
  error('invalid type for shim.string: '..type(v))
end

--- Duck type: always return a list.[+
--- * default controls val==nil
--- * empty   controls val==''
--- ]
function M.list(val, default, empty) --> {string}
  if val == nil                 then val = default or {} end
  if empty ~= nil and val == '' then return empty        end
  return (type(val) == 'table') and val or {val}
end

--- Duck type: if val is a string then splits it
--- if it's a list leaves alone.
function M.listSplit(val, sep)
  if val == nil then return {} end
  if type(val) == 'table' then return val end
  sep = '[^'..(sep or '%s')..']+'
  local t = {}; for m in val:gmatch(sep) do push(t, m) end
  return t
end

--- Duck type: get a file handle.
--- If [$v or default] is a string then open the file in mode [$default='w+']
function M.file(v, default, mode--[[w+]]) --> file, error?
  if BOOLS[v] ~= nil then
    return default -- TODO: handle false -> /dev/null.
  end
  v = v or default
  if type(v) == 'string' then return io.open(v, mode or 'w+') end
  return v
end

--- expand string keys into [$--key=value], ordered alphabetically.
--- This is mostly useful for interfacing with non-lua shells.
function M.expand(args)
  local out, keys = {}, {}
  for k, v in pairs(args) do
    if type(k) == 'number'     then out[k] = M.string(v)
    elseif type(k) == 'string' then push(keys, k)
    else error('non string key: '..k) end
  end
  table.sort(keys); for _, k in ipairs(keys) do 
    push(out, sfmt('--%s=%s', k, M.string(args[k])))
  end
  return out
end


--- return nil if env var does not exist, else boolean (true for 'true' or '1')
function M.getEnvBool(k)
  local v = os.getenv(k); if not v then return v end
  return ENV_VALS[lower(v)] or false
end

--- pop raw arguments after '--'
--- Removes them (including '--') from args.
function M.popRaw(args, to) --> to
  local ri; for i, v in ipairs(args) do
    if v == '--' then ri = i; break end
  end; if not ri then return end
  local to = to or {}
  local raw = table.move(args, ri+1, #args, #to+1, to)
  for i=ri,#args do args[i] = nil end -- clear from args
  return to
end

--- Setup lua using [$require(LUA_SETUP).setup(args, force)].
---
--- The default is to use ds.setup.
function M.runSetup(args, force)
  mty.setup()
  require(G.LUA_SETUP or os.getenv'LUA_SETUP' or 'ds')
    .setup(args, force)
end

--- Construct a metaty-like object from args.
---
--- If [$Args.subcmd] is truthy then treats it as a table of
--- subcmds. Looks for a subcmd at [$$args[1]]$, removes it and
--- constructs that subcmd, returning a table with the subcmd
--- key set.
---
--- For example:
--- [$construct({foo=Foo, bar=Bar}, {'foo', 'ding', zing=true})]
--- returns a {foo=Foo{'ding', zing=true}}.
-- FIXME: remove
function M.construct(Cmd, args) --> ok, err?
  args = M.parseStr(args)
  assert(Cmd and args, 'must provide (Cmd,args)')
  if type(Cmd) == 'table' and rawget(Cmd, 'subcmd') then
    local v = {}; for k in pairs(Cmd) do
      if k ~= 'subcmd' then push(v, k) end
    end
    local sc = args[1]
    if not sc or not Cmd[sc] then
      return nil, sfmt(
        'invalid subcmd %q, valid subcommands are: %s',
        sc or '', table.concat(v, ' '))
    end
    table.remove(args, 1)
    return {
      subcmd = sc,
      [sc]=M.construct(Cmd[sc], args),
    }
  end
  return mty.construct(Cmd, args)
end

function M.constructNew(Cmd, args) --> ok, err?
  args = M.parseStr(args)
  assert(Cmd and args, 'must provide (Cmd,args)')
  if type(Cmd) == 'table' and rawget(Cmd, 'subcmd') then
    local v = {}; for k in pairs(Cmd) do
      if k ~= 'subcmd' then push(v, k) end
    end
    local sc = args[1]
    if not sc or not Cmd[sc] then
      return nil, sfmt(
        'invalid subcmd %q, valid subcommands are: %s',
        sc or '', table.concat(v, ' '))
    end
    table.remove(args, 1)
    return M.constructNew(Cmd[sc], args)
  end
  return mty.construct(Cmd, args)
end

--- FIXME delete
function M.init(Cmd, args)
  local a, err = M.construct(Cmd, args)
  M.runSetup(a or {})
  return assert(a, err)
end

-- FIXME delete
function M.run(Args, args)
  return M.init(Args, args)()
end

--- Return whether a record was created with [@shim.cmd]
function M.isCmd(R)
  return type(R) == 'table' and rawget(R, '__cmd') and true
end

--- The [$getmt(Cmd).__call]
function M._constructCall(Cmd, args)
  return Cmd:new(args)()
end

--- [$Cmd:main()] constructor and runner.
---
--- This is intended to take care of doing everything needed to
--- run [@shim.cmd] or [@shim.subcmds] from the commandline.
---
--- Usage: [{$$ lang=lua}
---   if shim.isMain(mycmd) then mycmd:main(G.arg) end
--- ]$
function M._main(Cmd, args)
  local self, err = Cmd:new(M.parse(args))
  M.runSetup(self or {})
  assert(self, err)
  self()
end

--- for [$cmd.__doc]
function M._doc(R, d, pre)
  d.done[R] = true
  local name, loc, cmt, code = d:anyExtract(R)
  local hname = R.__name
  d:header(d.tyHeader, (pre and 'Subcmd ' or 'Command ')..R.__name, R.__name)
  -- Comments
  if cmt then
    for _, c in ipairs(cmt) do d:write(c); d:write'\n' end
  end
  mty._docFields(R, d, name, 'Arguments')
  d:endmod(R, 'Methods and Functions')
end

--- for [$subcmds.__doc]
function M._subsdoc(R, d, pre)
  local name, loc, cmt, code = d:anyExtract(R)
  pre = ((pre and (pre..' ')) or '')..R.__name
  d:header(d.modHeader, 'Command '..pre, name)
  -- Comments
  for _, c in ipairs(cmt or EMPTY) do d:write(c); d:write'\n' end
  for _, sub in ipairs(R.__attrs) do
    if sub:match'^_' then goto continue end
    local S = rawget(R, sub)
    if M.isCmd(S) and not d.done[S] then
      d.done[S] = true
      rawget(S, '__doc')(S, d, pre)
    end
    ::continue::
  end
  d:endmod(R, 'Functions')
end

local function namedCmd(name, R)
  R.new    = R.new    or M.constructNew
  R.main   = R.main   or M._main
  R.__doc  = R.__doc  or M._doc
  R.__cmd  = R.__cmd  or name
  R = mty._namedRecord(name, R)
  getmetatable(R).__call = M._constructCall
  G.MAIN = G.MAIN or R
  return R
end

--- Create a new command as your module.
---
--- [{$$ lang=lua}
--- local M = shim.cmd'mycmd' {
---   '...: argument documentation',
---   'foo: some paramater',
---   'to [path|file]: where to write output',
--- }
--- -- ... rest of your module.
--- if shim.isMain(M) then M:main(arg) end
--- return M
--- ]$
function M.cmd(name)
  return function(R)
    namedCmd(name, R)
    mod.save(name, R)
    return R
  end
end

--- Create a command composed of subcommands.
function M.subcmds(name)
  return function(R)
    R.__doc = R.__doc or M._subsdoc
    R.subcmd = true  -- FIXME: rename?
    namedCmd(name, R)
    mod.save(name, R)
    return R
  end
end

--- Usage: [$if shim.isMain(M) then os.exit(M:main(arg)) end]
function M.isMain(cmd) return G.MAIN == cmd end

return M