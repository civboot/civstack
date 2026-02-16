#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua tester for civ.
local M = mty.mod'sys:lua.test'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local info = require'ds.log'.info
local push = require'ds'.push
local w = require'civ.Worker':get()

local function main()
  for _, id in ipairs(w.ids) do
    local tgt = w:target(id); if tgt.kind ~= 'test' then goto continue end
    for _, src in pairs(tgt.src) do
      src = tgt.dir..src
      io.fmt:styled('notify', 'running test '..src, '\n')
      dofile(src)
    end
    ::continue::
  end
end

ds.main(main)
-- main()
