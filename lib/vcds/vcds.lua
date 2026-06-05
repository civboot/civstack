--- vsds: version control data structures (and algorithms)
local M = mod and mod'vcds' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds  = require'ds'
local push, sfmt = table.insert, string.format
local construct = mty.construct

local function nw(n) -- numwidth
  if n == nil then return '        ' end
  n = tostring(n); return n..string.rep(' ', 8-#n)
end

M.ADD = '+'
M.REM = '-'

-- TODO: I want to use this when applying patches
--- normalize a line for comparing (anchoring).
--- This just squashes and trims the end.
function M.normalize(s) return ds.squash(ds.trimEnd(s)) end

--- Single Line Diff
--- This type is good for displaying differences to a user.
M.Diff = mty'Diff' {
  "b (base)   orig file.  '+'=added",
  "c (change) new file.   '-'=removed",
  "text[string]",
}
getmetatable(M.Diff).__call = function(T, b, c, text)
  return mty.construct(T, {b=b, c=c, text=text})
end

function M.Diff:__tostring()
  return string.format("%4s %4s|%s", self.b, self.c, self.text)
end
function M.Diff:isKeep()
  return (self.b ~= M.ADD) and (self.c ~= M.REM)
end

local function pushAdd(ch, text)
  if not ch.add then ch.add = {} end; push(ch.add, text)
end

----------------------
-- ChangeList composed of Keep and Change directives
-- This is how diffs are often serialized

M.Keep = mty'Keep' {'num[int]'}
function M.Keep:len() return self.num and self.num or #self end

M.Change = mty'Change' {
  'rem[int|table] removed lines',
  'add[string]    text to add',
}
function M.Change:len()
  return (type(self.rem) == 'number') and self.rem or #self.rem
end

--- Apply changes to base (TableLines), push to [$out]
function M.apply(base, changes, out--[[{}]]) --> out
  local l = 1; out = out or {}
  for _, p in ipairs(changes) do
    local pty = mty.ty(p)
    if pty == M.Keep then
      for i=l, l + p:len() - 1 do push(out, assert(base[i], 'base OOB')) end
      l = l + p:len()
    else
      fmt.assertf(pty == M.Change, 'patch type must be Keep|Change: %s', pty)
      if p.add then for _, a in ipairs(p.add) do push(out, a) end end
      l = l + p.rem
    end
  end
  return out
end

----------------------
-- Conversion

function M.toChanges(diffs, full)
  local changes, p = {}, nil
  for _, d in ipairs(diffs) do
    if d:isKeep() then
      if not p or mty.ty(p) ~= M.Keep then
        push(changes, p); p = M.Keep{num=not full and 0 or nil}
      end
      if full then push(p, d.text) else p.num = p.num + 1 end
    else
      if not p or mty.ty(p) ~= M.Change then
        push(changes, p); p = M.Change{rem=full and {} or 0}
      end
      if d.b == M.ADD then pushAdd(p, d.text)
      else assert(d.c == M.REM)
        if full then push(p.rem, d.text)
        else         p.rem = p.rem + 1 end
      end
    end
  end
  if p then push(changes, p) end
  return changes
end

M.DiffSoF = M.Diff('^', 0,  '') -- start of file
M.DiffEoF = M.Diff('$', -1, '') -- end of file

M.DiffsExtender = mty'DiffsExtender' {
  'diffs [list]',
  'base',
  'bl [int]: base line',
  'cl [int]: change line',
}
getmetatable(M.DiffsExtender).__call = function(T, base)
  return construct(T, {diffs={}, base=base, bl=1, cl=1})
end
--- extend change to diffs
function M.DiffsExtender:__call(ch, keepMax)
  local chTy, base, diffs = mty.ty(ch), self.base, self.diffs
  if chTy == M.Keep then
    for l = self.bl, self.bl + ch:len() - 1 do
      push(diffs, M.Diff(l, self.cl, base[l]))
      self.cl = self.cl + 1
    end; self.bl = self.bl + ch:len()
  else
    fmt.assertf(chTy == M.Change, "changes must be Keep|Change: %s", chTy)
    for _, a in ipairs(ch.add) do
      push(diffs, M.Diff('+', self.cl, a)); self.cl = self.cl + 1
    end
    for l = self.bl, self.bl + ch:len() - 1 do
      push(diffs, M.Diff(l, '-', base[l]))
    end; self.bl = self.bl + ch:len()
  end
end
local DiffsExtender = M.DiffsExtender

--- Convert Changes to Diffs with full context
function M.toDiffs(base, changes) --> diffs
  local de = DiffsExtender(base)
  for _, ch in ipairs(changes) do de(ch) end
  return de.diffs
end

function M.createAnchorTop(base, l, aLen)
  local a = {}; if l < 1 then return a end
  for l = l, 1, -1 do
    if aLen <= 0 then break end
    local line = base[l]; push(a, M.Diff(l, '@', line))
    if ds.trim(line) ~= '' then aLen = aLen - 1 end
  end
  return ds.reverse(a)
end

function M.createAnchorBot(base, l, aLen)
  local a = {}; for l, line in ds.islice(base, l) do
    if aLen <= 0 then break end
    push(a, M.Diff(l, '@', line))
    if ds.trim(line) ~= '' then aLen = aLen - 1 end
  end
  return a
end

--- Create picks (aka cherry picks) iterator from changes.
--- These can then be applied to a new base using vcds.patch(base, picks)
---
--- Each "pick" is a list of Diffs which are anchored by the lines
--- above and below (unless they are start/end of file).
M.Picks = mty'Picks' {
  'changes [list]: list of changes',
  'ci [int]: for iterating',
  'de [DiffsExtender]',
  'set [table]: settings (need refactor)',
}
getmetatable(M.Picks).__call = function(T, base, changes, set) --> Picks
  set = set or {}
  set.anchorLen = set.anchorLen or 3
  return construct(T, {
    changes = changes, ci=1,
    de = DiffsExtender(base),
    set=set,
  })
end
function M.Picks:__call() --> iterator
  local de, changes, aLen = self.de, self.changes, self.set.anchorLen
  if self.ci > #changes then return end
  assert(ds.isEmpty(de.diffs))

  local ci, endci = self:groupChanges(self.ci)
  while self.ci < ci do de(changes[self.ci]); self.ci = self.ci + 1 end -- discard
  de.diffs = M.createAnchorTop(de.base, de.bl - 1, aLen)
  while self.ci <= endci do de(changes[self.ci]); self.ci = self.ci + 1 end -- changes
  ds.extend(de.diffs, M.createAnchorBot(de.base, de.bl, aLen))
  local diffs = de.diffs; de.diffs = {}
  return diffs
end

--- Get which changes to include in a patch group.
--- A group is a series of patches with Keep:len() < anchorLen (default=3)
--- between them.
function M.Picks:groupChanges(ci)
  local len, aLen = #self.changes, self.set.anchorLen
  while ci <= len and mty.ty(self.changes[ci]) == M.Keep do
    ci = ci + 1
  end
  local starti = ci
  for ci, ch in ds.islice(self.changes, ci) do local ci=ci
    local chTy = mty.ty(ch)
    if ci == len then
      if chTy == M.Keep then ci = ci - 1 end
      return starti, ci
    end
    if (chTy == M.Keep) and (ch:len() >= aLen) then
      return starti, ci - 1 end
  end; error'unreachable'
end

local function checkAnchor(iter, base, bl)
  local bline; for _, aline in table.unpack(iter) do
    if ds.trim(aline) == '' then              goto continue end
    bline = base[bl]; if not bline then return false end
    if ds.trim(bline) == '' then bl = bl + 1; goto continue end
    if not mty.eq(aline, bline) then return false end
    bl = bl + 1; ::continue::
  end
  return true
end

--- Find the actual anchor by searching for uniqueness in the anchors [+
--- * above=true:  find above (search up)
--- * above=false: find below (search down)
--- ]
function M.findAnchor(base, baseMap, anchors, above--[[false]]) --> (l, c)
  local iterFn = above and ds.ireverse or ipairs
  local alines = {}
  for ai, anchor in iterFn(anchors) do
    local bls = baseMap[anchor.text]; if not bls then return end
    if #bls == 1 then
      -- in this case below needs to subtract previous lines
      -- in `found` case, it is comparing correctly so no need.
      return bls[1] - (above and 0 or #alines), #alines + 1
    end
    push(alines, anchor.text)
    -- see if the whole anchor is unique
    local found, fbl = 0; for _, bl in ipairs(bls) do
      bl = above and bl or (bl - #alines + 1)
      if checkAnchor({iterFn(alines)}, base, bl) then
        found, fbl = found + 1, bl
      end
    end
    if found == 1 then return fbl, #alines end
  end
end

M.Patch = mty'Patch' {
  'conflict [string]', 'bl [number]',
}

function M.pickAnchorsTop(pick) --> isStartOfFile, anchors
  local anchors = {}; for _, d in ipairs(pick) do
    if not d:isKeep() then break end; push(anchors, d)
  end
  return pick[1].c == 1, anchors
end

function M.pickAnchorsBot(base, pick) --> isEndOfFile, anchors
  local anchors = {}; for _, d in ds.ireverse(pick) do
    if not d:isKeep() then break end; push(anchors, d)
  end
  return pick[#pick].b == #base, ds.reverse(anchors)
end

local function patchConflict(pick, conflict)
  local p = M.Patch{conflict=conflict}; ds.extend(p, pick)
  return p
end

local function patchApplyKeep(p, base, keep)
  for _, kline in ipairs(keep) do
    if base[bl] ~= kline then return false end
    push(p, base[bl])
    bl = bl + 1
  end
  return true
end

local function patchApplyChange(p, base, ch) --> bl, clean, err
  local remAnc, addAnc, iadd, irem = true, true, 1, 1
  while (iadd <= #ch.add) or (irem <= #ch.rem) do
    local bline = base[p.bl]
    local aline, rline = ch.add[iadd], ch.rem[irem]
    fmt.assertf(rline ~= aline, '!removed == added: %s', rline)
    if bline == rline then irem = irem + 1
    elseif iadd <= #ch.add then
      if bline == aline then p.bl = p.bl + 1 end
      push(p, aline); iadd = iadd + 1
    else return false end
  end
  return true
end

--- Create a patch item from a pick
---
--- At it's most basic it would just be: [+
--- * find line position via top and/or bottom anchor. We want at least 2 lines
--- * convert pick to change. Walk the text applying the change.
--- ]
---
--- There are some strategies to fix common anchor misses: [+
--- * If an anchor is missing, the nearby change can be used instead. Use either
---   the removed or added lines. For instance, if we are supposed to remove lines
---   then try and find them. Conversely if the patch was already applied then the
---   supposed-to-be added lines will already be there!
--- * When adding, existing identical text is okay.
--- * When removing, missing text is okay as long as it's followed by an anchor of
---   some kind
--- * Keep lines act as an anchor (for above) but are otherwise not required - they
---   are "free" to change or be removed. If they are missing then the algorithm will
---   try to continue the change with or without them (dynamic programming)
--- * empty lines are entirely ignored and are not considered an anchor
--- ]
function M.createPatch(base, baseMap, pick)
  local isSof, topA = M.pickAnchorsTop(pick)
  local isEof, botA = M.pickAnchorsBot(base, pick)
  local top, topLines = M.findAnchor(base, baseMap, topA, true)
  local bot, botLines = M.findAnchor(base, baseMap, botA, false)
  top = (isSof and 1)           or (top and (top + topLines))
  bot = (isEof and (#base + 1)) or (bot and (bot + botLines))
  -- TODO: use next change or bot as anchor
  if not top then return patchConflict(pick,
    '%s anchor not found',
    (not top and not bot) and 'top and bot' or 'top'
  )end
  local pch, clean = M.Patch{bl=top}, top and true
  local clean2, conflict
  local function checkDirty(dirtyErr)
    if not conflict and not (clean or clean2) then
      conflict = dirtyErr
    end
  end
  for _, ch in ipairs(M.toChanges(pick, true)) do
    if mty.ty(ch) == M.Keep then
      clean2, conflict = patchApplyKeep(pch, base, ch)
      checkDirty'missing Keep after unanchored remove'
    else assert(mty.ty(ch) == M.Change)
      clean2, conflict = patchApplyChange(pch, base, ch)
      checkDirty'removed lines missing without anchor'
    end
    if conflict then return patchConflict(pick, err) end
    clean = clean2
  end
  pch.bl = (isSof and 0) or top
  return pch
end

return M
