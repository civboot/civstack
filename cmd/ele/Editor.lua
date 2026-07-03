-- defines ele.Editor
local mty    = require'metaty'
local fmt    = require'fmt'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local lines  = require'lines'
local Gap    = require'lines.Gap'
local Buffer = require'lines.buffer'.Buffer
local ix     = require'civix'
local Edit   = require'ele.edit'.Edit
local et     = require'ele.types'
local push, pop, concat = table.insert, table.remove, table.concat

local info = mty.from'ds.log  info'
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
  'buffers {Buffer}', 'bufferId{Buffer: id}',
  'namedBuffers {string: Buffer}',
  'overlay [Buffer]: the overlay buffer',
  'pane [Buffer]: the currently active pane.',
  'view [RootView]: the root view',
  'display [Term|other]: display/terminal to write+paint text',
  'run [boolean]: set to false to stop the app', run=true,
  'ext [table]: table for extensions to store data',
  'search [str]: search pattern for searchBuf, etc',
  'lastEvent [table]: the last event executed.',
  'yank [ds.Deq]: a deque of removed text. See yankMax.',

  'error [callable]: error handler (ds.log.logfmt sig)',
  'warn  [callable]: warn handler',
  'newDat [callable(path)]: function to create new buffer',
    newDat = function(f)
      if not f then
        f = os.tmpname(); info('creating tmp', f)
      end
      return Gap:load(f)
    end,
  'redraw [boolean]: set to true to force a redraw',
  DEFAULT_BUFFERS = ds.BiMap{'find', 'nav', 'overlay', 'search'},
}

getmetatable(Editor).__call = function(T, self)
  self = ds.merge({
    s=EdSettings{},
    mode='command', modes={},
    actions=ds.rawcopy(require'ele.actions'),
    buffers={}, bufferId=ds.WeakK{},
    namedBuffers=ds.WeakV{},
    overlay = Buffer{id=-1, dat=Gap{}},
    resources={}, ext={},
    yank=ds.Deq{},
    redraw = true,
  }, self)
  self = mty.construct(T, self)
  self.namedBuffers.overlay = self.overlay
  self.namedBuffers.search  = self:namedBuffer'search'
  return self
end

function Editor:getEditor() return self end

function Editor:__fmt(f)
  f:write'Editor{mode='; f:string(self.mode); f:write'}'
end

--- list of named buffers (name -> buffer)

function Editor:init()
  require'ele.bindings'.install(self)
  return self
end

function Editor:edit()
  local e = self.pane
  assert(not e or mty.ty(e) == Edit, 'not Edit')
  return e
end

function Editor:bufferName(b) --> string
  return b.name or ('b#'..assert(b.id))
end

function Editor:currentLocation(e)
  e = e or self:edit()
  return et.EditLoc{b=self:bufferName(e.buf), l=e.l, c=e.c}
end

function Editor:pushLocation(e) --> pushed
  e = e or self:edit()
  local loc = self:currentLocation(e)
  -- noop if already the same
  if mty.eq(loc, e.locations:get(#e.locations)) then return end
  e.locations:push(loc)
  info('pushed location %q', loc)
  return true
end

--- Get an existing buffer if it exists.
--- Else return false if the buffer is path-like and should be
--- created, else nil.
--- Special buffers: [+
--- * [$b#tmp] creates a new buffer pointing to a tmp file.
--- ]
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
      if id == 'tmp' then return self:buffer(os.tmpname()) end
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

-- create new buffer.
-- idOrPath can be a buffer id, b#123 string or path/to/file.txt.
-- It will look for an existing buffer first, then create a
-- new one if not.
function Editor:buffer(idOrPath) --> Buffer
  if idOrPath ~= nil then
    local b = self:getBuffer(idOrPath); if b then return b end
  end
  return self:_buffer(#self.buffers + 1, idOrPath)
end

function Editor:_buffer(id, path)
  log.info('creating buffer %s %q', id, path)
  local dat = self.newDat(path) -- do first to allow yield
  local b = Buffer{id=id, dat=dat, tmp=not path and {} or nil}
  self.buffers[id] = b
  self.bufferId[b] = id
  return self.buffers[id]
end

--- Get or create a named buffer.
function Editor:namedBuffer(name, path)
  local b = self.namedBuffers[name]; if b then return b end
  b = self:buffer(path)
  b.name = name
  self.namedBuffers[name] = b
  return b
end


-- open path and focus. If already open then use existing buffer.
function Editor:open(path) --> edit
  return self:focus(self:buffer(path))
end

function Editor:draw()
  local v, d, e = self.view, self.display, self.pane
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
    if m == 'insert' and not self:edit().buf:changed() then
      self:edit():changeStart()
    elseif self.mode == 'insert' then
      self:edit().buf:discardUnusedStart()
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
  if self.pane == v then self.pane = nil end
  v.container = nil
  return v
end

--- Focus the first edit view in container c (default self.view)
function Editor:focusFirst(c)
  c = c or self.view
  while not et.isPane(c) do c = c[1] end
  assert(et.isPane(c))
  self.pane = c
  if not self.view then self.view = c end
  c:focus(self)
end

--- Replace the current edit view with the new [$self:buffer(b)].
--- Return the new edit view being focused.
function Editor:focus(p) --> Edit
  local cur = self.pane
  if not et.isPane(p) then
    local b = assertf(self:buffer(p), '%q', p)
    p = Edit{buf=b, yank=self.yank}
    -- TODO: don't hard-code this.
    if mty.ty(cur) == Edit then
      p.locations = cur.locations:copy(127)
    end
  end
  if cur then
    if p.container then
      -- TODO assert that p is part of self.view
      self.pane = p
    else
      cur.container:replace(cur, p):close(self)
    end
  else
    assert(not p.container, 'no root view, yet p has container')
    p.container = self
  end
  self.pane = p
  if not self.view then self.view = p end
  p:focus(self)
  return p
end

function Editor:close() end

function Editor:state() --> ele.types.State
  local bufs = {}; for i, b in pairs(self.buffers) do
    if not self.DEFAULT_BUFFERS[b.name] then
      push(bufs, et.BufState{id=b.id, name=b.name, path=b:path()})
    end
  end
  table.sort(bufs, function(a, b) return a.id < b.id end)
  return et.State {
    ID = et.ID,
    buffers=bufs,
    view = self.view:state(),
    pane = self.pane.id,
  }
end

function Editor:loadState(st) --> self
  et.ID = st.ID
  self:rmTmp()
  for k,b in pairs(self.buffers) do
    if not self.DEFAULT_BUFFERS[b.name] then
      self.buffers[k] = nil
    end
  end
  for _, b in ipairs(st.buffers) do
    local buf = self:_buffer(b.id, b.path)
    buf.name = b.name
  end
  self.view.container = nil; self.view:close(self)
  self.view = st.view:load(self)
  self.view.container = self
  self:focusFirst()
  ds.walk(self.view, nil, function(key, p)
    dbg('walking', key)
    if type(key) ~= 'number' then return ds.SKIP end
    if rawget(p, 'id') == st.pane then
      self:focus(p); return true -- stop
    end
  end)
  return self
end

--- Cleanup all temporary files. Used for tests.
function Editor:rmTmp()
  for _, b in pairs(self.buffers) do
    if b:path():find'^/tmp/lua_' then
      info('removing tmp', b:path())
      ix.rm(b:path())
    end
  end
end

return Editor