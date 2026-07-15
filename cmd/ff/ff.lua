#!/usr/bin/env -S lua
local shim = require'shim'

--- Usage: [$ff find_this or_this]
local FF = shim.cmd'ff' {
  'root   {paths}: list of root paths, i.e. [$r:path1/ r:path2]',
  'cnt    {pat}: list of patterns to find in the content',
  'path   {pat} [$p:%.lua] list of file path patterns',
  'sub [string]: the subsitution string to use with cnt.',
  'mut [bool]: mutate files (used with sub)',
  'dirs [bool]: show all non-excluded directories',
  'content [bool]: if false do not show content (only show paths)',
    content=true,
  'hidden [bool]: whether to include [$.hidden] paths (default=false)',
    hidden = false,
 [[pathsub [string]: the substitution string to rename the path.
   Note: this implies content=false and cannot be used with sub
 ]],
   'depth [int]: depth to search from root directories',
   'to [file]: where to print to',
}

local mty  = require'metaty'
local ds   = require'ds'
local log  = require'ds.log'
local pth  = require'ds.path'
local Iter = require'ds.Iter'
local civix = require'civix'
local vt100 = require'vt100'

local sfmt, gsub = string.format, string.gsub
local push = table.insert
local construct = mty.construct
local nice = pth.nice
local assertf = mty.from'fmt  assertf'

local fmtMatch, fmtSub, parseColons

--- Construct the cmd without executing.
FF.new = function(T, args) --> ff callable
  args = shim.parseStr(args)
  for _, k in ipairs{'root', 'cnt', 'path'} do
    args[k] = shim.list(args[k])
  end
  shim.popRaw(args, args.root)
  parseColons(args)
  if not args.hidden then table.insert(args.path, 1, '-/%.') end
  return construct(T, args)
end

function FF:__call() return self:iter():keysTo() end

getmetatable(FF).__call = function(T, self)
  return T:new(self)()
end

--- Get an iterator of matching paths.
---
--- Usage: [$for path, pty in FF:new{...}:iter() do ... end]
function FF:iter() --> iter[path, pty]
  -- FIXME: this should move to constructor?
  if self.pathsub then
    self.content = false
    assert(self.path, 'must set path pattern with path pathsub')
  else self.content = shim.bool(self.content) end
  if not self.content then
    assertf(#self.cnt == 0, 'content=false but content search set: %q', self.cnt)
  end
  assert(not (self.sub and self.pathsub), 'must set only one: sub pathsub')
  if #self.root == 0 then self.root[1] = pth.cwd() end
  do local pos -- ensure path has at least one postive matcher
    for _, p in ipairs(self.path) do
      if p:sub(1,1) ~= '-' then pos = true; break end
    end
    if not pos then push(self.path, '') end
  end

  log.info('ff %q', self)
  local sf = vt100.Fmt{to=self.to or io.stdout}
  local w = {}; for _, p in ipairs(self.root) do
    push(w, pth.canonical(p))
  end
  w.maxDepth = shim.int(self.depth)
  w = civix.Walk(w)
  local it, finds = Iter{w}, ds.find
  -- check path patterns
  if #self.path > 0 then;   it:map(function(p, pty)
    if (pty == 'dir') or finds(p, self.path) then return p, pty end
  end); end

  -- show/no-show dirs
  if self.dirs then;   it:map(function(p, pty)
      if pty == 'dir' then sf:styled('path', nice(p), '\n') end
      return p, pty
    end)
  else
    it:map(function(p, pty) if pty ~= 'dir' then return p, pty end end)
  end

  -- find pattern or sub in file
  local cnt, sub = self.cnt, self.sub
  if #cnt == 0 then
    it:map(function(p, pty)
      if pty ~= 'dir' then sf:styled('path', nice(p), '\n') end
      return p, pty
    end)
    -- FIXME: definitely print paths here
  else
    it:map(function(p, pty)
      if (pty == 'dir') or self:_find(p, cnt, sub) then return p, pty end
    end)
  end

  -- perform actual replacement mutation
  if sub and self.mut then
    it:map(function(p, pty)
      if pty == 'file' then
        local subPath = p..'.SUB'
        local to = assert(io.open(subPath, 'w+'))
        if to:seek'end' ~= 0 then error(sfmt(
          '%s already exists', subPath
        ))end
        self:_replace(p, to, cnt, sub)
        to:flush(); to:close();
        civix.mv(subPath, p)
      end
      return p, pty
    end)
  end

  -- filter out dirs at the end (files were already filtered)
  if #self.path > 0 then;   it:map(function(p, pty)
    if (pty ~= 'dir') or finds(p, self.path) then return p, pty end
  end); end

  if self.pathsub and self.mut then
    it:map(function(p, pty)
      local fs, fe, fi, fpat = ds.find(p, self.path)
      assert(fs)
      civix.forceMv(p, gsub(p, fpat, self.pathsub))
    end)
  end
  return it
