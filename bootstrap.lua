#!/usr/bin/env -S lua
-- This script bootstrapps civ.lua.
-- Run this to test and build the initial civ command.
local sfmt    = string.format
local io_open = io.open

local src = debug.getinfo(1).source
local D = src:match'@?(.*)bootstrap%.lua$'
print(sfmt('running bootstrap.lua in dir %q', D))
assert(not os.execute'ls lua*.core', 'lua.*core file found!')

assert(not MAIN, 'bootstrap.lua must not be used as a library')
MAIN = {}
NOLIB, BOOTSTRAP = true, true
LUA_SETUP = os.getenv'LUA_SETUP' or 'vt100'

local function preload(name, path)
  package.loaded[name] = dofile(D..path)
end

-- LOGLEVEL = tonumber(os.getenv'LOGLEVEL') or 4
-- LOGFN = function(lvl, msg) if LOGLEVEL >= lvl then
--   io.stderr:write(sfmt('LOG(%s): %s\n', lvl, msg))
-- end end

print'[[load]]'
  preload('metaty', 'lib/metaty/metaty.lua')
  require'metaty'.setup()
  preload('metaty.freeze', 'lib/metaty/freeze.lua')

  -- needed for civtest and related tests
  preload('shim', 'lib/shim/shim.lua')
  preload('fmt', 'lib/fmt/fmt.lua')
    preload('fmt.binary', 'lib/fmt/binary.lua')
  preload('ds', 'lib/ds/ds.lua')
    preload('ds.time', 'lib/ds/time.lua')
    preload('ds.heap', 'lib/ds/heap.lua')
    preload('ds.path', 'lib/ds/path.lua')
    preload('ds.log',  'lib/ds/log.lua')
    preload('ds.load', 'lib/ds/load.lua')
    preload('ds.Iter', 'lib/ds/Iter.lua')
    preload('ds.Grid', 'lib/ds/Grid.lua')
    -- TODO: move out of ds/test.lua
    preload('ds.utf8', 'lib/ds/utf8.lua')
    preload('ds.LL', 'lib/ds/LL.lua')
    preload('ds.IFile', 'lib/ds/IFile.lua')
    preload('ds.Stack', 'lib/ds/Stack.lua')
  preload('luk', 'lib/luk/luk.lua')
  preload('lap', 'lib/lap/lap.lua')
  preload('civix', 'lib/civix/civix.lua')
  preload('lines', 'lib/lines/lines.lua')
    preload('lines.diff', 'lib/lines/diff.lua')
    preload('lines.Gap', 'lib/lines/Gap.lua')
    preload('lines.Writer', 'lib/lines/Writer.lua')
    preload('lines.U3File', 'lib/lines/U3File.lua')
    preload('lines.futils', 'lib/lines/futils.lua')
    preload('lines.File',   'lib/lines/File.lua')
    preload('lines.EdFile', 'lib/lines/EdFile.lua')
  preload('pod', 'lib/pod/pod.lua')
  preload('lson', 'lib/lson/lson.lua')
  preload('civtest', 'lib/civtest/civtest.lua')
  preload('asciicolor', 'lib/asciicolor/asciicolor.lua')
  preload('vt100', 'lib/vt100/vt100.lua')
  preload('vt100.AcWriter', 'lib/vt100/AcWriter.lua')
  preload('civ.core', 'cmd/civ/core.lua')
  preload('civ.Worker', 'cmd/civ/Worker.lua')
  preload('civ', 'cmd/civ/civ.lua')

  -- Additional
  preload('lson', 'lib/lson/lson.lua')
  preload('ds.testing', 'lib/ds/testing/testing.lua')
  preload('pod.testing', 'lib/pod/testing/testing.lua')
  preload('lines.testing', 'lib/lines/testing/testing.lua')

require'vt100'.setup()
io.fmt:styled('notify', 'Running bootstrap.lua:', ' ');
io.fmt(G.arg); io.fmt:write'\n'

local core = require'civ.core'

local function bootTest()
  print'[[test]]'
  -- setup and run tests
  local log = require'ds.log'
  LOGFN = log.logFn; log.setLevel()

  local L = D..'lib/'
  for _, libtest in ipairs(dofile(L..'boot_tests.luk')) do
    dofile(L..libtest)
  end

  dofile(D..'cmd/civ/test_civ.lua')
  io.fmt:styled('notify', 'boot-test done', '\n')
  io.fmt:flush()
end

local function main()
  G.MAIN = nil; dofile(D..'cmd/civ/civ.lua')
end

if arg[1] == 'boot-test' then
  return bootTest()
end

main()
