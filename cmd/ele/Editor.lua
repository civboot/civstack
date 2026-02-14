-- defines ele.Editor
local mty    = require'metaty'
local fmt    = require'fmt'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local lines  = require'lines'
local Gap    = require'lines.Gap'
local Buffer = require'lines.buffer'.Buffer
local Edit   = require'ele.edit'.Edit
local et     = require'ele.types'
local push, pop, concat = table.insert, table.remove, table.concat

local min, max = math.min, math.max
local assertf = fmt.assertf
local sfmt = string.format

local EdSettings = mty'EdSettings' {
  'tabwidth [int]', tabwidth=2,
  'yankMax [int]: max yank size in bytes',
    yankMax=10 * 1024*1024, -- 10MiB
}

-- Editor is the global editor state that actions have access to.
--
-- action signature: function(data, event, evsend)
local Editor = mty'Editor' {
  's [EdSettings]',
  'mode  [string]: current editor mode',
  'modes [table]: keyboard bindings per mode (see: bindings.lua)',
  'actions [table]: actions which events can trigger (see: actions.lua)',
  'resources [table]: resources to close when shutting down',
  'buffers [list[Buffer]]', 'bufferId[map[Buffer, id]]',
  'namedBuffers [map[string,Buffer]]',
  'overlay [Buffer]: the overlay buffer',
  'edit [Buffer]: the current edit buffer. Also in namedBuffers.overlay',
  'view [RootView]: the root view',
  'display [Term|other]: display/terminal to write+paint text',
  'run [boolean]: set to false to stop the app', run=true,
  'ext [table]: table for extensions to store data',
  'search [str]: search pattern for searchBuf, etc',
  'lastEvent [table]: the last event executed.',
  'yank [ds.Deq]: a deque of removed text. See yankMax.',

  'error [callable]: error handler (ds.log.logfmt sig)',
  'warn  [callable]: warn handler',
  'newDat [callable(text)]: function to create new buffer',
    newDat = function(f) return f and Gap:load(f) or Gap({}, f) end,
  'redraw [boolean]: set to true to force a redraw',
}

getmetatable(Editor).__call = function(T, t)
  t = ds.merge({
    s=EdSettings{},
    mode='command', modes={},
    actions=ds.rawcopy(require'ele.actions'),
    buffers={}, bufferId={},
    namedBuffers=ds.WeakV{},
    overlay = Buffer{id=-1, dat=Gap{}},
    resources={}, ext={},
    yank=ds.Deq{},
    redraw = true,
  }, t)
  t = mty.construct(T, t)
  t.namedBuffers.overlay = t.overlay
  t.namedBuffers.search  = t:namedBuffer'search'
  return t
end

function Editor:__fmt(f)
  f:write'Editor{mode='; f:string(self.mode); f:write'}'
end

--- list of named buffers (name -> buffer)

function Editor:init()
  require'ele.bindings'.install(self)
  return self
end

--- Get an existing buffer if it exists.
--- Else return false if the buffer is path-like and should be
--- created, else nil.
function Editor:getBuffer(v) --> Buffer?
  if mty.ty(v) == Buffer then
    assert(self.bufferId[v], 'must create buffer with Editor:buffer')
    return v
  end
  if type(v) == 'number' then
    local b = self.buffers[v]; if b then return b end
  elseif type(v) == 'string' then
    local id = v:match'^b#(%d+)$'; if id then return self.buffers[tonumber(id)] end
    id = v:match'^b#([%w_-]+)$' if id then
      return assertf(self.namedBuffers[id], 'unknown named buffer: %q', id)
    end
    id = v:match'^%d+$'; if id then return self.buffers[tonumber(id)] end
    v = pth.canonical(v)
    for _, b in pairs(self.buffers) do
      if v == b.dat.path then return b end
    end
  elseif type(v) == 'nil' then -- create buffer
  else error('Cannot convert '..type(v)..' to buffer') end
end

