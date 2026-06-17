#!/usr/bin/env -S lua
local shim = require'shim'

--- lson JSON+ command and library.
---
--- [*Cmd usage:] [$lson path/to/file.json][{br}]
--- The command pretty-prints JSON+ as a lua object.
---
---
--- [*Lib usage:] [$tbl = lson.decode('{1: 2}')][{br}]
--- As a library it allows de/serialization of JSON+ to/from
--- Lua values.
local M = shim.cmd'lson' {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local pod = require'pod'
local lines = require'lines'

local empty = ds.empty
local push, concat = table.insert, table.concat
local sfmt, rep = string.format, string.rep
local sortKeys = fmt.sortKeys
local toPod, fromPod = pod.toPod, pod.fromPod
local Json, Lson, De
local none = ds.none

--- classify none as pod
local podSet = pod.Pod{
  mtPodFn=function(v, mt) return v == none end
}

--------------------
-- Main Public API

--- Encode lua value to JSON string
function M.json(v, pretty) --> string
  local enc = pretty and Json:pretty{} or Json{}
  return concat(enc(v))
end

--- Encode lua value to LSON string
function M.lson(v, pretty) --> string
  local enc = pretty and Lson:pretty{} or Lson{}
  return concat(enc(v))
end

--- Decode JSON/LSON string or lines object to a lua value.
function M.decode(s, podder, pset) --> value
  return De(s)(podder, pset)
end

------------------
-- JSON Encoder

--- Json Encoder (via fmt.Fmt)
--- This works identically to metaty.Fmt except it overrides
--- how tables are formatted to use JSON instead of printing them.
M.Json = mty.extend(fmt.Fmt, 'Json', {
  'null [any]: value to use for null', null=none,
  'listStart [string]', listStart = '[',
  'listEnd [string]',   listEnd   = ']',
  indexEnd = ',',  keyEnd = ',',
  keySet   = ':',
})
M.Json.pretty = function(T, self)
  self.listStart = self.listStart or '[\n'
  self.listEnd   = self.listEnd   or '\n]'
  self.keySet    = self.keySet    or ': '
  return fmt.Fmt.pretty(T, self)
end

---- note: [$%q] formats ALL newlines with a [$'\'] in front of them
---- it also uses [$\9] instead of [$\t] for some strange reason, fix that
local CTRL_SUB = {
  ['\\\n'] = '\\n', ['\\9'] = '\\t',
  ['\n'] = true, -- "invalid replacement value" but unreachable
}
function M.Json.string(f, s)
  f:write( (sfmt('%q', s):gsub('\\?[\n9]', CTRL_SUB)) )
end
function M.Json.table(f, t)
  if rawequal(t, f.null) then return f:write'null' end
  if f._level >= f.maxIndent then error'max depth reached (recursion?)' end
  local keys = sortKeys(t)
  f:level(1)
  if #keys == 0 then
    f:write((#t > 1) and f.listStart or '[')
    f:items(t, next(keys)); f:level(-1)
    f:write((#t > 1) and f.listEnd   or ']')
  else -- has non-list keys
    for i in ipairs(t) do push(keys, i) end
    f:write((#keys > 1) and f.tableStart or '{')
    f:keyvals(t, keys); f:level(-1)
    f:write((#keys > 1) and f.tableEnd or '}')
  end
end
function M.Json:__call(v, podder, pod)
  if v ~= none then
    v = toPod(v, podder, pod or podSet)
  end
  self[type(v)](self, v); return self
end
M.Json.tableKey = M.Json.__call

-------------------------------
-- LSON

local ENC_BYTES = {
  ['\n'] = '\\n', ['|'] = [[\|]], ['\\'] = '\\',
  n='n',
}
--- Implementation: basically we need convert newline -> \n
--- and | -> \|. The decoder treats \x (where x is not n or |)
--- as the literal \x, so we also replace \n -> \\n and \| -> \\\|
local function mbytes(backs, esc)
  return rep('\\', #backs * 2)..ENC_BYTES[esc]
end

--- The bytes type-encoder. Encodes as [$|bytes|] instead of [$"string"] for
--- lson You can set [$Enc.string = lson.bytes] for this behavior (or use the
--- Lson type).
function M.bytes(f, s)
  f:write('|', s:gsub('(\\*)([\\\n|n])', mbytes), '|')
end

--- Similar to JSON but no commas and strings are encoded as [$|bytes|]
M.Lson = mty.extend(M.Json, 'Lson', {
  indexEnd = ' ', keyEnd=' ',
})
M.Lson.string = M.bytes
M.Lson.pretty = function(T, self)
  self.listStart = self.listStart or '[\n'
  self.listEnd   = self.listEnd   or '\n]'
  self.indexEnd  = self.indexEnd  or '\n'
  self.keyEnd    = self.keyEnd    or '\n'
  self.keySet    = self.keySet    or ': '
  return fmt.Fmt.pretty(T, self)
end

-------------------------------
-- Decoder
local function eval(s) return load('return '..s, nil, 't', empty) end

function M._deNull(de) de:consume'^null';  return de.null end
function M._deTrue(de) de:consume'^true';  return true    end
function M._deFalse(de) de:consume'^false'; return false   end
function M._deNumber(de)
  local str = de:consume'^[^%s:,%]}]+'
  local n = de:assert(eval(str))()
  assert(type(n) == 'number')
  return n
end
function M._deString(de)
  local c, line, q1, c2 = de.c + 1, de.line
  while true do
    q1, c2 = line:find('\\*"', c)
    if not q1 then return de:error[[no matching '"' found]] end
    if (c2 - q1) % 2 == 0 then break end -- len of escapes before quote
    c = c2 + 1
  end
  local s = de:assert(eval(line:sub(de.c, c2)))()
  de.c = c2 + 1
  return s
end
local DE_BYTES = {
  ['\\\n'] = '\\\n', ['\\n'] = '\n',
  ['\\|']  = '|',    ['\\']  = '\\', ['\\\\'] = '\\',
}
function M._deBytes(de) -- |binary data|
  local b, l, c, line = {}, de.l, de.c + 1, de.line
  local c1, c2 = c
  while true do
    while c <= #line do
      c1, c2 = line:find('\\*|', c1); if c1 then
        if (c2 - c1) % 2 == 0 then
          push(b, line:sub(c, c2-1))
          c = c2 + 1
          goto done
        else c1 = c2 + 1 end
      else break end -- no | detected, next line
    end
    push(b, line:sub(c)); push(b, '\n')
    l, c = d.l + 1, 1
    line = d.dat[l]; if not line then error(sfmt(
      "%s.%s: '|' never closed (reached EOF)", de.l, de.c
    ))end
  end
  ::done::
  de.l, de.c, de.line = l, c, line
  return concat(b):gsub('\\[\nn|\\]?', DE_BYTES)
end
function M._deArray(de)
  de.c = de.c + 1
  local arr, value, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^%]', c) then break end
    push(arr, de())
  end
  de.c = de.c + 1
  return arr
end
function M._deObject(de)
  de.c = de.c + 1
  local obj, key, val, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^,', c) then de.c = de.c + 1; goto cont end
    if line:find('^}', c) then break end
    key = de(); de:assert(key ~= nil, 'expected key')
    de:skipWs(); de:consume'^:'; de:skipWs()
    val = de(); de:assert(val ~= nil, 'expected value')
    obj[key] = val
  end
  de.c = de.c + 1
  return obj
end

--- starting characters indicating what to parse
local DE_FNS = {
  n=M._deNull, t=M._deTrue, f=M._deFalse, ['-'] = M._deNumber,
  ['"']=M._deString, ['|']=M._deBytes,
  ['{']=M._deObject, ['[']=M._deArray,
}; for c=string.byte'0',string.byte'9' do
  DE_FNS[string.char(c)] = M._deNumber
end

--- [$De(string or lines) -> value-iter]
--- [$$for val in De'["my", "lson"]' do ... end]$
M.De = mty'De' {
  'dat [lines]: lines-like data to parse',
  'null [any]: value to use for null', null=none,

  -- mostly internal
  'l [int]', 'c [int]', 'line [string]',
}
getmetatable(M.De).__call = function(T, dat)
  if type(dat) == 'string' then dat = lines(dat) end
  return mty.construct(T, {dat=dat, l=1, c=1, line=dat[1]})
end

function M.De:assert(ok, msg)
  return ok or error(sfmt('%s.%s: %s', self.l, self.c, msg))
end
function M.De:skipWs(eofOkay)
  local l, c, line, dat = self.l, self.c, self.line, self.dat
  while true do
    while c > #line do
      l, c, line = l+1, 1, dat[l+1]
      if not line then
        self:assert(eofOkay, 'unexpected end of file')
        goto done
      end
    end
    c = line:find('[^%s,]', c); if c then break end
    l, c, line = l + 1, 1, dat[l+1]
  end
  ::done::
  self.l, self.c, self.line = l, c, line
end
-- consume the pattern returning the consumed string
function M.De:consume(pat, context)
  local line = self.line
  local c1, c2 = line:find(pat, self.c)
  if not c1 then error(sfmt(
    '%s.%s: missing %s %q', self.l, self.c,
    context or 'pattern', pat:gsub('[%^%%]', '')
  ))end
  self.c = c2 + 1
  return line:sub(c1, c2)
end
function M.De:__call(podder, pset)
  self:skipWs(true)
  local l, c = self.l, self.c
  if l > #self.dat then return end
  local fn = DE_FNS[self.line:sub(c, c)] or error(sfmt(
    'unrecognized character: %q', self.line:sub(c,c)))
  return fromPod(fn(self), podder, pset or podSet)
end

Json, Lson, De = M.Json, M.Lson, M.De -- locals

function M:__call()
  local lns = lines.load(assert(self[1], 'must set path'))
  fmt.pprint(M.decode(lns))
end

if shim.isMain(M) then M:main(arg) end
return M
