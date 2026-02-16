local mty = require'metaty'
-- Session: the root object of Ele, holds the editor
-- object and events.
--
-- This are not directly available to actions/etc
local Session = mty'Session' {
  'ed [Editor]',
  'events [Recv]', 'evsend [Send]',
  'keys [Recv]', 'keysend [Send]',
  'logf [File]', 'running [bool]',
}

local ds = require'ds'
local log = require'ds.log'
local lap = require'lap'
local civix = require'civix'
local et = require'ele.types'
local Editor = require'ele.Editor'
local edit = require'ele.edit'
local bindings = require'ele.bindings'
local actions = require'ele.actions'

local info = mty.from'ds.log  info'
local yield = coroutine.yield

-- local FRAME = 0.05
local FRAME = 0.05

getmetatable(Session).__call = function(T, s)
  s.ed = s.ed or Editor{}
  s.ed:init()
  s.events = lap.Recv(); s.evsend  = s.events:sender()
  s.keys   = lap.Recv(); s.keysend = s.keys:sender()
  s.ed:focus(s.ed:buffer())
  return mty.construct(T, s)
end
-- init test session
Session.test = function(T, s)
  local s = T(s)
  s.ed.error = log.LogTable{tee=log.err}
  s.ed.warn  = log.warn
  return s
end
-- init (not run) real user session
Session.user = function(T, s)
  local s = T(s)
  s.ed.error = log.err
  s.ed.warn  = log.warn
  local e = s.ed.edit
  e:insert(et.WELCOME)
  e.l, e.c = 1, 1
  return s
end

-- run events until they are exhuasted
Session.run = function(s)
  s.running = true
  local actions = s.ed.actions
  while #s.events > 0 do
    local ev = s.events()
    if type(ev) ~= 'table' or not ds.isPod(ev) then
      s.ed.error('event is not POD table: %q', ev)
      goto cont
    end
    log.info('run event %q', ev)
    if not ev then goto cont end
    s.ed.redraw = true
    local act = ev.action;
    if not act then
      s.ed:handleStandard(ev)
      goto cont
    end
    if act == 'exit' then
      s.ed.error'exit action received'
      s.ed.run = false
      s.running = false
      yield'STOP'
    end
    local actFn = actions[act]; if not actFn then
      s.ed.error('unknown action: %q', act)
      goto cont
    end
    local ok, err = ds.try(actFn, s.ed, ev, s.evsend)
    if not ok then
      s.ed.error('failed event %q. %q', ev, err)
    end
    ::cont::
  end
  s.running = false
end

-- send chord of keys and play them (run events)
-- this is only used in tests
Session.play = function(s, chord)
  log.info('play %q', chord)
  s.keysend:extend(bindings.chord(chord))
  while (#s.keys > 0) or (#s.events > 0) or s.running do
    yield(true)
  end
  log.info('draw %q', chord)
  s.ed.display:clear(); -- normally part of resize()
  s.ed.redraw = true; s.ed:draw()
end

-- Start a user session
Session.handleEvents = function(s)
  assert(LAP_ASYNC, 'must be started in async mode')
  assert(s.ed and s.keys)
  lap.schedule(function()
    LAP_TRACE[coroutine.running()] = true
    bindings.keyactions(s.ed, s.keys, s.evsend)
  end)
  lap.schedule(function()
    LAP_TRACE[coroutine.running()] = true
    while s.ed.run do
      s.events:wait()
      s:run()
    end
    log.info'exiting sesssion run + draw'
  end)
  return s
end

-- draw coroutine
Session.draw = function(s)
   while s.ed.run do
     if s.ed.redraw then
       s.ed.redraw = false
       s.ed.display:resize()
       s.ed:draw()
       s.ed.display:draw()
     end
     yield('sleep', FRAME)
   end
end

-- highlight coroutine
function Session:highlight()
  local Gap = require'lines.Gap'
  local hl = mty.from'pegl.lua  highlighter'
  hl.styleColor = require'asciicolor'.dark
  while self.ed.run do
    yield('sleep', 1)
    local buf = self.ed.edit.buf
    local path = buf.dat.path
    if path and path:find'%.lu[ak]$' then
      local lf = buf.dat:reader()
      local fg,bg = Gap{}, Gap{}
      hl:highlight(lf, fg,bg)
      if #buf == #fg then
        buf.fg, buf.bg = fg, bg
      end
    end
  end
end

return Session
