local mty = require'metaty'

--- module for writing simple tests
local M = mty.mod'civtest'
local G = mty.G; G.MAIN = G.MAIN or M

local mty = require'metaty'
local fmt = require'fmt'
local fbin = require'fmt.binary'
local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'
local ix = require'civix'
local info = require'ds.log'.info

M.SUBNAME = ''

local getmt = getmetatable
local get, BiMap          = mty.from'ds      get BiMap'
local isDir               = mty.from'ds.path isDir'
local push, concat        = mty.from'table   insert, concat'
local sfmt                = mty.from'string  format'

local function errordiff(e, r)
  local f = ctx.fmtlog
  if e == r then return f:styled(
    'bold', '\n!! Formatted strings are equal !!\n'
  )end
  ctx.fmtlog:styled('error', '\n!! DIFF:', '\n')
  ctx.fmtlog(require'lines.diff'.Diff(e, r));
end
local function fail(name)
  error(sfmt('Failed %s', name), 2)
end

function M._printName(name, path)
  name = name..M.SUBNAME
  rawset(M, 'NAME', name);
  ctx.fmtlog:styled('h2', sfmt('## Test %-32s', name), ' ')
  ctx.fmtlog:styled('path', pth.nice(path), '\n')
end

--- ["Note: you probably want to do [$T'name'] instead.
---   See [<#usage>].]
--- Run the test, printing information to the terminal.
---
--- This function computes name=[$name..civtest.SUBNAME]
--- and sets civtest.NAME to the new name, which can be
--- used in the test.
function M.runTest(name, fn, path)
  M._printName(name, path)
  return fn()
end

--- Write the diff of strings a vs b to the [@fmt.Fmt] [$f].
--- Typically, you want to call [<#civtest.eq>] instead.
function M.showDiff(f, a, b)
  f = fmt.Fmt:pretty{to=f, style=f.style}
  f:styled('error', '\n!! EXPECT:', '\n');   f(a)
  f:styled('error', '\n!! RESULT:', '\n');   f(b)
  if mty.ty(a) ~= mty.ty(b) then
    f:styled('error', '\n!! TYPES:', ' ',
             mty.name(a), ' != ', mty.name(b), '\n')
  else
    if type(a) == 'string' then
      if #a ~= #b then f:styled('notify', sfmt(
        '\nLengths: %s ~= %s', #a, #b
      ))end
    else a, b = fmt.pretty(a), fmt.pretty(b) end
    errordiff(a, b)
  end
end
local showDiff = M.showDiff

--- Assert that [$a] equals [$b] (according to [<#metaty.eq>]
--- and print a diff if not.
function M.eq(a, b, msg)
  if mty.eq(a, b) then return end
  showDiff(ctx.fmtlog, a, b)
  fail('Test.eq'..(msg and (': '..msg) or ''))
end

--- Assert that two list-like tables are equal.[{br}]
--- Note that this only compares integer keys up to [$#len].
function M.ieq(a, b, msg)
  if #a ~= #b then goto notequal end
  for i=1,#a do
    if not mty.eq(get(a,i), get(b,i)) then goto notequal end
  end
  do return end -- equal
  ::notequal::
  M.eq(ds.icopy(a), ds.icopy(b), msg)
  error'initially compared as not equal but then tested as equal'
end

--- Same as eq but for binary strings. Shows a very clear
--- diff for binary.
function M.binEq(e, r)
  assert(type(e) == 'string', 'expect must be string')
  assert(type(r) == 'string', 'result must be string')
  if e == r then return end
  if #e ~= #r then ctx.fmtlog:styled(
    'notify', sfmt('binary lengths: %s ~= %s\b', #e, #r)
  )end
  errordiff(fbin(e), fbin(r))
  fail'Test.binEq'
end

--- assert [$subj:find(pat)] or show a helpful error message.
function M.matches(pat, subj) --> !?error
  if subj:find(pat) then return end
  local f = ctx.fmtlog
  print('pat:', pat, 'subj:', subj)
  f:styled('error', '\n!! RESULT:', '\n');   f(subj)
  f:styled('error', '\n!! Did not match:', sfmt('%q\n', pat))
  f:styled('error', '!! Failed Test.matches: ', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  fail'matches'
end

--- assert [$subj:find(pat, 1, true)] (plain find)
--- or show a helpful error message.
function M.contains(plain, subj) --> !?error
  if subj:find(plain, 1, true) then return end
  local f = ctx.fmtlog
  f:styled('error', '\n!! RESULT:', '\n');   f(subj)
  f:styled('error', '\n!! Did not contain:', sfmt('%q\n', plain))
  f:styled('error', '!! Failed Test.contains:', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  fail'contains'
end

--- assert [$fn()] fails and the [$contains] is in the message.
function M.throws(contains, fn) --> ds.Error
  local ok, err = ds.try(fn)
  if ok then
    ctx.fmtlog:styled('error',
      '!! Unexpected: did not receive an error:\n')
    fail'throws: not receive expected error'
  end
  if err.msg:find(contains, 1, true) then return err end
  local f = ctx.fmtlog
  f:styled('error', '\n!! Unexpected Result:', '\n');
  f:styled('error', 'Actual error:', '\n')
  f:write(err.msg)
  f:styled('error', '\n# end actual error', '\n')
  showDiff(f, contains, err.msg)
  fail'Test.throws (not expected)'
end

--- Assert that the path exists.
function M.exists(path)
  path = pth.canonical(path)
  if not require'civix'.exists(path) then error(
    'does not exist: '..path
  )end
end

--- Assert that the path does not exist.
function M.notExists(path)
  path = pth.canonical(path)
  if require'civix'.exists(path) then error('exists: '..path)end
end

--- Assert the contents at the two file paths are equal.
function M.fileEq(a, b)
  local at, bt = pth.read(a), pth.read(b)
  if at == bt then return end
  showDiff(ctx.fmtlog, at, bt);
  ctx.fmtlog:styled('error', sfmt('Path expected: %s\n       result: %s',
    a, b), '\n')
  fail'Test.pathEq'
end

--- Deprecated: use fileEq instead.
M.pathEq = M.fileEq

--- Assert that path matches expect. Expect can be of type:
--- * string: asserts the file contents match.
--- * table: recursively assert the subtree contents exist.
--- * bool: (true)=assert existance, (false)=assert non-existance.
function M.path(path, expect)
  if type(expect) == 'boolean' then
    if expect then M.exists(path) else M.notExists(path) end
    return
  end
  M.exists(path)
  if ctx.fileType(expect) then
    expect:seek'set'
    expect = assert(expect:read'*a')
  end
  if type(expect) == 'string' then
    local txt = pth.read(path)
    if expect == txt then return end
    ctx.fmtlog:styled('error', '!! Path '..path, '\n')
    showDiff(ctx.fmtlog, expect, txt)
    fail'Test.tree'
  end
  if ix.pathtype(path) ~= ix.DIR then error(path..' is not a dir') end
  for k, v in pairs(expect) do M.path(pth.concat{path, k}, v) end
end

M.DirsEq = mty'DirsEq' {
  -- expected and result absolute dirs
  'd1 [dir]', 'd2 [dir]',
  -- remaining paths are relative to d1 and d2.
  -- all paths on each side (used for final diff)
  'paths1 {path}', 'paths2 {path}',
  'diff {path}: paths that had different type or content',
  'ignore {path: true}: paths/dirs to ignore',
}
getmetatable(M.DirsEq).__call = function(T, self)
  self.d1, self.d2 = pth.toDir(self.d1), pth.toDir(self.d2)
  self.paths1, self.paths2 = {}, {}
  self.diff = {}
  self.ignore = self.ignore
  return mty.construct(T, self)
end

function M.DirsEq:__call(dir)
  if self.ignore[dir] then return end
  local l1, l2 = BiMap(ix.ls(self.d1..dir)), BiMap(ix.ls(self.d2..dir))
  for _, e1 in ipairs(l1) do
    local p = dir..e1; if self.ignore[p] then goto cont end
    self.paths1[p] = true
    if not l2[e1] then push(self.diff, p); goto cont end
    self.paths2[p] = true
    if isDir(e1) then self(p)
    elseif not ix.pathEq(self.d1..p, self.d2..p) then push(self.diff, p) end
  ::cont::end
  for _, e2 in ipairs(l2) do -- check for items in only l2
    local p = dir..e2
    if not self.ignore[p] and not l1[e2] then
      push(self.diff, p); self.paths2[p] = true
    end
  end
end

--- Assert two dirs are recursively equal.
function M.dirs(expect, result, ignore)
  local d = M.DirsEq{d1=expect, d2=result, ignore=ignore}
  d''; if #d.diff == 0 then return end
  local d1, d2, f = d.d1, d.d2, ctx.fmtlog
  f:styled('warn', 'Found differences '..concat(d.diff, ', '), '\n')
  for _, p in ipairs(d.diff) do
    if pth.isDir(p) then goto cont end
    local c1 = d.paths1[p] and pth.read(d1..p) or '<DOES NOT EXIST>'
    local c2 = d.paths2[p] and pth.read(d2..p) or '<DOES NOT EXIST>'
    f:styled('error', 'Content: '..p, '\n')
    showDiff(f, c1, c2)
  ::cont::end
  if not mty.eq(d.paths1, d.paths2) then
    showDiff(f, d.paths1, d.paths2)
  end
  f:styled('error', sfmt('Dir %s\n!= %s', expect, result), '\n')
  error(sfmt('Dir %s ~= %s', expect, result))
end

getmetatable(M).__call = function(_, name)
  return M._printName(name, ds.shortloc(1))
end

getmetatable(M).__newindex = function() error"Immutable mod" end
return M