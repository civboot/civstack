local M = mod'ele.edit'

local mty    = require'metaty'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local Stack  = require'ds.Stack'
local motion = require'lines.motion'
local ix = require'civix'
local lines = require'lines'
local Gap   = require'lines.Gap'
local et    = require'ele.types'

local unpack       = table.unpack
local push, concat = table.insert, table.concat
local sfmt, srep   = string.format, string.rep
local min, max     = math.min, math.max
local span, box = mty.from(lines, 'span, box')
local assertf      = mty.from'fmt  assertf'
local info         = mty.from'ds.log  info'

--- Ele Edit View for viewing and editing text files in a pane.
M.Edit = mty.extend(et.BasePane, 'Edit', {
  -- vl/vc are what (top-left)line/column are being VIEWED by the user.
  -- They dynamically update during [$:draw()] as the cursor moves.
  'vl[int]', vl=1,    'vc[int]', vc=1,
  'buf [Buffer]',
  'yank [ds.Deq]: global yank deque',
  'locations [ds.Stack[ele.types.EditLoc]]: a deq of locations visited.',
  'lineStyle [str]: asciicolor style',
    lineStyle = 'bar:line',
})

getmetatable(M.Edit).__call = function(T, t)
  T.__init(t)
  local b = assert(t.buf, 'must set buf')
  t.l, t.c = t.l or b.l, t.c or b.c
  t.locations = Stack(t.locations or {})
  local self = mty.construct(T, t)
  self:changeStart()
  return self
end

M.Edit.getEditor = et.getEditor

function M.Edit:close(ed)
  et.BasePane.close(self, ed)
  local b = self.buf
  if b.tmp then
    b.tmp[self] = nil; if #b.tmp == 0 then
      ed.buffers[self.id] = nil
    end
  end
  b.l,b.c = self.l,self.c
end
function M.Edit:save(ed)
  local b = self.buf; local dat = b.dat
  local ro = b.readonly; b.readonly = true
  local path = assert(dat.path, 'must set path')
  local tpath = path..'.__ELE__'
  -- TODO: schedule the rest as coroutine to not block.
  dat:flush()
  local tmp = assert(io.open(tpath, 'w'))
  dat:dumpf(tmp); tmp:flush()
  dat:close();    tmp:close()
  -- TODO: I should move with :move (need to implement)
  ix.mv(tpath, path)
  b.readonly = ro -- in case the below fails
  dat = assert(ed.newDat(path),
               'CRITICAL: failed to load saved path')
  b.readonly = ro
  b.dat = dat
end

function M.Edit:__fmt(f)
  f:write'Edit[id='; f:number(self.id); f:write']'
end

function M.Edit:__len() return #self.buf end
function M.Edit:copy()
  return ds.copy(self, {
    id=T.nextViewId(),
    locations=self.locations:copy(127)
  })
end
function M.Edit:curLine()
  return self.buf.dat[self.l] end
