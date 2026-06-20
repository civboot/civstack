#!/usr/bin/env -S lua
local shim = require'shim'
local mty = require'metaty'

local info = require'ds.log'.info

--- Usage: [$civgame <game>][{br}]
--- Ele extension which comprise a set of games for learning civstack.
local civgame = shim.cmd'civgame' {}

function civgame:__call()
  info('civgame: %q', self)
  assert(self[1], 'must select game to run (typo, ...)')
  require'ele'{run='civgame.'..self[1]}
end

if shim.isMain(civgame) then
  civgame:main(mty.G.arg)
end
return civgame
