local mty = require'metaty'

--- The lines module, providing a uniform API for lines-like objects.
---
--- ["You can also call this module directly to get a table of lines
---   from a string]
local M = mty.mod'lines'

local ds  = require'ds'

local info                    = mty.from'ds.log  info'
local match, sfmt, ssub, srep = mty.from(string, 'match, format, sub, rep')
local push, pop, concat       = mty.from(table, 'insert, remove, concat')
local max, min, ibound        = math.max, math.min, ds.bound
local sort2, set, get, inset  = mty.from'ds  sort2,set,get,inset'
local rawsplit                = mty.rawsplit

M.CMAX = 999
M.CHUNK = 0x4000 -- 16KiB

getmetatable(M).__call = function(_, text, index)
  local t = {}
  for _, line in rawsplit, text, {'\n', index or 1} do
    push(t, line)
  end; return t
end
local new = getmetatable(M).__call

--- Join a table of strings with newlines.
function M.join(t) return concat(t, '\n') end --> string
local join = M.join

--- Enables addressing lines via either (l,l2) or (l,c, l2,c2) span.
function M.span(l, c, l2, c2) --> (l, c?, l2, c2?)
  if      l2 and c2 then return l, c, l2, c2  end --(l,c, l2,c2)
  if not (l2 or c2) then return l, 1, c+1, 0  end --(l,   l2)
  if not (c  or c2) and (l and l2) then
    return l, 1, l2+1, 0
  end --(l,   l2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end
local span = M.span

--- Bound the line/col for the lines table.[+
--- * [$l] will be from [$1 to #t+1].
--- * [$c] will be from [$$0 to #t[l]+1]$.
--- ]
--- [$tlen] is precomputed [$#t] and [$line] is pre-fetched [$$t[l]]$
---
--- This can handle negative integers.
function M.bound(t, l,c, tlen, ln) --> l, c
  tlen = tlen or #t; assert(l and c)
  if l < 0 then l = #t + l + 1 end
  l = ibound(l, 1, max(1, tlen + 1))
  local lnLen = #(ln or get(t, l) or '')
  if c == 'end' then c = lnLen + 1
  elseif c < 0  then c = lnLen + c + 1 end
  -- if c > lnLen then return ibound(l+1, 1, tlen+1), 0 end
  return l, ibound(c, 0, lnLen + 1)
end
local bound = M.bound

--- Bound a span from [$l,c -> l2,c2].
function M.boundSpan(t, l,c, l2,c2, tlen)
  tlen = tlen or #t
  local l,c, l2,c2 = span(l,c, l2,c2)
  assert(c and c2) -- FIXME: remove
  l,c   = bound(t, l,c, tlen)
  if l2 > #t then l2,c2 = tlen+1, 0 end
  if c2 > #(get(t,l2) or '') then l2,c2 = l2+1,0 end
  return l,c, bound(t, l2,c2, tlen)
end
local boundSpan = M.boundSpan

function M._args(...) --> lines
  local len = select('#', ...)
  if     len == 0 then return {}
  elseif len == 1 then return new(nil, select(1, ...))
  else                 return new(nil, concat{...}) end
end
local args = M._args

--- insert string at l, c[{br}]
---
--- Note: this is NOT performant (O(N)) for large tables.[{br}]
--- See: [<#Gap>] (or similar) for handling real-world workloads.
function M.insert(t, ins, l,c) --> nil
  ins = type(ins) == 'string' and M(ins) or ds.icopy(ins)
  if #ins == 0 then return end
  local ln = get(t,l) or ''
  local lnSt, lnEnd = ssub(ln, 1, c-1), ssub(ln, c) -- start,end
  local insLen = #ins
  if insLen == 1 then -- only one, just insert it
    return set(t,l, lnSt..ins[1]..lnEnd)
  end
  -- update start and end to preserve original
  ins[1]      = lnSt..ins[1]
  ins[insLen] = ins[insLen]..lnEnd
  inset(t, l, ins, 1)
end

--- Sort the span
function M.sort(...) --> l1, c1, l2, c2
  local l, c, l2, c2 = span(...)
  if l > l2 then l, c, l2, c2 = l2, c2, l, c
  elseif c and (l == l2) and (c > c2) then c, c2 = c2, c end
  return l, c, l2, c2
end

local function _lsub(sub, slen, t, l,c, l2,c2) --> {str}, l,c, l2,c2
  local len = #t
  l,c, l2,c2 = boundSpan(t, l,c, l2,c2, len)

  local s = {}
  if l > len or l > l2 then goto done end
  if l == l2 then
    push(s, sub(get(t,l), c,c2))
    goto done
  end
  push(s, sub(get(t,l), c))
  for i=l+1,l2-1 do push(s, get(t, i)) end
  if l2 <= len then
    push(s, sub(get(t,l2), 1,c2))
  end
  ::done::
  if c2 == 0 then
    l2 = l2-1; local ln2 = get(t,l2)
    c2 = ln2 and (#ln2+1) or 0
  end
  return s, l,c, l2,c2
end

--- Get the sub-span of the lines.[{br}]
function M.sub(l, ...) --> {str}, l,c
  return _lsub(string.sub, string.len, l, ...)
end

--- Get the UTF8 aware sub-span of the lines.[{br}]
function M.usub(l, ...) --> {str}, l,c
  return _lsub(ds.usub, utf8.len, l, ...)
end

--- create a table of lineText -> {lineNums}
function M.map(lines) --> table
  local map = {}; for l, line in ipairs(lines) do
    push(ds.getOrSet(map, line, ds.emptyTable), l)
  end
  return map
end

--- Get the [$l, c] with the +/- offset applied
function M.offset(t, off, l,c) --> l2,c2
  -- FIXME: bound l/c correctly.
  local len, off2, llen, ln = #t
  l,c = bound(t, l,c, len)
  if off > 0 then ::loopGt::
    ln = get(t,l); if not ln then return l-1,#get(t,l-1) + 1 end
    -- off2: what remains of offset if we use whole line (+newline)
    off2 = off - (#ln+1 - c)
    if off2 <= 0 then return l, c + off end
    off = off2
    l,c = l+1,0
    goto loopGt
  end
  if off == 0 then return l,c end
  if l > len then
    l,c = len, #(get(t,len) or '') + 1
  end
  if not get(t,l) then return 1,1 end
  while true do -- negative offset
    -- off2: what remains of offset if we use whole line
    off2 = off + c
    if off2 > 0 then return l, off2 end
    off, l = off2, l-1
    ln = get(t,l); if not ln then return 1,1 end
    c = #ln+1
  end
end

--- get the byte offset 
function M.offsetOf(t, l,c, l2,c2) --> int
  local len, off, sign = #t, 0
  if     l < l2 then sign = 1
  elseif l > l2 then sign = -1
  else               sign = (c <= c2) and 1 or -1 end
  if sign < 0 then l,c, l2,c2 = l2,c2, l,c end
  l,c, l2,c2 = M.boundSpan(t, l,c, l2,c2, len)
  -- determine direction. We always calculate
  -- in positive direction.
  while l < l2 do
    off = off + #get(t,l) + 1 - c
    l,c = l+1,0
  end
  return sign * (off + c2 - c)
end


--- find the pattern starting at l/c
--- Note: matches are only within a single line.
function M.find(t, pat, l,c) --> (l, c, c2)
  l, c = bound(t, l or 1, c or 1)
  local c2
  while true do
    local s = get(t,l)
    if not s then return nil end
    c,c2 = s:find(pat, c); if c then return l, c,c2 end
    l, c = l + 1, 1
  end
end

local function sfindBack(s, pat, ei)
  local s, fs, fe = s:sub(1, ei), nil, 0
  assert(#s < 256)
  info('@@ sfindBack pat=%q', pat)
  while true do
    info('@@ + %q %s', s, fe+1)
    local _fs, _fe = s:find(pat, fe + 1)
    if not _fs then break end
    if _fs > _fe then return end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

--- find the pattern (backwards) starting at l/c
function M.findBack(t, pat, l,c)
  l, c = bound(t, l or 1, c or (#get(t,l) + 1))
  local c2
  while true do
    info('@@ findBack l=%s', l)
    local s = get(t,l)
    if not s then return nil end
    c,c2 = sfindBack(s, pat, c)
    if c then return l, c,c2 end
    l, c = l - 1, nil
  end
end

--- remove span (l, c) -> (l2, c2), return what was removed
function M.remove(t, l,c, l2,c2) --> string|table
  local sub = string.sub
  local len = #t
  l,c, l2,c2 = boundSpan(t, l,c, l2,c2, len)

  if l > len or l > l2 then return {} end
  local ln = get(t,l)
  if l == l2 then
    set(t,l, sub(ln, 1,c-1)..sub(ln, c2+1))
    return { sub(ln, c,c2) }
  end
  -- calculate removed lines (identical to M.sub)
  local rm = { sub(ln, c) }
  for i=l+1,l2-1 do push(rm, get(t,i)) end
  local ln2 = get(t,l2) or ''
  if l2 <= len then
    push(rm, sub(ln2, 1,c2))
  end

  -- join first+last line
  local keep = {}
  if c > 1 or l2 <= len then
    push(keep, sub(ln, 1,c-1)..sub(ln2 or '', c2+1))
  end

  ds.inset(t, l, keep, l2 - l + 1)
  return rm
end

--- return the box of the lines.
---
--- [$$
--- Outside the box is not returned.
--- ***1------------------------+**
--- ***|l1,c1 = top left        |**
--- ***|       bot right = l2,c2|
--- ***+------------------------2**
--- *So no '*' chars are returned.*
--- ]$
function M.box(t, l1, c1, l2, c2, fill) --> lines
  local f = fill and assert(type(fill) == 'string') and (c2 - c1 + 1)
  local b = {}; for l=l1,l2 do
    local line = get(t,l)
    line = line and line:sub(c1, c2) or ''
    if fill and #line < f then line = line..srep(fill, f - #line) end
    push(b, line)
  end
  return b
end

--- Get the indentation of line.
function M.getIndent(t, l) --> str?
  local ln = get(t,l) or 'z'
  local ind = ln:match'^(%s*)'
  if #ind > 0 then return ind end
  if #ln > 0  then return ''  end
end

--- Get the autoIndent to use for line.
function M.autoIndent(t, l) --> string?
  local ind
  for i=l+1,#t do
    ind = M.getIndent(t,i); if ind then
      if ind ~= '' then return ind else break end
    end
  end
  for i=l-1,1,-1 do
    ind = M.getIndent(t,i); if ind then
      if ind ~= '' then return ind else break end
    end
  end
end

-------------------------
-- Save / Load from file

--- load lines from file or path. On error return (nil, errstr)
function M.load(f, close) --> (table?, errstr?)
  local err
  if type(f) == 'string' then close, f, err = true, io.open(f, 'r') end
  if f == nil then return nil, err or 'load(f=nil)' end
  local i, t = 1, {}
  for line in f:lines() do set(t,i, line); i = i + 1 end
  if close then f:close() end
  return t
end

--- write lines [$t] to file [$f] in chunks (default = 16KiB)
--- if f is a string then it is opened as a file and closed when done
function M.dump(t, f, close, chunk)
  if type(f) == 'string' then
    f = assert(io.open(f, 'w')); close = true
  end
  if #t == 0 then
    if close then f:close() end
    return
  end
  local dat, len, chunk = {}, 0, chunk or M.CHUNK
  for i=1,#t-1 do; local line = get(t, i)
    push(dat, line); len = len + #line + 1
    if len >= chunk then
      assert(f:write(concat(dat, '\n')):write'\n')
      ds.clear(dat)
      len = 0
    end
  end
  push(dat, get(t, #t))
  assert(f:write(concat(dat, '\n')))
  if close then f:close() end
end

--- Logic to make a table behave like a [$file:write(...)] method.
---
--- This is NOT performant, especially for large lines.
function M.write(t, ...) --> true
  local w = args(...); if #w == 0 then return true end
  local len, first = #t, w[1]
  if first ~= '' then
    if len == 0 then set(t,1, first)
    else             set(t,len, get(t,len)..first) end
  end
  for i=2,#w do set(t, len + i - 1, w[i]) end
  return true
end

return M