function M.Edit:colEnd() return #(self:curLine() or '') + 1 end
function M.Edit:lastLine() return self.buf[#self] end
function M.Edit:offset(off)
  return lines.offset(self.buf.dat, off, self.l, self.c)
end

function M.Edit:boundC(l,c)
  return ds.bound(c, 1, #self.buf:get(l) + 1)
end
function M.Edit:boundLC(l, c)
  if l <= 1 then
    if #self == 0 then return 1, 1 end
    return 1, ds.bound(c, 1, #self.buf:get(1) + 1)
  end
  l = ds.bound(l, 1, #self)
  return l, self:boundC(l,c)
end

-- bound the column for the line
function M.Edit:boundCol(c, l)
  return ds.bound(c, 1, #self.buf:get(l or self.l) + 1)
end

-- update view fields to see cursor (if needed)
function M.Edit:viewCursor()
  local l, c = self:boundLC(self.l, self.c)
  local bh, bw = self:barDims()
  local th, tw = self.th - bh, self.tw - bw
  if self.vl > l          then self.vl = l end
  if l > self.vl + th - 1 then self.vl = l - th + 1 end
  if c < self.vc          then self.vc = c end
  if c > self.vc + tw - 1 then self.vc = c - tw + 1 end
end

-----------------
-- Mutations: these update the changes in the buffer
function M.Edit:changeStart()
  self.buf:changeStart(self.l, self.c)
end

function M.Edit:changeUpdate2()
  local b = self.buf
  if b:changed() then
    local ch = assert(self.buf:getStart())
    ch[3], ch[4] = self.l, self.c
  end
end

function M.Edit:append(msg)
  local l2 = #self + 1
  self.buf:append(msg)
  self.l, self.c = l2, 1
  self:changeUpdate2()
end

function M.Edit:insert(s)
  local b = self.buf
  b:insert(s, self.l, self.c);
  self.l, self.c = lines.offset(b.dat, #s, self.l, self.c)
  -- if causes cursor to move to next line, move to end of cur line
  -- except in specific circumstances
  if (self.l > 1) and (self.c == 1) and ('\n' ~= s:sub(#s)) then
    self.l, self.c = self.l - 1, #b[self.l - 1] + 1
  end
  self:changeUpdate2()
end

function M.Edit:remove(...)
  local ch = self.buf:remove(...)
  self:changeUpdate2()
end

function M.Edit:removeOff(off, l, c)
  if off == 0 then return end
  l, c = l or self.l, c or self.c;
  local l2, c2 = lines.offset(self.buf.dat, ds.absDec(off), l, c)
  if off < 0 then l, l2, c, c2 = l2, l, c2, c end
  self:remove(l, c, l2, c2)
end

function M.Edit:replace(s, ...)
  local l1, c1 = self.l, self.c
  local l, c = span(...)
  assert(self.l == l and (not c or c1 == c))
  local chR = self:remove(...);
  local chI = self:insert(s)  ;
  self.l, self.c = l1, c1
  self:changeUpdate2()
end

--- Clear the buffer.
function M.Edit:clear()
  self:remove(1,#self)
  self.l,self.c = 1,1
  self:changeUpdate2()
end

-----------------
-- Undo / Redo
function M.Edit:undo()
  local chs = self.buf:undo(); if not chs then return end
  local ch = assert(chs[1])
  self.l, self.c = ch[1],ch[2]
  return true
end
function M.Edit:redo()
  local chs = self.buf:redo(); if not chs then return end
  local ch = assert(chs[1])
  self.l, self.c = ch[3],ch[4]
  return true
end

-----------------
-- Draw to display
function M.Edit:draw(ed, isRight)
  local d = ed.display
  local bh, bw = self:barDims()
  self:viewCursor()
  self:drawBars(d)
  self.th = self.th - bh
  self.tw = self.tw - bw
  self.tc = self.tc + bw
  local buf = self.buf
  buf.l,buf.c = self.l,self.c
  self:_drawBox(d.text, buf.dat)
  if buf.fg then -- use color
    self:_drawBox(d.fg, buf.fg)
    self:_drawBox(d.bg, buf.bg)
  else -- make first fg/bg a 'z'
    local spcs = srep('z\n', self.th) 
    d.fg:insert(self.tl,self.tc, spcs)
    d.bg:insert(self.tl,self.tc, spcs)
  end
end

-- draw box from lf onto g(rid).
function M.Edit:_drawBox(g, lf)
  g:insert(self.tl, self.tc, box(lf,
    self.vl,               self.vc,
    self.vl + self.th - 1, self.vc + self.tw - 1))
end

function M.Edit:barDims()
  if self.tw <= 10 or self.th <= 3 then return 0, 0 end
  return 1, 2
end
local function pad2(i)
  i = tostring(i)
  return srep(' ', 2 - #i)..i
end
function M.Edit:drawBars(d) --> botHeight, leftWidth
  if self.tw <= 10 or self.th <= 3 then return end
  local tl, tc, th, tw = self.tl, self.tc, self.th, self.tw
  local cl, cc, len = self.l,self.c, #self -- cl,cc: cursor line,col
  local wl = tl  -- wl: write line
  local txt, fgd, bgd = d.text, d.fg, d.bg
  local fb = d.styler:getFB(self.lineStyle)
  local fg,bg = srep(fb:sub(1,1), 2), srep(fb:sub(-1), 2)
  for l=self.vl, self.vl+self.th - 2 do
    if     l <= cl  then txt:insert(wl, tc, pad2(cl - l))
    elseif l <= len then txt:insert(wl, tc, pad2(l - cl))
    else                 txt:insert(wl, tc, '  ') end
    fgd:insert(wl, tc, fg)
    bgd:insert(wl, tc, bg)
    wl = wl + 1
  end

  local b, info = self.buf, {'|'}
  local name, id, p = b.name, assert(b.id), b.dat.path
  if p    then push(info, sfmt(' %s:%i.%i', pth.nice(p), self.l, self.c)) end
  if name then push(info, ' b#'..name..(p and '' or sfmt(':%i.%i', self.l,self.c)))
  end push(info, ' (b#'..id)
  if p or name then push(info, ')')
  else              push(info, sfmt(':%i.%i)', self.l, self.c)) end

  info = concat(info):sub(1, self.tw - 1)..' '
  txt:insert(wl, tc, info)
  for c=tc+#info, tc+tw-1 do txt[wl][c] = '=' end
  return 1, 2
end

-- Called by model for only the focused editor
function M.Edit:drawCursor(ed)
  -- TODO: alternativelly, consider using d.hide and simply
  -- reverting the fg/bg for the cursor.
  local d = ed.display
  local c = math.min(self.c, self:colEnd())
  d.l, d.c = self.tl + (self.l - self.vl), self.tc + (c - self.vc)
end

function M.Edit:copy()
  self.tl,self.tc, self.tw,self.th = -1,-1, -1,-1
  local e2 = ds.copy(self)
  e2.id, e2.container = et.uniqueId(), nil
  e2.modes = self.modes and ds.copy(self.modes) or nil
  return e2
end

--- Split the edit by wrapping it and a copy into split type S.
--- Return the resulting split.
function M.Edit:split(S) --> split
  local c = self.container
  local sp = S{};  c:replace(self, sp) -- note: DON'T close self
  sp:insert(1, self); sp:insert(2, self:copy())
  return sp
end

local function getIndent(ln) --> int
  return select(2, ln:find'^\t*')
end

function M.Edit:autoIndent()
  local b, l, ln, ind = self.buf, self.l
  while l >= 1 do -- look up
    ln = b:get(l); ind = getIndent(ln)
    if ind > 0 then goto doIndent end
    if #ln > 0 then break end
    l = l - 1
  end
  l = self.l + 1
  while l <= #b do
    ln = b:get(l); ind = getIndent(ln)
    if ind > 0 then goto doIndent end
    if #ln > 0 then break end
    l = l + 1
  end
  do return end
  ::doIndent::
  self.l,self.c = l,1
  self:write(srep('\t', ind))
end

function M.Edit:path() return self.buf:path() end --> path?

function M.Edit:state()
  return et.PaneState {
    ty = mty.fullname(self),
    dat = {
      id=self.id, path=self.buf:path(),
      l=self.l,   c=self.c,
      vl=self.vl, vc=self.vc,
    }
  }
end

function M.Edit.fromState(T, ed, s)
  local d = s.dat
  return T{
    id=d.id, buf=ed:buffer(d.path),
    l=d.l,    c=d.c,
    vl=d.vl, vc=d.vc,
  }
end

return M