local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local Iter = require'ds.Iter'
local T = require'civtest'
local info = require'ds.log'.info

local M  = require'civix'
local B  = M._B -- bootstrapped
local D = 'lib/civix/'
local O = '.out/'
local push = table.insert
local sfmt = string.format

local Duration = mty.from'ds.time  Duration'

local fin
local function tests()

-- test lib or bootstrap
local function testLib(m)
  local p1 = O..'lib.test'
  os.remove(p1)
  pth.write(p1, 'test data'); assert(m.exists(p1))
  os.remove(p1);              assert(not m.exists(p1))

  local d1 = O..'testDir/'
  M.rmRecursive(d1);  assert(not M.exists(d1)) -- setup
  m.mkdir(d1);                 assert(m.exists(d1))
  assert(not m.mkdir(d1))

  local p2 = d1..'test2.txt';   assert(not m.exists(p2))
  local d = m.dir(d1)
  T.eq(nil, d())

  pth.write(p2, 'test2 data'); assert(m.exists(p2))
  local t = {}; for v in m.dir(d1) do push(t, v) end
  T.eq({'test2.txt'}, t)
  local p3 = d1..'test3.txt'
  pth.write(p3, 'test3 data')
  t = {}; for v in m.dir(d1) do push(t, v) end
  table.sort(t); T.eq({'test2.txt', 'test3.txt'}, t)

  assert(not m.rmdir(d1))
  assert(os.remove(p2));       assert(not m.exists(p2))
  assert(os.remove(p3));       assert(not m.exists(p3))
  assert(m.rmdir(d1));         assert(not m.exists(d1))
end

if not G.NOLIB then
  T'lib'; do testLib(M) end
end
T'libBoot'; do testLib(B) end

local function directShTest(sh)
  T.eq('',           sh'true')
  T.eq('hi there\n', sh{'echo', 'hi there'})
  T.eq('foo --abc=ya --aa=bar --bb=42\n',
    sh{'echo', 'foo', '--abc=ya', aa='bar', bb=42})

  T.throws('Command failed with rc=1', function()
    sh'false'
  end)
  T.throws('Command failed with rc=1', function()
    sh{'commandNotExist', 'blah'}
  end)
end

T'directShBoot'; do directShTest(B.sh) end
T'directSh';     do directShTest(M.sh) end

T'testSh'; do
  local sh, out, err, s = M.sh

  T.eq('/tmp\n', sh{'pwd', CWD='/tmp'})

  T.eq('/tmp thisIsFOO\n',
    sh{'sh', '-c', 'echo $PWD $FOO',
       CWD='/tmp', ENV={'FOO=thisIsFOO'}})

  out, err, s = M.sh{'false', rc=true}
  T.eq(1, s:rc())

  T.eq('from stdin', sh{stdin='from stdin', 'cat'})

  local path = '.out/echo.test'
  local f = io.open(path, 'w+')
  out, err, s = sh{'echo', 'send to file', stdout=f}
  T.eq(nil, out); T.eq(nil, err);
  T.eq(nil, s.stdin); T.eq(nil, s.stdout)
  T.eq('send to file\n', io.open(path):read'a')
  f:seek'set'; T.eq('send to file\n', f:read'a')

  f:seek'set'
  out, err, s = sh{stdin=f, 'cat', stdout=io.open('.out/cat.test', 'w+')}
  T.eq(nil, out); T.eq(nil, err)
  T.eq('send to file\n', io.open('.out/cat.test'):read'a')

  out, err, s = sh{'sh', '-c', "echo 'on STDERR' >&2 ", stdout=false, stderr=true}
  T.eq(nil, out); T.eq('on STDERR\n', err)
  collectgarbage()
end

T'time'; do
  local period, e1 = Duration(0.001), M.epoch()
  for i=1,10 do
    M.sleep(period)
    local e2 = M.epoch()
    local result = e2 - e1; assert((e2 - e1) > period, result)
    e1 = e2
  end
  M.sleep(-2.3)
  local m = M.mono(); M.sleep(0.001); assert(m < M.mono())
end

local TEST_TREE = {
  ['a.txt'] = 'for civix a test',
  b = {
    ['b1.txt'] = '1 in dir b/',
    ['b2.txt'] = '2 in dir b/',
  },
}

local function mkTestTree(tree)
  local d = '.out/civix/'
  if M.exists(d) then M.rmRecursive(d) end
  M.mkTree(d, tree or TEST_TREE, true)
  return d
end

