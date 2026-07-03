local mty    = require'metaty'

--- Core ele types.
local M = mty.mod'ele.types'

local G      = mty.G
local ds     = require'ds'
local fmt    = require'fmt'
local log    = require'ds.log'
local pod    = require'pod'
M._term      = require'vt100'
local assertf = fmt.assertf
local sfmt = string.format
local toint = math.tointeger
local push, pop, concat = table.insert, table.remove, table.concat
local getp = ds.getp
local getmt = G.getmetatable

M.ID = 1
function M.uniqueId()
  local id = M.ID; M.ID = M.ID+1; return id
end

M.INIT_BUFS = 3 -- the default number of bufs on init (for testing)

M.WELCOME = [[
Welcome to the Ele Editor!

Press ^q (ctrl-q) twice at any time to exit.

This page will have more help message in the future.
]]

--- Cached buffer state
M.BufState = pod(mty'BufState' {
  'id [int]  #1: buffer id',
  'name [str]#2: buffer name',
  'path [str]#3: buffer path',
})

--- Cached window/pane state.
M.PaneState = mty'PaneState' {
  'ty [string]: the type to ds.wantpath, i.e. "ele.edit.Edit"',
  'dat [table]: the data to pass to the ty',
  'chld {ele.types.PaneState}: children',
}; pod(M.PaneState)

function M.PaneState:load(ed)
  local T = assertf(ds.wantpath(self.ty), 'unknown type: %q', self.ty)
  return T:fromState(ed, self)
end

--- Editor state for caching/reloading the current
--- editor state.
M.State = pod(mty'State' {
  'ID [int]#1: current uniqueId() state.',
  'buffers {ele.types.BufState}#2',
  'view [ele.types.PaneState]#3',
  'pane [int]#4: the currently focused pane',
})


function M.getEditor(c)
  local Editor = require'ele.Editor'
  while c and mty.ty(c) ~= Editor do
    c = c.container
  end
  return c
end

--- The base record for Edit/Game.
---
--- These should be implemented: [{$$ lang=lua}
--- function M.BasePane:state() --> PaneState
--- function M.BasePane.fromState(T, ed, s) --> new self
--- ]$
M.BasePane = mty'BasePane' {
  'id[int]',
  'container', -- parent (Editor/Split)
  'actions {string: fn}: override of actions, especially keyinput',
  'hide [bool]: whether to hide cursor', hide = true,
  'l [int]: cursor line', 'c [int]: cursor col', l=1, c=1,

  'tl[int]', tl=-1,   'tc[int]', tc=-1, -- term   line, col (top-left)
  'th[int]', th=-1,   'tw[int]', tw=-1, -- term   height, width
  'closed [bool]', closed = false,

  'modes [table]: override specific keybindings for this pane',

  IS_PANE = true,
}

function M.BasePane.__init(t)
  t.id = t.id or M.uniqueId()
end

getmetatable(M.BasePane).__call = function(T, t)
  T:__init(t)
  return mty.construct(T, t)
end

--- Called after this pane is focused by Editor.
function M.BasePane:focus(ed) end

--- Called when this pane is closed by Editor.
function M.BasePane:close(ed)
  assert(not self.container, 'close() before container removed')
  assert(ed, 'must provide Editor')
  self.closed = true
end

function M.BasePane:drawCursor(ed) end


function M.isPane(v)
  if type(v) ~= 'table' then return false end
  return rawget(getmt(v), 'IS_PANE')
end


--- A container with windows split vertically (i.e. tall windows)
M.VSplit = mty'VSplit' {
  'container [Editor|VSplit|HSplit]: parent container',
  -- Set by parent before draw
  'tl[int]', tl=-1, 'tc[int]', tc=-1, -- term line,col (top-left/right)
  'th[int]', th=-1, 'tw[int]', tw=-1, -- term   height, width
}
M.VSplit.getEditor = M.getEditor
M.VSplit.close = ds.noop
function M.VSplit:insert(i, v)
  assert(not v.container)
  table.insert(self, i, v); v.container = self
end

