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

M.SUBNAME = ''

local get = ds.get
local getmt = getmetatable
local push, sfmt = table.insert, string.format

local function errordiff(e, r)
  local f = io.fmt
  if e == r then return f:styled(
    'notice', '\n(Formatted strings are equal)'
  )end
  io.fmt:styled('error', '\n!! DIFF:', '\n')
  io.fmt(require'lines.diff'.Diff(e, r));
end
local function fail(name)
  error(sfmt('Failed %s', name), 2)
end

function M._printName(name, path)
  name = name..M.SUBNAME
  rawset(M, 'NAME', name);
  io.fmt:styled('h2', sfmt('## Test %-32s', name), ' ')
  io.fmt:styled('path', pth.nice(path), '\n')
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
  showDiff(io.fmt, a, b)
  fail('Test.eq'..(msg and (': '..msg) or ''))
end

--- Assert that the indexes of two items with a length are equal.
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
  if #e ~= #r then io.fmt:styled(
    'notify', sfmt('binary lengths: %s ~= %s\b', #e, #r)
  )end
  errordiff(fbin(e), fbin(r))
  fail'Test.binEq'
end

--- assert [$subj:find(pat)] or show a helpful error message.
function M.matches(pat, subj) --> !?error
  if subj:find(pat) then return end
  local f = io.fmt
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
  local f = io.fmt
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
    io.fmt:styled('error',
      '!! Unexpected: did not receive an error: ')
    fail'Test.throws (no error)'
  end
  if err.msg:find(contains, 1, true) then return err end
  local f = io.fmt 
  f:styled('error', '\n!! Unexpected Result:', '\n');
  f:styled('error', 'Actual error:', '\n')
  f:write(err.msg)
  f:styled('error', '\n# end actual error', '\n')
  showDiff(f, contains, err.msg)
  fail'Test.throws (not expected)'
end

--- Assert that the path exists.
function M.exists(path)
  if not require'civix'.exists(path) then error(
    'does not exist: '..path
  )end
end

--- Assert the contents at the two paths are equal.
function M.fileEq(a, b)
  local at, bt = pth.read(a), pth.read(b)
  if at == bt then return end
  showDiff(io.fmt, at, bt);
  io.fmt:styled('error', sfmt('Path expected: %s\n       result: %s',
    a, b), '\n')
  fail'Test.pathEq'
end

--- Deprecated: use fileEq instead.
M.pathEq = M.fileEq

--- Assert that path matches expect. Expect can be of type:
--- * string: asserts the file contents match.
--- * table: recursively assert the subtree contents exist.
function M.path(path, expect)
  M.exists(path)
  if io.type(expect) then
    expect:seek'set'
    expect = assert(expect:read'*a')
  end
  if type(expect) == 'string' then
    local txt = pth.read(path)
    if expect == txt then return end
    io.fmt:styled('error', '!! Path '..path, '\n')
    showDiff(io.fmt, expect, txt)
    fail'Test.tree'
  end
  if ix.pathtype(path) ~= ix.DIR then error(path..' is not a dir') end
  for k, v in pairs(expect) do M.path(pth.concat{path, k}, v) end
end

getmetatable(M).__call = function(_, name)
  return M._printName(name, ds.shortloc(1))
end

getmetatable(M).__newindex = function() error"Immutable mod" end
return M