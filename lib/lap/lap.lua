local G = G or _G

--- Lua module importing the LAP protocol so that libraries can
--- support both blocking and non-blocking IO.
local M = G.mod and G.mod'lap' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local heap = require'ds.heap'

local sfmt = string.format
local push, concat = table.insert, table.concat
local yield, create  = coroutine.yield, coroutine.create
local resume, status = coroutine.resume, coroutine.status
local running        = coroutine.running
local log = require'ds.log'
local Error = ds.Error
local TRACE = log.LEVEL.TRACE
local update = table.update

M._async = {}; M._sync = {}

-- lap protocol globals
G.LAP_READY     = G.LAP_READY or {}
G.LAP_FNS_SYNC  = G.LAP_FNS_SYNC  or {}
G.LAP_FNS_ASYNC = G.LAP_FNS_ASYNC or {}
G.LAP_TRACE     = G.LAP_TRACE or {}
G.LAP_CORS      = G.LAP_CORS or ds.WeakKV{}
G.LAP_ASYNC     = G.LAP_ASYNC or false

--- Clear all lap globals.
function M.reset()
  assert(not LAP_ASYNC, "don't clear while still running")
  G.LAP_READY, G.LAP_TRACE = {}, {}
  G.LAP_CORS = ds.WeakKV{}
end

function M.formatCorErrors(corErrors)
  local f = fmt.Fmt{}
  for i, ce in ipairs(corErrors) do
    f:write(sfmt('Coroutine Error #%s:\n', i))
    f(ce); f:write'\n'
  end
  return table.concat(f)
end

--- Switch lua to synchronous (blocking) mode.
function M.sync()
  if not LAP_ASYNC then return end
  for _, fn in ipairs(LAP_FNS_SYNC)  do fn() end
  assert(not LAP_ASYNC)
end

--- Switch lua to asynchronous (yielding) mode.
function M.async()
  if LAP_ASYNC then return end
  for _, fn in ipairs(LAP_FNS_ASYNC) do fn() end
  assert(LAP_ASYNC)
end

--- yield(fn) [+
--- * sync: noop
--- * async: coroutine.yield
--- ]
function M.yield() end
M._sync.yield = M.yield
M._async.yield = yield

--- [$schedule(fn) -> coroutine?] [+
--- * sync:  run the fn immediately and return nil
--- * async: create and schedule returned coroutine
--- ]
function M.schedule(fn, ...) fn(...) end
M._sync.schedule = M.schedule
function M._async.schedule(fn, ...)
  assert(select('#', ...) == 0, 'only function supported')
  local cor = create(fn)
  LAP_READY[cor] = 'scheduled'
  LAP_CORS[cor] = fn
  log.trace('schedule %s [%q]', cor, fn)
  return cor
end

----------------------------------
-- Ch: channel sender and receiver (Send/Recv)

