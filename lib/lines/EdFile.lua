local mty = require'metaty'
--- EdFile: an editable line-based file object, optimized for
--- indexed and consequitive reads and writes
---
--- [*Usage:][{$$ lang=lua}
--- local ed = EdFile(path, mode);
--- ed:set(1, 'first line')
--- ed:set(2, 'second line')
--- ed:set(1, 'changed first line')
--- ed:close()
--- ]$
local EdFile = mty.recordMod'EdFile' {
  'lf   [lines.File]: indexed append-only file.',
  'dats [list]: list of Slc | Gap objects.',
  'lens [list]: rolling sum of dat lengths.',
}

local ds = require'ds'
local log = require'ds.log'
local U3File = require'lines.U3File'
local Gap = require'lines.Gap'
local File = require'lines.File'
local U3File = require'lines.U3File'

local info = require'ds.log'.info
local push = table.insert
local getmt = getmetatable
local min, MAXINT = math.min, math.maxinteger
local index, newindex = mty.hardIndex, mty.newindex
local construct = mty.construct
local binsearch = ds.binarySearch
local get, lt, Slc, extend, inset, clear = mty.from'ds\
      get, lt, Slc, extend, inset, clear'
local move, EMPTY = table.move, {}

getmetatable(EdFile).__index = mty.hardIndex
EdFile.__newindex            = mty.hardNewindex

