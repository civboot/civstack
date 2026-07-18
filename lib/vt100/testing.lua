--- helpers for testing/demoing vt100
local M = mod and mod'vt100.testing' or {}

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local log = require'ds.log'
local vt = require'vt100'
local co = coroutine

local byte = string.byte

M.Fake = mty.extend(vt.Term, 'Fake')

function M.Fake:resize(l, c)
  assert(l and c, 'must pass l,c for Fake')
  self.l, self.c = l, c
  self:clear()
end

M.Fake.draw  = ds.nosupport
M.Fake.input = ds.nosupport

--- start rawmode using tmpfiles
function M.startTmp() --> out, err
  local err = io.tmpfile()
  vt.start(err)
  return err
end

--- TODO: I tried ot migrate this to the new rawSend
--- but it's not actually hooked up to run.
--- Debug it if I need the demo.lua again, else consider
--- deleting.
---
--- Run function in a LAP environment with terminal started
--- and std in/out set correctly.
function M.run(fn)
  local lap = require'lap'
  local cx = require'civix'
  local fd = require'fd'
  local ioin, ioread = io.stdin, io.read

  local t = vt.Term{h=10, w=80}
  local stderr = M.startTmp()
  local r = lap.Recv{}
  local rawRecv = lap.Recv{}
  local rawSend = rawRecv:sender()
  local byTh = co.create(function() while true do
    rawSend(byte(io.read(1)))
  end end)
  local szTh = co.create(function() t:resize() end)
  local inTh = co.create(function() t:input(r, rawRecv) end)

  local ok, err = ds.try(function()
    -- make stdin async
    io.stdin, io.read = fd.stdin, fd.read
    fd.stdin:toNonblock()

    -- send size request and wait until it is recieved
    T.eq({true, 'forget'}, {ds.resume(szTh)})
    T.eq(szTh, t._waiting)

    while t._waiting do
      T.eq({true, 'poll', 0, fd.sys.POLLIN}, {ds.resume(inTh)})
    end
    T.eq(nil, t._waiting)
    T.eq(nil, r())
    T.eq({true}, {ds.resume(szTh)})
    T.eq('dead', coroutine.status(szTh))

    log.info('term size: %s %s', t.h, t.w)
    fn(t)
  end)
  -- undo async stdin
  io.stdin, io.read = ioin, ioread
  fd.stdin:toBlock()
  vt.stop();

  io.flush()
  io.stderr:write('\nvt100.testing.run '..
    (ok and 'DONE' or ('ERROR:\n'..tostring(err)))
    ..'\n')
  stderr:flush(); stderr:seek'set'
  local err = stderr:read'a'
  if #err > 0 then log.info('STDERR:\n%s', err) end
  stderr:close()
  assert(ok, 'got error, see stderr')
end

return M