end


--- find patterns in path.
--- If there is a match then the path is logged to [$io.stdout] and the matches
--- to [$io.fmt].
function FF:_find(path, pats, sub) --> boolean
  local f, sf = io.fmt, vt100.Fmt{to=io.stdout}
  local onlypath = not self.content
  if not civix.exists(path) then
    sf:styled('error', 'Does not exist: '..path, '\n')
    return false
  end
  local found, l, find, ms, me, pi, pat = false, 0, ds.find
  for line in io.lines(path, 'L') do
    l, ms, me, pi, pat = l + 1, find(line, pats)
    if ms then
      if onlypath then
        local path, fs, fe, fi, fpat = path..'\n', find(path, self.path)
        assertf(fs, 'find(%q, %q) returned no paths', path, self.path)
        fmtMatch(f, nil, path..'\n', fs, fe)
        if self.pathsub then
          local after = assert(gsub(path, fpat, self.pathsub))
          fmtSub(f, path..'\n', after..'\n')
        end
        return true
      end
      if not found then
        sf:styled('path', nice(path), '\n'); sf:flush()
        found = true
      end
      fmtMatch(f, l, line, ms, me)
      if sub then
        local after = assert(gsub(line, pat, sub))
        fmtSub(f, line, after)
      end
    end
  end
  return found
end

--- perform replacement of [$pats] with [$sub], writing to [$to]
function FF:_replace(path, to, pats, sub)
  local find, ms, me, pi, pat = ds.find
  for line in io.lines(path, 'L') do
    ms, me, pi, pat = find(line, pats)
    to:write(ms and gsub(line, pat, sub) or line)
  end
end

local COLON = {
  ['r:']='root', ['p:']='path', ['c:']='cnt', ['s:']='sub',
}
--- parse [$c:commands] into t
function parseColons(args)
  local cmd, si
  for _, str in ipairs(args) do
    si = 1; cmd = COLON[str:sub(si, si+1)]
    if cmd then si = si + 2 else cmd = 'cnt' end
    if cmd == 'sub' then
      assert(not args.sub, 'sub specified twice')
      args.sub = str:sub(si)
    else
      push(args[cmd], str:sub(si))
    end
  end
  ds.clear(args)
end

-----------------------
-- Logging Utilities
local function linenum(l) return sfmt('% 6i ', l) end
local AFTER = '   --> '

local function splitMatch(str, ms, me) --> beg, mat, end_
  local beg, mat = str:sub(1,ms-1), str:sub(ms,me)
  local end_     = str:sub(me+1)
  local hasNL = str:sub(-1) == '\n'
  if hasNL then
    if end_ == '' then mat = mat:sub(1,-2)
    else end_ = end_:sub(1,-2) end
  else end_ = end_..'[EOL]' end
  return beg, mat, end_
end

function fmtMatch(f, l, str, ms, me)
  local beg, mat, end_ = splitMatch(str, ms, me)
  f:styled('line',  l and linenum(l) or '       ')
  f:styled(nil,     beg)
  f:styled('match', mat)
  f:styled(nil,     end_, '\n')
end
function fmtSub(f, before, after)
  local si, ei = 1, -1
  while before:sub(si,si) == after:sub(si,si) do si = si + 1 end
  while before:sub(ei,ei) == after:sub(ei,ei) do ei = ei - 1 end
  ei = #after + ei + 1
  if ei == 0 then return end
  local beg, mat, end_ = splitMatch(after, si, ei)
  f:styled('meta', AFTER)
  f:styled('meta', beg)
  f:styled(nil,    mat)
  f:styled('meta', end_, '\n')
end

if shim.isMain(FF) then FF:main(G.arg) end
return FF