local mty = require'metaty'

--- format module: format any type into a readable string
local M = mty.mod'fmt'

local G = mty.G
local getmt              = getmetatable
local sfmt, srep         = mty.from(string, 'format,rep')
local push, concat, sort = mty.from(table, 'insert,concat,sort')
local mathtype           = math.type
local split              = mty.split
local io                 = G.io

local DEPTH_ERROR = '{!max depth reached!}'

--- valid TTYs. These are used by other libraries
--- to determine if the output can handle color.
M.TTY = {
  [rawget(io, '_stdout') or io.stdout] = 1,
  [rawget(io, '_stderr') or io.stderr] = 2,
}

--- Compares two values of any type.
---
--- Note: [$nil < bool < number < string < table]
function M.cmpDuck(a, b)
  local aTy, bTy = type(a), type(b)
  if aTy ~= bTy then return aTy < bTy end
  return a < b
end
local cmpDuck = M.cmpDuck

--- keywords https://www.lua.org/manual/5.4/manual.html
M.KEYWORD = {}; for kw in string.gmatch([[
and       break     do        else      elseif    end
false     for       function  goto      if        in
local     nil       not       or        repeat    return
then      true      until     while
]], '%w+') do M.KEYWORD[kw] = true end
local KEYWORD = M.KEYWORD

--- Return a list of the table's keys sorted using [$cmpDuck]
function M.sortKeys(t) --> list
  local len, keys = #t, {}
  for k, v in pairs(t) do
    if not (mathtype(k) == 'integer' and (1 <= k) and (k <= len)) then
      push(keys, k)
    end
  end; sort(keys, cmpDuck)
  return keys
end

--- The formatter object.
---
--- This is the main API of this module. It enables formatting any
--- type by simply calling it's instance, writing the result to
--- [$to] (if set) or just the fmter itself. For the latter, you can construct
--- the string with [$fmter:tostring()] or just [$table.concat(fmter)].
M.Fmt = mty'Fmt' {
  'style     [bool]: enable styling. If true, set [$to=Styler]',
  "to        [file?]: if set calls write",
  "keyEnd    [string]",  keyEnd     = ', ',
  "keySet    [string]",  keySet     = '=',
  "indexEnd  [string]",  indexEnd   = ', ',
  "tableStart[string]",  tableStart = '{',
  "tableEnd  [string]",  tableEnd   = '}',
  "listEnd   [string] separator between list/map", listEnd    = '',
  "indent    [string]",  indent     = '  ',
  "maxIndent [int]",     maxIndent  = 20,
  "numfmt    [string]",  numfmt     = '%q',
  "strfmt    [string]",  strfmt     = '%q',
  "_level    [int]",     _level     = 0,
 [[_nl [string] (default='\n') newline, indent is added/removed]],
   _nl = '\n',

  -- overrideable methods
  'table [function]', 'string [function]',
}
local Fmt = M.Fmt

function Fmt:toPretty()
  self.tableStart = rawget(self, 'tableStart') or '{\n'
  self.tableEnd   = rawget(self, 'tableEnd')   or '\n}'
  self.listEnd    = rawget(self, 'listEnd')    or '\n'
  self.keyEnd     = rawget(self, 'keyEnd')     or ',\n'
  self.indent     = rawget(self, 'indent')     or '  '
  return self
end

--- Create a new Formatter object with default "pretty" settings.
--- Generally, this means line-separated and indented tables.
Fmt.pretty = function(T, self) return T(self):toPretty() end

--- Add to the indent level and get the new value
--- call with [$add=nil] to just get the current level
function Fmt:level(add) --> int: current level
  local l = self._level
  if add then
    l = l + add; assert(l >= 0, 'fmt._level cannot be negative')
    self._level, self._nl = l, '\n'..srep(self.indent, l)
  end
  return l
end