-- create new buffer from v (path or table of lines)
-- idOrPath can be a buffer id, b#123 string or path/to/file.txt.
-- It will look for an existing buffer first, then create a
-- new one if not.
function Editor:buffer(idOrPath) --> Buffer
  if idOrPath ~= nil then
    local b = self:getBuffer(idOrPath); if b then return b end
  end
  log.info('creating buffer %q', idOrPath)
  local dat = self.newDat(idOrPath) -- do first to allow yield
  local id = #self.buffers + 1
  local b = Buffer{id=id, dat=dat, tmp=not idOrPath and {} or nil}
  self.buffers[id] = b
  self.bufferId[b] = id
  return self.buffers[id]
end

--- Get or create a named buffer (NOT a path).
function Editor:namedBuffer(name, path)
  local b = self.namedBuffers[name]; if b then return b end
  b = self:buffer(path)
  b.name                = name
  self.namedBuffers[name] = b
  return b
end


-- open path and focus. If already open then use existing buffer.
function Editor:open(path) --> edit
  return self:focus(self:buffer(path))
end

function Editor:draw()
  local v, d, e = self.view, self.display, self.edit
  d.text:insert(1,1, sfmt('[mode:%s]', self.mode))
  v.tl, v.tc, v.th, v.tw = 2, 1, d.h-1, d.w
  v:draw(self, true)
  e:drawCursor(self)
  self:_drawOverlay()
end

function Editor:_drawOverlay()
  local ov = self.overlay; if not ov.ext.show then return end
  local d = self.display
  local h, w = min(d.h, max(1, #ov)), 1 -- get height and width of overlay
  for l=1,#ov do w = max(w, #ov:get(l)) end

  local l, c = d.l, d.c -- find where it goes, prefer above.
  if     h < l        then  l = l - h     -- put above
  elseif l + h <= d.h then  l = l + 1     -- put below
  elseif l >= (d.h/2) then  l = 1         -- more space on top
  else                      l = l + 1 end -- more space on bot

  -- Start column goes directly next to cursor if possible.
  if c + w > d.w then c = max(1, d.w - w) end
  local b = lines.box(ov.dat, 1,1, h,w, ' ') -- filled box
  b = concat(b, '\n')
  local fb = d.styler:getFB'info'
  d.text:insert(l, c, b)
  d.fg:insert(l, c, b:gsub('[^\n]', fb:sub(1,1)))
  d.bg:insert(l, c, b:gsub('[^\n]', fb:sub(-1)))
end

--- Handle standard event fields.
--- Currently this only handles the [$mode] field.
function Editor:handleStandard(ev)
  local m = ev.mode; if m and self.mode ~= m then
    local err = et.checkMode(self, m); if err then
      return self.error('%s has invalid mode', ev, m)
    end
    log.info(' + mode %s -> %s', self.mode, m)
    if m == 'insert' and not self.edit.buf:changed() then
      self.edit:changeStart()
    elseif self.mode == 'insert' then
      self.edit.buf:discardUnusedStart()
    end
    self.mode = m
  end
end

--- Replace the view/edit from with to.
--- Since Editor supports only [$self.view] this means
--- it must be that value.
function Editor:replace(from, to) --> from
  assert(to)
  assert(self.view == from, 'view being replaced is not self.view')
  assert(from.container == self)
  assert(not to.container or to.container == from)
  self.view = to
  to.container, from.container = self, nil
  return from
end

--- Remove a view and remove self as it's container.
--- This does NOT close the view.
function Editor:remove(v) --> v
  assert(self.view == v, 'view being removed is not self.view')
  assert(v.container == self)
  self.view = nil
  if self.edit == v then self.edit = nil end
  v.container = nil
  return v
end

--- Focus the first edit view in container c (default self.view)
function Editor:focusFirst(c)
  c = c or self.view
  while mty.ty(c) ~= Edit do c = c[1] end
  assert(mty.ty(c) == Edit)
  self.edit = c
  if not self.view then self.view = c end
end

--- Replace the current edit view with the new [$self:buffer(b)].
--- Return the new edit view being focused.
function Editor:focus(b) --> Edit
  local b = assertf(self:buffer(b), '%q', b)
  local e = Edit{buf=b, yank=self.yank}
  if self.edit then self.edit.container:replace(self.edit, e)
  else              e.container = self end
  self.edit = e
  if not self.view then self.view = e end
  return e
end

return Editor
