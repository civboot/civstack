local mty = require'metaty'

-- Bindings builin plugin
--
-- This defines the default keybindings and the function
-- for handling key inputs
local M = mty.mod'ele.bindings'

local fmt = require'fmt'
local ds = require'ds'
local et = require'ele.types'
local log = require'ds.log'
local vt100 = require'vt100'

local sfmt = string.format
local push, pop, concat = table.insert, table.remove, table.concat
local getp, dp = ds.getp, ds.dotpath
local info = log.info

---------------------------
-- Utility Functions and Callable Records

-- space-separated keys to a list, asserting valid keys
function M.chord(str) --> keylist
  local checkKey = et._term.checkKey
  local keys = {}; for k in str:gmatch'%S+' do
    push(keys, assert(checkKey(k)))
  end
  return keys
end

function M.literal(key)
  return fmt.assertf(et._term.literal(key),
    'invalid literal: %q', key)
end
function M.chordstr(chord)
  local s = {}
  for _, key in ipairs(chord) do push(s, M.literal(key)) end
  return concat(s)
end

---------------------------
-- TYPES

--- The state of the keyboard input (chord).
--- Some bindings are a simple action to perform, whereas callable bindings
--- can update the KeySt to affect future ones, such as decimals causing
--- later actions to be repeated a [$num] of times.
M.KeySt = mty'KeySt' {
  "chord [table]: list of keys which led to this binding, i.e. {'space', 'a'}",
  "event [table]: table to use when returning (emitting) an event.",
  "next [table|string]: the binding which will be used for the next key",
  "save [table|string]: saved binding, only used for help",
  "keep [boolean]: if true the above fields will be preserved in next call",
}


--- Check the current Key State.
function M.KeySt:check(ele) --> errstring?
  if self.next == nil then return end
  return (type(self.next) ~= 'table') and et.checkBinding(self.next)
    or getp(self, {'event', 'action'})
       and et.checkAction(ele, self.event.action)
end

--- A map of key -> binding.
--- The name and doc can be provided for the user.
--- 
--- Other "fields" must be valid chords. They will be automatically
--- split (by whitespace) to create sub-KeyBindings as-needed.
---
--- The value must be one of: [+
--- * KeyBindings instance to explicitly create chorded bindings.
--- * plain event table to fire off a simple event
--- * callable [$event(ev, keySt)] for more complex bindings.
--- ]
M.KeyBindings = mty'KeyBindings' {
  'name [string]: the name of the group for documentation',
  'doc [string]: documentation to display to the user',
}

function M.KeyBindings:bindingsDoc(f)
  f:write(self.name, ': ', '\n', self.doc, '\n\n')
  for _, k in ipairs(ds.orderedKeys(self)) do
    if k ~= 'name' and k ~= 'doc' then
      local v = self[k]
      v = type(v) == 'table' and rawget(v, 'name')
       or MOD_NAMES[v] or mty.name(v) or '(unknown)'
      v = v:match'.-%.?([^.]+)$'
      f:write('  ', k, ': ', v, '\n')
    end
  end
end
M.KeyBindings.getBinding = rawget
getmetatable(M.KeyBindings).__call = function(T, t)
  local b = {}
  for k, v in pairs(t) do T.__newindex(b, k, v) end
  return mty.constructUnchecked(T, b)
end
getmetatable(M.KeyBindings).__index = function(G, k)
  if G.__fields[k] then return end
  assert(et._term.checkKey(k))
