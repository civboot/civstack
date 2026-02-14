local mty = require'metaty'
local ds = require'ds'
local lines = require'lines'
local motion  = require'lines.motion'
local Gap  = require'lines.Gap'

local M = {}
local span, bound = lines.span, lines.bound
local push, ty = table.insert, mty.ty
local concat, sfmt, srep = mty.from(string, 'concat, format, rep')
local info               = mty.from'ds.log  info'
local construct = mty.construct

M.ChangeId = 0
function M.nextChangeId() M.ChangeId = M.ChangeId + 1; return M.ChangeId end

M.ChangeKind = mty.enum'ChangeKind' {
  START = 1,
  INSERT = 2,
  REMOVE = 3,
}
local START          = M.ChangeKind.START
local INSERT, REMOVE = M.ChangeKind.INSERT, M.ChangeKind.REMOVE
local checkKind = M.ChangeKind.id

--- start kind:   [$Change{k=START, l,c, l2,c2}][{br}]
--- insert kind:  [$Change{k=INSERT, l,c, s='inserted'}][{br}]
--- removed kind: [$Change{k=REMOVE, l,c, s='removed'}]
M.Change = mty'Change' {
  'k[ChangeKind]',
  's[string]: string changed',
}
getmetatable(M.Change).__call = function(T, self)
  checkKind(self.k)
  assert(self[1] and self[2], 'must set l,c')
  return construct(T, self)
end

M.Buffer = mty'Buffer' {
  'id  [int]', 'name [str?]',
  'dat [lines.File]: i.e. Gap, EdFile',
  'fg [lines.File]: foreground asciicolor',
  'bg [lines.File]: background asciicolor',
  'readonly [bool]', -- TODO: actually implement readonly
  'l [int]', 'c [int]', -- used by clients

  -- recorded changes from update (for undo/redo)
  -- TODO: put these in a file.
  'changes',
  'changeMax [int]',    changeMax=0,
  'changeStartI [int]', changeStartI=0,
  'changeI [int]',      changeI=0,

  'tmp[parents]: if set, delete when parents are empty',
  'ext[table]: table for arbitrary extensions',
}

getmetatable(M.Buffer).__index = mty.hardIndex
M.Buffer.__newindex            = mty.hardNewindex

getmetatable(M.Buffer).__call = function(T, t)
  assert(t.dat, 'must set dat')
  if #t.dat == 0 then
    t.dat:write''
    if t.fg then t.fg:write''; t.bg:write'' end
  end
  t.changes = t.changes or {}
  t.ext = t.ext or {}
  if t.fg then assert(t.bg, 'must set both fg and bg, or neither') end
  return construct(T, t)
end

local Buffer, Change = M.Buffer, M.Change

function Buffer:doRm(ch)
  local len = #ch.s - 1; if len < 0 then return ch end
  local dat = self.dat
  local l,c = ch[1],ch[2]
  local l2, c2 = lines.offset(dat, len, l,c)
  if self.fg then self:_matchColorLine(l) end
  lines.remove(dat, l,c, l2,c2)
  if self.fg then
    lines.remove(self.fg, l,c, l2,c2)
    lines.remove(self.bg, l,c, l2,c2)
  end
  return ch
end

--- get the last character or space if empty.
local function lastChar(s)
  return #s == 0 and ' ' or s:sub(#s)
end

