#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua builder for civ.
local M = mty.mod'sys:data.build'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local w = require'civ.Worker':get()
local info = require'ds.log'.info

for _, id in ipairs(w.ids) do
  local tgt = w:target(id)
  info('building %q', tgt:tgtname())
  w:copyOut(tgt)
  w:link(tgt)
end

