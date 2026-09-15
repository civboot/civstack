#!/usr/bin/env -S lua
local shim = require'shim'

--- Diffing module and command[{br}]
--- Cmd Usage: [$ldiff 'file/path1.txt' 'file/path2.txt'][{br}]
--- Lib Usage: [$ctx.fmtlog(ldiff.Diff(linesA, linesB))][{br}]
---
--- This library/cmd creates readable diffs using the "patience diff" alorithm.
--- The code was written from scratch referencing only the algorithm outline
--- below, but I want to give special thanks to James Coglan for his
--- [<https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm>
---  excellent blog post].
---
---
--- Fundamentals of patience diff: [+
--- * Skip unchanged lines on both top and bottom.
--- * Find unique lines in both sets and "align" them using "longest increasing
---   sequence".
--- * Repeat for each aligned section.
--- ]
local M = shim.cmd'lines.diff' {}

local mty = require'metaty'
local ds  = require'ds'
local push = table.insert
local clear = ds.clear
local construct = mty.construct
local str, sfmt = tostring, string.format

--- Datastructure which holds the result of computing the difference
--- between two lists of lines.[{br}]
---
--- Fields [$b] and [$c] are just the original base/change lines.
---
--- [$noc], [$rem] and [$add] are lists of integers which represent the length
--- of a block. For instance, if for a given index [$rem=3] and [$add=2] it
--- means that three lines were removed from [$b] and two were added to
--- [$c]. If [$noc=10] that means that there is a block of 10 identical lines.
M.Diff = mty'Diff' {
  'b [lines]: base, aka raw original lines',
  'c [lines]: change, aka raw new lines',
 [[len [int]: len of diff blocks (aka len of below fields).
   It's not possible to use # for below, since some values
   are nil.
 ]],
  'noc [ints]: nochange range (in both)',
  'rem [ints]: removed from b',
  'add [ints]: added from c',
}
local Diff = M.Diff

--- [$c] is a table of [$lineStr -> lineNum].
--- The first time [$lineStr] is found the line number [$l] is stored.
--- If found again, the stored line is set to false (and remains false),
--- meaning it is not a unique line.
---
--- The [$line] string is also pushed to [$c] so that it can be iterated
--- in-order
local function countLine(c, l, line, pushl)
  local r = c[line]
  if     r == nil   then c[line] = l; if pushl then push(c, line) end
  elseif r ~= false then c[line] = false end
end

--- Returns lists of line numbers which are unique in both [$b] and [$c],
--- ordered by when the appear in b.
local function uniqueMatches(bLines, cLines, b, b2, c, c2) --> bList, cList
  local bcount, ccount = {}, {}
  for i=b,b2 do countLine(bcount, i, bLines[i], true) end
  for i=c,c2 do countLine(ccount, i, cLines[i]) end
  local bl, cl = {}, {}
  for _, line in ipairs(bcount) do
    local b, c = bcount[line], ccount[line]
    if b and c then push(bl, b); push(cl, c); end
  end
  return bl, cl
end

--- Find the stack to the left of where we should place
--- using binary search.
local function findLeftStack(stacks, mc, c)
  local low, high, mid = 0, #stacks + 1
  while low + 1 < high do
    mid = (low + high) // 2
    if mc[stacks[mid]] < c then low  = mid
    else                        high = mid end
  end
  return low
end