-- Force the line to match in length.
-- Syntax highlighters are "lazy" and fill out
-- blocks using only a single character.
function Buffer:_matchColorLine(l)
  while #self.fg < l do self.fg:write'\n'; self.bg:write'\n' end
  local dln, fln = self.dat[l] or '', self.fg[l] or ''
  if #dln == #fln then return end
  assert(#fln < #dln)
  local bln = self.bg[l]
  self.fg[l] = fln..srep(lastChar(fln), #dln - #fln)
  self.bg[l] = bln..srep(lastChar(bln), #dln - #bln)
end

function Buffer:doInsert(ch)
  local l,c = ch[1],ch[2]
  if self.fg then self:_matchColorLine(l) end
  lines.insert(self.dat, ch.s, l,c)
  if self.fg then
    local s = ch.s:gsub('[^ \n]', 'z')
    lines.insert(self.fg, s, l,c)
    lines.insert(self.bg, s, l,c)
  end
  return ch
end

local function sError() error'attempt to use Start for undo/redo' end
local CHANGE_REDO = M.ChangeKind:matcher{
  START=sError,
  INSERT=Buffer.doInsert,
  REMOVE=Buffer.doRm,
}
local CHANGE_UNDO = M.ChangeKind:matcher{
  START=sError,
  INSERT=Buffer.doRm,
  REMOVE=Buffer.doInsert,
}

-- TODO: remove this
function Buffer.new(s)
  return Buffer{ dat=Gap(s) }
end

function Buffer:path() return self.dat.path end --> path?

function Buffer:__fmt(fmt)
  fmt:write(('Buffer{%s, id=%s, path=%q}'):format(
    self.tmp and (#self.tmp == 0) and '(closed) ' or '(tmp)',
    self.id, self.dat.path))
end
function Buffer:__len() return #self.dat       end
function Buffer:get(i)  return self.dat:get(i) end

function Buffer:addChange(ch)
  ch = Change(ch)
  self.changeI = self.changeI + 1; self.changeMax = self.changeI
  self.changes[self.changeI] = ch
  return ch
end
--- Return true if anything has changed since i (default=changeStartI)
function Buffer:changed(i) --> bool
  return (i or self.changeStartI) < self.changeI
end
function Buffer:discardUnusedStart()
  if self.changeI ~= 0 and self.changeStartI == self.changeI then
    local ch = self.changes[self.changeI]
    assert(ch.k == START)
    self.changeI = self.changeI - 1
    self.changeMax = self.changeI
    self.changeStartI = 0
  end
end
function Buffer:changeStart(l, c)
  local ch = Change{k=START, l,c}
  self:discardUnusedStart()
  self:addChange(ch); self.changeStartI = self.changeI
  return ch
end
function Buffer:getStart()
  if self.changeStartI <= self.changeMax then
    return self.changes[self.changeStartI]
  end
end
function Buffer:printChanges()
  for i=1,self.changeMax do
    pnt(self.changes[i], (i == self.changeI) and "<-- changeI" or "")
  end
end

function Buffer:canUndo() return self.changeI >= 1 end
function Buffer:canRedo() return self.changeI < self.changeMax end

function Buffer:undoTop()
  if self:canUndo() then return self.changes[self.changeI] end
end
function Buffer:redoTop()
  if self:canRedo() then return self.changes[self.changeI + 1] end
end

function Buffer:undo()
  local ch = self:undoTop(); if not ch then return end
  self:discardUnusedStart(); self.changeStartI = 0

  local done = {}
  while ch do
    self.changeI = self.changeI - 1
    push(done, ch)
    if ch.k == START then break
    else
      assert(ty(ch) == Change)
      CHANGE_UNDO[ch.k](self, ch)
    end
    ch = self:undoTop()
  end
  return ds.reverse(done)
end

function Buffer:redo()
  local ch = self:redoTop(); if not ch then return end
  self:discardUnusedStart(); self.changeStartI = 0
  assert(ch.k == START)
  local done = {ch}; self.changeI = self.changeI + 1
  ch = self:redoTop(); assert(ch.k ~= START)
  while ch and ch.k ~= START do
    self.changeI = self.changeI + 1
    push(done, ch)
    CHANGE_REDO[ch.k](self, ch)
    ch = self:redoTop()
  end
  return done
end

--- Some APIs allow negative values for spans, this converts them
--- to absolute positive line/cols.
function Buffer:span(...)
  local l, c, l2, c2 = span(...)
  if l  < 0 then l  = #self + l  + 1 end
  if l2 < 0 then l2 = #self + l2 + 1 end
  if c  and c  < 0 then c  = #self:get(l)  + c  + 1 end
  if c2 and c2 < 0 then c2 = #self:get(l2) + c2 + 1 end
  return l, c, l2, c2
end

function Buffer:append(s)
  local ch = self:addChange{k=INSERT, #self.dat+1,1, s=s}
  self:doInsert(ch)
  return ch
end

function Buffer:insert(s, l,c)
  l, c = bound(self.dat, l,c or 1)
  local ch = self:addChange{k=INSERT, l,c, s=s}
  self:doInsert(ch)
  return ch
end

function Buffer:remove(...)
  local l, c, l2, c2 = span(...)
  info('remove span %s.%s %s.%s', l,c, l2,c2)

  local t = self.dat
  if l2 > #t then l2, c2 = len, #get(t,#t) + 1 end
  l,c   = bound(t, l, c or 1)
  l2,c2 = bound(t, l2, c2 or (#t[l2] + 1))
  local lt, ct = motion.topLeft(l, c, l2, c2)
  lt, ct = bound(t, lt, ct)
  local s = lines.sub(t, l, c, l2, c2)
  local ch = self:addChange{
    k=REMOVE, lt,ct,
    s=type(s)=='string' and s or concat(s, '\n'),
  }
  info('remove %s.%s : %s.%s', l,c, l2,c2)
  self:doRm(ch)
  return ch
end

function Change:__tostring()
  return sfmt('Ch{%s %s.%s %s}', self.k, self[1],self[2],
      ('len='..#self.s) or sfmt('%s.%s', self[3],self[4]))
end

return M
