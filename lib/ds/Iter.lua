local mty = require'metaty'
--- Fluent iterator
---
--- [{$$ lang=lua}
--- isNumber = function(v) return type(v) == 'number' end
--- t = {4, 5, 'six', 7}
--- T.eq(
---   {'4', '5', '7'},
---   Iter:ofList(t)       -- iterate over ipairs(t)
---     :filterV(isNumber) -- only numbers
---     :mapV(tostring)    -- convert to string
---     :valsTo())         -- collect list of values (drops keys)
--- ]$
local Iter = mty'Iter' {
  '_li [int]: left index of fns (stored at negative index)', _li = 0,
  '_prevK [any]: the prevous key, used to get next',
}

local ds = require'ds'
local fmt = require'fmt'

local select, unpack = select, table.unpack
local pairs, ipairs = pairs, ipairs
local push, sort = table.insert, table.sort
local concat = table.concat
local construct = mty.construct
local rawislice, inext = ds.rawislice, ds.inext

local function swapKV(k, v) return v, k end

--------------------------------
-- Constructors

--- construct from table of [${nextFn, state, startK}] (see [$help 'for']).
--- Examples: [{$$ lang=lua}
---   self = Iter{pairs(t)}  -- recommendation: use It:of(t) instead
---   self = Iter{ipairs(t)} -- recommendation: use It:ofList(t) instead
---   self = Iter{myIterFn}
--- ]$
getmetatable(Iter).__call = function(T, t)
  t._prevK = t[3]; return setmetatable(t, T)
end

--- create iterable of [$pairs(t)]
Iter.of = function(T, t) return T{pairs(t)} end

--- create iterable of [$ipairs(t)]
Iter.ofList = function(T, t) return T{ipairs(t)} end

--- create an iterable that returns [$table.unpack] on each
--- value in [$ipairs(t)].
---
--- i.e. [$Iter:ofUnpacked{{5, 'five'}, {6, 'six'}}] will
--- return (5, 'five') then (6, 'six')
Iter.ofUnpacked = function(T, t)
  local i, len = 0, #t
  return T{function()
    if i >= len then return end
    i = i + 1; return unpack(t[i])
  end}
end

--- create an iterable of [$t] which emits keys in order.
--- [" WARNING: this first sorts the keys, which can be slow]
Iter.ofOrdMap = function(T, t, cmpFn) --> sortedIter[k, v]
  local keys = {}; for k, v in pairs(t) do push(keys, k) end
  sort(keys, cmpFn)
  return T{pairs(keys)}:lookup(t)
end

--- sort t then iterate over list
Iter.ofOrdList = function(T, t, cmpFn) --> sortedIter[i, v]
  sort(t, cmpFn); return T{ipairs(t)}
end

--- iterate over slice of [$starti:endi] in [$t]
Iter.ofSlc = function(T, t, starti, endi) --> iter[i, v]
  if endi then
    return T{rawislice, {t, endi}, (starti or 1) - 1}
  end
  return T{inext, t, (starti or 1) - 1}
end

--------------------------------
-- Mapping methods

--- emit [$k, v = fn(v)] for each non-nil result
---
--- ["Note: if performance matters this is the most performant
---         application function since self doesn't create an internal
---         function.
--- ]
function Iter:map(fn) --> self
  local li = self._li - 1; self[li] = fn; self._li = li
  return self
end

---- emit [$fn(k), v)] for each non-nil result.
function Iter:mapK(fn) --> self
  return self:map(function(k, v) k = fn(k); return k, v end)
end

--- emit [$k, fn(v)] for each non-nil result.
--- (filtered when [$newK==nil])
function Iter:mapV(fn) --> self
  return self:map(function(k, v)
    v = fn(v); if v ~= nil then return k, v end
  end)
end

---- emit only [$if fn(k, v)] results
function Iter:filter(fn) --> self
  return self:map(function(k, v)
    local b = fn(k, v); if b then return k, v end
  end)
end

---- emit only [$if fn(k)] results
function Iter:filterK(fn) --> self
  return self:map(function(k, v)
    local b = fn(k); if b then return k, v end
  end)
end

---- emit only [$if fn(v)] results
function Iter:filterV(fn) --> self
  return self:map(function(k, v)
    local b = fn(v); if b then return k, v end
  end)
end


--- emit[$$v, t[k]]$, looking up the iter's values in the table's keys.
function Iter:lookup(t) --> self
  return self:map(function(_, v) return v, t[v] end)
end

--- emit [$$t[k], v]$ for each non-nil [$$t[k]]$
function Iter:lookupK(t) --> self
  return self:map(function(k, v) return t[k], v end)