function Fmt:_write(str)
  if self.to then self.to:write(str)
  else            rawset(self, #self + 1, str) end
end
--- Same as [$file:write].
function Fmt:write(...)
  local str = concat{...}
  local doIndent = false
  for _, line in split(str, '\n') do
    if doIndent then self:_write(self._nl) end
    self:_write(line); doIndent = true
  end
  return self
end
function Fmt:flush() if self.to then self.to:flush() end; return true end
function Fmt:close() if self.to then self.to:close() end; return true end

--- Call [$to:styled(...)] if it is enabled, else simply [$self:write(text, ...)].
--- This allows for configurable styling of output, both for objects as well
--- as command-line utilities/etc.
function Fmt:styled(style, text, ...)
  if not self.style then self:write(text, ...); return end
  local to, doIndent = self.to, false
  for _, line in split(text, '\n') do
    if doIndent then self:_write(self._nl) end
    to:styled(style, line); doIndent = true
  end
  doIndent = false
  for _, line in split(concat{...}, '\n') do
    if doIndent then self:_write(self._nl) end
    to:write(line); doIndent = true
  end
end

function Fmt:__newindex(k, v)
  assert(type(k) == 'string', 'cannot set Fmt index')
  return rawset(self, k, v)
end

--- Format like a table key. This can be overriden by type extensions to
--- provide other behavior.
function Fmt:tableKey(k)
  if type(k) ~= 'string' or KEYWORD[k]
     or tonumber(k) or k:find'[^_%w]' then
    self:styled('meta', '[')
    if type(k) == 'string' then self:styled('string', sfmt('%q', k))
    else                        self(k) end
    self:styled('meta', ']', '')
  else self:styled('key', k, '') end
end

--- format a nil value.
Fmt['nil']      = function(self)
  self:styled('literal', 'nil', '')
end
--- format a boolean value.
function Fmt:boolean(b)
  self:styled('literal', tostring(b), '')
end
--- format a number value.
function Fmt:number(n)
  self:styled('num', sfmt(self.numfmt, n), '')
end
--- format a string value.
function Fmt:string(s)
  self:styled('string', sfmt(self.strfmt, s), '')
end
--- format a thread value.
function Fmt:thread(th)
  self:styled('literal', tostring(th), '')
end
--- format a userdata value.
function Fmt:userdata(ud)
  self:styled('literal', tostring(ud), '')
end
--- format a function value.
Fmt['function'] = function(self, fn)
  self:styled('path', sfmt('fn%q[%s]', mty.fninfo(fn)), '')
end

--- format items in table "list"
function Fmt:items(t, hasKeys, listEnd, si, ei)
  si, ei = si or 1, ei or #t
  for i=si,ei do
    self(t[i])
    if (i < ei) or hasKeys then self:styled('meta', self.indexEnd, '') end
  end
  if listEnd then self:styled('meta', listEnd, '') end
end

--- format key/vals in table "map".
function Fmt:keyvals(t, keys)
  local klen, kset, kend = #keys, self.keySet, self.keyEnd
  for i, k in ipairs(keys) do
    local v = t[k]
    self:tableKey(k); self:write(kset)
    if rawequal(t, v) then self:styled('keyword', 'self', '')
    else                   self(v) end
    if i < klen then self:styled('meta', kend, '') end
  end
end

--- Format only the list-elements of a table.
function Fmt:list(t)
  local multi = #t > 1
  self:level(1)
  self:styled('symbol', multi and self.tableStart or '{', '')
  self:items(t, false,  nil)
  self:level(-1)
  self:styled('symbol', multi and self.tableEnd or '}', '')
end

function Fmt:rawtable(t)
  local keys = M.sortKeys(t)
  local multi = #t + #keys > 1 -- use multiple lines
  self:level(1)
  self:styled('symbol', multi and self.tableStart or '{', '')
  self:items(t, next(keys), multi and (#t>0) and (#keys>0) and self.listEnd)
  self:keyvals(t, keys)
  self:level(-1)
  self:styled('symbol', multi and self.tableEnd or '}', '')
end

--- Recursively format a table.
--- Yes this is complicated. No, there is no way to really improve
--- this while preserving the features.
function Fmt:table(t)
  if self._level >= self.maxIndent then return self:write(DEPTH_ERROR) end
  local mt = getmt(t)
  if (mt ~= 'table') and (type(mt) == 'string') then
    return self:write(tostring(t))
  end
  if type(mt) == 'table' then
    local fn = rawget(mt, '__fmt'); if fn then return fn(t, self) end
    fn = rawget(mt, '__tostring');  if fn then return self:write(fn(t)) end
    local name = rawget(mt, '__name'); if name then self:write(name) end
  end
  return self:rawtable(t)
end
function Fmt:__call(v) self[type(v)](self, v); return self end

--- Format a list of arguments.
function Fmt:formatArgs(fmt, args)
  local i, lasti = 0, 1
  fmt:gsub('()(%%.)', function(si, m)
    self:write(fmt:sub(lasti, si-1)); lasti = si + #m
    if m == '%%' then self:write'%'
    else
      i = i + 1;
      if m == '%q' then self(args[i]) else self:write(sfmt(m, args[i])) end
    end
  end)
  self:write(fmt:sub(lasti))
  return i
end

--- like string.format but use [$Fmt] for [$%q].
--- Doesn't return the string, instead writes to [$Fmt]
function Fmt:format(fmt, ...) --> varargsUsed
  return self:formatArgs(fmt, {...})
end

--- fmt ... separated by sep
function Fmt:concat(sep, ...) --> self
  self(select(1, ...))
  for i=2,select('#', ...) do
    self:write(sep); self(select(i, ...))
  end
  return self
end
--- fmt ... separated by tabs
function Fmt:tabulated(...) return self:concat('\t', ...) end

--- fmt ... separated by newlines
function Fmt:lined(...) return self:concat('\n', ...) end

--- Returns the concattenated string written to the
--- formatter.[{br}]
--- Error if [$to] is set.
function Fmt:tostring()
  assert(not self.to, 'tostring called while storing to object')
  return concat(self)
end
function Fmt:__tostring() return 'fmt.Fmt{}' end

--- Similar to lua's [$tostring()] function except formats
--- tables/types.
function M.tostring(v, fmt)
  fmt = fmt or Fmt{}; assert(#fmt == 0, 'non-empty Fmt')
  return concat(fmt(v))
end

--- Similar to lua's [$string.format(...)] function
--- except [$%q] formats tables/types.
function M.format(fmt, ...)
  local f = Fmt{}
  assert(f:format(fmt, ...) == select('#', ...),
         'invalid number of %args')
  return concat(f)
end
local format = M.format

--- Shortcut for [$error(fmt.format(...))]
function M.errorf(...) error(format(...), 2) end

--- Asserts [$a] else throws [$error(fmt.format(...))].
function M.assertf(a, ...) --> a
  return a or error(format(...), 2)
end

--- Writes the formatted arguments to [$f].
function M.fprint(fmter, ...)
  assert(fmter, 'must set fmter')
  local a, len = {...}, select('#', ...)
  for i=1,len do
    local v = a[i]
    if type(v) == 'string' then fmter:write(v) else fmter(v) end
    if i < len then fmter:write'\t' end
  end; fmter:write'\n'
end
local fprint = M.fprint

--- [$print(...)] but using [$io.fmt].
function M.print(...) return fprint(io.fmt, ...) end

--- pretty print
function M.pprint(...)
  local f; if io.fmt then
    f = {}
    for k,v in pairs(io.fmt) do f[k] = v end
    setmetatable(f, getmetatable(io.fmt))
    f:toPretty()
  end
  return M.fprint(f, ...)
end

--- pretty format the value
function M.pretty(v) return concat(Fmt:pretty{}(v)) end --> string

--- Set to __fmt to format a type like a table.
function M.table(tbl, fmter) return fmter:rawtable(tbl) end

--- directly call fmt for better [$tostring]
getmt(M).__call = function(_, v) return concat(Fmt{}(v)) end
return M