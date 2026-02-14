local mty = require'metaty'

--- The lines module, providing a uniform API for lines-like objects.
---
--- ["You can also call this module directly to get a table of lines
---   from a string]
local M = mty.mod'lines'

local ds  = require'ds'

local info = mty.from'ds.log  info'
local push, pop = table.insert, table.remove
local concat    = table.concat
local max, min, bound = math.max, math.min, ds.bound
local srep = string.rep
local sort2 = ds.sort2
local rawsplit = mty.rawsplit

local set, get, inset = ds.set, ds.get, ds.inset

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

function M._args(...) --> lines
  local len = select('#', ...)
  if     len == 0 then return {}
  elseif len == 1 then return new(nil, select(1, ...))
  else                 return new(nil, concat{...}) end
end
local args = M._args

local function sinsert (s, i, v)
  return s:sub(1, i-1)..v..s:sub(i)
end

--- insert string at l, c[{br}]
---
--- Note: this is NOT performant (O(N)) for large tables.[{br}]
--- See: [<#Gap>] (or similar) for handling real-world workloads.
function M.insert(t, s, l,c) --> nil
  inset(t, l, M(sinsert(get(t, l) or '', c or 1, s)), 1)
end

--- Enables addressing lines via either (l,l2) or (l,c, l2,c2) span.
function M.span(l, c, l2, c2) --> (l, c?, l2, c2?)
  if      l2 and c2 then return l, c, l2, c2    end --(l,c, l2,c2)
  if not (l2 or c2) then return l, nil, c, nil  end --(l,   l2)
  if not (c  or c2) and (l and l2) then
    return l, nil, l2, nil
  end --(l,   l2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end
local span = M.span

--- Sort the span
function M.sort(...) --> l1, c1, l2, c2
  local l, c, l2, c2 = span(...)
  if l > l2 then l, c, l2, c2 = l2, c2, l, c
  elseif c and (l == l2) and (c > c2) then c, c2 = c2, c end
  return l, c, l2, c2
end

local function _lsub(sub, slen, t, ...)
  local l, c, l2, c2 = span(...)
  local len = #t
  local lb, lb2 = ds.bound(l, 1, len), ds.bound(l2, 1, len+1)
  if lb  > l  then c = 1 end
  if lb2 < l2 then c2 = nil end -- EoL
  l, l2 = lb, lb2
  local s = {} -- s is sub
  for i=l,l2 do push(s, get(t, i)) end
  if    nil == c then -- only lines
    if l2 < len then push(s, '') end -- newline
  elseif #s == 0 then s = '' -- empty
  elseif l == l2 then
    assert(1 == #s); local line = s[1]
     s = sub(line, c, c2)
    if c2 > slen(line) and l2 < len then s = s..'\n' end
  else
    local last = s[#s]
    s[1] = sub(s[1], c); s[#s] = sub(last, 1, c2)
    if c2 > #last and l2 < len then push(s, '') end
    s = join(s)
  end
  return s
end

--- Get the sub-span of the lines.[{br}]
--- Returns a string if the result is a single line, else a table of lines.
function M.sub(l, ...) --> string | table
  return _lsub(string.sub, string.len, l, ...)
end

--- Get the UTF8 aware sub-span of the lines.[{br}]
--- Returns a string if the result is a single line, else a table of lines.
function M.usub(l, ...) --> string | table
  return _lsub(ds.usub, utf8.len, l, ...)
end

--- create a table of lineText -> {lineNums}
function M.map(lines) --> table
  local map = {}; for l, line in ipairs(lines) do
    push(ds.getOrSet(map, line, ds.emptyTable), l)
  end
  return map
end

--- Bound the line/col for the lines table.[+
--- * [$l] will be from [$1 -#t ].
--- * [$c] will be from [$$1 - (#t[l]+1)]$.
--- ]
--- [$len] is precomputed [$t] and [$line] is pre-fetched [$$t[l]]$
---
--- This can handle negative integers.
function M.bound(t, l, c, len, line) --> l, c
  assert(l and c)
  if l < 0 then l = #t + l + 1 end
  l = bound(l, 1, max(1, len or #t))
  line = line or get(t, l) or ''
  if c == 'end' then c = #line + 1  end
  if c < 0  then c = #line + c + 1  end
  return l, bound(c, 1, #line + 1)
end

--- Get the [$l, c] with the +/- offset applied
function M.offset(t, off, l, c) --> l, c
  local len, m, llen, line = #t
  -- 0 based index for column
  l = bound(l, 1, len); c = bound(c - 1, 0, #get(t,l))
  while off > 0 do
    line = get(t, l)
    if nil == line then return len, #get(t,len) + 1 end
    llen = #line + 1 -- +1 is for the newline
    c = bound(c, 0, llen); m = llen - c
    if m > off then c = c + off; off = 0;
    else l, c, off = l + 1, 0, off - m
    end
    if l > len then return len, #get(t,len) + 1 end
  end
  while off < 0 do
    line = get(t,l)
    if nil == line then return 1, 1 end
    llen = #line
    c = bound(c, 0, llen); m = -c - 1
    if m < off then c = c + off; off = 0
    else l, c, off = l - 1, M.CMAX, off - m
    end
    if l <= 0 then return 1, 1 end
  end
  l = bound(l, 1, len)
  return l, bound(c, 0, #get(t,l)) + 1
end

--- get the byte offset 
function M.offsetOf(t, l,c, l2,c2) --> int
  local off, len, llen = 0, #t
  l,c = M.bound(t, l,c, len);  l2,c2 = M.bound(t, l2,c2, len)
  c, c2 = c - 1, c2 - 1 -- column math is 0-indexed
  while l < l2 do
    llen = #get(t,l) + 1
    c = bound(c, 0, llen)
    off = off + (llen - c)
    l, c = l + 1, 0
  end
  while l > l2 do
    llen = #get(t,l) + ((l==len and 0) or 1)
    c = bound(c, 0, llen)
    off = off - c
    l, c = l - 1, M.CMAX
  end
  llen = #get(t,l) + ((l==len and 0) or 1)
  c, c2 = bound(c, 0, llen), bound(c2, 0, llen)
  off = off + (c2 - c)
  return off
end

--- find the pattern starting at l/c
--- Note: matches are only within a single line.
function M.find(t, pat, l,c) --> (l, c, c2)
  l, c = M.bound(t, l or 1, c or 1)
  local c2
  while true do
    local s = get(t,l)
    if not s then return nil end
    c,c2 = s:find(pat, c); if c then return l, c,c2 end
    l, c = l + 1, 1
  end
end

local function findBack(s, pat, end_)
  local s, fs, fe = s:sub(1, end_), nil, 0
  assert(#s < 256)
  while true do
    local _fs, _fe = s:find(pat, fe + 1)
    if not _fs then break end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

--- find the pattern (backwards) starting at l/c
function M.findBack(t, pat, l,c)
  l, c = M.bound(t, l or 1, c or (#get(t,l) + 1))
  local c2
  while true do
    local s = get(t,l)
    if not s then return nil end
    c,c2 = findBack(s, pat, c)
    if c then return l, c,c2 end
    l, c = l - 1, nil
  end
end

--- remove span (l, c) -> (l2, c2), return what was removed
function M.remove(t, ...) --> string|table
  local l, c, l2, c2 = span(...);
  info('@@ lines.remove %s.%s - %s.%s', l,c, l2,c2)
  c, c2 = c or 1, c2 or #get(t,l2) + 1
  local len = #t
  if l2 > len then l2, c2 = len, #get(t,len) + 1 end
  info('@@ + %s.%s - %s.%s', l,c, l2,c2)
  if l > l2 then return {} end
  local rem, new = {}, {}
  if l == l2 then -- same line
    info'@@ + same line'
    if c <= c2 then
      local line = get(t,l); local llen = #line
      if c2 > llen then -- include newline
        if c > 1 then
          l2 = l2 + 1
          new[1] = line:sub(1, c-1)..(get(t,l2) or '')
        end
        rem[1] = line:sub(c, c2)
      else -- include newline in removal
        new[1] = line:sub(1, c-1)..line:sub(c2+1)
        rem[1] = line:sub(c, c2)
      end
    end
  else -- spans multiple lines
    local line = get(t,l)
    rem[1] = line:sub(c)
    local l1 = l
    if c <= 1     then -- skip, remove whole line
    -- elseif c is within first line then get sub-string of line
    elseif c <= #line then new[1] = line:sub(1, c - 1)
    -- else join first+second line
    else l1 = l+1;         new[1] = line..(get(t,l1) or '') end
    for i=l1+1,l2-1 do push(rem, get(t,i)) end
    if l1 < l2 then
      if c2 > #get(t,l2) then -- include newline
        push(rem, get(t,l2))
      else
        push(rem, get(t,l2):sub(1, c2))
        push(new, get(t,l2):sub(c2 + 1))
      end
    end
  end

  info('@@ + inset %s add=%s rm=%s', l, #new, l2-l+1)
  ds.inset(t, l, new, l2 - l + 1)
  return rem
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
  for i=1,#t-1 do; local line = t[i]
    push(dat, line); len = len + #line + 1
    if len >= chunk then
      push(dat, '\n')
      assert(f:write(concat(dat, '\n')))
      ds.clear(dat)
      len = 0
    end
  end
  push(dat, t[#t])
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