getmetatable(EdFile).__call = function(T, v, mode)
  local lf, err = File{path=v, mode=mode or 'a+'}
  if not lf then return nil, err end
  return construct(T, {
    lf=lf, dats={Slc{si=1, ei=#lf}}, lens={},
  })
end

function EdFile:__fmt(f)
  f:write'EdFile('; f(self.lf.path or 'no-path'); f:write')'
end

function EdFile:_updateLens(max)
  max = max or MAXINT
  local lens, dats, len = self.lens, self.dats
  for i=#lens+1, #dats do
    len = (lens[i - 1] or 0) + #dats[i]
    lens[i] = len
    if len >= max then return end
  end
end

function EdFile:__len()
  self:_updateLens()
  local l = self.lens; return l[#l] or 0
end

--- get the index into dats where [$:get(i)] is located
function EdFile:_datindex(i) --> di
  if i < 1 then return end
  local lens = self.lens; local len = lens[#lens]
  if not len or i > len then self:_updateLens(i) end
  if i > lens[#lens] then return end
  return binsearch(lens, i, lt) + 1
end

--- Get line at index
function EdFile:get(i) --> line
  local di = self:_datindex(i); if not di then return end
  local dat = self.dats[di]
  i = i - (self.lens[di-1] or 0) -- i is now index into dat
  return (getmt(dat) == Slc) and self.lf:get(dat.si + i - 1)
      or get(dat,i)
end

function EdFile:write(...) --> self?, errmsg?
  local dats = self.dats
  local last = dats[#dats]
  self.lens[#dats] = nil
  local ok, errmsg
  if getmt(last) == Slc then
    ok, errmsg = self.lf:write(...)
    last.ei = #self.lf.idx
  else ok, errmsg = last:write(...) end
  return ok and self or nil, errmsg
end

--- Set line at index.
function EdFile:set(i, v)
  self:inset(i, {v}, 1)
end

--- Return a read-only view of the EdFile which shares the
--- associated data structures.
function EdFile:reader()
  return EdFile {
    lf=self.lf:reader(),
    dats=self.dats, lens=self.lens
  }
end

--- Flush the .lf member (which can only be extended).
--- To write all data to disk you must call [$:dumpf()].
function EdFile:flush() return self.lf:flush() end

--- Note: to write all data to disk you must call [$:dumpf()].
function EdFile:close() return self.lf:close() end

--- Dump contents to file or path.
function EdFile:dumpf(f)
  local close = false
  if type(f) == 'string' then
    f = assert(io.open(f)); close = 1
  end
  -- TODO: this is not very performant. Update to
  --       write the whole Slc/Gap that it finds.
  for i=1,#self do f:write(self:get(i), '\n') end
  if close then f:flush(); f:close() end
end

--- Appends to lf for extend when possible.
function EdFile:extend(values)
  if #values == 0 then return end
  local dlen = #self.dats
  local last = self.dats[dlen]
  if getmt(last) == Slc then
    local lf = self.lf
    extend(lf, values); last.ei = #lf
  else extend(last, values) end
  local lens = self.lens
  if dlen == #lens then
    lens[dlen] = lens[dlen] + #values
  end
  return self
end

----------------------------
-- EdFile.inset
-- This is the major logic for mutating an EdFile

--- inset the dat, pushing to dats the values that have to be
--- reinserted into the EdFile.dats
local function insetDat(dats, dat, i, values, rmlen)
  if getmt(dat) ~= Slc then
    inset(dat, i, values, rmlen)
    push(dats, dat)
    return
  end
  local dlen, vlen = #dat, values and #values or 0
  if (vlen == 0) and (rmlen == 0 or i > dlen) then
    push(dats, dat) -- no change
    return
  end
  if i > 1 then
    push(dats, Slc{si=dat.si, ei=i - 1})
  end
  if vlen > 0 then push(dats, Gap(values)) end
  if i + rmlen <= dat.ei then
    push(dats, Slc{si=i + rmlen, ei=dat.ei})
  end
end

--- insert into EdFile's dats.
function EdFile:inset(i, values, rmlen) --> rm?
  rmlen = rmlen or 0

  -- General algorith:
  -- * Get the first and last dats in [i:i+rmlen]. Inner dats are dropped.
  -- * Handle Slc types by splitting them
  -- * Handle rmlen for each section individually
  -- * Handle Gaps by joining them
  local lens, df, dl = self.lens, self:_datindex(i), nil
  if not df then
    -- special case: extend. This is special because it writes to the file.
    assert(i == #self + 1, 'i > len+1')
    self:extend(values)
    return
  end

  if rmlen > 0 then -- find last dat to remove (and in-between)
    dl = self:_datindex(i + rmlen - 1)
    if dl then if (dl - df > 1) then
      -- update rmlen with dropped dats
      rmlen = rmlen - (lens[dl-1]-lens[df + 1])
    elseif df == dl then dl = nil end end
  end

  -- Note: rdats is replace dats (not rm), they
  -- are inset into dats at the end.
  local dats, rdats, ldat = self.dats , {}                 , nil
  local first,   fi, ei   = dats[df], i - (lens[df-1] or 0)

  -- We handle the first and last items separately. By the end of these
  -- blocks we want them to be of type Gap with the rmlen values removed.
  if getmt(first) == Slc then
    -- split up first slice
    if 1 < fi then
      push(rdats, Slc{si=first.si, ei=first.si + fi - 2})
    end
    if dl then
      rmlen = rmlen - (#first - fi); assert(rmlen > 0, 'programmer error')
    elseif (fi + rmlen) <= first.ei then -- put Slc at end
      local slc = Slc{si=(first.si+fi-1) + rmlen, ei=first.ei}
      rmlen, ldat = 0, slc
    end
    fi, first = 1, nil
  else -- Gap
    local rmfirst = min(rmlen, #first - fi + 1)
    if rmfirst > 0 then
      first:inset(fi, nil, rmfirst)
      rmlen = rmlen - rmfirst
    end
  end

  local last, li
  if dl then
    last = dats[dl]
    if getmt(last) == Slc then
      if rmlen < #last then
        ldat = Slc{si=last.si + rmlen, ei=last.ei}
      end
      last = nil
    elseif rmlen > 0 then
      last:inset(1, nil, rmlen); rmlen = 0
    end
  end

  if last then
    if first then first:extend(last) -- join first+last
    else          first, fi = last, 1 end
  end
  if values and #values > 0 then
    first = first or Gap()
    first:inset(fi, values, 0)
  end
  if first then push(rdats, first) end
  if ldat  then push(rdats, ldat) end

  -- consolodate Gap objects
  first = dats[df-1]
  -- TODO: I think the second check is implied?
  if (getmt(first) == Gap) and (getmt(rdats[1]) == Gap) then
    first:extend(rdats[1]); rdats[1], df = first, df - 1
  end
  local last = rdats[#rdats]
  if dl and (getmt(last) == Gap) and (getmt(dats[dl+1]) == Gap) then
    last:extend(dats[dl+1]); dl = dl + 1
  end
  move(EMPTY, df, #lens, df, lens) -- clear end lens
  inset(dats, df, rdats, (dl or df) - df + 1)
end

EdFile.icopy = ds.defaultICopy

return EdFile