T'cp'; do
  local p1, p2 = O..'cp.txt', O..'cp.2.txt'
  pth.write(p1, 'copy this\ndata')
  M.cp(p1, p2)
  T.eq(pth.read(p1), pth.read(p2))
  assert(M.exists(p2))
  M.rm(p1); assert(not M.exists(p1))
  M.rm(p2); assert(not M.exists(p2))
end

T'walk'; do
  local d = mkTestTree()
  local paths, types, depths = {}, {}, {}
  local w = M.Walk{d}; for path, ty in w do
    push(paths, path); push(types, ty); push(depths, w:depth())
  end
  T.eq({
      ".out/civix/", ".out/civix/a.txt",
      ".out/civix/b/",
        ".out/civix/b/b1.txt",
        ".out/civix/b/b2.txt" }, paths)
  T.eq({'dir', 'file', 'dir', 'file', 'file'}, types)
  T.eq({1,     1,      2,     2,       2},     depths)
  T.eq(nil, w()); T.eq(nil, w());

  local w = M.Walk{d}
  local saw = {}; local function see(path) push(saw, path) end
  local skipB = function(path, ptype)
    return not path:find'/b/' or w:skip()
  end
  local expect = {".out/civix/", ".out/civix/a.txt", ".out/civix/b/"}
  T.eq(expect, Iter{w}:listen(skipB):keysTo())
  
  w = M.Walk{d}
  T.eq(
    {".out/civix/", ".out/civix/a.txt"},
    Iter{w}:listen(see):filterK(skipB):keysTo())
  T.eq(expect, saw)

  T.eq({".out/civix/", ".out/civix/a.txt", ".out/civix/b/"},
       Iter{M.Walk{d, maxDepth=0}}:keysTo{})
  
  T.eq({".out/civix/", ".out/civix/a.txt", ".out/civix/b/",
        ".out/civix/b/b1.txt", ".out/civix/b/b2.txt"},
       Iter{M.Walk{d, maxDepth=1}}:keysTo{})
end

T'mkRmTree'; do
  local d = mkTestTree()
  T.eq(pth.read'.out/civix/a.txt', 
  'for civix a test')
  T.eq(pth.read'.out/civix/b/b1.txt', '1 in dir b/')
  T.eq(pth.read'.out/civix/b/b2.txt', '2 in dir b/')
  M.rmRecursive(d)
  assert(not M.exists(d))
end

T'cpTree'; do
  local d = mkTestTree()
  local d2 = '.out/civix2'
  if M.exists(d2) then M.rmRecursive(d2) end
  M.cpRecursive(d, d2)
  T.path(d2, TEST_TREE)
  M.rmRecursive(d2)
  M.cpRecursive(d, d2, {['b/b2.txt']=true})
  assert(not M.exists(d2..'b/b2.txt'))
end

T'stat'; do
  local path = O..'stat.txt'
  pth.write(path, 'hello\n')
  T.eq(6, M.stat(path):size())
  M.chmod(path, '775')
  T.eq('775', sfmt('%o', tonumber('777', 8) & M.stat(path):mode()))
  M.chmod(path, '711')
  T.eq('711', sfmt('%o', tonumber('777', 8) & M.stat(path):mode()))
end
fin = true;
end ---------------- end tests()

T'findBack' do
  T.eq('./HUB.luk', M.findBack('HUB.luk', 'lib/tests/'))
end

if not G.NOLIB then
local fd = require'fd'
local ixt = require'civix.testing'
fd.ioStd(); T.SUBNAME = '[ioStd]'
fin = false; tests(); assert(fin)

fd.ioSync(); T.SUBNAME = '[ioSync]'
fin = false; tests(); assert(fin)

T.SUBNAME = '[ioAsync]'
fin=false; ixt.runAsyncTest(tests); assert(fin)

fd.ioSync(); T.SUBNAME = ''

-- FIXME: consider re-working and enabling
-- T.fd_perf = function()
--   local Kib = string.rep('123456789ABCDEF\n', 64)
--   local data = string.rep(Kib, 500)
--   local count, run = 0, true
--   local res
--   local O = '.out/'
--   M.Lap{
--     -- make sleep insta-ready instead (open/close use it)
--     sleepFn = function(cor) LAP_READY[cor] = 'sleep' end,
--   }:run{
--     function() while run do
--       count = count + 1; coroutine.yield(true)
--     end end,
--     function()
--       local f = fd.openFDT(O..'perf.bin', 'w+')
--       f:write(data); f:seek'set'; res = f:read'a'
--       f:close()
--       run = false
--     end,
--   }
-- 
--   assert(data == res)
--   -- assert(count > 50, tostring(count))
-- end

fd.ioStd()
end -- if not G.NOLIB