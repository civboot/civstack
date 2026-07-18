G = G or _G
--- Helper methods for moving a cursor around a lines-like 2D grid.
--- The notation [$l.c] is used to refer to line, column where
--- both are indexed by 1.
local M = mod and mod'lines.motion' or {}

local mty = require'metaty'
local ds = require'ds'
local match, sfmt            = mty.from(string, 'match, format')
local sort2, bound, isWithin = mty.from(ds, 'sort2,bound,isWithin')
local min, max               = mty.from(math, 'min,max')

local byte, char = string.byte, string.char
local get = ds.get

--- Move [$s] closer to [$e] by 1.[{br}]
--- If they are equal do nothing.
function M.decDistance(s, e) --> int
  if s == e then return e end
  return (s < e) and (e - 1) or (e + 1)
end

--- Return whether [$l.c] is equal to or before [$l2.c2].
function M.lcLe(l, c, l2, c2) --> bool
  if l == l2 then return c <= c2 end
  return l < l2
end

--- Return whether [$l.c] is equal to or after [$l2.c2]
function M.lcGe(l, c, l2, c2) --> bool
  if l == l2 then return c >= c2 end
  return l > l2
end

--- Return the top-left (aka the minimum) of two points.
function M.topLeft(l,c, l2,c2) --> (l, c)
  if not c then
    assert(not c2); return sort2(l, l2), 1
  end
  if l == l2 then return l, min(c, c2) end
  if l <  l2 then return l, c end
  return l2, c2
end

-- Return whether [$l.c] is between [$l1.c1 - l2.c2] (inclusive).
function M.lcWithin(l, c, l1, c1, l2, c2) --> bool
  if l1 > l2 then l1, c1, l2, c2 = l2, c2, l1, c1
  elseif l1 == l2 then
    c1, c2 = sort2(c1, c2)
    return l == l1 and isWithin(c, c1, c2)
  end
  if isWithin(l, l1, l2) then
    if l == l1 then return c >= c1 end -- bottom
    if l == l2 then return c <= c2 end -- top
    return true
  end
  return false
end

local WordKind = {}; M.WordKind = WordKind
for c=0, 127 do
  local ch, kind = char(c), nil
  if 0 <= c and ch <= ' '        then kind = 'ws'
  elseif '1' <= ch and ch <= '9' then -- nil
  elseif 'a' <= ch and ch <= 'z' then -- nil
  elseif 'A' <= ch and ch <= 'Z' then -- nil
  elseif ch == '_'               then -- nil
  else kind = 'sym' end
  WordKind[ch] = kind
end

WordKind['('] = '()'; WordKind[')'] = '()'
WordKind['['] = '[]'; WordKind[']'] = '[]'
WordKind['{'] = '{}'; WordKind['}'] = '{}'
WordKind['"'] = '"'   WordKind["'"] = "'"

--- Given a character, return it's word-kind:
--- ws (whitespace), sym (symbol), let (letter).
function M.wordKind(ch) --> ws|sym|let
  return WordKind[ch] or 'let' -- letter
end

M.PathKind = ds.copy(M.WordKind); local PathKind = M.PathKind
for _, c in ipairs{'/', '.', '-', ':', '#'} do
  M.PathKind[c] = nil
end

--- Given a character, return it's path-kind:
--- ws (whitespace), sym (symbol), path (path)
function M.pathKind(ch) --> ws|sym|path
  return PathKind[ch] or 'path'
end

--- Get the start of the next word from si (start-index).
function M.forword(s, si, getKind) --> int
  si, getKind = si or 1, getKind or M.wordKind
  local i, kStart = si+1, getKind(s:sub(si,si))
  for ch in string.gmatch(s:sub(si+1), '.') do
    local k = getKind(ch)
    if k ~= kStart then
      if kStart ~= 'ws' and k == 'ws' then
        kStart = 'ws' -- find first non-whitespace
      else return i end
    end
    i = i + 1
  end
end

--- Get the start of the previous word from ei (end-index).
function M.backword(s, ei, getKind) --> int
  getKind = getKind or M.wordKind
  s = s:sub(1, ei-1):reverse()
  local i, kStart = 2, getKind(s:sub(1,1))
  for ch in string.gmatch(s:sub(2), '.') do
    local k = getKind(ch)
    if k ~= kStart then
      if kStart == 'ws' then kStart = k
      else return #s - i + 2 end
    end
    i = i + 1
  end
end

--- get the [$$range[si,ei]]$ of whatever is at [$$s[i]]$.
function M.getRange(s, i, getKind) --> si,ei
  getKind = getKind or M.wordKind
  local si, ei = i,i; if ei < i then return nil end
  local kind = getKind(s:sub(i,i))
  for k = i-1, 1, -1 do
    if kind == getKind(s:sub(k,k)) then si=k
    else break end
  end
  for k = i+1, #s do
    if kind == getKind(s:sub(k,k)) then ei=k
    else break end
  end
  return si, ei
end

--- find backwards from ei (end index).[{br}]
--- This searches for the pattern and returns the LAST one found.
--- This is HORRIBLY non-performant, only use for small amounts of data (like a
--- line).
function M.findBack(s, pat, ei, plain) --> int
  local s, fs, fe = s:sub(1, ei), nil, 0
  assert(#s < 256)
  while true do
    local _fs, _fe = s:find(pat, fe + 1, plain)
    if not _fs then break end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

return M