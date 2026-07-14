local G = G or _G
--- utilities for file loading of lines. Generally users shouldn't
--- need to use this file.
local M = G.mod and mod'lines.futils' or {}

local pth = require'ds.path'
local trace = require'ds.log'.trace
local ix = require'civix'
local U3File = require'lines.U3File'
local fd; if not G.NOLIB then fd = require'fd' end

--- Can be usd instead of loadIdx to force a reload of the index,
--- ignoring modification times/etc.
---
--- This is useful in some situtations where stat is not available.
function M.forceLoadIdx(f, idxpath)
    return U3File:load(idxpath)
end

--- load or reindex the file at path to/from idxpath.
function M.loadIdx(f, idxpath, fmode, reindex) --> idxFile
  local fstat, xstat
  if G.NOLIB then goto createnew end
  trace('loadIdx idxpath=%s mode=%s reindex=%q', idxpath, fmode, reindex)
  fstat, xstat = assert(ix.stat(f))
  if fd.isTrunc(fmode) then goto createnew end
  xstat = ix.stat(idxpath)
  if xstat and ix.statModifiedEq(fstat, xstat) then
    return U3File:load(idxpath)
  end
  ::createnew::
  trace('loadIndex createnew')
  ix.mkDirs(pth.last(idxpath))
  local idx, err = U3File:create(idxpath)
  if not idx then return nil, err end
  reindex(f, idx)
  f:flush(); idx:flush()
  if not G.NOLIB then
    ix.setModified(idx.f, fstat:modified())
  end
  return idx
end

return M