end
function M.KeyBindings:__newindex(k, v)
  if M.KeyBindings.__fields[k] then
    assert(type(v) == 'string', k)
    rawset(self, k, v)
    return
  end
  local mtv = getmetatable(v)
  fmt.assertf(mty.callable(v)
              or (mtv == M.KeyBindings)
              or (not mtv and type(v) == 'table'),
    '[%s] binding must be callable or plain table: %q', k, v)
  if k == 'fallback' then return rawset(self,k, v) end
  local kb = self -- walk the key bindings
  k = M.chord(k); assert(#k > 0, 'empty chord')
  for i=1,#k-1 do
    local key = k[i]; assert(et._term.checkKey(key))
    if not rawget(kb,key) then
      rawset(kb,key, M.KeyBindings{
        name=table.concat(ds.slice(k, 1,i), ' '),
      })
    end
    kb = rawget(kb,key)
  end
  local key = k[#k]
  assert(et._term.checkKey(key))
  rawset(kb,key, v)
end

---------------------------
-- Default ed.bindings functions

M.exit = {action='exit'}

M.splitVLeft  = {action='window', split='vertical'}
M.splitVRight = {action='window', split='vertical',   moveH=1}
M.splitHUp    = {action='window', split='horizontal'}
M.splitHDown  = {action='window', split='horizontal', moveV=1}

M.windowUp    = {action='window', moveV=-1}
M.windowDown  = {action='window', moveV=1}
M.windowLeft  = {action='window', moveH=-1}
M.windowRight = {action='window', moveH=1}

M.windowClose = {action='window', close=true}

function M.insertChord(keys)
  local ev = ds.tag(keys.event or {}, 'mut')
  ev.action, ev[1] = 'insert', M.chordstr(keys.chord)
  return ev
end
function M.unboundChord(keys)
  error('unbound chord: '..concat(keys.chord, ' '))
end

--- Go to command mode.
M.commandMode = {mode='command'}
--- Go to insert mode.
M.insertMode  = {mode='insert'}
--- Go to system mode.
M.systemMode  = {mode='system'}
--- Go to visual mode.
M.visualMode  = {mode='visual',  action='visual', 'start'}
--- Exit visual mode
M.visualStop  = {mode='command', action='visual', 'stop'}

M.insertTab   = {action='insertTab', tag='mut'}
M.insertEnter = {'\n', action='insert', tag='mut'}
M.insertsot   = {mode='insert', action='move', move='sot'}
M.inserteol   = {mode='insert', action='move', move='eol', cols=1}

M.insertBelow = {
  action='chain', mode='insert', tag='mut',
  {action='move', move='eol', cols=1},
  {action='insert', '\n', tag='mut'},
  {action='autoIndent', tag='mut'},
}
M.insertAbove = {
  action='chain', mode='insert', tag='mut',
  {action='move', move='sol'}, 
  {action='insert', '\n', autoIndent=true, tag='mut'},
  {action='move', rows=-1},
}

function M.moveAction(event)
  return function(keys)
    local ev = keys.event or {}
    ev.action = ev.action or 'move'
    return ds.update(ev, event)
  end
end
do local MA = M.moveAction
  M.right,   M.left      = MA{off=1},          MA{off=-1}
  M.forword, M.backword  = MA{move='forword'}, MA{move='backword'}
  M.endword              = MA{move='endword'}
  M.up                   = MA{move='lines', lines=-1}
  M.down                 = MA{move='lines', lines=1}
  --- sol=start of line  sot=start of text
  M.sol, M.sot           = MA{move='sol'}, MA{move='sot'}
  --- eol=end of line    eot=end of text
  M.eol, M.eot           = MA{move='eol'}, MA{move='eot'}
  --- sof=start of file  eof=end of file
  M.sof, M.eof           = MA{move='sof'}, MA{move='eof'}
  M.upScreen             = MA{move='screen', mul=-1, div=2}
  M.downScreen           = MA{move='screen', mul=1,  div=2}
end

function M.moveG(keySt) -- specific line or end-of-file
  local ev = keySt.event or {}
  return ev.times and {action='move', move='absolute', l=ev.times} or M.eof(ev)
end

function M.movekey(keys)
  local ev = keys.event or {}
  ev[ev.move] = M.literal(ds.last(keys.chord))
  return ev
end

-- Find a single character.
function M.find(keys)
  local ev = keys.event or {}; keys.event = ev
  ev.action, ev.move = ev.action or 'move', ev.move or 'find'
  keys.next = M.movekey
  keys.keep = true
end

--- go to the column before the character
function M.till(keys)
  M.find(keys); keys.event.cols = -1
end

--- go back to the character
function M.findback(keys)
  M.find(keys)
  keys.event.move = 'findback'
end

--- go back to the column after the character
function M.tillback(keys)
  M.findback(keys); keys.event.cols = 1
end

M.backspace = {action='backspace', tag='mut'}
M.delkey    = {action='remove', off=0, tag='mut'}

--- Join next line
M.join      = {action='chain', tag='mut',
  {action='move', move='eol', cols=1},
  {action='insert', ' ', tag='mut'},
  {action='move', move='eol', cols=1},
  {action='remove', move='nextLineText', cols=-1, tag='mut'},
}

--- delete until a movement command (or similar)
function M.delete(keySt)
  local ev = keySt.event or {}; keySt.event = ev
  if ev.action == 'remove' then
    ev.lines = 0
    return ev
  end
  ev.action, ev.tag = 'remove', 'mut'
  keySt.keep = true
end
function M.deleteEol(keySt)
  M.delete(keySt)
  local ev = ds.popk(keySt, 'event')
  ev.move, ev.tag, keySt.keep = 'eol', 'mut', nil
  return ev
end

function M.replace(keySt)
  local ev = keySt.event or {}
  if ev.replace then
    return {action='chain', tag='mut',
      {action='remove', off=0, times=ev.times, tag='mut'},
      {
        action='insert', times=ev.times, tag='mut',
        M.literal(ds.last(keySt.chord)),
      },
    }
  end
  ev.replace, ev.tag = 1, 'mut'
  keySt.event, keySt.next, keySt.keep = ev, M.replace, true
end

--- Delete <move> then enter insert.
function M.change(keySt)
  local ev = M.delete(keySt)
  keySt.event.mode = 'insert'
  return ev
end
function M.changeEol(keySt, evsend)
  M.delete(keySt)
  local ev = ds.popk(keySt, 'event')
  ev.move, ev.mode, keySt.keep = 'eol', 'insert', nil
  ev.tag = 'mut'
  return ev
end

function M.yank(keySt)
  local ev = keySt.event or {}; keySt.event = ev
  if ev.action == 'yank' then
    ev.lines = 0
    return ev
  end
  ev.action = 'yank'
  keySt.keep = true
end
function M.yankEol(keySt)
  M.yank(keySt)
  local ev = ds.popk(keySt, 'event')
  ev.move, keySt.keep = 'eol', nil
  return ev
end

function M.paste(keySt)
  -- TODO: allow P to 'walk up' the indexes.
  --   see M.searchBuf for how.
  return {action='paste', index=1, tag='mut'}
end

--- used for setting the number of times to do an action.
--- 1 0 d t x: delete till the 10th x
function M.times(keys)
  local ev = keys.event or {}; keys.event = ev
  ev.times = (ev.times or 0) * 10 + tonumber(ds.last(keys.chord))
  keys.keep = true
end
function M.zero(keys) -- special: movement if not after a digit
  local ev = keys.event or {}
  if not ev.action and ev.times then return M.times(keys) end
  ev.action, ev.move = ev.action or 'move', 'sol'
  return ev
end

M.again = {action='again'}

---------------------------
-- Search Buffer

M.hideOverlay = {action='buf', buf='b#overlay', ext={show=false}}

M.searchBufNext = {action='searchBuf', next=true}
M.searchBufPrev = {action='searchBuf', prev=true}
M.searchBufSub  = {action='searchBuf', next=true, sub=true, wrap=true}

--- Interactively search the buffer.
---
--- This holds onto keySt (sets .keep + .next), effectively owning all keyboard

--- inputs.
function M.searchBuf(keySt)
  local ev, chord = keySt.event or {}, keySt.chord
  keySt.event, keySt.keep = ev, true
  if #chord == 1 then -- initial call
    keySt.next = M.searchBuf
    return {action='buf', buf='b#overlay', clear=true, ext={show=true}}
  end
  local k, bufAction = chord[#chord], nil

  -- TODO: do tab / ^j / ^k / etc
  if k == 'back' then
    bufAction = {action='buf', buf='b#overlay', remove={1,-1,1,-1}}
  end
  if k == '^n' then return ds.update({overlay=true}, M.searchBufSub) end
  if k == 'enter' then
    keySt.keep = false
    return {action='chain',
      M.hideOverlay, ds.update({overlay='store'}, M.searchBufNext)
    }
  end

  local char = vt100.literal(k); if char then
    bufAction = {action='buf', buf='b#overlay', insert={char, 1,'end'}}
  end
  if bufAction then return {action='chain',
    bufAction,
    {action='searchBuf', overlay=true}
  } end
  keySt.keep = false -- any unknown control exits find w/out save
  return M.hideOverlay
end

--- Get help on next key. '??' gets help on current bindings.
function M.help(keySt)
  local ch = keySt.chord
  if ch[#ch - 1] ~= '?' then -- initial call, get one more key
    keySt.save, keySt.next, keySt.keep = keySt.next, M.help, true
    return
  end
  return {action='help'}
end

---------------------------
-- SYSTEM Mode
M.goEnter     = {action='path', go='enter',  mode='command'}
M.goPath      = {action='path', go='path',   mode='command'}
M.createPath  = {action='path', go='create', mode='command'}

M.pathFocus  = {action='path', entry='focus'}
M.pathBack   = {action='path', entry='back'}
M.pathExpand = {action='path', entry='expand'}
M.pathFocusExpand = {action='chain', M.pathFocus, M.pathExpand}
M.pathBackExpand = {action='chain',
  M.pathFocus, M.pathBack, M.pathExpand,
}

M.save   = {action='edit', save=true, mode='command'}
M.undo   = {action='edit', undo=true}
M.redo   = {action='edit', redo=true}
M.tmpBuf = {action='edit', focus='b#tmp'}

--- CWD: current working directory
M.navCwd = {action='nav', nav='cwd', mode='system'}

--- CBD: current buffer id
M.navCbd = {action='nav', nav='cbd', mode='system'}

--- View list of buffers
M.navBuf = {action='chain',
  {action='nav', nav='buf', mode='system'},
  {action='runBinding', 'searchBuf', chord={'/'}},
}

---------------------------
-- INSTALL

-- install the builtin keys plugin
--
-- Note: this does NOT start the keyactions coroutine
function M.install(ed)
  ed.ext.keys = M.KeySt{}
  -- TODO: replace with merge but need shouldMerge closure.
  ed.modes = ds.update(ed.modes or {}, {
      insert=M.insert,
      command=M.command,
      system=M.system,
      visual=M.visual,
  })
  if not ed.namedBuffers.nav then
    push(ed:namedBuffer'nav'.tmp, ed.ext.keys) -- mark as not closed
  end
  if not ed.namedBuffers.find then
    push(ed:namedBuffer'find'.tmp, ed.ext.keys) -- mark as not closed
  end
end

-- keyactions coroutine.
-- This should be scheduled with LAP, see user.lua and testing.lua
function M.keyactions(ed, keyrecv, evsend)
  assert(keyrecv:hasSender())
  log.info('keyactions keyrecv=%q', keyrecv)
  for key in keyrecv do
    log.info('key received: %q', key)
    if key == '^q' then
      ed.run = false; log.warn('received ^q, exiting')
      evsend{action='exit'}
    end
    if not ed.run then break end
    if key then
      if type(key) == 'string' then
        evsend{key, action='keyinput'}
        log.info('sent key %q', key)
      else assert(key[1] == 'size')
        local d = ed.display
        local ch = (d.h ~= key.h) or (d.w ~= key.w)
        d.h, d.w = key.h, key.w
        if ch then ed.redraw = true end
      end
    else ed.warn'received empty key' end
  end
  log.warn'exited keyactions'
end

---------------------------
-- BINDINGS
M.go = M.KeyBindings {
  name = 'go (utility)',
  doc = 'g stands for "go" and is used for lots of utility bindings',

  ['?'] = M.help,

  g = M.sof,
  f = M.goPath, F = M.createPath,
  ['/'] = M.navCwd, ['.'] = M.navCbd, ['b'] = M.navBuf,
  ['n'] = M.tmpBuf,

  ['h'] = M.windowLeft, ['l'] = M.windowRight,
  ['j'] = M.windowDown, ['k'] = M.windowUp,
  ['c'] = M.windowClose,

  ['H'] = M.splitVLeft, ['L'] = M.splitVRight,
  ['J'] = M.splitHDown, ['K'] = M.splitHUp,
}

--- Basic movement and times (used in multiple)
M.movement = {
  h   =M.left, j   =M.down, k =M.up, l     = M.right,
  left=M.left, down=M.down, up=M.up, right = M.right,

  w=M.forword,   b=M.backword, e=M.endword,
  t=M.till,      T=M.tillback,
  ['^'] = M.sot, ['$'] = M.eol,

  ['^d'] = M.downScreen, ['^u'] = M.upScreen,
  
  -- G is for GO
  g = M.go,
  G = M.moveG, -- start/end of file
}

-- times
M.movement['0'] = M.zero  -- sol+0times
for b=('1'):byte(), ('9'):byte() do
  M.movement[string.char(b)] = M.times
end

--- Other common bindings
M.common = {
  fallback = M.unboundChord,
  esc      = M.commandMode,
  ['^q ^q'] = M.exit,
  ['?'] = M.help,

  -- Complex movement
  B = {action='jump', location=-1}, ['^b'] = {action='jump', location=1},

  -- Insert
  i = M.insertMode, I=M.insertsot, A=M.inserteol,
  o = M.insertBelow, O = M.insertAbove,

  d = M.delete, D = M.deleteEol, J = M.join,
  c = M.change, C = M.changeEol,

  -- Search
  ['/'] = M.searchBuf,
  n = M.searchBufNext, N = M.searchBufPrev, ['^n'] = M.searchBufSub,

  -- Other
  y = M.yank, Y = M.yankEol,
  p = M.paste,
  u = M.undo, ['^r'] = M.redo,
  ['.'] = M.again,
}

--- Insert Mode: directly insert text into the buffer.
M.insert  = M.KeyBindings{name='insert mode', doc=[[
Insert mode is the primary editing mode of the editor,
allowing you to directly enter text.
Press [$esc] to exit to command mode.
]]}
ds.update(M.insert, {
  fallback = M.insertChord,
  ['^q']   = M.exit,
  esc      = M.commandMode,
  tab      = M.insertTab,
  right = M.right, left=M.left, up=M.up, down=M.down,
  back=M.backspace, del=M.delkey,
  -- rawmode terminal-paste converts newlines to '^j' to tell the
  -- terminal not to run each line.
  ['^j']   = M.insertEnter,
})

M.command = M.KeyBindings{
  name='command mode', 
  doc=[[
Command mode is the primary mode of the ele editor.
You can get to command mode by pressing "esc" in any other
mode. Commands typically have the following form:
  
  [number] (optional) is a decimal number.
  [action] something to do such as delete.
  [noun]   the movement or thing to delete.]]
}
ds.update(M.command, M.movement)
ds.update(M.command, M.common)
ds.update(M.command, {
  -- edit
  x = M.delkey, del=M.delkey,
  r = M.replace,

  -- movement
  f = M.find, F = M.findback,

  -- Modes
  s = M.systemMode, v=M.visualMode,
})

M.system = M.KeyBindings {
  name = 'system mode (base)',
  doc = [[
System mode is very similar to command mode, except many of the keys enable the
control of system-related resources such as files and directories. It is the
default mode in the nav buffer (i.e. [$g /]).

Typically you can get to system mode by pressing "s" while in command mode.
Press "esc" to go back to command mode.
]]}

ds.update(M.system, M.movement)
ds.update(M.system, M.common)
ds.update(M.system, {
  c = M.commandMode,
  s = M.save,

  enter = M.goEnter,
  h = M.pathBack,   H = M.pathBackExpand,
  l = M.pathExpand, L = M.pathFocusExpand,
  -- TODO: J/K: focus below/above
})

M.visual = M.KeyBindings {
  name = 'visual mode',
  doc  = [[
For selecting and modifying blocks of text.
Visual mode flips the normal language of chords on it's head.
You move any amount to visually select the block of text you want,
then you use an action to specify what to do.
]]}


-- TODO: on enter, visual mode will save the start position as ol,oc.
-- Movements happen "naturally", but yank/delete/change/insert need to be
-- handled special. For one thing they must execute IMMEDIATELY.
ds.update(M.visual, M.movement)
ds.update(M.visual, {
  fallback = M.unboundChord,
  esc = M.visualStop,
  -- i = M.insertChord,
})

return M