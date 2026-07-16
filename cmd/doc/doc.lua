#!/usr/bin/env -S lua
local shim = require'shim'

--- Usage: [$doc some.symbol]
local doc = shim.cmd'doc-cmd' {
  __cmd='doc',
  'to [string|file]: where to write output.',
}

local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'
local pod = require'pod'
local info = require'ds.log'.info
local warn = require'ds.log'.warn
local cxt = require'cxt'
local lines = require'lines'

local sfmt, srep = string.format, string.rep
local push = ds.push
local assertf = fmt.assertf

local EMPTY = {}

--- Find the object/name or return nil.
function doc.tryfind(obj) --> any?
  if type(obj) ~= 'string' then return obj end
  return G.MOD_LOOKUP[obj] or ds.wantpath(obj)
end

--- Find the object/name.
function doc.find(obj) --> any
  return assertf(doc.tryfind(obj), '%q could not be found', obj)
end

--- Given a list of comment lines strip the '---' from them.
function doc.stripComments(c)
  if #c == 0 then return c end
  local ind = c[1]:match'^%s*%-%-%-(%s+)' or ''
  local pat = '^%s*%-%-%-'..string.rep('%s?', #ind)..'(.*)%s*'
  for i, ln in ipairs(c) do c[i] = ln:match(pat) or ln end
  return c
end

--- Object passed to __doc methods.
--- Aids in writing cxt.
doc.Doc = mty'Doc' {
  'to [file]: file to write to.',
  'indent [string]', indent = '  ',
  'done [table]: already documented items',
  '_level [int]: intent level', _level = 0,
  '_nl [string]',               _nl    = '\n',

  'modHeader [int]: mod header lvl',         modHeader = 3,
  'tyHeader  [int]: type/record header lvl', tyHeader = 4,
}
getmetatable(doc.Doc).__call = function(R, self)
  self.done = self.done or {}
  return mty.construct(R, self)
end

doc.Doc.level  = fmt.Fmt.level
doc.Doc._write = fmt.Fmt._write
doc.Doc.write  = fmt.Fmt.write
doc.Doc.flush  = fmt.Fmt.flush
doc.Doc.close  = fmt.Fmt.close

--- Check that lines parse.
function doc.Doc:check(name, lns)
  cxt.parse(type(lns)=='string' and lines(lns) or lns, false,
            'name:'..(name or '(unknown)'))
end

function doc.Doc:bold(text) self:write(sfmt('[*%s]', text)) end
function doc.Doc:code(code) self:write(cxt.code(code))      end

function doc.Doc:link(link, text)
  if text then self:write(sfmt('[<%s>%s]', link, text))
  else         self:write(sfmt('[<%s>]', link)) end
end

function doc.Doc:named(name, id)
  self:write(sfmt('[{name=%s}%s]', id or name, assert(name)))
end

function doc.Doc:header(lvl, content, name)
  assertf(1 <= lvl and lvl <= 6, 'header lvl %s must be [1-6]', lvl)
  if name then
    self:write(sfmt('[{h%s name=%s}%s]\n', lvl, name, content))
  else
    self:write(sfmt('[{h%s}%s]\n', lvl, content))
  end
end

function doc.Doc:anyExtract(obj) --> name, loc, cmt, code
  local name, loc = mty.anyinfo(obj)
  return name, loc, self:extractCode(loc)
end

function doc.Doc:extractCode(loc) --> (commentLines, codeLines)
  if not loc then return end
  if type(loc) ~= 'string' then loc = select(2, mty.anyinfo(loc)) end
  if not loc or loc:find'%[' then return end
  local path, locLine = loc:match'(.*):(%d+)'
  if not path then error('loc path invalid: '..loc) end
  local l, lines, locLine = 1, ds.Deq{}, tonumber(locLine)
  local l, lines = 1, ds.Deq{}
  for line in io.lines(path) do -- starting line with 256 lines above.
    lines:push(line); if #lines > 256 then lines:pop() end
    if l == locLine then break end
    l = l + 1
  end
  assert(l == locLine, 'file not long enough')
  -- move the lines to a normal (non Deq) table and put in reverse order.
  lines = ds.reverse(table.move(lines, lines.left, lines.right, 1, {}))
  -- find where the code ends, then get all '---' comments.
  local code, cmts = {}, {}
  for l, line in ipairs(lines) do
    if line:find'^function' or line:find'^%w[^-=]+=' then
      table.move(lines, 1, l, 1, code); break
    end
  end
  for l=#code+1, #lines+1 do local
    line = lines[l]
    if not line or not line:find'^%s*%-%-%-' then
      table.move(lines, #code+1, l-1, 1, cmts); break
    end
  end
  cmts = doc.stripComments(ds.reverse(cmts))
  while #cmts > 0 and not cmts[#cmts]:match'%S' do
    cmts[#cmts] = nil
  end
  return cmts, ds.reverse(code)
end

--- Extract the function signature from the lines of code.
function doc.Doc:fnsig(code) --> (string, isMethod)
  if not code or not code[1] then return end
  code = code[1]
  local         s, r = code:match'(%b()).*%-%->%s*(.*)'
  if not s then s, r = code:match'(%b{}).*%-%->%s*(.*)' end
  if not s then
    s, r = code:match'function(%b()).*return%s*(.-)%s*end'
  end
  if not s then s    = code:match'function.*(%b())' end
  if not s then return end
  local sig = (s or '(...)')..(r and sfmt(' -> %s', r) or '')
  return sig, code:match'function[^(]+:' and true
end

--- Declare the function definition
function doc.Doc:declfn(fn, name, id) --> (cmt, sig, isMethod)
  local pname, loc  = mty.anyinfo(fn)
  local cmt, code   = self:extractCode(loc)
  local sig, isMeth = self:fnsig(code)
  name = (isMeth and 'fn:' or 'fn ')..(name or pname)
  if id then self:write(sfmt('[{*name=%s}%s]', id, name))
  else       self:bold(name) end
  if sig and sig ~= '' then self:code(sig) end
  if cmt and #cmt > 0 then
    self:check(pname, cmt)
    self:write'[{br}]\n'
    for i, c in ipairs(cmt) do
      self:write(c); if i < #cmt then self:write'\n' end
    end
  end
  return cmt, sig, isMeth
end

--- Document the module.
function doc.Doc:mod(m)
  local name, loc = mty.anyinfo(m)
  local cmts, code = self:extractCode(loc)
  self:header(3, 'Mod '..m.__name, m.__name)
  self:check(name, cmts or EMPTY)
  for _, c in ipairs(cmts or EMPTY) do
    self:write(c); self:write'\n\n'
  end
  return self:endmod(m, 'Functions')
end

--- Document the end (not header+comments) of module.
function doc.Doc:endmod(m, fnsName)
  local names = {}
  local fns, tys, oth = {}, {}, {}
  for _, k in ipairs(m.__attrs) do
    if k:match'^_' then goto continue end
    local v = rawget(m, k);
    if self.done[v] then goto continue end
    if v == nil then
      warn('%s.%s is in __attrs but no longer exists', m.__name, k)
      goto continue
    end
    names[v] = k
    if     type(v) == 'function'                     then push(fns, v)
    elseif type(v) == 'table' and rawget(v, '__doc') then push(tys, v)
    else push(oth, v) end
    ::continue::
  end

  if #tys > 0 then
    self:write'\n'; self:bold'Types: ';
    for _, ty in ipairs(tys) do
      self:level(1)
      self:link(sfmt('#%s.%s', m.__name, names[ty]), names[ty])
      self:level(-1); self:write' '
    end
    self:write'\n\n'
  end

  if #fns > 0 then
    self:bold(fnsName); self:write' [+\n'; 
    for _, fn in ipairs(fns) do
      self:write'* '; self:level(1)
      self:declfn(fn, names[fn], sfmt('%s.%s', m.__name, names[fn]))
      self:level(-1); self:write'\n'
    end
    self:write']\n'
  end

  for _, ty in ipairs(tys) do
    self:write'\n'; rawget(ty, '__doc')(ty, self)
  end
end

function doc.Doc:__call(name, obj, cmts)
  local ty = type(obj)
  if ty == 'function' then return self:declfn(obj) end
  if ty == 'table' and rawget(obj, '__doc') then
    return rawget(obj, '__doc')(obj, self)
  end
  local name, loc = mty.anyinfo(obj)
  local cmt, code = self:extractCode(loc)
  self:bold(name); self:write': raw '; self:code(ty) self:write'\n'
  if cmts and cmt and #cmt > 0 then
    for _, c in ipairs(cmts) do self:write(c) self:write'\n' end
  end
end

--- usage: [$doc{'any.symbol', '--to=optionalOutput.cxt'}]
function doc:__call()
  info('doc %q', self)
  assert(#self > 0, 'usage: doc any.symbol')
  local d = doc.Doc{to=assert(shim.file(self.to, io.stderr))}
  for _, obj in ipairs(self) do
    if type(obj) == 'string' then obj = doc.find(obj) end
    local name = G.MOD_NAMES[obj]
    dbg('doc', name, obj)
    d(name or '(unknown)', obj); d:write'\n'
  end
end

if shim.isMain(doc) then doc:main(arg) end
return doc