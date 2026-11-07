local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local Iter = require'ds.Iter'
local M  = require'lap'

local info = mty.from'ds.log  info'
local push, yield = table.insert, coroutine.yield
local co = coroutine

T.eq(ctx.__parent, CTX_BASE)

T'direct execute'; do
  local ctxBase = ctx.__parent
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
  ctx.__parent = ctxBase
end

T.eq(ctx.__parent, CTX_BASE)
local finished = 0
local slept, mono = 0, 0
local l = M.Lap {
  sleepFn=function() slept = slept + 1 end,
  monoFn=function() mono = mono + 1; return mono end,
  pollList=ds.nosupport,
}

local DONE
local _, errors = l:run{function()
assert(ctx.ASYNC)
T'schedule'; do
  local i = 0
  local cor = ctx.schedule(function()
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
  ctx.schedule(function()
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

-- This test exercises the sender/receiver pair with garbage collection happening.
T'gc'; do
  local w, r, s = ds.WeakV{}, {}, {}
  local recv = M.Recv(); 
  M.scheduleTraced('sender', function()
    local send = recv:sender()
    s.send, w.send = true, coroutine.running()
    for i=1,10 do send(i); collectgarbage(); yield(true) end
  end)
  while not s.send do info'waiting for send'; yield(true) end
  M.scheduleTraced('receiver', function()
    local lRecv = recv
    s.recv, w.recv = true, coroutine.running()
    for i in lRecv do push(r, i) end
  end)
  while not s.recv do info'waiting for recv'; yield(true) end
  recv = nil -- allow GC
  T.eq('thread', type(w.recv))
  M.scheduleTraced('gc', function()
    for i=1,10 do collectgarbage(); yield(true) end
  end)
  while #r < 10 do
    info'waiting for all recv'
    T.eq({true, true}, {w.send and true, w.recv and true})
    yield(true)
  end
  T.eq(Iter:ofRange(1,10):keysTo(), r)
  for i=1,5 do yield(true); collectgarbage() end
  T.eq({0, 0}, {w.send and 1 or 0, w.recv and 1 or 0}) 
end

DONE = true
end} -- end l:run

assert(DONE, 'lap tests did not actually run')

if errors then error('lap found errors:\n'..fmt(errors)) end
assert(l:isDone())
T.eq(2, finished)
M.reset()

-- note: update if fail, these just prove determinism
-- local n = 35; T.eq({slept=n, mono=n}, {slept=slept, mono=mono})