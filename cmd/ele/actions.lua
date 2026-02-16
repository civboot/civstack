-- Actions builtin plugin
local M = mod and mod'ele.actions' or {}
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local It = require'ds.Iter'
local pth = require'ds.path'
local log = require'ds.log'
local lines = require'lines'
local motion = require'lines.motion'
local ix = require'civix'
local et = require'ele.types'
local Edit = require'ele.edit'.Edit
local B = require'ele.bindings'

local push, pop = table.insert, table.remove
local concat    = table.concat
local unpack    = table.unpack
local sfmt      = string.format
local srep, sconcat = string.rep, string.concat
local min, max  = math.min, math.max
local info = mty.from'ds.log  info'
local callable = mty.callable
local try = ds.try
local assertf = fmt.assertf

----------------------------------
-- KEYBINDINGS

-- keyinput action.  This handles actual user keyboard inputs as well as
-- hotkey/etc.
--
-- The basic architecture of keys.lua is that the Keys object holds all
-- state necessary for determining user intent across a chord of keys,
-- which are pressed in sequence. Typically, these end with the binding
-- generating an event when all keys are gathered.
function M.keyinput(ed, ev, evsend)
  local mode = ed.modes[ed.mode]; local fallback = mode.fallback
  -- note: ki=key-input
  local ki, K, err = assert(ev[1], 'missing key'), ed.ext.keys
  if K.keep then K.keep = nil
  else           K.chord, K.event, K.next = {}, nil, nil end
  push(K.chord, ki)
  log.info('keyinput %q mode:%s %q', ki, ed.mode, K.chord)
  local nxt = K.next
  if nxt then
    local getb = type(nxt) == 'table' and mty.getmethod(nxt, 'getBinding')
    if getb then nxt = getb(nxt, ki) end
  else
    local emode = ds.getp(ed, {'edit', 'modes', ed.mode, ki})
    nxt = emode and rawget(emode, ki)
       or rawget(mode, ki)
       or emode and rawget(emode, 'fallback')
  end
  nxt = nxt or fallback
  local ok, ev
  if type(nxt) == 'table' and not getmetatable(nxt) then
    log.info(' + keyinput plain ev %q (%q)', K.chord, nxt)
    ok, ev = true, ds.copy(K.event or {}, nxt)
  elseif callable(nxt) then
    log.info(' + keyinput calling %q (%q)', K.chord, nxt)
    ok, ev = try(nxt, K)
    if not ok then
      return ed.error('%q (%s) failed: %q',
                      nxt, concat(K.chord, ' '), ev)
    end
  elseif mty.getmethod(nxt, 'getBinding') then
    K.next, K.keep = nxt, true
    return -- wait till next key
  else
    K.keep = nil
    fmt.errorf('%q is neither callable, plain table or KeyBindings',
      K.chord)
  end
  if ev then
    log.info(' --> %q', ev)
    evsend:pushLeft(ev)
  end
  err = K:check(ed); if err then
    K.keep = nil
    ed.error('%s -> invalid keys: %s', ki, err)
  end
end

----------------------------------
-- UTILITY

-- merge action
-- directly merges ed with event (action key removed)
function M.merge(ed, ev)
  ev.action = nil; ds.merge(ed, ev)
end

-- chain: push multiple events to the FRONT, effectively
--   replacing this action with it's children.
-- Note: supports times
function M.chain(ed, ev, evsend)
  for _=1,ev.times or 1 do evsend:extendLeft(ev) end
  ed:handleStandard(ev)
end

