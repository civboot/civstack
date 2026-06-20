#!/usr/bin/env -S lua
local shim = require'shim'
local mty = require'metaty'

--- Usage: [$civgame <game>][{br}]
--- Ele extension which comprise a set of games for learning civstack.
local civgame = shim.cmd'civgame' {}

function civgame:__call()
  assert(self[1], 'must select game to run (typo, ...)')
  require'ele'{run='civgame.'..self[1]}
end

if shim.isMain(ele) then civgame:main(mty.G.arg) end
return civgame
