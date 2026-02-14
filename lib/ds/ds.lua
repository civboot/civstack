local mty = require'metaty'

--- ds: data structures and algorithms.
local M = mty.mod'ds'

local G = mty.G
local fmt = require'fmt'
local shim = require'shim'

local ty = mty.ty
local next, getmt, setmt = mty.from(G,      'next,getmetatable,setmetatable')
local push, pop, concat  = mty.from(table,  'insert,remove,concat')
local move, sort, unpack = mty.from(table,  'move,sort,unpack')
local sfmt, sfind        = mty.from(string, 'format,find')
local ulen, uoff         = mty.from(utf8,   'len,offset')
local mathty, min, max   = mty.from(math,   'type,min,max')
local floor              = mty.from(math,   'floor')
local xpcall, traceback = xpcall, debug.traceback
local resume = coroutine.resume
local getmethod = mty.getmethod
local EMPTY = {}

--- Default LUA_SETUP, though vt100 is recommended for most users.
function M.setup(args)
  if G.IS_SETUP then return end
  args = args or {}
  io.user = fmt.Fmt{to=assert(shim.file(rawget(args, 'to'),  io.stdout))}
  io.fmt  = fmt.Fmt{to=assert(shim.file(rawget(args, 'log'), io.stderr))}
  G.IS_SETUP = true
end

--- pure-lua bootstrapped library (mainly for bootstrap.lua)
M._B = mty.mod'M._B'

--- concatenate varargs.
M._B.string_concat = function(sep, ...) --> string
  return concat({...}, sep)
end

--- push v onto table, returning index.
function M._B.push(t, v) --> index
  local i = #t + 1; t[i] = v; return i
end

--- return t with the key/vals of add inserted
function M._B.update(t, add) --> t
  for k,v in pairs(add) do t[k] = v end
  return t
end

--- update ignoring t.__pairs.
local function updateRaw(t, add)
  for k,v in next, add do
    t[k] = v
  end
  return t
end

local lib
if G.NOLIB then lib = M._B
else
  lib = require'ds.lib'
  updateRaw = lib.update
end

--- concatenate the string arguments.
M.sconcat = lib.string_concat --(sep, ...) --> string

--- push the value onto the end of the table, return the index.
M.push    = lib.push --(t, v) --> index

-- add missing globals
string.concat = rawget(string, 'concat') or lib.string_concat
table.update  = rawget(table, 'update')  or lib.update
table.push    = rawget(table,  'push')   or lib.push
local push, sconcat = M.push, M.sconcat

local sconcat = string.concat
local tupdate = table.update

M.PlainStyler = mty'PlainStyler' {}

------------------
-- DS psudo-metaevents
-- these use new "metaevent" (similar to __len) that tables can override

--- if t is a table returns t.__name or '?'
function M.name(t) --> string
  if not type(t) == 'table' then return end
  local mt = getmt(t)
end