function M.VSplit:replace(from, to) --> from
  -- TODO: This should recursively walk the containers.
  local i = assert(ds.indexOf(self, from), 'from not found in Split')
  assert(from.container == self)
  assert(not to.container)
  self[i], to.container, from.container = to, self, nil
  return from
end
function M.VSplit:remove(v) --> v
  local i = assertf(ds.indexOf(self, v), '%q not found in Split', v)
  table.remove(self, i); v.container = nil
  if #self == 0 then -- no items, this shouldn't happen
    log.warning('zero items left in %s', mty.name(self))
    self.container:remove(self)
  elseif #self == 1 then -- only 1 item left, close self
    self[1].container = nil
    self.container:replace(self, self[1]):close(self:getEditor())
    self[1] = nil
  end
  return v
end
function M.VSplit:draw(ed, isRight)
  local d = ed.display
  local len = #self; if len == 0 then return end
  local l,c = self.tl, self.tc
  local w,h = self.tw // len, self.th -- divide up the available width
  -- First view gets any extra width, the rest are even
  local v = self[1]; v.tl,v.tc, v.tw,v.th = l,c, w + (self.tw % len), h
  v:draw(ed, isRight)
  for i=2,len do
    c = c + v.tw -- increment the col# by previous width
    v = self[i];     v.tl,v.tc, v.tw,v.th = l,c, w,h
    v:draw(ed, false) -- note: not right-most.
  end
end
function M.VSplit:state()
  local chld = {}; for _, p in ipairs(self) do push(chld, p:state()) end
  return M.PaneState { ty=mty.fullname(self), chld=chld }
end
function M.VSplit.fromState(T, ed, s)
  local self = T{}; for i, paneState in ipairs(s.chld) do
    self:insert(i, paneState:load(ed))
  end
  return self
end

--- A container with windows split horizontally (i.e. wide windows)
M.HSplit = mty.extend(M.VSplit, 'HSplit')
function M.HSplit:draw(ed, isRight)
  local d = ed.display
  local len = #self; if len == 0 then return end
  local l,c = self.tl, self.tc
  local w,h = self.tw, self.th // len -- divide up the available height
  -- First view gets any extra height, the rest are even
  local v = self[1]; v.tl,v.tc, v.tw,v.th = l,c, w, h + (self.th % len)
  for i=2,len do
    l = l + v.th -- increment the line# by previous height
    v = self[i];     v.tl,v.tc, v.tw,v.th = l,c, w,h
  end
  for _, v in ipairs(self) do v:draw(ed, isRight) end
end

function M.checkBinding(b)
  if not mty.callable(b) then
    return 'binding must be callable'
  end
end

function M.checkBindings(btable, path)
  path = path or {}; push(path, '<root>')
  if type(btable) ~= 'table' then error(sfmt(
    '%s: bindings must be only tables and callables', concat(path)
  ))end

  local keyError, err = M._term.keyError
  for k, b in pairs(btable) do
    path[#path] = k
    if k == 'fallback' then
      if not mty.callable(b) then error(sfmt(
        '%s: fallback must be callable', concat(path)
      ))end
      goto continue
    end
    err = (type(k) ~= 'string') and 'keys must be str' or keyError(k)
    if err then return sfmt('%s: %s', concat(path, ' '), err) end
    if not mty.callable(b) then
      M.checkBindings(b, path)
    end
    ::continue::
  end
  pop(path)
end

function M.checkMode(data, mode) --> errstring
  if not data.modes[mode] then
    return sfmt('modes.%s does not exist', mode)
  end
end

function M.checkAction(data, action) --> errstring
  if not mty.callable(getp(data, {'actions', action})) then
    return sfmt('actions.%s is not a callable', action)
  end
end

--- The location the cursor was at, to be in a stack.
M.EditLoc = mty'EditLoc' { 'b [str]: buf name', 'l', 'c'}

--- parses l.c:b
function M.EditLoc.parse(T, str, defaultBuf)
  local l, c, b = str:match'^(%d+)%.(%d+)%s*(.*)$'
  b = b=='' and defaultBuf or b
  assertf(l and c and b, 'invalid EditLoc: %s b=%s', str, b)
  return T{b=b, l=toint(l), c=toint(c)}
end

return M
