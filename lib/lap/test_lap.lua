local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local M  = require'lap'

local push, yield = table.insert, coroutine.yield
local co = coroutine

T'execute'; do
  local l = M.Lap{}
  local v = 0
  local res = l:execute(co.create(
    function() v = 3; yield'forget' end
  ))
  T.eq(3, v)
  T.eq(nil, res)
  local res = l:execute(co.create(
    function() yield'foo' end
  ))
  T.eq('unknown kind: foo', res)

  local errFn = function() error'bar' end
  local res = l:execute(co.create(errFn))
  T.matches(': bar', res)
end

local finished = 0
local slept, mono = 0, 0
local l = M.Lap {
  sleepFn=function() slept = slept + 1 end,
  monoFn=function() mono = mono + 1; return mono end,
  pollList=ds.nosupport,
}

local DONE
local _, errors = l:run{function()
T'schedule'; do
  local i = 0
  local cor = M.schedule(function()
    for _=1,3 do i = i + 1; yield(true) end
    i = 99
  end)
  T.eq('scheduled', LAP_READY[cor])
  for ei=0, 3 do
    assert(LAP_READY[cor])
    T.eq(ei, i); yield(true)
  end
  T.eq(nil, LAP_READY[cor])
  T.eq(99, i)
  finished = finished + 1
end

T'ch'; do
  local r = M.Recv(); local s = r:sender()

  local t = {}
  M.schedule(function()
    for v in r do push(t, v) end
  end)
  T.eq({}, t);
  yield(true); T.eq({}, t)
  s(10);       T.eq({}, t)
  yield(true); T.eq({10}, t)

  s(11); s(12); T.eq({10}, t)
  yield(true);  T.eq({10, 11, 12}, t)
  T.eq({}, r:drain())

  ds.clear(t)
  s(13); T.eq({13}, r:drain())
  yield(true); T.eq({}, t)
  finished = finished + 1
end

T'any'; do
  local v
  local function fn4() for i=1,3 do yield(true) end; v=4 end
  local function fn8() for i=1,7 do yield(true) end; v=8 end
  local any = M.Any{fn8, fn4}
  T.eq(2, any:yield())
    T.eq({[2]=true}, any.done)
    T.eq(4, v)
  any.done[2] = nil
  T.eq(1, any:yield())
    T.eq({true},  any.done)
    T.eq(8, v)
end
DONE = true
end} -- end l:run

assert(DONE, 'lap tests did not actually run')

if errors then error('lap found errors:\n'..fmt(errors)) end
assert(l:isDone())
T.eq(2, finished)
M.reset()

-- note: update if fail, these just prove determinism
T.eq({slept=18, mono=18}, {slept=slept, mono=mono})