end

--- emit [$$k, $t[v]]$ for each non-nil [$$t[v]]$
function Iter:lookupV(t) --> self
  return self:map(function(k, v)
    v = t[v]; if v ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each non-nil [$$t[k]]$
function Iter:keyIn(t) --> self
  return self:map(function(k, v)
    if t[k] ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each nil [$$t[k]]$
function Iter:keyNotIn(t) --> self
  return self:map(function(k, v)
    if t[k] == nil then return k, v end
  end)
end

--- emit [$k, v] for each non-nil [$$t[v]]$
function Iter:valIn(t) --> self
  return self:map(function(k, v)
    if t[v] ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each nil [$$t[v]]$
function Iter:valNotIn(t) --> self
  return self:map(function(k, v)
    if t[v] == nil then return k, v end
  end)
end

--- emit [$k, v] after calling [$fn(k, v)].
--- The results of the fn are ignored
function Iter:listen(fn) --> self
  return self:map(function(k, v) fn(k, v); return k, v end)
end

--- emit [$i, k], dropping values. [$i] starts at [$1] and increments each
--- time called.
---
--- [" Note: this is most useful for iterators which don't emit a [$v].
---    i.e. getting the line number in [$file:lines()]]
function Iter:index() --> self
  local i = 0; return self:map(function(_, v) i = i + 1; return i, v end)
end

--- emit [$v, k] (swaps key and value)
function Iter:swap() --> self[v, k]
  return self:map(swapKV)
end

--------------------------------
-- Collecting Methods

--- run the iterator over all values, calling [$fn(k, v)] for each.
--- return the first [$k, v] where the fn returns a truthy value.
function Iter:find(fn) --> k, v
  local li, k = self._li
  for key, v in unpack(self) do
    k = key; for i=-1,li,-1 do
      k, v = self[i](k, v); if k == nil then goto skip end
    end
    if fn(k, v) then return k, v end
    ::skip::
  end
end


local function allFn(k, v) return not v end -- stop on first falsy
--- return true if any of the values are truthy
function Iter:all() return not self:find(allFn) end

local function anyFn(k, v) return v end     -- stop on first true
--- return true if any of the values are truthy
function Iter:any() return not not self:find(anyFn) end

--- run the iterator over all values, calling [$fn(k, v)] for each.
function Iter:run(fn--[[noop]]) --> nil
  local li, fn, k = self._li, fn or ds.noop
  for key, v in unpack(self) do
    k = key; for i=-1,li,-1 do
      k, v = self[i](k, v); if k == nil then goto skip end
    end
    fn(k, v)
    ::skip::
  end
end

--- collect non-nil [$k, v] into table-like object [$to]
Iter.to = function--(self, to={}) --> to
  (self, to) to = to or {}
  self:run(function(k, v) to[k] = v end)
  return to
end

--- collect emitted [$k] as a list (vals are dropped)
Iter.keysTo = function--(self, to={}) --> to
  (self, to) to = to or {}
  self:run(function(k) push(to, k) end)
  return to
end

--- collect emitted [$v] as a list (keys are dropped)
Iter.valsTo = function--(self, to={}) --> to
  (self, to) to = to or {}
  self:run(function(k, v) push(to, v) end)
  return to
end

function Iter:concat(sep) return concat(self:to(), sep) end

--- reset the iterator to run from the start
function Iter:reset() self._prevK = self[3]; return self end --> self

--- use as an iterator.
function Iter:__call()
  local li, k = self._li
  for key, v in self[1], self[2], self._prevK do
    k, self._prevK = key, key
    for i=-1,li,-1 do
      k, v = self[i](k, v); if k == nil then goto skip end
    end
    do return k, v end -- `do` necessary for parser
    ::skip::
  end
end
Iter.__ipairs = ds.nosupport

--- Used for testing. [$Iter:assertEq(it1, it2)] constructs both
--- iterators using [$Iter()] and then asserts the results are
--- identical.
function Iter:assertEq(it2)
  assert(mty.ty(self) == Iter, 'left is not Iter')
  assert(mty.ty(it2)  == Iter,  'right is not Iter')
  local i, T = 0, require'civtest'
  while true do
    i = i + 1
    local r1 = {self()}
    local r2 = {it2()}
    if not mty.eq(r1, r2) then
      ctx.fmtlog:styled('error', 'Result differs at index '..i, '\n')
      assertEq(r1, r2); error'unreachable'
    end
    if rawequal(r1[1], nil) then return end
  end
end

return Iter