--- insert values into list at index i.
--- Uses [$inset] method if available.
--- rmlen, if provided, will cause [$$t[i:i+rmlen]]$ to be removed first
---
--- inset is like an extend but the items are insert at any place in the array.
--- The rmlen will also remove a certain number of items.
function M.inset(t, i, values, rmlen) --> nil
  if getmt(t) then return t:inset(i, values, rmlen) end
  -- impl notes, there are two modes:
  -- * we want to keep some values after i: we cache those values then shift in
  -- * we don't want to keep values after i: we shift in the values and clear
  --   the rest
  rmlen = rmlen or 0; local tlen, vlen = #t, #values
  if tlen - i - rmlen >= 0 then -- we want to keep some values >= i
    local cache = move(t, i + rmlen, tlen, 1, {})
    move(values, 1, max(vlen, tlen - i + 1), i, t)
    move(cache, 1, #cache, i + vlen, t)
    return
  end
  -- not keeping values >= i
  move(values, 1, max(vlen, rmlen), max(1, i + 1 - rmlen), t)
end

---------------------
-- Pseudo Types

local CONCRETE_TYPES
--- the only four non-mutable data types in lua
M.CONCRETE_TYPES = {
  ['nil']=true, boolean=true, number=true, string=true
}
CONCRETE_TYPES = M.CONCRETE_TYPES

--- return true if the value is "plain old data".
---
--- Plain old data is defined as any concrete type or a table with no metatable
--- and who's pairs() are only POD.
local isPod; M.isPod = function(v, mtFn)
  local ty = type(v)
  if ty == 'table' then
    local mt = getmt(v)
    if mt then return (mtFn or retTrue)(v, mt) end
    for k, v in pairs(v) do
      if not (isPod(k, mtFn) and isPod(v, mtFn)) then
        return false
      end
    end
    return true
  end
  return CONCRETE_TYPES[ty]
end
isPod = M.isPod

-----------------
-- Utility

M.SKIP      = 'skip'
--- function that does and returns nothing.
function M.noop() end
--- Function that indicates an API is not supported for a type.
--- Throws [$error'not supported'].
function M.nosupport() error'not supported' end
--- identity function, return the inputs.
function M.iden(...) return ... end --> ...
--- function that always return true.
function M.retTrue() return true  end --> true
--- function that always return false.
function M.retFalse() return false end --> false
--- Function that creates a new, empty table.
function M.newTable() return {}    end --> {}
--- Function that returns [$a == b].
function M.eq(a, b) return a == b end --> bool

local retTrue = M.retTrue

--- Get the source location of wherever this is called
--- (or at a higher [$level]).
function M.srcloc(level) --> "/path/to/dir/file.lua:10"
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  return loc:sub(2)..':'..info.currentline
end
--- Same as srcloc but shortens to only the parent dir.
function M.shortloc(level) --> "dir/file.lua:10"
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  -- Get only the dir/file.lua. If no dir, get just file.lua.
  loc = loc:match'^@.-([^/]*/[^/]+)$' or loc:sub(2)
  return loc..':'..info.currentline
end
--- Same as srcloc but removes the [$file:linenum]
function M.srcdir(level) --> "/path/to/dir/"
  return M.srcloc(1 + (level or 0)):match'^(.*/)[^/]+$'
end

--- Create an error message for the coroutine which includes
--- it's traceback.
function M.coroutineErrorMessage(cor, err) --> string
  return sconcat('',
    'Coroutine error: ', debug.stacktraceback(cor, err), '\n',
    'Coroutine failed!')
end

---------------------
-- Order checking functions

--- Return whether [$min <= v <= max].
function M.isWithin(v, min, max) --> bool
  return (min <= v) and (v <= max)
end
--- return the minimum value
function M.min(a, b) --> minimum
  return (b < a) and b or a
end
--- return the maximum value
function M.max(a, b) --> maximum
  return (a < b) and b or a
end
--- Return [$a < b].
function M.lt(a, b) return a < b  end --> bool
--- Return [$a > b].
function M.gt(a, b) return a > b  end --> bool
--- Return [$a <= b].
function M.lte(a, b) return a <= b end --> bool
local lte = M.lte
--- Return value within [$$[min,max]]$ (inclusive).
function M.bound(v, min, max) --> int
  return ((v>max) and max) or ((v<min) and min) or v
end
--- Return the two passed-in values in sorted order.
function M.sort2(a, b) --> (small, large)
  if a <= b then return a, b end; return b, a
end

---------------------
-- Number Functions
--- Return whether value is even.
function M.isEven(a) return a % 2 == 0 end --> bool
--- Return whether value is odd.
function M.isOdd(a) return a % 2 == 1 end --> bool
--- Moves the absolute value of [$v] towards [$0] by [$1].
--- If [$v==0] then do nothing.
function M.absDec(v) --> number
  if v == 0 then return 0 end
  return ((v > 0) and v - 1) or v + 1
end

---------------------
-- String Functions

--- Concatenate all values in [$...], calling tostring on them if necessary.
--- This has several differences than table.concat:[+
--- * it does not require allocating a table to be called.
--- * it automatically calls tostring on the arguments.
--- ]
---
--- This function is most useful if you have a known number
--- of arguments or ... which you want to concatenate.
M.concat = string.concat--(sep, ...) --> string

--- return the string if it is only uppercase letters
function M.isupper(c) return c:match'^%u+$' end --> string?

--- return the string if it is only lowercase letters
function M.islower(c) return c:match'^%l+$' end --> string?

--- Remove [$pat] (default=[$%s], aka whitespace) from the front and back
--- of the string.
function M.trim(subj, pat, si) --> string
  pat = pat and ('^'..pat..'*(.-)'..pat..'*$') or '^%s*(.-)%s*$'
  return subj:match(pat, si)
end

--- Trim the end of the string by removing pat (default=[$%s])
function M.trimEnd(subj, pat, index) --> string
  pat = pat and ('^(.-)'..pat..'*$') or '^(.-)%s*$'
  return subj:match(pat, index)
end

--- Find any of a list of patterns. Return the match [$start, end] as well as
--- the [$index, pat] of the pattern matched.
function M.find(subj, pats, si, plain) --> (ms, me, pi, pat)
  si = si or 1
  for pi, p in ipairs(pats) do
    local ms, me = sfind(subj, p, si, plain)
    if ms then return ms, me, pi, p end
  end
end

M.split = mty.split         --(s, sep) --> strIter

--- Perform a split but returning a list instead of a string.
function M.splitList(...) --(s, sep) --> list
  local t = {}; for _, v in mty.split(...) do push(t, v) end
  return t
end

--- Squash a string: convert all whitespace to repl (default=single-space).
function M.squash(s, repl) return s:gsub('%s+', repl or ' ') end --> string

--- utf8 sub. If len is pre-computed you can pass it in for better performance.
function M.usub(s, si, ei, len)
  ei = ei or -1
  if si < 0 then len = len or ulen(s); si = len + si + 1 end
  local so = uoff(s, si)
  if not so then return '' end
  if ei < 0 then
    if ei == -1 then return s:sub(so) end
    len = len or ulen(s); ei = len + ei + 1
  end
  local eo = uoff(s, ei - si + 2, so) -- offset of character after ei
  return s:sub(so, eo and (eo - 1) or nil)
end

--- A way to declare simpler mulitline strings which: [+
--- * ignores the first/last newline if empty
--- * removes leading whitespace equal to the first
---   line (or second line if first line has no indent)
--- ]
--- Example: [{$$ lang=lua}
--- local s = require'ds'.simplestr
--- local mystr = s[[
---   this is
---     a string.
--- ]]
--- T.eq('this is\n  a string.', mystr)
--- ]$
function M.simplestr(s)
  local i, out, iden, spcs = 1, {}, nil
  for _, line in M.split(s, '\n') do
    spcs = line:match'^%s*'
    if iden then -- later lines, iden already set
      assert((#spcs == #line) or (#spcs >= #iden), 'invalid indent')
      push(out, line:sub(#iden + 1))
    else -- set iden from line 1 (if exists) or line 2
      iden = (i > 1 or spcs ~= '') and spcs or nil
      push(out, line:sub(#spcs + 1))
    end
    i = i + 1
  end
  return concat(out, '\n')
end

--- Convert integer to binary representation (0's and 1's) [+
--- * width will be the number of bits.
--- * sep4 will be used to separate every 4 bits, set to
---   nil to disable.
--- ]
function M.bin(uint, width--[[8]], sep4--[['_']]) --> str
  width = width or 8
  if sep4 == nil then sep4 = '_' end
  local str = {}
  for w=0,width-2 do
    push(str, tostring(1 & uint))
    uint = uint >> 1
    if sep4 and w % 4 == 3 then push(str, sep4) end
  end
  push(str, tostring(1 & uint))
  M.reverse(str)
  return concat(str, '')
end

---------------------
-- Table Functions

--- [$$t[k]]$ if t is a raw table, else [$getmetatable(t).get(t, k)]
---
--- This lets many types be substitutable for raw-tables in some APIs (i.e.
--- lines).
function M.get(t, k) --> value
  if getmt(t) then return t:get(k) end
  return t[k]
end
local get = M.get

--- [$$t[k] = v]$ if t is a raw table, else [$getmetatable(t).set(t, k, v)]
---
--- This lets many types be substitutable for raw-tables in some APIs (i.e.
--- lines).
function M.set(t, k, v)
  if getmt(t) then return t:set(k, v) end
  t[k] = v
end

--- Return whether [$t] contains a single value.
function M.isEmpty(t)
  for _ in pairs(t) do return false end
  return true
end

--- the full length of all pairs
--- ["WARNING: very slow, requires iterating the whole table]
function M.pairlen(t) --> int
  local l = 0; for _ in pairs(t) do l = l + 1 end; return l
end

--- Sort table and return it. Eventually this may use the [$__sort] metamethod.
function M.sort(t, fn) sort(t, fn); return t end --> t

--- sort t and remove anything where [$rmFn(v1, v2)]
--- (normally rmFn is [$ds.eq])
function M.sortUnique(t, sortFn, rmFn) --> t
  sort(t, sortFn); rmFn = rmFn or M.eq
  local i, len, iv, kv = 1, #t
  for k=2,len do
    iv, kv = t[i], t[k]
    if not rmFn(iv, kv) then
      i = i + 1; t[i] = kv
    end
    k = k + 1
  end
  move(EMPTY, i+1, len, i+1, t)
  return t
end

--- get index, handling negatives
function M.geti(t, i) --> t[i]
  return (i >= 0) and t[i] or t[#t + i + 1]
end

--- get the last value of a list-like table.
function M.last(t) return t[#t] end

--- get the first (and assert only) element of the list
function M.only(t) --> t[1]
  local l = #t; fmt.assertf(l == 1, 'not only: len=%s', l)
  return t[1]
end

--- get only the values of pairs(t) as a list
function M.values(t) --> list
  local vals = {}; for _, v in pairs(t) do push(vals, v) end
  return vals
end

--- get only the keys of [$pairs(t)] as a list.
function M.keys(t) --> list
  local keys = {}; for k in pairs(t) do push(keys, k) end
  return keys
end

--- next(t, key) but with indexes
M.inext = ipairs{} --(t, i) --> (i+1, v)
local inext = M.inext

--- inext but reversed.
function M.iprev(t, i) --> (t, i) --> (i-1, v)
  if i > 1 then return i - 1, t[i - 1] end
end

--- ipairs reversed
function M.ireverse(t) return M.iprev, t, #t + 1 end --> iter

--- ["You probably want islice instead.]
--- Usage: [$for i, v in rawislice, {t, ei}, si do ... end][{br}]
--- where [$si, ei] is the start/end indexes.
function M.rawislice(state, i) --> (i+1, v)
  i = i + 1; if i > state[2] then return end
  return i, state[1][i]
end

--- Usage: [$for i,v in islice(t, starti, endi)][{br}]
--- The default endi is [$#t], otherwise this ignores the list's length
--- ([$v] may be [$nil] for some [$i] values).
function M.islice(t, starti, endi) --> iter
  if endi then
    return M.rawislice, {t, endi}, (starti or 1) - 1
  end
  return inext, t, (starti or 1) - 1
end

--- Get a new list of indexes [$$[si-ei]]$ (inclusive).[{br}]
--- Defaults: [$si=1, ei=#t].
function M.slice(t, si, ei) --> list
  local sl = {}
  for i=si or 1,ei or #t do push(sl, t[i]) end
  return sl
end

--- Return true if two list-like tables are equal.[{br}]
--- Note that this only compares integer keys and ignores
--- others.
function M.ieq(a, b)
  if #a ~= #b then return false end
  for i=1,#a do if a[i] ~= b[i] then return false end end
  return true
end

--- Reverse a list-like table in-place (mutating it).
function M.reverse(t) --> t
  local l = #t; for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end

--- Extend [$t] with list-like values from [$l].
--- This mutates [$t].
function M.extend(t, l) --> t
  if getmt(t) then return t:extend(l) end
  return move(l, 1, #l, #t + 1, t)
end
local extend = M.extend

--- This is used by types implementing [$:extend].
--- It uses their [$get] and [$set] methods to implement
--- extend in a for loop.
---
--- ["types do this if they may [$yield] in their get/set, which
---   is not allowed through a C boundary like [$table.move]]
function M.defaultExtend(r, l) --> r
  local rset = getmt(r) and assert(r.set) or rawset
  local lget = getmt(l) and assert(l.get) or rawget
  local rlen = #r
  for k=1,#l do rset(r, rlen+k, lget(l,k)) end
  return r
end

--- Clear list-like elements of table.
--- default is all of it, but you can also specify a specific
--- start index and length.
function M.clear(t, si, len) --> t
  -- TODO: (len or #t) - si + 1
  return move(EMPTY, 1, len or #t, si or 1, t)
end
--- return t with the key/vals of add inserted
M.update = M._B.update
local update = M.update

--- Given a list of lists return a single depth list.
function M.flatten(listOfLists) --> list
  local t = {}
  for i, l in ipairs(listOfLists) do M.extend(t, l) end
  return t
end

--- like update but only for specified keys
function M.updateKeys(t, add, keys) --> t
  for _, k in ipairs(keys) do t[k] = add[k] end; return t
end

--- Get the sorted keys of t.
function M.orderedKeys(t, cmpFn) --> keys
  local keys = {}; for k in pairs(t) do push(keys, k) end
  sort(keys, cmpFn)
  return keys
end
--- Adds all [$key=index] to the table so the keys can
--- be iterated using [$for _, k in ipairs(t)]
function M.pushSortedKeys(t, cmpFn) --> t
  local keys = M.orderedKeys(t, cmpFn)
  for i, k in ipairs(keys) do t[i] = k end
  return t
end

--- Recursively merge m into t, overriding existing values.
--- List (integer) indexes are [,extended] instead of overwritten.
function M.merge(t, m) --> t
  local len = #m
  if len > 0 then move(m, 1, len, #t + 1, t) end -- extend
  for k, v in pairs(m) do
    if mathty(k) == 'integer' then
      assert(k <= len, 'merge table has integer keys > len')
    elseif type(t[k]) == 'table' and type(v) == 'table' then
      M.merge(t[k], v)
    else t[k] = v end
  end
  return t
end

--- Perform an ordered merge of [$$a[a_si:a_ei]$ and [$$b[b_si:b_ei]$
--- to [$$to[ti:a_ei-a_si + b_ei-b_si + 2]$, using [$cmp] (default [$ds.lte])
--- for comparison.
---
--- The return values is the table [$to], which will be created if not provided.
---
--- The [$mv] function is used for moving final values after one list
--- is empty (default=[$table.move]).
---
--- This can be part of a sorting algorithm or used to merge two
--- already-sorted lists.
function M.orderedMerge(a, b, to, cmp, a_si, a_ei, b_si, b_ei, ti, mv) --> to
  to = to or {}
  return M.orderedMergeRaw(
    a, b, to, cmp or lte,
    a_si or 1, a_ei or #a,
    b_si or 1, b_ei or #b,
    ti or #to + 1,
    mv or move)
end

--- orderedMerge without any default values.
function M.orderedMergeRaw(a, b, to, cmp, a_si, a_ei, b_si, b_ei, ti, mv) --> to
  -- Check for empty tables. In the loop we only check when the index changes.
  if b_si > b_ei then return mv(a, a_si,a_ei, ti, to) end
  if a_si > a_ei then return mv(b, b_si,b_ei, ti, to) end
  local av, bv
  while true do
    av, bv = a[a_si], b[b_si]
    if cmp(av, bv) then -- traditionally if(a <= b)
      to[ti], a_si, ti = av, a_si + 1, ti + 1 -- copy val from a
      -- if a is empty, move from b and finish.
      if a_si > a_ei then return mv(b, b_si,b_ei, ti, to) end
    else
      to[ti], b_si, ti = bv, b_si + 1, ti + 1 -- copy val from b
      -- if b is empty, move from a and finish.
      if b_si > b_ei then return mv(a, a_si,a_ei, ti, to) end
    end
  end
end

--- Remove key from [$t] and return it's value.
function M.popk(t, key) --> value
  local val = t[key]; t[key] = nil; return val
end

--- return len items from the end of [$t], removing them from [$t]
function M.drain(t, len--[[#t]]) --> table
  local out = {}; for i=1, min(#t, len) do push(out, pop(t)) end
  return M.reverse(out)
end

--- If the key exists, return it's value.
--- Else return [$newFn()]
function M.getOrSet(t, k, newFn) --> t[k] or newFn()
  local v = t[k]; if v ~= nil then return v end
  v = newFn(t, k); t[k] = v
  return v
end

--- Set the key to a value if it is currently nil.
--- Else do not change it.
function M.setIfNil(t, k, v)
  if t[k] == nil then t[k] = v end
end

--- Return an empty table, useful for newFn/etc in some APIs.
function M.emptyTable() return {} end

--- remove (mutate) the left side of the table (list).
--- noop if rm is not exactly equal to the left side.
function M.rmleft(t, rm, eq--[[ds.eq]]) --> t (mutated)
  eq = eq or M.eq
  for i, v in ipairs(rm) do
    if not t[i] or not eq(v, t[i]) then
      return
    end
  end
  local l, rl = #t, #rm
  move(t,     rl + 1, l,  1, t) -- move to start
  move(EMPTY, 1,      rl, l - rl + 1, t) -- clear end
  return t
end

--- used with ds.getp and ds.setp. Example [{$$ lang=lua}
---   local dp = require'ds'.dotpath
---   ds.getp(t, dp'a.b.c')
--- ]$
function M.dotpath(dots) --> list split by '.'
  local p = {}; for v in dots:gmatch'[^%.]+' do push(p, v) end
  return p
end

--- get the value at the path or nil if the value or any
--- intermediate table is missing.
--- [{$$ lang=lua}
---   get(t, {'a', 2, 'c'})  -> t.a?[2]?.c?
---   get(t, dotpath'a.b.c') -> t.a?.b?.c?
--- ]$
function M.getp(t, path) --> value? at path
  for _, k in ipairs(path) do
    t = t[k]; if t == nil then return nil end
  end
  return t
end

--- same as ds.getp but uses [$rawget]
function M.rawgetp(t, path) --> value? at path
  for _, k in ipairs(path) do
    t = rawget(t, k); if t == nil then return nil end
  end
  return t
end

--- set the value at path using newFn (default=ds.newTable) to create
--- missing intermediate tables.
--- [{$$ lang=lua}
--- set(t, dotpath'a.b.c', 2) -- t.a?.b?.c = 2
--- ]$
function M.setp(d, path, value, newFn) --> nil
  newFn = newFn or M.emptyTable
  local len = #path; assert(len > 0, 'empty path')
  for i=1,len-1 do d = M.getOrSet(d, path[i], newFn) end
  d[path[len]] = value
end

--- Return the index where the value is == find.
function M.indexOf(t, find) --> int
  for i, v in ipairs(t) do
    if v == find then return i end
  end
end

--- Return the index where [$value:match(pat)].
function M.indexOfPat(strs, pat) --> int
  for i, s in ipairs(strs) do if s:find(pat) then return i end end
end

--- Walk the table up to depth maxDepth (or infinite if nil) [+
--- * [$fieldFn(key, value, state)    -> stop] is called for every non-table value.
--- * [$tableFn(key, tblValue, state) -> stop] is called for every table value
--- ]
---
--- If tableFn [$stop==ds.SKIP] (i.e. 'skip') then that table is not recursed.
--- Else if stop then the walk is halted immediately
function M.walk(t, fieldFn, tableFn, maxDepth, state) --> nil
  if maxDepth then
    maxDepth = maxDepth - 1; if maxDepth < 0 then return end
  end
  for k, v in pairs(t) do
    if type(v) == 'table' then
      if tableFn then
        k = tableFn(k, v, state); if k then
          if k == M.SKIP then goto skip end
          return
        end
      end
      M.walk(v, fieldFn, tableFn, maxDepth, state)
    elseif fieldFn and fieldFn(k, v, state) then return end
    ::skip::
  end
end

--- A typo-safe table, typically used in libraries for storing constants.
---
--- Adding keys is always allowed but getting non-existant keys is an error.
M.TypoSafe = mty'TypoSafe'{}
getmt(M.TypoSafe).__call = mty.constructUnchecked
getmt(M.TypoSafe).__index = mty.hardIndex
M.TypoSafe.__newindex = nil


---------------------
-- Untyped Functions

--- Copy list-elements only
function M.icopy(t) --> list
  if getmt(t) then return t:icopy() end
  return move(t, 1, #t, 1, {})
end

--- For types implementing [$:copy()] method.
function M.defaultICopy(r)
  local t = {}; for i=1,#r do t[i] = r:get(i) end
  return t
end

function M.rawcopy(t)
  return setmt(updateRaw({}, t), getmt(t))
end

--- Copy and update full table
--- FIXME: remove add
function M.copy(t, add) --> new t
  if ty(t) ~= 'table' then
    return add and update(t:__copy(), add)
        or t:__copy()
  end
  return add and update(update({}, t), add)
      or update({}, t)
end

--- Recursively copy the table.
function M.deepcopy(t) --> table
  local out = {}; for k, v in pairs(t) do
    if 'table' == type(v) then v = M.deepcopy(v) end
    out[k] = v
  end
  return setmt(out, getmt(t))
end

---------------------
-- File Functions

--- Read the full contents of the path or throw an error.
function M.readPath(path) --!> string
  local f, out, err = assert(io.open(path))
  out, err = f:read('a'); f:close()
  return assert(out, err)
end

--- Write text to path or throw an error.
function M.writePath(path, text) --!> nil
  local f = fmt.assertf(io.open(path, 'w'), 'invalid %s', path)
  local out, err = f:write(text); f:close(); assert(out, err)
end

---------------------
-- Low-level Types

--- Weak key table, see docs on [$__mode]
M.WeakK = setmt(
  {__name='WeakK', __mode='k'}, {
  __name='Ty<WeakK>', __call=mty.constructUnchecked,
})

--- Weak value table, see docs on [$__mode]
M.WeakV = setmt(
  {__name='WeakV', __mode='v'}, {
  __name='Ty<WeakV>', __call=mty.constructUnchecked,
})

--- Weak key+value table, see docs on [$__mode]
M.WeakKV = setmt(
  {__name='WeakKV', __mode='kv'}, {
  __name='Ty<WeakKV>', __call=mty.constructUnchecked,
})

--- Table that ignores new indexes. Used to disable caching in tests.
M.Forget = setmt(
  {__name='Forget', __newindex=M.noop},
  {__name='Ty<Forget>', __call=mty.constructUnchecked}
)

--- Table that errors on missing key
M.Checked = setmt(
  {__name='Checked', __metatable='table',
   __index=function(_, k) error('unknown key: '..k) end,
  },
  {__name='Ty<Checked>', __call=mty.constructUnchecked}
)

--- A slice of anything with start and end indexes.
--- ["Note: This object does not hold a reference to the object being
---   sliced.]
M.Slc = mty'Slc' {
  'si [int]: start index',
  'ei [int]: end index',
}
local Slc = M.Slc
M.Slc.__len = function(s) return s.ei - s.si + 1 end --> #s

--- return either a single (new) merged or two sorted Slcs.
function M.Slc:merge(b) --> first, second?
  if self.si > b.si     then self, b = b, self end -- fix ordering
  if self.ei + 1 < b.si then return self, b end -- check overlap
  return Slc{si=self.si, ei=max(self.ei, b.ei)}
end

function M.Slc:__fmt(fmt) --> string
  fmt:write(sfmt('Slc[%s:%s]', self.si, self.ei))
end

---------------------
-- Sentinal, none type, bool()

local function _si() error('invalid operation on sentinel', 2) end
--- [$sentinel(name, metatable)]
--- Use to create a "sentinel type". Return the (singular) instance.
---
--- Sentinels are "single values" commonly used for things like: none, empty, EOF, etc.
--- They have most metatable methods disallowed and are immutable down. Methods can
--- only be set by the provided metatable value.
function M.sentinel(name, mt) --> NewType
  mt = M.update({
    __name=name, __tostring=function() return name end,
    __newindex=_si, __len=_si, __pairs=_si,
    __pairs = function() return M.noop end,
  }, mt or {})
  mt.__index = mt
  setmt(mt, {__name='Ty<'..name..'>', __index=mty.indexError})
  local S = setmt({}, mt)
  mt.__toPod   = function() return S end
  mt.__fromPod = function(_, pod, v)
    if v ~= S then error('expected '..name..' got '..type(v)) end
    return v
  end
  rawset(S, '__toPod', mt.__toPod)
  rawset(S, '__fromPod', mt.__fromPod)
  return S
end

--- none: "set as none" vs nil aka "unset"
---
--- none is a sentinel value. Use it in APIs where there is an
--- "unset but none" such as JSON's "null".
M.none = M.sentinel('none', {__metatable='none'})

--- convert to boolean (none aware)
function M.bool(v) --> bool
  return not rawequal(M.none, v) and v and true or false
end

--- An immutable empty table
M.empty = setmt({}, {
  __newindex = function() error('mutate ds.empty', 2) end,
  __metatable = 'table',
})

--- Immutable table
M.Imm = mty'Imm' {}
local IMM_DATA = '<!imm data!>'
getmt(M.Imm).__call = function(T, t)
  return setmt({[IMM_DATA]=(next(t) ~= nil) and t or nil}, T)
end
M.Imm.__metatable = 'table'
M.Imm.__newindex = function() error'cannot modify Imm table' end
function M.Imm:__index(k)
  local d = rawget(self, IMM_DATA); return d and d[k]
end
function M.Imm:__pairs() return next, rawget(self, IMM_DATA) or self end
function M.Imm:__len()
  local d = rawget(self, IMM_DATA); return not d and 0 or #d
end

M.empty = M.Imm{}

---------------------
-- Set
M.Set = mty'Set'{}
M.Set.__newindex = nil
getmt(M.Set).__index = nil
getmt(M.Set).__call = function(T, t)
  local s = {}
  for _, k in ipairs(t) do s[k] = true end
  return mty.constructUnchecked(T, s)
end

function M.Set:__fmt(f) --> nil
  f:write('Set', f.tableStart)
  local keys = {}; for k in ipairs(self) do push(keys, k) end
  sort(keys)
  if #keys > 1 then f:level(1) end
  for i, k in ipairs(keys) do
    f(k)
    if i < #keys then f:write(f.indexEnd) end
  end
  if #keys > 1 then f:level(-1) end
  f:write(f.tableEnd)
end

function M.Set:__eq(t) --> bool
  local len = 0
  for k in pairs(self) do
    if not t[k] then return false end
    len = len + 1
  end
  for _ in pairs(t) do -- ensure lengths are the same
    len = len - 1
    if len < 0 then return false end
  end
  return true
end

function M.Set:union(s) --> Set
  local both = M.Set{}
  for k in pairs(self) do if s[k] then both[k] = true end end
  return both
end

--- items in self but not in s
function M.Set:diff(s) --> Set
  local left = M.Set{}
  for k in pairs(self) do if not s[k] then left[k] = true end end
  return left
end

---------------------
-- Binary Search

local function _bs(t, v, cmp, si, ei)
  if ei <= si + 1 then -- cannot narrow further
    return cmp(t[ei], v) and ei
        or cmp(t[si], v) and si or (si - 1)
  end
  local mi = (si + ei) // 2
  if cmp(t[mi], v) then return _bs(t, v, cmp, mi, ei)
  else                  return _bs(t, v, cmp, si, mi - 1) end
end

--- Search the sorted table, return i such that: [+
--- * [$$cmp(t[i], v)]$ returns true  for indexes <= i
--- * [$$cmp(t[i], v)]$ returns false for indexes >  i
--- ]
--- If you want a value perfectly equal then check equality
--- on the resulting index.
function M.binarySearch(t, v, cmp, si--[[1]], ei--[[#t]]) --> index
  return _bs(t, v, cmp or lte, si or 1, ei or #t)
end

---------------------
-- Binary Tree

--- indexed table as Binary Tree.
--- These functions treat an indexed table as a binary tree
--- where root is at [$index=1]
M.bt = mod and mod'bt' or {}
function M.bt.left(t, i)    return t[i * 2]     end
function M.bt.right(t, i)   return t[i * 2 + 1] end
function M.bt.parent(t, i)  return t[i // 2]    end
function M.bt.lefti(t, i)   return   i * 2      end
function M.bt.righti(t, i)  return   i * 2 + 1  end
function M.bt.parenti(t, i) return   i // 2     end

---------------------
-- Directed Acyclic Graph

local function _dagSort(out, id, parentMap, visited) --> cycle?
  do -- detect cycles and whether we've already visited id.
    local v = visited[id]; if v then
      if type(v) == 'number' then  -- cycle detected
        push(visited, id);
        return M.slice(visited, v)
      end
      return -- already visited
    end
  end
  local info = require'ds.log'.info
  push(visited, id); visited[id] = #visited
  for _, pid in ipairs(
      fmt.assertf(parentMap[id], '%q missing parents', id)) do
    local cycle = _dagSort(out, pid, parentMap, visited)
    if cycle then return cycle end
  end
  push(out, id)
  pop(visited); visited[id] = true -- clear cycle detection
end

--- Sort the directed acyclic graph of ids + parentMap
--- to put children before the parents.
---
--- returns [$nil, cycle] in the case of a cycle
function M.dagSort(ids, parentMap) --> sorted?, cycle?
  local out, visited, cycle = {}, {}
  for _, id in ipairs(ids) do
    cycle = _dagSort(out, id, parentMap, visited)
    if cycle then return nil, cycle end
  end
  return out
end

---------------------
-- BiMap

-- CXT HERE BAD
--- Bidirectional Map.
--- Maps both [$key -> value] and [$value -> key].
--- Must use [$:remove] (instead of [$$bm[k] = nil]$ to handle deletions.
---
--- Note that [$pairs()] will return BOTH directions (in an unspecified order)
M.BiMap = mty'BiMap'{}
M.BiMap.__fields   = nil
M.BiMap.__fmt      = nil
M.BiMap.__tostring = nil

getmt(M.BiMap).__call = function(T, self)
  local rev = {}; for k, v in pairs(self) do rev[v] = k end
  for k, v in pairs(rev) do self[k] = v end
  return setmt(self, T)
end
function M.BiMap:__newindex(k, v)
  rawset(self, k, v); rawset(self, v, k)
end
getmt(M.BiMap).__index = nil
function M.BiMap:remove(k) --> v
  local v = self[k]; self[k] = nil; self[v] = nil; return v
end

---------------------
-- Deq Buffer

--- [$Deq() -> Deq], a deque datastructure.
--- Use as a first in/out (fifo) with [$deq:push(v)] and [$deq()] (pop).
---
--- Main methods: [{$$ lang=lua}
---   pushLeft()                  -- push on left side
---   pushRight() push()          -- push on right side
---   popRight()                  -- pop on right side
---   popLeft()   pop()  __call() -- pop on left side
--- ]$
M.Deq = mty'Deq'{
  'right [number]',
  'left  [number]'
}
getmt(M.Deq).__call = function(T)
  return mty.construct(T, {right=0, left=1})
end
function M.Deq:pushRight(val)
  local r = self.right + 1; self[r] = val; self.right = r
end
--- extend deq to right
function M.Deq:extendRight(vals) --> nil
  local r, vlen = self.right, #vals
  move(vals, 1, vlen, r + 1, self)
  self.right = self.right + vlen
end
function M.Deq:pushLeft(val) --> nil
  local l = self.left - 1;  self[l] = val; self.left = l
end
--- extend deq to left ([$$vals[1]]$ is left-most)
function M.Deq:extendLeft(vals) --> nil
  local vlen = #vals
  self.left = self.left - vlen
  move(vals, 1, vlen, self.left, self)
end
function M.Deq:popLeft() --> v
  local l = self.left; if l > self.right then return nil end
  local val = self[l]; self[l] = nil; self.left = l + 1
  return val
end
function M.Deq:popRight() --> v
  local r = self.right; if self.left > r then return nil end
  local val = self[r]; self[r] = nil; self.right = r - 1
  return val
end
M.Deq.push = M.Deq.pushRight --(d, v) --> nil
function M.Deq:__len() return self.right - self.left + 1 end --> #d
M.Deq.pop = M.Deq.popLeft --> (d) -> v
M.Deq.__call = M.Deq.pop  --> () -> v
function M.Deq:clear() --> nil: clear deq
  local l = self.left; move(EMPTY, l, self.right, l, self)
  self.left, self.right = 1, 0
end
function M.Deq:drain() --> table: get all items and clear deq
  local t = move(self, self.left, self.right, 1, {})
  self:clear(); return t
end

------------------
-- Export bytearray

if not G.NOLIB then
--- bytearray: an array of bytes that can also be used as a file.
---
--- Construct with [$bytearray(str...)]
---
--- Methods:[+
--- * [$b:len(v, fill='') --> int]
---     get (no args) or set the bytearray length. When v is set, the first
---     character of fill will be used to fill any characters above the current
---     length.
---
--- * [$b:size() --> int]
---     return the allocated space of the buffer.
---
--- * [$b:extend(str...) --> b]
---     extend bytearray with strings after len.
---
--- * [$b:sub(si, ei) --> string]: same as string:sub(...)
---
--- * [$b:replace(i, str)]:
---     replace the string at i with str, increasing length if necessary.
--- ]
---
--- In addition, bytearray is file-like with the methods read(), write(),
--- seek() and flush(). close() will free all internal memory. pos(n) gets and
--- sets the current "file" position, and supports negative indexes.
M.bytearray = lib.bytearray
function M.bytearray:lines(opt)
  return function() return self:read(opt) end
end
function M.bytearray:seek(whence, offset)
  if not whence or whence == 'cur' then return self:pos()
  elseif whence == 'set'           then return self:pos(offset or 0)
  elseif whence == 'end'           then return self:pos(-1) end
  error('unknown whence: '..whence)
end
M.bytearray.flush   = M.noop
M.bytearray.setvbuf = M.noop
end -- if not NOLIB

-----------------------
-- Handling Errors

--- Throw an error if [$select(i, ...)] is truthy, else return ...
---
--- For example, [$file:read'L'] returns [$line?, errmsg?].
--- However, the absence of line doesn't necessarily
--- indicate the presence of errmsg: EOF is just [$nil].
---
--- Therefore you can use [$line = check(2, f:read'L')]
--- to only assert on the presence of errmsg.
function M.check(i, ...) --!> ...
  if select(i, ...) then error(tostring(select(i, ...))) end
  return ...
end

M.IGNORE_TRACE = {
  [""]=true,
  ['stack traceback:']=true,
  ["[C]: in function 'error'"]=true,
  ["[C]: in ?"]=true,
}

--- convert the string traceback into a list
function M.tracelist(tbstr, level) --> {traceback}
  tbstr = tbstr or traceback(2 + (level or 0))
  local ig, tb = M.IGNORE_TRACE, {}
  for l in tbstr:gmatch'%s*([^\n]*)' do
    if not ig[l] then push(tb, l) end
  end
  return tb
end
--- Get the current traceback as an indented string.
function M.traceback(level) --> string
  return concat(M.tracelist(nil, 1 + (level or 0)), '\n    ')
end

local function fmtTracebackItem(f, tbitem)
  f:write'  '
  local path, li, ctx = tbitem:match'%s*(%S+):(%d+):%s*(.*)'
  if not path then return f:styled('warn', tbitem, '\n') end
  f:styled('warn', sfmt('[% 5i]', math.tointeger(li)), ' ')
  f:styled('path', require'ds.path'.nice(path), ' ')
  f:styled('warn', ctx, '\n')
end

--- Error message, traceback and cause
--- NOTE: you should only use this for printing/logging/etc.
M.Error = mty'Error' {
  'msg [string]', 'traceback {path}', 'cause [Error]',
}
function M.Error:__fmt(f)
  local pth = require'ds.path'
  f:styled('warn', '[ERROR] '..self.msg)
  if self.traceback and #self.traceback > 0 then
    f:styled('warn', '\ntraceback:', '\n')
    for _, item in ipairs(self.traceback) do
      fmtTracebackItem(f, item)
    end
  end
  if self.cause then
    f:styled('warn', '\nCaused by: ', '\n')
    f(self.cause)
  end
  f:write'\n'
end
function M.Error:__tostring() return fmt(self) end

--- create the error from the arguments.
--- tb can be one of: [$coroutine|string|table]
--- FIXME: have this take T as first arg
function M.Error.from(msg, tb, cause) --> Error
  local cause
  if ty(msg) == M.Error then
    cause, msg = msg, '(rethrown)'
  end
  tb = (type(tb) == 'thread') and traceback(tb) or tb
  return M.Error{
    msg=msg:match'^%S+/%S+:%d+: (.*)' or msg, -- remove line number
    traceback=(type(tb) == 'table') and tb or M.tracelist(tb),
    cause=cause,
  }
end

--- for use with xpcall. See: try
function M.Error.msgh(msg, level) --> Error
  return M.Error.from(msg, traceback('', (level or 1) + 1))
end

--- try to run the fn. Similar to pcall. Return one of: [+
--- * successs: [$(true, ...)]
--- * failure: [$(false, ds.Error{...})]
--- ]
function M.try(fn, ...) --> (ok, ...)
  return xpcall(fn, M.Error.msgh, ...)
end

--- Helper function for running commands as "main".
function M.main(fn, ...) --> errno?
  local ok, err = M.try(fn, ...); if ok then return nil end
  (io.fmt or print)(err); os.exit(1)
end

--- Same as coroutine.resume except uses a ds.Error object for errors
--- (has traceback)
function M.resume(th) --> (ok, err, b, c)
  local ok, a, b, c = resume(th)
  if ok then return ok, a, b, c end
  return nil, M.Error.from(a, th)
end

-----------------------
-- Import helpers

--- Try to get any [$string.to.path] by trying all possible combinations of
--- requiring the prefixes and getting the postfixes.
function M.wantpath(path) --> value?
  path = type(path) == 'string' and M.splitList(path, '%.') or path
  local obj
  for i=1,#path do
    local v = obj and M.rawgetp(obj, M.slice(path, i))
    if v then return v end
    obj = mty.want(table.concat(path, '.', 1, i))
  end
  return obj
end

--- indexrequire: [$R.foo] is same as [$require'foo']
--- This is mostly used in scripts/etc
M.R = setmt({}, {
  __index=function(_, k) return require(k) end,
  __newindex=function() error"don't set fields" end,
})

--- Include a resource (raw data) relative to the current file.
---
--- Example: [$M.myData = ds.resource'data/myData.csv']
function M.resource(relpath)
  return require'ds.path'.read(M.srcdir(1)..relpath)
end

--- exit immediately with message and errorcode = 99
function M.yeet(fmt, ...)
  io.fmt:styled('error',
    sfmt('YEET %s: %s', M.shortloc(1), sfmt(fmt or '', ...)),
    '\n')
  os.exit(99)
end

--- Print to io.sderr
function M.eprint(...)
  local t = {...}; for i,v in ipairs(t)
    do t[i] = tostring(v)
  end
  io.stderr:write(concat(t, '\t'), '\n')
end


return M
