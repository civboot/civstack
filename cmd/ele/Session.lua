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
local push = table.insert

-- local FRAME = 0.05
local FRAME = 0.05

Session.BUILTIN_ACTIONS = {
  clearEvents = function(s) s.events:clear() end,

  exit = function(s)
    s.ed.error'exit action received'
    s.ed.run = false
    s.running = false
    yield'STOP'
  end,
}

getmetatable(Session).__call = function(T, s)
  local ed = s.ed or Editor{}; s.ed = ed
  ed:init()
  s.events = lap.Recv(); s.evsend  = s.events:sender()
  s.keys   = lap.Recv(); s.keysend = s.keys:sender()
  ed:focus(ed:buffer())
  -- Add the again listener
  ed.listeners.again = function(ev)
    if not ds.getTag(ev, 'user') then return end
    local ext = ed.ext
    if ev.mode == 'insert' or ds.getTag(ev, 'againStart') then
      ext.nextAgain = {action='chain', ds.deepcopy(ev), tag='again'}
      return
    end
    local n = ext.nextAgain
    -- only push if mut or mid-chain
    if not (n or ds.getTag(ev, 'mut')) then return end
    ev = ds.deepcopy(ev)
    if n then
      push(n, ev)
      if (ev.mode and ev.mode ~= 'insert') or ds.getTag(ev, 'againEnd') then
        -- Use chain as again if any are mut.
        -- TODO: should proabaly recurse action=chain
        for _, ne in ipairs(n) do
          if ds.getTag(ne, 'mut') then ext.again = n end
        end
        ext.nextAgain = nil
      end
    else ext.again = ds.tag(ev, 'again') end
  end
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
  local e = s.ed.pane
  e:insert(et.WELCOME)
  e.l, e.c = 1, 1
  return s
end

-- run events until they are exhuasted
function Session:run()
  local ev, actions, act, actFn, ok, err
  self.running = true
  local ed = self.ed
  while #self.events > 0 do
    ev = self.events()
    actions = ed.pane.actions or ed.actions
    if type(ev) ~= 'table' or not ds.isPod(ev) then
      self.ed.error('event is not POD table: %q', ev)
      goto cont
    end
    log.info('run event %q', ev)
    if not ev then goto cont end
    self.ed.redraw = true
    act = ev.action; if not act then
      self.ed:handleStandard(ev)
      goto success
    end
    actFn = self.BUILTIN_ACTIONS[act]; if actFn then
      actFn(self)
      goto success
    end
    actFn = actions[act]; if not actFn then
      self.ed.error('unknown action: %q', act)
      goto cont
    end
    ok, err = ds.try(actFn, self.ed, ev, self.evsend)
    if not ok then
      self.ed.error('failed event %q. %q', ev, err)
      goto cont
    end
    ::success::
    for _, fn in pairs(ed.listeners) do fn(ev) end
    ::cont::
  end
  self.running = false
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
     lap.sleep(FRAME)
   end
end

-- highlight coroutine
function Session:highlight()
  local Gap = require'lines.Gap'
  local hl = mty.from'pegl.lua  highlighter'
  local hlAcs = mty.from'asciigame.acs  highlight'
  hl.styleColor = require'asciicolor'.dark
  local function highlight()
    local p = self.ed.pane
    if mty.ty(p) ~= edit.Edit then return end
    local buf = self.ed.pane.buf
    local path = buf.dat.path
    if path and path:find'%.lu[ak]$' then
      local fg,bg = Gap{}, Gap{}
      hl:highlight(buf.dat:reader(), fg,bg)
      if #buf == #fg then
        buf.fg, buf.bg = fg, bg
      end
    elseif path and path:find'%.acs$' then
      local fg,bg = Gap{}, Gap{}
      hlAcs(path, buf.dat:reader(), fg,bg)
      buf.fg, buf.bg = fg, bg
    end
  end
  while self.ed.run do
    lap.sleep(1)
    local ok, err = ds.try(highlight)
    if not ok then log.warn('highlight error:\n%q', err) end
  end
end

return Session