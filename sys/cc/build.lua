local mty  = require'metaty'

--- C compiler for civ build.
local M = mty.mod'sys:cc.build'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local ix = require'civix'
local T  = require'civtest'

local push = ds.push
local EMPTY = {}

local w = require'civ.Worker':get()

local function pushLibs(cmd, tgt)
  if tgt.out.lib then
    push(cmd, '-l'..assert(tgt.out.lib:match'lib([%w_]+)%.so'))
  end
  for _, id in ipairs(tgt.dep) do
    pushLibs(cmd, w:target(id))
  end
end

for _, id in ipairs(w.ids) do
  local tgt = w:target(id)
  local extra = tgt.extra or EMPTY
  ix.mkDirs(w.cfg.buildDir..'lib')
  w:copyOut(tgt)
  local lib = tgt.out.lib; if lib then
    lib = ds.only(lib)
    local cmd = {'cc'}
    for _, src  in ipairs(tgt.src) do push(cmd, tgt.dir..src) end
    for _, flag in ipairs(tgt.extra or EMPTY) do push(cmd, flag) end
    ds.extend(cmd, {'-fPIC', '-I'..w.cfg.buildDir..'include'})
    for _, dep  in ipairs(tgt.dep or EMPTY) do pushLibs(cmd, dep) end
    push(cmd, '-shared')
    lib = w.cfg.buildDir..'lib/'..lib
    ds.extend(cmd, {'-o', lib})
    ix.sh2(cmd)
    T.exists(lib)
  end
end