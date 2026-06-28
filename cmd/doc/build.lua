#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua builder for civ.
local M = mty.mod'civ:cmd/doc/build.lua'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local pth = require'ds.path'
local info = require'ds.log'.info
local ix = require'civix'
local doc = require'doc'
local core = require'civ.core'

local push = ds.push
local w = require'civ.Worker':get()

local B = assert(w.cfg.buildDir)
local docOut    = {'out', 'doc',    'lua'}
local readmeOut = {'out', 'readme', 'lua'}
local O = B..'doc/lua/'
local R = B..'readme/lua/'
ix.mkDirs(O)
ix.mkDirs(R)

local function dotOpen(t, p)
  return assert(io.open(O..ds.only(assert(ds.getp(t, p))), 'w+'))
end

local function build(id)
  local tgt = w:target(id)
  info('documenting %q', tgt:tgtname())

  local tgts = {}
  -- get dep objects
  for _, depId in ipairs(tgt.depIds) do
    local tgt = w:target(depId)
    tgts[tgt:tgtname()] = tgt
  end

  -- concatenate all the user srcs to a file
  local to = dotOpen(tgt, docOut)
  for i, src in ipairs(tgt.src) do
    ix.cp(tgt.dir..src, to); to:write'\n'
  end
  to:flush(); to:seek('set', 0)
  -- readme/ is just the user-written text
  ix.cp(to, R..ds.only(assert(ds.getp(tgt, readmeOut))))
  to:seek'end'

  local cmd = { to = to }
  for _, modtgt in ipairs(tgt.extra.lua) do
    ds.extend(cmd, tgts[core.tgtname(modtgt)].api)
  end
  info('doc cmd: %q', cmd)
  doc(cmd)
end

for _, id in ipairs(w.ids) do build(id) end