--- Get the longest increasing sequence (in reverse order).
local function patienceLIS(mb, mc) --> bList, cList
  local stacks = {}
  local prev, c, i = {}
  for mi, b in ipairs(mb) do
    i = findLeftStack(stacks, mc, mc[mi])
    if i > 0 then prev[mi] = stacks[i] end
    stacks[i+1] = mi
  end
  local mi = stacks[#stacks]; if not mi then return end
  local b, c = {}, {}
  while prev[mi] do push(b, mb[mi]); push(c, mc[mi]); mi = prev[mi] end
  push(b, mb[mi]); push(c, mc[mi])
  return b, c
end

----------------------------
-- Compute the diff

local function skipEqLinesTop(linesB, linesC, b, b2, c, c2) --> bi, ci
  while b <= b2 and c <= c2 do
    if linesB[b] ~= linesC[c] then return b, c end
    b, c = b + 1, c + 1
  end
  return b, c
end

local function skipEqLinesBot(linesB, linesC, b, b2, c, c2) --> bi, ci
  while b <= b2 and c <= c2 do
    if linesB[b2] ~= linesC[c2] then return b2, c2 end
    b2, c2 = b2 - 1, c2 - 1
  end
  return b2, c2
end

function Diff:_calc(b, b2, c, c2)
  local d = self
  local bSt, b2St, cSt, c2St = b, b2, c, c2
  local bNext, cNext
  b,  c  = skipEqLinesTop(d.b, d.c, b, b2, c, c2)
  b2, c2 = skipEqLinesBot(d.b, d.c, b, b2, c, c2)
  assert((c - cSt) == (b - bSt))

  local len
  if c > cSt then len = d.len + 1; d.noc[len] = c - cSt; d.len = len end
  local bl, cl = patienceLIS(uniqueMatches(d.b, d.c, b, b2, c, c2))
  if not bl or #bl == 0 then
    local rm, ad = b2 - b + 1, c2 - c + 1
    if rm == 0 and ad == 0 then -- skip
    else
      len = d.len + 1; d.len = len
      if rm > 0 then d.rem[len] = rm end
      if ad > 0 then d.add[len] = ad end
    end
    goto bottom
  end

  for i=#bl,0,-1 do
    local bm = bl[i]
    if bm then bNext, cNext = bm-1, cl[i]-1
    else       bNext, cNext = b2, c2 end
    d:_calc(b, bNext, c, cNext)
    if not bm then break end
    local cm = cl[i]
    len = d.len + 1; d.noc[len], d.len = 1, len
    b, c = bm + 1, cm + 1
  end
  ::bottom::
  c2 = c2 + 1 -- c2:c2St are unchanged lines (bot)
  if c2 <= c2St then
    len = d.len + 1
    d.noc[len], d.len = c2St - c2 + 1, len
  end
end

--- accumulate list[i] = list[i]+list[j], treating 0 as nil
local function acc(list, i, j)
  local v = (list[i] or 0) + (list[j] or 0)
  if v ~= 0 then list[i] = v end
end

--- compress all like-fields together
function Diff:_compress()
  local d = self
  local add, rem, noc, len = d.add, d.rem, d.noc, d.len
  -- scan the items, accumulating into i from j
  local i, j = 1, 1
  local clearj = function() add[j], rem[j], noc[j] = nil, nil, nil end
  while j <= len do
    if j <= i then j = i + 1 end
    if not (noc[i] or add[i] or rem[i]) then -- empty i
      acc(noc, i, j); acc(add, i, j); acc(rem, i, j)
      clearj(); j = j + 1
    elseif noc[i] then -- accumulate nochanges
      if noc[j] then acc(noc, i, j); noc[j] = nil; j = j + 1
      else i = i + 1 end
    else -- accumulate add/rem
      if add[j] or rem[j] then
         acc(add, i, j); acc(rem, i, j)
         clearj(); j = j + 1
      else i = i + 1 end
    end
  end
  d.len = i
  i = i + 1
  clear(add, i, len)
  clear(rem, i, len)
  clear(noc, i, len)
end

getmetatable(Diff).__call = function(T, linesB, linesC) --> Diff
  if type(linesB) == 'string' then linesB = ds.splitList(linesB, '\n') end
  if type(linesC) == 'string' then linesC = ds.splitList(linesC, '\n') end

  local d = mty.construct(T, {
    b=linesB, c=linesC, len=0, noc={}, rem={}, add={}
  })
  d:_calc(1, #linesB, 1, #linesC)
  d:_compress()
  return d
end

--- Iterate through nochange and change blocks, calling the functions for each
--- [+
--- * [$nocFn(baseStart, numUnchanged, changeStart, numUnchanged)]
--- * [$chgFn(baseStart, numRemoved,   changeStart, numAdded)]
--- ]
--- Note that the num removed/added will be nil if none were added/removed.
function Diff:map(nocFn, chgFn)
  local d = self
  local noc, add, rem = d.noc, d.add, d.rem
  local bl, cl, n, a, r = 1, 1 -- bl=base-line cl=changed-line
  for i=1,d.len do
    n = noc[i]
    if n then -- unchanged lines
      nocFn(bl, n, cl, n)
      bl, cl = bl + n, cl + n
    else
      a, r = add[i], rem[i]
      if a or r then
        chgFn(bl, r, cl, a)
        if r then bl = bl + r end
        if a then cl = cl + a end
      end
    end
  end
end

local function styleNoc(f, base, bl, cl)
  f:styled('line', sfmt('% 5i % 5i ', bl, cl))
  f:styled(nil   , base[bl] or '<eof>', '\n')
end
function Diff:__fmt(f)
  local base, chan = self.b, self.c
  self:map(
    function(bl, n, cl) -- nochange
      if n > 0 then styleNoc(f, base, bl, cl)         end
      if n > 1 then styleNoc(f, base, bl+n-1, cl+n-1) end
    end,
    function(bl, r, cl, a) -- change
      for l=0,(r or 0)-1 do
        f:styled('basel', sfmt('% 5i       ', bl+l))
        f:styled('base', base[bl+l], '\n')
      end
      for l=0,(a or 0)-1 do
        f:styled('changel', sfmt('% 11i ', cl+l))
        f:styled('change', chan[cl+l], '\n')
      end
    end)
end

M._toTest = {
  uniqueMatches = uniqueMatches,
  findLeftStack = findLeftStack,   patienceLIS    = patienceLIS,
  skipEqLinesTop = skipEqLinesTop, skipEqLinesBot = skipEqLinesBot,
}

function M:__call() -- command
  local b, c = table.unpack(self)
  assert(b and c, 'must provide args {base, change}')
  local paths
  if type(b) == 'string' then
    ctx.fmtlog:styled('base', b)
    b = assert(require'lines'.load(b))
    paths = true
  end
  if type(c) == 'string' then
    if paths then ctx.fmtlog:styled('meta', ' :: ') end
    ctx.fmtlog:styled('change', c, '\n')
    c = assert(require'lines'.load(c))
  elseif paths then ctx.fmtlog:write'\n' end
  ctx.fmtlog(M.Diff(b, c))
end

if shim.isMain(M) then M:main(mty.G.arg) end
return M