--- Create the receive side of a channel.[+
--- * Use [$recv:sender()] to create a sender. You can create
---   multiple senders.
--- * Use [$recv:recv()] or simply [$recv()] to receive a value
---   (or block)
--- * User [$sender:send(v)] or simply [$sender(v)] to send a value.
--- * [$recv:close()] when done. Also closes all senders.
--- * [$#recv] gets number of items buffered.
--- * [$recv:isDone()] returns true when either recv is closed
---   OR all senders are closed and [$#recv == 0]
--- ]
M.Recv = mty'Recv'{
  'deq    [Deq]',
  '_sends [WeakKV]',
  'cor    [thread]',
}
getmetatable(M.Recv).__call = function(T)
  return mty.construct(T, {deq=ds.Deq(), _sends=ds.WeakKV{}})
end

--- Close read side and all associated senders.
function M.Recv:close()
  local sends = self._sends; if not sends then return end
  for s in pairs(update({}, sends)) do s:close() end
  self._sends = nil
end

--- Clear the receiver.
function M.Recv:clear() self.deq:clear() end

M.Recv.__close  = M.Recv.close
function M.Recv:__len() return #self.deq          end
function M.Recv:isClosed() --> bool
  return self._sends == nil
end
--- Return false if there is no data and all senders
--- are closed.
function M.Recv:isDone() --> bool
  return (#self.deq == 0)
     and (not self._sends or ds.isEmpty(self._sends))
end
--- Create a new [<#lap.Sender>].
function M.Recv:sender() --> Sender
  local s = M.Send(self)
  assert(self._sends, 'sender on closed channel')[s] = true
  return s
end
--- Return if there is at least one sender still alive.
function M.Recv:hasSender() --> bool
  return self._sends and next(self._sends) and true or false
end
--- Yield [$forget] which will cause executor to forget this coroutine.
--- A sender will re-schedule this coroutine when sending data.
function M.Recv:wait()
  while (#self.deq == 0) and (self._sends and not ds.isEmpty(self._sends)) do
    self.cor = coroutine.running(); yield'forget'
  end
end
--- Wait for and get a value (alternatively call [$recv()] directly).
function M.Recv:recv() --> value
  self:wait() return self.deq()
end
M.Recv.__call = M.Recv.recv
--- drain the recv of all current values it has.
--- This does NOT wait for new items.
function M.Recv:drain() --> list
  return self.deq:drain()
end
function M.Recv:__fmt(f)
  f:write(sfmt('Recv{%s len=%s hasSender=%s}',
    self:isClosed() and 'closed' or 'active',
    #self.deq, self:hasSender() and 'yes' or 'no'))
end

local function recvReady(r)
  if r.cor then LAP_READY[r.cor] = 'ch.push' end
end
--- Sender, created through [$recv:sender()][{br}]
--- This is considered closed if the receiver is closed. The receiver will
--- automatically close if it is garbage collected.
M.Send = mty'Send'{'_recv[Recv]'}
getmetatable(M.Send).__call = function(T, recv)
  return mty.construct(T, { _recv=assert(recv, 'missing Recv') })
end
M.Send.__mode = 'kv'
--- Close this sender. Will also awaken the receiver coroutine.
M.Send.close = function(send)
  local r = send._recv; if r then
    local sends = assert(r._sends)
    sends[send] = nil; send._recv = nil
    if r.cor and ds.isEmpty(sends) then
      LAP_READY[r.cor] = 'ch.close'
    end
  end
end
M.Send.__close = M.Send.close
M.Send.isClosed = function(s) return s._recv == nil end
--- Push a value of data to the Recv.
M.Send.push = function(send, val)
  local r = assert(send._recv, 'recv closed')
  r.deq:push(val); recvReady(r)
end
--- Push a list of data to the Recv.
M.Send.extend = function(send, vals)
  local r = assert(send._recv, 'recv closed')
  r.deq:extendRight(vals); recvReady(r)
end
-- Preemtive send, pushing value on left.
M.Send.pushLeft = function(send, val)
  local r = assert(send._recv, 'recv closed')
  r.deq:pushLeft(val); recvReady(r)
end
-- Preemptive extend, pushing vals on left (order preserved).
M.Send.extendLeft = function(send, vals)
  local r = assert(send._recv, 'recv closed')
  r.deq:extendLeft(vals); recvReady(r)
end
M.Send.__call = M.Send.push
M.Send.__len = function(send)
  local r = send._recv; return r and #r or 0
end
M.Send.__fmt = function(send, f)
  f:write('Send{active=%s}', send:isClosed() and 'no' or 'yes')
end

----------------------------------
-- all / Any

--- Resume when all of the functions complete.
function M.all(fns)
  for _, f in ipairs(fns) do f() end
end
M._sync.all = M.all
function M._async.all(fns)
  local rcor, count, len = coroutine.running(), 0, #fns
  for _, fn in ipairs(fns) do
    assert(type(fn) == 'function')
    local cor = coroutine.create(function()
      fn(); count = count + 1
      if count == len then LAP_READY[rcor] = 'all-done' end
    end)
    LAP_READY[cor] = 'all-item'
  end
  yield'forget' -- forget until resumed by last completed child
end

--- [$Any(fns)]: handle resuming and restarting multiple fns.
---
--- Call [$any:ignore()] to stop the child threads from resuming
--- the current thread. This does NOT stop the child threads.
---
--- Example which handles multiple fns running simultaniously: [{$$ lang=lua}
--- local any = lap.Any{fn1, fn2}:schedule()
--- while true do
---   local i = any:yield()
---   -- do something related to index i
---   any:restart(i) -- restart i to run again
--- end
--- ]$
--- TODO: test this
M.Any = mty'Any'{
  'cor  [thread]: the coroutine this is running on.',
  'fns  {function}: the functions to schedule.',
  'done {int}: which indexes are complete.',
}
getmetatable(M.Any).__call = function(T, fns)
  local self = {
    cor = coroutine.running(),
    fns = {},
    done = {},
  }
  for i, fn in ipairs(fns) do
    assert(type(fn) == 'function')
    push(self.fns, function()
      fn(); self.done[i] = true
      if self.cor then
        LAP_READY[self.cor] = 'any-done'
      end
    end)
  end
  return mty.construct(T, self)
end

--- Stop running caring about functions.
function M.Any:ignore() self.cor = nil end

--- Ensure all fns are scheduled
function M.Any:schedule() --> self
  for i in pairs(self.fns) do
    if self.done[i] == nil then
      LAP_READY[coroutine.create(self.fns[i])] = 'any-item'
      self.done[i] = false
    end
  end
end

--- yield until any fn is done
function M.Any:yield() --> fnIndex
  while not next(self.done) do yield'forget' end
  return next(self.done)
end

--- Yield a sleep signal for the number of  seconds (float).
function M.sleep(s) return yield('sleep', s) end

----------------------------------
-- Lap
local function lt1(a, b) return a[1] < b[1] end
local LAP_UPDATE = {
  [true] = function(lap, cor) LAP_READY[cor] = true end,
  forget = ds.noop,
  sleep = function(lap, cor, sleepSec)
    if type(sleepSec) ~= 'number' then
      return sfmt('non-number sleep: %s', sleepSec)
    end
    lap.monoHeap:add{lap:monoFn() + sleepSec, cor}
  end,
  poll = function(lap, cor, fileno, events)
    local cur = lap.pollMap[fileno]
    if cor == cur then
      -- TODO: figure out why this happens sometimes.
      log.warn('coroutine %q (%q) polled twice',
               LAP_CORS[cor] or 'unnamed', cor)
    elseif cur then
      return fmt.format(
        'two coroutines are both attempting to listen to fileno=%s\n'
        ..'Previous %q (%q) traceback:\n  %s\nRunning %q (%q) traceback:\n  %s',
        fileno,
        LAP_CORS[cur] or 'unnamed', cur,
        table.concat(ds.tracelist(debug.traceback(cur)), '\n  '),
        LAP_CORS[cor] or 'unnamed', cor,
        table.concat(ds.tracelist(debug.traceback(cor)), '\n  '))
    end
    lap.pollList:insert(fileno, events)
    lap.pollMap[fileno] = cor
  end,
  -- Stop ALL coroutines.
  STOP = function(l) ds.clear(G.LAP_READY); l:stop() end
}; M.LAP_UPDATE = LAP_UPDATE

--- Default implementation of an executor, see [@civix.Lap] for
--- a more complete one.
---
--- "A single lap of the executor loop"
---
--- Example [{$$ lang=lua}
---   -- schedule your main fn, which may schedule other fns
---   lap.schedule(myMainFn)
---
---   -- create a Lap instance with the necessary configs
---   local Lap = lap.Lap{
---     sleepFn=civix.sleep, monoFn=civix.monoSecs, pollList=fd.PollList()
---   }
---
---   -- run repeatedly while there are coroutines to run
---   while next(LAP_READY) do
---     errors = Lap(); if errors then
---       -- handle errors
---     end
---     -- do other things in your application's executor loop
---   end
--- ]$
M.Lap = mty'Lap' {
  'sleepFn [function]',
  'monoFn  [function]',
  'monoHeap [Heap]',
  'defaultSleep [float]',
  'pollMap [table[fileno,coroutine]]',

[[pollList [PollList] Poll list data structure. Required methods:
* __len                   to get length with `#`
* insert(fileno, events)  insert the fileno+events into the poll list
* remove(fileno)          remove the fileno from poll list
* ready(self, durationSec) -> {filenos}
    poll for durationSec (float), return any ready filenos.
]],
}
M.Lap.defaultSleep = 0.01
getmetatable(M.Lap).__call = function(T, ex)
  ex.monoHeap = ex.monoHeap or heap.Heap{cmp = lt1}
  ex.pollMap  = ex.pollMap  or {}
  return mty.construct(T, ex)
end

--- Stop the executor, ending all coroutines.
function M.Lap:stop() self.pollMap, self.pollList = {}, {} end

--- Main entry point, schedules a list of functions in
--- the executor and returns when they are done.
function M.Lap:run(fns, setup, teardown)
  setup, teardown = setup or M.async, teardown or M.sync
  local errors
  assert(self:isDone(), "cannot run non-done Lap")
  assert(not LAP_ASYNC, 'already in async mode')
  if type(fns) == 'function' then
    LAP_READY[coroutine.create(fns)] = 'run'
  else
    for i, fn in ipairs(fns) do
      LAP_READY[coroutine.create(fn)] = 'run'
    end
  end
  setup()
  local ok, ierr = ds.try(function()
    while not self:isDone() do
      errors = self(); if errors then break end
    end
  end)
  if not ok then
    errors = errors or {}
    push(errors, ierr)
  end
  teardown()
  if errors then
    errors = M.formatCorErrors(errors)
    log.info('coroutine errors: %s', errors)
    error(errors)
  else log.info('Lap:run done. ready=%q, pm=%q', LAP_READY, self.pollMap) end
  return self, errors
end
--- (overrideable) function to use in order to sleep.
M.Lap.sleep = M.LAP_UPDATE.sleep

--- (overrideable) function to use in order to poll
--- file-descriptor completion status.
M.Lap.poll  = M.LAP_UPDATE.poll

--- Executes a single coroutine, used inside [$:run()]
function M.Lap:execute(cor, note) --> errstr?
  if LOGLEVEL >= TRACE and LAP_TRACE[cor] then
    log.trace("execute %s %s %q [%q]", cor, status(cor), note, LAP_CORS[cor])
  end
  local ok, kind, a, b = resume(cor)
  if not ok then return kind end -- kind=error
  local fn = LAP_UPDATE[kind]
  if fn then return fn(self, cor, a, b)
  elseif kind then return 'unknown kind: '..kind end
  return (status(cor) ~= 'dead')
     and 'non-dead coroutine yielded false/nil' or nil
end

--- run a single lap of the executor.
function M.Lap:__call()
  local errors = nil
  if next(LAP_READY) then
    local ready = LAP_READY; LAP_READY = {}
    for cor, note in pairs(ready) do
      local err = self:execute(cor, note)
      if err then
        errors = errors or {}
        push(errors, Error:from(err, cor))
      end
    end
  end
  if errors then return errors end

  -- Check for asleep coroutines
  local mh = self.monoHeap; local hpop = mh.pop
  local now, till = self:monoFn()
  if next(LAP_READY) then till = now -- no sleep when there are ready
  else                    till = now + self.defaultSleep end
  while true do -- handle mono (sleep)
    -- keep popping from the minheap until it is before 'now'
    local e = hpop(mh); if not e then break end
    if e[1] > now then
      mh:add(e); till = math.min(till, e[1])
      break
    end
    LAP_READY[e[2]] = 'sleep'
  end

  -- Poll or sleep before next loop
  local sleep = math.max(0, till - now)
  if next(self.pollMap) then
    local pl, pm = self.pollList, self.pollMap
    for _, fileno in ipairs(pl:ready(sleep)) do
      local cor = ds.popk(pm, fileno); pl:remove(fileno)
      if LOGLEVEL >= TRACE and LAP_TRACE[cor] then
        log.trace('scheduling fileno=%s %q', fileno, LAP_CORS[cor])
      end
      LAP_READY[cor] = 'poll'
    end
  else self.sleepFn(sleep) end
end
function M.Lap:isDone()
  return not (next(LAP_READY) or (#self.monoHeap > 0) or next(self.pollMap))
end

----------------------
-- Global Modifiers

local function toAsync()
  for k, v in pairs(M._async) do M[k] = v end
  LAP_ASYNC = true
end; push(LAP_FNS_ASYNC, toAsync)

local function toSync()
  for k, v in pairs(M._sync)  do M[k] = v end
  LAP_ASYNC = false
end; push(LAP_FNS_SYNC,  toSync)

if LAP_ASYNC then toAsync() else toSync() end

return M