----------------------------------
-- MOVE
-- This defines the move action
local DOMOVE = {
  lines = function(e, _, ev) e.l = e.l + ev.lines end,
  -- start/end of line/text
  sol = function(e, line) e.c = 1                           end,
  sot = function(e, line) e.c = line:find'%S' or 1          end,
  sof = function(e, line) e.l,e.c = 1,1                     end,
  eol = function(e, line) e.c = #line                       end,
  eot = function(e, line) e.c = line:find'.*%S%s*' or #line end,
  eof = function(e, line) e.l,e.c = #e,1                    end,

  --- move lines screen widths (e.th * ev.mul / ev.div)
  screen = function(e, line, ev)
    e.l = e.l + (e.th * (ev.mul or 1) // (ev.div or 1))
  end,
  -- move by word
  forword  = function(e, line)
    e.c = e:boundC(e.l,e.c)
    e.c = motion.forword(line, e.c) or (e.c + 1)
  end,
  backword = function(e, line)
    e.c = e:boundC(e.l,e.c)
    e.c = motion.backword(line, e.c) or (e.c + 1)
  end,
  -- search for character
  find = function(e, line, ev)
    e.c = e:boundC(e.l,e.c)
    e.c = line:find(ev.find, e.c+1, true) or e.c
  end,
  findback = function(e, line, ev)
    e.c = e:boundC(e.l,e.c)
    e.c = motion.findBack(line, ev.findback, e.c, true) or e.c
  end,
}
local function domove(e, ev)
  local fn = ev.move and DOMOVE[ev.move]
  if fn      then fn(e, e.buf:get(e.l), ev) end
  if ev.cols then e.c = e.c + ev.cols       end
  if ev.rows then e.l = e.l + ev.rows       end
  if ev.off  then
    e.c = e:boundC(e.l,e.c)
    e.l, e.c = e:offset(ev.off)
  end
end

-- move action
--
-- set move key to one of:
--   lines: move set number of lines (set lines = +/- int)
--   forword, backword: go to next/prev word
--   sol, eol: go to start/end of line
--   sot, eot: to to start/end of (non-whitespace) text
--   sof, eof: to to start/end of file
--   find, findback: find character forwards/backwards (set find/findback key)
--
-- these can additionally be set and will be done in order:
--   cols, off: move cursor by columns/offset (positive or negative)
--
-- Supports: times
function M.move(ed, ev)
  local e = ed.edit
  log.trace('move %q [start %s.%s]', ev, e.l, e.c)
  if ev.move == 'absolute' then
    e.l,e.c = ev.l, ev.c or e.c
  else
    for _=1,ev.times or 1 do domove(e, ev) end
  end
  e.l = e:boundLC(e.l, e.c)
  ed:handleStandard(ev)
end

--- Get the start/end of a move without changing
--- the position.
function M.getMove(ed, ev) --> l1,c1, l2,c2
  local e = ed.edit
  local e_c = e.c
  if ev.move == 'forword' then ev.cols = ev.cols or -1 end
  local l, c = e.l, e.c + (ev.cols1 or 0)
  M.move(ed, ev)
  local l2,c2 = e.l,e.c
  e.l,e.c = l,e_c
  return lines.sort(l, c, l2,c2)
end

----------------------------------
-- MODIFY

-- insert action, normally inserts ev[1] at the current position.
--
-- Set [$special] to call I_SPECIAL fn first.
function M.insert(ed, ev, evsend)
  -- Note: changeStart is in Editor.handleStandard.
  local e = ed.edit
  if ev[1] then
    e:insert(string.rep(assert(ev[1]), ev.times or 1))
  end
  ed:handleStandard(ev)
end

function M.insertTab(ed, ev)
  local tw = ed.s.tabwidth
  local c = (ed.edit.c - 1) % tw
  ed.edit:insert(srep(' ', tw - c))
  ed:handleStandard(ev)
end

--- Yank without ed:handleStandard()
function M._yank(ed, ev)
  local e = ed.edit
  if ev.lines == 0 then
    local t = ev.times; t = (t and (t - 1)) or 0
    log.info('yank lines(0) %s:%s', e.l, e.l + t)
    ed.yank:push(lines.sub(e.buf.dat, e.l, e.l + t))
  else
    local l,c, l2,c2 = M.getMove(ed, ev)
    log.info('yank %q: %s.%s -> %s.%s', ev, l,c, l2,c2)
    ed.yank:push(lines.sub(e.buf.dat, l,c, l2,c2))
  end
end

--- yank movement action.
function M.yank(ed, ev)
  local mode = ds.popk(ev, 'mode') -- cache, we handle at end
  M._yank(ed, ev)
  ev.mode = mode; ed:handleStandard(ev)
end

--- Paste from an index (default=1) from the yank stream.
--- The index goes from last -> first, so 1 is the most recent yank.
function M.paste(ed, ev)
  local ri = ev.index or 1  -- right index
  local dat = ed.yank[ed.yank.right - (ri - 1)]
  assertf(dat, 'yank index empty: %s', ri)
  local e = ed.edit; e:changeStart()
  if type(dat) == 'string' then e:insert(dat)
  else
    local s = concat(dat, '\n')
    e.c = #(e.buf:get(e.l) or '') + 1
    if s:sub(-1) == '\n' then
      e:insert('\n'..s:sub(1,-2))
    end
  end
  ed:handleStandard(ev)
  e:changeUpdate2()
end

-- remove movement action
--
-- This is always tied with a movement (except below).
-- It performs the movement and then uses the new location
-- as the "end"
--
-- Exceptions:
-- * lines=0 removes a single line (also supports times)
function M.remove(ed, ev)
  local mode = ds.popk(ev, 'mode') -- cache, we handle at end
  local e = ed.edit; e:changeStart()
  M._yank(ed, ev)
  local t = ev.times
  if ev.lines == 0 then
     local l2 = (t and (t - 1)) or 0
    log.info('remove lines(0) %s:%s', e.l, e.l + l2)
    e:remove(e.l, e.l + l2)
  else
    local l,c, l2,c2 = M.getMove(ed, ev)
    log.info('@@ remove t=%s', t)
    if t and l==l2 and c==c2 then c2 = c2 + (t-1) end
    log.info('remove %q: %s.%s -> %s.%s', ev, l,c, l2,c2)
    if ev.lines then e:remove(l,l2)
    else             e:remove(l,c, l2,c2) end
    l, c = motion.topLeft(l, c, l2, c2)
    e.l = math.min(#e.buf, l); e.c = e:boundCol(c)
  end
  ev.mode = mode; ed:handleStandard(ev)
  e:changeUpdate2()
end

----------------------------------
-- Search Buf

function M.searchBuf(ed, ev)
  local e, sb = ed.edit, ed:namedBuffer'search'
  if ev.overlay then -- update find buffer from overlay
    ed.search = ed.overlay:get(1)
    if ev.overlay == 'store' then
      sb:insert('\n'..ed.search, -1,'end')
    end
  else ed.search = sb:get(#sb) end

  for _=1, ev.times or 1 do
    if ev.next then
      local l,c = lines.find(e.buf.dat, ed.search, e.l,e.c+1)
      if not l and ev.wrap then
        l,c = lines.find(e.buf.dat, ed.search, 1,1)
      end
      if l then e.l,e.c = l,c end
    elseif ev.prev then
      local l,c = lines.findBack(e.buf.dat, ed.search, e.l,e.c-1)
      if not l and ev.wrap then
        l,c = lines.findBack(e.buf.dat, ed.search, -1,-1)
      end
      if l then e.l,e.c = l,c end
    end
  end
end

----------------------------------
-- NAV

M.nav = mod and mod'ele.actions.nav' or setmetatable({}, {})
getmetatable(M.nav).__call = function(_, ed, ev, evsend)
  local e1 = ed.edit
  local e = ed:focus'b#nav'
  e:changeStart()
  assertf(M.DO_NAV[ev.nav], 'unknown nav: %q', ev.nav)(ed, e1, e)
  e:changeUpdate2()
  ed:handleStandard(ev)
end

local nav = M.nav

M.DO_NAV = {
  cwd = function(ed, e1, e)
    e:clear(); e:insert(pth.small(pth.cwd())); e.l = 1
    nav.expandEntry(e.buf, 1, ix.ls)
  end,
  cbd = function(ed, e1, e)
    e:clear(); local p = e1.buf.dat.path
    if p then
      e:insert(pth.small(pth.dir(p))); e.l = 1
      nav.expandEntry(e.buf, 1, ix.ls)
    else e:insert(sfmt('b#%s', e.buf.id)); e.l,e.c = 1,1 end
  end,
  buf = function(ed, e1, e)
    e:clear()
    for i, b in It:ofOrdMap(ed.buffers) do
      local p = b:path()
      e:insert(sfmt('b#%-8s %s\n', b.name or i,
        p and pth.small(p) or '(tmp)'))
    end
    e.l,e.c = 1,1
    -- FIXME: enter find mode
  end,
}

function nav.getFocus(line)
  return line:match'^%-?([.~]?/[^\n]*)'
end
function nav.getEntry(line) --> (indent, kind, entry)
  local i, k, e = line:match'^(%s+)([*+-])%s*([^\n]+)'
  if not i then return end
  return i, k, e:match'^%./' and e:sub(3) or e
end
local getFocus, getEntry = nav.getFocus, nav.getEntry

--- Find the parent of current path entry
--- if isFocus the entry will be the focus (and ind will be 0)
function nav.findParent(b, l) --> linenum, line
  local line = b:get(l);
  if getFocus(line) then return l, line, true  end
  local ind = getEntry(line); if not ind then return end
  ind = #ind
  for l = l, 1, -1 do
    local line = b:get(l);
    if getFocus(line) then return l, line, true  end
    local i = getEntry(line); if not i then return end
    if #i < ind       then return l, line, false end
  end
end

--- Find the focus path line num (i.e. the starting directory)
function nav.findFocus(b, l) --> linenum, line
  for l=l,1,-1 do
    local line = b:get(l)
    if getFocus(line)     then return l, line end
    if not getEntry(line) then return end
  end
end

--- Find the last line of the focus's entities (or itself).
--- invariant: line l is an entry or focus.
function nav.findEnd(b, l) --> linenum
  while l + 1 <= #b do
    l = l + 1
    if not getEntry(b:get(l)) then return l - 1 end
  end
  return l
end

--- Find the view (focusLineNum, endLineNum, focusLine)
function nav.findView(b, l) --> (fln, eln, fline)
  local fl, fline = nav.findFocus(b, l); if not fl then return end
  return fl, assert(nav.findEnd(b, l), 'findEnd'), fline
end

--- Walk up the parents, getting the full path.
--- If not an entry, try to find the path from the column.
function nav.getPath(b, l,c) --> string
  local ln = b:get(l); local path, ind
  local focus   = getFocus(ln); if focus then return focus  end
  local i, _, e = getEntry(ln); if not i then goto nonentry end
  path, ind = {e}, #i

  -- Scan up, adding entries with less indent to path.
  for l = l-1, 1, -1 do
    local line = b:get(l)
    focus = getFocus(line); if focus then
      push(path, focus)
      return pth.concat(ds.reverse(path))
    end
    i, _, e = getEntry(line); if not i then break end
    if #i < ind then push(path, e); ind = #i end
  end
  ::nonentry::
  if not c then return end
  if motion.pathKind(ln:sub(c,c)) ~= 'path' then return end
  local si, ei = motion.getRange(ln, c, motion.pathKind)
  return ln:sub(si,ei)
end

function nav.findEntryEnd(b, l) --> linenum
  local ind = getEntry(b:get(l)); if not ind then return end
  ind = #ind
  for l=l+1, #b do
    local i = getEntry(b:get(l))
    if not i or #i <= ind then return l-1 end
  end
end

function nav.backFocus(b, l)
  local fl,fe = nav.findView(b, l)
  log.info('nav.backFocus fl=%i fe=%i', fl, fe)
  if not fl then return end
  if fe > fl then return b:remove(fl+1, fe) end
  local line = b:get(l)
  local dir = pth.last(line)
  b:remove(fl, #dir+1, fl, #line)
end

--- Go backwards on the entry, returning the new line
--- For focus, this will go back one component.
--- For entry, this will collapse parent (and move to it).
function nav.backEntry(b, l) --> ln
  ::start::
  local le = nav.findEntryEnd(b, l)
  if not le then
    nav.backFocus(b, l)
    return l
  end
  if l == le then
    l = nav.findParent(b, l)
    goto start
  end
  if le > l then b:remove(l+1, le) end
  return l
end

function nav.expandEntry(b, l, ls) --> numEntries
  local entries = ls(nav.getPath(b, l))
  if #entries == 0 then return end
  local line = b:get(l)
  local ind = #(getEntry(line) or '')
  for i, e in ipairs(entries) do
    entries[i] = sconcat('', srep(' ',ind+2), '* ', e)
  end
  b:insert('\n', l,#line+1)
  b:insert(concat(entries, '\n'), l+1,1)
  return #entries - 2
end

function nav.doBack(b, l, times)
  for _=1,times do
    local nl = nav.backEntry(b, l); if l == nl then break end
    l = nl
  end
end

function nav.doExpand(b, l, times, ls)
  local line, en = b:get(l), nil
  local path = getFocus(line) or select(3, getEntry(line))
  if not path or not pth.isDir(path) then return end
  ::expand::
  ls = ls or ix.ls
  local numEntries = nav.expandEntry(b, l, ls)
  times = times - 1; if times <= 0 then return end
  for l=l+1, l+numEntries do nav.doExpand(b, l, times, ls) end
end

--- go to path at l,c. If op=='create' then create the path
function nav.goPath(ed, create)
  local e = ed.edit
  local p = nav.getPath(e.buf, e.l,e.c)
  info('@@ nav.getPath %s', p)
  if p then
    local b = ed:getBuffer(p); if b then
      ed:focus(b); return
    end
  end
  p = pth.abs(pth.resolve(p))
  info('goPath %s', p)
  if create or ed:getBuffer(p) or ix.exists(p) then
    ed:focus(p)
  else error'TODO: goto nav' end
end

local DO_ENTRY = {
  focus  = nav.backFocus,
  back   = nav.doBack,
  expand = nav.doExpand,
}

--- perform the entry operation
function nav.doEntry(ed, op, times, ls)
  local e = ed.edit; local l = e.l
  e:changeStart()
  local fn = fmt.assertf(DO_ENTRY[op], 'uknown entry op: %s', op)
  local fl = fn(e.buf, l, times, ls) or l
  assert(math.type(fl) == 'integer')
  e.l = fl or l
  e:changeUpdate2()
end

function M.path(ed, ev, evsend)
  if ev.entry then
    nav.doEntry(ed, ev.entry, ev.times or 1, ix.ls)
  end
  if ev.go == 'enter' then
    local e = ed.edit
    local line = e.buf:get(e.l)
    if pth.isDir(line) then nav.doEntry(ed, 'expand', ev.times or 1, ix.ls)
    else                    nav.goPath(ed, ev.create) end
  elseif ev.go then nav.goPath(ed, ev.go == 'create') end
  ed:handleStandard(ev)
end

--- Do something with the edit view, in this order: [+
--- * save=true: save the current edit view.
--- * focus: focus the buffer, typically 'b#named'.
--- * clear: clear the current edit view.
--- ]
function M.edit(ed, ev)
  if ev.save  then
    ed.edit:save(ed)
  end
  if ev.focus then ed:focus(ev.focus) end
  if ev.clear then
    ed.edit:changeStart()
    ed.edit:clear()
  end
  if ev.undo then
    for _=1,ev.times or 1 do
      if not ed.edit:undo() then break end
    end
  end
  if ev.redo then
    for _=1,ev.times or 1 do

      if not ed.edit:redo() then break end





    end
  end
  ed:handleStandard(ev)
end

--- Directly modify a buffer by name. This is most commonly


--- used for the overlay.
function M.buf(ed, ev)
  local b; if ev.create then b = ed:buffer(ev.buf)
  else                       b = ed:getBuffer(ev.buf) end
  b:changeStart(0,0)
  if ev.ext then
    for p,v in pairs(ev.ext) do ds.setp(b.ext, ds.splitList(p, '%.'), v) end
  end
  if ev.clear then b:remove(1, #b) end
  if ev.remove then
    for _=1,ev.times or 1 do b:remove(unpack(ev.remove)) end
  end
  if ev.insert then
    for _=1,ev.times or 1 do b:insert(unpack(ev.insert)) end
  end
end

--- What a window.split translates to
M.SPLIT = {
  h = et.HSplit, horizontal=et.HSplit,
  v = et.VSplit, vertical=et.VSplit,
}
--- Window operations like split and close
function M.window(ed, ev)
  if ev.split then
    local S = assert(M.SPLIT[ev.split], ev.split)
    ed.edit:split(S)
  end
  if ev.moveV then
    local v = ed.edit; local c = e.container
    if mty.ty(c) == et.VSplit then
      v, c = c, c.container
    end
    if mty.ty(c) == et.HSplit then
      local i = assert(ds.indexOf(c, v)) + ev.moveV
      if 1 <= i and i <= #c then
        assert(mty.ty(c[i] == Edit))
        ed.edit = c[i]
      end
    end
  end
  if ev.moveH then
    local v = ed.edit; local c = v.container
    if mty.ty(c) == et.HSplit then
      v, c = c, c.container
      -- FIXME:
    end
    if mty.ty(c) == et.VSplit then
      local i = assert(ds.indexOf(c, v)) + ev.moveH
      if 1 <= i and i <= #c then
        assert(mty.ty(c[i] == Edit))
        ed.edit = c[i]
      end
    end
  end
  if ev.close then
    local e = ed.edit
    e.container:remove(e); e:close()
    ed.edit = nil;         ed:focusFirst()
    if not ed.view or not ed.edit then
      ed:focus(ed:buffer'b#scratch')
    end
  end
end

return M