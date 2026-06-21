local mty    = require'metaty'

--- Core ele types.
local M = mty.mod'ele.types'

local G      = mty.G
local ds     = require'ds'
local fmt    = require'fmt'
local log    = require'ds.log'
M._term      = require'vt100'
local assertf = fmt.assertf
local sfmt = string.format
local toint = math.tointeger
local push, pop, concat = table.insert, table.remove, table.concat
local getp = ds.getp
local getmt = G.getmetatable

M.INIT_BUFS = 3 -- the default number of bufs on init (for testing)

M.WELCOME = [[
Welcome to the Ele Editor!

Press ^q (ctrl-q) twice at any time to exit.

This page will have more help message in the future.
]]

function M.getEditor(c)
  local Editor = require'ele.Editor'
  while c and mty.ty(c) ~= Editor do
    c = c.container
  end
  return c
end

--- The base record for Edit/Game.
M.BasePane = mty'BasePane' {
  'id[int]',
  'container', -- parent (Editor/Split)
  'actions {string: fn}: override of actions, especially keyinput',
  'hide [bool]: whether to hide cursor', hide = true,
  'l [int]: cursor line', 'c [int]: cursor col', l=1, c=1,

  -- FIXME: I don't think vl/vc is actually used...
  'vl[int]', vl=1,    'vc[int]', vc=1,  -- view   line, col (top-left)
  'tl[int]', tl=-1,   'tc[int]', tc=-1, -- term   line, col (top-left)
  'th[int]', th=-1,   'tw[int]', tw=-1, -- term   height, width
  'closed [bool]', closed = false,

  'modes [table]: override specific keybindings for this pane',

  IS_PANE = true,
}

function M.BasePane.__init(t)
  t.id = M.uniqueId()
end

getmetatable(M.BasePane).__call = function(T, t)
  T:__init(t)
  return mty.construct(T, t)
end

--- Called after this pane is focused by Editor.
function M.BasePane:focus(ed)
end

--- Called when this pane is closed by Editor.
function M.BasePane:close(ed)
  assert(not self.container, 'close() before container removed')
  assert(ed, 'must provide Editor')
  self.closed = true
end

function M.BasePane:drawCursor(ed)
  if self.hide then return end
  -- FIXME: this can auto-draw cursor using same trick as vim.
end

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
M.VSplit.insert = function(sp, i, v)
  assert(not v.container)
  table.insert(sp, i, v); v.container = sp
end

M.VSplit.replace = function(sp, from, to) --> from
  local i = assert(ds.indexOf(sp, from), 'from not found in Split')
  assert(from.container == sp)
  assert(not to.container)
  sp[i], to.container, from.container = to, sp, nil
  return from
end
M.VSplit.remove = function(sp, v) --> v
  local i = assertf(ds.indexOf(sp, v), '%q not found in Split', v)
  table.remove(sp, i); v.container = nil
  if #sp == 0 then -- no items, this shouldn't happen
    log.warning('zero items left in %s', mty.name(sp))
    sp.container:remove(sp)
  elseif #sp == 1 then -- only 1 item left, close self
    sp[1].container = nil
    sp.container:replace(sp, sp[1]):close(sp:getEditor())
    sp[1] = nil
  end
  return v
end
M.VSplit.draw = function(sp, ed, isRight)
  local d = ed.display
  local len = #sp; if len == 0 then return end
  local l,c = sp.tl, sp.tc
  local w,h = sp.tw // len, sp.th -- divide up the available width
  -- First view gets any extra width, the rest are even
  local v = sp[1]; v.tl,v.tc, v.tw,v.th = l,c, w + (sp.tw % len), h
  v:draw(ed, isRight)
  for i=2,len do
    c = c + v.tw -- increment the col# by previous width
    v = sp[i];     v.tl,v.tc, v.tw,v.th = l,c, w,h
    v:draw(ed, false) -- note: not right-most.
  end
end

--- A container with windows split horizontally (i.e. wide windows)
M.HSplit = mty.extend(M.VSplit, 'HSplit')
M.HSplit.draw = function(sp, ed, isRight)
  local d = ed.display
  local len = #sp; if len == 0 then return end
  local l,c = sp.tl, sp.tc
  local w,h = sp.tw, sp.th // len -- divide up the available height
  -- First view gets any extra height, the rest are even
  local v = sp[1]; v.tl,v.tc, v.tw,v.th = l,c, w, h + (sp.th % len)
  for i=2,len do
    l = l + v.th -- increment the line# by previous height
    v = sp[i];     v.tl,v.tc, v.tw,v.th = l,c, w,h
  end
  for _, v in ipairs(sp) do v:draw(ed, isRight) end
end

M.ID = 1
function M.uniqueId()
  local id = M.ID; M.ID = M.ID+1; return id
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
