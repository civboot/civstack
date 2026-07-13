
local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local lap = require'lap'
local M = require'ele.bindings'
local et = require'ele.types'
local Editor = require'ele.Editor'
local keyinput = require'ele.actions'.keyinput

local push = table.insert

local actions = {
  insert=ds.noop, move=ds.noop, remove=ds.noop, merge=ds.noop,
}

local function U(ev)  return ds.tag(ev, 'user') end
local function UM(ev) return ds.tag(ds.tag(ev, 'user'), 'mut') end

local function events()
  local e = {}; return e, function(v) push(e, v) end
end

T'chords'; do
  T.eq({'space', 'a', 'b'}, M.chord'space a b')

  T.eq('a b', M.chordstr{'a', 'space', 'b'})
  T.eq('x',   M.chordstr{'x'})
end

local function newEditor(mode)
  local ed = Editor{
    mode=mode, modes={}, actions=actions, ext={},
    buffers={}, namedBuffers={},
  }
  M.install(ed)
  return ed
end

local function cleanup(d) d:rmTmp() end

T'bindings'; do
  local data = newEditor'insert'
  et.checkBindings(M.insert)
  et.checkBindings(M.command)
  cleanup(data)
end

local function assertKeys(keyinputs, mode, expectKeys, expectEvents)
  local data = newEditor(mode)
  data.error = require'fmt'.errorf
  local events = lap.Recv(); local evsend = events:sender()
  for _, ki in ipairs(M.chord(keyinputs)) do
    keyinput(data, {action='keyinput', ki}, evsend)
  end

  if expectKeys == false then T.eq(nil, data.ext.keys.keep)
  elseif expectKeys then T.eq(expectKeys, data.ext.keys) end
  T.eq(expectEvents or {}, events:drain())
  cleanup(data)
  return data
end

T'action'; do
  local d
  local mode = function(mode) return {mode=mode} end
  -- Switch between modes
  d = assertKeys('esc',   'insert', false, {U(mode'command')})
    T.eq({'esc'},   d.ext.keys.chord)
  d = assertKeys('i',     'command', false, {U(mode'insert')})
    T.eq({'i'},    d.ext.keys.chord)
  d = assertKeys('esc', 'insert', false, {U(mode'command')})

  -- Insert mode
  local ins = function(str) return {action='insert', str} end
  d = assertKeys('a', 'insert', false, {U(ins'a')})
    T.eq({'a'}, d.ext.keys.chord)
  d = assertKeys('space a', 'insert', false,
    {U(ins'a'), U(ins' ')}) -- note: reverse order because pushLeft
    T.eq({'a'}, d.ext.keys.chord)
    T.eq(nil, d.ext.again)

  -- move
  local move = function(t) t.action = 'move'; return t end
  assertKeys('l',     'command', false, { U(move{off=1}) })
  assertKeys('3 l',   'command', false, { U(move{off=1, times=3}) })
  assertKeys('3 0 l', 'command', false, { U(move{off=1, times=30}) })
  assertKeys('3 G',   'command', false, { U(move{move='absolute', l=3}) })
  assertKeys('G',     'command', false, { U(move{move='eof'}) })

  -- remove
  local rm = function(t) t.action = 'remove'; return t end
  assertKeys('d l',     'command', false, { UM(rm{off=1}) } )
  assertKeys('5 d l',   'command', false, { UM(rm{off=1,  times=5}) })
  assertKeys('3 d d',   'command', false, { UM(rm{lines=0, times=3}) })
  assertKeys('3 d f e', 'command', false,
    { UM(rm{move='find', find='e', times=3}) })
  assertKeys('3 r a',     'command', false, {
    UM{action='chain', rm{off=0, times=3}, {'a', action='insert', times=3}},
  })


  local ch = function(t) t.mode='insert'; return rm(t) end
  d = assertKeys('3 c l', 'command', false, { UM(ch{off=1, times=3}) })
  d = assertKeys('c c',   'command', false, { UM(ch{lines=0}) })

  d = assertKeys('x',     'command', false, { UM(rm{off=0}) })
  d = assertKeys('3 x',   'command', false, { UM(rm{off=0, times=3}) })

  -- find
  assertKeys('f x',       'command', false,
    { U(move{find='x', move='find'}) })
  assertKeys('1 0 d f x', 'command', false,
    {  UM(rm{find='x', move='find', times=10}) })
  assertKeys('1 0 d t x', 'command', false,
    {  UM(rm{find='x', move='find', times=10, cols=-1}) })

  -- Event
  assertKeys('I', 'command', false, { U(move{move='sot', mode='insert'}) })
end